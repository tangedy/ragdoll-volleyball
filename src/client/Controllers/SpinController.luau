--!strict
-- Daily cosmetic spin sheet (hub only). Shows the exact wheel the server will spin (the server sends
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
local T = Theme.Toybox
local SP = Config.Spin
local new = Theme.new

local SpinController = {}

local SHEET_SIZE = Vector2.new(820, 536)

local sheet: any
local panel: CanvasGroup
local rotor: Frame
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

-- Draw a wheel's slots around the rim of `target` (the rotor, which is what spins). Prizes already
-- in `ownedMap` carry a sticker with the coins they'd pay instead (`dupCoins` by rarity). Shared
-- with the loot chests (ChestController).
function SpinController.drawWheel(
	target: Frame,
	slots: { string },
	ownedMap: { [string]: boolean },
	dupCoins: { [string]: number }
): { Frame }
	for _, f in target:GetChildren() do
		f:Destroy()
	end
	local frames: { Frame } = {}
	local n = #slots
	if n == 0 then
		return frames
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
			BackgroundColor3 = T.line,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, target)
		if not item then
			continue
		end
		local rarity = Catalog.rarity(item)
		local slot = new("Frame", {
			Name = "Slot" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.35 * math.sin(rad), 0.5 - 0.35 * math.cos(rad)),
			Size = UDim2.fromScale(0.19, 0.19),
			Rotation = angle,
			BackgroundColor3 = Theme.Rarity[rarity],
			ZIndex = 6,
		}, target)
		Theme.corner(slot, Theme.Radius.S)
		Theme.stroke(slot, T.outline, 2.5)
		ShopController.drawArt(item, slot)
		if ownedMap[id] then
			-- already owned: it would pay coins instead
			Theme.sticker(slot, "+" .. tostring(dupCoins[rarity] or 0), T.sun, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromOffset(0, 18),
				ZIndex = 9,
			})
		end
		table.insert(frames, slot)
	end
	return frames
end

local function buildWheel(slots: { string })
	slotsShown = slots
	slotFrames = SpinController.drawWheel(rotor, slots, owned, SP.DuplicateCoins)
end

