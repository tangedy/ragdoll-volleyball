--!strict
-- Match HUD (spec §10 "Match HUD"): team plates with player pips and jail counts, timer badge,
-- round stars, reticle with charge ring + hitmarker, cooldown keycaps, held-ball chip, kill feed,
-- big sticker banners and screen flashes. Results show as a non-blocking card (Amendment A3).
-- No shops, purchase prompts or reward pop-ups during active combat.

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
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local MS = Net.MatchState
local C = Theme.Colors

local HUDController = {}

HUDController.settings = { CameraShake = true, ReducedMotion = false }
HUDController.cinematic = false

local gui: ScreenGui
local overlay: ScreenGui -- full-screen flashes (ignores insets)
local refs: { [string]: any } = {}
local feedFrame: Frame
local pips: { Red: { Frame }, Blue: { Frame } } = { Red = {}, Blue = {} }
local stars: { Red: { TextLabel }, Blue: { TextLabel } } = { Red = {}, Blue = {} }

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function num(key: string, default: number): number
	local v = MS:GetAttribute(key)
	return if type(v) == "number" then v else default
end

-- Building ------------------------------------------------------------------------------------------

local function teamPlate(team: string, parent: Instance, x: number, anchorX: number)
	local col = Config.Teams[team].Color
	local plate = Theme.new("Frame", {
		Name = team .. "Plate",
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.new(0.5, x, 0, 6),
		Size = UDim2.fromOffset(190, 54),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, parent)
	Theme.corner(plate, 16)
	Theme.gradient(plate, Theme.lighten(col, 0.2), Theme.darken(col, 0.25))
	Theme.stroke(plate, Theme.darken(col, 0.6), 3)
	local isRed = team == "Red"
	Theme.label(plate, {
		Name = "Name",
		Size = UDim2.new(0, 70, 0, 26),
		Position = if isRed then UDim2.fromOffset(10, 4) else UDim2.new(1, -80, 0, 4),
		Text = Config.Teams[team].Name,
		TextXAlignment = if isRed then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
	})
	refs[team .. "Jail"] = Theme.label(plate, {
		Size = UDim2.new(0, 90, 0, 20),
		Position = if isRed then UDim2.new(1, -96, 0, 6) else UDim2.fromOffset(6, 6),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 230, 160),
		TextXAlignment = if isRed then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
	}, 2)
	-- player pips: filled = on court, hollow = jailed/out
	local row = Theme.new("Frame", {
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 32),
		BackgroundTransparency = 1,
	}, plate)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5),
		HorizontalAlignment = if isRed then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right,
	}, row)
	for i = 1, 6 do
		local p = Theme.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, row)
		Theme.round(p)
		Theme.stroke(p, C.Ink, 2)
		table.insert(pips[team], p)
	end
	-- round-win stars under the plate
	local starRow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.new(0.5, x + (if isRed then 8 else -8), 0, 62),
		Size = UDim2.fromOffset(60, 24),
		BackgroundTransparency = 1,
	}, parent)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 2),
		HorizontalAlignment = if isRed then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right,
	}, starRow)
	for i = 1, Config.Match.RoundsToWin do
		local s = Theme.label(starRow, {
			LayoutOrder = i,
			Size = UDim2.fromOffset(24, 24),
			Text = "★",
			TextColor3 = Color3.fromRGB(80, 70, 110),
		}, 2)
		table.insert(stars[team], s)
	end
	refs[team .. "Plate"] = plate
	refs[team .. "Stars"] = starRow
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
		BackgroundColor3 = Color3.fromRGB(255, 40, 40),
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

	-- Scoreboard
	local board = Theme.new("Frame", {
		Name = "Board",
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundTransparency = 1,
	}, gui)
	refs.board = board
	teamPlate("Red", board, -44, 1)
	teamPlate("Blue", board, 44, 0)
	local timer = Theme.new("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(84, 62),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, board)
	Theme.corner(timer, 18)
	refs.timerGrad = Theme.gradient(timer, C.PanelLight, C.Ink)
	refs.timerStroke = Theme.stroke(timer, C.Gold, 3)
	refs.timer = Theme.label(timer, {
		Size = UDim2.new(1, -10, 0, 34),
		Position = UDim2.fromOffset(5, 6),
		Text = "1:15",
	})
	refs.round = Theme.body(timer, {
		Size = UDim2.new(1, -10, 0, 14),
		Position = UDim2.fromOffset(5, 42),
		Text = "ROUND 1",
		TextColor3 = C.Gold,
	})

	-- Phase pill
	local phase = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(360, 30),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
	}, gui)
	Theme.round(phase)
	refs.phasePill = phase
	refs.phase = Theme.label(phase, {
		Size = UDim2.new(1, -24, 1, -8),
		Position = UDim2.fromOffset(12, 4),
		Text = "",
	}, 2)

	-- Banner (sticker text) + subtitle
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
	-- big 3-2-1 countdown number (server-driven)
	refs.countdown = Theme.label(gui, {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(220, 200),
		Text = "",
		TextTransparency = 1,
		ZIndex = 21,
	}, 6)
	refs.countdownGrad = Theme.gradient(refs.countdown, Color3.new(1, 1, 1), C.Gold)
	refs.hint = Theme.label(gui, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.5, 0.05),
		Text = "",
		TextTransparency = 1,
		ZIndex = 19,
	}, 3)

	-- Kill feed (top right)
	feedFrame = Theme.new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(320, 170),
		BackgroundTransparency = 1,
	}, gui)
	Theme.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, feedFrame)

	-- Profile chip (top left): coin + coins, level badge + XP bar
	local chip = Theme.panel(gui, {
		Name = "Chip",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(196, 56),
	}, 16)
	refs.chip = chip
	local coin = Theme.new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, chip)
	Theme.round(coin)
	Theme.gradient(coin, C.Gold, C.GoldDark)
	Theme.stroke(coin, Theme.darken(C.GoldDark, 0.5), 2)
	Theme.label(coin, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = "C" }, 1.5)
	refs.coins = Theme.label(chip, {
		Position = UDim2.fromOffset(40, 6),
		Size = UDim2.new(1, -100, 0, 30),
		Text = "0",
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local lvl = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(46, 32),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, chip)
	Theme.corner(lvl, 10)
	Theme.gradient(lvl, Theme.lighten(C.Purple, 0.2), C.Purple)
	Theme.stroke(lvl, C.Ink, 2)
	refs.level = Theme.label(lvl, { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), Text = "1" }, 2)
	local xpBack = Theme.new("Frame", {
		Position = UDim2.new(0, 8, 1, -14),
		Size = UDim2.new(1, -16, 0, 7),
		BackgroundColor3 = C.Ink,
	}, chip)
	Theme.round(xpBack)
	refs.xpBar = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, xpBack)
	Theme.round(refs.xpBar)
	Theme.gradient(refs.xpBar, Color3.fromRGB(140, 240, 255), Color3.fromRGB(70, 160, 255), 0)
	refs.saveWarn = Theme.body(gui, {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.fromOffset(200, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 170, 120),
		Text = "",
	})

	-- Reticle: crosshair ring + ticks, charge ring underneath, hitmarker
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
	Theme.stroke(ring, Color3.new(1, 1, 1), 2.5, 0.05)
	Theme.new("UIStroke", { Color = C.Ink, Thickness = 5, Transparency = 0.6 }, Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, ret))
	for i = 0, 3 do
		local tick = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + 0.62 * math.sin(i * math.pi / 2), 0.5 - 0.62 * math.cos(i * math.pi / 2)),
			Size = if i % 2 == 0 then UDim2.fromOffset(3, 9) else UDim2.fromOffset(9, 3),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, ret)
		Theme.stroke(tick, C.Ink, 1, 0.3)
	end
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.Gold,
	}, ret)
	Theme.round(dot)
	refs.chargeBack = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(84, 10),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Visible = false,
	}, ret)
	Theme.round(refs.chargeBack)
	Theme.stroke(refs.chargeBack, Color3.new(1, 1, 1), 1.5, 0.4)
	refs.chargeFill = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, refs.chargeBack)
	Theme.round(refs.chargeFill)
	Theme.gradient(refs.chargeFill, C.Gold, Color3.fromRGB(255, 90, 60), 0)
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
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, hm)
		Theme.stroke(bar, C.Ink, 1.5, 0.2)
	end

	-- Bottom: held ball chip + cooldown keycaps
	local held = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.fromOffset(170, 34),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
		Visible = false,
	}, gui)
	Theme.round(held)
	refs.held = held
	refs.heldSwatch = Theme.new("Frame", {
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.new(1, 0, 0),
	}, held)
	Theme.round(refs.heldSwatch)
	Theme.stroke(refs.heldSwatch, Color3.new(1, 1, 1), 2)
	refs.heldText = Theme.label(held, {
		Position = UDim2.fromOffset(36, 5),
		Size = UDim2.new(1, -44, 1, -10),
		Text = "BALL",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 2)
	local chips = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(250, 46),
		BackgroundTransparency = 1,
	}, gui)
	refs.chips = chips
	local function keycap(name: string, key: string, text: string, x: number, color: Color3)
		local f = Theme.new("Frame", {
			Name = name,
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.new(0.48, 0, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ClipsDescendants = true,
		}, chips)
		Theme.corner(f, 12)
		Theme.gradient(f, Theme.lighten(color, 0.15), Theme.darken(color, 0.25))
		Theme.stroke(f, C.Ink, 2.5)
		local kc = Theme.new("Frame", {
			Position = UDim2.fromOffset(6, 7),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
		}, f)
		Theme.corner(kc, 8)
		Theme.stroke(kc, C.Ink, 2)
		local keyLabel = Theme.body(kc, { Name = "Key", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = key, TextColor3 = C.Ink, ZIndex = 4 })
		Theme.label(f, {
			Name = "Text",
			Position = UDim2.fromOffset(44, 9),
			Size = UDim2.new(1, -50, 1, -18),
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}, 2)
		Theme.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, f)
		return f, keyLabel
	end
	refs.dodgeChip, refs.dodgeKey = keycap("Dodge", "Q", "DODGE", 0, Color3.fromRGB(70, 130, 240))
	refs.catchChip, refs.catchKey = keycap("Catch", "E", "CATCH", 0.52, Color3.fromRGB(60, 190, 100))

	-- Results card (non-blocking)
	local results = Theme.panel(gui, {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.fromOffset(380, 200),
		Visible = false,
	}, 20)
	refs.results = results
	local ribbon = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 30, 0, 54),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	}, results)
	Theme.corner(ribbon, 14)
	refs.ribbonGrad = Theme.gradient(ribbon, C.Gold, C.GoldDark)
	Theme.stroke(ribbon, C.Ink, 3)
	refs.resultTitle = Theme.label(ribbon, {
		Size = UDim2.new(1, -20, 1, -10),
		Position = UDim2.fromOffset(10, 5),
		Text = "",
		ZIndex = 4,
	}, 3)
	refs.resultCoins = Theme.label(results, {
		Position = UDim2.fromOffset(16, 34),
		Size = UDim2.new(1, -32, 0, 50),
		Text = "+0 COINS",
		TextColor3 = C.Gold,
	}, 3)
	refs.resultBody = Theme.body(results, {
		Position = UDim2.fromOffset(16, 90),
		Size = UDim2.new(1, -32, 1, -100),
		TextScaled = false,
		TextSize = 17,
		TextWrapped = true,
		TextColor3 = C.Muted,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})

	-- Lobby switches
	local lobby = Theme.new("Frame", {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -12),
		Size = UDim2.fromOffset(200, 132),
		BackgroundTransparency = 1,
	}, gui)
	Theme.new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom }, lobby)
	refs.lobby = lobby
	local function switch(name: string, initial: boolean, onChange: (boolean) -> ()): (boolean) -> ()
		local state = initial
		local row = Theme.new("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.3,
		}, lobby)
		Theme.round(row)
		Theme.label(row, {
			Position = UDim2.fromOffset(14, 9),
			Size = UDim2.new(1, -74, 0, 20),
			Text = name,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 2)
		local track = Theme.new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(48, 24),
			BackgroundColor3 = C.Green,
		}, row)
		Theme.round(track)
		Theme.stroke(track, C.Ink, 2)
		local knob = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, track)
		Theme.round(knob)
		local function render(animate: boolean)
			local pos = if state then UDim2.new(1, -21, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
			local col = if state then C.Green else Color3.fromRGB(110, 100, 140)
			if animate then
				tween(knob, 0.15, { Position = pos })
				tween(track, 0.15, { BackgroundColor3 = col })
			else
				knob.Position = pos
				track.BackgroundColor3 = col
			end
		end
		render(false)
		row.Activated:Connect(function()
			state = not state
			render(true)
			SoundController.play("UIClick")
			onChange(state)
		end)
		-- external setter so the switch can follow server state
		return function(v: boolean)
			if v ~= state then
				state = v
				render(true)
			end
		end
	end
	local setQueue = switch("Play again", true, function(v)
		Net.request(Net.Actions.SetAutoQueue, { value = v })
	end)
	player:GetAttributeChangedSignal("AutoQueue"):Connect(function()
		setQueue(player:GetAttribute("AutoQueue") ~= false)
	end)
	switch("Camera shake", true, function(v)
		HUDController.settings.CameraShake = v
		Net.request(Net.Actions.SetSetting, { key = "CameraShake", value = v })
	end)
	switch("Reduced motion", false, function(v)
		HUDController.settings.ReducedMotion = v
		Net.request(Net.Actions.SetSetting, { key = "ReducedMotion", value = v })
	end)
end

-- Public effects --------------------------------------------------------------------------------------

local bannerToken = 0
-- Big sticker text that slams in, wobbles, and fades.
function HUDController.banner(text: string, color: Color3?, duration: number?, sound: string?)
	bannerToken += 1
	local token = bannerToken
	local b = refs.banner :: TextLabel
	local col = color or Color3.new(1, 1, 1)
	b.Text = text
	refs.bannerGrad.Color = ColorSequence.new(Theme.lighten(col, 0.65), col)
	b.TextTransparency = 0
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local reduced = HUDController.settings.ReducedMotion
	if not reduced then
		refs.bannerScale.Scale = 1.8
		b.Rotation = math.random(-6, 6)
		tween(refs.bannerScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(b, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
	else
		refs.bannerScale.Scale = 1
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
	local h = refs.hint :: TextLabel
	h.Text = text
	h.TextTransparency = 0
	local stroke = h:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	Theme.pop(h, 0.8, 0.2)
	task.delay(duration or 1.5, function()
		if token == hintToken then
			tween(h, 0.3, { TextTransparency = 1 })
			if stroke then
				tween(stroke, 0.3, { Transparency = 1 })
			end
		end
	end)
end

local feedOrder = 0
-- Feed line as a pill; names can carry rich-text colors.
function HUDController.feed(text: string)
	feedOrder -= 1
	local pill = Theme.new("Frame", {
		LayoutOrder = feedOrder,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
	}, feedFrame)
	Theme.round(pill)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)
	local l = Theme.body(pill, {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 15,
		RichText = true,
		TextColor3 = Color3.new(1, 1, 1),
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
	Theme.pop(pill, 0.7, 0.25)
	task.delay(5, function()
		if pill.Parent then
			tween(pill, 0.4, { BackgroundTransparency = 1 })
			tween(l, 0.4, { TextTransparency = 1 })
			task.delay(0.45, function()
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

-- "+25" coin reward under the banner: bounces in, then flies into the coin counter.
function HUDController.coinPop(amount: number)
	local reduced = HUDController.settings.ReducedMotion
	local holder = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(190, 64),
		BackgroundTransparency = 1,
		ZIndex = 22,
	}, gui)
	local coin = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 22,
	}, holder)
	Theme.round(coin)
	Theme.gradient(coin, C.Gold, C.GoldDark)
	Theme.stroke(coin, Theme.darken(C.GoldDark, 0.5), 3)
	Theme.label(coin, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = "C", ZIndex = 23 }, 2)
	local text = Theme.label(holder, {
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.new(1, -64, 1, 0),
		Text = ("+%d"):format(amount),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
	}, 4)
	Theme.gradient(text, Color3.fromRGB(255, 250, 200), C.Gold)
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
		-- fly to the coin counter (top-left chip) and shrink away
		local target = refs.chip.AbsolutePosition + Vector2.new(20, 20) - gui.AbsolutePosition
		local tw = tween(holder, 0.45, {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(60, 20),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(text, 0.45, { TextTransparency = 1 })
		tw.Completed:Once(function()
			holder:Destroy()
			Theme.pop(refs.chip, 1.2, 0.3)
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

-- Finisher cutscenes hide gameplay UI (the banner stays).
local CINEMATIC_HIDE = { "MobileControls", "Tutorial", "Reticle", "Spectator" }
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
		if child:IsA("GuiObject") and child ~= refs.banner then
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

local function showResults(data: any, persist: boolean?)
	local r = refs.results :: Frame
	local title = if data.aborted
		then "MATCH OVER"
		elseif data.won and data.coins > 0 then string.upper(data.tier) .. "!"
		elseif data.won then "YOU WIN!"
		elseif data.winner then "GOOD GAME!"
		else "DRAW!"
	refs.resultTitle.Text = title
	local top, bottom = C.Gold, C.GoldDark
	if not data.won then
		top, bottom = Color3.fromRGB(150, 140, 190), Color3.fromRGB(90, 80, 130)
	end
	refs.ribbonGrad.Color = ColorSequence.new(top, bottom)
	-- the summary is just the title, the coins and the three combat stats
	local lines = {
		("Hits %d   ·   Catches %d   ·   Knockouts %d"):format(data.stats.hits, data.stats.catches, data.stats.knockouts),
	}
	refs.resultBody.Text = table.concat(lines, "\n")
	r.Size = UDim2.fromOffset(380, 124)
	r.Visible = true
	Theme.pop(r, 0.5, 0.4)
	-- count the coins up
	local target = data.coins
	task.spawn(function()
		local t0 = os.clock()
		local dur = 0.8
		while os.clock() - t0 < dur do
			local a = (os.clock() - t0) / dur
			refs.resultCoins.Text = ("+%d COINS"):format(math.floor(target * (1 - (1 - a) ^ 3)))
			task.wait()
		end
		refs.resultCoins.Text = ("+%d COINS"):format(target)
	end)
	SoundController.play(if data.won then "Purchase" else "UIOpen")
	if not persist then
		task.delay(Config.Match.ResultsOverlay + 0.6, function()
			r.Visible = false
		end)
	end
end
HUDController.showResults = showResults

function HUDController.hideResults()
	refs.results.Visible = false
end

-- Per-frame update ------------------------------------------------------------------------------------

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function update()
	if HUDController.cinematic then
		return
	end
	local state = MS:GetAttribute("State") or "WaitingForPlayers"
	local endsAt = num("PhaseEndsAt", 0)
	local left = endsAt - Workspace:GetServerTimeNow()
	local inMatch = (player:GetAttribute("Team") or "") ~= ""
	local status = player:GetAttribute("Status")
	local live = state == "RoundActive" or state == "RoundCountdown" or state == "RoundResolution" or state == "Finisher"
	refs.board.Visible = live

	if live then
		local teamSize = num("TeamSize", 3)
		for _, team in { "Red", "Blue" } do
			local active = num(team .. "Active", 0)
			local jailed = num(team .. "Jail", 0)
			for i, p in pips[team] do
				p.Visible = i <= teamSize
				if i <= active then
					p.BackgroundColor3 = Color3.new(1, 1, 1)
					p.BackgroundTransparency = 0
				elseif i <= active + jailed then
					p.BackgroundColor3 = Color3.fromRGB(255, 220, 140)
					p.BackgroundTransparency = 0.55
				else
					p.BackgroundColor3 = C.Ink
					p.BackgroundTransparency = 0.6
				end
			end
			refs[team .. "Jail"].Text = if jailed > 0 then ("%d IN JAIL"):format(jailed) else ""
			local wins = num(team .. "Wins", 0)
			for i, s in stars[team] do
				s.TextColor3 = if i <= wins then C.Gold else Color3.fromRGB(80, 70, 110)
			end
		end
		refs.round.Text = ("ROUND %d"):format(num("Round", 1))
		if MS:GetAttribute("Overtime") and state == "RoundActive" then
			refs.timer.Text = "SUDDEN\nDEATH"
			refs.timer.TextColor3 = Color3.fromRGB(255, 220, 220)
			refs.timerStroke.Color = Color3.fromRGB(255, 60, 60)
			refs.timerGrad.Color = ColorSequence.new(Color3.fromRGB(220, 50, 50), Color3.fromRGB(110, 10, 30))
			local pulse = 1 + 0.06 * math.sin(os.clock() * 10)
			local sc = refs.timer.Parent:FindFirstChildOfClass("UIScale") or Theme.new("UIScale", nil, refs.timer.Parent)
			sc.Scale = if HUDController.settings.ReducedMotion then 1 else pulse
		else
			refs.timer.Text = if endsAt > 0 then fmtTime(left) else "--"
			refs.timer.TextColor3 = if left < 10 and state == "RoundActive" then Color3.fromRGB(255, 120, 100) else Color3.new(1, 1, 1)
			refs.timerStroke.Color = C.Gold
			refs.timerGrad.Color = ColorSequence.new(C.PanelLight, C.Ink)
		end
	end

	local phase = ""
	if state == "WaitingForPlayers" then
		phase = "Getting a match ready..."
	elseif state == "Intermission" then
		phase = if player:GetAttribute("AutoQueue") == false
			then "Play again is OFF"
			else ("Next match in %d"):format(math.max(0, math.ceil(left)))
	elseif state == "RoundCountdown" and inMatch then
		phase = "Get ready!"
	elseif not inMatch and live then
		phase = "Match in progress · you join next round"
	elseif status == "Spectating" then
		phase = "Next round soon"
	elseif status == "Jailed" then
		phase = "JAIL: hit an enemy to get back in!"
	end
	refs.phase.Text = phase
	refs.phasePill.Visible = phase ~= ""
	refs.lobby.Visible = not live or not inMatch

	-- reticle + charge
	local holding = AimController.holding()
	local ret = refs.reticle :: Frame
	ret.Visible = holding or refs.hitmarker.Visible
	if ret.Visible then
		local sp = AimController.screenPoint()
		ret.Position = UDim2.fromOffset(sp.X, sp.Y)
	end
	refs.chargeBack.Visible = AimController.charging
	refs.chargeFill.Size = UDim2.fromScale(AimController.chargeFraction(), 1)

	-- held ball
	local heldType = player:GetAttribute("HeldBall")
	if type(heldType) == "string" and heldType ~= "" then
		local def = BallDefinitions.get(heldType)
		refs.held.Visible = true
		refs.heldSwatch.BackgroundColor3 = def.Color
		refs.heldText.Text = if heldType == "Standard" then "BALL" else def.DisplayName
		refs.heldText.TextColor3 = if heldType == "Standard" then Color3.new(1, 1, 1) else Theme.lighten(def.Color, 0.3)
	else
		refs.held.Visible = false
	end

	-- cooldown keycaps
	refs.chips.Visible = AimController.lastInput ~= "Touch"
	local t = Workspace:GetServerTimeNow()
	local function fill(chip: Frame, readyAt: any, duration: number)
		local frac = if type(readyAt) == "number" then math.clamp((readyAt - t) / duration, 0, 1) else 0
		(chip:FindFirstChild("Fill") :: Frame).Size = UDim2.fromScale(frac, 1)
	end
	fill(refs.dodgeChip, player:GetAttribute("DodgeReadyAt"), Config.Player.DodgeCooldown)
	fill(refs.catchChip, player:GetAttribute("CatchReadyAt"), Config.Player.CatchCooldown)
	local gamepad = AimController.lastInput == "Gamepad"
	refs.dodgeKey.Text = if gamepad then "X" else "Q"
	refs.catchKey.Text = if gamepad then "LB" else "E"
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
		refs.coins.Text = tostring(coins)
		if lastCoins and coins ~= lastCoins then
			Theme.pop(refs.chip, 1.15, 0.3)
		end
		lastCoins = coins
		refs.level.Text = tostring(d.level)
		tween(refs.xpBar, 0.4, { Size = UDim2.fromScale(math.clamp(d.xp / math.max(d.xpNext, 1), 0, 1), 1) })
		refs.saveWarn.Text = if d.persistent then "" else "Progress not saving"
	end)
	RunService.RenderStepped:Connect(update)
end

return HUDController
