--!strict
-- Purple Flash: a blue orb (pulls in) and a red orb (pushes out) pop into existence in front of the
-- winner, then ease into a spiral around each other, tighter and faster, until they clash into a
-- violet singularity. Cut to the victim in dead silence, pull back, and a thick beam of violet
-- light tears out of the winner's hand, erasing the victim and carving a hollow path through the
-- court. The last shot is the winner's own view down the path.
--
--   0.0-0.65 shot 1, on the winner: the orbs pop in (0.05 / 0.15) and hover, swelling
--   0.65-1.9 the orbs ease into a spiral that tightens and speeds up, the frame warping as they close
--   1.9      clash: impact frames, the orbs snap into a crackling violet sphere
--   2.6-3.4  shot 2, close on the victim: every sound cut, total silence
--   3.4-3.6  hard pull-back to a wide side shot of the whole line
--   3.6      the beam fires at full length instantly; the victim breaks into pixels, the path is
--            carved out under it
--   4.05-5.0 the camera swoops into the winner's eyes; the beam thins away, revealing the path
--
-- The victim is a local stand-in (the real one is hidden and the server doesn't launch them), so it
-- can be broken apart. The path is local parts laid over the court.

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local POP_BLUE = 0.05
local POP_RED = 0.15
local POP_TIME = 0.45
local ORBIT = 0.65 -- the spiral starts
local CONTACT = 1.9
local CUT = 2.6
local PULL = 3.4 -- 0.8 s on the victim
local BLAST = 3.6 -- 0.2 s pull-back
local POV = 4.05
local POV_TIME = 0.4
local ORBIT_R = 3.4
local BEAM_R = 7
local BEAM_LEN = 220
local PATH_W = 14

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local BLUE = Color3.fromRGB(70, 170, 255)
local RED = Color3.fromRGB(255, 45, 45)
local VIOLET = Color3.fromRGB(130, 40, 235)
local DEEP = Color3.fromRGB(60, 0, 120)
local LAVENDER = Color3.fromRGB(215, 175, 255)
local CORE = Color3.fromRGB(250, 240, 255)
local VOID = Color3.fromRGB(6, 2, 12)

local UP = Vector3.yAxis

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

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Overshooting 0 -> 1 curve for things that pop into existence.
local function popIn(a: number): number
	a = math.clamp(a, 0, 1)
	local c = 2.2
	return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
end

-- Jagged lightning: a chain of thin neon segments redrawn between two points each frame.
type Bolt = { parts: { Part }, width: number }

local function makeBolt(ctx: any, segs: number, color: Color3, width: number): Bolt
	local parts = {}
	for _ = 1, segs do
		table.insert(
			parts,
			part(
				{ Material = Enum.Material.Neon, Color = color, Transparency = 1, Size = Vector3.one * width },
				ctx.folder
			)
		)
	end
	return { parts = parts, width = width }
end

local function drawBolt(b: Bolt, from: Vector3, to: Vector3, jitter: number, rng: Random)
	local n = #b.parts
	local prev = from
	for i, p in b.parts do
		local nxt = if i == n then to else from:Lerp(to, i / n) + rng:NextUnitVector() * jitter * rng:NextNumber(0.3, 1)
		local len = (nxt - prev).Magnitude
		if len > 0.01 then
			p.Size = Vector3.new(b.width, b.width, len)
			p.CFrame = CFrame.lookAt((prev + nxt) / 2, nxt)
			p.Transparency = 0
		else
			p.Transparency = 1
		end
		prev = nxt
	end
end

local function hideBolt(b: Bolt)
	for _, p in b.parts do
		p.Transparency = 1
	end
end

-- An orb: neon core, soft force-field halo and a coloured light.
type Orb = { core: Part, halo: Part, light: PointLight }

local function makeOrb(ctx: any, color: Color3, size: number): Orb
	local core = part(
		{ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Material = Enum.Material.Neon, Color = color },
		ctx.folder
	)
	local halo = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size * 1.9,
		Material = Enum.Material.ForceField,
		Color = color,
		Transparency = 0.1,
	}, ctx.folder)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 9
	light.Parent = core
	return { core = core, halo = halo, light = light }
