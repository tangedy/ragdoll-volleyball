--!strict
-- Daily cosmetic spin panel (hub only). Shows the exact wheel the server will spin (the server sends
-- the slots with the profile), the odds of this wheel by rarity, and the free / paid spin buttons.
-- A spin request starts the wheel at once; when the server's result arrives the wheel eases out onto
-- the winning slot, ticking past each slot, then the prize is revealed. The server decides and saves
-- everything; this only presents it.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local HubController = require(script.Parent.HubController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local C = Theme.Colors
local SP = Config.Spin
local new = Theme.new

local SpinController = {}

local panel: Frame
local wheelHolder: Frame
local rotor: Frame
local infoCol: Frame
local statusLabel: TextLabel
local oddsList: Frame
local spinButton: TextButton
local robuxButton: TextButton
local badge: Frame
local reveal: Frame
local slotsShown: { string } = {}
local slotFrames: { Frame } = {}
local status: any = nil -- profile.spin from the server
local owned: { [string]: boolean } = {}
local spinning = false
local rotation = 0
local spinConn: RBXScriptConnection? = nil
local lastTick = -1

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

-- Small icon for a prize: a ball swatch, a trail stripe, a title word or the item's emoji.
local function icon(item: Catalog.Item, parent: Instance, z: number)
	local d = item.Data
	if item.Category == "BallSkin" then
		local ball = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.55, 0.55),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = z,
		}, parent)
		new("UIAspectRatioConstraint", nil, ball)
		Theme.round(ball)
		local col = d.Color or Color3.fromRGB(214, 48, 49)
		Theme.gradient(ball, Theme.lighten(col, 0.45), Theme.darken(col, 0.15), 45)
		Theme.stroke(ball, C.Ink, 2)
	elseif item.Category == "Trail" and d.Colors then
		local keys = {}
		for i, col in d.Colors do
			table.insert(keys, ColorSequenceKeypoint.new(if #d.Colors == 1 then 0 else (i - 1) / (#d.Colors - 1), col))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, d.Colors[1]))
		end
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.8, 0.18),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Rotation = -15,
			ZIndex = z,
		}, parent)
		Theme.round(bar)
		new("UIGradient", { Color = ColorSequence.new(keys) }, bar)
	else
		local text = if item.Category == "Title" then d.Text else (d.Icon or "🎬")
		Theme.label(parent, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.85, if item.Category == "Title" then 0.3 else 0.5),
			Text = text,
			TextColor3 = if item.Category == "Title" then C.Gold else Color3.new(1, 1, 1),
			ZIndex = z,
		}, 1.5)
	end
end

-- Build the wheel's slots around the rim (they ride on `rotor`, which is what spins).
local function buildWheel(slots: { string })
	for _, f in rotor:GetChildren() do
		f:Destroy()
	end
	table.clear(slotFrames)
	slotsShown = slots
	local n = #slots
	if n == 0 then
		return
	end
	for i, id in slots do
		local item = Catalog.get(id)
		local angle = (i - 1) * 360 / n
		local rad = math.rad(angle)
		-- spoke between this slot and the next
		local spokeAngle = math.rad(angle + 180 / n)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.24 * math.sin(spokeAngle), 0.5 - 0.24 * math.cos(spokeAngle)),
			Size = UDim2.new(0, 3, 0.48, 0),
			Rotation = angle + 180 / n,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, rotor)
		if not item then
			continue
		end
		local rarity = Catalog.rarity(item)
		local col = Theme.Rarity[rarity]
		local slot = new("Frame", {
			Name = "Slot" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.34 * math.sin(rad), 0.5 - 0.34 * math.cos(rad)),
			Size = UDim2.fromScale(0.2, 0.2),
			Rotation = angle,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
		}, rotor)
		Theme.corner(slot, Theme.Radius.S)
		Theme.gradient(slot, Theme.lighten(col, 0.15), Theme.darken(col, 0.45))
		Theme.stroke(slot, C.Ink, 2)
		icon(item, slot, 6)
		if owned[id] then
			-- already owned: it would pay coins instead
			local tag = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1.05),
				Size = UDim2.fromScale(0.9, 0.3),
				BackgroundColor3 = C.Ink,
				ZIndex = 7,
			}, slot)
			Theme.round(tag)
			Theme.label(tag, {
				Size = UDim2.fromScale(1, 1),
				Text = ("+%d"):format(SP.DuplicateCoins[rarity] or 0),
				TextColor3 = C.Gold,
				ZIndex = 8,
			}, 1)
		end
		table.insert(slotFrames, slot)
	end
