--!strict
-- Hub UI: the action row of destinations (Shop, Spin, Daily, Settings), the shop and the daily
-- reward. Shown only in the hub, never during a match. While the shop is open the player stays in
-- the hub (auto-queue is paused and restored on close) so the short intermission never yanks them out
-- mid-purchase.
--
-- Layout follows the Toybox Island design system: the shop is a sheet with segmented category tabs
-- over a grid of item cards (name, tier color and sticker, preview, and an action on every card). The daily reward
-- is louder on purpose: a sheet with a sky header band, a row of toy day cards (today's grows, glows
-- and spins a sunburst behind its coin) and one shining primary button.

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
local AimController = require(script.Parent.AimController)
local SoundController = require(script.Parent.SoundController)
local GraphicsController = require(script.Parent.GraphicsController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local new = Theme.new

local ShopController = {}

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
local tiles: { { item: any, card: any } } = {}
local selectedId: string? = nil
local dailyTiles: { any } = {}
local dailyDot: Frame
local claimButton: TextButton
local claimShine: Frame
local currentTab = "BallSkin"
local profile: any = { coins = 0, owned = {}, equipped = {}, daily = nil }
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

-- Buy, equip, or (short on coins) a nudge.
local function primaryAction(item: Catalog.Item?)
	item = item or selectedItem()
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

local function previewAction(item: Catalog.Item)
	if item.Category == "Pose" then
		local IntroController = require(script.Parent.IntroController) :: any
		IntroController.preview(item.Data.Pose)
		ShopController.openShop(false)
	elseif item.Category == "Finisher" then
		ShopController.previewFinisher(item)
	end
end

-- A card's action for the item's state: Equipped (leaf, inert), Equip (sky), Buy (sun), or the
-- price, faded, while you can't afford it yet.
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
	elseif coins >= item.Price then
		Theme.setText(b, ("Buy · %s"):format(commas(item.Price)))
		Theme.recolor(b, T.sun)
		Theme.setEnabled(b, true)
	else
		Theme.setText(b, ("%s coins"):format(commas(item.Price)))
		Theme.recolor(b, "secondary")
		Theme.setEnabled(b, false)
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

local function itemCard(item: Catalog.Item, order: number): { [string]: any }
	local id = item.Id
	local tone = toneOf(item)
	local b = new("TextButton", {
		Name = id,
		LayoutOrder = order,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, shelf)
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
	b.SelectionGained:Connect(function()
		selectItem(id)
	end)
	return { button = b, art = art, action = action }
end

local function renderShelf()
	for _, child in shelf:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	table.clear(tiles)
	walletLabel.Text = commas(profile.coins or 0)
	-- event cosmetics show while their event runs (and forever once owned)
	local items = {}
	local events = Catalog.activeEvents()
	for _, item in Catalog.inCategory(currentTab) do
		if Catalog.isOffered(item, events) or owns(item) then
			table.insert(items, item)
		end
	end
	local keep = selectedId
	selectedId = nil
	local pick: string? = nil
	for i, item in items do
		table.insert(tiles, { item = item, card = itemCard(item, i) })
		if isEquipped(item) then
			pick = pick or item.Id
		end
	end
	-- keep the selection when re-rendering the same tab; otherwise start on the equipped item
	local still = false
	for _, e in tiles do
		still = still or e.item.Id == keep
	end
	selectItem((if still then keep else pick) or (items[1] and items[1].Id) or "")
	return items
end

-- Move the selection through the grid (arrows: left/right by one, up/down by a row).
local function step(delta: number)
	for i, e in tiles do
		if e.item.Id == selectedId then
			local nxt = tiles[math.clamp(i + delta, 1, #tiles)]
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

local function renderDaily()
	local d = profile.daily
	dailyDot.Visible = d ~= nil and not d.claimed
	if not d then
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
		card.coins.Visible = not done
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
	Theme.setText(claimButton, if d.claimed then "Come back tomorrow!" else ("Claim %s coins"):format(commas(d.amount)))
	Theme.recolor(claimButton, if d.claimed then "secondary" else "primary")
	Theme.setEnabled(claimButton, not d.claimed)
	claimShine.Visible = not d.claimed
end

-- Claimed: today's card pops and turns leaf with a check stamped on it, the button says come back
-- tomorrow, the sheet closes itself, and the coins fly into the counter.
local function celebrateClaim(day: number, amount: number)
	local card = dailyTiles[day]
	if card then
		Theme.pop(card.root, 1.25, Theme.Motion.Slow)
		Theme.pop(card.stamp, 2.2, Theme.Motion.Slow)
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
					step(-COLUMNS)
				elseif input.KeyCode == Enum.KeyCode.Down then
					step(COLUMNS)
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
		local roots = {}
		for _, card in dailyTiles do
			table.insert(roots, card.root)
		end
		Theme.popIn(roots)
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
local ROW_W = 4 * ACTION_W + 3 * Theme.Space.L
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
			else UDim2.fromOffset(ACTION_W, 4 * ACTION_H + 3 * Theme.Space.L)
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
	local catch = controls and controls.Enabled and controls:FindFirstChild("Catch") :: GuiObject?
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
				table.insert(list, e.card.button)
			end
			return list
		end)())
	end, { Size = UDim2.new(1, 0, 0, 48), ZIndex = 4 })
	setTab = setter
	-- the grid: four cards a row, scrolling down
	shelf = new("ScrollingFrame", {
		Name = "Shelf",
		Position = UDim2.fromOffset(-8, 56),
		Size = UDim2.new(1, 16, 1, -56),
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
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(ITEM_CARD.X, ITEM_CARD.Y),
		CellPadding = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		FillDirectionMaxCells = COLUMNS,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, shelf)
end

-- One day card: a toy card in its fill with a darker "Day N" strip, the coin art over a sunburst,
-- the amount, and a paper status strip along the bottom. renderDaily colors it.
local function dayCard(parent: Instance, i: number, amount: number): { [string]: any }
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
	-- the art: a sunburst behind one coin (three on the last day) and the amount
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
	local coins = new("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(60, 52),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, art)
	local spots: { { number } } = if last then { { 0.28, 0.62 }, { 0.72, 0.62 }, { 0.5, 0.38 } } else { { 0.5, 0.5 } }
	for n, spot in spots do
		Theme.coin(coins, if last then 34 else 44, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot[1], spot[2]),
			ZIndex = 7 + n,
		})
	end
	local amountLabel = Theme.text(art, 22, {
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = Theme.DisplayFace,
		Text = "+" .. commas(amount),
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
		coins = coins,
		stamp = stamp,
		status = status,
		last = last,
		today = false,
	}
end

-- While the daily sheet is open: today's coin bobs and its glow breathes, sunbursts turn, the Claim button
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
			card.coins.Position = UDim2.new(0.5, 0, 0.42, math.sin(t * 3.2) * 4)
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
	local row = new("Frame", {
		Name = "Days",
		Size = UDim2.new(1, 0, 0, CARD.Y + Theme.Ledge + 20),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, body)
	new("UIPadding", { PaddingTop = UDim.new(0, 10) }, row)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i, amount in Config.DailyRewards.Ladder do
		table.insert(dailyTiles, dayCard(row, i, amount))
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
		Size = UDim2.fromOffset(ACTION_W, 4 * ACTION_H + 3 * Theme.Space.L),
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
		if shop.frame.Visible then
			renderShelf()
		end
	end)
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
			if not shop.frame.Visible then
				ShopController.openDaily(true)
			end
		end
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
	-- won't pull you into a match, so you're never teleported mid-purchase or mid-spin
	local sentBusy = false
	RunService.RenderStepped:Connect(function()
		local hub = inHub()
		gui.Enabled = hub and not HUDController.cinematic
		local busy = hub and backdrop.Visible
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
