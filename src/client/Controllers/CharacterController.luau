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
	if not h or player.Character ~= character then
		return -- already replaced by a newer character: never point the camera at this one
	end
	h:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	h.CameraOffset = Vector3.new(0, 1.2, 0)
	local camera = workspace.CurrentCamera
	camera.CameraSubject = h
	camera.CameraType = Enum.CameraType.Custom
	-- your own name tag sits right in the middle of your view; everyone else still sees it
	local head = character:WaitForChild("Head", 5)
	local tag = head and head:WaitForChild("NameTag", 5)
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = false
	end
end

-- Put the camera behind `root`, looking past it at `focus` (same framing as the round start).
function CharacterController.faceCameraAt(root: BasePart, focus: Vector3)
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Custom then
		return -- a cutscene owns the camera
	end
	local flat = Vector3.new(focus.X - root.Position.X, 0, focus.Z - root.Position.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
	local camPos = root.Position - flat * 12 + Vector3.new(0, 5, 0)
	camera.CFrame = CFrame.lookAt(camPos, Vector3.new(focus.X, root.Position.Y + 1, focus.Z))
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
	-- spawning into the hub, or (re)spawning after an elimination: the server faces the character at
	-- the court; swing the camera in behind it so the action is the first thing you see
	local faceToken = 0
	Net.on("FaceCourt", function(d)
		if typeof(d.focus) ~= "Vector3" then
			return
		end
		faceToken += 1
		local token = faceToken
		local character = player.Character or player.CharacterAdded:Wait()
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		task.wait(0.15) -- let the server's teleport replicate first
		if not root or token ~= faceToken or player.Character ~= character then
			return
		end
		CharacterController.faceCameraAt(root, d.focus)
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
