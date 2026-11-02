--!strict
-- Model ball skins (Catalog Data.Model): a look built from parts in code that stands in for the
-- Standard ball's sphere. It's a look only: the real sphere keeps its size and physics and is just
-- hidden locally (BallSkinController), so radius, speed, knockback and catch timing never change.
-- Each builder makes a model of radius `r` centered on `cf`, its parts unanchored, massless and
-- non-colliding; weld it on with BallModels.weld, or anchor it (BallModels.anchor) to pose it, as
-- the shop preview does. Used by BallSkinController (balls in play), HalloweenController (the event
-- pumpkins) and ShopController (the shop and wheel previews).
--
-- Effect skins (Meteor, Disco Ball, Planet, Bomb) carry light effects kept cheap: Neon parts, at
-- most one shadowless PointLight and one low-rate ParticleEmitter a ball. Lights and emitters are
-- tagged "SkinFX" with their full Brightness / Rate (FullBrightness / FullRate attributes), and
-- BallSkinController scales them to the player's settings (Config.Visuals.NeonIntensity,
-- performance mode); NeonController dims the Neon parts like every other.
--
-- Surface markings are drawn with "spots": a second sphere that pokes just through the body, so
-- what shows is a round patch hugging the curve (no flat discs standing off the ball).

local Config = require(script.Parent.Config)
local JackOLantern = require(script.Parent.JackOLantern)

local BallModels = {}

type Builder = (cf: CFrame, r: number, form: string?) -> Model

local function piece(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.Massless = true
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

local function body(model: Model, cf: CFrame, r: number, color: Color3, material: Enum.Material?): Part
	local b = piece({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * r * 2,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CFrame = cf,
	}, model)
	model.PrimaryPart = b
	return b
end

-- A round patch of radius `rho` on the sphere (center `center`, radius `r`) facing `dir`, raised
-- `bulge` above it: a sphere through the patch's rim whose cap pokes out by `bulge`. Returns that
-- sphere's center and radius, so a patch can carry patches of its own (the eight ball's 8).
local function spot(
	model: Model,
	center: Vector3,
	r: number,
	dir: Vector3,
	rho: number,
	bulge: number,
	color: Color3,
	material: Enum.Material?
): (Vector3, number)
	local x = math.sqrt(math.max(r * r - rho * rho, 0)) -- the rim's plane, from the center
	local top = r + bulge
	local d = (top * top - r * r) / (2 * (top - x)) -- the patch sphere's center, along dir
	local a = top - d
	local at = center + dir.Unit * d
	piece({
		Name = "Spot",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * a * 2,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(at),
	}, model)
	return at, a
end

-- A thin band around the body where the plane `x = h` (in `frame`) cuts it: a disc just wider than
-- the sphere there, so only its rim shows. h = 0 is a great circle.
local function band(model: Model, frame: CFrame, r: number, h: number, w: number, color: Color3)
	local inner = math.max(0, math.abs(h) - w / 2)
	local radius = math.sqrt(math.max(r * r - inner * inner, 0)) + r * 0.025
	piece({
		Name = "Band",
		Shape = Enum.PartType.Cylinder, -- its axis is X
		Size = Vector3.new(w, radius * 2, radius * 2),
		Color = color,
		CFrame = frame * CFrame.new(h, 0, 0),
	}, model)
end

-- A light effect, tagged for BallSkinController (see the header), with its full strength kept.
local function tag(inst: Instance, props: { [string]: any }, parent: Instance)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst:SetAttribute("SkinFX", true)
	inst.Parent = parent
end

