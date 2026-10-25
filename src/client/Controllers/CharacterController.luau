--!strict
-- Local character handling: applies server-approved dodges, mirrors ragdoll state locally, keeps the
-- slightly elevated third-person view, and disables the reset button (resets are server-managed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DodgeMotion = require(Shared.DodgeMotion)
local Net = require(script.Parent.Net)

local player = Players.LocalPlayer

local CharacterController = {}

local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not h then
		return
	end
	h:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	h.CameraOffset = Vector3.new(0, 1.2, 0)
	local camera = workspace.CurrentCamera
	camera.CameraSubject = h
	camera.CameraType = Enum.CameraType.Custom
end

function CharacterController.init() end

function CharacterController.start()
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	-- each round countdown, swing the camera behind you facing the court (teleports keep the old yaw)
	Net.MatchState:GetAttributeChangedSignal("State"):Connect(function()
		if Net.MatchState:GetAttribute("State") ~= "RoundCountdown" or (player:GetAttribute("Team") or "") == "" then
			return
		end
		task.wait(0.15) -- let the spawn teleport replicate
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
			local camera = workspace.CurrentCamera
			camera.CFrame = CFrame.lookAt(root.Position - flat * 12 + Vector3.new(0, 5, 0), root.Position + flat * 10)
		end
	end)
	Net.on("DodgeAccepted", function(d)
		local character = player.Character
		if character and typeof(d.dir) == "Vector3" then
			DodgeMotion.apply(character, d.dir)
		end
	end)
	Net.on("Ragdoll", function(d)
		local h = humanoid()
		if not h then
			return
		end
		if d.on then
			h:ChangeState(Enum.HumanoidStateType.Physics)
		else
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

return CharacterController
