--!strict
-- Hub practice, entirely client-side: your own practice dummy and practice balls, simulated on your
-- machine. Nobody else sees them, nothing waits on the network, and the dummy really flies off the
-- open end of the deck and falls into the void, then a fresh one stands back up. Everything lives
-- in Workspace.Lobby.Practice, so it disappears with the hub while you're on the court
-- (HubController). Until the tutorial is done, practice moves to your own copy of the court instead
-- (Config.Tutorial.Court): you stand on the Red half, the dummy on the far half, and knocking it
-- off the court works as in a match. The only thing sent to the server is the tutorial event
-- (Practice remote).
-- A Standard ball you hold or throw wears your equipped skin, as match balls do. The dummy shows its
-- damage % overhead. At the tutorial's Heavy step it stands up at Config.Tutorial.HeavyDummyDamage
-- and one practice ball turns Heavy (power balls keep their own look, as in a match).

local CollectionService = game:GetService("CollectionService")
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
local BallSkinController = require(script.Parent.BallSkinController)
local BallGuideController = require(script.Parent.BallGuideController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local PR = Config.Practice
local TU = Config.Tutorial
local HEAVY_STEP = 4 -- the tutorial's Heavy step (docs/prompts/build-path.md)

local PracticeController = {}

type PBall = {
	part: Part,
	home: Vector3,
	ballType: string, -- BallDefinitions type: flight, damage and knockback all use it
	state: string, -- "Resting" | "Held" | "InFlight" | "Loose" | "Gone"
	weld: WeldConstraint?,
	pos: Vector3,
	vel: Vector3,
	throwOrigin: Vector3?, -- where it left the hand (closer hits deal more damage)
	flightT: number,
	lockUntil: number,
	backAt: number,
	homeAt: number, -- a missed tutorial Heavy ball goes back to its spot at this time (0 = never)
}

-- Where practice happens: the hub deck, or the tutorial's copy of the court.
type Place = {
	root: Instance, -- Workspace.Lobby or the court copy: practice pauses while it's out of the Workspace
	folder: Folder, -- the dummy and balls
	geometry: () -> { Instance }, -- what practice balls bounce off
	ballSpots: { Vector3 },
	dummyAt: Vector3,
	facing: Vector3, -- the dummy faces this way (your side)
	voidY: number,
	isOut: (pos: Vector3) -> boolean, -- a launched dummy here is off the stage
	standAt: (pos: Vector3) -> Vector3?, -- where a launched dummy still on the stage stands back up
	away: (pos: Vector3) -> boolean, -- a ball resting here is out of your reach: it comes home
	spawn: CFrame?, -- the court only: where you stand, and are put back after a fall
}

local hubRoot: Instance? = nil
local place: Place? = nil
local balls: { PBall } = {}
local held: PBall? = nil
local dummy: Model? = nil
local dummyHitbox: BasePart? = nil
local dummyDown = false
local dummyHitAt = 0
local dummyDamage = 0 -- damage % (knockback escalation); a fresh dummy starts over
local dummyHits = 0 -- hits since this dummy stood up: only a dummy you knocked off counts as out
local dummyLastHit = "" -- the ball type that hit it last (HeavyOut needs a Heavy hit)
local dummyBackAt = 0
local dummyTag: { label: TextLabel, shown: number }? = nil
local collide: { [BasePart]: boolean } = {}
local rng = Random.new()
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function active(): boolean
	return place ~= nil and place.root.Parent == Workspace
end

local equipped: { [string]: string } = {} -- from the server's Profile
local tutorialStep = 0 -- the server's Tutorial message; 0 until it arrives
local holdCourt = false -- the tutorial just finished: stay on the court until its Done card closes
local courtPending = false -- the tutorial court is wanted but the real one hasn't streamed in yet
local placed: Model? = nil -- the character last put on the court's spawn
local ballsEnabled = true -- setBallsEnabled: the dodge drill puts the balls away
local heavyBall: PBall? = nil -- the ball that's Heavy during the tutorial's Heavy step

local form: string? = nil -- the Legendary skin form your last practice pickup showed

local function heavyStep(): boolean
	return tutorialStep == HEAVY_STEP
end

-- Your skin while a Standard ball is yours (held or in flight), the plain look of its type otherwise.
local function applySkin(b: PBall)
	local def = BallDefinitions.get(b.ballType)
	local skin = Catalog.equipped(equipped, "BallSkin").Data
	local mine = b.ballType == "Standard" and (b.state == "Held" or b.state == "InFlight")
	b.part.Color = if mine and typeof(skin.Color) == "Color3" then skin.Color else def.Color
	b.part.Material = if mine and typeof(skin.Material) == "EnumItem" then skin.Material :: any else def.Material
	b.part.Reflectance = if mine and type(skin.Reflectance) == "number" then skin.Reflectance else 0
	b.part:SetAttribute("SkinPattern", if mine then skin.Pattern else nil) -- BallSkinController
	b.part:SetAttribute("SkinModel", if mine then skin.Model else nil) -- BallSkinController
	b.part:SetAttribute("SkinVariant", if mine then form else nil) -- a Legendary skin's form
end

local function setState(b: PBall, state: string)
	b.state = state
	if state == "Held" and b.ballType == "Standard" then
		-- a Legendary skin shows a fresh form on every pickup, as in a match (ShopService.pickForm)
		local variants = Catalog.equipped(equipped, "BallSkin").Data.Variants
		if type(variants) == "table" and #variants > 0 then
			form = BallSkinController.pickForm(variants, form)
			BallSkinController.flourish(form)
		else
			form = nil
		end
	end
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

-- Size, BallType (HalloweenController's pumpkin is Standard-only) and the power-ball glow, as
-- BallService.applyLook does for match balls.
local function setType(b: PBall, ballType: string)
	b.ballType = ballType
	local p = b.part
	p.Size = Vector3.one * ProjectileMath.radius(ballType) * 2
	p:SetAttribute("BallType", ballType)
	local light = p:FindFirstChild("TypeLight") :: PointLight?
	if light then
		light.Enabled = ballType ~= "Standard"
		light.Color = BallDefinitions.get(ballType).Color
	end
	applySkin(b)
end

local function makeBall(home: Vector3): PBall
	local p = Instance.new("Part")
	p.Name = "PracticeBall"
	p.Shape = Enum.PartType.Ball
	p.CollisionGroup = "Ball"
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.6, 0.55, 1, 1)
	p:SetAttribute("Context", "Lobby")
	local light = Instance.new("PointLight")
	light.Name = "TypeLight"
	light.Range = 8
	light.Brightness = 1.5
	light.Enabled = false
	light.Parent = p
	p.Parent = (place :: Place).folder
	local b: PBall = {
		part = p,
		home = home,
		ballType = "Standard",
		state = "Resting",
		weld = nil,
		pos = home,
		vel = Vector3.zero,
		flightT = 0,
		lockUntil = 0,
		backAt = 0,
		homeAt = 0,
	}
	setType(b, "Standard")
	setState(b, "Resting")
	physical(b, home, Vector3.zero)
	return b
end

local function setHeldAttr(b: PBall?)
	-- the HUD chip, the aim controller (throw speed and arc) and the floor arrows read this; the
	-- server never sets it in the hub, so the local value stands until we clear it
	player:SetAttribute("HeldBall", if b then b.ballType else "")
end

-- The type a ball should be right now: Heavy for the tutorial's Heavy ball, else Standard.
local function wantedType(b: PBall): string
	return if heavyStep() and b == heavyBall then "Heavy" else "Standard"
end

local function hide(b: PBall, backAt: number)
	setState(b, "Gone")
	b.part.Anchored = true
	b.part.CanCollide = false
	b.part.Transparency = 1
	b.backAt = backAt
end

local function returnHome(b: PBall)
	if held == b then
		held = nil
		setHeldAttr(nil)
	end
	if b.weld then
		b.weld:Destroy()
		b.weld = nil
	end
	b.homeAt = 0
	if b.ballType ~= wantedType(b) then
		setType(b, wantedType(b))
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
	b.homeAt = 0
	held = b
	setState(b, "Held")
	setHeldAttr(b)
	SoundController.play("Pickup", p.Position)
	Net.request(Net.Actions.Practice, { event = "Pickup" })
end

function PracticeController.throw(dir: Vector3, origin: Vector3, speed: number)
	local b = held
	if not b then
		return
	end
	held = nil
	setHeldAttr(nil)
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
	b.throwOrigin = origin
	b.flightT = 0
	b.lockUntil = os.clock() + PR.ThrowerLockout
	setState(b, "InFlight")
	SoundController.play("Throw", origin)
	Net.request(Net.Actions.Practice, { event = "Throw" })
end

-- Dummy -------------------------------------------------------------------------------------------

-- A fresh dummy's damage %: HeavyDummyDamage at the tutorial's Heavy step, else 0.
local function startDamage(): number
	return if heavyStep() then TU.HeavyDummyDamage else 0
end

-- The % over its head, drawn like DamageController's enemy tags (and the same pop when it rises). From
-- the practice lane the banner over the practice wall hides everything much above the dummy's head
-- (and its sun-yellow letters swallow a sun-yellow %), so the % sits just over the head, drawn on
-- top, and the name tag goes above it.
local function refreshTag()
	local t = dummyTag
	if not t then
		return
	end
	local damage = math.floor(dummyDamage + 0.5)
	t.label.Text = ("%d%%"):format(damage)
	t.label.TextColor3 = ProjectileMath.damageColor(damage)
	if damage > t.shown then
		Theme.pop(t.label, 1.5, Theme.Motion.Base)
	end
	t.shown = damage
end

local function makeTag(head: BasePart)
	local board = Theme.new("BillboardGui", {
		Name = "DamageTag",
		Size = UDim2.new(2.4, 48, 1, 22),
		StudsOffset = Vector3.new(0, 2.2, 0),
		MaxDistance = 110,
		LightInfluence = 0,
		AlwaysOnTop = true,
	}, nil)
	local label = Theme.label(board, { Size = UDim2.fromScale(1, 1) }, 3)
	board.Adornee = head
	board.Parent = head
	dummyTag = { label = label, shown = math.floor(dummyDamage + 0.5) }
	refreshTag()
end

local function spawnDummy()
	local template = ReplicatedStorage:FindFirstChild(PR.TemplateName)
	local at = place
	if not template or not template:IsA("Model") or not at then
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
		bb.StudsOffset = Vector3.new(0, 4.4, 0) -- above the damage % (makeTag)
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
	m:PivotTo(CFrame.lookAt(at.dummyAt, Vector3.new(at.facing.X, at.dummyAt.Y, at.facing.Z)))
	m.Parent = at.folder
	dummy = m
	dummyHitbox = box
	dummyDown = false
	dummyDamage = startDamage()
	dummyHits = 0
	dummyLastHit = ""
	dummyBackAt = 0
	dummyTag = nil
	if head and head:IsA("BasePart") then
		makeTag(head)
	end
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
	local ballType = ball.ballType
	local scale = ProjectileMath.escalation(dummyDamage)
	local dist = if ball.throwOrigin then ProjectileMath.flatDistance(ball.throwOrigin, at) else nil
	dummyDamage = math.min(dummyDamage + ProjectileMath.damageFor(ballType, dist), Config.Damage.Cap)
	dummyHits += 1
	dummyLastHit = ballType
	refreshTag()
	local kb = ProjectileMath.knockback(ball.vel, ballType, scale)
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
		ballType = ballType,
		position = at,
		direction = ball.vel,
		targetModel = m,
		thrower = player,
		escalation = scale,
	})
	HUDController.hitmarker()
	HUDController.hint("HIT!", 0.6)
	Net.request(Net.Actions.Practice, { event = "HitDummy" })
