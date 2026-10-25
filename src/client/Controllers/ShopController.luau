--!strict
-- Hub UI: the coins shop/locker (buy and equip cosmetics) and the daily login reward. Shown only in
-- the hub, never during a match. While the shop is open the player stays in the hub (auto-queue is
-- paused and restored on close) so the short intermission never yanks them out mid-purchase.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local C = Theme.Colors

local ShopController = {}

local gui: ScreenGui
local shopPanel: Frame
local dailyPanel: Frame
local grid: ScrollingFrame
local coinsLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local dailyBadge: Frame
local dailyBoxes: { Frame } = {}
local claimButton: TextButton
local currentTab = "BallSkin"
local profile: any = { coins = 0, owned = {}, equipped = {}, daily = nil }
local queueBeforeShop: boolean? = nil
local dailyAutoShown = false
local claimPending = false -- the player pressed Claim and we're waiting for the server's answer

local new = Theme.new

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function owns(item: Catalog.Item): boolean
	return item.Default == true or (profile.owned and profile.owned[item.Id] == true)
end

local function isEquipped(item: Catalog.Item): boolean
	return Catalog.equipped(profile.equipped, item.Category).Id == item.Id
end

-- Card accent by price: free/common gray-blue, mid purple, high gold.
local function tierColor(item: Catalog.Item): Color3
	if item.Price >= 2000 then
		return C.Gold
	elseif item.Price >= 800 then
		return C.Purple
	elseif item.Price > 0 then
		return Color3.fromRGB(70, 150, 255)
	end
	return Color3.fromRGB(120, 115, 160)
end

local function preview(item: Catalog.Item, parent: Instance)
	local box = new("Frame", {
		Size = UDim2.new(1, -16, 0, 74),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
	}, parent)
	Theme.corner(box, 12)
	local d = item.Data
	if item.Category == "BallSkin" then
		local ball = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, box)
		Theme.round(ball)
		local col = d.Color or Color3.fromRGB(214, 48, 49)
		Theme.gradient(ball, Theme.lighten(col, 0.45), Theme.darken(col, 0.15), 45)
		Theme.stroke(ball, C.Ink, 3)
		-- shine
		local shine = new("Frame", {
			Position = UDim2.fromScale(0.2, 0.15),
			Size = UDim2.fromScale(0.3, 0.22),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.35,
		}, ball)
		Theme.round(shine)
	elseif item.Category == "Trail" then
		local colors = d.Colors
		if colors and #colors > 0 then
			local keys = {}
			for i, c in colors do
				table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), c))
			end
			if #keys == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
			end
			local bar = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.82, 0, 0, 18),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Rotation = -12,
			}, box)
			Theme.round(bar)
			new("UIGradient", {
				Color = ColorSequence.new(keys),
				Transparency = NumberSequence.new(1, 0),
			}, bar)
		else
			Theme.label(box, { Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.25), Text = "NONE", TextColor3 = C.Muted }, 2)
		end
	else
		local text = if item.Category == "Title" then (if d.Text and d.Text ~= "" then d.Text else "NONE") else "🎬"
		Theme.label(box, {
			Size = UDim2.new(1, -12, 0.6, 0),
			Position = UDim2.new(0, 6, 0.2, 0),
			Text = text,
			TextColor3 = if item.Category == "Title" then C.Gold else Color3.new(1, 1, 1),
		}, 2.5)
	end
end

