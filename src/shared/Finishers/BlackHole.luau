--!strict
-- Black Hole: a dodgeball streaks in and stops hovering just short of the winner's outstretched
-- palm, gets crushed down to a pinpoint black hole, and is hurled. From the throw on it grows at a
-- constant rate, sucking in black dust; it lands behind the victim, its accretion rings form, and
-- the victim sprints for the camera, but is dragged back and swallowed (with chunks of the court).
--
--   0.0-2.25  shot 1, from the winner's side (they face screen-right):
--             0.0-0.7   close on the hand: the ball flies in from the right, slowing to a hover
--             0.8-1.05  the winner crushes it down, shivering and darkening, to a speck
--             1.05      it collapses into a tiny black hole: shake + impact frames
--             1.1-1.65  pull back to the full body while they wind up
--             1.75      throw: the hole rockets off to the right and starts growing
--   2.25-5.0  shot 2, wide head-on on the victim: the hole streaks past them and keeps growing
--             behind them while its rings form; they run toward the camera, slow, slide back, and
--             are ripped off their feet (flailing, spinning, shrinking) into it; it snaps shut
--
-- Both characters are stand-ins (copies wearing their avatars); the server doesn't launch anyone.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local FLY = 0.7
local SQUEEZE = 0.8
local FORM = 1.05
local WIND_UP = 1.2
local THROW = 1.75
local CUT = 2.25

local SEED_R = 0.16 -- the hole's radius when it forms
local GROW_RATE = 3.2 -- radius gained per second, from the throw until it snaps shut
-- the accretion rings start forming at this radius, and are fully formed RING_SPAN later
local RING_START = 2.8
local RING_SPAN = 2.5

-- the victim's escape attempt (shot 2 seconds)
local RUN_FROM = 0.15
local PULL = 1.25

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local VOID = Color3.fromRGB(8, 4, 14)
local VIOLET = Color3.fromRGB(150, 70, 255)
local HOT = Color3.fromRGB(255, 150, 60)
local BALL_RED = Color3.fromRGB(214, 48, 49)

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- The black hole: a void core, a glowing violet horizon (a disk behind the core, turned to the
-- camera, so it reads as a rim of light around pure black), two spinning accretion rings that form
-- once it is big enough, a shell that pulls sparkles inward, and a wider one that drags in black
-- dust. size() rescales everything; place() moves it.
type Hole = {
	core: Part,
	horizon: Part,
	rings: { Part },
	shell: Part,
	inflow: ParticleEmitter,
	dustShell: Part,
	dust: ParticleEmitter,
	light: PointLight,
	r: number,
	reducedMotion: boolean,
}

local function makeHole(ctx: any): Hole
	local core = part(
		-- black Neon ignores lighting, so the void stays pitch black under its own glow
		{ Shape = Enum.PartType.Ball, Color = VOID, Material = Enum.Material.Neon },
		ctx.folder
	)
	local horizon = part(
		{ Shape = Enum.PartType.Cylinder, Color = VIOLET, Material = Enum.Material.Neon, Transparency = 0.2 },
		ctx.folder
	)
	local rings = {}
	for _, col in { HOT, VIOLET } do
		table.insert(
			rings,
			part({
				Shape = Enum.PartType.Cylinder,
				Color = col,
				Material = Enum.Material.Neon,
				Transparency = 1,
			}, ctx.folder)
		)
	end
	local shell = part({ Shape = Enum.PartType.Ball, Transparency = 1 }, ctx.folder)
	local inflow = Instance.new("ParticleEmitter")
	inflow.Texture = SPARK
	inflow.Color = ColorSequence.new(Color3.fromRGB(230, 200, 255), VIOLET)
	inflow.LightEmission = 1
	inflow.Size = NumberSequence.new(0.6, 0.1)
	inflow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	inflow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	inflow.Shape = Enum.ParticleEmitterShape.Sphere
	inflow.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	inflow.Lifetime = NumberRange.new(0.5, 0.7)
	inflow.Speed = NumberRange.new(4, 6)
	inflow.Rate = if ctx.reducedMotion then 30 else 90
	inflow.Parent = shell
	-- black specks falling in from further out; locked to the shell so they still converge on the
	-- core while it flies
	local dustShell = part({ Shape = Enum.PartType.Ball, Transparency = 1 }, ctx.folder)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SPARK
	dust.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromRGB(30, 10, 50))
	dust.LightEmission = 0
	dust.LightInfluence = 0
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.05),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	dust.Shape = Enum.ParticleEmitterShape.Sphere
	dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	dust.Lifetime = NumberRange.new(0.7)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-300, 300)
	dust.LockedToPart = true
	dust.Parent = dustShell
	local light = Instance.new("PointLight")
	light.Color = VIOLET
	light.Brightness = 4
	light.Range = 12
	light.Parent = horizon
	return {
		core = core,
		horizon = horizon,
		rings = rings,
		shell = shell,
		inflow = inflow,
		dustShell = dustShell,
		dust = dust,
		light = light,
		r = 1,
		reducedMotion = ctx.reducedMotion == true,
	}
