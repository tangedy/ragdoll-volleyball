--!strict
-- Idempotent hub builder: a neon rooftop at night. The deck is the roof of a skyscraper that sinks
-- into the purple void, with parapets, a glass railing on the court side, props, string lights and
-- lit windows down the tower. Everything is placed in the deck's own frame (ArenaLayout.LobbyFrame:
-- X = right, F = forward toward the court), so moving LobbyOrigin moves the whole hub.
-- Rebuilding replaces Workspace.Lobby entirely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local ChestBuilder = require(script.Parent.ChestBuilder)

local A = Config.Arena
local L = Config.Lobby
local PAL = L.Palette

local LobbyBuilder = {}

local frame = ArenaLayout.LobbyFrame
local W = A.LobbySize.X / 2 -- half width
local D = A.LobbySize.Z / 2 -- half depth

-- Deck-frame CFrame: x = right, y = up from the deck surface, f = toward the court.
local function at(x: number, y: number, f: number): CFrame
	return frame * CFrame.new(x, y, -f)
end
LobbyBuilder.at = at

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

-- Solid scenery: characters stand on it and practice balls bounce off it.
local function solid(props: { [string]: any }, parent: Instance): Part
	return make("Part", props, parent)
end

-- Pure decoration: never collides, never queried, never touched.
local function decor(props: { [string]: any }, parent: Instance): Part
	local p = make("Part", props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end
LobbyBuilder.solid = solid
LobbyBuilder.decor = decor

-- A glowing neon strip with a soft light (no curtain: the hub is calmer than the court).
local function neon(name: string, cf: CFrame, size: Vector3, color: Color3, parent: Instance, light: number?): Part
	local p = decor({ Name = name, CFrame = cf, Size = size, Color = color, Material = Enum.Material.Neon }, parent)
	p.CastShadow = false
	if light then
		make("PointLight", { Color = color, Range = light, Brightness = 1.2, Shadows = false }, p)
	end
	return p
end
LobbyBuilder.neon = neon

-- A vertical cylinder standing on the deck (Roblox cylinders run along X, so tip it up).
local function column(
	props: { [string]: any },
	x: number,
	y: number,
	f: number,
	height: number,
	diameter: number,
	parent: Instance,
	isSolid: boolean
): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = at(x, y, f) * CFrame.Angles(0, 0, math.rad(90))
	return if isSolid then solid(props, parent) else decor(props, parent)
end
LobbyBuilder.column = column

-- Text painted on a face of a part (SurfaceGui), for signs and floor markings.
function LobbyBuilder.paint(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3,
	opts: { [string]: any }?
): TextLabel
	local sg = make("SurfaceGui", {
		Name = "Paint",
		Face = face,
		LightInfluence = 0,
		Brightness = 2,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 30,
	}, part)
	local t = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
	}, sg)
	if opts then
		for k, v in opts do
			(t :: any)[k] = v
		end
	end
	return t
end

-- Deck, inlays and edges -------------------------------------------------------------------------

local function buildDeck(collidable: Folder, decorF: Folder)
	solid({
		Name = "LobbyFloor",
		Size = Vector3.new(W * 2, A.LobbySize.Y, D * 2),
		CFrame = at(0, -A.LobbySize.Y / 2, 0),
		Color = PAL.Deck,
		Material = Enum.Material.Concrete,
	}, collidable)
	-- big concrete pavers in two tones (decor inlays a hair above the slab)
	local tile = 12
	local nx, nz = math.floor(W * 2 / tile), math.floor(D * 2 / tile)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			if (i + j) % 2 == 0 then
				local x = -W + tile / 2 + i * tile + (W * 2 - nx * tile) / 2
				local f = -D + tile / 2 + j * tile + (D * 2 - nz * tile) / 2
				decor({
					Name = "Paver",
					Size = Vector3.new(tile - 0.3, 0.04, tile - 0.3),
					CFrame = at(x, 0.02, f),
					Color = PAL.DeckAlt,
					Material = Enum.Material.Slate,
				}, decorF)
			end
		end
	end
end

-- Low parapet with a metal cap and a purple neon strip on its inner face.
local function parapet(x0: number, f0: number, x1: number, f1: number, collidable: Folder, decorF: Folder)
	local mid = Vector3.new((x0 + x1) / 2, 0, (f0 + f1) / 2)
	local len = math.max(math.abs(x1 - x0), math.abs(f1 - f0)) + 1
	local alongX = math.abs(x1 - x0) > math.abs(f1 - f0)
	local h = L.ParapetHeight
	local size = if alongX then Vector3.new(len, h, 1) else Vector3.new(1, h, len)
	solid({
		Name = "Parapet",
		Size = size,
		CFrame = at(mid.X, h / 2, mid.Z),
		Color = PAL.Wall,
		Material = Enum.Material.Concrete,
	}, collidable)
	decor({
		Name = "ParapetCap",
		Size = size + Vector3.new(if alongX then 0 else 0.4, -h + 0.3, if alongX then 0.4 else 0),
		CFrame = at(mid.X, h + 0.15, mid.Z),
		Color = PAL.Metal,
		Material = Enum.Material.Metal,
	}, decorF)
	-- the strip sits on the deck side of the wall
	local inward = Vector3.new(-mid.X, 0, -mid.Z)
	local nudge = if alongX
		then Vector3.new(0, 0, math.sign(inward.Z) * 0.55)
		else Vector3.new(math.sign(inward.X) * 0.55, 0, 0)
	neon(
		"ParapetGlow",
		at(mid.X + nudge.X, h - 0.25, mid.Z + nudge.Z),
		if alongX then Vector3.new(len - 1, 0.2, 0.1) else Vector3.new(0.1, 0.2, len - 1),
		PAL.Trim,
		decorF
	)