end

-- Odds of THIS wheel by rarity (each slot is 1 in N).
local function renderOdds()
	for _, f in oddsList:GetChildren() do
		if f:IsA("Frame") then
			f:Destroy()
		end
	end
	local counts: { [string]: number } = {}
	for _, id in slotsShown do
		local item = Catalog.get(id)
		if item then
			local r = Catalog.rarity(item)
			counts[r] = (counts[r] or 0) + 1
		end
	end
	for i, r in { "Legendary", "Epic", "Rare", "Common" } do
		local n = counts[r] or 0
		local row = new("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
		}, oddsList)
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Theme.Rarity[r],
		}, row)
		Theme.round(dot)
		Theme.stroke(dot, C.Ink, 1.5)
		Theme.body(row, {
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -22, 1, 0),
			Text = ("%s  %d%%"):format(string.upper(r), math.floor(n / math.max(#slotsShown, 1) * 100 + 0.5)),
			TextColor3 = if n > 0 then Theme.lighten(Theme.Rarity[r], 0.3) else C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
end

local function fmtCountdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%02d:%02d:%02d"):format(seconds // 3600, (seconds // 60) % 60, seconds % 60)
end

local function renderButtons()
	if not status then
		return
	end
	if status.free then
		Theme.setText(spinButton, "SPIN FREE!")
		Theme.recolor(spinButton, C.Gold)
	elseif status.paidLeft > 0 then
		Theme.setText(spinButton, ("SPIN · %d COINS"):format(status.cost))
		Theme.recolor(spinButton, C.Purple)
	else
		Theme.setText(spinButton, "COME BACK TOMORROW")
		Theme.recolor(spinButton, Color3.fromRGB(90, 85, 120))
	end
	robuxButton.Visible = (status.robux or 0) > 0 and not status.free
	badge.Visible = status.free == true
end

function SpinController.open(on: boolean)
	if on and not inHub() then
		return
	end
	if on then
		if not ShopController.isOpen(panel) then
			SoundController.play("UIOpen")
		end
		ShopController.openShop(false)
		ShopController.openDaily(false)
		Theme.show(panel, ShopController.getBackdrop())
		SpinController.layout()
	elseif not spinning then
		Theme.hide(panel, ShopController.getBackdrop())
		Theme.hide(reveal)
	end
end

-- Phones: the wheel goes on top and the info column below it.
function SpinController.layout()
	local compact = Theme.isCompact()
	panel.Size = if compact then UDim2.fromScale(0.94, 0.9) else UDim2.fromScale(0.74, 0.74)
	if compact then
		wheelHolder.AnchorPoint = Vector2.new(0.5, 0)
		wheelHolder.Position = UDim2.new(0.5, 0, 0, 40)
		wheelHolder.Size = UDim2.new(1, -Theme.Space.L * 2, 0.55, -40)
		infoCol.AnchorPoint = Vector2.new(0.5, 1)
		infoCol.Position = UDim2.new(0.5, 0, 1, -Theme.Space.M)
		infoCol.Size = UDim2.new(1, -Theme.Space.L * 2, 0.45, -Theme.Space.L)
		oddsList.Visible = false
	else
		wheelHolder.AnchorPoint = Vector2.new(0, 0.5)
		wheelHolder.Position = UDim2.new(0, Theme.Space.L, 0.5, 14)
		wheelHolder.Size = UDim2.new(0.55, -Theme.Space.L, 1, -70)
		infoCol.AnchorPoint = Vector2.new(1, 0.5)
		infoCol.Position = UDim2.new(1, -Theme.Space.L, 0.5, 14)
		infoCol.Size = UDim2.new(0.45, -Theme.Space.L, 1, -70)
		oddsList.Visible = true
	end
end

-- Confetti burst inside the reveal card.
local function confetti(parent: GuiObject, color: Color3)
	if HUDController.settings.ReducedMotion then
		return
	end
	local palette = { color, C.Gold, Color3.new(1, 1, 1), Theme.lighten(color, 0.4) }
	local rng = Random.new()
	for _ = 1, 26 do
		local bit = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.35),
			Size = UDim2.fromOffset(rng:NextInteger(6, 11), rng:NextInteger(10, 16)),
			BackgroundColor3 = palette[rng:NextInteger(1, #palette)],
			Rotation = rng:NextNumber(0, 360),
			BorderSizePixel = 0,
			ZIndex = 30,
		}, parent)
		local tx, ty = rng:NextNumber(-0.1, 1.1), rng:NextNumber(0.6, 1.2)
		Theme.tween(bit, rng:NextNumber(0.9, 1.4), {
			Position = UDim2.fromScale(tx, ty),
			Rotation = bit.Rotation + rng:NextNumber(-400, 400),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(1.5, function()
			bit:Destroy()
		end)
	end
end

local function showReveal(result: any)
	local item = Catalog.get(result.id)
	if not item then
		return
	end
	for _, f in reveal:GetChildren() do
		if not f:IsA("UICorner") and not f:IsA("UIGradient") and not f:IsA("UIStroke") and not f:IsA("UIScale") then
			f:Destroy()
		end
	end
	local col = Theme.Rarity[result.rarity] or C.Gold
	local grad = reveal:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(Theme.darken(col, 0.35), C.Panel)
	end
	local stroke = reveal:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = col
	end
	-- spinning light rays behind the prize
	local rays = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		ZIndex = 21,
	}, reveal)
	new("UIAspectRatioConstraint", nil, rays)
	for i = 0, 5 do
		local ray = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.14, 1),
			Rotation = i * 30,
			BackgroundColor3 = col,
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			ZIndex = 21,
		}, rays)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
	end
	if not HUDController.settings.ReducedMotion then
		Theme.tween(rays, 6, { Rotation = 180 }, Enum.EasingStyle.Linear)
	end
	Theme.label(reveal, {
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.M),
		Size = UDim2.new(1, -Theme.Space.L * 2, 0.12, 0),
		Text = string.upper(result.rarity) .. "!",
		TextColor3 = Theme.lighten(col, 0.25),
		ZIndex = 24,
	}, 3)
	local box = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 22,
	}, reveal)
	new("UIAspectRatioConstraint", nil, box)
	Theme.corner(box, Theme.Radius.L)
	Theme.gradient(box, Theme.lighten(col, 0.15), Theme.darken(col, 0.45))
	Theme.stroke(box, C.Ink, 3)
	icon(item, box, 23)
	Theme.label(reveal, {
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.1),
		Text = item.Name,
		ZIndex = 24,
	}, 2.5)
	Theme.body(reveal, {
		Position = UDim2.fromScale(0.05, 0.7),
		Size = UDim2.fromScale(0.9, 0.06),
		Text = if result.duplicate
			then ("ALREADY OWNED · +%d COINS"):format(result.coins)
			else ("NEW %s!"):format(string.upper(Catalog.CategoryNames[item.Category] or item.Category)),
		TextColor3 = if result.duplicate then C.Gold else C.Green,
		ZIndex = 24,
	})
	local buttons = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.new(1, -Theme.Space.L * 2, 0, 52),
		BackgroundTransparency = 1,
		ZIndex = 24,
	}, reveal)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.M),
	}, buttons)
	if not result.duplicate then
		local equip = Theme.button(buttons, "EQUIP", C.Green, { Size = UDim2.fromOffset(150, 52), ZIndex = 25 })
		equip.Activated:Connect(function()
			Net.request(Net.Actions.EquipItem, { id = item.Id })
			Theme.hide(reveal)
		end)
	end
	local ok = Theme.button(buttons, "AWESOME!", C.Gold, { Size = UDim2.fromOffset(150, 52), ZIndex = 25 })
	ok.Activated:Connect(function()
		Theme.hide(reveal)
	end)
	Theme.show(reveal)
	confetti(reveal, col)
	SoundController.play(if result.rarity == "Legendary" or result.rarity == "Epic" then "SpinLegendary" else "SpinReveal")
	if result.duplicate and result.coins > 0 then
		task.delay(0.6, function()
			HUDController.coinPop(result.coins)
		end)
	end
