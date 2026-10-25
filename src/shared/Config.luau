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
	SpawnSetback = 30, -- spawn distance from the center line
	SpawnEdgeMargin = 14,
	OpeningBallSpots = 6,
	OpeningBallOffset = 6, -- studs from the center line
	BarrierHeight = 40,
	-- Overtime: outer strips retract symmetrically.
	OvertimeStripWidth = 6,
	OvertimeStrips = 4, -- per side
	OvertimeStepInterval = 5,
	OvertimeWarning = 1,
	LobbyOrigin = Vector3.new(0, 200, -170),
	LobbySize = Vector3.new(70, 2, 70),
}

Config.Jail = {
	Enabled = true,
	StripDepth = 8,
	Gap = 4, -- void gap between a team's back line and the jail strip behind it
	RespawnDelay = 1.5,
	ReturnDelay = 1.0,
	ReturnImmunity = 1.5,
	MaxReturnsPerRound = 2,
}

Config.Player = {
	WalkSpeed = 18,
	JumpPower = 42,
	PickupRadius = 5,
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
	KnockoutCreditWindow = 4,
	MaxPitchUpDeg = 50,
	MaxPitchDownDeg = 35,
	HitProxySize = Vector3.new(3.2, 5.4, 2.4),
}

Config.Knockback = {
	HorizontalMin = 28,
	HorizontalMax = 40,
	Upward = 18,
	MaxSpeed = 70, -- clamp on resulting limb velocity
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

Config.PowerUps = {
	Enabled = true,
	DispenserInterval = 12,
	MaxPowerBallsPerSide = 1,
	Weights = { Heavy = 1, Rocket = 1, Pop = 1 },
}

Config.Bots = {
	Enabled = true,
	MaxPerServer = 5,
	TickInterval = 0.2,
	AimDelayMin = 0.6,
	AimDelayMax = 1.4,
	AimErrorDeg = { Easy = 8, Normal = 4 },
	Difficulty = "Easy",
	DodgeChance = 0.25,
	CatchChance = 0.10,
	ReactRange = 30,
	EdgeAvoid = 10, -- minimum distance from the edge when picking a wander target
	VoidAvoid = 6,
	WanderInterval = { 1.5, 3.5 },
	RewardMultiplier = 0.5,
	Names = { "Bot Bounce", "Bot Bonk", "Bot Zoom", "Bot Wobble", "Bot Pop", "Bot Flop" },
}

-- Pts: the one in-game currency. Earned from match wins (highest tier only), a small
-- participation payout for the losing team, and daily login rewards. Nothing else pays pts.
Config.Pts = {
	Win = 200, -- your team won the match
	WinAlive = 300, -- ...and you were on the court (not jailed/spectating) when it was won
	WinFlawless = 500, -- ...and you were never eliminated during the whole match
	WinLastElimination = 600, -- ...you scored the match-ending knockout
	LossParticipation = 50, -- finished a match you actually played in, on the losing team
	MinParticipationActions = 1, -- throws/catches/dodges needed for ANY pts payout (anti-AFK)
}

-- 7-day login ladder; day 8 starts the ladder again. A missed day resets to day 1.
Config.DailyRewards = {
	Ladder = { 100, 150, 200, 250, 300, 400, 750 },
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
	MaxDuration = 6, -- server-side cap; a finisher module's own Duration must be <= this
}

Config.Net = {
	MaxActionsPerSecond = 20,
	SuspicionLogThreshold = 10,
}

Config.Camera = {
	MaxShake = 0.6,
	ShakeDecay = 6,
}

Config.Data = {
	StoreName = "PlayerData_v1",
	SchemaVersion = 3,
	AutosaveInterval = 120,
	MaxRetries = 4,
	SessionLockTimeout = 300,
}

Config.Teams = {
	Red = { Name = "RED", Color = Color3.fromRGB(232, 70, 60), Sign = -1 },
	Blue = { Name = "BLUE", Color = Color3.fromRGB(60, 120, 235), Sign = 1 },
}

return Config
