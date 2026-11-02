--!strict
-- Supernova (Legendary): the winner turns their back on the victim and points at a distant sun. The
-- sun is sucked down to a point and goes out, and night falls. The point drops out of the sky into
-- the winner's hand, a condensed sun; they turn and hurl it into the victim's face. The world burns
-- brighter and brighter until only the victim's black silhouette is left on a pure white screen,
-- and then that fades away too. When the white clears, the spot where they stood is empty.
--
--   0.00-0.50  shot 1, from the victim's side: the winner turns around to face the sun behind them
--   0.50-1.30  shot 2, over their shoulder: they point at the sun (PointSky)
--   1.30-1.75  the sun collapses to a point and goes out (1.55): night falls
--   1.75-2.05  the point streaks down into the winner's raised hand, the camera tilting after it
--   2.05-2.40  shot 3, low in front: the condensed sun lights their face as they turn back
--   2.40-2.65  the throw: it streaks into the victim's face, the camera whipping round to meet it
--   2.65-3.75  impact: the light swells and the screen burns to white, the victim going black
--   3.75-4.20  pure white with only the silhouette left
--   4.20-4.60  the silhouette fades away
--   4.55-5.00  the white clears on the empty spot under the night sky
--
-- Nobody is launched (Stage.Launch = false): the victim is a local stand-in. The night is a local
-- change to Lighting, put back when the finisher's folder is destroyed, so it always comes back,
-- even if this errors or is cut off at the deadline. The silhouette is a ViewportFrame of black
-- copies of the stand-in's parts, filmed through the same camera, so it lines up with the world.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local TURN = 0.5
local POINT = 1.3 -- the sun starts to collapse
local NIGHT = 1.55 -- and goes out
local FALL = 1.75
local CATCH = 2.05
local THROW = 2.4
local IMPACT = 2.65
local WHITE_OUT = 3.75
local FADE = 4.2
local GONE = 4.6
local CLEAR = 4.55

local SUN_DIST = 380
local SUN_SIZE = 46 -- studs across, at SUN_DIST
local SUN_ELEVATION = math.rad(20)
local SUN_AZIMUTH = math.rad(14) -- off to one side, so the winner never hides it

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local GOLD = Color3.fromRGB(255, 214, 110)
local WHITE = Color3.fromRGB(255, 250, 235)
local CORONA = Color3.fromRGB(255, 150, 60)
local NIGHT_TINT = Color3.fromRGB(170, 185, 255)

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

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- A round frame centred in its parent, `scale` of its size.
local function disc(parent: Instance, scale: number, color: Color3, transparency: number, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(scale, scale)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

-- A glowing billboard (a white disc in gold and orange haloes) on an invisible anchor part. Billboards
-- aren't fogged by the atmosphere, so the sun reads at any distance. Returns the anchor, the
-- billboard and its outer halo layers (faded out when the sun goes out).
local function glowBillboard(ctx: any, at: Vector3, size: UDim2): (Part, BillboardGui, { Frame })
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(at) }, ctx.folder)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = anchor
	bb.Size = size
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb.Parent = anchor
	local halo = {
		disc(bb, 1, CORONA, 0.84, 1),
		disc(bb, 0.72, CORONA, 0.62, 2),
		disc(bb, 0.5, GOLD, 0.25, 3),
	}
	disc(bb, 0.34, WHITE, 0, 4)
	return anchor, bb, halo
end

-- The condensed sun: a white core in a gold glow, with a light, sparkles, a trail and a halo.
type Orb = { core: Part, glow: Part, light: PointLight, halo: BillboardGui, anchor: Part }
local function orb(ctx: any, at: Vector3): Orb
	local core = part(
		{ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Material = Enum.Material.Neon, Color = WHITE },
		ctx.folder
	)
	local glow = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.9,
		Material = Enum.Material.Neon,
		Color = GOLD,
		Transparency = 0.45,
	}, ctx.folder)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 22
	light.Brightness = 5
	light.Shadows = false
	light.Parent = core
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(WHITE, CORONA)
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.6, 0)
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = if ctx.reducedMotion then 15 else 45
	e.Parent = glow
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.5, 0)
	a0.Parent = glow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.5, 0)
	a1.Parent = glow
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(WHITE, CORONA)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.LightEmission = 1
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.Parent = glow
	-- a halo that's a fixed few pixels plus a few studs, so it's a bright dot far off and a glow up close
	local anchor, halo = glowBillboard(ctx, at, UDim2.new(5, 34, 5, 34))
	return { core = core, glow = glow, light = light, halo = halo, anchor = anchor }
end

