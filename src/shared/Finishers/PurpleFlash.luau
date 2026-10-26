--!strict
-- Purple Flash: a blue orb (pulls in) and a red orb (pushes out) pop into existence in front of the
-- winner and spiral around each other, tighter and faster, until they clash into a violet
-- singularity. Cut to the victim in dead silence; one second later the camera pulls back as a
-- giant purple blast erupts on them instantly, erasing them and leaving a crater in the court.
--
--   0.0-1.9  shot 1, on the winner: the orbs pop in (0.05 / 0.15) and spiral inward, the frame
--            warping and fringing as they close
--   1.9      clash: impact frames, the orbs snap into a crackling violet sphere
--   2.6-3.6  shot 2, close on the victim: every sound cut, total silence
--   3.6      shot 3, the camera pulls back hard as the blast fills the frame at full size; the
--            victim breaks into pixels and mist, the crater is punched out
--   3.6-5.0  the blast churns and collapses, mist rises out of the hole
--
-- The victim is a local stand-in (the real one is hidden and the server doesn't launch them), so it
-- can be broken apart. The crater is local parts laid over the court.

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local POP_BLUE = 0.05
local POP_RED = 0.15
local CONTACT = 1.9
local CUT = 2.6
local BLAST = 3.6 -- one second of silence after the cut
local ORBIT_R = 3.4
local BLAST_R = 15
local CRATER_R = 19

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local BLUE = Color3.fromRGB(70, 170, 255)
local RED = Color3.fromRGB(255, 45, 45)
local VIOLET = Color3.fromRGB(130, 40, 235)
local DEEP = Color3.fromRGB(60, 0, 120)
local LAVENDER = Color3.fromRGB(215, 175, 255)
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

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
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

local function disc(ctx: any, at: Vector3, lift: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(0.05, 1, 1)
	props.CFrame = CFrame.new(at + UP * lift) * CFrame.Angles(0, 0, math.rad(90))
	return part(props, ctx.folder)
end

type Pixel = { p: Part, vel: Vector3, age: number, life: number, size: number }

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
		local center = K + dir * 2.6 + UP * 1.1
		-- orbit plane: across the winner, tipped toward the camera so the circle reads
		local u = side
		local w = (dir * 0.75 + UP * 0.66).Unit

		local victim: Model? = nil
		local V = K + dir * 40
		local VG = Vector3.new(V.X, floorY, V.Z)
		if victimRoot then
			victim = ctx.standIn(ctx.victim)
			V = victimRoot.Position
			VG = Vector3.new(V.X, floorBelow(V, ignore) or floorY, V.Z)
			if victim then
				victim:PivotTo(CFrame.lookAt(V, Vector3.new(K.X, V.Y, K.Z)))
			end
		end
		local vHead = V + UP * 1.6

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
		local blast: { core: Part, halo: Part, shell: Part, light: PointLight }? = nil
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

			-- the orbs pop in, then spiral around each other, tighter and faster, until they clash
			if t < CONTACT then
				local p = math.clamp((t - POP_RED) / (CONTACT - POP_RED), 0, 1)
				local r = ORBIT_R * (1 - p) ^ 1.25
				angle += dt * (3.5 + 26 * p * p)
				local off = (u * math.cos(angle) + w * math.sin(angle)) * r
				local shove = if reduced then 0 else p * p * 0.25
				local bp = center + off + rng:NextUnitVector() * shove
				local rp = center - off + rng:NextUnitVector() * (0.08 + shove)
				local base = 1.6 - 0.5 * p
				sizeOrb(blue, base * popIn((t - POP_BLUE) / 0.2), 1.9 - 0.3 * math.sin(t * 9))
				sizeOrb(red, base * popIn((t - POP_RED) / 0.2), 2 + 0.35 * math.sin(t * 31))
				moveOrb(blue, CFrame.new(bp))
				moveOrb(red, CFrame.new(rp))
				pull.CFrame = CFrame.new(bp)
				if t >= POP_RED + 0.1 and t >= nextRing then
					nextRing = t + 0.22 - 0.14 * p
					ctx.fx.shockwave(rp, (cam.CFrame.Position - rp), RED, 4 + 2 * p, 0.25)
				end
			end
			if at("popBlue", POP_BLUE, t) then
				ctx.fx.flash(center, BLUE, 5)
				ctx.fx.burst(center, BLUE, if reduced then 6 else 20, 16, 0.4)
				pullFx.Rate = if reduced then 40 else 140
			end
			if at("popRed", POP_RED, t) then
				ctx.fx.flash(center, RED, 5)
				ctx.fx.burst(center, RED, if reduced then 6 else 20, 16, 0.4)
				redSparks.Rate = if reduced then 30 else 110
			end
			if at("squeeze", 0.9, t) then
				ctx.pose(hero, "Catch", 0.6)
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

			-- Shot 2: cut to the victim, and the world goes silent
			if at("cut", CUT, t) then
				if sphere then
					destroyOrb(sphere)
					sphere = nil
				end
				for _, b in tendrils do
					hideBolt(b)
				end
				mute(BLAST - CUT)
				mood.TintColor = Color3.fromRGB(215, 205, 235)
				mood.Saturation = -0.35
				mood.Brightness = -0.12
			end

			-- Shot 3: the blast, full size, instantly
			if at("blast", BLAST, t) then
				ctx.sound("PurpleSnap", VG)
				ctx.sound("PurpleRoar", VG)
				ctx.sound("PurpleErase", VG)
				task.spawn(impactFrames, ctx, LAVENDER)
				ctx.fx.shake(1)
				ctx.fx.flash(VG + UP * 4, Color3.new(1, 1, 1), BLAST_R * 3)
				ctx.fx.burst(VG + UP * 4, VIOLET, if reduced then 25 else 90, 60, 1.6)
				for i = 1, 3 do
					ctx.fx.shockwave(
						VG + UP * 0.4,
						UP,
						if i == 1 then Color3.new(1, 1, 1) else LAVENDER,
						CRATER_R * (2 + i),
						0.35 + 0.15 * i
					)
				end
				mood.TintColor = Color3.fromRGB(230, 210, 255)
				mood.Saturation = 0.3
				mood.Brightness = 0
				local mid = VG + UP * BLAST_R * 0.35
				local core = part({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * BLAST_R * 2,
					CFrame = CFrame.new(mid),
					Material = Enum.Material.Neon,
					Color = DEEP,
				}, ctx.folder)
				local halo = part({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * BLAST_R * 2.5,
					CFrame = CFrame.new(mid),
					Material = Enum.Material.ForceField,
					Color = VIOLET,
				}, ctx.folder)
				local shell = part({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * BLAST_R * 2.2,
					CFrame = CFrame.new(mid),
					Material = Enum.Material.Neon,
					Color = LAVENDER,
					Transparency = 0.55,
				}, ctx.folder)
				local light = Instance.new("PointLight")
				light.Color = VIOLET
				light.Range = 60
				light.Brightness = 12
				light.Parent = core
				blast = { core = core, halo = halo, shell = shell, light = light }
				for _ = 1, (if reduced then 3 else 9) do
					table.insert(arcs, makeBolt(ctx, 7, Color3.fromRGB(245, 230, 255), 0.35))
				end
				-- the victim: erased into pixels flung out of the blast
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
								local pos = (d.CFrame * CFrame.new(off)).Position
								local out = Vector3.new(pos.X - VG.X, 0, pos.Z - VG.Z)
								out = if out.Magnitude > 0.05 then out.Unit else rng:NextUnitVector()
								table.insert(pixels, {
									p = part({
										Size = Vector3.one * s,
										CFrame = CFrame.new(pos),
										Color = d.Color:Lerp(LAVENDER, 0.5),
										Material = Enum.Material.Neon,
									}, ctx.folder),
									vel = out * rng:NextNumber(10, 30) + UP * rng:NextNumber(12, 35),
									age = 0,
									life = rng:NextNumber(0.8, 1.3),
									size = s,
								})
							end
						end
					end
					victim:Destroy()
					victim = nil
				end
				-- the crater: deep violet lip, black pit, glowing scooped rim, punched out at once
				local d = CRATER_R * 2
				local outer = disc(ctx, VG, 0.05, { Color = Color3.fromRGB(40, 12, 60) })
				local inner = disc(ctx, VG, 0.07, { Color = VOID })
				local rim = disc(ctx, VG, 0.03, { Material = Enum.Material.Neon, Color = LAVENDER })
				tween(outer, 0.08, { Size = Vector3.new(0.05, d, d) })
				tween(inner, 0.1, { Size = Vector3.new(0.06, d * 0.74, d * 0.74) })
				tween(rim, 0.08, { Size = Vector3.new(0.04, d + 1.2, d + 1.2) })
				task.delay(0.6, function()
					tween(rim, 1.2, { Transparency = 0.7 })
				end)
				-- glowing violet mist rising out of the hole
				for i = 1, (if reduced then 3 else 8) do
					local a = i / 8 * math.pi * 2
					local anchor = part({
						Size = Vector3.one * 0.2,
						Transparency = 1,
						Position = VG
							+ (side * math.cos(a) + dir * math.sin(a)) * CRATER_R * rng:NextNumber(0.2, 0.8)
							+ UP * 0.5,
					}, ctx.folder)
					emitter(anchor, {
						Texture = SMOKE,
						Color = ColorSequence.new(VIOLET, DEEP),
						LightEmission = 0.6,
						Size = NumberSequence.new(4, 9),
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.5),
							NumberSequenceKeypoint.new(1, 1),
						}),
						Lifetime = NumberRange.new(1.2, 2),
						Speed = NumberRange.new(2, 5),
						EmissionDirection = Enum.NormalId.Top,
						SpreadAngle = Vector2.new(30, 30),
						Rate = if reduced then 2 else 6,
					}):Emit(if reduced then 1 else 3)
				end
				task.delay(0.35, function()
					ctx.banner(
						("%s was erased by %s"):format(ctx.victimName, ctx.killerName),
						LAVENDER,
						1.4,
						"PurpleInrush"
					)
				end)
			end

			-- the blast churns, ringed with shock collars and lightning, then collapses
			if blast then
				local bt = t - BLAST
				local life = math.clamp((bt - 0.55) / 0.6, 0, 1)
				local r = BLAST_R * (1 + 0.04 * math.sin(t * 50)) * (1 - life ^ 2)
				local mid = VG + UP * BLAST_R * 0.35
				local spin = CFrame.new(mid) * CFrame.Angles(t * 3, t * 5, t * 2)
				blast.core.Size = Vector3.one * math.max(r * 2, 0.05)
				blast.halo.Size = Vector3.one * math.max(r * 2.5, 0.05)
				blast.shell.Size = Vector3.one * math.max(r * 2.2, 0.05)
				blast.core.CFrame = spin
				blast.halo.CFrame = spin * CFrame.Angles(0, t * 4, 0)
				blast.shell.CFrame = CFrame.new(mid)
				blast.shell.Transparency = 0.55 + 0.45 * life
				blast.light.Brightness = 12 * (1 - life)
				for _, b in arcs do
					if life < 1 then
						local a = rng:NextUnitVector()
						drawBolt(
							b,
							mid + a * r * 1.02,
							mid + (a + rng:NextUnitVector() * 0.9).Unit * r * 1.15,
							r * 0.2,
							rng
						)
					else
						hideBolt(b)
					end
				end
				if life < 1 and t >= nextCollar then
					nextCollar = t + 0.09
					ctx.fx.shockwave(mid, rng:NextUnitVector(), LAVENDER, r * 3, 0.35)
				end
				if life >= 1 and not fired.gone then
					fired.gone = true
					blast.core:Destroy()
					blast.halo:Destroy()
					blast.shell:Destroy()
				end
			end

			-- pixels: flung out of the blast, shrinking and fading to violet
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
			local camPos: Vector3, lookAt: Vector3, fov: number
			if t < CUT then
				-- front shot on the winner, pushing in as the spiral tightens
				local p = math.clamp(t / CONTACT, 0, 1)
				local e = ctx.ease(p)
				camPos = (K + dir * 11 + UP * 2.2):Lerp(K + dir * 7.5 + side * 0.8 + UP * 1.4, e)
				lookAt = center + UP * 0.2
				fov = 60 + (if reduced then 0 else 22 * p ^ 3 + 2 * math.sin(t * 50) * p ^ 2)
				if t >= CONTACT then
					local s = math.clamp((t - CONTACT) / 0.25, 0, 1)
					fov = 84 - 30 * (1 - (1 - s) ^ 3)
					camPos = camPos:Lerp(center + dir * 4.5 + UP * 0.3, s * 0.45)
				elseif not reduced and p > 0.6 then
					-- fringe: alternating green/magenta tint as the space between them bends
					mood.TintColor = if math.floor(t * 40) % 2 == 0
						then Color3.fromRGB(255, 215, 255)
						else Color3.fromRGB(215, 255, 225)
				end
			elseif t < BLAST then
				-- close on the victim, held still in the silence
				local s = (t - CUT) / (BLAST - CUT)
				camPos = vHead - dir * (5.5 - 1.2 * s) + side * 0.6
				lookAt = vHead
				fov = 50
			else
				-- the pull-back: hard out to a high wide shot as the blast fills the court
				local s = math.clamp((t - BLAST) / 0.45, 0, 1)
				s = 1 - (1 - s) ^ 4
				local wide = VG - dir * 52 + side * 26 + UP * 32
				camPos = (vHead - dir * 4.3 + side * 0.6):Lerp(wide, s)
				camPos += (wide - VG).Unit * 6 * ctx.ease(math.clamp((t - BLAST - 0.45) / 1, 0, 1))
				lookAt = vHead:Lerp(VG + UP * 4, s)
				fov = 50 + 20 * s
			end
			cam.CFrame = CFrame.lookAt(camPos, lookAt)
			cam.FieldOfView = fov
		end)
		cam.FieldOfView = baseFov
		mood:Destroy()
	end,
}
