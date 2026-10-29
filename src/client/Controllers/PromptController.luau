--!strict
-- Interaction prompts in the Toybox style. The hub's kiosks (Shop, Spin, Daily) use ProximityPrompts
-- with Style = Custom, so Roblox draws nothing of its own; this draws each one floating over the
-- thing it opens: the station's name in outlined paper text over a toned toy button with the key to press (E, or the gamepad button) and the action. The key still works
-- through the prompt itself; clicking or tapping the button triggers it the same way.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local HUDController = require(script.Parent.HUDController)
local ShopController = require(script.Parent.ShopController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local new = Theme.new

local PromptController = {}

-- each prompt wears the color of the hub button for the same destination
local TONES: { [string]: Color3 } = {
	ShopPrompt = T.sun,
	SpinPrompt = T.candy,
	DailyPrompt = T.leaf,
}
local BUTTON = Vector2.new(250, 58)
local KEY = 34

local shown: { [ProximityPrompt]: BillboardGui } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string?
	if inputType == Enum.ProximityPromptInputType.Touch then
		return nil -- the button itself is the tap target
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function hide(prompt: ProximityPrompt)
	local bb = shown[prompt]
	if bb then
		shown[prompt] = nil
		bb:Destroy()
	end
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	hide(prompt)
	local anchor = prompt.Parent
	if not anchor or not (anchor:IsA("BasePart") or anchor:IsA("Attachment")) then
		return
	end
	local tone = TONES[prompt.Name] or T.sky
	local bb = new("BillboardGui", {
		Name = "Prompt_" .. prompt.Name,
		Adornee = anchor,
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(BUTTON.X + 24, 40 + BUTTON.Y + Theme.Ledge + 12),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	local root = new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, bb)
	local title = Theme.label(root, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 32),
		Text = prompt.ObjectText,
		ZIndex = 2,
	}, 2.5)
	new("UITextSizeConstraint", { MaxTextSize = 26 }, title)
	local button = Theme.button(root, prompt.ActionText, tone, {
		Name = "Action",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(BUTTON.X, BUTTON.Y + Theme.Ledge),
		ZIndex = 3,
		silent = true, -- the sheet it opens answers with its own sound
	})
	local key = keyText(prompt, inputType)
	local face = button:FindFirstChild("Face") :: Frame
	local label = face:FindFirstChild("Label") :: TextLabel
	if key then
		-- the key disc, like the Q Dodge / E Catch legends: ink with a paper letter
		local disc = new("Frame", {
			Name = "Key",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(KEY, KEY),
			BackgroundColor3 = T.ink,
			ZIndex = button.ZIndex + 3,
		}, face)
		Theme.round(disc)
		Theme.stroke(disc, T.outline, 2)
		Theme.text(disc, 17, {
			Size = UDim2.fromScale(1, 1),
			Text = key,
			TextColor3 = T.paper,
			ZIndex = button.ZIndex + 4,
		})
		label.Position = UDim2.new(0.5, (KEY + 10) / 2, 0.5, 0)
		label.Size = UDim2.new(1, -(KEY + 10) - 28, 0.5, 0)
	end
	button.Activated:Connect(function()
		prompt:InputHoldBegin()
		prompt:InputHoldEnd()
	end)
	shown[prompt] = bb
	Theme.pop(root, 0.6, Theme.Motion.Slow)
end

function PromptController.start()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	-- out of the way while a hub sheet is up or a cinematic plays; gone if its prompt goes
	RunService.RenderStepped:Connect(function()
		local visible = not ShopController.getBackdrop().Visible and not HUDController.cinematic
		for prompt, bb in shown do
			if not prompt.Parent or not prompt.Enabled then
				hide(prompt)
			elseif bb.Enabled ~= visible then
				bb.Enabled = visible
			end
		end
	end)
end

return PromptController
