--!strict
-- Daily cosmetic spin. One free spin per UTC day, plus extra spins bought with coins (capped per
-- day) or, once a developer product exists, Robux. Free bonus spins from the login ladder
-- (profile.BonusSpins, oldest first) stack with the daily one and are used before it; each is on its
-- own wheel (Config.Spin.Wheels), and like the daily spin they're allowed in restricted regions.
--
-- Every spin has a wheel of Config.Spin.Slots prizes. The wheel is generated from a seed of
-- (player, UTC day, spin number), so the client can show exactly the wheel it will spin before it
-- spins; each slot's rarity is drawn by Config.Spin.RarityWeights. The server then picks one slot
-- uniformly, so the odds are exactly what the wheel shows. A prize the player already owns pays
-- Config.Spin.DuplicateCoins instead. Everything is decided and saved here; the client only asks.

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

-- Prize pool by rarity: every catalog cosmetic that isn't a free default. With `powers`, the Power
-- Wheel's pool instead: every power that isn't the free starter.
local pools: { [string]: { [string]: { Catalog.Item } } } = {}
function SpinService.pool(powers: boolean?): { [string]: { Catalog.Item } }
	local key = if powers then "Power" else "Cosmetic"
	if pools[key] then
		return pools[key]
	end
	local p: { [string]: { Catalog.Item } } = { Common = {}, Rare = {}, Epic = {}, Legendary = {} }
	for _, item in Catalog.Items do
		-- event cosmetics are never on the wheels (they're only sold during their event), mastery
		-- cosmetics are only earned and Robux exclusives only bought (the chest pools narrow this one);
		-- powers are only on the Power Wheel
		if
			not item.Default
			and item.Price > 0
			and not item.Event
			and not item.Unlock
			and not item.Exclusive
			and (item.Category == "Power") == (powers == true)
		then
			table.insert(p[Catalog.rarity(item)], item)
		end
	end
	pools[key] = p
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

-- Free bonus spins waiting (Config.Spin.Wheels ids), oldest first.
function SpinService.bonusSpins(c: any): { string }
	local q = c.profile.BonusSpins
	if type(q) ~= "table" then
		q = {}
		c.profile.BonusSpins = q
	end
	return q
end

-- Config.Spin.Slots prizes drawn from `p` by `weights` with the seeded generator.
local function fillWheel(seeded: Random, p: { [string]: { Catalog.Item } }, weights: { [string]: number }): { string }
	local total = 0
	for _, r in RARITIES do
		if #p[r] > 0 then
			total += weights[r] or 0
		end
	end
	local slots: { string } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, SP.Slots do
		-- the rarity follows the weights exactly; within it, prefer a prize not already on the wheel
		local roll = seeded:NextNumber() * total
		local rarity = RARITIES[1]
		for _, r in RARITIES do
			if #p[r] > 0 and (weights[r] or 0) > 0 then
				rarity = r -- also the fallback if rounding leaves a sliver of roll
				roll -= weights[r]
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

-- The wheel for this player's next spin today (deterministic, so the preview is the real wheel).
-- `bonus` is a Config.Spin.Wheels id for a bonus spin; without it, it's the daily/paid wheel.
function SpinService.wheel(c: any, bonus: string?): { string }
	local st = SpinService.state(c)
	local who = if c.player then c.player.UserId else c.id
	local day = os.time() // 86400
	local spinNumber = (if st.freeUsed then 1 else 0) + st.paid
	local weights = SP.RarityWeights
	if bonus then
		-- its own seed stream, moved on by every spin (so each bonus spin gets a fresh wheel)
		spinNumber = 1000 + st.total
		weights = (SP.Wheels[bonus] or SP.Wheels.Standard).RarityWeights
	end
	local seeded = Random.new(math.abs(who) * 7919 + day * 104729 + spinNumber * 31 + 17)
	return fillWheel(seeded, SpinService.pool(), weights)
end

-- What the HUD needs: free spins waiting (bonus spins plus today's daily one), the bonus wheel the
-- next free spin is on (nil for the daily one), paid spins left today, and the next wheel.
-- Paid spins are off where paid random items are restricted (free and bonus spins stay).
function SpinService.status(c: any): {
	free: boolean,
	freeSpins: number,
	bonus: string?,
	paidLeft: number,
	cost: number,
	slots: { string },
	robux: number,
	restricted: boolean,
}
	local restricted = S.ComplianceService.paidRandomRestricted(c)
	if not c.profile then
		return {
			free = false,
			freeSpins = 0,
			paidLeft = 0,
			cost = SP.ExtraSpinCost,
			slots = {},
			robux = 0,
			restricted = restricted,
		}
	end
	local st = SpinService.state(c)
	local bonus = SpinService.bonusSpins(c)[1]
	local freeSpins = #SpinService.bonusSpins(c) + (if st.freeUsed then 0 else 1)
	return {
		free = freeSpins > 0,
		freeSpins = freeSpins,
		bonus = bonus,
		paidLeft = if restricted then 0 else math.max(0, SP.MaxPaidPerDay - st.paid),
		cost = SP.ExtraSpinCost,
		slots = SpinService.wheel(c, bonus),
		robux = if restricted then 0 else SP.RobuxProductId,
		restricted = restricted,
	}
end

local function inHub(c: any): boolean
	return not c.inMatch and c.status == "Lobby"
end

-- Roll the current wheel and grant the prize. `how` is "Free", "Coins" or "Robux"; a free spin uses
-- the oldest bonus spin first (the result says how = "Bonus" and its wheel), then the daily one.
-- Returns the result table, or nil and a reason.
function SpinService.spin(c: any, how: string): (any?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	if how ~= "Robux" and not inHub(c) then
		return nil, "Spin in the hub"
	end
	if how ~= "Free" and S.ComplianceService.paidRandomRestricted(c) then
		return nil, "Paid spins aren't available in your region"
	end
	local st = SpinService.state(c)
	local bonus: string? = nil
	if how == "Free" then
		bonus = SpinService.bonusSpins(c)[1]
		if bonus then
			how = "Bonus"
		elseif st.freeUsed then
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
	local slots = SpinService.wheel(c, bonus)
	local index = rng:NextInteger(1, #slots)
	local item = Catalog.get(slots[index]) :: Catalog.Item
	local rarity = Catalog.rarity(item)
	-- pay first, then advance the counters (the next wheel is a new one)
	if how == "Coins" then
		c.profile.Coins -= SP.ExtraSpinCost
		S.AnalyticsService.coinPurchase(c)
	end
	if how == "Bonus" then
		table.remove(SpinService.bonusSpins(c), 1)
	elseif how == "Free" then
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
		wheel = bonus,
	},
		nil
end

-- Power Wheel (Config.Powers.Wheel) ---------------------------------------------------------------
-- A paid wheel (coins, capped per day, or Robux) whose prizes are powers only. Same rules as the
-- cosmetic wheel: the wheel is seeded so the preview is the real one, one slot is picked uniformly,
-- and a power you already own pays Config.Spin.DuplicateCoins instead. Its counters are
-- profile.PowerSpin.
local PW = Config.Powers.Wheel

function SpinService.powerState(c: any): { date: string, paid: number, total: number }
	local p = c.profile
	local st = p.PowerSpin
	if type(st) ~= "table" then
		st = { date = "", paid = 0, total = 0 }
		p.PowerSpin = st
	end
	local d = today()
	if st.date ~= d then
		st.date = d
		st.paid = 0
	end
	st.total = tonumber(st.total) or 0
	return st
end

function SpinService.powerWheel(c: any): { string }
	local st = SpinService.powerState(c)
	local who = if c.player then c.player.UserId else c.id
	local seeded = Random.new(math.abs(who) * 6151 + (os.time() // 86400) * 92821 + st.total * 37 + 5)
	return fillWheel(seeded, SpinService.pool(true), PW.RarityWeights)
end

function SpinService.powerStatus(c: any): { paidLeft: number, cost: number, slots: { string }, robux: number }
	if not c.profile then
		return { paidLeft = 0, cost = PW.CoinCost, slots = {}, robux = 0 }
	end
	local restricted = S.ComplianceService.paidRandomRestricted(c)
	local st = SpinService.powerState(c)
	return {
		paidLeft = if restricted then 0 else math.max(0, PW.MaxPaidPerDay - st.paid),
		cost = PW.CoinCost,
		slots = SpinService.powerWheel(c),
		robux = if restricted then 0 else PW.RobuxProductId,
	}
end

-- Spin the Power Wheel: `how` is "Coins" or "Robux". Returns the result table, or nil and a reason.
function SpinService.spinPower(c: any, how: string): (any?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	if how ~= "Robux" and not inHub(c) then
		return nil, "Spin in the hub"
	end
	if S.ComplianceService.paidRandomRestricted(c) then
		return nil, "Paid spins aren't available in your region"
	end
	local st = SpinService.powerState(c)
	if how == "Coins" then
		if st.paid >= PW.MaxPaidPerDay then
			return nil, "No more Power Wheel spins today"
		end
		if c.profile.Coins < PW.CoinCost then
			return nil, ("Need %d more coins"):format(PW.CoinCost - c.profile.Coins)
		end
	elseif how ~= "Robux" then
		return nil, "Not available"
	end
	local slots = SpinService.powerWheel(c)
	local index = rng:NextInteger(1, #slots)
	local item = Catalog.get(slots[index]) :: Catalog.Item
	local rarity = Catalog.rarity(item)
	if how == "Coins" then
		c.profile.Coins -= PW.CoinCost
		st.paid += 1
		S.AnalyticsService.coinPurchase(c)
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
	S.AnalyticsService.event(c, "PowerSpin_" .. how .. "_" .. rarity, coins)
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
		power = true,
	},
		nil
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
	S.NetService.on(NetSchema.Actions.SpinPower, function(player, _p)
		local c = S.PlayerStateService.get(player)
		if not c then
			return
		end
		local result, why = SpinService.spinPower(c, "Coins")
		S.NetService.send(player, "SpinResult", result or { ok = false, message = why, power = true })
	end)
	S.PurchaseService.register(PW.RobuxProductId, function(c: any): boolean
		if S.ComplianceService.paidRandomRestricted(c) then
			c.profile.Coins += PW.CoinCost
			if c.player then
				S.NetService.send(c.player, "CoinsBought", { id = "PowerSpin", coins = PW.CoinCost })
			end
			return true
		end
		local result = SpinService.spinPower(c, "Robux")
		if not result then
			return false
		end
		if c.player then
			S.NetService.send(c.player, "SpinResult", result)
		end
		return true
	end)
	-- Robux extra spin (only once Config.Spin.RobuxProductId is set); PurchaseService handles the
	-- receipt and its save
	S.PurchaseService.register(SP.RobuxProductId, function(c: any): boolean
		-- the button is hidden where paid random items are restricted, but if a purchase gets through
		-- anyway, pay the spin's coin price instead: a receipt that never grants is never resolved
		if S.ComplianceService.paidRandomRestricted(c) then
			c.profile.Coins += SP.ExtraSpinCost
			if c.player then
				S.NetService.send(c.player, "CoinsBought", { id = "Spin", coins = SP.ExtraSpinCost })
			end
			return true
		end
		local result = SpinService.spin(c, "Robux")
		if not result then
			return false
		end
		if c.player then
			S.NetService.send(c.player, "SpinResult", result)
		end
		return true
	end)
end

return SpinService