local function light(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	tag(l, { Color = color, Brightness = brightness, Range = range, Shadows = false }, parent)
	l:SetAttribute("FullBrightness", brightness)
	return l
end

-- A low-rate emitter of the built-in sparkle texture, its particles coming off the surface of the
-- part it sits on (a ball part: its sphere). `props` sets the look.
local function emitter(parent: Instance, rate: number, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = rate
	e.LightEmission = 1
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	tag(e, props, parent)
	e:SetAttribute("FullRate", rate)
	return e
end

local builders: { [string]: Builder } = {}

-- The Jack-o'-Lantern skin and the Halloween event balls: a pumpkin a little bigger than the ball.
builders.Pumpkin = function(cf, r)
	return JackOLantern.build(cf, r * Config.Halloween.Ball.Scale, "Pumpkin")
end

-- Orange with black seams: two great circles and the two curved side seams.
builders.Basketball = function(cf, r)
	local model = Instance.new("Model")
	body(model, cf, r, Color3.fromRGB(232, 110, 32))
	local seam, w = Color3.fromRGB(30, 22, 18), r * 0.06
	band(model, cf, r, 0, w, seam) -- the vertical great circle
	band(model, cf * CFrame.Angles(0, 0, math.rad(90)), r, 0, w, seam) -- the equator
	band(model, cf * CFrame.Angles(0, math.rad(90), 0), r, r * 0.62, w, seam)
	band(model, cf * CFrame.Angles(0, math.rad(90), 0), r, -r * 0.62, w, seam)
	return model
end

-- White with 12 black patches at the corners of an icosahedron (the classic pattern's pentagons).
builders.Soccer = function(cf, r)
	local model = Instance.new("Model")
	body(model, cf, r, Color3.fromRGB(245, 245, 245))
	local phi = (1 + math.sqrt(5)) / 2
	local black = Color3.fromRGB(28, 28, 32)
	for _, v in
		{
			Vector3.new(0, 1, phi),
			Vector3.new(0, 1, -phi),
			Vector3.new(0, -1, phi),
			Vector3.new(0, -1, -phi),
			Vector3.new(1, phi, 0),
			Vector3.new(1, -phi, 0),
			Vector3.new(-1, phi, 0),
			Vector3.new(-1, -phi, 0),
			Vector3.new(phi, 0, 1),
			Vector3.new(phi, 0, -1),
			Vector3.new(-phi, 0, 1),
			Vector3.new(-phi, 0, -1),
		}
	do
		spot(model, cf.Position, r, cf:VectorToWorldSpace(v), r * 0.31, r * 0.03, black)
	end
	return model
end

-- Fuzzy yellow-green with the white curved seam (the tennis-ball curve, drawn in short segments).
local SEAM_SEGMENTS = 28
builders.Tennis = function(cf, r)
	local model = Instance.new("Model")
	body(model, cf, r, Color3.fromRGB(206, 232, 58), Enum.Material.Fabric)
	-- x = a cos t + b cos 3t, y = a sin t - b sin 3t, z = 2 sqrt(ab) sin 2t lies on the unit sphere
	-- whenever a + b = 1
	local a, b = 0.72, 0.28
	local function at(t: number): Vector3
		local p = Vector3.new(
			a * math.cos(t) + b * math.cos(3 * t),
			a * math.sin(t) - b * math.sin(3 * t),
			2 * math.sqrt(a * b) * math.sin(2 * t)
		)
		return cf:PointToWorldSpace(p * r * 1.01)
	end
	local w = r * 0.07
	for i = 0, SEAM_SEGMENTS - 1 do
		local p0 = at(i / SEAM_SEGMENTS * 2 * math.pi)
		local p1 = at((i + 1) / SEAM_SEGMENTS * 2 * math.pi)
		piece({
			Name = "Seam",
			Size = Vector3.new(w, w, (p1 - p0).Magnitude + w * 0.5),
			Color = Color3.fromRGB(250, 250, 245),
			CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
		}, model)
	end
	return model
end

-- Glossy black with the white circle and its 8 on the front (-Z). The 8 is two black rings, each
-- a black patch with a white one inside, laid on the white circle.
builders.EightBall = function(cf, r)
	local model = Instance.new("Model")
	local shell = body(model, cf, r, Color3.fromRGB(18, 18, 22))
	shell.Reflectance = 0.15
	local white, black = Color3.fromRGB(250, 250, 245), Color3.fromRGB(18, 18, 22)
	local front = cf.LookVector
	local c, a = spot(model, cf.Position, r, front, r * 0.42, r * 0.025, white)
	for _, ring in { { up = 0.13, rho = 0.13, hole = 0.065 }, { up = -0.12, rho = 0.15, hole = 0.075 } } do
		local dir = (front + cf.UpVector * ring.up).Unit
		local c2, a2 = spot(model, c, a, dir, r * ring.rho, r * 0.02, black)
		spot(model, c2, a2, dir, r * ring.hole, r * 0.015, white)
	end
	return model
end

-- Effect skins ----------------------------------------------------------------------------------

local EMBER = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 160)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 30)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 30, 10)),
})

-- Meteor: dark basalt cracked with glowing lava seams (the Meteor Strike finisher's palette), shedding
-- embers that float up, with a warm glow.
builders.Meteor = function(cf, r)
	local model = Instance.new("Model")
	local rock = body(model, cf, r, Color3.fromRGB(62, 50, 46), Enum.Material.Basalt)
	-- lumps of rock first, so the silhouette isn't a perfect sphere
	local lump = rock.Color:Lerp(Color3.new(0, 0, 0), 0.15)
	for _, v in { Vector3.new(1, 0.4, -0.3), Vector3.new(-0.6, -0.8, 0.5), Vector3.new(-0.2, 0.7, 1) } do
		spot(model, cf.Position, r, cf:VectorToWorldSpace(v), r * 0.4, r * 0.06, lump)
	end
	for _, p in model:GetChildren() do
		if p.Name == "Spot" then
			(p :: Part).Material = Enum.Material.Basalt
		end
	end
	-- then the lava seams, glowing
	local lava = Color3.fromRGB(255, 140, 30)
	for i, c in
		{
			{ x = 20, z = 0, h = 0.1, w = 0.07 },
			{ x = -35, z = 70, h = -0.3, w = 0.06 },
			{ x = 60, z = -40, h = 0.45, w = 0.05 },
		}
	do
		band(model, cf * CFrame.Angles(math.rad(c.x), math.rad(i * 50), math.rad(c.z)), r, c.h * r, c.w * r, lava)
	end
	for _, p in model:GetChildren() do
		if p.Name == "Band" then
			(p :: Part).Material = Enum.Material.Neon
		end
	end
	emitter(rock, 10, {
		Color = EMBER,
		Size = NumberSequence.new(r * 0.22, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(0.5, 1.5),
		Acceleration = Vector3.new(0, 4, 0),
		Drag = 2,
	})
	light(rock, lava, 1.5, r * 7)
	return model
end

-- Disco Ball: a mirror ball, its tiles marked out by dark grout lines, twinkling with sparkles.
builders.DiscoBall = function(cf, r)
	local model = Instance.new("Model")
	local mirror = body(model, cf, r, Color3.fromRGB(205, 210, 222), Enum.Material.Foil)
	mirror.Reflectance = 0.5
	local grout, w = Color3.fromRGB(70, 72, 84), r * 0.035
	for _, h in { -0.7, -0.35, 0, 0.35, 0.7 } do -- rows
		band(model, cf * CFrame.Angles(0, 0, math.rad(90)), r, h * r, w, grout)
	end
	for i = 0, 5 do -- columns: meridians 30 degrees apart
		band(model, cf * CFrame.Angles(0, math.rad(30 * i), 0), r, 0, w, grout)
	end
	emitter(mirror, 6, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(140, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 230)),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, r * 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(0, 0),
		LockedToPart = true,
	})
	return model
