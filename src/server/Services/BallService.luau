--!strict
-- Ball lifecycle (spec §8): Resting -> Held -> InFlight -> Spent -> Resting, with Caught -> Held and
-- Resetting from any state. In-flight balls are simulated on the server with a fixed step and swept
-- sphere casts between positions; Touched is never used for hits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local BallDefinitions = require(Shared.BallDefinitions)
local ProjectileMath = require(Shared.ProjectileMath)
local ArenaLayout = require(Shared.ArenaLayout)

export type Ball = {
	id: number,
	part: Part,
	type: string,
	isPower: boolean,
	state: string,
	context: string, -- "Match" | "Lobby"
	holder: any?,
	weld: WeldConstraint?,
	lastThrower: any?,
	lastTeam: string?,
	stateAt: number,
	lockoutUntil: number,
	throwerLockoutUntil: number,
	pos: Vector3,
	vel: Vector3,
	charge: number,
	throwId: number,
	flightT: number,
	hasHit: boolean,
}

local BallService = {}

local S: any
local balls: { [number]: Ball } = {}
local nextId = 0
local accumulator = 0
local folder: Folder
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setState(ball: Ball, state: string)
	ball.state = state
	ball.stateAt = now()
	ball.part:SetAttribute(Types.Attr.BallState, state)
end

local function applyLook(ball: Ball)
	local def = BallDefinitions.get(ball.type)
	local part = ball.part
	local r = ProjectileMath.radius(ball.type)
	part.Size = Vector3.one * r * 2
	part.Color = def.Color
	part.Material = def.Material
	part:SetAttribute(Types.Attr.BallType, ball.type)
	local trail = part:FindFirstChild("Trail") :: Trail?
	if trail then
		trail.Enabled = def.Trail
		trail.Color = ColorSequence.new(def.Color)
	end
	local light = part:FindFirstChild("TypeLight") :: PointLight?
	if light then
		light.Enabled = ball.type ~= "Standard"
		light.Color = def.Color
	end
end

