--!strict
-- Confetti Pop (Common): a giant striped party cannon pops into the winner's arms, rumbles, and
-- fires a roaring gust of confetti across the court that blows the victim clean off the stage.
--
--   0.00-0.70  front low shot on the winner: the cannon pops in and swings round to aim
--   0.70-1.30  over the shoulder: the cannon swells and shakes, fuse fizzing
--   1.30       FIRE: recoil, muzzle flash, a cone of confetti and wind streaks
--   1.30-1.55  the camera rides the gust across the court
--   1.55       the gust hits; the server launches the victim (LaunchDelay)
--   1.55-end   chase the victim off the arena in a cloud of confetti

local RunService = game:GetService("RunService")

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local AIM = 0.7
local FIRE = 1.3
local HIT = 1.55

local CONFETTI = {
	Color3.fromRGB(255, 90, 120),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(120, 230, 120),
	Color3.fromRGB(190, 120, 255),
}
local GOLD = Color3.fromRGB(255, 205, 70)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- The cannon, as pieces laid out along its own -Z (the muzzle end). `place(cf, scale)` moves and
-- sizes every piece around the cannon's pivot; `muzzle` and `breech` are local offsets.
type Cannon = { place: (CFrame, number) -> (), muzzle: Vector3, breech: Vector3, fuse: Attachment }

local LENGTH = 7.5
local RADIUS = 1.4

