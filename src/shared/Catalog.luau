--!strict
-- Every cosmetic (ball skins, trails, titles, finishers, intro poses), its coins price and (later)
-- its Robux product id. Cosmetics never change
-- competitive stats: skins apply only to Standard balls so power-up types always stay readable,
-- and nothing here touches radius, speed, knockback or catch timing (spec §13).

local BallDefinitions = require(script.Parent.BallDefinitions)
local Config = require(script.Parent.Config)

export type Category = "BallSkin" | "Trail" | "Title" | "Finisher" | "Pose"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type Item = {
	Id: string,
	Category: Category,
	Name: string,
	Price: number, -- coins; 0 = free / owned by default. Config.Economy.PriceByRarity for prizes
	-- the item's tier (docs/ECONOMY.md §2): it sets the shop tag, the wheel and chest odds and the
	-- duplicate coins. Every non-default item has one; price no longer decides it.
	Rarity: Rarity?,
	RobuxProductId: number, -- placeholder until products exist (Amendment A5)
	Default: boolean?,
	-- an event cosmetic (e.g. "Halloween"): sold only while that event is on, never on the spin or
	-- chest wheels, and kept forever once owned. Limited items show a LIMITED tag.
	Event: string?,
	Limited: boolean?,
	-- a bundle cosmetic: only granted by that Robux bundle (Config.CoinShop.Offers Id), never sold
	-- for coins, and on the shelf only once owned. Price is just its value.
	Bundle: string?,
	-- a Power Ball Mastery cosmetic: granted once the player has this many credited knockouts with
	-- that power ball (Ball = "All": that many with each type). Never sold, spun or rolled; on the
	-- shelf locked, with progress, until earned.
	Unlock: { Ball: string, Knockouts: number }?,
	-- a Robux-exclusive cosmetic: bought only with its own developer product (RobuxProductId, at
	-- Config.Economy.RobuxPriceByRarity / ByCategory), never sold for coins, spun or rolled. On the shelf with a
	-- Robux button and an EXCLUSIVE tag. Price is just its value. Epic or Legendary only.
	Exclusive: boolean?,
	Data: { [string]: any },
}

-- The forms a Legendary skin can show (BallModels.Forms): picked one per pickup.
local FORMS = { "Nice", "Evil", "Glitched" }

