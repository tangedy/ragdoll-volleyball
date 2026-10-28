--!strict
-- Input for PC, mobile and controller (spec §9). Throwing is a tap: the aim is always locked on to
-- an enemy while you hold a ball. Mobile gets dedicated large buttons plus the camera lock button.

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
local LockController = require(script.Parent.LockController)
local CharacterController = require(script.Parent.CharacterController)

local player = Players.LocalPlayer

local InputController = {}

InputController.buttons = {} :: { [string]: GuiObject }
InputController.changed = Instance.new("BindableEvent")

local function moveDirection(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.MoveDirection else Vector3.zero
end

function InputController.dodge()
	local dir = moveDirection()
	CharacterController.predictDodge(dir) -- move now; the server still decides the cooldown and state
	Net.request(Net.Actions.Dodge, { dir = dir })
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

local function bindDesktopAndGamepad()
	ContextActionService:BindAction("RD_Throw", function(_, state, input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			setInput("Mouse")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			setInput("Gamepad")
		end
		if state == Enum.UserInputState.Begin then
			AimController.fire()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("RD_Lock", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			setInput(if input.KeyCode == Enum.KeyCode.ButtonR3 then "Gamepad" else "Mouse")
			LockController.cycle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonR3)
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

-- Touch buttons: the hub's round action buttons (Theme.roundAction) made see-through: a pastel fill
-- in the toy outline, an ink glyph drawn from plain frames (no uploaded images), a cooldown disc that
-- shrinks away, and a squish on press. All colours are Toybox tokens, so the Halloween palette swap
-- reaches them too.
local T = Theme.Toybox
local INK = T.onFill
local FACE_TRANSPARENCY = 0.3 -- see-through, but still clearly the button's tone
local ICON = 0.56 -- glyph box, as a fraction of the button
local TONES: { [string]: Color3 } = {
	Throw = T.leaf, -- the one main action
	Catch = T.sky,
	Dodge = T.peach,
	Jump = T.sun,
	Lock = T.surface,
}

-- A rounded bar in the glyph box (all units are fractions of the box), ink unless `color` is
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
		BackgroundColor3 = color or INK,
		BackgroundTransparency = base or 0,
		BorderSizePixel = 0,
	}, parent)
	if not color then
		f:SetAttribute("Glyph", true) -- ink pieces fade with setDim; seams keep their colour
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

-- A dodgeball: an ink disc with two curved seams in the button's tone, end to end on its rim.
local function ball(parent: Instance, cx: number, cy: number, d: number, tone: Color3)
	local disc = bar(parent, cx, cy, d, d)
	arc(disc, -0.28, 0.5, 0.62, -35, 35, 0.1, tone)
	arc(disc, 1.28, 0.5, 0.62, 145, 215, 0.1, tone)
end

local Glyphs = {}

-- ">>" with speed lines; the second chevron trails off
function Glyphs.Dodge(box: Frame, _tone: Color3)
	bar(box, 0.2, 0.4, 0.15, 0.085)
	bar(box, 0.16, 0.6, 0.08, 0.085)
	for i, base in { 0, 0.55 } do
		local x = 0.47 + (i - 1) * 0.2
		bar(box, x, 0.39, 0.3, 0.11, 47, base)
		bar(box, x, 0.61, 0.3, 0.11, -47, base)
	end
end

-- a ball flying left-to-right with three speed lines
function Glyphs.Throw(box: Frame, tone: Color3)
	for _, l in { { 0.38, 0.27 }, { 0.5, 0.2 }, { 0.62, 0.27 } } do
		bar(box, 0.38 - l[2] / 2, l[1], l[2], 0.085)
	end
	ball(box, 0.68, 0.5, 0.5, tone)
end

-- two cupped hands around a ball, with a "ready" tick above
function Glyphs.Catch(box: Frame, tone: Color3)
	ball(box, 0.5, 0.55, 0.34, tone)
	arc(box, 0.5, 0.52, 0.4, 100, 200, 0.1)
	arc(box, 0.5, 0.52, 0.4, -20, 80, 0.1)
	bar(box, 0.5, 0.08, 0.07, 0.12)
	bar(box, 0.35, 0.13, 0.075, 0.075)
	bar(box, 0.65, 0.13, 0.075, 0.075)
end

-- an up arrow on a base line
function Glyphs.Jump(box: Frame, _tone: Color3)
	seg(box, 0.5, 0.2, 0.3, 0.42, 0.14)
	seg(box, 0.5, 0.2, 0.7, 0.42, 0.14)
	seg(box, 0.5, 0.26, 0.5, 0.68, 0.16)
	bar(box, 0.5, 0.82, 0.3, 0.06)
end

-- a padlock: open (Free), closed (Shift lock), or closed with a target on it (Aim lock); one
-- variant per mode, shown by setLockGlyph
function Glyphs.Lock(box: Frame, tone: Color3)
	for _, mode in Config.Lock.Modes do
		local v = Theme.new("Frame", {
			Name = mode,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = mode == "Free",
		}, box)
		local open = mode == "Free"
		local top = if open then 0.26 else 0.4
		arc(v, 0.5, top, 0.19, 180, 360, 0.11)
		seg(v, 0.31, top, 0.31, if open then top + 0.06 else 0.5, 0.11)
		seg(v, 0.69, top, 0.69, 0.5, 0.11)
		local body = bar(v, 0.5, 0.68, 0.66, 0.46);
		(body:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius = UDim.new(0.22, 0)
		if mode == "Aim" then
			arc(body, 0.5, 0.5, 0.27, 0, 360, 0.1, tone)
			bar(body, 0.5, 0.5, 0.14, 0.2, nil, nil, tone)
		else
			bar(body, 0.5, 0.42, 0.14, 0.2, nil, nil, tone)
			bar(body, 0.5, 0.62, 0.08, 0.3, nil, nil, tone)
		end
	end
end

-- Fade a whole button out (0 = full ink, 1 = the glyph melts into the fill). The glyph blends
-- colour rather than fading, so overlapping strokes stay solid instead of showing their joins; the
-- fill just turns more see-through.
local function setDim(btn: GuiObject, dim: number)
	if btn:GetAttribute("Dim") == dim then
		return
	end
	btn:SetAttribute("Dim", dim)
	local box = btn:FindFirstChild("Icon", true)
	local face = btn:FindFirstChild("Face") :: Frame?
	if not box or not face then
		return
	end
	face.BackgroundTransparency = FACE_TRANSPARENCY + (1 - FACE_TRANSPARENCY) * dim * 0.6
	-- the exact ink token at rest, so the Halloween swap still recognises it
	local color = if dim == 0 then INK else INK:Lerp(face.BackgroundColor3, dim)
	for _, d in box:GetDescendants() do
		if d:GetAttribute("Glyph") and d:IsA("GuiObject") then
			d.BackgroundColor3 = color
		end
	end
end

-- `passThrough` builds a plain, inactive frame instead of a button: touches on it still reach the
-- game (and Roblox's touch camera), and the caller detects presses itself.
local function makeButton(parent: Instance, name: string, size: number, pos: UDim2, passThrough: boolean?): GuiObject
	local b = Theme.new(if passThrough then "Frame" else "TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		BackgroundTransparency = 1,
		Active = not passThrough,
	}, parent)
	if not passThrough then
		b.Text = ""
		b.AutoButtonColor = false
	end
	local scale = Theme.new("UIScale", { Scale = 1 }, b)
	local tone = TONES[name]
	local face = Theme.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = tone,
		BackgroundTransparency = FACE_TRANSPARENCY,
	}, b)
	Theme.round(face)
	-- the toy outline, a touch heavier on the big buttons; the tutorial pulses it (Outline) and
	-- restores these Rest values
	local thickness = math.max(Theme.StrokeToy, math.floor(size * 0.045))
	local outline = Theme.stroke(face, T.outline, thickness, 0.1)
	outline.Name = "Outline"
	outline:SetAttribute("RestColor", T.outline)
	outline:SetAttribute("RestThickness", thickness)
	outline:SetAttribute("RestTransparency", 0.1)
	-- cooldown: an ink disc that shrinks to nothing as the move comes back
	local cooldown = Theme.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = T.outline,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(0, 0),
		BorderSizePixel = 0,
	}, face)
	Theme.round(cooldown)
	local box = Theme.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(ICON, ICON),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, b)
	Glyphs[name](box, tone)
	if passThrough then
		return b
	end
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

