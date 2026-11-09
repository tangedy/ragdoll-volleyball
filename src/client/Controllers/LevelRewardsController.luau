--!strict
-- Level rewards (docs/ECONOMY.md §8). The server banks each level's reward the moment you reach it
-- (RewardService.payLevels); this only presents it:
--   * the "Level rewards" sheet, opened from the Lv sticker on the coins chip: a paged grid of ten
--     level cards a page. Banked levels wear a check stamp, the next one glows with your XP toward
--     it, later ones are locked. Every 5th level (bonus) and 10th (an earn-only title) stands out.
--   * a dot on the Lv sticker while rewards banked this session haven't been looked at
--   * the level-up card when a match takes you up a level (LevelUp)
-- The sheet opens only in the hub, once the tutorial is done.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local new = Theme.new
local PR = Config.Progression

local LevelRewardsController = {}

local SIZE = Vector2.new(760, 596)
local CARD = Vector2.new(128, 150)
local GAP = 18
local PER_PAGE = 10
local PAGES = math.ceil(PR.LevelCap / PER_PAGE)
local KEYS = "RD_LevelKeys"
local CHEST_TONES: { [string]: Color3 } = { Title = T.sky, Gesture = T.leaf, Finisher = T.candy }

local sheet: any -- Theme.Sheet
local panel: CanvasGroup
local grid: Frame
local pageLabel: TextLabel
local pips: { TextButton } = {}
local prevButton: TextButton
local nextButton: TextButton
local levelText: TextLabel
local xpText: TextLabel
local xpFill: Frame
local stickerDot: Frame? = nil
local cards: { { [string]: any } } = {}
local page = 1

-- from the Profile push
local level = 1
local xp = 0
local xpNext = 1
local paid = 1 -- every level up to here is banked
local since: number? = nil -- where this session started: levels above it are new
local seen = 0 -- the highest banked level shown in the sheet this session
local newFrom = 0 -- the "NEW!" line while the sheet is open
local backPayShown = false

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function tutorialDone(): boolean
	return player:GetAttribute("TutorialDone") == true
end

local function isOpen(): boolean
	return sheet ~= nil and panel.Visible and panel:GetAttribute("ThemeOpen") ~= false
end

-- Banked levels the player hasn't seen in the sheet yet (only ones banked this session).
local function unseen(): number
	return paid - math.max(since or paid, seen)
end

local function refreshDot()
	if stickerDot then
		stickerDot.Visible = tutorialDone() and unseen() > 0
	end
end

-- Reward art and labels -------------------------------------------------------------------------------

local function rewardLabel(reward: any): string
	if reward.Kind == "Coins" then
		return "+" .. ShopController.commas(reward.Amount)
	elseif reward.Kind == "Spin" then
		return if reward.Wheel == "RarePlus" then "Rare+ spin" else "Bonus spin"
	elseif reward.Kind == "Chest" then
		local def = (Config.Quests.Chests :: any)[reward.Chest]
		return if def then def.Name else "Chest"
	elseif reward.Kind == "Boost" then
		return ("%dx coins"):format(Config.CoinShop.BoostMultiplier)
	end
	local item = reward.Id and Catalog.get(reward.Id)
	return if item then item.Name else "Item"
end
LevelRewardsController.rewardLabel = rewardLabel

-- One line for the level-up card from what the server banked (RewardService.payLevels).
local function bankedLabel(b: any): string
	if b.kind == "Coins" then
		return ("+%s coins"):format(ShopController.commas(b.coins or 0))
	elseif b.kind == "Spin" then
		return (if b.wheel == "RarePlus" then "Rare+ spin" else "Bonus spin") .. " · in Spin"
	elseif b.kind == "Chest" then
		local def = (Config.Quests.Chests :: any)[b.chest]
		local item = b.id and Catalog.get(b.id)
		local name = if def then def.Name else "Chest"
		if b.duplicate then
			return ("%s: +%s coins"):format(name, ShopController.commas(b.coins or 0))
		end
		return if item then ("%s: %s"):format(name, item.Name) else name
	elseif b.kind == "Cosmetic" then
		local item = b.id and Catalog.get(b.id)
		return if item then ("Title: %s"):format(item.Name) else "New title"
	end
	return "Reward"