end

-- Glass railing along the court side: metal posts, tinted panels and a cyan-lit handrail.
local function courtRailing(collidable: Folder, decorF: Folder)
	local h = L.RailHeight
	local f = D - 0.5
	local step = 8
	local count = math.floor(W * 2 / step)
	for i = 0, count do
		local x = -W + i * (W * 2 / count)
		solid({
			Name = "RailPost",
			Size = Vector3.new(0.5, h, 0.5),
			CFrame = at(x, h / 2, f),
			Color = PAL.Metal,
			Material = Enum.Material.Metal,
		}, collidable)
	end
	solid({
		Name = "RailGlass",
		Size = Vector3.new(W * 2, h - 0.6, 0.2),
		CFrame = at(0, (h - 0.6) / 2 + 0.1, f),
		Color = PAL.Cyan:Lerp(Color3.new(1, 1, 1), 0.6),
		Material = Enum.Material.Glass,
		Transparency = 0.7,
		CastShadow = false,
	}, collidable)
	decor({
		Name = "Handrail",
		Size = Vector3.new(W * 2 + 0.6, 0.35, 0.6),
		CFrame = at(0, h, f),
		Color = PAL.Metal,
		Material = Enum.Material.Metal,
	}, decorF)
	local glow = neon("HandrailGlow", at(0, h - 0.3, f - 0.35), Vector3.new(W * 2, 0.12, 0.12), PAL.Cyan, decorF)
	make(
		"SurfaceLight",
		{ Face = Enum.NormalId.Bottom, Color = PAL.Cyan, Range = 8, Angle = 70, Brightness = 1.2 },
		glow
	)
end

-- Invisible walls: keep walkers on the deck, and keep practice balls out of the court.
local function edgeBarriers(barriers: Folder)
	local wallH = 14
	local function wall(name: string, cf: CFrame, size: Vector3, group: string)
		make("Part", {
			Name = name,
			Size = size,
			CFrame = cf,
			Transparency = 1,
			CanQuery = group == "LobbyNet", -- practice-ball sphere casts stop at the net
			CanTouch = false,
			CastShadow = false,
			CollisionGroup = group,
		}, barriers)
	end
	-- walkers: back, right end and court side (the practice end is open past its own wall)
	wall("HubWallBack", at(0, wallH / 2, -D - 0.5), Vector3.new(W * 2 + 2, wallH, 1), "PlayerWall")
	wall("HubWallRight", at(W + 0.5, wallH / 2, 0), Vector3.new(1, wallH, D * 2 + 2), "PlayerWall")
	wall("HubWallFront", at(0, wallH / 2, D + 0.5), Vector3.new(W * 2 + 2, wallH, 1), "PlayerWall")
	wall("HubWallLeft", at(-W - 0.5, wallH / 2, 0), Vector3.new(1, wallH, D * 2 + 2), "PlayerWall")
	-- practice wall: walkers stop before the dummy, which stands near the open drop
	wall(
		"PracticeWall",
		at(L.Practice.WallX, A.BarrierHeight / 2, 0),
		Vector3.new(0.6, A.BarrierHeight, D * 2),
		"PlayerWall"
	)
	-- ball net on the court side: tall enough that no practice throw can arc over it
	wall("BallNet", at(0, 30, D + 1), Vector3.new(W * 2 + 2, 60, 1), "LobbyNet")
end

-- The tower under the deck ------------------------------------------------------------------------

