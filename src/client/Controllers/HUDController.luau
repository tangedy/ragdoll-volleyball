--!strict
-- Match HUD (spec §10 "Match HUD"): team plates with player pips and jail counts, timer pill, round
-- stars, reticle with charge bar + hitmarker, controller-hint legends with cooldowns, held-ball pill,
-- kill feed, big sticker banners and screen flashes. Results show as a non-blocking card (Amendment
-- A3). No shops, purchase prompts or reward pop-ups during active combat.
--
-- Built from the Toybox Island kit in Theme: chrome is quiet (surface pills, ink text) and color
-- belongs to the content (team plates, coins, stickers).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallDefinitions = require(Shared.BallDefinitions)
local Net = require(script.Parent.Net)
local AimController = require(script.Parent.AimController)
local LockController = require(script.Parent.LockController)
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local MS = Net.MatchState
local T = Theme.Toybox

local HUDController = {}

HUDController.settings = { CameraShake = true, ReducedMotion = false }
HUDController.cinematic = false

local gui: ScreenGui
local overlay: ScreenGui -- full-screen flashes (ignores insets)
local refs: { [string]: any } = {}
local feedFrame: Frame
local pips: { Red: { Frame }, Blue: { Frame } } = { Red = {}, Blue = {} }
local stars: { Red: { Frame }, Blue: { Frame } } = { Red = {}, Blue = {} }
local queueSetters: { (boolean) -> () } = {}

local function tween(
	inst: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function num(key: string, default: number): number
	local v = MS:GetAttribute(key)
	return if type(v) == "number" then v else default
end

-- Comfort settings: one place that applies a switch (HUD, the UI kit, and the server's copy).
function HUDController.applySetting(key: string, value: boolean)
	if key == "PlayAgain" then
		Net.request(Net.Actions.SetAutoQueue, { value = value })
		return
	end
	HUDController.settings[key] = value
	if key == "ReducedMotion" then
		Theme.settings.reducedMotion = value
	end
	Net.request(Net.Actions.SetSetting, { key = key, value = value })
end

-- Register a "Play again" toggle setter so every copy follows the server's AutoQueue.
function HUDController.followQueue(setter: (boolean) -> ())
	table.insert(queueSetters, setter)
	setter(player:GetAttribute("AutoQueue") ~= false)
end

-- Building ------------------------------------------------------------------------------------------

local PLATE = Vector2.new(164, 92) -- width follows the team size (see update)
local FACE = 40 -- headshot size

local function teamPlate(team: string, parent: Instance, x: number, anchorX: number)
	local col = Config.Teams[team].Color
	local onCol = Theme.textOn(col)
	local isRed = team == "Red"
	local plate = Theme.new("Frame", {
		Name = team .. "Plate",
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.new(0.5, x, 0, 6),
		Size = UDim2.fromOffset(PLATE.X, PLATE.Y),
		BackgroundColor3 = col,
	}, parent)
	Theme.corner(plate, 26)
	Theme.stroke(plate, T.outline, Theme.StrokeToy)
	Theme.label(plate, {
		Name = "Name",
		Size = UDim2.fromOffset(110, 30),
		Position = if isRed then UDim2.fromOffset(16, 6) else UDim2.new(1, -126, 0, 6),
		Text = Config.Teams[team].Name,
		TextColor3 = onCol,
		TextXAlignment = if isRed then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
	}, 0)
	-- player headshots: sun ring = on court, greyed = in jail, gone = out of the round
	local row = Theme.new("Frame", {
		Size = UDim2.new(1, -32, 0, FACE),
		Position = UDim2.fromOffset(16, 42),
		BackgroundTransparency = 1,
	}, plate)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = if isRed then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i = 1, 6 do
		local p = Theme.new("Frame", {
			Name = "Player" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(FACE, FACE),
			BackgroundColor3 = T.paper,
		}, row)
		Theme.round(p)
		Theme.stroke(p, T.outline, 2.5).Name = "Ring"
		Theme.round(Theme.new("ImageLabel", {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "",
		}, p))
		-- the grey wash over a player who's out
		Theme.round(Theme.new("Frame", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(128, 128, 128),
			BackgroundTransparency = 0.25,
			Visible = false,
			ZIndex = 2,
		}, p))
		table.insert(pips[team], p)
	end
	-- round-win stars under the plate
	local starRow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.new(0.5, x + (if isRed then -12 else 12), 0, PLATE.Y + 14),
		Size = UDim2.fromOffset(80, 26),
		BackgroundTransparency = 1,
	}, parent)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = if isRed then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
	}, starRow)
	for i = 1, Config.Match.RoundsToWin do
		local s = Theme.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = T.surfaceSunk,
		}, starRow)
		Theme.round(s)
		Theme.stroke(s, T.outline, 2)
		Theme.glyph(s, "star", T.line, {
			Name = "Star",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.7, 0.7),
		})
		table.insert(stars[team], s)
	end
	refs[team .. "Plate"] = plate
	refs[team .. "Stars"] = starRow