end

-- Planet: a deep-space world in banded purples wearing a glowing tilted ring. The ring reaches past
-- the ball; the hitbox is still only the sphere.
builders.Planet = function(cf, r)
	local model = Instance.new("Model")
	local world = body(model, cf, r, Color3.fromRGB(96, 70, 170))
	local up = cf * CFrame.Angles(0, 0, math.rad(90)) -- bands around the planet's Y axis
	for _, b in
		{
			{ h = -0.55, w = 0.22, c = Color3.fromRGB(70, 50, 140) },
			{ h = -0.1, w = 0.3, c = Color3.fromRGB(140, 100, 210) },
			{ h = 0.4, w = 0.2, c = Color3.fromRGB(70, 50, 140) },
		}
	do
		band(model, up, r, b.h * r, b.w * r, b.c)
	end
	local tilt = cf * CFrame.Angles(math.rad(22), 0, math.rad(12)) * CFrame.Angles(0, 0, math.rad(90))
	piece({
		Name = "RingGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 0.03, r * 3.2, r * 3.2),
		Color = Color3.fromRGB(120, 225, 255),
		Material = Enum.Material.Neon,
		CFrame = tilt,
	}, model)
	piece({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 0.06, r * 2.8, r * 2.8), -- thicker, so it covers the glow's middle
		Color = Color3.fromRGB(44, 40, 80),
		CFrame = tilt,
	}, model)
	light(world, Color3.fromRGB(120, 225, 255), 1, r * 6)
	return model
end

-- Bomb: a classic cartoon bomb, its lit fuse throwing sparks (just a look: it never goes off).
builders.Bomb = function(cf, r)
	local model = Instance.new("Model")
	local shell = body(model, cf, r, Color3.fromRGB(32, 32, 38))
	shell.Reflectance = 0.1
	local glint = cf:VectorToWorldSpace(Vector3.new(-0.5, 0.6, -0.6))
	spot(model, cf.Position, r, glint, r * 0.16, r * 0.01, Color3.fromRGB(110, 110, 125))
	local top = cf * CFrame.new(0, r * 0.95, 0)
	piece({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 0.28, r * 0.5, r * 0.5),
		Color = Color3.fromRGB(80, 80, 90),
		Material = Enum.Material.Metal,
		CFrame = top * CFrame.Angles(0, 0, math.rad(90)),
	}, model)
	-- the fuse: three short segments curling up and over
	local at = top * CFrame.new(0, r * 0.12, 0)
	local seg = r * 0.16
	for _ = 1, 3 do
		at = at * CFrame.Angles(0, 0, math.rad(-22))
		piece({
			Name = "Fuse",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(seg, r * 0.07, r * 0.07),
			Color = Color3.fromRGB(200, 170, 120),
			CFrame = at * CFrame.new(0, seg / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		}, model)
		at = at * CFrame.new(0, seg, 0)
	end
	local spark = piece({
		Name = "Spark",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * r * 0.14,
		Color = Color3.fromRGB(255, 220, 90),
		Material = Enum.Material.Neon,
		CFrame = at,
	}, model)
	emitter(spark, 20, {
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 110, 20)),
		Size = NumberSequence.new(r * 0.12, 0),
		Lifetime = NumberRange.new(0.15, 0.35),
		Speed = NumberRange.new(2, 4),
		Drag = 4,
	})
	light(spark, Color3.fromRGB(255, 170, 60), 1.5, r * 5)
	return model
end

-- Robux exclusives ---------------------------------------------------------------------------------
-- A step above the coin skins: each has a light and its own particles, and the Storm Core's arcs move.

-- Galaxy: deep space in a glass shell, a glowing core, a spiral of stars and nebula clouds, twinkling.
builders.Galaxy = function(cf, r)
	local model = Instance.new("Model")
	local space = body(model, cf, r, Color3.fromRGB(14, 12, 40))
	space.Reflectance = 0.1
	for _, n in
		{
			{ v = Vector3.new(0.6, 0.3, -0.7), rho = 0.42, c = Color3.fromRGB(120, 50, 180) },
			{ v = Vector3.new(-0.7, -0.2, 0.6), rho = 0.36, c = Color3.fromRGB(40, 90, 200) },
			{ v = Vector3.new(0.1, -0.9, -0.3), rho = 0.3, c = Color3.fromRGB(200, 60, 150) },
		}
	do
		spot(model, cf.Position, r, cf:VectorToWorldSpace(n.v.Unit), r * n.rho, r * 0.02, n.c)
	end
	-- the spiral arms: tiny neon stars along two curves around the ball
	for arm = 0, 1 do
		for i = 0, 8 do
			local t = i / 8
			local a = arm * math.pi + t * math.pi * 1.4
			local y = (t - 0.5) * 1.1
			local dir = cf:VectorToWorldSpace(Vector3.new(math.cos(a), y, math.sin(a)).Unit)
			piece({
				Name = "Star",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * r * (0.07 + 0.05 * (1 - t)),
				Color = if i % 3 == 0 then Color3.fromRGB(255, 240, 200) else Color3.fromRGB(190, 220, 255),
				Material = Enum.Material.Neon,
				CFrame = CFrame.new(cf.Position + dir * r * 1.01),
			}, model)
		end
	end
	light(space, Color3.fromRGB(150, 120, 255), 1.2, r * 6)
	emitter(space, 8, {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 140, 255)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, r * 0.25),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(0, 0.2),
		LockedToPart = true,
	})
	return model
end