-- Odds of a wheel by rarity (each slot is 1 in N), as rows in `list`.
function SpinController.drawOdds(list: Frame, slots: { string })
	for _, f in list:GetChildren() do
		if f:IsA("Frame") then
			f:Destroy()
		end
	end
	local counts: { [string]: number } = {}
	for _, id in slots do
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
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, list)
		Theme.sticker(row, r, Theme.Rarity[r], {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			ZIndex = 5,
		})
		Theme.text(row, 16, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromScale(0.4, 1),
			Text = ("%d%%"):format(math.floor(n / math.max(#slots, 1) * 100 + 0.5)),
			TextColor3 = if n > 0 then T.ink else T.inkMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 5,
		})
	end
end

local function renderOdds()
	SpinController.drawOdds(oddsList, slotsShown)
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
		Theme.setText(spinButton, "Spin for free")
		Theme.recolor(spinButton, "primary")
		Theme.setEnabled(spinButton, true)
	elseif status.paidLeft > 0 then
		Theme.setText(spinButton, ("Spin for %s coins"):format(ShopController.commas(status.cost)))
		Theme.recolor(spinButton, "primary")
		Theme.setEnabled(spinButton, true)
	else
		Theme.setText(spinButton, "Come back tomorrow")
		Theme.recolor(spinButton, "secondary")
		Theme.setEnabled(spinButton, false)
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
		ShopController.closeAll() -- shop, daily, settings and the loot chest sheet
		Theme.show(panel, ShopController.getBackdrop())
		Theme.focus(spinButton)
	elseif not spinning then
		if ShopController.isOpen(panel) then
			Theme.setHome(nil)
		end
		Theme.hide(panel, ShopController.getBackdrop())
		Theme.hide(reveal)
	end
end

-- Kept for older callers: the sheet is fixed size and scales with the screen.
function SpinController.layout() end

-- Confetti burst inside the reveal card.
local function confetti(parent: GuiObject, color: Color3)
	if HUDController.settings.ReducedMotion then
		return
	end
	local palette = { color, T.sun, T.candy, T.sky, T.leaf }
	local rng = Random.new()
	for _ = 1, 26 do
		local bit = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.35),
			Size = UDim2.fromOffset(rng:NextInteger(7, 11), rng:NextInteger(10, 15)),
			BackgroundColor3 = palette[rng:NextInteger(1, #palette)],
			Rotation = rng:NextNumber(0, 360),
			BorderSizePixel = 0,
			ZIndex = 30,
		}, parent)
		Theme.corner(bit, 3)
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

-- Fill the prize card `reveal` for a spin/chest result and show it; its buttons hand focus back to
-- `back`. Shared with the loot chests (ChestController).
function SpinController.drawReveal(reveal: Frame, result: any, back: GuiObject)
	local item = Catalog.get(result.id)
	if not item then
		return
	end
	for _, f in reveal:GetChildren() do
		if not f:IsA("UICorner") and not f:IsA("UIStroke") and not f:IsA("UIScale") then
			f:Destroy()
		end
	end
	local col = Theme.Rarity[result.rarity] or T.sun
	local stroke = reveal:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = col
	end
	-- slow light rays behind the prize (illustration)
	local rays = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
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
			BackgroundTransparency = 0.8,
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
	Theme.sticker(reveal, result.rarity, col, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.Space.L),
		Size = UDim2.fromOffset(0, 24),
		ZIndex = 24,
	})
	local box = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.36, 0.36),
		BackgroundColor3 = col,
		ZIndex = 22,
	}, reveal)
	new("UIAspectRatioConstraint", nil, box)
	Theme.corner(box, Theme.Radius.L)
	Theme.stroke(box, T.outline, Theme.StrokeToy)
	ShopController.drawArt(item, box)
	Theme.label(reveal, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(0.9, 0, 0, 34),
		Text = item.Name,
		ZIndex = 24,
	}, 0)
	Theme.body(reveal, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(0.9, 0, 0, 18),
		FontFace = Theme.TextFace,
		Text = if result.duplicate
			then ("You already had this, so here's %s coins instead."):format(ShopController.commas(result.coins))
			else ("New %s!"):format(
				(string.lower(Catalog.CategoryNames[item.Category] or item.Category):gsub("s$", ""))
			),
		ZIndex = 24,
	}).Position =
		UDim2.new(0.5, 0, 0.62, 40)
	local buttons = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.new(1, -Theme.Space.L * 2, 0, 56),
		BackgroundTransparency = 1,
		ZIndex = 24,
	}, reveal)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, buttons)
	local focusOn: TextButton
	if not result.duplicate then
		local equip = Theme.button(buttons, "Equip it", "primary", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(150, 56),
			ZIndex = 25,
		})
		equip.Activated:Connect(function()
			Net.request(Net.Actions.EquipItem, { id = item.Id })
			Theme.hide(reveal)
			Theme.focus(back)
		end)
		focusOn = equip
	end
	local ok = Theme.button(buttons, "Nice!", if result.duplicate then "primary" else "secondary", {
		LayoutOrder = 2,
		Size = UDim2.fromOffset(130, 56),
		ZIndex = 25,
	})
	ok.Activated:Connect(function()
		Theme.hide(reveal)
		Theme.focus(back)
	end)
	Theme.show(reveal)
	Theme.focus(focusOn or ok)
	confetti(reveal, col)
	SoundController.play(
		if result.rarity == "Legendary" or result.rarity == "Epic" then "SpinLegendary" else "SpinReveal"
	)
	if result.duplicate and result.coins > 0 then
		task.delay(0.6, function()
			HUDController.coinPop(result.coins)
		end)
	end
end

local function showReveal(result: any)
	SpinController.drawReveal(reveal, result, spinButton)
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

