--!strict
-- Hub practice, entirely client-side: your own practice dummy and practice balls, simulated on your
-- machine. Nobody else sees them, nothing waits on the network, and the dummy really flies off the
-- open end of the deck and falls into the void, then a fresh one stands back up. Everything lives
-- in Workspace.Lobby.Practice, so it disappears with the hub while you're on the court
-- (HubController). The only thing sent to the server is the tutorial event (Practice remote).
-- A ball you hold or throw wears your equipped skin, as match balls do.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local BallDefinitions = require(Shared.BallDefinitions)
local Catalog = require(Shared.Catalog)
local ProjectileMath = require(Shared.ProjectileMath)
local Net = require(script.Parent.Net)
local AimController = require(script.Parent.AimController)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer
local PR = Config.Practice

local PracticeController = {}

type PBall = {
	part: Part,
	home: Vector3,
	state: string, -- "Resting" | "Held" | "InFlight" | "Loose" | "Gone"
	weld: WeldConstraint?,
	pos: Vector3,
	vel: Vector3,
	charge: number,
	flightT: number,
	lockUntil: number,
	backAt: number,
}

local lobby: Instance? = nil
local folder: Folder? = nil
local balls: { PBall } = {}
local held: PBall? = nil
local dummy: Model? = nil
local dummyHitbox: BasePart? = nil
local dummyDown = false
local dummyHitAt = 0
local dummyHits = 0 -- knockback escalation; a fresh dummy starts over
local dummyBackAt = 0
local collide: { [BasePart]: boolean } = {}
local rng = Random.new()
local RADIUS = ProjectileMath.radius("Standard")
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function active(): boolean
	return lobby ~= nil and lobby.Parent == Workspace and folder ~= nil
end

local equipped: { [string]: string } = {} -- from the server's Profile

-- Your skin while the ball is yours (held or in flight), the plain Standard look otherwise.
local function applySkin(b: PBall)
	local def = BallDefinitions.get("Standard")
	local skin = Catalog.equipped(equipped, "BallSkin").Data
	local mine = b.state == "Held" or b.state == "InFlight"
	b.part.Color = if mine and typeof(skin.Color) == "Color3" then skin.Color else def.Color
	b.part.Material = if mine and typeof(skin.Material) == "EnumItem" then skin.Material :: any else def.Material
	b.part:SetAttribute("Pumpkin", if mine and skin.Pumpkin then true else nil) -- HalloweenController
end

local function setState(b: PBall, state: string)
	b.state = state
	applySkin(b)
	b.part:SetAttribute(
		"BallState",
		if state == "Loose" then "Spent" elseif state == "Gone" then "Resetting" else state
	)
end

-- Balls -------------------------------------------------------------------------------------------

local function physical(b: PBall, pos: Vector3, vel: Vector3)
	local p = b.part
	if b.weld then
		b.weld:Destroy()
		b.weld = nil
	end
	p.Anchored = false
	p.Massless = false
	p.CanCollide = true
	p.Transparency = 0
	p.CFrame = CFrame.new(pos)
	p.AssemblyLinearVelocity = vel
end

local function makeBall(home: Vector3): PBall
	local def = BallDefinitions.get("Standard")
	local p = Instance.new("Part")
	p.Name = "PracticeBall"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * RADIUS * 2
	p.Color = def.Color
	p.Material = def.Material
	p.CollisionGroup = "Ball"
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.6, 0.55, 1, 1)
	p:SetAttribute("Context", "Lobby")
	p.Parent = folder
	local b: PBall = {
		part = p,
		home = home,
		state = "Resting",
		weld = nil,
		pos = home,
		vel = Vector3.zero,
		charge = 0,
		flightT = 0,
		lockUntil = 0,
		backAt = 0,
	}
	setState(b, "Resting")
	physical(b, home, Vector3.zero)
	return b
end