-- Storm Core: a dark glass sphere around a crackling plasma core, lightning arcs racing over it.
-- Each arc's segments are glitch parts of kind "Arc" sharing an ArcGroup: BallSkinController turns
-- each group to a new random angle a few times a second, so the arcs jump about like real lightning.
builders.StormCore = function(cf, r)
	local model = Instance.new("Model")
	local shell = body(model, cf, r, Color3.fromRGB(30, 34, 60), Enum.Material.Glass)
	shell.Transparency = 0.35
	shell.Reflectance = 0.2
	local core = piece({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * r * 1.1,
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.Neon,
		CFrame = cf,
	}, model)
	local bolt = Color3.fromRGB(200, 240, 255)
	for group = 1, 3 do
		-- a zigzag over a third of a great circle, its kinks alternating either side
		local tilt = cf * CFrame.Angles(math.rad(group * 61), math.rad(group * 113), 0)
		local points = {}
		for i = 0, 5 do
			local a = i / 5 * math.pi * 0.7
			local off = if i % 2 == 0 then 0.12 else -0.12
			table.insert(points, tilt:PointToWorldSpace(Vector3.new(math.cos(a), off, math.sin(a)).Unit * r * 1.02))
		end
		for i = 1, #points - 1 do
			local p0, p1 = points[i], points[i + 1]
			local seg = piece({
				Name = "Arc",
				Size = Vector3.new(r * 0.05, r * 0.05, (p1 - p0).Magnitude + r * 0.03),
				Color = bolt,
				Material = Enum.Material.Neon,
				CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
			}, model)
			seg:SetAttribute("Glitch", "Arc")
			seg:SetAttribute("ArcGroup", group)
			seg:SetAttribute("GlitchBase", cf:ToObjectSpace(seg.CFrame))
		end
	end
	light(core, Color3.fromRGB(120, 220, 255), 1.6, r * 7)
	emitter(core, 10, {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(80, 200, 255)),
		Size = NumberSequence.new(r * 0.12, 0),
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(2, 4),
		Drag = 5,
	})
	return model
end

-- Legendary set: Oracle, Masquerade, Heartbreaker, Maw ---------------------------------------------
-- Each has its own base look and colors, and every pickup shows it in one of three forms (Catalog
-- Data.Variants, picked by the server; BallModels.Forms). The forms share one style across the set
-- so they read the same on every skin:
--   Nice     - the skin's colors brightened, a floating halo of glowing beads, a soft warm light and
--              a few gentle sparkles
--   Evil     - the skin's dark palette, black spikes, glowing red cracks and rising smoke
--   Glitched - the skin's colors with red/cyan channel-split copies, stray "pixels" and a scanline.
--              Those parts are welded with Welds tagged "Glitch" (their rest offset in GlitchBase),
--              which BallSkinController jitters a few times a second: nothing is created per frame.
-- The bases are bold shapes that read at ball size: an eye in gold hoops, a split two-faced mask, a
-- cracked heart in a ring of floating hearts, a fanged mouth.

BallModels.Forms = { "Nice", "Evil", "Glitched" }

type Palette = { body: Color3, accent: Color3, detail: Color3, glow: Color3 }
type Theme = {
	colors: Palette, -- Nice and Glitched (Nice brightens it)
	evil: Palette,
	base: (model: Model, cf: CFrame, r: number, pal: Palette, evil: boolean) -> (),
}

local WHITE = Color3.new(1, 1, 1)

-- A point on the sphere: `dir` nudged by (u, v) along its own right and up.
local function onSurface(cf: CFrame, dir: Vector3, u: number, v: number): Vector3
	local f = CFrame.lookAt(Vector3.zero, dir)
	return cf:VectorToWorldSpace((dir + f.RightVector * u + f.UpVector * v).Unit)
end

-- A flat tile hugging the surface at `dir`, turned `spin` degrees about the normal.
local function tile(model: Model, cf: CFrame, r: number, dir: Vector3, size: number, spin: number, color: Color3)
	local at = cf.Position + dir * r
	piece({
		Name = "Tile",
		Size = Vector3.new(size, size, r * 0.06),
		Color = color,
		CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(0, 0, math.rad(spin)),
	}, model)
end

-- A heart patch on the surface at `dir`: two round lobes over a diamond point.
local function heart(model: Model, cf: CFrame, r: number, dir: Vector3, size: number, color: Color3)
	for _, u in { -0.09, 0.09 } do
		spot(model, cf.Position, r, onSurface(cf, dir, u * size, 0.05 * size), r * 0.11 * size, r * 0.03, color)
	end
	tile(model, cf, r, onSurface(cf, dir, 0, -0.05 * size), r * 0.17 * size, 45, color)
end

-- A small solid neon heart standing free at `at` (facing its LookVector), `s` studs tall: two lobes
-- over a diamond, the lobes centered on the diamond's upper edges.
local function charm(model: Model, at: CFrame, s: number, color: Color3)
	local t = s * 0.5 -- the diamond's side and the lobes' diameter
	local k = t / (2 * math.sqrt(2))
	for _, x in { -1, 1 } do
		piece({
			Name = "Charm",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * t,
			Color = color,
			Material = Enum.Material.Neon,
			CFrame = at * CFrame.new(x * k, k, 0),
		}, model)
	end
	piece({
		Name = "Charm",
		Size = Vector3.new(t, t, t * 0.7),
		Color = color,
		Material = Enum.Material.Neon,
		CFrame = at * CFrame.Angles(0, 0, math.rad(45)),
	}, model)
end

-- A hoop of short segments: a circle of `radius` in `frame`'s XZ plane.
local function hoop(model: Model, frame: CFrame, radius: number, segs: number, thick: number, color: Color3)
	local function at(i: number): Vector3
		local a = i / segs * 2 * math.pi
		return frame:PointToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
	end
	for i = 0, segs - 1 do
		local p0, p1 = at(i), at(i + 1)
		piece({
			Name = "Hoop",
			Size = Vector3.new(thick, thick, (p1 - p0).Magnitude + thick * 0.4),
			Color = color,
			Material = Enum.Material.Foil,
			Reflectance = 0.25,
			CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
		}, model)
	end
