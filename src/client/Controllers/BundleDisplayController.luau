--!strict
-- The Haunted Bundle's stand in the hub (client-built, like the shop strip it mirrors): a round
-- plinth where the practice dummy, wearing the Pumpkin Head pose's jack-o-lantern, lurches like
-- Frankenstein's monster, a Jack-o'-Lantern ball turns on a column, a ghost wearing the Ghost tag
-- floats over the sign, and a prompt buys the bundle (CoinShopController.buyOffer).
--
-- It stands while an offer with a Display spot (Config.CoinShop.Offers) is live and Robux buttons
-- are unlocked for you (RobuxOk), the same as the shop's bundle strip. Once you own everything in
-- it the stand stays as decoration but says Owned and its prompt goes away.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local JackOLantern = require(Shared.JackOLantern)
local Net = require(script.Parent.Net)
local CoinShopController = require(script.Parent.CoinShopController)
local HubController = require(script.Parent.HubController)
local ShopController = require(script.Parent.ShopController)

local player = Players.LocalPlayer

local BundleDisplayController = {}

local PLINTH = Color3.fromRGB(44, 26, 64)
local ORANGE = Color3.fromRGB(255, 122, 26)
local GHOST = Color3.fromRGB(236, 255, 250)
local GHOST_TEXT = Color3.fromRGB(214, 255, 244)
local INK = Color3.fromRGB(24, 16, 34)
local TOP = 0.8 -- the plinth's height

type Stand = {
	model: Model,
	offer: any,
	prompt: ProximityPrompt,
	status: TextLabel,
	ball: Model,
	ballAt: CFrame,
	ghost: Model,
	ghostAt: CFrame,
}

local stand: Stand? = nil
local owned: { [string]: boolean } = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function commas(n: number): string
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (s:gsub("^,", ""))
end

local function liveOffer(): any
	local now = Workspace:GetServerTimeNow()
	for _, offer in Config.CoinShop.Offers do
		if offer.Display and Catalog.offerLive(offer, now) then
			return offer
		end
	end
	return nil
end

local function ownsAll(offer: any): boolean
	for _, id in offer.Items do
		if not owned[id] then
			return false
		end
	end
	return true
end

-- A little white ghost (face on its -Z side) with the Ghost tag floating over it.
local function makeGhost(cf: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Ghost"
	local body = part({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = cf,
		Color = GHOST,
		Transparency = 0.18,
	}, model)
	local stretch = Instance.new("SpecialMesh")
	stretch.MeshType = Enum.MeshType.Sphere
	stretch.Scale = Vector3.new(1, 1.2, 1)
	stretch.Parent = body
	model.PrimaryPart = body
	-- a wavy hem and two stubby arms
	for i = -1, 1 do
		part({
			Name = "Hem",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9,
			CFrame = cf * CFrame.new(i * 0.7, -1.25 - (if i == 0 then 0.2 else 0), 0),
			Color = GHOST,
			Transparency = 0.18,
		}, model)
	end
	for _, sx in { -1, 1 } do
		part({
			Name = "Arm",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = cf * CFrame.new(sx * 1.25, -0.1, -0.2),
			Color = GHOST,
			Transparency = 0.18,
		}, model)
	end
	-- hollow eyes and an "oooo" mouth
	for _, sx in { -0.42, 0.42 } do
		part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.36, 0.5, 0.2),
			CFrame = cf * CFrame.new(sx, 0.35, -1.13),
			Color = INK,
		}, model)
	end
	part({
		Name = "Mouth",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.34, 0.42, 0.2),
		CFrame = cf * CFrame.new(0, -0.3, -1.15),
		Color = INK,
	}, model)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(170, 255, 220)
	glow.Range = 10
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = body
	-- the Ghost tag, as it looks on a name tag
	local item = Catalog.get("Title_Ghost")
	local tag = Instance.new("BillboardGui")
	tag.Name = "GhostTag"
	tag.Size = UDim2.fromOffset(160, 34)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	tag.MaxDistance = 90
	tag.LightInfluence = 0
	tag.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.Text = if item then ("%s <i>%s</i> %s"):format(item.Data.Icon, item.Data.Text, item.Data.Icon) else "Ghost"
	label.TextColor3 = GHOST_TEXT
	label.TextTransparency = 0.25
	label.TextStrokeTransparency = 0.6
	label.Parent = tag
	model.Parent = parent
	return model
