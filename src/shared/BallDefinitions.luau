--!strict
-- Ball types (spec v0.1 §8). Visuals stay readable while held and in flight.

export type BallType = "Standard" | "Heavy" | "Rocket" | "Pop"

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
		Trail = false,
	},
}

local BallDefinitions = {}

BallDefinitions.Defs = Defs
BallDefinitions.PowerTypes = { "Heavy", "Rocket", "Pop" } :: { BallType }

function BallDefinitions.get(ballType: string): BallDef
	return Defs[ballType] or Defs["Standard"]
end

return BallDefinitions