local items: { Item } = {
	-- Ball skins: color/material of YOUR Standard ball while held and in flight.
	{
		Id = "Skin_Classic",
		Category = "BallSkin",
		Name = "Classic",
		Price = 0,
		RobuxProductId = 0,
		Default = true,
		Data = { Color = BallDefinitions.get("Standard").Color, Material = Enum.Material.SmoothPlastic }, -- red
	},
	{
		Id = "Skin_Orange",
		Category = "BallSkin",
		Name = "Orange",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 140, 30), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Yellow",
		Category = "BallSkin",
		Name = "Yellow",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 215, 40), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Green",
		Category = "BallSkin",
		Name = "Green",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(60, 200, 80), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Blue",
		Category = "BallSkin",
		Name = "Blue",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(40, 120, 255), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Purple",
		Category = "BallSkin",
		Name = "Purple",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(150, 70, 230), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_DarkGray",
		Category = "BallSkin",
		Name = "Dark Gray",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(70, 72, 80), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_White",
		Category = "BallSkin",
		Name = "White",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(245, 245, 245), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Bubblegum",
		Category = "BallSkin",
		Name = "Bubblegum",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 120, 190), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Lime",
		Category = "BallSkin",
		Name = "Lime",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(150, 230, 60), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Ice",
		Category = "BallSkin",
		Name = "Ice",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(220, 245, 255), Material = Enum.Material.Ice },
	},
	-- Data.Pattern: drawn on the ball by BallSkinController ("Zebra": black bands welded around a
	-- white ball; "Rainbow": the color cycles through the hues). Data.Reflectance: a metallic shine.
	{
		Id = "Skin_Zebra",
		Category = "BallSkin",
		Name = "Zebra",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(245, 245, 245), Material = Enum.Material.SmoothPlastic, Pattern = "Zebra" },
	},
	{
		Id = "Skin_Rainbow",
		Category = "BallSkin",
		Name = "Rainbow",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.SmoothPlastic, Pattern = "Rainbow" },
	},
	{
		Id = "Skin_Silver",
		Category = "BallSkin",
		Name = "Silver",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(205, 212, 222), Material = Enum.Material.Foil, Reflectance = 0.45 },
	},
	{
		Id = "Skin_Gold",
		Category = "BallSkin",
		Name = "Gold",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare", -- was Epic until Oct 29; owners keep it
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 196, 40), Material = Enum.Material.Foil, Reflectance = 0.35 },
	},
	-- Data.Model: a BallModels look shown in place of the sphere (BallSkinController); the sphere's
	-- size and physics never change. Color is the look's main color (the fallback if it can't build).
	{
		Id = "Skin_Basketball",
		Category = "BallSkin",
		Name = "Basketball",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(232, 110, 32), Material = Enum.Material.SmoothPlastic, Model = "Basketball" },
	},
	{
		Id = "Skin_Soccer",
		Category = "BallSkin",
		Name = "Soccer Ball",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(245, 245, 245), Material = Enum.Material.SmoothPlastic, Model = "Soccer" },
	},
	{
		Id = "Skin_Tennis",
		Category = "BallSkin",
		Name = "Tennis Ball",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(206, 232, 58), Material = Enum.Material.SmoothPlastic, Model = "Tennis" },
	},
	{
		Id = "Skin_EightBall",
		Category = "BallSkin",
		Name = "Eight Ball",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(18, 18, 22), Material = Enum.Material.SmoothPlastic, Model = "EightBall" },
	},
	-- effect skins: model skins with light effects (BallModels: Neon, a light, embers or sparkles)
	{
		Id = "Skin_Meteor",
		Category = "BallSkin",
		Name = "Meteor",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(62, 50, 46), Material = Enum.Material.Basalt, Model = "Meteor" }, -- goes with the Meteor Strike finisher
	},
	{
		Id = "Skin_DiscoBall",
		Category = "BallSkin",
		Name = "Disco Ball",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(205, 210, 222), Material = Enum.Material.Foil, Model = "DiscoBall" },
	},
	{
		Id = "Skin_Planet",
		Category = "BallSkin",
		Name = "Planet",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(96, 70, 170), Material = Enum.Material.SmoothPlastic, Model = "Planet" },
	},
	{
		Id = "Skin_Bomb",
		Category = "BallSkin",
		Name = "Bomb",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(32, 32, 38), Material = Enum.Material.SmoothPlastic, Model = "Bomb" },
	},
	-- The Legendary set (Verity, Falsity, Lovity, Cruelty): model skins with Data.Variants, the forms
	-- one of which shows on each pickup (never the same twice in a row; ShopService.pickForm). Every
	-- skin has the same three forms, each in its own colors (BallModels).
	{
		Id = "Skin_Verity",
		Category = "BallSkin",
		Name = "Verity",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = {
			Color = Color3.fromRGB(246, 242, 230),
			Material = Enum.Material.SmoothPlastic,
			Model = "Verity",
			Variants = FORMS,
		}, -- pearl white and gold
	},
	{
		Id = "Skin_Falsity",
		Category = "BallSkin",
		Name = "Falsity",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = {
			Color = Color3.fromRGB(112, 62, 172),
			Material = Enum.Material.SmoothPlastic,
			Model = "Falsity",
			Variants = FORMS,
		}, -- purple, with a smiling and a frowning mask
	},
	{
		Id = "Skin_Lovity",
		Category = "BallSkin",
		Name = "Lovity",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = {
			Color = Color3.fromRGB(255, 150, 196),
			Material = Enum.Material.SmoothPlastic,
			Model = "Lovity",
			Variants = FORMS,
		}, -- pink, scattered with hearts
	},
	{
		Id = "Skin_Cruelty",
		Category = "BallSkin",
		Name = "Cruelty",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = {
			Color = Color3.fromRGB(184, 22, 34),
			Material = Enum.Material.SmoothPlastic,
			Model = "Cruelty",
			Variants = FORMS,
		}, -- crimson, with a jagged black bite
	},
	-- Robux exclusives (Item.Exclusive): model skins with their own light and particles; the two
	-- Legendaries also shift between the Legendary forms on every pickup (Data.Variants)
	{
		Id = "Skin_Galaxy",
		Category = "BallSkin",
		Name = "Galaxy",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Color = Color3.fromRGB(14, 12, 40),
			Material = Enum.Material.SmoothPlastic,
			Model = "Galaxy",
		}, -- stars, nebulae and a twinkle
	},
	{
		Id = "Skin_StormCore",
		Category = "BallSkin",
		Name = "Storm Core",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Color = Color3.fromRGB(120, 220, 255),
			Material = Enum.Material.SmoothPlastic,
			Model = "StormCore",
		}, -- plasma core, jumping lightning arcs
	},
	{
		Id = "Skin_Sovereign",
		Category = "BallSkin",
		Name = "Sovereign",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Color = Color3.fromRGB(240, 190, 60),
			Material = Enum.Material.SmoothPlastic,
			Model = "Sovereign",
			Variants = FORMS,
		}, -- gold, jewels and a floating crown
	},
	{
		Id = "Skin_Phoenix",
		Category = "BallSkin",
		Name = "Phoenix",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Color = Color3.fromRGB(255, 120, 30),
			Material = Enum.Material.SmoothPlastic,
			Model = "Phoenix",
			Variants = FORMS,
		}, -- flame plumes and sparks
	},
	{
		Id = "Skin_Witchbrew",
		Category = "BallSkin",
		Name = "Witch's Brew",
		Price = 2500,
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only
		Data = { Color = Color3.fromRGB(140, 60, 220), Material = Enum.Material.Neon },
	},
	{
		Id = "Skin_JackOLantern",
		Category = "BallSkin",
		Name = "Jack-o'-Lantern",
		Price = 2500,
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only
		-- your Standard balls wear the carved Halloween pumpkin all year (BallModels "Pumpkin")
		Data = { Color = Config.Halloween.Ball.Body, Material = Enum.Material.SmoothPlastic, Model = "Pumpkin" },
	},
	-- Trails behind YOUR throws.
	{ Id = "Trail_None", Category = "Trail", Name = "None", Price = 0, RobuxProductId = 0, Default = true, Data = {} },
	{
		Id = "Trail_Sparkle",
		Category = "Trail",
		Name = "Sparkle",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Colors = { Color3.new(1, 1, 1), Color3.fromRGB(255, 250, 200) } },
	},
	{
		Id = "Trail_Flame",
		Category = "Trail",
		Name = "Flame",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Colors = { Color3.fromRGB(255, 230, 80), Color3.fromRGB(255, 70, 30) } },
	},
	{
		Id = "Trail_Rainbow",
		Category = "Trail",
		Name = "Rainbow",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = {
			Colors = {
				Color3.fromRGB(255, 60, 60),
				Color3.fromRGB(255, 220, 60),
				Color3.fromRGB(60, 220, 90),
				Color3.fromRGB(60, 140, 255),
			},
		},
	},
	{
		Id = "Trail_Ectoplasm",
		Category = "Trail",
		Name = "Ectoplasm",
		Price = 2500,
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only
		Data = { Colors = { Color3.fromRGB(140, 255, 90), Color3.fromRGB(150, 70, 230) } },
	},
	{
		Id = "Trail_PowerSurge",
		Category = "Trail",
		Name = "Power Surge",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Unlock = { Ball = "All", Knockouts = 25 }, -- Power Ball Mastery: 25 knockouts with each type
		Data = {
			Colors = { Color3.fromRGB(255, 140, 20), Color3.fromRGB(40, 140, 255), Color3.fromRGB(170, 70, 230) },
		},
	},
	-- Robux exclusives: longer, wider, glowing trails that shed sparkles (Catalog.trailStyle)
	{
		Id = "Trail_Aurora",
		Category = "Trail",
		Name = "Aurora",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Colors = { Color3.fromRGB(90, 255, 170), Color3.fromRGB(60, 200, 255), Color3.fromRGB(170, 90, 255) },
			Lifetime = 0.6,
			Width = 1.6,
			Glow = 0.8,
			Sparkle = { Color3.fromRGB(200, 255, 230), Color3.fromRGB(160, 140, 255) },
			SparkleRate = 18,
		}, -- northern lights
	},
	{
		Id = "Trail_NeonPulse",
		Category = "Trail",
		Name = "Neon Pulse",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Colors = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(255, 255, 255), Color3.fromRGB(40, 230, 255) },
			Lifetime = 0.5,
			Width = 1.3,
			Glow = 1,
			Sparkle = { Color3.fromRGB(255, 120, 220), Color3.fromRGB(80, 240, 255) },
			SparkleRate = 22,
		}, -- hot pink to cyan
	},
	{
		Id = "Trail_Stardust",
		Category = "Trail",
		Name = "Stardust",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Colors = { Color3.fromRGB(255, 236, 150), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 190, 70) },
			Lifetime = 0.8,
			Width = 1.8,
			Glow = 1,
			Sparkle = { Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 210, 90) },
			SparkleRate = 35,
		}, -- a comet's tail of gold
	},
	{
		Id = "Trail_VoidRift",
		Category = "Trail",
		Name = "Void Rift",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Colors = { Color3.fromRGB(170, 80, 255), Color3.fromRGB(40, 10, 70), Color3.fromRGB(10, 0, 20) },
			Lifetime = 0.8,
			Width = 2,
			Glow = 0.4,
			Sparkle = { Color3.fromRGB(200, 120, 255), Color3.fromRGB(90, 255, 230) },
			SparkleRate = 30,
		}, -- a tear in space
	},
	-- Titles shown on your name tag.
	{
		Id = "Title_None",
		Category = "Title",
		Name = "None",
		Price = 0,
		RobuxProductId = 0,
		Default = true,
		Data = { Text = "" },
	},
	{
		Id = "Title_Rookie",
		Category = "Title",
		Name = "Rookie",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Rookie" },
	},
	{
		Id = "Title_DodgeMaster",
		Category = "Title",
		Name = "Dodge Master",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Text = "Dodge Master" },
	},
	{
		Id = "Title_SkyLauncher",
		Category = "Title",
		Name = "Sky Launcher",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Text = "Sky Launcher" },
	},
	{
		Id = "Title_Untouchable",
		Category = "Title",
		Name = "Untouchable",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Text = "Untouchable" },
	},
	{
		Id = "Title_Bonk",
		Category = "Title",
		Name = "Bonk",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Bonk" },
	},
	{
		Id = "Title_Wobbly",
		Category = "Title",
		Name = "Wobbly",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Wobbly" },
	},
	{
		Id = "Title_Benchwarmer",
		Category = "Title",
		Name = "Benchwarmer",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Benchwarmer" },
	},
	{
		Id = "Title_Butterfingers",
		Category = "Title",
		Name = "Butterfingers",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Butterfingers" },
	},
	{
		Id = "Title_BallHog",
		Category = "Title",
		Name = "Ball Hog",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Ball Hog" },
	},
	{
		Id = "Title_NoodleArms",
		Category = "Title",
		Name = "Noodle Arms",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Text = "Noodle Arms" },
	},
	{
		Id = "Title_CatchKing",
		Category = "Title",
		Name = "Catch King",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Text = "Catch King" },
	},
	{
		Id = "Title_Jailbreaker",
		Category = "Title",
		Name = "Jailbreaker",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Text = "Jailbreaker" },
	},
	{
		Id = "Title_Bullseye",
		Category = "Title",
		Name = "Bullseye",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Text = "Bullseye" },
	},
	{
		Id = "Title_ComebackKid",
		Category = "Title",
		Name = "Comeback Kid",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Text = "Comeback Kid" },
	},
	{
		Id = "Title_VoidWalker",
		Category = "Title",
		Name = "Void Walker",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Text = "Void Walker" },
	},
	{
		Id = "Title_Showstopper",
		Category = "Title",
		Name = "Showstopper",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Text = "Showstopper" },
	},
	{
		Id = "Title_IronWall",
		Category = "Title",
		Name = "Iron Wall",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Text = "Iron Wall" },
	},
	{
		Id = "Title_RagdollRoyalty",
		Category = "Title",
		Name = "Ragdoll Royalty",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = { Text = "Ragdoll Royalty" },
	},
	{
		Id = "Title_FinalBoss",
		Category = "Title",
		Name = "The Final Boss",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = { Text = "The Final Boss" },
	},
	-- Power Ball Mastery titles: earned with power-ball knockouts (Unlock), never sold or rolled.
	{
		Id = "Title_Heavyweight",
		Category = "Title",
		Name = "Heavyweight",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Unlock = { Ball = "Heavy", Knockouts = 10 },
		Data = { Text = "Heavyweight" },
	},
	{
		Id = "Title_Rocketeer",
		Category = "Title",
		Name = "Rocketeer",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Unlock = { Ball = "Rocket", Knockouts = 10 },
		Data = { Text = "Rocketeer" },
	},
	{
		Id = "Title_PopStar",
		Category = "Title",
		Name = "Pop Star",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Unlock = { Ball = "Pop", Knockouts = 10 },
		Data = { Text = "Pop Star" },
	},
	{
		Id = "Title_PumpkinKing",
		Category = "Title",
		Name = "Pumpkin King",
		Price = 1500,
		Rarity = "Rare",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only
		Data = { Text = "Pumpkin King" },
	},
	{
		Id = "Title_Ghost",
		Category = "Title",
		Name = "Ghost",
		Price = 2500,
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only
		-- Style "Ghost": a special name tag, pale and see-through and framed in ghosts (ShopService)
		Data = { Text = "Ghost", Style = "Ghost", Icon = "👻" },
	},
	-- Robux exclusives: gradient titles, each letter its own color (TitleStyle); the Legendaries
	-- shimmer, the gradient sliding along them (TitleFxController)
	{
		Id = "Title_NeonAce",
		Category = "Title",
		Name = "Neon Ace",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Text = "Neon Ace",
			Gradient = { Color3.fromRGB(40, 230, 255), Color3.fromRGB(255, 60, 200) },
		}, -- cyan into pink
	},
	{
		Id = "Title_MidnightMenace",
		Category = "Title",
		Name = "Midnight Menace",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Text = "Midnight Menace",
			Gradient = { Color3.fromRGB(120, 80, 255), Color3.fromRGB(40, 140, 255), Color3.fromRGB(200, 120, 255) },
		}, -- purple and blue
	},
	{
		Id = "Title_TheChosenOne",
		Category = "Title",
		Name = "The Chosen One",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Text = "The Chosen One",
			Gradient = { Color3.fromRGB(255, 210, 70), Color3.fromRGB(255, 255, 230), Color3.fromRGB(255, 160, 40) },
			Animated = true,
		}, -- shimmering gold
	},
	{
		Id = "Title_MainCharacter",
		Category = "Title",
		Name = "Main Character",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true,
		Data = {
			Text = "Main Character",
			Gradient = {
				Color3.fromRGB(255, 80, 80),
				Color3.fromRGB(255, 200, 60),
				Color3.fromRGB(80, 230, 120),
				Color3.fromRGB(60, 160, 255),
				Color3.fromRGB(200, 100, 255),
			},
			Animated = true,
		}, -- a rainbow that never stops
	},
	-- Finishers: the cutscene everyone in the match watches when you score the final knockout.
	-- Data.Module names a module in ReplicatedStorage.Shared.Finishers.
	{
		Id = "Finisher_Default",
		Category = "Finisher",
		Name = "Final Knockout",
		Price = 0,
		RobuxProductId = 0,
		Default = true,
		Data = { Module = "Default" },
	},
	{
		Id = "Finisher_ConfettiPop",
		Category = "Finisher",
		Name = "Confetti Pop",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Module = "ConfettiPop", Icon = "🎉" },
	},
	{
		Id = "Finisher_AirHorn",
		Category = "Finisher",
		Name = "Air Horn",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Module = "AirHorn", Icon = "📯" },
	},
	{
		Id = "Finisher_SadTrombone",
		Category = "Finisher",
		Name = "Sad Trombone",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Module = "SadTrombone", Icon = "🎺" },
	},
	{
		Id = "Finisher_Bonk",
		Category = "Finisher",
		Name = "BONK!",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Module = "Bonk", Icon = "🔨" },
	},
	{
		Id = "Finisher_SlowMoReplay",
		Category = "Finisher",
		Name = "Slow-Mo Replay",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Module = "SlowMoReplay", Icon = "🎬" },
	},
	{
		Id = "Finisher_Paparazzi",
		Category = "Finisher",
		Name = "Paparazzi",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Module = "Paparazzi", Icon = "📸" },
	},
	{
		Id = "Finisher_Spotlight",
		Category = "Finisher",
		Name = "Spotlight",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Module = "Spotlight" },
	},
	{
		Id = "Finisher_Meteor",
		Category = "Finisher",
		Name = "Meteor Strike",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Module = "Meteor", Icon = "☄️" },
	},
	{
		Id = "Finisher_Pumpkin",
		Category = "Finisher",
		Name = "Pumpkin Reaper",
		Price = 2500,
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only (no longer sold for coins)
		Data = { Module = "Pumpkin", Icon = "🎃" },
	},
	{
		Id = "Finisher_DestinyArrives",
		Category = "Finisher",
		Name = "Destiny Arrives",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Module = "DestinyArrives", Icon = "🌀" },
	},
	{
		Id = "Finisher_Supernova",
		Category = "Finisher",
		Name = "Supernova",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = { Module = "Supernova", Icon = "🌟" }, -- the Finisher Chest's coin Legendary (Oct 29)
	},
	{
		Id = "Finisher_PurpleFlash",
		Category = "Finisher",
		Name = "Purple Flash",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Module = "PurpleFlash", Icon = "🟣" },
	},
	{
		Id = "Finisher_BlackHole",
		Category = "Finisher",
		Name = "Black Hole",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Module = "BlackHole", Icon = "🕳️" },
	},
	{
		Id = "Finisher_DodgeballRush",
		Category = "Finisher",
		Name = "Dodgeball Rush",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Module = "DodgeballRush", Icon = "🥊" },
	},
	{
		Id = "Finisher_BubbleTrouble",
		Category = "Finisher",
		Name = "Bubble Trouble",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Module = "BubbleTrouble", Icon = "🫧" },
	},
	{
		Id = "Finisher_OutOfThePark",
		Category = "Finisher",
		Name = "Out of the Park!",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Module = "OutOfThePark", Icon = "⚾" },
	},
	-- Intro poses: what you do while the match-start camera pans across your team.
	-- Data.Pose names a pose in Shared.IntroPoses.
	{
		Id = "Pose_Cheer",
		Category = "Pose",
		Name = "Fist Pump",
		Price = 0,
		RobuxProductId = 0,
		Default = true,
		Data = { Pose = "Cheer", Icon = "✊" },
	},
	{
		Id = "Pose_Wave",
		Category = "Pose",
		Name = "Big Wave",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Pose = "Wave", Icon = "👋" },
	},
	{
		Id = "Pose_ThumbsUp",
		Category = "Pose",
		Name = "Thumbs Up",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Pose = "ThumbsUp", Icon = "👍" },
	},
	{
		Id = "Pose_Shrug",
		Category = "Pose",
		Name = "Shrug",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Pose = "Shrug", Icon = "🤷" },
	},
	{
		Id = "Pose_Clap",
		Category = "Pose",
		Name = "Clap",
		Price = Config.Economy.PriceByRarity.Common,
		Rarity = "Common",
		RobuxProductId = 0,
		Data = { Pose = "Clap", Icon = "👏" },
	},
	{
		Id = "Pose_Salute",
		Category = "Pose",
		Name = "Salute",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Pose = "Salute", Icon = "🫡" },
	},
	{
		Id = "Pose_AirGuitar",
		Category = "Pose",
		Name = "Air Guitar",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Pose = "AirGuitar", Icon = "🎸" },
	},
	{
		Id = "Pose_Flex",
		Category = "Pose",
		Name = "Flex",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Pose = "Flex", Icon = "💪" },
	},
	{
		Id = "Pose_Point",
		Category = "Pose",
		Name = "You're Next",
		Price = Config.Economy.PriceByRarity.Rare,
		Rarity = "Rare",
		RobuxProductId = 0,
		Data = { Pose = "Point", Icon = "👉" },
	},
	{
		Id = "Pose_Bow",
		Category = "Pose",
		Name = "Take a Bow",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Pose = "Bow", Icon = "🙇" },
	},
	{
		Id = "Pose_Dab",
		Category = "Pose",
		Name = "Dab",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Pose = "Dab", Icon = "😎" },
	},
	{
		Id = "Pose_Robot",
		Category = "Pose",
		Name = "Robot",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Pose = "Robot", Icon = "🤖" },
	},
	{
		Id = "Pose_Floss",
		Category = "Pose",
		Name = "The Floss",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Pose = "Floss", Icon = "🕺" },
	},
	{
		Id = "Pose_HeartHands",
		Category = "Pose",
		Name = "Heart Hands",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Pose = "HeartHands", Icon = "🫶" },
	},
	{
		Id = "Pose_PowerUp",
		Category = "Pose",
		Name = "Power Up",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = { Pose = "PowerUp", Icon = "⚡" }, -- the Gesture Chest's coin Legendary; a golden aura flares (IntroPoses Fx)
	},
	{
		Id = "Pose_TrophyLift",
		Category = "Pose",
		Name = "Trophy Lift",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0, -- placeholder: set once the developer product exists (0 = not registered)
		Exclusive = true, -- Robux exclusive since Oct 29 (was a coin item: owners keep it)
		Data = { Pose = "TrophyLift", Icon = "🏆" }, -- its pose plays a confetti burst (IntroPoses Fx)
	},
	{
		Id = "Pose_PumpkinHead",
		Category = "Pose",
		Name = "Pumpkin Head",
		Price = 2500,
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween",
		Limited = true,
		Bundle = "Halloween2026", -- Haunted Bundle only
		-- a jack-o-lantern over your head while you shuffle like Frankenstein's monster (IntroPoses Prop)
		Data = { Pose = "PumpkinHead", Icon = "🎃" },
	},
}