end

local function disc(holder: GuiObject, size: number, fill: Color3, z: number): Frame
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		ZIndex = z,
	}, holder)
	Theme.round(f)
	Theme.stroke(f, T.outline, Theme.StrokeToy)
	return f
end

-- Frame-built art for a level's reward, centered in `holder` (sized about 60 x 52 at scale 1).
local function drawIcon(holder: Frame, reward: any, scale: number?)
	local s = scale or 1
	local z = holder.ZIndex
	if reward.Kind == "Coins" then
		local spots: { { number } } = if reward.Amount >= 150
			then { { 0.3, 0.62 }, { 0.7, 0.62 }, { 0.5, 0.36 } }
			elseif reward.Amount >= 100 then { { 0.38, 0.58 }, { 0.62, 0.42 } }
			else { { 0.5, 0.5 } }
		for n, spot in spots do
			Theme.coin(holder, math.floor((if #spots > 1 then 34 else 44) * s), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot[1], spot[2]),
				ZIndex = z + n,
			})
		end
	elseif reward.Kind == "Spin" then
		-- the hub wheel in miniature: four prize slots in the wheel's rarities and a sun hub
		local wheel = disc(holder, math.floor(50 * s), T.surfaceSunk, z)
		local slots: { string } = if reward.Wheel == "RarePlus"
			then { "Rare", "Epic", "Rare", "Legendary" }
			else { "Common", "Rare", "Common", "Epic" }
		for n, r in slots do
			local a = math.rad((n - 1) * 90)
			local slot = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + 0.3 * math.sin(a), 0.5 - 0.3 * math.cos(a)),
				Size = UDim2.fromScale(0.3, 0.3),
				BackgroundColor3 = Theme.Rarity[r],
				ZIndex = z + 1,
			}, wheel)
			Theme.round(slot)
			Theme.stroke(slot, T.outline, 1.5)
		end
		local hub = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.26, 0.26),
			BackgroundColor3 = T.sun,
			ZIndex = z + 2,
		}, wheel)
		Theme.round(hub)
		Theme.stroke(hub, T.outline, 1.5)
	elseif reward.Kind == "Chest" then
		-- a toy chest: body in the chest's tone, a darker lid, a sun latch
		local tone = CHEST_TONES[reward.Chest] or T.peach
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, math.floor(6 * s)),
			Size = UDim2.fromOffset(math.floor(50 * s), math.floor(30 * s)),
			BackgroundColor3 = tone,
			ZIndex = z,
		}, holder)
		Theme.corner(box, 6)
		Theme.stroke(box, T.outline, Theme.StrokeToy)
		local lid = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.new(1, 6, 0, math.floor(18 * s)),
			BackgroundColor3 = Theme.darken(tone, 0.22),
			ZIndex = z + 1,
		}, box)
		Theme.corner(lid, 8)
		Theme.stroke(lid, T.outline, Theme.StrokeToy)
		local latch = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.fromOffset(math.floor(12 * s), math.floor(14 * s)),
			BackgroundColor3 = T.sun,
			ZIndex = z + 2,
		}, box)
		Theme.corner(latch, 3)
		Theme.stroke(latch, T.outline, 2)
	else
		-- a title: its name tag, edged in its rarity's color
		local item = reward.Id and Catalog.get(reward.Id)
		local rarity = if item then Catalog.rarity(item) else "Rare"
		local tag = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, math.floor(30 * s)),
			BackgroundColor3 = T.paper,
			ZIndex = z,
		}, holder)
		Theme.round(tag)
		Theme.stroke(tag, Theme.Rarity[rarity] or T.outline, 4)
		local ring = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, tag)
		Theme.round(ring)
		Theme.stroke(ring, T.outline, 1.5)
		local text = Theme.text(tag, math.floor(14 * s), {
			Size = UDim2.new(1, -10, 1, 0),
			Position = UDim2.fromOffset(5, 0),
			FontFace = Theme.DisplayFace,
			Text = if rarity == "Legendary"
				then "✦ " .. (if item then item.Name else "") .. " ✦"
				else (if item then item.Name else ""),
			TextColor3 = T.ink,
			TextScaled = true,
			ZIndex = z + 1,
		})
		new("UITextSizeConstraint", { MaxTextSize = math.floor(15 * s) }, text)
	end
