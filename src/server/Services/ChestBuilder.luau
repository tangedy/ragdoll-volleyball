--!strict
-- Loot chest models for the hub deck (Config.Chest.Spots). Each one is a banded treasure chest on a
-- two-tier stone dais: plank walls, metal straps and corner guards with rivets, a lock plate, claw
-- feet, a barrel lid built from curved planks, a hoard of coins and gems inside, a floating gem
-- above it, sparkles and a price sign. Everything is built in the chest's own frame (front = -Z,
-- y = 0 on the deck), so a spot only has to say where it stands and which way it faces.
--
-- The lid is its own Model ("Lid") whose pivot is the back hinge, so ChestController can swing it
-- open with PivotTo(home * CFrame.Angles(angle, 0, 0)). The client also spins the floating gem
-- ("ChestGem"), lights the "Glow" light and fires the "Burst" emitter when a chest opens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CH = Config.Chest
local INK = Color3.fromRGB(16, 12, 34)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local ChestBuilder = {}

-- chest dimensions (studs)
local W = 5 -- width (X)
local D = 3.2 -- depth (Z); the barrel lid's radius is D / 2
local H = 2.4 -- body height
local R = D / 2
local DAIS = 1.7 -- top of the dais above the deck
local FEET = 0.25
local Y0 = DAIS + FEET -- bottom of the body
local TOP = Y0 + H -- the lid's hinge axis height

local function make(className: string, props: { [string]: any }, parent: Instance): any
	local p = Instance.new(className)
	if p:IsA("BasePart") then
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
	end
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function solid(props: { [string]: any }, parent: Instance): Part
	return make("Part", props, parent)
end

