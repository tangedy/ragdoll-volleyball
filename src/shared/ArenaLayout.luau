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

-- Middle of a team's half, on the court surface.
function ArenaLayout.halfCenter(team: string): Vector3
	return A.Origin + Vector3.new(0, 0, ArenaLayout.teamSign(team) * ArenaLayout.HalfLength / 2)
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
			local x = ArenaLayout.HalfWidth * (t - 0.5)
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

-- The hub deck's frame: centered on LobbyOrigin, LookVector pointing at the court (flat).
local courtFlat = Vector3.new(A.Origin.X, A.LobbyOrigin.Y, A.Origin.Z)
ArenaLayout.LobbyFrame = if (courtFlat - A.LobbyOrigin).Magnitude > 1
	then CFrame.lookAt(A.LobbyOrigin, courtFlat)
	else CFrame.new(A.LobbyOrigin)

-- A point on the deck: x = right, y = up from the deck surface, f = forward toward the court.
function ArenaLayout.lobbyPoint(x: number, y: number, f: number): Vector3
	return ArenaLayout.LobbyFrame * Vector3.new(x, y, -f)
end

-- Is a world position over the hub deck (any height)? margin grows (+) or shrinks (-) the area.
function ArenaLayout.inLobby(pos: Vector3, margin: number?): boolean
	local m = margin or 0
	local rel = ArenaLayout.LobbyFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= A.LobbySize.X / 2 + m and math.abs(rel.Z) <= A.LobbySize.Z / 2 + m
end

-- Clamp a world position onto the deck, `inset` studs in from the edges.
function ArenaLayout.clampToLobby(pos: Vector3, inset: number): Vector3
	local rel = ArenaLayout.LobbyFrame:PointToObjectSpace(pos)
	local hx, hz = A.LobbySize.X / 2 - inset, A.LobbySize.Z / 2 - inset
	return ArenaLayout.LobbyFrame * Vector3.new(math.clamp(rel.X, -hx, hx), rel.Y, math.clamp(rel.Z, -hz, hz))
end

function ArenaLayout.lobbySpawn(rng: Random): Vector3
	local s = Config.Lobby.Spawn
	return ArenaLayout.lobbyPoint(
		s.X + rng:NextNumber(-s.Spread, s.Spread),
		4,
		s.F + rng:NextNumber(-s.Spread, s.Spread)
	)
end

-- Where hub players face and look on (re)spawn: the middle of the court.
ArenaLayout.CourtFocus = A.Origin + Vector3.new(0, 2, 0)

ArenaLayout.LobbyVoidY = A.LobbyOrigin.Y - A.VoidDepth
local practice = Config.Lobby.Practice
ArenaLayout.DummyHome = ArenaLayout.lobbyPoint(practice.DummyX, 4, practice.F)
ArenaLayout.PracticeBallHome = ArenaLayout.lobbyPoint(practice.BallX, 2, practice.F)
-- the dummy faces back into the practice zone (it gets launched off the open end behind it)
ArenaLayout.DummyFacing = ArenaLayout.lobbyPoint(practice.DummyX + 10, 4, practice.F)

return ArenaLayout
