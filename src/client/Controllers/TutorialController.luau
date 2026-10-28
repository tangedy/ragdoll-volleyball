--!strict
-- Renders the server-owned tutorial step as one short card (<= 8 words) plus a pulsing pointer on
-- the exact mobile button when one applies. Text adapts to the current input device.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Net)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AimController = require(script.Parent.AimController)
local InputController = require(script.Parent.InputController)
local BallGuideController = require(script.Parent.BallGuideController)

local player = Players.LocalPlayer

local TutorialController = {}

local step = 0
local card: TextLabel
local cardHolder: Frame
local shownText = ""
local catchShownAt = 0

local function text(): (string?, string?)
	local input = AimController.lastInput
	local inMatch = (player:GetAttribute("Team") or "") ~= ""
	if step == 1 then
		return nil, nil -- floor arrows lead the player to a ball instead of text (BallGuideController)
	elseif step == 2 then
		if input == "Touch" then
			return "Tap THROW to hit your target!", "Throw"
		elseif input == "Gamepad" then
			return "Press RT to hit your target!", nil
		end
		return "Click to hit your target!", nil
	elseif step == 3 then
		return if inMatch then "Hit an enemy!" else "Launch the dummy!", nil
	elseif step == 4 then
		return "Stay on the court!", nil
	elseif step == 5 then
		-- catching is taught during downtime, not mid-fight
		local state = Net.MatchState:GetAttribute("State")
		if state == "RoundActive" and os.clock() - catchShownAt > 6 then
			return nil, nil
		end
		if input == "Touch" then
			return "Tap CATCH as a ball arrives!", "Catch"
		elseif input == "Gamepad" then
			return "Press LB as a ball arrives!", nil
		end
		return "Press E as a ball arrives!", nil
	end
	return nil, nil
end

-- Studio UI gallery hook.
function TutorialController.debugStep(n: number)
	step = n
	catchShownAt = os.clock()
end

function TutorialController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	-- a plain surface card with a "Tip" sticker (system messages stay plain: no character chatter)
	-- bottom right, just above the Play again pill (and above the touch buttons on phones)
	local holder = Theme.panel(gui, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.Space.L, 1, -76),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 56),
		Visible = false,
	}, 28)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 22) }, holder)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	Theme.autoScale(holder)
	Theme.sticker(holder, "Tip", Theme.Colors.Sun, { LayoutOrder = 1, Size = UDim2.fromOffset(0, 24) })
	card = Theme.text(holder, 20, {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		Text = "",
	})
	cardHolder = holder
end

function TutorialController.start()
	Net.on("Tutorial", function(d)
		if type(d.step) == "number" then
			step = d.step
			if step == 5 then
				catchShownAt = os.clock()
			end
		end
	end)
	local lastPointer: string? = nil
	RunService.RenderStepped:Connect(function()
		BallGuideController.enabled = step == 1
		local t, pointer = text()
		cardHolder.Visible = t ~= nil
		cardHolder.Position = if AimController.lastInput == "Touch"
			then UDim2.new(1, -12, 1, -320)
			else UDim2.new(1, -Theme.Space.L, 1, -76)
		if t then
			card.Text = t
			if t ~= shownText then
				Theme.pop(cardHolder, 0.6, Theme.Motion.Slow)
			end
		end
		shownText = t or ""
		-- point at the exact touch button with a breathing select-colored outline
		if pointer == nil and lastPointer == nil then
			return -- nothing pointed at now or last frame: the outlines are already at rest
		end
		lastPointer = pointer
		for name, b in InputController.buttons do
			local stroke = b:FindFirstChild("Outline", true) :: UIStroke?
			if stroke then
				local pulsing = pointer == name
				local restColor = stroke:GetAttribute("RestColor")
				local restThickness = stroke:GetAttribute("RestThickness")
				local restTransparency = stroke:GetAttribute("RestTransparency")
				stroke.Color = if pulsing
					then Theme.Colors.Select
					elseif typeof(restColor) == "Color3" then restColor
					else Theme.Colors.Outline
				stroke.Thickness = if pulsing
					then 5 + 2 * math.sin(os.clock() * 8)
					elseif type(restThickness) == "number" then restThickness
					else Theme.StrokeToy
				stroke.Transparency = if pulsing
					then 0
					elseif type(restTransparency) == "number" then restTransparency
					else 0
			end
		end
	end)
end

return TutorialController
