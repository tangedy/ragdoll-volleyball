--!strict
-- Intro poses: what each player does while the match-start camera pans across their team
-- (Splatoon-style). Each pose is a short looping sequence of frames; a frame is a set of arm segment directions in UpperTorso space
-- (+X = the character's right, -Z = forward, +Y = up) plus optional head/waist angles in degrees.
-- The client's PoseKit solves frames onto each rig's own joints, so they fit any body and work on
-- both new (AnimationConstraint) and classic (Motor6D) R15 rigs. Catalog "Pose" items name a pose
-- here with Data.Pose.

export type Segment = { upper: Vector3, fore: Vector3 }
export type Frame = {
	Right: Segment?,
	Left: Segment?,
	neck: number?, -- + look up, - bow the head
	waist: number?, -- + lean back, - bend forward
	twist: number?, -- + turn the chest to the character's left
}
export type Pose = {
	Name: string,
	Frames: { { frame: string, hold: number } }, -- played in order, then looped
	Blend: number, -- seconds to blend into each frame
	-- a one-shot effect replayed each time the sequence loops (IntroController): "Confetti" = a gold
	-- and white particle burst above the head
	Fx: string?,
	-- something worn for the whole pose (IntroController, and the shop portrait): "PumpkinHead" = a
	-- jack-o-lantern over the head (the head and its hats hidden inside)
	Prop: string?,
}

local REST_R: Segment = { upper = Vector3.new(0.12, -1, 0.02), fore = Vector3.new(0.08, -1, -0.12) }
local REST_L: Segment = { upper = Vector3.new(-0.12, -1, 0.02), fore = Vector3.new(-0.08, -1, -0.12) }
-- hand resting on the hip
local HIP_L: Segment = { upper = Vector3.new(-0.7, -0.6, 0.3), fore = Vector3.new(0.75, -0.45, -0.25) }

local function mirror(s: Segment): Segment
	return { upper = s.upper * Vector3.new(-1, 1, 1), fore = s.fore * Vector3.new(-1, 1, 1) }
end

local cheerUp: Segment = { upper = Vector3.new(0.3, 0.95, 0), fore = Vector3.new(0.12, 1, 0.05) }
local cheerPump: Segment = { upper = Vector3.new(0.8, 0.5, -0.1), fore = Vector3.new(0.05, 1, 0) }
local flexA: Segment = { upper = Vector3.new(1, 0.15, 0), fore = Vector3.new(0.05, 1, 0) }
local flexB: Segment = { upper = Vector3.new(1, 0.05, -0.2), fore = Vector3.new(-0.3, 1, 0) }
local waveUp: Segment = { upper = Vector3.new(0.65, 0.75, -0.1), fore = Vector3.new(0.6, 0.8, 0) }
local waveOver: Segment = { upper = Vector3.new(0.65, 0.75, -0.1), fore = Vector3.new(-0.25, 1, 0) }
local point: Segment = { upper = Vector3.new(0.12, -0.05, -1), fore = Vector3.new(0.02, 0.04, -1) }
local pointUp: Segment = { upper = Vector3.new(0.15, 0.3, -0.95), fore = Vector3.new(0.05, 0.4, -0.9) }
-- forearm up in front of the chest, fist on top
local thumbA: Segment = { upper = Vector3.new(0.3, -0.35, -0.9), fore = Vector3.new(0, 1, -0.2) }
local thumbB: Segment = { upper = Vector3.new(0.25, -0.1, -0.95), fore = Vector3.new(0.05, 0.95, -0.35) }
-- elbows at the sides, palms out and up
local shrugA: Segment = { upper = Vector3.new(0.45, -0.9, 0.05), fore = Vector3.new(0.85, 0.15, -0.5) }
local shrugB: Segment = { upper = Vector3.new(0.55, -0.8, 0.05), fore = Vector3.new(0.85, 0.4, -0.35) }
-- hands apart in front, then meeting in the middle
local clapOpen: Segment = { upper = Vector3.new(0.4, -0.5, -0.75), fore = Vector3.new(0.45, 0.15, -0.88) }
local clapShut: Segment = { upper = Vector3.new(0.3, -0.5, -0.8), fore = Vector3.new(-0.55, 0.15, -0.82) }
-- elbow out, fingertips at the brow
local salute: Segment = { upper = Vector3.new(0.85, 0.35, -0.35), fore = Vector3.new(-0.75, 0.6, -0.15) }
-- left hand out on the neck, right hand strumming at the hip
local guitarNeck: Segment = { upper = Vector3.new(-0.7, -0.2, -0.65), fore = Vector3.new(-0.55, 0.15, -0.82) }
local strumUp: Segment = { upper = Vector3.new(0.4, -0.85, -0.3), fore = Vector3.new(-0.6, -0.05, -0.8) }
local strumDown: Segment = { upper = Vector3.new(0.4, -0.8, -0.4), fore = Vector3.new(-0.45, -0.65, -0.6) }
-- robot: one arm a raised right angle, the other a lowered one
local robotUp: Segment = { upper = Vector3.new(1, 0, 0), fore = Vector3.new(0, 1, 0) }
local robotDown: Segment = { upper = Vector3.new(1, 0, 0), fore = Vector3.new(0, -1, 0) }
-- both hands together overhead, holding the trophy up
local trophyHigh: Segment = { upper = Vector3.new(0.2, 1, 0), fore = Vector3.new(-0.18, 1, 0) }
local trophyPump: Segment = { upper = Vector3.new(0.3, 0.8, -0.2), fore = Vector3.new(-0.3, 0.95, -0.05) }
-- Frankenstein's monster: both arms stuck straight out in front, rocking side to side
local zombieHigh: Segment = { upper = Vector3.new(0.14, 0.05, -1), fore = Vector3.new(0.08, 0.06, -1) }
local zombieLow: Segment = { upper = Vector3.new(0.18, -0.12, -1), fore = Vector3.new(0.1, -0.08, -1) }

local IntroPoses = {}

IntroPoses.Frames = {
	CheerUp = { Right = cheerUp, Left = mirror(cheerUp), neck = 15 },
	CheerPump = { Right = cheerPump, Left = mirror(cheerPump), neck = 8 },
	FlexA = { Right = flexA, Left = mirror(flexA), neck = -5, twist = 8 },
	FlexB = { Right = flexB, Left = mirror(flexB), neck = 0, twist = -8, waist = -6 },
	WaveA = { Right = waveUp, Left = REST_L, neck = 6 },
	WaveB = { Right = waveOver, Left = REST_L, neck = 6 },
	PointAt = { Right = point, Left = HIP_L, neck = 2 },
	PointUp = { Right = pointUp, Left = HIP_L, neck = 8, twist = 6 },
	BowDown = {
		Right = { upper = Vector3.new(0.1, -0.75, -0.6), fore = Vector3.new(-1, 0.1, -0.25) },
		Left = { upper = Vector3.new(-0.85, -0.45, 0.1), fore = Vector3.new(-0.7, -0.65, 0.2) },
		neck = -20,
		waist = -45,
	},
	BowUp = { Right = REST_R, Left = REST_L, neck = 5, waist = 0 },
	DabWind = { Right = REST_R, Left = REST_L, neck = 0, twist = 10 },
	Dab = {
		Right = { upper = Vector3.new(0.75, 0.62, -0.15), fore = Vector3.new(0.72, 0.65, -0.2) },
		Left = { upper = Vector3.new(0.35, 0.55, -0.75), fore = Vector3.new(0.95, 0.15, -0.25) },
		neck = -35,
		twist = -12,
	},
	ThumbA = { Right = thumbA, Left = HIP_L, neck = 4 },
	ThumbB = { Right = thumbB, Left = HIP_L, neck = 8, twist = 4 },
	ShrugA = { Right = shrugA, Left = mirror(shrugA), neck = 6 },
	ShrugB = { Right = shrugB, Left = mirror(shrugB), neck = 14, waist = 3 },
	ClapOpen = { Right = clapOpen, Left = mirror(clapOpen), neck = 4 },
	ClapShut = { Right = clapShut, Left = mirror(clapShut), neck = 2 },
	Salute = { Right = salute, Left = REST_L, neck = 4 },
	SaluteHold = { Right = salute, Left = REST_L, neck = 8, waist = 2 },
	StrumUp = { Right = strumUp, Left = guitarNeck, neck = 4, waist = 10, twist = 8 },
	StrumDown = { Right = strumDown, Left = guitarNeck, neck = -14, waist = 6, twist = 8 },
	RobotA = { Right = robotUp, Left = mirror(robotDown), neck = 0, twist = 15 },
	RobotB = { Right = robotDown, Left = mirror(robotUp), neck = 0, twist = -15 },
	TrophyHigh = { Right = trophyHigh, Left = mirror(trophyHigh), neck = 25, waist = 6 },
	TrophyPump = { Right = trophyPump, Left = mirror(trophyPump), neck = 18, waist = 2 },
	FrankLeft = { Right = zombieLow, Left = mirror(zombieHigh), neck = -6, waist = -4, twist = 12 },
	FrankRight = { Right = zombieHigh, Left = mirror(zombieLow), neck = -6, waist = -4, twist = -12 },
} :: { [string]: Frame }

IntroPoses.Poses = {
	Cheer = {
		Name = "Fist Pump",
		Blend = 0.16,
		Frames = { { frame = "CheerUp", hold = 0.36 }, { frame = "CheerPump", hold = 0.36 } },
	},
	Wave = {
		Name = "Big Wave",
		Blend = 0.18,
		Frames = { { frame = "WaveA", hold = 0.3 }, { frame = "WaveB", hold = 0.3 } },
	},
	Flex = { Name = "Flex", Blend = 0.3, Frames = { { frame = "FlexA", hold = 0.7 }, { frame = "FlexB", hold = 0.7 } } },
	Point = {
		Name = "You're Next",
		Blend = 0.28,
		Frames = { { frame = "PointAt", hold = 0.9 }, { frame = "PointUp", hold = 0.7 } },
	},
	Bow = {
		Name = "Take a Bow",
		Blend = 0.45,
		Frames = { { frame = "BowDown", hold = 1.3 }, { frame = "BowUp", hold = 0.9 } },
	},
	Dab = { Name = "Dab", Blend = 0.14, Frames = { { frame = "DabWind", hold = 0.45 }, { frame = "Dab", hold = 1.8 } } },
	ThumbsUp = {
		Name = "Thumbs Up",
		Blend = 0.2,
		Frames = { { frame = "ThumbA", hold = 0.6 }, { frame = "ThumbB", hold = 0.6 } },
	},
	Shrug = {
		Name = "Shrug",
		Blend = 0.22,
		Frames = { { frame = "ShrugA", hold = 0.5 }, { frame = "ShrugB", hold = 0.7 } },
	},
	Clap = {
		Name = "Clap",
		Blend = 0.08,
		Frames = { { frame = "ClapOpen", hold = 0.2 }, { frame = "ClapShut", hold = 0.16 } },
	},
	Salute = {
		Name = "Salute",
		Blend = 0.25,
		Frames = { { frame = "Salute", hold = 1.1 }, { frame = "SaluteHold", hold = 0.9 } },
	},
	AirGuitar = {
		Name = "Air Guitar",
		Blend = 0.1,
		Frames = { { frame = "StrumUp", hold = 0.22 }, { frame = "StrumDown", hold = 0.22 } },
	},
	-- tiny blends make the moves snap like a robot's
	Robot = {
		Name = "Robot",
		Blend = 0.04,
		Frames = { { frame = "RobotA", hold = 0.45 }, { frame = "RobotB", hold = 0.45 } },
	},
	TrophyLift = {
		Name = "Trophy Lift",
		Blend = 0.2,
		Fx = "Confetti",
		Frames = { { frame = "TrophyHigh", hold = 0.8 }, { frame = "TrophyPump", hold = 0.45 } },
	},
	-- slow, stiff blends: a lumbering monster with a jack-o-lantern for a head
	PumpkinHead = {
		Name = "Pumpkin Head",
		Blend = 0.5,
		Prop = "PumpkinHead",
		Frames = { { frame = "FrankLeft", hold = 0.75 }, { frame = "FrankRight", hold = 0.75 } },
	},
} :: { [string]: Pose }

IntroPoses.Default = "Cheer"

function IntroPoses.get(name: string?): Pose
	return IntroPoses.Poses[name or ""] or IntroPoses.Poses[IntroPoses.Default]
end

return IntroPoses
