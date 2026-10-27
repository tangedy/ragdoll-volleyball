--!strict
-- Daily cosmetic spin (separate from the daily coin ladder). One free spin per UTC day, plus extra
-- spins bought with coins (capped per day) or, once a developer product exists, Robux.
--
-- Every spin has a wheel of Config.Spin.Slots prizes. The wheel is generated from a seed of
-- (player, UTC day, spin number), so the client can show exactly the wheel it will spin before it
-- spins; each slot's rarity is drawn by Config.Spin.RarityWeights. The server then picks one slot
-- uniformly, so the odds are exactly what the wheel shows. A prize the player already owns pays
-- Config.Spin.DuplicateCoins instead. Everything is decided and saved here; the client only asks.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local NetSchema = require(Shared.NetSchema)

local SpinService = {}

local S: any
local SP = Config.Spin
local rng = Random.new()
local RARITIES = { "Common", "Rare", "Epic", "Legendary" }

export type SpinState = { date: string, freeUsed: boolean, paid: number, total: number, receipts: { string } }

function SpinService.init(services: any)
	S = services
end

local function today(): string
	return os.date("!%Y-%m-%d", os.time()) :: string
end

-- Prize pool by rarity: every catalog item that isn't a free default.
local pool: { [string]: { Catalog.Item } }? = nil
function SpinService.pool(): { [string]: { Catalog.Item } }
	if pool then
		return pool
	end
	local p: { [string]: { Catalog.Item } } = { Common = {}, Rare = {}, Epic = {}, Legendary = {} }
	for _, item in Catalog.Items do
		if not item.Default and item.Price > 0 then
			table.insert(p[Catalog.rarity(item)], item)
		end
	end
	pool = p
	return p
end

-- Today's spin counters (rolled over to a fresh day when the UTC date changes).
function SpinService.state(c: any): SpinState
	local p = c.profile
	local st = p.Spin :: SpinState
	if type(st) ~= "table" then
		st = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} }
		p.Spin = st
	end
	st.receipts = st.receipts or {}
	local d = today()
	if st.date ~= d then
		st.date = d
		st.freeUsed = false
		st.paid = 0
	end
	return st
end

-- The wheel for this player's next spin today (deterministic, so the preview is the real wheel).
function SpinService.wheel(c: any): { string }
	local st = SpinService.state(c)
	local who = if c.player then c.player.UserId else c.id
	local day = os.time() // 86400
	local spinNumber = (if st.freeUsed then 1 else 0) + st.paid
	local seeded = Random.new(math.abs(who) * 7919 + day * 104729 + spinNumber * 31 + 17)
	local p = SpinService.pool()
	local total = 0
	for _, r in RARITIES do
		if #p[r] > 0 then
			total += SP.RarityWeights[r]
		end
	end
	local slots: { string } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, SP.Slots do
		-- the rarity follows the weights exactly; within it, prefer a prize not already on the wheel
		local roll = seeded:NextNumber() * total
		local rarity = RARITIES[1]
		for _, r in RARITIES do
			if #p[r] > 0 then
				roll -= SP.RarityWeights[r]
				if roll <= 0 then
					rarity = r
					break
				end
			end
		end
		local list = p[rarity]
		local id = list[seeded:NextInteger(1, #list)].Id
		for _attempt = 1, 6 do
			if not used[id] then
				break
			end
			id = list[seeded:NextInteger(1, #list)].Id
		end
		used[id] = true
		table.insert(slots, id)
	end
	return slots
end

-- What the HUD needs: is the free spin ready, paid spins left today, and the next wheel.
function SpinService.status(c: any): { free: boolean, paidLeft: number, cost: number, slots: { string }, robux: number }
	if not c.profile then
		return { free = false, paidLeft = 0, cost = SP.ExtraSpinCost, slots = {}, robux = 0 }
	end
	local st = SpinService.state(c)
	return {
		free = not st.freeUsed,
		paidLeft = math.max(0, SP.MaxPaidPerDay - st.paid),
		cost = SP.ExtraSpinCost,
		slots = SpinService.wheel(c),
		robux = SP.RobuxProductId,
	}
end

local function inHub(c: any): boolean
	return not c.inMatch and c.status == "Lobby"
end

-- Roll the current wheel and grant the prize. `how` is "Free", "Coins" or "Robux".
-- Returns the result table, or nil and a reason.
function SpinService.spin(c: any, how: string): (any?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	if how ~= "Robux" and not inHub(c) then
		return nil, "Spin in the hub"
	end
	local st = SpinService.state(c)
	if how == "Free" then
		if st.freeUsed then
			return nil, "Free spin used today"
		end
	elseif how == "Coins" then
		if st.paid >= SP.MaxPaidPerDay then
			return nil, "No more spins today"
		end
		if c.profile.Coins < SP.ExtraSpinCost then
			return nil, ("Need %d more coins"):format(SP.ExtraSpinCost - c.profile.Coins)
		end
	elseif how ~= "Robux" then
		return nil, "Not available"
	end
	local slots = SpinService.wheel(c)
	local index = rng:NextInteger(1, #slots)
	local item = Catalog.get(slots[index]) :: Catalog.Item
	local rarity = Catalog.rarity(item)
	-- pay first, then advance the counters (the next wheel is a new one)
	if how == "Coins" then
		c.profile.Coins -= SP.ExtraSpinCost
	end
	if how == "Free" then
		st.freeUsed = true
	else
		st.paid += 1
	end
	st.total += 1
	local duplicate = S.ShopService.owns(c, item.Id)
	local coins = 0
	if duplicate then
		coins = SP.DuplicateCoins[rarity] or 0
		c.profile.Coins += coins
	else
		c.profile.OwnedCosmetics[item.Id] = true
	end
	S.AnalyticsService.event(c, "Spin_" .. how .. "_" .. rarity, coins)
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return {
		ok = true,
		index = index,
		slots = slots,
		id = item.Id,
		rarity = rarity,
		duplicate = duplicate,
		coins = coins,
		how = how,
	},
		nil
end

-- Robux extra spin (only when Config.Spin.RobuxProductId is set). Receipts are remembered on the
-- profile so a retried receipt never grants twice.
local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local c = player and S.PlayerStateService.get(player)
	if not c or not c.profileLoaded or receipt.ProductId ~= SP.RobuxProductId then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local st = SpinService.state(c)
	if table.find(st.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local result = SpinService.spin(c, "Robux")
	if not result then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(st.receipts, receipt.PurchaseId)
	while #st.receipts > 50 do
		table.remove(st.receipts, 1)
	end
	S.DataService.save(c, false)
	S.NetService.send(player :: Player, "SpinResult", result)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function SpinService.start()
	S.NetService.on(NetSchema.Actions.Spin, function(player, p)
		local c = S.PlayerStateService.get(player)
		if not c then
			return
		end
		local result, why = SpinService.spin(c, if p.paid then "Coins" else "Free")
		if result then
			S.NetService.send(player, "SpinResult", result)
		else
			S.NetService.send(player, "SpinResult", { ok = false, message = why })
		end
	end)
	if SP.RobuxProductId > 0 then
		MarketplaceService.ProcessReceipt = processReceipt
	end
end

return SpinService
