--!strict
-- Client entry point: presentation only. Controllers request actions; the server decides results.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"Net",
	"NeonController",
	"SoundController",
	"BallVisualController",
	"AimController",
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
