--!strict
-- The Coins sheet: bundles of coins sold for Robux (Config.CoinShop). Each card is a developer
-- product; Buy opens Roblox's own purchase pop-up, and the server (PurchaseService) adds the coins
-- once the receipt is in. The shop sends players here when they press Buy on something they can't
-- afford yet: the sheet then says how many coins they're short and points at the smallest bundle
-- that covers it, and after a purchase takes them straight back to the shop.
--
-- Value tags (shared/BundleValue, all worked out from Config and the Catalog): each coin bundle shows
-- "+X% BONUS" over the smallest bundle's coins per Robux, the best ratio wears a BEST VALUE ribbon,
-- and each limited-time offer says what it's "Worth" in coins.
--
-- Under the bundles, a row of 2x coins boosts (Config.CoinShop.Boosts, granted by BoostService):
-- the timed one shows its time left, the lifetime one says Owned once bought.
--
-- Above the bundles, while one is on sale, a strip for each limited-time cosmetic bundle
-- (Config.CoinShop.Offers, granted by PurchaseService): what's in it, the time left and Buy, or
-- Owned once you have everything in it. It hides itself at the offer's End; the sheet grows to fit
-- it and scales down so it takes no more of the screen than without it. The same strip also sits at
-- the top of the Shop's shelf while you don't own it yet (its items are on the shelf too).
--
-- The Coins button sits at the top of the action column, above Shop.
--
-- Clicking a bundle's strip (anywhere but Buy), or any of its items on the Shop's shelf, opens the
-- bundle's own page: every item in it as a card, plus its coins, with Buy and a Back button.
--
-- The same strip stack also carries the one-time Starter Pack (Config.CoinShop.Starter, until it's
-- bought) and the VIP game pass (until owned), at most MAX_STRIPS at once, limited offers first.
-- The lifetime 2x boost card prompts the DoubleCoins game pass once that pass exists.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local BundleValue = require(Shared.BundleValue)
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
local OFFER = Vector2.new(816, 96)
local MAX_STRIPS = 2 -- offer, Starter Pack and VIP strips shown on the Coins sheet at once
local SUBTITLE = "Coins go straight to your wallet."
-- "Witch's Brew ball skin" in an offer's contents line
local KIND = { BallSkin = "ball skin", Trail = "trail", Title = "title", Finisher = "finisher", Pose = "pose" }

local sheet: any -- Theme.Sheet
local walletLabel: TextLabel
type BundleCard = {
	root: GuiObject,
	art: GuiObject,
	buy: TextButton,
	bonus: GuiObject,
	ribbon: GuiObject,
	tag: GuiObject?,
}
local cards: { [string]: BundleCard } = {}
local bundleRobux: { [string]: number } = {} -- a coin bundle's real Robux price, from its product
local backToShop = false -- opened from the shop's Buy: return there after a purchase
local boostCards: { [string]: { root: GuiObject, status: TextLabel, buy: TextButton } } = {}
local boost = { untilTime = 0, forever = false } -- profile.boost from the server
-- where an offer card sits: the Coins sheet's strip, the Shop shelf's banner or the Bundles sheet
type OfferCard = { offer: any, root: GuiObject, status: TextLabel, buy: TextButton, place: string }
local offerCards: { OfferCard } = {}
local shopBanners = false -- built the Shop shelf's banners yet
local owned: { [string]: boolean } = {} -- profile.owned from the server
local starterBought = false -- profile.starter from the server
local vipStrip: { root: GuiObject, buy: TextButton }? = nil
local offersShown: number? = nil -- how many strips are up (nil until the first layout)
local offerRow: Frame
local bundleRow: Frame
local boostRow: Frame
local bundlesSheet: any -- Theme.Sheet: the limited-time bundles on their own
-- a bundle's page: every item in it as a card, plus its coins, with Buy at the bottom
local PREVIEW_SIZE = Vector2.new(880, 612)
local previewSheet: any -- Theme.Sheet
type Preview = {
	offer: any?,
	back: (() -> ())?,
	grid: ScrollingFrame,
	status: TextLabel,
	summary: TextLabel,
	buy: TextButton,
	backButton: TextButton,
	cards: { [string]: GuiObject },
}
local preview: Preview = {} :: any
local prices: { [string]: number } = {} -- an offer's real Robux price, from its product

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

