--!strict
-- Hub UI: the action row of destinations (Shop, Spin, Daily, Settings), the shop and the daily
-- reward ladder. Shown only in the hub, never during a match. While the shop is open the player stays in
-- the hub (auto-queue is paused and restored on close) so the short intermission never yanks them out
-- mid-purchase.
--
-- Layout follows the Toybox Island design system: the shop is a sheet with segmented category tabs
-- over a grid of item cards (name, tier color and sticker, preview, and an action on every card). The daily reward
-- is louder on purpose: a sheet with a sky header band, a row of toy day cards (today's grows, glows
-- and spins a sunburst behind its reward icon: coins, a prize wheel, the 2x disc or a gift) and one
-- shining primary button. A reward that lets you pick a cosmetic swaps the day cards for the choices.

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local AimController = require(script.Parent.AimController)
local SoundController = require(script.Parent.SoundController)
local GraphicsController = require(script.Parent.GraphicsController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local FinisherIcons = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("FinisherIcons"))
local PoseKit = require(script.Parent.PoseKit)
local IntroPoses = require(Shared.IntroPoses)
local JackOLantern = require(Shared.JackOLantern)
local BallModels = require(Shared.BallModels)

local player = Players.LocalPlayer
local T = Theme.Toybox
local new = Theme.new

local ShopController = {}
ShopController.onOpenSpin = nil :: (() -> ())? -- set by SpinController: a claimed bonus spin opens its sheet
ShopController.holdBusy = false -- set by QuestController while a quest chest opens: keeps you out of matches

local SHOP_SIZE = Vector2.new(880, 600)
local DAILY_SIZE = Vector2.new(760, 438)
local CARD = Vector2.new(92, 164) -- one day card
local SETTINGS_SIZE = Vector2.new(520, 492)

local gui: ScreenGui
local backdrop: TextButton
local actionRow: Frame
local shop: any -- Theme.Sheet
local daily: any -- Theme.Sheet
local settings: any -- Theme.Sheet
local shelf: ScrollingFrame
local walletLabel: TextLabel
local setTab: (string) -> ()
local tiles: { { item: any, card: any, row: number, col: number } } = {}
local selectedId: string? = nil
local dailyTiles: { any } = {}
local daysRow: Frame
local pickRow: Frame
local pickCards: { GuiObject } = {}
local pickShown = "" -- the choices pickRow was drawn for
local pickRequested = false -- the player took a choice and we're waiting for the server
local dailyDot: Frame
local claimButton: TextButton
local claimShine: Frame
local currentTab = "BallSkin"
-- the "Owned only" switch over the shelf: show just what you own (and the defaults), in every tab
ShopController.ownedOnly = false
local profile: any = { coins = 0, owned = {}, equipped = {}, daily = nil }
local dailyAutoShown = false
local claimPending = false -- the player pressed Claim and we're waiting for the server's answer

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function owns(item: Catalog.Item): boolean
	return item.Default == true or (profile.owned and profile.owned[item.Id] == true)
end

-- The limited-time Robux bundle (Config.CoinShop.Offers) a bundle-only item comes in, while that
-- bundle is on sale and Robux buttons are unlocked. Its items sit on the shelf with a button that
-- buys the whole bundle.
local function liveOffer(item: Catalog.Item): any
	if not item.Bundle or player:GetAttribute("RobuxOk") ~= true then
		return nil
	end
	local now = Workspace:GetServerTimeNow()
	for _, offer in Config.CoinShop.Offers do
		if offer.Id == item.Bundle and Catalog.offerLive(offer, now) then
			return offer
		end
	end
	return nil
end

-- A Robux-exclusive item's price in Robux while Robux buttons are unlocked (nil otherwise). It sits on
-- the shelf with a button that prompts its own developer product.
local function exclusivePrice(item: Catalog.Item): number?
	if player:GetAttribute("RobuxOk") ~= true then
		return nil
	end
	return Catalog.robuxPrice(item)
end

local function buyExclusive(item: Catalog.Item)
	if item.RobuxProductId <= 0 then
		SoundController.play("UIError")
		HUDController.hint("This item isn't on sale yet", 1.6)
		return
	end
	MarketplaceService:PromptProductPurchase(player, item.RobuxProductId)
end