end

local function stopSpin()
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
end

local function setRotation(r: number)
	rotation = r
	rotor.Rotation = r % 360
	-- tick each time a slot boundary passes the pointer
	local n = math.max(#slotsShown, 1)
	local slot = math.floor((r + 180 / n) / (360 / n))
	if slot ~= lastTick then
		lastTick = slot
		SoundController.play("WheelTick")
	end
end

-- Start the wheel turning immediately (before the server answers), ramping up to speed.
local function spinUp()
	stopSpin()
	local started = os.clock()
	spinConn = RunService.RenderStepped:Connect(function(dt)
		local speed = 620 * math.clamp((os.clock() - started) / 0.35, 0.15, 1)
		setRotation(rotation + speed * dt)
	end)
end

-- Ease out from the current angle onto slot `index` under the pointer (top), at least 3 turns on.
local function landOn(index: number, onDone: () -> ())
	stopSpin()
	local n = #slotsShown
	local theta = (index - 1) * 360 / n -- the slot's angle on the rotor (clockwise from the top)
	local from = rotation
	local turns = math.ceil((from + 3 * 360 + theta) / 360)
	local target = turns * 360 - theta
	-- a little randomness inside the slot so it doesn't always stop dead centre
	target += Random.new():NextNumber(-0.3, 0.3) * 360 / n
	local duration = if HUDController.settings.ReducedMotion then 1.2 else SP.SpinDuration
	local t0 = os.clock()
	spinConn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		setRotation(from + (target - from) * (1 - (1 - a) ^ 4))
		if a >= 1 then
			stopSpin()
			onDone()
		end
	end)