local function setHeldAttr(on: boolean)
	-- the HUD chip, the aim controller and the floor arrows read this; the server never sets it in
	-- the hub, so the local value stands until we clear it
	player:SetAttribute("HeldBall", if on then "Standard" else "")
end

local function returnHome(b: PBall)
	if held == b then
		held = nil
		setHeldAttr(false)
	end
	setState(b, "Resting")
	physical(b, b.home + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), Vector3.zero)
end

local function pickUp(b: PBall, character: Model)
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not hand then
		return
	end
	local p = b.part
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.AssemblyLinearVelocity = Vector3.zero
	p.CFrame = hand.CFrame * CFrame.new(0, -0.6, -0.4)
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = p
	w.Parent = p
	b.weld = w
	held = b
	setState(b, "Held")
	setHeldAttr(true)
	SoundController.play("Pickup", p.Position)
	Net.request(Net.Actions.Practice, { event = "Pickup" })
end

function PracticeController.throw(dir: Vector3, origin: Vector3, speed: number, charge: number)
	local b = held
	if not b then
		return
	end
	held = nil
	setHeldAttr(false)
	if b.weld then
		b.weld:Destroy()
		b.weld = nil
	end
	local p = b.part
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.new(origin)
	b.pos = origin
	b.vel = dir * speed
	b.charge = charge
	b.flightT = 0
	b.lockUntil = os.clock() + PR.ThrowerLockout
	setState(b, "InFlight")
	SoundController.play("Throw", origin)
	Net.request(Net.Actions.Practice, { event = "Throw" })
end

-- Dummy -------------------------------------------------------------------------------------------

local function spawnDummy()
	local template = ReplicatedStorage:FindFirstChild(PR.TemplateName)
	if not template or not template:IsA("Model") or not folder then
		return
	end
	if dummy then
		dummy:Destroy()
	end
	local was = template.Archivable
	template.Archivable = true
	local m = template:Clone()
	template.Archivable = was
	m.Name = "PracticeDummy"
	table.clear(collide)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Default" -- hub walls stop walkers only, so the dummy can fly off the end
			collide[d] = d.CanCollide
		end
	end
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		m:Destroy()
		return
	end
	local box = Instance.new("Part")
	box.Name = "HitBox"
	box.Size = Config.Player.HitProxySize
	box.Transparency = 1
	box.CanCollide = false
	box.CanTouch = false
	box.CanQuery = true
	box.Massless = true
	box.CFrame = root.CFrame
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = box
	w.Parent = box
	box.Parent = m
	-- name tag
	local head = m:FindFirstChild("Head")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(120, 30)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 230, 120)
		t.TextStrokeTransparency = 0.3
		t.Text = "DUMMY"
		t.Parent = bb
		bb.Parent = head
	end
	m:PivotTo(CFrame.lookAt(ArenaLayout.DummyHome, ArenaLayout.DummyFacing))
	m.Parent = folder
	dummy = m
	dummyHitbox = box
	dummyDown = false
	dummyHits = 0
	dummyBackAt = 0
end

local function setLimp(m: Model, limp: boolean)
	for _, d in m:GetDescendants() do
		-- new rigs: AnimationConstraints hand over to their built-in ball sockets; a Motor6D only
		-- goes limp if the rig has a socket for it
		local joint = (d:IsA("AnimationConstraint") and d.Name ~= "Root")
			or (
				d:IsA("Motor6D")
				and d.Name ~= "Root"
				and d.Parent ~= nil
				and d.Parent:FindFirstChild(d.Name .. "BallSocket") ~= nil
			)
		if joint then
			(d :: any).Enabled = not limp
		end
	end
	for part, was in collide do
		if part.Parent and part.Name ~= "HumanoidRootPart" and part.Name ~= "HitBox" then
			part.CanCollide = if limp then true else was
		end
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	if h then
		h.PlatformStand = limp
		h:ChangeState(if limp then Enum.HumanoidStateType.Physics else Enum.HumanoidStateType.GettingUp)
	end