-- NEW! tags on the category tabs: a tab is new while it has something on sale this player has never
-- seen (and doesn't own). Opening the tab marks it seen; the server saves that (ShopSeen), so the tag
-- only comes back when an item is added to that category (or an event brings its items back).
local tabTags: { [string]: GuiObject } = {}
local seenHere: { [string]: boolean } = {} -- marked this session, before the server's next Profile
local function isNew(item: Catalog.Item, events: { [string]: boolean }): boolean
	if owns(item) or seenHere[item.Id] or (profile.seen and profile.seen[item.Id]) then
		return false
	end
	return Catalog.isOffered(item, events)
end

local function refreshTabTags()
	local events = Catalog.activeEvents()
	for cat, tag in tabTags do
		local any = false
		for _, item in Catalog.inCategory(cat) do
			if isNew(item, events) then
				any = true
				break
			end
		end
		tag.Visible = any
	end
end

local function markSeen(cat: string)
	local events = Catalog.activeEvents()
	local changed = false
	for _, item in Catalog.inCategory(cat) do
		if isNew(item, events) then
			seenHere[item.Id] = true
			changed = true
		end
	end
	if changed then
		Net.request(Net.Actions.MarkSeen, { category = cat })
		refreshTabTags()
	end
end

-- A little red NEW! sticker sitting on the top edge of a tab.
local function newTag(tab: GuiObject): Frame
	local tag = Theme.new("Frame", {
		Name = "NewTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -1),
		Size = UDim2.fromOffset(48, 20),
		Rotation = -6,
		BackgroundColor3 = Theme.Colors.JoyRed,
		Visible = false,
		ZIndex = tab.ZIndex + 6,
	}, tab)
	Theme.round(tag)
	Theme.stroke(tag, Theme.Colors.Outline, 2)
	Theme.text(tag, 12, {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.DisplayFace,
		Text = "NEW!",
		TextColor3 = Theme.Colors.Paper,
		ZIndex = tag.ZIndex + 1,
	})
	return tag
end

local function isEquipped(item: Catalog.Item): boolean
	return Catalog.equipped(profile.equipped, item.Category).Id == item.Id
end

-- "1,280"
local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
ShopController.commas = commas

-- Tile tone: the rarity's fill; free defaults sit on a quiet sunk tile.
local function toneOf(item: Catalog.Item): Color3
	if item.Price <= 0 then
		return T.line
	end
	return Theme.Rarity[Catalog.rarity(item)]
end

-- The art inside a tile: a ball, a trail stripe, the title text, a finisher's drawn icon
-- (FinisherIcons), or the item's icon.
-- Pose portraits: the practice dummy standing in a pose, drawn live in a ViewportFrame (like a
-- screenshot, but nothing to upload). A ViewportFrame doesn't simulate, so the posed rig is built by
-- hand: every body part is placed from the root outward through its joints, with the pose's joint
-- rotations from PoseKit. It shows the pose's signature frame (the one held longest).
local function posedDummy(poseId: string): Model?
	local template = ReplicatedStorage:FindFirstChild(Config.Practice.TemplateName)
	if not template or not template:IsA("Model") then
		return nil
	end
	local wasArchivable = template.Archivable
	template.Archivable = true
	local rig = template:Clone()
	template.Archivable = wasArchivable
	for _, d in rig:GetDescendants() do
		local hitbox = d:IsA("BasePart") and (d.Name == "HitBox" or d.Name == "HitProxy")
		if hitbox or d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	local pose = IntroPoses.get(poseId)
	local frame, longest = pose.Frames[#pose.Frames].frame, -1
	for _, step in pose.Frames do
		if step.hold >= longest then
			frame, longest = step.frame, step.hold
		end
	end
	local transforms = PoseKit.solve(rig, frame)
	-- the joint graph: part0 -> part1 through f0 * Transform * f1:Inverse()
	type Link = { p0: BasePart, p1: BasePart, f0: CFrame, f1: CFrame, t: CFrame }
	local links: { Link } = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			local a0, a1 = d.Attachment0 :: Attachment, d.Attachment1 :: Attachment
			local p0, p1 = a0.Parent, a1.Parent
			if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				table.insert(
					links,
					{ p0 = p0, p1 = p1, f0 = a0.CFrame, f1 = a1.CFrame, t = transforms[d] or CFrame.identity }
				)
			end
		elseif d:IsA("JointInstance") and d.Part0 and d.Part1 then
			table.insert(
				links,
				{ p0 = d.Part0, p1 = d.Part1, f0 = d.C0, f1 = d.C1, t = transforms[d] or CFrame.identity }
			)
		elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 then
			local rel = d.Part0.CFrame:ToObjectSpace(d.Part1.CFrame)
			table.insert(links, { p0 = d.Part0, p1 = d.Part1, f0 = rel, f1 = CFrame.identity, t = CFrame.identity })
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		rig:Destroy()
		return nil
	end
	local placed: { [BasePart]: CFrame } = { [root] = CFrame.identity }
	local grew = true
	while grew do
		grew = false
		for _, l in links do
			if placed[l.p0] and not placed[l.p1] then
				placed[l.p1] = placed[l.p0] * l.f0 * l.t * l.f1:Inverse()
				grew = true
			elseif placed[l.p1] and not placed[l.p0] then
				placed[l.p0] = placed[l.p1] * l.f1 * l.t:Inverse() * l.f0:Inverse()
				grew = true
			end
		end
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if placed[d] then
				d.CFrame = placed[d]
			end
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			end
		elseif d:IsA("Constraint") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy() -- nothing to solve in a viewport; the parts are placed
		end
	end
	local h = rig:FindFirstChildOfClass("Humanoid")
	if h then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if pose.Prop == "PumpkinHead" then
		JackOLantern.onHead(rig, true)
	end
	return rig
end
-- the posed dummy, for the Haunted Bundle's stand in the hub (BundleDisplayController)
ShopController.posedDummy = posedDummy

local function posePortrait(art: Frame, poseId: string, z: number): boolean
	local rig = posedDummy(poseId)
	if not rig then
		return false
	end
	local vp = Theme.new("ViewportFrame", {
		Name = "Portrait",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(180, 176, 190),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
		ZIndex = z,
	}, art)
	rig.Parent = vp
	local cf, size = rig:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	-- in front of the dummy (it faces -Z), a little to its right and above, so the pose reads in 3D
	local dist = (size.Y / 2 + 0.4) / math.tan(math.rad(cam.FieldOfView / 2))
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0.3, 0.12, -1).Unit * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return true
end

-- A model skin (Catalog Data.Model) in a ViewportFrame: built by BallModels exactly as balls wear
-- it, seen from the front and a little above so its face (-Z) and top both read.
local function modelPortrait(art: Frame, name: string, z: number): boolean
	local model = BallModels.build(name, CFrame.identity, 1)
	if not model then
		return false
	end
	BallModels.anchor(model)
	local vp = Theme.new("ViewportFrame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.4, -1, 0.5),
		ZIndex = z,
	}, art)
	model.Parent = vp
	local _, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	-- the model fills about 55% of the art band's height, like the drawn balls
	local dist = (size.Magnitude / 2 / 0.55 * 0.6) / math.tan(math.rad(cam.FieldOfView / 2))
	cam.CFrame = CFrame.lookAt(Vector3.new(0.35, 0.45, -1).Unit * dist, Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return true
end

local GHOST_TEXT = Color3.fromRGB(214, 255, 244)
local STRIPE = Color3.fromRGB(25, 25, 28) -- the Zebra skin's bands (BallSkinController)

local function drawArt(item: Catalog.Item, art: Frame)
	local d = item.Data
	local z = art.ZIndex + 1
	if item.Category == "BallSkin" and type(d.Model) == "string" and modelPortrait(art, d.Model, z) then
		return -- a model skin: the real model, the same one the ball wears
	end
	if item.Category == "BallSkin" then
		local col = d.Color or Color3.fromRGB(214, 48, 49)
		local ball = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.52, 0.52),
			BackgroundColor3 = col,
			ZIndex = z,
		}, art)
		new("UIAspectRatioConstraint", nil, ball)
		Theme.round(ball)
		Theme.stroke(ball, T.outline, Theme.StrokeToy)
		-- patterns and metal sheen as a gradient over a white ball (it tints the fill, clipped to the round)
		local gradient: ColorSequence? = nil
		local rotation = 0
		if d.Pattern == "Zebra" then
			-- hard-edged black bands: two keypoints at each edge
			local keys = {}
			local edges = { 0.14, 0.24, 0.38, 0.5, 0.63, 0.73, 0.85, 0.92 }
			table.insert(keys, ColorSequenceKeypoint.new(0, col))
			for i, x in edges do
				local before = if i % 2 == 1 then col else STRIPE
				local after = if i % 2 == 1 then STRIPE else col
				table.insert(keys, ColorSequenceKeypoint.new(x - 0.001, before))
				table.insert(keys, ColorSequenceKeypoint.new(x, after))
			end
			table.insert(keys, ColorSequenceKeypoint.new(1, col))
			gradient = ColorSequence.new(keys)
			rotation = -35
		elseif d.Pattern == "Rainbow" then
			local keys = {}
			for i = 0, 6 do
				table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 7, 0.75, 1)))
			end
			gradient = ColorSequence.new(keys)
			rotation = 45
		elseif type(d.Reflectance) == "number" and d.Reflectance > 0 then
			-- metal: a bright glint up top fading through the color to a darker rim
			gradient = ColorSequence.new({
				ColorSequenceKeypoint.new(0, col:Lerp(Color3.new(1, 1, 1), 0.7)),
				ColorSequenceKeypoint.new(0.3, col),
				ColorSequenceKeypoint.new(0.55, col:Lerp(Color3.new(1, 1, 1), 0.25)),
				ColorSequenceKeypoint.new(1, col:Lerp(Color3.new(0, 0, 0), 0.4)),
			})
			rotation = 60
		end
		if gradient then
			ball.BackgroundColor3 = Color3.new(1, 1, 1)
			new("UIGradient", { Color = gradient, Rotation = rotation }, ball)
		end
		-- a single soft highlight
		local shine = new("Frame", {
			Position = UDim2.fromScale(0.2, 0.16),
			Size = UDim2.fromScale(0.3, 0.2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.45,
			ZIndex = z + 1,
		}, ball)
		Theme.round(shine)
	elseif item.Category == "Trail" then
		local colors: { Color3 }? = d.Colors
		if colors and #colors > 0 then
			local keys = {}
			for i, c in colors do
				table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), c))
			end
			if #keys == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
			end
			local bar = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.74, 0.16),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Rotation = -18,
				ZIndex = z,
			}, art)
			Theme.round(bar)
			Theme.stroke(bar, T.outline, 2.5)
			new("UIGradient", { Color = ColorSequence.new(keys) }, bar)
			if typeof(d.Width) == "number" and d.Width > 1 then
				bar.Size = UDim2.fromScale(0.8, 0.16 * math.min(d.Width, 1.6)) -- a wider trail draws wider
			end
			-- an exclusive trail's sparkles: a few glinting dots scattered along the bar
			local sparkle: { Color3 }? = d.Sparkle
			if sparkle and #sparkle > 0 then
				for i, at in
					{ Vector2.new(0.22, 0.3), Vector2.new(0.48, 0.72), Vector2.new(0.72, 0.28), Vector2.new(0.86, 0.62) }
				do
					local dot = new("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(at.X, at.Y),
						Size = UDim2.fromScale(0.07, 0.07),
						Rotation = 45,
						BackgroundColor3 = sparkle[(i - 1) % #sparkle + 1],
						ZIndex = z + 1,
					}, art)
					new("UIAspectRatioConstraint", nil, dot)
					Theme.stroke(dot, T.outline, 1.5)
				end
			end
		else
			Theme.body(art, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.7, 0.2),
				FontFace = Theme.LabelFace,
				Text = "None",
				TextColor3 = Theme.textOn(art.BackgroundColor3),
				ZIndex = z,
			})
		end
	elseif item.Category == "Pose" and type(d.Pose) == "string" and posePortrait(art, d.Pose, z) then
		art:SetAttribute("Portrait", true) -- the dummy, posed (the icon below is the fallback)
	elseif item.Category == "Title" and d.Style == "Ghost" then
		-- the Ghost tag looks like it does on your name tag: pale, see-through, framed in ghosts
		Theme.label(art, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.32),
			Text = ("%s %s %s"):format(d.Icon, d.Text, d.Icon),
			TextColor3 = GHOST_TEXT,
			TextTransparency = 0.15,
			ZIndex = z,
		}, 0)
	elseif item.Category == "Title" and type(d.Gradient) == "table" and #d.Gradient > 0 then
		-- a gradient title (the Robux exclusives): white text under a UIGradient of its colors, with a
		-- dark stroke so it reads on any band; animated ones slide the gradient along, as on name tags
		local label = Theme.label(art, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.32),
			Text = d.Text,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeColor3 = T.outline,
			TextStrokeTransparency = 0.2,
			ZIndex = z,
		}, 0)
		local keys = {}
		local cols: { Color3 } = d.Gradient
		for i, c in cols do
			table.insert(keys, ColorSequenceKeypoint.new(if #cols == 1 then 0 else (i - 1) / (#cols - 1), c))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, cols[1]))
		end
		local g = new("UIGradient", { Color = ColorSequence.new(keys) }, label)
		if d.Animated and not HUDController.settings.ReducedMotion then
			g.Offset = Vector2.new(-0.5, 0)
			TweenService:Create(
				g,
				TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Offset = Vector2.new(0.5, 0) }
			):Play()
		end
	elseif item.Category == "Title" then
		Theme.label(art, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.82, 0.3),
			Text = if d.Text and d.Text ~= "" then d.Text else "None",
			TextColor3 = Theme.textOn(art.BackgroundColor3),
			ZIndex = z,
		}, 0)
	elseif item.Category == "Finisher" and FinisherIcons.has(d.Module) then
		FinisherIcons.draw(art, d.Module, z)
	else
		Theme.label(art, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			Text = d.Icon or "★",
			TextColor3 = T.onFill,
			ZIndex = z,
		}, 0)
	end
