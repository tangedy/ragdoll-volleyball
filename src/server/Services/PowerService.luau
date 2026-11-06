--!strict
-- Equippable powers (Config.Powers, PowerDefinitions). Every combatant in a match has one or two
-- powers: slot 1 (its active and its ultimate) and, with the Extra Power Slot pass, slot 2 (an active
-- only). Actives run on cooldowns; the ultimate needs a full meter, which fills from hits, catches,
-- knockouts, dodges and a slow trickle (Config.Powers.Meter) and resets every round. Players ask
-- with UsePower / UseUltimate; bots decide in tick(). Everything is decided here.
--
-- Player attributes for the HUD (PowerController): Powers ("Heavy" or "Heavy,Blink"), PowerReadyAt1,
-- PowerReadyAt2 (server-time timestamps), UltCharge (0..Meter.Max) and Frozen / Phantom flags.
--
-- Ball powers turn the held ball into a power ball type (BallDefinitions) — the same balls the old
-- dispensers dropped. An ultimate ball also carries ball.power = { ult, owner }: its effect fires on
-- impact (onImpact) or launch (onLaunch); dropping it or having it caught turns it back to Standard.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local NetSchema = require(Shared.NetSchema)
local ArenaLayout = require(Shared.ArenaLayout)
local PowerDefinitions = require(Shared.PowerDefinitions)

local PowerService = {}

local S: any
local PW = Config.Powers
local M = PW.Meter
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

function PowerService.init(services: any)
	S = services
end

local function setAttr(c: any, key: string, value: any)
	S.PlayerStateService.setAttr(c, key, value)
end

local function alive(c: any): boolean
	return S.PlayerStateService.isAlive(c)
end

local function ragdolled(c: any): boolean
	return c.character ~= nil and S.RagdollService.isRagdolled(c.character)
end

local function inLiveMatch(c: any): boolean
	return PW.Enabled and c.inMatch and c.status == "Active" and S.MatchService.isRoundLive()
end

local function tell(c: any, text: string)
	if c.player then
		S.NetService.send(c.player, "Hint", { text = text, duration = 1.2 })
	end
end

-- A bot's power: rolled once per bot by catalog rarity (Config.Powers.BotRarityWeights).
local function rollBotPower(): string
	local w = PW.BotRarityWeights
	local list, total = {}, 0
	for _, item in Catalog.inCategory("Power") do
		local weight = (w :: any)[Catalog.rarity(item)] or 0
		total += weight
		table.insert(list, { id = Catalog.powerOf(item) :: string, w = weight })
	end
	local roll = rng:NextNumber() * total
	for _, e in list do
		roll -= e.w
		if roll <= 0 then
			return e.id
		end
	end
	return list[1].id
end

-- The combatant's equipped power ids (slot 1 first).
function PowerService.powersOf(c: any): { string }
	if not c.powers then
		PowerService.reset(c)
	end
	return c.powers
end

local function publish(c: any)
	setAttr(c, "Powers", table.concat(c.powers or {}, ","))
	setAttr(c, "PowerReadyAt1", (c.powerReadyAt or {})[1] or 0)
	setAttr(c, "PowerReadyAt2", (c.powerReadyAt or {})[2] or 0)
	setAttr(c, "UltCharge", math.floor(c.ult or 0))
end

-- Fresh round (MatchService resetCombatant): re-read the equipped powers, empty the meter, clear
-- freezes and phantoms. Actives become ready RoundStartDelay after GO (roundStarted).
function PowerService.reset(c: any)
	PowerService.unfreeze(c)
	PowerService.endPhantom(c)
	if c.isBot then
		c.botPower = c.botPower or rollBotPower()
		c.powers = { c.botPower }
	elseif c.profile then
		c.powers = S.ShopService.equippedPowers(c)
	else
		c.powers = { Catalog.powerOf(Catalog.get(PW.Starter)) :: string }
	end
	c.powerReadyAt = { 0, 0 }
	c.ult = 0
	c.ultCastUntil = 0
	c.botUltAt = nil
	publish(c)
