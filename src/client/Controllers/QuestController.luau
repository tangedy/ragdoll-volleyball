--!strict
-- Daily quests in the hub (presentation only; QuestService decides and saves everything).
--
--  * Panel (left edge of the hub): each quest with its progress bar, its chest and the chance of
--    each rarity from it, a Claim button, and the countdown to the UTC reset. The header folds it.
--  * Tap a quest's chest (or its odds): the chest sheet shows every item it can drop on the wheel,
--    the chance of each rarity and the coins a rarity pays once you own all of it.
--  * Claim: the chest sheet opens on that quest and the wheel spins (the chest rattling) while the
--    server rolls the prize; then the chest bursts, the wheel lands on the prize and the shared prize
--    card (SpinController.drawReveal) reveals it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallDefinitions = require(Shared.BallDefinitions)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
local SpinController = require(script.Parent.SpinController)
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local WheelSheet = require(UI:WaitForChild("WheelSheet"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local Q = Config.Quests
local SPACE = Theme.Space
local SIZE = Theme.TextSize
local new = Theme.new

local QuestController = {}

local RARITIES = { "Common", "Rare", "Epic", "Legendary" }
local CHEST_TONE: { [string]: Color3 } = { Title = T.sky, Gesture = T.candy, Finisher = T.sun }
local PANEL_W = 340
local ROW_H = 92
local TEXT_X = 52 -- right of a row's chest disc
local CLAIM_W = 84
local TIMEOUT = 7 -- seconds without an answer before a claim gives up

type Row = {
	frame: Frame,
	name: TextLabel,
	count: TextLabel,
	fill: Frame,
	odds: Frame,
	claim: TextButton,
}

local status: any = nil -- profile.quests from the server
local owned: { [string]: boolean } = {}

-- panel
local panel: Frame
local list: Frame
local resetLabel: TextLabel
local featuredLabel: TextLabel
local readySticker: Frame
local foldGlyph: GuiObject
local rows: { [string]: Row } = {}
local folded = false

-- chest sheet
local sheetRef: any
local sheet: CanvasGroup
local rotor: Frame
local info: WheelSheet.Info
local primary: TextButton
local reveal: Frame
local currentQuest: string? = nil
local slotsShown: { string } = {}
local slotFrames: { Frame } = {}

-- the claim in progress
local claiming = false
local claimToken = 0
local rotation = 0
local spinConn: RBXScriptConnection? = nil
local lastTick = -1

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function questOf(id: string?): any?
	for _, q in (if status then status.quests else nil) or {} do
		if q.id == id then
			return q
		end
	end
	return nil
end

-- "Resets in 05:12:33", from the server's reset time (the next UTC midnight).
local function untilReset(): string
	if not status or not status.resetsAt then
		return WheelSheet.untilReset()
	end
	local left = math.max(0, (tonumber(status.resetsAt) or 0) - os.time())
	return ("%02d:%02d:%02d"):format(left // 3600, (left // 60) % 60, left % 60)
end

-- Every item the quest's chest can drop, Common first, repeated round the wheel's slots.
local function dropsWheel(q: any): { string }
	local ids: { string } = {}
	for _, r in RARITIES do
		for _, id in (q.drops and q.drops[r]) or {} do
			table.insert(ids, id)
		end
	end
	local slots: { string } = {}
	if #ids == 0 then
		return slots
	end
	for i = 1, Q.RevealSlots do
		slots[i] = ids[(i - 1) % #ids + 1]
	end
	return slots
end

-- Panel -----------------------------------------------------------------------------------------------

-- One tiny sticker per rarity the chest can drop: its first letter and chance ("C 55%").
local function drawOddsStrip(strip: Frame, q: any)
	for _, f in strip:GetChildren() do
		if f:IsA("Frame") and f.Name == "Sticker" then
			f:Destroy()
		end
	end
	for i, r in RARITIES do
		local share = q.odds and tonumber(q.odds[r]) or 0
		if share > 0 then
			Theme.sticker(strip, ("%s %s"):format(string.sub(r, 1, 1), WheelSheet.percent(share)), Theme.Rarity[r], {
				LayoutOrder = i + 1,
				Size = UDim2.fromOffset(0, 18),
				ZIndex = 6,
			})
		end
	end
end

local function renderPanel()
	if not status then
		return
	end
	local ready = 0
	for _, q in status.quests do
		local row = rows[q.id]
		if not row then
			continue
		end
		local goal = math.max(1, tonumber(q.goal) or 1)
		local progress = math.min(goal, tonumber(q.progress) or 0)
		row.name.Text = q.name
		row.count.Text = if q.claimed then "Done" else ("%d/%d"):format(progress, goal)
		row.fill.Size = UDim2.fromScale(progress / goal, 1)
		row.fill.BackgroundColor3 = if progress >= goal then T.leaf else T.sky
		drawOddsStrip(row.odds, q)
		local busy = claiming and currentQuest == q.id
		if q.claimed then
			Theme.setText(row.claim, "Claimed")
			Theme.recolor(row.claim, "secondary")
			Theme.setEnabled(row.claim, false)
		elseif q.ready then
			ready += 1
			Theme.setText(row.claim, if busy then "..." else "Claim")
			Theme.recolor(row.claim, "primary")
			Theme.setEnabled(row.claim, not claiming)
		else
			Theme.setText(row.claim, "Claim")
			Theme.recolor(row.claim, "secondary")
			Theme.setEnabled(row.claim, false)
		end
	end
	local featured = status.featured
	featuredLabel.Visible = featured ~= nil
	if featured then
		local def = BallDefinitions.get(featured)
		featuredLabel.Text = ('⭐ Featured ball: <b><font color="#%s">%s</font></b>, mastery knockouts x%d'):format(
			def.Color:ToHex(),
			def.DisplayName,
			Config.PowerUps.Featured.MasteryBonus
		)
	end
	readySticker.Visible = ready > 0
	local label = readySticker:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = string.upper(("%d ready"):format(ready))
	end
end

local function setFolded(on: boolean)
	folded = on
	list.Visible = not on
	foldGlyph.Rotation = if on then 0 else 90
end

local function buildRow(q: any, order: number): Row
	local frame = Theme.well(list, {
		Name = q.Id,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_H),
		ZIndex = 3,
	}, Theme.Radius.M)
	Theme.padding(frame, SPACE.S)
	-- the chest: tap it for the drops and odds
	local disc = new("TextButton", {
		Name = "Chest",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = CHEST_TONE[q.Chest] or T.sun,
		ZIndex = 4,
	}, frame)
	Theme.round(disc)
	Theme.stroke(disc, T.outline, Theme.StrokeToy)
	Theme.glyph(disc, "gift", T.onFill, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56),
		ZIndex = 5,
	})
	local textW = -(TEXT_X + CLAIM_W + SPACE.S)
	local name = Theme.text(frame, SIZE.Label, {
		Name = "Name",
		Position = UDim2.fromOffset(TEXT_X, 0),
		Size = UDim2.new(1, textW - 40, 0, 18),
		Text = q.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	local count = Theme.text(frame, SIZE.Label, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(CLAIM_W + SPACE.S), 0, 0),
		Size = UDim2.fromOffset(40, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	Theme.text(frame, SIZE.Micro, {
		Name = "ChestName",
		Position = UDim2.fromOffset(TEXT_X, 19),
		Size = UDim2.new(1, textW, 0, 14),
		FontFace = Theme.TextFace,
		Text = (Q.Chests :: any)[q.Chest].Name,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local track = new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(TEXT_X, 38),
		Size = UDim2.new(1, textW, 0, 8),
		BackgroundColor3 = T.line,
		ZIndex = 4,
	}, frame)
	Theme.round(track)
	local fill =
		new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.sky, ZIndex = 5 }, track)
	Theme.round(fill)
	-- the chest's odds by rarity: also opens the chest sheet
	local strip = new("TextButton", {
		Name = "Odds",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -(CLAIM_W + SPACE.S), 0, 20),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, frame)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, SPACE.XS),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, strip)
	Theme.text(strip, SIZE.Micro, {
		Name = "Caption",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		FontFace = Theme.TextFace,
		Text = "Drops",
		TextColor3 = T.inkMuted,
		ZIndex = 5,
	})
	local claim = Theme.button(frame, "Claim", "secondary", {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(CLAIM_W, 44),
		ZIndex = 4,
	})
	Theme.setEnabled(claim, false)
	local function details()
		QuestController.open(q.Id, true)
	end
	disc.Activated:Connect(details)
	strip.Activated:Connect(details)
	claim.Activated:Connect(function()
		QuestController.claim(q.Id)
	end)
	return { frame = frame, name = name, count = count, fill = fill, odds = strip, claim = claim }
