--!strict
-- Server-authoritative combat rules (spec §7): pickup eligibility, charge/throw, dodge, catch,
-- hit resolution and knockback. Players and bots both enter through the do* functions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ProjectileMath = require(Shared.ProjectileMath)
local ArenaLayout = require(Shared.ArenaLayout)
local DodgeMotion = require(Shared.DodgeMotion)
local NetSchema = require(Shared.NetSchema)

local CombatService = {}

local S: any
local P = Config.Player
local A = NetSchema.Actions

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function alive(c: any): boolean
	return S.PlayerStateService.isAlive(c)
end

local function ragdolled(c: any): boolean
	return c.character ~= nil and S.RagdollService.isRagdolled(c.character)
end

local function send(c: any, kind: string, data: any)
	if c.player then
		S.NetService.send(c.player, kind, data)
	end
end

function CombatService.init(services: any)
	S = services
end

function CombatService.start()
	local PS = S.PlayerStateService
	S.NetService.on(A.ChargeStart, function(player, _p)
		local c = PS.get(player)
		if c then
			CombatService.doChargeStart(c)
		end
	end)
	S.NetService.on(A.Throw, function(player, p)
		local c = PS.get(player)
		if c then
			CombatService.doThrow(c, p.dir, p.throwId)
		end
	end)
	S.NetService.on(A.CancelAim, function(player, _p)
		local c = PS.get(player)
		if c and c.action == "Charging" then
			c.chargeStart = nil
			PS.setAction(c, "Idle")
		end
	end)
	S.NetService.on(A.Dodge, function(player, p)
		local c = PS.get(player)
		if c then
			CombatService.doDodge(c, p.dir)
		end
	end)
	S.NetService.on(A.Catch, function(player, _p)
		local c = PS.get(player)
		if c then
			CombatService.doCatch(c)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			CombatService.possessionTick()
		end
	end)
end

-- Context in which a combatant may act: "Match", "Lobby" or nil.
function CombatService.contextOf(c: any): string?
	if c.inMatch and (c.status == "Active" or c.status == "Jailed") and S.MatchService.isRoundLive() then
		return "Match"
	end
	if c.status == "Lobby" and not c.inMatch then
		return "Lobby"
	end
	return nil
end

function CombatService.canPickup(c: any, ball: any, pos: Vector3): boolean
	if not alive(c) or ragdolled(c) then
		return false
	end
	if c.pickupBlockedUntil and now() < c.pickupBlockedUntil then
		return false
	end
	-- free hands are all that matter: walking (or dodging, or just after a throw) over a ball grabs it
	if c.action ~= "Idle" and c.action ~= "Dodging" and c.action ~= "Recovering" then
		return false
	end
	local ctx = CombatService.contextOf(c)
	if ctx ~= ball.context then
		return false
	end
	if ctx == "Match" then
		if c.status == "Active" then
			return ArenaLayout.onHalf(c.team, pos, 0, -2)
		elseif c.status == "Jailed" then
			return ArenaLayout.inJail(c.team, pos)
		end
		return false
	end
	return true
end

function CombatService.onPickup(c: any, _ball: any)
	S.AnalyticsService.funnel(c, "PickedUpFirstBall")
	S.TutorialService.onEvent(c, "Pickup")
end

-- Valid targets for an in-flight ball: active, non-immune enemies of the thrower's team.
-- Teammates are never included, so they cannot block their own team's shots.
function CombatService.targetsFor(ball: any): { any }
	local list = {}
	local t = now()
	if ball.context == "Lobby" then
		for _, c in S.PlayerStateService.all() do
			if c.isDummy and alive(c) and t >= c.immuneUntil then
				table.insert(list, c)
			end
		end
		return list
	end
	if not S.MatchService.isRoundLive() then
		return list
	end
	for _, c in S.PlayerStateService.all() do
		if
			c.inMatch
			and c.status == "Active"
			and c.team ~= nil
			and c.team ~= ball.lastTeam
			and alive(c)
			and t >= c.immuneUntil
		then
			table.insert(list, c)
		end
	end
	return list
end

