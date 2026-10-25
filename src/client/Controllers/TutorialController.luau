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
			return "Hold THROW to aim. Release to throw.", "Throw"
		elseif input == "Gamepad" then
			return "Hold RT to aim. Release to throw.", nil
		end
		return "Hold to aim. Release to throw.", nil
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
	-- gold sticker card that gently bobs
	local holder = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -122),
		Size = UDim2.fromOffset(440, 56),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
	}, gui)
	Theme.corner(holder, 18)
	Theme.gradient(holder, Theme.lighten(Theme.Colors.Gold, 0.3), Theme.Colors.GoldDark)
	Theme.stroke(holder, Theme.Colors.Ink, 3.5)
	card = Theme.label(holder, {
		Size = UDim2.new(1, -28, 1, -14),
		Position = UDim2.fromOffset(14, 7),
		Text = "",
	}, 3)
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
	RunService.RenderStepped:Connect(function()
		BallGuideController.enabled = step == 1
		local t, pointer = text()
		cardHolder.Visible = t ~= nil
		if t then
			card.Text = t
			if t ~= shownText then
				Theme.pop(cardHolder, 0.7, 0.3)
			end
			cardHolder.Position = UDim2.new(0.5, 0, 1, -122 + 4 * math.sin(os.clock() * 3))
		end
		shownText = t or ""
		for name, b in InputController.buttons do
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				local pulsing = pointer == name
				stroke.Color = if pulsing then Color3.fromRGB(255, 215, 60) else Theme.Colors.Ink
				stroke.Thickness = if pulsing then 5 + 2 * math.sin(os.clock() * 8) else 3.5
				stroke.Transparency = 0
			end
		end
	end)
end

return TutorialController