end

-- A small padlock built from frames on a paper disc: an outlined shackle over a body with a keyhole.
local function padlock(parent: Instance, z: number, props: { [string]: any }): Frame
	local f = new("Frame", {
		Name = "Lock",
		BackgroundColor3 = T.paper,
		ZIndex = z,
	}, nil)
	for k, v in props do
		(f :: any)[k] = v
	end
	Theme.round(f)
	Theme.stroke(f, T.outline, 2.5)
	local shackle = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromScale(0.4, 0.44),
		BackgroundTransparency = 1,
		ZIndex = z + 1,
	}, f)
	Theme.corner(shackle, 8)
	Theme.stroke(shackle, T.ink, 2.5)
	local body = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.56, 0.4),
		BackgroundColor3 = T.ink,
		ZIndex = z + 2,
	}, f)
	Theme.corner(body, 3)
	local hole = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = T.paper,
		ZIndex = z + 3,
	}, body)
	Theme.round(hole)
	f.Parent = parent
	return f
end

local function sunburst(parent: Instance, size: number, z: number, transparency: number): Frame
	local rays = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, parent)
	for r = 0, 5 do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 14, 1, 0),
			Rotation = r * 30,
			BackgroundColor3 = T.paper,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = z,
		}, rays)
	end
	return rays
end

-- Level cards ---------------------------------------------------------------------------------------

local function toneOf(lv: number, reward: any): Color3
	if lv % 10 == 0 then
		return T.sun
	elseif reward.Kind == "Spin" then
		return T.candy
	elseif reward.Kind == "Chest" then
		return T.peach
	end
	return T.sky
end