local function catchGeometryOk(catcher: any, ball: any, at: Vector3): boolean
	local root = catcher.root
	if not root then
		return false
	end
	local incoming = -ball.vel
	if incoming.Magnitude < 1e-3 then
		return false
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatIn = Vector3.new(incoming.X, 0, incoming.Z)
	if flatLook.Magnitude < 1e-3 or flatIn.Magnitude < 1e-3 then
		return false
	end
	-- the ball must be coming at the catcher's front, and be in front of them
	local toBall = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
	local cone = math.cos(math.rad(P.CatchConeDeg))
	local facing = flatLook.Unit:Dot(flatIn.Unit) >= cone
	local inFront = toBall.Magnitude < 1 or flatLook.Unit:Dot(toBall.Unit) >= 0
	return facing and inFront
end

local function isCatching(c: any): boolean
	return c.action == "Catching" and now() <= c.catchUntil
end

-- Find a catching enemy whose catch radius the segment passes through. Returns (catcher, point).
function CombatService.findCatcher(ball: any, from: Vector3, to: Vector3): (any?, Vector3)
	if ball.context ~= "Match" or not S.MatchService.isRoundLive() then
		return nil, to
	end
	local seg = to - from
	local lenSq = math.max(seg:Dot(seg), 1e-6)
	local best, bestT, bestPoint = nil, math.huge, to
	for _, c in S.PlayerStateService.all() do
		if c.inMatch and c.status == "Active" and c.team ~= ball.lastTeam and isCatching(c) and c.root then
			local rp = c.root.Position
			local t = math.clamp((rp - from):Dot(seg) / lenSq, 0, 1)
			local point = from + seg * t
			if (point - rp).Magnitude <= P.CatchRadius and t < bestT and catchGeometryOk(c, ball, point) then
				best, bestT, bestPoint = c, t, point
			end
		end
	end
	return best, bestPoint
end

function CombatService.resolveCatch(ball: any, catcher: any)
	local thrower = ball.lastThrower
	S.PlayerStateService.setAction(catcher, "Idle")
	catcher.catchUntil = 0
	S.BallService.give(ball, catcher) -- a catch preserves the ball's type
	if thrower and thrower.isBot then
		catcher.stats.botCatches += 1
	else
		catcher.stats.catches += 1
	end
	send(
		catcher,
		"Banner",
		{ text = "YOU CAUGHT IT!", color = Color3.fromRGB(120, 255, 140), duration = 1.2, sound = "Catch" }
	)
	S.NetService.broadcast("Feed", {
		text = ("%s 🧤 caught %s's throw!"):format(
			S.MatchService.tag(catcher),
			if thrower then S.MatchService.tag(thrower) else "a"
		),
	})
	S.NetService.broadcast("Impact", { kind = "Catch", position = catcher.root and catcher.root.Position })
	S.AnalyticsService.event(catcher, "CatchSuccess")
	S.TutorialService.onEvent(catcher, "Catch")
end

function CombatService.resolveContact(ball: any, target: any, pos: Vector3)
	if isCatching(target) and catchGeometryOk(target, ball, pos) then
		CombatService.resolveCatch(ball, target)
		return
	end
	CombatService.applyHit(ball, target, pos)
end

local function uprightPoint(c: any): Vector3?
	local root = c.root
	if not root then
		return nil
	end
	local pos = root.Position
	if c.isDummy or c.status == "Lobby" then
		if pos.Y > ArenaLayout.LobbyVoidY + 20 then
			return Vector3.new(pos.X, Config.Arena.LobbyOrigin.Y + 3, pos.Z)
		end
		return nil
	end
	if c.status ~= "Active" then
		return pos
	end
	-- Recover on the court if the body is over this team's half and not clearly falling.
	local over = ArenaLayout.onHalf(
		c.team,
		Vector3.new(pos.X, Config.Arena.Origin.Y, pos.Z),
		S.ArenaService.getOvertimeSteps(),
		-0.5
	)
	if over and pos.Y > ArenaLayout.SurfaceY - 4 then
		local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps()) - 1.5
		local sign = ArenaLayout.teamSign(c.team)
		local rel = pos - Config.Arena.Origin
		local x = math.clamp(rel.X, -hw, hw)
		local z = sign * math.clamp(rel.Z * sign, 1.5, ArenaLayout.HalfLength - 1.5)
		return Config.Arena.Origin + Vector3.new(x, 3, z)
	end
	return nil -- falling: never rescue a legitimate void fall
end

