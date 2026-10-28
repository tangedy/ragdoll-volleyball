--!strict
-- Smooth client-rendered ball flight (spec §11 "Projectile implementation": client-rendered visuals
-- that reconcile to authoritative events; unique throw ids for prediction reconciliation).
--
-- In-flight balls follow a deterministic arc, so each client simulates it from the server's
-- launch record instead of waiting for ~20 Hz part replication. The authoritative part is hidden
-- locally while a visual exists and shown again once its BallState leaves InFlight (after a short
-- glide onto the real ball, so the swap never jumps).
-- The local thrower predicts the launch on release and blends into the server arc when it arrives.
-- An enemy ball whose arc is about to pass close to you carries a "!" above it all the way in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallDefinitions = require(Shared.BallDefinitions)
local ProjectileMath = require(Shared.ProjectileMath)
local Net = require(script.Parent.Net)
local HubController = require(script.Parent.HubController)
local OutlineController = require(script.Parent.OutlineController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

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
	lobby: boolean, -- a practice throw in the hub (collides with hub scenery, not the court)
	team: string?, -- the thrower's team (nil for your own throws: never a threat)
	warning: BillboardGui?, -- the "!" while it's heading at you
	radius: number,
	threat: boolean, -- last threat check result (re-checked at THREAT_RATE, not every frame)
	nextThreatAt: number,
	handoffAt: number?, -- the server ended the flight: glide onto the real ball, then hand over
}

local BallVisualController = {}

local BLEND_TIME = 0.15
local THREAT_RATE = 1 / 20 -- the "!" toggle doesn't need a 36-sample arc check every frame
-- Handoff: when a flight ends, the real ball's replicated position can be a sync or two stale
-- (in-flight parts are only written at 10 Hz), and showing it at once made balls jump backward on
-- landing and catches. The visual waits briefly for fresh replication, glides onto it, then swaps.
local HANDOFF_WAIT = 0.15 -- hold at most this long while the real ball is still far away
local HANDOFF_FAR = 4
local HANDOFF_DONE = 1.5 -- swap once this close (under two frames of motion at throw speed)
local HANDOFF_MAX = 0.4
local HANDOFF_RATE = 25
local folder: Folder
local visuals: { [Visual]: boolean } = {}
local byBallId: { [number]: Visual } = {}
local predicted: { [number]: Visual } = {} -- by throwId
local serverParts: { [number]: BasePart } = {}

-- GetServerTimeNow() wobbles by a few ms frame to frame as its clock estimate updates, which shows
-- up as micro-stutter on a 140 stud/s ball. Track its offset from os.clock() and ease it, snapping
-- only on a real resync.
local clockOffset: number? = nil
local function smoothServerNow(): number
	local c = os.clock()
	local target = Workspace:GetServerTimeNow() - c
	local offset = clockOffset
	if offset == nil or math.abs(target - offset) > 0.25 then
		offset = target
	else
		offset += (target - offset) * 0.05
	end
	clockOffset = offset
	return c + offset
end

local function makePart(ballType: string, at: Vector3): Part
	local def = BallDefinitions.get(ballType)
	local p = Instance.new("Part")
	p.Name = "BallVisual"
	p:SetAttribute("BallType", ballType) -- read by HalloweenController (jack-o-lantern Standard balls)
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
		OutlineController.setBallShown(part, not hidden)
	end
end

-- The incoming-ball warning: a joy-red "!" disc that rides above the ball.
local function makeWarning(ball: BasePart): BillboardGui
	local T = Theme.Toybox
	local bb = Instance.new("BillboardGui")
	bb.Name = "IncomingWarning"
	bb.Size = UDim2.fromOffset(40, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, ball.Size.Y / 2 + 1.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.ResetOnSpawn = false
	local disc = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundColor3 = T.joyRed,
	}, bb)
	Theme.round(disc)
	Theme.stroke(disc, T.paper, 3)
	local mark = Theme.text(disc, 26, {
		Size = UDim2.fromScale(1, 1),
		Text = "!",
		TextColor3 = T.paper,
		FontFace = Theme.DisplayFace,
	})
	Theme.textStroke(mark, 2)
	local scale = Theme.new("UIScale", { Scale = 0.3 }, disc)
	Theme.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	bb.Adornee = ball
	bb.Parent = ball
	return bb
