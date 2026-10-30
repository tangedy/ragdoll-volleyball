--!strict
-- Studio-only scenario tests for spec §16 / Amendment A edge cases. They drive the real services
-- with bots during a live round, so they need a bot-filled match (one Studio player is enough).
--
-- Run: press F9 in a Studio play session, or from the server command bar:
--   workspace:SetAttribute("RD_RunTests", true)
-- Results print to Output and land in workspace attribute "RD_TestResults".
-- Soak: workspace:SetAttribute("RD_Soak", 50) plays 50 untouched rounds and checks for build-up
-- (TestService.soak).
-- The last test deliberately ends the round (simultaneous final eliminations).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local ProjectileMath = require(Shared.ProjectileMath)
local Catalog = require(Shared.Catalog)
local BallDefinitions = require(Shared.BallDefinitions)

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
	Workspace:GetAttributeChangedSignal("RD_Soak"):Connect(function()
		local rounds = Workspace:GetAttribute("RD_Soak")
		if type(rounds) == "number" and rounds > 0 then
			Workspace:SetAttribute("RD_Soak", 0)
			task.spawn(TestService.soak, rounds)
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
	S.PlayerStateService.setDamage(c, 0)
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
	assertTrue(
		waitUntil(function()
			return target.action == "Ragdolled"
		end, 1.5),
		"throw did not hit"
	)
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
	assertTrue(
		waitUntil(function()
			return catcher.heldBall ~= nil or catcher.action == "Ragdolled"
		end, 1.5),
		"nothing happened"
	)
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
	assertTrue(
		waitUntil(function()
			return ball.holder ~= bot
		end, 0.6),
		"ball not dropped"
	)
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
	assertTrue(
		waitUntil(function()
			return jailee.status == "Jailed" and capped.status == "Spectating"
		end, 1),
		("statuses %s / %s"):format(jailee.status, capped.status)
	)
	assertTrue(jailee.eliminatedBy == enemy, "knockout credit missing")
	assertTrue(
		waitUntil(function()
			return ArenaLayout.inJail("Red", jailee.root.Position)
		end, Config.Jail.RespawnDelay + 1),
		"jailee not moved to jail"
	)
	-- out for the round: waits in jail with no way back, never in the hub
	assertTrue(
		waitUntil(function()
			return ArenaLayout.inJail("Red", capped.root.Position)
		end, 1),
		"capped player not waiting in jail"
	)
	S.RagdollService.recover(jailee.character, jailee.root.Position)
	S.PlayerStateService.setAction(jailee, "Idle")
	enemy.immuneUntil = 0
	task.wait(0.3)
	local revengesBefore = jailee.stats.revenges
	giveBall(jailee)
	S.CombatService.doThrow(jailee, aimAt(jailee, enemy, 0.5), 0)
	assertTrue(
		waitUntil(function()
			return jailee.status == "Returning" or jailee.status == "Active"
		end, 1.5),
		"jail hit did not register (status " .. jailee.status .. ")"
	)
	assertTrue(jailee.stats.revenges == revengesBefore + 1, "revenge not counted")
	assertTrue(
		waitUntil(function()
			return jailee.status == "Active"
		end, Config.Jail.ReturnDelay + 0.8),
		"did not return to court"
	)
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
	assertTrue(
		ArenaLayout.inJail("Red", bot.root.Position),
		("prisoner left the jail (z=%.1f)"):format(bot.root.Position.Z - O.Z)
	)
	S.PlayerStateService.setStatus(bot, "Active")
	ready(bot, point("Red", 0, 20))
end)

