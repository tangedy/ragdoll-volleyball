--!strict
-- Plays finisher cutscenes: for real on the match-ending knockout (server event "Finisher"), or as
-- a local-only preview from the shop. Loads the named module from ReplicatedStorage.Shared.Finishers
-- and always restores the camera, HUD and any poses/effects, even if a finisher errors.
-- See Shared/Finishers/README.md for the module contract and the toolkit passed in `ctx`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local EffectsController = require(script.Parent.EffectsController)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer
local Finishers = Shared:WaitForChild("Finishers")

local FinisherController = {}

FinisherController.playing = false

local function rootOf(model: any): BasePart?
	if typeof(model) == "Instance" and model:IsA("Model") then
		return model:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

local function runFor(seconds: number, fn: (number, number) -> ())
	local start = os.clock()
	local done = false
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local alpha = math.clamp((os.clock() - start) / math.max(seconds, 1e-3), 0, 1)
		local ok: boolean, err: any = pcall(fn :: any, alpha, dt)
		if not ok then
			warn("[Finisher] " .. tostring(err))
			done = true
		end
		if alpha >= 1 then
			done = true
		end
		if done then
			conn:Disconnect()
		end
	end)
	while not done do
		task.wait()
	end
end

-- Poses -------------------------------------------------------------------------------------------
-- A pose is a set of segment directions in UpperTorso space (+X = the character's right,
-- -Z = forward, +Y = up). Joint rotations are solved from the rig's own attachments, so poses fit
-- any body shape, on new (AnimationConstraint) and classic (Motor6D) R15 rigs alike.

type SegmentDirs = { upper: Vector3, fore: Vector3 }
-- arms are optional; `neck` tilts the head in degrees (+ = look up, - = bow down)
type PoseDef = { Right: SegmentDirs?, Left: SegmentDirs?, neck: number? }

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
local function holdPose(model: any, poseName: string, blendIn: number?): () -> ()
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

-- Locally hide parts of a model (whole model, or just the head + hats) until the finisher ends.
local hidden: { [BasePart]: number } = {}
local function hideLocal(model: any, headOnly: boolean?)
	if typeof(model) ~= "Instance" then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local isHead = d.Name == "Head" or (d.Parent and d.Parent:IsA("Accessory"))
			if not headOnly or isHead then
				hidden[d] = hidden[d] or d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		elseif d:IsA("Decal") and (not headOnly or (d.Parent and d.Parent.Name == "Head")) then
			d.Transparency = 1
		end
	end
end
-- Stand-in: hide the real character and put a copy wearing the same avatar in its place. The copy
-- has no scripts (no Animate fighting us), an anchored root, free-hanging limbs on their joints,
-- and is purely local (no physics owner, no network). Poses, or a premade animation loaded on its
-- Animator (e.g. exported from Moon Animator), drive it; it's destroyed when the finisher ends.
-- Accessories (hair, hats) and extras like the team band hang off welds, which don't reliably follow
-- joint-posed limbs. Pin each one to the body part it's welded to, every frame, at its original
-- offset (scaled with the model, for finishers that shrink it).
local function attachFollowers(copy: Model)
	local driven: { [BasePart]: boolean } = {}
	for _, d in copy:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Attachment1 then
			driven[d.Attachment1.Parent :: BasePart] = true
		elseif d:IsA("Motor6D") and d.Part1 then
			driven[d.Part1] = true
		end
	end
	local root = copy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		driven[root] = true
	end
	local follow: { { part: BasePart, to: BasePart, offset: CFrame } } = {}
	local seen: { [BasePart]: boolean } = {}
	for _, d in copy:GetDescendants() do
		local a: BasePart?, b: BasePart? = nil, nil
		if (d:IsA("JointInstance") and not d:IsA("Motor6D")) or d:IsA("WeldConstraint") then
			a, b = (d :: any).Part0, (d :: any).Part1
		elseif d:IsA("RigidConstraint") and d.Attachment0 and d.Attachment1 then
			a, b = d.Attachment0.Parent :: BasePart?, d.Attachment1.Parent :: BasePart?
		end
		if a and b then
			-- the free end is whichever side isn't a posed body part
			local part, to = if driven[a] then b else a, if driven[a] then a else b
			if not driven[part] and not seen[part] and part:IsDescendantOf(copy) then
				seen[part] = true
				table.insert(follow, { part = part, to = to, offset = to.CFrame:ToObjectSpace(part.CFrame) });
				(d :: any).Enabled = false
				part.Anchored = true
			end
		end
	end
	if #follow == 0 then
		return
	end
	local baseScale = copy:GetScale()
	local conn
	conn = RunService.PreRender:Connect(function()
		if not copy.Parent then
			conn:Disconnect()
			return
		end
		local scale = copy:GetScale() / baseScale
		for _, f in follow do
			local o = f.offset
			f.part.CFrame = f.to.CFrame * (CFrame.new(o.Position * scale) * o.Rotation)
		end
	end)
