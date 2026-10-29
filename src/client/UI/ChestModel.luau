--!strict
-- The treasure chest the quest chest opening shows in a ViewportFrame (QuestController). It's the
-- old hub loot chest without its dais: plank walls round a core, metal bands, straps, corner guards
-- and rivets, a lock plate, claw feet, a hoard of coins and gems inside and a barrel lid built from
-- curved planks. Built in its own frame: front = -Z, the feet on y = 0.
--
-- The lid is its own Model ("Lid") whose pivot is the back hinge, so the opening swings it with
-- PivotTo(home * CFrame.Angles(angle, 0, 0)). "Glow" is the treasure bed, recolored to the prize's
-- rarity when the lid bursts open.

local ChestModel = {}

local INK = Color3.fromRGB(16, 12, 34)
local WHITE = Color3.new(1, 1, 1)

export type Style = { Wood: Color3, WoodAlt: Color3, Metal: Color3, Glow: Color3, Gem: Color3 }

-- One look per quest chest (Config.Quests.Chests).
ChestModel.Styles = {
	Title = { -- frost
		Wood = Color3.fromRGB(70, 92, 128),
		WoodAlt = Color3.fromRGB(58, 78, 112),
		Metal = Color3.fromRGB(200, 236, 255),
		Glow = Color3.fromRGB(110, 225, 255),
		Gem = Color3.fromRGB(90, 200, 255),
	},
	Gesture = { -- royal
		Wood = Color3.fromRGB(78, 40, 96),
		WoodAlt = Color3.fromRGB(64, 32, 80),
		Metal = Color3.fromRGB(255, 186, 70),
		Glow = Color3.fromRGB(205, 120, 255),
		Gem = Color3.fromRGB(190, 90, 255),
	},
	Finisher = { -- gold
		Wood = Color3.fromRGB(122, 72, 40),
		WoodAlt = Color3.fromRGB(104, 60, 34),
		Metal = Color3.fromRGB(255, 196, 60),
		Glow = Color3.fromRGB(255, 210, 90),
		Gem = Color3.fromRGB(255, 70, 90),
	},
} :: { [string]: Style }

-- dimensions (studs)
local W = 5 -- width (X)
local D = 3.2 -- depth (Z); the barrel lid's radius is D / 2
local H = 2.4 -- body height
local R = D / 2
local Y0 = 0.25 -- bottom of the body (on its feet)
local TOP = Y0 + H -- the lid's hinge axis height
ChestModel.Size = Vector3.new(W, TOP + R, D)

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function rivet(cf: CFrame, color: Color3, parent: Instance)
	part({
		Name = "Rivet",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.17,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Metal,
	}, parent)
end

-- One piece of the barrel lid's arc: at angle phi (0 = straight up, -90 = the front edge), `radius`
-- out from the hinge axis, with its thickness along the arc's normal.
local function arcPiece(
	name: string,
	axis: CFrame,
	x: number,
	phi: number,
	radius: number,
	size: Vector3,
	props: { [string]: any },
	parent: Instance
)
	props.Name = name
	props.Size = size
	props.CFrame = axis * CFrame.new(x, 0, 0) * CFrame.Angles(phi, 0, 0) * CFrame.new(0, radius - size.Y / 2, 0)
	part(props, parent)
end

