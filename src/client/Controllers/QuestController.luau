--!strict
-- Daily quests in the hub (presentation only; QuestService decides and saves everything).
--
--  * Panel (left edge of the hub, small): one line per quest with an icon for what its chest gives
--    (titles, gestures, finishers), the goal, its count and a thin progress bar. Claim appears once
--    the goal is reached; a claimed quest shows the time until it comes back (15 minutes after a
--    player's first claim of it, otherwise the UTC reset) on a slimmer line. The panel's surface is
--    see-through so the hub shows behind it, and the button in its header folds it into a round
--    chest disc (wearing the notification dot while a chest is ready); tap the disc to unfold it.
--  * Tap a quest's icon: the chest sheet shows every item it can drop, the chance of each rarity
--    and the coins a rarity pays once you own all of it.
--  * Claim: a full-screen opening plays the treasure chest rattling while the server rolls the
--    prize, then bursting open in the prize's rarity colour; then the shared prize card
--    (SpinController.drawReveal) shows what you won in the middle of the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
local SpinController = require(script.Parent.SpinController)
local UI = script.Parent.Parent:WaitForChild("UI")
local ChestModel = require(UI:WaitForChild("ChestModel"))
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
-- each chest's disc colour and the glyph for what it gives
local CHEST_TONE: { [string]: Color3 } = { Title = T.sky, Gesture = T.candy, Finisher = T.sun }
local CHEST_GLYPH: { [string]: string } = { Title = "tag", Gesture = "hand", Finisher = "burst" }
local PANEL_W = 270
local ROW_H = 44
local DISC = 32
local DONE_H = 26 -- a claimed quest's row, folded down to one slim line
local DONE_DISC = 20
local PANEL_FADE = 0.2 -- the panel's surface transparency: the hub shows through it
local FOLDED_DISC = 48 -- the round chest the panel folds into
local TEXT_X = 40 -- right of a row's disc
local RIGHT_W = 64 -- the count, the Claim button or the cooldown, at a row's right
local TIMEOUT = 7 -- seconds without an answer before a claim gives up

type Row = {
	frame: Frame,
	folded: boolean?, -- showing the slim claimed line (nil until first drawn)
	live: Frame, -- the quest itself, until it's claimed
	name: TextLabel,
	count: TextLabel,
	fill: Frame,
	claim: TextButton,
	done: Frame, -- once claimed: the time until the quest comes back
	doneName: TextLabel,
	doneTime: TextLabel,
}

local status: any = nil -- profile.quests from the server
local owned: { [string]: boolean } = {}

-- panel
local panel: Frame
local list: Frame
local resetLabel: TextLabel
local foldedButton: TextButton -- the round chest the panel folds into
local foldedDot: Frame
local collapsed = false
local rows: { [string]: Row } = {}

-- chest sheet (drops and odds)
local sheetRef: any
local sheet: CanvasGroup
local rotor: Frame
local info: WheelSheet.Info
local primary: TextButton
local currentQuest: string? = nil

-- the claim in progress
local claiming = false
local claimToken = 0

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

-- `q` as it stands now: a claimed quest whose cooldown has run out is a fresh one again (the server
-- agrees the next time it looks at the quest).
local function current(q: any): any
	if not q.claimed or os.time() < (tonumber(q.nextAt) or math.huge) then
		return q
	end
	local fresh = table.clone(q)
	fresh.claimed = false
	fresh.ready = false
	fresh.progress = 0
	fresh.nextAt = nil
	return fresh
end

local function questOf(id: string?): any?
	for _, q in (if status then status.quests else nil) or {} do
		if q.id == id then
			return current(q)
		end
	end
	return nil
end

-- "14:05" under an hour, "5:12:33" above.
local function clock(seconds: number): string
	local left = math.max(0, seconds)
	if left < 3600 then
		return ("%d:%02d"):format(left // 60, left % 60)
	end
	return ("%d:%02d:%02d"):format(left // 3600, (left // 60) % 60, left % 60)
end

-- Time until the server's reset (the next UTC midnight).
local function untilReset(): string
	if not status or not status.resetsAt then
		return WheelSheet.untilReset()
	end
	return clock((tonumber(status.resetsAt) or 0) - os.time())
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
-- One line per quest: its chest icon, the goal and its count over a thin progress bar. A Claim
-- button takes the count's place once the goal is reached; a claimed quest shows a check and the
-- time until it comes back.

local function renderPanel()
	if not status then
		return
	end
	local anyReady = false
	for _, raw in status.quests do
		local q = current(raw)
		local row = rows[q.id]
		if not row then
			continue
		end
		local goal = math.max(1, tonumber(q.goal) or 1)
		local progress = math.min(goal, tonumber(q.progress) or 0)
		row.live.Visible = not q.claimed
		row.done.Visible = q.claimed == true
		-- a claimed quest folds down to a slim line (and back up when it comes back)
		local fold = q.claimed == true
		if row.folded ~= fold then
			local size = UDim2.new(1, 0, 0, if fold then DONE_H else ROW_H)
			-- folding eases down; unfolding snaps back so the live line never spills onto the next row
			if not fold or row.folded == nil or Theme.settings.reducedMotion then
				row.frame.Size = size
			else
				Theme.tween(row.frame, Theme.Motion.Base, { Size = size }, Enum.EasingStyle.Quint)
			end
			row.folded = fold
		end
		row.name.Text = q.name
		row.doneName.Text = q.name
		row.count.Text = ("%d/%d"):format(progress, goal)
		row.count.Visible = not q.ready
		row.fill.Size = UDim2.fromScale(progress / goal, 1)
		row.fill.BackgroundColor3 = if progress >= goal then T.leaf else T.sky
		row.claim.Visible = q.ready == true
		if q.ready then
			Theme.setText(row.claim, if claiming and currentQuest == q.id then "..." else "Claim")
			Theme.setEnabled(row.claim, not claiming)
		end
		if q.ready and not q.claimed then
			anyReady = true
		end
	end
	foldedDot.Visible = anyReady
end

local function renderTimers()
	resetLabel.Text = untilReset()
	if not status then
		return
	end
	local now = os.time()
	for _, q in status.quests do
		local row = rows[q.id]
		if row and row.done.Visible then
			local left = (tonumber(q.nextAt) or 0) - now
			if left <= 0 then
				renderPanel() -- its cooldown is over: back to a fresh quest
				return
			end
			row.doneTime.Text = clock(left)
		end
	end
end

-- A round disc in the toy outline holding `glyph`.
local function disc(
	parent: Instance,
	tone: Color3,
	glyph: string,
	glyphColor: Color3,
	button: boolean,
	size: number?
): any
	local d = new(if button then "TextButton" else "Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, (DISC - (size or DISC)) / 2, 0.5, 0),
		Size = UDim2.fromOffset(size or DISC, size or DISC),
		BackgroundColor3 = tone,
		ZIndex = 4,
	}, parent)
	if button then
		d.Text = ""
		d.AutoButtonColor = false
	end
	Theme.round(d)
	Theme.stroke(d, T.outline, Theme.StrokeToy)
	Theme.glyph(d, glyph, glyphColor, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.58),
		ZIndex = 5,
	})
	return d
