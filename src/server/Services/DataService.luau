--!strict
-- Safe persistence (spec §13 "Persistence", Amendment A4 schema). UpdateAsync with retry limits
-- and a session lock. If loading fails, the existing profile is never overwritten with defaults:
-- the player keeps playing on an unsaved in-memory profile and the HUD says progress is not saving.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Catalog = require(Shared.Catalog)

local DataService = {}

local S: any
local D = Config.Data
local store: DataStore? = nil

export type Profile = {
	SchemaVersion: number,
	Coins: number, -- the single currency (schema v4; v3 stored it as "Pts")
	OwnedCosmetics: { [string]: boolean },
	Equipped: { [string]: string },
	TutorialStep: number,
	Wins: number,
	Knockouts: number,
	Matches: number,
	-- Amendment A4 additions (schema v2)
	Level: number,
	XP: number,
	-- schema v12: today's quest progress and claimed chests by Config.Quests.List id (QuestService)
	DailyQuests: {
		date: string,
		progress: { [string]: number },
		claimed: { [string]: boolean },
		backAt: { [string]: number }?,
	},
	LoginStreak: { day: number, lastDate: string, claimedDate: string },
	IndexOwned: { [string]: boolean },
	CurrentWinStreak: number,
	BestWinStreak: number,
	-- schema v5: daily cosmetic spin counters (SpinService)
	Spin: { date: string, freeUsed: boolean, paid: number, total: number, receipts: { string } },
	-- schema v7: Robux receipts already granted (PurchaseService), newest last
	Receipts: { string },
	-- schema v8: shop items this player has already seen (a shop tab says NEW! until they look)
	ShopSeen: { [string]: boolean },
	-- schema v9: 2x coins boosts (BoostService): a timed boost's end (unix seconds) and the lifetime one
	CoinBoostUntil: number,
	CoinBoostForever: boolean,
	-- schema v9: seconds played (PurchaseService unlocks Robux buttons after Config.CoinShop.RobuxAfterSeconds)
	PlaySeconds: number,
	-- schema v11: typed login rewards (RewardService.grant): free bonus spins waiting, oldest first
	-- (Config.Spin.Wheels ids), and cosmetic picks waiting for the player's choice
	BonusSpins: { string },
	RewardPicks: { { source: string, ids: { string }, rarity: string, coins: number } },
	-- lifetime credited knockouts by power-ball type (Power Ball Mastery, ShopService.recordPowerKO)
	PowerKOs: { [string]: number },
	-- quests ever claimed (unix time of the first claim; it gets the short Config.Quests.FirstCooldown)
	QuestFirstClaims: { [string]: number },
	Lock: { JobId: string, Time: number }?,
}

local function default(): Profile
	return {
		SchemaVersion = D.SchemaVersion,
		Coins = 0,
		OwnedCosmetics = {},
		Equipped = {},
		TutorialStep = 1,
		Wins = 0,
		Knockouts = 0,
		Matches = 0,
		Level = 1,
		XP = 0,
		DailyQuests = { date = "", progress = {}, claimed = {} },
		LoginStreak = { day = 0, lastDate = "", claimedDate = "" },
		IndexOwned = {},
		CurrentWinStreak = 0,
		BestWinStreak = 0,
		Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} },
		Receipts = {},
		ShopSeen = {}, -- a brand-new player finds every tab NEW!
		CoinBoostUntil = 0,
		CoinBoostForever = false,
		PlaySeconds = 0,
		BonusSpins = {},
		RewardPicks = {},
		PowerKOs = {},
		QuestFirstClaims = {},
		Lock = nil,
	}
end