end
ShopController.drawArt = drawArt

-- Shop: item cards -----------------------------------------------------------------------------------
-- Every item is a card in a grid: art on a band tinted in its tier's fill (with the tier sticker),
-- its name, a preview button where there's something to preview, and its own action button. Hover
-- or gamepad selection picks a card for the keyboard (arrows move, Enter acts).

local ITEM_CARD = Vector2.new(192, 196)
local ART_H = 96
local COLUMNS = 4

local function selectedItem(): Catalog.Item?
	return if selectedId then Catalog.get(selectedId) else nil
end

-- Short on coins. The "+" by the wallet (need = nil) opens the Coins sheet; a Buy you can't afford
-- just says so, and only the AutoOpenAfterFails-th one opens the sheet, once a session. Before
-- Robux unlocks (tutorial plus play time) there's no Coins sheet at all.
local failedBuys = 0
local autoOpened = false
local function getCoins(need: number?)
	local CoinShopController = require(script.Parent.CoinShopController) :: any
	local unlocked = CoinShopController.unlocked()
	if need == nil then
		if unlocked then
			CoinShopController.open(true, nil)
		end
		return
	end
	failedBuys += 1
	if unlocked and not autoOpened and failedBuys >= Config.CoinShop.AutoOpenAfterFails then
		autoOpened = true
		CoinShopController.open(true, need)
		return
	end
	SoundController.play("UIError")
	HUDController.hint(("You need %d more coins"):format(need), 1.6)
end

-- Buy, equip, or (short on coins) the Coins sheet.
local function primaryAction(item: Catalog.Item?)
	item = item or selectedItem()
	if not item or isEquipped(item) then
		return
	end
	if owns(item) then
		Net.request(Net.Actions.EquipItem, { id = item.Id })
	elseif item.Unlock then
		SoundController.play("UIError")
		HUDController.hint("Earn it with power-ball knockouts", 1.6)
	elseif liveOffer(item) then
		local CoinShopController = require(script.Parent.CoinShopController) :: any
		CoinShopController.buyOffer(liveOffer(item))
	elseif item.Exclusive then
		if exclusivePrice(item) then
			buyExclusive(item)
		end
	elseif (profile.coins or 0) >= item.Price then
		Net.request(Net.Actions.BuyItem, { id = item.Id })
	else
		getCoins(item.Price - (profile.coins or 0))
	end
end

-- Close the shop, play the finisher preview on yourself, then reopen the shop where you were.
function ShopController.previewFinisher(item: any)
	local FinisherController = require(script.Parent.FinisherController) :: any
	if FinisherController.playing then
		return
	end
	shop.frame.Visible = false
	backdrop.Visible = false
	task.spawn(function()
		local ok = FinisherController.preview(item.Data.Module)
		if not ok then
			HUDController.hint("Preview works in the hub", 1.5)
		end
		if inHub() then
			ShopController.openShop(true)
		end
	end)
end

local function previewAction(item: Catalog.Item)
	if item.Category == "Pose" then
		local IntroController = require(script.Parent.IntroController) :: any
		IntroController.preview(item.Data.Pose)
		ShopController.openShop(false)
	elseif item.Category == "Finisher" then
		ShopController.previewFinisher(item)
	end
end

-- A card's action for the item's state: Equipped (leaf, inert), Equip (sky), Buy (sun), or Buy on
-- a plain surface while you can't afford it yet (still pressable: it opens the Coins sheet).
local function renderAction(item: Catalog.Item, b: TextButton)
	local coins = profile.coins or 0
	if isEquipped(item) then
		Theme.setText(b, "Equipped")
		Theme.recolor(b, T.leaf)
		Theme.setEnabled(b, true)
		b.Interactable = false
	elseif owns(item) then
		Theme.setText(b, "Equip")
		Theme.recolor(b, T.sky)
		Theme.setEnabled(b, true)
	elseif item.Unlock then
		-- Power Ball Mastery: locked until earned, showing the progress
		local have, need = Catalog.unlockProgress(item, profile.powerKOs)
		local ball = if item.Unlock.Ball == "All" then "each" else item.Unlock.Ball
		Theme.setText(b, ("🔒 %d/%d %s KOs"):format(have, need, ball))
		Theme.recolor(b, "secondary")
		Theme.setEnabled(b, false)
	elseif liveOffer(item) then
		-- bundle-only: the button buys the whole bundle
		Theme.setText(b, ("Bundle · R$ %d"):format(liveOffer(item).Robux))
		Theme.recolor(b, T.candy)
		Theme.setEnabled(b, true)
	elseif item.Exclusive then
		-- Robux-exclusive: the button prompts the item's own product
		Theme.setText(b, ("R$ %d"):format(exclusivePrice(item) or 0))
		Theme.recolor(b, T.candy)
		Theme.setEnabled(b, true)
	elseif coins >= item.Price then
		Theme.setText(b, ("Buy · %s"):format(commas(item.Price)))
		Theme.recolor(b, T.sun)
		Theme.setEnabled(b, true)
	else
		Theme.setText(b, ("Buy · %s"):format(commas(item.Price)))
		Theme.recolor(b, "secondary")
		Theme.setEnabled(b, true)
	end
end

local function scrollIntoView(button: GuiObject)
	local top = button.AbsolutePosition.Y - shelf.AbsolutePosition.Y + shelf.CanvasPosition.Y
	local bottom = top + button.AbsoluteSize.Y
	local view = shelf.AbsoluteSize.Y
	local y = shelf.CanvasPosition.Y
	local margin = 12
	if top - margin < y then
		y = top - margin
	elseif bottom + margin > y + view then
		y = bottom + margin - view
	end
	y = math.max(0, y)
	if math.abs(y - shelf.CanvasPosition.Y) > 0.5 then
		Theme.tween(shelf, Theme.Motion.Fast, { CanvasPosition = Vector2.new(0, y) }, Enum.EasingStyle.Quint)
	end
end

local function selectItem(id: string)
	if selectedId == id then
		return
	end
	selectedId = id
	for _, entry in tiles do
		if entry.item.Id == id then
			scrollIntoView(entry.card.button)
		end
	end
end

