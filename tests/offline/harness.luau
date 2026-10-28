--!nocheck
-- Offline test harness (Lune). Loads the game's real modules from src/ with small fakes for the Roblox
-- engine: services, players, an in-memory DataStore, PolicyService, a deterministic Random, DateTime
-- and instant task.wait. It covers server logic only: no physics, UI, replication or real players.
-- Run from the repo root: lune run tests/offline/run

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local realTask = require("@lune/task")

local H = {}

-- Knobs the tests flip ------------------------------------------------------------------------------
H.studio = true -- RunService:IsStudio()
H.events = {} -- every NetService.send / broadcast: { to, name, payload }
H.realPlayers = {} -- PlayerStateService.realPlayers()
H.policy = {} -- [userId] = PolicyInfo table, or "error" to make the lookup throw
H.storeError = nil :: string? -- UpdateAsync throws this while set
H.now = nil :: number? -- frozen os.time() for date tests (nil = real time)

-- Random: a deterministic stand-in with the Roblox API the game uses -------------------------------
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	local s = math.floor(math.abs(seed or os.clock() * 1e6)) % 2147483646 + 1
	return setmetatable({ s = s }, Random)
end
function Random:_next(): number
	self.s = (self.s * 16807) % 2147483647
	return (self.s - 1) / 2147483646
