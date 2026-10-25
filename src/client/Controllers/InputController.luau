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

-- Big round action button: gradient face, ink outline, label, cooldown shade, squash on press.
local function makeButton(parent: Instance, name: string, text: string, size: number, pos: UDim2, color: Color3): TextButton
	local b = Theme.new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.05,
		Text = "",
		AutoButtonColor = false,
		Active = true,
	}, parent)
	Theme.round(b)
	Theme.gradient(b, Theme.lighten(color, 0.3), Theme.darken(color, 0.15), 90)
	local stroke = Theme.stroke(b, Theme.Colors.Ink, 3.5)
	stroke.Name = "Outline"
	Theme.label(b, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.4),
		Text = text,
		ZIndex = 3,
	}, 2.5)
	local cd = Theme.new("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, b)
	Theme.round(cd)
	local scale = Theme.new("UIScale", nil, b)
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			scale.Scale = 0.9
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			scale.Scale = 1
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
	local throw = makeButton(gui, "Throw", "THROW", 112, UDim2.new(1, -205, 1, -90), Color3.fromRGB(230, 70, 60))
	local catch = makeButton(gui, "Catch", "CATCH", 76, UDim2.new(1, -310, 1, -70), Color3.fromRGB(60, 170, 90))
	local dodge = makeButton(gui, "Dodge", "DODGE", 76, UDim2.new(1, -235, 1, -200), Color3.fromRGB(60, 120, 230))
	InputController.buttons = { Throw = throw, Catch = catch, Dodge = dodge }

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
			(btn:FindFirstChild("Cooldown") :: Frame).Size = UDim2.fromScale(1, frac)
		end
		fill(b.Dodge, player:GetAttribute("DodgeReadyAt"), Config.Player.DodgeCooldown)
		fill(b.Catch, player:GetAttribute("CatchReadyAt"), Config.Player.CatchCooldown)
		local holding = AimController.holding()
		b.Throw.BackgroundTransparency = if holding then 0.05 else 0.6
		b.Catch.BackgroundTransparency = if holding then 0.6 else 0.15
	end)
end

return InputController
