--!strict
-- What a Robux bundle is worth, worked out from Config and the Catalog so the shop never shows a
-- number that isn't true (docs/ECONOMY.md, "Value tags"). The Coins sheet, the Shop shelf's offer
-- strip and the hub's bundle stand all use this, and the offline tests check it against Config.

local BundleValue = {}

type Priced = { Coins: number, Robux: number }

-- How many percent more coins per Robux `bundle` gives than `base` (the smallest bundle), rounded
-- down so the tag never claims more than the real bonus: 35,000 for 999 R against 1,000 for 49 R is
-- +71.7%, shown as +71%.
function BundleValue.bonus(bundle: Priced, base: Priced): number
	if bundle.Robux <= 0 or base.Robux <= 0 or base.Coins <= 0 then
		return 0
	end
	local ratio = (bundle.Coins / bundle.Robux) / (base.Coins / base.Robux)
	-- the tiny nudge keeps an exact whole percent (e.g. 1.5 -> 50) from flooring to one less
	return math.max(0, math.floor((ratio - 1) * 100 + 1e-9))
end

-- The index of the bundle with the most coins per Robux (the first one on a tie), or nil if no
-- bundle beats the smallest one, so "Best value" is only ever on a real winner.
function BundleValue.best(bundles: { Priced }): number?
	local best, rate = nil, bundles[1] and bundles[1].Coins / math.max(1, bundles[1].Robux) or 0
	for i, b in bundles do
		if b.Robux > 0 and b.Coins / b.Robux > rate then
			best, rate = i, b.Coins / b.Robux
		end
	end
	return best
end

-- An offer's value in coins: the catalog Price of every item in it (for bundle-only items that's
-- their documented value) plus the coins it pays.
function BundleValue.worth(offer: { Items: { string }, Coins: number? }, catalog: any): number
	local total = offer.Coins or 0
	for _, id in offer.Items do
		local item = catalog.get(id)
		if item then
			total += item.Price or 0
		end
	end
	return total
end

return BundleValue
