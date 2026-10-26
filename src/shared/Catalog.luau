--!strict
-- Every cosmetic, its coins price and (later) its Robux product id. Cosmetics never change
-- competitive stats: skins apply only to Standard balls so power-up types always stay readable,
-- and nothing here touches radius, speed, knockback or catch timing (spec §13).

export type Category = "BallSkin" | "Trail" | "Title" | "Finisher"

export type Item = {
	Id: string,
	Category: Category,
	Name: string,
	Price: number, -- coins; 0 = free / owned by default
	RobuxProductId: number, -- placeholder until products exist (Amendment A5)
	Default: boolean?,
	Data: { [string]: any },
}

local items: { Item } = {
	-- Ball skins: color/material of YOUR Standard ball while held and in flight.
	{ Id = "Skin_Classic", Category = "BallSkin", Name = "Classic", Price = 0, RobuxProductId = 0, Default = true, Data = {} },
	{
		Id = "Skin_Bubblegum",
		Category = "BallSkin",
		Name = "Bubblegum",
		Price = 500,
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 120, 190), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Lime",
		Category = "BallSkin",
		Name = "Lime",
		Price = 500,
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(150, 230, 60), Material = Enum.Material.SmoothPlastic },
	},
	{
		Id = "Skin_Ice",
		Category = "BallSkin",
		Name = "Ice",
		Price = 1200,
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(220, 245, 255), Material = Enum.Material.Ice },
	},
	{
		Id = "Skin_Gold",
		Category = "BallSkin",
		Name = "Gold",
		Price = 2500,
		RobuxProductId = 0,
		Data = { Color = Color3.fromRGB(255, 200, 50), Material = Enum.Material.Foil },
	},
	-- Trails behind YOUR throws.
	{ Id = "Trail_None", Category = "Trail", Name = "None", Price = 0, RobuxProductId = 0, Default = true, Data = {} },
	{
		Id = "Trail_Sparkle",
		Category = "Trail",
		Name = "Sparkle",
		Price = 400,
		RobuxProductId = 0,
		Data = { Colors = { Color3.new(1, 1, 1), Color3.fromRGB(255, 250, 200) } },
	},
	{
		Id = "Trail_Flame",
		Category = "Trail",
		Name = "Flame",
		Price = 800,
		RobuxProductId = 0,
		Data = { Colors = { Color3.fromRGB(255, 230, 80), Color3.fromRGB(255, 70, 30) } },
	},
	{
		Id = "Trail_Rainbow",
		Category = "Trail",
		Name = "Rainbow",
		Price = 1500,
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
	-- Titles shown on your name tag.
	{ Id = "Title_None", Category = "Title", Name = "None", Price = 0, RobuxProductId = 0, Default = true, Data = { Text = "" } },
	{ Id = "Title_Rookie", Category = "Title", Name = "Rookie", Price = 150, RobuxProductId = 0, Data = { Text = "Rookie" } },
	{ Id = "Title_DodgeMaster", Category = "Title", Name = "Dodge Master", Price = 1000, RobuxProductId = 0, Data = { Text = "Dodge Master" } },
	{ Id = "Title_SkyLauncher", Category = "Title", Name = "Sky Launcher", Price = 1500, RobuxProductId = 0, Data = { Text = "Sky Launcher" } },
	{ Id = "Title_Untouchable", Category = "Title", Name = "Untouchable", Price = 3000, RobuxProductId = 0, Data = { Text = "Untouchable" } },
	-- Finishers: the cutscene everyone in the match watches when you score the final knockout.
	-- Data.Module names a module in ReplicatedStorage.Shared.Finishers.
	{ Id = "Finisher_Default", Category = "Finisher", Name = "Final Knockout", Price = 0, RobuxProductId = 0, Default = true, Data = { Module = "Default" } },
	{ Id = "Finisher_Spotlight", Category = "Finisher", Name = "Spotlight", Price = 2000, RobuxProductId = 0, Data = { Module = "Spotlight" } },
	{
		Id = "Finisher_Meteor",
		Category = "Finisher",
		Name = "Meteor Strike",
		Price = 3000,
		RobuxProductId = 0,
		Data = { Module = "Meteor", Icon = "☄️" },
	},
	{
		Id = "Finisher_Pumpkin",
		Category = "Finisher",
		Name = "Pumpkin Reaper",
		Price = 2500,
		RobuxProductId = 0,
		Data = { Module = "Pumpkin", Icon = "🎃" },
	},
	{
		Id = "Finisher_PurpleFlash",
		Category = "Finisher",
		Name = "Purple Flash",
		Price = 4000,
		RobuxProductId = 0,
		Data = { Module = "PurpleFlash", Icon = "🟣" },
	},
}

local Catalog = {}

Catalog.Categories = { "BallSkin", "Trail", "Title", "Finisher" } :: { Category }
Catalog.CategoryNames = { BallSkin = "Ball Skins", Trail = "Trails", Title = "Titles", Finisher = "Finishers" }
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

-- The equipped item for a category from a profile's Equipped map, falling back to the default.
function Catalog.equipped(equipped: { [string]: string }?, category: string): Item
	local item = Catalog.get(equipped and equipped[category])
	if item and item.Category == category then
		return item
	end
	return Catalog.default(category)
end

return Catalog
