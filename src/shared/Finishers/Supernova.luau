--!strict
-- Supernova (Legendary): the world goes dark while the winner raises their arms and gathers a star.
-- Sparks spiral in from all around and feed a blazing orb overhead; the winner hurls it, and it
-- bursts on the victim in a supernova: a white-gold shell swelling out across the court, rings of
-- light and a rain of embers, blasting them off into the sky.
--
--   0.0-2.2  shot 1, slow orbit and push-in on the winner: the world dims, arms go up, sparks
--            spiral in and the star grows over their head (its light washing over them)
--   2.2-2.6  the throw: the star streaks from the winner to the victim, the camera whips after it
--   2.6      impact: flash, the supernova shell, three shockwaves, embers (the server launches the
--            victim at this moment)
--   2.6-4.8  shot 3: the camera rises and follows the victim flying off as the shell fades

local TweenService = game:GetService("TweenService")

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local GATHER = 2.2
local IMPACT = 2.6
local SPARKS = 14

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local GOLD = Color3.fromRGB(255, 214, 110)
local WHITE = Color3.fromRGB(255, 250, 235)
local CORONA = Color3.fromRGB(255, 150, 60)
local VIOLET = Color3.fromRGB(150, 110, 255)

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

-- The star: a white core in a gold glow, a light and a shimmer of sparkles. Grows with `size`.
local function star(ctx: any): (Part, Part, PointLight)
	local core = part(
		{ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, Material = Enum.Material.Neon, Color = WHITE },
		ctx.folder
	)
	local glow = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.4,
		Material = Enum.Material.Neon,
		Color = GOLD,
		Transparency = 0.45,
	}, ctx.folder)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 0
	light.Brightness = 4
	light.Shadows = false
	light.Parent = core
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(WHITE, CORONA)
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.8, 0)
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = if ctx.reducedMotion then 15 else 40
	e.Parent = glow
	return core, glow, light
end

local function place(core: Part, glow: Part, at: Vector3, size: number)
	core.Size = Vector3.one * size
	core.CFrame = CFrame.new(at)
	glow.Size = Vector3.one * size * 1.7
	glow.CFrame = CFrame.new(at)
end

