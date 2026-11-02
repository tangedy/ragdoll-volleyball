--!strict
-- The tutorial's dodge step (docs/prompts/build-path.md step 6), entirely client-side: on the
-- tutorial court your practice balls go away, the dummy turns to face you, winds up (a "!" over its
-- head and a glowing ball in its hand) and throws a practice ball straight at you, slower than a
-- match throw (Config.Tutorial.Drill). Dodging it sends Practice "Dodged", which finishes the step.
-- Getting hit gives you a small local knock and raises your HUD % locally (no ragdoll, no server
-- damage), sends GotHit, and the dummy throws again; after a few misses the throws slow down.
-- The drill ball is never a server ball, so it can't count toward the daily dodge quest.
--
-- Dodging is the real one (CombatService.doDodge, the client's DodgeMotion). The dash itself has no
-- immunity in a match, but here a ball that reaches you mid-dash goes through you and counts: a
-- first-time player's dodge with no direction held goes straight back along the ball's line, and
-- the step is about learning to press dodge, not which way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallDefinitions = require(Shared.BallDefinitions)
local ProjectileMath = require(Shared.ProjectileMath)
local Net = require(script.Parent.Net)
local EffectsController = require(script.Parent.EffectsController)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)
local PracticeController = require(script.Parent.PracticeController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local TU = Config.Tutorial
local D = TU.Drill
local T = Theme.Toybox
local DODGE_STEP = 6
local BALL_TYPE = "Standard"
local HIT_RADIUS = ProjectileMath.radius(BALL_TYPE) + 1.7 -- the ball touching your body

local TutorialDrillController = {}

type Shot = {
	part: Part,
	pos: Vector3,
	vel: Vector3,
	origin: Vector3,
	t: number,
	near: boolean, -- went by close enough, soon enough after a dodge, to count
}

local running = false
local misses = 0 -- hits and passes you didn't dodge, this drill
local phase = "Idle" -- "Idle" | "Windup" | "Flight" | "Done"
local phaseAt = 0 -- when the next phase starts (Idle) or this one started (Windup)
local shot: Shot? = nil
local telegraph: { Instance } = {}
local lastDodgeAt = -math.huge
local dodgeFrom: Vector3? = nil
local dashing = false
local damageBefore: any = nil -- your Damage attribute before the drill raised it locally
local localDamage = 0
local doneSentAt = 0

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function clearTelegraph()
	for _, inst in telegraph do
		inst:Destroy()
	end
	table.clear(telegraph)
end

local function clearShot()
	local s = shot
	if s then
		s.part:Destroy()
		shot = nil
	end
end

local function wantDrill(): boolean
	return PracticeController.tutorialStep() == DODGE_STEP and inHub() and PracticeController.onCourt()
end

local function stop()
	if not running then
		return
	end
	running = false
	clearTelegraph()
	clearShot()
	phase = "Idle"
	PracticeController.setBallsEnabled(true)
	if damageBefore ~= nil or localDamage > 0 then
		player:SetAttribute("Damage", damageBefore)
	end
	damageBefore, localDamage = nil, 0
end

local function begin()
	running = true
	misses = 0
	phase = "Idle"
	phaseAt = os.clock() + D.FirstDelay
	doneSentAt = 0
	PracticeController.setBallsEnabled(false)
end

-- The "!" over the dummy's head and a glowing ball in its right hand.
local function windup(m: Model, root: BasePart, me: Vector3)
	local at = root.Position
	m:PivotTo(CFrame.lookAt(m:GetPivot().Position, Vector3.new(me.X, m:GetPivot().Position.Y, me.Z)))
	local head = m:FindFirstChild("Head") :: BasePart?
	if head then
		local bb = Theme.new("BillboardGui", {
			Name = "DrillWarning",
			Size = UDim2.fromOffset(52, 52),
			StudsOffsetWorldSpace = Vector3.new(0, 6.6, 0), -- over the name tag and the %
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 250,
		}, nil)
		local disc = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.9),
			BackgroundColor3 = T.joyRed,
		}, bb)
		Theme.round(disc)
		Theme.stroke(disc, T.paper, 3)
		Theme.textStroke(
			Theme.text(disc, 34, {
				Size = UDim2.fromScale(1, 1),
				Text = "!",
				TextColor3 = T.paper,
				FontFace = Theme.DisplayFace,
			}),
			2
		)
		local scale = Theme.new("UIScale", { Scale = 0.3 }, disc)
		Theme.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		bb.Adornee = head
		bb.Parent = head
		table.insert(telegraph, bb)
	end
	local hand = (m:FindFirstChild("RightHand") or m:FindFirstChild("Right Arm")) :: BasePart?
	local def = BallDefinitions.get(BALL_TYPE)
	local glow = Theme.new("Part", {
		Name = "DrillGlow",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * ProjectileMath.radius(BALL_TYPE) * 2,
		Color = def.Color,
		Material = Enum.Material.Neon,
		Anchored = not hand,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = false,
		CFrame = if hand then hand.CFrame * CFrame.new(0, -0.8, 0) else CFrame.new(at + Vector3.new(1.5, 2, 0)),
	}, nil)
	Theme.new("PointLight", { Color = T.joyRed, Range = 10, Brightness = 2.5 }, glow)
	if hand then
		Theme.new("WeldConstraint", { Part0 = hand, Part1 = glow }, glow)
	end
	glow.Parent = m
	table.insert(telegraph, glow)
	SoundController.play("PowerUp", at)
