--!strict
-- Every sound cue in one table. A cue is a stack of layers played together, so a "hit" can be a
-- low thump + a sharp crack + a slap instead of one thin sample. Layers use Roblox's built-in
-- engine sounds (rbxasset://sounds, verified to load in Studio), shaped with EQ/distortion.
-- To use your own uploaded audio, replace a layer's `id` with "rbxassetid://<id>".

export type Layer = {
	id: string,
	volume: number,
	pitch: number,
	delay: number?, -- seconds after the cue starts
	jitter: number?, -- random pitch variation (fraction), so repeats don't sound robotic
	eq: { low: number, mid: number, high: number }?, -- dB gains
	distortion: number?, -- 0..1
	reverb: boolean?,
	startAt: number?, -- TimePosition to start from (trim long samples)
	stopAfter: number?, -- seconds; cut long samples short
}

local S = "rbxasset://sounds/"

local Cues: { [string]: { Layer } } = {
	-- Combat
	Throw = {
		{ id = S .. "swordlunge.wav", volume = 0.45, pitch = 1.25, jitter = 0.08, eq = { low = -6, mid = 0, high = 3 } },
	},
	Hit = {
		-- body: a deep, slightly crunchy thump
		{ id = S .. "bass.wav", volume = 1.0, pitch = 1.9, jitter = 0.05, eq = { low = 8, mid = 2, high = -4 }, distortion = 0.35, stopAfter = 0.35 },
		-- transient: the crack you feel
		{ id = S .. "snap.wav", volume = 0.75, pitch = 0.8, jitter = 0.06, eq = { low = 0, mid = 3, high = 4 } },
		-- slap tail
		{ id = S .. "hit.wav", volume = 0.5, pitch = 1.2, jitter = 0.06, delay = 0.01 },
	},
	HitHeavy = {
		{ id = S .. "bass.wav", volume = 1.0, pitch = 1.4, jitter = 0.04, eq = { low = 10, mid = 0, high = -6 }, distortion = 0.5, stopAfter = 0.5 },
		{ id = S .. "snap.wav", volume = 0.8, pitch = 0.6, jitter = 0.05 },
		{ id = S .. "metal.ogg", volume = 0.35, pitch = 0.7, delay = 0.02 },
	},
	Catch = {
		{ id = S .. "snap.wav", volume = 0.7, pitch = 1.35, jitter = 0.05 },
		{ id = S .. "button.wav", volume = 0.5, pitch = 0.8, delay = 0.03 },
	},
	Dodge = {
		{ id = S .. "swordlunge.wav", volume = 0.3, pitch = 1.6, jitter = 0.1, eq = { low = -10, mid = 0, high = 2 } },
	},
	Pickup = {
		{ id = S .. "clickfast.wav", volume = 0.35, pitch = 1.3, jitter = 0.05 },
	},
	-- Eliminations
	Elimination = {
		-- the eliminator's sting: big boom + glassy sparkle + rising ping
		{ id = S .. "bass.wav", volume = 1.0, pitch = 0.9, eq = { low = 10, mid = 0, high = -3 }, distortion = 0.4, stopAfter = 0.8 },
		{ id = S .. "glassbreak.wav", volume = 0.35, pitch = 1.3, delay = 0.02 },
		{ id = S .. "electronicpingshort.wav", volume = 0.6, pitch = 1.5, delay = 0.08 },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 2.0, delay = 0.2 },
	},
	VoidFall = {
		{ id = S .. "impact_water.mp3", volume = 0.5, pitch = 1.1, jitter = 0.06, stopAfter = 1.2, reverb = true },
		{ id = S .. "bass.wav", volume = 0.6, pitch = 0.7, eq = { low = 8, mid = -2, high = -8 }, stopAfter = 0.6 },
	},
	KnockedOut = {
		{ id = S .. "bass.wav", volume = 0.8, pitch = 0.6, eq = { low = 8, mid = -3, high = -8 }, stopAfter = 0.9 },
		{ id = S .. "electronicpingshort.wav", volume = 0.4, pitch = 0.5, delay = 0.05 },
	},
	Jail = {
		{ id = S .. "metal.ogg", volume = 0.55, pitch = 0.75 },
		{ id = S .. "metal.ogg", volume = 0.4, pitch = 0.6, delay = 0.12 },
	},
	JailEscape = {
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 1.2 },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 1.6, delay = 0.1 },
	},
	Revenge = {
		{ id = S .. "victory.wav", volume = 0.5, pitch = 1.3, stopAfter = 0.8 },
		{ id = S .. "snap.wav", volume = 0.6, pitch = 0.9 },
	},
	-- Match flow
	CountdownTick = {
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 1.0 },
	},
	Go = {
		{ id = S .. "electronicpingshort.wav", volume = 0.55, pitch = 1.6 },
		{ id = S .. "bass.wav", volume = 0.6, pitch = 1.6, stopAfter = 0.3, distortion = 0.2 },
	},
	LastPlayer = {
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.75 },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.75, delay = 0.18 },
	},
	SuddenDeath = {
		{ id = S .. "bass.wav", volume = 1.0, pitch = 0.45, eq = { low = 10, mid = 0, high = -10 }, distortion = 0.6, reverb = true },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.55, delay = 0.1 },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.55, delay = 0.45 },
	},
	StripWarn = {
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 0.9 },
	},
	StripDrop = {
		{ id = S .. "bass.wav", volume = 0.6, pitch = 0.8, eq = { low = 6, mid = 0, high = -6 }, stopAfter = 0.5 },
		{ id = S .. "collide.wav", volume = 0.35, pitch = 0.7 },
	},
	RoundWin = {
		{ id = S .. "victory.wav", volume = 0.6, pitch = 1.0 },
	},
	RoundLose = {
		{ id = S .. "victory.wav", volume = 0.35, pitch = 0.7 },
	},
	Finisher = {
		{ id = S .. "bass.wav", volume = 1.0, pitch = 0.7, eq = { low = 10, mid = 0, high = -4 }, distortion = 0.5, reverb = true },
		{ id = S .. "glassbreak.wav", volume = 0.4, pitch = 0.9, delay = 0.05 },
		{ id = S .. "victory.wav", volume = 0.5, pitch = 1.1, delay = 0.35 },
	},
	-- Meteor Strike finisher
	MeteorCharge = {
		{ id = S .. "bass.wav", volume = 0.9, pitch = 0.35, eq = { low = 10, mid = 0, high = -10 }, distortion = 0.4, reverb = true, stopAfter = 1.4 },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 0.45, delay = 0.25, reverb = true },
	},
	MeteorFall = {
		{ id = S .. "swordlunge.wav", volume = 0.7, pitch = 0.35, eq = { low = 6, mid = 0, high = -4 }, reverb = true },
		{ id = S .. "swordlunge.wav", volume = 0.5, pitch = 0.5, delay = 0.45, reverb = true },
		{ id = S .. "bass.wav", volume = 0.6, pitch = 0.5, delay = 0.6, distortion = 0.5, stopAfter = 0.9 },
	},
	MeteorImpact = {
		{ id = S .. "bass.wav", volume = 1.0, pitch = 0.55, eq = { low = 12, mid = 2, high = -6 }, distortion = 0.7, reverb = true },
		{ id = S .. "collide.wav", volume = 0.8, pitch = 0.6, distortion = 0.3 },
		{ id = S .. "glassbreak.wav", volume = 0.45, pitch = 0.7, delay = 0.03 },
		{ id = S .. "impact_water.mp3", volume = 0.4, pitch = 0.6, delay = 0.05, stopAfter = 1.2 },
	},
	-- Pumpkin Reaper finisher
	SpookyToss = {
		{ id = S .. "swordlunge.wav", volume = 0.5, pitch = 0.8, jitter = 0.05 },
	},
	PumpkinCatch = {
		{ id = S .. "snap.wav", volume = 0.6, pitch = 0.6 },
		{ id = S .. "bass.wav", volume = 0.5, pitch = 1.2, stopAfter = 0.25 },
	},
	PumpkinReveal = {
		{ id = S .. "bass.wav", volume = 1.0, pitch = 0.4, eq = { low = 10, mid = 0, high = -8 }, distortion = 0.5, reverb = true, stopAfter = 1.2 },
		{ id = S .. "HalloweenGhost.wav", volume = 0.7, pitch = 1.0, reverb = true, stopAfter = 2.2 },
		{ id = S .. "electronicpingshort.wav", volume = 0.4, pitch = 0.4, delay = 0.05, reverb = true },
	},
	UndeadRise = {
		{ id = S .. "collide.wav", volume = 0.8, pitch = 0.5, distortion = 0.3 },
		{ id = S .. "bass.wav", volume = 0.8, pitch = 0.55, eq = { low = 10, mid = 0, high = -6 }, stopAfter = 0.7 },
		{ id = S .. "impact_water.mp3", volume = 0.35, pitch = 0.45, delay = 0.05, stopAfter = 0.8 },
	},
	Drag = {
		{ id = S .. "swordlunge.wav", volume = 0.6, pitch = 0.3, reverb = true },
		{ id = S .. "HalloweenGhost.wav", volume = 0.45, pitch = 0.8, delay = 0.2, stopAfter = 1.8, reverb = true },
	},
	PowerUp = {
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 1.8 },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 2.4, delay = 0.08 },
	},
	CoinGain = {
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 1.7 },
		{ id = S .. "electronicpingshort.wav", volume = 0.4, pitch = 2.25, delay = 0.07 },
		{ id = S .. "clickfast.wav", volume = 0.3, pitch = 1.6, delay = 0.02 },
	},
	-- UI
	UIClick = {
		{ id = S .. "clickfast.wav", volume = 0.4, pitch = 1.1, jitter = 0.05 },
	},
	UIOpen = {
		{ id = S .. "switch.wav", volume = 0.4, pitch = 1.2 },
	},
	UIError = {
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 0.5 },
	},
	Purchase = {
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 1.3 },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 1.75, delay = 0.09 },
		{ id = S .. "button.wav", volume = 0.4, pitch = 1.0, delay = 0.02 },
	},
	DailyClaim = {
		{ id = S .. "victory.wav", volume = 0.5, pitch = 1.25 },
		{ id = S .. "electronicpingshort.wav", volume = 0.4, pitch = 1.8, delay = 0.1 },
	},
	Banner = {
		{ id = S .. "swordslash.wav", volume = 0.25, pitch = 1.4, jitter = 0.05 },
	},
}

local Sounds = {}

Sounds.Cues = Cues

return Sounds
