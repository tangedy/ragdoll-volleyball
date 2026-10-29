--!strict
-- Every sound cue in one table. A cue is a stack of layers played together, so a "hit" can be a
-- low thump + a sharp crack + a slap instead of one thin sample. Layers use Roblox's built-in
-- engine sounds (rbxasset://sounds, verified to load in Studio), shaped with EQ/distortion.
-- To use your own uploaded audio, replace a layer's `id` with "rbxassetid://<id>".
-- The dodgeball smacks are free Creator Store sound effects (kirbyzaz's Dodgeball_Impact set).

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
	-- volume follows a gamma curve over stopAfter seconds: rises to full at (shape - 1) * scale,
	-- then tails off, with a short linear fade (tail, seconds) so it ends on silence
	gamma: { shape: number, scale: number, tail: number }?,
}

local S = "rbxasset://sounds/"

-- The ballpark organ's "Charge!" (G C E G . E G), voiced as pings stacked an octave apart. Held notes
-- re-strike softly so they ring on like an organ; the last one is cut dead at 1.7 s, the instant the
-- Out of the Park ball hits.
local function charge(): { Layer }
	local notes =
		{ { 0, 0, 0.15 }, { 5, 0.15, 0.15 }, { 9, 0.3, 0.15 }, { 12, 0.45, 0.4 }, { 9, 0.95, 0.15 }, { 12, 1.1, 0.6 } }
	local layers: { Layer } = {}
	for _, n in notes do
		local pitch, at, hold = 2 ^ (n[1] / 12), n[2], n[3]
		local t = 0
		while t < hold - 1e-3 do
			local v = if t == 0 then 1 else 0.55
			local len = math.min(0.2, hold - t)
			table.insert(layers, {
				id = S .. "electronicpingshort.wav",
				volume = 0.5 * v,
				pitch = pitch,
				delay = at + t,
				stopAfter = len,
			})
			table.insert(layers, {
				id = S .. "electronicpingshort.wav",
				volume = 0.2 * v,
				pitch = pitch * 2,
				delay = at + t,
				stopAfter = len,
			})
			t += 0.1
		end
	end
	return layers
end

-- A buzzy brass note (Sad Trombone, Air Horn): a distorted, mid-boosted bass tone with a quieter
-- octave ping for pitch, `semis` from the base pitch, starting at `at`, lasting `hold` seconds.
-- `wobble` re-strikes it a hair sharp and flat for a vibrato.
local function brass(semis: number, at: number, hold: number, wobble: boolean?): { Layer }
	local pitch = 1.6 * 2 ^ (semis / 12)
	local layers: { Layer } = {}
	local step = if wobble then 0.12 else hold
	local t, i = 0, 0
	while t < hold - 1e-3 do
		local p = if wobble then pitch * (if i % 2 == 0 then 1.015 else 0.985) else pitch
		local len = math.min(step + 0.04, hold - t)
		table.insert(layers, {
			id = S .. "bass.wav",
			volume = 0.6,
			pitch = p,
			delay = at + t,
			eq = { low = -4, mid = 8, high = -2 },
			distortion = 0.55,
			stopAfter = len,
		})
		table.insert(layers, {
			id = S .. "electronicpingshort.wav",
			volume = 0.12,
			pitch = p * 0.5,
			delay = at + t,
			stopAfter = len,
		})
		t += step
		i += 1
	end
	return layers
end

local function concat(...: { Layer }): { Layer }
	local out: { Layer } = {}
	for _, list in { ... } do
		for _, l in list do
			table.insert(out, l)
		end
	end
	return out
end

-- UI vocabulary (Nintendo UX audio study): a few short, dry sounds that each mean one thing, so a
-- menu can be read by ear. Pitch carries the meaning: up = forward / on / success, down = back /
-- off, dull and toneless = a wall or a refusal. Navigation ticks stay under ~100 ms so fast input
-- becomes a rhythm. Only sounds that repeat fast (hover ticks, the wheel, coins) get a little random
-- pitch; deliberate presses (tabs, select, back, open, edge) sound exactly the same every time.
-- Tones are a pitched ping on one scale (`note` = semitones above the UI root), so every UI
-- sound is part of one family.
local UI_ROOT = 1.5
local function note(semitones: number): number
	return UI_ROOT * 2 ^ (semitones / 12)
end
-- a quick run of pinged notes: { semitones, delay, volume } each, cut to `len` seconds
local function run(notes: { { number } }, len: number): { Layer }
	local layers: { Layer } = {}
	for _, n in notes do
		table.insert(layers, {
			id = S .. "electronicpingshort.wav",
			volume = n[3],
			pitch = note(n[1]),
			delay = n[2],
			stopAfter = len,
		})
	end
	return layers
end
local function with(base: { Layer }, extra: { Layer }): { Layer }
	for _, l in extra do
		table.insert(base, l)
	end
	return base
end
local DRY_TICK = S .. "clickfast.wav"
local DULL = { low = 2, mid = -2, high = -14 } -- EQ that takes the ring out of a click

local uiCues: { [string]: { Layer } } = {
	-- cursor / hover / selection moving: a soft, short tick
	UIMove = { { id = DRY_TICK, volume = 0.14, pitch = 1.9, jitter = 0.07, stopAfter = 0.06 } },
	-- switching tabs or segments: a firmer tick with a faint tone
	UITab = with({ { id = DRY_TICK, volume = 0.22, pitch = 1.6, stopAfter = 0.07 } }, run({ { 7, 0, 0.1 } }, 0.06)),
	-- confirm / select: a click and a quick rising fifth
	UIClick = with(
		{ { id = DRY_TICK, volume = 0.3, pitch = 1.35, stopAfter = 0.08 } },
		run({ { 0, 0, 0.18 }, { 7, 0.035, 0.2 } }, 0.07)
	),
	-- back / close: softer and lower, the same fifth falling
	UIBack = with(
		{ { id = DRY_TICK, volume = 0.3, pitch = 0.95, stopAfter = 0.08 } },
		run({ { 0, 0, 0.18 }, { -5, 0.035, 0.17 } }, 0.08)
	),
	-- a sheet rising into view: a little pop and a three-step climb, in time with the slide-up
	UIOpen = with(
		{ { id = S .. "snap.wav", volume = 0.2, pitch = 1.7, stopAfter = 0.08 } },
		run({ { 0, 0, 0.12 }, { 4, 0.03, 0.12 }, { 7, 0.06, 0.13 } }, 0.07)
	),
	-- the end of a list / grid: a dull bump instead of the tick (you hit a wall)
	UIEdge = { { id = S .. "button.wav", volume = 0.3, pitch = 0.55, eq = DULL, stopAfter = 0.08 } },
	-- refused: a disabled button, too few coins, no spins left. Two dull bumps, stepping down
	UIError = {
		{ id = S .. "button.wav", volume = 0.32, pitch = 0.5, eq = DULL, stopAfter = 0.07 },
		{ id = S .. "button.wav", volume = 0.3, pitch = 0.42, delay = 0.085, eq = DULL, stopAfter = 0.08 },
	},
	-- settings switches: on climbs, off drops, so the new state is heard
	UIToggleOn = with(
		{ { id = S .. "switch.wav", volume = 0.28, pitch = 1.25, stopAfter = 0.08 } },
		run({ { 7, 0.02, 0.14 }, { 12, 0.05, 0.14 } }, 0.06)
	),
	UIToggleOff = with(
		{ { id = S .. "switch.wav", volume = 0.26, pitch = 0.95, stopAfter = 0.08 } },
		run({ { 0, 0.02, 0.12 }, { -5, 0.05, 0.11 } }, 0.06)
	),
	-- the server confirmed an equip: a single soft rising step (the press already clicked)
	UIEquip = run({ { 4, 0, 0.16 }, { 9, 0.05, 0.16 } }, 0.09),
	-- a tutorial step done: a small two-note "got it"
	UIStep = run({ { 7, 0, 0.18 }, { 12, 0.07, 0.2 } }, 0.12),
	-- success family: rising major arpeggios that grow with the size of the moment
	UISuccess = run({ { 0, 0, 0.28 }, { 4, 0.06, 0.28 }, { 7, 0.12, 0.3 }, { 12, 0.18, 0.32 } }, 0.16),
	Purchase = with(
		{ { id = S .. "button.wav", volume = 0.35, pitch = 1.0, stopAfter = 0.1 } },
		run({ { 0, 0, 0.3 }, { 4, 0.06, 0.3 }, { 7, 0.12, 0.32 }, { 12, 0.18, 0.34 } }, 0.16)
	),
	CoinGain = with(
		{ { id = DRY_TICK, volume = 0.22, pitch = 1.6, jitter = 0.04, delay = 0.01, stopAfter = 0.06 } },
		run({ { 7, 0, 0.3 }, { 12, 0.06, 0.28 } }, 0.12)
	),
	DailyClaim = with(
		{ { id = S .. "victory.wav", volume = 0.35, pitch = 1.25, delay = 0.22, stopAfter = 1.1 } },
		run({ { 0, 0, 0.32 }, { 4, 0.06, 0.32 }, { 7, 0.12, 0.34 }, { 12, 0.18, 0.36 }, { 16, 0.24, 0.3 } }, 0.18)
	),
	-- daily spin: the start is a select, the wheel a mechanical tick, the reveal a success
	SpinStart = with(
		{ { id = S .. "switch.wav", volume = 0.4, pitch = 0.85, stopAfter = 0.1 } },
		run({ { 0, 0.02, 0.18 }, { 7, 0.06, 0.2 } }, 0.08)
	),
	WheelTick = { { id = DRY_TICK, volume = 0.3, pitch = 1.5, jitter = 0.08, stopAfter = 0.05 } },
	SpinReveal = with(
		{ { id = S .. "victory.wav", volume = 0.4, pitch = 1.1, delay = 0.2, stopAfter = 1.2 } },
		run({ { 0, 0, 0.32 }, { 4, 0.06, 0.32 }, { 7, 0.12, 0.34 }, { 12, 0.18, 0.36 } }, 0.18)
	),
	SpinLegendary = with(
		{ { id = S .. "victory.wav", volume = 0.55, pitch = 0.95, delay = 0.3, stopAfter = 1.8 } },
		run({
			{ 0, 0, 0.32 },
			{ 4, 0.06, 0.32 },
			{ 7, 0.12, 0.34 },
			{ 12, 0.18, 0.36 },
			{ 16, 0.24, 0.36 },
			{ 19, 0.3, 0.36 },
			{ 24, 0.36, 0.34 },
		}, 0.2)
	),
	-- the signature: a toy "pop-ding" (snap + an octave ping). Heard when the game is ready to play
	-- (boot), and the one to reuse in trailers and anything that means "Ragdoll Dodgeball".
	Signature = with(
		{ { id = S .. "snap.wav", volume = 0.45, pitch = 1.5, stopAfter = 0.25 } },
		run({ { 0, 0.01, 0.34 }, { 12, 0.07, 0.32 }, { 19, 0.13, 0.22 } }, 0.35)
	),
}

local Cues: { [string]: { Layer } } = {
	-- Combat
	Throw = {
		{
			id = S .. "swordlunge.wav",
			volume = 0.45,
			pitch = 1.25,
			jitter = 0.08,
			eq = { low = -6, mid = 0, high = 3 },
		},
	},
	Hit = {
		-- a real rubber dodgeball smack
		{ id = "rbxassetid://8254245367", volume = 1.0, pitch = 1, jitter = 0.06, stopAfter = 1.2 },
		-- body: a soft low thump under it
		{
			id = S .. "bass.wav",
			volume = 0.45,
			pitch = 1.9,
			jitter = 0.05,
			eq = { low = 6, mid = 0, high = -8 },
			stopAfter = 0.3,
		},
	},
	HitHeavy = {
		{ id = "rbxassetid://8254247881", volume = 1.0, pitch = 0.95, jitter = 0.05, stopAfter = 1.2 },
		{ id = "rbxassetid://8254245367", volume = 0.5, pitch = 0.8, jitter = 0.05, stopAfter = 1.2 },
		{
			id = S .. "bass.wav",
			volume = 0.7,
			pitch = 1.4,
			jitter = 0.04,
			eq = { low = 10, mid = 0, high = -6 },
			distortion = 0.2,
			stopAfter = 0.45,
		},
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
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.9,
			eq = { low = 10, mid = 0, high = -3 },
			distortion = 0.4,
			stopAfter = 0.8,
		},
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
	-- Match flow. 3-2-1 is a scoreboard buzzer, GO is the referee's whistle (Pro Sound Effects audio
	-- from the Creator Store, free to use: Stadium Buzzer 2 and Referee Whistle 2).
	CountdownTick = {
		{ id = "rbxassetid://9119561249", volume = 0.7, pitch = 1, stopAfter = 0.5 },
		{ id = S .. "electronicpingshort.wav", volume = 0.25, pitch = 1.0 },
	},
	Go = {
		{ id = "rbxassetid://9118113825", volume = 0.9, pitch = 1, stopAfter = 2 },
		{ id = S .. "bass.wav", volume = 0.5, pitch = 1.6, stopAfter = 0.3, distortion = 0.2 },
	},
	LastPlayer = {
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.75 },
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.75, delay = 0.18 },
	},
	SuddenDeath = {
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.45,
			eq = { low = 10, mid = 0, high = -10 },
			distortion = 0.6,
			reverb = true,
		},
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
	-- Meteor Strike finisher
	MeteorCharge = {
		{
			id = S .. "bass.wav",
			volume = 0.9,
			pitch = 0.35,
			eq = { low = 10, mid = 0, high = -10 },
			distortion = 0.4,
			reverb = true,
			stopAfter = 1.4,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 0.45, delay = 0.25, reverb = true },
	},
	MeteorFall = {
		{ id = S .. "swordlunge.wav", volume = 0.7, pitch = 0.35, eq = { low = 6, mid = 0, high = -4 }, reverb = true },
		{ id = S .. "swordlunge.wav", volume = 0.5, pitch = 0.5, delay = 0.45, reverb = true },
		{ id = S .. "bass.wav", volume = 0.6, pitch = 0.5, delay = 0.6, distortion = 0.5, stopAfter = 0.9 },
	},
	MeteorImpact = {
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.55,
			eq = { low = 12, mid = 2, high = -6 },
			distortion = 0.7,
			reverb = true,
		},
		{ id = S .. "collide.wav", volume = 0.8, pitch = 0.6, distortion = 0.3 },
		{ id = S .. "glassbreak.wav", volume = 0.45, pitch = 0.7, delay = 0.03 },
		{ id = S .. "impact_water.mp3", volume = 0.4, pitch = 0.6, delay = 0.05, stopAfter = 1.2 },
	},
	-- Pumpkin Reaper finisher (horror cues from APM's "Horror Tools" and Pro Sound Effects, both
	-- free in the Creator Store)
	-- crowning: a creepy string build while the pumpkin goes on (0.55 s), ending on the reveal (1.9 s).
	-- To audition alternatives, open https://create.roblox.com/store/asset/<id> and swap the id:
	--   1846042216 String Effects 7 (APM)  [current]
	--   1846042187 String Effects 3 (APM)
	--   1840490160 Terror Sequence (Y) (APM)
	PumpkinDread = {
		{
			id = "rbxassetid://1846042216",
			volume = 0.9,
			pitch = 1,
			stopAfter = 1.45,
			gamma = { shape = 3, scale = 0.65, tail = 0.15 }, -- swells to its peak (1.3 s in) right on the reveal
		},
	},
	-- the zoom into the face: a screeching string stab that swells, peaks, then dies away into the cut
	PumpkinScream = {
		{
			id = "rbxassetid://9043353994", -- ONE SHOT-SCREAMER 04
			volume = 1.0,
			pitch = 1,
			startAt = 1.2,
			stopAfter = 1.7,
			gamma = { shape = 2, scale = 0.6, tail = 0.35 },
		},
		{ id = "rbxassetid://9120432706", volume = 0.6, pitch = 1, startAt = 1.3, stopAfter = 1.0 }, -- violin scrape
	},
	-- the drag: bats squeaking and flapping past (it used to be an explosion)
	-- the cut to the victim: the ghost moan right away, then bats flapping and swooping past. The
	-- wing-flap recording is about 5x quieter than the squeaks, hence its high volume.
	BatsFlyBy = {
		{ id = S .. "HalloweenGhost.wav", volume = 0.6, pitch = 1, reverb = true, stopAfter = 1.8 },
		{ id = "rbxassetid://9113443901", volume = 3.0, pitch = 1.4, startAt = 0.4, stopAfter = 2.3 }, -- wing flaps
		{ id = S .. "swordlunge.wav", volume = 1.0, pitch = 1.5, delay = 0.2 }, -- one swooping past
		{ id = S .. "swordlunge.wav", volume = 0.9, pitch = 1.9, delay = 0.95 }, -- and another
		{ id = "rbxassetid://9117003596", volume = 0.4, pitch = 1.7, delay = 0.1, stopAfter = 1.7 }, -- squeaks
		{ id = "rbxassetid://9117003596", volume = 0.28, pitch = 2.15, delay = 0.6, stopAfter = 1.4 },
	},
	-- the drag itself: a low pull
	Drag = {
		{ id = S .. "swordlunge.wav", volume = 0.6, pitch = 0.3, reverb = true },
	},
	-- Destiny Arrives finisher (free Pro Sound Effects assets from the Creator Store, plus built-ins)
	DestinyPortal = {
		{ id = "rbxassetid://9120726501", volume = 1.0, pitch = 0.8, stopAfter = 2.2, reverb = true }, -- giant airy whomp
		{
			id = S .. "bass.wav",
			volume = 0.8,
			pitch = 0.32,
			eq = { low = 10, mid = -4, high = -10 },
			reverb = true,
			stopAfter = 1.6,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 0.55, delay = 0.15, reverb = true },
	},
	DestinyStep = {
		{
			id = S .. "bass.wav",
			volume = 0.8,
			pitch = 0.75,
			eq = { low = 8, mid = 0, high = -8 },
			distortion = 0.2,
			stopAfter = 0.35,
		},
		{ id = S .. "collide.wav", volume = 0.35, pitch = 0.5, jitter = 0.05 },
	},
	DestinySnap = {
		{ id = "rbxassetid://9114428331", volume = 1.6, pitch = 1, stopAfter = 0.4 }, -- a clean finger snap
		{
			id = S .. "bass.wav",
			volume = 0.9,
			pitch = 0.45,
			delay = 0.04,
			eq = { low = 10, mid = -2, high = -8 },
			reverb = true,
			stopAfter = 1.2,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 2.5, delay = 0.05, reverb = true },
	},
	-- the victim blowing away: an eerie breathy wind and a fine hiss of dust
	DestinyDust = {
		{
			id = "rbxassetid://9113587573",
			volume = 1.0,
			pitch = 1,
			stopAfter = 2.2,
			gamma = { shape = 2, scale = 0.6, tail = 0.4 },
		},
		{
			id = S .. "impact_water.mp3",
			volume = 0.35,
			pitch = 2.4,
			eq = { low = -10, mid = 0, high = 6 },
			delay = 0.2,
			stopAfter = 1.6,
		},
	},
	-- Purple Flash finisher
	PurpleOrbs = {
		-- blue: a sucking sub swell with a glassy whine; red: dry rhythmic cracks and thuds
		{
			id = S .. "bass.wav",
			volume = 0.9,
			pitch = 0.3,
			eq = { low = 10, mid = -6, high = -10 },
			reverb = true,
			stopAfter = 1.3,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 2.8, reverb = true },
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 3.2, delay = 0.35, reverb = true },
		{ id = S .. "snap.wav", volume = 0.5, pitch = 0.9, delay = 0.15, jitter = 0.08 },
		{ id = S .. "bass.wav", volume = 0.55, pitch = 1.6, delay = 0.3, distortion = 0.4, stopAfter = 0.2 },
		{ id = S .. "snap.wav", volume = 0.5, pitch = 1.05, delay = 0.5, jitter = 0.08 },
		{ id = S .. "bass.wav", volume = 0.55, pitch = 1.6, delay = 0.7, distortion = 0.4, stopAfter = 0.2 },
		{ id = S .. "snap.wav", volume = 0.5, pitch = 0.95, delay = 0.9, jitter = 0.08 },
		{ id = S .. "bass.wav", volume = 0.55, pitch = 1.6, delay = 1.1, distortion = 0.4, stopAfter = 0.2 },
	},
	PurpleSqueeze = {
		-- sheared steel under compression
		{ id = S .. "metal.ogg", volume = 0.6, pitch = 0.45, distortion = 0.6, eq = { low = -4, mid = 4, high = 2 } },
		{ id = S .. "swordslash.wav", volume = 0.4, pitch = 0.35, delay = 0.2, reverb = true },
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 0.6, delay = 0.1 },
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 0.63, delay = 0.1 },
	},
	PurpleFuse = {
		-- lightning striking glass, then the sub-drop as the core stabilises
		{ id = S .. "snap.wav", volume = 1.0, pitch = 0.55 },
		{ id = S .. "glassbreak.wav", volume = 0.7, pitch = 0.75 },
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.35,
			delay = 0.04,
			eq = { low = 12, mid = -4, high = -10 },
			distortion = 0.5,
			reverb = true,
			stopAfter = 1.0,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 0.45, delay = 0.08, reverb = true },
	},
	PurpleSnap = {
		-- dry finger click, then the shock blast and a tear-away whoosh
		{ id = S .. "snap.wav", volume = 1.0, pitch = 1.25 },
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.6,
			delay = 0.04,
			eq = { low = 12, mid = 0, high = -4 },
			distortion = 0.7,
			stopAfter = 0.7,
		},
		{ id = S .. "swordlunge.wav", volume = 0.9, pitch = 0.45, delay = 0.05, distortion = 0.3 },
		{ id = S .. "collide.wav", volume = 0.6, pitch = 0.5, delay = 0.05 },
	},
	PurpleRoar = {
		-- the projectile tearing through atmosphere, with a fizzing disintegration hiss
		{ id = S .. "swordlunge.wav", volume = 0.9, pitch = 0.22, reverb = true, distortion = 0.4 },
		{
			id = S .. "bass.wav",
			volume = 0.9,
			pitch = 0.32,
			eq = { low = 10, mid = 0, high = -8 },
			distortion = 0.6,
			stopAfter = 1.6,
		},
		{
			id = S .. "impact_water.mp3",
			volume = 0.45,
			pitch = 1.9,
			eq = { low = -10, mid = 0, high = 6 },
			delay = 0.05,
			stopAfter = 1.4,
		},
	},
	PurpleErase = {
		{ id = S .. "glassbreak.wav", volume = 0.6, pitch = 0.5, reverb = true },
		{
			id = S .. "impact_water.mp3",
			volume = 0.5,
			pitch = 2.2,
			eq = { low = -10, mid = 0, high = 6 },
			stopAfter = 0.9,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.4, pitch = 0.35, delay = 0.05, reverb = true },
	},
	PurpleInrush = {
		-- distant thunder roll, then the air whipping back into the trench
		{
			id = S .. "bass.wav",
			volume = 0.8,
			pitch = 0.25,
			eq = { low = 10, mid = -4, high = -10 },
			reverb = true,
			stopAfter = 1.4,
		},
		{ id = S .. "swordlunge.wav", volume = 0.6, pitch = 0.4, delay = 0.45, reverb = true },
	},
	-- Black Hole finisher
	BallWhoosh = {
		{ id = S .. "swordlunge.wav", volume = 0.6, pitch = 0.9 },
		{ id = S .. "swordlunge.wav", volume = 0.35, pitch = 0.6, delay = 0.15 },
	},
	BlackHoleForm = {
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.3,
			eq = { low = 12, mid = 0, high = -10 },
			distortion = 0.7,
			reverb = true,
			stopAfter = 1.2,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.5, pitch = 0.3, reverb = true },
		{ id = S .. "glassbreak.wav", volume = 0.3, pitch = 0.5, delay = 0.03 },
	},
	BlackHoleThrow = {
		{ id = S .. "swordlunge.wav", volume = 0.8, pitch = 0.55 },
		{ id = S .. "bass.wav", volume = 0.6, pitch = 0.8, stopAfter = 0.4, distortion = 0.3 },
	},
	BlackHoleSuck = {
		{
			id = S .. "bass.wav",
			volume = 0.9,
			pitch = 0.25,
			eq = { low = 12, mid = -2, high = -12 },
			reverb = true,
			stopAfter = 2.4,
		},
		{ id = S .. "swordlunge.wav", volume = 0.5, pitch = 0.3, delay = 0.4, reverb = true },
		{ id = S .. "HalloweenGhost.wav", volume = 0.3, pitch = 0.5, delay = 0.6, stopAfter = 1.8 },
	},
	-- Dodgeball Rush finisher
	StandSummon = {
		-- the world drops out, then a crystalline hum swells as the spirit appears
		{
			id = S .. "bass.wav",
			volume = 0.8,
			pitch = 0.3,
			eq = { low = 10, mid = -4, high = -10 },
			reverb = true,
			stopAfter = 0.9,
		},
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 1.6, delay = 0.22, reverb = true },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 2.2, delay = 0.3, reverb = true },
	},
	BarrageHit = {
		{ id = S .. "bass.wav", volume = 0.7, pitch = 2.2, jitter = 0.12, distortion = 0.3, stopAfter = 0.12 },
		{ id = S .. "hit.wav", volume = 0.45, pitch = 1.1, jitter = 0.15 },
	},
	BarrageWhoosh = {
		{ id = S .. "swordlunge.wav", volume = 0.6, pitch = 1.1, jitter = 0.1 },
	},
	BarrageFinal = {
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 0.6,
			eq = { low = 12, mid = 2, high = -6 },
			distortion = 0.7,
			reverb = true,
		},
		{ id = S .. "snap.wav", volume = 0.9, pitch = 0.5 },
		{ id = S .. "glassbreak.wav", volume = 0.4, pitch = 0.8, delay = 0.02 },
		{ id = S .. "swordlunge.wav", volume = 0.6, pitch = 0.6, delay = 0.1, reverb = true },
	},
	CartCrash = {
		{ id = S .. "metal.ogg", volume = 0.8, pitch = 0.5 },
		{ id = S .. "collide.wav", volume = 0.7, pitch = 0.7 },
	},
	CartSlam = {
		{ id = S .. "metal.ogg", volume = 1.0, pitch = 0.35, distortion = 0.3, reverb = true },
		{ id = S .. "bass.wav", volume = 0.7, pitch = 0.7, stopAfter = 0.4, distortion = 0.4 },
	},
	-- Out of the Park finisher
	ParkToss = {
		{ id = S .. "swordlunge.wav", volume = 0.3, pitch = 1.9, eq = { low = -10, mid = 0, high = 2 } },
	},
	ParkCharge = charge(),
	ParkMorph = {
		-- a rubbery pop-squeeze, then a magic shimmer
		{ id = S .. "button.wav", volume = 0.6, pitch = 0.6 },
		{ id = S .. "snap.wav", volume = 0.6, pitch = 1.6, delay = 0.02 },
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 2.6, delay = 0.05, reverb = true },
		{ id = S .. "electronicpingshort.wav", volume = 0.25, pitch = 3.2, delay = 0.11, reverb = true },
		{ id = S .. "glassbreak.wav", volume = 0.12, pitch = 2.2, delay = 0.04 },
	},
	ParkBatLoad = {
		{ id = S .. "swordlunge.wav", volume = 0.4, pitch = 0.5, eq = { low = 0, mid = 0, high = -4 } },
	},
	ParkSwing = {
		{ id = S .. "swordlunge.wav", volume = 0.9, pitch = 0.8 },
		{ id = S .. "swordslash.wav", volume = 0.4, pitch = 0.9, delay = 0.05 },
	},
	ParkCrack = {
		-- wood on leather, with a ringing tail
		{ id = S .. "snap.wav", volume = 1.0, pitch = 0.7 },
		{ id = S .. "hit.wav", volume = 0.7, pitch = 0.6 },
		{ id = S .. "metal.ogg", volume = 0.3, pitch = 1.6, delay = 0.01, reverb = true },
		{ id = S .. "bass.wav", volume = 0.7, pitch = 1.6, distortion = 0.3, stopAfter = 0.25 },
	},
	ParkSmack = {
		-- a wet, bone-jarring thwack and a metallic sting
		{
			id = S .. "bass.wav",
			volume = 1.0,
			pitch = 1.2,
			eq = { low = 12, mid = 2, high = -4 },
			distortion = 0.6,
			stopAfter = 0.5,
		},
		{ id = S .. "snap.wav", volume = 1.0, pitch = 0.5 },
		{ id = S .. "hit.wav", volume = 0.8, pitch = 0.8 },
		{ id = S .. "impact_water.mp3", volume = 0.5, pitch = 0.8, stopAfter = 0.3 },
		{ id = S .. "metal.ogg", volume = 0.45, pitch = 2.2, delay = 0.03, reverb = true },
	},
	ParkLaunch = {
		-- shhhhh-FWOOM
		{ id = S .. "swordlunge.wav", volume = 1.0, pitch = 0.3, distortion = 0.3 },
		{
			id = S .. "bass.wav",
			volume = 0.8,
			pitch = 0.45,
			eq = { low = 10, mid = 0, high = -8 },
			distortion = 0.4,
			stopAfter = 1.0,
		},
	},
	ParkCheer = {
		-- the crowd erupting: a fanfare over layered hiss standing in for applause
		{ id = S .. "victory.wav", volume = 0.5, pitch = 1.0 },
		{
			id = S .. "impact_water.mp3",
			volume = 0.35,
			pitch = 2.6,
			eq = { low = -10, mid = 2, high = 4 },
			reverb = true,
			stopAfter = 2.4,
		},
		{
			id = S .. "impact_water.mp3",
			volume = 0.3,
			pitch = 3.1,
			delay = 0.15,
			eq = { low = -10, mid = 2, high = 4 },
			reverb = true,
			stopAfter = 2.4,
		},
		{
			id = S .. "impact_water.mp3",
			volume = 0.25,
			pitch = 2.2,
			delay = 0.3,
			eq = { low = -10, mid = 2, high = 4 },
			reverb = true,
			stopAfter = 2.4,
		},
	},
	ParkTwinkle = {
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 3.0, reverb = true },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 4.0, delay = 0.07, reverb = true },
	},
	PowerUp = {
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 1.8 },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 2.4, delay = 0.08 },
	},
	-- UI and menu sounds live in uiCues above; Banner is the in-match callout whoosh
	Banner = {
		{ id = S .. "swordslash.wav", volume = 0.25, pitch = 1.4, jitter = 0.05 },
	},
	-- Quest chests: rattling while the server rolls the prize, then bursting open
	ChestRattle = {
		{ id = S .. "clickfast.wav", volume = 0.35, pitch = 0.6, jitter = 0.1 },
		{ id = S .. "collide.wav", volume = 0.2, pitch = 1.4, delay = 0.04, jitter = 0.1 },
	},
	ChestBurst = {
		{ id = S .. "switch.wav", volume = 0.5, pitch = 0.6 },
		{ id = S .. "glassbreak.wav", volume = 0.25, pitch = 1.6, delay = 0.03 },
		{ id = S .. "electronicpingshort.wav", volume = 0.45, pitch = 1.2, delay = 0.08 },
		{ id = S .. "electronicpingshort.wav", volume = 0.4, pitch = 1.8, delay = 0.18 },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 2.4, delay = 0.3 },
	},
	-- Common / Rare finishers (Finishers/ConfettiPop, AirHorn, SadTrombone, Bonk, Paparazzi)
	ConfettiPop = {
		{ id = S .. "snap.wav", volume = 0.8, pitch = 0.8 },
		{ id = S .. "glassbreak.wav", volume = 0.25, pitch = 2.2, delay = 0.02 },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 2.0, delay = 0.06 },
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 2.67, delay = 0.12 },
		{ id = S .. "electronicpingshort.wav", volume = 0.3, pitch = 3.0, delay = 0.18 },
	},
	-- three blasts, short short long
	AirHorn = concat(brass(7, 0, 0.22), brass(7, 0.3, 0.22), brass(7, 0.6, 0.9), brass(12, 0.6, 0.9)),
	-- wah, wah, wah, waaah (each a semitone lower, the last one wobbling)
	SadTrombone = concat(brass(0, 0, 0.42), brass(-1, 0.5, 0.42), brass(-2, 1.0, 0.42), brass(-3, 1.5, 1.2, true)),
	Bonk = {
		{ id = S .. "metal.ogg", volume = 0.9, pitch = 1.6, stopAfter = 0.6 },
		{ id = S .. "hit.wav", volume = 0.6, pitch = 0.7 },
		{ id = S .. "bass.wav", volume = 0.6, pitch = 1.3, eq = { low = 8, mid = 0, high = -6 }, stopAfter = 0.35 },
		{ id = S .. "electronicpingshort.wav", volume = 0.25, pitch = 3.2, delay = 0.08 },
	},
	ShutterClick = {
		{ id = S .. "clickfast.wav", volume = 0.5, pitch = 1.5, jitter = 0.08 },
		{ id = S .. "switch.wav", volume = 0.3, pitch = 1.8, delay = 0.04, jitter = 0.08 },
	},
	-- Match intro (each team's shot)
	IntroStinger = {
		{ id = S .. "swordslash.wav", volume = 0.35, pitch = 0.9 },
		{ id = S .. "electronicpingshort.wav", volume = 0.35, pitch = 1.5, delay = 0.05 },
	},
}

for name, layers in uiCues do
	Cues[name] = layers
end

local Sounds = {}

-- Crowd cheers for an enemy going out: 5 s cut from each track's loudest moment (startAt), with
-- a gamma-shaped volume curve that peaks 0.3 s in and fades to silence.
local CHEER_CURVE = { shape = 1.3, scale = 1.0, tail = 0.35 }
Cues.CrowdCheer1 = {
	{ id = "rbxassetid://7174628595", volume = 0.8, pitch = 1, startAt = 2.15, stopAfter = 5, gamma = CHEER_CURVE },
}
Cues.CrowdCheer2 = {
	{ id = "rbxassetid://7755719721", volume = 0.8, pitch = 1, startAt = 0.35, stopAfter = 5, gamma = CHEER_CURVE },
}
Sounds.Cheers = { "CrowdCheer1", "CrowdCheer2" }

Sounds.Cues = Cues

return Sounds