-- Owner cosmetics (skin + trail) only ever apply to Standard balls, so power-up types stay readable.
local function applyOwnerLook(ball: Ball, c: any)
	applyLook(ball)
	if ball.type ~= "Standard" then
		return
	end
	local look = S.ShopService.ballLook(c)
	if not look then
		return
	end
	local part = ball.part
	if look.color then
		part.Color = look.color
	end
	if look.material then
		part.Material = look.material
	end
	local trail = part:FindFirstChild("Trail") :: Trail?
	if trail and look.trail and #look.trail > 0 then
		local keys = {}
		for i, col in look.trail do
			table.insert(keys, ColorSequenceKeypoint.new(if #look.trail == 1 then 0 else (i - 1) / (#look.trail - 1), col))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, look.trail[1]))
		end
		trail.Color = ColorSequence.new(keys)
		trail.Enabled = true
	end
end

local function makePart(ballType: string): Part
	local p = Instance.new("Part")
	p.Name = "Ball"
	p.Shape = Enum.PartType.Ball
	p.CanQuery = false -- balls never block sphere casts; ball-to-ball contact is visual only
	p.CanTouch = false
	p.CollisionGroup = "Ball"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.6, 0.55, 1, 1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.5, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.5, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.Enabled = false
	trail.Parent = p
	local light = Instance.new("PointLight")
	light.Name = "TypeLight"
	light.Range = 8
	light.Brightness = 2
	light.Enabled = false
	light.Parent = p
	return p
end

local function makePhysical(ball: Ball, pos: Vector3, vel: Vector3)
	local part = ball.part
	if ball.weld then
		ball.weld:Destroy()
		ball.weld = nil
	end
	part.Anchored = false
	part.Massless = false
	part.CanCollide = true
	part.Transparency = 0
	part.CFrame = CFrame.new(pos)
	part.AssemblyLinearVelocity = vel
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

function BallService.init(services: any)
	S = services
	folder = Workspace:WaitForChild("Balls") :: Folder
end

function BallService.start()
	RunService.Heartbeat:Connect(BallService.step)
	task.spawn(function()
		while true do
			task.wait(0.05)
			BallService.pickupTick()
			BallService.settleTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Ball.ConservationInterval)
			BallService.conservationTick()
		end
	end)
end

function BallService.all(): { Ball }
	local list = {}
	for _, b in balls do
		table.insert(list, b)
	end
	return list
end

function BallService.spawn(ballType: string, pos: Vector3, context: string, isPower: boolean?): Ball
	nextId += 1
	local part = makePart(ballType)
	local ball: Ball = {
		id = nextId,
		part = part,
		type = ballType,
		isPower = isPower == true,
		state = "Resting",
		context = context,
		holder = nil,
		weld = nil,
		lastThrower = nil,
		lastTeam = nil,
		stateAt = now(),
		lockoutUntil = 0,
		throwerLockoutUntil = 0,
		pos = pos,
		vel = Vector3.zero,
		charge = 0,
		throwId = 0,
		flightT = 0,
		hasHit = false,
	}
	part:SetAttribute(Types.Attr.BallId, ball.id)
	part:SetAttribute("Context", context)
	applyLook(ball)
	setState(ball, "Resting")
	balls[ball.id] = ball
	part.Parent = folder
	makePhysical(ball, pos, Vector3.zero)
	return ball
end

function BallService.destroy(ball: Ball)
	if ball.holder then
		local h = ball.holder
		h.heldBall = nil
		S.PlayerStateService.setAttr(h, Types.Attr.HeldBall, "")
	end
	balls[ball.id] = nil
	ball.part:Destroy()
end

function BallService.setType(ball: Ball, ballType: string)
	ball.type = ballType
	applyLook(ball)
end

-- Give possession. Callers must have already checked eligibility.
function BallService.give(ball: Ball, c: any)
	local character = c.character
	if not character then
		return
	end
	local hand = (character:FindFirstChild("RightHand") or c.root) :: BasePart
	local part = ball.part
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.Transparency = 0
	part.AssemblyLinearVelocity = Vector3.zero
	part.CFrame = hand.CFrame * CFrame.new(0, -0.6, -0.4)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = part
	weld.Parent = part
	ball.weld = weld
	ball.holder = c
	applyOwnerLook(ball, c)
	setState(ball, "Held")
	c.heldBall = ball
	c.heldSince = now()
	c.possessionWarned = false
	S.PlayerStateService.setAttr(c, Types.Attr.HeldBall, ball.type)
end

-- Release a held ball near the holder with a pickup lockout.
function BallService.drop(c: any)
	local ball = c.heldBall :: Ball?
	if not ball then
		return
	end
	c.heldBall = nil
	c.chargeStart = nil
	S.PlayerStateService.setAttr(c, Types.Attr.HeldBall, "")
	ball.holder = nil
	applyLook(ball)
	local pos = if c.root and c.root.Parent then c.root.Position + Vector3.new(0, 1, 0) else ball.part.Position
	makePhysical(ball, pos, Vector3.new(rng:NextNumber(-6, 6), 8, rng:NextNumber(-6, 6)))
	ball.lockoutUntil = now() + Config.Ball.PickupLockout
	setState(ball, "Spent")
end

-- Launch a held ball. `velocity` is fully server-computed.
function BallService.launch(c: any, velocity: Vector3, charge: number, throwId: number): Ball?
	local ball = c.heldBall :: Ball?
	local root = c.root :: BasePart?
	if not ball or not root then
		return nil
	end
	c.heldBall = nil
	S.PlayerStateService.setAttr(c, Types.Attr.HeldBall, "")
	ball.holder = nil
	if ball.weld then
		ball.weld:Destroy()
		ball.weld = nil
	end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local forward = if flat.Magnitude > 1e-3 then flat.Unit else root.CFrame.LookVector
	local origin = root.Position + Vector3.new(0, Config.Ball.SpawnUp, 0) + forward * Config.Ball.SpawnForward
	local part = ball.part
	part.Anchored = true
	part.CanCollide = false
	part.Massless = true
	part.CFrame = CFrame.new(origin)
	ball.pos = origin
	ball.vel = velocity
	ball.charge = charge
	ball.throwId = throwId
	ball.flightT = 0
	ball.hasHit = false
	ball.lastThrower = c
	ball.lastTeam = c.team
	ball.lockoutUntil = now() + Config.Ball.PickupLockout
	ball.throwerLockoutUntil = now() + Config.Ball.ThrowerLockout
	part:SetAttribute(Types.Attr.ThrowerTeam, c.team or "")
	setState(ball, "InFlight")
	-- Flight is deterministic, so clients render the arc locally from this launch record and
	-- reconcile to the authoritative ball's state changes (see BallVisualController).
	local look = if ball.type == "Standard" then S.ShopService.ballLook(c) else nil
	S.NetService.broadcast("BallLaunched", {
		look = look,
		id = ball.id,
		origin = origin,
		vel = velocity,
		ballType = ball.type,
		t0 = ball.stateAt,
		thrower = c.player,
		throwId = throwId,
		context = ball.context,
	})
	-- Explicit initial-overlap handling: a target already inside the ball's sphere is hit now.
	local targets = S.CombatService.targetsFor(ball)
	if #targets > 0 then
		local proxies = {}
		for _, t in targets do
			if t.proxy then
				table.insert(proxies, t.proxy)
			end
		end
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Include
		op.FilterDescendantsInstances = proxies
		local hits = Workspace:GetPartBoundsInRadius(origin, ProjectileMath.radius(ball.type), op)
		if #hits > 0 then
			local target = S.PlayerStateService.fromCharacter(hits[1].Parent)
			if target then
				S.CombatService.resolveContact(ball, target, origin)
			end
		end
	end
	return ball
end

-- Make an in-flight ball non-damaging and let physics carry it.
function BallService.spend(ball: Ball, pos: Vector3, vel: Vector3)
	if ball.state ~= "InFlight" then
		return
	end
	ball.hasHit = true
	setState(ball, "Spent")
	ball.isPower = false
	BallService.setType(ball, "Standard") -- reverts power types and clears the owner's skin
	makePhysical(ball, pos, vel)
end

local function simulate(ball: Ball, dt: number)
	local g = ProjectileMath.gravity(ball.type)
	local r = ProjectileMath.radius(ball.type)
	local from = ball.pos
	local nextVel = ball.vel + Vector3.new(0, -g * dt, 0)
	local to = from + (ball.vel + nextVel) * 0.5 * dt
	local delta = to - from

	-- Catch is evaluated before hits in the same step (spec §7 "Catch").
	local catcher, catchPos = S.CombatService.findCatcher(ball, from, to)

	local targets = S.CombatService.targetsFor(ball)
	local include: { Instance } = table.clone(S.ArenaService.sceneryList(ball.context))
	for _, t in targets do
		if t.proxy then
			table.insert(include, t.proxy)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local result = if delta.Magnitude > 1e-4 then Workspace:Spherecast(from, r, delta, params) else nil

	if catcher then
		local catchT = (catchPos - from):Dot(delta) / math.max(delta:Dot(delta), 1e-6)
		local hitT = if result then (result.Position - from):Dot(delta) / math.max(delta:Dot(delta), 1e-6) else math.huge
		if catchT <= hitT + 1e-3 then
			S.CombatService.resolveCatch(ball, catcher)
			return
		end
	end

	if result then
		local inst = result.Instance
		local target = if inst.Name == "HitProxy" then S.PlayerStateService.fromCharacter(inst.Parent) else nil
		local hitPos = result.Position
		if target then
			ball.pos = hitPos
			ball.part.CFrame = CFrame.new(hitPos)
			S.CombatService.resolveContact(ball, target, hitPos)
		else
			-- First contact with floor or scenery makes the ball spent.
			local n = result.Normal
			local v = ball.vel
			local reflected = (v - 2 * v:Dot(n) * n) * 0.45
			S.BallService.spend(ball, hitPos + n * (r + 0.05), reflected)
		end
		return
	end

	ball.pos = to
	ball.vel = nextVel
	ball.flightT += dt
	ball.part.CFrame = CFrame.new(to)
	local voidY = if ball.context == "Lobby" then ArenaLayout.LobbyVoidY else ArenaLayout.VoidY
	-- a wild match throw that sails over the hub deck is out (it never flies through hub players)
	local overHub = ball.context == "Match" and ArenaLayout.inLobby(to, 2) and to.Y < ArenaLayout.SurfaceY + 30
	if ball.flightT > Config.Ball.MaxFlightTime or to.Y < voidY or overHub then
		BallService.reset(ball)
	end
end

function BallService.step(dt: number)
	local cfg = Config.Ball
	accumulator += dt
	local steps = math.floor(accumulator / cfg.SimStep)
	if steps > cfg.MaxCatchUpSteps then
		-- bounded catch-up budget: drop excess time rather than spiralling
		steps = cfg.MaxCatchUpSteps
		accumulator = 0
	else
		accumulator -= steps * cfg.SimStep
	end
	for _ = 1, steps do
		for _, ball in balls do
			if ball.state == "InFlight" then
				simulate(ball, cfg.SimStep)
			end
		end
	end
end

-- Out-of-bounds: hide, then return to an under-supplied side after a delay.
function BallService.reset(ball: Ball)
	if ball.holder then
		local h = ball.holder
		h.heldBall = nil
		S.PlayerStateService.setAttr(h, Types.Attr.HeldBall, "")
		ball.holder = nil
	end
	if ball.weld then
		ball.weld:Destroy()
		ball.weld = nil
	end
	setState(ball, "Resetting")
	applyLook(ball)
	local part = ball.part
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	if ball.type ~= "Standard" then
		BallService.setType(ball, "Standard")
		ball.isPower = false
	end
	local id = ball.id
	task.delay(Config.Ball.OutOfBoundsReturnDelay, function()
		if balls[id] ~= ball or ball.state ~= "Resetting" then
			return
		end
		local pos = if ball.context == "Lobby"
			then ArenaLayout.PracticeBallHome + Vector3.new(rng:NextNumber(-4, 4), 1, rng:NextNumber(-4, 4))
			else BallService.underSuppliedSpot()
		setState(ball, "Resting")
		makePhysical(ball, pos, Vector3.zero)
	end)
end

local function zoneOf(pos: Vector3): string?
	for _, team in { "Red", "Blue" } do
		if ArenaLayout.onHalf(team, pos, 0, -1) then
			return team .. "Half"
		end
		if ArenaLayout.inJail(team, pos) then
			return team .. "Jail"
		end
	end
	return nil
end

function BallService.underSuppliedSpot(): Vector3
	local counts: { [string]: number } = { RedHalf = 0, BlueHalf = 0 }
	local jailed = S.MatchService.jailedCounts()
	for _, team in { "Red", "Blue" } do
		if jailed[team] > 0 then
			counts[team .. "Jail"] = 0
		end
	end
	for _, b in balls do
		if b.context == "Match" and b.state ~= "Resetting" then
			local pos = if b.holder and b.holder.root then b.holder.root.Position else b.part.Position
			local z = zoneOf(pos)
			if z and counts[z] ~= nil then
				counts[z] += 1
			end
		end
	end
	local best, bestCount = "RedHalf", math.huge
	local keys = {}
	for k in counts do
		table.insert(keys, k)
	end
	table.sort(keys)
	-- shuffle ties fairly
	for i = #keys, 2, -1 do
		local j = rng:NextInteger(1, i)
		keys[i], keys[j] = keys[j], keys[i]
	end
	for _, k in keys do
		-- a jail only qualifies when it has no ball at all
		local isJail = string.find(k, "Jail") ~= nil
		if counts[k] < bestCount and (not isJail or counts[k] == 0) then
			best, bestCount = k, counts[k]
		end
	end
	if string.find(best, "Jail") then
		local team = string.gsub(best, "Jail", "")
		return ArenaLayout.jailCenter(team) + Vector3.new(rng:NextNumber(-20, 20), 2, 0)
	end
	local team = string.gsub(best, "Half", "")
	local sign = ArenaLayout.teamSign(team)
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps()) - 4
	return Config.Arena.Origin + Vector3.new(rng:NextNumber(-hw, hw), 2, sign * rng:NextNumber(4, 14))