-- Each bundle at the price it really sells for: Config's Robux until the product's price loads.
local function pricedBundles(): { { Coins: number, Robux: number } }
	local list = {}
	for _, bundle in CS.Bundles do
		table.insert(list, { Coins = bundle.Coins, Robux = bundleRobux[bundle.Id] or bundle.Robux })
	end
	return list
end

-- The "+X% BONUS" pills and the BEST VALUE ribbon, from coins per Robux against the smallest
-- bundle (BundleValue). Re-run whenever a real price loads, so the tags always match the buttons.
local function renderValue()
	local list = pricedBundles()
	local best = BundleValue.best(list)
	for i, bundle in CS.Bundles do
		local card = cards[bundle.Id]
		if not card then
			continue
		end
		local extra = BundleValue.bonus(list[i], list[1])
		card.bonus.Visible = extra > 0
		Theme.setText(card.bonus, ("+%d%% BONUS"):format(extra))
		card.ribbon.Visible = i == best
		if card.tag then
			card.tag.Visible = i ~= best -- the ribbon takes the sticker's spot
		end
	end
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

-- A card's uploaded icon (Image asset id), filling `parent` and keeping its square shape.
local function drawIcon(parent: GuiObject, image: number, inset: number)
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
		BackgroundTransparency = 1,
		Image = "rbxassetid://" .. image,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = parent.ZIndex + 2,
	}, parent)
end

-- A loud outlined pill of paper text on `tone` ("+48% BONUS", "WORTH 21,500 COINS"), sized to its text.
local function valuePill(parent: Instance, text: string, tone: Color3, size: number, props: { [string]: any }): Frame
	local f = new("Frame", {
		Name = "Value",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 10),
		BackgroundColor3 = tone,
		BorderSizePixel = 0,
	}, nil)
	for k, v in props do
		(f :: any)[k] = v
	end
	Theme.round(f)
	Theme.stroke(f, T.outline, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, f)
	Theme.label(f, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextScaled = false,
		TextSize = size,
		Text = text,
		ZIndex = f.ZIndex + 1,
	}, 2)
	f.Parent = parent
	return f
end

local function buy(bundle: any)
	if bundle.ProductId <= 0 then
		SoundController.play("UIError")
		HUDController.hint("This bundle isn't on sale yet", 1.6)
		return
	end
	MarketplaceService:PromptProductPurchase(player, bundle.ProductId)
end

-- Prompt a game pass (Config.CoinShop.Passes id). Studio shows passes before they exist.
local function buyPass(id: string)
	local pass = CS.Passes[id]
	if pass.PassId <= 0 then
		SoundController.play("UIError")
		HUDController.hint("This pass isn't on sale yet", 1.6)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
end

