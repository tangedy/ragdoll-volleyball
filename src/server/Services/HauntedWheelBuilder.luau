--!strict
-- The Haunted Wheel (Halloween): a showpiece booth that stands in for the spin station's booth
-- while Halloween is on (HalloweenService), and is on show in the dev room (DevRoomService). A
-- black-and-orange wheel (glowing slices, bone dividers, a thorny rim studded with candle bulbs)
-- turns slowly in front of a harvest-moon halo on a gothic wall with bat wings, under a
-- jack-o-lantern hub that stays upright. A heap of carved pumpkins, candles and a skull sit in front
-- between two fire braziers, and black and orange mist rolls off all of it.
--
-- It only looks the part: the spin station keeps its own prompt, and the booth has none. The wheel
-- turns through the same "HubWheel" tag as the prize wheel (HubController, at its SpinRate), and
-- the "HubFlicker" lights flicker like flames.
-- Booth frame: x = right, y = up from the deck, -z = toward the court (LobbyBuilder.at).

local LobbyBuilder = require(script.Parent.LobbyBuilder)

local solid, decor = LobbyBuilder.solid, LobbyBuilder.decor

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local ORANGE = Color3.fromRGB(255, 112, 18)
local DEEP = Color3.fromRGB(255, 70, 8)
local CARVE = Color3.fromRGB(255, 196, 70)
local BLACK = Color3.fromRGB(16, 11, 20)
local SOOT = Color3.fromRGB(8, 4, 10)
local IRON = Color3.fromRGB(36, 32, 40)
local MEMBRANE = Color3.fromRGB(34, 16, 38)
local BONE = Color3.fromRGB(232, 222, 196)
local STEM = Color3.fromRGB(88, 112, 46)
local VINE = Color3.fromRGB(58, 96, 40)

local WHEEL_Y = 6.6 -- wheel centre above the deck
local WHEEL_Z = 3.3 -- and in front of the back wall (booth z)
local SLICES = 10
local R = 3.9 -- slice radius; the rim, bulbs and thorns sit outside it
local ICONS = { "🦇", "💀", "👻", "🕷️", "🍬" } -- on the black slices

local HauntedWheelBuilder = {}

-- Helpers -----------------------------------------------------------------------------------------

local function seq(points: { { number } }): NumberSequence
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end

