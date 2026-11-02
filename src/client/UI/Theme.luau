--!strict
-- The game's UI kit, built on the Toybox Island design system (a cozy, toy-like interface language:
-- calm grid-first layouts, a pulsing selection ring, warm rounded type, thick toy outlines, pastel
-- fills, and a little bounce on every press). Chrome uses the system's Day roles (warm white
-- surfaces, cocoa ink); fills are the same in both of its themes. Text drawn straight over the game
-- world (banners, the reticle, team pips) uses paper white with the toy outline so it reads anywhere.
--
-- Components (one per Toybox component, plus the pieces screens need):
--   button     pill Button: "primary" (leaf, once per screen), "secondary" (surface), "quiet", or a
--              fill color. Sinks into its toy ledge when pressed, pops back with an overshoot.
--   selectable the selection ring: exactly one thing wears it, it breathes, mouse hover and gamepad
--              selection both move it, and a sheet can set a "home" it returns to.
--   sheet      a floating surface with a title, an optional subtitle and a round close button;
--              opens with a short slide + fade.
--   segmented  tabs on a sunk track with a sliding outlined indicator.
--   tile       GameTile: a square tile that grows, wears the ring and shows its title in a bubble
--              when selected.
--   roundAction RoundAction: round outlined destination button with a caption and optional dot.
--   sticker    Badge: micro uppercase outlined sticker (NEW, EPIC, OWNED...).
--   dot        joy-red notification dot with a stepped wiggle.
--   toggle     switch on a sunk track; leaf when on.
--   legend     controller-hint legend: a filled key disc and a caption ("Q Dodge").
--   glyph      simple glyphs drawn on the 24px grid idea (star, sparkle, bag, gear, check...).
--   popIn      staggered pop-in (scale 0.6 -> 1, ease-pop, 40ms per item, at most 8 staggered).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Theme = {}

-- Comfort settings the kit honors (HUDController keeps these in sync with the player's switches).
Theme.settings = { reducedMotion = false }
local function reduced(): boolean
	return Theme.settings.reducedMotion
end

-- Tokens -------------------------------------------------------------------------------------------

-- Toybox Island color tokens (names as in its tokens.json; chrome values from the Day theme).
local T = {
	ground = Color3.fromHex("#f6f1e3"), -- page background
	surface = Color3.fromHex("#fffcf2"), -- cards, sheets, panels
	surfaceSunk = Color3.fromHex("#ece3cc"), -- wells and tracks inside a surface
	ink = Color3.fromHex("#4a3423"), -- primary text
	inkMuted = Color3.fromHex("#7a5a3f"), -- secondary text, captions
	line = Color3.fromHex("#e2d6bb"), -- hairline dividers
	outline = Color3.fromHex("#4a3423"), -- the toy outline around fills, text strokes
	onFill = Color3.fromHex("#4a3423"), -- text and glyphs on any pastel fill
	leaf = Color3.fromHex("#7cc47f"), -- primary fill: the one main action
	sun = Color3.fromHex("#f7cd46"), -- highlight fill: coins, rewards, "new"
	sky = Color3.fromHex("#8ed2ef"), -- calm secondary fill
	candy = Color3.fromHex("#ff9cc0"), -- playful accent, celebrations (sparingly)
	peach = Color3.fromHex("#ffb38a"), -- warm tertiary fill
	joyBlue = Color3.fromHex("#0ab9e6"),
	joyRed = Color3.fromHex("#ff4b3a"), -- notification dots, big numerals only
	select = Color3.fromHex("#0789b0"), -- the selection ring (never a fill)
	success = Color3.fromHex("#2f7d3b"),
	danger = Color3.fromHex("#c2392a"), -- error text
	shadowToy = Color3.fromHex("#cbbd9c"), -- the hard ledge under pressable things
	paper = Color3.fromHex("#fffcf2"), -- outlined text over the game world and on dark fills
	dim = Color3.fromHex("#0e1018"), -- the backdrop behind modal sheets
}
Theme.Toybox = T

-- The Halloween palette (HalloweenController swaps the UI onto it while the event runs). Same roles
-- and the same contrast as Day: light parchment surfaces, deep purple ink and outline, and the fills
-- turned pumpkin, slime, lavender, witch magenta, candy corn and violet. Roles that share a Day
-- color share a Halloween one (ink = outline = onFill, surface = paper), so the swap is one-to-one.
Theme.HalloweenToybox = {
	ground = Color3.fromHex("#f7e6d0"),
	surface = Color3.fromHex("#fff0dc"),
	surfaceSunk = Color3.fromHex("#f0d6b6"),
	ink = Color3.fromHex("#2e1a3a"),
	inkMuted = Color3.fromHex("#6e4f7e"),
	line = Color3.fromHex("#e8c9a4"),
	outline = Color3.fromHex("#2e1a3a"),
	onFill = Color3.fromHex("#2e1a3a"),
	leaf = Color3.fromHex("#8fdc5a"),
	sun = Color3.fromHex("#ff9a2e"),
	sky = Color3.fromHex("#b49cff"),
	candy = Color3.fromHex("#e07cff"),
	peach = Color3.fromHex("#ffc06b"),
	joyBlue = Color3.fromHex("#8b5cf6"),
	joyRed = Color3.fromHex("#e8343b"),
	select = Color3.fromHex("#ff7a00"),
	success = Color3.fromHex("#3f7d2a"),
	danger = Color3.fromHex("#c62f22"),
	shadowToy = Color3.fromHex("#c6997a"),
	paper = Color3.fromHex("#fff0dc"),
	dim = Color3.fromHex("#170a20"),
}

Theme.Colors = {
	-- Toybox roles
	Ground = T.ground,
	Surface = T.surface,
	SurfaceSunk = T.surfaceSunk,
	Line = T.line,
	Outline = T.outline,
	OnFill = T.onFill,
	Leaf = T.leaf,
	Sun = T.sun,
	Sky = T.sky,
	Candy = T.candy,
	Peach = T.peach,
	JoyBlue = T.joyBlue,
	JoyRed = T.joyRed,
	Select = T.select,
	Success = T.success,
	Paper = T.paper,
	-- older names, mapped onto those roles
	Ink = T.outline,
	Panel = T.surface,
	PanelLight = T.line,
	Card = T.surfaceSunk,
	Text = T.ink,
	Muted = T.inkMuted,
	Gold = T.sun,
	GoldDark = Color3.fromHex("#c99a1c"),
	Green = T.leaf,
	GreenDark = T.success,
	Danger = T.joyRed,
	DangerText = T.danger,
	Purple = T.sky,
	Red = Config.Teams.Red.Color,
	Blue = Config.Teams.Blue.Color,
}

-- The fills, in the order a grid of things should use them (repeat only after all six).
Theme.Fills = { T.sun, T.sky, T.leaf, T.candy, T.peach, T.joyBlue }

-- Display: Fredoka (titles and big moments). Body: a heavy rounded sans (Nunito, the closest Roblox
-- face to the system's M PLUS Rounded 1c): 800 for labels, lighter for running text.
Theme.Display = Enum.Font.FredokaOne
Theme.Body = Enum.Font.Nunito
local nunito = Font.fromEnum(Enum.Font.Nunito).Family
Theme.DisplayFace = Font.fromEnum(Enum.Font.FredokaOne)
Theme.LabelFace = Font.new(nunito, Enum.FontWeight.ExtraBold)
Theme.BodyFace = Font.new(nunito, Enum.FontWeight.Bold)
Theme.TextFace = Font.new(nunito, Enum.FontWeight.SemiBold)

Theme.StrokeToy = 3 -- the toy outline
Theme.StrokeSelect = 4 -- the selection ring
Theme.Ledge = 4 -- shadow-toy: the hard ledge under pressable things (1 when pressed)

-- 4px spacing scale, radius-sm/md/lg/xl, type sizes (px), and duration-quick/move/pop.
Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 }
Theme.Radius = { S = 10, M = 16, L = 24, XL = 36 }
Theme.TextSize = { Micro = 11, Caption = 13, Label = 15, Body = 16, Heading = 20, Title = 28, Display = 40 }
Theme.Motion = { Tap = 0.08, Fast = 0.15, Base = 0.24, Slow = 0.42, Pulse = 1.4 }

-- Rarity tones come from Config so the hub wheel, the shop and the spin panel always agree.
Theme.Rarity = Config.Spin.RarityColors :: { [string]: Color3 }

-- Text color for a fill: on-fill brown on light (pastel) fills, paper on dark ones (team colors).
function Theme.textOn(fill: Color3): Color3
	local lum = 0.2126 * fill.R + 0.7152 * fill.G + 0.0722 * fill.B
	return if lum > 0.5 then T.onFill else T.paper
end

-- Basics -------------------------------------------------------------------------------------------

function Theme.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local new = Theme.new

function Theme.corner(inst: Instance, radius: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.M) }, inst)
end

