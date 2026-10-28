--!strict
-- Idempotent graybox arena builder (spec §6). The hub deck is built separately by LobbyBuilder. Safe to run at server start or from the Studio
-- command bar (see tools/BuildGrayboxArena.luau). Rebuilding replaces Workspace.Arena entirely.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)

local A = Config.Arena
local J = Config.Jail

local ArenaBuilder = {}

local GROUPS = { "Characters", "Ragdoll", "Barrier", "PlayerWall", "Ball", "EdgeWall", "Ejected", "LobbyNet" }

function ArenaBuilder.setupCollisionGroups()
	for _, g in GROUPS do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	local function set(a: string, b: string, v: boolean)
		PhysicsService:CollisionGroupSetCollidable(a, b, v)
	end
	set("Characters", "Characters", false) -- no body-blocking
	set("Characters", "Barrier", true)
	set("Characters", "Ball", false)
	set("Characters", "Ragdoll", false)
	set("Ragdoll", "Ragdoll", false) -- avoid self-collision explosions
	set("Ragdoll", "Barrier", true)
	set("Ragdoll", "Ball", false)
	set("Ball", "Barrier", false) -- balls cross freely
	set("Ball", "Ball", true)
	set("Barrier", "Default", false)
	-- PlayerWall: stops walking characters only (jail and hub walls). Ragdolls fly through, so the
	-- back line stays a real edge instead of an invisible bumper.
	set("PlayerWall", "Characters", true)
	set("PlayerWall", "Ragdoll", false)
	set("PlayerWall", "Ball", false)
	set("PlayerWall", "Default", false)
	-- One-way court edges: EdgeWall only collides with "Ejected" bodies (flung past the edge), so a
	-- launched player can leave the court but can never bounce back onto it.
	for _, g in { "Default", "Characters", "Ragdoll", "Barrier", "PlayerWall", "Ball", "EdgeWall" } do
		set("EdgeWall", g, false)
	end
	set("EdgeWall", "Ejected", true)
	set("Ejected", "Default", true)
	set("Ejected", "Barrier", true)
	set("Ejected", "Characters", false)
	set("Ejected", "Ragdoll", false)
	set("Ejected", "Ejected", false)
	set("Ejected", "Ball", false)
	set("Ejected", "PlayerWall", false)
	-- LobbyNet: the hub's court-side ball net. Only balls hit it, so practice throws never land on
	-- the court, while walkers and flung bodies are unaffected.
	for _, g in GROUPS do
		set("LobbyNet", g, false)
	end
	set("LobbyNet", "Default", false)
	set("LobbyNet", "Ball", true)
