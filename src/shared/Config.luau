--!strict
-- Central gameplay configuration. Every balance value lives here (spec v0.1 §7, Amendment A).
-- All numbers are starting values to tune from playtest data.

local Config = {}

Config.Debug = {
	-- Dev keys (F6 reset round, F7 add bot, F8 toggle event) are only honoured in Studio.
	DevKeysInStudioOnly = true,
	LogSuspiciousRemotes = true,
}

Config.Match = {
	MinPlayers = 1, -- Amendment A2: a solo player gets a bot-filled 3v3
	MaxPlayers = 12,
	Intermission = 7, -- hub time between matches: talk, practice, shop, change cosmetics
	IntermissionSkipWhenFull = true,
	RoundCountdown = 3,
	RoundTime = 75,
	-- When the timer runs out: SUDDEN DEATH. Jail closes (no more returns) and the court keeps
	-- shrinking until a team is out. If the court is fully shrunk and it still hasn't ended after
	-- SuddenDeathFallback seconds, more players on court wins, then more hits, then a draw.
	SuddenDeathFallback = 15,
	RoundResolution = 3,
	ResultsOverlay = 4, -- shown over the live lobby while the next intermission runs
	RoundsToWin = 2, -- best of three
	MaxDrawReplays = 2,
	FirstMatchMaxWait = 15, -- a solo joiner must be in a match within this many seconds
}

-- Real players on server -> team size. Bots fill the rest (Amendment A2).
Config.MatchSizing = {
	{ MaxReal = 5, TeamSize = 3 },
	{ MaxReal = 9, TeamSize = 5 },
	{ MaxReal = 12, TeamSize = 6 },
}

Config.Arena = {
	Origin = Vector3.new(0, 200, 0), -- top surface of the court is at Origin.Y
	CourtLength = 96, -- along Z
	CourtWidth = 64, -- along X
	FloorThickness = 2,
	VoidDepth = 25, -- elimination plane below the court surface
	SpawnSetback = 24, -- spawn distance from the center line (24 from the back edge too)
	SpawnEdgeMargin = 14,
	OpeningBallSpots = 6,
	OpeningBallOffset = 6, -- studs from the center line
	BarrierHeight = 40,
	-- Overtime: outer strips retract symmetrically.
	OvertimeStripWidth = 6,
	OvertimeStrips = 4, -- per side
	OvertimeStepInterval = 5,
	OvertimeWarning = 1,
	EdgeWallOffset = 2.5, -- one-way wall distance outside the court edge
	EjectDistance = 5, -- a flung body this far past the edge has cleared the wall and can't return
	StuckOffCourtTime = 3, -- a body hanging past the edge this long without falling is out
	-- Hub deck: top surface at LobbyOrigin.Y. Size is in the deck's own frame, which always faces
	-- the court: X = width (left/right as you look at the court), Z = depth (toward the court).
	-- The hub sits level with the court, off its left side (-X), so hub players can watch the match
	-- across a void gap wider than any knockback can carry a body (LobbyGap). Players on the court
	-- don't see the hub at all (HubController hides it for them).
	LobbyGap = 36,
	LobbyOrigin = Vector3.new(-(64 / 2 + 36 + 84 / 2), 200, 0), -- -(CourtWidth/2 + LobbyGap + depth/2)
	LobbySize = Vector3.new(110, 2, 84),
}