function Theme.round(inst: Instance): UICorner
	return new("UICorner", { CornerRadius = UDim.new(1, 0) }, inst)
end

function Theme.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color or T.outline,
		Thickness = thickness or Theme.StrokeToy,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

-- Outline around text (the "sticker" look).
function Theme.textStroke(label: Instance, thickness: number?, color: Color3?): UIStroke
	return new("UIStroke", {
		Color = color or T.outline,
		Thickness = thickness or Theme.StrokeToy,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end

-- Toybox has no gradients: this paints one flat color, the middle of the pair (older screens pass
-- light->base, base->dark or light->dark around the color they mean).
function Theme.gradient(inst: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(top:Lerp(bottom, 0.5)), Rotation = rotation or 90 }, inst)
end

-- The flat ColorSequence Theme.gradient paints, for code that recolors a gradient later.
function Theme.flat(top: Color3, bottom: Color3?): ColorSequence
	return ColorSequence.new(if bottom then top:Lerp(bottom, 0.5) else top)
end

function Theme.padding(inst: Instance, px: number, py: number?)
	new("UIPadding", {
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	}, inst)
end

function Theme.lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), t)
end

function Theme.darken(c: Color3, t: number): Color3
	return c:Lerp(T.outline, t)
end

function Theme.tween(
	inst: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end
local tween = Theme.tween

-- ease-out-soft ≈ Quint out; ease-pop ≈ Back out.
local SOFT = Enum.EasingStyle.Quint
local POP = Enum.EasingStyle.Back

local clickSound: ((string) -> ())? = nil
function Theme.setClickSound(fn: (string) -> ())
	clickSound = fn
end
local function sound(cue: string)
	if clickSound then
		clickSound(cue)
	end
end
Theme.sound = sound

-- Text ---------------------------------------------------------------------------------------------

-- Display text: Fredoka, scaled, paper white with the toy outline (the "sticker" look). Pass a
-- stroke of 0 for plain ink display text (titles on a surface).
function Theme.label(parent: Instance?, props: { [string]: any }?, strokeThickness: number?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Theme.DisplayFace,
		TextScaled = true,
		TextColor3 = if strokeThickness == 0 then T.ink else T.paper,
		Text = "",
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	if strokeThickness ~= 0 then
		Theme.textStroke(l, strokeThickness)
	end
	l.Parent = parent
	return l
end

-- Body text (rounded sans, muted by default, no outline).
function Theme.body(parent: Instance?, props: { [string]: any }?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Theme.BodyFace,
		TextScaled = true,
		TextColor3 = T.inkMuted,
		Text = "",
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

-- Fixed-size text (for auto-sized pills and stickers, where TextScaled can't be used).
function Theme.text(parent: Instance?, size: number, props: { [string]: any }?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Theme.LabelFace,
		TextScaled = false,
		TextSize = size,
		TextColor3 = T.ink,
		Text = "",
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

-- Responsive scale ------------------------------------------------------------------------------------
-- 1 on a 1280x720-or-bigger screen, down to 0.62 on small phones. Elements registered with
-- Theme.autoScale keep a UIScale in sync as the window/device changes.

-- Every element has at most one UIScale (Roblox applies only one). Its "Base" attribute is the
-- element's resting scale (set by Theme.autoScale); animations scale relative to it.
local function scaleOf(inst: GuiObject): UIScale
	local sc = inst:FindFirstChildOfClass("UIScale")
	if not sc then
		sc = new("UIScale", nil, inst)
	end
	return sc :: UIScale
end
local function baseOf(sc: UIScale): number
	local b = sc:GetAttribute("Base")
	return if type(b) == "number" then b else 1
end
Theme.scaleOf = scaleOf

local scaled: { [UIScale]: number } = {}
function Theme.uiScale(): number
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X / 1280, vp.Y / 720) * 1.08, 0.62, 1)
end

-- Is this a small (phone-sized) screen? Layouts switch to their compact arrangement.
function Theme.isCompact(): boolean
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return vp.X < 900 or vp.Y < 520
end

local floors: { [UIScale]: number } = {}
local function rescaleAll()
	local s = Theme.uiScale()
	for sc, factor in scaled do
		if sc.Parent then
			local base = math.max(s * factor, floors[sc] or 0)
			sc:SetAttribute("Base", base)
			sc.Scale = base
		else
			scaled[sc] = nil
			floors[sc] = nil
		end
	end
end

-- Keep `inst` scaled to the screen (factor lets an element shrink a bit more or less than the rest;
-- floor keeps it from shrinking below that scale on small screens, so its text stays readable).
function Theme.autoScale(inst: GuiObject, factor: number?, floor: number?): UIScale
	local sc = scaleOf(inst)
	scaled[sc] = factor or 1
	floors[sc] = floor
	sc:SetAttribute("Base", math.max(Theme.uiScale() * (factor or 1), floor or 0))
	sc.Scale = baseOf(sc)
	return sc
end

task.defer(function()
	local function watch(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleAll)
		end
		rescaleAll()
	end
	watch(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watch(workspace.CurrentCamera)
	end)
end)

-- Motion ----------------------------------------------------------------------------------------------

-- Scale-pop an element (uses/creates its UIScale).
function Theme.pop(inst: GuiObject, from: number?, duration: number?)
	local scale = scaleOf(inst)
	local base = baseOf(scale)
	if reduced() then
		scale.Scale = base
		return
	end
	scale.Scale = (from or 0.6) * base
	tween(scale, duration or Theme.Motion.Slow, { Scale = base }, POP)
end

-- Pop a group in one after another (40ms apart, at most 8 staggered; the rest land with the 8th).
function Theme.popIn(items: { GuiObject }, stagger: number?)
	for i, inst in items do
		local delay = math.min(i - 1, 7) * (stagger or 0.04)
		if delay <= 0 then
			Theme.pop(inst, 0.6)
		else
			local sc = scaleOf(inst)
			sc.Scale = if reduced() then baseOf(sc) else 0.6 * baseOf(sc)
			task.delay(delay, function()
				Theme.pop(inst, 0.6)
			end)
		end
	end
end

-- Stepped wiggle (the hand-drawn frame-by-frame touch): rotate -4, 3, 0 in hard steps, forever.
local wiggling: { [GuiObject]: boolean } = {}
function Theme.wiggle(inst: GuiObject, on: boolean?)
	if on == false then
		wiggling[inst] = nil
	else
		wiggling[inst] = true
	end
	if on == false then
		inst.Rotation = 0
	end
end
task.spawn(function()
	local frames = { -4, 3, 0, 3 }
	local i = 0
	while true do
		task.wait(0.18)
		i = i % #frames + 1
		for inst in wiggling do
			if not inst.Parent then
				wiggling[inst] = nil
			else
				inst.Rotation = if reduced() then 0 else frames[i]
			end
		end
	end
end)

-- The selection ring ----------------------------------------------------------------------------------
-- Exactly one thing wears it. A 4px select-colored outline 3px off the element, breathing a soft
-- glow once every duration-pulse. Mouse hover and gamepad selection move it (with a soft tick); when
-- nothing is hovered it rests on the current "home" (e.g. the selected shop tile).

type Ring = { frame: Frame, glow: UIStroke }
local rings: { [GuiObject]: Ring } = {}
local hovered: GuiObject? = nil
local home: GuiObject? = nil
local shownRing: Ring? = nil
local shownTarget: GuiObject? = nil
local lastMoveSound = 0

-- an empty frame used as every selectable's SelectionImageObject (hides Roblox's own highlight)
local noSelection = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })

