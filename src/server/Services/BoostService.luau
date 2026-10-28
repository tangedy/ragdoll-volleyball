--!strict
-- 2x coins boosts (Config.CoinShop.Boosts), sold as developer products through PurchaseService.
-- The timed boost runs in real time from purchase and buying it again extends it; the lifetime one
-- is a flag on the profile. Either way the multiplier is Config.CoinShop.BoostMultiplier, applied
-- to match payouts (RewardService) and elimination coins (MatchService) only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local BoostService = {}

local S: any
local CS = Config.CoinShop

function BoostService.init(services: any)
	S = services
end

-- The coins multiplier for this combatant right now (1 for bots and anyone without a boost).
function BoostService.multiplier(c: any): number
	local p = c.profile
	if not c.player or not p then
		return 1
	end
	if p.CoinBoostForever == true or (tonumber(p.CoinBoostUntil) or 0) > os.time() then
		return CS.BoostMultiplier
	end
	return 1
end

-- What the client needs: when the timed boost ends (unix seconds, 0 for none) and the lifetime flag.
function BoostService.status(c: any): { untilTime: number, forever: boolean }
	local p = c.profile
	return {
		untilTime = if p then tonumber(p.CoinBoostUntil) or 0 else 0,
		forever = p ~= nil and p.CoinBoostForever == true,
	}
end

-- Grant one boost purchase. Returns true once it's on the profile (PurchaseService saves it).
function BoostService.grant(c: any, boost: any): boolean
	local p = c.profile
	if not p then
		return false
	end
	if boost.Forever then
		p.CoinBoostForever = true
	else
		local from = math.max(os.time(), tonumber(p.CoinBoostUntil) or 0)
		p.CoinBoostUntil = from + boost.Minutes * 60
	end
	if c.player then
		S.NetService.send(c.player, "BoostBought", { id = boost.Id })
	end
	return true
end

function BoostService.start()
	for _, boost in CS.Boosts do
		S.PurchaseService.register(boost.ProductId, function(c: any): boolean
			return BoostService.grant(c, boost)
		end)
	end
end

return BoostService