end

local function sizeHole(h: Hole, r: number)
	h.r = r
	h.core.Size = Vector3.one * r * 2
	h.horizon.Size = Vector3.new(0.05, r * 2.5, r * 2.5)
	-- rings spread out from the core and fade in as the hole passes RING_START
	local form = math.clamp((r - RING_START) / RING_SPAN, 0, 1)
	form = 1 - (1 - form) ^ 2
	for i, ring in h.rings do
		local d = r * (2 + form * (1.2 + i * 0.9))
		ring.Size = Vector3.new(0.12 * math.max(1, r * 0.4), d, d)
		ring.Transparency = 1 - (0.75 - 0.15 * i) * form
	end
	h.shell.Size = Vector3.one * r * 6
	-- inflow particles must reach the core from the shell surface within their lifetime
	h.inflow.Speed = NumberRange.new(r * 3.6, r * 4.4)
	h.inflow.Size = NumberSequence.new(0.25 * r + 0.3, 0.05 * r)
	-- dust starts 5r out and ends inside the core (radius r) after its 0.7s lifetime
	h.dustShell.Size = Vector3.one * r * 10
	h.dust.Speed = NumberRange.new(r * 5.7, r * 7.1)
	h.dust.Size = NumberSequence.new(0.12 * r + 0.2, 0.02)
	h.dust.Rate = math.min(260, 40 + r * 24) * (if h.reducedMotion then 0.3 else 1)
	h.light.Range = math.min(60, 10 + r * 5)
end

local function placeHole(h: Hole, pos: Vector3, t: number)
	h.core.CFrame = CFrame.new(pos)
	-- horizon disk faces the camera from just behind the core's centre
	local camPos = (Workspace.CurrentCamera :: Camera).CFrame.Position
	local toCam = camPos - pos
	toCam = if toCam.Magnitude > 0.01 then toCam.Unit else Vector3.zAxis
	h.horizon.CFrame = CFrame.lookAt(pos - toCam * h.r * 0.5, camPos) * CFrame.Angles(0, math.rad(90), 0)
	h.shell.CFrame = CFrame.new(pos)
	h.dustShell.CFrame = CFrame.new(pos)
	local facing = CFrame.lookAt(pos, camPos)
	for i, ring in h.rings do
		-- accretion disks seen nearly edge-on (a bright band across the void), gently wobbling
		local tilt = math.rad(8 + i * 9) + math.sin(t * 3 + i) * 0.04
		local roll = math.rad(if i == 1 then 12 else -9) + math.sin(t * 2.2 + i) * 0.05
		ring.CFrame = facing * CFrame.Angles(tilt, 0, roll) * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function hideHole(h: Hole, hidden: boolean)
	for _, p in { h.core, h.horizon, h.rings[1], h.rings[2] } do
		p.LocalTransparencyModifier = if hidden then 1 else 0
	end
	h.inflow.Enabled = not hidden
	h.dust.Enabled = not hidden
	h.light.Enabled = not hidden
end

-- Violet-black impact frames when the hole forms.
local function impactFrames(ctx: any)
	if ctx.reducedMotion then
		ctx.fx.screenFlash(Color3.fromRGB(200, 160, 255), 0.4, 0.3)
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
	task.delay(0.6, function()
		cc:Destroy()
	end)
	ctx.fx.screenFlash(Color3.new(1, 1, 1), 1, 0.06)
	task.wait(0.05)
	cc.Saturation = -1
	cc.Contrast = 3
	cc.Brightness = -0.3
	cc.TintColor = Color3.fromRGB(170, 90, 255)
	task.wait(0.07)
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Brightness = 0.55
	cc.Contrast = 2
	task.wait(0.05)
	cc.Brightness = -0.4
	cc.Contrast = 3
	cc.TintColor = Color3.fromRGB(120, 60, 200)
	task.wait(0.07)
	cc:Destroy()