local function itemCard(item: Catalog.Item, order: number, parent: Instance): { [string]: any }
	local id = item.Id
	local tone = toneOf(item)
	local b = new("TextButton", {
		Name = id,
		LayoutOrder = order,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, parent)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.surface,
		ZIndex = 5,
	}, b)
	Theme.corner(face, Theme.Radius.M)
	Theme.stroke(face, T.outline, Theme.StrokeToy)
	-- the art band in the tier's fill (rounded on top only: a filler squares its bottom)
	local band = tone
	local art = new("Frame", {
		Name = "Art",
		Size = UDim2.new(1, 0, 0, ART_H),
		BackgroundColor3 = band,
		ZIndex = 6,
	}, face)
	Theme.corner(art, Theme.Radius.M)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.Radius.M),
		Size = UDim2.new(1, 0, 0, Theme.Radius.M),
		BackgroundColor3 = band,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, art)
	new("Frame", {
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = T.outline,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, art)
	local canvas = new("Frame", {
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = band,
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, art)
	drawArt(item, canvas)
	Theme.sticker(face, if item.Price > 0 then Catalog.rarity(item) else "Free", T.paper, {
		Position = UDim2.fromOffset(8, 8),
		ZIndex = 10,
	})
	if item.Exclusive then
		Theme.sticker(face, "Exclusive", T.joyBlue, {
			Position = UDim2.fromOffset(8, 32),
			ZIndex = 10,
		})
	end
	if item.Category == "Finisher" or item.Category == "Pose" then
		local preview = Theme.iconButton(face, "play", "secondary", 34, {
			Name = "Preview",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			ZIndex = 10,
		})
		preview.Activated:Connect(function()
			selectItem(id)
			previewAction(item)
		end)
	end
	local name = Theme.label(face, {
		Name = "Name",
		Position = UDim2.fromOffset(10, ART_H + 8),
		Size = UDim2.new(1, -20, 0, 26),
		Text = item.Name,
		ZIndex = 7,
	}, 0)
	new("UITextSizeConstraint", { MaxTextSize = 22 }, name)
	local action = Theme.button(face, "", "primary", {
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 44),
		ZIndex = 8,
	})
	action.Activated:Connect(function()
		selectItem(id)
		primaryAction(item)
	end)
	renderAction(item, action)
	Theme.selectable(b, face)
	b.MouseEnter:Connect(function()
		selectItem(id)
	end)
	-- a finisher card plays its preview wherever you click it (the buy button sits on top and keeps
	-- its own click)
	if item.Category == "Finisher" then
		b.Activated:Connect(function()
			selectItem(id)
			SoundController.play("UIClick")
			previewAction(item)
		end)
	end
	b.SelectionGained:Connect(function()
		selectItem(id)
	end)
	return { button = b, art = art, action = action }
end

-- The shelf is grouped by tier, cheapest first: Free, then Common, Rare, Epic and Legendary. Each
-- group has a header (the tier's colored tag, a rule and how many of them you own) over its own
-- four-wide grid.
local TIERS = { "Free", "Common", "Rare", "Epic", "Legendary" }
local SECTION_W = COLUMNS * ITEM_CARD.X + (COLUMNS - 1) * Theme.Space.L

local function tierOf(item: Catalog.Item): string
	return if item.Price <= 0 then "Free" else Catalog.rarity(item)
end

local function shelfSection(tier: string, order: number, have: number, total: number): Frame
	local tone = if tier == "Free" then T.line else Theme.Rarity[tier]
	local root = new("Frame", {
		Name = "Section_" .. tier,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SECTION_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, shelf)
	root:SetAttribute("ShelfSection", true)
	new("UIListLayout", { Padding = UDim.new(0, Theme.Space.S), SortOrder = Enum.SortOrder.LayoutOrder }, root)
	local head = new("Frame", {
		Name = "Header",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, root)
	-- the rule runs the full width behind the tag and the count
	new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = tone,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, head)
	local tag = new("Frame", {
		Name = "Tag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = tone,
		ZIndex = 6,
	}, head)
	Theme.round(tag)
	Theme.stroke(tag, T.outline, Theme.StrokeToy)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, tag)
	Theme.text(tag, 20, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = Theme.DisplayFace,
		Text = string.upper(tier),
		TextColor3 = Theme.textOn(tone),
		ZIndex = 7,
	})
	Theme.sticker(head, ("%d/%d owned"):format(have, total), if have == total then T.leaf else T.surface, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 24),
		ZIndex = 6,
	})
	local grid = new("Frame", {
		Name = "Grid",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, root)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(ITEM_CARD.X, ITEM_CARD.Y),
		CellPadding = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		FillDirectionMaxCells = COLUMNS,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	return grid
end

local function renderShelf()
	for _, child in shelf:GetChildren() do
		if child:IsA("GuiButton") or child:GetAttribute("ShelfSection") then
			child:Destroy()
		end
	end
	table.clear(tiles)
	walletLabel.Text = commas(profile.coins or 0)
	local CoinShopController = require(script.Parent.CoinShopController) :: any
	CoinShopController.renderOffers() -- the Haunted Bundle banner at the top of the shelf
	-- event cosmetics show while their event runs (and forever once owned); mastery cosmetics always,
	-- locked until earned; bundle items while their bundle is on sale; Robux exclusives once Robux
	-- buttons are unlocked
	local byTier: { [string]: { Catalog.Item } } = {}
	local events = Catalog.activeEvents()
	for _, item in Catalog.inCategory(currentTab) do
		local shown = Catalog.isOffered(item, events)
			or owns(item)
			or item.Unlock
			or liveOffer(item)
			or exclusivePrice(item)
		if shown and (owns(item) or not ShopController.ownedOnly) then
			local tier = tierOf(item)
			byTier[tier] = byTier[tier] or {}
			table.insert(byTier[tier], item)
		end
	end
	local items = {}
	local keep = selectedId
	selectedId = nil
	local pick: string? = nil
	local row = 0
	for order, tier in TIERS do
		local list = byTier[tier]
		if not list then
			continue
		end
		local have = 0
		for _, item in list do
			have += if owns(item) then 1 else 0
		end
		local grid = shelfSection(tier, order, have, #list)
		for i, item in list do
			table.insert(items, item)
			local col = (i - 1) % COLUMNS + 1
			if col == 1 then
				row += 1
			end
			table.insert(tiles, { item = item, card = itemCard(item, i, grid), row = row, col = col })
			if isEquipped(item) then
				pick = pick or item.Id
			end
		end
	end
	if #items == 0 then
		local empty = Theme.body(shelf, {
			Name = "Empty",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 80),
			Text = "You don't own anything here yet.",
			TextColor3 = T.inkMuted,
			ZIndex = 5,
		})
		empty:SetAttribute("ShelfSection", true) -- cleared with the sections on the next render
	end
	-- keep the selection when re-rendering the same tab; otherwise start on the equipped item
	local still = false
	for _, e in tiles do
		still = still or e.item.Id == keep
	end
	selectItem((if still then keep else pick) or (items[1] and items[1].Id) or "")
	return items
end

-- Move the selection through the grid: left/right by one card (delta), up/down to the nearest card
-- in the row above or below (rows = -1 or 1), across the tier headers.
local function step(delta: number, rows: number?)
	for i, e in tiles do
		if e.item.Id == selectedId then
			local nxt = tiles[math.clamp(i + delta, 1, #tiles)]
			if rows then
				nxt = e
				for _, t in tiles do
					local closer = nxt == e or math.abs(t.col - e.col) < math.abs(nxt.col - e.col)
					if t.row == e.row + rows and closer then
						nxt = t
					end
				end
			end
			if nxt and nxt.item.Id ~= selectedId then
				selectItem(nxt.item.Id)
				Theme.setHome(nxt.card.button)
				SoundController.play("UIMove")
			else
				SoundController.play("UIEdge") -- the end of the grid: a bump, not a tick
			end
			return
		end
	end
end

-- Daily ----------------------------------------------------------------------------------------------

-- How a ladder reward (Config.DailyRewards) reads on its day card and on the Claim button.
local function boostDef(id: string?): any
	for _, b in Config.CoinShop.Boosts do
		if b.Id == id then
			return b
		end
	end
	return nil
end

local function rewardLabel(reward: any): string
	if reward.Kind == "Coins" then
		return "+" .. commas(reward.Amount)
	elseif reward.Kind == "Spin" then
		return if reward.Wheel == "RarePlus" then "Rare+ spin" else "Free spin"
	elseif reward.Kind == "Boost" then
		return ("%dx coins"):format(Config.CoinShop.BoostMultiplier)
	elseif reward.Id then
		local item = Catalog.get(reward.Id)
		return if item then item.Name else "Item"
	end
	return ("%s pick"):format(reward.Rarity or "Item")
end

local function claimLabel(reward: any): string
	if reward.Kind == "Coins" then
		return ("Claim %s coins"):format(commas(reward.Amount))
	elseif reward.Kind == "Spin" then
		return if reward.Wheel == "RarePlus" then "Claim a Rare+ spin" else "Claim a free spin"
	elseif reward.Kind == "Boost" then
		local b = boostDef(reward.Id)
		return ("Claim %dx coins%s"):format(
			Config.CoinShop.BoostMultiplier,
			if b and not b.Forever then (" (%d min)"):format(b.Minutes) else ""
		)
	elseif reward.Id then
		return "Claim " .. rewardLabel(reward)
	end
	return ("Pick an %s item"):format(reward.Rarity or "")
end

-- One choice of a cosmetic pick: the item on its rarity color, its name, and a Take button.
local function pickCard(parent: Instance, order: number, item: Catalog.Item): GuiObject
	local rarity = Catalog.rarity(item)
	local root = new("Frame", {
		Name = item.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(170, CARD.Y + Theme.Ledge),
		BackgroundColor3 = T.surface,
		ZIndex = 5,
	}, parent)
	Theme.corner(root, Theme.Radius.M)
	Theme.stroke(root, T.outline, Theme.StrokeToy)
	local art = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = Theme.Rarity[rarity] or T.candy,
		ZIndex = 6,
	}, root)
	Theme.corner(art, Theme.Radius.M)
	Theme.stroke(art, T.outline, Theme.StrokeToy)
	drawArt(item, art)
	Theme.text(root, 16, {
		Position = UDim2.fromOffset(6, 88),
		Size = UDim2.new(1, -12, 0, 20),
		FontFace = Theme.DisplayFace,
		Text = item.Name,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})
	local take = Theme.button(root, "Take it", "primary", {
		Name = "Take",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(140, 48),
		ZIndex = 7,
	})
	take.Activated:Connect(function()
		if not pickRequested then
			pickRequested = true
			Net.request(Net.Actions.PickReward, { id = item.Id })
		end
	end)
	return root
end

local function drawPicks(ids: { string })
	local key = table.concat(ids, ",")
	if key == pickShown then
		return
	end
	pickShown = key
	for _, f in pickCards do
		f:Destroy()
	end
	table.clear(pickCards)
	for i, id in ids do
		local item = Catalog.get(id)
		if item then
			table.insert(pickCards, pickCard(pickRow, i, item))
		end
	end
end

local function picking(): boolean
	local d = profile.daily
	return d ~= nil and type(d.pick) == "table" and type(d.pick.ids) == "table" and #d.pick.ids > 0
end

local function renderDaily()
	local d = profile.daily
	dailyDot.Visible = d ~= nil and (not d.claimed or picking())
	if not d then
		return
	end
	daysRow.Visible = not picking()
	pickRow.Visible = picking()
	if picking() then
		drawPicks(d.pick.ids)
		daily.subtitle.Text = ("Pick one %s item to keep!"):format(d.pick.rarity or "")
		Theme.setText(claimButton, "Pick one above")
		Theme.recolor(claimButton, "secondary")
		Theme.setEnabled(claimButton, false)
		claimShine.Visible = false
		return
	end
	daily.subtitle.Text = if d.claimed
		then "Collected today. Come back tomorrow for the next one."
		else ("Day %d of %d. Log in every day for bigger rewards."):format(d.day, #Config.DailyRewards.Ladder)
	for i, card in dailyTiles do
		local done = i < d.day or (d.claimed and i == d.day)
		local today = i == d.day and not d.claimed
		local fill = if done then T.leaf elseif today then T.sun elseif card.last then T.candy else T.sky
		card.face.BackgroundColor3 = fill
		card.top.BackgroundColor3 = Theme.darken(fill, 0.22)
		card.topFill.BackgroundColor3 = card.top.BackgroundColor3
		card.stamp.Visible = done
		card.icon.Visible = not done
		card.rays.Visible = today or (card.last and not done)
		card.glow.Visible = today
		card.today = today
		card.status.Text = if done
			then "Claimed"
			elseif today then "Today!"
			elseif i == d.day + 1 then "Tomorrow"
			elseif card.last then "Big prize"
			else "Soon"
		card.status.TextColor3 = if done then T.success else T.ink
		card.scale:SetAttribute("Base", if today then 1.08 else 1) -- pops settle here
		card.scale.Scale = if today then 1.08 else 1
	end
	local reward = Config.DailyRewards.Ladder[d.day]
	Theme.setText(
		claimButton,
		if d.claimed then "Come back tomorrow!" elseif reward then claimLabel(reward) else "Claim"
	)
	Theme.recolor(claimButton, if d.claimed then "secondary" else "primary")
	Theme.setEnabled(claimButton, not d.claimed)
	claimShine.Visible = not d.claimed
end

-- A cosmetic landed (a fixed reward or a pick): say so, or pop the coins a duplicate paid.
local function announceItem(result: any)
	local item = Catalog.get(result.id)
	if result.duplicate then
		HUDController.coinPop(tonumber(result.coins) or 0)
	elseif item then
		HUDController.hint(("%s is yours! Equip it in the Shop"):format(item.Name), 2.4)
	end
end

-- Claimed (`result` is the server's DailyResult): today's card pops and turns leaf with a check
-- stamped on it, then the reward plays out by kind. Coins fly into the counter; a bonus spin opens
-- the Spin sheet on its wheel; a boost is announced by its own BoostBought; a pick keeps the sheet
-- open on the choices.
local function celebrateClaim(result: any)
	local card = dailyTiles[result.day]
	if card then
		Theme.pop(card.root, 1.25, Theme.Motion.Slow)
		Theme.pop(card.stamp, 2.2, Theme.Motion.Slow)
	end
	task.defer(function()
		Theme.pop(claimButton, 0.85, Theme.Motion.Slow)
	end)
	SoundController.play("DailyClaim")
	if result.kind == "Pick" then
		Theme.popIn(pickCards)
		local first = pickCards[1] and pickCards[1]:FindFirstChild("Take")
		if first then
			Theme.focus(first :: GuiObject)
		end
		return
	end
	task.delay(1.4, function()
		if daily.frame.Visible then
			ShopController.openDaily(false)
		end
		if result.kind == "Coins" then
			HUDController.coinPop(tonumber(result.coins) or 0)
		elseif result.kind == "Spin" then
			if ShopController.onOpenSpin and inHub() then
				ShopController.onOpenSpin()
			else
				HUDController.hint("Your free spin is waiting at the Spin wheel", 2.4)
			end
		elseif result.kind == "Cosmetic" then
			announceItem(result)
		end
	end)
end

function ShopController.claimDaily()
	if profile.daily and not profile.daily.claimed and not claimPending then
		claimPending = true
		Net.request(Net.Actions.ClaimDaily)
	end
end

-- Open / close ---------------------------------------------------------------------------------------

local SHOP_KEYS = "RD_ShopKeys"
local function bindShopKeys(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority(
			SHOP_KEYS,
			function(_, state, input)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				if input.KeyCode == Enum.KeyCode.Left then
					step(-1)
				elseif input.KeyCode == Enum.KeyCode.Right then
					step(1)
				elseif input.KeyCode == Enum.KeyCode.Up then
					step(0, -1)
				elseif input.KeyCode == Enum.KeyCode.Down then
					step(0, 1)
				elseif input.KeyCode == Enum.KeyCode.Return then
					primaryAction()
				elseif input.KeyCode == Enum.KeyCode.ButtonB then
					SoundController.play("UIBack")
					ShopController.openShop(false)
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			3000,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right,
			Enum.KeyCode.Up,
			Enum.KeyCode.Down,
			Enum.KeyCode.Return,
			Enum.KeyCode.ButtonB
		)
	else
		ContextActionService:UnbindAction(SHOP_KEYS)
	end
end

function ShopController.isOpen(p: GuiObject): boolean
	return p.Visible and p:GetAttribute("ThemeOpen") ~= false
end

function ShopController.isShopOpen(): boolean
	return shop ~= nil and ShopController.isOpen(shop.frame)
end

function ShopController.openShop(on: boolean)
	if on and not inHub() then
		return
	end
	local f = shop.frame
	if on then
		if not ShopController.isOpen(f) then
			SoundController.play("UIOpen")
		end
		ShopController.openDaily(false)
		ShopController.openSettings(false)
		Theme.show(f, backdrop)
		markSeen(currentTab) -- opening the shop on a tab counts as looking at it
		renderShelf()
		bindShopKeys(true)
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		bindShopKeys(false)
		Theme.hide(f, if ShopController.isOpen(daily.frame) then nil else backdrop)
	end
end

function ShopController.openDaily(on: boolean)
	if on and not inHub() then
		return
	end
	local f = daily.frame
	if on then
		if not ShopController.isOpen(f) then
			SoundController.play("UIOpen")
		end
		ShopController.openShop(false)
		ShopController.openSettings(false)
		Theme.show(f, backdrop)
		renderDaily()
		if picking() then
			Theme.popIn(pickCards)
			local first = pickCards[1] and pickCards[1]:FindFirstChild("Take")
			Theme.focus((first or claimButton) :: GuiObject)
		else
			local roots = {}
			for _, card in dailyTiles do
				table.insert(roots, card.root)
			end
			Theme.popIn(roots)
			-- focus the likely answer: Claim
			Theme.focus(claimButton)
		end
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		Theme.hide(f, if ShopController.isOpen(shop.frame) then nil else backdrop)
	end
end

-- A sheet in the hub GUI, fixed size and scaled to the screen (so nothing ever spills off it).
function ShopController.sheet(
	name: string,
	title: string,
	size: Vector2,
	subtitle: string?,
	opts: { [string]: any }?
): any
	local o: { [string]: any } = { subtitle = subtitle }
	if opts then
		for k, v in opts do
			o[k] = v
		end
	end
	local s = Theme.sheet(gui, name, title, o)
	s.frame.Size = UDim2.fromOffset(size.X, size.Y)
	s.frame.Position = UDim2.fromScale(0.5, 0.48)
	Theme.autoScale(s.frame)
	return s
end

-- On touch screens the right edge belongs to the controls, so the action column becomes a row along
-- the bottom, a little larger, centred in the free space between the coins chip and the controls
-- (and shrunk only if that space is too narrow).
local ACTION_W, ACTION_H = 84, 56 + Theme.Ledge + 26 -- one Theme.roundAction button
local ACTIONS = 6 -- Bundles, Shop, Spin, Daily, Settings, Coins
local ROW_W = ACTIONS * ACTION_W + (ACTIONS - 1) * Theme.Space.L
local TOUCH_SCALE = 1.25 -- relative to the rest of the HUD
local actionLayout: UIListLayout
local actionScale: UIScale
local rowMode: boolean? = nil
local function layoutActions(gui: ScreenGui)
	local touch = AimController.lastInput == "Touch"
	if touch ~= rowMode then
		rowMode = touch
		actionLayout.FillDirection = if touch then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		actionRow.AnchorPoint = if touch then Vector2.new(0.5, 1) else Vector2.new(1, 0.5)
		actionRow.Size = if touch
			then UDim2.fromOffset(ROW_W, ACTION_H)
			else UDim2.fromOffset(ACTION_W, ACTIONS * ACTION_H + (ACTIONS - 1) * Theme.Space.L)
		if not touch then
			actionRow.Position = UDim2.new(1, -Theme.Space.L, 0.5, 0)
			local s = Theme.uiScale() * 0.95
			actionScale:SetAttribute("Base", s)
			actionScale.Scale = s
		end
	end
	if not touch then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local profile = pg and pg:FindFirstChild("Profile")
	local chip = profile and profile:FindFirstChild("Chip") :: GuiObject?
	local controls = pg and pg:FindFirstChild("MobileControls") :: ScreenGui?
	local catch = controls and controls.Enabled and controls:FindFirstChild("Catch", true) :: GuiObject?
	local left = if chip then chip.AbsolutePosition.X + chip.AbsoluteSize.X else gui.AbsolutePosition.X
	local right = if catch then catch.AbsolutePosition.X else gui.AbsolutePosition.X + gui.AbsoluteSize.X
	local s = math.clamp((right - left - 2 * Theme.Space.M) / ROW_W, 0.3, Theme.uiScale() * TOUCH_SCALE)
	if actionScale.Scale ~= s then
		actionScale:SetAttribute("Base", s)
		actionScale.Scale = s
	end
	actionRow.Position = UDim2.new(0, (left + right) / 2 - gui.AbsolutePosition.X, 1, -Theme.Space.S)
end

-- Is any hub sheet (shop, daily, settings, spin...) open? Theme.show/hide keep ThemeOpen current.
local function anySheetOpen(): boolean
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child:GetAttribute("ThemeOpen") == true then
			return true
		end
	end
	return false
end

-- A destination in the action column (Shop, Spin, Daily, Settings). Returns its button and dot.
function ShopController.addAction(
	label: string,
	tone: Color3,
	glyph: string,
	order: number,
	onClick: () -> ()
): (TextButton, Frame)
	local b, dot = Theme.roundAction(actionRow, label, tone, glyph, { LayoutOrder = order })
	b.Activated:Connect(function()
		-- opening plays the sheet's UIOpen; tapping the icon of the open sheet closes it: UIBack
		local wasOpen = anySheetOpen()
		onClick()
		if wasOpen and not anySheetOpen() then
			SoundController.play("UIBack")
		end
	end)
	return b, dot
end

-- Close every hub sheet (shop, daily and anything registered, like the spin wheel).
local extraClosers: { () -> () } = {}
function ShopController.onCloseAll(fn: () -> ())
	table.insert(extraClosers, fn)
end
function ShopController.closeAll()
	ShopController.openShop(false)
	ShopController.openDaily(false)
	ShopController.openSettings(false)
	for _, fn in extraClosers do
		fn()
	end
end
function ShopController.getBackdrop(): TextButton
	return backdrop
end

-- Kept for older callers: sheets now size themselves.
function ShopController.layout() end

-- Build ----------------------------------------------------------------------------------------------

local function buildShop()
	shop = ShopController.sheet("Shop", "Shop", SHOP_SIZE, nil, {
		tone = T.sun,
		glyph = "bag",
	})
	shop.close.Activated:Connect(function()
		ShopController.openShop(false)
	end)
	-- wallet: a coin and your balance, next to the close button
	local wallet = Theme.well(shop.header, {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -62, 0.5, -Theme.Ledge / 2),
		Size = UDim2.fromOffset(150, 40),
		ZIndex = 4,
	}, 20)
	Theme.coin(wallet, 28, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		ZIndex = 5,
	})
	walletLabel = Theme.text(wallet, 20, {
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -52, 1, 0),
		FontFace = Theme.DisplayFace,
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	-- "+" beside the wallet: get more coins
	local more = Theme.iconButton(shop.header, "plus", T.leaf, 40, {
		Name = "GetCoins",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -62 - 150 - Theme.Space.S, 0.5, -Theme.Ledge / 2),
		ZIndex = 4,
		silent = true, -- the Coins sheet answers with UIOpen
	})
	more.Activated:Connect(function()
		getCoins(nil)
	end)
	local function gateMore()
		more.Visible = player:GetAttribute("RobuxOk") == true
	end
	player:GetAttributeChangedSignal("RobuxOk"):Connect(gateMore)
	gateMore()
	local body = shop.body :: Frame
	-- category tabs
	local items = {}
	for _, cat in Catalog.Categories do
		table.insert(items, { key = cat, label = Catalog.CategoryNames[cat] or cat })
	end
	local tabsTrack, setter = Theme.segmented(body, items, currentTab, function(cat)
		currentTab = cat
		markSeen(cat)
		renderShelf()
		Theme.popIn((function()
			local list = {}
			for _, e in tiles do
				table.insert(list, e.card.button)
			end
			return list
		end)())
	end, { Size = UDim2.new(1, 0, 0, 48), ZIndex = 4 })
	setTab = setter
	for _, cat in Catalog.Categories do
		local tab = tabsTrack:FindFirstChild(cat) :: GuiObject?
		if tab then
			tabTags[cat] = newTag(tab)
		end
	end
	-- "Owned only" switch, right-aligned under the tabs (the label flips it too)
	local filterRow = new("Frame", {
		Name = "OwnedFilter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 56),
		Size = UDim2.fromOffset(190, 36),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, body)
	local function setOwnedOnly(on: boolean)
		ShopController.ownedOnly = on
		renderShelf()
	end
	local filterToggle, setFilter = Theme.toggle(filterRow, false, setOwnedOnly, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		ZIndex = 5,
	})
	local filterLabel = new("TextButton", {
		Name = "Label",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(filterToggle.Size.X.Offset + Theme.Space.S), 0.5, 0),
		Size = UDim2.new(1, -(filterToggle.Size.X.Offset + Theme.Space.S), 1, 0),
		BackgroundTransparency = 1,
		FontFace = Theme.LabelFace,
		Text = "Owned only",
		TextSize = 18,
		TextColor3 = T.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
	}, filterRow)
	filterLabel.Activated:Connect(function()
		local on = not ShopController.ownedOnly
		setFilter(on)
		setOwnedOnly(on)
	end)
	-- the shelf: tier sections of four-wide grids, scrolling down
	shelf = new("ScrollingFrame", {
		Name = "Shelf",
		Position = UDim2.fromOffset(-8, 98),
		Size = UDim2.new(1, 16, 1, -98),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ScrollBarImageColor3 = T.outline,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 4,
	}, body)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, shelf)
	-- the tier sections stacked down the shelf (a live Robux bundle's banner sits above them)
	new("UIListLayout", {
		Padding = UDim.new(0, Theme.Space.L),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, shelf)
end

-- The shop's scrolling shelf, for the Haunted Bundle banner (CoinShopController) to sit on.
function ShopController.shelf(): ScrollingFrame?
	return shelf
end

-- A reward's icon (Config.DailyRewards kinds) centred in `holder`: coins (three for a big pile), a
-- little prize wheel with rarity slots, the 2x disc, or a gift box in the pick's rarity color.
local function rewardIcon(holder: Frame, reward: any)
	local z = holder.ZIndex
	local function disc(size: number, fill: Color3): Frame
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = fill,
			ZIndex = z,
		}, holder)
		Theme.round(f)
		Theme.stroke(f, T.outline, Theme.StrokeToy)
		return f
	end
	if reward.Kind == "Coins" then
		local big = reward.Amount >= 600
		local spots: { { number } } = if big
			then { { 0.28, 0.62 }, { 0.72, 0.62 }, { 0.5, 0.38 } }
			else { { 0.5, 0.5 } }
		for n, spot in spots do
			Theme.coin(holder, if big then 34 else 44, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot[1], spot[2]),
				ZIndex = z + n,
			})
		end
	elseif reward.Kind == "Spin" then
		-- the hub wheel in miniature: a disc with four prize slots in its rarities and a sun hub
		local rare = reward.Wheel == "RarePlus"
		local wheel = disc(50, T.surfaceSunk)
		local slots: { string } = if rare
			then { "Rare", "Epic", "Rare", "Legendary" }
			else { "Common", "Rare", "Common", "Epic" }
		for n, r in slots do
			local a = math.rad((n - 1) * 90)
			local slot = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + 0.3 * math.sin(a), 0.5 - 0.3 * math.cos(a)),
				Size = UDim2.fromScale(0.3, 0.3),
				BackgroundColor3 = Theme.Rarity[r],
				ZIndex = z + 1,
			}, wheel)
			Theme.round(slot)
			Theme.stroke(slot, T.outline, 1.5)
		end
		local hub = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.26, 0.26),
			BackgroundColor3 = T.sun,
			ZIndex = z + 2,
		}, wheel)
		Theme.round(hub)
		Theme.stroke(hub, T.outline, 1.5)
	elseif reward.Kind == "Boost" then
		local d = disc(50, T.leaf)
		Theme.label(d, {
			Size = UDim2.fromScale(1, 1),
			Text = ("%dx"):format(Config.CoinShop.BoostMultiplier),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
		}, 2)
	else
		local item = reward.Id and Catalog.get(reward.Id)
		local rarity = if item then Catalog.rarity(item) else reward.Rarity
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(50, 50),
			BackgroundColor3 = Theme.Rarity[rarity] or T.candy,
			ZIndex = z,
		}, holder)
		Theme.corner(box, Theme.Radius.S)
		Theme.stroke(box, T.outline, Theme.StrokeToy)
		if item then
			drawArt(item, box)
		else
			Theme.glyph(box, "gift", T.paper, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.7, 0.7),
				ZIndex = z + 1,
			})
		end
	end