local function buildTower(decorF: Folder, rng: Random)
	local depth = L.BuildingDepth
	decor({
		Name = "Tower",
		Size = Vector3.new(W * 2 - 2, depth, D * 2 - 2),
		CFrame = at(0, -A.LobbySize.Y - depth / 2, 0),
		Color = PAL.Wall,
		Material = Enum.Material.Concrete,
	}, decorF)
	-- cornice: a lip under the deck with a purple underglow
	decor({
		Name = "Cornice",
		Size = Vector3.new(W * 2 + 1.5, 1.2, D * 2 + 1.5),
		CFrame = at(0, -A.LobbySize.Y - 0.6, 0),
		Color = PAL.Metal,
		Material = Enum.Material.Metal,
	}, decorF)
	local under = neon(
		"CorniceGlow",
		at(0, -A.LobbySize.Y - 1.3, 0),
		Vector3.new(W * 2 + 1.2, 0.2, D * 2 + 1.2),
		PAL.Trim,
		decorF
	)
	under.Transparency = 0.2
	-- lit windows on all four faces, one band of dark glass per storey
	-- each face: its length, and where a point `u` along it sits `out` studs off the tower wall
	local faces: { { len: number, pos: (number, number, number) -> CFrame, size: (number, number) -> Vector3 } } = {
		{
			len = W * 2 - 2,
			pos = function(u, y, out)
				return at(u, y, D - 1 + out)
			end,
			size = function(w, h)
				return Vector3.new(w, h, 0.2)
			end,
		},
		{
			len = W * 2 - 2,
			pos = function(u, y, out)
				return at(u, y, -D + 1 - out)
			end,
			size = function(w, h)
				return Vector3.new(w, h, 0.2)
			end,
		},
		{
			len = D * 2 - 2,
			pos = function(u, y, out)
				return at(W - 1 + out, y, u)
			end,
			size = function(w, h)
				return Vector3.new(0.2, h, w)
			end,
		},
		{
			len = D * 2 - 2,
			pos = function(u, y, out)
				return at(-W + 1 - out, y, u)
			end,
			size = function(w, h)
				return Vector3.new(0.2, h, w)
			end,
		},
	}
	local storeys = math.floor((depth - 12) / L.FloorHeight)
	local accents = { PAL.Window, PAL.Window, PAL.Window, PAL.Cyan, PAL.Pink }
	for _, face in faces do
		local cols = math.floor(face.len / 6)
		for s = 1, storeys do
			local y = -A.LobbySize.Y - 4 - s * L.FloorHeight
			decor({
				Name = "WindowBand",
				Size = face.size(face.len - 2, 5),
				CFrame = face.pos(0, y, 0.1),
				Color = Color3.fromRGB(20, 18, 34),
				Material = Enum.Material.Glass,
				Transparency = 0.1,
			}, decorF)
			for col = 0, cols - 1 do
				if rng:NextNumber() < L.LitWindowChance then
					local u = -face.len / 2 + 3 + col * 6
					local lit = decor({
						Name = "LitWindow",
						Size = face.size(3.6, 4.2),
						CFrame = face.pos(u, y, 0.25),
						Color = accents[rng:NextInteger(1, #accents)],
						Material = Enum.Material.Neon,
						Transparency = rng:NextNumber(0.15, 0.45),
					}, decorF)
					lit.CastShadow = false
				end
			end
		end
	end
end

-- Props -------------------------------------------------------------------------------------------

local function waterTower(x: number, f: number, collidable: Folder, decorF: Folder)
	local legH = 9
	for _, o in { { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } } do
		solid({
			Name = "TowerLeg",
			Size = Vector3.new(0.6, legH, 0.6),
			CFrame = at(x + o[1], legH / 2, f + o[2]),
			Color = PAL.Metal,
			Material = Enum.Material.Metal,
		}, collidable)
	end
	decor({
		Name = "TowerBrace",
		Size = Vector3.new(7, 0.4, 7),
		CFrame = at(x, legH * 0.55, f),
		Color = PAL.Metal,
		Material = Enum.Material.Metal,
		Transparency = 0.2,
	}, decorF)
	column(
		{ Name = "Tank", Color = PAL.Wood, Material = Enum.Material.WoodPlanks },
		x,
		legH + 4,
		f,
		8,
		9,
		collidable,
		true
	)
	for _, y in { legH + 1.5, legH + 6.5 } do
		column(
			{ Name = "TankBand", Color = PAL.Metal, Material = Enum.Material.Metal },
			x,
			y,
			f,
			0.5,
			9.3,
			decorF,
			false
		)
	end
	column(
		{ Name = "TankRoof", Color = PAL.Wall, Material = Enum.Material.Metal },
		x,
		legH + 8.6,
		f,
		1.2,
		9.8,
		decorF,
		false
	)
	column(
		{ Name = "TankRoofTop", Color = PAL.Wall, Material = Enum.Material.Metal },
		x,
		legH + 9.6,
		f,
		1,
		5,
		decorF,
		false
	)
	local ring = column(
		{ Name = "TankGlow", Color = PAL.Pink, Material = Enum.Material.Neon },
		x,
		legH + 8,
		f,
		0.2,
		9.4,
		decorF,
		false
	)
	ring.CastShadow = false
end

-- Stairwell shed (the "way down") with an antenna mast and a blinking red beacon on its roof.
local function accessShed(x: number, f: number, collidable: Folder, decorF: Folder)
	local h = 8
	solid({
		Name = "Shed",
		Size = Vector3.new(10, h, 8),
		CFrame = at(x, h / 2, f),
		Color = PAL.Wall:Lerp(PAL.Metal, 0.25),
		Material = Enum.Material.Concrete,
	}, collidable)
	decor({
		Name = "ShedDoor",
		Size = Vector3.new(3.4, 6, 0.2),
		CFrame = at(x - 2, 3, f + 4.05),
		Color = Color3.fromRGB(80, 80, 96),
		Material = Enum.Material.DiamondPlate,
	}, decorF)
	local exit =
		neon("ExitSign", at(x - 2, 6.8, f + 4.12), Vector3.new(2.4, 0.9, 0.1), Color3.fromRGB(80, 255, 120), decorF)
	LobbyBuilder.paint(exit, Enum.NormalId.Back, "EXIT", Color3.fromRGB(20, 60, 30))
	local mastH = 22
	column(
		{ Name = "Mast", Color = PAL.Metal, Material = Enum.Material.Metal },
		x + 2.5,
		h + mastH / 2,
		f - 1,
		mastH,
		0.5,
		decorF,
		false
	)
	for i = 1, 3 do
		decor({
			Name = "MastBar",
			Size = Vector3.new(4 - i, 0.2, 0.2),
			CFrame = at(x + 2.5, h + i * 5, f - 1),
			Color = PAL.Metal,
			Material = Enum.Material.Metal,
		}, decorF)
	end
	local beacon = decor({
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.2,
		CFrame = at(x + 2.5, h + mastH + 0.4, f - 1),
		Color = Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.Neon,
	}, decorF)
	beacon:AddTag("HubBeacon")
	make("PointLight", { Color = Color3.fromRGB(255, 40, 40), Range = 14, Brightness = 2 }, beacon)
end

local function acUnit(x: number, f: number, collidable: Folder, decorF: Folder)
	solid({
		Name = "ACUnit",
		Size = Vector3.new(5, 3.2, 4),
		CFrame = at(x, 1.6, f),
		Color = Color3.fromRGB(150, 152, 165),
		Material = Enum.Material.Metal,
	}, collidable)
	local fan = column(
		{ Name = "ACFan", Color = Color3.fromRGB(40, 40, 50), Material = Enum.Material.Metal },
		x,
		3.25,
		f,
		0.15,
		3,
		decorF,
		false
	)
	fan:AddTag("HubFan")
	decor({
		Name = "ACGrille",
		Size = Vector3.new(4.2, 2.2, 0.1),
		CFrame = at(x, 1.5, f + 2.05),
		Color = Color3.fromRGB(70, 72, 84),
		Material = Enum.Material.DiamondPlate,
	}, decorF)
end

local function planter(x: number, f: number, collidable: Folder, decorF: Folder, rng: Random)
	solid({
		Name = "Planter",
		Size = Vector3.new(4, 1.8, 4),
		CFrame = at(x, 0.9, f),
		Color = PAL.Wall:Lerp(PAL.Wood, 0.4),
		Material = Enum.Material.Wood,
	}, collidable)
	for i = 1, 3 do
		decor({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(2.2, 3.2),
			CFrame = at(x + rng:NextNumber(-0.8, 0.8), 2.2 + i * 0.25, f + rng:NextNumber(-0.8, 0.8)),
			Color = PAL.Plant:Lerp(Color3.fromRGB(40, 120, 90), rng:NextNumber()),
			Material = Enum.Material.Grass,
		}, decorF)
	end
end

local function bench(x: number, f: number, yaw: number, collidable: Folder, decorF: Folder)
	local base = at(x, 0, f) * CFrame.Angles(0, math.rad(yaw), 0)
	make("Part", {
		Name = "BenchSeat",
		Size = Vector3.new(6, 0.4, 1.8),
		CFrame = base * CFrame.new(0, 1.4, 0),
		Color = PAL.Wood,
		Material = Enum.Material.WoodPlanks,
	}, collidable)
	make("Part", {
		Name = "BenchBack",
		Size = Vector3.new(6, 1.4, 0.3),
		CFrame = base * CFrame.new(0, 2.4, 0.85) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = PAL.Wood,
		Material = Enum.Material.WoodPlanks,
	}, decorF).CanCollide =
		false
	for _, sx in { -2.6, 2.6 } do
		make("Part", {
			Name = "BenchLeg",
			Size = Vector3.new(0.3, 1.2, 1.6),
			CFrame = base * CFrame.new(sx, 0.6, 0),
			Color = PAL.Metal,
			Material = Enum.Material.Metal,
		}, decorF).CanCollide =
			false
	end
end

local function darken(c: Color3): Color3
	return c:Lerp(Color3.fromRGB(16, 12, 34), 0.6)
end

-- A glowing vending machine facing `yaw` (0 = facing the court).
local function vending(
	x: number,
	f: number,
	yaw: number,
	color: Color3,
	label: string,
	collidable: Folder,
	decorF: Folder
)
	local base = at(x, 0, f) * CFrame.Angles(0, math.rad(yaw), 0)
	make("Part", {
		Name = "Vending",
		Size = Vector3.new(4, 7, 3),
		CFrame = base * CFrame.new(0, 3.5, 0),
		Color = darken(color),
		Material = Enum.Material.SmoothPlastic,
	}, collidable)
	local front = decor({
		Name = "VendingFront",
		Size = Vector3.new(3.2, 4.4, 0.1),
		CFrame = base * CFrame.new(-0.2, 4.1, -1.55),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	}, decorF)
	make("SurfaceLight", { Face = Enum.NormalId.Front, Color = color, Range = 9, Brightness = 1.5, Angle = 100 }, front)
	LobbyBuilder.paint(front, Enum.NormalId.Front, label, Color3.new(1, 1, 1), { Rotation = 0 })
end

local function lampPost(x: number, f: number, color: Color3, decorF: Folder, collidable: Folder): Vector3
	local h = 9
	column(
		{ Name = "LampPole", Color = PAL.Metal, Material = Enum.Material.Metal },
		x,
		h / 2,
		f,
		h,
		0.45,
		collidable,
		true
	)
	local head = decor({
		Name = "LampHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.3,
		CFrame = at(x, h + 0.4, f),
		Color = color,
		Material = Enum.Material.Neon,
	}, decorF)
	-- no shadows: a shadow-casting point light per lamp post is one of the most expensive things
	-- a GPU can be asked to draw, and the deck's neon already sets the mood
	make("PointLight", { Color = color, Range = 22, Brightness = 1.4, Shadows = false }, head)
	return at(x, h, f).Position
end

-- Sagging strand of party bulbs between two points.
local function stringLights(a: Vector3, b: Vector3, bulbs: number, decorF: Folder)
	local colors = { PAL.Warm, PAL.Pink, PAL.Cyan, PAL.Warm }
	local sag = (b - a).Magnitude * 0.08
	local function point(t: number): Vector3
		return a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
	end
	local prev = point(0)
	for i = 1, bulbs do
		local t = i / (bulbs + 1)
		local p = point(t)
		local mid = (prev + p) / 2
		decor({
			Name = "Wire",
			Size = Vector3.new(0.06, 0.06, (p - prev).Magnitude),
			CFrame = CFrame.lookAt(mid, p),
			Color = Color3.fromRGB(30, 30, 30),
		}, decorF).CastShadow =
			false
		local bulb = decor({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.45,
			CFrame = CFrame.new(p - Vector3.new(0, 0.3, 0)),
			Color = colors[i % #colors + 1],
			Material = Enum.Material.Neon,
		}, decorF)
		bulb.CastShadow = false
		prev = p
	end
	local last = point(1)
	decor({
		Name = "Wire",
		Size = Vector3.new(0.06, 0.06, (last - prev).Magnitude),
		CFrame = CFrame.lookAt((prev + last) / 2, last),
		Color = Color3.fromRGB(30, 30, 30),
	}, decorF).CastShadow =
		false
end

-- Zones: stations, leaderboard, watch zone, helipad and signs -----------------------------------

local PROMPT_TEXT: { [string]: string } = { Shop = "Open shop", Spin = "Spin the wheel", Daily = "Daily reward" }
local INK = Color3.fromRGB(16, 12, 34)
local GOLD = Color3.fromRGB(255, 204, 64)

-- Neon outline around a w x h rectangle centred on `base` (in its local XY plane).
local function outline(base: CFrame, w: number, h: number, color: Color3, parent: Instance)
	for _, e in { { 0, h / 2, w, 0.25 }, { 0, -h / 2, w, 0.25 }, { -w / 2, 0, 0.25, h }, { w / 2, 0, 0.25, h } } do
		neon("Outline", base * CFrame.new(e[1], e[2], 0), Vector3.new(e[3], e[4], 0.12), color, parent)
	end
end

-- Glowing stacked text lines on a SurfaceGui (station screens and signs).
local function screenText(part: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3 } })
	local sg = make("SurfaceGui", {
		Name = "Screen",
		Face = face,
		LightInfluence = 0,
		Brightness = 2.5,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
	}, part)
	make("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, sg)
	for i, line in lines do
		local t = make("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.fromScale(0.94, line.size),
			BackgroundTransparency = 1,
			Text = line.text,
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			TextColor3 = line.color,
		}, sg)
		make("UIStroke", { Thickness = 4, Color = INK }, t)
	end
end

-- The physical prize wheel on the spin station's back wall (HubController spins it client-side).
local function prizeWheel(base: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "PrizeWheel"
	local center = base * CFrame.new(0, 6, 3.9)
	local disc = decor({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 7.6, 7.6),
		CFrame = center * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(30, 24, 58),
	}, model)
	model.PrimaryPart = disc
	local rc = Config.Spin.RarityColors
	local cycle = { rc.Common, rc.Rare, rc.Common, rc.Epic, rc.Common, rc.Rare, rc.Common, rc.Legendary }
	for i, col in cycle do
		local angle = math.rad((i - 1) * 360 / #cycle)
		decor({
			Name = "Slice",
			Size = Vector3.new(2.5, 3.3, 0.12),
			CFrame = center * CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.95, -0.25),
			Color = col,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CastShadow = false,
		}, model)
		decor({
			Name = "Spoke",
			Size = Vector3.new(0.18, 3.8, 0.16),
			CFrame = center * CFrame.Angles(0, 0, angle + math.rad(180 / #cycle)) * CFrame.new(0, 1.9, -0.3),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
		}, model)
	end
	decor({
		Name = "Hub",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.2,
		CFrame = center * CFrame.new(0, 0, -0.4),
		Color = GOLD,
		Material = Enum.Material.Neon,
	}, model)
	model:AddTag("HubWheel")
	model.Parent = parent
	-- fixed pointer at 12 o'clock
	decor({
		Name = "WheelPointer",
		Shape = Enum.PartType.Wedge,
		Size = Vector3.new(0.3, 1.2, 1),
		CFrame = base * CFrame.new(0, 10.3, 3.5) * CFrame.Angles(math.rad(180), 0, 0),
		Color = GOLD,
		Material = Enum.Material.Neon,
	}, parent)
end

-- A kiosk built like a little shop booth: platform, back wall with a glowing screen (or the prize
-- wheel), a counter with the prompt, a canopy with a lit title sign and a "stand here" ring.
local function station(def: any, parent: Folder)
	local base = at(def.X, 0, def.F)
	local col: Color3 = def.Color
	local dark = col:Lerp(INK, 0.65)
	local model = Instance.new("Model")
	model.Name = def.Id .. "Station"
	model:SetAttribute("Station", def.Id)
	solid({
		Name = "Platform",
		Size = Vector3.new(12, 0.4, 9),
		CFrame = base * CFrame.new(0, 0.2, 0.5),
		Color = PAL.Metal:Lerp(PAL.Deck, 0.5),
		Material = Enum.Material.DiamondPlate,
	}, model)
	solid({
		Name = "BackWall",
		Size = Vector3.new(12, 10, 0.8),
		CFrame = base * CFrame.new(0, 5, 4.6),
		Color = dark,
	}, model)
	for _, sx in { -6.2, 6.2 } do
		solid({
			Name = "Pillar",
			Size = Vector3.new(0.8, 10.6, 0.9),
			CFrame = base * CFrame.new(sx, 5.3, 4.5),
			Color = PAL.Metal,
			Material = Enum.Material.Metal,
		}, model)
	end
	if def.Id == "Spin" then
		prizeWheel(base, model)
	else
		local screen = decor({
			Name = "Screen",
			Size = Vector3.new(8.6, 5.6, 0.1),
			CFrame = base * CFrame.new(0, 6, 4.15),
			Color = Color3.fromRGB(20, 16, 40),
		}, model)
		screenText(screen, Enum.NormalId.Front, {
			{ text = def.Icon, size = 0.6, color = Color3.new(1, 1, 1) },
			{
				text = if def.Id == "Shop" then "SKINS · TRAILS · POSES" else "COME BACK DAILY",
				size = 0.25,
				color = col,
			},
		})
		outline(base * CFrame.new(0, 6, 4.1), 8.8, 5.8, col, model)
	end
	-- counter with a glowing front strip
	solid({
		Name = "Counter",
		Size = Vector3.new(8, 3, 2.4),
		CFrame = base * CFrame.new(0, 1.9, -1.4),
		Color = dark,
	}, model)
	decor({
		Name = "CounterTop",
		Size = Vector3.new(8.4, 0.3, 2.8),
		CFrame = base * CFrame.new(0, 3.5, -1.4),
		Color = PAL.Metal,
		Material = Enum.Material.Metal,
	}, model)
	neon("CounterGlow", base * CFrame.new(0, 2.8, -2.65), Vector3.new(7.6, 0.25, 0.1), col, model)
	-- canopy, downlight and title sign
	decor({
		Name = "Canopy",
		Size = Vector3.new(13.4, 0.5, 6.5),
		CFrame = base * CFrame.new(0, 10.4, 1.6) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = col,
	}, model)
	neon("CanopyGlow", base * CFrame.new(0, 9.9, -1.65), Vector3.new(13.4, 0.3, 0.2), col, model)
	local spot = decor({
		Name = "Downlight",
		Size = Vector3.one * 0.4,
		CFrame = base * CFrame.new(0, 9.6, -1) * CFrame.Angles(math.rad(-90), 0, 0),
		Transparency = 1,
	}, model)
	make("SpotLight", { Face = Enum.NormalId.Front, Color = col, Range = 16, Angle = 70, Brightness = 2.2 }, spot)
	local sign = decor({
		Name = "TitleSign",
		Size = Vector3.new(12, 2.6, 0.6),
		CFrame = base * CFrame.new(0, 12.2, -0.2),
		Color = INK,
	}, model)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		screenText(sign, face, { { text = def.Title, size = 0.85, color = col:Lerp(Color3.new(1, 1, 1), 0.35) } })
	end
	outline(base * CFrame.new(0, 12.2, -0.55), 12.1, 2.7, col, model)
	-- "stand here" ring in front of the counter
	local rings: { { any } } = {
		{ "StandRing", 7.4, 0.04, col, Enum.Material.Neon },
		{ "StandPad", 6.6, 0.05, Color3.fromRGB(28, 24, 44), Enum.Material.SmoothPlastic },
	}
	for _, ring in rings do
		decor({
			Name = ring[1],
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, ring[2], ring[2]),
			CFrame = base * CFrame.new(0, ring[3], -6) * CFrame.Angles(0, 0, math.rad(90)),
			Color = ring[4],
			Material = ring[5],
			CastShadow = false,
		}, model)
	end
	local anchor = decor({
		Name = "PromptAnchor",
		Size = Vector3.one * 0.5,
		CFrame = base * CFrame.new(0, 3.6, -2.4),
		Transparency = 1,
	}, model)
	make("ProximityPrompt", {
		Name = def.Id .. "Prompt",
		ActionText = PROMPT_TEXT[def.Id] or "Open",
		ObjectText = def.Title,
		HoldDuration = 0,
		Style = Enum.ProximityPromptStyle.Custom, -- drawn by PromptController in the Toybox style
		MaxActivationDistance = L.StationPromptDistance,
		RequiresLineOfSight = false,
	}, anchor)
	model.Parent = parent
end

-- Server leaderboard. LobbyService.refreshLeaderboard fills the rows in.
local function leaderboard(parent: Folder, collidable: Folder)
	local cfg = L.Leaderboard
	local base = at(cfg.X, 0, cfg.F) * CFrame.Angles(0, math.rad(90), 0) -- faces back into the deck
	for _, sx in { -9, 9 } do
		solid({
			Name = "BoardLeg",
			Size = Vector3.new(0.8, 4.2, 0.8),
			CFrame = base * CFrame.new(sx, 2.1, 0.6),
			Color = PAL.Metal,
			Material = Enum.Material.Metal,
		}, collidable)
	end
	local board = solid({
		Name = "Leaderboard",
		Size = Vector3.new(22, 13, 0.8),
		CFrame = base * CFrame.new(0, 10.5, 0.6),
		Color = INK,
	}, parent)
	outline(base * CFrame.new(0, 10.5, 0.15), 22.2, 13.2, GOLD, parent)
	local sg = make("SurfaceGui", {
		Name = "Board",
		Face = Enum.NormalId.Front,
		LightInfluence = 0,
		Brightness = 2,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 36,
	}, board)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 18),
		PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 26),
		PaddingRight = UDim.new(0, 26),
	}, sg)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, sg)
	local title = make("TextLabel", {
		LayoutOrder = 0,
		Size = UDim2.fromScale(1, 0.14),
		BackgroundTransparency = 1,
		Text = "🏆 TOP PLAYERS",
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = GOLD,
	}, sg)
	make("UIStroke", { Thickness = 4, Color = INK }, title)
	make("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0.06),
		BackgroundTransparency = 1,
		Text = "THIS SERVER  ·  NAME  ·  LEVEL  ·  WINS",
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(190, 182, 230),
	}, sg)
	local columns: { { any } } = {
		{ "Rank", 0, 0.1, Enum.TextXAlignment.Center },
		{ "PlayerName", 0.12, 0.54, Enum.TextXAlignment.Left },
		{ "Level", 0.67, 0.15, Enum.TextXAlignment.Center },
		{ "Wins", 0.83, 0.15, Enum.TextXAlignment.Center },
	}
	for i = 1, cfg.Rows do
		local row = make("Frame", {
			Name = "Row" .. i,
			LayoutOrder = 1 + i,
			Size = UDim2.new(1, 0, 0.72 / cfg.Rows, -6),
			BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(44, 36, 82) else Color3.fromRGB(30, 24, 58),
			BackgroundTransparency = 0.1,
			Visible = false,
		}, sg)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
		for _, c in columns do
			make("TextLabel", {
				Name = c[1],
				Position = UDim2.fromScale(c[2], 0.1),
				Size = UDim2.fromScale(c[3], 0.8),
				BackgroundTransparency = 1,
				Text = if c[1] == "Rank" then tostring(i) else "",
				TextScaled = true,
				Font = if c[1] == "PlayerName" then Enum.Font.GothamBold else Enum.Font.FredokaOne,
				TextColor3 = if i == 1
					then GOLD
					elseif c[1] == "Rank" then Color3.fromRGB(190, 182, 230)
					else Color3.new(1, 1, 1),
				TextXAlignment = c[4],
			}, row)
		end
	end