local function onScreen(inst: GuiObject): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") then
			return (node :: any).Enabled ~= false and node:IsDescendantOf(Players.LocalPlayer)
		end
		node = node.Parent
	end
	return false
end

local function refreshRing()
	local target = hovered or home
	-- disabled buttons don't take the ring
	if target and target:IsA("GuiButton") and not target.Interactable then
		target = if target == hovered and home ~= hovered then home else nil
	end
	if target and (not target.Parent or not rings[target] or not onScreen(target)) then
		if target == hovered then
			hovered = nil
		end
		target = if home and home.Parent and rings[home] and onScreen(home) then home else nil
	end
	if target ~= shownTarget then
		if shownRing then
			shownRing.frame.Visible = false
		end
		shownTarget = target
		shownRing = if target then rings[target] else nil
		if shownRing then
			shownRing.frame.Visible = true
			if target == hovered and os.clock() - lastMoveSound > 0.05 then
				lastMoveSound = os.clock()
				sound("UIMove")
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	refreshRing()
	if shownRing then
		-- breathe: the glow grows and fades once per duration-pulse
		local b = if reduced() then 0 else (math.sin(os.clock() * math.pi * 2 / Theme.Motion.Pulse) + 1) / 2
		shownRing.glow.Thickness = 2 + 7 * b
		shownRing.glow.Transparency = 0.55 + 0.4 * (1 - b)
	end
end)

-- Edge cases get their own sounds (UX audio study): pressing a disabled button gives the dull
-- refusal instead of silence, and a d-pad press that can't move the selection (the end of a row or
-- list) gives the dull bump instead of the tick.
local NAV_KEYS = {
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadDown] = true,
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true,
}
UserInputService.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return
		end
		-- the topmost button under the press; a disabled one doesn't fire Activated, so say so here
		for _, o in pg:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y) do
			if o:IsA("GuiButton") then
				if o:GetAttribute("Disabled") == true then
					sound("UIError")
				end
				return
			end
		end
	elseif NAV_KEYS[input.KeyCode] and GuiService.SelectedObject then
		local before = GuiService.SelectedObject
		-- give the engine's own selection move a moment to land first
		task.delay(0.06, function()
			if GuiService.SelectedObject == before then
				sound("UIEdge")
			end
		end)
	end
end)

-- Make `hit` selectable; the ring draws around `around` (defaults to hit). `radius` is the
-- element's corner radius (nil = pill/round).
function Theme.selectable(hit: GuiObject, around: GuiObject?, radius: number?): Frame
	local target = around or hit
	local gap = 3 + Theme.StrokeSelect / 2
	local frame = new("Frame", {
		Name = "SelectRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, gap * 2, 1, gap * 2),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = target.ZIndex + 6,
	}, target)
	new("UICorner", { CornerRadius = if radius then UDim.new(0, radius + gap) else UDim.new(1, 0) }, frame)
	new("UIStroke", {
		Color = T.select,
		Thickness = Theme.StrokeSelect,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, frame)
	local glowFrame = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, Theme.StrokeSelect * 2, 1, Theme.StrokeSelect * 2),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex,
	}, frame)
	new("UICorner", {
		CornerRadius = if radius then UDim.new(0, radius + gap + Theme.StrokeSelect) else UDim.new(1, 0),
	}, glowFrame)
	local glow = new("UIStroke", {
		Color = T.select,
		Thickness = 4,
		Transparency = 0.7,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, glowFrame)
	rings[hit] = { frame = frame, glow = glow }
	hit.SelectionImageObject = noSelection
	hit.Selectable = true
	hit.MouseEnter:Connect(function()
		hovered = hit
	end)
	hit.MouseLeave:Connect(function()
		if hovered == hit then
			hovered = nil
		end
	end)
	hit.SelectionGained:Connect(function()
		hovered = hit
	end)
	hit.SelectionLost:Connect(function()
		if hovered == hit then
			hovered = nil
		end
	end)
	hit.Destroying:Connect(function()
		rings[hit] = nil
	end)
	return frame
end

-- Where the ring rests when nothing is hovered (nil clears it).
function Theme.setHome(target: GuiObject?)
	home = target
end

-- Move gamepad selection onto `target` (if a gamepad is in use) and make it the ring's home.
function Theme.focus(target: GuiObject)
	home = target
	hovered = nil -- a stale hover (e.g. under a card that just opened) shouldn't keep the ring
	if GuiService.SelectedObject ~= nil then
		GuiService.SelectedObject = target
	end
end

-- Pressables -----------------------------------------------------------------------------------------

-- The press: the face sinks into its ledge in duration-tap and pops back with ease-pop.
local function pressable(hit: GuiButton, face: GuiObject, ledge: GuiObject?, restY: number)
	local function sink(down: boolean)
		local y = if down then restY + Theme.Ledge - 1 else restY
		if reduced() then
			face.Position = UDim2.new(face.Position.X, UDim.new(face.Position.Y.Scale, y))
			return
		end
		tween(
			face,
			if down then Theme.Motion.Tap else Theme.Motion.Slow,
			{ Position = UDim2.new(face.Position.X, UDim.new(face.Position.Y.Scale, y)) },
			if down then Enum.EasingStyle.Quad else POP
		)
	end
	hit.MouseButton1Down:Connect(function()
		sink(true)
	end)
	hit.MouseButton1Up:Connect(function()
		sink(false)
	end)
	hit.MouseLeave:Connect(function()
		sink(false)
	end)
	hit.SelectionLost:Connect(function()
		sink(false)
	end)
	local _ = ledge
end

-- Toybox Button. `kind` is "primary" (leaf: the one action a screen is for), "secondary" (surface,
-- outlined), "quiet" (no outline or ledge), or a fill Color3 for a toned button. Labels are
-- verb-first and sentence case. Returns the TextButton (the hit area); its "Face" holds the label.
-- props.back = true makes it sound like a back/close action; props.silent = true gives it no press
-- sound (for buttons that open a sheet, which answers with its own UIOpen).
local function kindColors(kind: any): (Color3, Color3, boolean)
	if kind == "primary" then
		return T.leaf, T.onFill, true
	elseif kind == "secondary" then
		return T.surface, T.ink, true
	elseif kind == "quiet" then
		return T.surface, T.ink, false
	elseif typeof(kind) == "Color3" then
		return kind, Theme.textOn(kind), true
	end
	return T.leaf, T.onFill, true
end

function Theme.button(parent: Instance?, text: string, kind: any, props: { [string]: any }?): TextButton
	local fill, textColor, toy = kindColors(kind)
	local isBack = props ~= nil and props.back == true
	local silent = props ~= nil and props.silent == true
	local b = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 52),
	}, nil)
	if props then
		for k, v in props do
			if k ~= "back" and k ~= "silent" then
				(b :: any)[k] = v
			end
		end
	end
	local ledgeH = if toy then Theme.Ledge else 0
	local ledge = new("Frame", {
		Name = "Ledge",
		Position = UDim2.fromOffset(0, ledgeH),
		Size = UDim2.new(1, 0, 1, -ledgeH),
		BackgroundColor3 = T.shadowToy,
		BackgroundTransparency = if toy then 0 else 1,
		BorderSizePixel = 0,
		ZIndex = b.ZIndex,
	}, b)
	Theme.round(ledge)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -ledgeH),
		BackgroundColor3 = fill,
		BackgroundTransparency = if kind == "quiet" then 1 else 0,
		BorderSizePixel = 0,
		ZIndex = b.ZIndex + 1,
	}, b)
	Theme.round(face)
	if toy then
		Theme.stroke(face, T.outline, Theme.StrokeToy)
	end
	Theme.body(face, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -28, 0.5, 0),
		FontFace = Theme.LabelFace,
		Text = text,
		TextColor3 = textColor,
		ZIndex = b.ZIndex + 2,
	})
	new("UITextSizeConstraint", { MaxTextSize = 22 }, face:FindFirstChild("Label"))
	pressable(b, face, ledge, 0)
	Theme.selectable(b, face)
	if kind == "quiet" then
		b.MouseEnter:Connect(function()
			face.BackgroundColor3 = T.surfaceSunk
			face.BackgroundTransparency = 0
		end)
		b.MouseLeave:Connect(function()
			face.BackgroundTransparency = 1
		end)
	end
	b.Activated:Connect(function()
		if not silent then
			sound(if isBack then "UIBack" else "UIClick")
		end
	end)
	b:SetAttribute("Kind", if typeof(kind) == "string" then kind else "tone")
	b.Parent = parent
	return b
