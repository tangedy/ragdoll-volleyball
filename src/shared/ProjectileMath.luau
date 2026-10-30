--!strict
-- Pure projectile helpers shared by the server simulation and the client trajectory preview.

local Config = require(script.Parent.Config)
local BallDefinitions = require(script.Parent.BallDefinitions)

local ProjectileMath = {}

-- Every throw is instant and full power: there is no charging.
function ProjectileMath.throwSpeed(ballType: string): number
	return Config.Player.ThrowSpeed * BallDefinitions.get(ballType).SpeedScale
end

function ProjectileMath.gravity(ballType: string): number
	return Config.Ball.Gravity * BallDefinitions.get(ballType).GravityScale
end

function ProjectileMath.radius(ballType: string): number
	return Config.Ball.Radius * BallDefinitions.get(ballType).RadiusScale
end

-- Position after t seconds of ballistic flight.
function ProjectileMath.positionAt(origin: Vector3, velocity: Vector3, gravity: number, t: number): Vector3
	return origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
end

function ProjectileMath.velocityAt(velocity: Vector3, gravity: number, t: number): Vector3
	return velocity + Vector3.new(0, -gravity * t, 0)
end

function ProjectileMath.isFiniteVector(v: Vector3): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < 1e6
		and math.abs(v.Y) < 1e6
		and math.abs(v.Z) < 1e6
end

-- Clamp an aim direction's pitch to the allowed bounds; returns a unit vector or nil if invalid.
function ProjectileMath.sanitizeDirection(dir: Vector3): Vector3?
	if not ProjectileMath.isFiniteVector(dir) or dir.Magnitude < 0.5 or dir.Magnitude > 2 then
		return nil
	end
	local unit = dir.Unit
	local flat = Vector3.new(unit.X, 0, unit.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	local pitch = math.asin(math.clamp(unit.Y, -1, 1))
	local maxUp = math.rad(Config.Player.MaxPitchUpDeg)
	local maxDown = math.rad(Config.Player.MaxPitchDownDeg)
	pitch = math.clamp(pitch, -maxDown, maxUp)
	local flatUnit = flat.Unit
	return (flatUnit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
end

-- Rotate a unit vector by a random angle inside a cone of the given half-angle (degrees).
function ProjectileMath.randomInCone(dir: Vector3, halfAngleDeg: number, rng: Random): Vector3
	if halfAngleDeg <= 0 then
		return dir
	end
	local angle = math.rad(halfAngleDeg) * math.sqrt(rng:NextNumber())
	local spin = rng:NextNumber() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local offset = CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)
	return (cf * offset).LookVector
end

-- Knockback scale at `damage` % (before this hit): tiny at first, growing with every hit.
function ProjectileMath.escalation(damage: number): number
	local e = Config.Knockback.Escalation
	return math.min(e.First + e.PerPercent * math.max(damage, 0), e.Max)
end

-- Horizontal distance between two points (throw origin -> hit point).
function ProjectileMath.flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

-- Damage % a hit adds, by ball type (power balls hit harder) and, when known, how far the ball
-- travelled: point blank hits deal Config.Damage.CloseMultiplier×, falling off to 1× at FarRange.
function ProjectileMath.damageFor(ballType: string, distance: number?): number
	local d = Config.Damage
	local base = d.PerHit * BallDefinitions.get(ballType).DamageScale
	local mult = 1
	if distance then
		local t = math.clamp((distance - d.CloseRange) / (d.FarRange - d.CloseRange), 0, 1)
		mult = d.CloseMultiplier + (1 - d.CloseMultiplier) * t
	end
	return math.floor(base * mult + 0.5)
end

-- HUD / billboard color for a damage %: white -> yellow -> red (Toybox paper, sun, joyRed).
function ProjectileMath.damageColor(damage: number): Color3
	local d = Config.Damage
	local white, yellow, red = Color3.fromHex("#fffcf2"), Color3.fromHex("#f7cd46"), Color3.fromHex("#ff4b3a")
	if damage <= d.YellowAt then
		return white:Lerp(yellow, math.clamp(damage / d.YellowAt, 0, 1))
	end
	return yellow:Lerp(red, math.clamp((damage - d.YellowAt) / (d.RedAt - d.YellowAt), 0, 1))
end

-- Speed cap for a launch at this escalation (big late-game launches go past the base cap).
function ProjectileMath.maxKnockbackSpeed(scale: number): number
	return Config.Knockback.MaxSpeed * math.max(scale, 1)
end

-- How long a hit at this escalation keeps you ragdolled.
function ProjectileMath.ragdollDuration(scale: number): number
	return Config.Player.RagdollDuration * math.clamp(0.7 + 0.3 * scale, 0.75, 1.4)
end

-- Knockback velocity change for a hit (spec §7 "Knockback"). Bounded and mass-independent.
-- `scale` is the escalation from ProjectileMath.escalation (1 when left out).
function ProjectileMath.knockback(ballVelocity: Vector3, ballType: string, scale: number?): Vector3
	local def = BallDefinitions.get(ballType)
	local kb = Config.Knockback
	local k = scale or 1
	local flat = Vector3.new(ballVelocity.X, 0, ballVelocity.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)
	local horizontal = kb.Horizontal * def.HorizontalKnockbackScale * k
	-- the hop grows more gently than the push, so big hits fly far rather than straight up
	local up = kb.Upward * def.UpwardKnockbackScale * math.clamp(k, 0.5, 1.4)
	local v = dir * horizontal + Vector3.new(0, up, 0)
	local cap = ProjectileMath.maxKnockbackSpeed(k)
	if v.Magnitude > cap then
		v = v.Unit * cap
	end
	return v
end

return ProjectileMath