end

-- One day card: a toy card in its fill with a darker "Day N" strip, the reward's icon over a
-- sunburst, its label, and a paper status strip along the bottom. renderDaily colors it.
local function dayCard(parent: Instance, i: number, reward: any): { [string]: any }
	local last = i == #Config.DailyRewards.Ladder
	local root = new("Frame", {
		Name = "Day" .. i,
		LayoutOrder = i,
		Size = UDim2.fromOffset(CARD.X, CARD.Y + Theme.Ledge),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, parent)
	local scale = new("UIScale", {}, root)
	-- today's breathing select-colored glow, just outside the card
	local glow = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 12, 1, 12),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, root)
	Theme.corner(glow, Theme.Radius.M + 6)
	local glowStroke = Theme.stroke(glow, T.select, Theme.StrokeSelect)
	local ledge = new("Frame", {
		Name = "Ledge",
		Position = UDim2.fromOffset(0, Theme.Ledge),
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = T.shadowToy,
		ZIndex = 4,
	}, root)
	Theme.corner(ledge, Theme.Radius.M)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = T.sky,
		ZIndex = 5,
	}, root)
	Theme.corner(face, Theme.Radius.M)
	Theme.stroke(face, T.outline, Theme.StrokeToy)
	-- top strip (rounded on top only: a square filler covers its lower corners)
	local top = new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 32),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, face)
	Theme.corner(top, Theme.Radius.M)
	local topFill = new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.Radius.M),
		Size = UDim2.new(1, 0, 0, Theme.Radius.M),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, top)
	local dayLabel = Theme.text(top, 19, {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.DisplayFace,
		Text = ("Day %d"):format(i),
		TextColor3 = T.paper,
		ZIndex = 7,
	})
	Theme.textStroke(dayLabel, 2)
	-- the art: a sunburst behind the reward's icon, and its label
	local art = new("Frame", {
		Name = "Art",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32 - 34),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 6,
	}, face)
	local rays = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(110, 110),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
	}, art)
	for r = 0, 5 do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 14, 1, 0),
			Rotation = r * 30,
			BackgroundColor3 = T.paper,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, rays)
	end
	local icon = new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(60, 52),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, art)
	rewardIcon(icon, reward)
	local label = rewardLabel(reward)
	local amountLabel = Theme.text(art, if #label > 6 then 16 else 22, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -4, 0, 24),
		FontFace = Theme.DisplayFace,
		Text = label,
		TextColor3 = T.paper,
		ZIndex = 10,
	})
	Theme.textStroke(amountLabel, 2.5)
	-- claimed: a paper check stamp, tilted like it was pressed on by hand
	local stamp = new("Frame", {
		Name = "Stamp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = T.paper,
		Rotation = -12,
		Visible = false,
		ZIndex = 11,
	}, art)
	Theme.round(stamp)
	Theme.stroke(stamp, T.outline, Theme.StrokeToy)
	Theme.glyph(stamp, "check", T.success, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = 12,
	})
	-- status strip
	local bottom = new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = T.paper,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, face)
	Theme.corner(bottom, Theme.Radius.M)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, Theme.Radius.M),
		BackgroundColor3 = T.paper,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, bottom)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = T.outline,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, bottom)
	local status = Theme.text(bottom, 15, {
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 8,
	})
	if last then
		Theme.sticker(root, "Bonus", T.sun, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -8, 0, 2),
			Rotation = 12,
			ZIndex = 14,
		})
	end
	return {
		root = root,
		scale = scale,
		glow = glow,
		glowStroke = glowStroke,
		face = face,
		top = top,
		topFill = topFill,
		rays = rays,
		icon = icon,
		stamp = stamp,
		status = status,
		last = last,
		today = false,
	}