end

function SpinController.spin()
	if spinning or not status or not inHub() then
		return
	end
	local paid = not status.free
	if paid and status.paidLeft <= 0 then
		SoundController.play("UIError")
		HUDController.hint("No more spins today", 1.5)
		return
	end
	spinning = true
	Theme.hide(reveal)
	SoundController.play("SpinStart")
	HubController.boostWheel(SP.SpinDuration + 1)
	spinUp()
	Net.request(Net.Actions.Spin, { paid = paid })
	-- if the server never answers, don't leave the wheel spinning forever
	task.delay(6, function()
		if spinning and spinConn and not panel:GetAttribute("Landing") then
			stopSpin()
			spinning = false
			HUDController.hint("Spin timed out, try again", 1.5)
		end
	end)
end

function SpinController.init()
	local gui = ShopController.gui :: ScreenGui
	local close
	panel, close = ShopController.panel("Spin", "DAILY SPIN", Vector2.new(780, 500))
	close.Activated:Connect(function()
		SpinController.open(false)
	end)
	panel.Parent = gui
	-- wheel: a dark disc with a gold rim; the rotor (slots + spokes) is what turns
	wheelHolder = new("Frame", { BackgroundTransparency = 1, ZIndex = 3 }, panel)
	new("UIAspectRatioConstraint", nil, wheelHolder)
	local disc = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	}, wheelHolder)
	Theme.round(disc)
	Theme.gradient(disc, C.PanelLight, C.Ink)
	Theme.stroke(disc, C.Gold, 5)
	rotor = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 }, disc)
	local hub = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.22, 0.22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
	}, disc)
	Theme.round(hub)
	Theme.gradient(hub, Theme.lighten(C.Gold, 0.3), C.GoldDark)
	Theme.stroke(hub, C.Ink, 3)
	Theme.label(hub, { Size = UDim2.fromScale(0.8, 0.4), Position = UDim2.fromScale(0.1, 0.3), Text = "SPIN", ZIndex = 10 }, 2)
	local pointer = Theme.label(wheelHolder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.14, 0.12),
		Text = "▼",
		TextColor3 = C.Gold,
		ZIndex = 12,
	}, 3)
	pointer.Name = "Pointer"

	-- info column: status line, odds, buttons
	infoCol = new("Frame", { BackgroundTransparency = 1, ZIndex = 3 }, panel)
	new("UIListLayout", {
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, infoCol)
	statusLabel = Theme.label(infoCol, {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		TextColor3 = C.Gold,
		ZIndex = 4,
	}, 2.5)
	Theme.body(infoCol, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 16),
		Text = ("ODDS ON THIS WHEEL · %d SLOTS, 1 IN %d EACH"):format(SP.Slots, SP.Slots),
		TextColor3 = C.Muted,
		ZIndex = 4,
	})
	oddsList = new("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 4 * 22 + 3 * 4),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, infoCol)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, oddsList)
	spinButton = Theme.button(infoCol, "SPIN FREE!", C.Gold, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 60), ZIndex = 4 })
	spinButton.Activated:Connect(SpinController.spin)
	robuxButton = Theme.button(infoCol, "EXTRA SPIN · ROBUX", Color3.fromRGB(40, 190, 120), {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 44),
		Visible = false,
		ZIndex = 4,
	})
	robuxButton.Activated:Connect(function()
		if SP.RobuxProductId > 0 then
			MarketplaceService:PromptProductPurchase(player, SP.RobuxProductId)
		end
	end)
	Theme.body(infoCol, {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 14),
		Text = "OWNED PRIZES PAY COINS INSTEAD",
		TextColor3 = C.Muted,
		ZIndex = 4,
	})

	-- prize reveal card (over the panel)
	reveal = new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.86),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 20,
		ClipsDescendants = true,
	}, panel)
	Theme.corner(reveal, Theme.Radius.XL)
	Theme.gradient(reveal, C.PanelLight, C.Panel)
	Theme.stroke(reveal, C.Gold, 4)
	new("UISizeConstraint", { MinSize = Vector2.new(280, 300) }, reveal)

	local btn = ShopController.addHubButton("🎡 SPIN", Color3.fromRGB(255, 80, 190), 2, function()
		SpinController.open(not ShopController.isOpen(panel))
	end)
	badge = Theme.badge(btn)
	ShopController.onCloseAll(function()
		SpinController.open(false)
	end)
	SpinController.layout()