end

-- A round icon button (close, arrows, the settings gear): same toy press, a glyph instead of text.
function Theme.iconButton(
	parent: Instance?,
	glyphName: string,
	kind: any,
	size: number,
	props: { [string]: any }?
): TextButton
	local b = Theme.button(nil, "", kind, props)
	b.Size = UDim2.fromOffset(size, size + Theme.Ledge)
	local face = b:FindFirstChild("Face") :: Frame
	local _, textColor = kindColors(kind)
	Theme.glyph(face, glyphName, textColor, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = b.ZIndex + 2,
	})
	if props then
		for k, v in props do
			if k ~= "back" and k ~= "silent" then
				(b :: any)[k] = v
			end
		end
	end
	b.Size = UDim2.fromOffset(size, size + Theme.Ledge)
	b.Parent = parent
	return b
end

-- Recolor a button (e.g. owned -> equipped states). `kind` as in Theme.button.
function Theme.recolor(b: TextButton, kind: any)
	local fill, textColor = kindColors(kind)
	local face = b:FindFirstChild("Face") :: Frame?
	if face then
		face.BackgroundColor3 = fill
		local label = face:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextColor3 = textColor
		end
	end
end

function Theme.setText(b: GuiObject, text: string)
	local l = b:FindFirstChild("Label", true) :: TextLabel?
	if l then
		l.Text = text
	end
end

-- Disabled: 45% faded, no ledge, ignores input.
function Theme.setEnabled(b: GuiButton, on: boolean)
	b.Interactable = on
	b:SetAttribute("Disabled", not on)
	local face = b:FindFirstChild("Face") :: Frame?
	local ledge = b:FindFirstChild("Ledge") :: Frame?
	if face then
		face.BackgroundTransparency = if b:GetAttribute("Kind") == "quiet" then 1 elseif on then 0 else 0.45
		local label = face:FindFirstChild("Label") :: TextLabel?
		if label then
			label.TextTransparency = if on then 0 else 0.45
		end
		local st = face:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = if on then 0 else 0.45
		end
	end
	if ledge and b:GetAttribute("Kind") ~= "quiet" then
		ledge.BackgroundTransparency = if on then 0 else 1
	end
end

-- Glyphs ---------------------------------------------------------------------------------------------
-- Simple, neutral glyphs (round caps, solid shapes). Text glyphs for the shapes a font draws well;
-- frames for the rest (bag, gear, gift, clock, eye, tag, hand, burst, pumpkin).

local TEXT_GLYPHS = {
	star = "★",
	sparkle = "✦",
	check = "✓",
	back = "‹",
	next = "›",
	play = "▶",
	plus = "+",
	coin = "C",
}