end

-- Does this enemy arc pass within WarnRadius of you in the next WarnLookahead seconds, while still
-- heading your way?
local function threatens(v: Visual, t: number, me: Vector3): boolean
	local A = Config.AimAssist
	local step = 1 / 30
	local s = 0
	local radiusSq = A.WarnRadius * A.WarnRadius
	while s <= A.WarnLookahead do
		local at = t + s
		local pos = ProjectileMath.positionAt(v.origin, v.vel, v.g, at)
		local rel = me - pos
		if rel:Dot(rel) < radiusSq then
			return s > 0 or ProjectileMath.velocityAt(v.vel, v.g, at):Dot(rel) > 0
		end
		s += step
	end
	return false
end

local function remove(v: Visual)
	visuals[v] = nil
	local ballId = v.ballId
	local owns = ballId ~= nil and byBallId[ballId] == v
	if owns then
		byBallId[ballId :: number] = nil
	end
	if v.throwId and predicted[v.throwId] == v then
		predicted[v.throwId] = nil
	end
	-- never un-hide a real ball that a newer visual (a re-throw) is drawing
	if owns or (ballId ~= nil and byBallId[ballId :: number] == nil) then
		setServerHidden(ballId, false)
	end
	v.part:Destroy()
end

local function newVisual(part: Part, origin: Vector3, vel: Vector3, g: number, t0: number): Visual
	return {
		part = part,
		origin = origin,
		vel = vel,
		g = g,
		t0 = t0,
		offset = Vector3.zero,
		blendStart = 0,
		ballId = nil,
		throwId = nil,
		stoppedAt = nil,
		createdAt = os.clock(),
		lobby = false,
		team = nil,
		warning = nil,
		radius = part.Size.X / 2,
		threat = false,
		nextThreatAt = 0,
		handoffAt = nil,
	}
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
	local v = newVisual(makePart(ballType, origin), origin, vel, ProjectileMath.gravity(ballType), smoothServerNow())
	v.throwId = throwId
	v.lobby = (player:GetAttribute("Team") or "") == ""
	visuals[v] = true
	predicted[throwId] = v
	local held = heldPartOfMine()
	if held then
		-- a catch you're re-throwing may still be gliding in: finish it first
		local heldId = held:GetAttribute("BallId")
		local old = if type(heldId) == "number" then byBallId[heldId] else nil
		if old then
			remove(old)
		end
		held.LocalTransparencyModifier = 1 -- the real ball is still welded until the server acts
		OutlineController.setBallShown(held, false)
		v.ballId = held:GetAttribute("BallId") :: number?
	end
end

