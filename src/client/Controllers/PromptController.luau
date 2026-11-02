--!strict
-- Interaction prompts in the Toybox style. The hub's kiosks (Shop, Spin, Daily, and a limited
-- bundle's stand) use ProximityPrompts
-- with Style = Custom, so Roblox draws nothing of its own; this draws each one floating over the
-- thing it opens: the station's name in outlined paper text over a toned toy button with the key to press (E, or the gamepad button) and the action. The key still works
-- through the prompt itself; clicking or tapping the button triggers it the same way.
-- The group reward kiosk's answer (GroupRewardService) comes back here as a hint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local HUDController = require(script.Parent.HUDController)
local Net = require(script.Parent.Net)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
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
	BundlePrompt = T.sun, -- the Haunted Bundle's stand (BundleDisplayController)
	GroupRewardPrompt = T.leaf, -- the group reward kiosk (LobbyBuilder)
}
local GROUP_PROMPT = "GroupRewardPrompt"
-- what the kiosk says when it doesn't pay (GroupRewardService.claim's reasons)
local GROUP_HINTS: { [string]: string } = {
	NotMember = "Join the group, then come back!",
	Claimed = "Already claimed. Thanks for joining!",
	Tutorial = "Finish the tutorial first!",
	Error = "Couldn't check the group. Try again soon!",
	NotReady = "One moment, still loading…",
}
local BUTTON = Vector2.new(250, 58)
local KEY = 34

local shown: { [ProximityPrompt]: BillboardGui } = {}
local inputs: { [ProximityPrompt]: Enum.ProximityPromptInputType } = {}
local groupClaimed = false -- this account has had the group reward (Profile push)

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
		inputs[prompt] = nil
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
	local action = prompt.ActionText
	if prompt.Name == GROUP_PROMPT and groupClaimed then
		tone, action = T.surfaceSunk, "Claimed ✓"
	end
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
	local button = Theme.button(root, action, tone, {
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
	inputs[prompt] = inputType
	Theme.pop(root, 0.6, Theme.Motion.Slow)
end

-- The hint for a group reward claim, and the kiosk's button turns to Claimed once it has paid.
local function rewardLine(reward: { [string]: any }): string
	if reward.kind == "Spin" then
		local wheel = Config.Spin.Wheels[reward.wheel]
		return ("🎁 %s! Use it in Spin"):format(if wheel then wheel.Name else "Bonus spin")
	elseif reward.kind == "Coins" then
		return ("🎁 +%d coins!"):format(reward.coins or 0)
	end
	return "🎁 Reward claimed!"
end

local function refreshGroupPrompt()
	for prompt, inputType in table.clone(inputs) do
		if prompt.Name == GROUP_PROMPT then
			show(prompt, inputType)
		end
	end
end

function PromptController.start()
	Net.on("Profile", function(data)
		local claimed = data.groupReward == true
		if claimed ~= groupClaimed then
			groupClaimed = claimed
			refreshGroupPrompt()
		end
	end)
	Net.on("GroupReward", function(data)
		if data.ok then
			SoundController.play("UISuccess")
			HUDController.hint(rewardLine(data.reward or {}), 3)
		else
			SoundController.play("UIError")
			HUDController.hint(GROUP_HINTS[data.reason] or GROUP_HINTS.Error, 2.4)
		end
	end)
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