-- Hub look: a neon rooftop at night (the top of a skyscraper floating in the purple void).
-- Positions below are in the deck frame: X = right, F = forward toward the court (+F = court side).
Config.Lobby = {
	Seed = 7, -- decor scatter (lit windows, props) is deterministic so every server looks the same
	BuildingDepth = 150, -- how far the tower below the deck reaches down into the void
	FloorHeight = 9, -- studs per storey of lit windows on the tower
	LitWindowChance = 0.22,
	ParapetHeight = 1.4,
	RailHeight = 3.4,
	BeaconBlink = 1.2, -- antenna beacon period (client-side)
	Spawn = { X = 0, F = 4, Spread = 7 }, -- the helipad in the middle of the deck
	-- practice zone at the deck's left end: open drop past the dummy, a walker-only wall before it
	Practice = { F = 0, DummyX = -49, BallX = -30, WallX = -43 },
	-- kiosk stations along the back of the deck, facing the court
	Stations = {
		{ Id = "Shop", Title = "SHOP & LOCKER", Icon = "🛒", X = -17, F = -33, Color = Color3.fromRGB(255, 140, 40) },
		{ Id = "Spin", Title = "DAILY SPIN", Icon = "🎡", X = 0, F = -33, Color = Color3.fromRGB(255, 80, 190) },
		{ Id = "Daily", Title = "DAILY REWARD", Icon = "🎁", X = 17, F = -33, Color = Color3.fromRGB(70, 150, 255) },
	},
	StationPromptDistance = 12,
	Leaderboard = { X = 52, F = -12, Rows = 8, Refresh = 5 }, -- on the right end, facing the deck
	WatchZone = { F = 33, Width = 50, Rows = 3 }, -- low bleachers at the court-side railing
	Palette = {
		Deck = Color3.fromRGB(58, 56, 74),
		DeckAlt = Color3.fromRGB(70, 68, 90),
		Wall = Color3.fromRGB(34, 30, 48),
		Metal = Color3.fromRGB(120, 120, 140),
		Trim = Color3.fromRGB(170, 110, 255), -- hub purple (matches the arena's hub trim)
		Cyan = Color3.fromRGB(70, 230, 255),
		Pink = Color3.fromRGB(255, 80, 190),
		Warm = Color3.fromRGB(255, 196, 120),
		Window = Color3.fromRGB(255, 214, 140),
		Wood = Color3.fromRGB(150, 96, 62),
		Plant = Color3.fromRGB(70, 170, 95),
	},
}

Config.Jail = {
	Enabled = true,
	StripDepth = 8,
	Gap = 8, -- void gap between a team's back line and the jail: wider than a lying body (~5.5)
	RespawnDelay = 1.5,
	ReturnDelay = 1.0,
	ReturnImmunity = 1.5,
	MaxReturnsPerRound = 2,
}

Config.Player = {
	WalkSpeed = 18,
	JumpPower = 42,
	PickupRadius = 6, -- horizontal distance from the player to the ball
	MaxHeldBalls = 1,
	FullChargeTime = 0.65,
	MinThrowSpeed = 85,
	MaxThrowSpeed = 120,
	ThrowRecovery = 0.4,
	RagdollDuration = 1.1,
	PostHitImmunity = 0.75,
	DodgeDuration = 0.28,
	DodgeSpeed = 42,
	DodgeCooldown = 2.5,
	CatchWindow = 0.22,
	CatchCooldown = 1.25,
	CatchConeDeg = 70, -- half-angle in front of the catcher
	CatchRadius = 6, -- a ball passing within this distance of a catching player can be caught
	PossessionWarn = 8,
	PossessionForceDrop = 12,
	ForceDropPickupBlock = 2, -- after a forced drop, no pickups for this long (no instant re-grab)
	KnockoutCreditWindow = 4,
	MaxPitchUpDeg = 50,
	MaxPitchDownDeg = 35,
	HitProxySize = Vector3.new(3.2, 5.4, 2.4),
}

Config.Knockback = {
	HorizontalMin = 28, -- quick throws: v0.1 strength
	HorizontalMax = 44, -- full charge: +10% over v0.1 (40) for a harder fling
	Upward = 26, -- more hang time = bigger-looking launch without much extra distance
	MaxSpeed = 80, -- clamp on resulting limb velocity
	-- Exaggeration: the whole body tumbles about a random axis while each limb windmills on its
	-- floppy joint. Bodies keep their natural slide on landing (no extra friction).
	TumbleSpin = 7, -- rad/s whole-body flip
	LimbSpin = 9, -- rad/s random per-limb spin
	LimbFlail = 10, -- studs/s random per-limb velocity (averages out across the body)
}

Config.Ball = {
	Radius = 1.1,
	Gravity = 70, -- studs/s^2 applied to in-flight balls (Workspace gravity is 196.2)
	SimStep = 1 / 60,
	MaxCatchUpSteps = 4,
	MaxFlightTime = 3,
	PickupLockout = 0.5, -- after a throw or drop
	ThrowerLockout = 1.0, -- the thrower specifically
	SettleSpeed = 3,
	SettleTimeout = 2.5,
	OutOfBoundsReturnDelay = 2,
	ConservationInterval = 3,
	BallsPerCourt = 6,
	SpawnForward = 2.5,
	SpawnUp = 1.5,
}

-- Client aim assist: pulls the throw onto an enemy near the aim, only with line of sight.
Config.AimAssist = {
	ConeDeg = { Mouse = 6, Gamepad = 10, Touch = 14 }, -- how far off the aim an enemy can be picked
	KeepFactor = 1.5, -- a picked enemy stays locked for the charge while inside cone × this
	Range = 160, -- studs
}

-- Hub practice (client-side): each player has their own dummy and practice balls.
Config.Practice = {
	TemplateName = "PracticeDummyTemplate", -- the dummy rig the server parks in ReplicatedStorage
	Balls = 2,
	BallSpread = 4, -- studs between practice balls along the lane
	DummyRespawn = 2, -- seconds after the dummy falls off before a new one stands up
	BallRespawn = 1.5, -- seconds after a ball falls off before it's back at its spot
	RecoverAfter = 2.2, -- a launched dummy still on the deck stands back up after this long
	ThrowerLockout = 0.6, -- can't re-grab your own throw for this long
}

Config.PowerUps = {
	Enabled = true,
	DispenserInterval = 12,
	MaxPowerBallsPerSide = 1,
	Weights = { Heavy = 1, Rocket = 1, Pop = 1 },
}

Config.Bots = {
	Enabled = true,
	MaxPerServer = 5,
	TickInterval = 0.15,
	-- Each bot's finisher: a tier is drawn from a gamma distribution over the tier index (0 Common,
	-- 1 Rare, 2 Epic, 3 Legendary; the draw is floored and capped at Legendary), then a finisher of
	-- that tier at random. Shape 2, scale 0.6 gives roughly 50% Common, 35% Rare, 11% Epic, 4%
	-- Legendary: mostly plain, with the odd showy bot.
	FinisherGamma = { Shape = 2, Scale = 0.6 },
	-- Difficulty profiles. Every bot gets one when it spawns (see Mix). All of them miss, mistime
	-- catches and fall for good throws; Hard is sharper, never perfect.
	--   AimErrorDeg: random cone around a perfect throw · ReactionTime: seconds before reacting to
	--   an incoming ball · DodgeChance / CatchChance: what it tries once it has reacted ·
	--   CatchTimingError: std-dev (s) of when it presses catch vs. the ball's arrival (the catch
	--   window is Player.CatchWindow, so a big error fails) · AimDelay: aim time before release ·
	--   ChargeHold: how long it charges (FullChargeTime = full power) · QuickThrowChance: snap
	--   throws with no aim time · EdgeCaution: studs from the edge where it starts backing off ·
	--   TargetSmarts: chance it picks the best target (near an edge, just got up, can't catch)
	--   instead of simply the nearest · Strafe: sidestep speed factor while aiming
	Profiles = {
		Easy = {
			AimErrorDeg = 9,
			ReactionTime = { 0.34, 0.55 },
			DodgeChance = 0.25,
			CatchChance = 0.12,
			CatchTimingError = 0.16,
			AimDelay = { 0.9, 1.7 },
			ChargeHold = { 0, 0.4 },
			QuickThrowChance = 0.05,
			EdgeCaution = 11,
			TargetSmarts = 0.25,
			Strafe = 0.3,
		},
		Normal = {
			AimErrorDeg = 5,
			ReactionTime = { 0.24, 0.4 },
			DodgeChance = 0.4,
			CatchChance = 0.2,
			CatchTimingError = 0.11,
			AimDelay = { 0.6, 1.3 },
			ChargeHold = { 0.1, 0.65 },
			QuickThrowChance = 0.12,
			EdgeCaution = 13,
			TargetSmarts = 0.6,
			Strafe = 0.6,
		},
		Hard = {
			AimErrorDeg = 3,
			ReactionTime = { 0.17, 0.3 },
			DodgeChance = 0.5,
			CatchChance = 0.28,
			CatchTimingError = 0.08,
			AimDelay = { 0.45, 1.0 },
			ChargeHold = { 0.25, 0.65 },
			QuickThrowChance = 0.18,
			EdgeCaution = 15,
			TargetSmarts = 0.85,
			Strafe = 1,
		},
	},
	-- Which profiles fill a match, by the average level of its real players (first row that fits).
	Mix = {
		{ MaxLevel = 3, Weights = { Easy = 0.8, Normal = 0.2 } },
		{ MaxLevel = 10, Weights = { Easy = 0.4, Normal = 0.5, Hard = 0.1 } },
		{ MaxLevel = math.huge, Weights = { Easy = 0.15, Normal = 0.55, Hard = 0.3 } },
	},
	-- Target scoring (lower = better): studs of distance, minus bonuses.
	TargetEdgeBonus = 30, -- full bonus for an enemy right at an edge, fading out over EdgeBonusRange
	EdgeBonusRange = 14,
	TargetGotUpBonus = 14, -- just recovered from a hit (wobbly, can't dodge yet)
	TargetCatchPenalty = 10, -- empty-handed and facing us: could catch the throw
	StallThrow = 4, -- holding a ball this long with no clear shot: throw at the nearest enemy anyway
	SuddenDeathHaste = 0.4, -- aim times shrink by this fraction in sudden death (rounds must end)
	ReactRange = 34,
	EdgeAvoid = 10, -- minimum distance from the edge when picking a wander target
	VoidAvoid = 6,
	WanderInterval = { 1.5, 3.5 },
	ClaimRadius = 10, -- two bots don't chase the same ball unless the other is this much farther
	RewardMultiplier = 0.5,
	-- bots wear these Roblox users' avatars and display names (in rotation); Names is the fallback
	-- when a profile can't be fetched
	Avatars = { 3568710137, 87247403, 1081151462, 765160767, 749465889, 171080174 },
	Names = { "Bot Bounce", "Bot Bonk", "Bot Zoom", "Bot Wobble", "Bot Pop", "Bot Flop" },
}

-- Coins: the one in-game currency. Earned from match wins (highest tier only), a small
-- participation payout for the losing team, eliminations, and daily login rewards.
Config.Coins = {
	Elimination = 25, -- paid instantly to whoever is credited with knocking someone off
	Win = 200, -- your team won the match
	WinAlive = 300, -- ...and you were on the court (not jailed/spectating) when it was won
	WinFlawless = 500, -- ...and you were never eliminated during the whole match
	WinLastElimination = 600, -- ...you scored the match-ending knockout
	LossParticipation = 50, -- finished a match you actually played in, on the losing team
	MinParticipationActions = 1, -- throws/catches/dodges needed for ANY coins payout (anti-AFK)
}

-- 7-day login ladder; day 8 starts the ladder again. A missed day resets to day 1.
Config.DailyRewards = {
	Ladder = { 100, 150, 200, 250, 300, 400, 750 },
}

-- Daily cosmetic spin (separate from the coin ladder above). One free spin per UTC day; extra spins
-- can be bought with coins. Every wheel has Slots prizes drawn by rarity weight from the catalog,
-- and the server picks one slot uniformly, so each spin's real odds are exactly what the wheel shows.
Config.Spin = {
	Slots = 12,
	RarityWeights = { Common = 60, Rare = 28, Epic = 10, Legendary = 2 },
	-- rarity of a catalog item by coin price (at least this much); free defaults are never prizes
	RarityByPrice = {
		{ Rarity = "Legendary", Min = 4000 },
		{ Rarity = "Epic", Min = 2500 },
		{ Rarity = "Rare", Min = 1000 },
	},
	DuplicateCoins = { Common = 100, Rare = 250, Epic = 500, Legendary = 1000 }, -- already owned
	ExtraSpinCost = 750, -- coins
	MaxPaidPerDay = 5,
	RobuxProductId = 0, -- placeholder developer product for an extra spin (not wired until it exists)
	SpinDuration = 4.2, -- seconds the wheel spins on the client before the reveal
	-- Toybox Island fills (the UI's design system): sky, leaf, candy, sun
	RarityColors = {
		Common = Color3.fromHex("#8ed2ef"),
		Rare = Color3.fromHex("#7cc47f"),
		Epic = Color3.fromHex("#ff9cc0"),
		Legendary = Color3.fromHex("#f7cd46"),
	},
}

Config.Rewards = {
	StreakEndMin = 5, -- "STREAK ENDED!" feed message threshold
}

Config.Progression = {
	XP = { Complete = 40, Win = 20, Hit = 3, Catch = 6, Knockout = 8, Revenge = 6 },
	MaxXPPerMatch = 150,
	LevelCap = 100,
	LevelBase = 100,
	LevelPerLevel = 25,
	StreakFlameAt = 3,
}

Config.Finisher = {
	Enabled = true,
	DefaultId = "Default",
	MinDuration = 3, -- every finisher runs 3-5 s (module Duration is clamped to this range)
	MaxDuration = 5,
}

-- Match intro (Splatoon-style): when a match starts, both teams stand on their spawns doing their
-- equipped intro poses while the camera dollies across the first team, then the second, then the
-- normal 3-2-1 countdown. Only the first round of a match gets the intro.
Config.Intro = {
	Enabled = true,
	Order = { "Blue", "Red" },
	BlueTime = 2,
	RedTime = 2,
	CameraBack = 9, -- studs in front of the line-up
	CameraUp = 2.4, -- above the players' roots (about chest height)
	PanOvershoot = 3, -- the pan starts/ends this far past the end players
	LookAhead = 2.5, -- the camera looks this far ahead along the line as it moves
	FieldOfView = 60,
}

Config.Net = {
	MaxActionsPerSecond = 20, -- sustained rate
	BurstActions = 40, -- short bursts allowed on top (inputs bunched up by a laggy connection)
	SuspicionLogThreshold = 10,
}

-- Performance mode (GraphicsController): turns on by itself on slow machines, or from ⚙ Settings.
Config.Graphics = {
	LowFps = 38, -- below this average for SlowWindowsToSwitch windows in a row: performance mode
	SampleWindow = 3, -- seconds per frame-rate sample
	SlowWindowsToSwitch = 2,
	WarmupTime = 8, -- ignore the first seconds after joining (loading hitches)
	LowQualityLevel = 3, -- a Roblox graphics quality of 1-3 (set by hand) starts in performance mode
	LowParticleScale = 0.4, -- one-shot effect bursts keep this share of their particles
}

Config.Visuals = {
	NeonIntensity = 0.5, -- every neon part, glow panel and scenery light shows at this fraction
}

Config.Camera = {
	MaxShake = 0.6,
	ShakeDecay = 6,
}

Config.Data = {
	StoreName = "PlayerData_v1",
	SchemaVersion = 5,
	AutosaveInterval = 120,
	MaxRetries = 4,
	SessionLockTimeout = 300,
}

Config.Teams = {
	Red = { Name = "RED", Color = Color3.fromRGB(232, 70, 60), Sign = -1 },
	Blue = { Name = "BLUE", Color = Color3.fromRGB(60, 120, 235), Sign = 1 },
}

return Config
