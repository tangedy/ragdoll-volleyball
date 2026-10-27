--!strict
-- Input for PC, mobile and controller (spec §9). Mobile gets dedicated large buttons: holding Throw
-- never blocks camera drags with another finger, and dragging off Throw cancels the aim.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Net = require(script.Parent.Net)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AimController = require(script.Parent.AimController)

local player = Players.LocalPlayer

local InputController = {}

InputController.buttons = {} :: { [string]: TextButton }
InputController.changed = Instance.new("BindableEvent")

local function moveDirection(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.MoveDirection else Vector3.zero
end

function InputController.dodge()
	if AimController.charging then
		AimController.cancel()
	end
	Net.request(Net.Actions.Dodge, { dir = moveDirection() })
end

function InputController.catch()
	Net.request(Net.Actions.Catch)
end

local function setInput(kind: string)
	if AimController.lastInput ~= kind then
		AimController.lastInput = kind
		InputController.changed:Fire(kind)
		Net.request(Net.Actions.ReportDevice, { kind = kind })
	end
end

local CANCEL = "RD_CancelAim"

local function bindCancel(on: boolean)
	if on then
		-- only bound while aiming, so right-drag camera rotation works the rest of the time
		ContextActionService:BindActionAtPriority(CANCEL, function(_, state)
			if state == Enum.UserInputState.Begin then
				AimController.cancel()
				bindCancel(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	else
		ContextActionService:UnbindAction(CANCEL)
	end
end

local function throwBegin()
	AimController.begin()
	if AimController.charging then
		bindCancel(true)
	end
end

local function throwEnd()
	bindCancel(false)
	AimController.release()
end

local function bindDesktopAndGamepad()
	ContextActionService:BindAction("RD_Throw", function(_, state, input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			setInput("Mouse")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			setInput("Gamepad")
		end
		if state == Enum.UserInputState.Begin then
			throwBegin()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			throwEnd()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("RD_Dodge", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			setInput(if input.KeyCode == Enum.KeyCode.ButtonX then "Gamepad" else "Mouse")
			InputController.dodge()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("RD_Catch", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			setInput(if input.KeyCode == Enum.KeyCode.ButtonL1 then "Gamepad" else "Mouse")
			InputController.catch()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonL1)
end

-- Touch buttons: a smoky see-through disc with a dark rim and a thin white inner ring, a white glyph
-- drawn from plain frames (no uploaded images), a cooldown disc that shrinks away, and a squish on
-- press.
local DISC = Color3.fromRGB(18, 28, 48)
local RIM = Color3.fromRGB(8, 14, 26)
local GLYPH = Color3.new(1, 1, 1)
local ICON = 0.6 -- glyph box, as a fraction of the button

-- A rounded bar in the glyph box (all units are fractions of the box), white unless `color` is
-- given. `base` is its own transparency.
local function bar(
	parent: Instance,
	cx: number,
	cy: number,
	w: number,
	h: number,
	rot: number?,
	base: number?,
	color: Color3?
): Frame
	local f = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx, cy),
		Size = UDim2.fromScale(w, h),
		Rotation = rot or 0,
		BackgroundColor3 = color or GLYPH,
		BackgroundTransparency = base or 0,
		BorderSizePixel = 0,
	}, parent)
	if not color then
		f:SetAttribute("Glyph", true) -- white pieces grey out with setDim; seams keep their colour
	end
	Theme.round(f)
	return f
end

-- A rounded stroke from (x1, y1) to (x2, y2), `t` thick. Its ends overlap by half a thickness, so
-- chained strokes join smoothly.
local function seg(parent: Instance, x1: number, y1: number, x2: number, y2: number, t: number, color: Color3?)
	local dx, dy = x2 - x1, y2 - y1
	bar(
		parent,
		(x1 + x2) / 2,
		(y1 + y2) / 2,
		math.sqrt(dx * dx + dy * dy) + t,
		t,
		math.deg(math.atan2(dy, dx)),
		nil,
		color
	)
end

-- A curve drawn as short strokes along a circle (centre cx, cy; radius r) from angle a0 to a1, in
-- degrees, 0 pointing right and 90 down. Curves need no clipping this way: CanvasGroup clipping
-- is dropped when the GPU budget for canvas groups runs out.
local function arc(
	parent: Instance,
	cx: number,
	cy: number,
	r: number,
	a0: number,
	a1: number,
	t: number,
	color: Color3?
)
	local steps = 6
	local function at(i: number): (number, number)
		local a = math.rad(a0 + (a1 - a0) * i / steps)
		return cx + r * math.cos(a), cy + r * math.sin(a)
	end
	for i = 0, steps - 1 do
		local x1, y1 = at(i)
		local x2, y2 = at(i + 1)
		seg(parent, x1, y1, x2, y2, t, color)
	end
end

-- A dodgeball: a white disc with two curved seams in the button's own colour, end to end on its rim.
local function ball(parent: Instance, cx: number, cy: number, d: number)
	local disc = bar(parent, cx, cy, d, d)
	arc(disc, -0.28, 0.5, 0.62, -35, 35, 0.1, DISC)
	arc(disc, 1.28, 0.5, 0.62, 145, 215, 0.1, DISC)
end

local Glyphs = {}

-- ">>" with speed lines; the second chevron trails in grey
function Glyphs.Dodge(box: Frame)
	bar(box, 0.2, 0.4, 0.15, 0.085)
	bar(box, 0.16, 0.6, 0.08, 0.085)
	for i, base in { 0, 0.55 } do
		local x = 0.47 + (i - 1) * 0.2
		bar(box, x, 0.39, 0.3, 0.11, 47, base)
		bar(box, x, 0.61, 0.3, 0.11, -47, base)
	end
end

-- a ball flying left-to-right with three speed lines
function Glyphs.Throw(box: Frame)
	for _, l in { { 0.38, 0.27 }, { 0.5, 0.2 }, { 0.62, 0.27 } } do
		bar(box, 0.38 - l[2] / 2, l[1], l[2], 0.085)
	end
	ball(box, 0.68, 0.5, 0.5)
end

-- two cupped hands around a ball, with a "ready" tick above
function Glyphs.Catch(box: Frame)
	ball(box, 0.5, 0.55, 0.34)
	arc(box, 0.5, 0.52, 0.4, 100, 200, 0.1)
	arc(box, 0.5, 0.52, 0.4, -20, 80, 0.1)
	bar(box, 0.5, 0.08, 0.07, 0.12)
	bar(box, 0.35, 0.13, 0.075, 0.075)
	bar(box, 0.65, 0.13, 0.075, 0.075)
end

-- an up arrow on a base line
function Glyphs.Jump(box: Frame)
	seg(box, 0.5, 0.2, 0.3, 0.42, 0.14)
	seg(box, 0.5, 0.2, 0.7, 0.42, 0.14)
	seg(box, 0.5, 0.26, 0.5, 0.68, 0.16)
	bar(box, 0.5, 0.82, 0.3, 0.06)
end

-- Grey a whole glyph out (0 = white, 1 = the disc colour). It blends colour rather than fading,
-- so overlapping strokes stay solid instead of showing their joins.
local function setDim(btn: TextButton, dim: number)
	if btn:GetAttribute("Dim") == dim then
		return
	end
	btn:SetAttribute("Dim", dim)
	local box = btn:FindFirstChild("Icon", true)
	if not box then
		return
	end
	local color = GLYPH:Lerp(DISC, dim)
	for _, d in box:GetDescendants() do
		if d:GetAttribute("Glyph") and d:IsA("GuiObject") then
			d.BackgroundColor3 = color
		end
	end
end

local function makeButton(parent: Instance, name: string, size: number, pos: UDim2): TextButton
	local b = Theme.new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Active = true,
	}, parent)
	local scale = Theme.new("UIScale", { Scale = 1 }, b)
	local face = Theme.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = DISC,
		BackgroundTransparency = 0.3,
	}, b)
	Theme.round(face)
	Theme.stroke(face, RIM, math.max(3, math.floor(size * 0.05)), 0.35).Name = "Rim"
	-- cooldown: a dark disc that shrinks to nothing as the move comes back
	local cooldown = Theme.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = RIM,
		BackgroundTransparency = 0.3,
		Size = UDim2.fromScale(0, 0),
		BorderSizePixel = 0,
	}, face)
	Theme.round(cooldown)
	-- the thin white inner ring; the tutorial pulses it (Outline) and restores these Rest values
	local inner = Theme.new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, b)
	Theme.round(inner)
	local outline = Theme.stroke(inner, GLYPH, 2, 0.3)
	outline.Name = "Outline"
	outline:SetAttribute("RestColor", GLYPH)
	outline:SetAttribute("RestThickness", 2)
	outline:SetAttribute("RestTransparency", 0.3)
	local box = Theme.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(ICON, ICON),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, b)
	Glyphs[name](box)
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			scale.Scale = 0.9
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			Theme.tween(scale, Theme.Motion.Slow, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	return b
end

local function buildMobile()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- respect notches and home bars
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	-- big Throw in the middle, Dodge above it, Catch down-left and Jump underneath
	local throw = makeButton(gui, "Throw", 112, UDim2.new(1, -137, 1, -165))
	local dodge = makeButton(gui, "Dodge", 68, UDim2.new(1, -137, 1, -266))
	local catch = makeButton(gui, "Catch", 88, UDim2.new(1, -230, 1, -67))
	local jump = makeButton(gui, "Jump", 78, UDim2.new(1, -136, 1, -62))
	InputController.buttons = { Throw = throw, Catch = catch, Dodge = dodge, Jump = jump }
	jump.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h then
				h.Jump = true
			end
		end
	end)
	-- our Jump replaces Roblox's own touch jump button, which would sit under the cluster
	task.spawn(function()
		local touchGui = player:WaitForChild("PlayerGui"):WaitForChild("TouchGui", 30)
		local frame = touchGui and touchGui:WaitForChild("TouchControlFrame", 10)
		local default = frame and frame:WaitForChild("JumpButton", 10)
		if default and default:IsA("GuiObject") then
			default.Visible = false
			default:GetPropertyChangedSignal("Visible"):Connect(function()
				if default.Visible then
					default.Visible = false
				end
			end)
		end
	end)

	local activeTouch: InputObject? = nil
	local cancelled = false
	throw.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or activeTouch then
			return
		end
		setInput("Touch")
		activeTouch = input
		cancelled = false
		throwBegin()
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input ~= activeTouch or cancelled then
			return
		end
		-- drag off the button (with margin) cancels the aim
		local p = Vector2.new(input.Position.X, input.Position.Y)
		local tl = throw.AbsolutePosition
		local br = tl + throw.AbsoluteSize
		local margin = 30
		if p.X < tl.X - margin or p.Y < tl.Y - margin or p.X > br.X + margin or p.Y > br.Y + margin then
			cancelled = true
			bindCancel(false)
			AimController.cancel()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input ~= activeTouch then
			return
		end
		activeTouch = nil
		if not cancelled then
			throwEnd()
		end
	end)
	catch.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setInput("Touch")
			InputController.catch()
		end
	end)
	dodge.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setInput("Touch")
			InputController.dodge()
		end
	end)
	return gui
