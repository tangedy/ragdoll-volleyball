--!strict
-- Temporary R15 ragdoll (spec §11 "Ragdoll implementation").
-- Joints are prepared once per character; only the relevant joints are toggled.
-- The Root joint stays enabled so HumanoidRootPart follows the torso and never falls through floors.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

-- A toggleable joint. New-style R15 rigs (Roblox's avatar joint upgrade) pose each limb with an
-- AnimationConstraint and already ship a limited BallSocketConstraint per joint: disabling the
-- AnimationConstraint lets the socket take over. Classic Motor6D rigs get a socket made for them.
type Joint = { driver: Instance, socket: BallSocketConstraint?, ownSocket: boolean }

type Rig = {
	joints: { Joint },
	collide: { [BasePart]: boolean },
	active: boolean,
}

local RagdollService = {}

local rng = Random.new()
local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local S: any

-- Limits for classic Motor6D rigs only (new-style rigs keep Roblox's anatomical socket limits).
local LIMITS: { [string]: { upper: number, twist: number } } = {
	Neck = { upper = 40, twist = 45 },
	Waist = { upper = 30, twist = 25 },
	LeftShoulder = { upper = 110, twist = 85 },
	RightShoulder = { upper = 110, twist = 85 },
	LeftElbow = { upper = 20, twist = 60 },
	RightElbow = { upper = 20, twist = 60 },
	LeftHip = { upper = 40, twist = 45 },
	RightHip = { upper = 40, twist = 45 },
	LeftKnee = { upper = 5, twist = 60 },
	RightKnee = { upper = 5, twist = 60 },
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
	local rig: Rig = { joints = {}, collide = {}, active = false }
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Name ~= "Root" then
			-- new-style rig: the matching ball socket sits next to it ("<Joint>BallSocket")
			local socket = d.Parent and d.Parent:FindFirstChild(d.Name .. "BallSocket")
			table.insert(rig.joints, {
				driver = d :: Instance,
				socket = if socket and socket:IsA("BallSocketConstraint") then socket else nil,
				ownSocket = false,
			})
		elseif d:IsA("Motor6D") and d.Name ~= "Root" and d.Part0 and d.Part1 then
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
			table.insert(rig.joints, { driver = d :: Instance, socket = socket, ownSocket = true })
		elseif d:IsA("BasePart") then
			rig.collide[d] = d.CanCollide
		end
	end
	rigs[character] = rig
end

-- Floppy (true) or posed (false).
local function setLimp(rig: Rig, limp: boolean)
	for _, j in rig.joints do
		(j.driver :: any).Enabled = not limp
		if j.socket and j.ownSocket then
			j.socket.Enabled = limp
		end
	end
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
function RagdollService.ragdoll(character: Model, velocityChange: Vector3?, maxSpeed: number?)
	local rig = rigs[character]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rig or not humanoid then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	setOwner(character, nil) -- temporary server ownership during the launch
	-- a bot's facing constraint (BotService) must never stiffen the tumble, even for one step
	local root = character:FindFirstChild("HumanoidRootPart")
	local facing = root and root:FindFirstChild("BotFace")
	if facing and facing:IsA("AlignOrientation") then
		facing.Enabled = false
	end
	rig.active = true
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	setLimp(rig, true)
	for part in rig.collide do
		-- only body limbs collide; accessories and the hit proxy stay non-colliding to avoid snags
		if part.Parent == character and part.Name ~= "HumanoidRootPart" and part.Name ~= "HitProxy" then
			part.CanCollide = true
			part.CollisionGroup = "Ragdoll"
		end
	end
	if velocityChange then
		local kb = Config.Knockback
		local cap = maxSpeed or kb.MaxSpeed
		-- a shared tumble about a random axis so the whole body flips, plus independent limb spin
		-- and flail so arms and legs windmill around their floppy joints
		local axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
		axis = if axis.Magnitude > 0.1 then axis.Unit else Vector3.xAxis
		local tumble = axis * kb.TumbleSpin
		for part in rig.collide do
			if part.Parent and not part.Anchored then
				local isLimb = part.Parent == character and part.Name ~= "HumanoidRootPart" and part.Name ~= "HitProxy"
				local flail = if isLimb
					then Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)) * kb.LimbFlail
					else Vector3.zero
				local v = part.AssemblyLinearVelocity * 0.2 + velocityChange + flail
				if v.Magnitude > cap then
					v = v.Unit * cap
				end
				part.AssemblyLinearVelocity = v
				local limbSpin = if isLimb
					then Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * kb.LimbSpin
					else Vector3.zero
				part.AssemblyAngularVelocity = tumble + limbSpin
			end
		end
	end
	if player and S then
		S.NetService.send(player, "Ragdoll", { on = true })
	end
end

-- Mark a flung body as having left the court: it can now hit the one-way edge walls, so it can
-- fall away from the court but never bounce back onto it.
function RagdollService.markEjected(character: Model)
	local rig = rigs[character]
	if not rig or not rig.active then
		return
	end
	for part in rig.collide do
		if part.Parent == character and part.Name ~= "HumanoidRootPart" and part.Name ~= "HitProxy" then
			part.CollisionGroup = "Ejected"
		end
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
	setLimp(rig, false)
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