function Theme.glyph(parent: Instance, name: string, color: Color3, props: { [string]: any }?): GuiObject
	local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24) }, nil)
	if props then
		for k, v in props do
			(holder :: any)[k] = v
		end
	end
	new("UIAspectRatioConstraint", nil, holder)
	local z = holder.ZIndex
	local textGlyph = TEXT_GLYPHS[name]
	if textGlyph then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			FontFace = if name == "coin" then Theme.DisplayFace else Theme.LabelFace,
			TextScaled = true,
			Text = textGlyph,
			TextColor3 = color,
			ZIndex = z,
		}, holder)
	elseif name == "close" then
		-- two round-capped bars crossed
		for _, r in { 45, -45 } do
			local bar = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 0.2),
				Rotation = r,
				BackgroundColor3 = color,
				ZIndex = z,
			}, holder)
			Theme.round(bar)
		end
	elseif name == "menu" then
		-- three round-capped bars stacked (the hamburger)
		for _, y in { 0.2, 0.5, 0.8 } do
			local bar = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, y),
				Size = UDim2.fromScale(0.95, 0.18),
				BackgroundColor3 = color,
				ZIndex = z,
			}, holder)
			Theme.round(bar)
		end
	elseif name == "bag" then
		-- shopping bag: a wide body with only the top of its handle loop showing
		local handle = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.02),
			Size = UDim2.fromScale(0.5, 0.46),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, holder)
		Theme.round(handle)
		new("UIStroke", { Color = color, Thickness = 2.5 }, handle)
		local body = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.96, 0.72),
			BackgroundColor3 = color,
			ZIndex = z + 1,
		}, holder)
		Theme.corner(body, 3)
	elseif name == "gear" then
		-- eight square teeth around a disc with a hole
		for i = 0, 3 do
			local tooth = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.26, 1.04),
				Rotation = i * 45,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = z,
			}, holder)
			Theme.corner(tooth, 2)
		end
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			BackgroundColor3 = color,
			ZIndex = z + 1,
		}, holder)
		Theme.round(ring)
		local hole = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.34, 0.34),
			BackgroundColor3 = T.outline,
			ZIndex = z + 2,
		}, holder)
		Theme.round(hole)
	elseif name == "gift" then
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.86, 0.62),
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.corner(box, 3)
		local lid = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.18),
			Size = UDim2.fromScale(1, 0.22),
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.corner(lid, 3)
		for _, x in { 0.36, 0.64 } do
			local bow = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(x, 0.22),
				Size = UDim2.fromScale(0.26, 0.22),
				BackgroundTransparency = 1,
				ZIndex = z,
			}, holder)
			Theme.round(bow)
			new("UIStroke", { Color = color, Thickness = 2.5 }, bow)
		end
	elseif name == "clock" then
		-- a ring with an hour hand pointing right and a minute hand pointing up
		local face = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, holder)
		Theme.round(face)
		new("UIStroke", { Color = color, Thickness = 2.5 }, face)
		for _, h in
			{
				{ anchor = Vector2.new(0.5, 1), pos = UDim2.fromScale(0.5, 0.56), size = UDim2.fromScale(0.13, 0.4) },
				{ anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(0.44, 0.5), size = UDim2.fromScale(0.3, 0.13) },
			}
		do
			local hand = new("Frame", {
				AnchorPoint = h.anchor,
				Position = h.pos,
				Size = h.size,
				BackgroundColor3 = color,
				ZIndex = z,
			}, holder)
			Theme.round(hand)
		end
	elseif name == "eye" then
		-- an eye (spectate): a wide rounded outline with a solid pupil
		local lid = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.95, 0.6),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, holder)
		Theme.round(lid)
		new("UIStroke", { Color = color, Thickness = 2.5 }, lid)
		local pupil = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.34, 0.34),
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.round(pupil)
	elseif name == "tag" then
		-- a name tag (titles): a rounded card with a punched hole and two lines of "text"
		local mark = Theme.textOn(color)
		local card = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 0.66),
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.corner(card, 4)
		local hole = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.16, 0.5),
			Size = UDim2.fromScale(0.15, 0.15),
			BackgroundColor3 = mark,
			ZIndex = z + 1,
		}, holder)
		Theme.round(hole)
		for i, w in { 0.52, 0.36 } do
			local line = new("Frame", {
				Position = UDim2.fromScale(0.32, 0.33 + (i - 1) * 0.22),
				Size = UDim2.fromScale(w, 0.11),
				BackgroundColor3 = mark,
				ZIndex = z + 1,
			}, holder)
			Theme.round(line)
		end
	elseif name == "hand" then
		-- an open, waving hand (gestures): palm, four fingers and a thumb
		local palm = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.54, 0.98),
			Size = UDim2.fromScale(0.54, 0.48),
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.corner(palm, 5)
		for i, h in { 0.4, 0.5, 0.47, 0.36 } do
			local finger = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.34 + (i - 1) * 0.135, 0.6),
				Size = UDim2.fromScale(0.13, h),
				BackgroundColor3 = color,
				ZIndex = z,
			}, holder)
			Theme.round(finger)
		end
		local thumb = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.2, 0.64),
			Size = UDim2.fromScale(0.13, 0.36),
			Rotation = -48,
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.round(thumb)
	elseif name == "burst" then
		-- an impact burst (finishers): long and short spikes round a solid core
		for i = 0, 7 do
			local spike = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.17, if i % 2 == 0 then 1.04 else 0.72),
				Rotation = i * 22.5,
				BackgroundColor3 = color,
				ZIndex = z,
			}, holder)
			Theme.round(spike)
		end
		local core = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.52, 0.52),
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.round(core)
	elseif name == "pumpkin" then
		-- a pumpkin (Halloween bundles): three overlapping lobes under a short leaning stem
		for _, lobe in { { 0.3, 0.6 }, { 0.7, 0.6 }, { 0.5, 0.68 } } do
			local l = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(lobe[1], 1),
				Size = UDim2.fromScale(lobe[2], 0.78),
				BackgroundColor3 = color,
				ZIndex = z,
			}, holder)
			Theme.round(l)
		end
		local stem = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.54, 0.3),
			Size = UDim2.fromScale(0.16, 0.3),
			Rotation = 14,
			BackgroundColor3 = color,
			ZIndex = z,
		}, holder)
		Theme.corner(stem, 2)
	end
	holder.Parent = parent
	return holder
end

-- Surfaces --------------------------------------------------------------------------------------------

-- shadow-lift behind a floating frame: a soft dark copy below it (a wide faint stroke feathers it).
local LIFT = 10
function Theme.shadow(f: GuiObject, radius: number?)
	local parent = f.Parent
	if not parent then
		return
	end
	local sh = new("Frame", {
		Name = f.Name .. "_Shadow",
		AnchorPoint = f.AnchorPoint,
		Position = f.Position + UDim2.fromOffset(0, LIFT),
		Size = f.Size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = math.max(0, f.ZIndex - 1),
		Visible = f.Visible,
	}, parent)
	Theme.corner(sh, radius or Theme.Radius.L)
	Theme.stroke(sh, Color3.new(0, 0, 0), 10, 0.85)
	sh:SetAttribute("Rest", 0.6)
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		sh.Visible = f.Visible
	end)
	f:GetPropertyChangedSignal("Position"):Connect(function()
		sh.Position = f.Position + UDim2.fromOffset(0, LIFT)
	end)
	f:GetPropertyChangedSignal("AnchorPoint"):Connect(function()
		sh.AnchorPoint = f.AnchorPoint
	end)
	-- follow the frame's rendered size, so size constraints on the frame apply to the shadow too
	local function syncSize()
		sh.Size = UDim2.fromOffset(f.AbsoluteSize.X, f.AbsoluteSize.Y)
	end
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncSize)
	task.defer(syncSize)
	f.AncestryChanged:Connect(function()
		if not f.Parent then
			sh:Destroy()
		end
	end)
end