end

-- GO: every active comes off cooldown a moment after the round starts.
function PowerService.roundStarted(roster: { any })
	local t = now() + PW.RoundStartDelay
	for _, c in roster do
		PowerService.powersOf(c)
		c.powerReadyAt = { t, t }
		publish(c)
	end
end

-- Ultimate meter ---------------------------------------------------------------------------------

function PowerService.addMeter(c: any, amount: number)
	if not c or not PW.Enabled or not c.inMatch or not S.MatchService.isRoundLive() then
		return
	end
	if c.isDummy then
		return
	end
	local before = c.ult or 0
	c.ult = math.clamp(before + amount, 0, M.Max)
	if math.floor(c.ult) ~= math.floor(before) then
		setAttr(c, "UltCharge", math.floor(c.ult))
	end
	if before < M.Max and c.ult >= M.Max then
		if c.player then
			S.NetService.send(c.player, "PowerFx", { kind = "UltReady" })
		elseif c.isBot then
			local d = PW.BotUltDelay
			c.botUltAt = now() + rng:NextNumber(d[1], d[2])
		end
	end
end

-- CombatService hooks.
function PowerService.onHit(thrower: any?, target: any, damage: number)
	if thrower and thrower.team ~= target.team then
		PowerService.addMeter(thrower, M.Hit * math.clamp(damage / Config.Damage.PerHit, 0.75, 2))
	end
	PowerService.addMeter(target, M.GotHit)
end

function PowerService.onCatch(c: any)
	PowerService.addMeter(c, M.Catch)
end

function PowerService.onKnockout(c: any)
	PowerService.addMeter(c, M.Knockout)
end

function PowerService.onDodge(c: any)
	PowerService.addMeter(c, M.Dodge)
end

-- Freeze (Frost, Time Stop) ----------------------------------------------------------------------

local function restoreSpeed(c: any)
	local h = c.humanoid :: Humanoid?
	if not h or not S.MatchService.isRoundLive() then
		return
	end
	local scale = if c.phantomUntil and now() < c.phantomUntil then c.phantomSpeed or 1 else 1
	h.WalkSpeed = Config.Player.WalkSpeed * scale
	h.JumpPower = Config.Player.JumpPower
end

-- Encase `c` in ice for `duration`: no moving, throwing, dodging or catching. Frozen players are
-- still hittable (a hit shatters the ice and launches them as usual), so teammates can follow up.
function PowerService.freeze(c: any, duration: number)
	if not alive(c) or ragdolled(c) or c.status ~= "Active" then
		return
	end
	local root = c.root :: BasePart
	local t = now()
	c.frozenUntil = math.max(c.frozenUntil or 0, t + duration)
	local until_ = c.frozenUntil
	c.chargeStart = nil
	c.catchUntil = 0
	S.PlayerStateService.setAction(c, "Frozen")
	if c.humanoid then
		c.humanoid.WalkSpeed = 0
		c.humanoid.JumpPower = 0
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	if not c.iceBlock then
		local ice = Instance.new("Part")
		ice.Name = "PowerIce"
		ice.Size = Vector3.new(4.6, 6.4, 4.6)
		ice.Material = Enum.Material.Ice
		ice.Color = Color3.fromRGB(170, 230, 255)
		ice.Transparency = 0.35
		ice.Anchored = true
		ice.CanCollide = false
		ice.CanQuery = false
		ice.CanTouch = false
		ice.CastShadow = false
		ice.CFrame = root.CFrame * CFrame.new(0, -0.3, 0)
		ice.Parent = c.character
		c.iceBlock = ice
	end
	setAttr(c, "Frozen", true)
	task.delay(duration, function()
		if c.frozenUntil == until_ then
			PowerService.unfreeze(c)
		end
	end)
end