end

local function buildRow(q: any, order: number): Row
	local frame = new("Frame", {
		Name = q.Id,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, list)
	local function layer(name: string): Frame
		return new(
			"Frame",
			{ Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 },
			frame
		)
	end
	local textW = -(TEXT_X + RIGHT_W + SPACE.S)

	-- the quest: its icon (tap it for the drops and odds), the goal, its count and progress, Claim
	local live = layer("Live")
	local icon = disc(live, CHEST_TONE[q.Chest] or T.sun, CHEST_GLYPH[q.Chest] or "gift", T.onFill, true)
	local name = Theme.text(live, SIZE.Body, {
		Name = "Name",
		Position = UDim2.fromOffset(TEXT_X, 4),
		Size = UDim2.new(1, textW, 0, 20),
		Text = q.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local track = new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(TEXT_X, 30),
		Size = UDim2.new(1, textW, 0, 6),
		BackgroundColor3 = T.line,
		ZIndex = 4,
	}, live)
	Theme.round(track)
	local fill =
		new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.sky, ZIndex = 5 }, track)
	Theme.round(fill)
	local count = Theme.text(live, SIZE.Body, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(RIGHT_W, 20),
		FontFace = Theme.DisplayFace,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	local claim = Theme.button(live, "Claim", "primary", {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(RIGHT_W, 32),
		Visible = false,
		ZIndex = 4,
	})
	icon.Activated:Connect(function()
		QuestController.open(q.Id, true)
	end)
	claim.Activated:Connect(function()
		QuestController.claim(q.Id)
	end)

	-- claimed: a small check, the goal greyed out and the time until it comes back, on a slim line
	local done = layer("Done")
	done.Visible = false
	disc(done, T.leaf, "check", T.onFill, false, DONE_DISC)
	local doneName = Theme.text(done, SIZE.Label, {
		Name = "Name",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, TEXT_X, 0.5, 0),
		Size = UDim2.new(1, textW, 0, 20),
		Text = q.Name,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local doneTime = Theme.text(done, SIZE.Label, {
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(RIGHT_W, 20),
		FontFace = Theme.DisplayFace,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	return {
		frame = frame,
		live = live,
		name = name,
		count = count,
		fill = fill,
		claim = claim,
		done = done,
		doneName = doneName,
		doneTime = doneTime,
	}
end

-- Fold the panel into its round chest disc, or unfold it; the one that appears pops in.
function QuestController.setCollapsed(on: boolean)
	if collapsed == on then
		return
	end
	collapsed = on
	SoundController.play(if on then "UIBack" else "UIOpen")
	local shown: GuiObject = if on then foldedButton else panel
	if panel.Parent and (panel.Visible or foldedButton.Visible) then
		panel.Visible = not on
		foldedButton.Visible = on
		Theme.pop(shown, 0.6)
	end
end

local function buildPanel()
	-- parented after it's built: no drop shadow, which would darken the see-through surface
	panel = Theme.panel(nil, {
		Name = "Quests",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.M, 0.4, 0),
		Size = UDim2.fromOffset(PANEL_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = PANEL_FADE,
		Visible = false,
		ZIndex = 2,
	}, Theme.Radius.M)
	panel.Parent = ShopController.gui
	Theme.stroke(panel, T.line, 2)
	Theme.padding(panel, SPACE.S + 2)
	-- never below 0.85: on phones the screen scale alone would shrink quest text to ~8px
	Theme.autoScale(panel, 0.8, 0.85)
	new("UIListLayout", { Padding = UDim.new(0, SPACE.XS), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	-- header: the title, the time until the daily reset and, at the right, the fold button
	local header = new("Frame", {
		Name = "Header",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, panel)
	Theme.text(header, SIZE.Heading, {
		Name = "Title",
		Size = UDim2.fromScale(0.6, 1),
		FontFace = Theme.DisplayFace,
		Text = "Daily quests",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local collapseButton = Theme.iconButton(header, "back", "secondary", 24, {
		Name = "Collapse",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		ZIndex = 4,
	})
	collapseButton.Activated:Connect(function()
		QuestController.setCollapsed(true)
	end)
	resetLabel = Theme.text(header, SIZE.Label, {
		Name = "Reset",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(24 + SPACE.S), 0, 0),
		Size = UDim2.new(0.4, -(24 + SPACE.S), 1, 0),
		Text = untilReset(),
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	list = new("Frame", {
		Name = "List",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, SPACE.XS), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, q in Q.List do
		rows[q.Id] = buildRow(q, i)
	end

	-- folded: a round chest disc in the panel's place; the dot says a chest is ready to claim
	foldedButton = Theme.iconButton(ShopController.gui, "gift", T.sun, FOLDED_DISC, {
		Name = "QuestsFolded",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.M, 0.4, 0),
		Visible = false,
		ZIndex = 2,
	})
	Theme.autoScale(foldedButton, 0.8, 0.85)
	foldedDot = Theme.dot(foldedButton:FindFirstChild("Face") :: Frame)
	foldedDot.Position = UDim2.new(1, -4, 0, 4)
	foldedButton.Activated:Connect(function()
		QuestController.setCollapsed(false)
	end)
end

-- Chest sheet -----------------------------------------------------------------------------------------

local function renderSheet()
	local q = questOf(currentQuest)
	if not q then
		return
	end
	local goal = math.max(1, tonumber(q.goal) or 1)
	local progress = math.min(goal, tonumber(q.progress) or 0)
	sheetRef.title.Text = q.chestName
	sheetRef.subtitle.Text = ("%s. You get one item from this chest, rolled when you claim."):format(q.name)
	if q.claimed then
		WheelSheet.setStatus(info, {
			fill = T.leaf,
			glyph = "check",
			title = "Claimed",
			detail = ("Back in %s"):format(clock((tonumber(q.nextAt) or 0) - os.time())),
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
	if q.ready and not claiming then
		Theme.setText(primary, "Open chest")
		Theme.recolor(primary, "primary")
		Theme.setEnabled(primary, true)
	else
		Theme.setText(primary, if q.claimed then "Claimed" else ("%d of %d done"):format(progress, goal))
		Theme.recolor(primary, "secondary")
		Theme.setEnabled(primary, false)
	end
	info.caption.Text = ("Quests reset in %s"):format(untilReset())
end

-- Show the chest sheet for quest `id`, or close it.
function QuestController.open(id: string?, on: boolean)
	if on and (claiming or not inHub() or not questOf(id)) then
		return
	end
	if on then
		if not ShopController.isOpen(sheet) then
			SoundController.play("UIOpen")
		end
		ShopController.closeAll()
		currentQuest = id
		SpinController.drawWheel(rotor, dropsWheel(questOf(id)), owned, Config.Economy.DuplicateCoins)
		renderSheet()
		Theme.show(sheet, ShopController.getBackdrop())
		Theme.focus(primary)
	else
		if ShopController.isOpen(sheet) then
			Theme.setHome(nil)
		end
		Theme.hide(sheet, ShopController.getBackdrop())
	end
end

-- Opening screen --------------------------------------------------------------------------------------
-- Full screen over the hub: the chest (a 3D model in a viewport) drops in and rattles, peeking its
-- lid, until the server answers; then it bursts open (flash, shockwave, light pillar, sparkles in the
-- prize's rarity colour), holds a beat, and gives way to the prize card in the middle.

local OPEN_ANGLE = math.rad(112)
local OPEN_TIME = 0.5
local MIN_RATTLE = 1.2 -- the chest always rattles at least this long before it bursts
local SHOT_HOLD = 1.1 -- seconds the open chest shows before the prize card
local VIEW = 440 -- the chest viewport's size (px, before the screen scale)
local CENTER = UDim2.fromScale(0.5, 0.54) -- where the chest sits on screen

type Opening = {
	token: number,
	quest: string,
	model: Model,
	lid: Model,
	home: CFrame,
	lidRel: CFrame, -- the lid's hinge relative to the chest
	glow: BasePart,
	started: number,
	result: any?,
	burstAt: number?,
	shown: boolean, -- the prize card is up
	conn: RBXScriptConnection,
}

local openGui: ScreenGui
local shade: Frame
local rays: Frame
local halo: Frame
local holder: Frame
local view: ViewportFrame
local viewCam: Camera
local chestTitle: TextLabel
local caption: TextLabel
local flash: Frame
local reveal: Frame
local opening: Opening? = nil

local function reduced(): boolean
	return HUDController.settings.ReducedMotion == true
end

local function backOut(x: number): number
	local c1 = 1.70158
	return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function setRayColor(color: Color3)
	for _, r in rays:GetChildren() do
		if r:IsA("Frame") then
			r.BackgroundColor3 = color
		end
	end
	halo.BackgroundColor3 = color
end

local function buildOpening()
	openGui = new("ScreenGui", {
		Name = "QuestChest",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20, -- over the hub, the HUD and the intro bars
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	shade = new("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.dim,
		BackgroundTransparency = 0.2,
		Active = true, -- nothing behind the opening takes clicks
		ZIndex = 1,
	}, openGui)
	-- slow light rays and a soft halo behind the chest, in the chest's glow (the prize's rarity later)
	rays = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTER,
		Size = UDim2.fromScale(1.6, 1.6),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, openGui)
	for i = 0, 7 do
		local ray = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.09, 1),
			Rotation = i * 22.5,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 2,
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
	halo = new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTER,
		Size = UDim2.fromScale(0.62, 0.62),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 0.8,
		ZIndex = 3,
	}, openGui)
	Theme.round(halo)
	holder = new("Frame", {
		Name = "Chest",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTER,
		Size = UDim2.fromOffset(VIEW, VIEW),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, openGui)
	Theme.autoScale(holder)
	view = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 180, 170),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.35, -1, 0.6),
		ZIndex = 5,
	}, holder)
	viewCam = Instance.new("Camera")
	viewCam.Parent = view
	view.CurrentCamera = viewCam
	chestTitle = Theme.label(openGui, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.new(0.9, 0, 0, 64),
		ZIndex = 8,
	}, 4)
	caption = Theme.label(holder, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.84),
		Size = UDim2.new(1, 0, 0, 38),
		Text = "Opening...",
		ZIndex = 8,
	}, 3)
	flash = new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, openGui)
	-- the prize card, filled by SpinController.drawReveal
	reveal = new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(440, 400),
		BackgroundColor3 = T.surfaceSunk,
		Visible = false,
		ZIndex = 20,
		Active = true,
		ClipsDescendants = true,
	}, openGui)
	Theme.corner(reveal, Theme.Radius.L)
	Theme.stroke(reveal, T.sun, 4)
	Theme.autoScale(reveal)