local function placeOrb(o: Orb, at: Vector3, scale: number)
	o.core.Size = Vector3.one * 1.1 * scale
	o.glow.Size = Vector3.one * 1.9 * scale
	o.core.CFrame = CFrame.new(at)
	o.glow.CFrame = CFrame.new(at)
	o.anchor.CFrame = CFrame.new(at)
	o.halo.Size = UDim2.new(5 * scale, 34, 5 * scale, 34)
end

-- Night: the sky goes dark and starry and the court is lit blue. Saves Lighting first and puts it
-- back when the finisher's folder is destroyed.
local function nightKit(ctx: any): (() -> (), ColorCorrectionEffect)
	local Lighting = game:GetService("Lighting")
	local grade = FinisherKit.tint(0, 0)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local saved = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
	local savedAtmo = if atmo
		then { Color = atmo.Color, Decay = atmo.Decay, Glare = atmo.Glare, Haze = atmo.Haze }
		else nil
	ctx.folder.Destroying:Connect(function()
		grade:Destroy()
		for k, v in saved do
			(Lighting :: any)[k] = v
		end
		if atmo and savedAtmo and atmo.Parent then
			for k, v in savedAtmo do
				(atmo :: any)[k] = v
			end
		end
	end)
	local function fall()
		Lighting.ClockTime = 0
		Lighting.Brightness = 1
		Lighting.Ambient = Color3.fromRGB(38, 42, 72)
		Lighting.OutdoorAmbient = Color3.fromRGB(48, 56, 100)
		if atmo then
			atmo.Color = Color3.fromRGB(22, 26, 52)
			atmo.Decay = Color3.fromRGB(12, 14, 34)
			atmo.Glare = 0
			atmo.Haze = 0.2
		end
		-- a blink of black as the sun goes out, settling into a cool blue night
		grade.TintColor = NIGHT_TINT
		grade.Saturation = -0.15
		grade.Brightness = -0.55
		tween(grade, 0.5, { Brightness = -0.06 })
	end
	return fall, grade
end

-- A full-screen white sheet and, over it, the victim as a black silhouette. Both start invisible.
type Burn = {
	gui: ScreenGui,
	white: Frame,
	shadow: ViewportFrame,
	sync: (cam: Camera) -> (),
}
local function burnScreen(ctx: any, victim: Model?): Burn
	local gui = Instance.new("ScreenGui")
	gui.Name = "SupernovaBurn"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 14 -- under the letterbox bars
	gui.ResetOnSpawn = false
	local white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.BorderSizePixel = 0
	white.ZIndex = 1
	white.Parent = gui
	local shadow = Instance.new("ViewportFrame")
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundTransparency = 1
	shadow.Ambient = Color3.new(0, 0, 0)
	shadow.LightColor = Color3.new(0, 0, 0)
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 1
	shadow.ZIndex = 2
	shadow.Parent = gui
	local vcam = Instance.new("Camera")
	vcam.Parent = shadow
	shadow.CurrentCamera = vcam
	-- a black copy of every visible part, moved onto its original each frame
	local copies: { { from: BasePart, to: BasePart } } = {}
	if victim then
		for _, d in victim:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
				local ok, c = pcall(function()
					return d:Clone()
				end)
				if ok and c then
					for _, child in c:GetChildren() do
						if not child:IsA("DataModelMesh") then
							child:Destroy()
						end
					end
					c.Anchored = true
					c.Parent = shadow
					table.insert(copies, { from = d, to = c })
				end
			end
		end
	end
	local player = Players.LocalPlayer
	gui.Parent = player and player:FindFirstChildOfClass("PlayerGui")
	ctx.folder.Destroying:Connect(function()
		gui:Destroy()
	end)
	return {
		gui = gui,
		white = white,
		shadow = shadow,
		sync = function(cam: Camera)
			vcam.CFrame = cam.CFrame
			vcam.FieldOfView = cam.FieldOfView
			for _, c in copies do
				if c.from.Parent then
					c.to.CFrame = c.from.CFrame
				end
			end
		end,
	}
end

-- Where the victim stood: a scorched ring with embers and smoke rising off it.
local function scorch(ctx: any, ground: Vector3)
	local ring = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 7, 7),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = CORONA,
		Transparency = 0.3,
	}, ctx.folder)
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 5.5, 5.5),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(20, 16, 14),
	}, ctx.folder)
	tween(ring, 1.2, { Transparency = 0.85 })
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = SPARK
	embers.Color = ColorSequence.new(GOLD, CORONA)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.3, 0)
	embers.Lifetime = NumberRange.new(0.8, 1.6)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.Rate = if ctx.reducedMotion then 12 else 40
	embers.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis: straight up
	embers.Parent = ring
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 56, 64))
	smoke.Size = NumberSequence.new(1.2, 3)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Speed = NumberRange.new(1.5, 3)
	smoke.Rate = if ctx.reducedMotion then 5 else 12
	smoke.EmissionDirection = Enum.NormalId.Right
	smoke.Parent = ring