local function renderGrid()
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for name, b in tabButtons do
		Theme.recolor(b, if name == currentTab then C.Gold else C.PanelLight)
	end
	coinsLabel.Text = tostring(profile.coins or 0)
	for i, item in Catalog.inCategory(currentTab) do
		local accent = tierColor(item)
		local card = new("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, grid)
		Theme.corner(card, 16)
		Theme.gradient(card, Theme.darken(accent, 0.45), C.Panel)
		Theme.stroke(card, if isEquipped(item) then C.Green else accent, if isEquipped(item) then 4 else 2.5)
		preview(item, card)
		Theme.label(card, {
			Position = UDim2.fromOffset(8, 86),
			Size = UDim2.new(1, -16, 0, 24),
			Text = item.Name,
		}, 2)
		local owned = owns(item)
		local equipped = isEquipped(item)
		local affordable = owned or (profile.coins or 0) >= item.Price
		local label = if equipped then "EQUIPPED" elseif owned then "EQUIP" else ("%d COINS"):format(item.Price)
		local color = if equipped then Color3.fromRGB(90, 85, 120) elseif owned then C.Green elseif affordable then C.Gold else Color3.fromRGB(120, 70, 80)
		local btn = Theme.button(card, label, color, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 40),
		})
		btn.Activated:Connect(function()
			if equipped then
				return
			end
			if owned then
				Net.request(Net.Actions.EquipItem, { id = item.Id })
			elseif affordable then
				Net.request(Net.Actions.BuyItem, { id = item.Id })
			else
				SoundController.play("UIError")
				HUDController.hint(("Need %d more coins"):format(item.Price - (profile.coins or 0)), 1.5)
			end
		end)
	end
end

local function renderDaily()
	local d = profile.daily
	dailyBadge.Visible = d ~= nil and not d.claimed
	if not d then
		return
	end
	for i, box in dailyBoxes do
		local isNext = i == d.day
		local done = i < d.day or (d.claimed and i == d.day)
		local grad = box:FindFirstChildOfClass("UIGradient") :: UIGradient
		local stroke = box:FindFirstChildOfClass("UIStroke") :: UIStroke
		local check = box:FindFirstChild("Check") :: TextLabel
		if done then
			grad.Color = ColorSequence.new(Theme.lighten(C.Green, 0.2), C.GreenDark)
			stroke.Color = C.Ink
		elseif isNext then
			grad.Color = ColorSequence.new(Theme.lighten(C.Gold, 0.3), C.GoldDark)
			stroke.Color = Color3.new(1, 1, 1)
		else
			grad.Color = ColorSequence.new(C.PanelLight, C.Panel)
			stroke.Color = C.Ink
		end
		check.Visible = done
	end
	Theme.setText(claimButton, if d.claimed then "COME BACK TOMORROW!" else ("CLAIM %d COINS"):format(d.amount))
	Theme.recolor(claimButton, if d.claimed then Color3.fromRGB(90, 85, 120) else C.Gold)
end

-- Claimed: today's box pops with a check, the button says come back tomorrow, the panel closes
-- itself, and the coins fly into the counter.
local function celebrateClaim(day: number, amount: number)
	local box = dailyBoxes[day]
	if box then
		local sc = box:FindFirstChildOfClass("UIScale") or new("UIScale", nil, box)
		sc.Scale = 1.35
		TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local check = box:FindFirstChild("Check") :: GuiObject?
		if check then
			Theme.pop(check, 0.2, 0.4)
		end
	end
	task.defer(function()
		-- after the regular profile refresh repaints the panel
		Theme.recolor(claimButton, C.Green)
		Theme.pop(claimButton, 0.8, 0.3)
	end)
	SoundController.play("DailyClaim")
	task.delay(1.4, function()
		if dailyPanel.Visible then
			ShopController.openDaily(false)
		end
		HUDController.coinPop(amount)
	end)
end

function ShopController.claimDaily()
	if profile.daily and not profile.daily.claimed and not claimPending then
		claimPending = true
		Net.request(Net.Actions.ClaimDaily)
	end
end

function ShopController.openShop(on: boolean)
	if on and not inHub() then
		return
	end
	if on and not shopPanel.Visible then
		SoundController.play("UIOpen")
		Theme.pop(shopPanel, 0.7, 0.3)
	end
	shopPanel.Visible = on
	if on then
		dailyPanel.Visible = false
		renderGrid()
		if queueBeforeShop == nil then
			queueBeforeShop = player:GetAttribute("AutoQueue") ~= false
			Net.request(Net.Actions.SetAutoQueue, { value = false })
		end
	elseif queueBeforeShop ~= nil then
		Net.request(Net.Actions.SetAutoQueue, { value = queueBeforeShop })
		queueBeforeShop = nil
	end
