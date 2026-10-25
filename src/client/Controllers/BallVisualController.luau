--!strict
-- Smooth client-rendered ball flight (spec §11 "Projectile implementation": client-rendered visuals
-- that reconcile to authoritative events; unique throw ids for prediction reconciliation).
--
-- In-flight balls follow a deterministic arc, so each client simulates it from the server's
-- launch record instead of waiting for ~20 Hz part replication. The authoritative part is hidden
-- locally while a visual exists and shown again the moment its BallState leaves InFlight.
-- The local thrower predicts the launch on release and blends into the server arc when it arrives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallDefinitions = require(Shared.BallDefinitions)
local ProjectileMath = require(Shared.ProjectileMath)
local Net = require(script.Parent.Net)

local player = Players.LocalPlayer

type Visual = {
	part: Part,
	origin: Vector3,
	vel: Vector3,
	g: number,
	t0: number, -- server time of launch
	offset: Vector3, -- prediction error being blended out
	blendStart: number,
	ballId: number?,
	throwId: number?,
	stoppedAt: Vector3?,
	createdAt: number,
}

local BallVisualController = {}

local BLEND_TIME = 0.15
local folder: Folder
local visuals: { [Visual]: boolean } = {}
local byBallId: { [number]: Visual } = {}
local predicted: { [number]: Visual } = {} -- by throwId
local serverParts: { [number]: BasePart } = {}

local function makePart(ballType: string, at: Vector3): Part
	local def = BallDefinitions.get(ballType)
	local p = Instance.new("Part")
	p.Name = "BallVisual"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * ProjectileMath.radius(ballType) * 2
	p.Color = def.Color
	p.Material = def.Material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(at)
	if def.Trail or ballType ~= "Standard" then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.3
		trail.Color = ColorSequence.new(def.Color)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.LightEmission = 0.6
		trail.Parent = p
	end
	p.Parent = folder
	return p
end

local function setServerHidden(ballId: number?, hidden: boolean)
	if not ballId then
		return
	end
	local part = serverParts[ballId]
	if part then
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
end

local function remove(v: Visual)
	visuals[v] = nil
	if v.ballId and byBallId[v.ballId] == v then
		byBallId[v.ballId] = nil
	end
	if v.throwId and predicted[v.throwId] == v then
		predicted[v.throwId] = nil
	end
	setServerHidden(v.ballId, false)
	v.part:Destroy()
end