function PowerService.unfreeze(c: any)
	if not c.frozenUntil then
		return
	end
	c.frozenUntil = nil
	if c.iceBlock then
		c.iceBlock:Destroy()
		c.iceBlock = nil
	end
	if c.root and c.root.Parent then
		c.root.Anchored = false
	end
	setAttr(c, "Frozen", false)
	if c.action == "Frozen" then
		S.PlayerStateService.setAction(c, "Idle")
	end
	restoreSpeed(c)
	if c.root then
		S.NetService.broadcast("PowerFx", { kind = "Shatter", position = c.root.Position })
	end
end

-- How long a Frost ball's hit freezes (PowerDefinitions Frost.FreezeTime).
function PowerService.freezeTime(): number
	return (PowerDefinitions.get("Frost") :: any).FreezeTime
end

function PowerService.isFrozen(c: any): boolean
	return c.frozenUntil ~= nil
end

-- Phantom (Blink's ultimate) ---------------------------------------------------------------------

function PowerService.endPhantom(c: any)
	if not c.phantomUntil then
		return
	end
	c.phantomUntil = nil
	if c.phantomFx then
		c.phantomFx:Destroy()
		c.phantomFx = nil
	end
	setAttr(c, "Phantom", false)
	if not c.frozenUntil then
		restoreSpeed(c)
	end
end

local function startPhantom(c: any, ult: any)
	local t = now()
	c.phantomUntil = t + ult.Duration
	c.phantomSpeed = ult.SpeedScale
	c.immuneUntil = math.max(c.immuneUntil, c.phantomUntil)
	local until_ = c.phantomUntil
	if c.character and not c.phantomFx then
		local h = Instance.new("Highlight")
		h.Name = "PowerPhantom"
		h.FillColor = Color3.fromRGB(200, 255, 240)
		h.FillTransparency = 0.45
		h.OutlineColor = Color3.fromRGB(120, 255, 200)
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = c.character
		c.phantomFx = h
	end
	setAttr(c, "Phantom", true)
	restoreSpeed(c)
	task.delay(ult.Duration, function()
		if c.phantomUntil == until_ then
			PowerService.endPhantom(c)
		end
	end)
end

-- Court helpers ----------------------------------------------------------------------------------

-- The nearest point to `pos` on c's own half, `margin` studs in from the edges and the centre line.
local function clampToHalf(c: any, pos: Vector3, margin: number): Vector3
	local o = Config.Arena.Origin
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps()) - margin
	local sign = ArenaLayout.teamSign(c.team)
	local rel = pos - o
	local x = math.clamp(rel.X, -hw, hw)
	local z = sign * math.clamp(rel.Z * sign, margin, ArenaLayout.HalfLength - margin)
	return Vector3.new(o.X + x, pos.Y, o.Z + z)
end

local function enemiesOf(c: any): { any }
	local list = {}
	for _, e in S.MatchService.roster() do
		if e.inMatch and e.status == "Active" and e.team and e.team ~= c.team and alive(e) then
			table.insert(list, e)
		end
	end
	return list
end

-- Knock every enemy of `owner` within `radius` of `pos` (but `skip`) away (`upward` for straight up)
-- with an area hit (CombatService.areaHit).
local function blast(
	owner: any,
	pos: Vector3,
	radius: number,
	damage: number,
	ballType: string,
	upward: boolean,
	skip: any?
)
	for _, e in enemiesOf(owner) do
		if e ~= skip and e.root then
			local to = e.root.Position - pos
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude <= radius and math.abs(to.Y) < radius then
				local dir = if upward
					then Vector3.new(flat.X * 0.15, 0, flat.Z * 0.15) + Vector3.yAxis * 0.01
					elseif flat.Magnitude > 0.5 then flat.Unit
					else Vector3.zAxis
				S.CombatService.areaHit(owner, e, pos, dir, damage, ballType)
			end
		end
	end
end

-- Actives ----------------------------------------------------------------------------------------

local function useBall(c: any, def: any): (boolean, string?)
	local ball = c.heldBall
	if not ball or ball.context ~= "Match" then
		return false, "Grab a ball first!"
	end
	if ball.power then
		return false, "Your ball is already powered up"
	end
	S.BallService.setType(ball, def.Ball)
	setAttr(c, "HeldBall", def.Ball)
	return true, nil