local function scheduleRecovery(c: any, duration: number?)
	local token = c.actionToken
	task.delay(duration or P.RagdollDuration, function()
		local tries = 0
		while c.actionToken == token and c.action == "Ragdolled" and alive(c) do
			local point = uprightPoint(c)
			if point then
				S.RagdollService.recover(c.character, point)
				S.PlayerStateService.setAction(c, "Idle")
				c.recoveredAt = now() -- bots single out players who just got up
				S.AnalyticsService.hitResolved(c, "Recovered")
				return
			end
			tries += 1
			if tries > 15 then
				-- off the court but not below the void plane yet: keep ragdolled; elimination decides
				if c.status ~= "Active" then
					S.RagdollService.recover(c.character, nil)
					S.PlayerStateService.setAction(c, "Idle")
				end
				return
			end
			task.wait(0.2)
		end
	end)
end

function CombatService.applyHit(ball: any, target: any, pos: Vector3)
	local thrower = ball.lastThrower
	local t = now()
	-- every hit launches harder than the last; a throw from jail lands at the current level
	local scale = ProjectileMath.escalation(target.hitsTaken)
	local kb = ProjectileMath.knockback(ball.vel, ball.charge, ball.type, scale)
	local ragdollTime = ProjectileMath.ragdollDuration(scale)
	local ballType = ball.type
	S.BallService.spend(ball, pos, -ball.vel * 0.12 + Vector3.new(0, 14, 0))
	if t < target.immuneUntil then
		return -- repeated hits during immunity add no force and do not extend the ragdoll
	end
	if not (thrower and thrower.status == "Jailed") then
		target.hitsTaken += 1
	end
	-- cancel current action; getting hit while charging drops the ball
	target.chargeStart = nil
	target.catchUntil = 0
	if target.heldBall then
		S.BallService.drop(target)
	end
	S.PlayerStateService.setAction(target, "Ragdolled")
	target.immuneUntil = t + ragdollTime + P.PostHitImmunity
	if target.character then
		S.RagdollService.ragdoll(target.character, kb, ProjectileMath.maxKnockbackSpeed(scale))
	end
	scheduleRecovery(target, ragdollTime)

	if thrower and thrower.team ~= target.team then
		target.lastHitBy = thrower
		target.lastHitAt = t
	end
	S.NetService.broadcast("Impact", {
		kind = "Hit",
		ballType = ballType,
		position = pos,
		direction = ball.vel,
		target = target.player,
		targetModel = target.character, -- clients flash this character white
		thrower = thrower and thrower.player,
		charge = ball.charge,
		escalation = scale,
	})
	if thrower then
		send(thrower, "Hint", { text = "HIT!", duration = 0.6 })
		if target.isDummy then
			S.TutorialService.onEvent(thrower, "HitDummy")
			S.AnalyticsService.funnel(thrower, "LandedFirstHit")
			return
		end
		if target.isBot then
			thrower.stats.botHits += 1
		else
			thrower.stats.hits += 1
		end
		S.AnalyticsService.funnel(thrower, "LandedFirstHit")
		S.TutorialService.onEvent(thrower, "Hit")
		S.MatchService.recordHit(thrower, target)
		if target.inMatch and target.team and target.root then
			local rel = target.root.Position - Config.Arena.Origin
			local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps())
			local depth = rel.Z * ArenaLayout.teamSign(target.team)
			local edge = math.min(hw - math.abs(rel.X), ArenaLayout.HalfLength - depth)
			S.AnalyticsService.hitStarted(target, thrower, edge, ballType)
		end
		if thrower.status == "Jailed" and target.status == "Active" then
			S.MatchService.onJailHit(thrower, target)
		end
	end
end

-- Studio dev key (F10): fling a combatant exactly like a real hit coming from behind them.
function CombatService.debugLaunch(c: any, charge: number)
	if not c.character or not c.root or ragdolled(c) then
		return
	end
	local look = c.root.CFrame.LookVector
	local kb = ProjectileMath.knockback(look * 100, charge, "Standard")
	if c.heldBall then
		S.BallService.drop(c)
	end
	S.PlayerStateService.setAction(c, "Ragdolled")
	c.immuneUntil = now() + P.RagdollDuration + P.PostHitImmunity
	S.RagdollService.ragdoll(c.character, kb)
	S.NetService.broadcast("Impact", {
		kind = "Hit",
		ballType = "Standard",
		position = c.root.Position,
		direction = look,
		targetModel = c.character,
		target = c.player,
	})
	scheduleRecovery(c)
