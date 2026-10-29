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
	Data: { [string]: any },
}

local items: { Item } = {
	-- Ball skins: color/material of YOUR Standard ball while held and in flight.
	{
		Id = "Skin_Classic",
		Category = "BallSkin",
		Name = "Classic",
		Price = 0,
		RobuxProductId = 0,
		Default = true,
		Data = {},
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
	{
		Id = "Skin_Gold",
		Category = "BallSkin",
		Name = "Gold",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 200, 50), Material = Enum.Material.Foil },
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
		RobuxProductId = 0,
		Data = { Module = "Meteor", Icon = "☄️" },
	},
	{
		Id = "Finisher_Pumpkin",
		Category = "Finisher",
		Name = "Pumpkin Reaper",
		Price = 2500, -- kept below the Epic price until the event ends (docs/ECONOMY.md §2)
		Rarity = "Epic",
		RobuxProductId = 0,
		Event = "Halloween", -- Halloween exclusive: on sale only during the event, kept once owned
		Limited = true,
		Data = { Module = "Pumpkin", Icon = "🎃" },
	},
	{
		Id = "Finisher_DestinyArrives",
		Category = "Finisher",
		Name = "Destiny Arrives",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = { Module = "DestinyArrives", Icon = "🌀" },
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
		RobuxProductId = 0,
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
		Id = "Finisher_OutOfThePark",
		Category = "Finisher",
		Name = "Out of the Park!",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
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
		RobuxProductId = 0,
		Data = { Pose = "Dab", Icon = "😎" },
	},
	{
		Id = "Pose_Robot",
		Category = "Pose",
		Name = "Robot",
		Price = Config.Economy.PriceByRarity.Epic,
		Rarity = "Epic",
		RobuxProductId = 0,
		Data = { Pose = "Robot", Icon = "🤖" },
	},
	{
		Id = "Pose_TrophyLift",
		Category = "Pose",
		Name = "Trophy Lift",
		Price = Config.Economy.PriceByRarity.Legendary,
		Rarity = "Legendary",
		RobuxProductId = 0,
		Data = { Pose = "TrophyLift", Icon = "🏆" }, -- its pose plays a confetti burst (IntroPoses Fx)
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

-- Is this item on sale (for coins) right now? Event items only while their event runs; bundle
-- and mastery items never.
function Catalog.isOffered(item: Item, events: { [string]: boolean }?): boolean
	if item.Bundle or item.Unlock then
		return false
	end
	if not item.Event then
		return true
	end
	return (events or Catalog.activeEvents())[item.Event] == true
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

-- The equipped item for a category from a profile's Equipped map, falling back to the default.
function Catalog.equipped(equipped: { [string]: string }?, category: string): Item
	local item = Catalog.get(equipped and equipped[category])
	if item and item.Category == category then
		return item
	end
	return Catalog.default(category)
end

return Catalog
