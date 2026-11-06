--!strict
-- The goal chip over the hub's coin card: the item you're saving for and how close you are. It's
-- the item you last couldn't afford (ShopService.setGoal, profile.savingFor), or until you pick
-- one, the cheapest coin item you can't afford yet ("Next up"). Once you can afford it, the chip
-- turns sun and says so. Tapping the chip opens the shop on the item; its "+" opens the Coins
-- sheet with the coins you're missing (once Robux buttons are unlocked). Hub only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Net = require(script.Parent.Net)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox

local SavingController = {}

local SIZE = Vector2.new(260, 58)

local profile: any = nil
local refs: { [string]: any } = {}
local goalId: string? = nil
local need = 0

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby"
		and (player:GetAttribute("Team") or "") == ""
		and player:GetAttribute("TutorialDone") == true
end

local function commas(n: number): string
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (s:gsub("^,", ""))
end

local function owns(item: Catalog.Item): boolean
	return item.Default == true or (profile and profile.owned and profile.owned[item.Id] == true)
end

local function priceOf(item: Catalog.Item): number
	local Shop = require(script.Parent.ShopController) :: any
	return Shop.priceOf(item)
end

-- The pinned goal if it's still a coin item you don't own, else the cheapest one you can't afford.
local function pickGoal(): (Catalog.Item?, boolean)
	local pinned = Catalog.get(profile.savingFor)
	if pinned and Catalog.coinSold(pinned) and not owns(pinned) then
		return pinned, true
	end
	local coins = profile.coins or 0
	local best: Catalog.Item? = nil
	for _, item in Catalog.Items do
		if Catalog.coinSold(item) and not owns(item) and priceOf(item) > coins then
			if not best or priceOf(item) < priceOf(best) then
				best = item
			end
		end
	end
	return best, false
end

local function render()
	local chip = refs.chip :: Frame?
	if not chip then
		return
	end
	if not profile then
		chip.Visible = false
		return
	end
	local item, pinned = pickGoal()
	goalId = if item then item.Id else nil
	chip.Visible = item ~= nil and inHub()
	if not item then
		return
	end
	local coins = profile.coins or 0
	local price = priceOf(item)
	need = math.max(0, price - coins)
	local ready = need == 0
	chip.BackgroundColor3 = if ready then T.sun else T.surface
	refs.title.Text = if ready
		then ("Buy %s now!"):format(item.Name)
		else ((if pinned then "Saving for " else "Next up: ") .. item.Name)
	refs.title.TextColor3 = if ready then Theme.textOn(T.sun) else T.ink
	refs.count.Text = ("%s / %s"):format(commas(math.min(coins, price)), commas(price))
	refs.count.TextColor3 = refs.title.TextColor3
	refs.fill.Size = UDim2.fromScale(math.clamp(coins / math.max(price, 1), 0, 1), 1)
	refs.fill.BackgroundColor3 = Theme.Rarity[Catalog.rarity(item)] or T.sun
	local CoinShop = require(script.Parent.CoinShopController) :: any
	refs.plus.Visible = not ready and CoinShop.unlocked()
end

local function build(card: Frame)
	local chip = Theme.panel(card, {
		Name = "Goal",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(0, -18), -- above the coin card, clear of its 2x COINS sticker
		Size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		Visible = false,
	}, Theme.Radius.M)
	refs.chip = chip
	local hit = Theme.new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 3,
	}, chip)
	refs.title = Theme.text(chip, 16, {
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.new(1, -70, 0, 20),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	})
	local back = Theme.new("Frame", {
		Position = UDim2.fromOffset(14, 33),
		Size = UDim2.new(1, -130, 0, 12),
		BackgroundColor3 = T.surfaceSunk,
		ZIndex = 2,
	}, chip)
	Theme.round(back)
	refs.fill = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.sun, ZIndex = 2 }, back)
	Theme.round(refs.fill)
	refs.count = Theme.text(chip, 13, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -58, 0, 29),
		Size = UDim2.fromOffset(100, 20),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
	})
	refs.plus = Theme.iconButton(chip, "plus", "primary", 34, {
		Name = "GetCoins",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		ZIndex = 4,
	})
	hit.Activated:Connect(function()
		if goalId then
			local Shop = require(script.Parent.ShopController) :: any
			Shop.openToItem(goalId)
		end
	end)
	refs.plus.Activated:Connect(function()
		local CoinShop = require(script.Parent.CoinShopController) :: any
		CoinShop.open(true, if need > 0 then need else nil)
	end)
end

function SavingController.start()
	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui"):WaitForChild("Profile", 30)
		local card = gui and gui:WaitForChild("Chip", 30)
		if not card then
			return
		end
		build(card :: Frame)
		render()
	end)
	Net.on("Profile", function(d)
		profile = d
		render()
	end)
	for _, key in { "Status", "Team", "TutorialDone", "RobuxOk" } do
		player:GetAttributeChangedSignal(key):Connect(render)
	end
end

return SavingController
