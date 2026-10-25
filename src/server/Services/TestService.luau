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

test("catch window catches an incoming throw (catch before hit)", function()
	local catcher = bots("Red")[1]
	local thrower = bots("Blue")[1]
	ready(catcher, point("Red", 10, 12))
	ready(thrower, point("Blue", 10, 12))
	task.wait(0.3)
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
		return bot.heldBall == nil
	end, 0.6), "ball not dropped")
	assertTrue(ball.holder == nil, "ball still has holder")
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

test("pts: highest win tier only; 50 for playing on the losing team", function()
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
	local P = Config.Pts
	local function check(c: any, want: number, label: string)
		local got = S.RewardService.pts(c, ctx)
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
	assertTrue(S.RewardService.pts(killer, abortCtx) == 0, "aborted match paid pts")
end)

test("daily reward: pays once per UTC day, ladder advances, missed day resets", function()
	local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
	local c: any = {
		profileLoaded = true,
		profile = { Pts = 0, LoginStreak = { day = 3, lastDate = yesterday, claimedDate = yesterday } },
	}
	local ladder = Config.DailyRewards.Ladder
	assertTrue(S.ShopService.claimDaily(c), "first claim refused")
	assertTrue(c.profile.LoginStreak.day == 4 and c.profile.Pts == ladder[4], "did not advance to day 4")
	assertTrue(not S.ShopService.claimDaily(c), "second claim the same day paid")
	assertTrue(c.profile.Pts == ladder[4], "pts changed on a refused claim")
	c.profile.LoginStreak = { day = 5, lastDate = "2000-01-01", claimedDate = "2000-01-01" }
	S.ShopService.claimDaily(c)
	assertTrue(c.profile.LoginStreak.day == 1, "missed day did not reset the ladder")
	c.profile.LoginStreak = { day = 7, lastDate = yesterday, claimedDate = yesterday }
	S.ShopService.claimDaily(c)
	assertTrue(c.profile.LoginStreak.day == 1, "day 7 did not wrap to day 1")
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
	assertTrue(waitUntil(function()
		return ms:GetAttribute("State") == "Intermission" or ms:GetAttribute("MatchId") ~= matchId
	end, 15), "match did not end after the finisher")
end)

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