end

local function updateDummy(at: Place)
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
	if at.isOut(root.Position) then
		-- off the stage: a new one stands up at home shortly. Only a dummy you hit counts as
		-- knocked off (the tutorial's KnockOff and Heavy steps).
		if dummyHits > 0 then
			Net.request(Net.Actions.Practice, { event = "DummyOut" })
			if heavyStep() and dummyLastHit == "Heavy" then
				Net.request(Net.Actions.Practice, { event = "HeavyOut" })
			end
		end
		m:Destroy()
		dummy = nil
		dummyTag = nil
		dummyHits = 0
		dummyBackAt = os.clock() + PR.DummyRespawn
		return
	end
	if dummyDown and os.clock() - dummyHitAt > PR.RecoverAfter then
		-- still on the stage: stand back up where it landed
		local stand = at.standAt(root.Position)
		if stand then
			dummyDown = false
			setLimp(m, false)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.AssemblyLinearVelocity = Vector3.zero
					d.AssemblyAngularVelocity = Vector3.zero
				end
			end
			m:PivotTo(CFrame.lookAt(stand, Vector3.new(at.facing.X, stand.Y, at.facing.Z)))
		end
	end
end

-- Simulation ---------------------------------------------------------------------------------------

-- A thrown ball lands loose. During the Heavy step the Heavy ball then goes back to its spot, so a
-- miss (or a hit that leaves the dummy on the deck) can be tried again.
local function land(b: PBall, pos: Vector3, vel: Vector3)
	setState(b, "Loose")
	physical(b, pos, vel)
	if heavyStep() and b == heavyBall then
		b.homeAt = os.clock() + TU.HeavyReturnAfter
	end
end

local function stepFlight(b: PBall, dt: number)
	local g = ProjectileMath.gravity(b.ballType)
	local radius = ProjectileMath.radius(b.ballType)
	local from = b.pos
	local nextVel = b.vel + Vector3.new(0, -g * dt, 0)
	local to = from + (b.vel + nextVel) * 0.5 * dt
	local delta = to - from
	local hit = if delta.Magnitude > 1e-4 then Workspace:Spherecast(from, radius, delta, castParams) else nil
	if hit then
		if dummyHitbox and hit.Instance == dummyHitbox and not dummyDown then
			launchDummy(b, hit.Position)
			land(b, hit.Position, -b.vel * 0.12 + Vector3.new(0, 14, 0))
			return
		elseif hit.Instance ~= dummyHitbox then
			local n = hit.Normal
			local v = b.vel
			land(b, hit.Position + n * (radius + 0.05), (v - 2 * v:Dot(n) * n) * 0.45)
			return
		end
	end
	b.pos = to
	b.vel = nextVel
	b.flightT += dt
	b.part.CFrame = CFrame.new(to)
	if b.flightT > Config.Ball.MaxFlightTime or to.Y < (place :: Place).voidY then
		hide(b, os.clock() + PR.BallRespawn)
	end
end

local function step(dt: number)
	if not active() then
		return
	end
	local at = place :: Place
	local list = at.geometry()
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
	-- on the tutorial court: stand on its spawn when you get there (or respawn), and after a fall
	local spawnAt = at.spawn
	if spawnAt and hub and character and root and (placed ~= character or root.Position.Y < at.voidY) then
		placed = character
		character:PivotTo(spawnAt)
		root.AssemblyLinearVelocity = Vector3.zero
		-- the camera keeps the hub's angle otherwise: look down the court at the dummy
		local CharacterController = require(script.Parent.CharacterController) :: any
		CharacterController.faceCameraAt(root, at.dummyAt, true)
	end
	local action = player:GetAttribute("Action")
	local canGrab = hub
		and ballsEnabled
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
			if b.homeAt == 0 and at.away(p.Position) then
				b.homeAt = t + TU.Court.AwayReturn -- out of your reach (the far half of the court)
			end
			if p.Position.Y < at.voidY then
				hide(b, t + PR.BallRespawn)
			elseif (b.homeAt > 0 and t >= b.homeAt) or b.ballType ~= wantedType(b) then
				returnHome(b)
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
		elseif b.state == "Gone" and ballsEnabled and t >= b.backAt then
			returnHome(b)
		end
	end
	updateDummy(at)
end

-- Bring the balls and dummy in line with the tutorial step. Safe to repeat: it runs on every
-- Tutorial message and once the practice area is built (the message can arrive first).
local function applyStep()
	if not heavyStep() then
		heavyBall = nil
	elseif not heavyBall then
		-- one ball turns Heavy: the first one you're not holding or throwing. A ball whose type
		-- is wrong goes back to its spot as the new type once it's at rest (step)
		for _, b in balls do
			if b.state ~= "Held" and b.state ~= "InFlight" then
				heavyBall = b
				break
			end
		end
		heavyBall = heavyBall or balls[1]
	end
	-- a dummy nobody has hit yet takes the step's starting % (it may have stood up before the step
	-- message arrived)
	if dummy and dummyHits == 0 and dummyDamage ~= startDamage() then
		dummyDamage = startDamage()
		refreshTag()
	end
