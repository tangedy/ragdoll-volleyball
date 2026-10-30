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
	-- hub time between matches (talk, practice, shop, spin): the match starts after this many
	-- seconds, or sooner once every queued player has pressed Ready
	LobbyMaxWait = 25,
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
	CourtLength = 144, -- along Z
	CourtWidth = 96, -- along X
	FloorThickness = 2,
	VoidDepth = 25, -- elimination plane below the court surface
	SpawnSetback = 36, -- spawn distance from the center line (36 from the back edge too)
	SpawnEdgeMargin = 21,
	OpeningBallSpots = 6,
	OpeningBallOffset = 9, -- studs from the center line
	BarrierHeight = 40,
	-- Overtime: outer strips retract symmetrically.
	OvertimeStripWidth = 9,
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
	LobbyOrigin = Vector3.new(-(96 / 2 + 36 + 84 / 2), 200, 0), -- -(CourtWidth/2 + LobbyGap + depth/2)
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
	-- Every throw is instant and full power (tap to fire): there is no charging.
	ThrowSpeed = 175,
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
	Horizontal = 50, -- every throw is full power
	Upward = 26, -- more hang time = bigger-looking launch without much extra distance
	MaxSpeed = 80, -- clamp on resulting limb velocity
	-- Exaggeration: the whole body tumbles about a random axis while each limb windmills on its
	-- floppy joint. Bodies keep their natural slide on landing (no extra friction).
	TumbleSpin = 7, -- rad/s whole-body flip
	LimbSpin = 9, -- rad/s random per-limb spin
	LimbFlail = 10, -- studs/s random per-limb velocity (averages out across the body)
	-- Each hit you take launches you harder (Smash-style). The knockback above is scaled by
	-- First + PerPercent × (your damage % before the hit), up to Max; the ragdoll lasts a little
	-- longer too. A long-range Standard hit (24%) adds ~0.48, so Max is reached around 105%.
	Escalation = { First = 0.3, PerPercent = 0.02, Max = 2.4 },
}

