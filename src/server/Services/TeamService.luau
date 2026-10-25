--!strict
-- Team sizing and assignment (spec §5 "Population changes", Amendment A2 "Match sizing").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local TeamService = {}

local S: any
local rng = Random.new()

function TeamService.init(services: any)
	S = services
end

function TeamService.teamSizeFor(realCount: number): number
	for _, row in Config.MatchSizing do
		if realCount <= row.MaxReal then
			return row.TeamSize
		end
	end
	return Config.Match.MaxPlayers // 2
end

local function count(roster: { any }, team: string, realOnly: boolean): number
	local n = 0
	for _, c in roster do
		if c.team == team and (not realOnly or not c.isBot) then
			n += 1
		end
	end
	return n
end

local function enter(c: any, roster: { any }, team: string)
	S.PlayerStateService.setTeam(c, team)
	c.inMatch = true
	c.stats = S.PlayerStateService.newStats()
	c.matchEliminations = 0
	c.aliveAtWin = false
	table.insert(roster, c)
	S.CharacterService.setTeamVisual(c)
end

-- Initial assignment: shuffle real players and alternate so teams differ by at most one.
function TeamService.assign(players: { any }, roster: { any }, teamSize: number)
	local list = table.clone(players)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	for _, c in list do
		local red, blue = count(roster, "Red", false), count(roster, "Blue", false)
		local team = if red <= blue then "Red" else "Blue"
		if count(roster, team, false) >= teamSize then
			team = if team == "Red" then "Blue" else "Red"
		end
		if count(roster, team, false) < teamSize then
			enter(c, roster, team)
		end
	end
end

-- Between rounds: waiting real players replace bots first, starting with the smaller team.
function TeamService.admitWaiting(roster: { any }, _teamSize: number)
	local maxPerTeam = Config.Match.MaxPlayers // 2
	for _, c in S.MatchService.queuedPlayers() do
		local redReal, blueReal = count(roster, "Red", true), count(roster, "Blue", true)
		local order: { string } = if redReal <= blueReal then { "Red", "Blue" } else { "Blue", "Red" }
		local placed = false
		for _, team in order do
			local bot = S.BotService.botOnTeam(roster, team)
			if bot then
				S.BotService.remove(roster, bot)
				enter(c, roster, team)
				c.lateJoin = true -- joined mid-match: can win, but not "flawless"
				placed = true
				break
			end
		end
		if not placed then
			local red, blue = count(roster, "Red", false), count(roster, "Blue", false)
			local team = if red <= blue then "Red" else "Blue"
			if count(roster, team, false) < maxPerTeam then
				enter(c, roster, team)
				c.lateJoin = true
			end
		end
	end
end

return TeamService