end

type Joints = { [string]: { inst: Instance, f0: CFrame } }

-- Joints of a stand-in by name, with their parent-side frames (for axis rotations).
local function jointsOf(model: Model): Joints
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Attachment0 then
			out[d.Name] = { inst = d :: Instance, f0 = (d.Attachment0 :: Attachment).CFrame }
		elseif d:IsA("Motor6D") then
			out[d.Name] = { inst = d :: Instance, f0 = d.C0 }
		end
	end
	return out
end

local function rot(j: { inst: Instance, f0: CFrame }, axis: Vector3, deg: number): CFrame
	return CFrame.fromAxisAngle(j.f0:VectorToObjectSpace(axis), math.rad(deg))
end

-- A frantic sprint: legs pumping, arms driving, a panicked glance back over the shoulder.
local function runCycle(joints: Joints, t: number, glance: number): { [string]: CFrame }
	local X, Y = Vector3.xAxis, Vector3.yAxis
	local out = {}
	local w = t * 17
	for _, side in { "Right", "Left" } do
		local s = math.sin(w + (if side == "Right" then 0 else math.pi))
		local c = math.cos(w + (if side == "Right" then 0 else math.pi))
		local sh, el, hip, knee =
			joints[side .. "Shoulder"], joints[side .. "Elbow"], joints[side .. "Hip"], joints[side .. "Knee"]
		if hip then
			out[hip.inst.Name] = rot(hip, X, 55 * s)
		end
		if knee then
			-- tucked tight on the forward swing
			out[knee.inst.Name] = rot(knee, X, -(15 + 75 * math.max(0, c)))
		end
		if sh then
			out[sh.inst.Name] = rot(sh, X, -60 * s)
		end
		if el then
			out[el.inst.Name] = rot(el, X, 85)
		end
	end
	local neck = joints["Neck"]
	if neck then
		out.Neck = rot(neck, Y, 65 * glance) * rot(neck, X, -10)
	end
	return out
end

-- Arms and legs thrashing, head whipping.
local function flail(joints: Joints, t: number): { [string]: CFrame }
	local X, Z = Vector3.xAxis, Vector3.zAxis
	local out = {}
	for _, side in { "Right", "Left" } do
		local sgn = if side == "Right" then 1 else -1
		local sh, el, hip, knee =
			joints[side .. "Shoulder"], joints[side .. "Elbow"], joints[side .. "Hip"], joints[side .. "Knee"]
		if sh then
			out[sh.inst.Name] = rot(sh, X, 110 + 60 * math.sin(t * 14 + sgn))
				* rot(sh, Z, sgn * (40 + 30 * math.sin(t * 10)))
		end
		if el then
			out[el.inst.Name] = rot(el, X, 50 + 40 * math.sin(t * 17 + sgn))
		end
		if hip then
			out[hip.inst.Name] = rot(hip, X, 45 * math.sin(t * 12 + sgn * 1.7)) * rot(hip, Z, sgn * 20)
		end
		if knee then
			out[knee.inst.Name] = rot(knee, X, -30 - 30 * math.sin(t * 15 + sgn))
		end
	end
	local neck = joints["Neck"]
	if neck then
		out.Neck = rot(neck, X, 35 * math.sin(t * 11)) * rot(neck, Z, 30 * math.sin(t * 8))
	end
	return out
end

-- Set joints to a blend of two poses (missing entries count as rest), scaled by `amount`.
local function applyBlend(joints: Joints, a: { [string]: CFrame }, b: { [string]: CFrame }, w: number, amount: number)
	local rest = CFrame.new()
	for name, j in joints do
		local ca, cb = a[name], b[name]
		if ca or cb then
			local cf = (ca or rest):Lerp(cb or rest, w);
			(j.inst :: any).Transform = rest:Lerp(cf, amount)
		end
	end
end

local function makeBall(ctx: any): Part
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, Color = BALL_RED }, ctx.folder)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), BALL_RED)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = ball
	return ball
end

