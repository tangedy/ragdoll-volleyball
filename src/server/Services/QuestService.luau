--!strict
-- Daily quests (Config.Quests, docs/ECONOMY.md §4). Three goals a UTC day, each paying its quest
-- chest once it's reached: knock out 3 opponents (Title Chest), play 2 games (Gesture Chest), win 1
-- game (Finisher Chest). Progress and claims reset at UTC midnight.
--
-- Progress comes from events that already pay rewards, so it follows their rules: MatchService
-- records a credited knockout where it pays the knockout coins (bot knockouts included), and
-- RewardService records a played and a won match where it banks the match (finished, not aborted,
-- with the anti-AFK minimum of actions; bot-filled matches count, as they do for coins and wins).
--
-- Claiming is hub-only and once per quest per day, except a player's very first claim of each
-- quest: that quest comes back with fresh progress Config.Quests.FirstCooldown later. The chest opens through RewardService.grant
-- (Kind = "Chest"), which rolls the prize on the server. The claim is marked in the same step as the
-- grant, so a repeated request never pays twice, and the profile saves right after. Quest chests
-- are free, so they're allowed where paid random items are restricted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local NetSchema = require(Shared.NetSchema)

local QuestService = {}

local S: any
local Q = Config.Quests

export type Daily = {
	date: string,
	progress: { [string]: number },
	claimed: { [string]: boolean },
	backAt: { [string]: number }?, -- quests on their first-claim cooldown: when they come back
}

function QuestService.init(services: any)
	S = services
end

local function today(): string
	return os.date("!%Y-%m-%d", os.time()) :: string
end

local function questOf(id: string): any?
	for _, q in Q.List do
		if q.Id == id then
			return q
		end
	end
	return nil
end

-- Today's quest state on the profile (rolled over to a fresh day when the UTC date changes). A
-- quest on its first-claim cooldown (d.backAt) comes back with fresh progress once that has passed.
function QuestService.daily(c: any): Daily
	local p = c.profile
	local d = p.DailyQuests
	if type(d) ~= "table" or type(d.progress) ~= "table" or type(d.claimed) ~= "table" then
		d = { date = "", progress = {}, claimed = {} }
		p.DailyQuests = d
	end
	if d.date ~= today() then
		d.date = today()
		d.progress = {}
		d.claimed = {}
		d.backAt = nil
	end
	if type(d.backAt) == "table" then
		for id, at in d.backAt do
			if os.time() >= (tonumber(at) or 0) then
				d.backAt[id] = nil
				d.progress[id] = nil
				d.claimed[id] = nil
			end
		end
	end
	return d
end

-- Quests this player has claimed at least once ever (unix time of that first claim).
local function firstClaims(c: any): { [string]: number }
	local p = c.profile
	if type(p.QuestFirstClaims) ~= "table" then
		p.QuestFirstClaims = {}
	end
	return p.QuestFirstClaims
end

-- Count `amount` (default 1) of `event` ("Knockout" | "Played" | "Won") toward today's quests, up to
-- each goal. Real, loaded players only; the caller pushes the profile.
function QuestService.record(c: any, event: string, amount: number?)
	if not c.player or not c.profileLoaded or not c.profile then
		return
	end
	local d = QuestService.daily(c)
	for _, q in Q.List do
		if q.Event == event then
			d.progress[q.Id] = math.min(q.Goal, (tonumber(d.progress[q.Id]) or 0) + (amount or 1))
		end
	end
end

-- What the lobby panel needs: each quest's progress and claim, its chest's drops by rarity and the
-- odds of each rarity, and when today's quests reset (unix seconds).
function QuestService.status(c: any): any
	local d: any = if c.profile then QuestService.daily(c) else { progress = {}, claimed = {} }
	local resetsAt = (os.time() // 86400 + 1) * 86400
	local quests = {}
	for _, q in Q.List do
		local drops: { [string]: { string } } = {}
		for rarity, items in S.RewardService.chestPool(q.Chest) do
			drops[rarity] = {}
			for _, item in items do
				table.insert(drops[rarity], item.Id)
			end
		end
		local progress = tonumber(d.progress[q.Id]) or 0
		table.insert(quests, {
			id = q.Id,
			name = q.Name,
			goal = q.Goal,
			progress = progress,
			claimed = d.claimed[q.Id] == true,
			-- a claimed quest comes back then (unix seconds): its first-claim cooldown, else the reset
			nextAt = if d.claimed[q.Id] then (d.backAt and d.backAt[q.Id]) or resetsAt else nil,
			ready = progress >= q.Goal and d.claimed[q.Id] ~= true,
			chest = q.Chest,
			chestName = (Q.Chests :: any)[q.Chest].Name,
			odds = S.RewardService.chestOdds(q.Chest),
			drops = drops,
		})
	end
	return { quests = quests, resetsAt = resetsAt, featured = S.ShopService.featuredBall() }
end

local function inHub(c: any): boolean
	return not c.inMatch and c.status == "Lobby"
end

-- Claim quest `id`'s chest: opens it now. Returns the Chest result (RewardService.grant) with
-- `ok` and `quest`, or nil and a reason (nothing changes then).
function QuestService.claim(c: any, id: string): ({ [string]: any }?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	local q = questOf(id)
	if not q then
		return nil, "Unknown quest"
	end
	if not inHub(c) then
		return nil, "Claim quest chests in the hub"
	end
	local d = QuestService.daily(c)
	if d.claimed[q.Id] then
		return nil, "Already claimed"
	end
	local progress = tonumber(d.progress[q.Id]) or 0
	if progress < q.Goal then
		return nil, ("%d of %d done"):format(progress, q.Goal)
	end
	local result, why = S.RewardService.grant(c, { Kind = "Chest", Chest = q.Chest }, "Quest" .. q.Id)
	if not result then
		return nil, why
	end
	d.claimed[q.Id] = true
	local first = firstClaims(c)
	if not first[q.Id] then
		first[q.Id] = os.time()
		d.backAt = d.backAt or {}
		d.backAt[q.Id] = os.time() + Q.FirstCooldown
	end
	result.ok = true
	result.quest = q.Id
	S.AnalyticsService.event(c, "QuestClaim_" .. q.Id, result.coins or 0)
	if c.player then
		S.DataService.push(c)
		task.spawn(S.DataService.save, c, false)
	end
	return result, nil
end

function QuestService.start()
	S.NetService.on(NetSchema.Actions.ClaimQuest, function(player, p)
		local c = S.PlayerStateService.get(player)
		if not c then
			return
		end
		local result, why = QuestService.claim(c, p.id)
		S.NetService.send(player, "QuestResult", result or { ok = false, quest = p.id, message = why })
	end)
end

return QuestService