end

local function standIn(model: any, parent: Instance, cf: CFrame?): Model?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local was = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(function()
		return model:Clone()
	end)
	model.Archivable = was
	if not ok or not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
		elseif d:IsA("AnimationConstraint") then
			d.Enabled = true
			-- rigid: limbs follow the pose exactly (no sag or wobble from gravity/forces)
			pcall(function()
				(d :: any).IsKinematic = true
			end)
		elseif d:IsA("Motor6D") then
			d.Enabled = true
		elseif d:IsA("BallSocketConstraint") then
			d.Enabled = false -- ragdoll sockets off: the stand-in is posed, not ragdolled
		end
	end
	local h = copy:FindFirstChildOfClass("Humanoid")
	if h then
		pcall(function()
			h.EvaluateStateMachine = false
		end)
		h.PlatformStand = true
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	copy.Name = model.Name .. "_StandIn"
	copy:PivotTo(cf or model:GetPivot())
	copy.Parent = parent
	attachFollowers(copy)
	hideLocal(model, false)
	return copy
end

local function unhideAll()
	for part, prev in hidden do
		if part.Parent then
			part.LocalTransparencyModifier = prev
			for _, d in part:GetChildren() do
				if d:IsA("Decal") then
					d.Transparency = 0
				end
			end
		end
	end
	table.clear(hidden)
end

-- Local-only ragdoll for preview stand-ins (the real finisher's victim is launched by the server).
local function localLaunch(model: Model, velocity: Vector3)
	for _, d in model:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Name ~= "Root" then
			d.Enabled = false
		elseif d:IsA("BasePart") then
			d.Anchored = false
			if d.Name ~= "HumanoidRootPart" then
				d.CanCollide = true
			end
		end
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	if h then
		h.PlatformStand = true
		h:ChangeState(Enum.HumanoidStateType.Physics)
	end
	local rng = Random.new()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = velocity
				+ Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-2, 6), rng:NextNumber(-8, 8))
			d.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		end
	end
end

-- Playback ----------------------------------------------------------------------------------------

-- Cinematic black bars that slide in from the top and bottom.
local LETTERBOX = 0.11 -- fraction of screen height per bar
local function letterbox(): () -> ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Letterbox"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 15
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local bars = {}
	for _, top in { true, false } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		f.Position = UDim2.fromScale(0, if top then 0 else 1)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = gui
		TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, LETTERBOX),
		}):Play()
		table.insert(bars, f)
	end
	return function()
		for _, f in bars do
			TweenService:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
				Size = UDim2.fromScale(1, 0),
			}):Play()
		end
		task.delay(0.35, function()
			gui:Destroy()
		end)
	end
end

