--!strict
-- Meteor Strike: the winner calmly crosses their arms while a giant flaming dodgeball breaks
-- through the clouds above them; cut to the victim as it slams down and blasts them off the court.
--
--   0.0-2.4  shot 1, one continuous eased move on the winner: push in, drop low, tilt up. Arms
--            cross; in the open sky above, light glows through a cloud layer, then the meteor
--            punches through (burst + light rays) and keeps coming
--   2.4-3.0  shot 2, low angle on the victim: the meteor slams down onto the target sigil
--   3.0      impact: white flash, two-tone impact frames, a beat of freeze, shockwaves, embers
--            (the server launches the victim at this moment)
--   3.0-4.8  shot 3: the camera follows the victim flying off

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local CUT = 2.4 -- shot 1 -> shot 2
local IMPACT = 3.0
local METEOR_RADIUS = 7

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local ORANGE = Color3.fromRGB(255, 140, 30)
local GOLD = Color3.fromRGB(255, 210, 90)
local RED = Color3.fromRGB(214, 48, 49)
local CLOUD = Color3.fromRGB(140, 126, 178)

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

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- Golden aura and rising embers around the winner while they pose.
local function aura(ctx: any, root: BasePart)
	local glow = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 6,
		CFrame = root.CFrame,
		Material = Enum.Material.ForceField,
		Color = GOLD,
		Transparency = 0.2,
	}, ctx.folder)
	local a = Instance.new("Attachment")
	a.Parent = glow
	emitter(a, {
		Texture = SPARK,
		Color = ColorSequence.new(GOLD, ORANGE),
		LightEmission = 1,
		Size = NumberSequence.new(0.5, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(4, 8),
		Rate = if ctx.reducedMotion then 15 else 45,
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
	})
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 14
	light.Brightness = 4
	light.Parent = glow
	tween(glow, 1.3, { Size = Vector3.one * 7.5, Transparency = 0.6 })
	return glow
end

-- The target sigil: two neon rings and a spinning inner disc on the ground under the victim.
local function sigil(ctx: any, at: Vector3)
	local rings = {}
	for i, r in { 15, 10 } do
		local ring = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 1, 1),
			CFrame = CFrame.new(at + Vector3.new(0, 0.08 * i, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = if i == 1 then ORANGE else GOLD,
			Transparency = 0.15,
		}, ctx.folder)
		tween(ring, 0.5, { Size = Vector3.new(0.1, r, r) }, Enum.EasingStyle.Back)
		table.insert(rings, ring)
	end
	local disc = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 8, 8),
		CFrame = CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = RED,
		Transparency = 0.55,
	}, ctx.folder)
	table.insert(rings, disc)
	return rings
end

