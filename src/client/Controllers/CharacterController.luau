--!strict
-- Local character handling: predicts dodges (and applies server-approved ones it didn't predict),
-- mirrors ragdoll state locally, keeps the slightly elevated third-person view, and disables the
-- reset button (resets are server-managed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Config = require(Shared.Config)
local DodgeMotion = require(Shared.DodgeMotion)
local Net = require(script.Parent.Net)
local SoundController = require(script.Parent.SoundController)

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
-- With `turnBody`, the character is turned to match: you own its physics, and shift lock would
-- otherwise have already turned it back to the old camera direction.
function CharacterController.faceCameraAt(root: BasePart, focus: Vector3, turnBody: boolean?)
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Custom then
		return -- a cutscene owns the camera
	end
	local flat = Vector3.new(focus.X - root.Position.X, 0, focus.Z - root.Position.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
	if turnBody then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
	local camPos = root.Position - flat * 12 + Vector3.new(0, 5, 0)
	camera.CFrame = CFrame.lookAt(camPos, Vector3.new(focus.X, root.Position.Y + 1, focus.Z))
end

-- Dodge prediction. You own your character's physics, so waiting for the server's DodgeAccepted
-- before moving only added a full round trip of input lag (and the server saw you move a round
-- trip late, so a dodge that looked in time could still get hit). When the server's own rules
-- (mirrored from CombatService.doDodge) say the dodge will go through, it starts on the press; the
-- server's acknowledgement is then consumed instead of applied a second time.
local DODGE_MARGIN = 0.05 -- the local cooldown ends a touch later than the server's, so it never runs ahead
local ACK_WINDOW = 1 -- an acknowledgement this long after the prediction belongs to it
local pendingDodges = 0
local lastPredictAt = 0
local predictedReadyAt = 0

function CharacterController.predictDodge(dir: Vector3): boolean
	local character = player.Character
	local h = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not h or h.PlatformStand then
		return false
	end
	local t = Workspace:GetServerTimeNow()
	local readyAt = player:GetAttribute("DodgeReadyAt")
	if (type(readyAt) == "number" and t < readyAt) or t < predictedReadyAt then
		return false
	end
	local action = player:GetAttribute("Action")
	if action ~= "Idle" and action ~= "Charging" then
		return false -- not while catching, ragdolled or in throw recovery
	end
	local status = player:GetAttribute("Status")
	if status ~= "Active" and status ~= "Lobby" and status ~= "Jailed" then
		return false
	end
	local inMatch = (player:GetAttribute("Team") or "") ~= ""
	if inMatch and Net.MatchState:GetAttribute("State") == "RoundCountdown" then
		return false -- frozen for the countdown
	end
	predictedReadyAt = t + Config.Player.DodgeCooldown + DODGE_MARGIN
	if os.clock() - lastPredictAt > ACK_WINDOW then
		pendingDodges = 0 -- an earlier prediction the server never confirmed
	end
	pendingDodges += 1
	lastPredictAt = os.clock()
	DodgeMotion.apply(character, dir)
	SoundController.play("Dodge")
	return true
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
	-- each round countdown, swing the camera behind you facing the enemy (teleports keep the old yaw).
	-- Straight down the court from your team's end, not your body's facing: shift lock has already
	-- turned the body back to the old camera direction by now.
	Net.MatchState:GetAttributeChangedSignal("State"):Connect(function()
		local team = player:GetAttribute("Team")
		if Net.MatchState:GetAttribute("State") ~= "RoundCountdown" or type(team) ~= "string" or team == "" then
			return
		end
		task.wait(0.15) -- let the spawn teleport replicate
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- turning the body writes its CFrame, so only once the teleport is really here: writing it at a
		-- stale spot (still in the hub) would undo the server's move onto the court
		if root and ArenaLayout.onHalf(team, root.Position, 0, -2) then
			local towardEnemy = Vector3.zAxis * -ArenaLayout.teamSign(team)
			CharacterController.faceCameraAt(root, root.Position + towardEnemy * 20, true)
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
		local from = if typeof(d.from) == "Vector3" then d.from else nil
		-- let the server's teleport replicate first. It travels apart from this message, so when we
		-- know the spot, wait for the body to actually get there: aiming from where it fell (out in
		-- the void past the other end) would point the camera the wrong way down the court
		local waited = 0
		repeat
			task.wait(0.05)
			waited += 0.05
		until waited >= 0.15 and (not from or not root or (root.Position - from).Magnitude < 8 or waited >= 1)
		if not root or token ~= faceToken or player.Character ~= character then
			return
		end
		CharacterController.faceCameraAt(root, d.focus, from ~= nil)
	end)
	Net.on("DodgeAccepted", function(d)
		if pendingDodges > 0 and os.clock() - lastPredictAt < ACK_WINDOW then
			pendingDodges -= 1
			return -- already moving (and heard) since the press
		end
		pendingDodges = 0
		local character = player.Character
		if character and typeof(d.dir) == "Vector3" then
			DodgeMotion.apply(character, d.dir)
		end
		SoundController.play("Dodge")
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
