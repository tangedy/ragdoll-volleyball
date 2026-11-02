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

-- A CFrame at `pos` looking level at `target` (no tilt); straight down +Z if `target` is overhead.
-- Every teleport and spawn faces through this so nothing is left with a stale yaw.
function ArenaLayout.faceFlat(pos: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.1 then
		flat = pos + Vector3.zAxis
	end
	return CFrame.lookAt(pos, flat)
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

-- Opening ball spots: symmetric, near the center line, half per side.
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
-- Finishers ---------------------------------------------------------------------------------------
-- Finishers play on the real court or on the shop preview's copy, so these take the court's origin
-- (defaults to the real one) and work in court-relative terms.

-- Horizontal distance from `pos` along `dir` to the court's back edge (the end `dir` heads for).
function ArenaLayout.distanceToBackEdge(pos: Vector3, dir: Vector3, origin: Vector3?): number
	local o = origin or A.Origin
	local dz = Vector3.new(dir.X, 0, dir.Z).Unit.Z
	if math.abs(dz) < 0.2 then
		return ArenaLayout.HalfWidth -- heading sideways: a side edge is about this far
	end
	local rel = pos.Z - o.Z
	local edge = (if dz > 0 then 1 else -1) * ArenaLayout.HalfLength
	return math.max((edge - rel) / dz, 0)
end

-- The launch that sends a finisher's victim off the far end: it keeps the finisher's upward speed
-- (Stage.Up) and pushes outward at least Stage.Out, more if that's what it takes to clear the
-- gap, the jail strip and its 4-stud wall behind the court, so it lands in the void whatever the
-- court size. Returns the velocity and the speed cap to ragdoll it with.
local JAIL_WALL = 4
function ArenaLayout.finisherLaunch(
	victimAt: Vector3,
	killerAt: Vector3,
	stage: any,
	origin: Vector3?
): (Vector3, number)
	local outward = Vector3.new(victimAt.X - killerAt.X, 0, victimAt.Z - killerAt.Z)
	outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.zAxis
	local up = tonumber(stage.Up) or 60
	local out = tonumber(stage.Out) or 45
	-- clear past the jail's far wall, with the root a body-height above the wall top
	local clear = ArenaLayout.distanceToBackEdge(victimAt, outward, origin) + J.Gap + J.StripDepth + 3
	local rise = JAIL_WALL + 4 - (victimAt.Y - (origin or A.Origin).Y) -- height to gain at that point
	local g = workspace.Gravity
	local disc = up * up - 2 * g * math.max(rise, 0)
	if disc > 0 then
		-- the latest time the arc is still high enough, and the outward speed to be past by then
		local t = (up + math.sqrt(disc)) / g
		out = math.max(out, clear / t)
	end
	local v = outward * out + Vector3.new(0, up, 0)
	return v, v.Magnitude + Config.Knockback.LimbFlail
end

ArenaLayout.PracticeBallHome = ArenaLayout.lobbyPoint(practice.BallX, 2, practice.F)
-- the dummy faces back into the practice zone (it gets launched off the open end behind it)
ArenaLayout.DummyFacing = ArenaLayout.lobbyPoint(practice.DummyX + 10, 4, practice.F)

return ArenaLayout
