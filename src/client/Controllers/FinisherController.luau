--!strict
-- Plays finisher cutscenes: for real on the match-ending knockout (server event "Finisher"), or as
-- a local-only preview from the shop. Loads the named module from ReplicatedStorage.Shared.Finishers
-- and always restores the camera, HUD and any poses/effects, even if a finisher errors.
-- See Shared/Finishers/README.md for the module contract and the toolkit passed in `ctx`.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local EffectsController = require(script.Parent.EffectsController)
local SoundController = require(script.Parent.SoundController)
local PoseKit = require(script.Parent.PoseKit)

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
-- Solved and held by PoseKit (shared with intro poses). The finisher remembers what it started so
-- restore() releases exactly those.

local finisherPoses: { [() -> ()]: boolean } = {}
local function holdPose(model: any, poseName: string, blendIn: number?): () -> ()
	local stop = PoseKit.hold(model, poseName, blendIn)
	finisherPoses[stop] = true
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
	-- same flail, speed cap and tumble as RagdollService.ragdoll, so the stand-in flies the arc a real
	-- victim does (uncapped, it lands in the jail strip instead of the void)
	local K = Config.Knockback
	local rng = Random.new()
	local axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	axis = if axis.Magnitude > 0.1 then axis.Unit else Vector3.xAxis
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local isLimb = d.Name ~= "HumanoidRootPart"
			local flail = if isLimb
				then Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)) * K.LimbFlail
				else Vector3.zero
			local v = velocity + flail
			if v.Magnitude > K.MaxSpeed then
				v = v.Unit * K.MaxSpeed
			end
			d.AssemblyLinearVelocity = v
			d.AssemblyAngularVelocity = axis * K.TumbleSpin
				+ (
					if isLimb
						then Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * K.LimbSpin
						else Vector3.zero
				)
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
	for stop in finisherPoses do
		stop()
	end
	table.clear(finisherPoses)
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

-- Shop preview ----------------------------------------------------------------------------------------
-- Plays a finisher on a private copy of the game court, far from the real one: a copy of you stands in
-- the middle of one half, a stand-in dummy in the middle of the other, staged exactly like a match.
-- Purely local; nobody else sees it, your real character stays in the hub, and nothing on the server
-- changes.

-- Clear of the real court and its 800-stud VoidGlow, but well inside the client's ~1000-stud physics
-- range from a character in the hub: any farther and the stand-in freezes instead of launching.
local PREVIEW_OFFSET = Vector3.new(0, 0, 800)

-- A local copy of the arena (workspace.Arena), shifted by PREVIEW_OFFSET. Tags are stripped so the
-- game's effects (rim flashes, neon) never mistake it for the real court.
local function buildPreviewCourt(): Folder?
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		return nil
	end
	local wasArchivable = arena.Archivable
	arena.Archivable = true
	local copy = arena:Clone()
	arena.Archivable = wasArchivable
	copy.Name = "PreviewCourt"
	for _, d in copy:GetDescendants() do
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag)
		end
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CFrame += PREVIEW_OFFSET
		end
	end
	copy.Parent = Workspace
	return copy :: Folder
end

-- A local copy of a model with its scripts, prompts and name tags removed; only the root anchored so
-- poses still play on the limbs.
local function previewActor(model: Model, name: string, anchorAll: boolean): Model
	local wasArchivable = model.Archivable
	model.Archivable = true
	local copy = model:Clone()
	model.Archivable = wasArchivable
	copy.Name = name
	for _, d in copy:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = anchorAll or d.Name == "HumanoidRootPart"
			d.CanTouch = false
		end
	end
	return copy
end

function FinisherController.preview(moduleName: string): boolean
	if FinisherController.playing then
		return false
	end
	local character = player.Character
	if not character or not rootOf(character) or player:GetAttribute("Status") ~= "Lobby" then
		return false
	end
	local def = loadModule(moduleName)
	if not def then
		return false
	end
	local template = ReplicatedStorage:FindFirstChild(Config.Practice.TemplateName)
	if not template then
		return false
	end
	local court = buildPreviewCourt()
	-- you on your team's half (Red in the hub), the dummy on the other, facing each other
	local team = player:GetAttribute("Team")
	local winner = if type(team) == "string" and team ~= "" then team else "Red"
	local up = Vector3.new(0, 3, 0)
	local killerAt = ArenaLayout.halfCenter(winner) + up + PREVIEW_OFFSET
	local victimAt = ArenaLayout.halfCenter(ArenaLayout.enemyOf(winner)) + up + PREVIEW_OFFSET
	local me = previewActor(character, "PreviewYou", false)
	local standIn = previewActor(template :: Model, "PreviewStandIn", true)
	me:PivotTo(CFrame.lookAt(killerAt, victimAt))
	standIn:PivotTo(CFrame.lookAt(victimAt, killerAt))
	me.Parent = Workspace
	standIn.Parent = Workspace
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local walk = humanoid and humanoid.WalkSpeed
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	play(def, {
		killer = me,
		victim = standIn,
		killerName = player.DisplayName,
		victimName = "Dummy",
		winner = winner,
		killerCF = CFrame.lookAt(killerAt, victimAt),
		victimCF = CFrame.lookAt(victimAt, killerAt),
	}, true)
	if humanoid and walk then
		humanoid.WalkSpeed = walk
	end
	task.delay(0.5, function()
		me:Destroy()
		standIn:Destroy()
		if court then
			court:Destroy()
		end
	end)
	return true
end

-- Shared with the match intro camera.
FinisherController.letterbox = letterbox

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