end

-- An effect that fades away and cleans itself up.
local function fx(className: string, props: { [string]: any }, goal: { [string]: any }, life: number, style: any?): any
	local f = new(className, props, openGui)
	Theme.tween(f, life, goal, style or Enum.EasingStyle.Quad)
	task.delay(life, function()
		f:Destroy()
	end)
	return f
end

-- The lid bursts: a white flash, a shockwave ring, a light pillar and sparkles flying out.
local function burstFx(color: Color3)
	if not reduced() then
		flash.BackgroundTransparency = 0.15
		Theme.tween(flash, 0.45, { BackgroundTransparency = 1 })
	end
	local ring = fx("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTER,
		Size = UDim2.fromScale(0.15, 0.15),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, { Size = UDim2.fromScale(1.5, 1.5) }, 0.7, Enum.EasingStyle.Quart)
	Theme.round(ring)
	local stroke = Theme.stroke(ring, color, 10)
	Theme.tween(stroke, 0.7, { Transparency = 1, Thickness = 2 })
	local pillar = fx("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = CENTER,
		Size = UDim2.fromScale(0.14, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, { Size = UDim2.fromScale(0.2, 1), BackgroundTransparency = 1 }, 1.2, Enum.EasingStyle.Quint)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, pillar)
	local rng = Random.new()
	for _ = 1, if reduced() then 8 else 22 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0.18, 0.5)
		local size = rng:NextInteger(22, 44)
		local spark = fx("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = CENTER,
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			FontFace = Theme.LabelFace,
			TextScaled = true,
			Text = if rng:NextNumber() < 0.5 then "✦" else "★",
			TextColor3 = if rng:NextNumber() < 0.65 then color else Color3.new(1, 1, 1),
			Rotation = rng:NextNumber(-40, 40),
			ZIndex = 7,
		}, {
			Position = CENTER + UDim2.fromScale(math.cos(angle) * dist * 0.6, math.sin(angle) * dist),
			Rotation = rng:NextNumber(-220, 220),
			TextTransparency = 1,
		}, rng:NextNumber(0.8, 1.3), Enum.EasingStyle.Quart)
		Theme.textStroke(spark, 2)
	end