end

-- While the daily sheet is open: today's reward icon bobs and its glow breathes, sunbursts turn, the Claim button
-- shines. Still under reduced motion.
local function animateDaily()
	if not daily.frame.Visible or Theme.settings.reducedMotion then
		return
	end
	local t = os.clock()
	for _, card in dailyTiles do
		if card.rays.Visible then
			card.rays.Rotation = (t * (if card.today then 45 else 20)) % 360
		end
		if card.today then
			card.icon.Position = UDim2.new(0.5, 0, 0.42, math.sin(t * 3.2) * 4)
			card.glowStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * math.pi * 2 / Theme.Motion.Pulse))
		end
	end
	if claimShine.Visible then
		local phase = (t % 2.6) / 1.1
		local grad = claimShine:FindFirstChildOfClass("UIGradient") :: UIGradient
		grad.Offset = Vector2.new(if phase < 1 then -1 + 2 * phase else 1, 0)
	end
end

local function buildDaily()
	daily = ShopController.sheet("Daily", "Daily rewards!", DAILY_SIZE, "Log in every day for bigger rewards.", {
		tone = T.joyBlue,
		glyph = "gift",
	})
	daily.close.Activated:Connect(function()
		ShopController.openDaily(false)
	end)
	local body = daily.body :: Frame
	-- the day cards, and in their place while a cosmetic pick waits, its choices
	local function cardRow(name: string, gap: number): Frame
		local row = new("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, CARD.Y + Theme.Ledge + 20),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, body)
		new("UIPadding", { PaddingTop = UDim.new(0, 10) }, row)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		return row
	end
	daysRow = cardRow("Days", 10)
	pickRow = cardRow("Pick", 24)
	pickRow.Visible = false
	for i, reward in Config.DailyRewards.Ladder do
		table.insert(dailyTiles, dayCard(daysRow, i, reward))
	end
	claimButton = Theme.button(body, "Claim", "primary", {
		Name = "Claim",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(340, 64),
		ZIndex = 5,
	})
	-- a paper glint that sweeps across the button every few seconds
	local face = claimButton:FindFirstChild("Face") :: Frame
	claimShine = new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.paper,
		ZIndex = claimButton.ZIndex + 1,
	}, face)
	Theme.round(claimShine)
	new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, claimShine)
	claimButton.Activated:Connect(function()
		ShopController.claimDaily()
	end)
	RunService.Heartbeat:Connect(animateDaily)