end

-- Throw from the dummy's hand at where you are now: a flat arc that crosses the ground at the
-- drill speed and arrives at your middle.
local function launch(m: Model, root: BasePart, me: Vector3)
	local glow = m:FindFirstChild("DrillGlow") :: BasePart?
	local origin = if glow then glow.Position else root.Position + Vector3.new(0, 2, 0)
	clearTelegraph()
	local speed = if misses >= D.SlowAfter then D.SlowSpeed else D.Speed
	local flat = Vector3.new(me.X - origin.X, 0, me.Z - origin.Z)
	local time = math.max(flat.Magnitude / speed, 0.2)
	local g = ProjectileMath.gravity(BALL_TYPE)
	local vy = (me.Y - origin.Y + 0.5 * g * time * time) / time
	local vel = flat.Unit * speed + Vector3.new(0, vy, 0)
	local def = BallDefinitions.get(BALL_TYPE)
	local p = Theme.new("Part", {
		Name = "DrillBall",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * ProjectileMath.radius(BALL_TYPE) * 2,
		Color = def.Color,
		Material = def.Material,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		CFrame = CFrame.new(origin),
	}, nil)
	p:SetAttribute("BallType", BALL_TYPE) -- HalloweenController's pumpkin, as on any Standard ball
	-- the streak every thrown ball has (BallVisualController.makePart)
	local a0 = Theme.new("Attachment", { Position = Vector3.new(0, 0.4, 0) }, p)
	local a1 = Theme.new("Attachment", { Position = Vector3.new(0, -0.4, 0) }, p)
	Theme.new("Trail", {
		Name = "SpeedStreak",
		Attachment0 = a0,
		Attachment1 = a1,
		Lifetime = 0.18,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0.35, 1),
		WidthScale = NumberSequence.new(1, 0.2),
		LightEmission = 0.6,
	}, p)
	p.Parent = m.Parent
	shot = { part = p, pos = origin, vel = vel, origin = origin, t = 0, near = false }
	SoundController.play("Throw", origin)
end

local function again()
	misses += 1
	phase = "Idle"
	phaseAt = os.clock() + D.Again
end

local function onHit(s: Shot, root: BasePart)
	local character = player.Character
	EffectsController.localImpact({
		kind = "Hit",
		ballType = BALL_TYPE,
		position = s.pos,
		direction = s.vel,
		targetModel = character,
		target = player,
	})
	-- a small knock, not a ragdoll: you own your character's physics, so this is local
	local away = Vector3.new(s.vel.X, 0, s.vel.Z)
	away = if away.Magnitude > 0.1 then away.Unit else -root.CFrame.LookVector
	root.AssemblyLinearVelocity = away * 26 + Vector3.new(0, 18, 0)
	-- the step-2 lesson: your own % goes up when you're hit (the HUD reads this attribute)
	if damageBefore == nil then
		damageBefore = player:GetAttribute("Damage")
		localDamage = tonumber(damageBefore) or 0
	end
	local dmg = ProjectileMath.damageFor(BALL_TYPE, ProjectileMath.flatDistance(s.origin, s.pos))
	localDamage = math.min(localDamage + dmg, Config.Damage.Cap)
	player:SetAttribute("Damage", math.floor(localDamage + 0.5))
	HUDController.hint("See? YOUR % went up!", 1.8)
	Net.request(Net.Actions.Practice, { event = "GotHit" })
	clearShot()
	again()