-- A surface (card, sheet, panel): flat, rounded (radius-lg), no outline, floating on shadow-lift.
function Theme.panel(parent: Instance?, props: { [string]: any }?, radius: number?): Frame
	local f = new("Frame", {
		BackgroundColor3 = T.surface,
		BorderSizePixel = 0,
	}, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Theme.corner(f, radius or Theme.Radius.L)
	f.Parent = parent
	if parent then
		Theme.shadow(f, radius or Theme.Radius.L)
	end
	return f
end

-- A small info pill on a surface (phase line, feed lines, hints): no outline.
function Theme.pill(parent: Instance?, props: { [string]: any }?): Frame
	local f = new("Frame", {
		BackgroundColor3 = T.surface,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	}, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Theme.round(f)
	f.Parent = parent
	return f
end

-- A sunk well inside a surface (tracks, stat tiles, the area behind a shelf).
function Theme.well(parent: Instance?, props: { [string]: any }?, radius: number?): Frame
	local f = new("Frame", { BackgroundColor3 = T.surfaceSunk, BorderSizePixel = 0 }, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Theme.corner(f, radius or Theme.Radius.M)
	f.Parent = parent
	return f
end

-- Sheet: the floating surface every hub screen lives on. A CanvasGroup (so it can fade as one),
-- radius-lg, shadow-lift, a display-font title (sentence case) with an optional caption under it,
-- and a round secondary close button. Content goes in the returned `body`, which already has the
-- sheet's padding. opts: maxSize (Vector2), subtitle, tone (Color3: a loud header band in that fill
-- with an outlined paper title, a joy-red close button and a toy outline round the whole sheet, for
-- screens that should grab attention, like rewards), glyph (with tone: a glyph disc by the title).
export type Sheet = {
	frame: CanvasGroup,
	body: Frame,
	header: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	close: TextButton,
}
local BAND = 76
function Theme.sheet(parent: Instance, name: string, title: string, opts: { [string]: any }?): Sheet
	local o: { [string]: any } = opts or {}
	local pad = Theme.Space.XL
	local tone: Color3? = o.tone
	local f = new("CanvasGroup", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundColor3 = T.surface,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		ZIndex = 2,
	}, parent)
	Theme.corner(f, Theme.Radius.L)
	if o.maxSize then
		new("UISizeConstraint", { MaxSize = o.maxSize }, f)
	end
	Theme.shadow(f, Theme.Radius.L)
	local header = new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(pad, pad - 4),
		Size = UDim2.new(1, -pad * 2, 0, 52),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, f)
	local titleLabel, subtitle, close, top
	if tone then
		-- the band, its outline edge, a few paper polka dots, and the outline round the sheet (inset,
		-- since a CanvasGroup clips anything drawn outside it)
		local band = new("Frame", {
			Name = "Band",
			Size = UDim2.new(1, 0, 0, BAND),
			BackgroundColor3 = tone,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, f)
		new("Frame", {
			Name = "Edge",
			Position = UDim2.new(0, 0, 1, -Theme.StrokeToy),
			Size = UDim2.new(1, 0, 0, Theme.StrokeToy),
			BackgroundColor3 = T.outline,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, band)
		for i, d in { { 0.62, 14, 0.2 }, { 0.71, 30, 0.75 }, { 0.8, 18, 0.35 }, { 0.88, 40, 0.15 } } do
			local dot = new("Frame", {
				Name = "Polka" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(d[1], d[3] + 0.3),
				Size = UDim2.fromOffset(d[2], d[2]),
				BackgroundColor3 = T.paper,
				BackgroundTransparency = 0.78,
				ZIndex = 2,
			}, band)
			Theme.round(dot)
		end
		local border = new("Frame", {
			Name = "Border",
			Position = UDim2.fromOffset(Theme.StrokeToy, Theme.StrokeToy),
			Size = UDim2.new(1, -Theme.StrokeToy * 2, 1, -Theme.StrokeToy * 2),
			BackgroundTransparency = 1,
			ZIndex = 50,
		}, f)
		Theme.corner(border, Theme.Radius.L - Theme.StrokeToy)
		Theme.stroke(border, T.outline, Theme.StrokeToy)
		header.Position = UDim2.fromOffset(pad - 6, (BAND - 52) / 2)
		header.Size = UDim2.new(1, -(pad - 6) * 2, 0, 52)
		local left = 0
		if o.glyph then
			local disc = new("Frame", {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(48, 48),
				BackgroundColor3 = if tone == T.sun then T.paper else T.sun,
				Rotation = -8,
				ZIndex = 4,
			}, header)
			Theme.corner(disc, Theme.Radius.M)
			Theme.stroke(disc, T.outline, Theme.StrokeToy)
			Theme.glyph(disc, o.glyph, T.onFill, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.6, 0.6),
				ZIndex = 5,
			})
			left = 62
		end
		titleLabel = Theme.label(header, {
			Name = "Title",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, left, 0.5, 0),
			Size = UDim2.new(1, -left - 64, 0, 40),
			Text = title,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}, Theme.StrokeToy)
		close = Theme.iconButton(header, "close", T.joyRed, 48, {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, -Theme.Ledge / 2),
			ZIndex = 4,
			back = true,
		})
		local hasSub = (o.subtitle or "") ~= ""
		subtitle = Theme.body(f, {
			Name = "Subtitle",
			Position = UDim2.fromOffset(pad, BAND + 12),
			Size = UDim2.new(1, -pad * 2, 0, 20),
			Text = o.subtitle or "",
			FontFace = Theme.TextFace,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
		top = BAND + 12 + (if hasSub then 32 else 0)
		subtitle:GetPropertyChangedSignal("Text"):Connect(function()
			subtitle.Visible = subtitle.Text ~= ""
		end)
		subtitle.Visible = hasSub
	else
		titleLabel = Theme.label(header, {
			Name = "Title",
			Size = UDim2.new(1, -64, 0, 34),
			Text = title,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}, 0)
		subtitle = Theme.body(header, {
			Name = "Subtitle",
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, -64, 0, 18),
			Text = o.subtitle or "",
			FontFace = Theme.TextFace,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
		close = Theme.iconButton(header, "close", "secondary", 44, {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			ZIndex = 4,
			back = true,
		})
		top = pad + 60
	end
	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(pad, top),
		Size = UDim2.new(1, -pad * 2, 1, -(top + pad)),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, f)
	return { frame = f, body = body, header = header, title = titleLabel, subtitle = subtitle, close = close }
end

-- Sheets and pop-ups ----------------------------------------------------------------------------------
-- Navigation motion is fast and quiet: a sheet slides 24px and fades in duration-move; closing is a
-- quicker fade back down. Plain Frames (older pop-ups) do the same with a small scale instead of the
-- fade. Never blocks input. The optional backdrop dims the game behind modal sheets.

local function shadowOf(panel: GuiObject): Frame?
	local p = panel.Parent
	return if p then p:FindFirstChild(panel.Name .. "_Shadow") :: Frame? else nil
end

local function restOf(panel: GuiObject): UDim2
	local r = panel:GetAttribute("RestPosition")
	if typeof(r) == "UDim2" then
		return r
	end
	panel:SetAttribute("RestPosition", panel.Position)
	return panel.Position
end

function Theme.show(panel: GuiObject, backdrop: GuiObject?)
	local closing = panel.Visible and panel:GetAttribute("ThemeOpen") == false
	local wasOpen = panel.Visible and not closing
	panel:SetAttribute("ThemeOpen", true)
	panel.Visible = true
	if backdrop then
		if not backdrop.Visible then
			backdrop.BackgroundTransparency = 1
		end
		backdrop.Visible = true
		tween(backdrop, Theme.Motion.Base, { BackgroundTransparency = 0.45 })
	end
	if wasOpen then
		return
	end
	local rest = restOf(panel)
	local sh = shadowOf(panel)
	if panel:IsA("CanvasGroup") then
		if not reduced() and not closing then
			panel.GroupTransparency = 1
			panel.Position = rest + UDim2.fromOffset(0, 24)
			if sh then
				sh.BackgroundTransparency = 1
			end
		end
		tween(panel, Theme.Motion.Base, { GroupTransparency = 0, Position = rest }, SOFT)
		if sh then
			tween(sh, Theme.Motion.Base, { BackgroundTransparency = sh:GetAttribute("Rest") or 0.6 }, SOFT)
		end
	else
		local sc = scaleOf(panel)
		if not closing and not reduced() then
			sc.Scale = 0.9 * baseOf(sc)
		end
		tween(sc, Theme.Motion.Base, { Scale = baseOf(sc) }, POP)
	end
end

function Theme.hide(panel: GuiObject, backdrop: GuiObject?)
	if not panel.Visible or panel:GetAttribute("ThemeOpen") == false then
		return -- already closed or closing
	end
	panel:SetAttribute("ThemeOpen", false)
	if backdrop and backdrop.Visible then
		tween(backdrop, Theme.Motion.Fast, { BackgroundTransparency = 1 }).Completed:Once(function(state)
			-- a sheet opening meanwhile restarts the backdrop tween, which cancels this one
			if state == Enum.PlaybackState.Completed then
				backdrop.Visible = false
			end
		end)
	end
	local function finish()
		-- only finish closing if nothing reopened it meanwhile
		if panel:GetAttribute("ThemeOpen") == false then
			panel.Visible = false
			if panel:IsA("CanvasGroup") then
				panel.Position = restOf(panel)
				panel.GroupTransparency = 0
			else
				local sc = scaleOf(panel)
				sc.Scale = baseOf(sc)
			end
		end
	end
	if panel:IsA("CanvasGroup") then
		local rest = restOf(panel)
		local sh = shadowOf(panel)
		if sh then
			tween(sh, Theme.Motion.Fast, { BackgroundTransparency = 1 })
		end
		tween(panel, Theme.Motion.Fast, { GroupTransparency = 1, Position = rest + UDim2.fromOffset(0, 16) }).Completed:Once(
			finish
		)
	else
		local sc = scaleOf(panel)
		tween(sc, Theme.Motion.Fast, { Scale = 0.92 * baseOf(sc) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(
			finish
		)
	end
end

-- Full-screen dim layer behind modal sheets; clicking it calls onClose.
function Theme.backdrop(parent: Instance, onClose: (() -> ())?): TextButton
	local b = new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -60),
		BackgroundColor3 = T.dim,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 0,
	}, parent)
	if onClose then
		b.Activated:Connect(function()
			sound("UIBack")
			onClose()
		end)
	end
	return b
end

-- Small components ------------------------------------------------------------------------------------

-- Badge sticker: micro uppercase text in an outlined pill (sun = new, candy = limited, leaf =
-- complete, sky = info). Auto-sizes to its text.
function Theme.sticker(parent: Instance?, text: string, tone: Color3, props: { [string]: any }?): Frame
	local f = new("Frame", {
		Name = "Sticker",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = tone,
		BorderSizePixel = 0,
	}, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Theme.round(f)
	Theme.stroke(f, T.outline, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, f)
	Theme.text(f, 12, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = string.upper(text),
		TextColor3 = Theme.textOn(tone),
		ZIndex = f.ZIndex + 1,
	})
	f.Parent = parent
	return f
end

-- Notification dot: joy-red, outlined, with a paper "!" and a gentle pulse. Optional text = a sun
-- count bubble instead (that one keeps the stepped wiggle).
local pulsing: { [GuiObject]: UIScale } = {}
function Theme.dot(parent: GuiObject, text: string?): Frame
	local count = text ~= nil and text ~= ""
	local dot = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = if count then T.sun else T.joyRed,
		Visible = false,
		ZIndex = (parent.ZIndex or 1) + 6,
	}, parent)
	Theme.round(dot)
	Theme.stroke(dot, T.outline, Theme.StrokeToy)
	if count then
		Theme.text(
			dot,
			12,
			{ Size = UDim2.fromScale(1, 1), Text = text or "", TextColor3 = T.onFill, ZIndex = dot.ZIndex + 1 }
		)
		Theme.wiggle(dot)
	else
		Theme.text(dot, 17, {
			Name = "Mark",
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, -1),
			FontFace = Theme.DisplayFace,
			Text = "!",
			TextColor3 = T.paper,
			ZIndex = dot.ZIndex + 1,
		})
		pulsing[dot] = new("UIScale", nil, dot)
	end
	return dot
