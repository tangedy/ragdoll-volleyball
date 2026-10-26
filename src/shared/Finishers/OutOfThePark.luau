--!strict
-- Out of the Park: the winner flips up a red dodgeball that pops into a baseball at the top of the
-- toss, winds up a wooden bat to the ballpark organ's "Charge!" and smashes it across the court.
-- Time freezes on a monochrome impact frame as the ball meets the victim's face (SMACK!), then they
-- rocket clean out of the arena to a stadium cheer and vanish with a twinkle on the horizon.
--
--   0.00-0.45  over the winner's shoulder: the toss; at the apex the dodgeball morphs into a baseball
--   0.45-1.05  low angle from behind the batter, looking up: the bat loads, the ball hangs and drops
--   1.05-1.20  the swing; 1.20 CRACK at the sweet spot
--   1.20-1.70  whip pan after the ball: a comet trail with spiral wind lines streaking at the victim
--   1.70-2.00  frozen impact frame: extreme close-up, monochrome strobe, SMACK!, suspended debris
--   2.00-3.70  time resumes: the victim is launched off the arena; OUT OF THE PARK! and confetti
--   3.70-5.00  a twinkle on the horizon where they vanish while the crowd keeps cheering
--
-- The victim is a local stand-in (the real one is hidden and the server doesn't launch them).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MORPH = 0.45
local SWING = 1.05
local CONTACT = 1.2
local FACE = 1.7
local UNFREEZE = 2.0
local TITLE = 2.55
local TWINKLE = 3.7

local FLY_DIST = 260 -- how far off the arena the victim sails before the twinkle
local FLY_UP = 90

local BALL_RED = Color3.fromRGB(214, 48, 49)
local LEATHER = Color3.fromRGB(245, 242, 232)
local STITCH = Color3.fromRGB(200, 30, 35)
local WOOD = Color3.fromRGB(196, 146, 88)
local WHITE = Color3.new(1, 1, 1)
local CRACK_YELLOW = Color3.fromRGB(255, 220, 60)
local DUST = Color3.fromRGB(225, 215, 190)
local CONFETTI = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 210, 50),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(90, 220, 110),
}

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

local function tween(
	inst: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		:Play()
end

local function trail(parent: BasePart, a: Vector3, b: Vector3, life: number, color: ColorSequence): Trail
	local a0 = Instance.new("Attachment")
	a0.Position = a
	a0.Parent = parent
	local a1 = Instance.new("Attachment")
	a1.Position = b
	a1.Parent = parent
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = life
	t.LightEmission = 1
	t.FaceCamera = true
	t.Color = color
	t.Transparency = NumberSequence.new(0, 1)
	t.Enabled = false
	t.Parent = parent
	return t
end

-- The baseball: a white leather sphere (squashable through its mesh) with two red seam bands, made
-- from discs just wider than the ball so only a thin ring shows. Returns a mover and the trails.
type Baseball = {
	ball: Part,
	mesh: SpecialMesh,
	place: (CFrame) -> (),
	show: (boolean) -> (),
	seams: (boolean) -> (),
	trails: { Trail },
}
local SEAM_OFFSETS = {
	CFrame.Angles(0, math.rad(30), math.rad(22)),
	CFrame.Angles(0, math.rad(-30), math.rad(-22)),
}
local function makeBaseball(ctx: any): Baseball
	local ball = part({ Size = Vector3.one * 0.9, Material = Enum.Material.SmoothPlastic, Color = LEATHER }, ctx.folder)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = ball
	local seamParts: { Part } = {}
	for _ = 1, #SEAM_OFFSETS do
		table.insert(
			seamParts,
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.05, 0.95, 0.95),
				Material = Enum.Material.SmoothPlastic,
				Color = STITCH,
			}, ctx.folder)
		)
	end
	-- the comet: a fat white streak, plus two thin ribbons off-axis that corkscrew as the ball spins
	local trails = {
		trail(ball, Vector3.new(0, 0.45, 0), Vector3.new(0, -0.45, 0), 0.22, ColorSequence.new(WHITE, CRACK_YELLOW)),
		trail(ball, Vector3.new(1, 0, 0), Vector3.new(1.08, 0, 0), 0.3, ColorSequence.new(WHITE)),
		trail(ball, Vector3.new(-1, 0, 0), Vector3.new(-1.08, 0, 0), 0.3, ColorSequence.new(WHITE)),
	}
	local self: Baseball
	self = {
		ball = ball,
		mesh = mesh,
		trails = trails,
		place = function(cf: CFrame)
			ball.CFrame = cf
			for i, s in seamParts do
				s.CFrame = cf * SEAM_OFFSETS[i]
			end
		end,
		show = function(on: boolean)
			ball.Transparency = if on then 0 else 1
			self.seams(on)
		end,
		seams = function(on: boolean)
			for _, s in seamParts do
				s.Transparency = if on then 0 else 1
			end
		end,
	}
	self.show(false)
	return self