return {
	Id = "BlackHole",
	Name = "Black Hole",
	Duration = 5.0,
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local baseFov = cam.FieldOfView
		local rng = Random.new()
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		local hero: Model? = nil
		-- the hole's growth runs off the moment it leaves the winner's hand
		local throwClock = t0 + THROW
		ctx.banner("BLACK HOLE!", VIOLET, 1.2)

		-- Shot 1: side view on the winner ----------------------------------------------------------
		if killerRoot then
			hero = ctx.standIn(ctx.killer) or ctx.killer
			local K = killerRoot.Position
			local look = killerRoot.CFrame.LookVector
			local f = Vector3.new(look.X, 0, look.Z)
			f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
			local side = f:Cross(Vector3.yAxis) -- the winner's right; the camera sits on this side
			local hand = (hero :: any):FindFirstChild("RightHand") :: BasePart?
			ctx.pose(hero, "ReachOut", 0.3)
			local ball = makeBall(ctx)
			local hole = makeHole(ctx)
			sizeHole(hole, SEED_R)
			hideHole(hole, true)
			local function palm(): Vector3
				return if hand then hand.Position else K + f * 2.4 + Vector3.new(0, 1.3, 0)
			end
			-- close-up framing on the outstretched hand; the ball enters from screen-right (+f)
			local closeCam = K + side * 5 + f * 2.6 + Vector3.new(0, 1.2, 0)
			local closeLook = K + f * 3.4 + Vector3.new(0, 1.2, 0)
			-- pulled-back framing: full body, room on the right for the throw
			local wideCam = K + side * 9.5 + f * 2.5 + Vector3.new(0, 1.8, 0)
			local wideLook = K + f * 2.5 + Vector3.new(0, 1.2, 0)
			local squeezing = false
			local formed = false
			local woundUp = false
			local thrown = false
			local throwFrom = Vector3.zero
			ctx.sound("BallWhoosh")
			ctx.runFor(CUT, function(alpha: number)
				local t = alpha * CUT
				-- camera: tight on the hand, then an eased pull-back to the full body
				local pull = ctx.ease(math.clamp((t - 1.1) / 0.55, 0, 1))
				local camPos = closeCam:Lerp(wideCam, pull)
				local camLook = closeLook:Lerp(wideLook, pull)
				cam.CFrame = CFrame.lookAt(camPos, camLook)

				local stopAt = palm() + f * 1.5 -- hovering just short of the fingertips
				if t < FLY then
					-- flies in horizontally from the right, decelerating to a halt
					local u = t / FLY
					local e = 1 - (1 - u) ^ 3
					local pos = (stopAt + f * 45):Lerp(stopAt, e)
					ball.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, (1 - e) * 14)
				elseif t < FORM then
					-- crushed down: slow at first, then caving in fast, shivering harder and going dark
					local sq = math.clamp((t - SQUEEZE) / (FORM - SQUEEZE), 0, 1)
					local k = sq ^ 2
					ball.Size = Vector3.one * (2.2 - 1.95 * k)
					ball.Color = BALL_RED:Lerp(VOID, k)
					local shiver = (0.04 + 0.16 * sq) * (if ctx.reducedMotion then 0.3 else 1)
					ball.CFrame = CFrame.new(stopAt + rng:NextUnitVector() * shiver)
					if sq > 0 and not squeezing then
						squeezing = true
						ctx.fx.shake(0.15)
					end
				elseif not formed then
					formed = true
					ball.Transparency = 1
					local trail = ball:FindFirstChildOfClass("Trail")
					if trail then
						trail.Enabled = false
					end
					hideHole(hole, false)
					ctx.sound("BlackHoleForm", stopAt)
					ctx.fx.shake(0.7)
					ctx.fx.burst(stopAt, VIOLET, if ctx.reducedMotion then 12 else 40, 20, 1)
					task.spawn(impactFrames, ctx)
				end
				if formed and not thrown then
					-- a throbbing speck, riding the hand through the wind-up
					sizeHole(hole, SEED_R * (1 + 0.2 * math.sin(t * 40)))
					if not woundUp and t >= WIND_UP then
						woundUp = true
						ctx.pose(hero, "WindUp", 0.4)
					end
					local at = if t < WIND_UP then stopAt else palm() + Vector3.new(0, 0.9, 0)
					placeHole(hole, at, t)
					throwFrom = at
				end
				if not thrown and t >= THROW then
					thrown = true
					throwClock = os.clock()
					ctx.pose(hero, "ThrowFollow", 0.1)
					ctx.sound("BlackHoleThrow", throwFrom)
				end
				if thrown then
					local u = os.clock() - throwClock
					sizeHole(hole, SEED_R + GROW_RATE * u)
					placeHole(hole, throwFrom + f * (u * 70) + Vector3.new(0, u * 2, 0), t)
				end
			end)
			hideHole(hole, true)
		else
			task.wait(CUT)
		end
		cam.FieldOfView = baseFov

		-- Shot 2: the victim runs, and is swallowed ------------------------------------------------
		if not victimRoot then
			task.wait(math.max(0, ctx.duration - (os.clock() - t0)))
			return
		end
		-- a clear stage: the winner's stand-in and anyone else standing around could block the lens
		ctx.hide(hero)
		for _, plr in Players:GetPlayers() do
			ctx.hide(plr.Character)
		end
		local bots = Workspace:FindFirstChild("Bots")
		if bots then
			for _, m in bots:GetChildren() do
				ctx.hide(m)
			end
		end
		local G = victimRoot.Position - Vector3.new(0, 3, 0) -- the court under their feet
		local o = ctx.outward :: Vector3
		local s = o:Cross(Vector3.yAxis)
		local standCF = victimRoot.CFrame
		local puppet = ctx.standIn(ctx.victim)
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		local joints = if puppet then jointsOf(puppet) else {}
		local H = G + o * 13 + Vector3.new(0, 7, 0) -- where the hole settles, behind the victim
		local camA = G - o * 25 + Vector3.new(0, 4, 0)
		local camB = G - o * 20 + Vector3.new(0, 4.2, 0)
		-- facing away from the hole, toward the camera
		local away = Vector3.new(-o.X, 0, -o.Z)
		away = if away.Magnitude > 0.1 then away.Unit else -Vector3.zAxis
		local runRot = CFrame.lookAt(Vector3.zero, away).Rotation
		local function runOffset(t: number): number
			-- sprints out, slows as the pull builds, then slides backward with legs still pumping
			local k = math.clamp((t - RUN_FROM) / (PULL - RUN_FROM), 0, 1)
			return 14 * k * (1 - 0.8 * k)
		end
		local runEnd = standCF.Position + away * runOffset(PULL)
		local hole = makeHole(ctx)
		sizeHole(hole, 1)
		local dark = Instance.new("ColorCorrectionEffect")
		dark.Parent = cam
		task.delay(ctx.duration + 0.5, function()
			dark:Destroy()
		end)
		-- chunks of court torn up and pulled in with the victim
		local chunks: { { p: Part, from: Vector3, delay: number, spin: Vector3 } } = {}
		for i = 1, (if ctx.reducedMotion then 4 else 10) do
			local from = G + o * rng:NextNumber(-3, 6) + s * rng:NextNumber(-7, 7) + Vector3.new(0, 0.3, 0)
			local p = part({
				Size = Vector3.new(rng:NextNumber(1, 2.4), 0.6, rng:NextNumber(1, 2.4)),
				CFrame = CFrame.new(from),
				Color = Color3.fromRGB(150, 95, 100):Lerp(Color3.fromRGB(110, 120, 160), rng:NextNumber()),
				Material = Enum.Material.WoodPlanks,
			}, ctx.folder)
			table.insert(chunks, {
				p = p,
				from = from,
				delay = PULL - 0.35 + i * 0.06,
				spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6)),
			})
		end
		ctx.sound("BlackHoleSuck", H)
		local shotStart = os.clock()
		local shotLen = math.max(0.5, ctx.duration - (shotStart - t0))
		local collapsed = false
		ctx.runFor(shotLen, function(alpha: number)
			local t = os.clock() - shotStart
			-- wide head-on, slowly pushing in
			cam.CFrame = CFrame.lookAt(camA:Lerp(camB, ctx.ease(alpha)), G + Vector3.new(0, 4, 0):Lerp(H - G, 0.35))

			-- the hole streaks over from behind the camera and settles behind the victim, still
			-- growing at the same steady rate it has since the throw
			local arrive = math.clamp(t / 0.45, 0, 1)
			local holePos = (camA + Vector3.new(0, 4, 0)):Lerp(H, 1 - (1 - arrive) ^ 3)
			local r = SEED_R + GROW_RATE * (os.clock() - throwClock)
			local swell = math.clamp((r - 2) / 6, 0, 1)
			if t > shotLen - 0.35 then
				-- snaps shut
				local c = math.clamp((t - (shotLen - 0.35)) / 0.2, 0, 1)
				r = math.max(0.01, r * (1 - c))
				if not collapsed and c > 0.6 then
					collapsed = true
					ctx.fx.flash(H, Color3.fromRGB(230, 200, 255), 30)
					ctx.fx.shockwave(H, (camA - H).Unit, VIOLET, 60, 0.4)
					ctx.fx.shake(0.4)
					ctx.sound("BlackHoleForm", H)
				end
			end
			sizeHole(hole, r)
			placeHole(hole, holePos, t)
			dark.Brightness = -0.12 * swell
			dark.Contrast = 0.25 * swell
			dark.Saturation = -0.3 * swell
			if swell > 0 and swell < 1 then
				ctx.fx.shake(0.04)
			end

			-- the victim: sprints for the camera, loses ground, then is lifted, flailing, spinning,
			-- dragged in and crushed to nothing
			if proot and puppet then
				local turn = math.clamp((t - RUN_FROM) / 0.2, 0, 1)
				local runAmt = 1 - (1 - turn) ^ 2
				if t < PULL then
					local k = math.clamp((t - RUN_FROM) / (PULL - RUN_FROM), 0, 1)
					local bob = math.abs(math.sin(t * 17)) * 0.3 * runAmt
					local pos = standCF.Position + away * runOffset(t) + Vector3.new(0, bob, 0)
					-- leaning harder into it as the pull builds
					local lean = CFrame.Angles(-math.rad(14 + 20 * k) * runAmt, 0, 0)
					proot.CFrame = CFrame.new(pos) * standCF.Rotation:Lerp(runRot, runAmt) * lean
					local glance = math.sin(math.clamp((t - RUN_FROM) / 0.5, 0, 1) * math.pi)
					applyBlend(joints, runCycle(joints, t, glance), {}, 0, runAmt)
				else
					local u = math.clamp((t - PULL) / (shotLen - 0.4 - PULL), 0, 1)
					-- already sliding back, so it leaves with some speed and accelerates in
					local pull = 0.25 * u + 0.75 * u ^ 2.4
					local wobble = Vector3.new(math.sin(t * 9) * 0.6, math.sin(t * 7) * 0.4, 0)
					local pos = runEnd:Lerp(H, pull)
						+ Vector3.new(0, math.sin(math.min(1, u * 1.5) * math.pi * 0.5) * 3, 0)
						+ wobble * (1 - pull)
					-- yanked off their feet backward, then tumbling
					local yank = CFrame.Angles(math.rad(40) * math.min(1, u * 5), 0, 0)
					local spin = CFrame.Angles(u * u * 14, u * 9, u * u * 6)
					proot.CFrame = CFrame.new(pos) * runRot * yank * spin
					local toFlail = math.clamp((t - PULL) / 0.2, 0, 1)
					applyBlend(joints, runCycle(joints, t, 0), flail(joints, t), toFlail, 1)
					if u > 0.6 then
						local sc = math.max(0.02, 1 - (u - 0.6) / 0.4)
						pcall(function()
							(puppet :: any):ScaleTo(sc)
						end)
					end
				end
			end

			-- court chunks rip free and fall up into it
			for _, c in chunks do
				local u = math.clamp((t - c.delay) / 1.1, 0, 1)
				local e = u ^ 2
				c.p.CFrame = CFrame.new(c.from:Lerp(H, e)) * CFrame.Angles(c.spin.X * u, c.spin.Y * u, c.spin.Z * u)
				c.p.Transparency = if u >= 0.97 then 1 else 0
				if u > 0 and u < 0.05 and not (c :: any).popped then
					(c :: any).popped = true
					ctx.fx.burst(c.from, Color3.fromRGB(120, 90, 80), 6, 10, 0.6)
				end
			end
			if not (ctx :: any)._bhBanner and t > 1.6 then
				(ctx :: any)._bhBanner = true
				ctx.banner(("%s erased %s!"):format(ctx.killerName, ctx.victimName), VIOLET, 1.6)
			end
		end)
		dark:Destroy()
	end,
}