local function buildCannon(ctx: any): Cannon
	local pieces: { { p: BasePart, size: Vector3, offset: CFrame } } = {}
	local CYL = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis is X; turn it onto Z
	local function add(props: { [string]: any }, size: Vector3, offset: CFrame)
		local p = part(props, ctx.folder)
		table.insert(pieces, { p = p, size = size, offset = offset })
	end
	-- the barrel: candy stripes, flaring a little toward the muzzle
	local bands = 6
	for i = 1, bands do
		local z = LENGTH / 2 - (i - 0.5) * LENGTH / bands
		local r = RADIUS * (0.9 + 0.12 * i / bands)
		add({
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.SmoothPlastic,
			Color = CONFETTI[(i - 1) % #CONFETTI + 1],
		}, Vector3.new(LENGTH / bands + 0.02, r * 2, r * 2), CFrame.new(0, 0, z) * CYL)
	end
	-- gold rim and a dark mouth stuffed with confetti
	add(
		{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = GOLD, Reflectance = 0.15 },
		Vector3.new(0.6, RADIUS * 2.7, RADIUS * 2.7),
		CFrame.new(0, 0, -LENGTH / 2 - 0.1) * CYL
	)
	add(
		{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(30, 20, 40) },
		Vector3.new(0.1, RADIUS * 2.1, RADIUS * 2.1),
		CFrame.new(0, 0, -LENGTH / 2 - 0.42) * CYL
	)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		add(
			{ Material = Enum.Material.SmoothPlastic, Color = CONFETTI[(i - 1) % #CONFETTI + 1] },
			Vector3.new(0.5, 0.06, 0.3),
			CFrame.new(math.cos(a) * RADIUS * 0.55, math.sin(a) * RADIUS * 0.55, -LENGTH / 2 - 0.45)
				* CFrame.Angles(a, a * 2, 0)
		)
	end
	-- gold back cap, a fuse on top of it, and a grip underneath
	add(
		{ Shape = Enum.PartType.Ball, Material = Enum.Material.Metal, Color = GOLD, Reflectance = 0.15 },
		Vector3.one * RADIUS * 1.9,
		CFrame.new(0, 0, LENGTH / 2)
	)
	add(
		{ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(240, 235, 220) },
		Vector3.new(0.9, 0.22, 0.22),
		CFrame.new(0, RADIUS * 0.9, LENGTH / 2 + 0.3) * CFrame.Angles(0, 0, math.rad(70))
	)
	add(
		{ Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(70, 45, 90) },
		Vector3.new(0.5, 1.6, 0.7),
		CFrame.new(0, -RADIUS - 0.5, LENGTH / 2 - 2.2) * CFrame.Angles(math.rad(-15), 0, 0)
	)

	-- fizzing fuse: sparks from an attachment at its tip
	local fusePart = pieces[#pieces - 1].p
	local fuse = Instance.new("Attachment")
	fuse.Position = Vector3.new(0.45, 0, 0)
	fuse.Parent = fusePart
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 130, 40))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.3, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(4, 8)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Rate = 0
	sparks.Parent = fuse

	return {
		place = function(cf: CFrame, scale: number)
			for _, piece in pieces do
				local o = piece.offset
				piece.p.Size = piece.size * scale
				piece.p.CFrame = cf * CFrame.new(o.Position * scale) * o.Rotation
			end
		end,
		muzzle = Vector3.new(0, 0, -LENGTH / 2 - 0.5),
		breech = Vector3.new(0, 0, LENGTH / 2),
		fuse = fuse,
	}
end

-- A bit of paper confetti, flying freely: flutters, slows in the air, sinks and fades.
type Bit = { p: Part, pos: Vector3, vel: Vector3, spin: Vector3, rot: CFrame, life: number, age: number }

local function newBit(ctx: any, rng: Random, at: Vector3, vel: Vector3, life: number): Bit
	local s = rng:NextNumber(0.8, 1.4)
	local p = part({
		Size = Vector3.new(0.45 * s, 0.05, 0.28 * s),
		Material = Enum.Material.SmoothPlastic,
		Color = CONFETTI[rng:NextInteger(1, #CONFETTI)],
		CFrame = CFrame.new(at),
	}, ctx.folder)
	return {
		p = p,
		pos = at,
		vel = vel,
		spin = rng:NextUnitVector() * rng:NextNumber(8, 20),
		rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
		life = life,
		age = 0,
	}
end

local function stepBits(bits: { Bit }, dt: number)
	for i = #bits, 1, -1 do
		local b = bits[i]
		b.age += dt
		if b.age >= b.life then
			b.p:Destroy()
			table.remove(bits, i)
		else
			b.vel *= math.max(0, 1 - dt * 2.2) -- air drag: the gust slows into a drifting cloud
			b.vel += Vector3.new(0, -14 * dt, 0)
			b.pos += b.vel * dt
			b.rot *= CFrame.Angles(b.spin.X * dt, b.spin.Y * dt, b.spin.Z * dt)
			b.p.CFrame = CFrame.new(b.pos) * b.rot
			b.p.Transparency = math.clamp((b.age - (b.life - 0.4)) / 0.4, 0, 1)
		end
	end
end

-- A thin white streak racing along the gust.
type Streak = { p: Part, from: Vector3, to: Vector3, t: number, speed: number }

return {
	Id = "ConfettiPop",
	Name = "Confetti Pop",
	Duration = 4.2,
	-- flat and fast: blown off sideways rather than popped up
	Stage = { LaunchDelay = HIT, Up = 60, Out = 95 },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local rng = Random.new()
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		if not killerRoot or not victimRoot then
			FinisherKit.heroShot(ctx, HIT)
			FinisherKit.followLaunch(ctx, ctx.duration - HIT)
			return
		end

		local K = killerRoot.Position
		local V = victimRoot.Position
		local f = Vector3.new(V.X - K.X, 0, V.Z - K.Z)
		f = if f.Magnitude > 0.1 then f.Unit else FinisherKit.facing(killerRoot)
		local side = f:Cross(Vector3.yAxis) -- the winner's right
		local target = V + Vector3.new(0, 0.5, 0)

		-- the cannon is held at the right hip, tucked under the arm
		local unpose = ctx.pose(ctx.killer, "Catch", 0.2)
		local cannon = buildCannon(ctx)
		local function hold(): CFrame
			local root = killerRoot.CFrame
			local at = (root * CFrame.new(1.7, 0.6, -2.6)).Position
			return CFrame.lookAt(at, target)
		end
		local sparks = cannon.fuse:FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter

		-- free-flying confetti and wind streaks, stepped every frame for the whole finisher
		local bits: { Bit } = {}
		local streaks: { Streak } = {}
		local sim = RunService.RenderStepped:Connect(function(dt: number)
			stepBits(bits, dt)
			for i = #streaks, 1, -1 do
				local s = streaks[i]
				s.t += dt * s.speed
				if s.t >= 1 then
					s.p:Destroy()
					table.remove(streaks, i)
				else
					local head = s.from:Lerp(s.to, s.t)
					s.p.CFrame = CFrame.lookAt(head, s.to) * CFrame.new(0, 0, s.p.Size.Z / 2)
					s.p.Transparency = 0.3 + 0.7 * s.t
				end
			end
		end)
		task.delay(ctx.duration + 0.3, function()
			sim:Disconnect() -- always cleaned up, even if the finisher errors
		end)

		-- Pop in and aim: front low shot, the barrel swinging round toward the lens -------------------
		ctx.sound("ConfettiCannonSummon", K)
		ctx.fx.burst(K + f * 2 + Vector3.new(0, 1, 0), GOLD, 12, 20, 0.6)
		-- off to the winner's left, far enough out that the muzzle swings past the lens, not into it
		local front = K + f * 11 - side * 2.5 + Vector3.new(0, 1.2, 0)
		local frontLook = K + f * 2 + side * 0.8 + Vector3.new(0, 1, 0)
		ctx.runFor(AIM, function(alpha: number)
			-- springy pop-in, a quick swing from pointing up to on target
			local s = math.min(1, alpha / 0.45)
			local scale = 1 + math.sin(s * math.pi * 1.5) * (1 - s) * 0.6
			scale *= math.min(1, 0.15 + s * 1.7)
			local swing = (1 - ctx.ease(math.min(1, alpha * 1.6))) * math.rad(70)
			cannon.place(hold() * CFrame.Angles(swing, 0, 0), math.max(0.05, scale))
			cam.CFrame = CFrame.lookAt(front:Lerp(front - f * 1.5, ctx.ease(alpha)), frontLook)
		end)

		-- Wind-up: over the shoulder, the cannon swells and shakes ------------------------------------
		sparks.Rate = if ctx.reducedMotion then 40 else 120
		ctx.sound("ConfettiCannonFuse", K)
		local shoulderA = K - f * 6.5 + side * 4 + Vector3.new(0, 2.6, 0)
		local shoulderB = K - f * 5 + side * 3 + Vector3.new(0, 2, 0)
		local aimAt = K:Lerp(target, 0.55)
		ctx.runFor(FIRE - AIM, function(alpha: number)
			local throb = 1 + alpha * 0.12 + math.sin(alpha * 40) * 0.035 * alpha
			local jitter = if ctx.reducedMotion
				then CFrame.identity
				else CFrame.Angles(rng:NextNumber(-1, 1) * 0.02 * alpha, rng:NextNumber(-1, 1) * 0.02 * alpha, 0)
			cannon.place(hold() * jitter, throb)
			cam.CFrame = CFrame.lookAt(shoulderA:Lerp(shoulderB, ctx.ease(alpha)), aimAt)
			if not ctx.reducedMotion then
				ctx.fx.shake(0.02 * alpha)
			end
		end)
		sparks.Rate = 0

		-- FIRE ---------------------------------------------------------------------------------------
		local aim = hold()
		local muzzle = (aim * CFrame.new(cannon.muzzle)).Position
		local dir = (target - muzzle).Unit
		local dist = (target - muzzle).Magnitude
		local travel = HIT - FIRE
		ctx.sound("ConfettiCannonFire", muzzle)
		ctx.fx.flash(muzzle, Color3.new(1, 1, 1), 7)
		ctx.fx.shockwave(muzzle, dir, Color3.new(1, 1, 1), 12, 0.3)
		for _, color in CONFETTI do
			ctx.fx.burst(muzzle + dir, color, if ctx.reducedMotion then 4 else 10, 45, 0.6)
		end
		ctx.fx.shake(if ctx.reducedMotion then 0.2 else 0.6)
		if not ctx.reducedMotion then
			ctx.fx.screenFlash(Color3.new(1, 1, 1), 0.3, 0.08)
		end
		-- the gust: a cone of confetti fast enough to reach the victim right at the hit
		local gustSpeed = dist / travel
		local up = Vector3.yAxis
		local across = dir:Cross(up).Unit
		for _ = 1, (if ctx.reducedMotion then 30 else 90) do
			local spread = across * rng:NextNumber(-1, 1) + up * rng:NextNumber(-0.6, 0.9)
			local v = (dir + spread * rng:NextNumber(0, 0.22)).Unit * gustSpeed * rng:NextNumber(1.05, 1.5)
			table.insert(bits, newBit(ctx, rng, muzzle + rng:NextUnitVector() * 0.6, v, rng:NextNumber(1.6, 2.6)))
		end
		for _ = 1, (if ctx.reducedMotion then 4 else 12) do
			local off = across * rng:NextNumber(-2, 2) + up * rng:NextNumber(-1, 2)
			local p = part({
				Size = Vector3.new(0.08, 0.08, rng:NextNumber(4, 8)),
				Material = Enum.Material.Neon,
				Color = Color3.new(1, 1, 1),
				Transparency = 0.3,
			}, ctx.folder)
			table.insert(streaks, {
				p = p,
				from = muzzle + off * 0.3,
				to = target + dir * 12 + off,
				t = rng:NextNumber(-0.15, 0),
				speed = rng:NextNumber(2.6, 3.4),
			})
		end

		-- the camera rides along beside the gust; the cannon kicks back and springs home
		local rideFrom = cam.CFrame.Position
		local rideTo = target - dir * 9 + across * 6 + Vector3.new(0, 2.5, 0)
		ctx.runFor(travel, function(alpha: number)
			local kick = math.sin(math.min(1, alpha * 1.4) * math.pi) * (1 - alpha * 0.5)
			cannon.place(hold() * CFrame.new(0, 0, 1.4 * kick) * CFrame.Angles(math.rad(18) * kick, 0, 0), 1.05)
			local gustHead = muzzle:Lerp(target, alpha)
			if ctx.reducedMotion then
				cam.CFrame = CFrame.lookAt(shoulderB, aimAt:Lerp(target, alpha))
			else
				cam.CFrame = CFrame.lookAt(rideFrom:Lerp(rideTo, ctx.ease(alpha)), gustHead)
			end
		end)

		-- The hit: the gust slams into the victim and blows them off the arena --------------------------
		ctx.sound("ConfettiPop", target)
		ctx.fx.shockwave(target, -dir, Color3.new(1, 1, 1), 16, 0.35)
		for _, color in CONFETTI do
			ctx.fx.burst(target, color, if ctx.reducedMotion then 6 else 14, 40, 0.8)
		end
		ctx.fx.shake(if ctx.reducedMotion then 0.15 else 0.45)
		cannon.place(hold(), 1)
		unpose()

		-- a confetti plume streaming off the victim as they fly
		local plume = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = victimRoot.CFrame }, ctx.folder)
		local plumeAt = Instance.new("Attachment")
		plumeAt.Parent = plume
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, CONFETTI[1]),
			ColorSequenceKeypoint.new(0.25, CONFETTI[2]),
			ColorSequenceKeypoint.new(0.5, CONFETTI[3]),
			ColorSequenceKeypoint.new(0.75, CONFETTI[4]),
			ColorSequenceKeypoint.new(1, CONFETTI[5]),
		})
		emitter.Size = NumberSequence.new(0.35)
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(3, 8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.RotSpeed = NumberRange.new(-300, 300)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Acceleration = Vector3.new(0, -10, 0)
		emitter.Drag = 2
		emitter.Rate = if ctx.reducedMotion then 25 else 80
		emitter.Parent = plumeAt

		FinisherKit.followLaunch(ctx, math.max(0.3, ctx.duration - (os.clock() - t0)), function()
			plume.CFrame = victimRoot.CFrame
		end)
		emitter.Rate = 0
	end,
}