end

-- Places ------------------------------------------------------------------------------------------

-- The hub deck: the practice balls sit along the lane in front of the practice wall, and the dummy
-- stands near the open end.
local function hubPlace(lobby: Instance): Place
	local P = Config.Lobby.Practice
	local spots = {}
	for i = 1, PR.Balls do
		local offset = (i - (PR.Balls + 1) / 2) * PR.BallSpread
		table.insert(spots, ArenaLayout.lobbyPoint(P.BallX, 2, P.F + offset))
	end
	local f = Instance.new("Folder")
	f.Name = "Practice"
	f.Parent = lobby
	return {
		root = lobby,
		folder = f,
		geometry = function(): { Instance }
			local list = {}
			for _, name in { "Collidable", "Barriers" } do
				local x = lobby:FindFirstChild(name)
				if x then
					table.insert(list, x)
				end
			end
			return list
		end,
		ballSpots = spots,
		dummyAt = ArenaLayout.DummyHome,
		facing = ArenaLayout.DummyFacing,
		voidY = ArenaLayout.LobbyVoidY,
		isOut = function(pos: Vector3): boolean
			return pos.Y < ArenaLayout.LobbyVoidY
		end,
		standAt = function(pos: Vector3): Vector3?
			if ArenaLayout.inLobby(pos, -1) and pos.Y > Config.Arena.LobbyOrigin.Y - 2 then
				return ArenaLayout.clampToLobby(Vector3.new(pos.X, Config.Arena.LobbyOrigin.Y + 3, pos.Z), 2)
			end
			return nil
		end,
		away = function(_pos: Vector3): boolean
			return false
		end,
		spawn = nil,
	}