return {
	Id = "Supernova",
	Name = "Supernova",
	Duration = 4.8,
	-- server: the victim waits where they stand, then is blasted high off the court at impact
	Stage = { LaunchDelay = IMPACT, Up = 110, Out = 40 },
	play = function(ctx: any)
		local t0 = os.clock()
		local rng = Random.new()
		local cam = ctx.camera
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		local dark = FinisherKit.tint(-0.35, -0.25, Color3.fromRGB(200, 190, 255))
		local core, glow, light = star(ctx)

		-- Shot 1: the winner gathers a star ---------------------------------------------------------
		ctx.sound("MeteorCharge")
		local over = Vector3.zero
		if killerRoot then
			local hero = ctx.standIn(ctx.killer) or ctx.killer
			local K = killerRoot.Position
			local f = FinisherKit.facing(killerRoot)
			local side = f:Cross(Vector3.yAxis)
			over = K + Vector3.new(0, 5.5, 0)
			ctx.pose(hero, "RaiseOverhead", 0.5)
			-- sparks start in a wide ring around the winner and spiral into the star
			local sparks = {}
			for i = 1, SPARKS do
				local a = i / SPARKS * 2 * math.pi
				table.insert(sparks, {
					part = part({
						Shape = Enum.PartType.Ball,
						Size = Vector3.one * 0.5,
						Material = Enum.Material.Neon,
						Color = if i % 3 == 0 then VIOLET else GOLD,
					}, ctx.folder),
					a = a,
					r = rng:NextNumber(14, 22),
					y = rng:NextNumber(-2, 8),
					delay = rng:NextNumber(0, 0.6),
				})
			end
			local turn = if ctx.reducedMotion then 0.12 else 0.35
			ctx.runFor(GATHER, function(alpha: number)
				local t = alpha * GATHER
				-- camera: a slow orbit from the front, pushing in and dropping low to look up at the star
				local e = ctx.ease(alpha)
				local ang = (e - 0.5) * math.pi * turn
				local dir = (f * math.cos(ang) + side * math.sin(ang))
				local camPos = K + dir * (13 - 6 * e) + Vector3.new(0, 2.5 - 2.2 * e, 0)
				cam.CFrame = CFrame.lookAt(camPos, K:Lerp(over, 0.35 + 0.4 * e))
				-- sparks spiral in, each on its own schedule, and vanish into the star
				for _, s in sparks do
					local k = math.clamp((t - s.delay) / (GATHER - 0.4 - s.delay), 0, 1)
					local a = s.a + k * 4
					local r = s.r * (1 - k ^ 1.4)
					s.part.CFrame = CFrame.new(over + Vector3.new(math.cos(a) * r, s.y * (1 - k), math.sin(a) * r))
					s.part.Transparency = if k >= 1 then 1 else 0
				end
				local size = 0.4 + 3.2 * alpha ^ 1.5
				place(core, glow, over, size)
				light.Range = 6 + 30 * alpha
			end)
			for _, s in sparks do
				s.part:Destroy()
			end
			ctx.sound("PurpleFuse", over)
			ctx.fx.flash(over, WHITE, 10)
			ctx.pose(hero, "ThrowFollow", 0.12)
		else
			task.wait(GATHER)
		end

		if not victimRoot then
			dark:Destroy()
			task.wait(math.max(0, ctx.duration - (os.clock() - t0)))
			return
		end

		-- The throw: the star streaks to the victim, the camera whipping after it -----------------
		local target = victimRoot.Position
		local from = if over.Magnitude > 0 then over else target + Vector3.new(0, 30, 0)
		local camFrom = cam.CFrame.Position
		local throwSide = (target - from):Cross(Vector3.yAxis)
		throwSide = if throwSide.Magnitude > 0.1 then throwSide.Unit else Vector3.xAxis
		local camTo = target + throwSide * 22 + Vector3.new(0, 6, 0)
		ctx.runFor(math.max(0.2, IMPACT - (os.clock() - t0)), function(alpha: number)
			local pos = from:Lerp(target + Vector3.new(0, 1, 0), alpha ^ 1.3)
				+ Vector3.new(0, math.sin(alpha * math.pi) * 6, 0)
			place(core, glow, pos, 3.6)
			cam.CFrame = CFrame.lookAt(camFrom:Lerp(camTo, ctx.ease(alpha)), pos)
		end)

		-- Impact: the supernova ---------------------------------------------------------------------
		local ground = target - Vector3.new(0, 2.5, 0)
		ctx.sound("MeteorImpact", ground)
		core:Destroy()
		glow:Destroy()
		dark.Brightness = 0.25 -- the dark world blinks bright for an instant
		tween(dark, 0.8, { Brightness = 0, Saturation = 0.15 })
		ctx.fx.screenFlash(WHITE, 0.8, 0.5)
		ctx.fx.flash(target, WHITE, 40)
		local shell = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 4,
			CFrame = CFrame.new(target),
			Material = Enum.Material.Neon,
			Color = GOLD,
			Transparency = 0.15,
		}, ctx.folder)
		local inner = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3,
			CFrame = CFrame.new(target),
			Material = Enum.Material.Neon,
			Color = WHITE,
			Transparency = 0,
		}, ctx.folder)
		local boom = Instance.new("PointLight")
		boom.Color = GOLD
		boom.Range = 60
		boom.Brightness = 6
		boom.Shadows = false
		boom.Parent = inner
		tween(shell, 1.4, { Size = Vector3.one * 70, Transparency = 1 }, Enum.EasingStyle.Quint)
		tween(inner, 0.9, { Size = Vector3.one * 26, Transparency = 1 }, Enum.EasingStyle.Quint)
		tween(boom, 1.4, { Brightness = 0 })
		ctx.fx.shockwave(ground + Vector3.new(0, 0.3, 0), Vector3.yAxis, GOLD, 80, 0.7)
		ctx.fx.shockwave(target, Vector3.new(0.3, 1, 0.2).Unit, WHITE, 50, 0.5)
		task.delay(0.15, function()
			ctx.fx.shockwave(ground + Vector3.new(0, 0.6, 0), Vector3.yAxis, VIOLET, 55, 0.6)
		end)
		ctx.fx.burst(target, GOLD, if ctx.reducedMotion then 30 else 110, 90, 1.8)
		ctx.fx.burst(target, VIOLET, if ctx.reducedMotion then 10 else 40, 60, 1.2)
		ctx.fx.shake(0.8)
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 22, 22),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Neon,
			Color = CORONA,
			Transparency = 0.35,
		}, ctx.folder)
		ctx.banner(("%s went supernova on %s!"):format(ctx.killerName, ctx.victimName), Color3.new(1, 1, 1), 1.4)

		-- Shot 3: follow the victim into the sky, the shell fading behind them ----------------------
		local followFrom = cam.CFrame.Position
		ctx.runFor(math.max(0.3, ctx.duration - (os.clock() - t0)), function(alpha: number)
			if not victimRoot.Parent then
				return
			end
			local at = victimRoot.Position
			local desired = at + Vector3.new(0, 12, 0) + (followFrom - at).Unit * 26
			cam.CFrame = CFrame.lookAt(followFrom:Lerp(desired, ctx.ease(math.min(1, alpha * 2))), at)
		end)
		dark:Destroy()
	end,
}