end

local function buildPanel()
	panel = Theme.panel(ShopController.gui, {
		Name = "Quests",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.L, 0.45, 0),
		Size = UDim2.fromOffset(PANEL_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 2,
	}, Theme.Radius.L)
	Theme.padding(panel, SPACE.M)
	Theme.autoScale(panel, 0.85)
	new("UIListLayout", { Padding = UDim.new(0, SPACE.S), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	-- header: title, ready count and the reset countdown; tapping it folds the list away
	local header = new("TextButton", {
		Name = "Header",
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, panel)
	foldGlyph = Theme.glyph(header, "next", T.inkMuted, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 90,
		ZIndex = 4,
	})
	Theme.text(header, SIZE.Heading, {
		Name = "Title",
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.fromOffset(150, 24),
		FontFace = Theme.DisplayFace,
		Text = "Daily quests",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	readySticker = Theme.sticker(header, "0 ready", T.sun, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Visible = false,
		ZIndex = 4,
	})
	resetLabel = Theme.text(header, SIZE.Caption, {
		Name = "Reset",
		Position = UDim2.fromOffset(24, 24),
		Size = UDim2.new(1, -24, 0, 16),
		FontFace = Theme.TextFace,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	header.Activated:Connect(function()
		SoundController.play(if folded then "UIOpen" else "UIBack")
		setFolded(not folded)
	end)
	list = new("Frame", {
		Name = "List",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, SPACE.S), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, q in Q.List do
		rows[q.Id] = buildRow(q, i)
	end
	-- today's featured power ball (Config.PowerUps.Featured), under the quests
	featuredLabel = Theme.text(list, SIZE.Caption, {
		Name = "Featured",
		LayoutOrder = #Q.List + 1,
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = Theme.TextFace,
		RichText = true,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 4,
	})
	-- on touch screens the left side is the thumbstick's, so the panel starts folded there
	setFolded(UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
end

-- Chest sheet -----------------------------------------------------------------------------------------

local function buildWheel(slots: { string })
	slotsShown = slots
	slotFrames = SpinController.drawWheel(rotor, slots, owned, Config.Economy.DuplicateCoins)
end

local function renderSheet()
	local q = questOf(currentQuest)
	if not q then
		return
	end
	local goal = math.max(1, tonumber(q.goal) or 1)
	local progress = math.min(goal, tonumber(q.progress) or 0)
	sheetRef.title.Text = q.chestName
	sheetRef.subtitle.Text = ("%s. You get one item from this chest, rolled when you claim."):format(q.name)
	if claiming then
		WheelSheet.setStatus(info, { fill = T.sun, glyph = "star", title = "Opening...", detail = "Good luck!" })
	elseif q.claimed then
		WheelSheet.setStatus(info, {
			fill = T.leaf,
			glyph = "check",
			title = "Claimed today",
			detail = ("New quests in %s"):format(untilReset()),
		})
	elseif q.ready then
		WheelSheet.setStatus(info, {
			fill = T.sun,
			glyph = "star",
			title = "Quest complete",
			detail = "Your chest is ready to open.",
		})
	else
		WheelSheet.setStatus(info, {
			fill = T.surface,
			count = goal - progress,
			title = q.name,
			detail = ("%d of %d done today"):format(progress, goal),
			progress = progress / goal,
		})
	end
	WheelSheet.setOdds(info.odds, q.odds or {}, 1, Config.Economy.DuplicateCoins, {
		precise = true,
		countText = function(r: string): string
			local n = #((q.drops and q.drops[r]) or {})
			return ("%d item%s"):format(n, if n == 1 then "" else "s")
		end,
	})
	info.price.Text = "Free"
	info.priceNote.Text = "Once a day per quest"
	if claiming then
		Theme.setText(primary, "Opening...")
		Theme.setEnabled(primary, false)
	elseif q.ready then
		Theme.setText(primary, "Open chest")
		Theme.recolor(primary, "primary")
		Theme.setEnabled(primary, true)
	else
		Theme.setText(primary, if q.claimed then "Claimed today" else ("%d of %d done"):format(progress, goal))
		Theme.recolor(primary, "secondary")
		Theme.setEnabled(primary, false)
	end
	info.caption.Text = ("Quests reset in %s"):format(untilReset())
end

-- Show the chest sheet for quest `id`, or close it (never mid-claim).
function QuestController.open(id: string?, on: boolean)
	if on and (not inHub() or not questOf(id)) then
		return
	end
	if on then
		if not ShopController.isOpen(sheet) then
			SoundController.play("UIOpen")
		end
		if id ~= currentQuest then
			Theme.hide(reveal)
		end
		ShopController.closeAll()
		currentQuest = id
		buildWheel(dropsWheel(questOf(id)))
		renderSheet()
		Theme.show(sheet, ShopController.getBackdrop())
		Theme.focus(primary)
	elseif not claiming then
		if ShopController.isOpen(sheet) then
			Theme.setHome(nil)
		end
		Theme.hide(sheet, ShopController.getBackdrop())
		Theme.hide(reveal)
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
	local n = math.max(#slotsShown, 1)
	local slot = math.floor((r + 180 / n) / (360 / n))
	if slot ~= lastTick then
		lastTick = slot
		SoundController.play("WheelTick")
	end
end

-- Turn the wheel (and rattle the chest) until the server answers.
local function spinUp()
	stopSpin()
	local started = os.clock()
	local nextRattle = 0
	spinConn = RunService.RenderStepped:Connect(function(dt)
		local speed = 620 * math.clamp((os.clock() - started) / 0.35, 0.15, 1)
		setRotation(rotation + speed * dt)
		if os.clock() >= nextRattle then
			nextRattle = os.clock() + 0.2
			SoundController.play("ChestRattle", nil, 0.8)
		end
	end)
end

-- Ease out from the current angle onto slot `index` under the pointer, at least 3 turns on.
local function landOn(index: number, onDone: () -> ())
	stopSpin()
	local n = #slotsShown
	local theta = (index - 1) * 360 / n
	local from = rotation
	local target = math.ceil((from + 3 * 360 + theta) / 360) * 360 - theta
	target += Random.new():NextNumber(-0.3, 0.3) * 360 / n
	local duration = if HUDController.settings.ReducedMotion then 1.2 else Q.SpinDuration
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

local function finishClaim()
	claiming = false
	renderPanel()
	renderSheet()
end

local function abortClaim(message: string?)
	claimToken += 1
	stopSpin()
	finishClaim()
	if message then
		SoundController.play("UIError")
		HUDController.hint(message, 1.6)
	end
end

-- Claim quest `id`'s chest: opens its sheet and spins while the server rolls the prize.
function QuestController.claim(id: string)
	local q = questOf(id)
	if claiming or not q or not inHub() then
		return
	end
	if not q.ready then
		SoundController.play("UIError")
		HUDController.hint(if q.claimed then "Already claimed today" else q.name .. " first", 1.5)
		return
	end
	QuestController.open(id, true)
	claiming = true
	claimToken += 1
	local token = claimToken
	Theme.hide(reveal)
	renderPanel()
	renderSheet()
	SoundController.play("SpinStart")
	spinUp()
	Net.request(Net.Actions.ClaimQuest, { id = id })
	task.delay(TIMEOUT, function()
		if claiming and token == claimToken and spinConn and not sheet:GetAttribute("Landing") then
			abortClaim("Couldn't open the chest, try again")
		end
	end)
end

local function onResult(d: any)
	if not claiming or d.quest ~= currentQuest then
		return
	end
	if d.ok == false then
		abortClaim(tostring(d.message or "Can't open the chest right now"))
		return
	end
	local token = claimToken
	SoundController.play("ChestBurst")
	-- the wheel shown is the chest's drops; the server's has the prize at d.index
	local same = #d.slots == #slotsShown
	for i, id in d.slots do
		same = same and slotsShown[i] == id
	end
	if not same then
		buildWheel(d.slots)
	end
	sheet:SetAttribute("Landing", true)
	landOn(d.index, function()
		sheet:SetAttribute("Landing", false)
		if token ~= claimToken then
			return
		end
		local slot = slotFrames[d.index]
		if slot then
			Theme.pop(slot, 1.5, 0.4)
		end
		task.delay(0.35, function()
			if token ~= claimToken then
				return
			end
			finishClaim()
			SpinController.drawReveal(reveal, d, primary)
		end)
	end)
end

function QuestController.init()
	sheetRef = ShopController.sheet(
		"Quest",
		"Quest chest",
		WheelSheet.SIZE,
		"One item from this chest, rolled when you claim.",
		{ tone = T.sun, glyph = "gift" }
	)
	sheet = sheetRef.frame
	sheetRef.close.Activated:Connect(function()
		QuestController.open(nil, false)
	end)
	local body = sheetRef.body :: Frame
	rotor = SpinController.wheelFrame(body, "Chest", T.sun)
	info = WheelSheet.info(body, { primary = "Open chest", countHeader = "Items", dupHeader = "All owned" })
	primary = info.primary
	primary.Activated:Connect(function()
		if currentQuest then
			QuestController.claim(currentQuest)
		end
	end)
	-- prize reveal card (over the sheet's content), filled by SpinController.drawReveal
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
	ShopController.onCloseAll(function()
		QuestController.open(nil, false)
	end)
	buildPanel()
end

function QuestController.start()
	Net.on("Profile", function(d)
		status = d.quests
		owned = d.owned or {}
		renderPanel()
		if sheet.Visible and not claiming then
			local q = questOf(currentQuest)
			if q then
				buildWheel(dropsWheel(q))
			end
			renderSheet()
		end
	end)
	Net.on("QuestResult", onResult)
	local nextTick = 0
	RunService.RenderStepped:Connect(function()
		-- leaving the hub (pulled into a match) cuts a claim short; the prize is already saved
		if claiming and not inHub() then
			abortClaim(nil)
		end
		if not inHub() and sheet.Visible and not claiming then
			QuestController.open(nil, false)
		end
		-- the panel steps aside while any sheet is up
		panel.Visible = status ~= nil and not ShopController.getBackdrop().Visible
		if os.clock() < nextTick then
			return
		end
		nextTick = os.clock() + 0.5
		resetLabel.Text = ("Resets in %s"):format(untilReset())
		if sheet.Visible and not claiming then
			renderSheet()
		end
	end)
end

return QuestController