end

-- A jagged line over the surface through `points` (u, v around `dir`), as thin segments.
local function crack(model: Model, cf: CFrame, r: number, dir: Vector3, points: { Vector2 }, w: number, color: Color3)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local p0 = cf.Position + onSurface(cf, dir, a.X, a.Y) * r * 1.015
		local p1 = cf.Position + onSurface(cf, dir, b.X, b.Y) * r * 1.015
		piece({
			Name = "Crack",
			Size = Vector3.new(w, w, (p1 - p0).Magnitude + w * 0.5),
			Color = color,
			Material = Enum.Material.Neon,
			CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
		}, model)
	end
end

-- A WedgePart built like piece().
local function wedge(props: { [string]: any }, parent: Instance): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = false
	p.Massless = true
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

-- A saw tooth standing on the ball's surface around its equator at angle `a`, its long edge on the
-- lip at height `lip` (x r) and its point toward the middle of the mouth (`up` false: it hangs down).
local function tooth(model: Model, cf: CFrame, r: number, a: number, lip: number, up: boolean, color: Color3)
	local h, w = r * 0.24, r * 0.17
	local y = if up then lip + 0.12 else lip - 0.12 -- the tooth's center height (x r)
	local out = cf:VectorToWorldSpace(Vector3.new(math.cos(a), y, math.sin(a)).Unit)
	local upv = (cf.UpVector - out * out:Dot(cf.UpVector)).Unit
	local frame = CFrame.fromMatrix(cf.Position + out * r * 1.005, out, upv)
	wedge({
		Name = "Tooth",
		Size = Vector3.new(r * 0.06, h, w),
		Color = color,
		CFrame = if up then frame else frame * CFrame.Angles(math.pi, 0, 0),
	}, model)
end