local function heldPartOfMine(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	for _, part in serverParts do
		if part:GetAttribute("BallState") == "Held" then
			local weld = part:FindFirstChildOfClass("WeldConstraint")
			if weld and weld.Part0 and weld.Part0:IsDescendantOf(character) then
				return part
			end
		end
	end
	return nil
end

-- Called by AimController on release, before the server confirms.
function BallVisualController.predict(throwId: number, origin: Vector3, vel: Vector3, ballType: string)
	local v: Visual = {
		part = makePart(ballType, origin),
		origin = origin,
		vel = vel,
		g = ProjectileMath.gravity(ballType),
		t0 = Workspace:GetServerTimeNow(),
		offset = Vector3.zero,
		blendStart = 0,
		ballId = nil,
		throwId = throwId,
		stoppedAt = nil,
		createdAt = os.clock(),
	}
	visuals[v] = true
	predicted[throwId] = v
	local held = heldPartOfMine()
	if held then
		held.LocalTransparencyModifier = 1 -- the real ball is still welded until the server acts
		v.ballId = held:GetAttribute("BallId") :: number?
	end
end

local function onLaunched(d: any)
	if type(d.id) ~= "number" or typeof(d.origin) ~= "Vector3" or typeof(d.vel) ~= "Vector3" then
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	local g = ProjectileMath.gravity(d.ballType)
	local mine: Visual? = if d.thrower == player then predicted[d.throwId] else nil
	if mine then
		-- reconcile: switch to the authoritative arc, blending out the visible difference
		local v = mine
		local current = v.part.Position
		v.origin = d.origin
		v.vel = d.vel
		v.g = g
		v.t0 = d.t0
		v.offset = current - ProjectileMath.positionAt(d.origin, d.vel, g, serverNow - d.t0)
		v.blendStart = os.clock()
		v.ballId = d.id
		predicted[d.throwId] = nil
		byBallId[d.id] = v
		setServerHidden(d.id, true)
		BallVisualController.applyLook(v.part, d.look)
		return
	end
	local old = byBallId[d.id]
	if old then
		remove(old)
	end
	local v: Visual = {
		part = makePart(d.ballType, ProjectileMath.positionAt(d.origin, d.vel, g, math.max(serverNow - d.t0, 0))),
		origin = d.origin,
		vel = d.vel,
		g = g,
		t0 = d.t0,
		offset = Vector3.zero,
		blendStart = 0,
		ballId = d.id,
		throwId = nil,
		stoppedAt = nil,
		createdAt = os.clock(),
	}
	visuals[v] = true
	byBallId[d.id] = v
	setServerHidden(d.id, true)
	BallVisualController.applyLook(v.part, d.look)
end

-- Owner cosmetics from the launch record (Standard balls only; the server never sends a look
-- for power-up types).
function BallVisualController.applyLook(part: Part, look: any)
	if type(look) ~= "table" then
		return
	end
	if typeof(look.color) == "Color3" then
		part.Color = look.color
	end
	if typeof(look.material) == "EnumItem" and (look.material :: EnumItem).EnumType == Enum.Material then
		part.Material = look.material :: any
	end
	if type(look.trail) == "table" and #look.trail > 0 and not part:FindFirstChildOfClass("Trail") then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = part
		local keys = {}
		for i, col in look.trail do
			if typeof(col) == "Color3" then
				table.insert(keys, ColorSequenceKeypoint.new(if #look.trail == 1 then 0 else (i - 1) / (#look.trail - 1), col))
			end
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, keys[1].Value))
		end
		if #keys >= 2 then
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.35
			trail.Color = ColorSequence.new(keys)
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.LightEmission = 0.5
			trail.Parent = part
		end
	end
end

local function track(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local id = part:GetAttribute("BallId")
	if type(id) ~= "number" then
		return
	end
	serverParts[id] = part
	part:GetAttributeChangedSignal("BallState"):Connect(function()
		local v = byBallId[id]
		if v and part:GetAttribute("BallState") ~= "InFlight" then
			remove(v) -- the server decided the outcome; show the real ball
		end
	end)
	part.AncestryChanged:Connect(function()
		if not part.Parent then
			serverParts[id] = nil
			local v = byBallId[id]
			if v then
				remove(v)
			end
		end
	end)
end

function BallVisualController.init()
	folder = Instance.new("Folder")
	folder.Name = "BallVisuals"
	folder.Parent = Workspace
end

function BallVisualController.start()
	local balls = Workspace:WaitForChild("Balls")
	for _, p in balls:GetChildren() do
		track(p)
	end
	balls.ChildAdded:Connect(track)
	Net.on("BallLaunched", onLaunched)
	Net.on("ThrowResult", function(d)
		if d.ok == false then
			local v = predicted[d.throwId]
			if v then
				remove(v)
			end
		end
	end)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	RunService.RenderStepped:Connect(function()
		local arena = Workspace:FindFirstChild("Arena")
		local collidable = arena and arena:FindFirstChild("Collidable")
		params.FilterDescendantsInstances = if collidable then { collidable } else {}
		local serverNow = Workspace:GetServerTimeNow()
		for v in visuals do
			local t = serverNow - v.t0
			-- predictions the server never confirmed, and arcs past max flight time, expire
			if t > Config.Ball.MaxFlightTime + 0.5 or (v.ballId == nil and os.clock() - v.createdAt > 1) then
				remove(v)
				continue
			end
			if v.stoppedAt then
				continue
			end
			local blend = if v.blendStart > 0 then math.clamp(1 - (os.clock() - v.blendStart) / BLEND_TIME, 0, 1) else 1
			local pos = ProjectileMath.positionAt(v.origin, v.vel, v.g, math.max(t, 0)) + v.offset * blend
			-- hold at scenery contact until the server's verdict replicates (never draw through floors)
			local last = v.part.Position
			local delta = pos - last
			if delta.Magnitude > 1e-3 and (os.clock() - v.createdAt) > 0.05 then
				local hit = Workspace:Spherecast(last, v.part.Size.X / 2, delta, params)
				if hit then
					pos = hit.Position + hit.Normal * (v.part.Size.X / 2)
					v.stoppedAt = pos
				end
			end
			v.part.CFrame = CFrame.new(pos)
		end
	end)
end

return BallVisualController
