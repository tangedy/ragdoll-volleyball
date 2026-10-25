--!strict
-- Pure arena geometry shared by the server (authority) and client (presentation).
-- Court length runs along Z; Red owns z < 0, Blue owns z > 0. Width runs along X.

local Config = require(script.Parent.Config)

local A = Config.Arena
local J = Config.Jail

local ArenaLayout = {}

ArenaLayout.HalfLength = A.CourtLength / 2
ArenaLayout.HalfWidth = A.CourtWidth / 2
ArenaLayout.SurfaceY = A.Origin.Y
ArenaLayout.VoidY = A.Origin.Y - A.VoidDepth

function ArenaLayout.teamSign(team: string): number
	return if team == "Red" then -1 else 1
end

function ArenaLayout.enemyOf(team: string): string
	return if team == "Red" then "Blue" else "Red"
end

-- Center of a team's jail strip: directly behind the ENEMY half, past a small void gap.
function ArenaLayout.jailCenter(team: string): Vector3
	local enemySign = -ArenaLayout.teamSign(team)
	local z = enemySign * (ArenaLayout.HalfLength + J.Gap + J.StripDepth / 2)
	return Vector3.new(A.Origin.X, A.Origin.Y, A.Origin.Z + z)
end

-- Current safe half-width of the court (shrinks during overtime).
function ArenaLayout.safeHalfWidth(overtimeSteps: number): number
	return ArenaLayout.HalfWidth - A.OvertimeStripWidth * math.clamp(overtimeSteps, 0, A.OvertimeStrips)
end

-- Is a world position on the given team's half (within the current safe width)?
function ArenaLayout.onHalf(team: string, pos: Vector3, overtimeSteps: number, margin: number?): boolean
	local m = margin or 0
	local rel = pos - A.Origin
	local sign = ArenaLayout.teamSign(team)
	local hw = ArenaLayout.safeHalfWidth(overtimeSteps) - m
	local zOnSide = rel.Z * sign
	return math.abs(rel.X) <= hw and zOnSide >= m and zOnSide <= ArenaLayout.HalfLength - m
end

function ArenaLayout.inJail(team: string, pos: Vector3): boolean
	local c = ArenaLayout.jailCenter(team)
	local rel = pos - c
	return math.abs(rel.X) <= ArenaLayout.HalfWidth and math.abs(rel.Z) <= J.StripDepth / 2 + 0.5
end

-- Spawn points spread across the width, set back from the center line.
function ArenaLayout.spawnPoints(team: string, count: number): { Vector3 }
	local sign = ArenaLayout.teamSign(team)
	local points = {}
	local usable = ArenaLayout.HalfWidth - A.SpawnEdgeMargin
	for i = 1, count do
		local t = if count == 1 then 0.5 else (i - 1) / (count - 1)
		local x = -usable + 2 * usable * t
		-- stagger alternate spawns so lines are not perfectly flat
		local z = sign * (A.SpawnSetback + (if i % 2 == 0 then 4 else 0))
		table.insert(points, A.Origin + Vector3.new(x, 3, z))
	end
	return points
end

-- Opening ball spots: symmetric, near the center line, three per side.
function ArenaLayout.openingBallSpots(): { Vector3 }
	local spots = {}
	local perSide = A.OpeningBallSpots // 2
	for _, sign in { -1, 1 } do
		for i = 1, perSide do
			local t = if perSide == 1 then 0.5 else (i - 1) / (perSide - 1)
			local x = -16 + 32 * t
			table.insert(spots, A.Origin + Vector3.new(x, 2, sign * A.OpeningBallOffset))
		end
	end
	return spots
end

function ArenaLayout.randomPointOnHalf(team: string, overtimeSteps: number, edgeMargin: number, rng: Random): Vector3
	local sign = ArenaLayout.teamSign(team)
	local hw = math.max(2, ArenaLayout.safeHalfWidth(overtimeSteps) - edgeMargin)
	local x = rng:NextNumber(-hw, hw)
	local z = sign * rng:NextNumber(math.min(8, ArenaLayout.HalfLength / 2), ArenaLayout.HalfLength - edgeMargin)
	return A.Origin + Vector3.new(x, 3, z)
end

function ArenaLayout.lobbySpawn(rng: Random): Vector3
	local o = A.LobbyOrigin
	return o + Vector3.new(rng:NextNumber(-12, 12), 4, rng:NextNumber(-20, -8))
end

ArenaLayout.LobbyVoidY = A.LobbyOrigin.Y - A.VoidDepth
ArenaLayout.DummyHome = A.LobbyOrigin + Vector3.new(0, 4, A.LobbySize.Z / 2 - 6)
ArenaLayout.PracticeBallHome = A.LobbyOrigin + Vector3.new(0, 2, 0)

return ArenaLayout