-- The meteor: a giant dodgeball with a molten shell, light, fire, smoke and a long trail.
local function meteor(ctx: any, scale: number?): Part
	local k = scale or 1
	local ball = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (METEOR_RADIUS * k) * 2,
		Material = Enum.Material.SmoothPlastic,
		Color = RED,
	}, ctx.folder)
	-- dodgeball seam stripes (thin discs just wider than the ball read as bands; placeMeteor moves
	-- every child part by its "Offset" attribute)
	for _, rot in { CFrame.Angles(0, 0, 0), CFrame.Angles(0, math.rad(90), 0) } do
		local seam = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, (METEOR_RADIUS * k) * 2.02, (METEOR_RADIUS * k) * 2.02),
			Material = Enum.Material.Neon,
			Color = GOLD,
		}, ball)
		seam:SetAttribute("Offset", rot)
	end
	local shell = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (METEOR_RADIUS * k) * 2.5,
		Material = Enum.Material.Neon,
		Color = ORANGE,
		Transparency = 0.65,
	}, ball)
	shell:SetAttribute("Offset", CFrame.identity)
	local light = Instance.new("PointLight")
	light.Color = ORANGE
	light.Range = 60 * k
	light.Brightness = 6
	light.Parent = ball
	local a = Instance.new("Attachment")
	a.Parent = ball
	emitter(a, {
		Texture = FIRE,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 160)),
			ColorSequenceKeypoint.new(0.4, ORANGE),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 30, 10)),
		}),
		LightEmission = 0.9,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 9 * k), NumberSequenceKeypoint.new(1, 2 * k) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(2, 6),
		Rate = if ctx.reducedMotion then 40 else 120,
		SpreadAngle = Vector2.new(180, 180),
		LockedToPart = false,
	})
	emitter(a, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(90, 60, 50), Color3.fromRGB(40, 35, 40)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(1, 3),
		Rate = if ctx.reducedMotion then 10 else 30,
		SpreadAngle = Vector2.new(180, 180),
	})
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, (METEOR_RADIUS * k) * 0.8, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -(METEOR_RADIUS * k) * 0.8, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), Color3.fromRGB(200, 40, 10))
	trail.Transparency = NumberSequence.new(0.05, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = ball
	return ball
end

local function placeMeteor(ball: Part, cf: CFrame)
	ball.CFrame = cf
	for _, c in ball:GetChildren() do
		if c:IsA("BasePart") then
			local off = c:GetAttribute("Offset")
			c.CFrame = cf * (if typeof(off) == "CFrame" then off else CFrame.identity)
		end
	end
end

-- A cloud deck: a dense core of soft puffs (hides the meteor until it breaks through) with
-- fluffy particle edges. Both are lit by the meteor's light, so the deck glows from within.
local function clouds(ctx: any, center: Vector3, radius: number, rng: Random)
	local n = if ctx.reducedMotion then 12 else 26
	for i = 1, n do
		local ang = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber()) * (if i <= 8 then 0.35 else 1)
		local size = rng:NextNumber(24, 42)
		local puff = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = CFrame.new(center + Vector3.new(math.cos(ang) * r, rng:NextNumber(-5, 5), math.sin(ang) * r)),
			Material = Enum.Material.SmoothPlastic,
			Color = CLOUD:Lerp(Color3.fromRGB(70, 60, 100), rng:NextNumber(0, 0.5)),
			Transparency = if i <= 8 then 0.05 else 0.3,
			Reflectance = 0,
		}, ctx.folder)
		if i % 3 == 0 and not ctx.reducedMotion then
			local a = Instance.new("Attachment")
			a.Parent = puff
			emitter(a, {
				Texture = SMOKE,
				Color = ColorSequence.new(CLOUD),
				LightInfluence = 1,
				Size = NumberSequence.new(size * 0.6, size * 0.9),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(2, 3),
				Speed = NumberRange.new(0.5, 1.5),
				Rate = 3,
				SpreadAngle = Vector2.new(180, 180),
			}):Emit(3)
		end
	end
end

-- Light rays fanning down from where the meteor tears through the clouds.
local function rays(ctx: any, from: Vector3, toward: Vector3, rng: Random)
	local base = (toward - from).Unit
	for _ = 1, (if ctx.reducedMotion then 3 else 7) do
		local dir = (base + Vector3.new(rng:NextNumber(-0.45, 0.45), rng:NextNumber(-0.1, 0.25), rng:NextNumber(-0.45, 0.45))).Unit
		local len = rng:NextNumber(60, 110)
		local ray = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(len, 1, 1),
			CFrame = CFrame.lookAt(from + dir * len / 2, from + dir * len) * CFrame.Angles(0, math.rad(90), 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 225, 160),
			Transparency = 1,
		}, ctx.folder)
		local w = rng:NextNumber(2.5, 6)
		tween(ray, 0.25, { Transparency = 0.72, Size = Vector3.new(len, w, w) })
		task.delay(0.6, function()
			tween(ray, 0.6, { Transparency = 1 })
		end)
	end
end