end

-- Low bleachers at the court-side railing: the best seats to watch the match from the hub.
local function watchZone(collidable: Folder, decorF: Folder)
	local cfg = L.WatchZone
	local depth = 3.5
	local front = D - 1.5
	for i = 1, cfg.Rows do
		local h = 0.9 * i
		local f = front - depth / 2 - (i - 1) * depth
		solid({
			Name = "Bleacher",
			Size = Vector3.new(cfg.Width, h, depth),
			CFrame = at(0, h / 2, f),
			Color = PAL.Wall:Lerp(PAL.Metal, 0.2),
			Material = Enum.Material.Concrete,
		}, collidable)
		decor({
			Name = "BleacherSeat",
			Size = Vector3.new(cfg.Width, 0.2, depth - 0.6),
			CFrame = at(0, h + 0.1, f - 0.2),
			Color = PAL.Wood,
			Material = Enum.Material.WoodPlanks,
		}, decorF)
		neon("BleacherGlow", at(0, h - 0.1, f + depth / 2 + 0.02), Vector3.new(cfg.Width, 0.12, 0.08), PAL.Cyan, decorF)
	end
end

-- Flat floor marking: a SurfaceGui on an invisible tile. yaw turns which way the text reads.
local function floorLabel(
	text: string,
	x: number,
	f: number,
	w: number,
	h: number,
	yaw: number,
	color: Color3,
	parent: Instance
)
	local tileP = decor({
		Name = "FloorLabel",
		Size = Vector3.new(w, 0.05, h),
		CFrame = at(x, 0.07, f) * CFrame.Angles(0, math.rad(yaw), 0),
		Transparency = 1,
	}, parent)
	LobbyBuilder.paint(tileP, Enum.NormalId.Top, text, color, { TextTransparency = 0.15 })