end

function BallService.pickupTick()
	local t = now()
	local radius = Config.Player.PickupRadius
	local candidates = S.PlayerStateService.all()
	for _, ball in balls do
		-- landed balls are harmless, so rolling ("Spent") balls can be grabbed too, not just settled ones
		if (ball.state == "Resting" or ball.state == "Spent") and t >= ball.lockoutUntil then
			local pos = ball.part.Position
			local best, bestDist = nil, radius
			for _, c in candidates do
				if c.heldBall == nil and c.root and not c.isDummy and S.CombatService.canPickup(c, ball, pos) then
					local rp = c.root.Position
					-- horizontal distance, with a generous height window (balls sit low, roots high)
					local d = Vector3.new(rp.X - pos.X, 0, rp.Z - pos.Z).Magnitude
					if math.abs(rp.Y - pos.Y) > 7 then
						d = math.huge
					end
					if d <= bestDist and not (ball.lastThrower == c and t < ball.throwerLockoutUntil) then
						best, bestDist = c, d
					end
				end
			end
			-- Ownership is resolved here, once per ball per tick; a ball cannot be assigned twice.
			if best then
				BallService.give(ball, best)
				S.CombatService.onPickup(best, ball)
			end
		end
	end
end

function BallService.settleTick()
	local t = now()
	for _, ball in balls do
		if ball.state == "Spent" or ball.state == "Resting" then
			local part = ball.part
			local voidY = if ball.context == "Lobby" then ArenaLayout.LobbyVoidY else ArenaLayout.VoidY
			-- below the void, or a match ball settled somewhere nobody can reach: put it back in play
			local stranded = ball.context == "Match" and ball.state == "Resting" and zoneOf(part.Position) == nil
			if part.Position.Y < voidY or stranded then
				BallService.reset(ball)
			elseif
				ball.state == "Spent"
				and (
					part.AssemblyLinearVelocity.Magnitude < Config.Ball.SettleSpeed
					or t - ball.stateAt > Config.Ball.SettleTimeout
				)
			then
				setState(ball, "Resting")
			end
		end
	end