end

local function useBlink(c: any, def: any, dir: Vector3?): (boolean, string?)
	local root = c.root :: BasePart
	local look = root.CFrame.LookVector
	local d = dir or Vector3.new(look.X, 0, look.Z)
	if d.Magnitude < 0.1 then
		d = Vector3.zAxis
	end
	local from = root.Position
	local to = clampToHalf(c, from + d.Unit * def.Distance, 3)
	local character = c.character :: Model
	character:PivotTo(CFrame.new(to) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	c.immuneUntil = math.max(c.immuneUntil, now() + def.Immunity)
	S.NetService.broadcast("PowerFx", { kind = "Blink", from = from, to = to })
	return true, nil
end

local function useMagnet(c: any, def: any): (boolean, string?)
	if c.heldBall then
		return false, "Your hands are full"
	end
	if c.action ~= "Idle" and c.action ~= "Dodging" and c.action ~= "Recovering" then
		return false, nil
	end
	local root = c.root :: BasePart
	local best, bestD = nil, def.Range
	for _, ball in S.BallService.all() do
		if ball.context == "Match" and (ball.state == "Resting" or ball.state == "Spent") and not ball.holder then
			local pos = ball.part.Position
			local d = (pos - root.Position).Magnitude
			if d < bestD and ArenaLayout.onHalf(c.team, pos, 0, -2) then
				best, bestD = ball, d
			end
		end
	end
	if not best then
		return false, "No loose ball on your side"
	end
	local from = best.part.Position
	S.BallService.give(best, c)
	S.CombatService.onPickup(c, best)
	S.NetService.broadcast("PowerFx", { kind = "Magnet", from = from, to = root.Position })
	return true, nil
end

-- Use slot `slot`'s active. `dir` is the move direction (Blink). Returns whether it fired.
function PowerService.use(c: any, slot: number, dir: Vector3?): boolean
	if not inLiveMatch(c) or not alive(c) or ragdolled(c) or c.frozenUntil then
		return false
	end
	if c.action == "Casting" then
		return false
	end
	local id = PowerService.powersOf(c)[slot]
	local def = PowerDefinitions.get(id)
	if not def then
		return false
	end
	local t = now()
	if t < (c.powerReadyAt[slot] or 0) then
		return false
	end
	local ok, why
	if def.Kind == "Ball" then
		ok, why = useBall(c, def)
	elseif def.Id == "Blink" then
		ok, why = useBlink(c, def, dir)
	elseif def.Id == "Magnet" then
		ok, why = useMagnet(c, def)
	end
	if not ok then
		if why then
			tell(c, why)
		end
		return false
	end
	c.powerReadyAt[slot] = t + def.Cooldown
	setAttr(c, "PowerReadyAt" .. slot, c.powerReadyAt[slot])
	S.NetService.broadcast("PowerFx", {
		kind = "Active",
		power = def.Id,
		caster = c.character,
		position = c.root and c.root.Position,
	})
	S.AnalyticsService.event(c, "PowerUse_" .. def.Id)
	return true
end

-- Ultimates --------------------------------------------------------------------------------------

local function stormBalls(c: any, ult: any)
	local o = Config.Arena.Origin
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps()) - 6
	local sign = ArenaLayout.teamSign(c.team)
	for i = 1, ult.Count do
		task.delay((i - 1) * 0.12, function()
			if not S.MatchService.isRoundLive() then
				return
			end
			local x = rng:NextNumber(-hw, hw)
			local z = sign * rng:NextNumber(8, ArenaLayout.HalfLength - 8)
			local ball = S.BallService.spawn("Standard", Vector3.new(o.X + x, o.Y + 28, o.Z + z), "Match", true)
			ball.temporary = true
			ball.expiresAt = now() + PW.ExtraBallLife + 3
		end)
	end
end

