--!strict
-- Client entry point: presentation only. Controllers request actions; the server decides results.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"Net",
	"NeonController",
	"GraphicsController",
	"SoundController",
	"BallVisualController",
	"HalloweenController",
	"AimController",
	"LockController",
	"OutlineController",
	"InputController",
	"HUDController",
	"EffectsController",
	"CharacterController",
	"SpectatorController",
	"BallGuideController",
	"PracticeController",
	"TutorialController",
	"FinisherController",
	"IntroController",
	"HubController",
	"ShopController",
	"SpinController",
	"QuestController",
	"PromptController",
	"CoinShopController",
	"FavoriteController",
	"DebugController",
}

local C: { [string]: any } = {}
for _, name in ORDER do
	C[name] = require(Controllers:WaitForChild(name)) :: any
end
for _, name in ORDER do
	if C[name].init then
		C[name].init()
	end
end
for _, name in ORDER do
	if C[name].start then
		C[name].start()
	end
end

-- Studio-only dev keys (the server also refuses them outside Studio).
if RunService:IsStudio() then
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F6 then
			C.Net.request(C.Net.Actions.Dev, { cmd = "SkipIntermission" })
		elseif input.KeyCode == Enum.KeyCode.F7 then
			C.Net.request(C.Net.Actions.Dev, { cmd = "ForceOvertime" })
		elseif input.KeyCode == Enum.KeyCode.F9 then
			C.Net.request(C.Net.Actions.Dev, { cmd = "RunTests" })
		elseif input.KeyCode == Enum.KeyCode.F10 then
			C.Net.request(C.Net.Actions.Dev, { cmd = "LaunchMe" })
		elseif input.KeyCode == Enum.KeyCode.G then
			C.Net.request(C.Net.Actions.Dev, { cmd = "GiveCoins" })
		elseif input.KeyCode == Enum.KeyCode.T then
			C.Net.request(C.Net.Actions.Dev, { cmd = "SkipToFinisher" })
		end
	end)
end

-- H toggles Halloween and ; goes to the dev room and back: in Studio, or for the game's owner on a
-- live server (HalloweenService.canToggle decides; for a group-owned game the client can't tell, so
-- it asks and the server says no).
local Players = game:GetService("Players")
local me = Players.LocalPlayer
if RunService:IsStudio() or game.CreatorType == Enum.CreatorType.Group or me.UserId == game.CreatorId then
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.H then
			C.Net.request(C.Net.Actions.Dev, { cmd = "ToggleHalloween" })
		elseif input.KeyCode == Enum.KeyCode.Semicolon then
			C.Net.request(C.Net.Actions.Dev, { cmd = "DevRoom" })
		end
	end)
end