-- A Block part drawn as an ellipsoid of the given size.
local function ellipsoid(props: { [string]: any }, size: Vector3, parent: Instance): Part
	props.Size = size
	local p = decor(props, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A square-section bar from a to b.
local function bar(a: Vector3, b: Vector3, thick: number, props: { [string]: any }, parent: Instance): Part
	props.Size = Vector3.new(thick, thick, (b - a).Magnitude)
	props.CFrame = CFrame.lookAt((a + b) / 2, b)
	return decor(props, parent)
end

-- A flat triangle a-b-c, `thick` deep, from two wedges. Everything pointed or curved here (slices,
-- wings, thorns, carved faces) is drawn with these.
local function triangle(a: Vector3, b: Vector3, c: Vector3, thick: number, props: { [string]: any }, parent: Instance)
	if (b - a):Cross(c - a).Magnitude < 1e-4 then
		return
	end
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- make bc the longest edge, so the height from a lands inside it and splits it into two wedges
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local halves = {
		{ depth = math.abs(ab:Dot(back)), cf = CFrame.fromMatrix((a + b) / 2, right, up, back) },
		{ depth = math.abs(ac:Dot(back)), cf = CFrame.fromMatrix((a + c) / 2, -right, up, -back) },
	}
	for _, half in halves do
		local p = table.clone(props)
		p.Shape = Enum.PartType.Wedge
		p.Size = Vector3.new(thick, height, half.depth)
		p.CFrame = half.cf
		p.CastShadow = false
		decor(p, parent)
	end
end

-- An invisible box that particles pour out of.
local function source(name: string, cf: CFrame, size: Vector3, parent: Instance): Part
	return decor({ Name = name, CFrame = cf, Size = size, Transparency = 1, CastShadow = false }, parent)
end

-- `heavy` mist is switched off in performance mode (GraphicsController).
local function emitter(props: { [string]: any }, parent: Instance, heavy: boolean?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	for k, v in props do
		(e :: any)[k] = v
	end
	if heavy then
		e:SetAttribute("Scenery", true)
	end
	e.Parent = parent
	return e
end

-- A warm light that HubController flickers around `brightness`.
local function flicker(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l:SetAttribute("Base", brightness)
	l:AddTag("HubFlicker")
	l.Parent = parent
end

-- Pumpkins ----------------------------------------------------------------------------------------

-- Carved faces, drawn across the front of a pumpkin in units of its radius: the left eye (mirrored
-- for the right), an optional nose, and the mouth as columns {x, top, bottom}. A column repeated at
-- the same x with a new top or bottom steps the edge there, which is how the teeth are cut.
type Face = { eye: { { number } }, nose: { { number } }?, mouth: { { number } } }
local FACES: { Face } = {
	{ -- the classic: triangle eyes and nose, a wide grin with one tooth down and one up
		eye = { { -0.58, 0.1 }, { -0.16, 0.1 }, { -0.37, 0.46 } },
		nose = { { -0.09, -0.08 }, { 0.09, -0.08 }, { 0, 0.1 } },
		mouth = {
			{ -0.64, -0.12, -0.24 },
			{ -0.42, -0.24, -0.46 },
			{ -0.2, -0.3, -0.56 },
			{ -0.2, -0.42, -0.56 },
			{ 0.02, -0.42, -0.56 },
			{ 0.02, -0.31, -0.56 },
			{ 0.22, -0.29, -0.54 },
			{ 0.22, -0.29, -0.43 },
			{ 0.42, -0.24, -0.38 },
			{ 0.42, -0.24, -0.46 },
			{ 0.64, -0.12, -0.24 },
		},
	},
	{ -- angry: eyes slanting down to the middle, a jagged zigzag mouth
		eye = { { -0.6, 0.36 }, { -0.14, 0.14 }, { -0.52, 0.04 } },
		mouth = {
			{ -0.6, -0.2, -0.3 },
			{ -0.4, -0.3, -0.5 },
			{ -0.2, -0.22, -0.42 },
			{ 0, -0.32, -0.56 },
			{ 0.2, -0.22, -0.42 },
			{ 0.4, -0.3, -0.5 },
			{ 0.6, -0.2, -0.3 },
		},
	},
	{ -- sly: downturned eyes, a little nose, a thin smile with a single fang
		eye = { { -0.56, 0.38 }, { -0.18, 0.38 }, { -0.37, 0.08 } },
		nose = { { -0.07, 0 }, { 0.07, 0 }, { 0, -0.12 } },
		mouth = {
			{ -0.6, -0.16, -0.22 },
			{ -0.3, -0.3, -0.42 },
			{ -0.08, -0.34, -0.5 },
			{ -0.08, -0.44, -0.5 },
			{ 0.08, -0.44, -0.5 },
			{ 0.08, -0.34, -0.5 },
			{ 0.3, -0.3, -0.42 },
			{ 0.6, -0.16, -0.22 },
		},
	},
}

-- A pumpkin of radius r centred at `cf`, facing cf's look direction: ribbed lobes round a darker
-- core, a curly stem, a leaf on the big ones, and (with a face) a glowing carved face and a light.
-- Returns its height above the centre, for stacking.
local function pumpkin(cf: CFrame, r: number, face: number?, parent: Instance, rng: Random, light: boolean?): number
	local h = r * 0.82 -- a little squashed
	local tint = ORANGE:Lerp(Color3.fromRGB(205, 70, 8), rng:NextNumber(0, 0.6))
	local core = ellipsoid(
		{ Name = "Pumpkin", CFrame = cf, Color = tint:Lerp(Color3.new(0, 0, 0), 0.35) },
		Vector3.new(r * 1.9, h * 1.96, r * 1.9),
		parent
	)
	if r >= 0.9 then
		core.CanCollide = true
		core.CanQuery = true
	end
	local lobes = if r >= 0.8 then 8 else 6
	for i = 0, lobes - 1 do
		ellipsoid({
			Name = "Lobe",
			CFrame = cf * CFrame.Angles(0, i * 2 * math.pi / lobes, 0) * CFrame.new(0, 0, -0.45 * r),
			Color = if i % 2 == 0 then tint else tint:Lerp(Color3.fromRGB(255, 150, 60), 0.18),
		}, Vector3.new(r * (if lobes == 8 then 0.95 else 1.15), h * 2, r * 1.1), parent)
	end
	-- stem: a dark cap, a leaning woody stalk and a curled tip
	ellipsoid(
		{ Name = "StemCap", CFrame = cf * CFrame.new(0, h * 0.92, 0), Color = STEM:Lerp(BLACK, 0.35) },
		Vector3.new(r * 0.5, r * 0.18, r * 0.5),
		parent
	)
	local lean = cf
		* CFrame.new(0, h * 0.92, 0)
		* CFrame.Angles(math.rad(rng:NextNumber(-14, 14)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-16, 16)))
	decor({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 0.5, r * 0.2, r * 0.2),
		CFrame = lean * CFrame.new(0, r * 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STEM,
		Material = Enum.Material.Wood,
	}, parent)
	decor({
		Name = "StemTip",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 0.3, r * 0.14, r * 0.14),
		CFrame = lean * CFrame.new(r * 0.1, r * 0.55, 0) * CFrame.Angles(0, 0, math.rad(25)),
		Color = STEM:Lerp(BLACK, 0.2),
		Material = Enum.Material.Wood,
	}, parent)
	if r >= 0.9 then
		triangle(
			cf * Vector3.new(r * 0.05, h * 0.96, 0),
			cf * Vector3.new(r * 0.62, h * 0.8, -r * 0.2),
			cf * Vector3.new(r * 0.4, h * 0.94, r * 0.34),
			0.05,
			{ Name = "Leaf", Color = VINE },
			parent
		)
	end
	local f = face and FACES[face]
	if f then
		-- a point on the front of the pumpkin, just proud of the skin
		local function at(p: { number }, mirror: number?): Vector3
			local x, y = p[1] * (mirror or 1), p[2]
			local z = math.sqrt(math.max(0.05, 1 - x * x - y * y))
			return cf * Vector3.new(x * r, y * h, -(z * r + 0.02))
		end
		local carve = { Name = "Carve", Color = CARVE, Material = Enum.Material.Neon }
		local thick = math.max(0.05, 0.06 * r)
		for _, m in { 1, -1 } do
			triangle(at(f.eye[1], m), at(f.eye[2], m), at(f.eye[3], m), thick, table.clone(carve), parent)
		end
		if f.nose then
			triangle(at(f.nose[1]), at(f.nose[2]), at(f.nose[3]), thick, table.clone(carve), parent)
		end
		for i = 1, #f.mouth - 1 do
			local a, b = f.mouth[i], f.mouth[i + 1]
			if a[1] ~= b[1] then
				local at1, bt, bb, ab = at({ a[1], a[2] }), at({ b[1], b[2] }), at({ b[1], b[3] }), at({ a[1], a[3] })
				triangle(at1, bt, bb, thick, table.clone(carve), parent)
				triangle(at1, bb, ab, thick, table.clone(carve), parent)
			end
		end
		if light then
			flicker(core, ORANGE, r * 5 + 3, 1.3)
		end
	end
	return h
end

-- Small props --------------------------------------------------------------------------------------

-- A candle standing on `cf` (its foot), with a dribble of wax and a flame.
local function candle(cf: CFrame, height: number, parent: Instance)
	decor({
		Name = "Candle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.32, 0.32),
		CFrame = cf * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = BONE,
	}, parent)
	ellipsoid(
		{ Name = "Wax", CFrame = cf * CFrame.new(0.14, height - 0.12, -0.04), Color = BONE },
		Vector3.new(0.12, 0.3, 0.12),
		parent
	)
	ellipsoid(
		{ Name = "Flame", CFrame = cf * CFrame.new(0, height + 0.2, 0), Color = CARVE, Material = Enum.Material.Neon },
		Vector3.new(0.16, 0.34, 0.16),
		parent
	).CastShadow =
		false
end

-- A skull centred on `cf`, facing its look direction, with embers glowing in its eye sockets.
local function skull(cf: CFrame, s: number, parent: Instance)
	ellipsoid({ Name = "Skull", CFrame = cf, Color = BONE }, Vector3.new(0.8, 0.74, 0.86) * s, parent)
	decor({
		Name = "Jaw",
		Size = Vector3.new(0.48, 0.24, 0.44) * s,
		CFrame = cf * CFrame.new(0, -0.36 * s, -0.12 * s),
		Color = BONE,
	}, parent)
	for _, sx in { -1, 1 } do
		decor({
			Name = "Socket",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.24 * s,
			CFrame = cf * CFrame.new(sx * 0.18 * s, 0, -0.33 * s),
			Color = SOOT,
		}, parent)
		decor({
			Name = "Ember",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.09 * s,
			CFrame = cf * CFrame.new(sx * 0.18 * s, 0, -0.44 * s),
			Color = ORANGE,
			Material = Enum.Material.Neon,
		}, parent)
	end
	triangle(
		cf * Vector3.new(-0.06 * s, -0.16 * s, -0.42 * s),
		cf * Vector3.new(0.06 * s, -0.16 * s, -0.42 * s),
		cf * Vector3.new(0, -0.05 * s, -0.43 * s),
		0.04,
		{ Name = "Nose", Color = SOOT },
		parent
	)
end

-- A bat with its wings spread, centred on `cf` and facing its look direction.
local function bat(cf: CFrame, s: number, parent: Instance)
	ellipsoid({ Name = "Bat", CFrame = cf, Color = BLACK }, Vector3.new(0.5, 0.75, 0.45) * s, parent)
	for _, side in { -1, 1 } do
		local function p(x: number, y: number): Vector3
			return cf * Vector3.new(side * x * s, y * s, 0)
		end
		local wing = { Name = "Wing", Color = BLACK }
		triangle(p(0.15, 0.15), p(1.5, 0.5), p(1.05, -0.2), 0.05, table.clone(wing), parent)
		triangle(p(0.15, 0.15), p(1.05, -0.2), p(0.25, -0.25), 0.05, table.clone(wing), parent)
		triangle(p(0.08, 0.3), p(0.22, 0.3), p(0.16, 0.52), 0.05, { Name = "Ear", Color = BLACK }, parent)
		decor({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.09 * s,
			CFrame = cf * CFrame.new(side * 0.09 * s, 0.14 * s, -0.22 * s),
			Color = ORANGE,
			Material = Enum.Material.Neon,
		}, parent)
	end
end

-- A tripod brazier standing on `cf`: legs, an iron bowl of coals, flames and black smoke.
local function brazier(cf: CFrame, parent: Instance)
	local iron = { Color = IRON, Material = Enum.Material.Metal }
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3 + math.pi / 6
		local foot = cf * Vector3.new(math.sin(a) * 0.8, 0, math.cos(a) * 0.8)
		local top = cf * Vector3.new(math.sin(a) * 0.3, 2.85, math.cos(a) * 0.3)
		local leg = table.clone(iron)
		leg.Name = "Leg"
		bar(foot, top, 0.16, leg, parent)
	end
	decor({
		Name = "Bowl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 1.5, 1.5),
		CFrame = cf * CFrame.new(0, 3.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = IRON,
		Material = Enum.Material.Metal,
	}, parent)
	local coals = ellipsoid(
		{ Name = "Coals", CFrame = cf * CFrame.new(0, 3.3, 0), Color = DEEP, Material = Enum.Material.Neon },
		Vector3.new(1.2, 0.35, 1.2),
		parent
	)
	flicker(coals, ORANGE, 13, 1.6)
	local src = source("Flames", cf * CFrame.new(0, 3.45, 0), Vector3.new(0.9, 0.2, 0.9), parent)
	emitter({
		Name = "Fire",
		Texture = FIRE,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 90)),
			ColorSequenceKeypoint.new(0.45, ORANGE),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 25, 0)),
		}),
		LightEmission = 1,
		Size = seq({ { 0, 1.3 }, { 1, 0.2 } }),
		Transparency = seq({ { 0, 0.25 }, { 0.7, 0.5 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 28,
		Speed = NumberRange.new(2.5, 4),
		SpreadAngle = Vector2.new(8, 8),
		Acceleration = Vector3.new(0, 2, 0),
		RotSpeed = NumberRange.new(-60, 60),
	}, src)
	emitter({
		Name = "Smoke",
		Texture = SMOKE,
		Color = ColorSequence.new(SOOT),
		Size = seq({ { 0, 0.8 }, { 1, 3.6 } }),
		Transparency = seq({ { 0, 1 }, { 0.15, 0.45 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2.5, 3.5),
		Rate = 7,
		Speed = NumberRange.new(2, 3.5),
		SpreadAngle = Vector2.new(12, 12),
		RotSpeed = NumberRange.new(-20, 20),
	}, src)
end

-- The wheel -----------------------------------------------------------------------------------------

-- The turning part: everything here spins about the disc's axis.
local function wheel(c: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "HauntedWheel"
	-- a frame on the wheel at angle a (clockwise from 12 o'clock), r out and z in front of the disc,
	-- with Y pointing outward and its front face toward the viewer
	local function spoke(a: number, r: number, z: number): CFrame
		return c * CFrame.Angles(0, 0, -a) * CFrame.new(0, r, -z)
	end
	-- the pivot: HubController turns the model about the disc's local X, which points out of the wall
	local disc = decor({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, R * 2 + 1, R * 2 + 1),
		CFrame = c * CFrame.Angles(0, math.rad(90), 0),
		Color = BLACK,
	}, model)
	model.PrimaryPart = disc
	local step = 2 * math.pi / SLICES
	for i = 0, SLICES - 1 do
		local mid = i * step -- slice 0 sits under the pointer at 12 o'clock
		local lit = i % 2 == 0
		triangle(
			(c * CFrame.new(0, 0, -0.26)).Position,
			spoke(mid - step / 2, R, 0.26).Position,
			spoke(mid + step / 2, R, 0.26).Position,
			0.1,
			{
				Name = "Slice",
				Color = if not lit then Color3.fromRGB(14, 8, 18) elseif i % 4 == 0 then ORANGE else DEEP,
				Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			},
			model
		)
		-- a spooky icon on the black slices, a mystery mark on the orange ones
		local icon = decor({
			Name = "Icon",
			Size = Vector3.new(1.5, 1.5, 0.05),
			CFrame = spoke(mid, R * 0.66, 0.33),
			Transparency = 1,
		}, model)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 50
		sg.Parent = icon
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = if lit then Enum.Font.Creepster else Enum.Font.FredokaOne
		t.Text = if lit then "?" else ICONS[(i - 1) // 2 + 1]
		t.TextColor3 = SOOT
		t.Parent = sg
		-- a bone between this slice and the next, knobbly at the rim end
		local edge = mid + step / 2
		local inner, outer = 1.7, R - 0.15
		decor({
			Name = "Bone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(outer - inner, 0.26, 0.26),
			CFrame = spoke(edge, (inner + outer) / 2, 0.42) * CFrame.Angles(0, 0, math.rad(90)),
			Color = BONE,
		}, model)
		for _, side in { -1, 1 } do
			decor({
				Name = "Knob",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.4,
				CFrame = spoke(edge, outer, 0.42) * CFrame.new(side * 0.15, 0, 0),
				Color = BONE,
			}, model)
		end
		-- a candle bulb on the rim over the slice, an iron thorn over the bone
		local bulb = decor({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.5,
			CFrame = spoke(mid, R + 0.2, 0.65),
			Color = CARVE,
			Material = Enum.Material.Neon,
		}, model)
		bulb.CastShadow = false
		triangle(
			spoke(edge - 0.07, R + 0.4, 0.3).Position,
			spoke(edge + 0.07, R + 0.4, 0.3).Position,
			spoke(edge, R + 1.1, 0.3).Position,
			0.3,
			{ Name = "Thorn", Color = IRON, Material = Enum.Material.Metal },
			model
		)
	end
	-- the iron rim
	local segments = 20
	for i = 0, segments - 1 do
		decor({
			Name = "Rim",
			Size = Vector3.new(2 * math.pi * (R + 0.2) / segments * 1.06, 0.5, 0.6),
			CFrame = spoke((i + 0.5) * 2 * math.pi / segments, R + 0.2, 0.3),
			Color = IRON,
			Material = Enum.Material.Metal,
		}, model)
	end
	-- the collar round the hub: an iron ring with a glowing edge
	for _, ring in
		{
			{ name = "HubGlow", d = 3.5, z = 0.3, color = ORANGE, material = Enum.Material.Neon },
			{ name = "Collar", d = 3.1, z = 0.36, color = IRON, material = Enum.Material.Metal },
		}
	do
		decor({
			Name = ring.name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, ring.d, ring.d),
			CFrame = c * CFrame.new(0, 0, -ring.z) * CFrame.Angles(0, math.rad(90), 0),
			Color = ring.color,
			Material = ring.material,
		}, model)
	end
	model:SetAttribute("SpinRate", -0.7) -- slower than the prize wheel, and the other way round
	model:AddTag("HubWheel")
	model.Parent = parent
	return model
end

-- The booth ---------------------------------------------------------------------------------------

-- Build the haunted wheel booth on `base` (a deck point on the back row, facing the court).
function HauntedWheelBuilder.build(base: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "HauntedWheelStation"
	local rng = Random.new(31)
	local function P(x: number, y: number, z: number): Vector3
		return base * Vector3.new(x, y, z)
	end

	-- platform and the gothic back wall with its pointed top
	solid({
		Name = "Platform",
		Size = Vector3.new(12, 0.4, 9),
		CFrame = base * CFrame.new(0, 0.2, 0.5),
		Color = Color3.fromRGB(28, 22, 32),
		Material = Enum.Material.Slate,
	}, model)
	LobbyBuilder.neon("EdgeGlow", base * CFrame.new(0, 0.42, -3.96), Vector3.new(12, 0.08, 0.12), ORANGE, model)
	solid({
		Name = "BackWall",
		Size = Vector3.new(12, 12, 0.8),
		CFrame = base * CFrame.new(0, 6, 4.6),
		Color = BLACK,
		Material = Enum.Material.Slate,
	}, model)
	triangle(
		P(-6, 12, 4.6),
		P(6, 12, 4.6),
		P(0, 16.2, 4.6),
		0.8,
		{ Name = "Spire", Color = BLACK, Material = Enum.Material.Slate },
		model
	)
	for _, sx in { -1, 1 } do
		bar(
			P(sx * 6, 12, 4.16),
			P(0, 16.2, 4.16),
			0.14,
			{ Name = "SpireGlow", Color = ORANGE, Material = Enum.Material.Neon, CastShadow = false },
			model
		)
	end
	bar(P(0, 16, 4.6), P(0, 17.9, 4.6), 0.18, { Name = "Finial", Color = IRON, Material = Enum.Material.Metal }, model)
	decor({
		Name = "FinialOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.8,
		CFrame = base * CFrame.new(0, 16.9, 4.6),
		Color = ORANGE,
		Material = Enum.Material.Neon,
	}, model)

	-- twisted iron pillars, each topped with a glowing orb
	for _, sx in { -6.2, 6.2 } do
		decor({
			Name = "PillarFoot",
			Size = Vector3.new(1.3, 0.6, 1.3),
			CFrame = base * CFrame.new(sx, 0.7, 4.5),
			Color = IRON,
			Material = Enum.Material.Metal,
		}, model)
		for k = 0, 9 do
			solid({
				Name = "Pillar",
				Size = Vector3.new(0.8, 1.22, 0.8),
				CFrame = base * CFrame.new(sx, 1.6 + k * 1.1, 4.5) * CFrame.Angles(0, math.rad(k * 18), 0),
				Color = IRON,
				Material = Enum.Material.Metal,
			}, model)
		end
		decor({
			Name = "PillarCap",
			Size = Vector3.new(1.2, 0.35, 1.2),
			CFrame = base * CFrame.new(sx, 12.2, 4.5),
			Color = IRON,
			Material = Enum.Material.Metal,
		}, model)
		decor({
			Name = "PillarOrb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.6,
			CFrame = base * CFrame.new(sx, 12.7, 4.5),
			Color = ORANGE,
			Material = Enum.Material.Neon,
		}, model)
	end

	-- the harvest moon behind the wheel: an orange corona fading to red, dark at its heart
	local c = base * CFrame.new(0, WHEEL_Y, WHEEL_Z)
	local halo = nil :: Part?
	for _, ring in
		{
			{ name = "Halo", d = 11.2, z = 0.48, color = ORANGE, material = Enum.Material.Neon, alpha = 0.25 },
			{
				name = "HaloInner",
				d = 10,
				z = 0.44,
				color = Color3.fromRGB(190, 40, 6),
				material = Enum.Material.Neon,
				alpha = 0.15,
			},
			{ name = "HaloCore", d = 8.6, z = 0.4, color = BLACK, material = Enum.Material.SmoothPlastic, alpha = 0 },
		}
	do
		local p = decor({
			Name = ring.name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.04, ring.d, ring.d),
			CFrame = c * CFrame.new(0, 0, ring.z) * CFrame.Angles(0, math.rad(90), 0),
			Color = ring.color,
			Material = ring.material,
			Transparency = ring.alpha,
			CastShadow = false,
		}, model)
		halo = halo or p
	end
	local glow = Instance.new("PointLight")
	glow.Color = ORANGE
	glow.Range = 14
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = halo

	-- bat wings spread from behind the moon: black membranes on glowing orange bones
	for _, sx in { -1, 1 } do
		local function w(x: number, y: number): Vector3
			return P(sx * x, y, 3.9)
		end
		local shoulder, wrist, low = w(3.2, 9.4), w(6.4, 12.6), w(3.4, 6.2)
		local tips = { w(9.2, 13.2), w(9.6, 10), w(8, 6.8) }
		-- scallops between the finger tips, pulled in toward the wrist
		local function scallop(a: Vector3, b: Vector3): Vector3
			return ((a + b) / 2):Lerp(wrist, 0.32)
		end
		local outline = { tips[1], scallop(tips[1], tips[2]), tips[2], scallop(tips[2], tips[3]), tips[3] }
		table.insert(outline, scallop(tips[3], low))
		table.insert(outline, low)
		table.insert(outline, shoulder)
		for i = 1, #outline - 1 do
			triangle(wrist, outline[i], outline[i + 1], 0.08, { Name = "Membrane", Color = MEMBRANE }, model)
			-- a thin ember glow along the scalloped trailing edge, so the wing reads against the dark
			if i <= 6 then
				bar(
					outline[i],
					outline[i + 1],
					0.07,
					{ Name = "WingEdge", Color = DEEP, Material = Enum.Material.Neon, CastShadow = false },
					model
				)
			end
		end
		local boneStyle = { Color = ORANGE, Material = Enum.Material.Neon, CastShadow = false }
		local arm = table.clone(boneStyle)
		arm.Name = "WingArm"
		bar(shoulder, wrist, 0.18, arm, model)
		for _, tip in tips do
			local finger = table.clone(boneStyle)
			finger.Name = "WingFinger"
			bar(wrist, tip, 0.12, finger, model)
		end
		triangle(wrist, w(6.2, 13.4), w(6.75, 13.1), 0.12, { Name = "Claw", Color = BONE }, model)
	end

	-- the wheel, its upright jack-o-lantern hub, and a fang for a pointer
	wheel(c, model)
	pumpkin(c * CFrame.new(0, 0, -0.9), 1.15, 1, model, rng, true)
	local top = R + 1.1
	triangle(
		(c * Vector3.new(-0.42, top + 0.3, -1)),
		(c * Vector3.new(0.42, top + 0.3, -1)),
		(c * Vector3.new(0, R - 0.05, -1)),
		0.3,
		{ Name = "Fang", Color = BONE },
		model
	)
	decor({
		Name = "FangMount",
		Size = Vector3.new(1.4, 0.5, 1.2),
		CFrame = c * CFrame.new(0, top + 0.5, -0.8),
		Color = IRON,
		Material = Enum.Material.Metal,
	}, model)

	-- title board in creepy letters
	local sign = decor({
		Name = "TitleSign",
		Size = Vector3.new(8.4, 2.1, 0.3),
		CFrame = base * CFrame.new(0, 13.9, 3.95),
		Color = BLACK,
	}, model)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Screen"
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 2.5
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.94, 0.9)
	title.Position = UDim2.fromScale(0.03, 0.05)
	title.BackgroundTransparency = 1
	title.Text = "HAUNTED WHEEL"
	title.TextScaled = true
	title.Font = Enum.Font.Creepster
	title.TextColor3 = Color3.fromRGB(255, 150, 40)
	title.Parent = sg
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = SOOT
	stroke.Parent = title
	for _, e in { { 0, 1.05, 8.5, 0.12 }, { 0, -1.05, 8.5, 0.12 }, { -4.2, 0, 0.12, 2.2 }, { 4.2, 0, 0.12, 2.2 } } do
		LobbyBuilder.neon(
			"SignGlow",
			sign.CFrame * CFrame.new(e[1], e[2], -0.16),
			Vector3.new(e[3], e[4], 0.08),
			ORANGE,
			model
		)
	end
	bat(base * CFrame.new(-4.9, 15.7, 3.5) * CFrame.Angles(0, 0, math.rad(12)), 1, model)
	bat(base * CFrame.new(5.2, 16.5, 3.6) * CFrame.Angles(0, 0, math.rad(-18)), 0.85, model)
	bat(base * CFrame.new(2.6, 18.1, 3.9) * CFrame.Angles(0, 0, math.rad(8)), 0.7, model)

	-- the pumpkin heap in front of the wheel, spilling off the platform
	local deck = 0.4
	local function sit(x: number, z: number, r: number, onDeck: boolean?): CFrame
		return base * CFrame.new(x, (if onDeck then 0 else deck) + r * 0.82, z)
	end
	local function yaw(deg: number): CFrame
		return CFrame.Angles(0, math.rad(deg), 0)
	end
	local big = sit(-1.7, -0.7, 1.55) * yaw(12)
	local bigH = pumpkin(big, 1.55, 1, model, rng, true)
	pumpkin(big * CFrame.new(0.15, bigH + 0.8 * 0.82 - 0.12, -0.2) * yaw(-20), 0.8, 3, model, rng)
	pumpkin(sit(2.3, -1.6, 1.15) * yaw(-18), 1.15, 2, model, rng, true)
	pumpkin(sit(4.2, 0.9, 1) * yaw(-30), 1, 3, model, rng, true)
	pumpkin(sit(-3.9, -2.3, 0.8) * yaw(25), 0.8, 2, model, rng)
	pumpkin(sit(-0.3, -3.1, 0.5) * yaw(40), 0.5, nil, model, rng)
	pumpkin(sit(-4.6, 1.3, 0.6) * yaw(-10), 0.6, nil, model, rng)
	pumpkin(sit(-5.6, -5.4, 0.9, true) * yaw(30), 0.9, 1, model, rng, true)
	pumpkin(sit(5.4, -5, 0.7, true) * yaw(-25), 0.7, 3, model, rng)
	pumpkin(sit(4.3, -5.9, 0.45, true) * yaw(70), 0.45, nil, model, rng)
	pumpkin(sit(-4.2, -6, 0.5, true) * yaw(-50), 0.5, nil, model, rng)
	-- candles, a skull and a vine trailing along the front edge
	for _, cd in { { 1.2, -3.3, 1.1 }, { 1.6, -2.9, 0.7 }, { 0.8, -2.85, 0.85 }, { -2.7, -3.4, 0.6 } } do
		candle(base * CFrame.new(cd[1], deck, cd[2]), cd[3], model)
	end
	flicker(source("CandleLight", base * CFrame.new(1.2, deck + 1.5, -3), Vector3.one * 0.2, model), CARVE, 7, 0.9)
	skull(base * CFrame.new(3.3, deck + 0.38, -3.3) * yaw(-20), 1, model)
	local vine = { P(-5.4, 0.47, -3.5), P(-4.4, 0.47, -3.85), P(-3.4, 0.47, -3.55) }
	for _, p in { P(-2.3, 0.47, -3.85), P(-1.4, 0.47, -3.6), P(-0.9, 0.47, -3.85) } do
		table.insert(vine, p)
	end
	for i = 1, #vine - 1 do
		bar(vine[i], vine[i + 1], 0.12, { Name = "Vine", Color = VINE }, model)
		if i % 2 == 1 then
			triangle(
				vine[i],
				vine[i] + base:VectorToWorldSpace(Vector3.new(0.25, 0.02, -0.45)),
				vine[i] + base:VectorToWorldSpace(Vector3.new(0.5, 0.02, 0.05)),
				0.04,
				{ Name = "Leaf", Color = STEM },
				model
			)
		end
	end
	brazier(base * CFrame.new(-5.3, deck, -3.2), model)
	brazier(base * CFrame.new(5.3, deck, -3.2), model)

	-- an orange wash from above onto the wheel
	local spot = decor({
		Name = "Downlight",
		Size = Vector3.one * 0.4,
		CFrame = CFrame.lookAt(P(0, 14.5, -5), c.Position),
		Transparency = 1,
	}, model)
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Front
	sl.Color = ORANGE:Lerp(Color3.new(1, 1, 1), 0.3)
	sl.Range = 20
	sl.Angle = 50
	sl.Brightness = 2
	sl.Parent = spot

	-- the mist: black fog over the floor with an orange glow in it, wisps curling off the wheel,
	-- embers drifting up from the pumpkins and black smoke towering behind the spire
	local floor = source("FloorMist", base * CFrame.new(0, 0.5, -2), Vector3.new(16, 0.6, 12), model)
	emitter({
		Name = "BlackFog",
		Texture = SMOKE,
		Color = ColorSequence.new(SOOT),
		Size = seq({ { 0, 3 }, { 0.5, 6 }, { 1, 8 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.5 }, { 0.7, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(6, 9),
		Rate = 7,
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(60, 60),
		Drag = 0.4,
		RotSpeed = NumberRange.new(-12, 12),
	}, floor)
	emitter({
		Name = "OrangeFog",
		Texture = SMOKE,
		Color = ColorSequence.new(ORANGE, DEEP),
		LightEmission = 0.4,
		Size = seq({ { 0, 2 }, { 1, 6 } }),
		Transparency = seq({ { 0, 1 }, { 0.25, 0.75 }, { 0.75, 0.85 }, { 1, 1 } }),
		Lifetime = NumberRange.new(5, 8),
		Rate = 4,
		Speed = NumberRange.new(0.2, 0.5),
		SpreadAngle = Vector2.new(60, 60),
		RotSpeed = NumberRange.new(-15, 15),
	}, floor, true)
	local face = source("WheelMist", c * CFrame.new(0, 0, -1.2), Vector3.new(9, 9, 0.4), model)
	emitter({
		Name = "BlackWisps",
		Texture = SMOKE,
		Color = ColorSequence.new(SOOT),
		Size = seq({ { 0, 1.5 }, { 1, 4.5 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(3, 5),
		Rate = 4,
		Speed = NumberRange.new(0.5, 1.2),
		SpreadAngle = Vector2.new(30, 30),
		RotSpeed = NumberRange.new(-30, 30),
	}, face, true)
	emitter({
		Name = "OrangeWisps",
		Texture = SMOKE,
		Color = ColorSequence.new(ORANGE, Color3.fromRGB(120, 30, 0)),
		LightEmission = 0.8,
		Size = seq({ { 0, 1 }, { 1, 3.5 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.65 }, { 1, 1 } }),
		Lifetime = NumberRange.new(3, 5),
		Rate = 4,
		Speed = NumberRange.new(0.5, 1.2),
		SpreadAngle = Vector2.new(30, 30),
		RotSpeed = NumberRange.new(-30, 30),
	}, face, true)
	emitter({
		Name = "Embers",
		Texture = SPARK,
		Color = ColorSequence.new(CARVE, DEEP),
		LightEmission = 1,
		Size = seq({ { 0, 0.25 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2, 4),
		Rate = 10,
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 0.6, 0),
		RotSpeed = NumberRange.new(-90, 90),
	}, source("EmberZone", base * CFrame.new(0, 1.2, -1.4), Vector3.new(10, 1.2, 4), model), true)
	for _, sx in { -4.5, 4.5 } do
		emitter({
			Name = "Plume",
			Texture = SMOKE,
			Color = ColorSequence.new(SOOT),
			Size = seq({ { 0, 3 }, { 1, 9 } }),
			Transparency = seq({ { 0, 1 }, { 0.15, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(5, 7),
			Rate = 3,
			Speed = NumberRange.new(2, 3),
			SpreadAngle = Vector2.new(10, 10),
			RotSpeed = NumberRange.new(-10, 10),
		}, source("PlumeBase", base * CFrame.new(sx, 11, 5.6), Vector3.new(3, 1, 1.5), model), true)
	end
	emitter({
		Name = "PlumeGlow",
		Texture = SMOKE,
		Color = ColorSequence.new(ORANGE, DEEP),
		LightEmission = 0.6,
		Size = seq({ { 0, 2 }, { 1, 6 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.6 }, { 1, 1 } }),
		Lifetime = NumberRange.new(3, 5),
		Rate = 2,
		Speed = NumberRange.new(1.5, 2.5),
		SpreadAngle = Vector2.new(15, 15),
		RotSpeed = NumberRange.new(-10, 10),
	}, source("SpireGlowMist", base * CFrame.new(0, 15, 5.4), Vector3.new(2, 1, 1), model), true)

	model.Parent = parent
	return model
end

return HauntedWheelBuilder