local Catalog = {}

Catalog.Categories = { "BallSkin", "Trail", "Title", "Finisher", "Pose" } :: { Category }
Catalog.CategoryNames = {
	BallSkin = "Ball Skins",
	Trail = "Trails",
	Title = "Titles",
	Finisher = "Finishers",
	Pose = "Gestures",
}
Catalog.Items = items

local byId: { [string]: Item } = {}
for _, item in items do
	byId[item.Id] = item
end

function Catalog.get(id: string?): Item?
	return if id then byId[id] else nil
end

function Catalog.default(category: string): Item
	for _, item in items do
		if item.Category == category and item.Default then
			return item
		end
	end
	error("no default for " .. category)
end

function Catalog.inCategory(category: string): { Item }
	local list = {}
	for _, item in items do
		if item.Category == category then
			table.insert(list, item)
		end
	end
	return list
end

-- An item's rarity tier (its explicit Rarity; defaults have none and count as Common). Used by the
-- shop tags, the daily spin and the quest chests.
function Catalog.rarity(item: Item): Rarity
	return item.Rarity or "Common"
end

-- Which events are running right now (the server sets an attribute per event on ReplicatedStorage;
-- only "Halloween" exists so far).
function Catalog.activeEvents(): { [string]: boolean }
	local rs = game:GetService("ReplicatedStorage")
	return { Halloween = rs:GetAttribute("Halloween") == true }