end

function ShopController.openDaily(on: boolean)
	if on and not inHub() then
		return
	end
	if on and not dailyPanel.Visible then
		SoundController.play("UIOpen")
		Theme.pop(dailyPanel, 0.7, 0.3)
	end
	dailyPanel.Visible = on
	if on then
		ShopController.openShop(false)
		renderDaily()
	end
end

local function panel(name: string, size: UDim2, title: string, maxSize: Vector2): (Frame, TextButton)
	local p = Theme.panel(gui, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = size,
		Visible = false,
		Active = true,
	}, 22)
	new("UISizeConstraint", { MaxSize = maxSize }, p)
	-- title ribbon
	local ribbon = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.fromOffset(250, 48),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	}, p)
	Theme.corner(ribbon, 14)
	Theme.gradient(ribbon, Theme.lighten(C.Purple, 0.25), C.Purple)
	Theme.stroke(ribbon, C.Ink, 3)
	Theme.label(ribbon, { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), Text = title, ZIndex = 4 }, 3)
	local close = Theme.button(p, "X", C.Danger, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 10, 0, -12),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 5,
	})
	return p, close
end

function ShopController.init()
	gui = new("ScreenGui", {
		Name = "Hub",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 8,
	}, player:WaitForChild("PlayerGui"))

	-- Big hub buttons on the right edge
	local buttons = new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(128, 150),
		BackgroundTransparency = 1,
	}, gui)
	new("UIListLayout", { Padding = UDim.new(0, 12) }, buttons)
	local shopBtn = Theme.button(buttons, "🛒 SHOP", Color3.fromRGB(255, 140, 40), { Size = UDim2.fromOffset(128, 66) })
	shopBtn.Activated:Connect(function()
		ShopController.openShop(not shopPanel.Visible)
	end)
	local dailyBtn = Theme.button(buttons, "🎁 DAILY", Color3.fromRGB(70, 150, 255), { Size = UDim2.fromOffset(128, 66) })
	dailyBtn.Activated:Connect(function()
		ShopController.openDaily(not dailyPanel.Visible)
	end)
	dailyBadge = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = C.Danger,
		Visible = false,
		ZIndex = 6,
	}, dailyBtn)
	Theme.round(dailyBadge)
	Theme.stroke(dailyBadge, Color3.new(1, 1, 1), 2.5)
	Theme.label(dailyBadge, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = "!", ZIndex = 7 }, 1.5)

	-- Shop & locker
	local close
	shopPanel, close = panel("Shop", UDim2.fromScale(0.8, 0.76), "SHOP & LOCKER", Vector2.new(760, 540))
	close.Activated:Connect(function()
		ShopController.openShop(false)
	end)
	local wallet = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -54, 0, 14),
		Size = UDim2.fromOffset(150, 38),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
	}, shopPanel)
	Theme.round(wallet)
	local coin = new("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.new(1, 1, 1) }, wallet)
	Theme.round(coin)
	Theme.gradient(coin, C.Gold, C.GoldDark)
	Theme.label(coin, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = "C" }, 1.5)
	coinsLabel = Theme.label(wallet, {
		Position = UDim2.fromOffset(38, 5),
		Size = UDim2.new(1, -46, 1, -10),
		Text = "0",
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
	local tabs = new("Frame", {
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.new(1, -36, 0, 44),
		BackgroundTransparency = 1,
	}, shopPanel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	for _, cat in Catalog.Categories do
		local b = Theme.button(tabs, Catalog.CategoryNames[cat], C.PanelLight, { Size = UDim2.new(0.25, -6, 1, 0) })
		b.Activated:Connect(function()
			currentTab = cat
			renderGrid()
		end)
		tabButtons[cat] = b
	end
	grid = new("ScrollingFrame", {
		Position = UDim2.fromOffset(18, 116),
		Size = UDim2.new(1, -36, 1, -130),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, shopPanel)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, grid)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(158, 168),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	-- Daily reward
	local dclose
	dailyPanel, dclose = panel("Daily", UDim2.fromScale(0.72, 0.5), "DAILY REWARD", Vector2.new(720, 330))
	dclose.Activated:Connect(function()
		ShopController.openDaily(false)
	end)
	local row = new("Frame", {
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 0.5, 0),
		BackgroundTransparency = 1,
	}, dailyPanel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, row)
	for i, amount in Config.DailyRewards.Ladder do
		local box = new("Frame", {
			Size = UDim2.new(1 / #Config.DailyRewards.Ladder, -8, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, row)
		Theme.corner(box, 14)
		Theme.gradient(box, C.PanelLight, C.Panel)
		Theme.stroke(box, C.Ink, 3)
		Theme.label(box, {
			Size = UDim2.new(1, -8, 0.24, 0),
			Position = UDim2.fromOffset(4, 6),
			Text = ("DAY %d"):format(i),
		}, 2)
		Theme.label(box, {
			Size = UDim2.new(1, -8, 0.34, 0),
			Position = UDim2.new(0, 4, 0.36, 0),
			Text = tostring(amount),
			TextColor3 = if i == #Config.DailyRewards.Ladder then C.Gold else Color3.new(1, 1, 1),
		}, 2.5)
		Theme.body(box, {
			Size = UDim2.new(1, -8, 0.14, 0),
			Position = UDim2.new(0, 4, 0.74, 0),
			Text = "COINS",
			TextColor3 = C.Muted,
		})
		Theme.label(box, {
			Name = "Check",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 6, 0, -8),
			Size = UDim2.fromOffset(28, 28),
			Text = "✓",
			TextColor3 = C.Green,
			Visible = false,
		}, 2.5)
		table.insert(dailyBoxes, box)
	end
	claimButton = Theme.button(dailyPanel, "CLAIM", C.Gold, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0.62, 0, 0, 58),
	})
	claimButton.Activated:Connect(function()
		ShopController.claimDaily()
	end)
end

function ShopController.start()
	Net.on("Profile", function(d)
		local justClaimed = claimPending and d.daily and d.daily.claimed
		profile = d
		if justClaimed then
			claimPending = false
			renderDaily()
			celebrateClaim(d.daily.day, Config.DailyRewards.Ladder[d.daily.day] or 0)
		end
		if shopPanel.Visible then
			renderGrid()
		end
		renderDaily()
		-- show the daily card once per session when there's something to claim (never auto-claims)
		if not dailyAutoShown and d.daily and not d.daily.claimed and inHub() then
			dailyAutoShown = true
			task.delay(1.5, function()
				if inHub() and not shopPanel.Visible then
					ShopController.openDaily(true)
				end
			end)
		end
	end)
	Net.on("ShopResult", function(d)
		if not d.ok and d.message then
			HUDController.hint(tostring(d.message), 1.6)
		elseif d.ok and not d.equip then
			local item = Catalog.get(d.id)
			HUDController.banner(("UNLOCKED %s!"):format(if item then string.upper(item.Name) else "ITEM"), C.Gold, 1.4, "Purchase")
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ShopPrompt" then
			ShopController.openShop(true)
		elseif prompt.Name == "DailyPrompt" then
			ShopController.openDaily(true)
		end
	end)
	-- pulse the daily "today" box
	RunService.RenderStepped:Connect(function()
		local hub = inHub()
		gui.Enabled = hub and not HUDController.cinematic
		if not hub and (shopPanel.Visible or dailyPanel.Visible) then
			ShopController.openShop(false)
			ShopController.openDaily(false)
		end
		if dailyPanel.Visible and profile.daily and not profile.daily.claimed then
			local box = dailyBoxes[profile.daily.day]
			if box then
				local sc = box:FindFirstChildOfClass("UIScale") or new("UIScale", nil, box)
				sc.Scale = 1 + 0.05 * math.sin(os.clock() * 6)
			end
		end
	end)
end

return ShopController