-- Migrate any older schema to the current one, filling missing fields without losing data.
function DataService.migrate(old: any): Profile
	local data = default()
	if type(old) ~= "table" then
		return data
	end
	local version = tonumber(old.SchemaVersion) or 1
	for k, v in old do
		(data :: any)[k] = v
	end
	if version < 2 then
		-- v1 (spec v0.1) had no progression spine
		data.Level = 1
		data.XP = 0
		data.LoginStreak = { day = 0, lastDate = "", claimedDate = "" }
		data.IndexOwned = {}
		data.CurrentWinStreak = 0
		data.BestWinStreak = 0
	end
	if version < 3 then
		-- v3: the daily ladder gains a claimed date
		data.LoginStreak.claimedDate = data.LoginStreak.claimedDate or ""
	end
	if version < 4 then
		-- v4: the currency is "Coins" again (v3 briefly stored it as "Pts"); keep whichever exists
		local anyData = data :: any
		data.Coins = tonumber(anyData.Pts) or tonumber(anyData.Coins) or 0
		anyData.Pts = nil
	end
	if version < 5 then
		-- v5: the daily cosmetic spin; everyone starts with today's free spin available
		data.Spin = { date = "", freeUsed = false, paid = 0, total = 0, receipts = {} }
	end
	if version < 7 or type(data.Receipts) ~= "table" then
		-- v7: Robux receipts move to one list for every product
		data.Receipts = {}
	end
	if version < 8 or type(data.ShopSeen) ~= "table" then
		-- v8: returning players have effectively seen today's catalog; only items added from now on
		-- (and event items, when their event runs) show as NEW!
		data.ShopSeen = {}
		for _, item in Catalog.Items do
			if not item.Event then
				data.ShopSeen[item.Id] = true
			end
		end
	end
	if version < 9 then
		-- v9: coin boosts; nobody owns one yet
		data.CoinBoostUntil = tonumber(data.CoinBoostUntil) or 0
		data.CoinBoostForever = data.CoinBoostForever == true
		-- returning players who've finished a few matches are past the Robux wait already
		data.PlaySeconds = if (tonumber(data.Matches) or 0) >= 3 then Config.CoinShop.RobuxAfterSeconds else 0
	end
	if version < 11 then
		-- v11: the login ladder pays typed rewards. It's still 7 days, so the streak carries over as
		-- it is (same day, same claimed date); only a damaged entry is repaired, never reset.
		local ls = data.LoginStreak :: any
		if type(ls) ~= "table" then
			ls = { day = 0, lastDate = "", claimedDate = "" }
			data.LoginStreak = ls
		end
		local day = math.floor(tonumber(ls.day) or 0)
		ls.day = if day >= 1 then (day - 1) % #Config.DailyRewards.Ladder + 1 else 0
		ls.claimedDate = if type(ls.claimedDate) == "string" then ls.claimedDate else ""
		ls.lastDate = if type(ls.lastDate) == "string" then ls.lastDate else ls.claimedDate
	end
	if type(data.BonusSpins) ~= "table" then
		data.BonusSpins = {}
	end
	if version < 12 then
		-- v12: the lobby chests are gone (chests come from daily quests now). Paid opens were instant,
		-- so the only chest a player could still be owed is today's free open that was ready but not
		-- taken yet (v10 ChestDaily: Common after 1 match, Rare after 3). Each one becomes a free bonus
		-- spin on the wheel with the same odds, used from the Spin sheet.
		local cd = (data :: any).ChestDaily
		if type(cd) == "table" and cd.date == os.date("!%Y-%m-%d", os.time()) then
			local matches = tonumber(cd.matches) or 0
			local claimed = if type(cd.claimed) == "table" then cd.claimed else {}
			local owedChests = {
				{ Tier = "Common", After = 1, Wheel = "Standard" },
				{ Tier = "Rare", After = 3, Wheel = "RarePlus" },
			}
			for _, owed in owedChests do
				if matches >= owed.After and not claimed[owed.Tier] then
					table.insert(data.BonusSpins, owed.Wheel)
				end
			end
		end
		local anyData = data :: any
		anyData.ChestDaily = nil
		anyData.ChestOpens = nil
		-- the v2 placeholder ({ date, ids, progress }) was never used
		data.DailyQuests = { date = "", progress = {}, claimed = {} }
	end
	if type(data.RewardPicks) ~= "table" then
		data.RewardPicks = {}
	end
	if type(data.PowerKOs) ~= "table" then
		data.PowerKOs = {}
	end
	if type(data.QuestFirstClaims) ~= "table" then
		data.QuestFirstClaims = {}
	end
	data.SchemaVersion = D.SchemaVersion
	return data
end

function DataService.init(services: any)
	S = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(D.StoreName)
	end)
	store = if ok then result else nil
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

-- The player list (leaderstats): lifetime wins, eliminations and coins. Eliminations include the
-- current match's, which only bank into the profile when the match ends.
local LEADERSTATS = { "Wins", "Eliminations", "Coins" }
local function leaderstats(c: any, p: Profile)
	local player = c.player :: Player
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "leaderstats"
		for _, name in LEADERSTATS do
			local v = Instance.new("IntValue")
			v.Name = name
			v.Parent = f
		end
		f.Parent = player
		folder = f
	end
	local stats = c.stats
	local pending = if stats and not stats.banked then stats.knockouts + stats.botKnockouts else 0
	local values: { [string]: number } = { Wins = p.Wins, Eliminations = p.Knockouts + pending, Coins = p.Coins }
	for name, value in values do
		local v = (folder :: Instance):FindFirstChild(name) :: IntValue?
		if v and v.Value ~= value then
			v.Value = value
		end
	end
