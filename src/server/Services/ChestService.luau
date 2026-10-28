--!strict
-- Loot chests on the hub deck, in three tiers (Config.Chest.Tiers; each spot in Config.Chest.Spots
-- names its tier). Each open spins a wheel of Config.Chest.Slots prizes drawn from every cosmetic
-- that isn't a free default, using only the rarities in that tier's RarityWeights, so the Rare and
-- Epic chests guarantee that rarity or better. There's no daily cap on paid opens.
--
-- Free opens: each UTC day, a tier with FreeAfterMatches opens once for free after that many
-- finished matches that day (RewardService calls matchPlayed). A free open isn't a paid random
-- item, so it's allowed where those are restricted.
--
-- Like the daily spin, the wheel is generated from a seed of (player, opens so far, tier), so the
-- client shows exactly the wheel it will spin before paying; the server then picks one slot
-- uniformly, so the odds are exactly what the wheel shows. A prize the player already owns pays
-- Config.Chest.DuplicateCoins instead. Opening is hub-only and needs you standing at that chest.
-- Everyone nearby sees its lid fly open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local NetSchema = require(Shared.NetSchema)
local LobbyBuilder = require(script.Parent.LobbyBuilder)

local ChestService = {}

local S: any
local CH = Config.Chest
local rng = Random.new()
local RARITIES = { "Common", "Rare", "Epic", "Legendary" }
local TIER_ORDER = { "Common", "Rare", "Epic" }
local REACH_SLACK = 6 -- studs past the prompt distance (latency, and the prompt measures from its anchor)

function ChestService.init(services: any)
	S = services
end

local function today(): string
	return os.date("!%Y-%m-%d", os.time()) :: string
end

-- The tier name of chest `index` (nil for an unknown chest).
function ChestService.tierOf(index: number): string?
	local spot = CH.Spots[index]
	return spot and spot.Tier or nil
end

-- Today's free-chest counters (rolled over to a fresh day when the UTC date changes).
function ChestService.daily(c: any): { date: string, matches: number, claimed: { [string]: boolean } }
	local p = c.profile
	local d = p.ChestDaily
	if type(d) ~= "table" then
		d = { date = "", matches = 0, claimed = {} }
		p.ChestDaily = d
	end
	if d.date ~= today() then
		d.date = today()
		d.matches = 0
		d.claimed = {}
	end
	return d
end

-- Is this tier's free open ready for this player today?
function ChestService.isFree(c: any, tierName: string): boolean
	local tier = (CH.Tiers :: any)[tierName]
	if not tier or not c.profile or (tier.FreeAfterMatches or 0) <= 0 then
		return false
	end
	local d = ChestService.daily(c)
	return d.matches >= tier.FreeAfterMatches and not d.claimed[tierName]
end

-- A finished match counts toward today's free chests; say so when one becomes ready.
function ChestService.matchPlayed(c: any)
	if not c.profile then
		return
	end
	local before: { [string]: boolean } = {}
	for _, name in TIER_ORDER do
		before[name] = ChestService.isFree(c, name)
	end
	local d = ChestService.daily(c)
	d.matches += 1
	for _, name in TIER_ORDER do
		if not before[name] and ChestService.isFree(c, name) and c.player then
			S.NetService.send(
				c.player,
				"Hint",
				{ text = ("Free %s ready in the hub!"):format((CH.Tiers :: any)[name].Name), duration = 3 }
			)
		end
	end
end

-- The wheel for this player's next open of chest `index` (deterministic, so the preview is real).
function ChestService.wheel(c: any, index: number): { string }
	local tier = (CH.Tiers :: any)[ChestService.tierOf(index) or "Common"]
	local who = if c.player then c.player.UserId else c.id
	local opens = tonumber(c.profile and c.profile.ChestOpens) or 0
	local seeded = Random.new(math.abs(who) * 6151 + opens * 92821 + index * 7717 + 4099)
	local p = S.SpinService.pool()
	local weights = tier.RarityWeights
	local total = 0
	for _, r in RARITIES do
		if #p[r] > 0 then
			total += weights[r] or 0
		end
	end
	local slots: { string } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, CH.Slots do
		local roll = seeded:NextNumber() * total
		local rarity: string? = nil
		for _, r in RARITIES do
			local w = weights[r] or 0
			if #p[r] > 0 and w > 0 then
				rarity = r
				roll -= w
				if roll <= 0 then
					break
				end
			end
		end
		-- within the rarity, prefer a prize not already on the wheel
		local list = p[rarity or "Common"]
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