end

-- The tutorial court: a local copy of workspace.Arena at Config.Tutorial.Court.Offset (built like
-- FinisherController's preview court: tags, scripts and prompts stripped). You stand on the Red half;
-- the dummy is on the far half and is out once it's off the court, as a player would be.
local function courtPlace(): Place?
	local arena = Workspace:FindFirstChild("Arena")
	local floors = arena and arena:FindFirstChild("Collidable")
	-- the court streams in after its folders: wait for both halves' floors (ArenaBuilder's Core_*)
	if not arena or not floors or not floors:FindFirstChild("Core_Red") or not floors:FindFirstChild("Core_Blue") then
		return nil
	end
	local C = TU.Court
	local A = Config.Arena
	local wasArchivable = arena.Archivable
	arena.Archivable = true
	local copy = arena:Clone()
	arena.Archivable = wasArchivable
	copy.Name = "TutorialCourt"
	for _, d in copy:GetDescendants() do
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag)
		end
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CFrame += C.Offset
		end
	end
	local o = A.Origin + C.Offset
	local hw, hl = ArenaLayout.HalfWidth, ArenaLayout.HalfLength
	-- the court's edge walls only hold players in a match: wall your half in for walkers (the centre
	-- barrier is already in the copy). Balls and the dummy pass straight through PlayerWall.
	local walls = Instance.new("Folder")
	walls.Name = "TutorialWalls"
	walls.Parent = copy
	for _, w in
		{
			{ Vector3.new(-hw - 0.5, 10, -hl / 2), Vector3.new(1, 20, hl) },
			{ Vector3.new(hw + 0.5, 10, -hl / 2), Vector3.new(1, 20, hl) },
			{ Vector3.new(0, 10, -hl - 0.5), Vector3.new(hw * 2 + 2, 20, 1) },
		}
	do
		Theme.new("Part", {
			Name = "TutorialWall",
			Anchored = true,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			CollisionGroup = "PlayerWall",
			Size = w[2],
			CFrame = CFrame.new(o + w[1]),
		}, walls)
	end
	local f = Instance.new("Folder")
	f.Name = "Practice"
	f.Parent = copy
	copy.Parent = Workspace
	local collidable = copy:FindFirstChild("Collidable")
	return {
		root = copy,
		folder = f,
		geometry = function(): { Instance }
			return if collidable then { collidable } else {}
		end,
		ballSpots = {
			o + Vector3.new(-C.BallSpread / 2, 2, -C.BallZ),
			o + Vector3.new(C.BallSpread / 2, 2, -C.BallZ),
		},
		dummyAt = o + Vector3.new(0, 4, C.DummyZ),
		facing = o + Vector3.new(0, 4, -hl),
		voidY = ArenaLayout.VoidY,
		isOut = function(pos: Vector3): boolean
			local rel = pos - o
			local e = A.EjectDistance -- this far past the edge, a body can't come back (as in a match)
			return pos.Y < ArenaLayout.VoidY or math.abs(rel.X) > hw + e or math.abs(rel.Z) > hl + e
		end,
		standAt = function(pos: Vector3): Vector3?
			local rel = pos - o
			if math.abs(rel.X) <= hw and math.abs(rel.Z) <= hl and pos.Y > A.Origin.Y - 2 then
				return o + Vector3.new(math.clamp(rel.X, -hw + 2, hw - 2), 3, math.clamp(rel.Z, 6, hl - 2))
			end
			return nil
		end,
		away = function(pos: Vector3): boolean
			local rel = pos - o
			return rel.Z > -0.5 or rel.Z < -hl or math.abs(rel.X) > hw
		end,
		spawn = CFrame.lookAt(o + Vector3.new(0, 4, -C.SpawnZ), o + Vector3.new(0, 4, 0)),
	}
