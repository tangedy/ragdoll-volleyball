--!strict
-- Match state machine (spec §5, Amendment A1/A3):
-- WaitingForPlayers -> Intermission -> RoundCountdown -> RoundActive -> RoundResolution
--   -> RoundCountdown (next round) | results overlay during the next Intermission.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local ArenaLayout = require(Shared.ArenaLayout)
local BallDefinitions = require(Shared.BallDefinitions)
local NetSchema = require(Shared.NetSchema)

local MatchService = {}

local S: any
local M = Config.Match
local J = Config.Jail
local stateFolder: Folder
local rng = Random.new()

local state = "WaitingForPlayers"
local matchId = 0
local roundId = 0
local roster: { any } = {}
local wins = { Red = 0, Blue = 0 }
local roundsToWin = Config.Match.RoundsToWin -- this match's (a first match can be shorter)
local roundHits = { Red = 0, Blue = 0 }
local overtime = false
local teamSize = 3
local devSkip = false
local devOvertime = false
local clockHeld = false -- TestService: round timer can't run out while the suite runs
local devFinisherBy: any? = nil -- Studio T key: end the match with this player's finisher
-- the most recent void elimination this round: who fell and who (if anyone) gets the credit
local lastElim: { victim: any, credit: any? }? = nil
local staging = false -- a finisher is staging the victim; don't move them to jail/lobby
local botOnlyOk = false -- TestService: a match with no real players in it doesn't abort

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Counts and rosters are republished five times a second; only real changes go to the engine
-- (and so to every client).
local published: { [string]: any } = {}

function MatchService.setAttr(key: string, value: any)
	if stateFolder and (published[key] ~= value or value == nil) then
		published[key] = value
		stateFolder:SetAttribute(key, value)
	end
end

local function setState(name: string, duration: number?)
	state = name
	MatchService.setAttr("State", name)
	MatchService.setAttr("PhaseEndsAt", if duration then now() + duration else 0)
end

local function banner(text: string, color: Color3?, duration: number?, sound: string?)
	S.NetService.broadcast("Banner", { text = text, color = color, duration = duration or 1.6, sound = sound })
end

-- A win/lose banner: same text for everyone, but winners and losers hear different stingers. It's
-- the winners' screen, so it rains confetti in the winning team's color.
local function resultBanner(text: string, winner: string, duration: number)
	local color = Config.Teams[winner].Color
	for _, c in S.PlayerStateService.realPlayers() do
		local sound = if c.inMatch and c.team == winner then "RoundWin" elseif c.inMatch then "RoundLose" else nil
		S.NetService.send(
			c.player,
			"Banner",
			{ text = text, color = color, duration = duration, sound = sound, confetti = true }
		)
	end
end

