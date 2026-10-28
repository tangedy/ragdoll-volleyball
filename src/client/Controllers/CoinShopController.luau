--!strict
-- The Coins sheet: bundles of coins sold for Robux (Config.CoinShop). Each card is a developer
-- product; Buy opens Roblox's own purchase pop-up, and the server (PurchaseService) adds the coins
-- once the receipt is in. The shop sends players here when they press Buy on something they can't
-- afford yet: the sheet then says how many coins they're short and points at the smallest bundle
-- that covers it, and after a purchase takes them straight back to the shop.
--
-- Under the bundles, a row of 2x coins boosts (Config.CoinShop.Boosts, granted by BoostService):
-- the timed one shows its time left, the lifetime one says Owned once bought.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)
local ShopController = require(script.Parent.ShopController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local new = Theme.new
local CS = Config.CoinShop

local CoinShopController = {}

local SHEET_SIZE = Vector2.new(900, 570)
local CARD = Vector2.new(156, 300)
local ART_H = 120
local BOOST = Vector2.new(400, 76)
local SUBTITLE = "Coins go straight to your wallet."

local sheet: any -- Theme.Sheet
local walletLabel: TextLabel
local cards: { [string]: { root: GuiObject, art: GuiObject, buy: TextButton } } = {}
local backToShop = false -- opened from the shop's Buy: return there after a purchase
local boostCards: { [string]: { root: GuiObject, status: TextLabel, buy: TextButton } } = {}
local boost = { untilTime = 0, forever = false } -- profile.boost from the server

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

-- Robux buttons only after the tutorial and some play time (PurchaseService sets RobuxOk).
function CoinShopController.unlocked(): boolean
	return player:GetAttribute("RobuxOk") == true
end

-- "1,280"
local function commas(n: number): string
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (s:gsub("^,", ""))
end

-- Bonus over the smallest bundle's coins-per-Robux, e.g. "+40% bonus" (nil for none).
local function bonusText(bundle: any): string?
	local base = CS.Bundles[1]
	local rate = base.Coins / base.Robux
	local extra = math.floor((bundle.Coins / bundle.Robux / rate - 1) * 100 + 0.5)
	return if extra >= 5 then ("+%d%% bonus"):format(extra) else nil
end

-- A heap of coins that grows with the bundle: `rows` rows of overlapping coins, wider at the bottom.
local function drawHeap(parent: GuiObject, rows: number)
	local size = 34
	for r = 1, rows do
		local count = rows - r + 2
		local y = -12 - (r - 1) * (size * 0.5)
		for i = 1, count do
			local x = (i - (count + 1) / 2) * size * 0.72
			Theme.coin(parent, size, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, x, 1, y),
				ZIndex = parent.ZIndex + r,
			})
		end
	end
end

local function buy(bundle: any)
	if bundle.ProductId <= 0 then
		SoundController.play("UIError")
		HUDController.hint("This bundle isn't on sale yet", 1.6)
		return
	end
	MarketplaceService:PromptProductPurchase(player, bundle.ProductId)
end

