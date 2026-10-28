--!strict
-- Registry of combatants: real players, bots and the practice dummy share one record shape so
-- every rule runs through the same pipeline (Amendment A2: no special-case physics for bots).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

export type Stats = {
	throws: number,
	hits: number,
	botHits: number,
	catches: number,
	botCatches: number,
	knockouts: number,
	botKnockouts: number,
	revenges: number,
	dodges: number,
	jailEscapes: number,
	streakEnds: number,
	eliminationCoins: number,
	banked: boolean, -- RewardService has added these to the profile's lifetime totals
}

export type Combatant = {
	id: number,
	name: string,
	player: Player?,
	isBot: boolean,
	isDummy: boolean,
	character: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	proxy: BasePart?,
	team: string?,
	status: string,
	action: string,
	actionToken: number,
	heldBall: any?,
	heldSince: number,
	possessionWarned: boolean,
	chargeStart: number?,
	dodgeReadyAt: number,
	catchReadyAt: number,
	catchUntil: number,
	immuneUntil: number,
	hitsTaken: number, -- knockback escalation (Config.Knockback.Escalation)
	lastHitBy: Combatant?,
	lastHitAt: number,
	eliminatedBy: Combatant?,
	jailReturns: number,
	autoQueue: boolean,
	inMatch: boolean,
	stats: Stats,
	settings: { [string]: boolean },
	bot: any?, -- bot brain state
}

local PlayerStateService = {}

local nextId = 0
local all: { [number]: Combatant } = {}
local byPlayer: { [Player]: Combatant } = {}
local byCharacter: { [Model]: Combatant } = {}
-- all() runs many times per physics step (ball sweeps, pickups, bots), so the sorted list is cached
-- and rebuilt only when someone joins or leaves. A rebuild makes a new table, so a caller iterating
-- the old one while combatants are added or removed is never disturbed. Callers must not mutate it.
local sortedCache: { Combatant }? = nil

local S: any

function PlayerStateService.init(services: any)
	S = services
end

function PlayerStateService.newStats(): Stats
	return {
		throws = 0,
		hits = 0,
		botHits = 0,
		catches = 0,
		botCatches = 0,
		knockouts = 0,
		botKnockouts = 0,
		revenges = 0,
		dodges = 0,
		jailEscapes = 0,
		streakEnds = 0,
		eliminationCoins = 0,
		banked = false,
	}
end

function PlayerStateService.create(name: string, player: Player?, isBot: boolean, isDummy: boolean): Combatant
	nextId += 1
	local c: Combatant = {
		id = nextId,
		name = name,
		player = player,
		isBot = isBot,
		isDummy = isDummy,
		character = nil,
		humanoid = nil,
		root = nil,
		proxy = nil,
		team = nil,
		status = "Lobby",
		action = "Idle",
		actionToken = 0,
		heldBall = nil,
		heldSince = 0,
		possessionWarned = false,
		chargeStart = nil,
		dodgeReadyAt = 0,
		catchReadyAt = 0,
		catchUntil = 0,
		immuneUntil = 0,
		hitsTaken = 0,
		lastHitBy = nil,
		lastHitAt = -math.huge,
		eliminatedBy = nil,
		jailReturns = 0,
		autoQueue = true,
		inMatch = false,
		stats = PlayerStateService.newStats(),
		settings = { ReducedMotion = false, CameraShake = true },
		bot = nil,
	}
	all[c.id] = c
	sortedCache = nil
	if player then
		byPlayer[player] = c
	end
	return c
end

function PlayerStateService.remove(c: Combatant)
	all[c.id] = nil
	sortedCache = nil
	if c.player then
		byPlayer[c.player] = nil
	end
	if c.character then
		byCharacter[c.character] = nil
	end
end

function PlayerStateService.attachCharacter(c: Combatant, character: Model)
	if c.character then
		byCharacter[c.character] = nil
	end
	c.character = character
	c.humanoid = character:FindFirstChildOfClass("Humanoid")
	c.root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	c.proxy = character:FindFirstChild("HitProxy") :: BasePart?
	byCharacter[character] = c
	PlayerStateService.syncAttributes(c)
end

function PlayerStateService.get(player: Player): Combatant?
	return byPlayer[player]
end

function PlayerStateService.fromCharacter(model: Instance?): Combatant?
	if model and model:IsA("Model") then
		return byCharacter[model]
	end
	return nil
end

function PlayerStateService.all(): { Combatant }
	if sortedCache then
		return sortedCache
	end
	local list = {}
	for _, c in all do
		table.insert(list, c)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	sortedCache = list
	return list
end

function PlayerStateService.now(): number
	return Workspace:GetServerTimeNow()
end

-- Only what other clients read off a character goes on it (outlines, aim targeting, spectating and
-- hub hiding read Team and Status; bots have no Player, so this is their only copy). Everything else
-- (Action, HeldBall, cooldowns, Level, Streak) is read off your own Player object, so a character copy
-- was replicated to every client for nothing.
local CHARACTER_KEYS: { [string]: boolean } = {
	[Types.Attr.Team] = true,
	[Types.Attr.Status] = true,
	[Types.Attr.IsBot] = true,
}

local function setAttr(c: Combatant, key: string, value: any)
	if c.character and CHARACTER_KEYS[key] then
		c.character:SetAttribute(key, value)
	end
	if c.player then
		c.player:SetAttribute(key, value)
	end
end
PlayerStateService.setAttr = setAttr

function PlayerStateService.syncAttributes(c: Combatant)
	setAttr(c, Types.Attr.Team, c.team or "")
	setAttr(c, Types.Attr.Status, c.status)
	setAttr(c, Types.Attr.Action, c.action)
	setAttr(c, Types.Attr.IsBot, c.isBot)
	setAttr(c, Types.Attr.DodgeReadyAt, c.dodgeReadyAt)
	setAttr(c, Types.Attr.CatchReadyAt, c.catchReadyAt)
	setAttr(c, Types.Attr.HeldBall, if c.heldBall then c.heldBall.type else "")
end

function PlayerStateService.setStatus(c: Combatant, status: string)
	-- analytics: time spent spectating (spec §14)
	local anyC = c :: any
	if status == "Spectating" and c.status ~= "Spectating" then
		anyC.spectateStart = os.clock()
	elseif c.status == "Spectating" and status ~= "Spectating" and anyC.spectateStart then
		S.AnalyticsService.event(c, "SpectateTime", os.clock() - anyC.spectateStart)
		anyC.spectateStart = nil
	end
	c.status = status
	setAttr(c, Types.Attr.Status, status)
end

function PlayerStateService.setTeam(c: Combatant, team: string?)
	c.team = team
	setAttr(c, Types.Attr.Team, team or "")
end

-- Set the single current action. With a duration, it reverts to Idle unless replaced meanwhile.
function PlayerStateService.setAction(c: Combatant, action: string, duration: number?)
	c.actionToken += 1
	local token = c.actionToken
	c.action = action
	setAttr(c, Types.Attr.Action, action)
	if duration then
		task.delay(duration, function()
			if c.actionToken == token and c.action == action then
				c.action = "Idle"
				setAttr(c, Types.Attr.Action, "Idle")
			end
		end)
	end
end

function PlayerStateService.isAlive(c: Combatant): boolean
	return c.character ~= nil and c.character.Parent ~= nil and c.root ~= nil and c.root.Parent ~= nil
end

function PlayerStateService.realPlayers(): { Combatant }
	local list = {}
	for _, c in PlayerStateService.all() do
		if c.player and c.player.Parent == Players then
			table.insert(list, c)
		end
	end
	return list
end

return PlayerStateService
