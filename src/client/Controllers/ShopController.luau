--!strict
-- Hub UI: the action row of destinations (Shop, Spin, Daily, Settings), the shop and the daily
-- reward. Shown only in the hub, never during a match. While the shop is open the player stays in
-- the hub (auto-queue is paused and restored on close) so the short intermission never yanks them out
-- mid-purchase.
--
-- Layout follows the Toybox Island design system: the shop is a sheet with segmented category tabs,
-- one horizontal shelf of item tiles (exactly one selected: it grows, wears the selection ring and
-- shows its name in a bubble) and a detail strip with the item's stickers and its actions. Hovering
-- or moving the gamepad selection along the shelf selects; the primary button acts. The daily reward
-- is a sheet with a row of day tiles and one primary button.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local new = Theme.new

local ShopController = {}

local SHOP_SIZE = Vector2.new(880, 520)
local DAILY_SIZE = Vector2.new(720, 400)
local SETTINGS_SIZE = Vector2.new(520, 372)

local gui: ScreenGui
local backdrop: TextButton
local actionRow: Frame
local shop: any -- Theme.Sheet
local daily: any -- Theme.Sheet
local settings: any -- Theme.Sheet
local shelf: ScrollingFrame
local walletLabel: TextLabel
local setTab: (string) -> ()
local detail: { [string]: any } = {}
local tiles: { { item: any, tile: any } } = {}
local selectedId: string? = nil
local dailyTiles: { any } = {}
local dailyDot: Frame
local claimButton: TextButton
local currentTab = "BallSkin"
local profile: any = { coins = 0, owned = {}, equipped = {}, daily = nil }
local queueBeforeShop: boolean? = nil
local dailyAutoShown = false
local claimPending = false -- the player pressed Claim and we're waiting for the server's answer

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function owns(item: Catalog.Item): boolean
	return item.Default == true or (profile.owned and profile.owned[item.Id] == true)
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

-- The art inside a tile: a ball, a trail stripe, the title text, or the item's icon.
local function drawArt(item: Catalog.Item, art: Frame)
	local d = item.Data
	local z = art.ZIndex + 1
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
	elseif item.Category == "Title" then
		Theme.label(art, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.82, 0.3),
			Text = if d.Text and d.Text ~= "" then d.Text else "None",
			TextColor3 = Theme.textOn(art.BackgroundColor3),
			ZIndex = z,
		}, 0)
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

-- Shop: detail strip ---------------------------------------------------------------------------------

local function selectedItem(): Catalog.Item?
	return if selectedId then Catalog.get(selectedId) else nil
end

local function renderDetail()
	local item = selectedItem()
	if not item then
		return
	end
	detail.name.Text = item.Name
	for _, s in detail.stickers:GetChildren() do
		if s:IsA("Frame") then
			s:Destroy()
		end
	end
	local owned, equipped = owns(item), isEquipped(item)
	local coins = profile.coins or 0
	local order = 0
	local function sticker(text: string, tone: Color3)
		order += 1
		Theme.sticker(detail.stickers, text, tone, { LayoutOrder = order })
	end
	if item.Price > 0 then
		sticker(Catalog.rarity(item), Theme.Rarity[Catalog.rarity(item)])
	end
	if equipped then
		sticker("Equipped", T.leaf)
	elseif owned then
		sticker("Owned", T.sky)
	end
	detail.caption.Text = if equipped
		then "You're using this one."
		elseif owned then "It's yours. Equip it to use it in matches."
		elseif coins >= item.Price then ("Costs %s coins. You have %s."):format(commas(item.Price), commas(coins))
		else ("You need %s more coins."):format(commas(item.Price - coins))
	local primary = detail.primary :: TextButton
	if equipped then
		Theme.setText(primary, "Equipped")
		Theme.recolor(primary, "secondary")
		Theme.setEnabled(primary, false)
	elseif owned then
		Theme.setText(primary, "Equip")
		Theme.recolor(primary, "primary")
		Theme.setEnabled(primary, true)
	else
		Theme.setText(primary, ("Buy for %s"):format(commas(item.Price)))
		local afford = coins >= item.Price
		Theme.recolor(primary, if afford then "primary" else "secondary")
		Theme.setEnabled(primary, afford)
	end
	local secondary = detail.secondary :: TextButton
	secondary.Visible = item.Category == "Pose" or item.Category == "Finisher"
	Theme.setText(secondary, if item.Category == "Pose" then "Try it on" else "Preview")
end