end

-- Take down the current place: its balls (out of your hand too), its dummy, and the court copy.
local function clearPlace()
	if held then
		held = nil
		setHeldAttr(nil)
	end
	for _, b in balls do
		b.part:Destroy()
	end
	table.clear(balls)
	heavyBall = nil
	if dummy then
		dummy:Destroy()
	end
	dummy, dummyHitbox, dummyTag = nil, nil, nil
	dummyDown, dummyHits, dummyBackAt = false, 0, 0
	local was = place
	place = nil
	if was then
		if was.spawn then
			was.root:Destroy()
		else
			was.folder:Destroy()
		end
	end
end

local function usePlace(p: Place)
	clearPlace()
	place = p
	placed = nil
	for _, spot in p.ballSpots do
		table.insert(balls, makeBall(spot))
	end
	spawnDummy()
	applyStep()
end

-- The court until the tutorial is done (and its Done card closed), the hub after.
local function syncPlace()
	local lobby = hubRoot
	if not lobby then
		return -- not set up yet (start)
	end
	local onCourt = place ~= nil and place.spawn ~= nil
	local wantCourt = (tutorialStep >= 1 and tutorialStep < TU.Done) or holdCourt
	courtPending = false
	if wantCourt and not onCourt then
		local p = courtPlace()
		if p then
			usePlace(p)
		else
			courtPending = true -- the court hasn't streamed in yet: try again next frame (step)
		end
	elseif not wantCourt and (onCourt or place == nil) then
		usePlace(hubPlace(lobby))
	end
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