end

local function closeOpening(fade: boolean)
	local o = opening
	opening = nil
	claiming = false
	if o then
		o.conn:Disconnect()
		o.model:Destroy()
	end
	Theme.hide(reveal)
	if fade and not reduced() then
		local token = claimToken
		Theme.tween(shade, 0.25, { BackgroundTransparency = 1 })
		for _, f in { rays, halo, chestTitle, caption } :: { GuiObject } do
			f.Visible = false
		end
		task.delay(0.25, function()
			if token == claimToken and not opening then
				openGui.Enabled = false
			end
		end)
	else
		openGui.Enabled = false
	end
	renderPanel()
end

local function abortClaim(message: string?)
	claimToken += 1
	closeOpening(false)
	if message then
		SoundController.play("UIError")
		HUDController.hint(message, 1.6)
	end
end

-- Show the prize card in the middle of the screen; dismissing it closes the opening.
local function showPrize(o: Opening)
	o.shown = true
	Theme.tween(view, 0.25, { ImageTransparency = 1 })
	Theme.tween(caption, 0.2, { TextTransparency = 1 })
	local row = rows[o.quest]
	local token = o.token
	SpinController.drawReveal(reveal, o.result, if row then row.claim else panel, function()
		if opening and opening.token == token then
			closeOpening(true)
		end
	end)
