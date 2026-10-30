--!strict
-- Tap to throw (spec §7 "Throw", §9 aiming). While you hold a ball the aim is always locked on to
-- an enemy (the one nearest your aim, or the nearest one in Aim lock) and every throw is full
-- power, so a tap fires straight at them. The client only presents the target and predicted arc;
-- the server decides the throw.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ProjectileMath = require(Shared.ProjectileMath)
local Net = require(script.Parent.Net)
local BallVisualController = require(script.Parent.BallVisualController)

local player = Players.LocalPlayer

local AimController = {}

AimController.lastInput = "Mouse" -- "Mouse" | "Touch" | "Gamepad"
-- Where the throw would go right now (the target's led position, or the plain aim point) and the
-- enemy it's locked on to. Updated every frame while you hold a ball (or in Aim lock); the HUD
-- crosshair is drawn on the target so it matches the arc preview.
AimController.aimPoint = nil :: Vector3?
AimController.assistModel = nil :: Model?
-- Aim lock (LockController): always pick the nearest enemy instead of the one nearest the aim.
AimController.preferNearest = false
-- Hub practice is client-side: PracticeController sets these so throwing a practice ball never
-- talks to the server, and offers its dummy as a target.
AimController.localHeld = function(): boolean
	return false
end
AimController.localThrow = function(_dir: Vector3, _origin: Vector3, _speed: number) end
AimController.extraTargets = function(): { Model }
	return {}
end

local throwId = 0
local previewFolder: Folder
local dots: { Part } = {}
local DOTS = 8
local pendingUntil = 0 -- a tap while busy (dodging, recovering) fires once you're free

local function attr(name: string): any
	return player:GetAttribute(name)
end

function AimController.holding(): boolean
	local held = attr("HeldBall")
	return type(held) == "string" and held ~= ""
end

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Screen point the aim goes through: the mouse on PC, the screen center elsewhere (and in Shift
-- lock, where the mouse is held in the center).
function AimController.screenPoint(): Vector2
	local camera = Workspace.CurrentCamera
	if AimController.lastInput == "Mouse" and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return UserInputService:GetMouseLocation()
	end
	local vp = camera.ViewportSize
	return Vector2.new(vp.X / 2, vp.Y / 2)
end

-- One shared params object for the aim rays. Its exclude list (you, the balls, the preview, your
-- practice balls) used to be rebuilt into a fresh RaycastParams twice a frame while holding a ball;
-- now it's only re-marshalled when one of those instances comes or goes.
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
local aimExcluded: { Instance } = {}

local function excludeParams(): RaycastParams
	local list: { Instance } = { previewFolder }
	if player.Character then
		table.insert(list, player.Character)
	end
	local balls = Workspace:FindFirstChild("Balls")
	if balls then
		table.insert(list, balls)
	end
	local lobby = Workspace:FindFirstChild("Lobby")
	local practice = lobby and lobby:FindFirstChild("Practice")
	if practice then
		table.insert(list, practice) -- don't aim at your own practice balls
	end
	local same = #list == #aimExcluded
	if same then
		for i, inst in list do
			if aimExcluded[i] ~= inst then
				same = false
				break
			end
		end
	end
	if not same then
		aimExcluded = list
		aimParams.FilterDescendantsInstances = list
	end
	return aimParams
end

type Candidate = { model: Model, root: BasePart, angle: number, dist: number }

-- Every enemy you could throw at right now: on court, in range and in line of sight.
local function candidates(ray: Ray): { Candidate }
	local list: { Candidate } = {}
	local myTeam = attr("Team")
	local params = excludeParams()
	local function consider(model: Instance, anyTeam: boolean)
		if not model:IsA("Model") or model == player.Character then
			return
		end
		if not anyTeam then
			local team = model:GetAttribute("Team")
			if type(myTeam) ~= "string" or myTeam == "" or team == nil or team == "" or team == myTeam then
				return
			end
			if model:GetAttribute("Status") ~= "Active" then
				return
			end
		end
		local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not r then
			return
		end
		local to = r.Position - ray.Origin
		if to.Magnitude > Config.AimAssist.Range or to.Magnitude < 1e-3 then
			return
		end
		local hit = Workspace:Raycast(ray.Origin, to, params)
		if hit and not hit.Instance:IsDescendantOf(model) then
			return -- never aim through scenery
		end
		local angle = math.acos(math.clamp(to.Unit:Dot(ray.Direction.Unit), -1, 1))
		local me = root()
		local dist = if me then (r.Position - me.Position).Magnitude else to.Magnitude
		table.insert(list, { model = model, root = r, angle = angle, dist = dist })
	end
	-- players' characters and the bots folder, not every child of the Workspace each frame
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		for _, other in Players:GetPlayers() do
			local model = other.Character
			if model and model.Parent == Workspace then
				consider(model, false)
			end
		end
		for _, model in bots:GetChildren() do
			consider(model, false)
		end
	else
		for _, model in Workspace:GetChildren() do
			consider(model, false) -- no bots folder: bots spawn straight into the Workspace
		end
	end
	for _, model in AimController.extraTargets() do
		consider(model, true)
	end
	return list
end

-- The current target. It stays picked while it's still close to the aim (or still the nearest in
-- Aim lock), so the crosshair doesn't flick between two players standing together.
local locked: Model? = nil