-- The wheel on the left of a sheet's `body`: a sunk disc in the toy outline with a label on the hub
-- and a pointer at the top. Returns the rotor (where the slots go), which is what turns.
function SpinController.wheelFrame(body: Frame, hubText: string, hubColor: Color3): Frame
	local wheelHolder = new("Frame", {
		Name = "Wheel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 4),
		Size = UDim2.fromOffset(380, 380),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, body)
	local ledge = new("Frame", {
		Position = UDim2.fromOffset(0, Theme.Ledge + 2),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.shadowToy,
		ZIndex = 3,
	}, wheelHolder)
	Theme.round(ledge)
	local disc = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.surfaceSunk,
		ZIndex = 4,
	}, wheelHolder)
	Theme.round(disc)
	Theme.stroke(disc, T.outline, 4)
	local wheelRotor = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, disc)
	local hub = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.24, 0.24),
		BackgroundColor3 = hubColor,
		ZIndex = 10,
	}, disc)
	Theme.round(hub)
	Theme.stroke(hub, T.outline, Theme.StrokeToy)
	Theme.label(hub, {
		Size = UDim2.fromScale(0.7, 0.34),
		Position = UDim2.fromScale(0.15, 0.33),
		Text = hubText,
		TextColor3 = T.onFill,
		ZIndex = 11,
	}, 0)
	-- pointer: a sun wedge in the toy outline at the top
	local pointer = new("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.01),
		Size = UDim2.fromOffset(30, 30),
		Rotation = 45,
		BackgroundColor3 = T.sun,
		ZIndex = 12,
	}, wheelHolder)
	Theme.corner(pointer, 5)
	Theme.stroke(pointer, T.outline, Theme.StrokeToy)
	return wheelRotor
end

function SpinController.init()
	sheet = ShopController.sheet(
		"Spin",
		"Daily spin",
		SHEET_SIZE,
		"One free spin a day. Every slot is equally likely.",
		{ tone = T.candy, glyph = "star" }
	)
	panel = sheet.frame
	sheet.close.Activated:Connect(function()
		SpinController.open(false)
	end)
	local body = sheet.body :: Frame
	rotor = SpinController.wheelFrame(body, "Spin", T.sun)

	-- info column: status line, odds, buttons
	local infoCol = new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -420, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, body)
	new("UIListLayout", {
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, infoCol)
	statusLabel = Theme.label(infoCol, {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	}, 0)
	local oddsWell = Theme.well(infoCol, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 4 * 26 + 3 * 6 + 24 + 36),
		ZIndex = 4,
	}, Theme.Radius.M)
	Theme.padding(oddsWell, Theme.Space.L, Theme.Space.M)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, oddsWell)
	Theme.body(oddsWell, {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.LabelFace,
		Text = "Odds on this wheel",
		TextColor3 = T.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	oddsList = new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 4 * 26 + 3 * 6),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, oddsWell)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, oddsList)
	spinButton = Theme.button(infoCol, "Spin for free", "primary", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 60),
		ZIndex = 4,
	})
	spinButton.Activated:Connect(SpinController.spin)
	robuxButton = Theme.button(infoCol, "Extra spin with Robux", "secondary", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 52),
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
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = Theme.TextFace,
		Text = "Prizes you already own pay coins instead.",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})

	-- prize reveal card (over the sheet's content)
	reveal = new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 400),
		BackgroundColor3 = T.surfaceSunk,
		Visible = false,
		ZIndex = 20,
		Active = true,
		ClipsDescendants = true,
	}, body)
	Theme.corner(reveal, Theme.Radius.L)
	Theme.stroke(reveal, T.sun, 4)

	local btn
	btn, badge = ShopController.addAction("Spin", T.candy, "star", 2, function()
		SpinController.open(not ShopController.isOpen(panel))
	end)
	local _ = btn
	ShopController.onCloseAll(function()
		SpinController.open(false)
	end)
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
		-- a Robux spin can arrive while the sheet is closed: open it to show the spin
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
			statusLabel.Text = "Spinning..."
		elseif status.free then
			statusLabel.Text = "Free spin ready!"
		else
			local left = 86400 - (os.time() % 86400)
			statusLabel.Text = ("Next free spin in %s"):format(fmtCountdown(left))
		end
		if spinButton then
			spinButton.Active = not spinning
		end
	end)
end

return SpinController