end

local function pushProfile(c: any)
	local p = c.profile :: Profile
	if not c.player then
		return
	end
	leaderstats(c, p)
	S.NetService.send(c.player, "Profile", {
		coins = p.Coins,
		owned = p.OwnedCosmetics,
		equipped = p.Equipped,
		daily = S.ShopService.dailyStatus(c),
		spin = S.SpinService.status(c),
		quests = S.QuestService.status(c),
		level = p.Level,
		xp = p.XP,
		xpNext = Progression.xpToNext(p.Level),
		streak = p.CurrentWinStreak,
		persistent = c.persistent,
		tutorialStep = p.TutorialStep,
		seen = p.ShopSeen,
		boost = S.BoostService.status(c),
		powerKOs = p.PowerKOs,
	})
	S.PlayerStateService.setAttr(c, "Level", p.Level)
	S.PlayerStateService.setAttr(c, "Streak", p.CurrentWinStreak)
	S.ShopService.applyCosmetics(c)
end
DataService.push = pushProfile

-- Write the profile with UpdateAsync. Returns whether it reached the DataStore: false when every
-- attempt failed, or when another server has taken the session over (its newer copy is kept).
local function write(c: any, release: boolean): boolean
	local player = c.player :: Player
	local data = table.clone(c.profile)
	data.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
	for attempt = 1, D.MaxRetries do
		local takenOver = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function(old: any)
				local lock = type(old) == "table" and old.Lock or nil
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < D.SessionLockTimeout then
					takenOver = true
					return nil -- session was taken over; never clobber the newer owner
				end
				-- a lock-keeping save that lands after the release save mustn't lock the profile again
				if c.released and not release then
					takenOver = true
					return nil
				end
				return data
			end)
		end)
		if ok then
			if takenOver then
				warn(("[Data] %s's session moved to another server; this copy wasn't saved"):format(player.Name))
			end
			return not takenOver
		end
		warn(("[Data] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
	return false
end

function DataService.load(c: any)
	local player = c.player :: Player
	c.profile = default()
	c.persistent = false
	local loaded: Profile? = nil
	if store then
		-- errors and a lock held by another server have separate budgets: a player who hops servers
		-- waits for the old server's release save instead of playing the whole session unsaved
		local failures, lockWaits = 0, 0
		while failures < D.MaxRetries and lockWaits < D.LockWaitRetries do
			local lockedByOther = false
			local ok, err = pcall(function()
				(store :: DataStore):UpdateAsync(key(player), function(old: any)
					local lock = type(old) == "table" and old.Lock or nil
					if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < D.SessionLockTimeout then
						lockedByOther = true
						return nil -- cancel: another server still owns this session
					end
					local data = DataService.migrate(old)
					data.Lock = { JobId = game.JobId, Time = os.time() }
					loaded = data
					return data
				end)
			end)
			if ok and loaded then
				break
			end
			if not ok then
				failures += 1
				warn(("[Data] load attempt %d failed for %s: %s"):format(failures, player.Name, tostring(err)))
				if string.find(tostring(err), "API access is not enabled", 1, true) then
					break -- Studio without API access: retrying can't help, play unsaved straight away
				end
			elseif lockedByOther then
				lockWaits += 1
				if lockWaits == D.LockWaitRetries then
					warn(("[Data] %s is still locked by another server; playing unsaved"):format(player.Name))
				end
			end
			if player.Parent ~= Players then
				break
			end
			task.wait(if lockedByOther then 3 else failures)
		end
	end
	if loaded then
		c.profile = loaded
		c.persistent = true
	end
	c.profileLoaded = true
	-- left while the save was loading: PlayerRemoving's release save ran before this server held the
	-- lock, so release it now or the next server would wait out SessionLockTimeout
	if c.released or player.Parent ~= Players then
		if c.persistent then
			write(c, true)
		end
		return
	end
	pushProfile(c)
	player:SetAttribute("ProfileReady", true) -- the loading screen waits for this
end

-- Returns whether the profile reached the DataStore. `release` drops the session lock (on leave
-- and shutdown); after that, lock-keeping saves for this player are refused.
function DataService.save(c: any, release: boolean): boolean
	if release then
		c.released = true
	elseif c.released then
		return false
	end
	if not c.persistent or not store or not c.player then
		return false
	end
	return write(c, release)
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(D.AutosaveInterval)
			for _, c in S.PlayerStateService.realPlayers() do
				task.spawn(DataService.save, c, false)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for _, c in S.PlayerStateService.realPlayers() do
			pending += 1
			task.spawn(function()
				DataService.save(c, true)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
