--!strict
-- Match state machine (spec §5, Amendment A1/A3):
-- WaitingForPlayers -> Intermission -> RoundCountdown -> RoundActive -> RoundResolution
--   -> RoundCountdown (next round) | results overlay during the next Intermission.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
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
local roundHits = { Red = 0, Blue = 0 }
local overtime = false
local teamSize = 3
local devSkip = false
local devOvertime = false
-- the most recent void elimination this round: who fell and who (if anyone) gets the credit
local lastElim: { victim: any, credit: any? }? = nil
local staging = false -- a finisher is staging the victim; don't move them to jail/lobby

local function now(): number
	return Workspace:GetServerTimeNow()
end

function MatchService.setAttr(key: string, value: any)
	if stateFolder then
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

-- A win/lose banner: same text for everyone, but winners and losers hear different stingers.
local function resultBanner(text: string, winner: string, duration: number)
	local color = Config.Teams[winner].Color
	for _, c in S.PlayerStateService.realPlayers() do
		local sound = if c.inMatch and c.team == winner then "RoundWin" elseif c.inMatch then "RoundLose" else nil
		S.NetService.send(c.player, "Banner", { text = text, color = color, duration = duration, sound = sound })
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
end

function MatchService.start()
	S.NetService.on(NetSchema.Actions.Dev, function(player, p)
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
				S.CombatService.debugLaunch(c, 1)
			end
		end
	end)
	task.spawn(MatchService.run)
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