local themes: { [string]: Theme } = {
	-- the all-seeing eye: a pearl eyeball with a glowing iris, ringed by two crossed gold hoops
	Oracle = {
		colors = {
			body = Color3.fromRGB(240, 236, 226),
			accent = Color3.fromRGB(232, 182, 58),
			detail = Color3.fromRGB(18, 14, 30),
			glow = Color3.fromRGB(90, 220, 255),
		},
		evil = {
			body = Color3.fromRGB(44, 38, 46),
			accent = Color3.fromRGB(120, 24, 30),
			detail = Color3.fromRGB(10, 6, 8),
			glow = Color3.fromRGB(255, 40, 30),
		},
		base = function(model, cf, r, pal)
			local look = cf.LookVector
			local c, a = spot(model, cf.Position, r, look, r * 0.5, r * 0.035, pal.accent) -- gold rim
			local c2, a2 = spot(model, c, a, look, r * 0.4, r * 0.015, pal.glow, Enum.Material.Neon) -- iris
			spot(model, c2, a2, look, r * 0.17, r * 0.02, pal.detail) -- pupil
			-- a glint in the pupil
			spot(model, cf.Position, r * 1.06, onSurface(cf, look, 0.09, 0.1), r * 0.05, r * 0.01, WHITE)
			-- an outer gold ring around the eye
			band(model, cf * CFrame.Angles(0, math.rad(90), 0), r, r * 0.55, r * 0.05, pal.accent)
			hoop(model, cf * CFrame.Angles(math.rad(62), 0, math.rad(20)), r * 1.32, 18, r * 0.07, pal.accent)
			hoop(model, cf * CFrame.Angles(math.rad(-62), 0, math.rad(-20)), r * 1.32, 18, r * 0.07, pal.accent)
			for _, d in { Vector3.new(0, 1, 0), Vector3.new(0, -1, 0) } do -- glowing studs at the poles
				piece({
					Name = "Pivot",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * r * 0.18,
					Color = pal.glow,
					Material = Enum.Material.Neon,
					CFrame = CFrame.new(cf:PointToWorldSpace(d * r * 1.05)),
				}, model)
			end
		end,
	},
	-- two faces in one: ivory and violet halves split by a gold seam, a domino mask with glowing
	-- eyes, the mouth smiling on the ivory side and frowning on the violet, harlequin diamonds behind
	Masquerade = {
		colors = {
			body = Color3.fromRGB(96, 46, 160),
			accent = Color3.fromRGB(236, 190, 70),
			detail = Color3.fromRGB(246, 240, 228),
			glow = Color3.fromRGB(120, 255, 220),
		},
		evil = {
			body = Color3.fromRGB(26, 16, 34),
			accent = Color3.fromRGB(110, 20, 28),
			detail = Color3.fromRGB(70, 64, 70),
			glow = Color3.fromRGB(255, 40, 30),
		},
		base = function(model, cf, r, pal)
			local look = cf.LookVector
			spot(model, cf.Position, r, cf.RightVector, r, r * 0.012, pal.detail) -- the ivory half
			band(model, cf, r, 0, r * 0.09, pal.accent) -- the seam
			local ink = Color3.fromRGB(20, 14, 26)
			for _, u in { -0.3, 0.3 } do -- the mask's eyes
				tile(model, cf, r * 1.01, onSurface(cf, look, u, 0.16), r * 0.34, 45, ink)
				spot(
					model,
					cf.Position,
					r * 1.05,
					onSurface(cf, look, u, 0.16),
					r * 0.1,
					r * 0.02,
					pal.glow,
					Enum.Material.Neon
				)
			end
			for i = -3, 3 do -- the mouth: up at the ivory end, down at the violet
				local u = i * 0.1
				local v = -0.3 + 1.3 * u * math.abs(u)
				spot(model, cf.Position, r, onSurface(cf, look, u, v), r * 0.055, r * 0.025, ink)
			end
			for i = -2, 2 do -- harlequin diamonds down the back seam
				local dir = onSurface(cf, -look, 0, i * 0.32)
				tile(model, cf, r * 1.01, dir, r * 0.2, 45, if i % 2 == 0 then pal.accent else pal.glow)
			end
		end,
	},
	-- a big heart cracked down the middle, glowing through the break, in a tilted ring of floating
	-- neon hearts
	Heartbreaker = {
		colors = {
			body = Color3.fromRGB(255, 120, 172),
			accent = Color3.fromRGB(214, 22, 74),
			detail = Color3.fromRGB(255, 236, 246),
			glow = Color3.fromRGB(255, 160, 210),
		},
		evil = {
			body = Color3.fromRGB(40, 8, 22),
			accent = Color3.fromRGB(16, 8, 12),
			detail = Color3.fromRGB(255, 40, 40),
			glow = Color3.fromRGB(255, 40, 30),
		},
		base = function(model, cf, r, pal)
			local look = cf.LookVector
			heart(model, cf, r, look, 2.7, pal.accent)
			heart(model, cf, r, -look, 1.4, pal.detail)
			-- the break: a jagged glowing line through the front heart
			crack(model, cf, r * 1.03, look, {
				Vector2.new(0, 0.28),
				Vector2.new(0.06, 0.16),
				Vector2.new(-0.05, 0.04),
				Vector2.new(0.05, -0.08),
				Vector2.new(-0.03, -0.2),
				Vector2.new(0, -0.34),
			}, r * 0.05, pal.detail)
			-- the ring of hearts, each turned to face out from the ball
			local ring = cf * CFrame.Angles(math.rad(18), 0, math.rad(-14))
			for i = 0, 4 do
				local a = i / 5 * 2 * math.pi
				local at = ring:PointToWorldSpace(Vector3.new(math.cos(a), 0, math.sin(a)) * r * 1.42)
				charm(model, CFrame.lookAt(at, at + (at - cf.Position), ring.UpVector), r * 0.36, pal.glow)
			end
		end,
	},
	-- a fanged mouth all the way round: a dark gap lined with saw teeth, angry glowing eyes above it
	-- and two curved horns
	Maw = {
		colors = {
			body = Color3.fromRGB(196, 24, 40),
			accent = Color3.fromRGB(26, 8, 14),
			detail = Color3.fromRGB(250, 244, 226),
			glow = Color3.fromRGB(255, 214, 60),
		},
		evil = {
			body = Color3.fromRGB(30, 10, 14),
			accent = Color3.fromRGB(255, 40, 30),
			detail = Color3.fromRGB(150, 140, 130),
			glow = Color3.fromRGB(255, 40, 30),
		},
		base = function(model, cf, r, pal, evil)
			local look = cf.LookVector
			local lip = 0.15 -- half the mouth's height (x r)
			band(model, cf * CFrame.Angles(0, 0, math.rad(90)), r, 0, r * lip * 2, pal.accent)
			if evil then -- the mouth glows like a furnace
				for _, p in model:GetChildren() do
					if p.Name == "Band" then
						(p :: Part).Material = Enum.Material.Neon
					end
				end
			end
			local teeth = 14
			for i = 0, teeth - 1 do
				local a = i / teeth * 2 * math.pi
				tooth(model, cf, r, a, lip, false, pal.detail) -- top row, hanging down
				tooth(model, cf, r, a + math.pi / teeth, -lip, true, pal.detail) -- bottom row
			end
			local ink = Color3.fromRGB(16, 8, 10)
			for _, side in { -1, 1 } do
				local eye = onSurface(cf, look, side * 0.3, 0.44)
				spot(model, cf.Position, r, eye, r * 0.15, r * 0.03, pal.glow, Enum.Material.Neon)
				local at = cf.Position + eye * r * 1.04
				piece({ -- a slit pupil
					Name = "Pupil",
					Size = Vector3.new(r * 0.05, r * 0.22, r * 0.04),
					Color = ink,
					CFrame = CFrame.lookAt(at, at + eye, cf.UpVector),
				}, model)
				local brow = cf.Position + onSurface(cf, look, side * 0.3, 0.68) * r * 1.02
				piece({ -- an angry brow, slanting down to the middle
					Name = "Brow",
					Size = Vector3.new(r * 0.36, r * 0.08, r * 0.08),
					Color = ink,
					CFrame = CFrame.lookAt(brow, brow + (brow - cf.Position), cf.UpVector)
						* CFrame.Angles(0, 0, math.rad(-side * 22)),
				}, model)
				-- a horn: two wedges, sweeping up and out from the crown
				local base = cf * CFrame.Angles(0, 0, math.rad(-side * 32)) * CFrame.new(0, r * 0.92, 0)
				wedge({
					Name = "Horn",
					Size = Vector3.new(r * 0.16, r * 0.5, r * 0.28),
					Color = pal.detail:Lerp(ink, 0.25),
					CFrame = base * CFrame.new(0, r * 0.22, 0) * CFrame.Angles(0, if side < 0 then math.pi else 0, 0),
				}, model)
			end
		end,
	},
	-- Robux exclusive: royalty. Gold with a jeweled band and a floating crown of gold points, always
	-- shedding a little gold dust (on top of whatever its form adds)
	Sovereign = {
		colors = {
			body = Color3.fromRGB(240, 190, 60),
			accent = Color3.fromRGB(120, 40, 160),
			detail = Color3.fromRGB(255, 70, 90),
			glow = Color3.fromRGB(255, 220, 120),
		},
		evil = {
			body = Color3.fromRGB(70, 52, 20),
			accent = Color3.fromRGB(40, 10, 50),
			detail = Color3.fromRGB(200, 20, 30),
			glow = Color3.fromRGB(200, 20, 30),
		},
		base = function(model, cf, r, pal, evil)
			local core = model.PrimaryPart :: Part
			core.Material = Enum.Material.Foil
			core.Reflectance = if evil then 0.05 else 0.3
			band(model, cf * CFrame.Angles(0, 0, math.rad(90)), r, 0, r * 0.22, pal.accent) -- the royal sash
			for i = 0, 5 do -- jewels set in it
				local a = i / 6 * 2 * math.pi
				local dir = cf:VectorToWorldSpace(Vector3.new(math.cos(a), 0, math.sin(a)))
				spot(model, cf.Position, r * 1.02, dir, r * 0.08, r * 0.035, if i % 2 == 0 then pal.detail else WHITE)
			end
			-- the crown: a ring of gold points standing on the ball's crown
			local top = cf * CFrame.new(0, r * 0.82, 0)
			for i = 0, 6 do
				local a = i / 7 * 2 * math.pi
				local at = top * CFrame.new(math.cos(a) * r * 0.5, 0, math.sin(a) * r * 0.5)
				piece({
					Name = "CrownPoint",
					Size = Vector3.new(r * 0.12, r * 0.42, r * 0.12),
					Color = pal.body:Lerp(WHITE, 0.15),
					Material = Enum.Material.Foil,
					Reflectance = 0.25,
					CFrame = at * CFrame.new(0, r * 0.12, 0) * CFrame.Angles(0, -a, math.rad(-10)),
				}, model)
			end
			emitter(core, 3, {
				Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(240, 180, 50)),
				Size = NumberSequence.new(r * 0.1, 0),
				Lifetime = NumberRange.new(0.6, 1),
				Speed = NumberRange.new(0.2, 0.4),
				Acceleration = Vector3.new(0, -1, 0),
			})
		end,
	},
	-- Robux exclusive: rebirth. Flame-orange swept with glowing feather plumes, trailing sparks
	Phoenix = {
		colors = {
			body = Color3.fromRGB(255, 120, 30),
			accent = Color3.fromRGB(255, 210, 60),
			detail = Color3.fromRGB(220, 40, 30),
			glow = Color3.fromRGB(255, 170, 70),
		},
		evil = {
			body = Color3.fromRGB(40, 16, 12),
			accent = Color3.fromRGB(150, 30, 20),
			detail = Color3.fromRGB(255, 60, 30),
			glow = Color3.fromRGB(200, 20, 30),
		},
		base = function(model, cf, r, pal, evil)
			local core = model.PrimaryPart :: Part
			-- feather plumes: swept-back blades on both sides, glowing at their tips
			for side = -1, 1, 2 do
				for i = 0, 3 do
					local back = math.rad(25 + i * 18)
					local at = cf * CFrame.Angles(0, side * math.rad(90), 0) * CFrame.Angles(back, 0, 0)
					piece({
						Name = "Feather",
						Size = Vector3.new(r * 0.08, r * 0.2, r * (0.7 - i * 0.1)),
						Color = if i % 2 == 0 then pal.accent else pal.detail,
						Material = if i == 0 and not evil then Enum.Material.Neon else Enum.Material.SmoothPlastic,
						CFrame = at * CFrame.new(0, 0, r * 0.95),
					}, model)
				end
			end
			band(model, cf * CFrame.Angles(math.rad(70), 0, 0), r, r * 0.3, r * 0.08, pal.accent)
			band(model, cf * CFrame.Angles(math.rad(70), 0, 0), r, -r * 0.05, r * 0.06, pal.detail)
			emitter(core, 8, {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 160)),
					ColorSequenceKeypoint.new(0.5, pal.body),
					ColorSequenceKeypoint.new(1, pal.detail),
				}),
				Size = NumberSequence.new(r * 0.18, 0),
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(0.5, 1.2),
				Acceleration = Vector3.new(0, 3, 0),
				Drag = 2,
			})
		end,
	},
}