-- One level card: a toy card with a "Lv N" strip, the reward's art and label, and a paper status strip.
local function levelCard(parent: Instance, lv: number, order: number): { [string]: any }
	local reward = PR.Rewards[lv]
	local got = lv <= paid
	local isNext = not got and lv == level + 1
	local milestone = lv % 10 == 0
	local bonus = lv % 5 == 0 and not milestone
	local fill = if reward then toneOf(lv, reward) else T.leaf
	local root = new("Frame", {
		Name = "Level" .. lv,
		LayoutOrder = order,
		Size = UDim2.fromOffset(CARD.X, CARD.Y + Theme.Ledge),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, parent)
	if milestone then
		new("UIScale", { Scale = 1.05 }, root)
	end
	local glow = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -Theme.Ledge / 2),
		Size = UDim2.new(1, 12, 1, 12 - Theme.Ledge),
		BackgroundTransparency = 1,
		Visible = isNext,
		ZIndex = 4,
	}, root)
	Theme.corner(glow, Theme.Radius.M + 6)
	local glowStroke = Theme.stroke(glow, T.select, Theme.StrokeSelect)
	local ledge = new("Frame", {
		Name = "Ledge",
		Position = UDim2.fromOffset(0, Theme.Ledge),
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = T.shadowToy,
		ZIndex = 4,
	}, root)
	Theme.corner(ledge, Theme.Radius.M)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = fill,
		ClipsDescendants = true,
		ZIndex = 5,
	}, root)
	Theme.corner(face, Theme.Radius.M)
	Theme.stroke(face, T.outline, if milestone then 4 else Theme.StrokeToy)
	-- top strip (rounded on top only: a square filler covers its lower corners)
	local stripTone = Theme.darken(fill, 0.28)
	local top = new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = stripTone,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, face)
	Theme.corner(top, Theme.Radius.M)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.Radius.M),
		Size = UDim2.new(1, 0, 0, Theme.Radius.M),
		BackgroundColor3 = stripTone,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, top)
	local lvLabel = Theme.text(top, 18, {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.DisplayFace,
		Text = ("Lv %d"):format(lv),
		TextColor3 = T.paper,
		ZIndex = 7,
	})
	Theme.textStroke(lvLabel, 2)
	-- the art over a sunburst (milestones and the next level), and its label
	local art = new("Frame", {
		Name = "Art",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30 - 30),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 6,
	}, face)
	local rays = sunburst(art, 120, 6, if milestone then 0.35 else 0.6)
	rays.Visible = milestone or isNext
	local icon = new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, -16, 0, 52),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, art)
	local label: TextLabel
	if reward then
		drawIcon(icon, reward)
		label = Theme.text(art, 17, {
			Name = "Amount",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 22),
			FontFace = Theme.DisplayFace,
			Text = rewardLabel(reward),
			TextColor3 = T.paper,
			TextScaled = true,
			ZIndex = 10,
		})
		new("UITextSizeConstraint", { MaxTextSize = if reward.Kind == "Coins" then 22 else 17 }, label)
	else
		-- level 1: where everyone starts
		Theme.glyph(icon, "play", T.paper, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(40, 40),
			ZIndex = 8,
		})
		label = Theme.text(art, 18, {
			Name = "Amount",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 22),
			FontFace = Theme.DisplayFace,
			Text = "Start!",
			TextColor3 = T.paper,
			ZIndex = 10,
		})
	end
	Theme.textStroke(label, 2.5)
	-- banked: a paper check stamp, tilted like it was pressed on by hand
	if got then
		local stamp = new("Frame", {
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -22, 0, 22),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = T.paper,
			Rotation = -12,
			ZIndex = 12,
		}, art)
		Theme.round(stamp)
		Theme.stroke(stamp, T.outline, Theme.StrokeToy)
		Theme.glyph(stamp, "check", T.success, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.72, 0.72),
			ZIndex = 13,
		})
	elseif not isNext then
		-- locked: the art stays readable under a paper veil, and a padlock sits on the strip
		new("Frame", {
			Name = "Veil",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = T.surface,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, art)
		padlock(face, 14, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0, 15),
			Size = UDim2.fromOffset(26, 26),
		})
	end
	-- status strip
	local bottom = new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = T.paper,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, face)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = T.outline,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, bottom)
	if isNext then
		local track = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.new(1, -16, 0, 16),
			BackgroundColor3 = T.surfaceSunk,
			ZIndex = 8,
		}, bottom)
		Theme.round(track)
		Theme.stroke(track, T.outline, 1.5)
		local fillBar = new("Frame", {
			Size = UDim2.fromScale(math.clamp(xp / math.max(xpNext, 1), 0.06, 1), 1),
			BackgroundColor3 = T.leaf,
			ZIndex = 9,
		}, track)
		Theme.round(fillBar)
		Theme.text(track, 12, {
			Size = UDim2.fromScale(1, 1),
			Text = ("%d / %d XP"):format(xp, xpNext),
			TextColor3 = T.ink,
			ZIndex = 10,
		})
	else
		Theme.text(bottom, 15, {
			Size = UDim2.new(1, 0, 1, 2),
			Text = if got then "✓ Got it!" else ("Reach Lv %d"):format(lv),
			TextColor3 = if got then T.success else T.inkMuted,
			ZIndex = 8,
		})
	end
	-- stickers: what's new, and what's big
	if got and lv > newFrom and lv > 1 then
		Theme.sticker(root, "New!", T.joyRed, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(-6, 2),
			Rotation = -10,
			ZIndex = 16,
		})
	end
	if milestone then
		Theme.sticker(root, if lv == PR.LevelCap then "Max!" else "Title", T.joyRed, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -10, 0, 2),
			Rotation = 12,
			ZIndex = 15,
		})
	elseif bonus then
		Theme.sticker(root, "Bonus", T.sun, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -10, 0, 2),
			Rotation = 12,
			ZIndex = 15,
		})
	end
	return {
		root = root,
		rays = rays,
		icon = icon,
		glowStroke = glowStroke,
		isNext = isNext,
		milestone = milestone,
	}