end

local function moveOrb(o: Orb, cf: CFrame)
	o.core.CFrame = cf
	o.halo.CFrame = cf * CFrame.Angles(0, os.clock() * 4, 0)
end

local function sizeOrb(o: Orb, size: number, halo: number)
	o.core.Size = Vector3.one * math.max(size, 0.05)
	o.halo.Size = Vector3.one * math.max(size * halo, 0.05)
end

local function destroyOrb(o: Orb)
	o.core:Destroy()
	o.halo:Destroy()
end

-- Anime impact frames: white, inky black and white, stark silhouette, back.
local function impactFrames(ctx: any, tint: Color3)
	if ctx.reducedMotion then
		ctx.fx.screenFlash(LAVENDER, 0.5, 0.3)
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
	task.delay(0.6, function()
		cc:Destroy() -- always cleaned up, even if the finisher errors
	end)
	ctx.fx.screenFlash(Color3.new(1, 1, 1), 1, 0.05)
	task.wait(0.04)
	cc.Saturation = -1
	cc.Contrast = 3
	cc.Brightness = 0.55
	task.wait(0.05)
	cc.Brightness = -0.45
	cc.Contrast = 3
	task.wait(0.05)
	cc.Brightness = 0.35
	cc.TintColor = tint
	task.wait(0.04)
	cc:Destroy()
end

-- Total silence: every sound group drops to zero, then comes back.
local function mute(seconds: number)
	local saved: { [SoundGroup]: number } = {}
	for _, g in SoundService:GetDescendants() do
		if g:IsA("SoundGroup") then
			saved[g] = g.Volume
			g.Volume = 0
		end
	end
	task.delay(seconds, function()
		for g, v in saved do
			g.Volume = v
		end
	end)
end