-- Anime-style impact frames: flash white, then a few frames of harsh two-tone, then back.
local function impactFrames(ctx: any)
	if ctx.reducedMotion then
		ctx.fx.screenFlash(Color3.new(1, 1, 1), 0.5, 0.3)
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
	task.delay(0.6, function()
		cc:Destroy() -- always cleaned up, even if the finisher errors
	end)
	ctx.fx.screenFlash(Color3.new(1, 1, 1), 1, 0.06)
	task.wait(0.05)
	-- frame 1: inky high-contrast silhouette, red tint
	cc.Saturation = -1
	cc.Contrast = 3
	cc.Brightness = -0.15
	cc.TintColor = Color3.fromRGB(255, 70, 50)
	task.wait(0.07)
	-- frame 2: blown-out white
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Brightness = 0.6
	cc.Contrast = 2
	task.wait(0.05)
	-- frame 3: inverted-feel dark frame
	cc.Brightness = -0.35
	cc.Contrast = 3
	cc.TintColor = Color3.fromRGB(255, 190, 120)
	task.wait(0.07)
	cc:Destroy()
end

return {
	Id = "Meteor",
	Name = "Meteor Strike",
	Duration = 4.8,
	-- server: the victim stands where they fell from, then is blasted off right at impact
	Stage = { LaunchDelay = IMPACT, Up = 85, Out = 35 },
	play = function(ctx: any)
		local t0 = os.clock()
		local rng = Random.new()
		local cam = ctx.camera
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)

		-- Shot 1: the winner ------------------------------------------------------------------
		ctx.sound("MeteorCharge")
		if killerRoot then
			-- the winner is played by a stand-in wearing their avatar (the real character is hidden)
			local hero = ctx.standIn(ctx.killer) or ctx.killer
			local K = killerRoot.Position
			local look = killerRoot.CFrame.LookVector
			local f = Vector3.new(look.X, 0, look.Z)
			f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
			local side = f:Cross(Vector3.yAxis)
			aura(ctx, killerRoot)
			-- sky behind the winner (camera looks back past them), up and off to one side
			local skyAnchor = K - f * 150 + side * 60
			local cloudY = K.Y + 105
			clouds(ctx, Vector3.new(skyAnchor.X, cloudY, skyAnchor.Z), 55, rng)
			local glow = part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 26,
				CFrame = CFrame.new(skyAnchor.X, cloudY + 14, skyAnchor.Z),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 170, 70),
				Transparency = 1,
			}, ctx.folder)
			local glowLight = Instance.new("PointLight")
			glowLight.Color = ORANGE
			glowLight.Range = 0
			glowLight.Brightness = 8
			glowLight.Parent = glow
			local ball = meteor(ctx, 2.2) -- far away, so bigger to read as giant
			local mStart = Vector3.new(skyAnchor.X, cloudY + 26, skyAnchor.Z)
			-- heads straight at the winner: by the cut it has covered ~60% of the way to them
			local mEnd = mStart:Lerp(K + Vector3.new(0, 8, 0), 0.6)
			placeMeteor(ball, CFrame.new(mStart))
			ball.Parent = nil -- hidden above the deck until it breaks through
			local broke = false
			local posed = false
			-- camera: from a chest-height medium shot to a low, close angle looking up
			local camA = K + f * 11 + side * 1.5 + Vector3.new(0, 1.8, 0)
			local camB = K + f * 5 + side * 2.2 + Vector3.new(0, -1.6, 0)
			local lookA = K + Vector3.new(0, 1.2, 0)
			local lookB = K + Vector3.new(0, 4.2, 0) - f * 3
			ctx.runFor(CUT, function(alpha: number)
				local t = alpha * CUT
				local e = ctx.ease(math.min(1, t / 1.9))
				cam.CFrame = CFrame.lookAt(camA:Lerp(camB, e), lookA:Lerp(lookB, e))
				if not posed and t > 0.25 then
					posed = true
					ctx.pose(hero, "CrossArms", 0.55)
				end
				-- light swells behind the clouds, then the meteor tears through
				if t > 0.7 then
					local g = math.clamp((t - 0.7) / 0.6, 0, 1)
					glow.Transparency = 1 - 0.55 * g
					glowLight.Range = 110 * g
				end
				if t > 0.95 then
					if not ball.Parent then
						ball.Parent = ctx.folder
					end
					local m = math.clamp((t - 0.95) / (CUT - 0.95), 0, 1)
					local pos = mStart:Lerp(mEnd, m ^ 1.6)
					placeMeteor(ball, CFrame.lookAt(pos, pos + (mEnd - mStart).Unit) * CFrame.Angles(m * 6, 0, 0))
					if not broke and pos.Y < cloudY then
						broke = true
						ctx.fx.flash(pos, Color3.fromRGB(255, 230, 170), 40)
						ctx.fx.shockwave(Vector3.new(pos.X, cloudY, pos.Z), Vector3.yAxis, GOLD, 70, 0.5)
						rays(ctx, pos, K, rng)
						ctx.sound("MeteorFall")
						tween(glow, 0.5, { Transparency = 1 })
					end
				end
			end)
			ball:Destroy() -- continuity cut: the "real" meteor falls on the victim in shot 2
		else
			task.wait(CUT)
		end

		-- Shot 2: the victim -------------------------------------------------------------------
		if not victimRoot then
			task.wait(math.max(0, ctx.duration - (os.clock() - t0)))
			return
		end
		local ground = victimRoot.Position - Vector3.new(0, 3, 0)
		sigil(ctx, ground)
		local ball = meteor(ctx)
		local approach = Vector3.new(-0.4, 1, 0.3).Unit
		local startPos = ground + approach * 95
		local endPos = ground + Vector3.new(0, METEOR_RADIUS * 0.6, 0)
		local flatSide = Vector3.new(approach.Z, 0, -approach.X).Unit
		local camPos = ground + flatSide * 26 + Vector3.new(0, 2, 0) - Vector3.new(approach.X, 0, approach.Z).Unit * 8
		cam.FieldOfView = 78
		local fallTime = IMPACT - (os.clock() - t0)
		ctx.runFor(math.max(0.3, fallTime), function(alpha: number)
			local pos = startPos:Lerp(endPos, alpha ^ 2)
			placeMeteor(ball, CFrame.lookAt(pos, pos + (endPos - startPos).Unit) * CFrame.Angles(alpha * 8, 0, 0))
			cam.CFrame = CFrame.lookAt(camPos, pos:Lerp(ground + Vector3.new(0, 4, 0), alpha ^ 1.3))
			ctx.fx.shake(0.04 + alpha * 0.08)
		end)

		-- Impact ------------------------------------------------------------------------------
		local frozen = cam.CFrame
		ctx.sound("MeteorImpact", ground)
		impactFrames(ctx)
		cam.CFrame = frozen
		ctx.fx.flash(ground + Vector3.new(0, 3, 0), Color3.fromRGB(255, 240, 200), 34)
		ctx.fx.shockwave(ground + Vector3.new(0, 0.3, 0), Vector3.yAxis, ORANGE, 50, 0.55)
		ctx.fx.shockwave(ground + Vector3.new(0, 0.6, 0), Vector3.yAxis, GOLD, 32, 0.35)
		ctx.fx.burst(ground + Vector3.new(0, 2, 0), ORANGE, if ctx.reducedMotion then 25 else 90, 75, 1.7)
		ctx.fx.shake(0.6)
		for _, d in ball:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Rate = 0
			end
		end
		tween(ball, 0.5, { Transparency = 1, Size = Vector3.one * METEOR_RADIUS * 2.6 })
		for _, c in ball:GetChildren() do
			if c:IsA("BasePart") then
				tween(c, 0.35, { Transparency = 1 })
			end
		end
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 18, 18),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(40, 25, 20),
			Transparency = 0.2,
		}, ctx.folder)
		ctx.banner(("%s crushed %s!"):format(ctx.killerName, ctx.victimName), Color3.new(1, 1, 1), 1.4)

		-- Shot 3: follow the victim flying off -------------------------------------------------
		local followFrom = cam.CFrame.Position
		ctx.runFor(math.max(0.3, ctx.duration - (os.clock() - t0)), function(alpha: number)
			if not victimRoot.Parent then
				return
			end
			local target = victimRoot.Position
			local desired = target + Vector3.new(0, 10, 0) + (followFrom - target).Unit * 24
			cam.CFrame = CFrame.lookAt(followFrom:Lerp(desired, ctx.ease(math.min(1, alpha * 2))), target)
		end)
	end,
}
