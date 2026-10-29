--!strict
-- Match rewards. Coins (the one currency) follow the designer's win tiers, highest tier only:
--   600 scored the match-ending knockout · 500 never eliminated all match · 300 on the court at
--   the win · 200 won · 50 played on the losing team. XP and level (Amendment A4) and win streaks
-- are unchanged. Rewards are granted once per match id per player and shown only in the results
-- overlay, never during combat.
--
-- RewardService.grant is the one place any typed reward (Config.DailyRewards explains the kinds)
-- lands on a profile: the daily login ladder and the daily quest chests (QuestService) both use it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Catalog = require(Shared.Catalog)
local NetSchema = require(Shared.NetSchema)

local RewardService = {}

local S: any
local P = Config.Coins
local X = Config.Progression.XP
local rng = Random.new()
local RARITIES = { "Common", "Rare", "Epic", "Legendary" }
local MAX_PICKS = 10 -- pending picks kept on a profile (oldest first); more pay their duplicate coins

function RewardService.init(services: any)
	S = services
end

export type MatchContext = {
	matchId: number,
	winner: string?,
	aborted: boolean,
	casual: boolean,
	duration: number,
	finalEliminator: any?, -- combatant credited with the match-ending knockout
}

-- Pure coins rule, exposed for tests. Returns coins and the tier name shown in the results overlay.
function RewardService.coins(c: any, ctx: MatchContext): (number, string)
	local s = c.stats
	local won = ctx.winner ~= nil and c.team == ctx.winner and not ctx.aborted
	-- anti-AFK: every coins payout needs at least one real action (spec v0.1 §13)
	local participated = (s.throws + s.catches + s.botCatches + s.dodges) >= P.MinParticipationActions
	if not participated then
		return 0, if ctx.aborted then "MATCH ABORTED" else "NO REWARD (IDLE)"
	end
	if won then
		if ctx.finalEliminator == c then
			return P.WinLastElimination, "FINAL KNOCKOUT"
		elseif (c.matchEliminations or 0) == 0 and not c.lateJoin then
			return P.WinFlawless, "FLAWLESS WIN"
		elseif c.aliveAtWin then
			return P.WinAlive, "SURVIVED THE WIN"
		end
		return P.Win, "WIN"
	end
	if not ctx.aborted and ctx.winner ~= nil then
		return P.LossParticipation, "GOOD GAME"
	end
	return 0, if ctx.aborted then "MATCH ABORTED" else "NO REWARD"
end

function RewardService.xp(c: any, ctx: MatchContext): number
	local s = c.stats
	local botRate = Config.Bots.RewardMultiplier
	local won = ctx.winner ~= nil and c.team == ctx.winner and not ctx.aborted
	local participated = (s.throws + s.catches + s.botCatches + s.dodges) >= P.MinParticipationActions
	local xp = 0
	if participated and not ctx.aborted then
		xp += X.Complete
		if won then
			xp += X.Win
		end
	end
	xp += s.hits * X.Hit + math.floor(s.botHits * X.Hit * botRate) + s.catches * X.Catch + math.floor(
		s.botCatches * X.Catch * botRate
	) + s.knockouts * X.Knockout + math.floor(s.botKnockouts * X.Knockout * botRate) + s.revenges * X.Revenge
	return math.min(xp, Config.Progression.MaxXPPerMatch)
end