end

-- Actions ------------------------------------------------------------------------------------------

function CombatService.doChargeStart(c: any)
	if not c.heldBall or c.action ~= "Idle" or ragdolled(c) then
		return
	end
	if CombatService.contextOf(c) ~= c.heldBall.context then
		return
	end
	c.chargeStart = now() -- the server records charge start; clients never submit power
	S.PlayerStateService.setAction(c, "Charging")
end

function CombatService.doThrow(c: any, dir: Vector3, throwId: number): boolean
	local ball = c.heldBall
	local ok = ball ~= nil
		and (c.action == "Charging" or c.action == "Idle")
		and not ragdolled(c)
		and alive(c)
		and CombatService.contextOf(c) == ball.context
	if not ok then
		send(c, "ThrowResult", { throwId = throwId, ok = false })
		return false
	end
	local charge = 1 -- every throw is full power: tap to fire, no charging
	c.chargeStart = nil
	local speed = ProjectileMath.throwSpeed(charge, ball.type)
	S.BallService.launch(c, dir * speed, charge, throwId)
	S.PlayerStateService.setAction(c, "Recovering", P.ThrowRecovery)
	c.stats.throws += 1
	send(c, "ThrowResult", { throwId = throwId, ok = true })
	S.AnalyticsService.funnel(c, "ThrewFirstBall")
	S.TutorialService.onEvent(c, "Throw")
	return true
end

function CombatService.doDodge(c: any, dir: Vector3): boolean
	local t = now()
	if t < c.dodgeReadyAt or ragdolled(c) or not alive(c) then
		return false
	end
	if c.action ~= "Idle" and c.action ~= "Charging" then
		return false -- not while catching, ragdolled or in throw recovery
	end
	if not (c.status == "Active" or c.status == "Lobby" or c.status == "Jailed") then
		return false
	end
	if S.MatchService.isFrozen(c) then
		return false
	end
	c.dodgeReadyAt = t + P.DodgeCooldown
	S.PlayerStateService.setAttr(c, "DodgeReadyAt", c.dodgeReadyAt)
	if c.action == "Charging" then
		c.chargeStart = nil
	end
	S.PlayerStateService.setAction(c, "Dodging", P.DodgeDuration)
	c.stats.dodges += 1
	if c.player then
		S.NetService.send(c.player, "DodgeAccepted", { dir = dir })
	elseif c.character then
		DodgeMotion.apply(c.character, dir)
	end
	return true
end

function CombatService.doCatch(c: any): boolean
	local t = now()
	if c.heldBall or t < c.catchReadyAt or ragdolled(c) or not alive(c) then
		return false
	end
	if c.action ~= "Idle" and c.action ~= "Dodging" then
		return false
	end
	if c.status ~= "Active" and c.status ~= "Lobby" then
		return false -- jailed players cannot catch
	end
	c.catchReadyAt = t + P.CatchCooldown
	c.catchUntil = t + P.CatchWindow
	S.PlayerStateService.setAttr(c, "CatchReadyAt", c.catchReadyAt)
	S.PlayerStateService.setAction(c, "Catching", P.CatchWindow)
	S.AnalyticsService.event(c, "CatchAttempt")
	return true
end

-- After 8 s holding a ball, warn; after 12 s, force a drop (spec §16).
function CombatService.possessionTick()
	if not S.MatchService.isRoundLive() then
		return
	end
	local t = now()
	for _, c in S.PlayerStateService.all() do
		local ball = c.heldBall
		if ball and ball.context == "Match" then
			local held = t - c.heldSince
			if held >= P.PossessionForceDrop then
				S.BallService.drop(c)
				c.pickupBlockedUntil = t + P.ForceDropPickupBlock
				if c.action == "Charging" then
					S.PlayerStateService.setAction(c, "Idle")
				end
				send(c, "Possession", { dropped = true })
			elseif held >= P.PossessionWarn and not c.possessionWarned then
				c.possessionWarned = true
				send(c, "Possession", { warn = true, remaining = P.PossessionForceDrop - held })
			end
		end
	end
end

return CombatService