-- Damage % (Smash-style, shown on the HUD and over opponents' heads). Each hit adds PerHit × the
-- ball's DamageScale (BallDefinitions), scaled up for close-range hits; it only drives knockback
-- (Config.Knockback.Escalation): you're out when you're knocked off the court. Hits thrown from jail
-- land at your current % without raising it. It resets each round (not when you escape jail).
Config.Damage = {
	PerHit = 24, -- a Standard ball
	-- distance bonus (horizontal studs from where the ball was thrown): CloseMultiplier× at
	-- CloseRange or nearer, easing down to 1× at FarRange and beyond
	CloseRange = 15,
	FarRange = 70,
	CloseMultiplier = 1.6,
	Cap = 999,
	-- HUD / billboard color: white at 0%, yellow at YellowAt, red from RedAt
	YellowAt = 50,
	RedAt = 100,
	-- "Hit them off the court!" shows at match start for a player's first HintMatches matches
	HintMatches = 3,
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

-- Client auto-aim: while you hold a ball it's always locked on to an enemy in line of sight (the
-- one nearest your aim, or the nearest one in Aim lock), and a tap throws at them.
Config.AimAssist = {
	ConeDeg = { Mouse = 6, Gamepad = 10, Touch = 22 }, -- enemies inside this cone of the aim win the pick
	KeepFactor = 1.5, -- the current target stays picked while inside cone × this
	-- share of the target's movement the throw leads by (touch gets the strongest assist)
	Lead = { Mouse = 0.5, Gamepad = 0.8, Touch = 1 },
	Range = 220, -- studs
	BufferTime = 0.3, -- a tap during a dodge or throw recovery fires as soon as you're free
	-- incoming-ball warning: an enemy ball whose arc passes this close to you shows a "!"
	WarnRadius = 7,
	WarnLookahead = 1.2, -- seconds of the arc checked ahead
}

-- Camera lock modes (the lock button, or Shift / R3): Free is normal Roblox movement, Shift lock
-- keeps you facing where the camera looks, Aim lock keeps you facing the nearest enemy.
Config.Lock = {
	Modes = { "Free", "Shift", "Aim" },
	ShoulderOffset = 1.75, -- studs the camera moves right in Shift lock
}

-- Hub practice (client-side): each player has their own dummy and practice balls.
Config.Practice = {
	TemplateName = "PracticeDummyTemplate", -- the dummy rig the server parks in ReplicatedStorage
	Balls = 2,
	BallSpread = 4, -- studs between practice balls along the lane
	DummyRespawn = 0.75, -- seconds after the dummy falls off before a new one stands up
	BallRespawn = 0.5, -- seconds after a ball falls off before it's back at its spot
	RecoverAfter = 2.2, -- a launched dummy still on the deck stands back up after this long
	ThrowerLockout = 0.6, -- can't re-grab your own throw for this long
}

Config.PowerUps = {
	Enabled = true,
	DispenserInterval = 12,
	MaxPowerBallsPerSide = 1,
	Weights = { Heavy = 1, Rocket = 1, Pop = 1 },
	-- Featured ball of the day: one power type a UTC day, in BallDefinitions.PowerTypes order. It
	-- drops WeightBoost times as often, and its knockouts count MasteryBonus times toward Power Ball
	-- Mastery (the Catalog Unlock cosmetics).
	Featured = { Enabled = true, WeightBoost = 3, MasteryBonus = 2 },
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
	-- Difficulty profiles. Every bot gets one when it spawns (see Mix). All of them miss and fall for
	-- good throws, and none of them ever catch; Hard is sharper, never perfect.
	--   AimErrorDeg: random cone around a perfect throw · ReactionTime: seconds before reacting to
	--   an incoming ball · DodgeChance: how often it dodges once it has reacted · AimDelay: aim
	--   time before release · QuickThrowChance: snap
	--   throws with no aim time · EdgeCaution: studs from the edge where it starts backing off ·
	--   TargetSmarts: chance it picks the best target (near an edge, just got up, can't catch)
	--   instead of simply the nearest · Strafe: sidestep speed factor while aiming
	Profiles = {
		Easy = {
			AimErrorDeg = 11,
			ReactionTime = { 0.34, 0.55 },
			DodgeChance = 0.25,
			AimDelay = { 1.2, 2.1 },
			QuickThrowChance = 0.03,
			EdgeCaution = 11,
			TargetSmarts = 0.25,
			Strafe = 0.3,
		},
		Normal = {
			AimErrorDeg = 6.5,
			ReactionTime = { 0.24, 0.4 },
			DodgeChance = 0.4,
			AimDelay = { 0.9, 1.7 },
			QuickThrowChance = 0.08,
			EdgeCaution = 13,
			TargetSmarts = 0.6,
			Strafe = 0.6,
		},
		Hard = {
			AimErrorDeg = 4,
			ReactionTime = { 0.17, 0.3 },
			DodgeChance = 0.5,
			AimDelay = { 0.7, 1.3 },
			QuickThrowChance = 0.12,
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
	JailPickupDelay = 3, -- a jailed bot waits this long after a ball shows up before going for it
	PickupAfterThrow = 2, -- after throwing, a bot wanders this long before going for another ball
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

-- Coin bundles sold for Robux in the Coins sheet. Each one is a developer product: create it in the
-- Creator Dashboard (Monetization > Developer Products) and paste its id into ProductId. Robux is only
-- what the card shows until the real price loads from the product; a bundle whose ProductId is 0
-- shows "Soon" and can't be bought. Tag is an optional sticker ("Popular", "Best value").
-- Image (bundles and boosts): optional card icon, an Image asset id (upload a 512x512 decal in
-- Studio's Asset Manager and use its image id; briefs in docs/PASS_ICONS.md). While it's 0 the card
-- draws its own art (the coin heap, the 2x disc).
Config.CoinShop = {
	-- 2x coins boosts (developer products, BoostService): they double the coins you earn from
	-- matches and eliminations, never bundles, dailies or wheel refunds. The timed one runs in real
	-- time and buying it again adds Minutes. Boosts don't stack past BoostMultiplier.
	BoostMultiplier = 2,
	-- Robux placement (release plan, Stage 2): every Robux button stays hidden until the player has
	-- finished this many matches; the Coins sheet opens by itself only on the AutoOpenAfterFails-th
	-- coin purchase you couldn't afford, at most once a session.
	RobuxAfterMatches = 1,
	AutoOpenAfterFails = 3,
	Boosts = {
		{
			Id = "Boost30",
			Name = "2x Coins",
			Detail = "30 minutes",
			Robux = 19,
			ProductId = 3723376951,
			Image = 0, -- PLACEHOLDER: icon image id (optional)
			Minutes = 30,
			Forever = false,
		},
		{
			Id = "BoostForever",
			Name = "2x Coins",
			Detail = "Forever",
			Robux = 199,
			ProductId = 3723376954,
			Image = 0, -- PLACEHOLDER: icon image id (optional)
			Minutes = 0,
			Forever = true,
		},
	},
	Bundles = {
		{ Id = "Handful", Name = "Handful of coins", Coins = 1000, Robux = 49, ProductId = 3723376190, Image = 0 },
		{ Id = "Pouch", Name = "Pouch of coins", Coins = 2750, Robux = 99, ProductId = 3723376232, Image = 0 },
		{
			Id = "Sack",
			Name = "Sack of coins",
			Coins = 6000,
			Robux = 199,
			ProductId = 3723376234,
			Image = 0,
			Tag = "Popular",
		},
		{ Id = "Chest", Name = "Chest of coins", Coins = 16000, Robux = 499, ProductId = 3723376237, Image = 0 },
		{
			Id = "Vault",
			Name = "Vault of coins",
			Coins = 35000,
			Robux = 999,
			ProductId = 3723376239,
			Image = 0,
			Tag = "Best value",
		},
	},
	-- ==========================================================================================
	-- LIMITED-TIME OFFERS: Robux bundles of cosmetics plus coins, shown at the top of the Coins
	-- sheet only between Start (inclusive) and End (exclusive), UTC, so each one hides itself when
	-- it ends without a republish. PurchaseService grants Items (catalog ids, each marked with
	-- Bundle = this offer's Id) and Coins.
	--   PLACEHOLDERS TO FILL IN (0 until created):
	--   * ProductId: a developer product (Creator Dashboard > Monetization > Developer Products).
	--     While it's 0 the card shows "Soon" and can't be bought.
	--   * Image: optional card art, an Image asset id (upload a decal in Studio's Asset Manager and
	--     use its image id). While it's 0 the card draws its own pumpkin.
	-- Robux is only what the card shows until the real price loads from the product.
	-- ==========================================================================================
	Offers = {
		{
			Id = "Halloween2026",
			Name = "Haunted Bundle",
			Items = {
				"Skin_JackOLantern",
				"Pose_PumpkinHead",
				"Finisher_Pumpkin",
				"Title_Ghost",
				"Skin_Witchbrew",
				"Trail_Ectoplasm",
				"Title_PumpkinKing",
			},
			Coins = 5000,
			Robux = 299,
			ProductId = 3723612223, -- developer product "Haunted Bundle"
			Image = 0, -- PLACEHOLDER: card art image id (optional)
			Start = "2026-10-28T00:00:00Z",
			End = "2026-11-04T00:00:00Z", -- on sale through Nov 3 (UTC)
			Tag = "Limited",
			-- its stand in the hub (BundleDisplayController), in deck coordinates like Config.Lobby
			Display = { X = 12, F = -14 },
		},
	},
}

-- 7-day login ladder (docs/ECONOMY.md §3); day 8 starts the ladder again. A missed day resets to
-- day 1, which is a strong welcome back on purpose. Each day is a typed reward that
-- RewardService.grant hands out (daily quests use the same kinds):
--   { Kind = "Coins", Amount = n }
--   { Kind = "Spin", Wheel = id }   a free bonus spin on Config.Spin.Wheels[id], used from the Spin
--                                   sheet; it stacks with the daily free spin
--   { Kind = "Boost", Id = id }     a free Config.CoinShop.Boosts entry
--   { Kind = "Cosmetic", Id = id }  one catalog item (DuplicateCoins if it's already owned)
--   { Kind = "Cosmetic", Rarity = r, Choices = n, DuplicateCoins = c }  pick 1 of n unowned items of
--                                   that rarity (c coins when none are left)
--   { Kind = "Chest", Chest = id }  open a Config.Quests.Chests chest now: one item of its category
export type Reward = {
	Kind: string,
	Amount: number?,
	Wheel: string?,
	Id: string?,
	Rarity: string?,
	Choices: number?,
	DuplicateCoins: number?,
	Chest: string?,
}
Config.DailyRewards = {
	Ladder = {
		{ Kind = "Spin", Wheel = "RarePlus" },
		{ Kind = "Coins", Amount = 250 },
		{ Kind = "Boost", Id = "Boost30" },
		{ Kind = "Coins", Amount = 400 },
		{ Kind = "Spin", Wheel = "Standard" },
		{ Kind = "Coins", Amount = 600 },
		{ Kind = "Cosmetic", Rarity = "Epic", Choices = 3, DuplicateCoins = 1000 },
	} :: { Reward },
}

-- Daily cosmetic spin (separate from the coin ladder above). One free spin per UTC day; extra spins
-- can be bought with coins. Every wheel has Slots prizes drawn by rarity weight from the catalog,
-- and the server picks one slot uniformly, so each spin's real odds are exactly what the wheel shows.
Config.Spin = {
	Slots = 12,
	RarityWeights = { Common = 60, Rare = 28, Epic = 10, Legendary = 2 },
	DuplicateCoins = { Common = 100, Rare = 250, Epic = 500, Legendary = 1000 }, -- already owned
	ExtraSpinCost = 1000, -- coins
	MaxPaidPerDay = 5,
	RobuxProductId = 3723376241, -- developer product "Extra daily spin" (35 Robux; price set in the Creator Dashboard)
	RobuxImage = 0, -- PLACEHOLDER: icon image id on the Robux spin button (optional; docs/PASS_ICONS.md)
	SpinDuration = 4.2, -- seconds the wheel spins on the client before the reveal
	-- Toybox Island fills (the UI's design system): sky, leaf, candy, sun
	RarityColors = {
		Common = Color3.fromHex("#8ed2ef"),
		Rare = Color3.fromHex("#7cc47f"),
		Epic = Color3.fromHex("#ff9cc0"),
		Legendary = Color3.fromHex("#f7cd46"),
	},
}
-- Wheels a free bonus spin (a login reward) can be on. Bonus spins are free, so they're allowed where
-- paid random items are restricted.
Config.Spin.Wheels = {
	Standard = { Name = "Bonus spin", RarityWeights = Config.Spin.RarityWeights },
	RarePlus = { Name = "Rare+ spin", RarityWeights = { Common = 0, Rare = 70, Epic = 24, Legendary = 6 } },
}

-- Cosmetic economy (docs/ECONOMY.md §2). Every prize item has an explicit Rarity in the Catalog and
-- sells for its rarity's flat price, so a price change never moves an item between tiers.
-- DuplicateCoins (20% of the price) is what a daily quest chest pays when you already own every
-- item of the rarity it rolled. RobuxPriceByRarity is what a Robux-exclusive cosmetic (Item.Exclusive)
-- costs; exclusives are Epic or Legendary only. RobuxPriceByCategory overrides it for the smaller
-- cosmetics (titles and gestures).
Config.Economy = {
	PriceByRarity = { Common = 500, Rare = 1750, Epic = 5000, Legendary = 12000 },
	DuplicateCoins = { Common = 100, Rare = 350, Epic = 1000, Legendary = 2400 },
	RobuxPriceByRarity = { Epic = 79, Legendary = 199 },
	RobuxPriceByCategory = {
		Title = { Epic = 39, Legendary = 99 },
		Pose = { Epic = 39, Legendary = 99 },
	},
}

-- Daily quests (docs/ECONOMY.md §4). Progress resets at UTC midnight; each quest's chest can be
-- claimed once that UTC day, after its goal is reached. Progress comes from the match events that
-- already pay rewards: a credited knockout (bots included, the same as the 25-coin knockout
-- payout), and a finished match you took part in (the anti-AFK rule the match coins use).
--   Event: "Knockout" | "Played" | "Won"
-- Quest chests are free, so they're allowed where paid random items are restricted.
-- The very first time a player claims a quest, it comes back FirstCooldown seconds later (fresh
-- progress) instead of waiting for the UTC reset; every later claim waits for the reset.
Config.Quests = {
	FirstCooldown = 15 * 60,
	List = {
		{ Id = "Knockouts", Name = "Knock out 3", Event = "Knockout", Goal = 3, Chest = "Title" },
		{ Id = "Played", Name = "Play 2 games", Event = "Played", Goal = 2, Chest = "Gesture" },
		{ Id = "Won", Name = "Win 1 game", Event = "Won", Goal = 1, Chest = "Finisher" },
	},
	-- Each chest rolls one item of its Catalog category: a rarity by RarityWeights (rarities the
	-- category has no prize items in are skipped and the rest renormalized), then an unowned item
	-- of that rarity at random, or Config.Economy.DuplicateCoins when every one is owned.
	-- Gestures are the Pose category (the intro poses).
	Chests = {
		Title = {
			Name = "Title Chest",
			Category = "Title",
			RarityWeights = { Common = 55, Rare = 30, Epic = 12, Legendary = 3 },
		},
		Gesture = {
			Name = "Gesture Chest",
			Category = "Pose",
			RarityWeights = { Common = 60, Rare = 28, Epic = 10, Legendary = 2 },
		},
		Finisher = {
			Name = "Finisher Chest",
			Category = "Finisher",
			RarityWeights = { Common = 60, Rare = 30, Epic = 9, Legendary = 1 },
		},
	},
	RevealSlots = 12, -- prizes on the reveal wheel (the chest's drops, the rolled prize among them)
	SpinDuration = 4.2, -- seconds the reveal wheel spins on the client
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
	-- Destiny Arrives: the titan's look, baked from a set of catalog items (the server builds it once
	-- into ReplicatedStorage; if that fails the finisher dresses the practice dummy instead). Asset ids
	-- are HumanoidDescription fields; anything left out stays the default.
	DestinyAvatar = {
		Head = 10725826963,
		LeftArm = 27112052,
		Shirt = 5648314277,
		Pants = 3107419155,
		Accessories = {
			-- the gauntlet: sold as a shoulder accessory hung on the torso, where it only lines up with
			-- the hand at rest; AttachTo re-welds it to the hand so it follows the snap
			{ AssetId = 2988781799, AccessoryType = Enum.AccessoryType.Shoulder, AttachTo = "LeftHand" },
		},
		SkinColor = Color3.fromRGB(167, 94, 155), -- every body part
	},
	DestinyTemplateName = "DestinyTitanTemplate",
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
	LowPropHz = 30, -- performance mode: hub props (wheels, fans) animate at most this often
	LowTitleFps = 4, -- performance mode: animated titles redraw this many times a second (else 10)
	PropCullDistance = 180, -- hub wheels this far from the camera stop turning (you can't see them)
}

Config.Visuals = {
	NeonIntensity = 0.5, -- every neon part, glow panel and scenery light shows at this fraction
	FinisherNeon = 0.7, -- finisher neon and lights are dimmed further by this (not Purple Flash)
	FinisherNeonExempt = { PurpleFlash = true, Pumpkin = true }, -- the jack-o-lantern's carved face must glow
	-- Outlines so players and balls stand out from the court: each team is outlined in the other
	-- team's color (blue players stand on a blue floor), and balls get a dark ink outline.
	TeamOutline = { Red = Color3.fromRGB(60, 120, 235), Blue = Color3.fromRGB(232, 70, 60) },
	BallOutline = Color3.fromRGB(28, 20, 14),
}

-- The dev room (DevRoomService): ";" in Studio or for the game's owner. A dark hall far above the
-- map, built while someone is in it, showing work in progress (today the Haunted Wheel).
Config.DevRoom = {
	Origin = Vector3.new(0, 420, 900), -- floor centre
	Size = Vector3.new(44, 26, 48),
}

-- Halloween event. `Enabled` is the switch servers start with; the live state is the "Halloween"
-- attribute on ReplicatedStorage (HalloweenService), which the dev toggle flips at runtime: H in
-- Studio or for the game's owner, or workspace:SetAttribute("RD_Halloween", true/false) from the
-- server command bar. While it's on: dusk lighting, props from the asset pack around the hub, the
-- Haunted Wheel in place of the spin station's booth, the music, the Halloween UI palette, jack-o-lantern balls, and the Halloween cosmetics in the shop.
Config.Halloween = {
	Enabled = true,
	-- UTC window the event runs in (Start inclusive, End exclusive). Servers switch it on and off by
	-- themselves at these times, so the event ends without a republish. End is Nov 2 00:00 UTC, so
	-- Halloween night lasts its full evening in the Americas too.
	Start = "2026-10-01T00:00:00Z",
	End = "2026-11-02T00:00:00Z",
	-- looping background music (free DistroKid tracks from the Creator Store), played in turn
	Music = { "rbxassetid://111631783838916", "rbxassetid://115585877205328" },
	MusicVolume = { Hub = 0.32, Match = 0.16 }, -- quieter while you're playing
	-- Halloween lighting (ArenaBuilder.setupLighting restores the normal day)
	Lighting = {
		ClockTime = 17.95, -- the sun just setting: an orange horizon and stars, with the court still easy to read
		Brightness = 2.4,
		Ambient = Color3.fromRGB(146, 118, 168),
		OutdoorAmbient = Color3.fromRGB(160, 128, 178),
		Atmosphere = {
			Density = 0.32,
			Offset = 0.1,
			Color = Color3.fromRGB(196, 140, 200),
			Decay = Color3.fromRGB(120, 50, 80),
			Glare = 0.4,
			Haze = 1.4,
		},
		Bloom = { Intensity = 1, Size = 26, Threshold = 0.95 },
		Color = { Saturation = 0.18, Contrast = 0.1, Brightness = 0.02, Tint = Color3.fromRGB(255, 232, 214) },
		VoidGlow = Color3.fromRGB(255, 120, 40), -- the glow far below the court turns pumpkin orange
	},
	-- Props from ServerStorage.HalloweenAssets ("Folder/Model"), placed on the hub deck (deck frame:
	-- X = right, F = toward the court, Yaw 0 = facing the court). A spot that would overlap anything
	-- already on the deck is skipped, so the hub's own layout always wins.
	Props = {
		{ Asset = "Structures/SkullArch", X = 0, F = 18, Yaw = 0, Scale = 1 },
		{ Asset = "Props/PumpkinStack", X = -8, F = -24, Yaw = 20, Scale = 1 },
		{ Asset = "Props/PumpkinStack", X = 27, F = -24, Yaw = -25, Scale = 1 },
		{ Asset = "Lighting/JackSignPostLantern", X = -24, F = 10, Yaw = 30, Scale = 1 },
		{ Asset = "Lighting/BannerLanternPost", X = 24, F = 10, Yaw = -30, Scale = 1 },
		{ Asset = "Lighting/BigLantern", X = -36, F = -30, Yaw = 0, Scale = 1 },
		{ Asset = "Lighting/BigLantern", X = 36, F = -30, Yaw = 0, Scale = 1 },
		{ Asset = "Props/PurpleCauldron", X = -28, F = -12, Yaw = 0, Scale = 1 },
		{ Asset = "Props/PurpleScarecrow", X = 47, F = 22, Yaw = -60, Scale = 1 },
		{ Asset = "Props/LanternCrateStack", X = -48, F = -36, Yaw = 40, Scale = 1 },
		{ Asset = "Graveyard/FencedGrave", X = 46, F = -36, Yaw = -30, Scale = 1 },
		{ Asset = "Graveyard/LeaningCoffin", X = 30, F = -38, Yaw = 10, Scale = 1 },
		{ Asset = "Structures/CandleFence", X = -16, F = 26, Yaw = 0, Scale = 1 },
		{ Asset = "Structures/CandleFence", X = 16, F = 26, Yaw = 0, Scale = 1 },
		{ Asset = "Structures/PotionStall", X = -45, F = 24, Yaw = 60, Scale = 1 },
		{ Asset = "Structures/LanternWell", X = 40, F = 2, Yaw = 0, Scale = 1 },
		{ Asset = "Nature/HauntedLanternTree", X = -52, F = 34, Yaw = 0, Scale = 1 },
		{ Asset = "Nature/CrystalTree", X = 52, F = 34, Yaw = 0, Scale = 1 },
		{ Asset = "Creatures/BlackCat", X = -6, F = 8, Yaw = 150, Scale = 1 },
	},
	-- jack-o-lantern Standard balls (client-side look; the ball's physics never change)
	Ball = {
		Body = Color3.fromRGB(255, 122, 26),
		Rib = Color3.fromRGB(214, 90, 14),
		Stem = Color3.fromRGB(86, 120, 44),
		Carve = Color3.fromRGB(255, 214, 90), -- the glowing carved face
		Scale = 1.2, -- body size relative to the ball (its height is squashed to 88%), so the sphere stays hidden inside
	},
}

Config.Camera = {
	MaxShake = 0.6,
	ShakeDecay = 6,
}

Config.Data = {
	StoreName = "PlayerData_v1",
	SchemaVersion = 12,
	AutosaveInterval = 120,
	MaxRetries = 4,
	LockWaitRetries = 10, -- 3 s apart: how long a joiner waits for another server to release their save
	SessionLockTimeout = 300,
}

Config.Teams = {
	Red = { Name = "RED", Color = Color3.fromRGB(232, 70, 60), Sign = -1 },
	Blue = { Name = "BLUE", Color = Color3.fromRGB(60, 120, 235), Sign = 1 },
}

return Config