end

-- One frame of the opening: rattle until the answer is in (and MIN_RATTLE has passed), then burst.
local function step(o: Opening)
	local t = os.clock() - o.started
	rays.Rotation = (rays.Rotation + (if o.burstAt then 0.5 else 0.15)) % 360
	halo.BackgroundTransparency = 0.82 - 0.06 * math.sin(t * 5)
	if not o.burstAt then
		if o.result and t >= MIN_RATTLE then
			-- burst open now
			o.burstAt = t
			local color = Theme.Rarity[o.result.rarity] or T.sun
			o.glow.Color = color
			setRayColor(color)
			caption.Text = ""
			SoundController.play("ChestBurst")
			burstFx(color)
			if not reduced() then
				Theme.tween(viewCam, 0.6, { FieldOfView = 34 }, Enum.EasingStyle.Quint)
			end
		else
			-- rattle: shakes harder the longer it waits, hopping now and then, the lid peeking open
			local shake = if reduced() then 0 else math.clamp((t - 0.3) / 1.4, 0, 1)
			local a = if reduced() then 0 else math.rad(2 + 5 * shake)
			local wob = CFrame.Angles(math.sin(t * 41) * a * 0.4, math.sin(t * 23) * a * 0.6, math.sin(t * 37) * a)
			local hop = math.max(0, math.sin(t * 9)) * 0.14 * shake
			local base = o.home * CFrame.new(0, hop, 0) * wob
			o.model:PivotTo(base)
			local peek = math.rad(5 + 7 * shake) * math.max(0, math.sin(t * 6))
			o.lid:PivotTo(base * o.lidRel * CFrame.Angles(peek, 0, 0))
			return
		end
	end
	-- open: the lid swings back past upright and settles; the chest gives a little bounce
	local since = t - (o.burstAt :: number)
	local a = math.clamp(since / OPEN_TIME, 0, 1)
	local bounce = math.max(0, math.sin(math.min(since / 0.35, 1) * math.pi)) * 0.35
	local base = o.home * CFrame.new(0, bounce, 0)
	o.model:PivotTo(base)
	o.lid:PivotTo(base * o.lidRel * CFrame.Angles(OPEN_ANGLE * backOut(a), 0, 0))
	if not o.shown and since >= (if reduced() then 0.5 else SHOT_HOLD) then
		showPrize(o)
	end