local function decor(props: { [string]: any }, parent: Instance): Part
	local p = make("Part", props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function glow(
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local p = decor({ Name = name, CFrame = cf, Size = size, Color = color, Material = Enum.Material.Neon }, parent)
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	return p
end

local function rivet(cf: CFrame, color: Color3, parent: Instance)
	decor({
		Name = "Rivet",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.17,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Metal,
		CastShadow = false,
	}, parent)
end

-- A disc lying flat on the deck (cylinders run along X, so tip it up).
local function disc(
	name: string,
	base: CFrame,
	y: number,
	height: number,
	diameter: number,
	props: { [string]: any },
	parent: Instance,
	isSolid: boolean
): Part
	props.Name = name
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
	return if isSolid then solid(props, parent) else decor(props, parent)
end

-- One piece of the barrel lid's arc: at angle phi (0 = straight up, -90 = the front edge), `radius`
-- out from the hinge axis, with its thickness along the arc's normal. `axis` is the lid's axis frame.
local function arcPiece(
	name: string,
	axis: CFrame,
	x: number,
	phi: number,
	radius: number,
	size: Vector3,
	props: { [string]: any },
	parent: Instance
): Part
	props.Name = name
	props.Size = size
	props.CFrame = axis * CFrame.new(x, 0, 0) * CFrame.Angles(phi, 0, 0) * CFrame.new(0, radius - size.Y / 2, 0)
	return decor(props, parent)
end

-- Two-tier stone dais with a glowing ring, a plinth with metal trim and four little lantern posts.
local function dais(base: CFrame, st: any, model: Model)
	local stone = st.Stone
	disc("DaisLow", base, 0.3, 0.6, 9, { Color = stone, Material = Enum.Material.Slate }, model, true)
	disc(
		"DaisRing",
		base,
		0.5,
		0.16,
		9.25,
		{ Color = st.Glow, Material = Enum.Material.Neon, CastShadow = false },
		model,
		false
	)
	disc("DaisHigh", base, 0.9, 0.6, 7, {
		Color = stone:Lerp(Color3.new(1, 1, 1), 0.12),
		Material = Enum.Material.Slate,
	}, model, true)
	disc("DaisInlay", base, 1.21, 0.04, 6.2, {
		Color = stone:Lerp(INK, 0.4),
		Material = Enum.Material.Granite,
		CastShadow = false,
	}, model, false)
	solid({
		Name = "Plinth",
		Size = Vector3.new(W + 1.2, 0.5, D + 1.2),
		CFrame = base * CFrame.new(0, 1.45, 0),
		Color = stone:Lerp(INK, 0.25),
		Material = Enum.Material.Slate,
	}, model)
	-- metal trim around the plinth's top edge
	for _, e in { { 0, -(D + 1.2) / 2, W + 1.3, 0.16 }, { 0, (D + 1.2) / 2, W + 1.3, 0.16 } } do
		decor({
			Name = "PlinthTrim",
			Size = Vector3.new(e[3], 0.16, e[4]),
			CFrame = base * CFrame.new(e[1], DAIS - 0.08, e[2]),
			Color = st.Metal,
			Material = Enum.Material.Metal,
		}, model)
	end
	for _, sx in { -1, 1 } do
		decor({
			Name = "PlinthTrim",
			Size = Vector3.new(0.16, 0.16, D + 1.3),
			CFrame = base * CFrame.new(sx * (W + 1.2) / 2, DAIS - 0.08, 0),
			Color = st.Metal,
			Material = Enum.Material.Metal,
		}, model)
	end
	-- lantern posts on the low tier, at the four diagonals
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local px, pz = math.sin(a) * 3.95, math.cos(a) * 3.95
		local post = base * CFrame.new(px, 0, pz)
		solid({
			Name = "LanternPost",
			Size = Vector3.new(0.5, 1.3, 0.5),
			CFrame = post * CFrame.new(0, 0.6 + 0.65, 0),
			Color = stone:Lerp(Color3.new(1, 1, 1), 0.2),
			Material = Enum.Material.Slate,
		}, model)
		decor({
			Name = "LanternCap",
			Size = Vector3.new(0.7, 0.14, 0.7),
			CFrame = post * CFrame.new(0, 1.97, 0),
			Color = st.Metal,
			Material = Enum.Material.Metal,
		}, model)
		glow("LanternOrb", post * CFrame.new(0, 2.32, 0), Vector3.one * 0.5, st.Glow, model, Enum.PartType.Ball)
	end
end

-- The chest's box: plank walls round a solid core, metal bands, straps, corner guards, rivets, the
-- lock plate, claw feet and the treasure inside (which only shows once the lid lifts).
local function body(base: CFrame, st: any, model: Model, rng: Random)
	local wood, woodAlt, metal = st.Wood, st.WoodAlt, st.Metal
	local function plankColor(i: number): Color3
		local c = if i % 2 == 0 then wood else woodAlt
		return c:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.12))
	end
	solid({
		Name = "Core",
		Size = Vector3.new(W - 0.2, H, D - 0.2),
		CFrame = base * CFrame.new(0, Y0 + H / 2, 0),
		Color = woodAlt:Lerp(INK, 0.3),
		Material = Enum.Material.Wood,
	}, model)
	-- planks: four courses on every face, with a hairline gap between them
	local course = H / 4
	for i = 1, 4 do
		local y = Y0 + (i - 0.5) * course
		for _, sz in { -1, 1 } do
			decor({
				Name = "Plank",
				Size = Vector3.new(W - 0.3, course - 0.07, 0.12),
				CFrame = base * CFrame.new(0, y, sz * (D / 2 - 0.05)),
				Color = plankColor(i + (sz + 1) / 2),
				Material = Enum.Material.WoodPlanks,
			}, model)
		end
		for _, sx in { -1, 1 } do
			decor({
				Name = "Plank",
				Size = Vector3.new(0.12, course - 0.07, D - 0.3),
				CFrame = base * CFrame.new(sx * (W / 2 - 0.05), y, 0),
				Color = plankColor(i + 1 + (sx + 1) / 2),
				Material = Enum.Material.WoodPlanks,
			}, model)
		end
	end
	-- horizontal bands round the bottom and the rim
	for _, y in { Y0 + 0.14, TOP - 0.14 } do
		for _, sz in { -1, 1 } do
			decor({
				Name = "Band",
				Size = Vector3.new(W + 0.06, 0.28, 0.12),
				CFrame = base * CFrame.new(0, y, sz * (D / 2 + 0.03)),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
		end
		for _, sx in { -1, 1 } do
			decor({
				Name = "Band",
				Size = Vector3.new(0.12, 0.28, D + 0.06),
				CFrame = base * CFrame.new(sx * (W / 2 + 0.03), y, 0),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
		end
	end
	-- vertical straps front and back (they carry on over the lid), with rivets
	for _, sx in { -1.55, 1.55 } do
		for _, sz in { -1, 1 } do
			local z = sz * (D / 2 + 0.07)
			decor({
				Name = "Strap",
				Size = Vector3.new(0.44, H, 0.12),
				CFrame = base * CFrame.new(sx, Y0 + H / 2, z),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
			for _, y in { Y0 + 0.55, Y0 + H / 2, TOP - 0.55 } do
				rivet(base * CFrame.new(sx, y, z + sz * 0.07), metal:Lerp(Color3.new(1, 1, 1), 0.3), model)
			end
		end
	end
	-- L-shaped corner guards on the four upright edges
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local cx, cz = sx * (W / 2 + 0.05), sz * (D / 2 + 0.05)
			decor({
				Name = "CornerGuard",
				Size = Vector3.new(0.6, H + 0.1, 0.12),
				CFrame = base * CFrame.new(cx - sx * 0.28, Y0 + H / 2, cz),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
			decor({
				Name = "CornerGuard",
				Size = Vector3.new(0.12, H + 0.1, 0.6),
				CFrame = base * CFrame.new(cx, Y0 + H / 2, cz - sz * 0.28),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
			for _, y in { Y0 + 0.5, TOP - 0.5 } do
				rivet(base * CFrame.new(cx - sx * 0.3, y, cz + sz * 0.07), metal, model)
				rivet(base * CFrame.new(cx + sx * 0.07, y, cz - sz * 0.3), metal, model)
			end
			-- claw foot: a metal ball under each corner
			decor({
				Name = "Foot",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.62,
				CFrame = base * CFrame.new(sx * (W / 2 - 0.3), DAIS + 0.2, sz * (D / 2 - 0.3)),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
		end
	end
	-- lock plate, keyhole and a little shield of trim round it
	local lockZ = -(D / 2 + 0.16)
	decor({
		Name = "LockPlate",
		Size = Vector3.new(1.05, 1.15, 0.16),
		CFrame = base * CFrame.new(0, TOP - 0.62, lockZ),
		Color = metal,
		Material = Enum.Material.Metal,
	}, model)
	decor({
		Name = "LockBoss",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.72, 0.72),
		CFrame = base * CFrame.new(0, TOP - 0.72, lockZ - 0.1) * CFrame.Angles(0, math.rad(90), 0),
		Color = metal:Lerp(Color3.new(1, 1, 1), 0.25),
		Material = Enum.Material.Metal,
	}, model)
	decor({
		Name = "Keyhole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 0.22, 0.22),
		CFrame = base * CFrame.new(0, TOP - 0.66, lockZ - 0.17) * CFrame.Angles(0, math.rad(90), 0),
		Color = INK,
	}, model)
	decor({
		Name = "Keyhole",
		Size = Vector3.new(0.1, 0.24, 0.06),
		CFrame = base * CFrame.new(0, TOP - 0.82, lockZ - 0.17),
		Color = INK,
	}, model)
	-- the hoard: a glowing bed, a heap of tipped coins and a couple of gems (under the closed lid)
	local bed = glow("Glow", base * CFrame.new(0, TOP + 0.03, 0), Vector3.new(W - 0.5, 0.06, D - 0.5), st.Glow, model)
	make("PointLight", { Name = "GlowLight", Color = st.Glow, Range = 14, Brightness = 0, Shadows = false }, bed)
	for _ = 1, 18 do
		local px = rng:NextNumber(-(W / 2 - 0.6), W / 2 - 0.6)
		local pz = rng:NextNumber(-(R - 0.55), R - 0.55)
		-- higher in the middle of the heap, and never through the closed lid
		local mound = (1 - math.abs(px) / (W / 2)) * 0.55 + (1 - math.abs(pz) / R) * 0.25
		decor({
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.09, 0.52, 0.52),
			CFrame = base * CFrame.new(px, TOP + 0.08 + mound * rng:NextNumber(0.3, 1), pz) * CFrame.Angles(
				rng:NextNumber(-0.6, 0.6),
				rng:NextNumber(0, math.pi),
				math.rad(90) + rng:NextNumber(-0.5, 0.5)
			),
			Color = Color3.fromRGB(255, 205, 70),
			Material = Enum.Material.Foil,
			CastShadow = false,
		}, model)
	end
	for _, g in
		{
			{ x = -0.9, z = 0.2, color = st.Gem :: Color3 },
			{ x = 1.1, z = -0.15, color = Color3.fromRGB(80, 230, 140) },
			{ x = 0.15, z = 0.35, color = st.Glow :: Color3 },
		}
	do
		decor({
			Name = "TreasureGem",
			Size = Vector3.one * 0.42,
			CFrame = base * CFrame.new(g.x, TOP + 0.5, g.z) * CFrame.Angles(math.rad(45), math.rad(35), math.rad(45)),
			Color = g.color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			Reflectance = 0.2,
			CastShadow = false,
		}, model)
	end
end

-- The barrel lid: curved planks over fan-filled end caps, metal arcs over the straps and both ends,
-- a front lip with a hasp and a jewel. Pivot = the back hinge.
local function lid(base: CFrame, st: any, model: Model, rng: Random): Model
	local wood, woodAlt, metal = st.Wood, st.WoodAlt, st.Metal
	local lidModel = Instance.new("Model")
	lidModel.Name = "Lid"
	local axis = base * CFrame.new(0, TOP, 0)
	local hinge = decor({
		Name = "Hinge",
		Size = Vector3.new(W, 0.2, 0.2),
		CFrame = axis * CFrame.new(0, 0, R),
		Transparency = 1,
	}, lidModel)
	lidModel.PrimaryPart = hinge
	local planks = 7
	local step = math.pi / planks
	local chord = 2 * R * math.sin(step / 2) * 1.06
	for i = 1, planks do
		local phi = -math.pi / 2 + (i - 0.5) * step
		arcPiece("LidPlank", axis, 0, phi, R, Vector3.new(W - 0.3, 0.16, chord), {
			Color = (if i % 2 == 0 then wood else woodAlt):Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.1)),
			Material = Enum.Material.WoodPlanks,
		}, lidModel)
		-- end caps: a fan of slabs from the axis out to the rim fills each half-disc
		for _, sx in { -1, 1 } do
			arcPiece("LidCap", axis, sx * (W / 2 - 0.1), phi, R - 0.02, Vector3.new(0.14, R - 0.02, chord), {
				Color = woodAlt,
				Material = Enum.Material.WoodPlanks,
			}, lidModel)
		end
	end
	-- metal arcs: over each strap and round both ends, smoother than the planks
	local bands = 10
	local bstep = math.pi / bands
	local bchord = 2 * (R + 0.08) * math.sin(bstep / 2) * 1.1
	for i = 1, bands do
		local phi = -math.pi / 2 + (i - 0.5) * bstep
		for _, x in { -1.55, 1.55 } do
			arcPiece("LidBand", axis, x, phi, R + 0.08, Vector3.new(0.44, 0.12, bchord), {
				Color = metal,
				Material = Enum.Material.Metal,
			}, lidModel)
		end
		for _, sx in { -1, 1 } do
			arcPiece("LidEdge", axis, sx * (W / 2 + 0.02), phi, R + 0.06, Vector3.new(0.22, 0.2, bchord), {
				Color = metal,
				Material = Enum.Material.Metal,
			}, lidModel)
		end
		if i % 3 == 2 then
			for _, x in { -1.55, 1.55 } do
				rivet(
					axis * CFrame.new(x, 0, 0) * CFrame.Angles(phi, 0, 0) * CFrame.new(0, R + 0.14, 0),
					metal:Lerp(Color3.new(1, 1, 1), 0.3),
					lidModel
				)
			end
		end
	end
	-- lips along the front and back edges of the lid
	for _, sz in { -1, 1 } do
		decor({
			Name = "LidLip",
			Size = Vector3.new(W + 0.06, 0.24, 0.14),
			CFrame = axis * CFrame.new(0, 0.12, sz * (R + 0.04)),
			Color = metal,
			Material = Enum.Material.Metal,
		}, lidModel)
	end
	-- hasp hanging over the lock plate
	decor({
		Name = "Hasp",
		Size = Vector3.new(0.46, 0.62, 0.1),
		CFrame = axis * CFrame.new(0, -0.18, -(R + 0.36)),
		Color = metal:Lerp(Color3.new(1, 1, 1), 0.15),
		Material = Enum.Material.Metal,
	}, lidModel)
	-- the jewel on the front of the lid, in a metal setting
	local jewelAt = axis * CFrame.Angles(math.rad(-58), 0, 0) * CFrame.new(0, R + 0.1, 0)
	decor({
		Name = "JewelSetting",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.74, 0.74),
		CFrame = jewelAt * CFrame.Angles(0, 0, math.rad(90)),
		Color = metal,
		Material = Enum.Material.Metal,
	}, lidModel)
	local jewel =
		glow("Jewel", jewelAt * CFrame.new(0, 0.12, 0), Vector3.one * 0.46, st.Gem, lidModel, Enum.PartType.Ball)
	jewel.Material = Enum.Material.Glass
	jewel.Transparency = 0.05
	jewel.Reflectance = 0.25
	glow("JewelCore", jewelAt * CFrame.new(0, 0.1, 0), Vector3.one * 0.26, st.Gem, lidModel, Enum.PartType.Ball)
	lidModel.Parent = model
	return lidModel
end

-- A cut gem hovering over the chest (ChestController spins and bobs it): a glowing core inside a
-- glass shell, both as cubes stood on a corner.
local function floatingGem(base: CFrame, st: any, model: Model)
	local gem = Instance.new("Model")
	gem.Name = "FloatingGem"
	local at = base * CFrame.new(0, TOP + R + 2.3, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.26))
	local core = glow("GemCore", at, Vector3.one * 0.7, st.Glow, gem)
	gem.PrimaryPart = core
	decor({
		Name = "GemShell",
		Size = Vector3.one * 1.05,
		CFrame = at,
		Color = st.Gem,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Reflectance = 0.2,
		CastShadow = false,
	}, gem)
	make("PointLight", { Color = st.Glow, Range = 9, Brightness = 0.9, Shadows = false }, core)
	gem:AddTag("ChestGem")
	gem.Parent = model
end

-- Price sign floating above everything.
local function sign(base: CFrame, model: Model, tier: any, guarantee: string)
	local anchor = decor({
		Name = "SignAnchor",
		Size = Vector3.one * 0.2,
		CFrame = base * CFrame.new(0, TOP + R + 5, 0),
		Transparency = 1,
	}, model)
	local bb = make("BillboardGui", {
		Name = "PriceSign",
		Size = UDim2.fromScale(7, 2.4),
		LightInfluence = 0,
		MaxDistance = 70,
	}, anchor)
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, bb)
	local lines: { { any } } = {
		{ string.upper(tier.Name), 0.55, Color3.new(1, 1, 1) },
		{ ("%s · %d COINS"):format(guarantee, tier.Cost), 0.32, Color3.fromRGB(255, 214, 80) },
	}
	for i, line in lines do
		local t = make("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.fromScale(1, line[2]),
			BackgroundTransparency = 1,
			Text = line[1],
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			TextColor3 = line[3],
		}, bb)
		make("UIStroke", { Thickness = 3, Color = INK }, t)
	end
end

local function effects(base: CFrame, st: any, model: Model)
	-- the burst comes out of the open box; the FX part only holds its attachment
	local holder = decor({
		Name = "FX",
		Size = Vector3.one * 0.2,
		CFrame = base * CFrame.new(0, TOP + 0.3, 0),
		Transparency = 1,
	}, model)
	local att = make("Attachment", { Name = "FXAttachment" }, holder)
	-- idle sparkles rise off a shell just around the lid (not from inside it, where they'd be hidden)
	local aura = decor({
		Name = "SparkleZone",
		Size = Vector3.new(W + 0.8, R + 0.8, D + 0.8),
		CFrame = base * CFrame.new(0, TOP + R / 2, 0),
		Transparency = 1,
	}, model)
	make("ParticleEmitter", {
		Name = "Sparkles",
		Texture = SPARKLE,
		Color = ColorSequence.new(st.Glow, Color3.new(1, 1, 1)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2.2),
		Rate = 5,
		Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(40, 40),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	}, aura)
	-- the open burst (ChestController calls :Emit)
	make("ParticleEmitter", {
		Name = "Burst",
		Texture = SPARKLE,
		Color = ColorSequence.new(st.Glow, Color3.new(1, 1, 1)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.5),
		Rate = 0,
		Enabled = false,
		Speed = NumberRange.new(10, 20),
		Drag = 3,
		Acceleration = Vector3.new(0, -8, 0),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
	}, att)
	-- a soft wash of light from above, in the chest's colour
	local spot = decor({
		Name = "Downlight",
		Size = Vector3.one * 0.3,
		CFrame = base * CFrame.new(0, TOP + 8, -3) * CFrame.Angles(math.rad(-110), 0, 0),
		Transparency = 1,
	}, model)
	make("SpotLight", { Face = Enum.NormalId.Front, Color = st.Glow, Range = 14, Angle = 55, Brightness = 1.4 }, spot)
end

-- Build chest `index` at `base` (on the deck, front facing -Z) into `parent`.
function ChestBuilder.build(index: number, base: CFrame, styleName: string, parent: Instance): Model
	local st = (CH.Styles :: any)[styleName] or CH.Styles.Gold
	local rng = Random.new(1000 + index)
	local model = Instance.new("Model")
	model.Name = "LootChest" .. index
	model:SetAttribute("ChestIndex", index)
	model:SetAttribute("Style", styleName)
	dais(base, st, model)
	body(base, st, model, rng)
	lid(base, st, model, rng)
	floatingGem(base, st, model)
	local tierName = (CH.Spots[index] and CH.Spots[index].Tier) or "Common"
	local tier = (CH.Tiers :: any)[tierName]
	local lowest = "Common"
	for _, r in { "Common", "Rare", "Epic", "Legendary" } do
		if (tier.RarityWeights[r] or 0) > 0 then
			lowest = r
			break
		end
	end
	model:SetAttribute("Tier", tierName)
	sign(base, model, tier, if lowest == "Common" then "ANY COSMETIC" else string.upper(lowest) .. "+")
	effects(base, st, model)
	local anchor = decor({
		Name = "PromptAnchor",
		Size = Vector3.one * 0.5,
		CFrame = base * CFrame.new(0, Y0 + H * 0.6, -(D / 2 + 0.8)),
		Transparency = 1,
	}, model)
	local prompt = make("ProximityPrompt", {
		Name = "ChestPrompt",
		ActionText = "Open",
		ObjectText = tier.Name,
		HoldDuration = 0,
		Style = Enum.ProximityPromptStyle.Custom, -- drawn by PromptController in the Toybox style
		MaxActivationDistance = CH.PromptDistance,
		RequiresLineOfSight = false,
	}, anchor)
	prompt:SetAttribute("ChestIndex", index)
	model.PrimaryPart = model:FindFirstChild("Core") :: BasePart
	model:AddTag("LootChest")
	model.Parent = parent
	return model
end

return ChestBuilder