end

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function decor(props: { [string]: any }, parent: Instance): Part
	local p = part(props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function label(parent: BasePart, text: string, color: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(6, 3)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.Parent = bb
	bb.Parent = parent
end

-- Bright early-afternoon daylight: a high sun, a clear blue sky and a light, airy haze, with
-- bloom on neon only (high threshold) so the court itself stays readable. The ambient is warm and
-- high, so faces and the far side of the court never sit in shadow.
-- (GraphicsController drops shadows, sun rays and bloom locally on slower machines.)
function ArenaBuilder.setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(150, 150, 158)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 172, 182)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	local function ensure(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing and existing.ClassName == className then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
		return inst
	end
	local atmo = ensure("Atmosphere", "RD_Atmosphere") :: Atmosphere
	atmo.Density = 0.22
	atmo.Offset = 0.15
	atmo.Color = Color3.fromRGB(205, 228, 255)
	atmo.Decay = Color3.fromRGB(120, 165, 225)
	atmo.Glare = 0.15
	atmo.Haze = 0.6
	local bloom = ensure("BloomEffect", "RD_Bloom") :: BloomEffect
	bloom.Intensity = 0.8
	bloom.Size = 24
	bloom.Threshold = 1.15
	local cc = ensure("ColorCorrectionEffect", "RD_Color") :: ColorCorrectionEffect
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.Brightness = 0.04
	cc.TintColor = Color3.fromRGB(255, 252, 245)
	local rays = ensure("SunRaysEffect", "RD_SunRays") :: SunRaysEffect
	rays.Intensity = 0.04
	rays.Spread = 0.6
end

-- Returns the arena folder. Strip parts carry attributes Side ("L"/"R") and StripIndex (1 = outermost).
function ArenaBuilder.build(): Folder
	ArenaBuilder.setupCollisionGroups()
	ArenaBuilder.setupLighting()
	local existing = Workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local collidable = Instance.new("Folder")
	collidable.Name = "Collidable"
	collidable.Parent = arena
	local barriers = Instance.new("Folder")
	barriers.Name = "Barriers"
	barriers.Parent = arena
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = arena

	local o = A.Origin
	local th = A.FloorThickness
	local hl = ArenaLayout.HalfLength
	local hw = ArenaLayout.HalfWidth
	local floorY = o.Y - th / 2
	local redTint = Color3.fromRGB(205, 140, 135)
	local blueTint = Color3.fromRGB(130, 158, 210)

	-- Court floor: a fixed core plus retractable strips on each side, split per team half.
	local stripW = A.OvertimeStripWidth
	local coreHalf = hw - stripW * A.OvertimeStrips
	local function floorSegment(name: string, xMin: number, xMax: number, side: string?, index: number?)
		for _, team in { "Red", "Blue" } do
			local sign = ArenaLayout.teamSign(team)
			local p = part({
				Name = name .. "_" .. team,
				Size = Vector3.new(xMax - xMin, th, hl),
				CFrame = CFrame.new(o.X + (xMin + xMax) / 2, floorY, o.Z + sign * hl / 2),
				Color = if team == "Red" then redTint else blueTint,
				Material = Enum.Material.WoodPlanks,
			}, collidable)
			p:SetAttribute("Team", team)
			if side and index then
				p:SetAttribute("Side", side)
				p:SetAttribute("StripIndex", index)
				p:AddTag("CourtStrip")
			end
		end
	end
	floorSegment("Core", -coreHalf, coreHalf, nil, nil)
	for i = 1, A.OvertimeStrips do
		local outer = hw - stripW * (i - 1)
		local inner = hw - stripW * i
		floorSegment("Strip_R" .. i, inner, outer, "R", i)
		floorSegment("Strip_L" .. i, -outer, -inner, "L", i)
	end

	-- Glowing team rims with light curtains rising from them (decor only: never collide, never
	-- queried). Back rims are split per floor segment so they drop with retracting strips; side rims
	-- exist for every shrink level and only the current outer edge is shown (RimLevel).
	local function rimPiece(
		name: string,
		center: Vector3,
		length: number,
		alongZ: boolean,
		color: Color3,
		height: number,
		brightness: number
	): Part
		local yaw = if alongZ then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
		local rim = decor({
			Name = name,
			Size = Vector3.new(length, 0.35, 0.5),
			CFrame = CFrame.new(center) * yaw,
			Color = color,
			Material = Enum.Material.Neon,
		}, decorFolder)
		rim:SetAttribute("RimColor", color)
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Top
		light.Color = color
		light.Range = 10
		light.Angle = 80
		light.Brightness = 1.6
		light.Parent = rim
		-- rising sparkles
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparks.Lifetime = NumberRange.new(1.2, 2)
		sparks.Speed = NumberRange.new(2.5, 5)
		sparks.Rate = math.max(1, length / 6)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.SpreadAngle = Vector2.new(5, 5)
		sparks.Parent = rim
		-- light curtain: a see-through panel whose glow fades out going up
		local curtain = decor({
			Name = "Curtain",
			Size = Vector3.new(length, height, 0.05),
			CFrame = rim.CFrame * CFrame.new(0, height / 2, 0),
			Transparency = 1,
		}, rim)
		curtain.CastShadow = false
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local sg = Instance.new("SurfaceGui")
			sg.Name = "Glow"
			sg.Face = face
			sg.LightInfluence = 0
			sg.Brightness = brightness
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 6
			sg.Parent = curtain
			local f = Instance.new("Frame")
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = color
			f.BorderSizePixel = 0
			f.Parent = sg
			local g = Instance.new("UIGradient")
			g.Rotation = 90 -- keypoint 0 = top
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.55, 0.8),
				NumberSequenceKeypoint.new(1, 0.1),
			})
			g.Parent = f
		end
		return rim
	end

	local rimY = o.Y - 0.05
	for _, team in { "Red", "Blue" } do
		local sign = ArenaLayout.teamSign(team)
		local col = Config.Teams[team].Color
		-- back rim, one piece per floor segment
		local segments = { { -coreHalf, coreHalf, 0 } }
		for i = 1, A.OvertimeStrips do
			local outer = hw - stripW * (i - 1)
			local inner = hw - stripW * i
			table.insert(segments, { inner, outer, i })
			table.insert(segments, { -outer, -inner, i })
		end
		for _, seg in segments do
			local xMin, xMax, idx = seg[1], seg[2], seg[3]
			local rim = rimPiece(
				"BackRim_" .. team,
				Vector3.new(o.X + (xMin + xMax) / 2, rimY, o.Z + sign * (hl + 0.25)),
				xMax - xMin,
				false,
				col,
				7,
				2.6
			)
			rim:SetAttribute("Team", team)
			rim:AddTag("CourtRim")
			if idx > 0 then
				rim:SetAttribute("StripIndex", idx)
			end
		end
		-- side rims for every shrink level (level k = outer edge after k-1 retractions)
		for level = 1, A.OvertimeStrips + 1 do
			local edge = hw - stripW * (level - 1)
			for _, xs in { -1, 1 } do
				local rim = rimPiece(
					"SideRim_" .. team,
					Vector3.new(o.X + xs * (edge + 0.25), rimY, o.Z + sign * hl / 2),
					hl,
					true,
					col,
					7,
					2.6
				)
				rim:SetAttribute("Team", team)
				rim:SetAttribute("RimLevel", level)
				rim:AddTag("CourtRim")
				if level > 1 then
					-- inner edges only light up as the court shrinks
					rim.Transparency = 1
					for _, d in rim:GetDescendants() do
						if d:IsA("SurfaceLight") or d:IsA("ParticleEmitter") or d:IsA("SurfaceGui") then
							(d :: any).Enabled = false
						end
					end
				end
			end
		end
	end
	-- One-way edge walls just outside every outer court edge (see collision groups above).
	-- Side walls exist per shrink level; ArenaService enables only the current outer edge.
	local edgeH = 60
	local function edgeWall(name: string, cf: CFrame, size: Vector3, level: number?)
		local w = part({
			Name = name,
			Size = size,
			CFrame = cf,
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			CollisionGroup = "EdgeWall",
		}, barriers)
		w:AddTag("EdgeWall")
		if level then
			w:SetAttribute("WallLevel", level)
			w.CanCollide = level == 1
		end
	end
	for _, team in { "Red", "Blue" } do
		local sign = ArenaLayout.teamSign(team)
		edgeWall(
			"EdgeWallBack_" .. team,
			CFrame.new(o.X, o.Y + edgeH / 2 - 15, o.Z + sign * (hl + A.EdgeWallOffset)),
			Vector3.new(A.CourtWidth + 40, edgeH, 0.5)
		)
	end
	for level = 1, A.OvertimeStrips + 1 do
		local edge = hw - stripW * (level - 1)
		for _, xs in { -1, 1 } do
			edgeWall(
				"EdgeWallSide",
				CFrame.new(o.X + xs * (edge + A.EdgeWallOffset), o.Y + edgeH / 2 - 15, o.Z),
				Vector3.new(0.5, edgeH, A.CourtLength + 2),
				level
			)
		end
	end

	-- glowing center line
	local center = rimPiece(
		"CenterLine",
		Vector3.new(o.X, o.Y + 0.02, o.Z),
		A.CourtWidth,
		false,
		Color3.fromRGB(255, 255, 255),
		3,
		0.8
	)
	center.Size = Vector3.new(A.CourtWidth, 0.06, 0.9)
	center:AddTag("CourtRim")

	-- Center barrier: blocks characters and ragdolls, not balls or queries.
	part({
		Name = "CenterBarrier",
		Size = Vector3.new(A.CourtWidth + 24, A.BarrierHeight, 0.6),
		CFrame = CFrame.new(o.X, o.Y + A.BarrierHeight / 2, o.Z),
		Transparency = 1,
		Color = Color3.new(1, 1, 1),
		CanQuery = false,
		CanTouch = false,
		CollisionGroup = "Barrier",
	}, barriers)

	-- Jail strips: separate floor behind the enemy back line, walled so nobody can fall out.
	for _, team in { "Red", "Blue" } do
		local c = ArenaLayout.jailCenter(team)
		local enemySign = -ArenaLayout.teamSign(team)
		local col = Config.Teams[team].Color
		local jailFloor = part({
			Name = "JailFloor_" .. team,
			Size = Vector3.new(A.CourtWidth, th, J.StripDepth),
			CFrame = CFrame.new(c.X, floorY, c.Z),
			Color = col:Lerp(Color3.fromRGB(40, 40, 50), 0.55),
			Material = Enum.Material.DiamondPlate,
		}, collidable)
		jailFloor:SetAttribute("JailTeam", team)
		local wallH = 4
		-- far wall and side walls are solid for everything, so balls stay in the jail too
		part({
			Name = "JailWallFar_" .. team,
			Size = Vector3.new(A.CourtWidth + 2, wallH, 1),
			CFrame = CFrame.new(c.X, o.Y + wallH / 2, c.Z + enemySign * (J.StripDepth / 2 + 0.5)),
			Color = col,
			Material = Enum.Material.Glass,
			Transparency = 0.82, -- see-through: the jailed player's camera sits behind it
		}, collidable)
		for _, xs in { -1, 1 } do
			part({
				Name = "JailWallSide_" .. team,
				Size = Vector3.new(1, wallH, J.StripDepth),
				CFrame = CFrame.new(c.X + xs * (hw + 0.5), o.Y + wallH / 2, c.Z),
				Color = col,
				Material = Enum.Material.Glass,
				Transparency = 0.75,
			}, collidable)
		end
		-- neon trim around the jail floor (lower, dimmer curtains than the court)
		local jailRimFar = rimPiece(
			"JailRim_" .. team,
			Vector3.new(c.X, o.Y - 0.05, c.Z + enemySign * (J.StripDepth / 2)),
			A.CourtWidth,
			false,
			col,
			3,
			1.4
		)
		jailRimFar:AddTag("JailRim")
		for _, xs in { -1, 1 } do
			local r = rimPiece(
				"JailRim_" .. team,
				Vector3.new(c.X + xs * hw, o.Y - 0.05, c.Z),
				J.StripDepth,
				true,
				col,
				3,
				1.4
			)
			r:AddTag("JailRim")
		end
		-- near side: blocks walkers and ragdolls both ways (nobody crosses between court and jail),
		-- but balls pass, so prisoners can still throw onto the court
		part({
			Name = "JailBarrier_" .. team,
			Size = Vector3.new(A.CourtWidth + 2, A.BarrierHeight, 0.6),
			CFrame = CFrame.new(c.X, o.Y + A.BarrierHeight / 2, c.Z - enemySign * (J.StripDepth / 2 + 0.3)),
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CollisionGroup = "Barrier",
		}, barriers)
		local sign = decor({
			Name = "JailSign_" .. team,
			Size = Vector3.new(1, 1, 1),
			Transparency = 1,
			CFrame = CFrame.new(c.X, o.Y + 6, c.Z + enemySign * (J.StripDepth / 2)),
		}, decorFolder)
		label(sign, Config.Teams[team].Name .. " JAIL", col)
	end

	-- Mirrored power-up dispensers (point-symmetric so both teams have identical access).
	for _, team in { "Red", "Blue" } do
		local sign = ArenaLayout.teamSign(team)
		local pad = decor({
			Name = "Dispenser_" .. team,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 6, 6),
			CFrame = CFrame.new(o.X + sign * 30, o.Y + 0.2, o.Z + sign * 30) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 215, 60),
			Material = Enum.Material.Neon,
		}, decorFolder)
		pad:SetAttribute("Team", team)
		label(pad, "?", Color3.fromRGB(255, 230, 90))
	end

	-- Open sky far below the court (decorative only, nowhere near the playable surface).
	decor({
		Name = "VoidGlow",
		Size = Vector3.new(800, 1, 800),
		CFrame = CFrame.new(o.X, o.Y - 160, o.Z),
		Color = Color3.fromRGB(120, 190, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	}, decorFolder)

	arena.Parent = Workspace
	return arena
end

return ArenaBuilder