local function onLaunched(d: any)
	if type(d.id) ~= "number" or typeof(d.origin) ~= "Vector3" or typeof(d.vel) ~= "Vector3" then
		return
	end
	local serverNow = smoothServerNow()
	local g = ProjectileMath.gravity(d.ballType)
	local mine: Visual? = if d.thrower == player then predicted[d.throwId] else nil
	if mine then
		local stale = byBallId[d.id]
		if stale and stale ~= mine then
			remove(stale)
		end
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
	local lobby = d.context == "Lobby"
	if lobby and HubController.lobbyHidden then
		return -- you're on the court and the hub is hidden: don't draw practice throws
	end
	local part = makePart(d.ballType, ProjectileMath.positionAt(d.origin, d.vel, g, math.max(serverNow - d.t0, 0)))
	local v = newVisual(part, d.origin, d.vel, g, d.t0)
	v.ballId = d.id
	v.lobby = lobby
	v.team = if d.thrower ~= player and type(d.team) == "string" then d.team else nil
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
				table.insert(
					keys,
					ColorSequenceKeypoint.new(if #look.trail == 1 then 0 else (i - 1) / (#look.trail - 1), col)
				)
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
		local state = part:GetAttribute("BallState")
		if v and state ~= "InFlight" and not v.handoffAt then
			-- the server decided the outcome: glide onto the real ball, then show it
			if state == "Resetting" then
				remove(v) -- out of bounds: it vanishes anyway
			else
				v.handoffAt = os.clock()
				if v.warning then
					v.warning:Destroy()
					v.warning = nil
				end
			end
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

	-- court throws stop at court scenery; hub practice throws at the hub deck and its ball net.
	-- The filters are only re-marshalled when the scenery they point at changes, not every frame.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local lobbyParams = RaycastParams.new()
	lobbyParams.FilterType = Enum.RaycastFilterType.Include
	local courtScenery: Instance? = nil
	local lobbyRoot: Instance? = nil
	local lobbyDirty = true
	local lobbyConns: { RBXScriptConnection } = {}
	local function markLobbyDirty()
		lobbyDirty = true
	end
	local function refreshFilters()
		local arena = Workspace:FindFirstChild("Arena")
		local collidable = arena and arena:FindFirstChild("Collidable")
		if collidable ~= courtScenery then
			courtScenery = collidable
			params.FilterDescendantsInstances = if collidable then { collidable } else {}
		end
		local lobby = Workspace:FindFirstChild("Lobby")
		if lobby ~= lobbyRoot then
			lobbyRoot = lobby
			lobbyDirty = true
			for _, conn in lobbyConns do
				conn:Disconnect()
			end
			table.clear(lobbyConns)
			if lobby then
				table.insert(lobbyConns, lobby.ChildAdded:Connect(markLobbyDirty))
				table.insert(lobbyConns, lobby.ChildRemoved:Connect(markLobbyDirty))
			end
		end
		if lobbyDirty then
			lobbyDirty = false
			lobbyParams.FilterDescendantsInstances = if lobby then lobby:GetChildren() else {}
		end
	end

	RunService.RenderStepped:Connect(function(dt: number)
		if next(visuals) == nil then
			return -- nothing in flight
		end
		local clock = os.clock()
		refreshFilters() -- two lookups; it only re-marshals a filter when the scenery changed
		local serverNow = smoothServerNow()
		local myTeam = player:GetAttribute("Team")
		local character = player.Character
		local myRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for v in visuals do
			if v.handoffAt then
				local real = if v.ballId then serverParts[v.ballId] else nil
				local elapsed = clock - v.handoffAt
				if not real or elapsed > HANDOFF_MAX then
					remove(v)
					continue
				end
				local cur = v.part.Position
				local target = real.Position
				local gap = (target - cur).Magnitude
				if gap < HANDOFF_DONE then
					remove(v)
				elseif gap < HANDOFF_FAR or elapsed > HANDOFF_WAIT then
					v.part.CFrame = CFrame.new(cur:Lerp(target, 1 - math.exp(-dt * HANDOFF_RATE)))
				end -- else: the real ball's fresh position hasn't replicated yet; hold here
				continue
			end
			local t = serverNow - v.t0
			-- predictions the server never confirmed, and arcs past max flight time, expire
			if t > Config.Ball.MaxFlightTime + 0.5 or (v.ballId == nil and clock - v.createdAt > 1) then
				remove(v)
				continue
			end
			if v.stoppedAt then
				continue
			end
			local pos = ProjectileMath.positionAt(v.origin, v.vel, v.g, math.max(t, 0))
			if v.blendStart > 0 then
				local blend = 1 - (clock - v.blendStart) / BLEND_TIME
				if blend > 0 then
					pos += v.offset * blend
				else
					v.blendStart = 0 -- prediction error fully blended out
				end
			end
			-- hold at scenery contact until the server's verdict replicates (never draw through floors)
			local last = v.part.Position
			local delta = pos - last
			if delta.Magnitude > 1e-3 and (clock - v.createdAt) > 0.05 then
				local hit = Workspace:Spherecast(last, v.radius, delta, if v.lobby then lobbyParams else params)
				if hit then
					pos = hit.Position + hit.Normal * v.radius
					v.stoppedAt = pos
				end
			end
			v.part.CFrame = CFrame.new(pos)
			-- incoming warning: enemy balls about to pass close to you
			if v.team ~= nil and v.team ~= myTeam and not v.lobby and v.stoppedAt == nil and myRoot ~= nil then
				if clock >= v.nextThreatAt then
					v.nextThreatAt = clock + THREAT_RATE
					v.threat = threatens(v, math.max(t, 0), myRoot.Position)
				end
			else
				v.threat = false
			end
			if v.threat and not v.warning then
				v.warning = makeWarning(v.part)
			elseif not v.threat and v.warning then
				v.warning:Destroy()
				v.warning = nil
			end
		end
	end)
end

return BallVisualController