-- Show the lock button's glyph and caption for a mode.
local function setLockGlyph(btn: GuiObject, mode: string)
	local box = btn:FindFirstChild("Icon")
	if box then
		for _, v in box:GetChildren() do
			if v:IsA("GuiObject") then
				v.Visible = v.Name == mode
			end
		end
	end
	local caption = btn:FindFirstChild("Caption") :: TextLabel?
	if caption then
		caption.Text = if mode == "Shift" then "SHIFT" elseif mode == "Aim" then "AIM" else "FREE"
	end
end

local function buildMobile()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	-- laid out from the real screen edge: in landscape a notch only cuts into the middle of the side,
	-- and these sit clear of it, so the safe-area margin would just push them away from the thumb
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	-- the whole cluster lives in one bottom-right frame that shrinks on short (phone) screens, so it
	-- never climbs up into the top-right corner where the Play again toggle and kill feed sit. Its
	-- frame is inactive: touches between the buttons still reach the game and the camera.
	local cluster = Theme.new("Frame", {
		Name = "Cluster",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(240, 290),
		BackgroundTransparency = 1,
		Active = false,
	}, gui)
	local clusterScale = Theme.new("UIScale", { Scale = 1 }, cluster)
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		clusterScale.Scale = math.clamp(vp.Y / 440, 0.75, 1)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	-- big Throw in the middle, Dodge above it, Catch down-left and Jump underneath, tucked to the right,
	-- and the camera lock up-left of Throw. Throw lets its touch through, so a finger that taps it
	-- can carry on dragging to turn the camera.
	local throw = makeButton(cluster, "Throw", 100, UDim2.new(1, -92, 1, -156), true)
	local dodge = makeButton(cluster, "Dodge", 62, UDim2.new(1, -92, 1, -247))
	local catch = makeButton(cluster, "Catch", 80, UDim2.new(1, -176, 1, -68))
	local jump = makeButton(cluster, "Jump", 70, UDim2.new(1, -91, 1, -63))
	local lock = makeButton(cluster, "Lock", 54, UDim2.new(1, -182, 1, -186))
	-- captioned like the hub's round buttons
	local caption = Theme.text(lock, 13, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(60, 16),
		FontFace = Theme.LabelFace,
		TextColor3 = T.paper,
		ZIndex = 3,
	})
	Theme.textStroke(caption, 2, T.outline)
	setLockGlyph(lock, LockController.mode)
	LockController.changed.Event:Connect(function(mode)
		setLockGlyph(lock, mode)
	end)
	lock.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			setInput("Touch")
			LockController.cycle()
		end
	end)
	InputController.buttons = { Throw = throw, Catch = catch, Dodge = dodge, Jump = jump, Lock = lock }
	jump.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- Humanoid.Jump would be reset by the default control script on the next frame, so start
		-- the jump state directly (only from the ground, never mid-ragdoll)
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if
			h
			and not h.PlatformStand
			and h.FloorMaterial ~= Enum.Material.Air
			and h:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		then
			h:ChangeState(Enum.HumanoidStateType.Jumping)
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

	-- Throw: a touch that starts inside its circle throws at once. The touch isn't held by a button,
	-- so Roblox's camera turns with it if the finger keeps dragging. Touches that land on another
	-- button first (gameProcessed) are ignored.
	local activeTouch: InputObject? = nil
	local throwScale = throw:FindFirstChildOfClass("UIScale") :: UIScale
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch or gameProcessed or activeTouch then
			return
		end
		if not gui.Enabled or not throw.Visible then
			return
		end
		local centre = throw.AbsolutePosition + throw.AbsoluteSize / 2
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if (p - centre).Magnitude > throw.AbsoluteSize.X / 2 then
			return
		end
		setInput("Touch")
		activeTouch = input
		throwScale.Scale = 0.9
		AimController.fire()
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input ~= activeTouch then
			return
		end
		activeTouch = nil
		Theme.tween(throwScale, Theme.Motion.Slow, { Scale = 1 }, Enum.EasingStyle.Back)
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
	local cooldownOf: { [GuiObject]: Frame } = setmetatable({}, { __mode = "k" }) :: any
	local lastFrac: { [GuiObject]: number } = setmetatable({}, { __mode = "k" }) :: any
	RunService.RenderStepped:Connect(function()
		local b = InputController.buttons
		if not b.Throw then
			return
		end
		local t = Workspace:GetServerTimeNow()
		local function fill(btn: GuiObject, readyAt: any, duration: number)
			local frac = if type(readyAt) == "number" then math.clamp((readyAt - t) / duration, 0, 1) else 0
			-- the overlay is found once per button (a recursive search every frame added up)
			local overlay = cooldownOf[btn]
			if not overlay or not overlay.Parent then
				local found = btn:FindFirstChild("Cooldown", true) :: Frame
				overlay = found
				cooldownOf[btn] = found
				lastFrac[btn] = nil
			end
			if lastFrac[btn] ~= frac then
				lastFrac[btn] = frac
				overlay.Size = UDim2.fromScale(frac, frac)
			end
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