end

-- Settings: one row per switch (label, a plain explanation, the toggle).
local function buildSettings()
	settings = ShopController.sheet("Settings", "Settings", SETTINGS_SIZE, "These stay with you between visits.", {
		tone = T.sky,
		glyph = "gear",
	})
	settings.close.Activated:Connect(function()
		ShopController.openSettings(false)
	end)
	local body = settings.body :: Frame
	new("UIListLayout", { Padding = UDim.new(0, Theme.Space.M), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local function row(
		order: number,
		label: string,
		caption: string,
		initial: boolean,
		onChange: (boolean) -> ()
	): (boolean) -> ()
		local r = Theme.well(body, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 72), ZIndex = 4 }, Theme.Radius.M)
		Theme.text(r, 18, {
			Position = UDim2.fromOffset(20, 12),
			Size = UDim2.new(1, -110, 0, 26),
			Text = label,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		})
		Theme.body(r, {
			Position = UDim2.fromOffset(20, 40),
			Size = UDim2.new(1, -110, 0, 18),
			FontFace = Theme.TextFace,
			Text = caption,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		})
		local _, set = Theme.toggle(r, initial, onChange, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -20, 0.5, 0),
			ZIndex = 5,
		})
		return set
	end
	HUDController.followQueue(row(1, "Play again", "Join the next match automatically.", true, function(v)
		HUDController.applySetting("PlayAgain", v)
	end))
	row(2, "Camera shake", "Shake the camera on big hits.", HUDController.settings.CameraShake, function(v)
		HUDController.applySetting("CameraShake", v)
	end)
	row(
		3,
		"Reduced motion",
		"Calmer effects: no bounces, flashes or shake.",
		HUDController.settings.ReducedMotion,
		function(v)
			HUDController.applySetting("ReducedMotion", v)
		end
	)
	local setPerformance = row(
		4,
		"Performance mode",
		"Smoother on slower devices: fewer lights, shadows and sparkles.",
		GraphicsController.low,
		function(v)
			GraphicsController.set(v, true)
		end
	)
	-- it can also switch on by itself when the game runs slowly
	GraphicsController.onChanged(setPerformance)