end

function InputController.init() end

function InputController.start()
	bindDesktopAndGamepad()
	task.defer(function()
		Net.request(Net.Actions.ReportDevice, { kind = AimController.lastInput })
	end)
	local mobileGui: ScreenGui? = nil
	local function refresh()
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if touch and not mobileGui then
			mobileGui = buildMobile()
			setInput("Touch")
		end
		if mobileGui then
			mobileGui.Enabled = AimController.lastInput == "Touch"
		end
	end
	refresh()
	-- Studio gallery ("Touch"): show the touch controls on a desktop until the mouse moves
	function InputController.forceTouch()
		setInput("Touch")
		if not mobileGui then
			mobileGui = buildMobile()
		end
		refresh()
	end
	UserInputService.LastInputTypeChanged:Connect(function(t)
		if t == Enum.UserInputType.Touch then
			setInput("Touch")
			if not mobileGui then
				mobileGui = buildMobile()
			end
		elseif t == Enum.UserInputType.Gamepad1 then
			setInput("Gamepad")
		elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Keyboard then
			setInput("Mouse")
		end
		refresh()
	end)
	-- cooldown overlays on mobile buttons
	RunService.RenderStepped:Connect(function()
		local b = InputController.buttons
		if not b.Throw then
			return
		end
		local t = Workspace:GetServerTimeNow()
		local function fill(btn: TextButton, readyAt: any, duration: number)
			local frac = if type(readyAt) == "number" then math.clamp((readyAt - t) / duration, 0, 1) else 0
			(btn:FindFirstChild("Cooldown", true) :: Frame).Size = UDim2.fromScale(frac, frac)
		end
		fill(b.Dodge, player:GetAttribute("DodgeReadyAt"), Config.Player.DodgeCooldown)
		fill(b.Catch, player:GetAttribute("CatchReadyAt"), Config.Player.CatchCooldown)
		-- Throw greys out without a ball; Catch fades while you hold one
		local held = player:GetAttribute("HeldBall")
		local hasBall = type(held) == "string" and held ~= ""
		setDim(b.Throw, if hasBall then 0 else 0.45)
		setDim(b.Catch, if hasBall then 0.45 else 0)
	end)
end

return InputController