local function restore(folder: Folder, fov: number, closeBars: () -> ())
	for stop in activePoses do
		stop()
	end
	unhideAll()
	folder:Destroy()
	closeBars()
	local camera = Workspace.CurrentCamera
	camera.FieldOfView = fov
	camera.CameraType = Enum.CameraType.Custom
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then
		camera.CameraSubject = h
	end
	HUDController.setCinematic(false)
	FinisherController.playing = false
end

local function loadModule(name: string): (any?, ModuleScript?)
	local moduleScript = Finishers:FindFirstChild(name) or Finishers:FindFirstChild(Config.Finisher.DefaultId)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil, nil
	end
	local ok, def = pcall(require, moduleScript)
	if not ok or type(def) ~= "table" or type(def.play) ~= "function" then
		return nil, nil
	end
	return def, moduleScript
end

-- Duration rule shared with the server: every finisher runs 3-5 seconds.
function FinisherController.duration(def: any): number
	return math.clamp(tonumber(def.Duration) or 4, Config.Finisher.MinDuration, Config.Finisher.MaxDuration)
end

local function play(def: any, d: any, preview: boolean)
	FinisherController.playing = true
	HUDController.setCinematic(true)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local fov = camera.FieldOfView
	local closeBars = letterbox()
	-- hide world billboards (name tags, pad "?" and jail labels) for a clean cinematic
	local hiddenTags: { BillboardGui } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BillboardGui") and d.Enabled then
			d.Enabled = false
			table.insert(hiddenTags, d)
		end
	end
	local function showTags()
		for _, tag in hiddenTags do
			if tag.Parent then
				tag.Enabled = true
			end
		end
	end
	-- the server stages both at their court centers; snap them there locally too, so the scene is
	-- built from those spots even if a position update is still in flight
	local stagedCF: { [Instance]: CFrame } = {}
	for _, role in { { d.killer, d.killerCF }, { d.victim, d.victimCF } } do
		local model, cf = role[1], role[2]
		if typeof(model) == "Instance" and model:IsA("Model") and typeof(cf) == "CFrame" then
			stagedCF[model] = cf
			pcall(function()
				model:PivotTo(cf)
			end)
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "FinisherFX"
	folder.Parent = Workspace
	local duration = FinisherController.duration(def)
	local ctx = {
		camera = camera,
		killer = d.killer,
		victim = d.victim,
		killerName = tostring(d.killerName or "?"),
		victimName = tostring(d.victimName or "?"),
		winnerColor = if d.winner and Config.Teams[d.winner] then Config.Teams[d.winner].Color else Color3.new(1, 1, 1),
		duration = duration,
		isPreview = preview,
		-- horizontal direction "off the arena" from the victim (away from the court center, or away
		-- from you in the preview)
		outward = (function(): Vector3
			local vr, kr = rootOf(d.victim), rootOf(d.killer)
			local from = if preview and kr then kr.Position else Config.Arena.Origin
			if not vr then
				return Vector3.zAxis
			end
			local v = Vector3.new(vr.Position.X - from.X, 0, vr.Position.Z - from.Z)
			return if v.Magnitude > 0.1 then v.Unit else Vector3.zAxis
		end)(),
		reducedMotion = HUDController.settings.ReducedMotion,
		folder = folder, -- parent temporary parts here; destroyed when the finisher ends
		-- finishers play without on-screen text; the cue's sound still plays
		banner = function(_text: string, _color: Color3?, _seconds: number?, sound: string?)
			if sound then
				SoundController.play(sound)
			end
		end,
		runFor = runFor,
		rootOf = rootOf,
		pose = holdPose,
		standIn = function(model: any): Model?
			return standIn(model, folder, if typeof(model) == "Instance" then stagedCF[model] else nil)
		end,
		hideHead = function(model: any)
			hideLocal(model, true)
		end,
		hide = function(model: any)
			hideLocal(model, false)
		end,
		-- slow in, fast middle, slow out
		ease = function(a: number): number
			return if a < 0.5 then 4 * a * a * a else 1 - (-2 * a + 2) ^ 3 / 2
		end,
		sound = function(cue: string, at: Vector3?)
			SoundController.play(cue, at)
		end,
		fx = {
			burst = EffectsController.burst,
			shockwave = EffectsController.shockwave,
			flash = EffectsController.flashSphere,
			shake = EffectsController.addShake,
			screenFlash = HUDController.flash,
		},
	}
	-- the preview launches its stand-in locally on the same schedule the server uses
	local stage = def.Stage or {}
	if preview and typeof(d.victim) == "Instance" and stage.Launch ~= false then
		task.delay(tonumber(stage.LaunchDelay) or 1, function()
			local kr, vr = rootOf(d.killer), rootOf(d.victim)
			if vr and vr.Parent then
				local away = if kr
					then Vector3.new(vr.Position.X - kr.Position.X, 0, vr.Position.Z - kr.Position.Z)
					else Vector3.zAxis
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
				localLaunch(
					d.victim :: Model,
					away * (tonumber(stage.Out) or 40) + Vector3.new(0, tonumber(stage.Up) or 60, 0)
				)
			end
		end)
	end
	local finished = false
	task.spawn(function()
		local okPlay, err = pcall(def.play, ctx)
		if not okPlay then
			warn("[Finisher] " .. tostring(err))
		end
		finished = true
	end)
	-- hard stop at the duration so the match is never blocked
	local deadline = os.clock() + duration + 0.2
	while not finished and os.clock() < deadline do
		task.wait()
	end
	restore(folder, fov, closeBars)
	showTags()
