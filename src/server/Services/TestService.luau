--!strict
-- Studio-only scenario tests for spec §16 / Amendment A edge cases. They drive the real services
-- with bots during a live round, so they need a bot-filled match (one Studio player is enough).
--
-- Run: press F9 in a Studio play session, or from the server command bar:
--   workspace:SetAttribute("RD_RunTests", true)
-- Results print to Output and land in workspace attribute "RD_TestResults".
-- The last test deliberately ends the round (simultaneous final eliminations).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local ProjectileMath = require(Shared.ProjectileMath)
local Catalog = require(Shared.Catalog)

local TestService = {}

local S: any
local running = false
local O = Config.Arena.Origin

local function now(): number
	return Workspace:GetServerTimeNow()
end

function TestService.init(services: any)
	S = services
end

function TestService.start()
	if not RunService:IsStudio() then
		return
	end
	Workspace:GetAttributeChangedSignal("RD_KnockbackProbe"):Connect(function()
		if Workspace:GetAttribute("RD_KnockbackProbe") == true then
			Workspace:SetAttribute("RD_KnockbackProbe", false)
			task.spawn(TestService.knockbackProbe)
		end
	end)
	Workspace:GetAttributeChangedSignal("RD_RunTests"):Connect(function()
		if Workspace:GetAttribute("RD_RunTests") == true then
			Workspace:SetAttribute("RD_RunTests", false)
			task.spawn(TestService.runAll)
		end
	end)
end

-- Helpers ------------------------------------------------------------------------------------------

local function assertTrue(cond: any, msg: string)
	if not cond then
		error(msg, 0)
	end
end

local function waitUntil(fn: () -> boolean, timeout: number): boolean
	local t = os.clock()
	while os.clock() - t < timeout do
		if fn() then
			return true
		end
		task.wait()
	end
	return fn()
end

local function bots(team: string): { any }
	local list = {}
	for _, c in S.MatchService.roster() do
		if c.isBot and c.team == team and S.PlayerStateService.isAlive(c) then
			table.insert(list, c)
		end
	end
	return list
end

-- Put a bot back into a clean, active, idle state at a point on its half.
local function ready(c: any, pos: Vector3)
	if c.heldBall then
		S.BallService.drop(c)
	end
	if c.character and S.RagdollService.isRagdolled(c.character) then
		S.RagdollService.recover(c.character, pos)
	end
	S.PlayerStateService.setStatus(c, "Active")
	S.PlayerStateService.setAction(c, "Idle")
	c.immuneUntil = 0
	c.catchUntil = 0
	c.chargeStart = nil
	c.dodgeReadyAt = 0
	c.catchReadyAt = 0
	c.jailReturns = 0
	S.CharacterService.teleport(c, pos, Vector3.new(pos.X, pos.Y, O.Z))
	if c.humanoid then
		c.humanoid:MoveTo(pos)
	end
end

local function giveBall(c: any): any
	local ball = S.BallService.spawn("Standard", c.root.Position + Vector3.new(0, 3, 0), "Match")
	S.BallService.give(ball, c)
	return ball
end

-- Aim straight at a target's root with the same gravity compensation bots use.
local function aimAt(thrower: any, target: any, charge: number): Vector3
	local tp = target.root.Position
	local flat = Vector3.new(tp.X - thrower.root.Position.X, 0, tp.Z - thrower.root.Position.Z)
	local origin = thrower.root.Position + Vector3.new(0, Config.Ball.SpawnUp, 0) + flat.Unit * Config.Ball.SpawnForward
	local speed = ProjectileMath.throwSpeed(charge, "Standard")
	local g = ProjectileMath.gravity("Standard")
	local dir = (tp - origin).Unit
	for _ = 1, 3 do
		local t = (tp - origin).Magnitude / speed
		dir = (tp + Vector3.new(0, 0.5 * g * t * t, 0) - origin).Unit
	end
	return dir
end

local function point(team: string, x: number, depth: number): Vector3
	return O + Vector3.new(x, 3, ArenaLayout.teamSign(team) * depth)
end

-- Tests --------------------------------------------------------------------------------------------

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