-- A pass's card Buy button shows its real price once it loads.
local function passPrice(id: string, button: TextButton)
	local pass = CS.Passes[id]
	if pass.PassId <= 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(pass.PassId, Enum.InfoType.GamePass)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			Theme.setText(button, ("R$ %d"):format(info.PriceInRobux))
		end
	end)
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
	-- the "2x" disc, or the boost's uploaded icon in its place
	local disc = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = if def.Forever then T.sun else T.leaf,
		BackgroundTransparency = if (def.Image or 0) > 0 then 1 else 0,
		ZIndex = 6,
	}, root)
	if (def.Image or 0) > 0 then
		drawIcon(disc, def.Image, -4)
	else
		Theme.round(disc)
		Theme.stroke(disc, T.outline, Theme.StrokeToy)
		Theme.label(disc, {
			Size = UDim2.fromScale(1, 1),
			Text = ("%dx"):format(CS.BoostMultiplier),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 7,
		}, 2)
	end
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
	-- the lifetime boost is sold as its game pass once that pass exists
	local pass = if def.Pass and CS.Passes[def.Pass].PassId > 0 then def.Pass else nil
	button.Activated:Connect(function()
		if pass then
			buyPass(pass)
		else
			buy(def)
		end
	end)
	boostCards[def.Id] = { root = root, status = status, buy = button }
	if pass then
		Theme.setText(button, ("R$ %d"):format(CS.Passes[pass].Robux))
		passPrice(pass, button)
		return
	end
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
	if (bundle.Image or 0) > 0 then
		drawIcon(heap, bundle.Image, 6)
	else
		drawHeap(heap, order)
	end
	-- Config's own "Best value" tag is skipped: the ribbon below goes on whichever bundle really
	-- gives the most coins per Robux, so the two can never disagree.
	local tag: GuiObject? = nil
	if bundle.Tag and string.lower(bundle.Tag) ~= "best value" then
		tag = Theme.sticker(root, bundle.Tag, T.candy, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			ZIndex = 20,
		})
	end
	local ribbon = valuePill(root, "★ BEST VALUE", T.joyRed, 18, {
		Name = "BestValue",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 2),
		Rotation = -4,
		Visible = false,
		ZIndex = 21,
	})
	Theme.stroke(ribbon, T.outline, Theme.StrokeToy)
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
	-- filled in by renderValue (hidden on the smallest bundle, which is the baseline)
	local bonus = valuePill(root, "", T.leaf, 16, {
		Name = "Bonus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(CARD.X / 2, ART_H + 72),
		Visible = false,
		ZIndex = 8,
	})
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
	cards[bundle.Id] = { root = root, art = art, buy = button, bonus = bonus, ribbon = ribbon, tag = tag }
	-- the real price comes from the product itself (it can be changed on the dashboard); the bonus
	-- tags are worked out again from it
	if bundle.ProductId > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(bundle.ProductId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				Theme.setText(button, ("R$ %d"):format(info.PriceInRobux))
				bundleRobux[bundle.Id] = info.PriceInRobux
				renderValue()
			end
		end)
	end
end

-- Limited-time bundles ------------------------------------------------------------------------------

local function stamp(iso: string): number
	return DateTime.fromIsoDate(iso).UnixTimestamp
end