end

-- Shop preview: plays a finisher on you and a stand-in dummy in the hub. Purely local; nobody
-- else sees it and nothing on the server changes.
function FinisherController.preview(moduleName: string): boolean
	if FinisherController.playing then
		return false
	end
	local character = player.Character
	local root = rootOf(character)
	if not character or not root or player:GetAttribute("Status") ~= "Lobby" then
		return false
	end
	local def = loadModule(moduleName)
	if not def then
		return false
	end
	local template = Workspace:FindFirstChild("Bots") and (Workspace :: any).Bots:FindFirstChild("Practice Dummy")
	if not template then
		return false
	end
	local wasArchivable = template.Archivable
	template.Archivable = true
	local standIn = template:Clone()
	template.Archivable = wasArchivable
	standIn.Name = "PreviewStandIn"
	for _, dsc in standIn:GetDescendants() do
		if dsc:IsA("BillboardGui") or dsc:IsA("LuaSourceContainer") then
			dsc:Destroy()
		elseif dsc:IsA("BasePart") then
			dsc.Anchored = true
		end
	end
	-- stand it 18 studs in front of you, kept inside the hub
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis
	local lo = Config.Arena.LobbyOrigin
	local half = Config.Arena.LobbySize / 2 - Vector3.new(6, 0, 6)
	local spot = root.Position + look * 18
	spot = Vector3.new(
		math.clamp(spot.X, lo.X - half.X, lo.X + half.X),
		lo.Y + 3,
		math.clamp(spot.Z, lo.Z - half.Z, lo.Z + half.Z)
	)
	standIn:PivotTo(CFrame.lookAt(spot, Vector3.new(root.Position.X, spot.Y, root.Position.Z)))
	standIn.Parent = Workspace
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local walk = humanoid and humanoid.WalkSpeed
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	play(def, {
		killer = character,
		victim = standIn,
		killerName = player.DisplayName,
		victimName = "Dummy",
		winner = player:GetAttribute("Team") ~= "" and player:GetAttribute("Team") or "Red",
	}, true)
	if humanoid and walk then
		humanoid.WalkSpeed = walk
	end
	task.delay(0.5, function()
		standIn:Destroy()
	end)
	return true
end

function FinisherController.init() end

function FinisherController.start()
	Net.on("Finisher", function(d)
		if FinisherController.playing then
			return
		end
		local def = loadModule(tostring(d.module))
		if def then
			play(def, d, false)
		end
	end)
end

return FinisherController