end
RunService.RenderStepped:Connect(function()
	local s = 1 + 0.12 * (0.5 + 0.5 * math.sin(os.clock() * math.pi * 2 / 1.1))
	for dot, sc in pulsing do
		if not dot.Parent then
			pulsing[dot] = nil
		elseif dot.Visible then
			sc.Scale = if reduced() then 1 else s
		end
	end
end)

-- Older name for the notification dot.
function Theme.badge(parent: GuiObject, _text: string?): Frame
	return Theme.dot(parent)
end

-- Coin icon: a sun disc in the toy outline with an on-fill "C".
function Theme.coin(parent: Instance, size: number, props: { [string]: any }?): Frame
	local coin = new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = T.sun,
	}, nil)
	if props then
		for k, v in props do
			(coin :: any)[k] = v
		end
	end
	Theme.round(coin)
	Theme.stroke(coin, T.outline, math.clamp(size / 14, 1.5, Theme.StrokeToy))
	Theme.body(coin, {
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.2, 0.2),
		FontFace = Theme.DisplayFace,
		Text = "C",
		TextColor3 = T.onFill,
		ZIndex = coin.ZIndex + 1,
	})
	coin.Parent = parent
	return coin
end

-- A stat tile: a sunk well with a big value over a caption.
function Theme.statChip(parent: Instance, caption: string, color: Color3, props: { [string]: any }?): TextLabel
	local f = Theme.well(nil, props, Theme.Radius.M)
	local value = Theme.label(f, {
		Name = "Value",
		Position = UDim2.fromOffset(Theme.Space.S, Theme.Space.S),
		Size = UDim2.new(1, -Theme.Space.L, 0.56, -Theme.Space.S),
		Text = "0",
		TextColor3 = color,
	}, 0)
	Theme.body(f, {
		Name = "Caption",
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.fromScale(1, 0.24),
		FontFace = Theme.TextFace,
		Text = caption,
	})
	f.Parent = parent
	return value
end

-- Toggle: a sunk, outlined track (leaf when on) with a cream thumb that slides with ease-pop.
-- Returns the hit button and a setter (for following server state without firing onChange).
function Theme.toggle(
	parent: Instance?,
	initial: boolean,
	onChange: (boolean) -> (),
	props: { [string]: any }?
): (TextButton, (boolean) -> ())
	local state = initial
	local b = new("TextButton", {
		Name = "Toggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = T.surfaceSunk,
		Size = UDim2.fromOffset(56, 32),
	}, nil)
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	Theme.round(b)
	Theme.stroke(b, T.outline, Theme.StrokeToy)
	local thumb = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = T.surface,
		ZIndex = b.ZIndex + 1,
	}, b)
	Theme.round(thumb)
	Theme.stroke(thumb, T.outline, 2)
	local function render(animate: boolean)
		local pos = if state then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		local col = if state then T.leaf else T.surfaceSunk
		if animate and not reduced() then
			tween(thumb, Theme.Motion.Slow, { Position = pos }, POP)
			tween(b, Theme.Motion.Fast, { BackgroundColor3 = col })
		else
			thumb.Position = pos
			b.BackgroundColor3 = col
		end
	end
	render(false)
	Theme.selectable(b)
	b.Activated:Connect(function()
		state = not state
		render(true)
		sound(if state then "UIToggleOn" else "UIToggleOff")
		onChange(state)
	end)
	b.Parent = parent
	return b, function(v: boolean)
		if v ~= state then
			state = v
			render(true)
		end
	end
end