-- "12:05 left"
local function timeLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%d:%02d:%02d left"):format(seconds // 3600, (seconds // 60) % 60, seconds % 60)
	end
	return ("%d:%02d left"):format(seconds // 60, seconds % 60)
end

local function renderBoosts()
	local left = boost.untilTime - Workspace:GetServerTimeNow()
	for _, def in CS.Boosts do
		local card = boostCards[def.Id]
		if not card then
			continue
		end
		if def.Forever then
			card.status.Text = if boost.forever then "Owned: every match pays double" else "Every match pays double"
			card.buy.Visible = not boost.forever
		elseif boost.forever then
			card.status.Text = "You already have 2x forever"
			card.buy.Visible = false
		else
			card.status.Text = if left > 0 then "Active: " .. timeLeft(left) else "Matches pay double"
			card.buy.Visible = true
		end
	end
end

local function boostCard(parent: Instance, def: any, order: number)
	local root = new("Frame", {
		Name = def.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(BOOST.X, BOOST.Y),
		BackgroundColor3 = T.surface,
		ZIndex = 5,
	}, parent)
	Theme.corner(root, Theme.Radius.M)
	Theme.stroke(root, T.outline, Theme.StrokeToy)
	-- the "2x" disc
	local disc = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = if def.Forever then T.sun else T.leaf,
		ZIndex = 6,
	}, root)
	Theme.round(disc)
	Theme.stroke(disc, T.outline, Theme.StrokeToy)
	Theme.label(disc, {
		Size = UDim2.fromScale(1, 1),
		Text = ("%dx"):format(CS.BoostMultiplier),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
	}, 2)
	Theme.text(root, 20, {
		Position = UDim2.fromOffset(78, 12),
		Size = UDim2.new(1, -200, 0, 24),
		FontFace = Theme.DisplayFace,
		Text = ("%s · %s"):format(def.Name, def.Detail),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local status = Theme.body(root, {
		Position = UDim2.fromOffset(78, 42),
		Size = UDim2.new(1, -200, 0, 18),
		FontFace = Theme.TextFace,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local button = Theme.button(root, ("R$ %d"):format(def.Robux), "primary", {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(104, 48),
		ZIndex = 8,
	})
	button.Activated:Connect(function()
		buy(def)
	end)
	boostCards[def.Id] = { root = root, status = status, buy = button }
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(def.ProductId, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			Theme.setText(button, ("R$ %d"):format(info.PriceInRobux))
		end
	end)
end

local function bundleCard(parent: Instance, bundle: any, order: number, tone: Color3)
	local root = new("Frame", {
		Name = bundle.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = T.surface,
		ZIndex = 5,
	}, parent)
	Theme.corner(root, Theme.Radius.M)
	Theme.stroke(root, T.outline, Theme.StrokeToy)
	-- the art band in the card's fill, rounded on top only, with an outline under it
	local art = new("Frame", {
		Name = "Art",
		Size = UDim2.new(1, 0, 0, ART_H),
		BackgroundColor3 = tone,
		ZIndex = 6,
	}, root)
	Theme.corner(art, Theme.Radius.M)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.Radius.M),
		Size = UDim2.new(1, 0, 0, Theme.Radius.M),
		BackgroundColor3 = tone,
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
	local heap = new("Frame", {
		Name = "Heap",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
	}, art)
	drawHeap(heap, order)
	if bundle.Tag then
		Theme.sticker(root, bundle.Tag, if order == #CS.Bundles then T.sun else T.candy, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			ZIndex = 20,
		})
	end
	-- the amount: a coin and the number, big
	local amount = new("Frame", {
		Name = "Amount",
		Position = UDim2.fromOffset(0, ART_H + 12),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, amount)
	Theme.coin(amount, 26, { LayoutOrder = 1, ZIndex = 8 })
	Theme.text(amount, 28, {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		FontFace = Theme.DisplayFace,
		Text = commas(bundle.Coins),
		ZIndex = 8,
	})
	Theme.body(root, {
		Name = "Name",
		Position = UDim2.fromOffset(10, ART_H + 50),
		Size = UDim2.new(1, -20, 0, 18),
		FontFace = Theme.TextFace,
		Text = bundle.Name,
		ZIndex = 7,
	})
	local bonus = bonusText(bundle)
	if bonus then
		Theme.text(root, 16, {
			Name = "Bonus",
			Position = UDim2.fromOffset(10, ART_H + 72),
			Size = UDim2.new(1, -20, 0, 20),
			Text = bonus,
			TextColor3 = T.success,
			ZIndex = 7,
		})
	end
	local button = Theme.button(root, ("R$ %d"):format(bundle.Robux), "primary", {
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 48),
		ZIndex = 8,
	})
	if bundle.ProductId <= 0 then
		Theme.setText(button, "Soon")
		Theme.recolor(button, "secondary")
	end
	button.Activated:Connect(function()
		buy(bundle)
	end)
	cards[bundle.Id] = { root = root, art = art, buy = button }
	-- the real price comes from the product itself (it can be changed on the dashboard)
	if bundle.ProductId > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(bundle.ProductId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				Theme.setText(button, ("R$ %d"):format(info.PriceInRobux))
			end
		end)
	end
end

local function build()
	sheet = ShopController.sheet("Coins", "Get coins", SHEET_SIZE, SUBTITLE, {
		tone = T.peach,
		glyph = "coin",
	})
	sheet.close.Activated:Connect(function()
		CoinShopController.open(false)
	end)
	-- wallet: a coin and your balance, next to the close button (as in the shop)
	local wallet = Theme.well(sheet.header, {
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
	local row = new("Frame", {
		Name = "Bundles",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, sheet.body)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i, bundle in CS.Bundles do
		bundleCard(row, bundle, i, Theme.Fills[(i - 1) % #Theme.Fills + 1])
	end
	local boosts = new("Frame", {
		Name = "Boosts",
		Position = UDim2.fromOffset(0, 16 + CARD.Y + Theme.Space.L),
		Size = UDim2.new(1, 0, 0, BOOST.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, sheet.body)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, boosts)
	for i, def in CS.Boosts do
		boostCard(boosts, def, i)
	end
	renderBoosts()
	local action = ShopController.addAction("Coins", T.peach, "coin", 5, function()
		CoinShopController.open(not ShopController.isOpen(sheet.frame))
	end)
	local function gate()
		action.Visible = CoinShopController.unlocked()
	end
	player:GetAttributeChangedSignal("RobuxOk"):Connect(gate)
	gate()
	ShopController.onCloseAll(function()
		CoinShopController.open(false)
	end)
end

-- Open or close the sheet. `need` (coins short) is set when the shop sent you here.
function CoinShopController.open(on: boolean, need: number?)
	if on and not (inHub() and CoinShopController.unlocked()) then
		return
	end
	local f = sheet.frame
	if on then
		if not ShopController.isOpen(f) then
			SoundController.play("UIOpen")
		end
		ShopController.closeAll()
		backToShop = need ~= nil
		sheet.subtitle.Text = if need
			then ("You need %s more coins for that. Grab a bundle!"):format(commas(need))
			else SUBTITLE
		Theme.show(f, ShopController.getBackdrop())
		-- point at the smallest bundle that covers what's missing (or the first one)
		local pick = CS.Bundles[1]
		if need then
			for _, bundle in CS.Bundles do
				pick = bundle
				if bundle.Coins >= need then
					break
				end
			end
		end
		local card = cards[pick.Id]
		if card then
			Theme.focus(card.buy)
			if need then
				task.delay(Theme.Motion.Base, function()
					Theme.pop(card.root, 1.12, Theme.Motion.Slow)
				end)
			end
		end
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		Theme.hide(f, ShopController.getBackdrop())
	end
end

function CoinShopController.init()
	build()
end

function CoinShopController.start()
	Net.on("Profile", function(d)
		walletLabel.Text = commas(d.coins or 0)
		if type(d.boost) == "table" then
			boost = { untilTime = tonumber(d.boost.untilTime) or 0, forever = d.boost.forever == true }
			renderBoosts()
		end
	end)
	Net.on("BoostBought", function(d)
		SoundController.play("Purchase")
		local card = boostCards[tostring(d.id)]
		if card then
			Theme.pop(card.root, 1.1, Theme.Motion.Slow)
		end
		HUDController.hint(("%dx coins is on!"):format(CS.BoostMultiplier), 2)
	end)
	-- the server granted a bundle: celebrate, then (if the shop sent you) go back to it
	Net.on("CoinsBought", function(d)
		local coins = tonumber(d.coins) or 0
		SoundController.play("Purchase")
		HUDController.coinPop(coins)
		local card = cards[tostring(d.id)]
		if card then
			Theme.pop(card.art, 1.25, Theme.Motion.Slow)
		end
		if backToShop and ShopController.isOpen(sheet.frame) and inHub() then
			backToShop = false
			task.delay(0.6, function()
				if ShopController.isOpen(sheet.frame) and inHub() then
					CoinShopController.open(false)
					ShopController.openShop(true)
				end
			end)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		if userId == player.UserId and not purchased then
			SoundController.play("UIBack")
		end
	end)
	local nextTick = 0
	RunService.RenderStepped:Connect(function()
		if not inHub() and sheet.frame.Visible then
			CoinShopController.open(false)
		end
		-- the timed boost's countdown, once a second while the sheet is up
		if sheet.frame.Visible and os.clock() >= nextTick then
			nextTick = os.clock() + 1
			renderBoosts()
		end
	end)
end

return CoinShopController