end

local function launchDummy(ball: PBall, at: Vector3)
	local m = dummy
	if not m then
		return
	end
	-- the dummy feels escalation like a real player: every hit launches it harder until it respawns
	local scale = ProjectileMath.escalation(dummyHits)
	dummyHits += 1
	local kb = ProjectileMath.knockback(ball.vel, ball.charge, "Standard", scale)
	local cap = ProjectileMath.maxKnockbackSpeed(scale)
	local K = Config.Knockback
	setLimp(m, true)
	local axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	axis = if axis.Magnitude > 0.1 then axis.Unit else Vector3.xAxis
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local flail = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1))
				* K.LimbFlail
			local v = kb + flail
			if v.Magnitude > cap then
				v = v.Unit * cap
			end
			d.AssemblyLinearVelocity = v
			d.AssemblyAngularVelocity = axis * K.TumbleSpin
				+ Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * K.LimbSpin
		end
	end
	dummyDown = true
	dummyHitAt = os.clock()
	EffectsController.localImpact({
		kind = "Hit",
		ballType = "Standard",
		position = at,
		direction = ball.vel,
		targetModel = m,
		thrower = player,
		charge = ball.charge,
		escalation = scale,
	})
	HUDController.hitmarker()
	HUDController.hint("HIT!", 0.6)
	Net.request(Net.Actions.Practice, { event = "HitDummy" })
end

local function updateDummy()
	local m = dummy
	local root = m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not m or not root or not m.Parent then
		if dummyBackAt == 0 then
			dummyBackAt = os.clock() + PR.DummyRespawn
		elseif os.clock() >= dummyBackAt then
			spawnDummy()
		end
		return
	end
	if root.Position.Y < ArenaLayout.LobbyVoidY then
		-- fell off the stage: a new one stands up at home shortly
		m:Destroy()
		dummy = nil
		dummyBackAt = os.clock() + PR.DummyRespawn
		return
	end
	if dummyDown and os.clock() - dummyHitAt > PR.RecoverAfter then
		-- still on the deck: stand back up where it landed
		local pos = root.Position
		if ArenaLayout.inLobby(pos, -1) and pos.Y > Config.Arena.LobbyOrigin.Y - 2 then
			dummyDown = false
			setLimp(m, false)
			local at = ArenaLayout.clampToLobby(Vector3.new(pos.X, Config.Arena.LobbyOrigin.Y + 3, pos.Z), 2)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.AssemblyLinearVelocity = Vector3.zero
					d.AssemblyAngularVelocity = Vector3.zero
				end
			end
			m:PivotTo(CFrame.lookAt(at, Vector3.new(ArenaLayout.DummyFacing.X, at.Y, ArenaLayout.DummyFacing.Z)))
		end
	end
end

-- Simulation ---------------------------------------------------------------------------------------

local function stepFlight(b: PBall, dt: number)
	local g = ProjectileMath.gravity("Standard")
	local from = b.pos
	local nextVel = b.vel + Vector3.new(0, -g * dt, 0)
	local to = from + (b.vel + nextVel) * 0.5 * dt
	local delta = to - from
	local hit = if delta.Magnitude > 1e-4 then Workspace:Spherecast(from, RADIUS, delta, castParams) else nil
	if hit then
		if dummyHitbox and hit.Instance == dummyHitbox and not dummyDown then
			launchDummy(b, hit.Position)
			setState(b, "Loose")
			physical(b, hit.Position, -b.vel * 0.12 + Vector3.new(0, 14, 0))
			return
		elseif hit.Instance ~= dummyHitbox then
			local n = hit.Normal
			local v = b.vel
			setState(b, "Loose")
			physical(b, hit.Position + n * (RADIUS + 0.05), (v - 2 * v:Dot(n) * n) * 0.45)
			return
		end
	end
	b.pos = to
	b.vel = nextVel
	b.flightT += dt
	b.part.CFrame = CFrame.new(to)
	if b.flightT > Config.Ball.MaxFlightTime or to.Y < ArenaLayout.LobbyVoidY then
		setState(b, "Gone")
		b.part.Anchored = true
		b.part.Transparency = 1
		b.backAt = os.clock() + PR.BallRespawn
	end