end

-- A wooden bat: knob, handle, then a barrel that thickens toward the end.
local function makeBat(ctx: any): (Vector3, Vector3) -> ()
	local pieces = {
		{ len = 0.12, dia = 0.42, at = 0.06 }, -- knob
		{ len = 1.4, dia = 0.24, at = 0.82 }, -- handle
		{ len = 0.7, dia = 0.36, at = 1.85 }, -- taper
		{ len = 1.3, dia = 0.5, at = 2.85 }, -- barrel
	}
	local parts: { Part } = {}
	for _, p in pieces do
		table.insert(
			parts,
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(p.len, p.dia, p.dia),
				Material = Enum.Material.Wood,
				Color = WOOD,
			}, ctx.folder)
		)
	end
	-- grip: where the hands hold it; dir: the bat's axis, knob to tip
	return function(grip: Vector3, dir: Vector3)
		-- a cylinder's axis is X; turn the look direction onto it
		local base = CFrame.lookAt(grip, grip + dir) * CFrame.Angles(0, math.rad(90), 0)
		for i, p in pieces do
			parts[i].CFrame = base * CFrame.new(p.at - 0.4, 0, 0)
		end
	end
end

-- On-screen comic text, cleaned up with the finisher's folder. `burst` puts a jagged white starburst
-- behind it (two overlapping squares); the drop shadow gives the stadium lettering its depth.
local function overlay(ctx: any): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "OutOfTheParkFX"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14 -- under the letterbox bars
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ctx.folder.Destroying:Connect(function()
		gui:Destroy()
	end)
	return gui
end

local function comicText(
	gui: ScreenGui,
	text: string,
	pos: UDim2,
	size: UDim2,
	rotation: number,
	fill: Color3,
	stroke: Color3,
	burst: boolean
): (Frame, UIScale)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = pos
	holder.Size = size
	holder.Rotation = rotation
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = holder
	if burst then
		for i, r in { 0, 45 } do
			local sq = Instance.new("Frame")
			sq.AnchorPoint = Vector2.new(0.5, 0.5)
			sq.Position = UDim2.fromScale(0.5, 0.5)
			sq.Size = UDim2.fromScale(1.15, 1.15)
			sq.SizeConstraint = Enum.SizeConstraint.RelativeYY
			sq.Rotation = r + 10
			sq.BackgroundColor3 = if i == 1 then CRACK_YELLOW else WHITE
			sq.BorderSizePixel = 0
			sq.ZIndex = 1
			local edge = Instance.new("UIStroke")
			edge.Thickness = 4
			edge.Color = Color3.new(0, 0, 0)
			edge.Parent = sq
			sq.Parent = holder
		end
	end
	for _, layer in { "shadow", "face" } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Position = if layer == "shadow" then UDim2.fromOffset(5, 7) else UDim2.fromOffset(0, 0)
		label.Font = Enum.Font.LuckiestGuy
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = if layer == "shadow" then Color3.fromRGB(40, 10, 10) else fill
		label.ZIndex = if layer == "shadow" then 2 else 3
		local s = Instance.new("UIStroke")
		s.Thickness = 5
		s.Color = if layer == "shadow" then Color3.fromRGB(40, 10, 10) else stroke
		s.Parent = label
		label.Parent = holder
	end
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	return holder, scale
end