end

-- One team's players for the scoreboard: from the server's roster string ("id|status;..."), or,
-- before that arrives, faceless entries built from the counts.
local function rosterOf(team: string, size: number, active: number, jailed: number): { { id: number, status: string } }
	local list: { { id: number, status: string } } = {}
	local raw = MS:GetAttribute(team .. "Roster")
	if type(raw) == "string" and raw ~= "" then
		for id, status in string.gmatch(raw, "(-?%d+)|([^;]*)") do
			table.insert(list, { id = tonumber(id) or 0, status = status or "" })
		end
		return list
	end
	for i = 1, size do
		local status = if i <= active then "Active" elseif i <= active + jailed then "Jailed" else "Out"
		table.insert(list, { id = 0, status = status })
	end
	return list
end

local function build()
	gui = Theme.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))
	overlay = Theme.new("ScreenGui", {
		Name = "Overlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 3,
	}, player:WaitForChild("PlayerGui"))
	refs.flash = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, overlay)
	-- red-edged vignette for when you get hit
	refs.vignette = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.joyRed,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, overlay)
	Theme.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, 1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, refs.vignette)

	-- Scoreboard: two team plates either side of the timer
	local board = Theme.new("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(2 * PLATE.X + 2 * 64, PLATE.Y + 46),
		BackgroundTransparency = 1,
	}, gui)
	refs.board = board
	Theme.autoScale(board)
	teamPlate("Red", board, -64, 1)
	teamPlate("Blue", board, 64, 0)
	local timer = Theme.new("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(116, PLATE.Y),
		BackgroundColor3 = T.surface,
	}, board)
	Theme.corner(timer, 26)
	refs.timerStroke = Theme.stroke(timer, T.outline, Theme.StrokeToy)
	refs.timerFace = timer
	refs.timer = Theme.label(timer, {
		Size = UDim2.new(1, -16, 0, 44),
		Position = UDim2.fromOffset(8, 10),
		Text = "1:15",
	}, 0)
	refs.round = Theme.text(timer, 15, {
		Size = UDim2.new(1, -10, 0, 18),
		Position = UDim2.fromOffset(5, 60),
		FontFace = Theme.TextFace,
		Text = "Round 1",
		TextColor3 = T.inkMuted,
	})

	-- Phase line: a quiet surface pill under the scoreboard
	local phase = Theme.pill(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
	})
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, phase)
	Theme.autoScale(phase)
	refs.phasePill = phase
	refs.phase = Theme.text(phase, 17, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = "",
	})

	-- Banner (sticker text): fill-colored display type in a thick toy outline
	refs.banner = Theme.label(gui, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.75, 0.12),
		Text = "",
		TextTransparency = 1,
		ZIndex = 20,
	}, 5)
	refs.bannerGrad = Theme.new("UIGradient", { Rotation = 90 }, refs.banner)
	refs.bannerScale = Theme.new("UIScale", nil, refs.banner)
	-- big 3-2-1 countdown number (server-driven): sun numerals in the toy outline
	refs.countdown = Theme.label(gui, {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(220, 200),
		Text = "",
		TextColor3 = T.sun,
		TextTransparency = 1,
		ZIndex = 21,
	}, 6)
	-- Hint: a bubble (surface pill, select-colored type) like a tile's title bubble
	local hint = Theme.pill(gui, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 19,
	})
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, hint)
	Theme.autoScale(hint)
	refs.hintPill = hint
	refs.hint = Theme.text(hint, 22, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = Theme.DisplayFace,
		Text = "",
		TextColor3 = T.select,
		ZIndex = 20,
	})

	-- Kill feed (top right): surface pills
	feedFrame = Theme.new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Space.M, 0, Theme.Space.S),
		Size = UDim2.fromOffset(340, 180),
		BackgroundTransparency = 1,
	}, gui)
	Theme.autoScale(feedFrame, 0.95)
	Theme.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, feedFrame)

	-- Profile card (bottom left): coin balance, level sticker + XP track. It has its own gui that
	-- ignores the device safe area, so it sits right in the corner: notches only cut into the middle
	-- of a phone's side edges in landscape, never the bottom corners.
	local profileGui = Theme.new("ScreenGui", {
		Name = "Profile",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 4,
	}, player:WaitForChild("PlayerGui"))
	local chip = Theme.panel(profileGui, {
		Name = "Chip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.Space.L, 1, -Theme.Space.M),
		Size = UDim2.fromOffset(260, 84),
	}, Theme.Radius.L)
	refs.chip = chip
	Theme.autoScale(chip, 0.9)
	Theme.coin(chip, 42, { Position = UDim2.fromOffset(16, 12) })
	refs.coins = Theme.label(chip, {
		Position = UDim2.fromOffset(68, 12),
		Size = UDim2.new(1, -150, 0, 42),
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 0)
	local lvl = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(66, 34),
		BackgroundColor3 = T.sky,
	}, chip)
	Theme.round(lvl)
	Theme.stroke(lvl, T.outline, Theme.StrokeToy)
	refs.level = Theme.text(lvl, 16, {
		Size = UDim2.fromScale(1, 1),
		Text = "Lv 1",
		TextColor3 = T.onFill,
	})
	local xpBack = Theme.new("Frame", {
		Position = UDim2.new(0, 16, 1, -22),
		Size = UDim2.new(1, -32, 0, 10),
		BackgroundColor3 = T.surfaceSunk,
	}, chip)
	Theme.round(xpBack)
	refs.xpBar = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.sky,
	}, xpBack)
	Theme.round(refs.xpBar)
	refs.saveWarn = Theme.body(gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.Space.L + 4, 1, -112),
		Size = UDim2.fromOffset(220, 16),
		FontFace = Theme.TextFace,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.danger,
		Text = "",
	})

	-- Reticle: crosshair ring + ticks, hitmarker
	local reticleGui = Theme.new("ScreenGui", {
		Name = "Reticle",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 6,
	}, player:WaitForChild("PlayerGui"))
	local ret = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Visible = false,
	}, reticleGui)
	refs.reticle = ret
	local ring = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, ret)
	Theme.round(ring)
	Theme.stroke(ring, T.paper, 2.5)
	Theme.new(
		"UIStroke",
		{ Color = T.outline, Thickness = 5, Transparency = 0.5 },
		Theme.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 0,
		}, ret)
	)
	for i = 0, 3 do
		local tick = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.62 * math.sin(i * math.pi / 2), 0.5 - 0.62 * math.cos(i * math.pi / 2)),
			Size = if i % 2 == 0 then UDim2.fromOffset(3, 9) else UDim2.fromOffset(9, 3),
			BackgroundColor3 = T.paper,
			BorderSizePixel = 0,
		}, ret)
		Theme.stroke(tick, T.outline, 1, 0.3)
	end
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = T.sun,
	}, ret)
	Theme.round(dot)
	local hm = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		Rotation = 45,
		Visible = false,
	}, ret)
	refs.hitmarker = hm
	for _, sz in { UDim2.fromOffset(4, 46), UDim2.fromOffset(46, 4) } do
		local bar = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = sz,
			BackgroundColor3 = T.paper,
			BorderSizePixel = 0,
		}, hm)
		Theme.stroke(bar, T.outline, 1.5, 0.2)
	end

	-- Held ball: a pill with the ball's swatch, bottom centre (just above the legends)
	local held = Theme.pill(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L - 46 - Theme.Space.M),
		Size = UDim2.fromOffset(180, 42),
		Visible = false,
	})
	Theme.autoScale(held)
	refs.held = held
	refs.heldSwatch = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Color3.new(1, 0, 0),
	}, held)
	Theme.round(refs.heldSwatch)
	Theme.stroke(refs.heldSwatch, T.outline, 2.5)
	refs.heldText = Theme.text(held, 17, {
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -54, 1, 0),
		Text = "Ball",
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Bottom centre: controller legends (with cooldowns)
	local legends = Theme.new("Frame", {
		Name = "Legends",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.fromOffset(3 * 144 + 2 * Theme.Space.S, 46),
		BackgroundTransparency = 1,
	}, gui)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Space.S),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, legends)
	Theme.autoScale(legends, 0.95)
	refs.chips = legends
	refs.dodgeChip, refs.dodgeKey = Theme.legend(legends, "Q", "Dodge", { LayoutOrder = 1 }, T.joyRed)
	refs.catchChip, refs.catchKey = Theme.legend(legends, "E", "Catch", { LayoutOrder = 2 }, T.joyBlue)
	-- camera lock: shows the current mode; Shift (R3) or a click cycles it
	local lockChip, lockKey, lockCaption = Theme.legend(legends, "Shift", "Free", { LayoutOrder = 3 }, T.sun)
	lockKey.TextSize = 10
	refs.lockKey, refs.lockCaption = lockKey, lockCaption
	Theme.new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = lockChip.ZIndex + 4,
	}, lockChip).Activated
		:Connect(function()
			LockController.cycle()
		end)
	-- Bottom right, in the hub: the Play again toggle
	local corner = Theme.new("Frame", {
		Name = "Corner",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.Space.L, 1, -Theme.Space.L),
		Size = UDim2.fromOffset(200, 48),
		BackgroundTransparency = 1,
	}, gui)
	refs.corner = corner
	Theme.autoScale(corner, 0.95)
	local playAgain = Theme.pill(corner, {
		Name = "PlayAgain",
		Size = UDim2.fromOffset(200, 48),
	})
	Theme.text(playAgain, 17, {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -90, 1, 0),
		Text = "Play again",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local _, setQueue = Theme.toggle(playAgain, true, function(v)
		HUDController.applySetting("PlayAgain", v)
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0) })
	HUDController.followQueue(setQueue)
	refs.playAgain = playAgain

	-- Results card (non-blocking): title + tier sticker, coins counting up, three stat wells, level
	local results = Theme.panel(gui, {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromOffset(420, 280),
		Visible = false,
	}, Theme.Radius.L)
	refs.results = results
	Theme.autoScale(results)
	refs.resultTitle = Theme.label(results, {
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.new(1, -48, 0, 36),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 0)
	refs.resultSticker = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 26),
		Size = UDim2.fromOffset(160, 22),
		BackgroundTransparency = 1,
	}, results)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, refs.resultSticker)
	local coinRow = Theme.new("Frame", {
		Position = UDim2.fromOffset(24, 64),
		Size = UDim2.new(1, -48, 0, 46),
		BackgroundTransparency = 1,
	}, results)
	Theme.coin(coinRow, 40, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	refs.resultCoins = Theme.label(coinRow, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 52, 0.5, 0),
		Size = UDim2.new(1, -52, 1, 0),
		Text = "+0",
		TextColor3 = T.sun,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 0)
	local statRow = Theme.new("Frame", {
		Position = UDim2.fromOffset(24, 122),
		Size = UDim2.new(1, -48, 0, 74),
		BackgroundTransparency = 1,
	}, results)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Space.M),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, statRow)
	local chipSize = UDim2.new(1 / 3, -Theme.Space.M * 2 / 3, 1, 0)
	refs.statHits = Theme.statChip(statRow, "Hits", T.peach, { Size = chipSize, LayoutOrder = 1 })
	refs.statCatches = Theme.statChip(statRow, "Catches", T.leaf, { Size = chipSize, LayoutOrder = 2 })
	refs.statKOs = Theme.statChip(statRow, "Knockouts", T.candy, { Size = chipSize, LayoutOrder = 3 })
	-- level + XP footer
	refs.resultLevel = Theme.text(results, 17, {
		Position = UDim2.new(0, 24, 1, -64),
		Size = UDim2.new(0.5, -24, 0, 22),
		Text = "Level 1",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	refs.resultXP = Theme.body(results, {
		Position = UDim2.new(0, 24, 1, -40),
		Size = UDim2.new(0.5, -24, 0, 16),
		FontFace = Theme.TextFace,
		Text = "+0 XP",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	refs.resultStreak = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -34),
		Size = UDim2.fromOffset(180, 24),
		BackgroundTransparency = 1,
	}, results)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, refs.resultStreak)
	-- kept for the gallery/debug text path (aborted matches etc.)
	refs.resultBody = refs.resultXP
