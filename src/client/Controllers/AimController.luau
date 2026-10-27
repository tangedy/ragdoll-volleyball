--!strict
-- Hold to aim, release to throw (spec §7 "Throw", §9 aiming). The client only presents the charge
-- and predicted arc; the server records charge start and computes power on release.

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

AimController.charging = false
AimController.chargeStartedAt = 0
AimController.lastInput = "Mouse" -- "Mouse" | "Touch" | "Gamepad"
-- Where the current aim actually points (the assisted enemy's root when assist locks on), and that
-- enemy. Updated while charging; the HUD crosshair is drawn on it so it matches the arc preview.
AimController.aimPoint = nil :: Vector3?
AimController.assistModel = nil :: Model?
-- Hub practice is client-side: PracticeController sets these so charging and releasing a practice
-- ball never talk to the server.
AimController.localHeld = function(): boolean
	return false
end
AimController.localThrow = function(_dir: Vector3, _origin: Vector3, _speed: number, _charge: number) end

local throwId = 0
local previewFolder: Folder
local dots: { Part } = {}
local DOTS = 8

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

-- Screen point the throw aims through: the mouse on PC, the screen center elsewhere.
function AimController.screenPoint(): Vector2
	local camera = Workspace.CurrentCamera
	if AimController.lastInput == "Mouse" then
		return UserInputService:GetMouseLocation()
	end
	local vp = camera.ViewportSize
	return Vector2.new(vp.X / 2, vp.Y / 2)
end

local function excludeList(): { Instance }
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
	return list
end

-- Mild aim assist: only inside a narrow cone, only with line of sight, only for valid enemies.
-- The enemy picked during this charge. Keeping it (rather than re-picking every frame) means the
-- arc, the crosshair and the release all aim at the same player even when two stand close together.
local locked: Model? = nil

local function assistTarget(ray: Ray): (Vector3?, Model?)
	local myTeam = attr("Team")
	if type(myTeam) ~= "string" or myTeam == "" then
		return nil, nil
	end
	local A = Config.AimAssist
	local cone = math.rad(A.ConeDeg[AimController.lastInput] or A.ConeDeg.Mouse)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList()
	if locked then
		local keep: Vector3? = nil
		AimController._consider(locked, myTeam, ray, params, function(pos, angle)
			if angle < cone * A.KeepFactor then
				keep = pos
			end
		end)
		if keep then
			return keep, locked
		end
		locked = nil
	end
	local best, bestModel, bestAngle = nil, nil, cone
	local function consider(model: Instance)
		AimController._consider(model, myTeam, ray, params, function(pos, angle)
			if angle < bestAngle then
				best, bestModel, bestAngle = pos, model :: Model, angle
			end
		end)
	end
	for _, model in Workspace:GetChildren() do
		consider(model)
	end
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			consider(model)
		end
	end
	if AimController.charging then
		locked = bestModel
	end
	return best, bestModel
end

function AimController._consider(
	model: Instance,
	myTeam: string,
	ray: Ray,
	params: RaycastParams,
	cb: (Vector3, number) -> ()
)
	if not model:IsA("Model") or model == player.Character then
		return
	end
	local team = model:GetAttribute("Team")
	if team == nil or team == "" or team == myTeam or model:GetAttribute("Status") ~= "Active" then
		return
	end
	local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not r then
		return
	end
	local to = r.Position - ray.Origin
	if to.Magnitude > Config.AimAssist.Range then
		return
	end
	local angle = math.acos(math.clamp(to.Unit:Dot(ray.Direction.Unit), -1, 1))
	local hit = Workspace:Raycast(ray.Origin, to, params)
	if hit and not hit.Instance:IsDescendantOf(model) then
		return -- never assist through scenery
	end
	cb(r.Position, angle)
end

-- Direction from the server's ball spawn point, compensated for gravity so the arc lands near the aim.
function AimController.computeDirection(): (Vector3?, Vector3?, number)
	local r = root()
	if not r then
		return nil, nil, 0
	end
	local camera = Workspace.CurrentCamera
	local sp = AimController.screenPoint()
	local ray = camera:ViewportPointToRay(sp.X, sp.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList()
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * 300
	local assisted, model = assistTarget(ray)
	point = assisted or point
	AimController.aimPoint = point
	AimController.assistModel = model
	local ballType = attr("HeldBall") or "Standard"
	local flat = Vector3.new(point.X - r.Position.X, 0, point.Z - r.Position.Z)
	local forward = if flat.Magnitude > 0.1 then flat.Unit else r.CFrame.LookVector
	local origin = r.Position + Vector3.new(0, Config.Ball.SpawnUp, 0) + forward * Config.Ball.SpawnForward
	local charge = if AimController.charging
		then ProjectileMath.chargeFromHold(os.clock() - AimController.chargeStartedAt)
		else 0
	local speed = ProjectileMath.throwSpeed(charge, ballType)
	local g = ProjectileMath.gravity(ballType)
	local dist = (point - origin).Magnitude
	-- don't compensate far-off sky points; keep long throws as-aimed
	local tFlight = math.min(dist, 90) / speed
	local dir = (point + Vector3.new(0, 0.5 * g * tFlight * tFlight, 0) - origin)
	if dir.Magnitude < 0.1 then
		return nil, nil, 0
	end
	local clean = ProjectileMath.sanitizeDirection(dir.Unit)
	return clean, origin, speed
end

function AimController.begin()
	if AimController.charging or not AimController.holding() then
		return
	end
	if attr("Action") ~= "Idle" and attr("Action") ~= "Dodging" then
		return
	end
	AimController.charging = true
	AimController.chargeStartedAt = os.clock()
	if not AimController.localHeld() then
		Net.request(Net.Actions.ChargeStart)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
end

local function stopCharging()
	AimController.charging = false
	AimController.aimPoint = nil
	AimController.assistModel = nil
	locked = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
	for _, d in dots do
		d.Transparency = 1
	end
end

function AimController.release()
	if not AimController.charging then
		return
	end
	local dir, origin, speed = AimController.computeDirection()
	local ballType = attr("HeldBall") or "Standard"
	local charge = ProjectileMath.chargeFromHold(os.clock() - AimController.chargeStartedAt)
	stopCharging()
	if AimController.localHeld() then
		if dir and origin then
			AimController.localThrow(dir, origin, speed, charge)
		end
		return
	end
	if dir and origin then
		throwId += 1
		Net.request(Net.Actions.Throw, { dir = dir, throwId = throwId })
		BallVisualController.predict(throwId, origin, dir * speed, ballType)
	else
		Net.request(Net.Actions.CancelAim)
	end
end

function AimController.cancel()
	if AimController.charging then
		stopCharging()
		if not AimController.localHeld() then
			Net.request(Net.Actions.CancelAim) -- cancelling keeps the ball
		end
	end
end

function AimController.chargeFraction(): number
	if not AimController.charging then
		return 0
	end
	return ProjectileMath.chargeFromHold(os.clock() - AimController.chargeStartedAt)
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
		if AimController.charging and not AimController.holding() then
			-- lost the ball (hit, forced drop): the server already cancelled
			stopCharging()
			return
		end
		if not AimController.charging then
			return
		end
		local dir, origin, speed = AimController.computeDirection()
		local r = root()
		if r and dir then
			-- face the throw direction while aiming
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.1 then
				r.CFrame = CFrame.lookAt(r.Position, r.Position + flat)
			end
		end
		if not dir or not origin then
			return
		end
		-- short predicted trajectory, never a full-court laser
		local ballType = attr("HeldBall") or "Standard"
		local g = ProjectileMath.gravity(ballType)
		local v = dir * speed
		for i, d in dots do
			local t = i * 0.045
			d.Position = ProjectileMath.positionAt(origin, v, g, t)
			d.Transparency = 0.15 + i * 0.08
		end
	end)
end

return AimController