end
function Random:NextNumber(a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + (hi - lo) * self:_next()
end
function Random:NextInteger(a: number, b: number): number
	return a + math.floor(self:_next() * (b - a + 1))
end

-- DateTime: the two calls the game makes ----------------------------------------------------------
local function daysFromCivil(y: number, m: number, d: number): number
	y = if m <= 2 then y - 1 else y
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local doy = (153 * (if m > 2 then m - 3 else m + 9) + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end
local DateTime = {}
function DateTime.fromUnixTimestamp(t: number)
	return {
		UnixTimestamp = t,
		ToIsoDate = function(_self)
			return os.date("!%Y-%m-%dT%H:%M:%SZ", t)
		end,
	}
end
function DateTime.fromIsoDate(iso: string)
	local y, mo, d, h, mi, s = string.match(iso, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	assert(y, "bad ISO date " .. iso)
	local t = daysFromCivil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
		+ tonumber(h) * 3600
		+ tonumber(mi) * 60
		+ tonumber(s)
	return DateTime.fromUnixTimestamp(t)
end

-- Fake instances ------------------------------------------------------------------------------------
local function signal()
	local fns = {}
	return {
		Connect = function(_, fn)
			table.insert(fns, fn)
			return { Disconnect = function() end }
		end,
		Once = function(_, fn)
			table.insert(fns, fn)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, fn in fns do
				fn(...)
			end
		end,
	}
end

local Inst = {}
local function instance(className: string, props: { [string]: any }?)
	local o = {
		ClassName = className,
		Name = className,
		_attrs = {},
		_children = {},
		_signals = {},
	}
	for k, v in props or {} do
		o[k] = v
	end
	return setmetatable(o, Inst)
end
H.instance = instance
Inst.__index = function(self, k)
	local m = rawget(Inst, k)
	if m then
		return m
	end
	if k == "Parent" then
		return rawget(self, "_parent")
	end
	return nil
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old and type(old) == "table" and rawget(old, "_children") then
			local i = table.find(old._children, self)
			if i then
				table.remove(old._children, i)
			end
		end
		rawset(self, "_parent", v)
		if v and type(v) == "table" and rawget(v, "_children") then
			table.insert(v._children, self)
		end
		return
	end
	rawset(self, k, v)
end
function Inst:GetAttribute(k)
	return self._attrs[k]
end
function Inst:SetAttribute(k, v)
	self._attrs[k] = v
	local s = self._signals[k]
	if s then
		s:Fire()
	end
end
function Inst:GetAttributeChangedSignal(k)
	self._signals[k] = self._signals[k] or signal()
	return self._signals[k]
end
function Inst:FindFirstChild(name)
	for _, c in self._children do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function Inst:WaitForChild(name)
	return self:FindFirstChild(name)
end
function Inst:FindFirstChildOfClass(cls)
	for _, c in self._children do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst:GetChildren()
	return table.clone(self._children)
end
function Inst:GetDescendants()
	return {}
end
function Inst:IsA(cls)
	return self.ClassName == cls
end
function Inst:Destroy()
	self.Parent = nil
end
function Inst:AddTag() end

-- Module references: script.Parent.X / Shared.X resolve to paths under src/ -----------------------
local Ref = {}
local function ref(path: string)
	return setmetatable({ __path = path }, Ref)
end
Ref.__index = function(self, k)
	if k == "WaitForChild" or k == "FindFirstChild" then
		return function(s, name)
			return ref(s.__path .. "/" .. name)
		end
	end
	if k == "Parent" then
		return ref((string.match(self.__path, "^(.*)/[^/]+$")) or "")
	end
	if k == "Name" then
		return (string.match(self.__path, "([^/]+)$"))
	end
	return ref(self.__path .. "/" .. k)
end

-- Services -------------------------------------------------------------------------------------------
local services = {}
local game = instance("DataModel")
H.game = game
function game:GetService(name)
	return services[name]
end
function game:BindToClose() end
game.JobId = "offline-job"
game.CreatorId = 1
game.CreatorType = roblox.Enum.CreatorType.User

local Workspace = instance("Workspace", { Name = "Workspace" })
function Workspace:GetServerTimeNow()
	return H.now or os.time()
end
services.Workspace = Workspace

local ReplicatedStorage = instance("ReplicatedStorage")
function ReplicatedStorage:WaitForChild(name)
	if name == "Shared" then
		return ref("shared")
	end
	return Inst.FindFirstChild(self, name)
end
services.ReplicatedStorage = ReplicatedStorage

local RunService = instance("RunService")
function RunService:IsStudio()
	return H.studio
end
RunService.Heartbeat = signal()
RunService.Stepped = signal()
services.RunService = RunService

local Players = instance("Players")
Players.PlayerAdded = signal()
Players.PlayerRemoving = signal()
function Players:GetPlayers()
	return self:GetChildren()
end
function Players:GetPlayerByUserId(id)
	for _, p in self._children do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
services.Players = Players

-- In-memory DataStore with UpdateAsync semantics (a nil return cancels the write).
H.store = {} :: { [string]: any }
local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
H.deepCopy = deepCopy
local DataStoreService = instance("DataStoreService")
function DataStoreService:GetDataStore(_name)
	return {
		UpdateAsync = function(_self, key, fn)
			if H.storeError then
				error(H.storeError)
			end
			local result = fn(deepCopy(H.store[key]))
			if result ~= nil then
				H.store[key] = deepCopy(result)
			end
			return result
		end,
	}
end
services.DataStoreService = DataStoreService

local PolicyService = instance("PolicyService")
function PolicyService:GetPolicyInfoForPlayerAsync(player)
	local info = H.policy[player.UserId]
	if info == "error" then
		error("HTTP 500 (policy lookup failed)")
	end
	return info or { ArePaidRandomItemsRestricted = false }
end
services.PolicyService = PolicyService

for _, name in
	{
		"MarketplaceService",
		"AnalyticsService",
		"ServerStorage",
		"Lighting",
		"CollectionService",
		"TweenService",
		"HttpService",
	}
do
	services[name] = instance(name)
end

-- Stubs for modules the tested services touch but that need a real place -------------------------
local function noopTable(name: string)
	return setmetatable({}, {
		__index = function(_, k)
			return function() end
		end,
		__tostring = function()
			return name
		end,
	})
end

local NetService = noopTable("NetService")
rawset(NetService, "send", function(to, name, payload)
	table.insert(H.events, { to = to, name = name, payload = payload })
end)
rawset(NetService, "broadcast", function(name, payload)
	table.insert(H.events, { to = "all", name = name, payload = payload })
end)

local PlayerStateService = noopTable("PlayerStateService")
rawset(PlayerStateService, "realPlayers", function()
	return H.realPlayers
end)
rawset(PlayerStateService, "get", function(player)
	for _, c in H.realPlayers do
		if c.player == player then
			return c
		end
	end
	return nil
end)

local stubs = {
	["server/Services/NetService"] = NetService,
	["server/Services/AnalyticsService"] = noopTable("AnalyticsService"),
	["server/Services/PlayerStateService"] = PlayerStateService,
	["server/Services/MatchService"] = setmetatable({
		tag = function(c)
			return c.name or "?"
		end,
	}, {
		__index = function()
			return function() end
		end,
	}),
	["server/Services/LobbyBuilder"] = {
		at = function(x, y, f)
			return roblox.CFrame.new(x, y, f)
		end,
	},
	["server/Services/ArenaBuilder"] = noopTable("ArenaBuilder"),
	["server/Services/HauntedWheelBuilder"] = noopTable("HauntedWheelBuilder"),
}

-- The fast task library: waits yield one scheduler step instead of sleeping, so retry loops finish.
local fastTask = table.clone(realTask)
fastTask.wait = function(_t)
	realTask.wait(0)
	return 0
end
fastTask.delay = function(_t, fn, ...)
	return realTask.spawn(fn, ...)
end

local fakeOs = setmetatable({
	time = function(t)
		if t then
			return os.time(t)
		end
		return H.now or os.time()
	end,
}, { __index = os })

-- Loader -----------------------------------------------------------------------------------------
local cache: { [string]: any } = {}
local loading: { [string]: boolean } = {}
local env

local function fileFor(path: string): string
	if string.sub(path, 1, 7) == "shared/" or path == "shared" then
		return "src/" .. path .. ".luau"
	end
	return "src/" .. path .. ".luau"
end

local function load(path: string)
	if cache[path] ~= nil then
		return cache[path]
	end
	if stubs[path] then
		cache[path] = stubs[path]
		return stubs[path]
	end
	assert(not loading[path], "require cycle at " .. path)
	loading[path] = true
	local file = fileFor(path)
	local source = fs.readFile(file)
	local moduleEnv = table.clone(env)
	moduleEnv.script = ref(path)
	local fn = luau.load(luau.compile(source), { debugName = file, environment = moduleEnv })
	local result = fn()
	loading[path] = nil
	cache[path] = result
	return result
end

local function fakeRequire(target)
	if type(target) == "table" and rawget(target, "__path") then
		return load(target.__path)
	end
	error("offline harness can't require " .. tostring(target))
end

env = {
	game = game,
	workspace = Workspace,
	require = fakeRequire,
	task = fastTask,
	os = fakeOs,
	Random = Random,
	DateTime = DateTime,
	Instance = {
		new = function(cls)
			return instance(cls)
		end,
	},
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Enum = roblox.Enum,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	TweenInfo = {
		new = function()
			return {}
		end,
	},
	warn = function(...)
		if H.verbose then
			print("[warn]", ...)
		end
	end,
	print = print,
	typeof = typeof,
}

H.require = load
H.DateTime = DateTime
H.Enum = roblox.Enum
H.Vector3 = roblox.Vector3

-- Wire the real services through one shared table, the way Bootstrap does.
local SERVICES = {
	"NetService",
	"AnalyticsService",
	"PlayerStateService",
	"MatchService",
	"DataService",
	"RewardService",
	"TutorialService",
	"ShopService",
	"ComplianceService",
	"SpinService",
	"PurchaseService",
	"BoostService",
	"ChestService",
	"HalloweenService",
}
H.S = {}
for _, name in SERVICES do
	H.S[name] = load("server/Services/" .. name)
end
for _, name in SERVICES do
	local s = H.S[name]
	if rawget(s, "init") then
		s.init(H.S)
	end
end
-- start only what registers handlers (no loops that wait on the place)
H.S.ShopService.applyCosmetics = function() end
for _, name in { "SpinService", "BoostService", "ChestService", "PurchaseService" } do
	H.S[name].start()
end

H.Config = load("shared/Config")
H.Catalog = load("shared/Catalog")

-- Helpers for tests --------------------------------------------------------------------------------
local nextUserId = 5000
function H.player(): any
	nextUserId += 1
	local p = instance("Player", { Name = "Tester" .. nextUserId, DisplayName = "Tester", UserId = nextUserId })
	p.Parent = Players
	return p
end

function H.stats()
	return {
		throws = 0,
		catches = 0,
		botCatches = 0,
		dodges = 0,
		hits = 0,
		botHits = 0,
		knockouts = 0,
		botKnockouts = 0,
		revenges = 0,
		eliminationCoins = 0,
		banked = false,
	}
end

-- A loaded, in-hub real player combatant (unsaved unless loaded through DataService).
function H.combatant(withPlayer: boolean?): any
	local c: any = {
		id = math.random(1, 1e6),
		name = "tester",
		profile = H.S.DataService.migrate(nil),
		profileLoaded = true,
		persistent = false,
		inMatch = false,
		status = "Lobby",
		stats = H.stats(),
	}
	if withPlayer ~= false then
		c.player = H.player()
		c.paidRandomRestricted = false
		table.insert(H.realPlayers, c)
	end
	return c
end

function H.reset()
	H.events = {}
	H.realPlayers = {}
	H.policy = {}
	H.storeError = nil
	H.now = nil
	H.studio = true
	Workspace._attrs = {}
	ReplicatedStorage._attrs = {}
end

function H.eventsNamed(name: string)
	local out = {}
	for _, e in H.events do
		if e.name == name then
			table.insert(out, e)
		end
	end
	return out
end

-- Tiny test runner ---------------------------------------------------------------------------------
H.tests = {}
function H.test(name: string, fn: () -> ())
	table.insert(H.tests, { name = name, fn = fn })
end
function H.check(cond: any, msg: string)
	if not cond then
		error(msg, 2)
	end
end
function H.eq(got: any, want: any, msg: string)
	if got ~= want then
		error(("%s: got %s, want %s"):format(msg, tostring(got), tostring(want)), 2)
	end
end

function H.run(): number
	local pass, fails = 0, {}
	for _, t in H.tests do
		H.reset()
		local ok, err = pcall(t.fn)
		if ok then
			pass += 1
			print("PASS " .. t.name)
		else
			table.insert(fails, t.name)
			print("FAIL " .. t.name .. "\n     " .. tostring(err))
		end
	end
	print(("\n%d/%d passed"):format(pass, #H.tests))
	return #fails
end

return H
