--!strict
-- A carved jack-o-lantern built from parts (Config.Halloween.Ball colors): a squashed body with
-- darker ribs, a stem, and a glowing carved face on its -Z side. Used for the Halloween balls and
-- the Jack-o'-Lantern ball skin (HalloweenController), the Pumpkin Head intro pose (IntroController)
-- and the Haunted Bundle display in the hub (BundleDisplayController). Body parts are named "Body"
-- and "Rib" so they can be recolored.

local Config = require(script.Parent.Config)

local B = Config.Halloween.Ball

local JackOLantern = {}

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

-- A pumpkin of body radius `r` centered on `cf` (face toward cf's -Z), its parts unanchored and
-- massless. Weld it on with JackOLantern.weld, or anchor it and move it with PivotTo.
function JackOLantern.build(cf: CFrame, r: number, name: string?): Model
	local model = Instance.new("Model")
	model.Name = name or "JackOLantern"
	local k = r / 1.35 -- the face layout is drawn for the Pumpkin finisher's 1.35-stud pumpkin
	local body = piece({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * r * 2,
		Color = B.Body,
		CFrame = cf,
	}, model)
	local squash = Instance.new("SpecialMesh")
	squash.MeshType = Enum.MeshType.Sphere
	squash.Scale = Vector3.new(1, 0.88, 1)
	squash.Parent = body
	model.PrimaryPart = body
	for i = 0, 2 do
		piece({
			Name = "Rib",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1 * k, r * 2.02 * 0.88, r * 2.02),
			Color = B.Rib,
			CFrame = cf * CFrame.Angles(0, math.rad(60 * i), 0) * CFrame.Angles(0, math.rad(90), 0),
		}, model)
	end
	piece({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5 * k, 0.3 * k, 0.3 * k),
		Color = B.Stem,
		CFrame = cf * CFrame.new(0, r * 0.88 + 0.15 * k, 0) * CFrame.Angles(0, 0, math.rad(80)),
	}, model)
	-- the glowing carved face: diamond eyes, a nose and a jagged grin
	local function feature(x: number, y: number, size: Vector3, rotZ: number)
		x, y = x * k, y * k * 0.88
		local z = -math.sqrt(math.max(0.05 * k, r * r - x * x - (y / 0.88) ^ 2)) + 0.02
		local pos = Vector3.new(x, y, z)
		piece({
			Name = "Carve",
			Size = size * k,
			Color = B.Carve,
			Material = Enum.Material.Neon,
			CFrame = cf * CFrame.lookAt(pos, pos * 2) * CFrame.Angles(0, 0, math.rad(rotZ)),
		}, model)
	end
	feature(-0.48, 0.32, Vector3.new(0.42, 0.42, 0.06), 45)
	feature(0.48, 0.32, Vector3.new(0.42, 0.42, 0.06), 45)
	feature(0, 0.02, Vector3.new(0.2, 0.2, 0.06), 45)
	for i = -2, 2 do
		feature(i * 0.27, -0.42 + (if i % 2 == 0 then 0.06 else -0.06), Vector3.new(0.26, 0.2, 0.06), 0)
	end
	return model
end

-- Weld every part of `model` to `part` where they stand now, so the pumpkin follows it.
function JackOLantern.weld(model: Model, part: BasePart)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = part
			w.Part1 = p
			w.Parent = p
		end
	end
end

-- Anchor every part (for a pumpkin moved with PivotTo, or posed in a ViewportFrame).
function JackOLantern.anchor(model: Model)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
end

-- Is `p` worn on `head` (an accessory handle welded to it)?
local function onHead(p: BasePart, head: BasePart): boolean
	for _, j in p:GetChildren() do
		if j:IsA("JointInstance") and (j.Part0 == head or j.Part1 == head) then
			return true
		end
		if j:IsA("WeldConstraint") and (j.Part0 == head or j.Part1 == head) then
			return true
		end
	end
	return false
end

-- Put a jack-o-lantern over `character`'s head (the Pumpkin Head pose), hiding the head, its face
-- and the hats and hair on it. `posed` is for a rig that never moves (the shop portrait and the hub
-- stand): the pumpkin is anchored and the head hidden for good. Otherwise the pumpkin is welded on
-- and hidden only locally; the returned function takes it off and shows the head again.
function JackOLantern.onHead(character: Model, posed: boolean?): () -> ()
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return function() end
	end
	-- sized off the head's height so classic (2x1x1) and mesh heads both end up inside
	local r = math.clamp(head.Size.Y * 0.75, 0.75, 1.4)
	local pumpkin = JackOLantern.build(head.CFrame * CFrame.new(0, r * 0.08, 0), r, "RD_PumpkinHead")
	if posed then
		JackOLantern.anchor(pumpkin)
	else
		JackOLantern.weld(pumpkin, head)
	end
	pumpkin.Parent = character
	local parts: { BasePart } = { head }
	for _, acc in character:GetChildren() do
		local handle = acc:IsA("Accoutrement") and acc:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") and onHead(handle, head) then
			table.insert(parts, handle)
		end
	end
	local decals: { [Decal]: number } = {}
	for _, d in head:GetChildren() do
		if d:IsA("Decal") then
			decals[d] = d.Transparency
			d.Transparency = 1
		end
	end
	for _, p in parts do
		if posed then
			p.Transparency = 1
		else
			p.LocalTransparencyModifier = 1
		end
	end
	return function()
		pumpkin:Destroy()
		for d, t in decals do
			d.Transparency = t
		end
		for _, p in parts do
			p.LocalTransparencyModifier = 0
		end
	end
end

return JackOLantern