end

local function helipad(decorF: Folder)
	local s = L.Spawn
	local discs: { { any } } = {
		{ "PadRing", 21, 0.05, PAL.Trim, Enum.Material.Neon },
		{ "Pad", 19.6, 0.06, Color3.fromRGB(34, 32, 48), Enum.Material.Concrete },
	}
	for _, d in discs do
		decor({
			Name = d[1],
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, d[2], d[2]),
			CFrame = at(s.X, d[3], s.F) * CFrame.Angles(0, 0, math.rad(90)),
			Color = d[4],
			Material = d[5],
			CastShadow = false,
		}, decorF)
	end
	floorLabel("H", s.X, s.F, 9, 9, 0, Color3.fromRGB(255, 230, 140), decorF)
end

-- Signpost by the helipad. Arrows read from the spawn, facing the court.
local function signpost(decorF: Folder, collidable: Folder)
	local x, f = 11, 13
	column({ Name = "SignPole", Color = PAL.Metal, Material = Enum.Material.Metal }, x, 5, f, 10, 0.4, collidable, true)
	local signs: { { any } } = {
		{ "◀  PRACTICE", PAL.Warm },
		{ "LEADERBOARD  ▶", GOLD },
		{ "▲  WATCH THE MATCH", PAL.Cyan },
		{ "BEHIND YOU: SHOP · SPIN · DAILY", PAL.Pink },
	}
	for i, sgn in signs do
		local board = decor({
			Name = "SignBoard",
			Size = Vector3.new(9, 1.3, 0.25),
			-- yaw 180: the readable (front) face points back at the helipad; boards hang on the helipad
			-- side of the pole so the pole never shows through the text
			CFrame = at(x, 9.6 - i * 1.6, f - 0.4) * CFrame.Angles(0, math.rad(180), 0),
			Color = INK,
		}, decorF)
		screenText(board, Enum.NormalId.Front, { { text = sgn[1], size = 0.85, color = sgn[2] } })
	end