end

function SpinController.start()
	Net.on("Profile", function(d)
		status = d.spin
		owned = d.owned or {}
		if status and not spinning then
			buildWheel(status.slots or {})
			renderOdds()
		end
		renderButtons()
	end)
	Net.on("SpinResult", function(d)
		if d.ok == false then
			stopSpin()
			spinning = false
			SoundController.play("UIError")
			HUDController.hint(tostring(d.message or "Can't spin right now"), 1.6)
			return
		end
		-- a Robux spin can arrive while the panel is closed: open it to show the spin
		if not ShopController.isOpen(panel) and inHub() then
			SpinController.open(true)
			spinUp()
			spinning = true
		end
		-- the wheel shown should already be this one; rebuild if anything changed
		local same = #d.slots == #slotsShown
		for i, id in d.slots do
			same = same and slotsShown[i] == id
		end
		if not same then
			buildWheel(d.slots)
			renderOdds()
		end
		panel:SetAttribute("Landing", true)
		landOn(d.index, function()
			panel:SetAttribute("Landing", false)
			spinning = false
			local slot = slotFrames[d.index]
			if slot then
				Theme.pop(slot, 1.5, 0.4)
			end
			task.delay(0.35, function()
				showReveal(d)
				-- the next wheel (from the profile push) appears once the reveal is up
				if status then
					buildWheel(status.slots or {})
					renderOdds()
				end
			end)
		end)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "SpinPrompt" then
			SpinController.open(true)
		end
	end)
	local nextStatusAt = 0
	RunService.RenderStepped:Connect(function()
		if not inHub() and panel.Visible and not spinning then
			SpinController.open(false)
		end
		if os.clock() < nextStatusAt or not status then
			return
		end
		nextStatusAt = os.clock() + 0.5
		if spinning then
			statusLabel.Text = "SPINNING..."
		elseif status.free then
			statusLabel.Text = "FREE SPIN READY!"
		else
			local left = 86400 - (os.time() % 86400)
			statusLabel.Text = ("FREE SPIN IN %s"):format(fmtCountdown(left))
		end
		if spinButton then
			spinButton.Active = not spinning
		end
	end)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(SpinController.layout)
end

return SpinController