end

-- The sheet ----------------------------------------------------------------------------------------

local function renderProgress()
	if not sheet then
		return
	end
	levelText.Text = ("Level %d"):format(level)
	if level >= PR.LevelCap then
		xpText.Text = "Max level! Every reward is banked."
		xpFill.Size = UDim2.fromScale(1, 1)
	else
		xpText.Text = ("%d / %d XP to Level %d"):format(xp, xpNext, level + 1)
		xpFill.Size = UDim2.fromScale(math.clamp(xp / math.max(xpNext, 1), 0.03, 1), 1)
	end
end

local function renderPage(animate: boolean?)
	if not sheet then
		return
	end
	for _, c in cards do
		c.root:Destroy()
	end
	table.clear(cards)
	local first = (page - 1) * PER_PAGE + 1
	local last = math.min(PR.LevelCap, first + PER_PAGE - 1)
	for lv = first, last do
		table.insert(cards, levelCard(grid, lv, lv))
	end
	pageLabel.Text = ("Levels %d–%d"):format(first, last)
	for i, pip in pips do
		local here = i == page
		local done = i * PER_PAGE <= paid
		pip.Size = UDim2.fromOffset(if here then 22 else 14, if here then 22 else 14)
		pip.BackgroundColor3 = if here then T.select elseif done then T.leaf else T.surfaceSunk
	end
	Theme.setEnabled(prevButton, page > 1)
	Theme.setEnabled(nextButton, page < PAGES)
	renderProgress()
	if animate then
		local roots = {}
		for _, c in cards do
			table.insert(roots, c.root)
		end
		Theme.popIn(roots)
	end
end

local function flip(delta: number)
	local to = math.clamp(page + delta, 1, PAGES)
	if to == page then
		SoundController.play("UIEdge")
		return
	end
	page = to
	SoundController.play("UITab")
	renderPage(true)
end