-- "2d 5h left", or the clock under a day
local function endsIn(seconds: number): string
	if seconds >= 86400 then
		return ("%dd %dh left"):format(seconds // 86400, (seconds // 3600) % 24)
	end
	return timeLeft(seconds)
end

local function offerOwned(offer: any): boolean
	if offer.Once then
		return starterBought -- the Starter Pack: bought once, even if its items came another way
	end
	for _, id in offer.Items do
		if not owned[id] then
			return false
		end
	end
	return true
end

-- A one-time offer (the Starter Pack) is always on sale; a limited one only inside its window.
local function offerOn(offer: any, now: number): boolean
	return offer.Once == true or Catalog.offerLive(offer, now)
end

-- The status line under an offer's name.
local function offerStatus(offer: any, now: number): string
	if offerOwned(offer) then
		return "Owned: equip it in the Shop"
	elseif offer.Once then
		return "One-time offer · only once per account"
	end
	return "Limited time · " .. endsIn(stamp(offer.End) - now)
end

-- Products that don't exist yet stay off the live game; Studio shows them (with "Soon") to test.
local function onSale(id: number): boolean
	return id > 0 or RunService:IsStudio()
end

-- Show each offer only inside its window; the strip stack (and the room the sheet makes for it)
-- grows with the strips showing, up to MAX_STRIPS.
local offerCard: (parent: Instance, offer: any, order: number, place: string) -> ()
local function renderOffers()
	local shelf = ShopController.shelf()
	if not shopBanners and shelf then
		shopBanners = true
		for _, offer in CS.Offers do
			offerCard(shelf, offer, 0, "Shop")
		end
	end
	local now = Workspace:GetServerTimeNow()
	local strips = 0
	for _, card in offerCards do
		local offer = card.offer
		local live = offerOn(offer, now)
		local have = offerOwned(offer)
		if card.place == "Shop" then
			-- (and not while the shelf shows only what you own)
			card.root.Visible = live and not have and CoinShopController.unlocked() and not ShopController.ownedOnly
		elseif card.place == "Coins" then
			-- the Starter Pack leaves once bought; a limited offer stays up saying Owned
			local show = live and not (offer.Once and have) and onSale(offer.ProductId) and strips < MAX_STRIPS
			card.root.Visible = show
			strips += if show then 1 else 0
		else
			card.root.Visible = live
		end
		if live then
			card.status.Text = offerStatus(offer, now)
			card.buy.Visible = not have
		end
	end
	if vipStrip then
		local show = player:GetAttribute("Pass_VIP") ~= true and onSale(CS.Passes.VIP.PassId) and strips < MAX_STRIPS
		vipStrip.root.Visible = show
		strips += if show then 1 else 0
	end
	local any = strips > 0
	if strips ~= offersShown then
		offersShown = strips
		local shift = strips * (OFFER.Y + Theme.Space.L)
		offerRow.Size = UDim2.new(1, 0, 0, math.max(0, shift - Theme.Space.L))
		offerRow.Visible = any
		bundleRow.Position = UDim2.fromOffset(0, 16 + shift)
		boostRow.Position = UDim2.fromOffset(0, 16 + shift + CARD.Y + Theme.Space.L)
		local h = SHEET_SIZE.Y + shift
		sheet.frame.Size = UDim2.fromOffset(SHEET_SIZE.X, h)
		Theme.autoScale(sheet.frame, SHEET_SIZE.Y / h) -- no taller on screen than without the strip
	end
end

local function buyOffer(offer: any)
	if not offerOn(offer, Workspace:GetServerTimeNow()) then
		SoundController.play("UIError")
		HUDController.hint("This offer has ended", 1.6)
		renderOffers()
		return
	end
	buy(offer)
end

function offerCard(parent: Instance, offer: any, order: number, place: string)
	local root = new("Frame", {
		Name = offer.Id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(OFFER.X, OFFER.Y),
		BackgroundColor3 = T.surface,
		Visible = false,
		ZIndex = 5,
	}, parent)
	Theme.corner(root, Theme.Radius.M)
	Theme.stroke(root, T.outline, Theme.StrokeToy)
	-- clicking the strip anywhere but Buy opens the bundle's page; Back there returns here
	local open = new("TextButton", {
		Name = "Open",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, root)
	open.Activated:Connect(function()
		SoundController.play("UIClick")
		CoinShopController.openPreview(offer, function()
			if place == "Shop" then
				ShopController.openShop(true)
			elseif place == "Bundles" then
				CoinShopController.openBundles(true)
			else
				CoinShopController.open(true)
			end
		end)
	end)
	-- the art disc: the offer's uploaded image, or a pumpkin until there is one
	local disc = new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = T.peach,
		BackgroundTransparency = if (offer.Image or 0) > 0 then 1 else 0,
		ZIndex = 6,
	}, root)
	if (offer.Image or 0) > 0 then
		drawIcon(disc, offer.Image, -4)
	else
		Theme.round(disc)
		Theme.stroke(disc, T.outline, Theme.StrokeToy)
		Theme.text(disc, 40, {
			Size = UDim2.fromScale(1, 1),
			Text = offer.Glyph or "🎃",
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 7,
		})
	end
	if offer.Tag then
		Theme.sticker(root, offer.Tag, T.candy, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(48, 0),
			ZIndex = 20,
		})
	end
	Theme.text(root, 22, {
		Position = UDim2.fromOffset(98, 10),
		Size = UDim2.new(1, -440, 0, 26),
		FontFace = Theme.DisplayFace,
		Text = offer.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	-- what it's worth: every item's catalog Price (their value) plus the coins (BundleValue.worth)
	valuePill(root, ("WORTH %s COINS"):format(commas(BundleValue.worth(offer, Catalog))), T.sun, 16, {
		Name = "Worth",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -146, 0, 10),
		Rotation = -2,
		ZIndex = 9,
	})
	-- what's inside: "Witch's Brew ball skin · Ectoplasm trail · ... · +5,000 coins"
	-- (just the names once there are more than four, so the line still fits)
	local parts = {}
	for _, id in offer.Items do
		local item = Catalog.get(id)
		if item then
			table.insert(
				parts,
				if #offer.Items > 4 then item.Name else ("%s %s"):format(item.Name, KIND[item.Category] or "")
			)
		end
	end
	table.insert(parts, ("+%s coins"):format(commas(offer.Coins)))
	for _, b in CS.Boosts do
		if b.Id == offer.Boost then
			table.insert(parts, ("%dx coins for %s"):format(CS.BoostMultiplier, b.Detail))
		end
	end
	local contents = Theme.body(root, {
		Position = UDim2.fromOffset(98, 40),
		Size = UDim2.new(1, -240, 0, 18),
		FontFace = Theme.TextFace,
		Text = table.concat(parts, " · "),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})
	new("UITextSizeConstraint", { MaxTextSize = 18 }, contents)
	local status = Theme.text(root, 16, {
		Position = UDim2.fromOffset(98, 64),
		Size = UDim2.new(1, -240, 0, 20),
		Text = "",
		TextColor3 = T.success,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	-- The price is shown once, as it is. There's deliberately no crossed-out "was R$ ..." price: none
	-- of these bundles has ever sold for more Robux, and a strike-through price that never existed is
	-- a made-up discount that misleads players (the fake "reference price" consumer rules ban). Add one
	-- only if the product really sold at that higher price first, and take the number from that.
	local button = Theme.button(root, ("R$ %d"):format(offer.Robux), "primary", {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(120, 52),
		ZIndex = 8,
	})
	if offer.ProductId <= 0 then
		Theme.setText(button, "Soon")
		Theme.recolor(button, "secondary")
	end
	button.Activated:Connect(function()
		buyOffer(offer)
	end)
	Theme.text(root, 14, {
		Name = "SeeInside",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -140, 1, -8),
		Size = UDim2.fromOffset(110, 18),
		Text = "See what's inside ›",
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
	})
	table.insert(offerCards, { offer = offer, root = root, status = status, buy = button, place = place })
	if offer.ProductId > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(offer.ProductId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[offer.Id] = info.PriceInRobux
				Theme.setText(button, ("R$ %d"):format(info.PriceInRobux))
			end
		end)
	end
end

-- The VIP game pass as a strip like an offer's: what it gives and Buy. It leaves once you own it.
local function vipCard(parent: Instance, order: number)
	local vip = CS.Passes.VIP
	local root = new("Frame", {
		Name = "VIP",
		LayoutOrder = order,
		Size = UDim2.fromOffset(OFFER.X, OFFER.Y),
		BackgroundColor3 = T.surface,
		Visible = false,
		ZIndex = 5,
	}, parent)
	Theme.corner(root, Theme.Radius.M)
	Theme.stroke(root, T.outline, Theme.StrokeToy)
	local disc = new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = T.sun,
		BackgroundTransparency = if (vip.Image or 0) > 0 then 1 else 0,
		ZIndex = 6,
	}, root)
	if (vip.Image or 0) > 0 then
		drawIcon(disc, vip.Image, -4)
	else
		Theme.round(disc)
		Theme.stroke(disc, T.outline, Theme.StrokeToy)
		Theme.label(disc, {
			Size = UDim2.fromScale(1, 1),
			Text = "VIP",
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 7,
		}, 2)
	end
	Theme.sticker(root, "Forever", T.candy, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(48, 0),
		ZIndex = 20,
	})
	Theme.text(root, 22, {
		Position = UDim2.fromOffset(98, 10),
		Size = UDim2.new(1, -240, 0, 26),
		FontFace = Theme.DisplayFace,
		Text = vip.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local perks = Theme.body(root, {
		Position = UDim2.fromOffset(98, 40),
		Size = UDim2.new(1, -240, 0, 18),
		FontFace = Theme.TextFace,
		Text = ("A gold VIP tag on your name · a free spin and %s coins every day you play"):format(
			commas(vip.DailyCoins)
		),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	})
	new("UITextSizeConstraint", { MaxTextSize = 18 }, perks)
	Theme.text(root, 16, {
		Position = UDim2.fromOffset(98, 64),
		Size = UDim2.new(1, -240, 0, 20),
		Text = "Game pass · yours forever",
		TextColor3 = T.success,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	local button = Theme.button(root, ("R$ %d"):format(vip.Robux), "primary", {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(120, 52),
		ZIndex = 8,
	})
	if vip.PassId <= 0 then
		Theme.setText(button, "Soon")
		Theme.recolor(button, "secondary")
	end
	button.Activated:Connect(function()
		buyPass("VIP")
	end)
	passPrice("VIP", button)
	vipStrip = { root = root, buy = button }
end

-- Whether any limited-time offer is on sale right now.
local function anyOfferLive(): boolean
	local now = Workspace:GetServerTimeNow()
	for _, offer in CS.Offers do
		if Catalog.offerLive(offer, now) then
			return true
		end
	end
	return false
end

-- Bundle page ----------------------------------------------------------------------------------------
-- Opened by clicking a bundle's strip (Shop shelf, Bundles or Coins sheet) or any of its items on the
-- shelf: a sheet like the Shop's with a card for everything in the bundle and one for its coins, the
-- time left and Buy. Back returns to wherever it was opened from.

local function renderPreviewStatus()
	local offer = preview.offer
	if not offer then
		return
	end
	local have = offerOwned(offer)
	preview.status.Text = offerStatus(offer, Workspace:GetServerTimeNow())
	preview.buy.Visible = not have
	if offer.ProductId <= 0 then
		Theme.setText(preview.buy, "Soon")
		Theme.recolor(preview.buy, "secondary")
	else
		Theme.setText(preview.buy, ("Buy bundle · R$ %d"):format(prices[offer.Id] or offer.Robux))
		Theme.recolor(preview.buy, "primary")
	end
end

-- The coins that come with a bundle, as a card like the items' (a heap on a peach band).
local function coinsCard(parent: Instance, coins: number, order: number): Frame
	local size = ShopController.CONTENTS_CARD
	local artH = size.Y - 70
	local face = new("Frame", {
		Name = "Coins",
		LayoutOrder = order,
		BackgroundColor3 = T.surface,
		ZIndex = 5,
	}, parent)
	Theme.corner(face, Theme.Radius.M)
	Theme.stroke(face, T.outline, Theme.StrokeToy)
	local art = new("Frame", {
		Name = "Art",
		Size = UDim2.new(1, 0, 0, artH),
		BackgroundColor3 = T.peach,
		ZIndex = 6,
	}, face)
	Theme.corner(art, Theme.Radius.M)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.Radius.M),
		Size = UDim2.new(1, 0, 0, Theme.Radius.M),
		BackgroundColor3 = T.peach,
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
	drawHeap(heap, 3)
	local name = Theme.label(face, {
		Name = "Name",
		Position = UDim2.fromOffset(10, artH + 8),
		Size = UDim2.new(1, -20, 0, 26),
		Text = ("+%s coins"):format(commas(coins)),
		ZIndex = 7,
	}, 0)
	new("UITextSizeConstraint", { MaxTextSize = 22 }, name)
	Theme.body(face, {
		Name = "Kind",
		Position = UDim2.fromOffset(10, artH + 36),
		Size = UDim2.new(1, -20, 0, 20),
		FontFace = Theme.TextFace,
		Text = "Straight to your wallet",
		TextColor3 = T.inkMuted,
		ZIndex = 7,
	})
	return face
end

local function fillPreview(offer: any)
	for _, child in preview.grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(preview.cards)
	-- after a finisher preview, come back to this page (still going Back to where it came from)
	local back = preview.back
	local function reopen()
		CoinShopController.openPreview(offer, back)
	end
	for i, id in offer.Items do
		local item = Catalog.get(id)
		if item then
			preview.cards[id] = ShopController.contentsCard(item, i, preview.grid, reopen)
		end
	end
	if (offer.Coins or 0) > 0 then
		preview.cards.Coins = coinsCard(preview.grid, offer.Coins, #offer.Items + 1)
	end
	preview.summary.Text = ("%d items + %s coins · worth %s"):format(
		#offer.Items,
		commas(offer.Coins or 0),
		commas(BundleValue.worth(offer, Catalog))
	)
end

local function buildPreview()
	previewSheet = ShopController.sheet("BundlePreview", "Bundle", PREVIEW_SIZE, nil, {
		tone = T.sun,
		glyph = "pumpkin",
	})
	previewSheet.close.Activated:Connect(function()
		CoinShopController.openPreview(nil)
	end)
	local body = previewSheet.body :: Frame
	-- top bar: Back, and what's in it
	local backButton = Theme.button(body, "‹ Back", "secondary", {
		Name = "Back",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(120, 44),
		ZIndex = 5,
	})
	backButton.Activated:Connect(function()
		local back = preview.back
		CoinShopController.openPreview(nil)
		if back then
			back()
		end
	end)
	local summary = Theme.text(body, 20, {
		Name = "Summary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -140, 0, 44),
		FontFace = Theme.DisplayFace,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
	})
	-- the contents: four-wide cards, scrolling if a bundle has more than fits
	local grid = new("ScrollingFrame", {
		Name = "Contents",
		Position = UDim2.fromOffset(-8, 52),
		Size = UDim2.new(1, 16, 1, -52 - 76),
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
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, grid)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(ShopController.CONTENTS_CARD.X, ShopController.CONTENTS_CARD.Y),
		CellPadding = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		FillDirectionMaxCells = 4,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	-- footer: the time left and Buy
	local footer = new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -8),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, body)
	local status = Theme.text(footer, 18, {
		Name = "Status",
		Size = UDim2.new(1, -280, 1, 0),
		Text = "",
		TextColor3 = T.success,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local buyButton = Theme.button(footer, "Buy bundle", "primary", {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(260, 56),
		ZIndex = 6,
	})
	buyButton.Activated:Connect(function()
		if preview.offer then
			buyOffer(preview.offer)
		end
	end)
	preview.grid = grid
	preview.status = status
	preview.summary = summary
	preview.buy = buyButton
	preview.backButton = backButton
	preview.cards = {}
	ShopController.onCloseAll(function()
		CoinShopController.openPreview(nil)
	end)
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
	offerRow = new("Frame", {
		Name = "Offers",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, OFFER.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, sheet.body)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, offerRow)
	-- limited offers first, then the Starter Pack, then VIP (renderOffers shows the first MAX_STRIPS)
	for i, offer in CS.Offers do
		offerCard(offerRow, offer, i, "Coins")
	end
	offerCard(offerRow, CS.Starter, #CS.Offers + 1, "Coins")
	vipCard(offerRow, #CS.Offers + 2)
	local row = new("Frame", {
		Name = "Bundles",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, CARD.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, sheet.body)
	bundleRow = row
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i, bundle in CS.Bundles do
		bundleCard(row, bundle, i, Theme.Fills[(i - 1) % #Theme.Fills + 1])
	end
	renderValue()
	local boosts = new("Frame", {
		Name = "Boosts",
		Position = UDim2.fromOffset(0, 16 + CARD.Y + Theme.Space.L),
		Size = UDim2.new(1, 0, 0, BOOST.Y),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, sheet.body)
	boostRow = boosts
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
	renderOffers()
	local action = ShopController.addAction("Coins", T.peach, "coin", 0, function()
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

	-- the Bundles sheet: every limited-time offer, one strip under another
	local pad = Theme.Space.XL
	bundlesSheet = ShopController.sheet(
		"Bundles",
		"Limited bundles",
		Vector2.new(OFFER.X + pad * 2, 76 + 12 + 32 + 16 + #CS.Offers * (OFFER.Y + Theme.Space.L) + pad),
		"Exclusive cosmetics plus coins, only for a short time.",
		{ tone = T.sun, glyph = "pumpkin" }
	)
	bundlesSheet.close.Activated:Connect(function()
		CoinShopController.openBundles(false)
	end)
	local list = new("Frame", {
		Name = "Offers",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 1, -16),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, bundlesSheet.body)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.L),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	for i, offer in CS.Offers do
		offerCard(list, offer, i, "Bundles")
	end
	ShopController.onCloseAll(function()
		CoinShopController.openBundles(false)
	end)
	buildPreview()
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
		renderOffers()
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

-- Open or close the Bundles sheet (the pumpkin button).
function CoinShopController.openBundles(on: boolean)
	local f = bundlesSheet.frame
	if on then
		if not (inHub() and CoinShopController.unlocked() and anyOfferLive()) then
			return
		end
		if not ShopController.isOpen(f) then
			SoundController.play("UIOpen")
		end
		ShopController.closeAll()
		renderOffers()
		Theme.show(f, ShopController.getBackdrop())
		for _, card in offerCards do
			if card.place == "Bundles" and card.root.Visible and card.buy.Visible then
				Theme.focus(card.buy)
				break
			end
		end
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		Theme.hide(f, ShopController.getBackdrop())
	end
end

-- Open a bundle's page (`back` reopens wherever it was opened from; `focusId` pops that item's card),
-- or close it with nil.
function CoinShopController.openPreview(offer: any?, back: (() -> ())?, focusId: string?)
	local f = previewSheet.frame
	if offer then
		local live = Catalog.offerLive(offer, Workspace:GetServerTimeNow())
		if not (inHub() and CoinShopController.unlocked() and live) then
			return
		end
		if not ShopController.isOpen(f) then
			SoundController.play("UIOpen")
		end
		ShopController.closeAll()
		preview.offer = offer
		preview.back = back
		previewSheet.title.Text = offer.Name
		preview.backButton.Visible = back ~= nil
		fillPreview(offer)
		renderPreviewStatus()
		Theme.show(f, ShopController.getBackdrop())
		local list = {}
		for _, id in offer.Items do
			table.insert(list, preview.cards[id])
		end
		table.insert(list, preview.cards.Coins)
		Theme.popIn(list)
		Theme.focus(if preview.buy.Visible then preview.buy else previewSheet.close)
		local card = focusId and preview.cards[focusId]
		if card then
			task.delay(Theme.Motion.Slow, function()
				Theme.pop(card, 1.1, Theme.Motion.Slow)
			end)
		end
	else
		if ShopController.isOpen(f) then
			Theme.setHome(nil)
		end
		Theme.hide(f, ShopController.getBackdrop())
	end
end

-- Buy a limited-time bundle (the Shop's bundle items and banner use this too).
CoinShopController.buyOffer = buyOffer
-- An offer's Robux price: the product's real one once loaded, else Config's (the hub stand's sign).
function CoinShopController.offerRobux(offer: any): number
	return prices[offer.Id] or offer.Robux
end
-- Show, hide and count down the bundle strips (the Shop calls this when it draws its shelf).
CoinShopController.renderOffers = renderOffers

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
		if d.starter ~= nil then
			starterBought = d.starter == true
		end
		if type(d.owned) == "table" then
			owned = d.owned
			renderOffers()
			-- the bundle page's Owned stickers and Buy follow what you own
			if previewSheet.frame.Visible and preview.offer then
				task.defer(fillPreview, preview.offer)
				renderPreviewStatus()
			end
		end
	end)
	-- the server granted a limited-time bundle: its coins and its cosmetics (equip them in the shop)
	Net.on("BundleBought", function(d)
		SoundController.play("Purchase")
		local coins = tonumber(d.coins) or 0
		if coins > 0 then
			HUDController.coinPop(coins)
		end
		-- a Robux-exclusive cosmetic arrives as a one-item bundle named after the item
		local exclusive = Catalog.get(d.id)
		if exclusive then
			HUDController.hint(("%s unlocked! Equip it in the Shop"):format(exclusive.Name), 2.4)
		end
		for _, card in offerCards do
			if card.offer.Id == d.id and card.root.Visible then
				Theme.pop(card.root, 1.08, Theme.Motion.Slow)
			end
		end
		for _, offer in CS.Offers do
			if offer.Id == d.id then
				HUDController.hint(("%s unlocked! Equip it in the Shop"):format(offer.Name), 2.4)
			end
		end
		if d.id == CS.Starter.Id then
			HUDController.hint("Starter Pack unlocked! Equip it in the Shop", 2.4)
		end
	end)
	-- VIP's daily gift: its coins and a bonus spin (waiting on the Spin sheet)
	Net.on("VipGift", function(d)
		SoundController.play("Purchase")
		HUDController.coinPop(tonumber(d.coins) or 0)
		HUDController.hint("VIP daily gift: coins and a free spin!", 2.4)
	end)
	player:GetAttributeChangedSignal("Pass_VIP"):Connect(function()
		renderOffers()
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
		if not inHub() and bundlesSheet.frame.Visible then
			CoinShopController.openBundles(false)
		end
		if not inHub() and previewSheet.frame.Visible then
			CoinShopController.openPreview(nil)
		end
		if os.clock() < nextTick then
			return
		end
		nextTick = os.clock() + 1
		-- the timed boost's and the offers' countdowns while this sheet, the bundles or the shop is up
		if sheet.frame.Visible or bundlesSheet.frame.Visible or ShopController.isShopOpen() then
			renderBoosts()
			renderOffers()
		end
		if previewSheet.frame.Visible then
			renderPreviewStatus()
		end
	end)
end

return CoinShopController