local function scrollIntoView(button: GuiObject)
	local left = button.AbsolutePosition.X - shelf.AbsolutePosition.X + shelf.CanvasPosition.X
	local right = left + button.AbsoluteSize.X
	local view = shelf.AbsoluteSize.X
	local x = shelf.CanvasPosition.X
	local margin = 24
	if left - margin < x then
		x = left - margin
	elseif right + margin > x + view then
		x = right + margin - view
	end
	x = math.max(0, x)
	if math.abs(x - shelf.CanvasPosition.X) > 0.5 then
		Theme.tween(shelf, Theme.Motion.Fast, { CanvasPosition = Vector2.new(x, 0) }, Enum.EasingStyle.Quint)
	end
end

local function selectItem(id: string, quiet: boolean?)
	if selectedId == id then
		return
	end
	selectedId = id
	for _, entry in tiles do
		local on = entry.item.Id == id
		entry.tile.setSelected(on)
		if on then
			scrollIntoView(entry.tile.button)
		end
	end
	renderDetail()
	local _ = quiet
end

-- Shop: shelf --------------------------------------------------------------------------------------

local function tileSize(): number
	return if Theme.isCompact() then 112 else 144
end

local function renderShelf()
	for _, child in shelf:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	table.clear(tiles)
	walletLabel.Text = commas(profile.coins or 0)
	local items = Catalog.inCategory(currentTab)
	local size = tileSize()
	local keep = selectedId
	selectedId = nil
	local pick: string? = nil
	for i, item in items do
		local tile = Theme.tile(shelf, size, toneOf(item), item.Name, { LayoutOrder = i, Name = item.Id })
		drawArt(item, tile.art)
		if isEquipped(item) then
			-- the equipped one carries a leaf check in its corner (the shelf otherwise shows art alone)
			local check = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -8, 0, 8),
				Size = UDim2.fromOffset(30, 30),
				BackgroundColor3 = T.leaf,
				ZIndex = tile.art.ZIndex + 3,
			}, tile.art)
			Theme.round(check)
			Theme.stroke(check, T.outline, Theme.StrokeToy)
			Theme.glyph(check, "check", T.onFill, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.6, 0.6),
				ZIndex = check.ZIndex + 1,
			})
			pick = pick or item.Id
		end
		local id = item.Id
		tile.button.MouseEnter:Connect(function()
			selectItem(id)
		end)
		tile.button.SelectionGained:Connect(function()
			selectItem(id)
		end)
		tile.button.Activated:Connect(function()
			selectItem(id)
			SoundController.play("UIClick")
		end)
		table.insert(tiles, { item = item, tile = tile })
	end
	-- keep the selection when re-rendering the same tab; otherwise start on the equipped item
	local still = false
	for _, e in tiles do
		still = still or e.item.Id == keep
	end
	selectItem((if still then keep else pick) or (items[1] and items[1].Id) or "")
	return items
end