end

function ShopController.openSettings(on: boolean)
	if on and not inHub() then
		return
	end
	local f = settings.frame
	if on then
		if not ShopController.isOpen(f) then
			SoundController.play("UIOpen")
		end
		ShopController.openShop(false)
		ShopController.openDaily(false)
		Theme.show(f, backdrop)
	else
		Theme.hide(f, backdrop)
	end
end

function ShopController.init()
	gui = new("ScreenGui", {
		Name = "Hub",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	ShopController.gui = gui
	backdrop = Theme.backdrop(gui, function()
		ShopController.closeAll()
	end)

	-- the action column: round destinations stacked down the right edge of the hub (on touch screens
	-- a row along the bottom instead; see layoutActions)
	actionRow = new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.Space.L, 0.5, 0),
		Size = UDim2.fromOffset(ACTION_W, ACTIONS * ACTION_H + (ACTIONS - 1) * Theme.Space.L),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, gui)
	actionLayout = new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actionRow)
	actionScale = Theme.autoScale(actionRow, 0.95)
	ShopController.addAction("Shop", T.sun, "bag", 1, function()
		ShopController.openShop(not ShopController.isOpen(shop.frame))
	end)
	local _
	_, dailyDot = ShopController.addAction("Daily", T.leaf, "gift", 3, function()
		ShopController.openDaily(not ShopController.isOpen(daily.frame))
	end)
	ShopController.addAction("Settings", T.sky, "gear", 4, function()
		ShopController.openSettings(not ShopController.isOpen(settings.frame))
	end)

	buildShop()
	buildDaily()
	buildSettings()
end

function ShopController.start()
	-- an event starting or ending changes what's on the shelf
	ReplicatedStorage:GetAttributeChangedSignal("Halloween"):Connect(function()
		refreshTabTags()
		if shop.frame.Visible then
			markSeen(currentTab)
			renderShelf()
		end
	end)
	-- Robux unlocking brings the bundle items (and their banner) onto the shelf
	player:GetAttributeChangedSignal("RobuxOk"):Connect(function()
		if shop.frame.Visible then
			renderShelf()
		end
	end)
	Net.on("Profile", function(d)
		profile = d
		refreshTabTags()
		if shop.frame.Visible then
			renderShelf()
		end
		renderDaily()
		-- show the daily sheet once per session when there's something to claim or pick (never
		-- auto-claims)
		if not dailyAutoShown and d.daily and (not d.daily.claimed or picking()) and inHub() then
			dailyAutoShown = true
			if not shop.frame.Visible then
				ShopController.openDaily(true)
			end
		end
	end)
	-- the server's answer to Claim: the granted reward ({ ok, day, kind, ... }) or why not
	Net.on("DailyResult", function(d)
		claimPending = false
		if d.ok then
			renderDaily()
			celebrateClaim(d)
		else
			SoundController.play("UIError")
			HUDController.hint(tostring(d.message or "Can't claim right now"), 1.6)
		end
	end)
	Net.on("PickResult", function(d)
		pickRequested = false
		if not d.ok then
			SoundController.play("UIError")
			HUDController.hint(tostring(d.message or "Can't pick that"), 1.6)
			return
		end
		SoundController.play("DailyClaim")
		for _, f in pickCards do
			if f.Name == d.id then
				Theme.pop(f, 1.2, Theme.Motion.Slow)
			end
		end
		task.delay(0.9, function()
			if daily.frame.Visible and not picking() then
				ShopController.openDaily(false)
			end
			announceItem(d)
		end)
	end)
	Net.on("ShopResult", function(d)
		if not d.ok and d.message then
			HUDController.hint(tostring(d.message), 1.6)
			SoundController.play("UIError")
		elseif d.ok then
			-- the bought/equipped card pops in place; after a purchase its button becomes "Equip"
			-- the press already clicked: an equip gets a soft confirm, a purchase the success run
			SoundController.play(if d.equip then "UIEquip" else "Purchase")
			task.defer(function()
				for _, e in tiles do
					if e.item.Id == d.id then
						Theme.pop(e.card.art, 1.25, Theme.Motion.Slow)
						Theme.pop(e.card.action, 0.85, Theme.Motion.Slow)
					end
				end
			end)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ShopPrompt" then
			ShopController.openShop(true)
		elseif prompt.Name == "DailyPrompt" then
			ShopController.openDaily(true)
		end
	end)
	-- any open sheet (shop, daily, spin, settings) shares the backdrop: while it's up the server
	-- won't pull you into a match, so you're never teleported mid-purchase or mid-spin (the quest
	-- chest opening screen holds it too, through ShopController.holdBusy)
	local sentBusy = false
	RunService.RenderStepped:Connect(function()
		local hub = inHub()
		gui.Enabled = hub and not HUDController.cinematic
		local busy = hub and (backdrop.Visible or ShopController.holdBusy)
		if busy ~= sentBusy then
			sentBusy = busy
			Net.request(Net.Actions.SetBusy, { value = busy })
		end
		-- the row steps aside while a sheet is up
		actionRow.Visible = not backdrop.Visible
		if hub then
			layoutActions(gui)
		end
		if not hub and backdrop.Visible then
			ShopController.closeAll()
		end
		if not hub and (shop.frame.Visible or daily.frame.Visible) then
			ShopController.openShop(false)
			ShopController.openDaily(false)
		end
	end)
	local _ = setTab
end

return ShopController
