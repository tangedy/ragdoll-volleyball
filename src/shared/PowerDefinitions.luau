--!strict
-- Equippable powers (Config.Powers). Each power has an active (Kind "Ball": it turns the ball you're
-- holding into a power ball; Kind "Self": it acts on you or the court) on a cooldown, and an ultimate
-- charged by the meter. The shop sells them as Catalog items of Category "Power" whose Data.Power
-- is an id here. PowerService runs them on the server; PowerController drives the buttons.

local Config = require(script.Parent.Config)

export type PowerKind = "Ball" | "Self"

export type PowerDef = {
	Id: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Kind: PowerKind,
	Cooldown: number, -- seconds
	Ball: string?, -- Kind "Ball": the BallDefinitions type the held ball becomes
	Active: string, -- one line for the shop and the HUD
	Ult: {
		Id: string,
		Name: string,
		Text: string,
		NeedsBall: boolean, -- it powers up the ball you're holding (so you must hold one)
		-- tuning, read by PowerService
		[string]: any,
	},
	[string]: any, -- active tuning, read by PowerService
}

local Defs: { [string]: PowerDef } = {
	Heavy = {
		Id = "Heavy",
		Name = "Heavy",
		Icon = "🪨",
		Color = Color3.fromRGB(255, 140, 20),
		Kind = "Ball",
		Cooldown = 14,
		Ball = "Heavy",
		Active = "Your ball turns HEAVY: bigger, slower, hits much harder.",
		Ult = {
			Id = "Meteor",
			Name = "METEOR",
			BallType = "Meteor",
			Text = "Your ball becomes a giant meteor. Its impact shockwave launches everyone nearby.",
			NeedsBall = true,
			ShockRadius = 18,
			ShockDamage = 18,
		},
	},
	Rocket = {
		Id = "Rocket",
		Name = "Rocket",
		Icon = "🚀",
		Color = Color3.fromRGB(40, 140, 255),
		Kind = "Ball",
		Cooldown = 14,
		Ball = "Rocket",
		Active = "Your ball turns ROCKET: fast and flat.",
		Ult = {
			Id = "Barrage",
			Name = "BARRAGE",
			BallType = "Rocket",
			Text = "Your throw splits into homing rockets, one at each of up to 3 enemies.",
			NeedsBall = true,
			Extra = 2, -- rockets beside your own throw
			TurnDegPerSec = 200,
			MaxTurnDeg = 120,
		},
	},
	Pop = {
		Id = "Pop",
		Name = "Pop",
		Icon = "🎈",
		Color = Color3.fromRGB(170, 70, 230),
		Kind = "Ball",
		Cooldown = 16,
		Ball = "Pop",
		Active = "Your ball turns POP: it launches whoever it hits sky-high.",
		Ult = {
			Id = "Geyser",
			Name = "GEYSER",
			BallType = "Pop",
			Text = "Your POP ball erupts where it lands, launching everyone near it skyward.",
			NeedsBall = true,
			Radius = 14,
			Damage = 16,
		},
	},
	Blink = {
		Id = "Blink",
		Name = "Blink",
		Icon = "💨",
		Color = Color3.fromRGB(120, 255, 200),
		Kind = "Self",
		Cooldown = 10,
		Active = "Teleport a short way where you're moving, untouchable for a moment.",
		Distance = 18,
		Immunity = 0.35,
		Ult = {
			Id = "Phantom",
			Name = "PHANTOM",
			Text = "Turn into a phantom for 4 s: balls pass through you and you run faster.",
			NeedsBall = false,
			Duration = 4,
			SpeedScale = 1.35,
		},
	},
	Magnet = {
		Id = "Magnet",
		Name = "Magnet",
		Icon = "🧲",
		Color = Color3.fromRGB(255, 80, 110),
		Kind = "Self",
		Cooldown = 12,
		Active = "Pull the nearest loose ball on your side straight into your hand.",
		Range = 60,
		Ult = {
			Id = "BallStorm",
			Name = "BALL STORM",
			Text = "Rain 5 extra balls down onto your side of the court.",
			NeedsBall = false,
			Count = 5,
		},
	},
	Frost = {
		Id = "Frost",
		Name = "Frost",
		Icon = "❄️",
		Color = Color3.fromRGB(150, 225, 255),
		Kind = "Ball",
		Cooldown = 18,
		Ball = "Frost",
		Active = "Your ball turns FROST: whoever it hits is frozen solid for a moment.",
		FreezeTime = 1.4,
		Ult = {
			Id = "TimeStop",
			Name = "TIME STOP",
			Text = "Freeze every enemy on the court for 2.5 s.",
			NeedsBall = false,
			Duration = 2.5,
		},
	},

	-- Common --------------------------------------------------------------------------------------
	Curve = {
		Id = "Curve",
		Name = "Curve",
		Icon = "🌀",
		Color = Color3.fromRGB(140, 255, 90),
		Kind = "Ball",
		Cooldown = 12,
		Ball = "Curve",
		Active = "Your ball turns CURVE: it bends hard around to find its target.",
		TurnDegPerSec = 140,
		MaxTurnDeg = 75,
		Ult = {
			Id = "Boomerang",
			Name = "BOOMERANG",
			Text = "A curving throw that flies back into your hand after it hits or misses.",
			NeedsBall = true,
			BallType = "Curve",
			ReturnDelay = 0.35,
		},
	},
	Bounce = {
		Id = "Bounce",
		Name = "Bounce",
		Icon = "🏀",
		Color = Color3.fromRGB(255, 200, 40),
		Kind = "Ball",
		Cooldown = 13,
		Ball = "Bounce",
		Active = "Your ball turns BOUNCE: after it lands it ricochets into another enemy.",
		Range = 45,
		Ult = {
			Id = "Pinball",
			Name = "PINBALL",
			Text = "Your ball pinballs between up to 4 enemies.",
			NeedsBall = true,
			BallType = "Bounce",
			Bounces = 4,
		},
	},

	-- Rare ----------------------------------------------------------------------------------------
	Shield = {
		Id = "Shield",
		Name = "Shield",
		Icon = "🛡️",
		Color = Color3.fromRGB(120, 200, 255),
		Kind = "Self",
		Cooldown = 12,
		Active = "A 1.5 s bubble that catches the next ball for you (or blocks it if your hands are full).",
		Duration = 1.5,
		Ult = {
			Id = "Fortress",
			Name = "FORTRESS",
			Text = "A wall rises along your side of the centre line and blocks enemy balls for 4 s.",
			NeedsBall = false,
			Duration = 4,
		},
	},
	Grapple = {
		Id = "Grapple",
		Name = "Grapple",
		Icon = "🪝",
		Color = Color3.fromRGB(200, 150, 90),
		Kind = "Self",
		Cooldown = 13,
		Active = "Yank the nearest enemy off their feet toward the centre line.",
		Range = 80,
		Pull = 30,
		Ult = {
			Id = "Tether",
			Name = "TETHER",
			Text = "Chain the two nearest enemies together for 6 s: hit one and both go flying.",
			NeedsBall = false,
			Duration = 6,
		},
	},

	-- Epic ----------------------------------------------------------------------------------------
	Decoy = {
		Id = "Decoy",
		Name = "Decoy",
		Icon = "🎭",
		Color = Color3.fromRGB(230, 120, 255),
		Kind = "Self",
		Cooldown = 14,
		Active = "Vanish for 2 s and leave an afterimage: homing throws and bots lose track of you.",
		Duration = 2,
		Ult = {
			Id = "MirrorSquad",
			Name = "MIRROR SQUAD",
			Text = "Three mirror copies of you each throw a real ball at an enemy.",
			NeedsBall = false,
			Count = 3,
		},
	},
	Gravity = {
		Id = "Gravity",
		Name = "Gravity",
		Icon = "🌑",
		Color = Color3.fromRGB(110, 60, 170),
		Kind = "Ball",
		Cooldown = 15,
		Ball = "Gravity",
		Active = "Your ball turns GRAVITY: it drags nearby enemies in where it lands.",
		Radius = 14,
		Damage = 6,
		Ult = {
			Id = "BlackHole",
			Name = "BLACK HOLE",
			Text = "A black hole opens behind the enemy team and drags them toward the edge.",
			NeedsBall = false,
			Duration = 3,
			Pulses = 3,
			Radius = 42,
			Damage = 5,
		},
	},

	-- Legendary -------------------------------------------------------------------------------------
	Giant = {
		Id = "Giant",
		Name = "Giant",
		Icon = "🗿",
		Color = Color3.fromRGB(160, 130, 100),
		Kind = "Self",
		Cooldown = 18,
		Active = "Grow huge for 5 s: hits barely move you (but you're a bigger target).",
		Duration = 5,
		Scale = 1.5,
		KnockbackScale = 0.45,
		Ult = {
			Id = "Titan",
			Name = "TITAN",
			Text = "Become a titan for 6 s: every step you take sends out a shockwave.",
			NeedsBall = false,
			Duration = 6,
			Scale = 2,
			KnockbackScale = 0.3,
			StompEvery = 0.7,
			StompRadius = 12,
			StompDamage = 6,
		},
	},
	Thunder = {
		Id = "Thunder",
		Name = "Thunder",
		Icon = "⚡",
		Color = Color3.fromRGB(255, 240, 90),
		Kind = "Ball",
		Cooldown = 16,
		Ball = "Thunder",
		Active = "Your ball turns THUNDER: its hit chains lightning to 2 nearby enemies.",
		Chains = 2,
		ChainRange = 24,
		ChainDamage = 10,
		Ult = {
			Id = "StormCloud",
			Name = "STORM CLOUD",
			Text = "Lightning strikes enemies 5 times over 2.5 s.",
			NeedsBall = false,
			Strikes = 5,
			Duration = 2.5,
			Damage = 14,
		},
	},

	-- Mythic ----------------------------------------------------------------------------------------
	Rewind = {
		Id = "Rewind",
		Name = "Rewind",
		Icon = "⏪",
		Color = Color3.fromRGB(255, 122, 89),
		Kind = "Self",
		Cooldown = 20,
		Active = "Snap back to where you were 3 s ago, with the damage % you had then. Works mid-tumble.",
		Seconds = 3,
		WhileRagdolled = true,
		Ult = {
			Id = "Replay",
			Name = "REPLAY",
			Text = "Your whole team rewinds 3 s: places and damage %.",
			NeedsBall = false,
			WhileRagdolled = true,
		},
	},

	-- Secret ------------------------------------------------------------------------------------------
	Void = {
		Id = "Void",
		Name = "Void",
		Icon = "🕳️",
		Color = Color3.fromRGB(155, 123, 255),
		Kind = "Self",
		Cooldown = 9,
		Active = "Phase out for 1 s: balls pass straight through you.",
		Duration = 1,
		Ult = {
			Id = "EdgeCollapse",
			Name = "EDGE COLLAPSE",
			Text = "The edges of the enemy court crumble for 4 s, flinging anyone near them off.",
			NeedsBall = false,
			Duration = 4,
			Band = 11, -- studs in from the enemy side and back edges
			Damage = 8,
		},
	},
}