end

local function startOpening(q: any)
	local stale = opening
	if stale then
		stale.conn:Disconnect()
		stale.model:Destroy()
	end
	local model = ChestModel.build(q.chest)
	local lid = model:FindFirstChild("Lid") :: Model
	local home = model:GetPivot()
	local lidRel = home:ToObjectSpace(lid:GetPivot())
	model.Parent = view
	-- the camera: in front, a little to the right and above, looking at the middle of the chest
	local focus = Vector3.new(0, ChestModel.Size.Y * 0.48, 0)
	viewCam.FieldOfView = 40
	viewCam.CFrame = CFrame.lookAt(focus + Vector3.new(3.4, 3.6, -9.6), focus)
	view.ImageTransparency = 0
	local tone = ChestModel.Styles[q.chest] and ChestModel.Styles[q.chest].Glow or T.sun
	setRayColor(tone)
	chestTitle.Text = q.chestName
	caption.Text = "Opening..."
	caption.TextTransparency = 0
	for _, f in { rays, halo, chestTitle, caption } :: { GuiObject } do
		f.Visible = true
	end
	reveal.Visible = false
	flash.BackgroundTransparency = 1
	shade.BackgroundTransparency = 1
	Theme.tween(shade, 0.25, { BackgroundTransparency = 0.2 })
	openGui.Enabled = true
	Theme.pop(holder, 0.25, 0.5)
	Theme.pop(chestTitle, 0.6)
	local o: Opening
	o = {
		token = claimToken,
		quest = q.id,
		model = model,
		lid = lid,
		home = home,
		lidRel = lidRel,
		glow = model:FindFirstChild("Glow") :: BasePart,
		started = os.clock(),
		result = nil,
		burstAt = nil,
		shown = false,
		conn = RunService.RenderStepped:Connect(function()
			step(o)
		end),
	}
	opening = o
	-- rattle sounds, quicker as it waits, until it bursts
	task.spawn(function()
		local gap = 0.26
		while opening == o and not o.burstAt do
			SoundController.play("ChestRattle", nil, 0.8)
			task.wait(gap)
			gap = math.max(0.14, gap * 0.93)
		end
	end)