end

return {
	Id = "Supernova",
	Name = "Supernova",
	Duration = 5.0,
	-- nobody is launched: the victim burns away on a local copy
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		if not killerRoot then
			task.wait(ctx.duration)
			return
		end
		local function waitUntil(t: number)
			task.wait(math.max(0, t - (os.clock() - t0)))
		end
		local function phase(from: number, to: number, fn: (number) -> ())
			ctx.runFor(math.max(0.05, to - (os.clock() - t0)), function()
				local t = os.clock() - t0
				fn(math.clamp((t - from) / (to - from), 0, 1))
			end)
		end

		-- geometry: the winner faces the victim; the sun hangs low in the sky behind the winner
		local P = killerRoot.Position
		local f = FinisherKit.facing(killerRoot)
		local V = if victimRoot then victimRoot.Position else P + f * 30
		local side = f:Cross(Vector3.yAxis)
		local back = -f * math.cos(SUN_AZIMUTH) + side * math.sin(SUN_AZIMUTH)
		local sunDir = back * math.cos(SUN_ELEVATION) + Vector3.yAxis * math.sin(SUN_ELEVATION)
		local sunPos = P + sunDir * SUN_DIST
		local right = back:Cross(Vector3.yAxis) -- the winner's right once they face the sun

		local hero = ctx.standIn(ctx.killer)
		local heroRoot = hero and hero:FindFirstChild("HumanoidRootPart") :: BasePart?
		local poser = hero or ctx.killer
		local towardVictim = CFrame.lookAt(P, P + f)
		local towardSun = CFrame.lookAt(P, P + back)
		local function hand(): Vector3
			local h = poser and poser:FindFirstChild("RightHand") :: BasePart?
			return if h then h.Position else P + Vector3.new(0, 2.5, 0)
		end

		-- the victim's copy waits facing the winner
		local puppet = if victimRoot then ctx.standIn(ctx.victim) else nil
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		local standing = CFrame.lookAt(V, V - f)
		if proot then
			proot.CFrame = standing
		end
		if ctx.victim then
			ctx.hide(ctx.victim)
		end
		local head = puppet and puppet:FindFirstChild("Head") :: BasePart?
		local face = (if head then head.Position else V + Vector3.new(0, 1.6, 0)) - f * 0.7

		local sunAnchor, sunBoard, sunHalo = glowBillboard(ctx, sunPos, UDim2.fromScale(SUN_SIZE, SUN_SIZE))
		local nightfall, grade = nightKit(ctx)

		-- Shot 1: the winner turns their back on the victim, toward the sun ---------------------------
		ctx.sound("SupernovaPoint")
		phase(0, TURN, function(k: number)
			if heroRoot then
				heroRoot.CFrame = towardVictim:Lerp(towardSun, ctx.ease(k))
			end
			local camPos = P + f * (12 - 1.5 * k) - side * 3.2 + Vector3.new(0, 0.8, 0)
			cam.CFrame = CFrame.lookAt(camPos, P + Vector3.new(0, 2.6 + 2 * k, 0))
		end)

		-- Shot 2: over their shoulder, pointing at the sun; it collapses and night falls -------------
		ctx.pose(poser, "PointSky", 0.25)
		local camBack = P - back * 6.5 + right * 2.4 + Vector3.new(0, 0.6, 0)
		local wentOut, dark = false, false
		phase(TURN, FALL, function(k: number)
			local t = os.clock() - t0
			-- a slow push-in toward the sun
			local camPos = camBack + back * (1.6 * smooth(k))
			cam.CFrame = CFrame.lookAt(camPos, sunPos)
			-- the sun throbs, then swells and is sucked down to a point
			local size = SUN_SIZE * (1 + 0.04 * math.sin(t * 14))
			if t >= POINT then
				local c = math.clamp((t - POINT) / (NIGHT - POINT), 0, 1)
				size = SUN_SIZE * math.max(0.05, (1 + 0.25 * math.sin(c * math.pi)) * (1 - c * c))
			end
			sunBoard.Size = UDim2.fromScale(size, size)
			if t >= POINT and not wentOut then
				-- (fires once, on the collapse's first frame)
				wentOut = true
				ctx.sound("SupernovaSunOut")
			end
			if t >= NIGHT and not dark then
				dark = true
				for _, h in sunHalo do
					h.BackgroundTransparency = 1
				end
				nightfall()
			end
		end)
		if not dark then
			nightfall() -- (no frame landed between NIGHT and FALL)
		end

		-- The point drops out of the sky into the winner's hand ---------------------------------------
		sunAnchor:Destroy()
		local star = orb(ctx, sunPos)
		ctx.sound("SupernovaCatch")
		local camNow = cam.CFrame.Position
		phase(FALL, CATCH, function(k: number)
			local at = sunPos:Lerp(hand(), k * k)
			placeOrb(star, at, 0.5 + 0.5 * k)
			cam.CFrame = CFrame.lookAt(camNow, sunPos:Lerp(hand(), smooth(k * 1.2)))
		end)
		ctx.fx.flash(hand(), WHITE, 5)
		ctx.pose(poser, "WindUp", 0.2)

		-- Shot 3: low in front, the condensed sun lighting their face as they turn back --------------
		phase(CATCH, THROW, function(k: number)
			if heroRoot then
				heroRoot.CFrame = towardSun:Lerp(towardVictim, ctx.ease(math.min(1, k * 1.4)))
			end
			placeOrb(star, hand() + Vector3.new(0, 0.3, 0), 1 + 0.06 * math.sin(k * 30))
			local camPos = P + f * (7.5 - 1 * k) + side * 2.2 + Vector3.new(0, -0.3, 0)
			cam.CFrame = CFrame.lookAt(camPos, P + Vector3.new(0, 1.9, 0))
		end)

		if not puppet or not victimRoot then
			-- nobody to throw it at: hold it aloft until the end
			ctx.runFor(math.max(0.1, ctx.duration - (os.clock() - t0)), function()
				placeOrb(star, hand() + Vector3.new(0, 0.3, 0), 1)
			end)
			return
		end

		-- The throw: straight into the victim's face, the camera whipping round to meet it -----------
		ctx.pose(poser, "ThrowFollow", 0.08)
		local from = hand() + Vector3.new(0, 0.3, 0)
		local camFrom = cam.CFrame.Position
		local faceCam = face - f * 5.5 + side * 1.6 + Vector3.new(0, 0.2, 0)
		phase(THROW, IMPACT, function(k: number)
			local at = from:Lerp(face, k) + Vector3.new(0, math.sin(k * math.pi) * 1.5, 0)
			placeOrb(star, at, 1)
			cam.CFrame = CFrame.lookAt(camFrom:Lerp(faceCam, ctx.ease(k)), at:Lerp(face, ctx.ease(k)))
		end)

		-- Impact: the light swells and everything burns to white ----------------------------------------
		ctx.sound("SupernovaBurn", face)
		ctx.fx.flash(face, WHITE, 7)
		if not ctx.reducedMotion then
			ctx.fx.shake(0.5)
		end
		ctx.pose(puppet, "Catch", 0.06) -- hands up at the face
		star.light.Range = 40
		star.light.Brightness = 8
		local burn = burnScreen(ctx, puppet)
		local gradeFrom = grade.Brightness
		phase(IMPACT, WHITE_OUT, function(k: number)
			placeOrb(star, face, 1 + 5 * k ^ 1.5)
			star.light.Range = 40 + 20 * k
			if proot then
				proot.CFrame = standing * CFrame.Angles(math.rad(10 + 14 * smooth(k)), 0, 0)
			end
			-- brighter and brighter: the world washes out, then the white sheet takes over
			grade.Brightness = gradeFrom + (0.9 - gradeFrom) * k ^ 1.4
			grade.Saturation = -0.15 - 0.6 * k
			burn.white.BackgroundTransparency = 1 - k ^ 2.5
			burn.shadow.ImageTransparency = 1 - smooth((k - 0.35) / 0.55)
			cam.CFrame = CFrame.lookAt(faceCam:Lerp(face, 0.15 * smooth(k)), face)
			burn.sync(cam)
		end)
		burn.white.BackgroundTransparency = 0
		burn.shadow.ImageTransparency = 0
		burn.sync(cam)

		-- Pure white with only the silhouette; behind it the victim and the star are gone and the night
		-- comes back, ready for the white to clear
		star.core:Destroy()
		star.glow:Destroy()
		star.anchor:Destroy()
		local ground = Vector3.new(V.X, V.Y - 2.9, V.Z)
		scorch(ctx, ground)
		grade.Brightness = -0.06
		grade.Saturation = -0.15
		waitUntil(FADE)

		-- The silhouette fades away, then the white clears on the empty spot --------------------------
		ctx.hide(puppet)
		local wide = V - f * 13 + side * 4 + Vector3.new(0, 2.5, 0)
		local holdCam = cam.CFrame
		phase(FADE, ctx.duration - 0.02, function()
			local t = os.clock() - t0
			burn.shadow.ImageTransparency = math.clamp((t - FADE) / (GONE - FADE), 0, 1)
			local c = math.clamp((t - CLEAR) / (ctx.duration - 0.05 - CLEAR), 0, 1)
			burn.white.BackgroundTransparency = smooth(c)
			cam.CFrame = holdCam:Lerp(CFrame.lookAt(wide, V), ctx.ease(c))
		end)
		burn.white.BackgroundTransparency = 1
	end,
}
