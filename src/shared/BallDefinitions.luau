--!strict
-- Ball types (spec v0.1 §8). Visuals stay readable while held and in flight.

-- Heavy, Rocket and Pop come from the ball powers (PowerDefinitions); Frost from the Frost power and
-- Meteor from Heavy's ultimate. None of them spawn on their own any more.
-- Curve, Bounce, Gravity and Thunder come from those powers' actives.
export type BallType =
	"Standard"
	| "Heavy"
	| "Rocket"
	| "Pop"
	| "Frost"
	| "Meteor"
	| "Curve"
	| "Bounce"
	| "Gravity"
	| "Thunder"

export type BallDef = {
	Type: BallType,
	DisplayName: string,
	Color: Color3,
	Material: Enum.Material,
	RadiusScale: number,
	SpeedScale: number,
	GravityScale: number,
	HorizontalKnockbackScale: number,
	UpwardKnockbackScale: number,
	DamageScale: number, -- × Config.Damage.PerHit: power balls build damage % faster
	Trail: boolean,
}

local Defs: { [string]: BallDef } = {
	Standard = {
		Type = "Standard",
		DisplayName = "Standard",
		Color = Color3.fromRGB(214, 48, 49),
		Material = Enum.Material.SmoothPlastic,
		RadiusScale = 1,
		SpeedScale = 1,
		GravityScale = 1,
		HorizontalKnockbackScale = 1,
		UpwardKnockbackScale = 1,
		DamageScale = 1,
		Trail = false,
	},
	Heavy = {
		Type = "Heavy",
		DisplayName = "HEAVY",
		Color = Color3.fromRGB(255, 140, 20),
		Material = Enum.Material.Metal,
		RadiusScale = 1.45,
		SpeedScale = 0.8,
		GravityScale = 1.3,
		HorizontalKnockbackScale = 1.25,
		UpwardKnockbackScale = 1,
		DamageScale = 1.75,
		Trail = false,
	},
	Rocket = {
		Type = "Rocket",
		DisplayName = "ROCKET",
		Color = Color3.fromRGB(40, 140, 255),
		Material = Enum.Material.Neon,
		RadiusScale = 1,
		SpeedScale = 1.35,
		GravityScale = 0.5,
		HorizontalKnockbackScale = 0.85,
		UpwardKnockbackScale = 1,
		DamageScale = 1.5,
		Trail = true,
	},
	Pop = {
		Type = "Pop",
		DisplayName = "POP",
		Color = Color3.fromRGB(170, 70, 230),
		Material = Enum.Material.Neon,
		RadiusScale = 1.1,
		SpeedScale = 1,
		GravityScale = 1,
		HorizontalKnockbackScale = 0.55,
		UpwardKnockbackScale = 2.2,
		DamageScale = 1.5,
		Trail = false,
	},
	-- Frost power: a normal throw that freezes whoever it hits (PowerService.freeze) instead of
	-- launching them, so a teammate can follow up
	Frost = {
		Type = "Frost",
		DisplayName = "FROST",
		Color = Color3.fromRGB(150, 225, 255),
		Material = Enum.Material.Ice,
		RadiusScale = 1.1,
		SpeedScale = 1.05,
		GravityScale = 0.9,
		HorizontalKnockbackScale = 0.2,
		UpwardKnockbackScale = 0.2,
		DamageScale = 1.25,
		Trail = true,
	},
	-- Heavy's ultimate: a huge slow ball whose impact (hit or miss) sends out a shockwave
	Meteor = {
		Type = "Meteor",
		DisplayName = "METEOR",
		Color = Color3.fromRGB(255, 90, 30),
		Material = Enum.Material.CrackedLava,
		RadiusScale = 2.6,
		SpeedScale = 0.85,
		GravityScale = 0.9,
		HorizontalKnockbackScale = 1.6,
		UpwardKnockbackScale = 1.3,
		DamageScale = 2.5,
		Trail = true,
	},
	-- Curve power: bends hard toward its target (PowerService.onLaunch)
	Curve = {
		Type = "Curve",
		DisplayName = "CURVE",
		Color = Color3.fromRGB(140, 255, 90),
		Material = Enum.Material.Neon,
		RadiusScale = 1,
		SpeedScale = 1,
		GravityScale = 0.8,
		HorizontalKnockbackScale = 1,
		UpwardKnockbackScale = 1,
		DamageScale = 1.15,
		Trail = true,
	},
	-- Bounce power: ricochets into a second enemy after it lands (PowerService.onImpact)
	Bounce = {
		Type = "Bounce",
		DisplayName = "BOUNCE",
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.SmoothPlastic,
		RadiusScale = 1.05,
		SpeedScale = 1,
		GravityScale = 1,
		HorizontalKnockbackScale = 0.9,
		UpwardKnockbackScale = 1.2,
		DamageScale = 1.1,
		Trail = false,
	},
	-- Gravity power: pulls nearby enemies in where it lands
	Gravity = {
		Type = "Gravity",
		DisplayName = "GRAVITY",
		Color = Color3.fromRGB(90, 40, 140),
		Material = Enum.Material.Glass,
		RadiusScale = 1.2,
		SpeedScale = 0.95,
		GravityScale = 1.1,
		HorizontalKnockbackScale = 0.9,
		UpwardKnockbackScale = 0.8,
		DamageScale = 1.2,
		Trail = true,
	},
	-- Thunder power: its hit chains lightning to nearby enemies
	Thunder = {
		Type = "Thunder",
		DisplayName = "THUNDER",
		Color = Color3.fromRGB(255, 245, 120),
		Material = Enum.Material.Neon,
		RadiusScale = 1,
		SpeedScale = 1.15,
		GravityScale = 0.7,
		HorizontalKnockbackScale = 1,
		UpwardKnockbackScale = 1,
		DamageScale = 1.3,
		Trail = true,
	},
}

local BallDefinitions = {}

BallDefinitions.Defs = Defs
BallDefinitions.PowerTypes = { "Heavy", "Rocket", "Pop" } :: { BallType }

function BallDefinitions.get(ballType: string): BallDef
	return Defs[ballType] or Defs["Standard"]
end

return BallDefinitions