end

local function step(dt: number)
	if not active() then
		return
	end
	local lobbyFolder = lobby :: Instance
	local list: { Instance } = {}
	for _, name in { "Collidable", "Barriers" } do
		local f = lobbyFolder:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	if dummyHitbox then
		table.insert(list, dummyHitbox)
	end
	castParams.FilterDescendantsInstances = list
	local hub = inHub()
	-- leaving the hub (a match starting): the held practice ball goes back to its spot
	if not hub and held then
		returnHome(held)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local action = player:GetAttribute("Action")
	local canGrab = hub
		and held == nil
		and root ~= nil
		and (action == "Idle" or action == "Dodging" or action == "Recovering" or action == nil)
	local t = os.clock()
	for _, b in balls do
		if b.state == "InFlight" then
			local remaining = dt
			while remaining > 0 do
				local h = math.min(remaining, Config.Ball.SimStep)
				stepFlight(b, h)
				remaining -= h
				if b.state ~= "InFlight" then
					break
				end
			end
		elseif b.state == "Loose" or b.state == "Resting" then
			local p = b.part
			if p.Position.Y < ArenaLayout.LobbyVoidY then
				setState(b, "Gone")
				p.Anchored = true
				p.Transparency = 1
				b.backAt = t + PR.BallRespawn
			else
				if b.state == "Loose" and p.AssemblyLinearVelocity.Magnitude < Config.Ball.SettleSpeed then
					setState(b, "Resting")
				end
				if canGrab and t >= b.lockUntil and root then
					local rp = root.Position
					local d = Vector3.new(rp.X - p.Position.X, 0, rp.Z - p.Position.Z).Magnitude
					if d <= Config.Player.PickupRadius and math.abs(rp.Y - p.Position.Y) <= 7 then
						pickUp(b, character :: Model)
						canGrab = false
					end
				end
			end
		elseif b.state == "Gone" and t >= b.backAt then
			returnHome(b)
		end
	end
	updateDummy()
end

-- The practice balls sit along the lane in front of the practice wall.
local function ballSpots(): { Vector3 }
	local P = Config.Lobby.Practice
	local spots = {}
	for i = 1, PR.Balls do
		local offset = (i - (PR.Balls + 1) / 2) * PR.BallSpread
		table.insert(spots, ArenaLayout.lobbyPoint(P.BallX, 2, P.F + offset))
	end
	return spots
end

function PracticeController.init()
	AimController.localHeld = function(): boolean
		return held ~= nil
	end
	AimController.localThrow = PracticeController.throw
	-- in the hub the auto-aim locks on to your dummy
	AimController.extraTargets = function(): { Model }
		local m = dummy
		if m and m.Parent and not dummyDown and inHub() then
			return { m }
		end
		return {}
	end
end

function PracticeController.start()
	Net.on("Profile", function(d)
		equipped = if type(d) == "table" and type(d.equipped) == "table" then d.equipped else {}
		for _, b in balls do
			applySkin(b)
		end
	end)
	task.spawn(function()
		local l = Workspace:WaitForChild("Lobby", 60)
		if not l then
			return
		end
		lobby = l
		local f = Instance.new("Folder")
		f.Name = "Practice"
		f.Parent = l
		folder = f
		for _, spot in ballSpots() do
			table.insert(balls, makeBall(spot))
		end
		ReplicatedStorage:WaitForChild(PR.TemplateName, 60)
		spawnDummy()
		RunService.Heartbeat:Connect(step)
	end)
end

return PracticeController
