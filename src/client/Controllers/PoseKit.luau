--!strict
-- Pose toolkit shared by finishers and intro poses. A pose is a set of segment directions in
-- UpperTorso space (+X = the character's right, -Z = forward, +Y = up), plus optional head and waist
-- angles. Joint rotations are solved from the rig's own attachments, so poses fit any body shape,
-- on new (AnimationConstraint) and classic (Motor6D) R15 rigs alike. Holding a pose writes joint
-- Transforms every Stepped, after the Animator, so it wins over the idle/walk animation on the
-- arms, head and waist while the legs keep animating. Purely local (nothing replicates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IntroPoses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IntroPoses"))

local PoseKit = {}

type SegmentDirs = { upper: Vector3, fore: Vector3 }
-- arms are optional; `neck` tilts the head in degrees (+ = look up, - = bow down)
type PoseDef = { Right: SegmentDirs?, Left: SegmentDirs?, neck: number?, waist: number?, twist: number? }

local REST_R = { upper = Vector3.new(0.12, -1, 0.02), fore = Vector3.new(0.08, -1, -0.12) }
local REST_L = { upper = Vector3.new(-0.12, -1, 0.02), fore = Vector3.new(-0.08, -1, -0.12) }

local POSES: { [string]: PoseDef } = {
	CrossArms = {
		Right = { upper = Vector3.new(-0.02, -0.72, -0.7), fore = Vector3.new(-1, 0.2, 0.02) },
		Left = { upper = Vector3.new(0.02, -0.8, -0.6), fore = Vector3.new(1, -0.02, -0.18) },
	},
	ArmsUp = {
		Right = { upper = Vector3.new(0.35, 0.94, 0), fore = Vector3.new(0.2, 1, 0) },
		Left = { upper = Vector3.new(-0.35, 0.94, 0), fore = Vector3.new(-0.2, 1, 0) },
	},
	-- hands out in front of the chest, ready to catch
	Catch = {
		Right = { upper = Vector3.new(0.3, -0.45, -0.85), fore = Vector3.new(-0.3, 0.2, -1) },
		Left = { upper = Vector3.new(-0.3, -0.45, -0.85), fore = Vector3.new(0.3, 0.2, -1) },
		neck = -10,
	},
	-- holding something up over a bowed head
	RaiseOverhead = {
		Right = { upper = Vector3.new(0.45, 0.88, -0.2), fore = Vector3.new(-0.65, 0.7, -0.15) },
		Left = { upper = Vector3.new(-0.45, 0.88, -0.2), fore = Vector3.new(0.65, 0.7, -0.15) },
		neck = -55,
	},
	-- arms flung wide to the sides, palms forward (an orb in each hand)
	ArmsSpread = {
		Right = { upper = Vector3.new(1, -0.15, -0.3), fore = Vector3.new(0.85, 0.2, -0.5) },
		Left = { upper = Vector3.new(-1, -0.15, -0.3), fore = Vector3.new(-0.85, 0.2, -0.5) },
	},
	-- right arm straight out, finger pointed at the target
	PointForward = {
		Right = { upper = Vector3.new(0.12, -0.05, -1), fore = Vector3.new(0.02, 0.04, -1) },
		Left = REST_L,
	},
	BowHead = { Right = REST_R, Left = REST_L, neck = -60 },
	-- right arm straight out in front, palm toward something arriving
	ReachOut = {
		Right = { upper = Vector3.new(0.12, -0.02, -1), fore = Vector3.new(0.02, 0.06, -1) },
		Left = REST_L,
	},
	-- right arm cocked up and back, left arm forward for balance
	WindUp = {
		Right = { upper = Vector3.new(0.45, 0.55, 0.7), fore = Vector3.new(0.05, 1, 0.35) },
		Left = { upper = Vector3.new(-0.25, -0.15, -0.95), fore = Vector3.new(-0.1, 0.1, -1) },
		neck = 5,
	},
	-- follow-through after the throw
	ThrowFollow = {
		Right = { upper = Vector3.new(-0.25, -0.25, -0.93), fore = Vector3.new(-0.35, -0.45, -0.82) },
		Left = { upper = Vector3.new(-0.3, -0.6, 0.55), fore = Vector3.new(-0.2, -0.9, 0.4) },
		neck = -8,
	},
	LookUp = { Right = REST_R, Left = REST_L, neck = 12 },
}

type JointInfo = { inst: Instance, f0: CFrame, f1: CFrame }

local function findJoint(model: Model, name: string): JointInfo?
	for _, d in model:GetDescendants() do
		if d.Name == name then
			if d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
				return { inst = d :: Instance, f0 = d.Attachment0.CFrame, f1 = d.Attachment1.CFrame }
			elseif d:IsA("Motor6D") then
				return { inst = d :: Instance, f0 = d.C0, f1 = d.C1 }
			end
		end
	end
	return nil
end

-- Solve a pose into joint Transforms. Returns { [jointInstance] = Transform }.
local function solvePose(model: Model, poseName: string): { [Instance]: CFrame }
	local pose = POSES[poseName]
	local out: { [Instance]: CFrame } = {}
	if not pose then
		return out
	end
	for _, side in { "Right", "Left" } do
		local dirs = (pose :: any)[side] :: SegmentDirs?
		local sh = findJoint(model, side .. "Shoulder")
		local el = findJoint(model, side .. "Elbow")
		local wr = findJoint(model, side .. "Wrist")
		if not (dirs and sh and el and wr) then
			continue
		end
		-- rest direction of a segment in its joint frame: toward the next joint along the limb
		local upperRest = sh.f1:VectorToObjectSpace(el.f0.Position - sh.f1.Position).Unit
		local tS = CFrame.fromRotationBetweenVectors(upperRest, sh.f0:VectorToObjectSpace(dirs.upper.Unit))
		out[sh.inst] = tS
		local upperInTorso = sh.f0 * tS * sh.f1:Inverse()
		local foreInUpper = upperInTorso:VectorToObjectSpace(dirs.fore.Unit)
		local foreRest = el.f1:VectorToObjectSpace(wr.f0.Position - el.f1.Position).Unit
		out[el.inst] = CFrame.fromRotationBetweenVectors(foreRest, el.f0:VectorToObjectSpace(foreInUpper))
	end
	if pose.waist or pose.twist then
		local waist = findJoint(model, "Waist")
		if waist then
			-- bend about the lower torso's right axis, turn about its up axis
			local pitchAxis = waist.f0:VectorToObjectSpace(Vector3.xAxis)
			local yawAxis = waist.f0:VectorToObjectSpace(Vector3.yAxis)
			out[waist.inst] = CFrame.fromAxisAngle(pitchAxis, math.rad(pose.waist or 0))
				* CFrame.fromAxisAngle(yawAxis, math.rad(pose.twist or 0))
		end
	end
	if pose.neck then
		local neck = findJoint(model, "Neck")
		if neck then
			-- pitch about the torso's right axis, expressed in the neck joint's frame
			local axis = neck.f0:VectorToObjectSpace(Vector3.xAxis)
			out[neck.inst] = CFrame.fromAxisAngle(axis, math.rad(pose.neck))
		end
	end
	return out
end

local activePoses: { [() -> ()]: boolean } = {}
local poseByModel: { [Instance]: () -> () } = {}

-- Hold a pose on a character, blending in from whatever it is doing now. Starting a new pose on
-- the same character replaces the old one. Returns a stop function (also called on cleanup).
function PoseKit.hold(model: any, poseName: string, blendIn: number?): () -> ()
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return function() end
	end
	local previous = poseByModel[model]
	local targets = solvePose(model, poseName)
	local start = os.clock()
	local blend = math.max(blendIn or 0.25, 0.01)
	local from: { [Instance]: CFrame } = {}
	for j in targets do
		from[j] = (j :: any).Transform
	end
	if previous then
		previous()
	end
	local conn = RunService.Stepped:Connect(function()
		local a = math.clamp((os.clock() - start) / blend, 0, 1)
		a = 1 - (1 - a) ^ 3
		for j, cf in targets do
			if j.Parent then
				(j :: any).Transform = from[j]:Lerp(cf, a)
			end
		end
	end)
	local stop
	stop = function()
		conn:Disconnect()
		activePoses[stop] = nil
		if poseByModel[model] == stop then
			poseByModel[model] = nil
		end
	end
	activePoses[stop] = true
	poseByModel[model] = stop
	return stop
end

-- Intro pose frames live in Shared.IntroPoses (shared so the server tests can check them).
for name, frame in IntroPoses.Frames do
	POSES[name] = frame :: any
end

function PoseKit.has(poseName: string): boolean
	return POSES[poseName] ~= nil
end

-- Stop every pose this module is holding (any owner).
function PoseKit.stopAll()
	for stop in activePoses do
		stop()
	end
end

-- Loop an intro pose's frames on a character until the returned stop function is called.
function PoseKit.playSequence(model: any, poseId: string?): () -> ()
	local pose = IntroPoses.get(poseId)
	local running = true
	local current: (() -> ())? = nil
	task.spawn(function()
		while running do
			for _, step in pose.Frames do
				if not running then
					break
				end
				current = PoseKit.hold(model, step.frame, pose.Blend)
				task.wait(step.hold)
			end
		end
	end)
	return function()
		running = false
		if current then
			current()
		end
	end
end

return PoseKit