end

-- A glowing line of text on a face of `p`.
local function screen(p: BasePart, lines: { { text: string, size: number, color: Color3 } }): { TextLabel }
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 2.5
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.Parent = p
	local list = Instance.new("UIListLayout")
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sg
	local labels = {}
	for i, line in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.Size = UDim2.fromScale(0.94, line.size)
		t.BackgroundTransparency = 1
		t.Text = line.text
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = line.color
		t.Parent = sg
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = INK
		stroke.Parent = t
		table.insert(labels, t)
	end
	return labels
end

local function build(offer: any, lobby: Instance): Stand
	local model = Instance.new("Model")
	model.Name = "BundleDisplay_" .. offer.Id
	local spot = ArenaLayout.lobbyPoint(offer.Display.X, 0, offer.Display.F)
	local spawn = ArenaLayout.lobbyPoint(Config.Lobby.Spawn.X, 0, Config.Lobby.Spawn.F)
	-- facing the helipad, where everyone arrives
	local base = CFrame.lookAt(spot, Vector3.new(spawn.X, spot.Y, spawn.Z))

	-- plinth, with a glowing orange rim
	part({
		Name = "Plinth",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(TOP, 9, 9),
		CFrame = base * CFrame.new(0, TOP / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PLINTH,
		Material = Enum.Material.Slate,
		CanCollide = true,
	}, model)
	local rim = part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 9.3, 9.3),
		CFrame = base * CFrame.new(0, TOP - 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ORANGE,
		Material = Enum.Material.Neon,
	}, model)
	local rimLight = Instance.new("PointLight")
	rimLight.Color = ORANGE
	rimLight.Range = 12
	rimLight.Brightness = 1.4
	rimLight.Shadows = false
	rimLight.Parent = rim

	-- the sign at the back, on two posts
	for _, sx in { -3.9, 3.9 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.45, 9.4, 0.45),
			CFrame = base * CFrame.new(sx, TOP + 4.7, 3.4),
			Color = INK,
			Material = Enum.Material.Wood,
			CanCollide = true,
		}, model)
	end
	local board = part({
		Name = "Sign",
		Size = Vector3.new(8.4, 3, 0.4),
		CFrame = base * CFrame.new(0, TOP + 8, 3.4),
		Color = INK,
	}, model)
	local labels = screen(board, {
		{ text = string.upper(offer.Name), size = 0.42, color = ORANGE },
		{ text = ("%d items + %s coins"):format(#offer.Items, commas(offer.Coins)), size = 0.24, color = GHOST_TEXT },
		{ text = "", size = 0.26, color = Color3.fromRGB(255, 214, 90) },
	})
	for _, e in { { 0, 1.5, 8.6, 0.12 }, { 0, -1.5, 8.6, 0.12 }, { -4.25, 0, 0.12, 3.1 }, { 4.25, 0, 0.12, 3.1 } } do
		part({
			Name = "SignGlow",
			Size = Vector3.new(e[3], e[4], 0.1),
			CFrame = board.CFrame * CFrame.new(e[1], e[2], -0.22),
			Color = ORANGE,
			Material = Enum.Material.Neon,
		}, model)
	end

	-- the dummy in the Pumpkin Head pose
	local rig = ShopController.posedDummy("PumpkinHead")
	if rig then
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local cf, size = rig:GetBoundingBox()
		local pivot = rig:GetPivot()
		local feet = pivot:PointToObjectSpace(cf.Position - Vector3.new(0, size.Y / 2, 0)).Y
		rig:PivotTo(base * CFrame.new(-1.7, TOP - feet, 0.5))
		rig.Parent = model
	end

	-- the Jack-o'-Lantern ball turning on a column
	part({
		Name = "Column",
		Size = Vector3.new(1.4, 2.6, 1.4),
		CFrame = base * CFrame.new(2.3, TOP + 1.3, 0.3),
		Color = PLINTH:Lerp(Color3.new(1, 1, 1), 0.08),
		Material = Enum.Material.Slate,
		CanCollide = true,
	}, model)
	part({
		Name = "ColumnCap",
		Size = Vector3.new(1.7, 0.2, 1.7),
		CFrame = base * CFrame.new(2.3, TOP + 2.7, 0.3),
		Color = ORANGE,
		Material = Enum.Material.Neon,
	}, model)
	local ballAt = base * CFrame.new(2.3, TOP + 4.1, 0.3)
	local ball = JackOLantern.build(ballAt, 1.05, "JackOLanternBall")
	JackOLantern.anchor(ball)
	ball.Parent = model

	local ghostAt = base * CFrame.new(3.4, TOP + 11.6, 2.6)
	local ghost = makeGhost(ghostAt, model)

	-- the prompt, at the plinth's front edge
	local anchor = part({
		Name = "PromptAnchor",
		Size = Vector3.one * 0.5,
		CFrame = base * CFrame.new(0, 2.6, -4.4),
		Transparency = 1,
	}, model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BundlePrompt"
	prompt.ObjectText = string.upper(offer.Name)
	prompt.ActionText = if offer.ProductId > 0 then ("Buy · R$ %d"):format(offer.Robux) else "Soon"
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by PromptController
	prompt.MaxActivationDistance = Config.Lobby.StationPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	model.Parent = lobby
	return {
		model = model,
		offer = offer,
		prompt = prompt,
		status = labels[3],
		ball = ball,
		ballAt = ballAt,
		ghost = ghost,
		ghostAt = ghostAt,
	}
end

local function clear()
	if stand then
		stand.model:Destroy()
		stand = nil
	end
end

-- Build, refresh or take down the stand for whatever is live now.
local function render()
	local lobby = Workspace:FindFirstChild("Lobby")
	if HubController.lobbyHidden and stand then
		lobby = stand.model.Parent -- the hub is lifted out while you're on the court: keep the stand
	end
	local offer = liveOffer()
	if not offer or not lobby or not CoinShopController.unlocked() then
		clear()
		return
	end
	if stand and (stand.offer ~= offer or stand.model.Parent ~= lobby) then
		clear() -- another offer, or the hub was rebuilt
	end
	local s = stand or build(offer, lobby)
	stand = s
	local have = ownsAll(offer)
	s.prompt.Enabled = not have
	s.status.Text = if have
		then "OWNED · equip it in the Shop"
		elseif offer.ProductId > 0 then ("R$ %d · LIMITED TIME"):format(offer.Robux)
		else "COMING SOON"
end

function BundleDisplayController.init() end

function BundleDisplayController.start()
	Net.on("Profile", function(d)
		if type(d.owned) == "table" then
			owned = d.owned
			render()
		end
	end)
	player:GetAttributeChangedSignal("RobuxOk"):Connect(render)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if stand and prompt == stand.prompt then
			CoinShopController.buyOffer(stand.offer)
		end
	end)
	-- the ball turns and the ghost bobs (only while you can see them)
	RunService.RenderStepped:Connect(function()
		local s = stand
		if not s or HubController.lobbyHidden then
			return
		end
		local t = os.clock()
		s.ball:PivotTo(s.ballAt * CFrame.new(0, math.sin(t * 2) * 0.15, 0) * CFrame.Angles(0, t * 1.2, 0))
		s.ghost:PivotTo(
			s.ghostAt
				* CFrame.new(math.sin(t * 0.7) * 0.4, math.sin(t * 1.6) * 0.5, 0)
				* CFrame.Angles(0, math.sin(t * 0.9) * 0.35, math.sin(t * 1.3) * 0.12)
		)
	end)
	-- offers open and close on the clock, and the hub can stream in late
	task.spawn(function()
		while true do
			render()
			task.wait(5)
		end
	end)
end

return BundleDisplayController
