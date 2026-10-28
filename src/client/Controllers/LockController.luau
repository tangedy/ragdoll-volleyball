--!strict
-- Camera lock modes, cycled by the lock button (or Shift / R3):
--   Free  : normal Roblox movement, the character turns to face where it walks.
--   Shift : shift lock. The character always faces where the camera looks, so you can run in any
--           direction without spinning; the camera sits over the right shoulder and the mouse is
--           held in the center.
--   Aim   : the character always faces the nearest enemy, and the auto-aim always picks them.
-- Works the same on touch, where Roblox has no shift lock of its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local AimController = require(script.Parent.AimController)

local player = Players.LocalPlayer

local LockController = {}

LockController.mode = "Free"
LockController.changed = Instance.new("BindableEvent")

local BASE_OFFSET = Vector3.new(0, 1.2, 0) -- CharacterController's raised third-person view
local applied = false -- whether we're currently overriding rotation / camera / mouse

function LockController.set(mode: string)
	if mode == LockController.mode then
		return
	end
	LockController.mode = mode
	AimController.preferNearest = mode == "Aim"
	LockController.changed:Fire(mode)
end

function LockController.cycle()
	local modes = Config.Lock.Modes
	local i = table.find(modes, LockController.mode) or 1
	LockController.set(modes[i % #modes + 1])
end

local function release(humanoid: Humanoid?)
	if not applied then
		return
	end
	applied = false
	if humanoid then
		humanoid.AutoRotate = true
		humanoid.CameraOffset = BASE_OFFSET
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function face(rootPart: BasePart, dir: Vector3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 1e-3 then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flat)
	end
end

local function step()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = Workspace.CurrentCamera
	local mode = LockController.mode
	-- cutscenes own the camera, and a ragdolled body flops freely
	local usable = humanoid ~= nil
		and rootPart ~= nil
		and not humanoid.PlatformStand
		and camera.CameraType == Enum.CameraType.Custom
		and player:GetAttribute("Action") ~= "Ragdolled"
	if mode == "Free" or not usable or not humanoid or not rootPart then
		release(humanoid)
		return
	end
	applied = true
	humanoid.AutoRotate = false
	if mode == "Shift" then
		face(rootPart, camera.CFrame.LookVector)
		humanoid.CameraOffset = BASE_OFFSET + Vector3.new(Config.Lock.ShoulderOffset, 0, 0)
		if AimController.lastInput == "Mouse" then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	else
		humanoid.CameraOffset = BASE_OFFSET
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		local target = AimController.assistModel
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			face(rootPart, targetRoot.Position - rootPart.Position)
		elseif humanoid.MoveDirection.Magnitude > 0.1 then
			face(rootPart, humanoid.MoveDirection) -- nobody to face: turn with movement as normal
		end
	end
end

function LockController.init() end

function LockController.start()
	-- just after the default camera, which resets the mouse behavior every frame
	RunService:BindToRenderStep("RD_Lock", Enum.RenderPriority.Camera.Value + 1, step)
	player.CharacterAdded:Connect(function()
		applied = true -- re-apply (or release) on the new character
	end)
end

return LockController