function RewardService.awardMatch(roster: { any }, ctx: MatchContext)
	-- "STREAK ENDED!": a losing real player on a 5+ streak in a non-casual match.
	if ctx.winner and not ctx.casual then
		for _, c in roster do
			if
				c.player
				and c.profile
				and c.team ~= ctx.winner
				and c.profile.CurrentWinStreak >= Config.Rewards.StreakEndMin
			then
				S.NetService.broadcast("Feed", {
					text = ("🔥 STREAK ENDED! %s's %d-win streak is over!"):format(
						S.MatchService.tag(c),
						c.profile.CurrentWinStreak
					),
				})
			end
		end
	end
	for _, c in roster do
		if c.player and c.player.Parent and c.profile and c.rewardedMatch ~= ctx.matchId then
			c.rewardedMatch = ctx.matchId
			local coins, tier = RewardService.coins(c, ctx)
			local boost = S.BoostService.multiplier(c)
			coins *= boost
			local xp = RewardService.xp(c, ctx)
			local won = ctx.winner ~= nil and c.team == ctx.winner and not ctx.aborted
			local p = c.profile
			p.Coins += coins
			local oldLevel = p.Level
			p.Level, p.XP = Progression.addXP(p.Level, p.XP, xp)
			if not ctx.aborted then
				p.Matches += 1
			end
			if won then
				p.Wins += 1
			end
			p.Knockouts += c.stats.knockouts + c.stats.botKnockouts
			-- daily quests: a finished match you took part in (the coins' anti-AFK rule) counts as
			-- played, and as won when your team won; bot-filled matches count, as they do for coins
			local s = c.stats
			if not ctx.aborted and (s.throws + s.catches + s.botCatches + s.dodges) >= P.MinParticipationActions then
				S.QuestService.record(c, "Played")
				if won then
					S.QuestService.record(c, "Won")
				end
			end
			c.stats.banked = true
			-- bot-heavy (casual) matches neither advance nor break streaks
			if not ctx.casual and not ctx.aborted and ctx.winner then
				if won then
					p.CurrentWinStreak += 1
					p.BestWinStreak = math.max(p.BestWinStreak, p.CurrentWinStreak)
				else
					p.CurrentWinStreak = 0
				end
			end
			S.NetService.send(c.player, "Results", {
				winner = ctx.winner,
				aborted = ctx.aborted,
				won = won,
				casual = ctx.casual,
				-- everything earned this match: the tier payout plus the instant elimination coins
				coins = coins + (c.stats.eliminationCoins or 0),
				tier = tier,
				boost = boost,
				xp = xp,
				level = p.Level,
				leveledUp = p.Level > oldLevel,
				streak = p.CurrentWinStreak,
				wins = p.Wins, -- lifetime, this match included (FavoriteController asks from the 2nd)
				stats = {
					hits = c.stats.hits + c.stats.botHits,
					catches = c.stats.catches + c.stats.botCatches,
					knockouts = c.stats.knockouts + c.stats.botKnockouts,
					revenges = c.stats.revenges,
				},
				persistent = c.persistent,
			})
			S.DataService.push(c)
			task.spawn(S.DataService.save, c, false)
		end
	end
end

-- Typed rewards -------------------------------------------------------------------------------------

-- Is `reward` a well-formed typed reward this server can grant? (Config is checked by tests too.)
function RewardService.valid(reward: any): boolean
	if type(reward) ~= "table" then
		return false
	end
	local kind = reward.Kind
	if kind == "Coins" then
		return type(reward.Amount) == "number" and reward.Amount > 0
	elseif kind == "Spin" then
		return Config.Spin.Wheels[reward.Wheel] ~= nil
	elseif kind == "Boost" then
		for _, b in Config.CoinShop.Boosts do
			if b.Id == reward.Id then
				return true
			end
		end
		return false
	elseif kind == "Chest" then
		return type(reward.Chest) == "string" and (Config.Quests.Chests :: any)[reward.Chest] ~= nil
	elseif kind == "Cosmetic" then
		if reward.Id ~= nil then
			return Catalog.get(reward.Id) ~= nil
		end
		return Config.Spin.RarityWeights[reward.Rarity] ~= nil
			and type(reward.DuplicateCoins) == "number"
			and (reward.Choices == nil or (type(reward.Choices) == "number" and reward.Choices >= 1))
	end
	return false
end

-- Unowned prize-pool items of one rarity (the wheels' pool: no defaults, event or bundle items).
local function unowned(c: any, rarity: string): { string }
	local ids = {}
	for _, item in S.SpinService.pool()[rarity] or {} do
		if not item.Bundle and not S.ShopService.owns(c, item.Id) then
			table.insert(ids, item.Id)
		end
	end
	return ids
end

-- Own one catalog item, or pay `dupCoins` when it's already owned. Returns the client's result.
local function giveItem(c: any, id: string, dupCoins: number?): { [string]: any }
	local item = Catalog.get(id) :: Catalog.Item
	local rarity = Catalog.rarity(item)
	local duplicate = S.ShopService.owns(c, id)
	local coins = 0
	if duplicate then
		coins = dupCoins or Config.Spin.DuplicateCoins[rarity] or 0
		c.profile.Coins += coins
	else
		c.profile.OwnedCosmetics[id] = true
	end
	return { kind = "Cosmetic", id = id, rarity = rarity, duplicate = duplicate, coins = coins }
end

-- Quest chests ---------------------------------------------------------------------------------------

-- A chest's prize pool by rarity: the wheels' pool (no defaults, event or bundle items) narrowed to
-- the chest's category.
function RewardService.chestPool(chest: string): { [string]: { Catalog.Item } }
	local def = (Config.Quests.Chests :: any)[chest]
	local out: { [string]: { Catalog.Item } } = {}
	for _, r in RARITIES do
		out[r] = {}
		for _, item in S.SpinService.pool()[r] or {} do
			if def and item.Category == def.Category and not item.Bundle then
				table.insert(out[r], item)
			end
		end
	end
	return out
end

-- The chance of each rarity from this chest: its weights over the rarities its category has items
-- in, renormalized (a rarity with no items is 0).
function RewardService.chestOdds(chest: string): { [string]: number }
	local def = (Config.Quests.Chests :: any)[chest]
	local pool = RewardService.chestPool(chest)
	local total = 0
	for _, r in RARITIES do
		if #pool[r] > 0 then
			total += def.RarityWeights[r] or 0
		end
	end
	local odds: { [string]: number } = {}
	for _, r in RARITIES do
		odds[r] = if total > 0 and #pool[r] > 0 then (def.RarityWeights[r] or 0) / total else 0
	end
	return odds
end

-- Open a quest chest (docs/ECONOMY.md §4): roll a rarity by the chest's odds, then an unowned item
-- of it at random; when every item of that rarity is owned, one of them is shown as the prize and
-- pays its duplicate coins. Also builds the reveal wheel: the chest's drops, the prize among them.
local function openChest(c: any, chest: string): { [string]: any }
	local odds = RewardService.chestOdds(chest)
	local pool = RewardService.chestPool(chest)
	local roll = rng:NextNumber()
	local rarity = "Common"
	for _, r in RARITIES do
		if odds[r] > 0 then
			rarity = r
			roll -= odds[r]
			if roll <= 0 then
				break
			end
		end
	end
	local fresh: { string } = {}
	for _, item in pool[rarity] do
		if not S.ShopService.owns(c, item.Id) then
			table.insert(fresh, item.Id)
		end
	end
	local id: string
	local coins = 0
	if #fresh > 0 then
		id = fresh[rng:NextInteger(1, #fresh)]
		c.profile.OwnedCosmetics[id] = true
	else
		id = pool[rarity][rng:NextInteger(1, #pool[rarity])].Id
		coins = Config.Economy.DuplicateCoins[rarity] or 0
		c.profile.Coins += coins
	end
	-- the reveal wheel: every drop in a shuffled ring, repeated to fill the slots
	local ids: { string } = {}
	for _, r in RARITIES do
		for _, item in pool[r] do
			table.insert(ids, item.Id)
		end
	end
	for i = #ids, 2, -1 do
		local j = rng:NextInteger(1, i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	local slots: { string } = {}
	local at: { number } = {}
	for i = 1, Config.Quests.RevealSlots do
		slots[i] = ids[(i - 1) % #ids + 1]
		if slots[i] == id then
			table.insert(at, i)
		end
	end
	if #at == 0 then
		slots[1] = id
		at = { 1 }
	end
	return {
		kind = "Chest",
		chest = chest,
		id = id,
		rarity = rarity,
		duplicate = #fresh == 0,
		coins = coins,
		slots = slots,
		index = at[rng:NextInteger(1, #at)],
	}
end

-- Grant one typed reward to a loaded profile. `source` names where it came from ("Daily4", a quest
-- id): it tags analytics and the pick it may leave waiting. The caller pushes and saves the profile.
-- Returns what was granted, for the client:
--   { kind = "Coins", coins }
--   { kind = "Spin", wheel }                                 (queued in BonusSpins)
--   { kind = "Boost", id }
--   { kind = "Cosmetic", id, rarity, duplicate, coins }      (owned now, or coins for a duplicate)
--   { kind = "Pick", ids, rarity }                           (waits for RewardService.pick)
--   { kind = "Chest", chest, id, rarity, duplicate, coins, slots, index }  (a quest chest, opened)
-- or nil and a reason (nothing is changed then).
function RewardService.grant(c: any, reward: any, source: string): ({ [string]: any }?, string?)
	local p = c.profile
	if not c.profileLoaded or not p then
		return nil, "Not ready yet"
	end
	if not RewardService.valid(reward) then
		return nil, "Unknown reward"
	end
	local result: { [string]: any }
	if reward.Kind == "Coins" then
		p.Coins += reward.Amount
		result = { kind = "Coins", coins = reward.Amount }
	elseif reward.Kind == "Spin" then
		if type(p.BonusSpins) ~= "table" then
			p.BonusSpins = {}
		end
		table.insert(p.BonusSpins, reward.Wheel)
		result = { kind = "Spin", wheel = reward.Wheel }
	elseif reward.Kind == "Boost" then
		for _, b in Config.CoinShop.Boosts do
			if b.Id == reward.Id then
				S.BoostService.grant(c, b)
			end
		end
		result = { kind = "Boost", id = reward.Id }
	elseif reward.Kind == "Chest" then
		result = openChest(c, reward.Chest)
	elseif reward.Id then
		result = giveItem(c, reward.Id, reward.DuplicateCoins)
	else
		local ids = unowned(c, reward.Rarity)
		for i = #ids, 2, -1 do -- shuffle, then offer the first few
			local j = rng:NextInteger(1, i)
			ids[i], ids[j] = ids[j], ids[i]
		end
		local n = math.floor(reward.Choices or 1)
		if type(p.RewardPicks) ~= "table" then
			p.RewardPicks = {}
		end
		if #ids == 0 or #p.RewardPicks >= MAX_PICKS then
			-- every item of that rarity is owned: the duplicate coins instead
			p.Coins += reward.DuplicateCoins
			result = { kind = "Cosmetic", rarity = reward.Rarity, duplicate = true, coins = reward.DuplicateCoins }
		elseif n <= 1 or #ids == 1 then
			result = giveItem(c, ids[1], reward.DuplicateCoins)
		else
			local choices = table.move(ids, 1, math.min(n, #ids), 1, {})
			table.insert(p.RewardPicks, {
				source = source,
				ids = choices,
				rarity = reward.Rarity,
				coins = reward.DuplicateCoins,
			})
			result = { kind = "Pick", ids = choices, rarity = reward.Rarity }
		end
	end
	S.AnalyticsService.event(c, ("Reward_%s_%s"):format(source, result.kind), result.coins or 0)
	return result, nil
end

-- The oldest pick waiting for this player ({ source, ids, rarity, coins }), or nil.
function RewardService.pendingPick(c: any): any?
	local picks = c.profile and c.profile.RewardPicks
	return if type(picks) == "table" then picks[1] else nil
end

-- Take one item from the oldest waiting pick. The pick is spent before the item lands, so a repeated
-- request never grants twice; an item bought meanwhile pays the pick's duplicate coins. Pushes and
-- saves. Returns the Cosmetic result, or nil and a reason.
function RewardService.pick(c: any, id: string): ({ [string]: any }?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	local pending = RewardService.pendingPick(c)
	if not pending or type(pending.ids) ~= "table" or not table.find(pending.ids, id) or not Catalog.get(id) then
		return nil, "That isn't one of your choices"
	end
	table.remove(c.profile.RewardPicks, 1)
	local result = giveItem(c, id, tonumber(pending.coins))
	result.ok = true
	S.AnalyticsService.event(c, ("RewardPick_%s"):format(tostring(pending.source)), result.coins)
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return result, nil
end

function RewardService.start()
	S.NetService.on(NetSchema.Actions.PickReward, function(player, p)
		local c = S.PlayerStateService.get(player)
		if not c then
			return
		end
		local result, why = RewardService.pick(c, p.id)
		S.NetService.send(player, "PickResult", result or { ok = false, message = why })
	end)
end

return RewardService
