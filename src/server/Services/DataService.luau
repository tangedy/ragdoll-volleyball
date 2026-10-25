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
	DailyQuests: { date: string, ids: { string }, progress: { number } },
	LoginStreak: { day: number, lastDate: string, claimedDate: string },
	IndexOwned: { [string]: boolean },
	CurrentWinStreak: number,
	BestWinStreak: number,
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
		DailyQuests = { date = "", ids = {}, progress = {} },
		LoginStreak = { day = 0, lastDate = "", claimedDate = "" },
		IndexOwned = {},
		CurrentWinStreak = 0,
		BestWinStreak = 0,
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
		data.DailyQuests = { date = "", ids = {}, progress = {} }
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

local function pushProfile(c: any)
	local p = c.profile :: Profile
	if not c.player then
		return
	end
	S.NetService.send(c.player, "Profile", {
		coins = p.Coins,
		owned = p.OwnedCosmetics,
		equipped = p.Equipped,
		daily = S.ShopService.dailyStatus(c),
		level = p.Level,
		xp = p.XP,
		xpNext = Progression.xpToNext(p.Level),
		streak = p.CurrentWinStreak,
		persistent = c.persistent,
		tutorialStep = p.TutorialStep,
	})
	S.PlayerStateService.setAttr(c, "Level", p.Level)
	S.PlayerStateService.setAttr(c, "Streak", p.CurrentWinStreak)
	S.ShopService.applyCosmetics(c)
end
DataService.push = pushProfile

function DataService.load(c: any)
	local player = c.player :: Player
	c.profile = default()
	c.persistent = false
	local loaded: Profile? = nil
	if store then
		for attempt = 1, D.MaxRetries do
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
				warn(("[Data] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
			end
			if lockedByOther and attempt == D.MaxRetries then
				warn(("[Data] %s is still locked by another server; playing unsaved"):format(player.Name))
			end
			if player.Parent ~= Players then
				return
			end
			task.wait(if lockedByOther then 3 else attempt)
		end
	end
	if loaded then
		c.profile = loaded
		c.persistent = true
	end
	c.profileLoaded = true
	pushProfile(c)
end

function DataService.save(c: any, release: boolean)
	if not c.persistent or not store or not c.player then
		return
	end
	local player = c.player :: Player
	local data = table.clone(c.profile)
	data.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
	for attempt = 1, D.MaxRetries do
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function(old: any)
				local lock = type(old) == "table" and old.Lock or nil
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < D.SessionLockTimeout then
					return nil -- session was taken over; never clobber the newer owner
				end
				return data
			end)
		end)
		if ok then
			return
		end
		warn(("[Data] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
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