-- Move the shelf selection left/right (keyboard arrows).
local function step(delta: number)
	for i, e in tiles do
		if e.item.Id == selectedId then
			local nxt = tiles[math.clamp(i + delta, 1, #tiles)]
			if nxt and nxt.item.Id ~= selectedId then
				selectItem(nxt.item.Id)
				Theme.setHome(nxt.tile.button)
				SoundController.play("UIMove")
			end
			return
		end
	end
end

local function primaryAction()
	local item = selectedItem()
	if not item or isEquipped(item) then
		return
	end
	if owns(item) then
		Net.request(Net.Actions.EquipItem, { id = item.Id })
	elseif (profile.coins or 0) >= item.Price then
		Net.request(Net.Actions.BuyItem, { id = item.Id })
	else
		SoundController.play("UIError")
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

local function secondaryAction()
	local item = selectedItem()
	if not item then
		return
	end
	if item.Category == "Pose" then
		local IntroController = require(script.Parent.IntroController) :: any
		IntroController.preview(item.Data.Pose)
		ShopController.openShop(false)
	elseif item.Category == "Finisher" then
		ShopController.previewFinisher(item)
	end
end

-- Daily ----------------------------------------------------------------------------------------------

local function renderDaily()
	local d = profile.daily
	dailyDot.Visible = d ~= nil and not d.claimed
	if not d then
		return
	end
	daily.subtitle.Text = if d.claimed
		then "Collected today. Come back tomorrow for the next one."
		else ("Day %d of %d. Log in every day for bigger rewards."):format(d.day, #Config.DailyRewards.Ladder)
	for i, tile in dailyTiles do
		local done = i < d.day or (d.claimed and i == d.day)
		local today = i == d.day and not d.claimed
		local isLast = i == #dailyTiles
		tile.art.BackgroundColor3 = if done
			then T.leaf
			elseif today then T.sun
			elseif isLast then T.candy
			else T.surfaceSunk
		local amount = tile.art:FindFirstChild("Amount") :: TextLabel
		local check = tile.art:FindFirstChild("Done") :: GuiObject
		amount.Visible = not done
		amount.TextColor3 = if today or isLast then T.onFill else T.inkMuted
		check.Visible = done
		tile.setSelected(today)
	end
	Theme.setText(claimButton, if d.claimed then "Come back tomorrow!" else ("Claim %s coins"):format(commas(d.amount)))
	Theme.recolor(claimButton, if d.claimed then "secondary" else "primary")
	Theme.setEnabled(claimButton, not d.claimed)
end

-- Claimed: today's tile pops and turns leaf, the button says come back tomorrow, the sheet closes
-- itself, and the coins fly into the counter.
local function celebrateClaim(day: number, amount: number)
	local tile = dailyTiles[day]
	if tile then
		Theme.pop(tile.art, 1.3, Theme.Motion.Slow)
	end
	task.defer(function()
		Theme.pop(claimButton, 0.85, Theme.Motion.Slow)
	end)
	SoundController.play("DailyClaim")
	task.delay(1.4, function()
		if daily.frame.Visible then
			ShopController.openDaily(false)
		end
		HUDController.coinPop(amount)
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
		ContextActionService:BindActionAtPriority(SHOP_KEYS, function(_, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if input.KeyCode == Enum.KeyCode.Left then
				step(-1)
			elseif input.KeyCode == Enum.KeyCode.Right then
				step(1)
			elseif input.KeyCode == Enum.KeyCode.Return then
				primaryAction()
			elseif input.KeyCode == Enum.KeyCode.ButtonB then
				ShopController.openShop(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Return, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(SHOP_KEYS)
	end
end

function ShopController.isOpen(p: GuiObject): boolean
	return p.Visible and p:GetAttribute("ThemeOpen") ~= false
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
		renderShelf()
		bindShopKeys(true)
		if queueBeforeShop == nil then
			queueBeforeShop = player:GetAttribute("AutoQueue") ~= false
			Net.request(Net.Actions.SetAutoQueue, { value = false })
		end
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		bindShopKeys(false)
		Theme.hide(f, if ShopController.isOpen(daily.frame) then nil else backdrop)
	end
	if not on and queueBeforeShop ~= nil then
		local pref = player:GetAttribute("QueuePreference")
		local restoreTo = if type(pref) == "boolean" then pref else queueBeforeShop
		Net.request(Net.Actions.SetAutoQueue, { value = restoreTo })
		queueBeforeShop = nil
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
		-- focus the likely answer: Claim
		Theme.focus(claimButton)
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		Theme.hide(f, if ShopController.isOpen(shop.frame) then nil else backdrop)
	end
end

-- A sheet in the hub GUI, fixed size and scaled to the screen (so nothing ever spills off it).
function ShopController.sheet(name: string, title: string, size: Vector2, subtitle: string?): any
	local s = Theme.sheet(gui, name, title, { subtitle = subtitle })
	s.frame.Size = UDim2.fromOffset(size.X, size.Y)
	s.frame.Position = UDim2.fromScale(0.5, 0.48)
	Theme.autoScale(s.frame)
	return s
end

-- A destination in the action row (Shop, Spin, Daily, Settings). Returns its button and dot.
function ShopController.addAction(
	label: string,
	tone: Color3,
	glyph: string,
	order: number,
	onClick: () -> ()
): (TextButton, Frame)
	local b, dot = Theme.roundAction(actionRow, label, tone, glyph, { LayoutOrder = order })
	b.Activated:Connect(onClick)
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
	shop = ShopController.sheet("Shop", "Shop", SHOP_SIZE, "Pick something to see it up close.")
	shop.close.Activated:Connect(function()
		ShopController.openShop(false)
	end)
	-- wallet: a coin and your balance, next to the close button
	local wallet = Theme.well(shop.header, {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 2),
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
	local body = shop.body :: Frame
	-- category tabs
	local items = {}
	for _, cat in Catalog.Categories do
		table.insert(items, { key = cat, label = Catalog.CategoryNames[cat] or cat })
	end
	local _, setter = Theme.segmented(body, items, currentTab, function(cat)
		currentTab = cat
		renderShelf()
		Theme.popIn((function()
			local list = {}
			for _, e in tiles do
				table.insert(list, e.tile.art)
			end
			return list
		end)())
	end, { Size = UDim2.new(1, 0, 0, 48), ZIndex = 4 })
	setTab = setter
	-- the shelf: one row of tiles that scrolls sideways (room above for the title bubble)
	shelf = new("ScrollingFrame", {
		Name = "Shelf",
		Position = UDim2.fromOffset(-8, 52),
		Size = UDim2.new(1, 16, 0, 56 + 144 + 26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ZIndex = 4,
	}, body)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 60),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, shelf)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, shelf)
	-- the detail strip: name, stickers and a caption on the left, the actions on the right
	local strip = Theme.well(body, {
		Name = "Detail",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 108),
		ZIndex = 4,
	}, Theme.Radius.L)
	detail.name = Theme.label(strip, {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -400, 0, 32),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, 0)
	detail.stickers = new("Frame", {
		Name = "Stickers",
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.new(1, -400, 0, 20),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, strip)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Space.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, detail.stickers)
	detail.caption = Theme.body(strip, {
		Position = UDim2.fromOffset(20, 76),
		Size = UDim2.new(1, -400, 0, 18),
		FontFace = Theme.TextFace,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local actions = new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(360, 56),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, strip)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actions)
	detail.secondary = Theme.button(actions, "Preview", "secondary", {
		Name = "Secondary",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(150, 56),
		ZIndex = 6,
	})
	detail.secondary.Activated:Connect(secondaryAction)
	detail.primary = Theme.button(actions, "Buy", "primary", {
		Name = "Primary",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(190, 56),
		ZIndex = 6,
	})
	detail.primary.Activated:Connect(primaryAction)
end

local function buildDaily()
	daily = ShopController.sheet("Daily", "Daily reward", DAILY_SIZE, "")
	daily.close.Activated:Connect(function()
		ShopController.openDaily(false)
	end)
	local body = daily.body :: Frame
	local row = new("Frame", {
		Name = "Days",
		Size = UDim2.new(1, 0, 0, 56 + 84 + 26),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, body)
	new("UIPadding", { PaddingTop = UDim.new(0, 58) }, row)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i, amount in Config.DailyRewards.Ladder do
		local tile = Theme.tile(row, 76, T.surfaceSunk, ("Today · +%s"):format(commas(amount)), {
			LayoutOrder = i,
			Selectable = false,
		})
		tile.button.Selectable = false
		Theme.text(tile.art, 22, {
			Name = "Amount",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(1, 0.4),
			FontFace = Theme.DisplayFace,
			Text = commas(amount),
			ZIndex = tile.art.ZIndex + 1,
		})
		Theme.glyph(tile.art, "check", T.onFill, {
			Name = "Done",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			Visible = false,
			ZIndex = tile.art.ZIndex + 1,
		})
		Theme.body(tile.button, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 8),
			Size = UDim2.new(1, 0, 0, 16),
			FontFace = Theme.TextFace,
			Text = ("Day %d"):format(i),
			ZIndex = tile.art.ZIndex,
		})
		table.insert(dailyTiles, tile)
	end
	claimButton = Theme.button(body, "Claim", "primary", {
		Name = "Claim",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(300, 60),
		ZIndex = 5,
	})
	claimButton.Activated:Connect(function()
		ShopController.claimDaily()
	end)
end

-- Settings: one row per switch (label, a plain explanation, the toggle).
local function buildSettings()
	settings = ShopController.sheet("Settings", "Settings", SETTINGS_SIZE, "These stay with you between visits.")
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

	-- the action row: round destinations centred near the bottom of the hub
	actionRow = new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.fromOffset(4 * 84 + 3 * Theme.Space.XL, 56 + Theme.Ledge + 26),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, gui)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.XL),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actionRow)
	Theme.autoScale(actionRow, 0.95)
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
	Net.on("Profile", function(d)
		local justClaimed = claimPending and d.daily and d.daily.claimed
		profile = d
		if justClaimed then
			claimPending = false
			renderDaily()
			celebrateClaim(d.daily.day, Config.DailyRewards.Ladder[d.daily.day] or 0)
		end
		if shop.frame.Visible then
			renderShelf()
		end
		renderDaily()
		-- show the daily sheet once per session when there's something to claim (never auto-claims)
		if not dailyAutoShown and d.daily and not d.daily.claimed and inHub() then
			dailyAutoShown = true
			task.delay(1.5, function()
				if inHub() and not shop.frame.Visible then
					ShopController.openDaily(true)
				end
			end)
		end
	end)
	Net.on("ShopResult", function(d)
		if not d.ok and d.message then
			HUDController.hint(tostring(d.message), 1.6)
			SoundController.play("UIError")
		elseif d.ok then
			-- the bought/equipped tile pops in place; after a purchase the primary becomes "Equip"
			SoundController.play(if d.equip then "UIClick" else "Purchase")
			task.defer(function()
				for _, e in tiles do
					if e.item.Id == d.id then
						Theme.pop(e.tile.art, 1.25, Theme.Motion.Slow)
					end
				end
				if not d.equip then
					Theme.pop(detail.primary, 0.85, Theme.Motion.Slow)
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
	RunService.RenderStepped:Connect(function()
		local hub = inHub()
		gui.Enabled = hub and not HUDController.cinematic
		-- the row steps aside while a sheet is up
		actionRow.Visible = not backdrop.Visible
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