local PowerDefinitions = {}

PowerDefinitions.Defs = Defs
-- shop / HUD order
PowerDefinitions.Order = {
	"Heavy",
	"Rocket",
	"Curve",
	"Bounce",
	"Pop",
	"Blink",
	"Shield",
	"Grapple",
	"Magnet",
	"Decoy",
	"Gravity",
	"Frost",
	"Giant",
	"Thunder",
	"Rewind",
	"Void",
}

function PowerDefinitions.get(id: string?): PowerDef?
	return if id then Defs[id] else nil
end

-- Mastery (Config.Powers.Mastery) -------------------------------------------------------------------

local MASTERY = Config.Powers.Mastery

-- The mastery level for `xp` total mastery XP (1..MaxLevel).
function PowerDefinitions.masteryLevel(xp: number?): number
	local level = 1
	for i, need in MASTERY.Thresholds do
		if (xp or 0) >= need then
			level = i
		end
	end
	return math.min(level, MASTERY.MaxLevel)
end

-- Progress inside the current level: (xp into it, xp it takes), or (0, 0) once Mastered.
function PowerDefinitions.masteryProgress(xp: number?): (number, number)
	local level = PowerDefinitions.masteryLevel(xp)
	if level >= MASTERY.MaxLevel then
		return 0, 0
	end
	local from, to = MASTERY.Thresholds[level], MASTERY.Thresholds[level + 1]
	return (xp or 0) - from, to - from
end

-- The perks of a mastery level.
function PowerDefinitions.masteryPerks(level: number): { cooldown: number, meter: number }
	local l = math.clamp(level, 1, MASTERY.MaxLevel)
	return { cooldown = MASTERY.CooldownScale[l] or 1, meter = MASTERY.MeterScale[l] or 1 }
end

-- The ultimate's ball types: a held ball turned into one of these is an ultimate ball (dropping it
-- or getting it caught reverts it to Standard).
PowerDefinitions.UltBallTypes = { Meteor = true } :: { [string]: boolean }

return PowerDefinitions