-- After the wind-up: the self ultimates take effect (the ball ones powered the ball at once).
local function ultEffect(c: any, def: any)
	local ult = def.Ult
	if not inLiveMatch(c) or not alive(c) then
		return
	end
	if ult.Id == "Phantom" then
		startPhantom(c, ult)
	elseif ult.Id == "BallStorm" then
		stormBalls(c, ult)
	elseif ult.Id == "TimeStop" then
		for _, e in enemiesOf(c) do
			if not e.phantomUntil then -- a phantom is out of time's reach
				PowerService.freeze(e, ult.Duration)
			end
		end
	end
	S.NetService.broadcast("PowerFx", { kind = "UltEffect", ult = ult.Id, caster = c.character, team = c.team })
end

function PowerService.useUltimate(c: any): boolean
	if not inLiveMatch(c) or not alive(c) or ragdolled(c) or c.frozenUntil then
		return false
	end
	if (c.ult or 0) < M.Max then
		return false
	end
	if c.action ~= "Idle" and c.action ~= "Charging" and c.action ~= "Recovering" then
		return false
	end
	local def = PowerDefinitions.get(PowerService.powersOf(c)[1])
	if not def then
		return false
	end
	local ult = def.Ult
	if ult.NeedsBall then
		local ball = c.heldBall
		if not ball or ball.context ~= "Match" then
			tell(c, "Grab a ball first!")
			return false
		end
		ball.power = { ult = ult.Id, owner = c }
		local ballType = if ult.Id == "Meteor" then "Meteor" elseif ult.Id == "Geyser" then "Pop" else "Rocket"
		S.BallService.setType(ball, ballType)
		setAttr(c, "HeldBall", ballType)
	end
	local t = now()
	c.ult = 0
	setAttr(c, "UltCharge", 0)
	c.botUltAt = nil
	c.chargeStart = nil
	-- the wind-up: untouchable and still for a beat while the camera pushes in
	c.ultCastUntil = t + PW.UltWindup
	c.immuneUntil = math.max(c.immuneUntil, t + PW.UltWindup)
	S.PlayerStateService.setAction(c, "Casting", PW.UltWindup)
	S.NetService.broadcast("PowerFx", {
		kind = "Ult",
		ult = ult.Id,
		name = ult.Name,
		power = def.Id,
		caster = c.character,
		casterPlayer = c.player,
		casterName = c.name,
		team = c.team,
		windup = PW.UltWindup,
	})
	S.MatchService.feed(("%s ⚡ used <b>%s</b>!"):format(S.MatchService.tag(c), ult.Name))
	S.AnalyticsService.event(c, "UltUse_" .. ult.Id)
	if not ult.NeedsBall then
		task.delay(PW.UltWindup, ultEffect, c, def)
	end
	return true
end

-- Ultimate balls -----------------------------------------------------------------------------------

-- Called right after `ball` was thrown by `c` (CombatService.doThrow). Barrage splits off extra
-- homing rockets, one at each other enemy.
function PowerService.onLaunch(c: any, ball: any)
	local power = ball.power
	if not power or power.ult ~= "Barrage" then
		return
	end
	local ult = (PowerDefinitions.get("Rocket") :: any).Ult
	local main = ball.homing
	S.BallService.boostHoming(ball, ult.TurnDegPerSec, ult.MaxTurnDeg, main)
	local others = {}
	for _, e in enemiesOf(c) do
		if e ~= main then
			table.insert(others, e)
		end
	end
	local speed = ball.vel.Magnitude
	for i = 1, ult.Extra do
		local target = others[i]
		local spread = CFrame.Angles(0, math.rad(if i % 2 == 1 then 18 else -18) * math.ceil(i / 2), 0)
		local vel = spread:VectorToWorldSpace(ball.vel)
		if target and target.root then
			local to = target.root.Position - ball.pos
			vel = (to.Unit + Vector3.new(0, 0.12, 0)).Unit * speed
		end
		local extra = S.BallService.fireExtra(c, "Rocket", vel)
		if extra then
			S.BallService.boostHoming(extra, ult.TurnDegPerSec, ult.MaxTurnDeg, target)
		end
	end
	ball.power = nil -- the main rocket is a normal (strongly homing) rocket from here
end

