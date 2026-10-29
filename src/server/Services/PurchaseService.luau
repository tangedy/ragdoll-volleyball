--!strict
-- Robux purchases (developer products). Roblox allows one ProcessReceipt callback per game, so every
-- product registers a handler here by product id: coin bundles and limited-time cosmetic bundles
-- (Config.CoinShop), boosts (BoostService) and the extra spin (SpinService). A handler grants the
-- purchase and returns true; nothing is reported as granted until the profile holding it has saved,
-- and every PurchaseId is remembered on the profile so a retried receipt never grants twice.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)

local PurchaseService = {}

local S: any
local MAX_RECEIPTS = 100

type Handler = (c: any, receipt: any) -> boolean
local handlers: { [number]: Handler } = {}

function PurchaseService.init(services: any)
	S = services
end

-- Route a developer product to its grant. Products still at the placeholder id 0 are skipped.
function PurchaseService.register(productId: number, handler: Handler)
	if productId > 0 then
		handlers[productId] = handler
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local handler = handlers[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local c = player and S.PlayerStateService.get(player)
	if not handler or not c or not c.profileLoaded or not c.profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- an unsaved profile would lose what was paid for: wait for a server that can save it (Studio
	-- never saves, and test purchases there cost nothing)
	if not c.persistent and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = c.profile.Receipts
	if table.find(receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, granted = pcall(handler, c, receipt)
	if not ok then
		warn("[Purchase] grant failed: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(receipts, receipt.PurchaseId)
	while #receipts > MAX_RECEIPTS do
		table.remove(receipts, 1)
	end
	S.AnalyticsService.event(c, "RobuxPurchase_" .. tostring(receipt.ProductId), receipt.CurrencySpent or 0)
	S.DataService.push(c)
	if c.persistent and not S.DataService.save(c, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
PurchaseService.process = processReceipt -- the F9 suite feeds it receipts

-- Robux buttons show only after the tutorial plus Config.CoinShop.RobuxAfterSeconds of play. The
-- client reads the "RobuxOk" player attribute; purchases themselves are always honoured.
function PurchaseService.robuxUnlocked(c: any): boolean
	local p = c.profile
	if not c.profileLoaded or not p then
		return false
	end
	if RunService:IsStudio() and workspace:GetAttribute("RD_RobuxUnlocked") == true then
		return true -- Studio testing: workspace:SetAttribute("RD_RobuxUnlocked", true)
	end
	return (tonumber(p.TutorialStep) or 0) >= S.TutorialService.Done
		and (tonumber(p.PlaySeconds) or 0) >= Config.CoinShop.RobuxAfterSeconds
end

-- Grant one limited-time bundle (Config.CoinShop.Offers): its cosmetics and its coins. This runs
-- whenever the receipt arrives, even after the offer has ended (the card is hidden by then, but a
-- receipt that never grants is never resolved), and cosmetics already owned simply stay owned.
-- Nothing is equipped: the player picks that in the shop. The client celebrates on "BundleBought".
function PurchaseService.grantOffer(c: any, offer: any): boolean
	local p = c.profile
	if not p then
		return false
	end
	local items = {}
	for _, id in offer.Items do
		if Catalog.get(id) then
			p.OwnedCosmetics[id] = true
			table.insert(items, id)
		else
			warn(("[Purchase] offer %s names unknown item %s"):format(offer.Id, id))
		end
	end
	p.Coins += offer.Coins
	if c.player then
		S.NetService.send(c.player, "BundleBought", { id = offer.Id, coins = offer.Coins, items = items })
	end
	return true
end

local TICK = 10
local function playClock()
	while true do
		task.wait(TICK)
		for _, c in S.PlayerStateService.realPlayers() do
			if c.profileLoaded and c.profile and c.player then
				c.profile.PlaySeconds = (tonumber(c.profile.PlaySeconds) or 0) + TICK
				local ok = PurchaseService.robuxUnlocked(c)
				if c.player:GetAttribute("RobuxOk") ~= ok then
					c.player:SetAttribute("RobuxOk", ok)
				end
			end
		end
	end
end

function PurchaseService.start()
	task.spawn(playClock)
	-- coin bundles: the coins land straight in the wallet; the client celebrates on "CoinsBought"
	for _, bundle in Config.CoinShop.Bundles do
		PurchaseService.register(bundle.ProductId, function(c: any): boolean
			c.profile.Coins += bundle.Coins
			if c.player then
				S.NetService.send(c.player, "CoinsBought", { id = bundle.Id, coins = bundle.Coins })
			end
			return true
		end)
	end
	-- limited-time cosmetic bundles (products still at the placeholder id 0 aren't registered)
	for _, offer in Config.CoinShop.Offers do
		PurchaseService.register(offer.ProductId, function(c: any): boolean
			return PurchaseService.grantOffer(c, offer)
		end)
	end
	MarketplaceService.ProcessReceipt = processReceipt
end

return PurchaseService