-- Your practice dummy (nil while it's respawning), for the tutorial's dodge drill.
function PracticeController.dummyModel(): Model?
	local m = dummy
	return if m and m.Parent then m else nil
end

-- Your practice balls' parts and types (the tutorial's arrows point at them).
function PracticeController.ballParts(): { { part: BasePart, ballType: string, state: string } }
	local list = {}
	for _, b in balls do
		table.insert(list, { part = b.part, ballType = b.ballType, state = b.state })
	end
	return list
end

-- The tutorial step from the server's last Tutorial message (0 until it arrives).
function PracticeController.tutorialStep(): number
	return tutorialStep
end

-- Are you practising on the tutorial court (rather than the hub deck)?
function PracticeController.onCourt(): boolean
	return place ~= nil and place.spawn ~= nil
end

-- The tutorial's Done card closed: back to the hub, where practice carries on as before. During a
-- match (it can start while the card is up) the server has already moved you: just switch places.
function PracticeController.finishTutorial()
	if not holdCourt then
		return
	end
	holdCourt = false
	syncPlace()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character and root and inHub() then
		character:PivotTo(ArenaLayout.faceFlat(ArenaLayout.lobbySpawn(rng), ArenaLayout.CourtFocus))
		local CharacterController = require(script.Parent.CharacterController) :: any
		CharacterController.faceCameraAt(root, ArenaLayout.CourtFocus, true)
	end