-- An ultimate ball landed: on a target (`target`) or on the court / scenery (nil). The ball's own
-- hit has already been applied; this adds the area effect.
function PowerService.onImpact(power: any, pos: Vector3, target: any?)
	local owner = power.owner
	if not owner or not owner.team then
		return
	end
	if power.ult == "Meteor" then
		local ult = (PowerDefinitions.get("Heavy") :: any).Ult
		blast(owner, pos, ult.ShockRadius, ult.ShockDamage, "Heavy", false, target)
		S.NetService.broadcast("PowerFx", { kind = "Shockwave", position = pos, radius = ult.ShockRadius })
	elseif power.ult == "Geyser" then
		local ult = (PowerDefinitions.get("Pop") :: any).Ult
		blast(owner, pos, ult.Radius, ult.Damage, "Pop", true, target)
		S.NetService.broadcast("PowerFx", { kind = "Geyser", position = pos, radius = ult.Radius })
	end
end

-- Bots -------------------------------------------------------------------------------------------

local function incomingBall(c: any): any?
	local root = c.root
	if not root then
		return nil
	end
	for _, ball in S.BallService.all() do
		if ball.state == "InFlight" and ball.context == "Match" and ball.lastTeam ~= c.team then
			local to = root.Position - ball.pos
			if to.Magnitude < 24 and ball.vel:Dot(to) > 0 then
				return ball
			end
		end
	end
	return nil
end

local function botThink(c: any, t: number)
	if not inLiveMatch(c) or not alive(c) or ragdolled(c) or c.frozenUntil then
		return
	end
	local id = PowerService.powersOf(c)[1]
	local def = PowerDefinitions.get(id)
	if not def then
		return
	end
	if c.botUltAt and t >= c.botUltAt and (c.ult or 0) >= M.Max then
		if not def.Ult.NeedsBall or c.heldBall then
			PowerService.useUltimate(c)
			return
		end
	end
	if t < (c.powerReadyAt[1] or 0) or rng:NextNumber() > PW.BotUseChance then
		return
	end
	if def.Kind == "Ball" then
		if c.heldBall and not c.heldBall.power and c.heldBall.type == "Standard" then
			PowerService.use(c, 1)
		end
	elseif def.Id == "Blink" then
		local ball = incomingBall(c)
		if ball then
			local side = ball.vel:Cross(Vector3.yAxis)
			PowerService.use(c, 1, if rng:NextNumber() < 0.5 then side else -side)
		end
	elseif def.Id == "Magnet" then
		if not c.heldBall then
			PowerService.use(c, 1)
		end
	end
end

-- Every 0.25 s: the meter's trickle, bot decisions, and extra balls that have lain around too long.
function PowerService.tick(dt: number)
	local t = now()
	if S.MatchService.isRoundLive() then
		for _, c in S.MatchService.roster() do
			if c.inMatch and c.status == "Active" then
				if not c.powers then
					PowerService.reset(c)
				end
				PowerService.addMeter(c, M.Passive * dt)
				if c.isBot then
					botThink(c, t)
				end
			end
		end
	end
	for _, ball in S.BallService.all() do
		if
			ball.temporary
			and ball.expiresAt
			and t >= ball.expiresAt
			and (ball.state == "Resting" or ball.state == "Spent")
			and not ball.holder
		then
			S.NetService.broadcast("PowerFx", { kind = "Poof", position = ball.part.Position })
			S.BallService.destroy(ball)
		end
	end
end

function PowerService.start()
	local PS = S.PlayerStateService
	S.NetService.on(NetSchema.Actions.UsePower, function(player, p)
		local c = PS.get(player)
		if c then
			if p.slot == 2 and #PowerService.powersOf(c) < 2 then
				return
			end
			PowerService.use(c, p.slot, p.dir)
		end
	end)
	S.NetService.on(NetSchema.Actions.UseUltimate, function(player, _p)
		local c = PS.get(player)
		if c then
			PowerService.useUltimate(c)
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local n = os.clock()
			PowerService.tick(n - last)
			last = n
		end
	end)
end

return PowerService