local function bindKeys(on: boolean)
	if not on then
		ContextActionService:UnbindAction(KEYS)
		return
	end
	ContextActionService:BindActionAtPriority(
		KEYS,
		function(_, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.ButtonL1 then
				flip(-1)
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.ButtonR1 then
				flip(1)
			elseif input.KeyCode == Enum.KeyCode.ButtonB then
				SoundController.play("UIBack")
				LevelRewardsController.open(false)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		3000,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonB
	)
end

-- Why the sheet can't open right now, or nil when it can.
local function blocked(): string?
	if not tutorialDone() then
		return "Level rewards open after the tutorial"
	elseif not inHub() then
		return "Level rewards open in the hub"
	end
	return nil
end

function LevelRewardsController.open(on: boolean)
	if not sheet then
		return
	end
	if on then
		local why = blocked()
		if why then
			SoundController.play("UIError")
			HUDController.hint(why, 1.6)
			return
		end
		if not isOpen() then
			SoundController.play("UIOpen")
		end
		ShopController.closeAll()
		-- this view shows what's new; after it, those count as seen
		newFrom = math.max(since or paid, seen)
		seen = paid
		refreshDot()
		page = math.clamp(math.ceil(math.min(level + 1, PR.LevelCap) / PER_PAGE), 1, PAGES)
		Theme.show(panel, ShopController.getBackdrop())
		renderPage(true)
		bindKeys(true)
		Theme.focus(nextButton)
	else
		bindKeys(false)
		if isOpen() then
			Theme.setHome(nil)
		end
		Theme.hide(panel, ShopController.getBackdrop())
	end
end

function LevelRewardsController.isOpen(): boolean
	return isOpen()
end

local function buildSheet()
	sheet = ShopController.sheet(
		"LevelRewards",
		"Level rewards",
		SIZE,
		"Every level banks a reward the moment you reach it.",
		{ tone = T.leaf, glyph = "star" }
	)
	panel = sheet.frame
	sheet.close.Activated:Connect(function()
		LevelRewardsController.open(false)
	end)
	local body = sheet.body :: Frame
	local z = body.ZIndex

	-- your level and XP toward the next one
	local progress = Theme.well(body, {
		Name = "Progress",
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = z,
	}, Theme.Radius.M)
	local lvChip = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(104, 30),
		BackgroundColor3 = T.sky,
		ZIndex = z + 1,
	}, progress)
	Theme.round(lvChip)
	Theme.stroke(lvChip, T.outline, Theme.StrokeToy)
	levelText = Theme.text(lvChip, 16, {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.DisplayFace,
		Text = "Level 1",
		TextColor3 = T.onFill,
		ZIndex = z + 2,
	})
	local track = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 122, 0.5, 0),
		Size = UDim2.new(1, -134, 0, 24),
		BackgroundColor3 = T.surface,
		ZIndex = z + 1,
	}, progress)
	Theme.round(track)
	Theme.stroke(track, T.outline, 2)
	xpFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.leaf,
		ZIndex = z + 2,
	}, track)
	Theme.round(xpFill)
	xpText = Theme.text(track, 14, {
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextColor3 = T.ink,
		ZIndex = z + 3,
	})

	-- the page of cards: two rows of five
	grid = new("Frame", {
		Name = "Grid",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, (CARD.Y + Theme.Ledge) * 2 + GAP),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, body)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD.X, CARD.Y + Theme.Ledge),
		CellPadding = UDim2.fromOffset(GAP, GAP),
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	-- paging: ‹ Levels 11–20 › and a pip per page
	local pager = new("Frame", {
		Name = "Pager",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 48 + Theme.Ledge),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, body)
	prevButton = Theme.iconButton(pager, "back", "secondary", 44, {
		Name = "Prev",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = z + 1,
	})
	prevButton.Activated:Connect(function()
		flip(-1)
	end)
	nextButton = Theme.iconButton(pager, "next", "secondary", 44, {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		ZIndex = z + 1,
	})
	nextButton.Activated:Connect(function()
		flip(1)
	end)
	pageLabel = Theme.label(pager, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 60, 0.5, -2),
		Size = UDim2.fromOffset(200, 32),
		Text = "Levels 1–10",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z + 1,
	}, 0)
	local pipRow = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, -2),
		Size = UDim2.fromOffset(PAGES * 30, 26),
		BackgroundTransparency = 1,
		ZIndex = z + 1,
	}, pager)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pipRow)
	for i = 1, PAGES do
		local pip = new("TextButton", {
			Name = "Page" .. i,
			LayoutOrder = i,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = T.surfaceSunk,
			ZIndex = z + 2,
		}, pipRow)
		Theme.round(pip)
		Theme.stroke(pip, T.outline, 2)
		pip.Activated:Connect(function()
			if i ~= page then
				page = i
				SoundController.play("UITab")
				renderPage(true)
			end
		end)
		pips[i] = pip
	end

	ShopController.onCloseAll(function()
		LevelRewardsController.open(false)
	end)
end