-- Feed name tag: bold, in the combatant's team color (rich text, escaped).
local function tag(c: any): string
	local name = string.gsub(string.gsub(string.gsub(c.name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
	local team = c.team and Config.Teams[c.team]
	if not team then
		return "<b>" .. name .. "</b>"
	end
	return ('<b><font color="#%s">%s</font></b>'):format(team.Color:ToHex(), name)
end
MatchService.tag = tag

local function feed(text: string)
	S.NetService.broadcast("Feed", { text = text })
end
MatchService.feed = feed

function MatchService.init(services: any)
	S = services
	local existing = ReplicatedStorage:FindFirstChild(NetSchema.MatchStateFolder)
	if existing and existing:IsA("Folder") then
		stateFolder = existing
	else
		local f = Instance.new("Folder")
		f.Name = NetSchema.MatchStateFolder
		f.Parent = ReplicatedStorage
		stateFolder = f
	end
	setState("WaitingForPlayers")
	for _, k in { "Round", "RedWins", "BlueWins", "RedActive", "BlueActive", "RedJail", "BlueJail", "OvertimeSteps" } do
		MatchService.setAttr(k, 0)
	end
	MatchService.setAttr("Overtime", false)
	MatchService.setAttr("MatchId", 0)
	MatchService.setAttr("RedRoster", "")
	MatchService.setAttr("BlueRoster", "")
end

function MatchService.start()
	S.NetService.on(NetSchema.Actions.Dev, function(player, p)
		-- the Halloween switch has its own permission (Studio, or the game's owner on a live server)
		if p.cmd == "ToggleHalloween" then
			S.HalloweenService.devToggle(player)
			return
		elseif p.cmd == "DevRoom" then
			S.DevRoomService.toggle(player)
			return
		end
		if Config.Debug.DevKeysInStudioOnly and not RunService:IsStudio() then
			S.NetService.reject(player, "dev-outside-studio")
			return
		end
		if p.cmd == "SkipIntermission" then
			devSkip = true
		elseif p.cmd == "ForceOvertime" then
			devOvertime = true
		elseif p.cmd == "RunTests" then
			task.spawn(S.TestService.runAll)
		elseif p.cmd == "LaunchMe" then
			local c = S.PlayerStateService.get(player)
			if c then
				S.CombatService.debugLaunch(c)
			end
		elseif p.cmd == "GiveCoins" then
			local c = S.PlayerStateService.get(player)
			if c and c.profile then
				c.profile.Coins += 1000000
				S.DataService.push(c)
				S.NetService.send(player, "Hint", { text = "+1,000,000 coins (dev)", duration = 1.5 })
			end
		elseif p.cmd == "TutorialReset" or p.cmd == "TutorialSkip" then
			local c = S.PlayerStateService.get(player)
			if c and not c.inMatch then
				if p.cmd == "TutorialReset" then
					S.TutorialService.devReset(c)
				else
					S.TutorialService.devSkip(c)
				end
			end
		elseif p.cmd == "FillUlt" or p.cmd == "PowerSlot" or p.cmd == "AllPowers" then
			-- powers testing (Studio): a full ultimate meter, the Extra Power Slot pass, every power
			local c = S.PlayerStateService.get(player)
			if c and p.cmd == "FillUlt" then
				S.PowerService.addMeter(c, Config.Powers.Meter.Max)
			elseif c and p.cmd == "PowerSlot" then
				S.GamePassService.setOwned(c, "PowerSlot")
			elseif c and c.profile then
				for _, item in Catalog.inCategory("Power") do
					c.profile.OwnedCosmetics[item.Id] = true
				end
				S.DataService.push(c)
			end
		elseif string.sub(p.cmd, 1, 6) == "Power:" then
			-- powers testing (Studio): swap slot 1 to this power mid-match, off cooldown
			local c = S.PlayerStateService.get(player)
			if c then
				S.PowerService.devSet(c, string.sub(p.cmd, 7))
			end
		elseif p.cmd == "SkipToFinisher" then
			local c = S.PlayerStateService.get(player)
			if c and c.inMatch and c.team then
				devFinisherBy = c
			else
				S.NetService.send(player, "Hint", { text = "Join a match first (dev T)", duration = 1.5 })
			end
		end
	end)
	S.NetService.on(NetSchema.Actions.LeaveMatch, function(player)
		local c = S.PlayerStateService.get(player)
		if c and not MatchService.leaveMatch(c) and c.inMatch then
			S.NetService.send(player, "Hint", { text = "Can't leave right now", duration = 1.5 })
		end
	end)
	task.spawn(MatchService.run)
	-- join in progress: anyone who pressed PLAY goes straight in while a bot's slot is open; the hub
	-- PLAY button reads JOIN MATCH while OpenSlots > 0
	task.spawn(function()
		while true do
			task.wait(0.25)
			local open = MatchService.openSlots()
			MatchService.setAttr("OpenSlots", open)
			if open > 0 then
				for _, c in MatchService.queuedPlayers() do
					if not MatchService.joinInProgress(c) then
						break
					end
				end
			end
		end
	end)
end

function MatchService.getState(): string
	return state
end

function MatchService.isRoundLive(): boolean
	return state == "RoundActive"
end

function MatchService.isOvertime(): boolean
	return overtime
end

function MatchService.isFrozen(c: any): boolean
	return c.inMatch and state == "RoundCountdown"
end

-- Studio test hooks (TestService only).
function MatchService.debugForceSuddenDeath()
	devOvertime = true
end

-- While held, the round timer never runs out (so the suite can't drift into sudden death).
function MatchService.debugHoldClock(on: boolean)
	clockHeld = on
end

function MatchService.debugSetWins(red: number, blue: number)
	wins = { Red = red, Blue = blue }
	MatchService.setAttr("RedWins", red)
	MatchService.setAttr("BlueWins", blue)
end

function MatchService.roster(): { any }
	return roster
end

function MatchService.jailedCounts(): { Red: number, Blue: number }
	local counts = { Red = 0, Blue = 0 }
	for _, c in roster do
		if c.status == "Jailed" and c.team then
			counts[c.team] += 1
		end
	end
	return counts
end

local function activeCounts(): (number, number)
	local red, blue = 0, 0
	for _, c in roster do
		if c.status == "Active" then
			if c.team == "Red" then
				red += 1
			elseif c.team == "Blue" then
				blue += 1
			end
		end
	end
	return red, blue
end

-- "userId|status;userId|status;..." for one team, in roster order (the scoreboard headshots). Bots
-- use the user id of the avatar they wear; 0 means no face to show.
local function rosterString(team: string): string
	local parts = {}
	for _, c in roster do
		if c.team == team then
			local id = if c.player then c.player.UserId else (c.avatarUserId or 0)
			table.insert(parts, ("%d|%s"):format(id, c.status or ""))
		end
	end
	return table.concat(parts, ";")
end

local function publishCounts()
	local red, blue = activeCounts()
	local jail = MatchService.jailedCounts()
	MatchService.setAttr("RedActive", red)
	MatchService.setAttr("BlueActive", blue)
	MatchService.setAttr("RedJail", jail.Red)
	MatchService.setAttr("BlueJail", jail.Blue)
	MatchService.setAttr("RedRoster", rosterString("Red"))
	MatchService.setAttr("BlueRoster", rosterString("Blue"))
end

local function realInRoster(): number
	local n = 0
	for _, c in roster do
		if c.player and c.player.Parent then
			n += 1
		end
	end
	return n
end

function MatchService.queuedPlayers(): { any }
	local list = {}
	for _, c in S.PlayerStateService.realPlayers() do
		-- an open hub menu never holds anyone back (the client closes it when they're pulled in);
		-- only the dev room does, and an unfinished tutorial (whatever Play again says)
		local away = c.player:GetAttribute("InDevRoom") == true or c.player:GetAttribute("TutorialDone") ~= true
		if c.autoQueue and not away and not c.inMatch and S.PlayerStateService.isAlive(c) and c.profileLoaded then
			table.insert(list, c)
		end
	end
	return list
end

-- Called by CombatService for every confirmed enemy hit.
function MatchService.recordHit(thrower: any, target: any)
	if not thrower.inMatch or not target.inMatch or not thrower.team then
		return
	end
	roundHits[thrower.team] += 1
end

local function spawnFor(c: any): Vector3
	local list = {}
	for _, o in roster do
		if o.team == c.team then
			table.insert(list, o)
		end
	end
	local idx = table.find(list, c) or 1
	local points = ArenaLayout.spawnPoints(c.team, math.max(#list, 1))
	return points[math.clamp(idx, 1, #points)]
end

local function faceCenter(pos: Vector3): Vector3
	return Vector3.new(pos.X, pos.Y, Config.Arena.Origin.Z)
end

function MatchService.moveToLobby(c: any)
	c.inMatch = false
	S.PlayerStateService.setDamage(c, 0)
	S.PlayerStateService.setTeam(c, nil)
	S.PlayerStateService.setStatus(c, "Lobby")
	S.PlayerStateService.setAction(c, "Idle")
	S.CharacterService.setTeamVisual(c)
	if c.heldBall then
		S.BallService.drop(c)
	end
	if c.humanoid then
		c.humanoid.WalkSpeed = Config.Player.WalkSpeed
		c.humanoid.JumpPower = Config.Player.JumpPower
	end
	S.CharacterService.placeFacing(c, ArenaLayout.lobbySpawn(rng), ArenaLayout.DummyHome)
end

local function jailSpot(c: any): Vector3
	return ArenaLayout.jailCenter(c.team) + Vector3.new(rng:NextNumber(-24, 24), 3, 0)
end

-- Eliminations ------------------------------------------------------------------------------------

local function eliminate(c: any)
	local t = now()
	local credit = c.lastHitBy
	if credit and (t - c.lastHitAt > Config.Player.KnockoutCreditWindow or credit.team == c.team) then
		credit = nil
	end
	c.eliminatedBy = credit
	c.matchEliminations = (c.matchEliminations or 0) + 1
	lastElim = { victim = c, credit = credit }
	local ballType = c.pendingHit and c.pendingHit.ballType -- read before hitResolved clears it
	S.AnalyticsService.hitResolved(c, "Void")
	S.PowerService.clearEffects(c)
	if c.heldBall then
		S.BallService.drop(c)
	end
	c.chargeStart = nil
	local reward = 0
	if credit then
		if c.isBot then
			credit.stats.botKnockouts += 1
		else
			credit.stats.knockouts += 1
		end
		-- instant elimination bonus for real players
		if credit.player and credit.profile then
			reward = Config.Coins.Elimination * S.BoostService.multiplier(credit)
			credit.profile.Coins += reward
			credit.stats.eliminationCoins += reward
			S.QuestService.record(credit, "Knockout") -- the daily 3-knockout quest, bots included
			S.ShopService.recordPowerKO(credit, ballType) -- Power Ball Mastery, bots included
			S.DataService.push(credit)
		end
		S.PowerService.onKnockout(credit)
		feed(("%s 💥 launched %s off the court!"):format(tag(credit), tag(c)))
	else
		feed(("%s fell off!"):format(tag(c)))
	end
	if c.player then
		S.NetService.send(
			c.player,
			"Banner",
			{ text = "KNOCKED OUT!", color = Color3.fromRGB(255, 90, 80), duration = 1.4, sound = "KnockedOut" }
		)
	end
	-- everyone: rim pulse + void splash; the eliminator also gets the ELIMINATION! moment
	local fallPos = if c.root then c.root.Position else c.lastCourtPos
	S.NetService.broadcast("Elimination", {
		victimName = c.name,
		victimTeam = c.team,
		killerName = if credit then credit.name else nil,
		killer = if credit then credit.player else nil,
		killerTeam = if credit then credit.team else nil,
		coins = reward,
		position = fallPos,
		edge = c.lastCourtPos,
	})
	S.AnalyticsService.event(c, "VoidElimination", if credit then 1 else 0)

	local canJail = J.Enabled and not overtime and c.jailReturns < J.MaxReturnsPerRound
	local thisRound = roundId
	if canJail then
		S.PlayerStateService.setStatus(c, "Jailed")
		S.AnalyticsService.event(c, "JailEntry")
		task.delay(J.RespawnDelay, function()
			-- the 1.5 s fall-and-splash beat keeps the clippable fall visible
			if roundId == thisRound and c.status == "Jailed" and not staging and S.PlayerStateService.isAlive(c) then
				local spot = jailSpot(c)
				S.CharacterService.placeFacing(c, spot, faceCenter(spot))
				S.PlayerStateService.setAction(c, "Idle")
			end
		end)
	else
		-- out for the rest of the round (sudden death, or no returns left): wait it out in your
		-- team's jail, unable to get back in, never back in the hub. If the round is already over by
		-- the time you land, you go straight back onto the court for the next one.
		S.PlayerStateService.setStatus(c, "Spectating")
		task.delay(J.RespawnDelay, function()
			if
				roundId ~= thisRound
				or c.status ~= "Spectating"
				or not c.inMatch
				or staging
				or not S.PlayerStateService.isAlive(c)
			then
				return
			end
			local spot = if state == "RoundActive" then jailSpot(c) else spawnFor(c)
			S.CharacterService.placeFacing(c, spot, faceCenter(spot))
			S.PlayerStateService.setAction(c, "Idle")
			if c.player then
				S.NetService.send(c.player, "Hint", { text = "Next round soon", duration = 3 })
			end
		end)
	end
end

function MatchService.onJailHit(thrower: any, target: any)
	if overtime or thrower.status ~= "Jailed" or not thrower.inMatch then
		-- sudden death: prisoners can no longer get back in
		return
	end
	S.PlayerStateService.setStatus(thrower, "Returning")
	thrower.jailReturns += 1
	if target == thrower.eliminatedBy then
		thrower.stats.revenges += 1
		if thrower.player then
			S.NetService.send(
				thrower.player,
				"Banner",
				{ text = "REVENGE!", color = Color3.fromRGB(255, 200, 40), duration = 1.5, sound = "Revenge" }
			)
		end
		feed(("%s got REVENGE on %s!"):format(tag(thrower), tag(target)))
		S.AnalyticsService.event(thrower, "RevengeHit")
	end
	local thisRound = roundId
	task.delay(J.ReturnDelay, function()
		if
			roundId ~= thisRound
			or (thrower.status :: string) ~= "Returning"
			or not MatchService.isRoundLive()
			or overtime
		then
			return
		end
		if thrower.heldBall then
			S.BallService.drop(thrower)
		end
		-- back on your own half: the camera still points the way it did in jail (away from the
		-- enemy from here), so swing it round too
		local pos = spawnFor(thrower)
		S.CharacterService.placeFacing(thrower, pos, faceCenter(pos))
		S.PlayerStateService.setStatus(thrower, "Active")
		S.PlayerStateService.setAction(thrower, "Idle")
		thrower.immuneUntil = now() + J.ReturnImmunity
		-- damage % carries over: escaping jail doesn't wipe the knockback you've built up
		thrower.stats.jailEscapes += 1
		feed(("%s escaped jail!"):format(tag(thrower)))
		S.AnalyticsService.event(thrower, "JailReturn")
	end)
end

-- Per-step court checks. All void eliminations found this step are resolved together, so a win is
-- never decided by callback order.
local function courtStep()
	local fallen = {}
	for _, c in roster do
		if c.status == "Active" then
			if not S.PlayerStateService.isAlive(c) then
				table.insert(fallen, c)
			else
				local pos = c.root.Position
				if pos.Y < ArenaLayout.VoidY then
					table.insert(fallen, c)
				elseif c.action == "Ragdolled" then
					-- once a flung body is past the court edge it becomes "ejected": the one-way edge
					-- walls stop it bouncing back on. If it somehow stays off the court without
					-- falling (wedged on an edge), it still counts as out after a few seconds.
					local sign = ArenaLayout.teamSign(c.team)
					local rel = pos - Config.Arena.Origin
					local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps())
					local past = math.max(math.abs(rel.X) - hw, rel.Z * sign - ArenaLayout.HalfLength)
					if past > 0.8 then
						c.offCourtSince = c.offCourtSince or os.clock()
						if past > Config.Arena.EjectDistance and not c.ejected then
							-- fully beyond the one-way wall: from now on it can't bounce back in
							c.ejected = true
							S.RagdollService.markEjected(c.character)
						end
						if os.clock() - c.offCourtSince > Config.Arena.StuckOffCourtTime then
							table.insert(fallen, c)
						end
					else
						c.offCourtSince = nil
					end
				elseif c.action ~= "Ragdolled" then
					if pos.Y > ArenaLayout.SurfaceY - 1 then
						c.lastCourtPos = pos
					end
					-- server-side center line enforcement; collision alone is not sufficient
					local sign = ArenaLayout.teamSign(c.team)
					local rel = pos - Config.Arena.Origin
					if rel.Z * sign < -0.5 and pos.Y > ArenaLayout.SurfaceY - 2 then
						c.character:PivotTo(
							CFrame.new(pos.X, pos.Y, Config.Arena.Origin.Z + sign * 1.5) * c.root.CFrame.Rotation
						)
					end
				end
			end
		elseif (c.status == "Jailed" or c.status == "Spectating") and S.PlayerStateService.isAlive(c) then
			local pos = c.root.Position
			if pos.Y < ArenaLayout.VoidY then
				local spot = jailSpot(c)
				S.CharacterService.placeFacing(c, spot, faceCenter(spot))
			end
		end
	end
	for _, c in roster do
		if c.action ~= "Ragdolled" then
			c.offCourtSince = nil
			c.ejected = nil
		end
	end
	for _, c in fallen do
		c.offCourtSince = nil
		c.ejected = nil
		eliminate(c)
	end
	if #fallen > 0 then
		local red, blue = activeCounts()
		local counts: { [string]: number } = { Red = red, Blue = blue }
		for team, n in counts do
			if n == 1 then
				for _, c in roster do
					if c.team == team and c.status == "Active" and c.player then
						S.NetService.send(c.player, "Banner", {
							text = "LAST PLAYER!",
							color = Color3.fromRGB(255, 220, 60),
							duration = 1.5,
							sound = "LastPlayer",
						})
					end
				end
			end
		end
	end
end

-- Round flow -------------------------------------------------------------------------------------

local function resetCombatant(c: any)
	if c.heldBall then
		S.BallService.drop(c)
	end
	c.jailReturns = 0
	c.eliminatedBy = nil
	c.lastHitBy = nil
	c.lastHitAt = -math.huge
	c.immuneUntil = 0
	S.PlayerStateService.setDamage(c, 0)
	c.chargeStart = nil
	c.catchUntil = 0
	c.dodgeReadyAt = 0
	c.catchReadyAt = 0
	S.PowerService.reset(c) -- empty ultimate meter, fresh powers, no ice or phantom left over
	S.PlayerStateService.setStatus(c, "Active")
	S.PlayerStateService.setAction(c, "Idle")
	S.PlayerStateService.syncAttributes(c)
	S.CharacterService.setTeamVisual(c)
end

local function freeze(on: boolean)
	for _, c in roster do
		if c.humanoid then
			c.humanoid.WalkSpeed = if on then 0 else Config.Player.WalkSpeed
			c.humanoid.JumpPower = if on then 0 else Config.Player.JumpPower
		end
	end
end

-- Joining and leaving mid-match ---------------------------------------------------------------------

-- Rounds you can drop into: the countdown and the live round (not the intro, a finisher or the gap
-- after a round, when admitWaiting puts waiting players in at the next round's reset anyway).
local JOIN_STATES = { RoundCountdown = true, RoundActive = true }

local function halt(c: any)
	if c.humanoid then
		c.humanoid.WalkSpeed = 0
		c.humanoid.JumpPower = 0
	end
end

local function realOnTeam(team: string): number
	local n = 0
	for _, c in roster do
		if c.team == team and c.player and c.player.Parent then
			n += 1
		end
	end
	return n
end

-- The bot a joiner takes over: one still on the court, on the side with fewer real players, the
-- least damaged first (you inherit its %).
local function openBot(): any?
	local best, bestKey = nil, math.huge
	local redReal, blueReal = realOnTeam("Red"), realOnTeam("Blue")
	for _, c in roster do
		if c.isBot and c.status == "Active" and S.PlayerStateService.isAlive(c) and not c.heldBall then
			local real = if c.team == "Red" then redReal else blueReal
			local key = real * 10000 + (c.damage or 0)
			if key < bestKey then
				best, bestKey = c, key
			end
		end
	end
	return best
end

function MatchService.openSlots(): number
	if not M.JoinInProgress or not JOIN_STATES[state] or staging or (realInRoster() == 0 and not botOnlyOk) then
		return 0
	end
	local n = 0
	for _, c in roster do
		if c.isBot and c.status == "Active" and S.PlayerStateService.isAlive(c) then
			n += 1
		end
	end
	return n
end

-- Put a hub player straight into the live round in place of a bot (see Config.Match.JoinInProgress).
-- Returns whether they went in.
function MatchService.joinInProgress(c: any): boolean
	if
		c.inMatch
		or not c.player
		or not c.profileLoaded
		or c.spawning
		or c.player:GetAttribute("TutorialDone") ~= true
		or c.player:GetAttribute("InDevRoom") == true
		or not S.PlayerStateService.isAlive(c)
		or MatchService.openSlots() == 0
	then
		return false
	end
	local bot = openBot()
	if not bot then
		return false
	end
	local team = bot.team
	local index = table.find(roster, bot)
	local cf = bot.root.CFrame
	local damage = bot.damage or 0
	S.BotService.remove(roster, bot)
	S.TeamService.enter(c, roster, team, index)
	c.lateJoin = true -- joined mid-match: can win, but not "flawless"
	c.matchStartedAt = now()
	resetCombatant(c)
	S.PlayerStateService.setDamage(c, damage)
	c.immuneUntil = now() + M.JoinImmunity
	S.CharacterService.placeFacing(c, cf.Position, faceCenter(cf.Position))
	if state == "RoundCountdown" then
		halt(c)
	elseif c.humanoid then
		c.humanoid.WalkSpeed = Config.Player.WalkSpeed
		c.humanoid.JumpPower = Config.Player.JumpPower
	end
	S.AnalyticsService.matchStarted(c)
	S.AnalyticsService.event(c, "JoinInProgress", if state == "RoundActive" then 1 else 0)
	feed(("%s jumped in!"):format(tag(c)))
	publishCounts()
	return true
end

-- Someone in the match is leaving it (the Leave button, or leaving the game). A bot with their name
-- and avatar carries on in their slot, in the same state (status, damage, jail returns, who last hit
-- them), so their team is never a player short. Nobody stands in once no real player is left: the
-- match aborts then anyway. The bot is built after they're off the roster, since the avatar build
-- yields; if the round or match moved on meanwhile it's fitted to that instead.
local function handOff(c: any)
	local index = table.find(roster, c)
	if not index then
		return
	end
	if c.heldBall then
		S.BallService.drop(c)
	end
	-- spawn and jail spots are worked out while they're still on the roster
	local cf: CFrame? = nil
	local root = c.root :: BasePart?
	if c.status == "Active" and root and root.Parent then
		cf = root.CFrame
	else
		local spot = if c.status == "Active" then spawnFor(c) else jailSpot(c)
		cf = ArenaLayout.faceFlat(spot, faceCenter(spot))
	end
	table.remove(roster, index)
	local team = c.team
	if not team or (realInRoster() == 0 and not botOnlyOk) then
		return
	end
	local snapshot = {
		status = c.status,
		damage = c.damage or 0,
		jailReturns = c.jailReturns,
		lastHitBy = c.lastHitBy,
		lastHitAt = c.lastHitAt,
		immuneUntil = c.immuneUntil,
		matchEliminations = c.matchEliminations,
	}
	local level = if c.profile then tonumber(c.profile.Level) or 1 else 1
	local thisMatch, thisRound = matchId, roundId
	task.spawn(function()
		local ok, bot = pcall(S.BotService.create, team, roster, S.BotService.pickDifficulty(level), {
			name = c.name,
			desc = c.avatarDesc,
			avatarUserId = if c.player then c.player.UserId else c.avatarUserId,
			cf = cf,
			index = index,
		})
		if not ok then
			warn("[Match] stand-in bot failed: " .. tostring(bot))
			return
		end
		if matchId ~= thisMatch or not table.find(roster, bot) then
			S.BotService.remove(roster, bot) -- the match ended while it was being built
			return
		end
		if roundId ~= thisRound then
			resetCombatant(bot) -- a new round started: it plays it fresh from its spawn
			local pos = spawnFor(bot)
			S.CharacterService.teleport(bot, pos, faceCenter(pos))
		else
			S.PlayerStateService.setStatus(bot, snapshot.status)
			S.PlayerStateService.setDamage(bot, snapshot.damage)
			bot.jailReturns = snapshot.jailReturns
			bot.lastHitBy = snapshot.lastHitBy
			bot.lastHitAt = snapshot.lastHitAt
			bot.immuneUntil = snapshot.immuneUntil
			bot.matchEliminations = snapshot.matchEliminations
			S.PlayerStateService.syncAttributes(bot)
			S.CharacterService.setTeamVisual(bot)
		end
		-- hits the leaver landed still count: a knockout from them is credited to their stand-in
		for _, o in roster do
			if o.lastHitBy == c then
				o.lastHitBy = bot
			end
		end
		if lastElim and lastElim.credit == c then
			lastElim.credit = bot
		end
		if state == "RoundCountdown" or state == "Intro" then
			halt(bot)
		end
		publishCounts()
	end)
	publishCounts()
end

-- The in-match Leave button: back to the hub, with a stand-in bot in your place. You keep the
-- knockout coins already paid and your quest progress; the match's own reward is gone. PLAY is off
-- afterwards (or you'd be put straight back in).
function MatchService.leaveMatch(c: any): boolean
	if not c.inMatch or not table.find(roster, c) or state == "Intro" or state == "Finisher" or staging then
		return false
	end
	S.AnalyticsService.event(c, "LeftMatch_" .. tostring(c.status), tonumber(stateFolder:GetAttribute("Round")) or 0)
	handOff(c)
	c.autoQueue = false
	c.queueDeclined = true -- no solo auto-queue straight back in
	if c.player then
		c.player:SetAttribute("AutoQueue", false)
	end
	MatchService.moveToLobby(c)
	publishCounts()
	return true
end

-- TestService: let a match run with no real player in it, so one Studio player can leave and rejoin.
function MatchService.debugAllowBotOnly(on: boolean)
	botOnlyOk = on
end

local function resetRound()
	roundId += 1
	overtime = false
	lastElim = nil
	roundHits = { Red = 0, Blue = 0 }
	MatchService.setAttr("Overtime", false)
	S.ArenaService.resetCourt()
	S.TeamService.admitWaiting(roster, teamSize)
	-- clear held balls first so nobody carries one through the reset
	for _, c in roster do
		if c.heldBall then
			S.BallService.drop(c)
		end
	end
	S.BallService.resetMatchBalls()
	for _, c in roster do
		local pos = spawnFor(c)
		if not S.PlayerStateService.isAlive(c) then
			-- built facing the enemy: a build still waiting on the avatar finishes after the teleport
			-- below, so its own CFrame is where it ends up
			local cf = ArenaLayout.faceFlat(pos, faceCenter(pos))
			if c.player then
				S.CharacterService.spawnPlayer(c, cf)
			else
				S.CharacterService.spawn(c, Instance.new("HumanoidDescription"), cf)
			end
		end
		resetCombatant(c)
		S.CharacterService.teleport(c, pos, faceCenter(pos))
	end
	publishCounts()
end

local function teamEmpty(team: string): boolean
	for _, c in roster do
		if c.team == team then
			return false
		end
	end
	return true
end

local function shouldAbort(): boolean
	return (realInRoster() == 0 and not botOnlyOk) or teamEmpty("Red") or teamEmpty("Blue")
end

-- Feed line naming today's featured ball (Config.PowerUps.Featured), once a match.
local function announceFeatured()
	local featured = S.ShopService.featuredBall()
	if not featured then
		return
	end
	local def = BallDefinitions.get(featured)
	feed(
		('⭐ Featured ball today: <b><font color="#%s">%s</font></b>. Its knockouts count x%d for mastery!'):format(
			def.Color:ToHex(),
			def.DisplayName,
			Config.PowerUps.Featured.MasteryBonus
		)
	)
end

local function waitPhase(seconds: number, abortCheck: (() -> boolean)?): boolean
	local endsAt = now() + seconds
	while now() < endsAt do
		if abortCheck and abortCheck() then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Before a round goes live (intro, countdown) everyone belongs on their own half, and the void check
-- isn't running yet. Anyone who isn't there (a respawn that landed in the hub, a teleport their
-- client undid, a fall) goes back to their spawn instead of falling into jail when the round starts.
local function holdOnSpawn()
	local steps = S.ArenaService.getOvertimeSteps()
	for _, c in roster do
		if c.status == "Active" and not c.spawning and S.PlayerStateService.isAlive(c) then
			local pos = c.root.Position
			if pos.Y < ArenaLayout.SurfaceY - 2 or not ArenaLayout.onHalf(c.team, pos, steps, -2) then
				local spot = spawnFor(c)
				S.CharacterService.placeFacing(c, spot, faceCenter(spot))
				if c.humanoid then
					c.humanoid.WalkSpeed = 0
					c.humanoid.JumpPower = 0
				end
			end
		end
	end
end

local function startSuddenDeath()
	overtime = true
	MatchService.setAttr("Overtime", true)
	MatchService.setAttr("PhaseEndsAt", 0)
	banner("SUDDEN DEATH!", Color3.fromRGB(255, 80, 60), 2, "SuddenDeath")
	-- prisoners can no longer respawn: anyone mid-return stays in jail
	for _, c in roster do
		if c.status == "Returning" then
			S.PlayerStateService.setStatus(c, "Jailed")
		end
	end
end

-- Returns ("Red" | "Blue" | "Draw" | "Abort", endedByElimination).
-- When the round timer runs out it never ends on a count: SUDDEN DEATH starts instead. Jail closes
-- and the court keeps shrinking until a team is out. Only if the court is fully shrunk and it
-- still hasn't ended after SuddenDeathFallback seconds does a count, then hits, decide it.
local function playRound(): (string, boolean)
	setState("RoundActive", M.RoundTime)
	banner("GO!", Color3.fromRGB(120, 255, 140), 0.8, "Go")
	S.PowerService.roundStarted(roster)
	-- comeback: the team behind on rounds starts with some ultimate meter
	local behind = if wins.Red < wins.Blue then "Red" elseif wins.Blue < wins.Red then "Blue" else nil
	if behind then
		S.PowerService.comeback(roster, behind)
	end
	local endsAt = now() + M.RoundTime
	local sdStart = 0
	local stepsDone = 0
	local warned = 0
	local fallbackAt = math.huge
	local nextPublish = 0
	S.AnalyticsService.roundStarted(roster)
	while true do
		task.wait()
		local t = now()
		courtStep()
		if t >= nextPublish then
			publishCounts()
			nextPublish = t + 0.2
		end
		if shouldAbort() then
			return "Abort", false
		end
		-- dev T: this player's team wins now, ending on their finisher over a random enemy
		local dev = devFinisherBy
		if dev then
			devFinisherBy = nil
			local enemies = {}
			for _, e in roster do
				if e.team ~= dev.team and S.PlayerStateService.isAlive(e) then
					table.insert(enemies, e)
				end
			end
			if #enemies > 0 and dev.team then
				local victim = enemies[rng:NextInteger(1, #enemies)]
				if victim.character and S.RagdollService.isRagdolled(victim.character) then
					S.RagdollService.recover(victim.character, nil)
				end
				-- stage them where they stand if that's on the court, else at their spawn
				local pos = victim.root.Position
				if not ArenaLayout.onHalf(victim.team, pos, S.ArenaService.getOvertimeSteps(), 0) then
					pos = spawnFor(victim)
				end
				victim.lastCourtPos = pos
				lastElim = { victim = victim, credit = dev }
				wins[dev.team] = roundsToWin - 1
				return dev.team, true
			end
		end
		local red, blue = activeCounts()
		if red == 0 and blue == 0 then
			return "Draw", true -- simultaneous final eliminations resolve together
		elseif red == 0 then
			return "Blue", true
		elseif blue == 0 then
			return "Red", true
		end
		if clockHeld and not overtime then
			endsAt = math.max(endsAt, t + 1)
		end
		if devOvertime and not overtime then
			devOvertime = false
			endsAt = t
		end
		if not overtime and t >= endsAt then
			startSuddenDeath()
			sdStart = t
		end
		if overtime then
			local A = Config.Arena
			local k = stepsDone + 1
			if k <= A.OvertimeStrips then
				local stepAt = sdStart + k * A.OvertimeStepInterval
				if warned < k and t >= stepAt - A.OvertimeWarning then
					warned = k
					S.ArenaService.warnStrips(k)
				end
				if t >= stepAt then
					stepsDone = k
					S.ArenaService.retractStrips(k)
					if k == A.OvertimeStrips then
						fallbackAt = t + M.SuddenDeathFallback
					end
				end
			elseif t >= fallbackAt then
				if red ~= blue then
					return if red > blue then "Red" else "Blue", false
				end
				if roundHits.Red ~= roundHits.Blue then
					return if roundHits.Red > roundHits.Blue then "Red" else "Blue", false
				end
				return "Draw", false
			end
		end
	end
end

-- Finisher: everyone in the match watches the match-ending knockout. The server stages it
-- (freezes play, re-launches the victim per the finisher's Stage data) and each client plays the
-- finisher module's camera/effects. Finisher modules live in ReplicatedStorage.Shared.Finishers.
local function playFinisher(killer: any, victim: any, winner: string)
	if not Config.Finisher.Enabled then
		return
	end
	local moduleName = S.ShopService.finisherModule(killer)
	local folder = Shared:FindFirstChild("Finishers")
	local moduleScript = folder
		and (folder:FindFirstChild(moduleName) or folder:FindFirstChild(Config.Finisher.DefaultId))
	if not moduleScript then
		return
	end
	local ok, def = pcall(require, moduleScript)
	if not ok or type(def) ~= "table" then
		warn("[Finisher] could not load " .. moduleName)
		return
	end
	local duration = math.clamp(tonumber(def.Duration) or 4, Config.Finisher.MinDuration, Config.Finisher.MaxDuration)
	staging = true
	setState("Finisher", duration)
	freeze(true)
	-- the court is the set: wherever they really are, the winner stands in the middle of their half
	-- and the victim in the middle of theirs, facing each other
	local stage = def.Stage or {}
	local up = Vector3.new(0, 3, 0)
	local killerAt = ArenaLayout.halfCenter(winner) + up
	local victimAt = ArenaLayout.halfCenter(victim.team or ArenaLayout.enemyOf(winner)) + up
	local staged = false
	for _, c in { killer, victim } do
		if c.character and S.PlayerStateService.isAlive(c) then
			local at, facing = if c == killer then killerAt else victimAt, if c == killer then victimAt else killerAt
			S.CharacterService.teleport(c, at, facing) -- also stands them up if ragdolled
			staged = true
		end
	end
	if staged then
		task.wait(0.15) -- let the teleports replicate before clients build the scene
	end
	local payload = {
		module = moduleScript.Name,
		killer = killer.character,
		victim = victim.character,
		killerName = killer.name,
		victimName = victim.name,
		winner = winner,
		duration = duration,
		killerCF = CFrame.lookAt(killerAt, victimAt),
		victimCF = CFrame.lookAt(victimAt, killerAt),
	}
	for _, c in roster do
		if c.player then
			S.NetService.send(c.player, "Finisher", payload)
		end
	end
	-- launched off the far end for the camera, hard enough to clear the jail on any court size
	-- (ArenaLayout.finisherLaunch); Stage.Launch = false means the finisher moves the victim itself
	-- (client-side puppet)
	if stage.Launch ~= false and victim.character and S.PlayerStateService.isAlive(victim) then
		local launch, cap = ArenaLayout.finisherLaunch(victimAt, killerAt, stage)
		task.delay(tonumber(stage.LaunchDelay) or 0.8, function()
			if victim.character then
				S.RagdollService.ragdoll(victim.character, launch, cap)
				-- clear the jail barrier, and never get switched to "Ejected" (which collides with it)
				victim.ejected = true
				S.RagdollService.markFinisherFlight(victim.character)
			end
		end)
	end
	S.AnalyticsService.event(killer, "FinisherPlayed_" .. moduleScript.Name)
	waitPhase(duration, nil)
	staging = false
end

-- Intro (Splatoon-style): everyone is already on their spawn facing the center line (resetRound).
-- Every client plays each player's equipped intro pose; players in the match also get the camera,
-- which pans across one team, then the other (Config.Intro). The 3-2-1 countdown follows.
local function playIntro()
	local I = Config.Intro
	if not I.Enabled then
		return
	end
	local teams = {}
	local total = 0
	local times = {}
	-- every real player here has already sat through an intro this session: a quicker one
	local introScale = I.RepeatScale or 1
	for _, c in roster do
		if c.player and (c.sessionGames or 0) == 0 then
			introScale = 1
			break
		end
	end
	for _, team in I.Order do
		local members = {}
		local minX, maxX = math.huge, -math.huge
		local sumZ, n = 0, 0
		for _, c in roster do
			if c.team == team and S.PlayerStateService.isAlive(c) then
				local pos = c.root.Position
				minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
				sumZ += pos.Z
				n += 1
				table.insert(members, { model = c.character, pose = S.ShopService.introPose(c) })
			end
		end
		if n > 0 then
			teams[team] = {
				members = members,
				center = Vector3.new((minX + maxX) / 2, ArenaLayout.SurfaceY + 3, sumZ / n),
				facing = Vector3.new(0, 0, -ArenaLayout.teamSign(team)), -- toward the center line
				halfWidth = (maxX - minX) / 2,
			}
		end
		local t = (if team == "Blue" then I.BlueTime else I.RedTime) * introScale
		table.insert(times, t)
		total += t
	end
	setState("Intro", total)
	for _, c in S.PlayerStateService.realPlayers() do
		S.NetService.send(c.player, "Intro", {
			teams = teams,
			order = I.Order,
			times = times,
			cinematic = c.inMatch, -- only players in the match get the camera
		})
	end
	waitPhase(total, function()
		holdOnSpawn()
		return false
	end)
end

local function runMatch(queued: { any })
	matchId += 1
	MatchService.setAttr("MatchId", matchId)
	roster = {}
	teamSize = S.TeamService.teamSizeFor(#queued)
	MatchService.setAttr("TeamSize", teamSize)
	S.TeamService.assign(queued, roster, teamSize)
	S.BotService.fill(roster, teamSize)
	wins = { Red = 0, Blue = 0 }
	MatchService.setAttr("RedWins", 0)
	MatchService.setAttr("BlueWins", 0)
	-- a match of only brand-new players (no finished game yet) is a single round: their first
	-- reward and results card come sooner (Config.Match.FirstMatchRounds)
	roundsToWin = M.RoundsToWin
	local allNew, anyReal = true, false
	for _, c in roster do
		if c.player then
			anyReal = true
			if not c.profile or (tonumber(c.profile.Matches) or 0) > 0 then
				allNew = false
			end
		end
	end
	if anyReal and allNew then
		roundsToWin = M.FirstMatchRounds
	end
	MatchService.setAttr("RoundsToWin", roundsToWin)
	local roundNumber = 0
	local draws = 0
	local aborted = false
	local finalEliminator: any? = nil
	local matchStart = now()
	S.AnalyticsService.setMatchType(roster)
	for _, c in roster do
		c.stats = S.PlayerStateService.newStats()
		c.matchStartedAt = matchStart
		c.matchEliminations = 0
		c.aliveAtWin = false
		c.lateJoin = false
		S.AnalyticsService.matchStarted(c)
	end
	while wins.Red < roundsToWin and wins.Blue < roundsToWin do
		roundNumber += 1
		MatchService.setAttr("Round", roundNumber)
		resetRound()
		freeze(true)
		if roundNumber == 1 and draws == 0 then
			playIntro() -- the first round of a match opens with the team intro
		end
		setState("RoundCountdown", M.RoundCountdown)
		S.BotService.setPaused(false)
		-- server-driven 3-2-1 so every client shows each tick, then GO! when the round goes live
		local ok = true
		for n = M.RoundCountdown, 1, -1 do
			for _, c in roster do
				if c.player then
					S.NetService.send(c.player, "Countdown", { n = n })
				end
			end
			if not waitPhase(1, function()
				holdOnSpawn()
				return shouldAbort()
			end) then
				ok = false
				break
			end
		end
		freeze(false)
		if not ok then
			aborted = true
			break
		end
		if roundNumber == 1 then
			announceFeatured()
			-- new players: how you actually win a fight (damage % only sets how far you fly)
			for _, c in roster do
				if c.player and c.profile and (tonumber(c.profile.Matches) or 0) < Config.Damage.HintMatches then
					S.NetService.send(c.player, "Hint", { text = "Hit them off the court!", duration = 3, fade = true })
				end
			end
		end
		local result, byElimination = playRound()
		publishCounts()
		if result == "Abort" then
			aborted = true
			break
		end
		local decidesMatch = (result == "Red" or result == "Blue") and wins[result] + 1 >= roundsToWin
		if not decidesMatch then
			-- nobody goes back to the hub between rounds: the jailed stay in jail, and anyone knocked
			-- out for good (sudden death) is put straight back on the court for the next round
			for _, c in roster do
				if c.status == "Spectating" and S.PlayerStateService.isAlive(c) then
					local pos = spawnFor(c)
					S.CharacterService.placeFacing(c, pos, faceCenter(pos))
				end
			end
		end
		if decidesMatch then
			MatchService.botBanter(result)
			-- reward tiers read this: who was still on the court when the match was won
			for _, c in roster do
				c.aliveAtWin = c.team == result and c.status == "Active"
			end
			local elim = lastElim
			if byElimination and elim and elim.credit and elim.credit.team == result then
				finalEliminator = elim.credit
				playFinisher(elim.credit, elim.victim, result)
			end
		end
		setState("RoundResolution", M.RoundResolution)
		if result == "Draw" then
			draws += 1
			roundNumber -= 1
			banner("DRAW! REPLAY!", Color3.new(1, 1, 1), 2)
		else
			wins[result] += 1
			MatchService.setAttr("RedWins", wins.Red)
			MatchService.setAttr("BlueWins", wins.Blue)
			-- the match-winning round goes straight to "RED WINS!" (no stacked round + match banners)
			if decidesMatch then
				resultBanner(("%s WINS!"):format(Config.Teams[result].Name), result, 2.4)
			else
				resultBanner(("%s WINS THE ROUND!"):format(Config.Teams[result].Name), result, 2.2)
			end
		end
		S.AnalyticsService.roundEnded(roster)
		S.AnalyticsService.event(nil, "RoundDuration", now() - matchStart)
		if not waitPhase(M.RoundResolution, nil) then
			break
		end
		if draws > M.MaxDrawReplays then
			break -- avoid infinite replays; the match ends without a winner
		end
	end
	S.BotService.setPaused(true)

	local winner: string? = nil
	if not aborted then
		if wins.Red >= roundsToWin then
			winner = "Red"
		elseif wins.Blue >= roundsToWin then
			winner = "Blue"
		end
	end
	-- the winner banner already played during the final round's resolution, and that wait outlasts
	-- it, so the results card below never overlaps it
	if aborted then
		banner("MATCH ABORTED", Color3.new(1, 1, 1), 2)
	end
	local bots = 0
	for _, c in roster do
		if c.isBot then
			bots += 1
		end
	end
	local casual = bots * 2 > #roster
	S.RewardService.awardMatch(roster, {
		matchId = matchId,
		winner = winner,
		aborted = aborted,
		casual = casual,
		duration = now() - matchStart,
		finalEliminator = finalEliminator,
	})
	S.AnalyticsService.matchEnded(
		roster,
		{ aborted = aborted, bots = bots, duration = now() - matchStart, winner = winner }
	)
	S.ArenaService.resetCourt()
	S.BallService.clearContext("Match")
	S.BotService.clear()
	local finished = roster
	roster = {}
	for _, c in finished do
		if c.player and c.player.Parent then
			MatchService.moveToLobby(c)
		end
	end
	publishCounts()
end

-- A couple of bots say something in a chat bubble as the match is decided ("gg"), so a bot-filled
-- server feels a little more alive (Config.Bots.Banter). Clients draw the bubble (HUDController).
function MatchService.botBanter(winner: string)
	local BT = Config.Bots.Banter
	if not BT or not BT.Enabled then
		return
	end
	local said = 0
	for _, c in roster do
		if said >= BT.MaxPerMatch then
			break
		end
		if c.isBot and c.character and math.random() < BT.Chance then
			said += 1
			local lines = if c.team == winner then BT.Win else BT.Lose
			local text = lines[math.random(1, #lines)]
			local model = c.character
			task.delay(math.random() * 1.2 + 0.3, function()
				if model.Parent then
					S.NetService.broadcast("BotChat", { model = model, text = text })
				end
			end)
		end
	end
end

-- The one real player in the server, when they'd be queued but for PLAY and haven't opted out (see
-- Config.Match.SoloAutoQueue).
local function soloCandidate(): any?
	if not M.SoloAutoQueue then
		return nil
	end
	local players = S.PlayerStateService.realPlayers()
	if #players ~= 1 then
		return nil
	end
	local c = players[1]
	if
		c.autoQueue
		or c.queueDeclined
		or c.inMatch
		or not c.profileLoaded
		or not c.player
		or c.player:GetAttribute("TutorialDone") ~= true
		or c.player:GetAttribute("InDevRoom") == true
		or not S.PlayerStateService.isAlive(c)
	then
		return nil
	end
	return c
end

function MatchService.run()
	while true do
		local queued = MatchService.queuedPlayers()
		local lobbyWait = M.LobbyMaxWait
		if #queued == 0 then
			setState("WaitingForPlayers")
			local solo = nil
			repeat
				task.wait(0.25)
				queued = MatchService.queuedPlayers()
				solo = if #queued == 0 then soloCandidate() else nil
			until #queued > 0 or solo
			if solo then
				-- alone in the hub: queue them, and fresh out of the tutorial, start almost at once
				solo.autoQueue = true
				solo.player:SetAttribute("AutoQueue", true)
				local doneAt = solo.tutorialDoneAt
				if doneAt and os.clock() - doneAt <= M.SoloAfterTutorialWindow then
					lobbyWait = M.SoloAfterTutorialWait
				end
				solo.tutorialDoneAt = nil
				queued = MatchService.queuedPlayers()
			end
		end
		-- someone fresh out of the tutorial is waiting: their first match starts almost at once
		for _, c in queued do
			if c.tutorialDoneAt and os.clock() - c.tutorialDoneAt <= M.SoloAfterTutorialWindow then
				lobbyWait = math.min(lobbyWait, M.SoloAfterTutorialWait)
				c.tutorialDoneAt = nil
			end
		end
		-- the intermission always runs its full wait (PLAY only queues you; nobody can start it
		-- early), unless the match is already full
		setState("Intermission", lobbyWait)
		local endsAt = now() + lobbyWait
		local cancelled = false
		while now() < endsAt do
			task.wait(0.2)
			queued = MatchService.queuedPlayers()
			if #queued == 0 then
				cancelled = true
				break
			end
			if devSkip or (M.IntermissionSkipWhenFull and #queued >= M.MaxPlayers) then
				devSkip = false
				break
			end
		end
		if not cancelled then
			local trace = ""
			local ok = xpcall(runMatch, function(e)
				trace = debug.traceback(tostring(e))
				return e
			end, MatchService.queuedPlayers())
			if not ok then
				warn("[Match] match crashed, recovering: " .. trace)
				MatchService.recover()
			end
		end
	end
end

-- A script error mid-match must never strand players on the court or stop matchmaking for the rest
-- of the server's life: tidy everything back to the hub and let the loop start the next match.
function MatchService.recover()
	staging = false
	devFinisherBy = nil
	devSkip = false
	devOvertime = false
	overtime = false
	MatchService.setAttr("Overtime", false)
	pcall(S.BotService.setPaused, true)
	pcall(S.ArenaService.resetCourt)
	pcall(S.BallService.clearContext, "Match")
	pcall(S.BotService.clear)
	local finished = roster
	roster = {}
	for _, c in finished do
		if c.player and c.player.Parent then
			pcall(MatchService.moveToLobby, c)
		end
	end
	-- anyone still flagged in a match without being on the roster (half-admitted) goes back too
	for _, c in S.PlayerStateService.realPlayers() do
		if c.inMatch then
			pcall(MatchService.moveToLobby, c)
		end
	end
	pcall(publishCounts)
	banner("MATCH ABORTED", Color3.new(1, 1, 1), 2)
	task.wait(1)
end

-- Population changes -------------------------------------------------------------------------------

-- Left the game: a bot with their name takes their place if they were in the match (handOff).
function MatchService.onLeave(c: any)
	handOff(c)
	if c.heldBall then
		S.BallService.drop(c)
	end
	publishCounts()
end

-- A player's character vanished (e.g. destroyed by the engine). During a live round an active
-- player's loss counts as a fall; before it (intro, countdown) it doesn't, and they're rebuilt on
-- their spawn. Returns where to rebuild them, or nil for the hub.
function MatchService.onCharacterLost(c: any): Vector3?
	if not c.inMatch then
		return nil
	end
	if c.status == "Active" then
		if not MatchService.isRoundLive() then
			return spawnFor(c)
		end
		eliminate(c)
	end
	if c.status == "Jailed" or c.status == "Spectating" or c.status == "Returning" then
		return ArenaLayout.jailCenter(c.team) + Vector3.new(0, 3, 0)
	end
	return spawnFor(c)
end

return MatchService