-- Nice: a halo of glowing beads floating over the ball, a soft light and gentle sparkles.
local function niceForm(model: Model, cf: CFrame, r: number, pal: Palette, core: Part)
	local ring = cf * CFrame.new(0, r * 1.3, 0)
	for i = 0, 9 do
		local a = i / 10 * 2 * math.pi
		piece({
			Name = "Halo",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * r * 0.13,
			Color = pal.glow,
			Material = Enum.Material.Neon,
			CFrame = ring * CFrame.new(math.cos(a) * r * 0.55, 0, math.sin(a) * r * 0.55),
		}, model)
	end
	light(core, pal.glow, 1, r * 6)
	emitter(core, 4, {
		Color = ColorSequence.new(WHITE, pal.glow),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, r * 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(0.3, 0.6),
		Acceleration = Vector3.new(0, 1, 0),
	})
end

-- Evil: black spikes, glowing red cracks and smoke curling up.
local SPIKES = {
	Vector3.new(0, 1, 0),
	Vector3.new(0.9, 0.35, 0.3),
	Vector3.new(-0.7, 0.4, -0.6),
	Vector3.new(0.2, -0.3, -1),
	Vector3.new(-0.5, -0.6, 0.7),
	Vector3.new(0.6, -0.8, -0.2),
	Vector3.new(-1, 0, 0.2),
}
local function evilForm(model: Model, cf: CFrame, r: number, pal: Palette, core: Part)
	for _, v in SPIKES do
		local dir = cf:VectorToWorldSpace(v.Unit)
		local at = cf.Position + dir * r * 1.05
		piece({
			Name = "Spike",
			Size = Vector3.new(r * 0.13, r * 0.13, r * 0.55),
			Color = Color3.fromRGB(16, 12, 14),
			Material = Enum.Material.Slate,
			CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(0, 0, math.rad(45)),
		}, model)
	end
	local crack = Color3.fromRGB(255, 50, 30)
	band(model, cf * CFrame.Angles(math.rad(30), math.rad(40), 0), r, r * 0.2, r * 0.04, crack)
	band(model, cf * CFrame.Angles(math.rad(-50), math.rad(-20), math.rad(60)), r, -r * 0.35, r * 0.035, crack)
	for _, p in model:GetChildren() do
		if p.Name == "Band" and (p :: Part).Color == crack then
			(p :: Part).Material = Enum.Material.Neon
		end
	end
	light(core, pal.glow, 0.8, r * 5)
	emitter(core, 6, {
		Color = ColorSequence.new(Color3.fromRGB(150, 20, 20), Color3.fromRGB(20, 16, 18)),
		LightEmission = 0.2,
		Size = NumberSequence.new(r * 0.2, r * 0.6),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(0.3, 0.8),
		Acceleration = Vector3.new(0, 2.5, 0),
		Drag = 1,
	})