-- The Lv sticker on the coins chip (HUDController's Profile gui) opens the sheet and wears the dot.
local function hookSticker()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Profile", 30)
	local chip = gui and gui:WaitForChild("Chip", 10)
	if not chip then
		return
	end
	local sticker: Frame? = nil
	for _, d in chip:GetDescendants() do
		if d:IsA("TextLabel") and string.match(d.Text, "^Lv %d+") and d.Parent and d.Parent:IsA("Frame") then
			sticker = d.Parent :: Frame
			break
		end
	end
	if not sticker then
		warn("[LevelRewards] couldn't find the Lv sticker on the coins chip")
		return
	end
	local hit = new("TextButton", {
		Name = "LevelRewardsHit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 16, 1, 16),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = sticker.ZIndex + 4,
	}, sticker)
	hit.MouseEnter:Connect(function()
		Theme.pop(sticker, 1.12, Theme.Motion.Fast)
	end)
	hit.Activated:Connect(function()
		if isOpen() then
			SoundController.play("UIBack")
			LevelRewardsController.open(false)
		else
			LevelRewardsController.open(true)
		end
	end)
	-- in a match the sticker is just a sticker: clicks there go to the game
	local function sync()
		hit.Visible = inHub()
	end
	player:GetAttributeChangedSignal("Status"):Connect(sync)
	player:GetAttributeChangedSignal("Team"):Connect(sync)
	sync()
	stickerDot = Theme.dot(sticker)
	refreshDot()
end

-- The level-up card -----------------------------------------------------------------------------------

local toastGui: ScreenGui
local toastToken = 0

-- Slams in at the left edge: a sun star with the new level, LEVEL UP! on a leaf band, and what each
-- level banked. Tapping it opens the sheet (in the hub). Gone after a few seconds.
local function toast(d: any)
	toastToken += 1
	local token = toastToken
	for _, c in toastGui:GetChildren() do
		c:Destroy()
	end
	local rewards: { any } = if type(d.rewards) == "table" then d.rewards else {}
	local shown = math.min(#rewards, 3)
	local height = 104 + shown * 40 + (if #rewards > shown then 22 else 0) + 30
	local root = new("TextButton", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Theme.Space.L, 0.5, -20),
		Size = UDim2.fromOffset(330, height),
		BackgroundColor3 = T.surface,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
	}, toastGui)
	Theme.autoScale(root)
	Theme.corner(root, Theme.Radius.L)
	Theme.stroke(root, T.outline, Theme.StrokeToy)
	local band = new("Frame", {
		Name = "Band",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = T.leaf,
		ZIndex = 3,
	}, root)
	Theme.corner(band, Theme.Radius.L)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.Radius.L),
		Size = UDim2.new(1, 0, 0, Theme.Radius.L),
		BackgroundColor3 = T.leaf,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, band)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -Theme.StrokeToy),
		Size = UDim2.new(1, 0, 0, Theme.StrokeToy),
		BackgroundColor3 = T.outline,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, band)
	Theme.label(band, {
		Position = UDim2.fromOffset(104, 6),
		Size = UDim2.new(1, -116, 0, 44),
		Text = "LEVEL UP!",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, Theme.StrokeToy)
	-- the star: a turning sunburst behind a sun disc with the new level on it
	local star = new("Frame", {
		Name = "Star",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(54, 46),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = T.sun,
		Rotation = -8,
		ZIndex = 8,
	}, root)
	Theme.round(star)
	Theme.stroke(star, T.outline, Theme.StrokeToy)
	local rays = sunburst(root, 116, 6, 0.35)
	rays.Position = UDim2.fromOffset(54, 46)
	for _, ray in rays:GetChildren() do
		(ray :: Frame).BackgroundColor3 = T.sun
	end
	local num = Theme.text(star, if (d.level or 0) >= 100 then 32 else 40, {
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.DisplayFace,
		Text = tostring(d.level or level),
		TextColor3 = T.paper,
		ZIndex = 9,
	})
	Theme.textStroke(num, 3)
	-- what each level banked
	local list = new("Frame", {
		Position = UDim2.fromOffset(16, 104),
		Size = UDim2.new(1, -32, 0, shown * 40),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, root)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local title = false
	for i = 1, shown do
		local b = rewards[#rewards - shown + i] -- the newest levels
		title = title or b.kind == "Cosmetic"
		local row = Theme.well(list, {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 36),
			ZIndex = 3,
		}, Theme.Radius.S)
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(46, 32),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, row)
		local reward = PR.Rewards[b.level]
		if reward and reward.Kind ~= "Cosmetic" then
			drawIcon(holder, reward, 0.6)
		else
			Theme.glyph(holder, "star", Theme.Rarity[b.rarity or "Rare"] or T.sun, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(28, 28),
				ZIndex = 6,
			})
		end
		Theme.text(row, 15, {
			Position = UDim2.fromOffset(56, 0),
			Size = UDim2.new(1, -62, 1, 0),
			Text = ('<font color="#%s">Lv %d</font>  %s'):format(T.inkMuted:ToHex(), b.level, bankedLabel(b)),
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = T.ink,
			ZIndex = 6,
		})
	end
	if #rewards > shown then
		Theme.text(root, 13, {
			Position = UDim2.fromOffset(16, 104 + shown * 40),
			Size = UDim2.new(1, -32, 0, 20),
			Text = ("+%d more level rewards"):format(#rewards - shown),
			TextColor3 = T.inkMuted,
			ZIndex = 4,
		})
	end
	Theme.text(root, 13, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -8),
		Size = UDim2.new(1, -32, 0, 18),
		Text = if inHub() then "Tap to see every level reward" else "Tap your Lv in the hub to see them all",
		TextColor3 = T.inkMuted,
		ZIndex = 4,
	})
	root.Activated:Connect(function()
		if blocked() == nil then
			LevelRewardsController.open(true)
		end
	end)
	-- in: slide from the left with an overshoot, the star pops; out: slide back
	local reduced = Theme.settings.reducedMotion
	if not reduced then
		root.Position = UDim2.new(0, -360, 0.5, -20)
		Theme.tween(root, 0.45, { Position = UDim2.new(0, Theme.Space.L, 0.5, -20) }, Enum.EasingStyle.Back)
		Theme.pop(star, 1.8, 0.5)
	end
	SoundController.play(if title then "SpinReveal" else "UISuccess")
	if title then
		HUDController.confetti(T.sun)
	end
	task.spawn(function()
		local t0 = os.clock()
		while token == toastToken and root.Parent and os.clock() - t0 < 5 do
			if not reduced then
				rays.Rotation = ((os.clock() - t0) * 40) % 360
			end
			RunService.RenderStepped:Wait()
		end
		if token ~= toastToken or not root.Parent then
			return
		end
		Theme.tween(
			root,
			0.3,
			{ Position = UDim2.new(0, -360, 0.5, -20) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		).Completed
			:Wait()
		if token == toastToken then
			root:Destroy()
		end
	end)
end
LevelRewardsController.toast = toast

-- Lifecycle -----------------------------------------------------------------------------------------

function LevelRewardsController.init()
	buildSheet()
	toastGui = new("ScreenGui", {
		Name = "LevelUp",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
	}, player:WaitForChild("PlayerGui"))
end

function LevelRewardsController.start()
	Net.on("Profile", function(d)
		level = tonumber(d.level) or level
		xp = tonumber(d.xp) or xp
		xpNext = tonumber(d.xpNext) or xpNext
		local lr = d.levelRewards
		if type(lr) == "table" then
			paid = tonumber(lr.paid) or paid
			since = since or tonumber(lr.since)
		end
		-- a returning player's back-pay (levels passed before level rewards existed), said once
		if not backPayShown and since and paid > since then
			backPayShown = true
			task.spawn(function()
				while not tutorialDone() or player:GetAttribute("Booted") ~= true do
					task.wait(0.5)
				end
				HUDController.feed(
					("🎁 Level rewards for levels %d–%d are in! Tap your <b>Lv</b> to see them."):format(
						(since :: number) + 1,
						paid
					)
				)
			end)
		end
		refreshDot()
		if isOpen() then
			renderPage(false)
		end
	end)
	Net.on("LevelUp", function(d)
		paid = math.max(paid, tonumber(d.level) or paid)
		level = math.max(level, tonumber(d.level) or level)
		refreshDot()
		toast(d)
	end)
	player:GetAttributeChangedSignal("TutorialDone"):Connect(refreshDot)
	task.spawn(hookSticker)
	-- close when the player leaves the hub; while open, the next card's glow breathes and the
	-- milestone sunbursts turn
	RunService.RenderStepped:Connect(function()
		if not isOpen() then
			return
		end
		if blocked() then
			LevelRewardsController.open(false)
			return
		end
		if Theme.settings.reducedMotion then
			return
		end
		local t = os.clock()
		for _, c in cards do
			if c.rays.Visible then
				c.rays.Rotation = (t * (if c.isNext then 45 else 20)) % 360
			end
			if c.isNext then
				c.icon.Position = UDim2.new(0.5, 0, 0.4, math.sin(t * 3.2) * 4)
				c.glowStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * math.pi * 2 / Theme.Motion.Pulse))
			end
		end
	end)
end

return LevelRewardsController