test("two players, one ball: assigned exactly once", function()
	local red = bots("Red")
	assertTrue(#red >= 2, "need 2 red bots")
	local a, b = red[1], red[2]
	local p = point("Red", -20, 22)
	ready(a, p + Vector3.new(-1.5, 0, 0))
	ready(b, p + Vector3.new(1.5, 0, 0))
	task.wait(0.2)
	local ball = S.BallService.spawn("Standard", p + Vector3.new(0, -1, 0), "Match")
	S.BallService.pickupTick()
	local holders = 0
	for _, c in S.MatchService.roster() do
		if c.heldBall == ball then
			holders += 1
		end
	end
	assertTrue(holders == 1, ("ball held by %d combatants"):format(holders))
	assertTrue(ball.holder and ball.holder.heldBall == ball, "holder link inconsistent")
	assertTrue(ball.state == "Held", "ball state " .. ball.state)
end)

test("hit while charging cancels the throw and drops the ball", function()
	local target = bots("Red")[1]
	local thrower = bots("Blue")[1]
	assertTrue(target and thrower, "need a bot per team")
	ready(target, point("Red", 0, 12))
	ready(thrower, point("Blue", 0, 12))
	task.wait(0.3)
	local held = giveBall(target)
	S.CombatService.doChargeStart(target)
	assertTrue(target.action == "Charging", "target not charging")
	giveBall(thrower)
	S.CombatService.doThrow(thrower, aimAt(thrower, target, 0), 0)
	assertTrue(waitUntil(function()
		return target.action == "Ragdolled"
	end, 1.5), "throw did not hit")
	assertTrue(target.heldBall == nil, "target still holds a ball")
	assertTrue(held.holder == nil and held.state ~= "Held", "dropped ball still held")
	assertTrue(target.chargeStart == nil, "charge not cleared")
end)

-- Remove loose balls near a spot so pickups can't interfere with a scenario.
local function clearBallsNear(pos: Vector3, radius: number)
	for _, b in S.BallService.all() do
		if b.context == "Match" and not b.holder and (b.part.Position - pos).Magnitude < radius then
			S.BallService.destroy(b)
		end
	end
end

test("catch window catches an incoming throw (catch before hit)", function()
	local catcher = bots("Red")[1]
	local thrower = bots("Blue")[1]
	ready(catcher, point("Red", 10, 12))
	ready(thrower, point("Blue", 10, 12))
	task.wait(0.3)
	clearBallsNear(catcher.root.Position, 14)
	if catcher.heldBall then
		S.BallService.drop(catcher)
		clearBallsNear(catcher.root.Position, 14)
	end
	giveBall(thrower)
	local before = catcher.stats.catches + catcher.stats.botCatches
	S.CombatService.doThrow(thrower, aimAt(thrower, catcher, 0), 0)
	-- open the catch just before arrival
	S.PlayerStateService.setAction(catcher, "Catching")
	catcher.catchUntil = now() + 1.0
	assertTrue(waitUntil(function()
		return catcher.heldBall ~= nil or catcher.action == "Ragdolled"
	end, 1.5), "nothing happened")
	assertTrue(catcher.heldBall ~= nil, "was hit instead of catching")
	assertTrue(catcher.stats.catches + catcher.stats.botCatches == before + 1, "catch not counted")
end)

test("catch and a second hit in the same step keep ball ownership consistent", function()
	local catcher = bots("Red")[1]
	local blue = bots("Blue")
	assertTrue(#blue >= 2, "need 2 blue bots")
	ready(catcher, point("Red", -6, 12))
	ready(blue[1], point("Blue", -9, 12))
	ready(blue[2], point("Blue", -3, 12))
	task.wait(0.3)
	giveBall(blue[1])
	giveBall(blue[2])
	S.PlayerStateService.setAction(catcher, "Catching")
	catcher.catchUntil = now() + 1.0
	S.CombatService.doThrow(blue[1], aimAt(blue[1], catcher, 0), 0)
	S.CombatService.doThrow(blue[2], aimAt(blue[2], catcher, 0), 0)
	task.wait(1.2)
	local holdersByBall: { [any]: number } = {}
	for _, c in S.MatchService.roster() do
		if c.heldBall then
			holdersByBall[c.heldBall] = (holdersByBall[c.heldBall] or 0) + 1
			assertTrue(c.heldBall.holder == c, "held ball points at another holder")
		end
	end
	for _, n in holdersByBall do
		assertTrue(n == 1, "a ball has two holders")
	end
	for _, b in S.BallService.all() do
		assertTrue(b.state ~= "InFlight" or b.flightT < Config.Ball.MaxFlightTime, "ball stuck in flight")
	end
end)

test("leaving while holding a ball releases it", function()
	local roster = S.MatchService.roster()
	local bot = bots("Red")[1]
	local ball = giveBall(bot)
	S.BotService.remove(roster, bot)
	assertTrue(ball.holder == nil, "ball still has a holder")
	assertTrue(ball.part.Parent ~= nil, "ball was destroyed")
	assertTrue(table.find(roster, bot) == nil, "bot still in roster")
	S.BotService.create("Red", roster)
	task.wait(0.2)
end)

test("server pushes characters back across the center line", function()
	local bot = bots("Red")[1]
	ready(bot, point("Red", 0, 10))
	task.wait(0.2)
	bot.character:PivotTo(CFrame.new(O + Vector3.new(0, 3, 6)))
	task.wait(0.3)
	local z = bot.root.Position.Z - O.Z
	assertTrue(z < 0, ("red bot still on blue half (z=%.1f)"):format(z))
end)

test("possession timeout forces a drop at 12 s", function()
	local bot = bots("Blue")[1]
	ready(bot, point("Blue", 0, 20))
	local ball = giveBall(bot)
	bot.heldSince = now() - (Config.Player.PossessionForceDrop + 0.1)
	assertTrue(waitUntil(function()
		return ball.holder ~= bot
	end, 0.6), "ball not dropped")
	assertTrue(ball.holder == nil, "ball still has holder")
	-- and no instant re-grab: the player can't pick anything up for a moment
	task.wait(0.8)
	assertTrue(bot.heldBall == nil, "re-grabbed a ball right after the forced drop")
end)

test("ball conservation repairs missing balls without duplicates", function()
	local removed = 0
	for _, b in S.BallService.all() do
		if b.context == "Match" and b.state == "Resting" and not b.isPower and removed < 2 then
			S.BallService.destroy(b)
			removed += 1
		end
	end
	S.BallService.conservationTick()
	local standard, ids = 0, {}
	for _, b in S.BallService.all() do
		assertTrue(not ids[b.id], "duplicate ball id")
		ids[b.id] = true
		if b.context == "Match" and not b.isPower then
			standard += 1
		end
	end
	assertTrue(standard >= Config.Ball.BallsPerCourt, ("only %d standard balls"):format(standard))
	assertTrue(standard <= Config.Ball.BallsPerCourt + 2 * Config.PowerUps.MaxPowerBallsPerSide, "too many balls")
end)

test("void fall -> jail; jail hit -> return; revenge on own eliminator; cap -> spectate", function()
	local red = bots("Red")
	local blue = bots("Blue")
	assertTrue(#red >= 2 and #blue >= 1, "need bots")
	local jailee, capped, enemy = red[1], red[2], blue[1]
	ready(jailee, point("Red", -10, 20))
	ready(capped, point("Red", 10, 20))
	ready(enemy, point("Blue", 0, 30))
	task.wait(0.3)
	-- enemy gets knockout credit on jailee
	jailee.lastHitBy = enemy
	jailee.lastHitAt = now()
	capped.jailReturns = Config.Jail.MaxReturnsPerRound
	jailee.character:PivotTo(CFrame.new(O + Vector3.new(-40, -40, -20)))
	capped.character:PivotTo(CFrame.new(O + Vector3.new(40, -40, -20)))
	assertTrue(waitUntil(function()
		return jailee.status == "Jailed" and capped.status == "Spectating"
	end, 1), ("statuses %s / %s"):format(jailee.status, capped.status))
	assertTrue(jailee.eliminatedBy == enemy, "knockout credit missing")
	assertTrue(waitUntil(function()
		return ArenaLayout.inJail("Red", jailee.root.Position)
	end, Config.Jail.RespawnDelay + 1), "jailee not moved to jail")
	S.RagdollService.recover(jailee.character, jailee.root.Position)
	S.PlayerStateService.setAction(jailee, "Idle")
	enemy.immuneUntil = 0
	task.wait(0.3)
	local revengesBefore = jailee.stats.revenges
	giveBall(jailee)
	S.CombatService.doThrow(jailee, aimAt(jailee, enemy, 0.5), 0)
	assertTrue(waitUntil(function()
		return jailee.status == "Returning" or jailee.status == "Active"
	end, 1.5), "jail hit did not register (status " .. jailee.status .. ")")
	assertTrue(jailee.stats.revenges == revengesBefore + 1, "revenge not counted")
	assertTrue(waitUntil(function()
		return jailee.status == "Active"
	end, Config.Jail.ReturnDelay + 0.8), "did not return to court")
	assertTrue(ArenaLayout.onHalf("Red", jailee.root.Position, 0, -2), "returned to wrong place")
	assertTrue(jailee.immuneUntil > now(), "no return immunity")
end)

test("jail wall: a prisoner cannot walk from the jail onto the court", function()
	local bot = bots("Red")[1]
	ready(bot, point("Red", 0, 20))
	task.wait(0.2)
	S.PlayerStateService.setStatus(bot, "Jailed")
	S.CharacterService.teleport(bot, ArenaLayout.jailCenter("Red") + Vector3.new(0, 3, 0))
	task.wait(0.3)
	-- the red jail is behind the BLUE back line; try to walk onto the blue court
	bot.humanoid:MoveTo(O + Vector3.new(0, 3, 30))
	task.wait(2.5)
	assertTrue(ArenaLayout.inJail("Red", bot.root.Position), ("prisoner left the jail (z=%.1f)"):format(bot.root.Position.Z - O.Z))
	S.PlayerStateService.setStatus(bot, "Active")
	ready(bot, point("Red", 0, 20))
end)

test("one-way edge: a flung body past the edge can't come back onto the court", function()
	local bot = bots("Blue")[1]
	ready(bot, point("Blue", 0, 44))
	task.wait(0.3)
	bot.immuneUntil = 0
	S.PlayerStateService.setAction(bot, "Ragdolled")
	S.RagdollService.ragdoll(bot.character, Vector3.new(0, 28, 45)) -- out past the blue back line
	assertTrue(waitUntil(function()
		return bot.ejected == true or bot.status ~= "Active"
	end, 1.5), "never marked ejected")
	-- shove it straight back at the court
	for _, p in bot.character:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			p.AssemblyLinearVelocity = Vector3.new(0, 25, -70)
		end
	end
	task.wait(1.2)
	local z = bot.root.Position.Z - O.Z
	local backOnCourt = bot.status == "Active" and z < ArenaLayout.HalfLength and bot.root.Position.Y > ArenaLayout.SurfaceY - 2
	assertTrue(not backOnCourt, ("body bounced back onto the court (z=%.1f)"):format(z))
	-- tidy up whatever state it ended in
	S.PlayerStateService.setStatus(bot, "Active")
	ready(bot, point("Blue", 0, 20))
end)

test("rolling (not yet settled) balls can be picked up", function()
	local bot = bots("Red")[1]
	ready(bot, point("Red", -12, 18))
	task.wait(0.3)
	local ball = S.BallService.spawn("Standard", bot.root.Position + Vector3.new(2, -1.5, 0), "Match")
	ball.state = "Spent" -- still rolling after a throw
	ball.part.AssemblyLinearVelocity = Vector3.new(9, 0, 0)
	ball.lockoutUntil = 0
	S.BallService.pickupTick()
	assertTrue(ball.holder == bot, "rolling ball was not picked up")
end)

test("an elimination pays the eliminator 25 coins instantly", function()
	local me
	for _, c in S.MatchService.roster() do
		if c.player and c.profile then
			me = c
		end
	end
	assertTrue(me ~= nil, "no real player in the match")
	local enemyTeam = if me.team == "Red" then "Blue" else "Red"
	local victim = bots(enemyTeam)[1]
	assertTrue(victim ~= nil, "no enemy bot")
	ready(victim, point(enemyTeam, 0, 20))
	task.wait(0.2)
	local before = me.profile.Coins
	victim.lastHitBy = me
	victim.lastHitAt = now()
	victim.character:PivotTo(CFrame.new(victim.root.Position - Vector3.new(0, 60, 0)))
	assertTrue(waitUntil(function()
		return victim.status ~= "Active"
	end, 1), "victim not eliminated")
	assertTrue(me.profile.Coins == before + Config.Coins.Elimination, ("coins %d -> %d"):format(before, me.profile.Coins))
	S.PlayerStateService.setStatus(victim, "Active")
	ready(victim, point(enemyTeam, 0, 20))
end)

test("victory poses: a free default, 3+ to unlock, every pose and frame defined", function()
	local VictoryPoses = require(Shared.VictoryPoses)
	local items = Catalog.inCategory("Pose")
	local defaults, paid = 0, 0
	for _, item in items do
		if item.Default then
			defaults += 1
			assertTrue(item.Price == 0, "default pose isn't free")
		else
			paid += 1
		end
		local pose = VictoryPoses.Poses[item.Data.Pose]
		assertTrue(pose ~= nil, item.Id .. " names an unknown pose")
		for _, step in pose.Frames do
			assertTrue(VictoryPoses.Frames[step.frame] ~= nil, item.Id .. " uses an unknown frame " .. step.frame)
			assertTrue(step.hold > 0, item.Id .. " has a zero-length frame")
		end
	end
	assertTrue(defaults == 1 and paid >= 3, ("%d default and %d paid poses"):format(defaults, paid))
	-- equipping is server-checked like any cosmetic: owned or default only
	local c: any = { profileLoaded = true, inMatch = false, status = "Lobby", profile = { Coins = 0, OwnedCosmetics = {}, Equipped = {}, Level = 1, CurrentWinStreak = 0 } }
	assertTrue(S.ShopService.victoryPose(c) == VictoryPoses.Default, "default pose not used")
	assertTrue(not S.ShopService.equip(c, "Pose_Dab"), "equipped an unowned pose")
	c.profile.OwnedCosmetics.Pose_Dab = true
	assertTrue(S.ShopService.equip(c, "Pose_Dab") and S.ShopService.victoryPose(c) == "Dab", "owned pose not equipped")
end)

test("bots: difficulty mix uses real profiles; new players mostly get Easy bots", function()
	local profiles = Config.Bots.Profiles :: { [string]: any }
	for _, row in (Config.Bots.Mix :: any) :: { { Weights: { [string]: number } } } do
		for name in row.Weights do
			assertTrue(profiles[name] ~= nil, "mix names unknown profile " .. name)
		end
	end
	local easy = 0
	for _ = 1, 200 do
		if S.BotService.pickDifficulty(1) == "Easy" then
			easy += 1
		end
	end
	assertTrue(easy > 120, ("only %d/200 Easy bots for level-1 players"):format(easy))
	for name, prof in profiles do
		-- beatable: every profile misses a little and reacts slower than a frame
		assertTrue(prof.AimErrorDeg >= 2 and prof.ReactionTime[1] >= 0.1, name .. " profile is superhuman")
	end
end)

test("bots: a smart bot targets the enemy at the edge over a closer one in the middle", function()
	local bot = bots("Red")[1]
	local blue = bots("Blue")
	assertTrue(bot and #blue >= 2, "need a red bot and 2 blue bots")
	for _, c in S.MatchService.roster() do
		if c.team == "Blue" and c ~= blue[1] and c ~= blue[2] then
			S.PlayerStateService.setStatus(c, "Spectating")
		end
	end
	ready(bot, point("Red", 0, 12))
	ready(blue[1], point("Blue", 0, 14)) -- closest, safe in the middle
	ready(blue[2], point("Blue", 28, 20)) -- farther, 4 studs from the side edge
	task.wait(0.3)
	local smart = S.BotService.pickTarget(bot, true, false)
	local naive = S.BotService.pickTarget(bot, false, false)
	for _, c in S.MatchService.roster() do
		if c.team == "Blue" then
			S.PlayerStateService.setStatus(c, "Active")
		end
	end
	ready(blue[2], point("Blue", 0, 20))
	assertTrue(naive == blue[1], "naive pick isn't the nearest enemy")
	assertTrue(smart == blue[2], "smart pick ignored the enemy at the edge")
end)

test("bots: a bot holding a ball always throws (never stalls the round)", function()
	local bot = bots("Blue")[1]
	local enemy = bots("Red")[1]
	ready(bot, point("Blue", 0, 20))
	ready(enemy, point("Red", 0, 20))
	task.wait(0.3)
	local throws = bot.stats.throws
	giveBall(bot)
	bot.bot.plan = nil
	local deadline = os.clock() + Config.Bots.StallThrow + 1
	while os.clock() < deadline and bot.heldBall do
		S.BotService.tickOne(bot)
		task.wait(Config.Bots.TickInterval)
	end
	assertTrue(bot.heldBall == nil and bot.stats.throws == throws + 1, "bot kept the ball")
	task.wait(1) -- let the throw land
	ready(enemy, point("Red", 0, 20))
end)

test("bots: dodges go toward the middle, never off the edge", function()
	local bot = bots("Red")[1]
	ready(bot, point("Red", 26, 24)) -- 6 from the right edge
	task.wait(0.3)
	local inside = S.BotService.safeFor(bot, bot.root.Position + Vector3.new(-8, 0, 0))
	local outside = S.BotService.safeFor(bot, bot.root.Position + Vector3.new(8, 0, 0))
	assertTrue(inside and not outside, "edge safety check is wrong")
	assertTrue(S.BotService.edgeDistance("Red", bot.root.Position) < 7, "edge distance is wrong")
end)

test("hub: every station has a prompt; spawn, dummy and practice ball are on the deck", function()
	local lobby = Workspace:FindFirstChild("Lobby")
	assertTrue(lobby ~= nil, "no Workspace.Lobby")
	local stations = (lobby :: Instance):FindFirstChild("Stations") :: Instance
	for _, def in Config.Lobby.Stations do
		local model = stations:FindFirstChild(def.Id .. "Station")
		assertTrue(model ~= nil, "missing station " .. def.Id)
		local prompt = (model :: Instance):FindFirstChild(def.Id .. "Prompt", true)
		assertTrue(prompt and prompt:IsA("ProximityPrompt"), "station " .. def.Id .. " has no prompt")
		local anchor = (prompt :: Instance).Parent :: BasePart
		assertTrue(ArenaLayout.inLobby(anchor.Position), "station " .. def.Id .. " is off the deck")
	end
	local board = stations:FindFirstChild("Leaderboard")
	assertTrue(board and board:FindFirstChild("Board"), "no leaderboard")
	local rng = Random.new(1)
	for _ = 1, 20 do
		assertTrue(ArenaLayout.inLobby(ArenaLayout.lobbySpawn(rng), -2), "lobby spawn off the deck")
	end
	assertTrue(ArenaLayout.inLobby(ArenaLayout.PracticeBallHome, -1), "practice ball off the deck")
	assertTrue(ArenaLayout.inLobby(ArenaLayout.DummyHome, 0), "dummy off the deck")
end)

test("spawning into the hub faces the court", function()
	local bot = bots("Red")[1]
	local spot = ArenaLayout.lobbySpawn(Random.new(3))
	S.CharacterService.placeFacing(bot, spot, ArenaLayout.CourtFocus)
	local look = bot.root.CFrame.LookVector
	local want = Vector3.new(ArenaLayout.CourtFocus.X - spot.X, 0, ArenaLayout.CourtFocus.Z - spot.Z).Unit
	local dot = look:Dot(want)
	ready(bot, point("Red", 0, 20))
	assertTrue(dot > 0.98, ("hub spawn faces %.0f° away from the court"):format(math.deg(math.acos(math.clamp(dot, -1, 1)))))
end)

test("hub sits level with the court, beside it, across the void gap", function()
	local A = Config.Arena
	assertTrue(math.abs(A.LobbyOrigin.Y - A.Origin.Y) < 1, "hub is not level with the court")
	-- no deck corner may come within LobbyGap of the court or either jail strip
	local hx, hz = A.LobbySize.X / 2, A.LobbySize.Z / 2
	local courtHalfZ = ArenaLayout.HalfLength + Config.Jail.Gap + Config.Jail.StripDepth
	for _, c in { { -hx, -hz }, { hx, -hz }, { -hx, hz }, { hx, hz } } do
		local p = ArenaLayout.LobbyFrame * Vector3.new(c[1], 0, c[2])
		local rel = p - A.Origin
		local dx = math.max(0, math.abs(rel.X) - ArenaLayout.HalfWidth)
		local dz = math.max(0, math.abs(rel.Z) - courtHalfZ)
		assertTrue(math.max(dx, dz) >= A.LobbyGap - 0.5, ("deck corner only %.1f from the court"):format(math.max(dx, dz)))
	end
	-- and it's next to the court: the court-side edge faces the middle of the court within the gap
	local front = ArenaLayout.lobbyPoint(0, 0, hz)
	local toCourt = (Vector3.new(A.Origin.X, front.Y, A.Origin.Z) - front).Magnitude
	assertTrue(toCourt <= ArenaLayout.HalfWidth + A.LobbyGap + 1, ("hub is %.0f studs from the court centre"):format(toCourt))
	-- a match ball over the hub is out; the ball net only stops practice balls
	assertTrue(ArenaLayout.inLobby(ArenaLayout.CourtFocus) == false, "court centre counts as hub")
end)

test("no constraint, ball or bot build-up", function()
	local rigs, sockets = 0, 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Humanoid") then
			rigs += 1
		elseif d:IsA("BallSocketConstraint") then
			sockets += 1
		end
	end
	assertTrue(sockets <= rigs * 14, ("%d sockets for %d rigs"):format(sockets, rigs))
	local bots = #(Workspace:FindFirstChild("Bots") :: Folder):GetChildren()
	assertTrue(bots <= Config.Bots.MaxPerServer + 1, ("%d bot models"):format(bots))
	local balls = #(Workspace:FindFirstChild("Balls") :: Folder):GetChildren()
	assertTrue(balls <= Config.Ball.BallsPerCourt + 2 * Config.PowerUps.MaxPowerBallsPerSide + 6, ("%d balls"):format(balls))
end)

test("simultaneous final eliminations -> draw (ends the round)", function()
	local red, blue = bots("Red"), bots("Blue")
	local lastRed, lastBlue = red[1], blue[1]
	assertTrue(lastRed and lastBlue, "need a bot per team")
	for _, c in S.MatchService.roster() do
		if c ~= lastRed and c ~= lastBlue then
			S.PlayerStateService.setStatus(c, "Spectating")
		end
	end
	ready(lastRed, point("Red", 0, 20))
	ready(lastBlue, point("Blue", 0, 20))
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	local redWins, blueWins = ms:GetAttribute("RedWins"), ms:GetAttribute("BlueWins")
	task.wait(0.2)
	lastRed.character:PivotTo(CFrame.new(O + Vector3.new(0, -60, -20)))
	lastBlue.character:PivotTo(CFrame.new(O + Vector3.new(0, -60, 20)))
	assertTrue(waitUntil(function()
		return ms:GetAttribute("State") == "RoundResolution"
	end, 2), "round did not end")
	assertTrue(ms:GetAttribute("RedWins") == redWins and ms:GetAttribute("BlueWins") == blueWins, "a team was awarded the round")
end)

test("coins: highest win tier only; 50 for playing on the losing team", function()
	local function fake(team: string, elims: number, alive: boolean, throws: number): any
		local st = S.PlayerStateService.newStats()
		st.throws = throws
		return { team = team, stats = st, matchEliminations = elims, aliveAtWin = alive, lateJoin = false }
	end
	local killer = fake("Red", 0, true, 3)
	local flawless = fake("Red", 0, true, 3)
	local survivor = fake("Red", 1, true, 3)
	local jailedWinner = fake("Red", 2, false, 3)
	local loser = fake("Blue", 1, false, 2)
	local idleLoser = fake("Blue", 1, false, 0)
	local ctx = { matchId = 1, winner = "Red", aborted = false, casual = true, duration = 60, finalEliminator = killer }
	local P = Config.Coins
	local function check(c: any, want: number, label: string)
		local got = S.RewardService.coins(c, ctx)
		assertTrue(got == want, ("%s: got %d, want %d"):format(label, got, want))
	end
	check(killer, P.WinLastElimination, "last elimination")
	check(flawless, P.WinFlawless, "flawless")
	check(survivor, P.WinAlive, "alive at win")
	check(jailedWinner, P.Win, "won from jail")
	check(loser, P.LossParticipation, "loser who played")
	check(idleLoser, 0, "idle loser")
	check(fake("Red", 0, true, 0), 0, "idle winner")
	local late = fake("Red", 0, true, 3)
	late.lateJoin = true
	check(late, P.WinAlive, "late joiner can't be flawless")
	local abortCtx = table.clone(ctx)
	abortCtx.aborted = true
	assertTrue(S.RewardService.coins(killer, abortCtx) == 0, "aborted match paid coins")
end)

test("daily reward: pays once per UTC day, ladder advances, missed day resets", function()
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
	local c: any = {
		profileLoaded = true,
		profile = { Coins = 0, LoginStreak = { day = 3, lastDate = yesterday, claimedDate = yesterday } },
	}
	local ladder = Config.DailyRewards.Ladder
	assertTrue(S.ShopService.claimDaily(c), "first claim refused")
	assertTrue(c.profile.LoginStreak.day == 4 and c.profile.Coins == ladder[4], "did not advance to day 4")
	assertTrue(not S.ShopService.claimDaily(c), "second claim the same day paid")
	assertTrue(c.profile.Coins == ladder[4], "coins changed on a refused claim")
	c.profile.LoginStreak = { day = 5, lastDate = "2000-01-01", claimedDate = "2000-01-01" }
	S.ShopService.claimDaily(c)
	assertTrue(c.profile.LoginStreak.day == 1, "missed day did not reset the ladder")
	c.profile.LoginStreak = { day = 7, lastDate = yesterday, claimedDate = yesterday }
	S.ShopService.claimDaily(c)
	assertTrue(c.profile.LoginStreak.day == 1, "day 7 did not wrap to day 1")
end)

test("daily spin: one free spin a day, paid spins cost coins and are capped, duplicates pay coins", function()
	local SP = Config.Spin
	local c: any = {
		id = 900001,
		profileLoaded = true,
		inMatch = false,
		status = "Lobby",
		profile = { Coins = 0, OwnedCosmetics = {}, Equipped = {}, Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} } },
	}
	local preview = S.SpinService.wheel(c)
	assertTrue(#preview == SP.Slots, "wheel has the wrong number of slots")
	local r1 = S.SpinService.spin(c, "Free")
	assertTrue(r1 and r1.ok, "free spin refused")
	assertTrue(r1.slots[r1.index] == r1.id and r1.id == preview[r1.index], "prize isn't the wheel slot the client was shown")
	assertTrue(c.profile.OwnedCosmetics[r1.id] == true, "prize not granted")
	assertTrue(S.SpinService.spin(c, "Free") == nil, "second free spin the same day")
	assertTrue(S.SpinService.spin(c, "Coins") == nil, "paid spin with no coins")
	c.profile.Coins = SP.ExtraSpinCost * (SP.MaxPaidPerDay + 1)
	local before = c.profile.Coins
	assertTrue(S.SpinService.spin(c, "Coins") ~= nil, "paid spin refused")
	assertTrue(c.profile.Coins <= before - SP.ExtraSpinCost + SP.DuplicateCoins.Legendary, "paid spin didn't cost coins")
	for _ = 2, SP.MaxPaidPerDay do
		S.SpinService.spin(c, "Coins")
	end
	assertTrue(S.SpinService.spin(c, "Coins") == nil, "paid spins aren't capped")
	-- own everything: a spin pays duplicate coins and grants nothing new
	c.profile.Spin.date = "2000-01-01" -- a new UTC day: the free spin is back
	for _, item in Catalog.Items do
		c.profile.OwnedCosmetics[item.Id] = true
	end
	local coins = c.profile.Coins
	local r2 = S.SpinService.spin(c, "Free")
	assertTrue(r2 and r2.duplicate and r2.coins == SP.DuplicateCoins[r2.rarity], "duplicate didn't pay coins")
	assertTrue(c.profile.Coins == coins + r2.coins, "duplicate coins not added")
	-- only the hub
	c.status, c.inMatch = "Active", true
	c.profile.Spin.date = "2000-01-01"
	assertTrue(S.SpinService.spin(c, "Free") == nil, "spun during a match")
end)

test("daily spin: wheels follow the rarity weights", function()
	local counts: { [string]: number } = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
	local total = 0
	for i = 1, 400 do
		local c: any = { id = 800000 + i, profile = { Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} } } }
		for _, id in S.SpinService.wheel(c) do
			counts[Catalog.rarity(Catalog.get(id) :: any)] += 1
			total += 1
		end
	end
	local W = Config.Spin.RarityWeights
	local sum = W.Common + W.Rare + W.Epic + W.Legendary
	for r, n in counts do
		local want = W[r] / sum
		local got = n / total
		assertTrue(math.abs(got - want) < 0.04, ("%s is %.1f%% of slots, expected %.1f%%"):format(r, got * 100, want * 100))
	end
end)

test("save schema v5 migration keeps v4 data and adds the daily spin", function()
	local migrated = S.DataService.migrate({
		SchemaVersion = 4,
		Coins = 1234,
		OwnedCosmetics = { Skin_Lime = true },
		Equipped = { BallSkin = "Skin_Lime" },
		Level = 7,
	})
	assertTrue(migrated.SchemaVersion == Config.Data.SchemaVersion and Config.Data.SchemaVersion >= 5, "schema not bumped")
	assertTrue(migrated.Coins == 1234 and migrated.Level == 7, "v4 data lost")
	assertTrue(migrated.OwnedCosmetics.Skin_Lime == true and migrated.Equipped.BallSkin == "Skin_Lime", "cosmetics lost")
	assertTrue(type(migrated.Spin) == "table" and migrated.Spin.freeUsed == false, "no spin state")
	local v1 = S.DataService.migrate({ SchemaVersion = 1, Coins = 5 })
	assertTrue(v1.Spin ~= nil and v1.LoginStreak ~= nil, "v1 profile not fully migrated")
end)

test("sudden death: jail closes (no returns, no new prisoners)", function()
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	S.MatchService.debugForceSuddenDeath()
	assertTrue(waitUntil(function()
		return ms:GetAttribute("Overtime") == true
	end, 1), "sudden death did not start")
	local red, blue = bots("Red"), bots("Blue")
	local faller, enemy = red[1], blue[1]
	ready(faller, point("Red", -10, 20))
	ready(enemy, point("Blue", 0, 20))
	task.wait(0.2)
	faller.character:PivotTo(CFrame.new(O + Vector3.new(-40, -40, -20)))
	assertTrue(waitUntil(function()
		return faller.status ~= "Active"
	end, 1), "faller not eliminated")
	assertTrue(faller.status == "Spectating", "eliminated in sudden death but went to " .. faller.status)
	-- an existing prisoner landing a hit stays in jail
	local prisoner = red[2] or red[1]
	S.PlayerStateService.setStatus(prisoner, "Jailed")
	S.MatchService.onJailHit(prisoner, enemy)
	task.wait(Config.Jail.ReturnDelay + 0.3)
	assertTrue(prisoner.status == "Jailed", "prisoner got out during sudden death: " .. prisoner.status)
end)

test("finisher plays on the match-ending knockout, then the match ends", function()
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	local red, blue = bots("Red"), bots("Blue")
	local killer = red[1]
	assertTrue(killer and #blue > 0, "need bots")
	S.MatchService.debugSetWins(1, 0)
	local matchId = ms:GetAttribute("MatchId")
	-- every Blue combatant (bots and any player) falls at once, credited to the Red killer
	for _, c in S.MatchService.roster() do
		if c.team == "Blue" and c.status == "Active" and c.root then
			c.lastHitBy = killer
			c.lastHitAt = now()
			c.lastCourtPos = c.root.Position
			c.character:PivotTo(CFrame.new(c.root.Position - Vector3.new(0, 60, 0)))
		end
	end
	assertTrue(waitUntil(function()
		return ms:GetAttribute("State") == "Finisher"
	end, 2), "no finisher phase")
	-- then the winners' victory poses, lined up on their half, before the match ends
	assertTrue(waitUntil(function()
		return ms:GetAttribute("State") == "Victory"
	end, 12), "no victory moment after the finisher")
	for _, c in S.MatchService.roster() do
		if c.team == "Red" and S.PlayerStateService.isAlive(c) then
			assertTrue(ArenaLayout.onHalf("Red", c.root.Position, 0, -1), c.name .. " not lined up on the winning half")
		end
	end
	assertTrue(waitUntil(function()
		return ms:GetAttribute("State") == "Intermission" or ms:GetAttribute("MatchId") ~= matchId
	end, Config.Victory.Duration + 4), "match did not end after the victory poses")
end)

-- Knockback probe (tuning): real throws at a bot standing at several spots on its half, at min and
-- full charge. Reports how many hits end in the void per spot and how far the body travelled.
-- Run: workspace:SetAttribute("RD_KnockbackProbe", true); results in "RD_KnockbackResults".
function TestService.knockbackProbe()
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	if not waitUntil(function()
		return ms:GetAttribute("State") == "RoundActive"
	end, 30) then
		Workspace:SetAttribute("RD_KnockbackResults", "SKIPPED: no live round")
		return
	end
	S.BotService.setPaused(true)
	local spots = {
		{ name = "center of half (x0, 14 from line)", x = 0, depth = 14 },
		{ name = "spawn line (x0, 30 deep)", x = 0, depth = 30 },
		{ name = "deep (x0, 38 deep = 10 from back)", x = 0, depth = 38 },
		{ name = "near side (x22 = 10 from edge)", x = 22, depth = 24 },
		{ name = "edge (x27 = 5 from edge)", x = 27, depth = 24 },
	}
	local lines = {}
	for _, spot in spots do
		for _, charge in { 0, 1 } do
			local ko, trials, travel, hits = 0, 3, 0, 0
			for _ = 1, trials do
				-- knockouts can end the round; wait for the next one instead of throwing at nothing
				waitUntil(function()
					return ms:GetAttribute("State") == "RoundActive"
				end, 15)
				if ms:GetAttribute("State") ~= "RoundActive" then
					break
				end
				S.BotService.setPaused(true) -- a new round un-pauses bots
				local target = bots("Blue")[1]
				local thrower = bots("Red")[1]
				if not (target and thrower) then
					break
				end
				local tp = point("Blue", spot.x, spot.depth)
				ready(target, tp)
				ready(thrower, point("Red", spot.x * 0.5, 4))
				target.jailReturns = 0
				task.wait(0.35)
				local start = target.root.Position
				giveBall(thrower)
				thrower.chargeStart = now() - charge * Config.Player.FullChargeTime
				S.PlayerStateService.setAction(thrower, "Charging")
				S.CombatService.doThrow(thrower, aimAt(thrower, target, charge), 0)
				local hit = waitUntil(function()
					return target.action == "Ragdolled"
				end, 1.5)
				if hit then
					hits += 1
					local maxD = 0
					local t0 = os.clock()
					while os.clock() - t0 < 4 do
						if target.root and target.root.Parent then
							local p = target.root.Position
							maxD = math.max(maxD, (Vector3.new(p.X, 0, p.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude)
						end
						if target.status ~= "Active" then
							break
						end
						task.wait()
					end
					if target.status ~= "Active" then
						ko += 1
					end
					travel += maxD
				end
				-- put the team back so the round keeps running
				S.PlayerStateService.setStatus(target, "Active")
				task.wait(0.2)
			end
			table.insert(lines, ("%-38s charge %3.0f%%: hits %d/3, void %d, avg travel %.1f studs"):format(spot.name, charge * 100, hits, ko, if hits > 0 then travel / hits else 0))
		end
	end
	S.BotService.setPaused(false)
	local out = table.concat(lines, "\n")
	print("[KnockbackProbe]\n" .. out)
	Workspace:SetAttribute("RD_KnockbackResults", out)
end

function TestService.runAll()
	if running then
		return
	end
	running = true
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	local results = {}
	if not waitUntil(function()
		return ms:GetAttribute("State") == "RoundActive"
	end, 30) then
		running = false
		Workspace:SetAttribute("RD_TestResults", "SKIPPED: no live round within 30 s")
		return
	end
	S.BotService.setPaused(true)
	local pass = 0
	for _, t in tests do
		-- round-ending tests leave a gap; wait for the next round to go live
		waitUntil(function()
			return ms:GetAttribute("State") == "RoundActive"
		end, 12)
		if ms:GetAttribute("State") ~= "RoundActive" then
			table.insert(results, "SKIP " .. t.name .. " (no live round)")
			continue
		end
		S.BotService.setPaused(true)
		local ok: boolean, err: any = pcall(t.fn :: any)
		if ok then
			pass += 1
			table.insert(results, "PASS " .. t.name)
		else
			table.insert(results, "FAIL " .. t.name .. ": " .. tostring(err))
		end
		task.wait(0.3)
	end
	S.BotService.setPaused(false)
	local summary = ("%d/%d passed\n%s"):format(pass, #tests, table.concat(results, "\n"))
	print("[Tests]\n" .. summary)
	Workspace:SetAttribute("RD_TestResults", summary)
	running = false
end

return TestService