end

-- Put your practice balls away (false) or back on their spots (true). While they're away you can't
-- grab one, and a held ball leaves your hand.
function PracticeController.setBallsEnabled(on: boolean)
	if on == ballsEnabled then
		return
	end
	ballsEnabled = on
	for _, b in balls do
		if not on then
			if held == b then
				held = nil
				setHeldAttr(nil)
			end
			if b.weld then
				b.weld:Destroy()
				b.weld = nil
			end
			b.homeAt = 0
			hide(b, 0)
		elseif b.state == "Gone" then
			b.backAt = 0 -- back on the next frame
		end
	end
end

function PracticeController.start()
	Net.on("Profile", function(d)
		equipped = if type(d) == "table" and type(d.equipped) == "table" then d.equipped else {}
		for _, b in balls do
			applySkin(b)
		end
	end)
	Net.on("Tutorial", function(d)
		if type(d) == "table" and type(d.step) == "number" then
			-- finishing on the court: stay there until the Done card closes (finishTutorial)
			if d.step >= TU.Done and tutorialStep >= 1 and tutorialStep < TU.Done and place and place.spawn then
				holdCourt = true
			elseif d.step < TU.Done then
				holdCourt = false
			end
			tutorialStep = d.step
			applyStep()
			syncPlace()
		end
	end)
	BallGuideController.practiceBalls = function(): Instance?
		return if place then place.folder else nil
	end
	task.spawn(function()
		local l = Workspace:WaitForChild("Lobby", 60)
		if not l then
			return
		end
		ReplicatedStorage:WaitForChild(PR.TemplateName, 60)
		Workspace:WaitForChild("Arena", 60)
		hubRoot = l
		syncPlace()
		RunService.Heartbeat:Connect(function(dt)
			if holdCourt and not inHub() then
				PracticeController.finishTutorial() -- a match took you off the court copy first
			elseif courtPending then
				syncPlace()
			end
			step(dt)
		end)
	end)
end

return PracticeController