end

-- Glitched: channel-split copies, stray pixels and a scanline, all welded with jitterable Welds.
local function glitchPart(model: Model, cf: CFrame, kind: string, props: { [string]: any }): Part
	local p = piece(props, model)
	p:SetAttribute("Glitch", kind)
	p:SetAttribute("GlitchBase", cf:ToObjectSpace(p.CFrame))
	return p
end
local function glitchedForm(model: Model, cf: CFrame, r: number, pal: Palette)
	for i, c in { Color3.fromRGB(255, 40, 90), Color3.fromRGB(40, 230, 255) } do
		glitchPart(model, cf, "Ghost", {
			Name = "Ghost",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * r * 1.96,
			Color = c,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			CFrame = cf * CFrame.new((if i == 1 then -1 else 1) * r * 0.09, 0, 0),
		})
	end
	for i, c in { pal.accent, pal.detail, WHITE, pal.accent, Color3.fromRGB(40, 230, 255), Color3.fromRGB(255, 40, 90) } do
		local dir = Vector3.new(math.cos(i * 2.1), math.sin(i * 1.3), math.sin(i * 2.1)).Unit
		local at = cf:PointToWorldSpace(dir * r)
		glitchPart(model, cf, "Pixel", {
			Name = "Pixel",
			Size = Vector3.one * r * 0.17,
			Color = c,
			Material = Enum.Material.Neon,
			CFrame = CFrame.lookAt(at, at + cf:VectorToWorldSpace(dir)),
		})
	end
	glitchPart(model, cf, "Scan", {
		Name = "Scan",
		Shape = Enum.PartType.Cylinder, -- its axis is X: turned to lie flat across the ball
		Size = Vector3.new(r * 0.05, r * 2.05, r * 2.05),
		Color = WHITE,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
	})
end

local function legendary(name: string): Builder
	local theme = themes[name]
	return function(cf, r, form)
		local model = Instance.new("Model")
		local evil = form == "Evil"
		local pal = if evil then theme.evil else theme.colors
		if form == "Nice" then
			pal = {
				body = pal.body:Lerp(WHITE, 0.12),
				accent = pal.accent:Lerp(WHITE, 0.08),
				detail = pal.detail,
				glow = pal.glow,
			}
		end
		local core = body(model, cf, r, pal.body)
		theme.base(model, cf, r, pal, evil)
		if form == "Evil" then
			evilForm(model, cf, r, pal, core)
		elseif form == "Glitched" then
			glitchedForm(model, cf, r, pal)
		else
			niceForm(model, cf, r, pal, core)
		end
		return model
	end
end

for name in themes do
	builders[name] = legendary(name)
end

-- The radius a Glitched scanline needs at offset `h` along its axis to just clear a ball of radius r.
function BallModels.scanRadius(r: number, h: number): number
	return math.sqrt(math.max(r * r - h * h, 0)) + r * 0.025
end

-- Model names a skin can use (Catalog Data.Model).
BallModels.Names = {} :: { [string]: boolean }
for name in builders do
	BallModels.Names[name] = true
end

-- Build the named model around `cf` at ball radius `r` (the instance named `instanceName`, default
-- "RD_BallModel"), or nil for an unknown name. `form`: a Legendary skin's form (BallModels.Forms;
-- Nice when not given).
function BallModels.build(name: string, cf: CFrame, r: number, instanceName: string?, form: string?): Model?
	local builder = builders[name]
	if not builder then
		return nil
	end
	local model = builder(cf, r, form)
	model.Name = instanceName or "RD_BallModel"
	model:SetAttribute("BallModel", name)
	return model
end

-- Weld every part of `model` to `part` where they stand now, so it follows every move. Glitch parts
-- get a Weld (its C0 is what BallSkinController jitters); the rest WeldConstraints.
function BallModels.weld(model: Model, part: BasePart)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p:GetAttribute("Glitch") then
			local w = Instance.new("Weld")
			w.Name = "GlitchWeld"
			w.Part0 = part
			w.Part1 = p
			w.C0 = part.CFrame:ToObjectSpace(p.CFrame)
			w.Parent = p
		end
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and not p:GetAttribute("Glitch") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = part
			w.Part1 = p
			w.Parent = p
		end
	end
end

-- Anchor every part (a model posed in a ViewportFrame or moved with PivotTo).
BallModels.anchor = JackOLantern.anchor

return BallModels