-- A four-point twinkle star pinned to a far-off spot (fixed pixel size, so it shows at any distance).
local function twinkle(ctx: any, at: Vector3)
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1, Position = at }, ctx.folder)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(110, 110)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = anchor
	local spin = Instance.new("Frame")
	spin.AnchorPoint = Vector2.new(0.5, 0.5)
	spin.Position = UDim2.fromScale(0.5, 0.5)
	spin.Size = UDim2.fromScale(1, 1)
	spin.BackgroundTransparency = 1
	spin.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = spin
	for _, s in { { 1, 0.07, 0 }, { 0.07, 1, 0 }, { 0.55, 0.05, 45 }, { 0.05, 0.55, 45 } } do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(s[1], s[2])
		ray.Rotation = s[3]
		ray.BackgroundColor3 = WHITE
		ray.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ray
		local glow = Instance.new("UIStroke")
		glow.Color = CRACK_YELLOW
		glow.Thickness = 2
		glow.Parent = ray
		ray.Parent = spin
	end
	tween(scale, 0.18, { Scale = 1.3 }, Enum.EasingStyle.Back)
	tween(spin, 0.6, { Rotation = 120 }, Enum.EasingStyle.Linear)
	task.delay(0.25, function()
		tween(scale, 0.35, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
end

-- Confetti showering down in front of the camera.
local function confetti(ctx: any, at: Vector3)
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1, Position = at }, ctx.folder)
	for _, color in CONFETTI do
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.3
		e.Size = NumberSequence.new(0.35)
		e.Squash = NumberSequence.new(-0.6, 0.6)
		e.Lifetime = NumberRange.new(1.6, 2.6)
		e.Speed = NumberRange.new(12, 24)
		e.SpreadAngle = Vector2.new(70, 70)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -16, 0)
		e.Drag = 1.5
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-360, 360)
		e.Rate = 0
		e.Parent = anchor
		e:Emit(if ctx.reducedMotion then 10 else 30)
	end
end

-- The frozen impact frame: monochrome with yellow and red highlights, strobing for ~200 ms, then
-- held drained until time resumes. Reduced motion gets one soft flash instead of the strobe.
local function impactFrames(ctx: any, cc: ColorCorrectionEffect)
	if ctx.reducedMotion then
		ctx.fx.screenFlash(WHITE, 0.5, 0.3)
		cc.Saturation = -0.6
		return
	end
	ctx.fx.screenFlash(WHITE, 1, 0.05)
	task.wait(0.03)
	cc.Saturation = -1
	cc.Contrast = 3
	cc.Brightness = -0.15
	cc.TintColor = Color3.fromRGB(255, 232, 130)
	task.wait(0.07)
	cc.Brightness = 0.5
	cc.Contrast = 2.2
	cc.TintColor = WHITE
	task.wait(0.06)
	cc.Brightness = -0.25
	cc.Contrast = 3
	cc.TintColor = Color3.fromRGB(255, 120, 110)
	task.wait(0.06)
	cc.Saturation = -0.85
	cc.Contrast = 1.4
	cc.Brightness = 0
	cc.TintColor = Color3.fromRGB(255, 240, 200)
end

