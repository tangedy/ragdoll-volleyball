--!strict
-- Pure projectile helpers shared by the server simulation and the client trajectory preview.

local Config = require(script.Parent.Config)
local BallDefinitions = require(script.Parent.BallDefinitions)

local ProjectileMath = {}

-- Charge in [0, 1] from server-recorded hold time. Holding past full charge gives no extra benefit.
function ProjectileMath.chargeFromHold(holdSeconds: number): number
	return math.clamp(holdSeconds / Config.Player.FullChargeTime, 0, 1)
end

function ProjectileMath.throwSpeed(charge: number, ballType: string): number
	local def = BallDefinitions.get(ballType)
	local p = Config.Player
	return (p.MinThrowSpeed + (p.MaxThrowSpeed - p.MinThrowSpeed) * charge) * def.SpeedScale
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

-- Knockback scale after `hitsTaken` earlier hits: tiny at first, growing with every hit.
function ProjectileMath.escalation(hitsTaken: number): number
	local e = Config.Knockback.Escalation
	return math.min(e.First + e.PerHit * math.max(hitsTaken, 0), e.Max)
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
function ProjectileMath.knockback(ballVelocity: Vector3, charge: number, ballType: string, scale: number?): Vector3
	local def = BallDefinitions.get(ballType)
	local kb = Config.Knockback
	local k = scale or 1
	local flat = Vector3.new(ballVelocity.X, 0, ballVelocity.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)
	local horizontal = (kb.HorizontalMin + (kb.HorizontalMax - kb.HorizontalMin) * charge)
		* def.HorizontalKnockbackScale
		* k
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