test("one-way edge: a flung body past the edge can't come back onto the court", function()
	local bot = bots("Blue")[1]
	ready(bot, point("Blue", 0, ArenaLayout.HalfLength - 4))
	task.wait(0.3)
	bot.immuneUntil = 0
	S.PlayerStateService.setAction(bot, "Ragdolled")
	S.RagdollService.ragdoll(bot.character, Vector3.new(0, 28, 45)) -- out past the blue back line
	assertTrue(
		waitUntil(function()
			return bot.ejected == true or bot.status ~= "Active"
		end, 1.5),
		"never marked ejected"
	)
	-- shove it straight back at the court
	for _, p in bot.character:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			p.AssemblyLinearVelocity = Vector3.new(0, 25, -70)
		end
	end
	task.wait(1.2)
	local z = bot.root.Position.Z - O.Z
	local backOnCourt = bot.status == "Active"
		and z < ArenaLayout.HalfLength
		and bot.root.Position.Y > ArenaLayout.SurfaceY - 2
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

test("an elimination pays the eliminator 25 coins instantly and counts toward the knockout quest", function()
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
	local quests = S.QuestService.daily(me)
	local savedKnockouts = quests.progress.Knockouts
	quests.progress.Knockouts = 0
	victim.lastHitBy = me
	victim.lastHitAt = now()
	victim.character:PivotTo(CFrame.new(victim.root.Position - Vector3.new(0, 60, 0)))
	assertTrue(
		waitUntil(function()
			return victim.status ~= "Active"
		end, 1),
		"victim not eliminated"
	)
	assertTrue(
		me.profile.Coins == before + Config.Coins.Elimination * S.BoostService.multiplier(me),
		("coins %d -> %d"):format(before, me.profile.Coins)
	)
	local counted = quests.progress.Knockouts
	quests.progress.Knockouts = savedKnockouts -- leave the tester's real quest as it was
	assertTrue(counted == 1, ("knockout quest at %s after a bot knockout"):format(tostring(counted)))
	S.PlayerStateService.setStatus(victim, "Active")
	ready(victim, point(enemyTeam, 0, 20))
end)

test("intro poses: a free default, 3+ to unlock, every pose and frame defined", function()
	local IntroPoses = require(Shared.IntroPoses)
	local items = Catalog.inCategory("Pose")
	local defaults, paid = 0, 0
	for _, item in items do
		if item.Default then
			defaults += 1
			assertTrue(item.Price == 0, "default pose isn't free")
		else
			paid += 1
		end
		local pose = IntroPoses.Poses[item.Data.Pose]
		assertTrue(pose ~= nil, item.Id .. " names an unknown pose")
		for _, step in pose.Frames do
			assertTrue(IntroPoses.Frames[step.frame] ~= nil, item.Id .. " uses an unknown frame " .. step.frame)
			assertTrue(step.hold > 0, item.Id .. " has a zero-length frame")
		end
	end
	assertTrue(defaults == 1 and paid >= 3, ("%d default and %d paid poses"):format(defaults, paid))
	-- equipping is server-checked like any cosmetic: owned or default only
	local c: any = {
		profileLoaded = true,
		inMatch = false,
		status = "Lobby",
		profile = { Coins = 0, OwnedCosmetics = {}, Equipped = {}, Level = 1, CurrentWinStreak = 0 },
	}
	assertTrue(S.ShopService.introPose(c) == IntroPoses.Default, "default pose not used")
	-- the intro pans Blue then Red for 2 s each, before the 3 s countdown
	local I = Config.Intro
	assertTrue(I.Order[1] == "Blue" and I.Order[2] == "Red", "intro order isn't Blue then Red")
	assertTrue(I.BlueTime == 2 and I.RedTime == 2 and Config.Match.RoundCountdown == 3, "intro timings changed")
	assertTrue(not S.ShopService.equip(c, "Pose_Dab"), "equipped an unowned pose")
	c.profile.OwnedCosmetics.Pose_Dab = true
	assertTrue(S.ShopService.equip(c, "Pose_Dab") and S.ShopService.introPose(c) == "Dab", "owned pose not equipped")
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
	ready(bot, point("Red", 20, 12))
	ready(blue[1], point("Blue", 20, 10)) -- closest (22 studs), well clear of every edge
	ready(blue[2], point("Blue", ArenaLayout.HalfWidth - 4, 14)) -- farther (~35), 4 studs from the side edge
	-- both hold a ball, so the could-catch penalty (which hinges on exact facing) applies to neither
	giveBall(blue[1])
	giveBall(blue[2])
	task.wait(0.3)
	local smart = S.BotService.pickTarget(bot, true, false)
	local naive = S.BotService.pickTarget(bot, false, false)
	for _, c in S.MatchService.roster() do
		if c.team == "Blue" then
			S.PlayerStateService.setStatus(c, "Active")
		end
	end
	ready(blue[1], point("Blue", 0, 14))
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

test("bots: two teammates by one ball don't both chase it", function()
	local red = bots("Red")
	assertTrue(#red >= 2, "need 2 red bots")
	local a, b = red[1], red[2]
	local p = point("Red", -14, 20)
	ready(a, p + Vector3.new(-2, 0, 0))
	ready(b, p + Vector3.new(2, 0, 0))
	task.wait(0.3)
	clearBallsNear(p, 30)
	local near = S.BallService.spawn("Standard", p + Vector3.new(0, -1.5, 6), "Match")
	local far = S.BallService.spawn("Standard", p + Vector3.new(0, -1.5, -14), "Match")
	near.lockoutUntil, far.lockoutUntil = math.huge, math.huge -- out of reach: watch the plans only
	a.bot.claim, b.bot.claim = nil, nil
	a.bot.thrownAt, b.bot.thrownAt = nil, nil
	S.BotService.tickOne(a)
	S.BotService.tickOne(b)
	S.BotService.tickOne(a)
	local ok = a.bot.claim ~= b.bot.claim or a.bot.claim == nil
	S.BallService.destroy(near)
	S.BallService.destroy(far)
	assertTrue(ok, "both bots went for the same ball")
end)

test("bots: wait PickupAfterThrow after a throw before chasing a ball", function()
	local bot = bots("Red")[1]
	local p = point("Red", 0, 20)
	ready(bot, p)
	task.wait(0.3)
	clearBallsNear(p, 30)
	local ball = S.BallService.spawn("Standard", p + Vector3.new(0, -1.5, 6), "Match")
	bot.bot.claim = nil
	bot.bot.thrownAt = Workspace:GetServerTimeNow()
	S.BotService.tickOne(bot)
	local waited = bot.bot.claim == nil
	bot.bot.thrownAt = Workspace:GetServerTimeNow() - Config.Bots.PickupAfterThrow - 0.1
	S.BotService.tickOne(bot)
	local chased = bot.bot.claim == ball.id
	bot.bot.claim, bot.bot.thrownAt = nil, nil
	S.BallService.destroy(ball)
	assertTrue(waited, "bot went for a ball right after throwing")
	assertTrue(chased, "bot still ignores balls after the wait")
end)

test("bots: dodges go toward the middle, never off the edge", function()
	local bot = bots("Red")[1]
	ready(bot, point("Red", ArenaLayout.HalfWidth - 6, 24)) -- 6 from the right edge
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
	assertTrue(
		dot > 0.98,
		("hub spawn faces %.0f° away from the court"):format(math.deg(math.acos(math.clamp(dot, -1, 1))))
	)
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
		assertTrue(
			math.max(dx, dz) >= A.LobbyGap - 0.5,
			("deck corner only %.1f from the court"):format(math.max(dx, dz))
		)
	end
	-- and it's next to the court: the court-side edge faces the middle of the court within the gap
	local front = ArenaLayout.lobbyPoint(0, 0, hz)
	local toCourt = (Vector3.new(A.Origin.X, front.Y, A.Origin.Z) - front).Magnitude
	assertTrue(
		toCourt <= ArenaLayout.HalfWidth + A.LobbyGap + 1,
		("hub is %.0f studs from the court centre"):format(toCourt)
	)
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
	assertTrue(
		balls <= Config.Ball.BallsPerCourt + 2 * Config.PowerUps.MaxPowerBallsPerSide + 6,
		("%d balls"):format(balls)
	)
end)

-- Signed distance into a team's own half (positive = on its side of the center line).
local function depthOnOwnHalf(c: any): number
	return ArenaLayout.teamSign(c.team) * (c.root.Position.Z - O.Z)
end

test("center line: walking, jumping and dodging at the line never cross it", function()
	local bot = bots("Red")[1]
	assertTrue(bot ~= nil, "need a red bot")
	local across = point("Blue", 0, 12)
	-- walk straight at the enemy half
	ready(bot, point("Red", 0, 2))
	task.wait(0.3)
	bot.humanoid:MoveTo(across)
	task.wait(2)
	assertTrue(depthOnOwnHalf(bot) > -0.5, ("walked across (depth %.1f)"):format(depthOnOwnHalf(bot)))
	-- jump while walking at it
	ready(bot, point("Red", 0, 2))
	task.wait(0.3)
	bot.humanoid:MoveTo(across)
	for _ = 1, 3 do
		bot.humanoid.Jump = true
		task.wait(0.6)
	end
	assertTrue(depthOnOwnHalf(bot) > -0.5, ("jumped across (depth %.1f)"):format(depthOnOwnHalf(bot)))
	-- dodge straight at it
	ready(bot, point("Red", 0, 2))
	task.wait(0.3)
	local toward = Vector3.new(0, 0, ArenaLayout.teamSign("Blue"))
	assertTrue(S.CombatService.doDodge(bot, toward), "dodge refused")
	task.wait(Config.Player.DodgeDuration + 0.5)
	assertTrue(depthOnOwnHalf(bot) > -0.5, ("dodged across (depth %.1f)"):format(depthOnOwnHalf(bot)))
	ready(bot, point("Red", 0, 20))
end)

test("a character removed mid-ragdoll counts as a fall and is rebuilt", function()
	local me
	for _, c in S.MatchService.roster() do
		if c.player and c.status == "Active" then
			me = c
		end
	end
	assertTrue(me ~= nil, "no active real player in the match")
	ready(me, point(me.team, 0, 20))
	task.wait(0.3)
	me.immuneUntil = 0
	S.PlayerStateService.setAction(me, "Ragdolled")
	S.RagdollService.ragdoll(me.character, Vector3.new(0, 20, 0))
	task.wait(0.2)
	local old = me.character
	old:Destroy() -- what the engine does on a reset or a fall past FallenPartsDestroyHeight
	assertTrue(
		waitUntil(function()
			return me.status ~= "Active"
		end, 3),
		"still Active with no character"
	)
	assertTrue(
		waitUntil(function()
			return me.character ~= nil and me.character ~= old and S.PlayerStateService.isAlive(me)
		end, 10),
		"character was never rebuilt"
	)
	S.PlayerStateService.setStatus(me, "Active")
	ready(me, point(me.team, 0, 20))
end)

test("paid random items: restricted players can't buy spins but still open quest chests", function()
	Workspace:SetAttribute("RD_PaidRandomRestricted", true)
	local ok, err = pcall(function()
		local c: any = {
			id = 900002,
			player = { UserId = 900002 },
			profileLoaded = true,
			inMatch = false,
			status = "Lobby",
			profile = {
				Coins = 100000,
				OwnedCosmetics = {},
				Equipped = {},
				Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} },
			},
		}
		local st = S.SpinService.status(c)
		assertTrue(st.restricted and st.paidLeft == 0 and st.robux == 0, "spin status still offers paid spins")
		assertTrue(S.SpinService.spin(c, "Coins") == nil, "paid spin for a restricted player")
		assertTrue(S.SpinService.spin(c, "Robux") == nil, "Robux spin for a restricted player")
		assertTrue(c.profile.Coins == 100000, "a refused open cost coins")
		assertTrue(st.free == true, "the free spin should stay open")
		local player = c.player
		c.player = nil -- (a claim pushes the profile, which needs a real Player)
		S.QuestService.daily(c).progress.Won = 1
		assertTrue(S.QuestService.claim(c, "Won") ~= nil, "quest chest refused in a restricted region")
		c.player = player
		-- (granting a prize pushes the profile, which needs a real Player, so the successful paths
		-- are checked through the policy itself)
		Workspace:SetAttribute("RD_PaidRandomRestricted", false)
		assertTrue(not S.ComplianceService.paidRandomRestricted(c), "still restricted when the policy allows")
		assertTrue(S.SpinService.status(c).paidLeft > 0, "paid spins not offered when allowed")
		c.player = nil
		assertTrue(not S.ComplianceService.paidRandomRestricted(c), "bots should never be restricted")
	end)
	Workspace:SetAttribute("RD_PaidRandomRestricted", nil)
	assertTrue(ok, tostring(err))
end)

test("saving: no lock-keeping save goes out after the release save", function()
	local c: any = { persistent = false, player = nil, profile = {} }
	S.DataService.save(c, true) -- the leave/shutdown save marks the session released
	assertTrue(c.released == true, "release save didn't mark the session")
	c.persistent = true
	assertTrue(S.DataService.save(c, false) == false, "an autosave ran after the release")
end)

test("Halloween follows its UTC window", function()
	local H = Config.Halloween
	local savedEnabled, savedStart, savedEnd = H.Enabled, H.Start, H.End
	local function iso(t: number): string
		return DateTime.fromUnixTimestamp(t):ToIsoDate()
	end
	local ok, err = pcall(function()
		local t = os.time()
		H.Enabled = true
		H.Start, H.End = iso(t - 3600), iso(t + 3600)
		assertTrue(S.HalloweenService.scheduled(), "off inside its window")
		H.Start, H.End = iso(t - 7200), iso(t - 3600)
		assertTrue(not S.HalloweenService.scheduled(), "on after its window")
		H.Start, H.End = iso(t + 3600), iso(t + 7200)
		assertTrue(not S.HalloweenService.scheduled(), "on before its window")
		H.Enabled = false
		H.Start, H.End = iso(t - 3600), iso(t + 3600)
		assertTrue(not S.HalloweenService.scheduled(), "on while disabled")
	end)
	H.Enabled, H.Start, H.End = savedEnabled, savedStart, savedEnd
	assertTrue(ok, tostring(err))
end)

test("purchases: every product grants once, retries never double-grant, failures recover", function()
	local me
	for _, c in S.PlayerStateService.realPlayers() do
		if c.profile and c.player then
			me = c
		end
	end
	assertTrue(me ~= nil, "no real player with a profile")
	local p = me.profile
	local saved = {
		coins = p.Coins,
		untilTime = p.CoinBoostUntil,
		forever = p.CoinBoostForever,
		receipts = table.clone(p.Receipts),
		owned = table.clone(p.OwnedCosmetics),
	}
	local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local Later = Enum.ProductPurchaseDecision.NotProcessedYet
	local n = 0
	local function receipt(productId: number, purchaseId: string?): any
		n += 1
		return {
			PlayerId = me.player.UserId,
			ProductId = productId,
			PurchaseId = purchaseId or ("RD_TEST_%d_%d"):format(os.time(), n),
			CurrencySpent = 0,
		}
	end
	local ok, err = pcall(function()
		-- every configured product has a handler
		local CS = Config.CoinShop
		for _, b in CS.Bundles do
			assertTrue(b.ProductId > 0, b.Id .. " has no product id")
		end
		-- coin bundle: granted once, the same receipt again changes nothing
		local bundle = CS.Bundles[1]
		local r = receipt(bundle.ProductId)
		local before = p.Coins
		assertTrue(S.PurchaseService.process(r) == Granted, "bundle not granted")
		assertTrue(p.Coins == before + bundle.Coins, "bundle coins not added")
		assertTrue(S.PurchaseService.process(r) == Granted, "retried receipt not acknowledged")
		assertTrue(p.Coins == before + bundle.Coins, "retried receipt granted twice")
		-- timed boost stacks from its current end; the lifetime boost sets the flag
		p.CoinBoostUntil, p.CoinBoostForever = 0, false
		assertTrue(S.BoostService.multiplier(me) == 1, "boost active before buying")
		local timed, forever = CS.Boosts[1], CS.Boosts[2]
		assertTrue(S.PurchaseService.process(receipt(timed.ProductId)) == Granted, "timed boost not granted")
		local first = p.CoinBoostUntil
		assertTrue(math.abs(first - (os.time() + timed.Minutes * 60)) <= 2, "timed boost has the wrong length")
		assertTrue(S.BoostService.multiplier(me) == CS.BoostMultiplier, "timed boost not doubling")
		S.PurchaseService.process(receipt(timed.ProductId))
		assertTrue(p.CoinBoostUntil == first + timed.Minutes * 60, "a second timed boost didn't extend it")
		p.CoinBoostUntil = 0
		assertTrue(S.PurchaseService.process(receipt(forever.ProductId)) == Granted, "lifetime boost not granted")
		assertTrue(
			p.CoinBoostForever == true and S.BoostService.multiplier(me) == CS.BoostMultiplier,
			"lifetime boost off"
		)
		-- limited-time bundle (a test id routes to its grant while the real one is a placeholder):
		-- items and coins once, the same receipt again changes nothing
		for _, offer in CS.Offers do
			local offerId = 999000222
			S.PurchaseService.register(offerId, function(c: any): boolean
				return S.PurchaseService.grantOffer(c, offer)
			end)
			for _, id in offer.Items do
				p.OwnedCosmetics[id] = nil
			end
			local br = receipt(offerId)
			local coinsBefore = p.Coins
			assertTrue(S.PurchaseService.process(br) == Granted, offer.Id .. " not granted")
			assertTrue(S.PurchaseService.process(br) == Granted, offer.Id .. " retry not acknowledged")
			assertTrue(p.Coins == coinsBefore + offer.Coins, offer.Id .. " coins wrong after a retry")
			for _, id in offer.Items do
				assertTrue(p.OwnedCosmetics[id] == true, offer.Id .. " missing " .. id)
			end
		end
		-- a grant that throws is retried later and lands then, exactly once
		local fakeId = 999000111
		local fail = true
		S.PurchaseService.register(fakeId, function(c: any): boolean
			if fail then
				error("simulated failure mid-grant")
			end
			c.profile.Coins += 7
			return true
		end)
		local fr = receipt(fakeId)
		local coins = p.Coins
		assertTrue(S.PurchaseService.process(fr) == Later, "failed grant was acknowledged")
		assertTrue(p.Coins == coins and not table.find(p.Receipts, fr.PurchaseId), "failed grant left a trace")
		fail = false
		assertTrue(S.PurchaseService.process(fr) == Granted, "retry after a failure not granted")
		assertTrue(S.PurchaseService.process(fr) == Granted and p.Coins == coins + 7, "retry granted twice")
		-- unknown products and absent players wait for a server that can handle them
		assertTrue(S.PurchaseService.process(receipt(424242)) == Later, "unknown product acknowledged")
		local away = receipt(bundle.ProductId)
		away.PlayerId = 1
		assertTrue(S.PurchaseService.process(away) == Later, "receipt for an absent player acknowledged")
	end)
	p.Coins, p.CoinBoostUntil, p.CoinBoostForever, p.Receipts, p.OwnedCosmetics =
		saved.coins, saved.untilTime, saved.forever, saved.receipts, saved.owned
	S.DataService.push(me)
	assertTrue(ok, tostring(err))
end)

test("Robux buttons stay hidden until the first finished match", function()
	local studioUnlock = Workspace:GetAttribute("RD_RobuxUnlocked")
	Workspace:SetAttribute("RD_RobuxUnlocked", nil)
	local c: any = {
		profileLoaded = true,
		profile = { TutorialStep = 1, Matches = 0 },
	}
	assertTrue(not S.PurchaseService.robuxUnlocked(c), "unlocked for a brand-new player")
	c.profile.Matches = Config.CoinShop.RobuxAfterMatches
	assertTrue(S.PurchaseService.robuxUnlocked(c), "still locked after a finished match")
	Workspace:SetAttribute("RD_RobuxUnlocked", studioUnlock)
	local migrated = S.DataService.migrate({ SchemaVersion = 8, Matches = 5 })
	assertTrue(S.PurchaseService.robuxUnlocked({ profileLoaded = true, profile = migrated }), "a returning player is locked again")
	assertTrue(migrated.CoinBoostForever == false and migrated.CoinBoostUntil == 0, "v9 boost fields missing")
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
	assertTrue(
		waitUntil(function()
			return ms:GetAttribute("State") == "RoundResolution"
		end, 2),
		"round did not end"
	)
	assertTrue(
		ms:GetAttribute("RedWins") == redWins and ms:GetAttribute("BlueWins") == blueWins,
		"a team was awarded the round"
	)
end)

test("a team with only jailed players loses the round", function()
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	S.MatchService.debugSetWins(0, 0) -- so this round can't end the match
	local red = bots("Red")[1]
	assertTrue(red ~= nil, "need a red bot")
	ready(red, point("Red", 0, 20))
	for _, c in S.MatchService.roster() do
		if c.team == "Blue" then
			S.PlayerStateService.setStatus(c, "Jailed")
		end
	end
	assertTrue(
		waitUntil(function()
			return ms:GetAttribute("State") == "RoundResolution"
		end, 2),
		"round didn't end with every Blue player jailed"
	)
	assertTrue(ms:GetAttribute("RedWins") == 1, "Red wasn't awarded the round")
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

test("daily reward: one claim per UTC day, ladder advances, missed day resets, every kind lands", function()
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
	local function fresh(day: number, claimed: string): any
		return {
			id = 900010,
			profileLoaded = true,
			inMatch = false,
			status = "Lobby",
			profile = {
				Coins = 0,
				OwnedCosmetics = {},
				Equipped = {},
				BonusSpins = {},
				RewardPicks = {},
				CoinBoostUntil = 0,
				LoginStreak = { day = day, lastDate = claimed, claimedDate = claimed },
			},
		}
	end
	local ladder = Config.DailyRewards.Ladder
	assertTrue(ladder[1].Kind == "Spin", "day 1 isn't a free spin")
	for i, reward in ladder do
		assertTrue(S.RewardService.valid(reward), ("day %d isn't a valid reward"):format(i))
	end
	-- day 4 pays its coins, once
	local c = fresh(3, yesterday)
	local r = S.ShopService.claimDaily(c)
	assertTrue(r and r.day == 4 and c.profile.LoginStreak.day == 4, "did not advance to day 4")
	assertTrue(c.profile.Coins == ladder[4].Amount, "day 4 didn't pay its coins")
	assertTrue(not S.ShopService.claimDaily(c), "second claim the same day paid")
	assertTrue(c.profile.Coins == ladder[4].Amount, "coins changed on a refused claim")
	-- a missed day starts over at day 1: a Rare+ bonus spin
	c = fresh(5, "2000-01-01")
	r = S.ShopService.claimDaily(c)
	assertTrue(r and c.profile.LoginStreak.day == 1, "missed day did not reset the ladder")
	assertTrue(r.kind == "Spin" and c.profile.BonusSpins[1] == ladder[1].Wheel, "day 1 spin not queued")
	-- day 7 wraps to day 1
	c = fresh(7, yesterday)
	S.ShopService.claimDaily(c)
	assertTrue(c.profile.LoginStreak.day == 1, "day 7 did not wrap to day 1")
	-- day 3: the free boost
	c = fresh(2, yesterday)
	r = S.ShopService.claimDaily(c)
	assertTrue(r and r.kind == "Boost" and c.profile.CoinBoostUntil > os.time(), "day 3 boost not running")
	-- day 7: pick one of the offered Epics, exactly once
	c = fresh(6, yesterday)
	r = S.ShopService.claimDaily(c)
	assertTrue(r and r.kind == "Pick" and #r.ids >= 1, "day 7 offered no pick")
	assertTrue(S.ShopService.dailyStatus(c).pick ~= nil, "pick missing from the daily status")
	assertTrue(not S.RewardService.pick(c, "Skin_Lime"), "took an item that wasn't offered")
	local got = S.RewardService.pick(c, r.ids[1])
	assertTrue(got and got.ok and c.profile.OwnedCosmetics[r.ids[1]], "picked item not owned")
	assertTrue(not S.RewardService.pick(c, r.ids[1]), "a pick granted twice")
end)

test("daily spin: one free spin a day, paid spins cost coins and are capped, duplicates pay coins", function()
	local SP = Config.Spin
	local c: any = {
		id = 900001,
		profileLoaded = true,
		inMatch = false,
		status = "Lobby",
		profile = {
			Coins = 0,
			OwnedCosmetics = {},
			Equipped = {},
			Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} },
		},
	}
	local preview = S.SpinService.wheel(c)
	assertTrue(#preview == SP.Slots, "wheel has the wrong number of slots")
	local r1 = S.SpinService.spin(c, "Free")
	assertTrue(r1 and r1.ok, "free spin refused")
	assertTrue(
		r1.slots[r1.index] == r1.id and r1.id == preview[r1.index],
		"prize isn't the wheel slot the client was shown"
	)
	assertTrue(c.profile.OwnedCosmetics[r1.id] == true, "prize not granted")
	assertTrue(S.SpinService.spin(c, "Free") == nil, "second free spin the same day")
	assertTrue(S.SpinService.spin(c, "Coins") == nil, "paid spin with no coins")
	c.profile.Coins = SP.ExtraSpinCost * (SP.MaxPaidPerDay + 1)
	local before = c.profile.Coins
	assertTrue(S.SpinService.spin(c, "Coins") ~= nil, "paid spin refused")
	assertTrue(
		c.profile.Coins <= before - SP.ExtraSpinCost + SP.DuplicateCoins.Legendary,
		"paid spin didn't cost coins"
	)
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

-- A loaded, in-hub combatant with no Player (claims push the profile only for real players).
local function questTester(id: number): any
	return {
		id = id,
		profileLoaded = true,
		inMatch = false,
		status = "Lobby",
		profile = { Coins = 0, OwnedCosmetics = {}, Equipped = {} },
	}
end

local function questStatus(c: any, id: string): any
	for _, q in S.QuestService.status(c).quests do
		if q.id == id then
			return q
		end
	end
	return nil
end

test("quests: progress counts up to each goal; only real players track it", function()
	local c = questTester(900030)
	c.player = { UserId = 900030 } -- record() only tracks real players
	S.QuestService.record(c, "Knockout")
	S.QuestService.record(c, "Knockout")
	assertTrue(questStatus(c, "Knockouts").progress == 2, "2 knockouts not counted")
	assertTrue(not questStatus(c, "Knockouts").ready, "ready at 2 of 3")
	S.QuestService.record(c, "Knockout", 4)
	local q = questStatus(c, "Knockouts")
	assertTrue(q.progress == 3 and q.ready, "knockouts not capped at the goal")
	assertTrue(questStatus(c, "Played").progress == 0, "a knockout counted as a game")
	S.QuestService.record(c, "Played")
	S.QuestService.record(c, "Won")
	assertTrue(questStatus(c, "Played").progress == 1 and questStatus(c, "Won").ready, "played/won not counted")
	local bot = questTester(900031)
	S.QuestService.record(bot, "Knockout")
	assertTrue(bot.profile.DailyQuests == nil, "a bot's quests were tracked")
end)

test("mastery: power-ball knockouts count by type; mastery cosmetics stay out of shop and pools", function()
	local c = questTester(900035)
	c.player = { UserId = 900035 } -- recordPowerKO() only tracks real players
	c.profile.PowerKOs = {}
	local featured = S.ShopService.featuredBall()
	local plain = "Heavy"
	for _, t in BallDefinitions.PowerTypes do
		if t ~= featured then
			plain = t
		end
	end
	S.ShopService.recordPowerKO(c, "Standard")
	assertTrue(next(c.profile.PowerKOs) == nil, "a Standard knockout counted")
	S.ShopService.recordPowerKO(c, plain)
	assertTrue(c.profile.PowerKOs[plain] == 1, "a power knockout wasn't counted")
	if featured then
		S.ShopService.recordPowerKO(c, featured)
		local bonus = Config.PowerUps.Featured.MasteryBonus
		assertTrue(c.profile.PowerKOs[featured] == bonus, "the featured ball didn't count double")
	end
	for _, item in Catalog.Items do
		if item.Unlock then
			assertTrue(not Catalog.isOffered(item), item.Id .. " is offered for coins")
			for _, list in S.SpinService.pool() do
				for _, it in list do
					assertTrue(it.Id ~= item.Id, item.Id .. " is on the wheels")
				end
			end
		end
	end
	for _, q in Config.Quests.List do
		local pool = S.RewardService.chestPool(q.Chest)
		for _, r in { "Common", "Rare", "Epic", "Legendary" } do
			assertTrue(#pool[r] > 0, q.Chest .. " chest has no " .. r .. " items")
		end
	end
end)

test("quests: a new UTC day clears progress and claims", function()
	local c = questTester(900032)
	local d = S.QuestService.daily(c)
	d.progress.Won = 1
	assertTrue(S.QuestService.claim(c, "Won") ~= nil, "claim refused")
	d.progress.Knockouts = 2
	d.date = "2000-01-01" -- yesterday, as far as the service can tell
	for _, q in S.QuestService.status(c).quests do
		assertTrue(q.progress == 0 and not q.claimed, q.id .. " survived the reset")
	end
	local resetsAt = S.QuestService.status(c).resetsAt
	assertTrue(resetsAt % 86400 == 0 and resetsAt > os.time(), "reset isn't the next UTC midnight")
	assertTrue(resetsAt - os.time() <= 86400, "reset more than a day away")
end)

test("quests: the first claim of a quest comes back after the short cooldown, later ones wait for the reset", function()
	local c = questTester(900033)
	local d = S.QuestService.daily(c)
	d.progress.Won = 1
	assertTrue(S.QuestService.claim(c, "Won") ~= nil, "first claim refused")
	local st = questStatus(c, "Won")
	local wait = st.nextAt - os.time()
	assertTrue(st.claimed and math.abs(wait - Config.Quests.FirstCooldown) <= 1, "first claim's cooldown is wrong")
	assertTrue(S.QuestService.claim(c, "Won") == nil, "claimed again during the cooldown")
	assert(d.backAt, "no cooldown recorded")
	d.backAt.Won = os.time() - 1 -- the cooldown has run out
	st = questStatus(c, "Won")
	assertTrue(not st.claimed and st.progress == 0, "quest didn't come back fresh")
	d.progress.Won = 1
	assertTrue(S.QuestService.claim(c, "Won") ~= nil, "second claim refused")
	st = questStatus(c, "Won")
	assertTrue(st.nextAt == S.QuestService.status(c).resetsAt, "second claim didn't wait for the reset")
end)

test("exclusives: Robux-exclusive cosmetics never come out of a spin or chest and aren't sold for coins", function()
	local exclusive: { [string]: boolean } = {}
	local any = false
	for _, item in Catalog.Items do
		if item.Exclusive then
			any = true
			exclusive[item.Id] = true
			assertTrue(not Catalog.isOffered(item), item.Id .. " is offered for coins")
			assertTrue(Catalog.robuxPrice(item) ~= nil, item.Id .. " has no Robux price for its rarity")
		end
	end
	assertTrue(any, "no Exclusive item to check")
	for r, list in S.SpinService.pool() do
		for _, it in list do
			assertTrue(not exclusive[it.Id], it.Id .. " is in the " .. r .. " spin pool")
		end
	end
	for chest in Config.Quests.Chests do
		for r, list in S.RewardService.chestPool(chest) do
			for _, it in list do
				assertTrue(not exclusive[it.Id], it.Id .. " is in the " .. chest .. " chest's " .. r .. " pool")
			end
		end
	end
end)

test("quests: a chest is claimed once, only when done and only in the hub", function()
	local c = questTester(900033)
	assertTrue(S.QuestService.claim(c, "Played") == nil, "claimed an unfinished quest")
	S.QuestService.daily(c).progress.Played = 2
	c.status, c.inMatch = "Active", true
	assertTrue(S.QuestService.claim(c, "Played") == nil, "claimed during a match")
	c.status, c.inMatch = "Lobby", false
	local r = S.QuestService.claim(c, "Played")
	assertTrue(r and r.ok and r.kind == "Chest" and r.chest == "Gesture", "claim refused")
	assertTrue((Catalog.get(r.id) :: any).Category == "Pose", "the Gesture Chest dropped a non-gesture")
	assertTrue(c.profile.OwnedCosmetics[r.id] == true, "prize not owned")
	assertTrue(r.slots[r.index] == r.id, "reveal wheel doesn't land on the prize")
	local coins = c.profile.Coins
	assertTrue(S.QuestService.claim(c, "Played") == nil, "claimed twice")
	assertTrue(c.profile.Coins == coins, "a refused claim paid coins")
	assertTrue(questStatus(c, "Played").claimed, "not shown as claimed")
end)

test("quests: chest drops follow the rarity odds and stay in the chest's category", function()
	for _, def in Config.Quests.List do
		local odds = S.RewardService.chestOdds(def.Chest)
		local category = (Config.Quests.Chests :: any)[def.Chest].Category
		local counts: { [string]: number } = {}
		local n = 1500
		for i = 1, n do
			local r = S.RewardService.grant(questTester(910000 + i), { Kind = "Chest", Chest = def.Chest }, "Test")
			local item = Catalog.get(r.id) :: any
			assertTrue(item.Category == category, def.Chest .. " dropped a " .. item.Category)
			assertTrue(Catalog.rarity(item) == r.rarity and not r.duplicate, def.Chest .. " prize mislabeled")
			counts[r.rarity] = (counts[r.rarity] or 0) + 1
		end
		for rarity, p in odds do
			local got = (counts[rarity] or 0) / n
			assertTrue(
				math.abs(got - p) < 0.04,
				("%s: %s %.1f%%, want %.1f%%"):format(def.Chest, rarity, got * 100, p * 100)
			)
		end
	end
end)

test("quests: duplicates only once a rarity is all owned, and pay that rarity's coins", function()
	local c = questTester(900034)
	local pool = S.RewardService.chestPool("Title")
	for _, items in pool do
		for _, item in items do
			c.profile.OwnedCosmetics[item.Id] = true
		end
	end
	local spare = pool.Rare[1].Id
	local sawRare, sawDup = false, false
	for _ = 1, 150 do
		c.profile.OwnedCosmetics[spare] = nil -- one unowned Rare title
		local before = c.profile.Coins
		local r = S.RewardService.grant(c, { Kind = "Chest", Chest = "Title" }, "Test")
		if r.rarity == "Rare" then
			sawRare = true
			assertTrue(r.id == spare and not r.duplicate and r.coins == 0, "an owned Rare title dropped")
		else
			sawDup = true
			assertTrue(r.duplicate and r.coins == Config.Economy.DuplicateCoins[r.rarity], "wrong duplicate payout")
			assertTrue(c.profile.Coins - before == r.coins, "duplicate coins not paid")
		end
	end
	assertTrue(sawRare and sawDup, "150 rolls never hit both cases")
end)

test("save schema v12 migration turns today's unopened free chests into bonus spins", function()
	local today = os.date("!%Y-%m-%d", os.time())
	local m = S.DataService.migrate({
		SchemaVersion = 11,
		Coins = 7,
		ChestOpens = 4,
		ChestDaily = { date = today, matches = 3, claimed = { Common = true } },
	})
	assertTrue(m.SchemaVersion == Config.Data.SchemaVersion, "schema not bumped")
	assertTrue(#m.BonusSpins == 1 and m.BonusSpins[1] == "RarePlus", "the unopened Rare chest wasn't converted")
	assertTrue((m :: any).ChestDaily == nil and (m :: any).ChestOpens == nil, "lobby chest data kept")
	assertTrue(m.Coins == 7, "coins lost")
	local stale = S.DataService.migrate({ SchemaVersion = 11, ChestDaily = { date = "2000-01-01", matches = 5 } })
	assertTrue(#stale.BonusSpins == 0, "an expired free chest was granted")
end)

test("daily spin: wheels follow the rarity weights", function()
	local counts: { [string]: number } = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
	local total = 0
	for i = 1, 400 do
		local c: any = {
			id = 800000 + i,
			profile = { Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} } },
		}
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
		assertTrue(
			math.abs(got - want) < 0.04,
			("%s is %.1f%% of slots, expected %.1f%%"):format(r, got * 100, want * 100)
		)
	end
end)

test("daily spin: bonus spins go first on their own wheel and stack with the daily spin", function()
	local c: any = {
		id = 900011,
		profileLoaded = true,
		inMatch = false,
		status = "Lobby",
		profile = {
			Coins = 0,
			OwnedCosmetics = {},
			Equipped = {},
			BonusSpins = { "RarePlus" },
			Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} },
		},
	}
	local st = S.SpinService.status(c)
	assertTrue(st.freeSpins == 2 and st.bonus == "RarePlus", "bonus spin not counted")
	for _, id in st.slots do
		assertTrue(Catalog.rarity(Catalog.get(id) :: any) ~= "Common", "a Common on the Rare+ wheel")
	end
	local r = S.SpinService.spin(c, "Free")
	assertTrue(r and r.how == "Bonus" and r.slots[r.index] == r.id, "bonus spin not used first")
	assertTrue(#c.profile.BonusSpins == 0 and not c.profile.Spin.freeUsed, "bonus spin used the daily one")
	assertTrue(S.SpinService.spin(c, "Free") ~= nil, "daily spin gone after a bonus spin")
	assertTrue(S.SpinService.spin(c, "Free") == nil, "a third free spin")
end)

test("save schema v11 migration keeps login streaks and adds bonus spins and picks", function()
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
	local migrated = S.DataService.migrate({
		SchemaVersion = 10,
		Coins = 50,
		LoginStreak = { day = 6, lastDate = yesterday, claimedDate = yesterday },
	})
	assertTrue(migrated.SchemaVersion == Config.Data.SchemaVersion, "schema not bumped")
	assertTrue(migrated.LoginStreak.day == 6 and migrated.LoginStreak.claimedDate == yesterday, "streak lost")
	assertTrue(migrated.Coins == 50, "coins lost")
	assertTrue(type(migrated.BonusSpins) == "table" and type(migrated.RewardPicks) == "table", "no v11 fields")
	local c: any = { profileLoaded = true, profile = migrated }
	assertTrue(S.ShopService.dailyStatus(c).day == 7, "streak didn't continue at day 7")
	local damaged = S.DataService.migrate({ SchemaVersion = 10, LoginStreak = { day = "4", claimedDate = yesterday } })
	assertTrue(damaged.LoginStreak.day == 4, "a damaged streak was reset")
end)

test("save schema v5 migration keeps v4 data and adds the daily spin", function()
	local migrated = S.DataService.migrate({
		SchemaVersion = 4,
		Coins = 1234,
		OwnedCosmetics = { Skin_Lime = true },
		Equipped = { BallSkin = "Skin_Lime" },
		Level = 7,
	})
	assertTrue(
		migrated.SchemaVersion == Config.Data.SchemaVersion and Config.Data.SchemaVersion >= 5,
		"schema not bumped"
	)
	assertTrue(migrated.Coins == 1234 and migrated.Level == 7, "v4 data lost")
	assertTrue(
		migrated.OwnedCosmetics.Skin_Lime == true and migrated.Equipped.BallSkin == "Skin_Lime",
		"cosmetics lost"
	)
	assertTrue(type(migrated.Spin) == "table" and migrated.Spin.freeUsed == false, "no spin state")
	local v1 = S.DataService.migrate({ SchemaVersion = 1, Coins = 5 })
	assertTrue(v1.Spin ~= nil and v1.LoginStreak ~= nil, "v1 profile not fully migrated")
end)

test("sudden death: jail closes (no returns, no new prisoners)", function()
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	S.MatchService.debugForceSuddenDeath()
	assertTrue(
		waitUntil(function()
			return ms:GetAttribute("Overtime") == true
		end, 1),
		"sudden death did not start"
	)
	local red, blue = bots("Red"), bots("Blue")
	local faller, enemy = red[1], blue[1]
	ready(faller, point("Red", -10, 20))
	ready(enemy, point("Blue", 0, 20))
	task.wait(0.2)
	faller.character:PivotTo(CFrame.new(O + Vector3.new(-40, -40, -20)))
	assertTrue(
		waitUntil(function()
			return faller.status ~= "Active"
		end, 1),
		"faller not eliminated"
	)
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
	assertTrue(
		waitUntil(function()
			return ms:GetAttribute("State") == "Finisher"
		end, 2),
		"no finisher phase"
	)
	assertTrue(
		waitUntil(function()
			return ms:GetAttribute("State") == "Intermission" or ms:GetAttribute("MatchId") ~= matchId
		end, 15),
		"match did not end after the finisher"
	)
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
	local hw, hl = ArenaLayout.HalfWidth, ArenaLayout.HalfLength
	local spots = {
		{ name = "center of half (x0, 14 from line)", x = 0, depth = 14 },
		{ name = "spawn line", x = 0, depth = Config.Arena.SpawnSetback },
		{ name = "deep (10 from back)", x = 0, depth = hl - 10 },
		{ name = "near side (10 from edge)", x = hw - 10, depth = hl / 2 },
		{ name = "edge (5 from edge)", x = hw - 5, depth = hl / 2 },
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
							maxD =
								math.max(maxD, (Vector3.new(p.X, 0, p.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude)
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
			table.insert(
				lines,
				("%-38s charge %3.0f%%: hits %d/3, void %d, avg travel %.1f studs"):format(
					spot.name,
					charge * 100,
					hits,
					ko,
					if hits > 0 then travel / hits else 0
				)
			)
		end
	end
	S.BotService.setPaused(false)
	local out = table.concat(lines, "\n")
	print("[KnockbackProbe]\n" .. out)
	Workspace:SetAttribute("RD_KnockbackResults", out)
end

-- Soak test: let bots play `rounds` real rounds untouched, and watch for build-up and stuck bodies.
-- Run: workspace:SetAttribute("RD_Soak", 50) with Play again on and every menu closed (about a
-- minute a round). Progress and the verdict land in workspace attribute "RD_SoakResults".
--
-- Per round it records rigs, ball sockets, bot models, balls, workspace instances and server memory.
-- Throughout, it counts server script errors and stuck combatants: on court and Active but ragdolled
-- for over 10 s, below the court for over 3 s without being eliminated, or at a NaN position.
function TestService.soak(rounds: number)
	if running then
		return
	end
	running = true
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	local Stats = game:GetService("Stats")
	local ScriptContext = game:GetService("ScriptContext")
	local errors: { string } = {}
	local errConn = ScriptContext.Error:Connect(function(message: string, trace: string)
		if #errors < 20 then
			table.insert(errors, message .. " @ " .. (string.split(trace, "\n")[1] or ""))
		end
	end)
	local stuck: { string } = {}
	local ragdollSince: { [any]: number } = {}
	local lowSince: { [any]: number } = {}
	local samples: { { rigs: number, sockets: number, bots: number, balls: number, inst: number, mem: number } } = {}
	local lines: { string } = {}
	local function sample()
		local rigs, sockets = 0, 0
		local all = Workspace:GetDescendants()
		for _, d in all do
			if d:IsA("Humanoid") then
				rigs += 1
			elseif d:IsA("BallSocketConstraint") then
				sockets += 1
			end
		end
		local row = {
			rigs = rigs,
			sockets = sockets,
			bots = #(Workspace:FindFirstChild("Bots") :: Folder):GetChildren(),
			balls = #(Workspace:FindFirstChild("Balls") :: Folder):GetChildren(),
			inst = #all,
			mem = Stats:GetTotalMemoryUsageMb(),
		}
		table.insert(samples, row)
		local line = ("round %d: rigs %d, sockets %d, bots %d, balls %d, instances %d, memory %.0f MB"):format(
			#samples,
			row.rigs,
			row.sockets,
			row.bots,
			row.balls,
			row.inst,
			row.mem
		)
		table.insert(lines, line)
		print("[Soak] " .. line)
		Workspace:SetAttribute("RD_SoakResults", ("running: %d/%d rounds\n%s"):format(#samples, rounds, line))
	end
	local function checkStuck()
		local t = os.clock()
		for _, c in S.MatchService.roster() do
			local root = c.root :: BasePart?
			if c.status ~= "Active" or not root or not root.Parent then
				ragdollSince[c], lowSince[c] = nil, nil
				continue
			end
			local p = root.Position
			if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then
				table.insert(stuck, c.name .. " at a NaN position")
				continue
			end
			if c.action == "Ragdolled" then
				ragdollSince[c] = ragdollSince[c] or t
				if t - ragdollSince[c] > 10 then
					table.insert(stuck, ("%s ragdolled for 10 s on round %d"):format(c.name, #samples + 1))
					ragdollSince[c] = math.huge
				end
			else
				ragdollSince[c] = nil
			end
			if p.Y < ArenaLayout.SurfaceY - 30 then
				lowSince[c] = lowSince[c] or t
				if t - lowSince[c] > 3 then
					table.insert(stuck, ("%s below the court but not out on round %d"):format(c.name, #samples + 1))
					lowSince[c] = math.huge
				end
			else
				lowSince[c] = nil
			end
		end
	end
	S.BotService.setPaused(false)
	local lastState = ms:GetAttribute("State")
	local quietSince = os.clock()
	while #samples < rounds do
		task.wait(1)
		checkStuck()
		local state = ms:GetAttribute("State")
		if state == "RoundActive" then
			quietSince = os.clock()
		end
		if state ~= lastState and state == "RoundResolution" then
			sample()
		end
		lastState = state
		-- nothing has played for 3 minutes: matchmaking is stuck (or a menu is holding the player)
		if os.clock() - quietSince > 180 then
			table.insert(
				stuck,
				("no round went live for 3 minutes after round %d (state %s)"):format(#samples, tostring(state))
			)
			break
		end
	end
	errConn:Disconnect()
	-- verdict: no errors, nothing stuck, caps held, and no steady growth after a warm-up
	local problems: { string } = {}
	for _, row in samples do
		if row.sockets > row.rigs * 14 then
			table.insert(problems, ("%d sockets for %d rigs"):format(row.sockets, row.rigs))
			break
		end
	end
	for _, row in samples do
		if row.bots > Config.Bots.MaxPerServer + 1 then
			table.insert(problems, ("%d bot models"):format(row.bots))
			break
		end
	end
	local warm = samples[math.min(5, #samples)]
	local last = samples[#samples]
	if warm and last and #samples >= 10 then
		if last.inst > warm.inst * 1.15 then
			table.insert(problems, ("instances grew %d -> %d after warm-up"):format(warm.inst, last.inst))
		end
		if last.mem > warm.mem * 1.25 then
			table.insert(problems, ("memory grew %.0f -> %.0f MB after warm-up"):format(warm.mem, last.mem))
		end
	end
	for _, e in errors do
		table.insert(problems, "error: " .. e)
	end
	for _, st in stuck do
		table.insert(problems, "stuck: " .. st)
	end
	local verdict = if #problems == 0 and #samples >= rounds then "PASS" else "FAIL"
	local summary = ("%s: %d/%d rounds\n%s\n%s"):format(
		verdict,
		#samples,
		rounds,
		table.concat(problems, "\n"),
		table.concat(lines, "\n")
	)
	print("[Soak]\n" .. summary)
	Workspace:SetAttribute("RD_SoakResults", summary)
	running = false
end

function TestService.runAll()
	if running then
		return
	end
	running = true
	local ms = ReplicatedStorage:FindFirstChild("MatchState") :: Folder
	local results = {}
	-- start in a normal live round (not sudden death), then keep its timer from running out
	if
		not waitUntil(function()
			return ms:GetAttribute("State") == "RoundActive" and ms:GetAttribute("Overtime") ~= true
		end, 90)
	then
		running = false
		Workspace:SetAttribute("RD_TestResults", "SKIPPED: no live round (outside sudden death) within 90 s")
		return
	end
	S.MatchService.debugHoldClock(true)
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
	S.MatchService.debugHoldClock(false)
	local summary = ("%d/%d passed\n%s"):format(pass, #tests, table.concat(results, "\n"))
	print("[Tests]\n" .. summary)
	Workspace:SetAttribute("RD_TestResults", summary)
	running = false
end

return TestService
