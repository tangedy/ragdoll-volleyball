--!strict
-- Temporary R15 ragdoll (spec §11 "Ragdoll implementation").
-- Constraints are prepared once per character; only the relevant joints are toggled.
-- The Root joint stays enabled so HumanoidRootPart follows the torso and never falls through floors.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

type Rig = {
	pairs: { { motor: Motor6D, socket: BallSocketConstraint } },
	collide: { [BasePart]: boolean },
	active: boolean,
}

local RagdollService = {}

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local S: any

local LIMITS: { [string]: { upper: number, twist: number } } = {
	Neck = { upper = 30, twist = 40 },
	Waist = { upper = 20, twist = 20 },
	LeftShoulder = { upper = 90, twist = 60 },
	RightShoulder = { upper = 90, twist = 60 },
	LeftElbow = { upper = 80, twist = 5 },
	RightElbow = { upper = 80, twist = 5 },
	LeftHip = { upper = 60, twist = 30 },
	RightHip = { upper = 60, twist = 30 },
	LeftKnee = { upper = 80, twist = 5 },
	RightKnee = { upper = 80, twist = 5 },
}

function RagdollService.init(services: any)
	S = services
end

function RagdollService.prepare(character: Model)
	if rigs[character] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
	local rig: Rig = { pairs = {}, collide = {}, active = false }
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Name ~= "Root" and d.Part0 and d.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagA0_" .. d.Name
			a0.CFrame = d.C0
			a0.Parent = d.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagA1_" .. d.Name
			a1.CFrame = d.C1
			a1.Parent = d.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			local lim = LIMITS[d.Name] or { upper = 45, twist = 30 }
			socket.LimitsEnabled = true
			socket.UpperAngle = lim.upper
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -lim.twist
			socket.TwistUpperAngle = lim.twist
			socket.Enabled = false
			socket.Parent = d.Parent
			table.insert(rig.pairs, { motor = d, socket = socket })
		elseif d:IsA("BasePart") then
			rig.collide[d] = d.CanCollide
		end
	end
	rigs[character] = rig
end

function RagdollService.isRagdolled(character: Model): boolean
	local rig = rigs[character]
	return rig ~= nil and rig.active
end

local function setOwner(character: Model, owner: Player?)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(owner)
			end)
		end
	end
end

-- Ragdoll the character and apply one bounded velocity change to every limb (mass-independent,
-- so avatar size and accessories do not change competitive performance).
function RagdollService.ragdoll(character: Model, velocityChange: Vector3?)
	local rig = rigs[character]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rig or not humanoid then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	setOwner(character, nil) -- temporary server ownership during the launch
	rig.active = true
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	for _, p in rig.pairs do
		p.motor.Enabled = false
		p.socket.Enabled = true
	end
	for part in rig.collide do
		-- only body limbs collide; accessories and the hit proxy stay non-colliding to avoid snags
		if part.Parent == character and part.Name ~= "HumanoidRootPart" and part.Name ~= "HitProxy" then
			part.CanCollide = true
			part.CollisionGroup = "Ragdoll"
		end
	end
	setOwner(character, nil)
	if velocityChange then
		local maxSpeed = Config.Knockback.MaxSpeed
		for part in rig.collide do
			if part.Parent and not part.Anchored then
				local v = part.AssemblyLinearVelocity * 0.2 + velocityChange
				if v.Magnitude > maxSpeed then
					v = v.Unit * maxSpeed
				end
				part.AssemblyLinearVelocity = v
				part.AssemblyAngularVelocity = Vector3.new(
					math.random(-4, 4),
					math.random(-2, 2),
					math.random(-4, 4)
				)
			end
		end
	end
	if player and S then
		S.NetService.send(player, "Ragdoll", { on = true })
	end
end

-- Restore joints, collision and ownership. `upright` optionally places the root at a valid point.
function RagdollService.recover(character: Model, upright: Vector3?)
	local rig = rigs[character]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rig or not humanoid then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	rig.active = false
	for _, p in rig.pairs do
		p.socket.Enabled = false
		p.motor.Enabled = true
	end
	for part, collide in rig.collide do
		if part.Parent then
			part.CanCollide = collide
			part.CollisionGroup = "Characters"
		end
	end
	humanoid.PlatformStand = false
	if root then
		local pos = upright or root.Position
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.1 then
			flat = Vector3.zAxis
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
	end
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		setOwner(character, player)
		if S then
			S.NetService.send(player, "Ragdoll", { on = false })
		end
	end
end

return RagdollService