end

-- Repair missing balls without duplicating existing ones; trim surplus standard balls.
function BallService.conservationTick()
	if not S.MatchService.isRoundLive() then
		return
	end
	local list = {}
	for _, b in balls do
		if b.context == "Match" then
			table.insert(list, b)
		end
	end
	local want = Config.Ball.BallsPerCourt
	local maxTotal = want + 2 * Config.PowerUps.MaxPowerBallsPerSide
	local standardCount = 0
	for _, b in list do
		if not b.isPower then
			standardCount += 1
		end
	end
	for _ = standardCount + 1, want do
		BallService.spawn("Standard", BallService.underSuppliedSpot(), "Match")
	end
	if #list > maxTotal then
		local extra = #list - maxTotal
		for _, b in list do
			if extra <= 0 then
				break
			end
			if b.state == "Resting" and not b.isPower then
				BallService.destroy(b)
				extra -= 1
			end
		end
	end
end

function BallService.clearContext(context: string)
	for _, b in balls do
		if b.context == context then
			BallService.destroy(b)
		end
	end
end

function BallService.resetMatchBalls()
	BallService.clearContext("Match")
	for _, pos in ArenaLayout.openingBallSpots() do
		BallService.spawn("Standard", pos, "Match")
	end
end

function BallService.countPower(team: string): number
	local n = 0
	for _, b in balls do
		if b.context == "Match" and b.isPower then
			local pos = if b.holder and b.holder.root then b.holder.root.Position else b.part.Position
			if ArenaLayout.onHalf(team, pos, 0, -2) or (b.holder and b.holder.team == team) then
				n += 1
			end
		end
	end
	return n
end

function BallService.ensurePracticeBall()
	for _, b in balls do
		if b.context == "Lobby" then
			return
		end
	end
	BallService.spawn("Standard", ArenaLayout.PracticeBallHome, "Lobby")
	BallService.spawn("Standard", ArenaLayout.PracticeBallHome + Vector3.new(6, 0, 0), "Lobby")
end

return BallService