end

-- Is this item on sale (for coins) right now? Event items only while their event runs; bundle,
-- mastery and Robux-exclusive items never.
function Catalog.isOffered(item: Item, events: { [string]: boolean }?): boolean
	if item.Bundle or item.Unlock or item.Exclusive then
		return false
	end
	if not item.Event then
		return true
	end
	return (events or Catalog.activeEvents())[item.Event] == true
end

-- A Robux-exclusive item's price in Robux (Config.Economy.RobuxPriceByCategory for titles and
-- gestures, else RobuxPriceByRarity), or nil for any other item.
function Catalog.robuxPrice(item: Item): number?
	if not item.Exclusive then
		return nil
	end
	local rarity = Catalog.rarity(item)
	local byCategory = (Config.Economy.RobuxPriceByCategory :: any)[item.Category]
	if byCategory and byCategory[rarity] then
		return byCategory[rarity]
	end
	return (Config.Economy.RobuxPriceByRarity :: any)[rarity]
end

-- Is a limited-time Robux bundle (Config.CoinShop.Offers) on sale at `now` (unix seconds)? Inside
-- its UTC Start/End window only. This only hides the card: a receipt that arrives later still grants.
function Catalog.offerLive(offer: any, now: number): boolean
	return now >= DateTime.fromIsoDate(offer.Start).UnixTimestamp
		and now < DateTime.fromIsoDate(offer.End).UnixTimestamp