-- What the HUD needs: per tier its price, next wheel and whether it's free now; today's match count
-- and each free tier's threshold; and whether paid opens are allowed at all.
function ChestService.status(c: any): any
	local restricted = S.ComplianceService.paidRandomRestricted(c)
	local tiers = {}
	local free = {}
	for index, spot in CH.Spots do
		local tier = (CH.Tiers :: any)[spot.Tier]
		tiers[spot.Tier] = {
			cost = tier.Cost,
			slots = if c.profile then ChestService.wheel(c, index) else {},
			free = ChestService.isFree(c, spot.Tier),
		}
	end
	local d = if c.profile then ChestService.daily(c) else { matches = 0, claimed = {} }
	for _, name in TIER_ORDER do
		local tier = (CH.Tiers :: any)[name]
		if (tier.FreeAfterMatches or 0) > 0 then
			table.insert(free, {
				tier = name,
				name = tier.Name,
				need = tier.FreeAfterMatches,
				claimed = d.claimed[name] == true,
			})
		end
	end
	return { tiers = tiers, free = free, matches = d.matches, restricted = restricted }
end

-- Where chest `index` stands, in world space.
function ChestService.position(index: number): Vector3?
	local spot = CH.Spots[index]
	if not spot then
		return nil
	end
	return LobbyBuilder.at(spot.X, 0, spot.F).Position
end

local function inHub(c: any): boolean
	return not c.inMatch and c.status == "Lobby"
end

-- Open chest `index`: free if today's free open is ready, else pay. Rolls the current wheel and
-- grants the prize. Returns the result table, or nil and a reason.
function ChestService.open(c: any, index: number): (any?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	local tierName = ChestService.tierOf(index)
	local tier = tierName and (CH.Tiers :: any)[tierName]
	if not tierName or not tier then
		return nil, "Not available"
	end
	local free = ChestService.isFree(c, tierName)
	if not free and S.ComplianceService.paidRandomRestricted(c) then
		return nil, "Chests aren't available in your region"
	end
	if not inHub(c) then
		return nil, "Open chests in the hub"
	end
	local at = ChestService.position(index) :: Vector3
	local root = c.root :: BasePart?
	if c.player and (not root or (root.Position - at).Magnitude > CH.PromptDistance + REACH_SLACK) then
		return nil, "Walk up to the chest"
	end
	if not free and c.profile.Coins < tier.Cost then
		return nil, ("Need %d more coins"):format(tier.Cost - c.profile.Coins)
	end
	local slots = ChestService.wheel(c, index)
	local slot = rng:NextInteger(1, #slots)
	local item = Catalog.get(slots[slot]) :: Catalog.Item
	local rarity = Catalog.rarity(item)
	-- pay (or use today's free open) first, then advance the counter (the next wheel is a new one)
	if free then
		ChestService.daily(c).claimed[tierName] = true
	else
		c.profile.Coins -= tier.Cost
	end
	c.profile.ChestOpens = (tonumber(c.profile.ChestOpens) or 0) + 1
	local duplicate = S.ShopService.owns(c, item.Id)
	local coins = 0
	if duplicate then
		coins = CH.DuplicateCoins[rarity] or 0
		c.profile.Coins += coins
	else
		c.profile.OwnedCosmetics[item.Id] = true
	end
	S.AnalyticsService.event(c, ("Chest_%s_%s_%s"):format(tierName, if free then "Free" else "Paid", rarity), coins)
	if c.player then
		S.DataService.push(c)
		task.spawn(S.DataService.save, c, false)
	end
	return {
		ok = true,
		chest = index,
		index = slot,
		slots = slots,
		id = item.Id,
		rarity = rarity,
		duplicate = duplicate,
		coins = coins,
		free = free,
	},
		nil
end

function ChestService.start()
	S.NetService.on(NetSchema.Actions.OpenChest, function(player, p)
		local c = S.PlayerStateService.get(player)
		if not c then
			return
		end
		local result, why = ChestService.open(c, p.chest)
		if not result then
			S.NetService.send(player, "ChestResult", { ok = false, chest = p.chest, message = why })
			return
		end
		S.NetService.send(player, "ChestResult", result)
		-- everyone else sees that chest burst open (their client skips the opener's own chest)
		S.NetService.broadcast(
			"ChestOpened",
			{ chest = p.chest, rarity = result.rarity, userId = player.UserId, delay = CH.SpinDuration }
		)
	end)
end

return ChestService