end

local function practiceSigns(decorF: Folder, collidable: Folder)
	local p = L.Practice
	-- a banner over the practice wall, readable from the plaza
	for _, f in { -14, 14 } do
		column(
			{ Name = "BannerPole", Color = PAL.Metal, Material = Enum.Material.Metal },
			p.WallX + 2,
			5.5,
			f,
			11,
			0.4,
			collidable,
			true
		)
	end
	local banner = decor({
		Name = "PracticeBanner",
		Size = Vector3.new(28, 3, 0.2),
		CFrame = at(p.WallX + 2, 9.5, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Color = INK,
	}, decorF)
	screenText(banner, Enum.NormalId.Front, { { text = "🎯 LAUNCH THE DUMMY!", size = 0.85, color = PAL.Warm } })
	-- dark rubber mat for the practice lane
	local x0, x1 = -W, p.WallX + 14
	decor({
		Name = "PracticeMat",
		Size = Vector3.new(x1 - x0, 0.05, D * 2 - 6),
		CFrame = at((x0 + x1) / 2, 0.05, 0),
		Color = Color3.fromRGB(36, 34, 44),
		Material = Enum.Material.Fabric,
	}, decorF)
	floorLabel("PRACTICE ZONE", p.WallX + 7, 24, 16, 4, -90, PAL.Warm, decorF)
end

-- Build ------------------------------------------------------------------------------------------

function LobbyBuilder.build(): Folder
	local existing = Workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = lobby
		return f
	end
	local collidable = sub("Collidable")
	local decorF = sub("Decor")
	local barriers = sub("Barriers")
	local stations = sub("Stations")
	local rng = Random.new(L.Seed)

	buildDeck(collidable, decorF)
	buildTower(decorF, rng)
	-- parapets: back and right end full length; the court side gets the glass railing instead, and
	-- the practice end (left) stays open past the practice wall
	parapet(-W, -D, W, -D, collidable, decorF)
	parapet(W, -D, W, D, collidable, decorF)
	parapet(L.Practice.WallX, D - 0.5, -W, D - 0.5, collidable, decorF)
	courtRailing(collidable, decorF)
	edgeBarriers(barriers)

	-- the open practice end: hazard stripes along the drop
	for i = 0, math.floor(D * 2 / 4) - 1 do
		decor({
			Name = "Hazard",
			Size = Vector3.new(1.2, 0.05, 4),
			CFrame = at(-W + 0.6, 0.03, -D + 2 + i * 4),
			Color = if i % 2 == 0 then PAL.Warm else Color3.fromRGB(25, 25, 30),
			Material = Enum.Material.SmoothPlastic,
		}, decorF)
	end

	waterTower(W - 9, -D + 9, collidable, decorF)
	accessShed(W - 24, -D + 5, collidable, decorF)
	acUnit(-W + 18, -D + 4, collidable, decorF)
	acUnit(-W + 24, -D + 4, collidable, decorF)
	for _, p in { { -26, 24 }, { 30, 24 }, { 30, -16 }, { -26, -16 } } do
		planter(p[1], p[2], collidable, decorF, rng)
	end
	bench(W - 6, 14, 90, collidable, decorF)
	bench(W - 6, 26, 90, collidable, decorF)
	vending(W - 3, 4, 90, PAL.Cyan, "FIZZ", collidable, decorF)
	vending(W - 3, 34, 90, PAL.Pink, "BONK\nCOLA", collidable, decorF)

	-- lamp posts at the plaza corners, with party lights strung between them
	local lamps = {
		lampPost(-24, -20, PAL.Warm, decorF, collidable),
		lampPost(24, -20, PAL.Warm, decorF, collidable),
		lampPost(24, 20, PAL.Warm, decorF, collidable),
		lampPost(-24, 20, PAL.Warm, decorF, collidable),
	}
	for i = 1, #lamps do
		stringLights(lamps[i], lamps[i % #lamps + 1], 10, decorF)
	end
	stringLights(lamps[1], lamps[3], 14, decorF)

	-- zones: stations along the back, leaderboard on the right end, bleachers at the railing
	for _, def in L.Stations do
		station(def, stations)
	end
	leaderboard(stations, collidable)
	-- loot chests on their daises around the plaza
	local chests = sub("Chests")
	for i, spot in Config.Chest.Spots do
		ChestBuilder.build(i, at(spot.X, 0, spot.F) * CFrame.Angles(0, math.rad(spot.Yaw), 0), spot.Style, chests)
	end
	watchZone(collidable, decorF)
	helipad(decorF)
	signpost(decorF, collidable)
	practiceSigns(decorF, collidable)
	floorLabel("WATCH ZONE", 0, L.WatchZone.F - L.WatchZone.Rows * 1.75 - 3, 18, 4, 180, PAL.Cyan, decorF)
	floorLabel("LOUNGE", W - 14, 20, 12, 3.5, 90, PAL.Pink, decorF)

	lobby.Parent = Workspace
	return lobby
end

return LobbyBuilder
