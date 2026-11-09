--!strict
-- Daily quests (Config.Quests, docs/ECONOMY.md §4). The hub shows Config.Quests.Shown of them: the
-- Repeats quest (play 12 minutes, for coins, again and again) and daily quests picked at random for
-- each player each UTC day from the rest (knock out 3, hit 10 players, dodge 5 balls, win 1 game),
-- each paying its quest chest once it's reached. Daily progress and claims reset at UTC midnight;
-- a Repeats quest's progress carries over.
--
-- Progress comes from match events, so it follows their rules: MatchService records a credited
-- knockout where it pays the knockout coins (bot knockouts included), CombatService a hit on an
-- enemy (bots included) and a dodge an enemy ball flew past, and RewardService a won match where it
-- banks the match (finished, not aborted, with the anti-AFK minimum of actions; bot-filled matches
-- count, as they do for coins and wins). Every daily quest's progress is tracked, picked or not;
-- only the picked ones show and can be claimed. Playtime ticks here, once a second, while the
-- player has moved in the last Config.Quests.ActiveWindow seconds; the count is mirrored on the
-- QuestPlaytime player attribute so the panel's bar climbs live.
--
-- Claiming is hub-only. A daily quest is claimed once per day, except a player's very first claim
-- of each quest: that quest comes back with fresh progress Config.Quests.FirstCooldown later. Its
-- chest opens through RewardService.grant (Kind = "Chest"), which rolls the prize on the server. A
-- Repeats quest pays its Reward (RepeatAmount after the day's first claim) and starts again from 0,
-- up to MaxClaims times a UTC day; then it's claimed until the reset and its clock stops. The claim
-- is marked in the same step as the
-- grant, so a repeated request never pays twice, and the profile saves right after. Quest chests
-- are free, so they're allowed where paid random items are restricted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
	picks: { string }?, -- today's daily quests, in panel order
	repeatClaims: { [string]: number }?, -- Repeats quests: times claimed today
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

-- The daily quests to show today: as many as fit beside the Repeats quests, at random. (A module
-- function so tests can pin the picks.)
function QuestService.pickDaily(): { string }
	local pool, repeating = {}, 0
	local picks = {}
	for _, q in Q.List do
		if q.Repeats then
			repeating += 1
		elseif q.Always then
			table.insert(picks, q.Id)
		else
			table.insert(pool, q.Id)
		end
	end
	local rng = Random.new()
	for _ = 1, math.min(#pool, Q.Shown - repeating - #picks) do
		table.insert(picks, table.remove(pool, rng:NextInteger(1, #pool)) :: string)
	end
	return picks
end

-- Today's quest state on the profile (rolled over to a fresh day when the UTC date changes, keeping
-- the Repeats quests' progress). A quest on its first-claim cooldown (d.backAt) comes back with
-- fresh progress once that has passed.
function QuestService.daily(c: any): Daily
	local p = c.profile
	local d = p.DailyQuests
	if type(d) ~= "table" or type(d.progress) ~= "table" or type(d.claimed) ~= "table" then
		d = { date = "", progress = {}, claimed = {} }
		p.DailyQuests = d
	end
	if d.date ~= today() then
		local progress = {}
		for _, q in Q.List do
			if q.Repeats then
				progress[q.Id] = d.progress[q.Id]
			end
		end
		d.date = today()
		d.progress = progress
		d.claimed = {}
		d.backAt = nil
		d.picks = nil
		d.repeatClaims = nil
	end
	if type(d.picks) ~= "table" then
		d.picks = QuestService.pickDaily()
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

-- The quests on the panel, in order: today's daily picks, then the Repeats quests.
local function shown(d: Daily): { any }
	local list = {}
	for _, id in d.picks or {} do
		local q = questOf(id)
		if q and not q.Repeats then
			table.insert(list, q)
		end
	end
	for _, q in Q.List do
		if q.Repeats then
			table.insert(list, q)
		end
	end
	return list
end

local function isShown(d: Daily, id: string): boolean
	for _, q in shown(d) do
		if q.Id == id then
			return true
		end
	end
	return false
end

-- Quests this player has claimed at least once ever (unix time of that first claim).
local function firstClaims(c: any): { [string]: number }
	local p = c.profile
	if type(p.QuestFirstClaims) ~= "table" then
		p.QuestFirstClaims = {}
	end
	return p.QuestFirstClaims
end

-- How many times Repeats quest `q` has been claimed today, and the coins its next claim pays.
local function repeatClaims(d: Daily, q: any): number
	return tonumber(d.repeatClaims and d.repeatClaims[q.Id]) or 0
end

-- A Repeats quest with FirstGoal uses it (and FirstName) until the day's first claim.
local function goalOf(d: Daily, q: any): number
	return if q.FirstGoal and repeatClaims(d, q) == 0 then q.FirstGoal else q.Goal
end

local function nameOf(d: Daily, q: any): string
	return if q.FirstName and repeatClaims(d, q) == 0 then q.FirstName else q.Name
end

local function repeatPay(d: Daily, q: any): number
	return if repeatClaims(d, q) == 0 then q.Reward.Amount else q.RepeatAmount or q.Reward.Amount
end

-- Count `amount` (default 1) of `event` ("Knockout" | "Hit" | "Dodge" | "Won" | "Playtime") toward
-- today's quests, up to each goal. Real, loaded players only; the caller pushes the profile.
function QuestService.record(c: any, event: string, amount: number?)
	if not c.player or not c.profileLoaded or not c.profile then
		return
	end
	local d = QuestService.daily(c)
	for _, q in Q.List do
		if q.Event == event then
			d.progress[q.Id] = math.min(goalOf(d, q), (tonumber(d.progress[q.Id]) or 0) + (amount or 1))
		end
	end
end

-- What the lobby panel needs: each shown quest's progress and claim, its chest's drops by rarity
-- and the odds of each rarity (or a Repeats quest's reward), and when today's quests reset (unix
-- seconds).
function QuestService.status(c: any): any
	local d: any = if c.profile then QuestService.daily(c) else { progress = {}, claimed = {}, picks = {} }
	local resetsAt = (os.time() // 86400 + 1) * 86400
	local quests = {}
	for _, q in shown(d) do
		local progress = tonumber(d.progress[q.Id]) or 0
		local entry: { [string]: any } = {
			id = q.Id,
			name = nameOf(d, q),
			goal = goalOf(d, q),
			event = q.Event,
			progress = progress,
			claimed = d.claimed[q.Id] == true,
			-- a claimed quest comes back then (unix seconds): its first-claim cooldown, else the reset
			nextAt = if d.claimed[q.Id] then (d.backAt and d.backAt[q.Id]) or resetsAt else nil,
			ready = progress >= goalOf(d, q) and d.claimed[q.Id] ~= true,
		}
		if q.Repeats then
			entry.repeats = true
			entry.coins = repeatPay(d, q) -- what the next claim pays
			entry.firstCoins = q.Reward.Amount
			entry.repeatCoins = q.RepeatAmount or q.Reward.Amount
			entry.claims = repeatClaims(d, q)
			entry.maxClaims = q.MaxClaims
		else
			local drops: { [string]: { string } } = {}
			for rarity, items in S.RewardService.chestPool(q.Chest) do
				drops[rarity] = {}
				for _, item in items do
					table.insert(drops[rarity], item.Id)
				end
			end
			entry.chest = q.Chest
			entry.chestName = (Q.Chests :: any)[q.Chest].Name
			entry.odds = S.RewardService.chestOdds(q.Chest)
			entry.drops = drops
		end
		table.insert(quests, entry)
	end
	return {
		quests = quests,
		resetsAt = resetsAt,
		featured = S.ShopService.featuredBall(),
		skinOfTheDay = S.ShopService.skinOfTheDay(),
	}
end

-- The shown quest closest to done that isn't claimed (ready ones first), for the results card:
-- { name, progress, goal, ready } or nil. Playtime quests are left out (they tick in seconds).
function QuestService.closest(c: any): { [string]: any }?
	if not c.profile then
		return nil
	end
	local d = QuestService.daily(c)
	local best, bestScore = nil, -1
	for _, q in shown(d) do
		if q.Event == "Playtime" or d.claimed[q.Id] then
			continue
		end
		local goal = goalOf(d, q)
		local progress = math.min(goal, tonumber(d.progress[q.Id]) or 0)
		local score = progress / math.max(1, goal)
		if score > bestScore then
			best = { name = nameOf(d, q), progress = progress, goal = goal, ready = progress >= goal, event = q.Event }
			bestScore = score
		end
	end
	return best
end

local function inHub(c: any): boolean
	return not c.inMatch and c.status == "Lobby"
end

-- Claim quest `id`: opens its chest now, or pays a Repeats quest's reward and starts it again.
-- Returns the RewardService.grant result with `ok` and `quest`, or nil and a reason (nothing
-- changes then).
function QuestService.claim(c: any, id: string): ({ [string]: any }?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	local q = questOf(id)
	if not q then
		return nil, "Unknown quest"
	end
	if not inHub(c) then
		return nil, "Claim quest rewards in the hub"
	end
	local d = QuestService.daily(c)
	if not isShown(d, q.Id) then
		return nil, "Not one of today's quests"
	end
	if d.claimed[q.Id] then
		return nil, "Already claimed"
	end
	local progress = tonumber(d.progress[q.Id]) or 0
	if progress < goalOf(d, q) then
		return nil, "Not done yet"
	end
	local reward = if q.Repeats
		then { Kind = "Coins", Amount = repeatPay(d, q) }
		else { Kind = "Chest", Chest = q.Chest }
	local result, why = S.RewardService.grant(c, reward, "Quest" .. q.Id)
	if not result then
		return nil, why
	end
	if q.Repeats then
		d.progress[q.Id] = 0
		local counts = d.repeatClaims or {}
		d.repeatClaims = counts
		local claims = (tonumber(counts[q.Id]) or 0) + 1
		counts[q.Id] = claims
		if q.MaxClaims and claims >= q.MaxClaims then
			d.claimed[q.Id] = true -- done for today; back at the reset
		end
		if c.player then
			c.player:SetAttribute("QuestPlaytime", 0)
		end
	else
		d.claimed[q.Id] = true
		local first = firstClaims(c)
		if not first[q.Id] then
			first[q.Id] = os.time()
			d.backAt = d.backAt or {}
			d.backAt[q.Id] = os.time() + Q.FirstCooldown
		end
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

-- Playtime: once a second, a second for every player who has moved in the last ActiveWindow
-- seconds (ragdoll flights count; standing still in the hub doesn't). Reaching the goal pushes the
-- profile so Claim shows.
local function playClock()
	while true do
		task.wait(1)
		local t = os.clock()
		for _, c in S.PlayerStateService.realPlayers() do
			if not c.profileLoaded or not c.profile or not c.root then
				continue
			end
			local pos = c.root.Position
			local last = c.questLastPos :: Vector3?
			if not last or (Vector3.new(pos.X - last.X, 0, pos.Z - last.Z)).Magnitude >= 1 then
				c.questLastPos = pos
				c.questActiveAt = t
			end
			-- the onboarding funnel's "Played 12 minutes": 12 real active minutes this session, not the
			-- playtime quest's goal (its first claim of the day is only 8)
			if t - (c.questActiveAt or -math.huge) <= Q.ActiveWindow then
				c.sessionActiveSeconds = (c.sessionActiveSeconds or 0) + 1
				if c.sessionActiveSeconds == Config.Analytics.FunnelPlaySeconds then
					S.AnalyticsService.played12Minutes(c)
				end
			end
			for _, q in Q.List do
				if q.Event ~= "Playtime" then
					continue
				end
				local d = QuestService.daily(c)
				local before = tonumber(d.progress[q.Id]) or 0
				-- a quest claimed out for today doesn't tick until the reset
				if
					before < goalOf(d, q)
					and not d.claimed[q.Id]
					and t - (c.questActiveAt or -math.huge) <= Q.ActiveWindow
				then
					QuestService.record(c, "Playtime")
					if (tonumber(d.progress[q.Id]) or 0) >= goalOf(d, q) then
						S.DataService.push(c)
					end
				end
				c.player:SetAttribute("QuestPlaytime", tonumber(d.progress[q.Id]) or 0)
			end
		end
	end
end

-- Studio testing (modules required from the command bar are separate copies, so this is the way
-- in): workspace:SetAttribute("RD_Quest", "Playtime=715") sets a quest's progress for every
-- player, "Picks=Hits,Dodges" sets today's picks, and "" only reads. Each player's picks and
-- progress land in their RD_QuestState attribute.
local function devHook()
	Workspace:GetAttributeChangedSignal("RD_Quest"):Connect(function()
		local cmd = tostring(Workspace:GetAttribute("RD_Quest") or "")
		local key, value = cmd:match("^(%w+)=(.*)$")
		for _, c in S.PlayerStateService.realPlayers() do
			if not c.profileLoaded or not c.profile then
				continue
			end
			local d = QuestService.daily(c)
			if key == "Picks" then
				d.picks = value:split(",")
			elseif key and questOf(key) then
				d.progress[key] = tonumber(value) or 0
			end
			if key then
				S.DataService.push(c)
			end
			local parts = { "picks=" .. table.concat(d.picks or {}, ",") }
			for _, q in Q.List do
				table.insert(parts, ("%s=%d"):format(q.Id, tonumber(d.progress[q.Id]) or 0))
			end
			c.player:SetAttribute("RD_QuestState", table.concat(parts, " "))
		end
		Workspace:SetAttribute("RD_Quest", nil)
	end)
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
	task.spawn(playClock)
	if RunService:IsStudio() then
		devHook()
	end
end

return QuestService
