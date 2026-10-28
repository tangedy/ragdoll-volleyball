--!strict
-- Loot chests on the hub deck (Config.Chest). Each open costs Config.Chest.Cost coins and spins a
-- wheel of Config.Chest.Slots prizes drawn from every cosmetic that isn't a free default. There's
-- no daily cap.
--
-- Like the daily spin, the wheel is generated from a seed of (player, opens so far), so the client
-- shows exactly the wheel it will spin before paying; each slot's rarity is drawn by
-- Config.Chest.RarityWeights, and the server then picks one slot uniformly, so the odds are exactly
-- what the wheel shows. A prize the player already owns pays Config.Chest.DuplicateCoins instead.
-- Opening is hub-only and needs you standing at that chest. Everyone nearby sees its lid fly open.

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
local REACH_SLACK = 6 -- studs past the prompt distance (latency, and the prompt measures from its anchor)

function ChestService.init(services: any)
	S = services
end

-- The wheel for this player's next chest (deterministic, so the preview is the real wheel).
function ChestService.wheel(c: any): { string }
	local who = if c.player then c.player.UserId else c.id
	local opens = tonumber(c.profile and c.profile.ChestOpens) or 0
	local seeded = Random.new(math.abs(who) * 6151 + opens * 92821 + 4099)
	local p = S.SpinService.pool()
	local total = 0
	for _, r in RARITIES do
		if #p[r] > 0 then
			total += CH.RarityWeights[r]
		end
	end
	local slots: { string } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, CH.Slots do
		local roll = seeded:NextNumber() * total
		local rarity = RARITIES[1]
		for _, r in RARITIES do
			if #p[r] > 0 then
				roll -= CH.RarityWeights[r]
				if roll <= 0 then
					rarity = r
					break
				end
			end
		end
		-- within the rarity, prefer a prize not already on the wheel
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

-- What the HUD needs: the price and the next wheel.
function ChestService.status(c: any): { cost: number, slots: { string } }
	if not c.profile then
		return { cost = CH.Cost, slots = {} }
	end
	return { cost = CH.Cost, slots = ChestService.wheel(c) }
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

-- Pay, roll the current wheel and grant the prize. Returns the result table, or nil and a reason.
function ChestService.open(c: any, index: number): (any?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	if not inHub(c) then
		return nil, "Open chests in the hub"
	end
	local at = ChestService.position(index)
	if not at then
		return nil, "Not available"
	end
	local root = c.root :: BasePart?
	if c.player and (not root or (root.Position - at).Magnitude > CH.PromptDistance + REACH_SLACK) then
		return nil, "Walk up to the chest"
	end
	if c.profile.Coins < CH.Cost then
		return nil, ("Need %d more coins"):format(CH.Cost - c.profile.Coins)
	end
	local slots = ChestService.wheel(c)
	local slot = rng:NextInteger(1, #slots)
	local item = Catalog.get(slots[slot]) :: Catalog.Item
	local rarity = Catalog.rarity(item)
	-- pay first, then advance the counter (the next wheel is a new one)
	c.profile.Coins -= CH.Cost
	c.profile.ChestOpens = (tonumber(c.profile.ChestOpens) or 0) + 1
	local duplicate = S.ShopService.owns(c, item.Id)
	local coins = 0
	if duplicate then
		coins = CH.DuplicateCoins[rarity] or 0
		c.profile.Coins += coins
	else
		c.profile.OwnedCosmetics[item.Id] = true
	end
	S.AnalyticsService.event(c, "Chest_" .. rarity, coins)
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return {
		ok = true,
		chest = index,
		index = slot,
		slots = slots,
		id = item.Id,
		rarity = rarity,
		duplicate = duplicate,
		coins = coins,
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
