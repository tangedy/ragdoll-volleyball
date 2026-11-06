--!strict
-- Equippable powers (Config.Powers). Each power has an active (Kind "Ball": it turns the ball you're
-- holding into a power ball; Kind "Self": it acts on you or the court) on a cooldown, and an ultimate
-- charged by the meter. The shop sells them as Catalog items of Category "Power" whose Data.Power
-- is an id here. PowerService runs them on the server; PowerController drives the buttons.

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
}

local PowerDefinitions = {}

PowerDefinitions.Defs = Defs
-- shop / HUD order
PowerDefinitions.Order = { "Heavy", "Rocket", "Pop", "Blink", "Magnet", "Frost" }

function PowerDefinitions.get(id: string?): PowerDef?
	return if id then Defs[id] else nil
end

-- The ultimate's ball types: a held ball turned into one of these is an ultimate ball (dropping it
-- or getting it caught reverts it to Standard).
PowerDefinitions.UltBallTypes = { Meteor = true } :: { [string]: boolean }

return PowerDefinitions