local function pickTarget(ray: Ray): Candidate?
	local list = candidates(ray)
	if #list == 0 then
		locked = nil
		return nil
	end
	local best: Candidate = list[1]
	local current: Candidate? = nil
	for _, c in list do
		if AimController.preferNearest then
			if c.dist < best.dist then
				best = c
			end
		elseif c.angle < best.angle then
			best = c
		end
		if c.model == locked then
			current = c
		end
	end
	if current and current ~= best then
		local A = Config.AimAssist
		local cone = math.rad(A.ConeDeg[AimController.lastInput] or A.ConeDeg.Mouse)
		local keep = if AimController.preferNearest
			then current.dist < best.dist + 6
			else current.angle < cone * A.KeepFactor or current.angle < best.angle + cone
		if keep then
			best = current
		end
	end
	locked = best.model
	return best
end

-- Direction from the server's ball spawn point, compensated for gravity (and led onto a moving
-- target) so the arc lands on the aim. Returns direction, origin and speed.
function AimController.computeDirection(): (Vector3?, Vector3?, number)
	local r = root()
	if not r then
		return nil, nil, 0
	end
	local camera = Workspace.CurrentCamera
	local sp = AimController.screenPoint()
	local ray = camera:ViewportPointToRay(sp.X, sp.Y)
	local ballType = attr("HeldBall") or "Standard"
	local speed = ProjectileMath.throwSpeed(ballType)
	local g = ProjectileMath.gravity(ballType)
	local target = pickTarget(ray)
	local point: Vector3
	if target then
		local pos = target.root.Position
		local vel = target.root.AssemblyLinearVelocity
		local lead = Config.AimAssist.Lead[AimController.lastInput] or 0.5
		local tLead = (pos - r.Position).Magnitude / speed
		point = pos + Vector3.new(vel.X, 0, vel.Z) * tLead * lead
	else
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, excludeParams())
		point = if hit then hit.Position else ray.Origin + ray.Direction * 300
	end
	AimController.aimPoint = point
	AimController.assistModel = if target then target.model else nil
	local flat = Vector3.new(point.X - r.Position.X, 0, point.Z - r.Position.Z)
	local forward = if flat.Magnitude > 0.1 then flat.Unit else r.CFrame.LookVector
	local origin = r.Position + Vector3.new(0, Config.Ball.SpawnUp, 0) + forward * Config.Ball.SpawnForward
	local dist = (point - origin).Magnitude
	-- don't compensate far-off sky points; keep long throws as-aimed
	local tFlight = math.min(dist, 120) / speed
	local dir = (point + Vector3.new(0, 0.5 * g * tFlight * tFlight, 0) - origin)
	if dir.Magnitude < 0.1 then
		return nil, nil, 0
	end
	local clean = ProjectileMath.sanitizeDirection(dir.Unit)
	return clean, origin, speed
end

local function canThrowNow(): boolean
	if AimController.localHeld() then
		local action = attr("Action")
		return action == nil or action == "Idle" or action == "Dodging" or action == "Recovering"
	end
	return attr("Action") == "Idle"
end

local function hideDots()
	for _, d in dots do
		d.Transparency = 1
	end
end

local function throwNow()
	pendingUntil = 0
	local dir, origin, speed = AimController.computeDirection()
	if not dir or not origin then
		return
	end
	local r = root()
	if r then
		-- snap to face the throw
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.1 then
			r.CFrame = CFrame.lookAt(r.Position, r.Position + flat)
		end
	end
	hideDots()
	if AimController.localHeld() then
		AimController.localThrow(dir, origin, speed)
		return
	end
	local ballType = attr("HeldBall") or "Standard"
	throwId += 1
	Net.request(Net.Actions.Throw, { dir = dir, throwId = throwId })
	BallVisualController.predict(throwId, origin, dir * speed, ballType)
end

-- Tap: throw at the current target right away (or as soon as a dodge/recovery ends).
function AimController.fire()
	if not AimController.holding() then
		return
	end
	if canThrowNow() then
		throwNow()
	else
		pendingUntil = os.clock() + Config.AimAssist.BufferTime
	end
end

function AimController.init()
	previewFolder = Instance.new("Folder")
	previewFolder.Name = "AimPreview"
	previewFolder.Parent = Workspace
	for i = 1, DOTS do
		local d = Instance.new("Part")
		d.Name = "Dot"
		d.Shape = Enum.PartType.Ball
		d.Size = Vector3.one * (0.55 - i * 0.03)
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.Neon
		d.Color = Color3.new(1, 1, 1)
		d.Transparency = 1
		d.Parent = previewFolder
		table.insert(dots, d)
	end
end

function AimController.start()
	RunService.RenderStepped:Connect(function()
		local holding = AimController.holding()
		if pendingUntil > 0 then
			if not holding or os.clock() > pendingUntil then
				pendingUntil = 0
			elseif canThrowNow() then
				throwNow()
				return
			end
		end
		if not holding and not AimController.preferNearest then
			if AimController.aimPoint or AimController.assistModel then
				AimController.aimPoint = nil
				AimController.assistModel = nil
				locked = nil
				hideDots()
			end
			return
		end
		local dir, origin, speed = AimController.computeDirection()
		if not holding or not dir or not origin then
			hideDots()
			return
		end
		-- short predicted trajectory, never a full-court laser
		local ballType = attr("HeldBall") or "Standard"
		local g = ProjectileMath.gravity(ballType)
		local v = dir * speed
		for i, d in dots do
			local t = i * 0.035
			d.Position = ProjectileMath.positionAt(origin, v, g, t)
			d.Transparency = 0.15 + i * 0.08
		end
	end)
end

return AimController