local function publishCounts()
	local red, blue = activeCounts()
	local jail = MatchService.jailedCounts()
	MatchService.setAttr("RedActive", red)
	MatchService.setAttr("BlueActive", blue)
	MatchService.setAttr("RedJail", jail.Red)
	MatchService.setAttr("BlueJail", jail.Blue)
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
		if c.autoQueue and not c.inMatch and S.PlayerStateService.isAlive(c) and c.profileLoaded then
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
	S.CharacterService.teleport(c, ArenaLayout.lobbySpawn(rng))
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
	S.AnalyticsService.hitResolved(c, "Void")
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
			reward = Config.Coins.Elimination
			credit.profile.Coins += reward
			credit.stats.eliminationCoins += reward
			S.DataService.push(credit)
		end
		feed(("%s 💥 launched %s off the court!"):format(tag(credit), tag(c)))
	else
		feed(("%s fell off!"):format(tag(c)))
	end
	if c.player then
		S.NetService.send(c.player, "Banner", { text = "KNOCKED OUT!", color = Color3.fromRGB(255, 90, 80), duration = 1.4, sound = "KnockedOut" })
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
				S.CharacterService.teleport(c, jailSpot(c), faceCenter(jailSpot(c)))
				S.PlayerStateService.setAction(c, "Idle")
			end
		end)
	else
		S.PlayerStateService.setStatus(c, "Spectating")
		task.delay(J.RespawnDelay, function()
			if c.status == "Spectating" and not staging and S.PlayerStateService.isAlive(c) then
				S.CharacterService.teleport(c, ArenaLayout.lobbySpawn(rng))
				S.PlayerStateService.setAction(c, "Idle")
				if c.player then
					S.NetService.send(c.player, "Hint", { text = "Next round soon", duration = 3 })
				end
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
			S.NetService.send(thrower.player, "Banner", { text = "REVENGE!", color = Color3.fromRGB(255, 200, 40), duration = 1.5, sound = "Revenge" })
		end
		feed(("%s got REVENGE on %s!"):format(tag(thrower), tag(target)))
		S.AnalyticsService.event(thrower, "RevengeHit")
	end
	local thisRound = roundId
	task.delay(J.ReturnDelay, function()
		if roundId ~= thisRound or (thrower.status :: string) ~= "Returning" or not MatchService.isRoundLive() or overtime then
			return
		end
		if thrower.heldBall then
			S.BallService.drop(thrower)
		end
		local pos = spawnFor(thrower)
		S.CharacterService.teleport(thrower, pos, faceCenter(pos))
		S.PlayerStateService.setStatus(thrower, "Active")
		S.PlayerStateService.setAction(thrower, "Idle")
		thrower.immuneUntil = now() + J.ReturnImmunity
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
						c.character:PivotTo(CFrame.new(pos.X, pos.Y, Config.Arena.Origin.Z + sign * 1.5) * c.root.CFrame.Rotation)
					end
				end
			end
		elseif c.status == "Jailed" and S.PlayerStateService.isAlive(c) then
			local pos = c.root.Position
			if pos.Y < ArenaLayout.VoidY then
				S.CharacterService.teleport(c, jailSpot(c))
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
						S.NetService.send(c.player, "Banner", { text = "LAST PLAYER!", color = Color3.fromRGB(255, 220, 60), duration = 1.5, sound = "LastPlayer" })
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
	c.chargeStart = nil
	c.catchUntil = 0
	c.dodgeReadyAt = 0
	c.catchReadyAt = 0
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
		if not S.PlayerStateService.isAlive(c) then
			if c.player then
				S.CharacterService.spawnPlayer(c, CFrame.new(spawnFor(c)))
			else
				S.CharacterService.spawn(c, Instance.new("HumanoidDescription"), CFrame.new(spawnFor(c)))
			end
		end
		resetCombatant(c)
		local pos = spawnFor(c)
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
	return realInRoster() == 0 or teamEmpty("Red") or teamEmpty("Blue")
end

local function spawnPowerUps()
	if not Config.PowerUps.Enabled then
		return
	end
	-- Both teams always receive the same type, so luck is never one-sided.
	local types = BallDefinitions.PowerTypes
	local weights = Config.PowerUps.Weights :: { [string]: number }
	local total = 0
	for _, t in types do
		total += weights[t] or 0
	end
	local roll = rng:NextNumber() * total
	local chosen = types[1]
	for _, t in types do
		roll -= weights[t] or 0
		if roll <= 0 then
			chosen = t
			break
		end
	end
	local spawned = false
	if
		S.BallService.countPower("Red") < Config.PowerUps.MaxPowerBallsPerSide
		and S.BallService.countPower("Blue") < Config.PowerUps.MaxPowerBallsPerSide
	then
		for _, team in { "Red", "Blue" } do
			S.BallService.spawn(chosen, S.ArenaService.dispenserPosition(team), "Match", true)
		end
		spawned = true
	end
	if spawned then
		feed(("%s balls dropped!"):format(BallDefinitions.get(chosen).DisplayName))
		S.NetService.broadcast("Sound", { cue = "PowerUp", position = S.ArenaService.dispenserPosition("Red") })
		S.NetService.broadcast("Sound", { cue = "PowerUp", position = S.ArenaService.dispenserPosition("Blue") })
	end
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
	local endsAt = now() + M.RoundTime
	local sdStart = 0
	local stepsDone = 0
	local warned = 0
	local fallbackAt = math.huge
	local nextPower = now() + Config.PowerUps.DispenserInterval
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
		local red, blue = activeCounts()
		if red == 0 and blue == 0 then
			return "Draw", true -- simultaneous final eliminations resolve together
		elseif red == 0 then
			return "Blue", true
		elseif blue == 0 then
			return "Red", true
		end
		if t >= nextPower then
			nextPower = t + Config.PowerUps.DispenserInterval
			spawnPowerUps()
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
	local moduleScript = folder and (folder:FindFirstChild(moduleName) or folder:FindFirstChild(Config.Finisher.DefaultId))
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
	-- stage the victim: back above the spot they fell from, then launched again for the camera
	local stage = def.Stage or {}
	local from = victim.lastCourtPos
	if victim.character and S.PlayerStateService.isAlive(victim) and from then
		local outward = Vector3.new(from.X - Config.Arena.Origin.X, 0, from.Z - Config.Arena.Origin.Z)
		outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.zAxis
		S.CharacterService.teleport(victim, from + Vector3.new(0, 3, 0), from + Vector3.new(0, 3, 0) - outward)
		local delay = tonumber(stage.LaunchDelay) or 0.8
		local launch = outward * (tonumber(stage.Out) or 45) + Vector3.new(0, tonumber(stage.Up) or 60, 0)
		-- Stage.Launch = false: the finisher moves the victim itself (client-side puppet)
		if stage.Launch ~= false then
			task.delay(delay, function()
				if victim.character then
					S.RagdollService.ragdoll(victim.character, launch)
				end
			end)
		end
	end
	local payload = {
		module = moduleScript.Name,
		killer = killer.character,
		victim = victim.character,
		killerName = killer.name,
		victimName = victim.name,
		winner = winner,
		duration = duration,
	}
	for _, c in roster do
		if c.player then
			S.NetService.send(c.player, "Finisher", payload)
		end
	end
	S.AnalyticsService.event(killer, "FinisherPlayed_" .. moduleScript.Name)
	waitPhase(duration, nil)
	staging = false
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
	local roundNumber = 0
	local draws = 0
	local aborted = false
	local finalEliminator: any? = nil
	local matchStart = now()
	for _, c in roster do
		c.stats = S.PlayerStateService.newStats()
		c.matchStartedAt = matchStart
		c.matchEliminations = 0
		c.aliveAtWin = false
		c.lateJoin = false
		S.AnalyticsService.matchStarted(c)
	end
	while wins.Red < M.RoundsToWin and wins.Blue < M.RoundsToWin do
		roundNumber += 1
		MatchService.setAttr("Round", roundNumber)
		resetRound()
		setState("RoundCountdown", M.RoundCountdown)
		freeze(true)
		S.BotService.setPaused(false)
		-- server-driven 3-2-1 so every client shows each tick, then GO! when the round goes live
		local ok = true
		for n = M.RoundCountdown, 1, -1 do
			for _, c in roster do
				if c.player then
					S.NetService.send(c.player, "Countdown", { n = n })
				end
			end
			if not waitPhase(1, shouldAbort) then
				ok = false
				break
			end
		end
		freeze(false)
		if not ok then
			aborted = true
			break
		end
		for _, c in roster do
			S.AnalyticsService.funnel(c, "EnteredFirstRound")
		end
		local result, byElimination = playRound()
		publishCounts()
		if result == "Abort" then
			aborted = true
			break
		end
		local decidesMatch = (result == "Red" or result == "Blue") and wins[result] + 1 >= M.RoundsToWin
		if decidesMatch then
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
		for _, c in roster do
			S.AnalyticsService.funnel(c, "CompletedFirstRound")
		end
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
		if wins.Red >= M.RoundsToWin then
			winner = "Red"
		elseif wins.Blue >= M.RoundsToWin then
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
	S.AnalyticsService.matchEnded(roster, { aborted = aborted, bots = bots, duration = now() - matchStart })
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

function MatchService.run()
	while true do
		local queued = MatchService.queuedPlayers()
		if #queued == 0 then
			setState("WaitingForPlayers")
			repeat
				task.wait(0.25)
				queued = MatchService.queuedPlayers()
			until #queued > 0
		end
		setState("Intermission", M.Intermission)
		local endsAt = now() + M.Intermission
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
			runMatch(MatchService.queuedPlayers())
		end
	end
end

-- Population changes -------------------------------------------------------------------------------

function MatchService.onLeave(c: any)
	local idx = table.find(roster, c)
	if idx then
		table.remove(roster, idx)
	end
	if c.heldBall then
		S.BallService.drop(c)
	end
	publishCounts()
end

function MatchService.onCharacterLost(c: any)
	-- a player's character vanished (e.g. destroyed by the engine); treat it as a fall if active
	if c.inMatch and c.status == "Active" then
		eliminate(c)
	end
end

return MatchService