end

-- Claim quest `id`'s chest: the opening plays while the server rolls the prize.
function QuestController.claim(id: string)
	local q = questOf(id)
	if claiming or not q or not inHub() then
		return
	end
	if not q.ready then
		SoundController.play("UIError")
		HUDController.hint(if q.claimed then "Already claimed" else q.name .. " first", 1.5)
		return
	end
	ShopController.closeAll()
	currentQuest = id
	claiming = true
	claimToken += 1
	local token = claimToken
	renderPanel()
	SoundController.play("UIOpen")
	startOpening(q)
	Net.request(Net.Actions.ClaimQuest, { id = id })
	task.delay(TIMEOUT, function()
		local o = opening
		if claiming and token == claimToken and o and not o.result then
			abortClaim("Couldn't open the chest, try again")
		end
	end)
end

local function onResult(d: any)
	local o = opening
	if not claiming or not o or d.quest ~= o.quest then
		return
	end
	if d.ok == false then
		abortClaim(tostring(d.message or "Can't open the chest right now"))
		return
	end
	o.result = d
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
	ShopController.onCloseAll(function()
		QuestController.open(nil, false)
	end)
	buildPanel()
	buildOpening()
end

function QuestController.start()
	Net.on("Profile", function(d)
		status = d.quests
		owned = d.owned or {}
		renderPanel()
		if sheet.Visible then
			local q = questOf(currentQuest)
			if q then
				SpinController.drawWheel(rotor, dropsWheel(q), owned, Config.Economy.DuplicateCoins)
			end
			renderSheet()
		end
	end)
	Net.on("QuestResult", onResult)
	local nextTick = 0
	RunService.RenderStepped:Connect(function()
		-- leaving the hub (pulled into a match) cuts an opening short; the prize is already saved
		if claiming and not inHub() then
			abortClaim(nil)
		end
		if not inHub() and sheet.Visible then
			QuestController.open(nil, false)
		end
		-- the panel steps aside while any sheet or the opening is up
		local show = status ~= nil and not ShopController.getBackdrop().Visible and not openGui.Enabled
		panel.Visible = show and not collapsed
		foldedButton.Visible = show and collapsed
		if os.clock() < nextTick then
			return
		end
		nextTick = os.clock() + 0.5
		renderTimers()
		if sheet.Visible then
			renderSheet()
		end
	end)
end

return QuestController