return {
	Id = "OutOfThePark",
	Name = "Out of the Park!",
	Duration = 5,
	-- the server leaves the victim standing; the home run is played on a local puppet
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local rng = Random.new()
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		if not killerRoot or not victimRoot then
			task.wait(ctx.duration)
			return
		end
		local reduced = ctx.reducedMotion
		local function phase(tEnd: number, fn: (number, number) -> ())
			ctx.runFor(math.max(0.01, tEnd - (os.clock() - t0)), function(_alpha: number, dt: number)
				fn(os.clock() - t0, dt)
			end)
		end

		-- geometry: the winner faces the victim across the net; `side` is the winner's right
		local up = Vector3.yAxis
		local K = killerRoot.Position
		local V = victimRoot.Position
		local f = Vector3.new(V.X - K.X, 0, V.Z - K.Z)
		f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
		local side = f:Cross(up)
		local o = ctx.outward :: Vector3
		local launchDir = f + o
		launchDir = if launchDir.Magnitude > 0.1 then launchDir.Unit else f

		local hero = ctx.standIn(ctx.killer) or ctx.killer
		local heroCF = CFrame.lookAt(K, K + f)
		local function turnHero(yaw: number)
			pcall(function()
				hero:PivotTo(heroCF * CFrame.Angles(0, math.rad(yaw), 0))
			end)
		end
		turnHero(0)
		local leftHand = hero:FindFirstChild("LeftHand") :: BasePart?
		local rightHand = hero:FindFirstChild("RightHand") :: BasePart?

		local puppet = ctx.standIn(ctx.victim)
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		local victimCF = CFrame.lookAt(V, V - f)
		if proot then
			proot.CFrame = victimCF
		end
		-- the victim's face, toward the batter
		local F = V + up * 1.6 - f * 0.7

		local cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = Lighting
		ctx.folder.Destroying:Connect(function()
			cc:Destroy() -- always cleaned up, even if the finisher errors
		end)
		local gui = overlay(ctx)

		-- the swing: the bat sweeps around a pivot at the shoulders. phi = 90 points it straight back,
		-- 0 out to the right (contact, moving toward the victim), -90 at the victim, then round left.
		local pivot = K + up * 1.3 + f * 0.2
		local function batDir(phi: number, tilt: number): Vector3
			local r = math.rad(phi)
			return (side * math.cos(r) - f * math.sin(r) + up * tilt).Unit
		end
		local placeBat = makeBat(ctx)
		local function swingBat(phi: number, tilt: number, yaw: number)
			local dir = batDir(phi, tilt)
			local grip = if rightHand then rightHand.Position else pivot + dir * 0.9
			placeBat(grip, dir)
			turnHero(yaw)
		end
		local SWEET = 3.4 -- grip-to-sweet-spot
		local C = pivot + side * (0.9 + SWEET) -- where the ball is met

		-- Phase 1: the toss, the morph, the wind-up ------------------------------------------------
		local toss = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, Color = BALL_RED }, ctx.folder)
		local tossFrom = if leftHand then leftHand.Position else K + up * 0.6 + f * 0.8 - side * 0.6
		local apex = K + up * 5.2 + f * 1.2 + side * 1.8
		local baseball = makeBaseball(ctx)
		ctx.pose(hero, "ReachOut", 0.1)
		ctx.sound("ParkToss")
		ctx.sound("ParkCharge")

		local camA0 = K - f * 5.5 - side * 2.4 + up * 2.6
		local camA1 = K - f * 4.6 - side * 2 + up * 2.2
		phase(MORPH, function(t: number)
			local u = t / MORPH
			local pos = tossFrom:Lerp(apex, 1 - (1 - u) ^ 2)
			toss.CFrame = CFrame.new(pos) * CFrame.Angles(u * 6, u * 3, 0)
			swingBat(30, -0.9, 0)
			cam.CFrame = CFrame.lookAt(camA0:Lerp(camA1, ctx.ease(u)), (K + up * 2.5 + f * 3):Lerp(pos, 0.5))
		end)

		-- the morph: the dodgeball shrivels and hardens into a baseball in a poof of comic dust
		ctx.sound("ParkMorph")
		tween(toss, 0.06, { Size = Vector3.one * 0.5, Color = LEATHER })
		task.delay(0.06, function()
			toss:Destroy()
		end)
		baseball.show(true)
		baseball.mesh.Scale = Vector3.one * 1.8
		tween(baseball.mesh, 0.18, { Scale = Vector3.one }, Enum.EasingStyle.Back)
		ctx.fx.burst(apex, DUST, if reduced then 8 else 18, 7, 0.9)
		ctx.fx.flash(apex, CRACK_YELLOW, 3)
		ctx.pose(hero, "WindUp", 0.15)
		ctx.sound("ParkBatLoad")

		local camB = K - f * 3.6 + side * 3.4 - up * 2.3 -- low, behind the batter, looking up
		local camBFrom = cam.CFrame
		cam.FieldOfView = if reduced then 72 else 80
		phase(SWING, function(t: number)
			local u = (t - MORPH) / (SWING - MORPH)
			-- hangs at the top, then drops into the zone
			local pos = apex:Lerp(C, u * u)
			baseball.place(CFrame.new(pos) * CFrame.Angles(t * 4, t * 2, 0))
			local load = ctx.ease(math.min(1, u * 1.6))
			swingBat(30 + 95 * load, -0.9 + 1.8 * load, -28 * load + math.sin(t * 30) * 1.5 * load)
			local target = pos:Lerp(K + up * 2 + side * 1.5, 0.45)
			if reduced then
				cam.CFrame =
					camBFrom:Lerp(CFrame.lookAt(camB + up * 1.6 - f * 1.5, target), ctx.ease(math.min(1, u * 1.5)))
			else
				cam.CFrame = CFrame.lookAt(camB:Lerp(camB + f * 0.8, u), target)
			end
		end)

		-- Phase 2: the swing and the hit -------------------------------------------------------------
		ctx.sound("ParkSwing")
		ctx.pose(hero, "Catch", 0.08)
		phase(CONTACT, function(t: number)
			local u = (t - SWING) / (CONTACT - SWING)
			baseball.place(CFrame.new(C) * CFrame.Angles(t * 4, t * 2, 0)) -- waiting in the zone
			local e = u * u -- accelerating through the zone
			swingBat(125 - 125 * e, 0.9 - 0.9 * e, -28 + 28 * e)
		end)
		ctx.sound("ParkCrack")
		ctx.fx.flash(C, WHITE, 5)
		ctx.fx.shockwave(C, f, CRACK_YELLOW, 10, 0.25)
		ctx.fx.shockwave(C, f, WHITE, 16, 0.35)
		ctx.fx.burst(C, CRACK_YELLOW, if reduced then 8 else 22, 30, 0.6)
		ctx.fx.shake(0.5)
		ctx.pose(hero, "ThrowFollow", 0.06)
		for _, tr in baseball.trails do
			tr.Enabled = true
		end

		-- the flight: a whip pan after the ball as it streaks at the victim's face
		local flightFrom = cam.CFrame
		local nextDust = 0
		local flinched = false
		phase(FACE, function(t: number)
			local u = (t - CONTACT) / (FACE - CONTACT)
			local pos = C:Lerp(F, u)
			-- spin around the flight axis so the side ribbons corkscrew
			baseball.place(CFrame.lookAt(pos, pos + (F - C)) * CFrame.Angles(0, 0, t * 45))
			-- follow-through
			local fu = math.min(1, (t - CONTACT) / 0.25)
			local fe = 1 - (1 - fu) ^ 3
			swingBat(-160 * fe, 0.6 * fe, 35 * fe)
			if t >= nextDust and not reduced then
				nextDust = t + 0.05
				ctx.fx.burst(pos, DUST, 3, 4, 0.5)
			end
			if not flinched and u > 0.6 then
				flinched = true
				ctx.pose(puppet, "ArmsSpread", 0.1)
			end
			local chase = if reduced
				then CFrame.lookAt(pos - f * 10 + side * 8 + up * 3, pos + f * 4)
				else CFrame.lookAt(pos - f * 6 + side * 2.5 + up * 1.2, pos + f * 6)
			local k = math.min(1, (t - CONTACT) / (if reduced then 0.3 else 0.1))
			cam.CFrame = flightFrom:Lerp(chase, 1 - (1 - k) ^ 2)
			cam.FieldOfView = if reduced then 72 else 80 + 15 * k
		end)

		-- Phase 3: the frozen impact ------------------------------------------------------------------
		for _, tr in baseball.trails do
			tr.Enabled = false
		end
		ctx.sound("ParkSmack")
		-- the ball pressed flat into the face, which is shoved back with it
		baseball.seams(false)
		baseball.place(CFrame.lookAt(F, F + f))
		baseball.mesh.Scale = Vector3.new(1.5, 1.5, 0.45)
		if proot then
			proot.CFrame = victimCF * CFrame.new(0, 0, -0.3) * CFrame.Angles(math.rad(22), 0, math.rad(-6))
		end
		ctx.pose(puppet, "LookUp", 0.02)
		local closeCam = if reduced
			then CFrame.lookAt(F + side * 6 - f * 3 + up * 1, F)
			else CFrame.lookAt(F + side * 2.4 - f * 1.2 + up * 0.2, F)
		cam.CFrame = closeCam
		cam.FieldOfView = if reduced then 60 else 45
		-- sweat, spit and stars hanging in the air around the hit
		local debris: { { p: Part, dir: Vector3 } } = {}
		for i = 1, (if reduced then 6 else 16) do
			local dir = (rng:NextUnitVector() - f * 0.6).Unit
			local star = i % 3 == 0
			local p = part({
				Shape = if star then Enum.PartType.Block else Enum.PartType.Ball,
				Size = if star then Vector3.one * 0.22 else Vector3.one * rng:NextNumber(0.1, 0.2),
				Material = if star then Enum.Material.Neon else Enum.Material.Glass,
				Color = if star then CRACK_YELLOW else Color3.fromRGB(190, 225, 255),
				Transparency = if star then 0 else 0.3,
				CFrame = CFrame.new(F + dir * rng:NextNumber(0.5, 2.2)) * CFrame.Angles(0, math.rad(45), math.rad(45)),
			}, ctx.folder)
			table.insert(debris, { p = p, dir = dir })
		end
		local toCam = (closeCam.Position - F).Unit
		ctx.fx.shockwave(F, toCam, CRACK_YELLOW, 7, 0.3)
		ctx.fx.shockwave(F, toCam, Color3.fromRGB(255, 80, 70), 11, 0.3)
		ctx.fx.shake(0.6)
		local screen = cam:WorldToViewportPoint(F)
		local smack = comicText(
			gui,
			"SMACK!",
			UDim2.fromOffset(screen.X - 40, screen.Y - 60),
			UDim2.fromScale(0.3, 0.17),
			-14,
			CRACK_YELLOW,
			Color3.fromRGB(200, 20, 20),
			true
		)
		task.spawn(impactFrames, ctx, cc)
		phase(UNFREEZE, function(t: number)
			-- the world is paused: only the camera creeps in
			local u = (t - FACE) / (UNFREEZE - FACE)
			cam.CFrame = closeCam * CFrame.new(0, 0, -0.3 * u)
		end)

		-- Phase 4: out of the park -----------------------------------------------------------------
		tween(cc, 0.15, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE })
		smack:Destroy()
		baseball.show(false)
		for _, d in debris do
			tween(d.p, 0.5, { Position = d.p.Position + d.dir * 8, Transparency = 1 })
		end
		ctx.sound("ParkLaunch")
		ctx.sound("ParkCheer")
		ctx.fx.shake(0.4)
		ctx.fx.burst(F, WHITE, if reduced then 6 else 16, 25, 0.8)
		local streak = proot
			and trail(proot, Vector3.new(0, 1, 0), Vector3.new(0, -1, 0), 0.7, ColorSequence.new(WHITE))
		if streak then
			streak.Enabled = true
		end
		local launchFrom = if proot then proot.Position else V
		local function flyPos(u: number): Vector3
			local e = 1 - (1 - u) ^ 2.2
			return launchFrom + launchDir * FLY_DIST * e + up * FLY_UP * e
		end
		local wide = V - launchDir * 16 + side * 14 + up * 6
		local flailAt = 0
		local flailArms = false
		local titled = false
		phase(TWINKLE, function(t: number)
			local u = (t - UNFREEZE) / (TWINKLE - UNFREEZE)
			local pos = flyPos(u)
			if proot then
				proot.CFrame = CFrame.lookAt(pos, pos - launchDir) * CFrame.Angles(u * 16, u * 7, u * 11)
			end
			if t >= flailAt then
				flailAt = t + 0.13
				flailArms = not flailArms
				ctx.pose(puppet, if flailArms then "ArmsUp" else "ArmsSpread", 0.08)
			end
			if not titled and t >= TITLE then
				titled = true
				comicText(
					gui,
					"OUT OF THE PARK!",
					UDim2.fromScale(0.5, 0.42),
					UDim2.fromScale(0.75, 0.2),
					-5,
					Color3.fromRGB(255, 236, 120),
					Color3.fromRGB(190, 25, 30),
					false
				)
				confetti(ctx, (cam.CFrame * CFrame.new(0, 5, -14)).Position)
			end
			local pull = ctx.ease(math.min(1, (t - UNFREEZE) / 0.5))
			cam.CFrame = CFrame.lookAt(closeCam.Position:Lerp(wide, pull), pos)
			cam.FieldOfView = 60 - 10 * u
		end)

		-- the twinkle: gone past the horizon -----------------------------------------------------------
		local gone = flyPos(1)
		if puppet then
			ctx.hide(puppet)
		end
		ctx.sound("ParkTwinkle")
		twinkle(ctx, gone)
		phase(ctx.duration - 0.05, function(t: number)
			local u = (t - TWINKLE) / (ctx.duration - TWINKLE)
			cam.CFrame = CFrame.lookAt(wide + (gone - wide).Unit * 2 * u, gone)
		end)
	end,
}