end

-- Public effects --------------------------------------------------------------------------------------

local bannerToken = 0
-- Big sticker text that slams in, wobbles, and fades. opts.scale shrinks it (1 = full size);
-- opts.rich takes the text as rich text with its own <font color> runs.
function HUDController.banner(
	text: string,
	color: Color3?,
	duration: number?,
	sound: string?,
	opts: { scale: number?, rich: boolean? }?
)
	bannerToken += 1
	local token = bannerToken
	local b = refs.banner :: TextLabel
	local col = color or T.paper
	local size = opts and opts.scale or 1
	local rich = opts ~= nil and opts.rich == true
	b.RichText = rich
	b.Text = text
	refs.bannerGrad.Enabled = not rich
	refs.bannerGrad.Color = Theme.flat(col)
	b.TextTransparency = 0
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local reduced = HUDController.settings.ReducedMotion
	if not reduced then
		refs.bannerScale.Scale = 1.8 * size
		b.Rotation = math.random(-6, 6)
		tween(refs.bannerScale, 0.32, { Scale = size }, Enum.EasingStyle.Back)
		tween(b, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
	else
		refs.bannerScale.Scale = size
		b.Rotation = 0
	end
	SoundController.play(sound or "Banner")
	task.delay(duration or 1.6, function()
		if token == bannerToken then
			tween(b, 0.3, { TextTransparency = 1 })
			if stroke then
				tween(stroke, 0.3, { Transparency = 1 })
			end
		end
	end)
end

local hintToken = 0
function HUDController.hint(text: string, duration: number?)
	hintToken += 1
	local token = hintToken
	local pill = refs.hintPill :: Frame
	refs.hint.Text = text
	pill.Visible = text ~= ""
	if text == "" then
		return
	end
	Theme.pop(pill, 0.6, Theme.Motion.Slow)
	task.delay(duration or 1.5, function()
		if token == hintToken then
			pill.Visible = false
		end
	end)
end

local feedOrder = 0
-- Feed line as a surface pill; names can carry rich-text colors.
function HUDController.feed(text: string)
	feedOrder -= 1
	local pill = Theme.pill(feedFrame, {
		LayoutOrder = feedOrder,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, pill)
	local l = Theme.text(pill, 15, {
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Theme.BodyFace,
		RichText = true,
		Text = text,
	})
	-- keep at most 5
	local items = {}
	for _, c in feedFrame:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		return (a :: Frame).LayoutOrder > (b :: Frame).LayoutOrder
	end)
	while #items > 5 do
		(table.remove(items, 1) :: Frame):Destroy()
	end
	Theme.pop(pill, 0.6, Theme.Motion.Slow)
	task.delay(5, function()
		if pill.Parent then
			tween(pill, 0.3, { BackgroundTransparency = 1 })
			tween(l, 0.3, { TextTransparency = 1 })
			task.delay(0.35, function()
				pill:Destroy()
			end)
		end
	end)
end

-- Full-screen flash (eliminations); respects reduced motion with a much softer flash.
function HUDController.flash(color: Color3, intensity: number, duration: number)
	local f = refs.flash :: Frame
	local reduced = HUDController.settings.ReducedMotion
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (if reduced then intensity * 0.3 else intensity)
	tween(f, duration, { BackgroundTransparency = 1 })
end

function HUDController.vignette(intensity: number, duration: number)
	local v = refs.vignette :: Frame
	v.BackgroundTransparency = 1 - intensity
	tween(v, duration, { BackgroundTransparency = 1 })
end

-- "+25" coin reward under the banner: pops in, then flies into the coin counter.
function HUDController.coinPop(amount: number)
	local reduced = HUDController.settings.ReducedMotion
	local holder = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(190, 64),
		BackgroundTransparency = 1,
		ZIndex = 22,
	}, gui)
	local coin = Theme.coin(holder, 52, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		ZIndex = 22,
	})
	local text = Theme.label(holder, {
		Position = UDim2.fromOffset(66, 0),
		Size = UDim2.new(1, -66, 1, 0),
		Text = ("+%d"):format(amount),
		TextColor3 = T.sun,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, 4)
	SoundController.play("CoinGain")
	if reduced then
		task.delay(1.2, function()
			holder:Destroy()
		end)
		return
	end
	Theme.pop(holder, 0.2, 0.45)
	-- coin spins while it hangs there
	tween(coin, 0.6, { Rotation = 360 }, Enum.EasingStyle.Back)
	task.delay(0.9, function()
		-- fly to the coin counter (the profile card) and shrink away
		local target = refs.chip.AbsolutePosition + Vector2.new(20, 20) - gui.AbsolutePosition
		local tw = tween(holder, 0.45, {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(60, 20),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(text, 0.45, { TextTransparency = 1 })
		tw.Completed:Once(function()
			holder:Destroy()
			Theme.pop(refs.chip, 1.12, 0.3)
		end)
	end)
end

function HUDController.hitmarker()
	local hm = refs.hitmarker :: Frame
	hm.Visible = true
	local scale = hm:FindFirstChildOfClass("UIScale") or Theme.new("UIScale", nil, hm)
	scale.Scale = 1.4
	tween(scale, 0.15, { Scale = 0.8 })
	task.delay(0.18, function()
		hm.Visible = false
	end)
end

-- Finisher cutscenes hide all gameplay UI, banner included (finishers play without text).
local CINEMATIC_HIDE = { "MobileControls", "Tutorial", "Reticle", "Spectator", "Profile" }
function HUDController.setCinematic(on: boolean)
	local pg = player:FindFirstChild("PlayerGui")
	for _, name in CINEMATIC_HIDE do
		local g = pg and pg:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			if on then
				g:SetAttribute("WasEnabled", g.Enabled)
				g.Enabled = false
			elseif g:GetAttribute("WasEnabled") ~= nil then
				g.Enabled = g:GetAttribute("WasEnabled") :: boolean
				g:SetAttribute("WasEnabled", nil)
			end
		end
	end
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			if on then
				child:SetAttribute("WasVisible", child.Visible)
				child.Visible = false
			elseif child:GetAttribute("WasVisible") ~= nil then
				child.Visible = child:GetAttribute("WasVisible") :: boolean
				child:SetAttribute("WasVisible", nil)
			end
		end
	end
	HUDController.cinematic = on
end

-- Results card -------------------------------------------------------------------------------------

local resultsToken = 0
local function showResults(data: any, persist: boolean?)
	resultsToken += 1
	local token = resultsToken
	local r = refs.results :: Frame
	refs.resultTitle.Text = if data.aborted
		then "Match over"
		elseif data.won then "You win!"
		elseif data.winner then "Good game!"
		else "Draw!"
	for _, s in refs.resultSticker:GetChildren() do
		if s:IsA("Frame") then
			s:Destroy()
		end
	end
	if data.won and data.coins > 0 and data.tier then
		Theme.sticker(refs.resultSticker, tostring(data.tier), T.sun, { Size = UDim2.fromOffset(0, 22) })
	elseif data.aborted then
		Theme.sticker(refs.resultSticker, "Aborted", T.sky, { Size = UDim2.fromOffset(0, 22) })
	end
	local stats = data.stats or { hits = 0, catches = 0, knockouts = 0 }
	refs.statHits.Text = tostring(stats.hits or 0)
	refs.statCatches.Text = tostring(stats.catches or 0)
	refs.statKOs.Text = tostring(stats.knockouts or 0)
	refs.resultLevel.Text = if data.leveledUp
		then ("Level up! You're level %d"):format(data.level or 1)
		else ("Level %d"):format(data.level or 1)
	refs.resultLevel.TextColor3 = if data.leveledUp then T.success else T.ink
	refs.resultXP.Text = ("+%d XP"):format(data.xp or 0)
	for _, s in refs.resultStreak:GetChildren() do
		if s:IsA("Frame") then
			s:Destroy()
		end
	end
	local streak = tonumber(data.streak) or 0
	if streak >= Config.Progression.StreakFlameAt then
		Theme.sticker(refs.resultStreak, ("%d win streak"):format(streak), T.peach, { Size = UDim2.fromOffset(0, 24) })
	end
	Theme.show(r)
	-- count the coins up, then pop the stat wells in one after another
	local target = data.coins or 0
	task.spawn(function()
		local t0 = os.clock()
		local dur = 0.8
		while os.clock() - t0 < dur and token == resultsToken do
			local a = (os.clock() - t0) / dur
			refs.resultCoins.Text = ("+%d"):format(math.floor(target * (1 - (1 - a) ^ 3)))
			task.wait()
		end
		refs.resultCoins.Text = ("+%d"):format(target)
	end)
	local wells = {}
	for _, v in { refs.statHits, refs.statCatches, refs.statKOs } do
		table.insert(wells, (v :: TextLabel).Parent :: GuiObject)
	end
	task.delay(0.2, function()
		Theme.popIn(wells, 0.08)
	end)
	if data.leveledUp then
		task.delay(0.8, function()
			Theme.pop(refs.resultLevel, 1.4, 0.4)
		end)
	end
	SoundController.play(if data.won then "UISuccess" else "UIOpen")
	if not persist then
		task.delay(Config.Match.ResultsOverlay + 0.6, function()
			if token == resultsToken then
				Theme.hide(r)
			end
		end)
	end
end
HUDController.showResults = showResults

function HUDController.hideResults()
	Theme.hide(refs.results)
end

-- Per-frame update ------------------------------------------------------------------------------------

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local TEAMS = { "Red", "Blue" }
local boardKeys: { [string]: string } = {}

local function update()
	if HUDController.cinematic then
		return
	end
	local state = MS:GetAttribute("State") or "WaitingForPlayers"
	local endsAt = num("PhaseEndsAt", 0)
	local left = endsAt - Workspace:GetServerTimeNow()
	local inMatch = (player:GetAttribute("Team") or "") ~= ""
	local status = player:GetAttribute("Status")
	local live = state == "RoundActive"
		or state == "RoundCountdown"
		or state == "RoundResolution"
		or state == "Finisher"
	refs.board.Visible = live

	if live then
		local teamSize = num("TeamSize", 3)
		for _, team in TEAMS do
			local active = num(team .. "Active", 0)
			local jailed = num(team .. "Jail", 0)
			local wins = num(team .. "Wins", 0)
			-- the plate only changes when the roster does: skip re-parsing and re-writing ~40 GUI
			-- properties every frame
			local key = ("%s|%s|%s|%s|%s"):format(
				tostring(MS:GetAttribute(team .. "Roster")),
				teamSize,
				active,
				jailed,
				wins
			)
			if boardKeys[team] == key then
				continue
			end
			boardKeys[team] = key
			local entries = rosterOf(team, teamSize, active, jailed)
			for i, p in pips[team] do
				local e = entries[i]
				local jail = e ~= nil and (e.status == "Jailed" or e.status == "Returning")
				local onCourt = e ~= nil and e.status == "Active"
				p.Visible = jail or onCourt -- out of the round: the headshot leaves the banner
				if e and p.Visible then
					local face = p:FindFirstChild("Face") :: ImageLabel
					local ring = p:FindFirstChild("Ring") :: UIStroke
					face.Image = if e.id > 0
						then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(e.id)
						else ""
					face.ImageColor3 = if jail then Color3.fromRGB(150, 150, 150) else Color3.new(1, 1, 1)
					p.BackgroundColor3 = if jail then Color3.fromRGB(170, 170, 170) else T.paper;
					(p:FindFirstChild("Dim") :: Frame).Visible = jail
					ring.Color = if onCourt then T.sun else T.outline
					ring.Thickness = if onCourt then 3.5 else 2.5
				end
			end
			-- just wide enough for the team's headshots
			refs[team .. "Plate"].Size = UDim2.fromOffset(math.max(132, 32 + teamSize * (FACE + 6) - 6), PLATE.Y)
			for i, s in stars[team] do
				local won = i <= wins
				s.BackgroundColor3 = if won then T.sun else T.surfaceSunk
				local glyph = s:FindFirstChild("Star")
				local label = glyph and glyph:FindFirstChildOfClass("TextLabel")
				if label then
					label.TextColor3 = if won then T.onFill else T.line
				end
			end
		end
		refs.round.Text = ("Round %d"):format(num("Round", 1))
		local face = refs.timerFace :: Frame
		if MS:GetAttribute("Overtime") and state == "RoundActive" then
			refs.timer.Text = "Sudden\ndeath"
			face.BackgroundColor3 = T.joyRed
			refs.timer.TextColor3 = T.ink
			refs.round.TextColor3 = T.ink
			local pulse = 1 + 0.06 * math.sin(os.clock() * 10)
			local sc = face:FindFirstChildOfClass("UIScale") or Theme.new("UIScale", nil, face)
			sc.Scale = if HUDController.settings.ReducedMotion then 1 else pulse
		else
			refs.timer.Text = if endsAt > 0 then fmtTime(left) else "--"
			face.BackgroundColor3 = T.surface
			refs.timer.TextColor3 = if left < 10 and state == "RoundActive" then T.danger else T.ink
			refs.round.TextColor3 = T.inkMuted
		end
	end

	local phase = ""
	-- in the hub, say plainly why you aren't being put in a match (never a silent wait)
	local queueOff = player:GetAttribute("AutoQueue") == false
	local busy = player:GetAttribute("Busy") == true
	local waitReason = if queueOff
		then "Play again is off · turn it on in ⚙ to play"
		elseif busy then "Close the menu to join the next match"
		else nil
	if not inMatch and waitReason and (state == "WaitingForPlayers" or state == "Intermission" or live) then
		phase = waitReason
	elseif state == "WaitingForPlayers" then
		phase = "Getting a match ready..."
	elseif state == "Intermission" then
		phase = ("Next match in %d"):format(math.max(0, math.ceil(left)))
	elseif state == "RoundCountdown" and inMatch then
		phase = "Get ready!"
	elseif not inMatch and live then
		phase = "Match in progress · you'll join next round"
	elseif status == "Spectating" then
		phase = "Next round soon"
	elseif status == "Jailed" then
		phase = "In jail: hit an enemy to get back in!"
	end
	if state == "Intro" then
		phase = "Match starting!"
	end
	if refs.phase.Text ~= phase and phase ~= "" and refs.phasePill.Visible then
		Theme.pop(refs.phasePill, 0.9, 0.25)
	end
	refs.phase.Text = phase
	refs.phasePill.Visible = phase ~= ""
	-- stack under the scoreboard, which shrinks on small screens
	local s = Theme.uiScale()
	local below = if live then 140 * s else Theme.Space.M
	refs.phasePill.Position = UDim2.new(0.5, 0, 0, below)
	refs.results.Position = UDim2.new(0.5, 0, 0, below + (if refs.phasePill.Visible then 40 * s else 0) + 16 * s)
	local hub = not live or not inMatch
	refs.playAgain.Visible = hub
	-- on touch screens the controls own the bottom-right corner and the hub icons the bottom row:
	-- Play again moves to the top right
	local touch = AimController.lastInput == "Touch"
	refs.corner.AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 1)
	refs.corner.Position = if touch
		then UDim2.new(1, -Theme.Space.M, 0, Theme.Space.M)
		else UDim2.new(1, -Theme.Space.L, 1, -Theme.Space.L)

	-- reticle: while you hold a ball (or in Aim lock) the crosshair sits on the enemy the auto-aim
	-- is locked on to, the same player a tap throws at. With no target it follows the mouse.
	local holding = AimController.holding()
	local ret = refs.reticle :: Frame
	local model = AimController.assistModel
	local aiming = (holding or AimController.preferNearest)
		and (model ~= nil or (holding and AimController.lastInput == "Mouse"))
	ret.Visible = aiming or refs.hitmarker.Visible
	if aiming then
		local sp = AimController.screenPoint()
		-- the target's live position (no frame of lag behind the arc)
		local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local v, onScreen = Workspace.CurrentCamera:WorldToViewportPoint(root.Position)
			if onScreen then
				sp = Vector2.new(v.X, v.Y)
			end
		end
		ret.Position = UDim2.fromOffset(sp.X, sp.Y)
	end

	-- held ball
	local heldType = player:GetAttribute("HeldBall")
	if type(heldType) == "string" and heldType ~= "" then
		local def = BallDefinitions.get(heldType)
		refs.held.Visible = true
		refs.heldSwatch.BackgroundColor3 = def.Color
		refs.heldText.Text = if heldType == "Standard" then "Ball" else def.DisplayName
	else
		refs.held.Visible = false
	end

	-- legends + cooldowns (touch screens have their own buttons)
	refs.chips.Visible = AimController.lastInput ~= "Touch"
	local t = Workspace:GetServerTimeNow()
	local function fill(chip: Frame, readyAt: any, duration: number)
		local frac = if type(readyAt) == "number" then math.clamp((readyAt - t) / duration, 0, 1) else 0
		(chip:FindFirstChild("Fill") :: Frame).Size = UDim2.fromScale(frac, 1)
		local key = chip:FindFirstChild("Key") :: Frame
		key.BackgroundTransparency = if frac > 0 then 0.55 else 0
	end
	fill(refs.dodgeChip, player:GetAttribute("DodgeReadyAt"), Config.Player.DodgeCooldown)
	fill(refs.catchChip, player:GetAttribute("CatchReadyAt"), Config.Player.CatchCooldown)
	local gamepad = AimController.lastInput == "Gamepad"
	refs.dodgeKey.Text = if gamepad then "X" else "Q"
	refs.catchKey.Text = if gamepad then "LB" else "E"
	refs.lockKey.Text = if gamepad then "R3" else "Shift"
	local mode = LockController.mode
	refs.lockCaption.Text = if mode == "Shift" then "Shift lock" elseif mode == "Aim" then "Aim lock" else "Free cam"
end

function HUDController.init()
	build()
	Theme.setClickSound(function(cue)
		SoundController.play(cue)
	end)
end

function HUDController.start()
	Net.on("Banner", function(d)
		HUDController.banner(d.text, d.color, d.duration, d.sound)
	end)
	Net.on("Hint", function(d)
		HUDController.hint(d.text, d.duration)
	end)
	Net.on("Feed", function(d)
		HUDController.feed(d.text)
	end)
	Net.on("Results", showResults)
	local countdownToken = 0
	Net.on("Countdown", function(d)
		if type(d.n) ~= "number" then
			return
		end
		countdownToken += 1
		local token = countdownToken
		local l = refs.countdown :: TextLabel
		local stroke = l:FindFirstChildOfClass("UIStroke")
		l.Text = tostring(d.n)
		l.TextTransparency = 0
		if stroke then
			stroke.Transparency = 0
		end
		if not HUDController.settings.ReducedMotion then
			Theme.pop(l, 2.2, 0.35)
		end
		SoundController.play("CountdownTick")
		task.delay(0.8, function()
			if token == countdownToken then
				tween(l, 0.15, { TextTransparency = 1 })
				if stroke then
					tween(stroke, 0.15, { Transparency = 1 })
				end
			end
		end)
	end)
	Net.on("Possession", function(d)
		if d.dropped then
			HUDController.hint("Too slow! Ball dropped.", 1.5)
		elseif d.warn then
			HUDController.hint("Throw it!", 1.5)
		end
	end)
	local lastCoins: number? = nil
	Net.on("Profile", function(d)
		local coins = d.coins or 0
		local s = tostring(math.floor(coins)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
		refs.coins.Text = (s:gsub("^,", ""))
		if lastCoins and coins ~= lastCoins then
			Theme.pop(refs.chip, 1.1, 0.3)
		end
		lastCoins = coins
		refs.level.Text = ("Lv %d"):format(d.level or 1)
		tween(refs.xpBar, 0.4, { Size = UDim2.fromScale(math.clamp(d.xp / math.max(d.xpNext, 1), 0, 1), 1) })
		refs.saveWarn.Text = if d.persistent then "" else "Progress isn't saving in this server"
	end)
	player:GetAttributeChangedSignal("AutoQueue"):Connect(function()
		local v = player:GetAttribute("AutoQueue") ~= false
		for _, set in queueSetters do
			set(v)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return HUDController