end

-- Power Ball Mastery progress toward an Unlock item from a PowerKOs map ({ Heavy = n, ... }):
-- (have, need). For Ball = "All", `have` is the lowest count across the power types.
function Catalog.unlockProgress(item: Item, powerKOs: { [string]: number }?): (number, number)
	local u = item.Unlock
	if not u then
		return 0, 0
	end
	local kos = powerKOs or {}
	if u.Ball ~= "All" then
		return math.min(u.Knockouts, tonumber(kos[u.Ball]) or 0), u.Knockouts
	end
	local low = math.huge
	for _, t in BallDefinitions.PowerTypes do
		low = math.min(low, tonumber(kos[t]) or 0)
	end
	return math.min(u.Knockouts, low), u.Knockouts
end

-- How a trail draws past its colors: plain trails use the ball's defaults; exclusive ones set
-- Data.Lifetime (seconds), Data.Width (x the ball's trail width), Data.Glow (LightEmission 0-1) and
-- Data.Sparkle (particle colors shed along the path, at Data.SparkleRate a second).
export type TrailStyle = {
	lifetime: number?,
	width: number?,
	glow: number?,
	sparkle: { Color3 }?,
	sparkleRate: number?,
}
function Catalog.trailStyle(item: Item): TrailStyle?
	local d = item.Data
	if not (d.Lifetime or d.Width or d.Glow or d.Sparkle) then
		return nil
	end
	return { lifetime = d.Lifetime, width = d.Width, glow = d.Glow, sparkle = d.Sparkle, sparkleRate = d.SparkleRate }
end

-- The equipped item for a category from a profile's Equipped map, falling back to the default.
function Catalog.equipped(equipped: { [string]: string }?, category: string): Item
	local item = Catalog.get(equipped and equipped[category])
	if item and item.Category == category then
		return item
	end
	return Catalog.default(category)
end

return Catalog