end

local function onDodged(s: Shot)
	SoundController.play("BallWhoosh", s.pos)
	HUDController.banner("NICE DODGE!", T.leaf, 1.3, "UISuccess")
	Net.request(Net.Actions.Practice, { event = "Dodged" })
	doneSentAt = os.clock()
	clearShot()
	phase = "Done"
end

-- Closest distance from `point` to the segment a → b.
local function segmentDistance(a: Vector3, b: Vector3, point: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 1e-6 then math.clamp((point - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * t - point).Magnitude
end

local function stepShot(s: Shot, root: BasePart, dt: number)
	local g = ProjectileMath.gravity(BALL_TYPE)
	local from = s.pos
	local nextVel = s.vel + Vector3.new(0, -g * dt, 0)
	local to = from + (s.vel + nextVel) * 0.5 * dt
	s.pos, s.vel, s.t = to, nextVel, s.t + dt
	s.part.CFrame = CFrame.new(to)
	local me = root.Position
	local now = os.clock()
	local inDash = dashing or now - lastDodgeAt <= Config.Player.DodgeDuration + 0.1
	local recent = inDash or now - lastDodgeAt <= D.DodgeGrace
	local d = segmentDistance(from, to, me)
	if d <= HIT_RADIUS then
		if not inDash then
			onHit(s, root)
			return
		end
		s.near = true -- mid-dash: it goes through you (see the header)
	end
	if recent then
		local fromD = if dodgeFrom then segmentDistance(from, to, dodgeFrom) else math.huge
		if math.min(d, fromD) <= D.DodgeRadius then
			s.near = true
		end
	end
	-- gone past you (or down / too long in the air): decide
	local passed = (me - to):Dot(Vector3.new(s.vel.X, 0, s.vel.Z)) < -2
	if passed or to.Y < Config.Arena.Origin.Y - 4 or s.t > Config.Ball.MaxFlightTime then
		if s.near then
			onDodged(s)
		else
			clearShot()
			HUDController.hint("Dodge it as it comes!", 1.4)
			again()
		end
	end
end

local function step(dt: number)
	if not running then
		if wantDrill() then
			begin()
		end
		return
	end
	if not wantDrill() then
		stop()
		return
	end
	local root = myRoot()
	-- your dodge: DodgeMotion's velocity on your root, whether predicted or sent by the server
	local isDashing = root ~= nil and root:FindFirstChild("DodgeVelocity") ~= nil
	if isDashing and not dashing and root then
		lastDodgeAt = os.clock()
		dodgeFrom = root.Position
	end
	dashing = isDashing
	local m = PracticeController.dummyModel()
	local dummyRoot = m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if phase == "Done" then
		-- the server moves the step on (stop() then runs); if the Dodged event was dropped (its step
		-- throttle), send it again
		if os.clock() - doneSentAt > 1.5 then
			doneSentAt = os.clock()
			Net.request(Net.Actions.Practice, { event = "Dodged" })
		end
		return
	end
	local s = shot
	if s then
		if root then
			local remaining = dt
			while remaining > 0 and shot == s do
				local h = math.min(remaining, Config.Ball.SimStep)
				stepShot(s, root, h)
				remaining -= h
			end
		end
		return
	end
	if not m or not dummyRoot or not root then
		clearTelegraph()
		phase = "Idle" -- the dummy is respawning: wait for it
		return
	end
	local me = root.Position
	if phase == "Idle" and os.clock() >= phaseAt then
		phase = "Windup"
		phaseAt = os.clock()
		windup(m, dummyRoot, me)
	elseif phase == "Windup" and os.clock() - phaseAt >= D.Windup then
		phase = "Flight"
		launch(m, dummyRoot, me)
	end
end

function TutorialDrillController.start()
	-- Heartbeat, as PracticeController: it keeps running even when the window isn't drawing
	RunService.Heartbeat:Connect(step)
	player.CharacterAdded:Connect(function()
		dashing = false
	end)
end

return TutorialDrillController