-- The box: plank walls round a core, metal bands, straps, corner guards, rivets, the lock plate,
-- claw feet and the treasure inside (which only shows once the lid lifts).
local function body(st: Style, model: Model, rng: Random)
	local wood, woodAlt, metal = st.Wood, st.WoodAlt, st.Metal
	local function plankColor(i: number): Color3
		local c = if i % 2 == 0 then wood else woodAlt
		return c:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.12))
	end
	part({
		Name = "Core",
		Size = Vector3.new(W - 0.2, H, D - 0.2),
		CFrame = CFrame.new(0, Y0 + H / 2, 0),
		Color = woodAlt:Lerp(INK, 0.3),
		Material = Enum.Material.Wood,
	}, model)
	-- planks: four courses on every face, with a hairline gap between them
	local course = H / 4
	for i = 1, 4 do
		local y = Y0 + (i - 0.5) * course
		for _, sz in { -1, 1 } do
			part({
				Name = "Plank",
				Size = Vector3.new(W - 0.3, course - 0.07, 0.12),
				CFrame = CFrame.new(0, y, sz * (D / 2 - 0.05)),
				Color = plankColor(i + (sz + 1) / 2),
				Material = Enum.Material.WoodPlanks,
			}, model)
		end
		for _, sx in { -1, 1 } do
			part({
				Name = "Plank",
				Size = Vector3.new(0.12, course - 0.07, D - 0.3),
				CFrame = CFrame.new(sx * (W / 2 - 0.05), y, 0),
				Color = plankColor(i + 1 + (sx + 1) / 2),
				Material = Enum.Material.WoodPlanks,
			}, model)
		end
	end
	-- bands round the bottom and the rim
	for _, y in { Y0 + 0.14, TOP - 0.14 } do
		for _, sz in { -1, 1 } do
			part({
				Name = "Band",
				Size = Vector3.new(W + 0.06, 0.28, 0.12),
				CFrame = CFrame.new(0, y, sz * (D / 2 + 0.03)),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
		end
		for _, sx in { -1, 1 } do
			part({
				Name = "Band",
				Size = Vector3.new(0.12, 0.28, D + 0.06),
				CFrame = CFrame.new(sx * (W / 2 + 0.03), y, 0),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
		end
	end
	-- straps front and back (they carry on over the lid), with rivets
	for _, sx in { -1.55, 1.55 } do
		for _, sz in { -1, 1 } do
			local z = sz * (D / 2 + 0.07)
			part({
				Name = "Strap",
				Size = Vector3.new(0.44, H, 0.12),
				CFrame = CFrame.new(sx, Y0 + H / 2, z),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
			for _, y in { Y0 + 0.55, Y0 + H / 2, TOP - 0.55 } do
				rivet(CFrame.new(sx, y, z + sz * 0.07), metal:Lerp(WHITE, 0.3), model)
			end
		end
	end
	-- L-shaped corner guards on the four upright edges, and a claw foot under each corner
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local cx, cz = sx * (W / 2 + 0.05), sz * (D / 2 + 0.05)
			part({
				Name = "CornerGuard",
				Size = Vector3.new(0.6, H + 0.1, 0.12),
				CFrame = CFrame.new(cx - sx * 0.28, Y0 + H / 2, cz),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
			part({
				Name = "CornerGuard",
				Size = Vector3.new(0.12, H + 0.1, 0.6),
				CFrame = CFrame.new(cx, Y0 + H / 2, cz - sz * 0.28),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
			for _, y in { Y0 + 0.5, TOP - 0.5 } do
				rivet(CFrame.new(cx - sx * 0.3, y, cz + sz * 0.07), metal, model)
				rivet(CFrame.new(cx + sx * 0.07, y, cz - sz * 0.3), metal, model)
			end
			part({
				Name = "Foot",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.62,
				CFrame = CFrame.new(sx * (W / 2 - 0.3), 0.31, sz * (D / 2 - 0.3)),
				Color = metal,
				Material = Enum.Material.Metal,
			}, model)
		end
	end
	-- lock plate and keyhole
	local lockZ = -(D / 2 + 0.16)
	part({
		Name = "LockPlate",
		Size = Vector3.new(1.05, 1.15, 0.16),
		CFrame = CFrame.new(0, TOP - 0.62, lockZ),
		Color = metal,
		Material = Enum.Material.Metal,
	}, model)
	part({
		Name = "LockBoss",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.72, 0.72),
		CFrame = CFrame.new(0, TOP - 0.72, lockZ - 0.1) * CFrame.Angles(0, math.rad(90), 0),
		Color = metal:Lerp(WHITE, 0.25),
		Material = Enum.Material.Metal,
	}, model)
	part({
		Name = "Keyhole",
		Size = Vector3.new(0.12, 0.34, 0.06),
		CFrame = CFrame.new(0, TOP - 0.74, lockZ - 0.17),
		Color = INK,
	}, model)
	-- the hoard: a glowing bed, a heap of tipped coins and a few gems
	part({
		Name = "Glow",
		Size = Vector3.new(W - 0.5, 0.06, D - 0.5),
		CFrame = CFrame.new(0, TOP + 0.03, 0),
		Color = st.Glow,
		Material = Enum.Material.Neon,
	}, model)
	for _ = 1, 18 do
		local px = rng:NextNumber(-(W / 2 - 0.6), W / 2 - 0.6)
		local pz = rng:NextNumber(-(R - 0.55), R - 0.55)
		local mound = (1 - math.abs(px) / (W / 2)) * 0.55 + (1 - math.abs(pz) / R) * 0.25
		part({
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.09, 0.52, 0.52),
			CFrame = CFrame.new(px, TOP + 0.08 + mound * rng:NextNumber(0.3, 1), pz) * CFrame.Angles(
				rng:NextNumber(-0.6, 0.6),
				rng:NextNumber(0, math.pi),
				math.rad(90) + rng:NextNumber(-0.5, 0.5)
			),
			Color = Color3.fromRGB(255, 205, 70),
			Material = Enum.Material.Foil,
		}, model)
	end
	for _, g in
		{
			{ x = -0.9, z = 0.2, color = st.Gem },
			{ x = 1.1, z = -0.15, color = Color3.fromRGB(80, 230, 140) },
			{ x = 0.15, z = 0.35, color = st.Glow },
		}
	do
		part({
			Name = "TreasureGem",
			Size = Vector3.one * 0.42,
			CFrame = CFrame.new(g.x, TOP + 0.5, g.z) * CFrame.Angles(math.rad(45), math.rad(35), math.rad(45)),
			Color = g.color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			Reflectance = 0.2,
		}, model)
	end
end

-- The barrel lid: curved planks over fan-filled end caps, metal arcs over the straps and both ends,
-- lips front and back, a hasp and a jewel. Pivot = the back hinge.
local function lid(st: Style, model: Model, rng: Random)
	local wood, woodAlt, metal = st.Wood, st.WoodAlt, st.Metal
	local lidModel = Instance.new("Model")
	lidModel.Name = "Lid"
	local axis = CFrame.new(0, TOP, 0)
	lidModel.PrimaryPart = part({
		Name = "Hinge",
		Size = Vector3.new(W, 0.2, 0.2),
		CFrame = axis * CFrame.new(0, 0, R),
		Transparency = 1,
	}, lidModel)
	local planks = 7
	local step = math.pi / planks
	local chord = 2 * R * math.sin(step / 2) * 1.06
	for i = 1, planks do
		local phi = -math.pi / 2 + (i - 0.5) * step
		arcPiece("LidPlank", axis, 0, phi, R, Vector3.new(W - 0.3, 0.16, chord), {
			Color = (if i % 2 == 0 then wood else woodAlt):Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.1)),
			Material = Enum.Material.WoodPlanks,
		}, lidModel)
		for _, sx in { -1, 1 } do
			arcPiece("LidCap", axis, sx * (W / 2 - 0.1), phi, R - 0.02, Vector3.new(0.14, R - 0.02, chord), {
				Color = woodAlt,
				Material = Enum.Material.WoodPlanks,
			}, lidModel)
		end
	end
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
					metal:Lerp(WHITE, 0.3),
					lidModel
				)
			end
		end
	end
	for _, sz in { -1, 1 } do
		part({
			Name = "LidLip",
			Size = Vector3.new(W + 0.06, 0.24, 0.14),
			CFrame = axis * CFrame.new(0, 0.12, sz * (R + 0.04)),
			Color = metal,
			Material = Enum.Material.Metal,
		}, lidModel)
	end
	part({
		Name = "Hasp",
		Size = Vector3.new(0.46, 0.62, 0.1),
		CFrame = axis * CFrame.new(0, -0.18, -(R + 0.36)),
		Color = metal:Lerp(WHITE, 0.15),
		Material = Enum.Material.Metal,
	}, lidModel)
	local jewelAt = axis * CFrame.Angles(math.rad(-58), 0, 0) * CFrame.new(0, R + 0.1, 0)
	part({
		Name = "JewelSetting",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.74, 0.74),
		CFrame = jewelAt * CFrame.Angles(0, 0, math.rad(90)),
		Color = metal,
		Material = Enum.Material.Metal,
	}, lidModel)
	part({
		Name = "Jewel",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.46,
		CFrame = jewelAt * CFrame.new(0, 0.12, 0),
		Color = st.Gem,
		Material = Enum.Material.Neon,
	}, lidModel)
	lidModel.Parent = model
end

-- Build the chest for quest chest `chest` ("Title" | "Gesture" | "Finisher"), unparented.
function ChestModel.build(chest: string): Model
	local st = ChestModel.Styles[chest] or ChestModel.Styles.Finisher
	local rng = Random.new(7)
	local model = Instance.new("Model")
	model.Name = "QuestChest"
	body(st, model, rng)
	lid(st, model, rng)
	model.PrimaryPart = model:FindFirstChild("Core") :: BasePart
	return model
end

return ChestModel