-- Segmented tabs: labels on a sunk pill track; the active one sits on an outlined surface pill that
-- slides between them (duration-quick, ease-out-soft). items = { {key, label} }. Returns the track
-- and a setter.
function Theme.segmented(
	parent: Instance?,
	items: { { key: string, label: string } },
	initial: string,
	onSelect: (string) -> (),
	props: { [string]: any }?
): (Frame, (string) -> ())
	local track = new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = T.surfaceSunk,
		Size = UDim2.new(1, 0, 0, 48),
	}, nil)
	if props then
		for k, v in props do
			(track :: any)[k] = v
		end
	end
	Theme.round(track)
	local n = #items
	local inset = 5
	local indicator = new("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, inset, 0.5, 0),
		Size = UDim2.new(1 / n, -inset * 2, 1, -inset * 2),
		BackgroundColor3 = T.surface,
		ZIndex = track.ZIndex + 1,
	}, track)
	Theme.round(indicator)
	Theme.stroke(indicator, T.outline, Theme.StrokeToy)
	local labels: { [string]: TextLabel } = {}
	local index: { [string]: number } = {}
	local current = initial
	local function place(animate: boolean)
		local i = index[current] or 1
		local pos = UDim2.new((i - 1) / n, inset, 0.5, 0)
		if animate and not reduced() then
			tween(indicator, Theme.Motion.Fast, { Position = pos }, SOFT)
		else
			indicator.Position = pos
		end
		for key, l in labels do
			l.TextColor3 = if key == current then T.ink else T.inkMuted
		end
	end
	for i, item in items do
		index[item.key] = i
		local seg = new("TextButton", {
			Name = item.key,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((i - 1) / n, 0),
			Size = UDim2.fromScale(1 / n, 1),
			ZIndex = track.ZIndex + 2,
		}, track)
		labels[item.key] = Theme.body(seg, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -16, 0.44, 0),
			FontFace = Theme.LabelFace,
			Text = item.label,
			ZIndex = track.ZIndex + 3,
		})
		new("UITextSizeConstraint", { MaxTextSize = 18 }, labels[item.key])
		Theme.selectable(seg, seg)
		seg.Activated:Connect(function()
			if current ~= item.key then
				current = item.key
				place(true)
				sound("UITab")
				onSelect(item.key)
			end
		end)
	end
	place(false)
	track.Parent = parent
	return track, function(key: string)
		if current ~= key then
			current = key
			place(true)
		end
	end
end

-- GameTile: a square tile of art on a fill (radius-md). Selecting it grows it to 1.06, puts the
-- ring on it and shows its title in a bubble above (leave ~56px above a shelf for the bubble).
-- Returns the hit button, the art frame (draw the art in it) and a setter for selection.
export type Tile = {
	button: TextButton,
	art: Frame,
	setSelected: (boolean) -> (),
	setTitle: (string) -> (),
}
function Theme.tile(parent: Instance?, size: number, tone: Color3, title: string, props: { [string]: any }?): Tile
	local b = new("TextButton", {
		Name = "Tile",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	}, nil)
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	local art = new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = tone,
		ZIndex = b.ZIndex + 1,
		ClipsDescendants = false,
	}, b)
	Theme.corner(art, Theme.Radius.M)
	local artScale = new("UIScale", nil, art)
	Theme.selectable(b, art, Theme.Radius.M)
	-- the title bubble: a pill in select-colored display type (sunk, so it reads on a sheet's surface)
	local bubble = Theme.pill(b, {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -16),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundColor3 = T.surfaceSunk,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = b.ZIndex + 8,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, bubble)
	local bubbleText = Theme.text(bubble, 18, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = Theme.DisplayFace,
		Text = title,
		TextColor3 = T.select,
		ZIndex = bubble.ZIndex + 1,
	})
	local selected = false
	b.Parent = parent
	return {
		button = b,
		art = art,
		setSelected = function(on: boolean)
			if on == selected then
				return
			end
			selected = on
			bubble.Visible = on
			if reduced() then
				artScale.Scale = 1
			else
				tween(artScale, Theme.Motion.Fast, { Scale = if on then 1.06 else 1 }, SOFT)
				if on then
					Theme.pop(bubble, 0.6, Theme.Motion.Fast * 2)
				end
			end
			if on then
				Theme.setHome(b)
			end
		end,
		setTitle = function(text: string)
			bubbleText.Text = text
		end,
	}
end

-- RoundAction: a round outlined disc (56px) on a toy ledge with an outlined paper caption under it
-- (it sits over the game world) that turns sun and heavy when selected. Destinations, not actions. Returns the hit button and its dot.
function Theme.roundAction(
	parent: Instance?,
	label: string,
	tone: Color3,
	glyphName: string,
	props: { [string]: any }?
): (TextButton, Frame)
	local disc = 56
	local b = new("TextButton", {
		Name = label,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(84, disc + Theme.Ledge + 26),
	}, nil)
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	local ledge = new("Frame", {
		Name = "Ledge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.Ledge),
		Size = UDim2.fromOffset(disc, disc),
		BackgroundColor3 = T.outline, -- a dark ledge: it sits over the night scene, not a sheet
		ZIndex = b.ZIndex,
	}, b)
	Theme.round(ledge)
	local face = new("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(disc, disc),
		BackgroundColor3 = tone,
		ZIndex = b.ZIndex + 1,
	}, b)
	Theme.round(face)
	Theme.stroke(face, T.outline, Theme.StrokeToy)
	Theme.glyph(face, glyphName, T.onFill, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.46, 0.46),
		ZIndex = b.ZIndex + 2,
	})
	local caption = Theme.text(b, 14, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = Theme.TextFace,
		Text = label,
		TextColor3 = T.paper,
		ZIndex = b.ZIndex + 1,
	})
	Theme.textStroke(caption, 2, T.outline)
	pressable(b, face, ledge, 0)
	Theme.selectable(b, face)
	local function emphasize(on: boolean)
		caption.TextColor3 = if on then T.sun else T.paper
		caption.FontFace = if on then Theme.LabelFace else Theme.TextFace
	end
	b.MouseEnter:Connect(function()
		emphasize(true)
	end)
	b.MouseLeave:Connect(function()
		emphasize(false)
	end)
	b.SelectionGained:Connect(function()
		emphasize(true)
	end)
	b.SelectionLost:Connect(function()
		emphasize(false)
	end)
	-- no press sound of its own: the sheet it opens or closes answers with UIOpen / UIBack
	local dot = Theme.dot(face)
	dot.Position = UDim2.new(1, -6, 0, 6)
	b.Parent = parent
	return b, dot
end

-- Controller-hint legend: a filled disc (ink, or `tone` with the toy outline) with the key, then a caption. Returns the
-- frame plus its key and caption labels; set `Cooldown` (0..1) on the frame's "Fill" to show a
-- cooldown draining across the pill.
function Theme.legend(
	parent: Instance?,
	key: string,
	caption: string,
	props: { [string]: any }?,
	tone: Color3?
): (Frame, TextLabel, TextLabel)
	local f = Theme.pill(nil, {
		Name = caption,
		Size = UDim2.fromOffset(144, 46),
		ClipsDescendants = true,
	})
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.surfaceSunk,
		BorderSizePixel = 0,
		ZIndex = f.ZIndex + 1,
	}, f)
	local disc = new("Frame", {
		Name = "Key",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = tone or T.ink,
		ZIndex = f.ZIndex + 2,
	}, f)
	Theme.round(disc)
	if tone then
		Theme.stroke(disc, T.outline, 2)
	end
	local keyLabel = Theme.text(disc, 15, {
		Name = "Letter",
		Size = UDim2.fromScale(1, 1),
		Text = key,
		TextColor3 = if tone then Theme.textOn(tone) else T.paper,
		ZIndex = f.ZIndex + 3,
	})
	local captionLabel = Theme.text(f, 18, {
		Name = "Caption",
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -50, 1, 0),
		Text = caption,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = f.ZIndex + 2,
	})
	f.Parent = parent
	local _ = fill
	return f, keyLabel, captionLabel
end

return Theme
