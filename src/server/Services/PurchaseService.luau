--!strict
-- Robux purchases (developer products). Roblox allows one ProcessReceipt callback per game, so every
-- product registers a handler here by product id: coin bundles (Config.CoinShop) and the extra spin
-- (SpinService). A handler grants the purchase and returns true; nothing is reported as granted
-- until the profile holding it has saved, and every PurchaseId is remembered on the profile so a
-- retried receipt never grants twice.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

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

function PurchaseService.start()
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
	MarketplaceService.ProcessReceipt = processReceipt
end

return PurchaseService