-- The court surface under a point (ignores characters and our own effects). nil over the void.
local function floorBelow(pos: Vector3, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 4 do
		params.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(pos + UP * 6, -UP * 40, params)
		if not hit then
			return nil
		end
		local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(ignore, model)
		else
			return hit.Position.Y
		end
	end
	return nil
end

-- Lay a flat strip on the floor from `a` to `b` (both at floor height).
local function strip(ctx: any, a: Vector3, b: Vector3, width: number, lift: number, props: { [string]: any }): Part
	props.Size = Vector3.new(width, 0.05, (b - a).Magnitude)
	props.CFrame = CFrame.lookAt((a + b) / 2 + UP * lift, b + UP * lift)
	return part(props, ctx.folder)
end

-- Beam section: a cylinder from `a` to `b` with the given diameter.
local function beamPart(p: Part, a: Vector3, b: Vector3, diameter: number)
	local d = math.max(diameter, 0.05)
	p.Size = Vector3.new((b - a).Magnitude, d, d)
	p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

type Pixel = { p: Part, vel: Vector3, age: number, life: number, size: number }
type Beam = { sections: { { p: Part, from: number, to: number, scale: number } }, light: PointLight }

return {
	Id = "PurpleFlash",
	Name = "Purple Flash",
	Duration = 5.0,
	-- the server leaves the victim standing; they are erased as a local stand-in
	Stage = { Launch = false },
	play = function(ctx: any)
		local rng = Random.new()
		local cam = ctx.camera
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		if not killerRoot then
			task.wait(ctx.duration)
			return
		end
		local baseFov = cam.FieldOfView
		local reduced = ctx.reducedMotion
		local ignore: { Instance } = { ctx.folder }
		for _, m in { ctx.killer, ctx.victim } do
			if typeof(m) == "Instance" then
				table.insert(ignore, m)
			end
		end

		-- geometry: the winner turns to face the victim
		local K = killerRoot.Position
		local look = killerRoot.CFrame.LookVector
		local dir = Vector3.new(look.X, 0, look.Z)
		if victimRoot then
			local v = Vector3.new(victimRoot.Position.X - K.X, 0, victimRoot.Position.Z - K.Z)
			if v.Magnitude > 1 then
				dir = v
			end
		end
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.zAxis
		local side = dir:Cross(UP) -- the winner's right
		local floorY = floorBelow(K, ignore) or (K.Y - 3)

		local hero = ctx.standIn(ctx.killer) or ctx.killer
		hero:PivotTo(CFrame.lookAt(K, K + dir))
		local rHand = hero:FindFirstChild("RightHand") :: BasePart?
		local head = hero:FindFirstChild("Head") :: BasePart?
		local center = K + dir * 2.6 + UP * 1.1
		-- orbit plane: across the winner, tipped toward the camera so the circle reads
		local u = side
		local w = (dir * 0.75 + UP * 0.66).Unit

		local victim: Model? = nil
		local V = K + dir * 40
		if victimRoot then
			victim = ctx.standIn(ctx.victim)
			V = victimRoot.Position
			if victim then
				victim:PivotTo(CFrame.lookAt(V, Vector3.new(K.X, V.Y, K.Z)))
			end
		end
		local vHead = V + UP * 1.6
		local lineMid = (K + V) / 2
		local lineLen = (V - K).Magnitude

		-- mood: darker, punchier contrast for the build-up
		local mood = Instance.new("ColorCorrectionEffect")
		mood.Brightness = -0.08
		mood.Contrast = 0.3
		mood.Saturation = 0.25
		mood.Parent = cam
		task.delay(ctx.duration + 0.5, function()
			mood:Destroy()
		end)

		-- Shot 1: the orbs ---------------------------------------------------------------------
		local blue = makeOrb(ctx, BLUE, 1.6)
		local red = makeOrb(ctx, RED, 1.6)
		sizeOrb(blue, 0, 1)
		sizeOrb(red, 0, 1)
		-- blue pulls in: particles spawn on a sphere around it and fall into the core
		local pull = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Transparency = 1 }, ctx.folder)
		local pullFx = emitter(pull, {
			Texture = SPARK,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Color = ColorSequence.new(Color3.new(1, 1, 1), BLUE),
			LightEmission = 1,
			Size = NumberSequence.new(0.25, 0.05),
			Squash = NumberSequence.new(-1.5),
			Transparency = NumberSequence.new(0.2, 0),
			Lifetime = NumberRange.new(0.28, 0.32),
			Speed = NumberRange.new(11, 13),
			Rate = 0,
			LockedToPart = true,
		})
		-- red pushes out: jagged sparks flung away
		local push = Instance.new("Attachment")
		push.Parent = red.core
		local redSparks = emitter(push, {
			Texture = SPARK,
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 200), RED),
			LightEmission = 1,
			Size = NumberSequence.new(0.35, 0),
			Squash = NumberSequence.new(-1),
			Lifetime = NumberRange.new(0.15, 0.3),
			Speed = NumberRange.new(18, 30),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
			Rate = 0,
		})
		-- each orb leaves a ribbon so the spiral draws itself
		local function ribbon(o: Orb, color: Color3)
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position, a1.Position = UP * 0.45, -UP * 0.45
			a0.Parent, a1.Parent = o.core, o.core
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Lifetime = 0.22
			tr.LightEmission = 1
			tr.FaceCamera = true
			tr.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			tr.Transparency = NumberSequence.new(0.15, 1)
			tr.Parent = o.core
		end
		ribbon(blue, BLUE)
		ribbon(red, RED)

		local sphere: Orb? = nil
		local tendrils: { Bolt } = {}
		local arcs: { Bolt } = {}
		local beam: Beam? = nil
		local beamFrom = K
		local pixels: { Pixel } = {}
		local fired: { [string]: boolean } = {}
		local function at(name: string, time: number, t: number): boolean
			if not fired[name] and t >= time then
				fired[name] = true
				return true
			end
			return false
		end
		local angle = 0
		local nextRing = 0
		local nextCollar = 0

		ctx.sound("PurpleOrbs", center)
		ctx.pose(hero, "ArmsSpread", 0.3)
		if victim then
			ctx.pose(victim, "Catch", 0.4)
		end
		local t0 = os.clock()
		ctx.runFor(ctx.duration, function(_alpha: number, dt: number)
			local t = os.clock() - t0

			-- the orbs pop in and hover, then ease into a spiral that tightens and speeds up
			if t < CONTACT then
				local p = math.clamp((t - ORBIT) / (CONTACT - ORBIT), 0, 1)
				local r = ORBIT_R * (1 - p) ^ 1.25
				angle += dt * (24 * p ^ 1.5 + 4 * math.min(1, p * 6))
				local off = (u * math.cos(angle) + w * math.sin(angle)) * r
				local bob = UP * 0.15 * math.sin(t * 5) * (1 - p)
				local shove = if reduced then 0 else p * p * 0.25
				local bp = center + off + bob + rng:NextUnitVector() * shove
				local rp = center - off - bob + rng:NextUnitVector() * (0.08 + shove)
				local base = 1.6 - 0.5 * p
				sizeOrb(blue, base * popIn((t - POP_BLUE) / POP_TIME), 1.9 - 0.3 * math.sin(t * 9))
				sizeOrb(red, base * popIn((t - POP_RED) / POP_TIME), 2 + 0.35 * math.sin(t * 31))
				moveOrb(blue, CFrame.new(bp))
				moveOrb(red, CFrame.new(rp))
				pull.CFrame = CFrame.new(bp)
				if t >= POP_RED + 0.2 and t >= nextRing then
					nextRing = t + 0.22 - 0.14 * p
					ctx.fx.shockwave(rp, (cam.CFrame.Position - rp), RED, 4 + 2 * p, 0.25)
				end
			end
			if at("popBlue", POP_BLUE, t) then
				ctx.fx.flash(center + u * ORBIT_R, BLUE, 5)
				ctx.fx.burst(center + u * ORBIT_R, BLUE, if reduced then 6 else 20, 16, 0.4)
				pullFx.Rate = if reduced then 40 else 140
			end
			if at("popRed", POP_RED, t) then
				ctx.fx.flash(center - u * ORBIT_R, RED, 5)
				ctx.fx.burst(center - u * ORBIT_R, RED, if reduced then 6 else 20, 16, 0.4)
				redSparks.Rate = if reduced then 30 else 110
			end
			if at("squeeze", 1.1, t) then
				ctx.pose(hero, "Catch", 0.5)
				ctx.sound("PurpleSqueeze", center)
			end

			-- the clash: impact frames, the orbs collapse into the violet singularity
			if at("contact", CONTACT, t) then
				destroyOrb(blue)
				destroyOrb(red)
				pull:Destroy()
				task.spawn(impactFrames, ctx, Color3.fromRGB(235, 220, 255))
				ctx.fx.shake(0.6)
				ctx.fx.shockwave(center, dir, LAVENDER, 22, 0.35)
				ctx.fx.shockwave(center, UP, VIOLET, 18, 0.4)
				ctx.fx.burst(center, VIOLET, if reduced then 15 else 50, 30, 0.8)
				ctx.banner("PURPLE FLASH", LAVENDER, 1.1, "PurpleFuse")
				mood.TintColor = Color3.fromRGB(225, 205, 255)
				local o = makeOrb(ctx, DEEP, 2.4)
				o.halo.Color = VIOLET
				o.light.Color = VIOLET
				o.light.Range = 30
				o.light.Brightness = 10
				sphere = o
				for _ = 1, (if reduced then 3 else 7) do
					table.insert(tendrils, makeBolt(ctx, 5, LAVENDER, 0.08))
				end
			end

			-- the violet sphere churns in front of the winner until the cut
			if sphere and t < CUT then
				local s = math.clamp((t - CONTACT) / 0.12, 0, 1)
				local size = (2.4 + 0.15 * math.sin(t * 40)) * (0.4 + 0.6 * s)
				sizeOrb(sphere, size, 1.6)
				moveOrb(sphere, CFrame.new(center) * CFrame.Angles(t * 13, t * 17, t * 5))
				for i, b in tendrils do
					if (i + math.floor(t * 30)) % 3 ~= 0 then
						local out = rng:NextUnitVector()
						drawBolt(
							b,
							center + out * size * 0.5,
							center + (out + rng:NextUnitVector() * 0.6).Unit * size * rng:NextNumber(1.1, 2.1),
							0.3,
							rng
						)
					else
						hideBolt(b)
					end
				end
			end

			-- Shot 2: cut to the victim, and the world goes silent until the beam
			if at("cut", CUT, t) then
				if sphere then
					destroyOrb(sphere)
					sphere = nil
				end
				for _, b in tendrils do
					hideBolt(b)
				end
				mute(BLAST - CUT - 0.02)
				mood.TintColor = Color3.fromRGB(215, 205, 235)
				mood.Saturation = -0.35
				mood.Brightness = -0.12
				-- off camera: the winner levels their hand at the victim
				ctx.pose(hero, "PointForward", 0.2)
			end

			-- the beam: full length, instantly, out of the winner's hand
			if at("blast", BLAST, t) then
				local hand = if rHand then rHand.Position else K + dir * 2 + UP * 1.2
				beamFrom = hand + dir * 0.8
				ctx.sound("PurpleSnap", beamFrom)
				ctx.sound("PurpleRoar", V)
				ctx.sound("PurpleErase", V)
				task.spawn(impactFrames, ctx, LAVENDER)
				ctx.fx.shake(1)
				ctx.fx.flash(beamFrom, Color3.new(1, 1, 1), 16)
				ctx.fx.shockwave(beamFrom, dir, Color3.new(1, 1, 1), 26, 0.35)
				ctx.fx.flash(vHead, LAVENDER, BEAM_R * 4)
				ctx.fx.burst(vHead, VIOLET, if reduced then 25 else 90, 60, 1.6)
				mood.TintColor = Color3.fromRGB(230, 210, 255)
				mood.Saturation = 0.3
				mood.Brightness = 0
				-- a flared muzzle (stacked widening sections), then the full-width beam: violet
				-- sheath around a white-hot core
				local sections = {}
				local function section(from: number, to: number, scale: number, props: { [string]: any })
					props.Shape = Enum.PartType.Cylinder
					table.insert(sections, { p = part(props, ctx.folder), from = from, to = to, scale = scale })
				end
				local flare = { { 0, 2, 0.25 }, { 2, 4.5, 0.5 }, { 4.5, 8, 0.75 }, { 8, BEAM_LEN, 1 } }
				for _, f in flare do
					section(f[1], f[2], f[3] * BEAM_R * 2.6, { Material = Enum.Material.ForceField, Color = VIOLET })
					section(f[1], f[2], f[3] * BEAM_R * 2, {
						Material = Enum.Material.Neon,
						Color = VIOLET,
						Transparency = 0.35,
					})
					section(f[1], f[2], f[3] * BEAM_R * 1.1, { Material = Enum.Material.Neon, Color = CORE })
				end
				local light = Instance.new("PointLight")
				light.Color = VIOLET
				light.Range = 60
				light.Brightness = 12
				light.Parent = sections[#sections].p
				beam = { sections = sections, light = light }
				for _ = 1, (if reduced then 3 else 10) do
					table.insert(arcs, makeBolt(ctx, 8, Color3.fromRGB(245, 230, 255), 0.3))
				end
				-- the victim: erased into pixels blown down the beam
				if victim then
					for _, d in victim:GetDescendants() do
						if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
							local n = if reduced then 2 else math.clamp(math.floor(d.Size.Magnitude * 2.5), 2, 8)
							for _ = 1, n do
								local off = Vector3.new(
									rng:NextNumber(-0.5, 0.5) * d.Size.X,
									rng:NextNumber(-0.5, 0.5) * d.Size.Y,
									rng:NextNumber(-0.5, 0.5) * d.Size.Z
								)
								local s = rng:NextNumber(0.3, 0.6)
								table.insert(pixels, {
									p = part({
										Size = Vector3.one * s,
										CFrame = d.CFrame * CFrame.new(off),
										Color = d.Color:Lerp(LAVENDER, 0.5),
										Material = Enum.Material.Neon,
									}, ctx.folder),
									vel = dir * rng:NextNumber(25, 60)
										+ side * rng:NextNumber(-10, 10)
										+ UP * rng:NextNumber(-4, 10),
									age = 0,
									life = rng:NextNumber(0.6, 1.1),
									size = s,
								})
							end
						end
					end
					victim:Destroy()
					victim = nil
				end
				-- the hollow path: carved from the winner's feet to the far edge of the floor
				local pathFrom = Vector3.new(K.X, floorY, K.Z) + dir * 2.5
				local pathTo = pathFrom
				local step = 0
				while step < BEAM_LEN do
					local probe = pathFrom + dir * (step + 2)
					local y = floorBelow(probe, ignore)
					if not y or math.abs(y - floorY) > 3 then
						break
					end
					step += 2
					pathTo = pathFrom + dir * step
				end
				if step > 1 then
					strip(ctx, pathFrom, pathTo, PATH_W, 0.04, { Color = Color3.fromRGB(40, 12, 60) })
					strip(ctx, pathFrom, pathTo, PATH_W * 0.68, 0.06, { Color = VOID })
					for _, s in { 1, -1 } do
						local edge = side * s * PATH_W / 2
						local rim = strip(ctx, pathFrom + edge, pathTo + edge, 0.4, 0.08, {
							Material = Enum.Material.Neon,
							Color = LAVENDER,
						})
						task.delay(0.6, function()
							rim.Transparency = 0.5
						end)
					end
					-- glowing violet mist rising out of the cut
					local d = 0
					while d < step do
						local anchor = part({
							Size = Vector3.one * 0.2,
							Transparency = 1,
							Position = pathFrom + dir * d + side * rng:NextNumber(-3, 3) + UP * 0.5,
						}, ctx.folder)
						emitter(anchor, {
							Texture = SMOKE,
							Color = ColorSequence.new(VIOLET, DEEP),
							LightEmission = 0.6,
							Size = NumberSequence.new(3, 7),
							Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.5),
								NumberSequenceKeypoint.new(1, 1),
							}),
							Lifetime = NumberRange.new(1.2, 2),
							Speed = NumberRange.new(1, 3),
							EmissionDirection = Enum.NormalId.Top,
							SpreadAngle = Vector2.new(30, 30),
							Rate = if reduced then 2 else 6,
						}):Emit(if reduced then 1 else 3)
						d += if reduced then 16 else 7
					end
				end
			end

			-- the beam roars: thickness churns, lightning and shock collars along it, then it thins
			-- away as the camera reaches the winner's eyes
			if beam then
				local fade = math.clamp((t - (POV + POV_TIME * 0.5)) / 0.45, 0, 1)
				local throb = 1 + 0.06 * math.sin(t * 55) + 0.04 * math.sin(t * 23)
				local thin = (1 - fade) ^ 2
				for _, s in beam.sections do
					beamPart(s.p, beamFrom + dir * s.from, beamFrom + dir * s.to, s.scale * throb * thin)
				end
				beam.light.Brightness = 12 * thin
				for _, b in arcs do
					if thin > 0.05 then
						local along = beamFrom + dir * rng:NextNumber(4, lineLen + 30)
						local a = (side * rng:NextNumber(-1, 1) + UP * rng:NextNumber(-1, 1)).Unit
						local reach = BEAM_R * thin
						drawBolt(b, along + a * reach, along + dir * rng:NextNumber(4, 10) + a * reach * 1.4, 1.2, rng)
					else
						hideBolt(b)
					end
				end
				if thin > 0.05 and t >= nextCollar then
					nextCollar = t + 0.05
					ctx.fx.shockwave(
						beamFrom + dir * rng:NextNumber(3, lineLen + 20),
						dir,
						LAVENDER,
						BEAM_R * 3.4 * thin,
						0.3
					)
				end
				if fade >= 1 and not fired.gone then
					fired.gone = true
					for _, s in beam.sections do
						s.p:Destroy()
					end
				end
			end
			if at("inrush", POV + POV_TIME, t) then
				ctx.sound("PurpleInrush", K + dir * 20)
			end

			-- pixels: blown down the beam, shrinking and fading to violet
			for i = #pixels, 1, -1 do
				local px = pixels[i]
				px.age += dt
				local a = px.age / px.life
				if a >= 1 then
					px.p:Destroy()
					table.remove(pixels, i)
				else
					px.vel *= 0.95
					px.p.CFrame = CFrame.new(px.p.Position + px.vel * dt) * CFrame.Angles(px.age * 6, px.age * 4, 0)
					px.p.Size = Vector3.one * px.size * (1 - a)
					px.p.Transparency = a * 0.6
					px.p.Color = px.p.Color:Lerp(VIOLET, dt * 4)
				end
			end

			-- camera ----------------------------------------------------------------------------
			local wide = lineMid + side * (lineLen * 0.55 + 18) + UP * (lineLen * 0.2 + 8)
			local camPos: Vector3, lookAt: Vector3, fov: number
			if t < CUT then
				-- front shot on the winner, pushing in as the spiral tightens
				local p = math.clamp(t / CONTACT, 0, 1)
				local e = ctx.ease(p)
				camPos = (K + dir * 11 + UP * 2.2):Lerp(K + dir * 7.5 + side * 0.8 + UP * 1.4, e)
				lookAt = center + UP * 0.2
				local warp = math.clamp((t - ORBIT) / (CONTACT - ORBIT), 0, 1)
				fov = 60 + (if reduced then 0 else 22 * warp ^ 3 + 2 * math.sin(t * 50) * warp ^ 2)
				if t >= CONTACT then
					local s = math.clamp((t - CONTACT) / 0.25, 0, 1)
					fov = 84 - 30 * (1 - (1 - s) ^ 3)
					camPos = camPos:Lerp(center + dir * 4.5 + UP * 0.3, s * 0.45)
				elseif not reduced and warp > 0.6 then
					-- fringe: alternating green/magenta tint as the space between them bends
					mood.TintColor = if math.floor(t * 40) % 2 == 0
						then Color3.fromRGB(255, 215, 255)
						else Color3.fromRGB(215, 255, 225)
				end
			elseif t < PULL then
				-- close on the victim, held still in the silence
				local s = (t - CUT) / (PULL - CUT)
				camPos = vHead - dir * (5.5 - 1.2 * s) + side * 0.6
				lookAt = vHead
				fov = 50
			elseif t < POV then
				-- the pull-back to a wide side shot of the whole line, which the beam then fills
				local s = math.clamp((t - PULL) / (BLAST - PULL), 0, 1)
				s = 1 - (1 - s) ^ 3
				camPos = (vHead - dir * 4.3 + side * 0.6):Lerp(wide, s)
				lookAt = vHead:Lerp(lineMid + UP * 2, s)
				fov = 50 + 20 * s
			else
				-- into the winner's eyes, looking down the path the beam carved
				local s = ctx.ease(math.clamp((t - POV) / POV_TIME, 0, 1))
				local eye = if head then head.Position + dir * 0.3 + UP * 0.2 else K + UP * 2.2
				local far = Vector3.new(K.X, floorY, K.Z) + dir * math.max(lineLen + 15, 40)
				camPos = wide:Lerp(eye, s)
				lookAt = (lineMid + UP * 2):Lerp(far, s)
				fov = 70 - 2 * s
				if s > 0.85 and not fired.hideHead then
					fired.hideHead = true
					ctx.hideHead(hero)
				end
			end
			cam.CFrame = CFrame.lookAt(camPos, lookAt)
			cam.FieldOfView = fov
		end)
		cam.FieldOfView = baseFov
		mood:Destroy()
	end,
}
