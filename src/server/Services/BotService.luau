--!strict
-- Fill-in bots (Amendment A2). They act only through CombatService's do* functions, so they follow
-- the same rules, projectile pipeline and knockback as players. Each bot has a difficulty profile
-- (Config.Bots.Profiles): it picks targets (edge-standers, players who just got up), times its
-- charge and release, sidesteps while aiming, dodges after a human-ish reaction time (bots never
-- catch), shares balls with teammates and backs away from edges. Every profile misses and
-- mistimes, so bots stay beatable, and a held ball is always thrown within
-- StallThrow seconds so a round can never stall on a bot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local ProjectileMath = require(Shared.ProjectileMath)

local BotService = {}

local S: any
local B = Config.Bots
local rng = Random.new()
local paused = true
local nameIndex = 0
-- fetched once at startup from Config.Bots.Avatars: { name, desc } per user, in list order
local profiles: { { id: number, name: string, desc: HumanoidDescription } } = {}

-- Roblox's default R15 animation pack, for avatars without their own
local DEFAULT_ANIMS: { [string]: string } = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}
local WALK_SPEED_REF = 16 -- the speed the run animation is authored for

local function now(): number
	return Workspace:GetServerTimeNow()
end

function BotService.init(services: any)
	S = services
end

-- Fetch the bot avatars' display names and HumanoidDescriptions (web calls, so off the main path).
-- A user that fails to load is skipped; with none loaded, bots keep the gray default look.
local function loadProfiles()
	local ids: { number } = B.Avatars or {}
	if #ids == 0 then
		return
	end
	local names: { [number]: string } = {}
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(ids)
	end)
	if ok and infos then
		for _, info in infos do
			names[info.Id] = if info.DisplayName ~= "" then info.DisplayName else info.Username
		end
	end
	local loaded = {}
	for _, id in ids do
		local okDesc, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(id)
		end)
		local name: string? = names[id]
		if not name then
			local okName, username = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			name = if okName then username else nil
		end
		if okDesc and desc and name then
			table.insert(loaded, { id = id, name = name, desc = desc })
		else
			warn(("[Bots] couldn't load avatar for user %d"):format(id))
		end
	end
	profiles = loaded
end

function BotService.start()
	task.spawn(loadProfiles)
	RunService.Heartbeat:Connect(function(dt)
		if not paused then
			BotService.tick()
			BotService.react()
		end
		BotService.animate(dt)
	end)
end

function BotService.setPaused(v: boolean)
	paused = v
end

local function bots(): { any }
	local list = {}
	for _, c in S.PlayerStateService.all() do
		if c.isBot then
			table.insert(list, c)
		end
	end
	return list
end

local function setupAnimation(c: any)
	local humanoid = c.humanoid :: Humanoid?
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local function load(id: string): AnimationTrack?
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		return if ok then track else nil
	end
	-- the avatar's own pack where it has one (read off its Animate script), else Roblox's default
	local ids: { [string]: string } = c.animIds or {}
	local tracks: { [string]: AnimationTrack } = {}
	for key, default in DEFAULT_ANIMS do
		local track = load(ids[key] or default) or (if ids[key] then load(default) else nil)
		if track then
			track.Looped = key ~= "jump"
			track.Priority = if key == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			tracks[key] = track
		end
	end
	c.bot.anims = tracks
	c.bot.playing = nil
end

-- Cross-fade a bot to one movement animation (idle / run / jump / fall).
local function playAnim(c: any, key: string, speed: number?)
	local brain = c.bot
	local tracks = brain.anims
	if not tracks then
		return
	end
	local track = tracks[key]
	if brain.playing ~= key then
		for k, t in tracks do
			if k ~= key and t.IsPlaying then
				t:Stop(0.2)
			end
		end
		if track then
			track:Play(0.2)
		end
		brain.playing = key
		brain.trackSpeed = nil
	end
	-- only push a new speed when it has really changed (it is replicated to every client)
	if track and speed and math.abs((brain.trackSpeed or -1) - speed) > 0.03 then
		brain.trackSpeed = speed
		track:AdjustSpeed(speed)
	end
end

function BotService.create(team: string, roster: { any }, difficulty: string?): any
	local profile = nil
	if #profiles > 0 then
		nameIndex = nameIndex % #profiles + 1
		profile = profiles[nameIndex]
	else
		nameIndex = nameIndex % #B.Names + 1
	end
	local c = S.PlayerStateService.create(if profile then profile.name else B.Names[nameIndex], nil, true, false)
	local level = difficulty or "Easy"
	c.bot = {
		plan = nil, -- the current throw plan while holding a ball
		claim = nil, -- id of the ball this bot is going for
		thrownAt = nil, -- when it last threw (it waits PickupAfterThrow before chasing a ball)
		nextWanderAt = 0,
		wander = nil,
		nextThinkAt = 0, -- next decision step (see tick)
		reacted = {}, -- launchSeq -> this bot's decision about that throw
		difficulty = level,
		profile = B.Profiles[level] or B.Profiles.Easy,
	}
	c.avatarUserId = if profile then profile.id else nil -- for the scoreboard headshot
	S.PlayerStateService.setTeam(c, team)
	local spawn = ArenaLayout.spawnPoints(team, 1)[1]
	local desc: HumanoidDescription
	if profile then
		-- a real avatar (CharacterService normalizes its scale so hitboxes stay fair)
		desc = profile.desc:Clone()
	else
		-- fallback: neutral light gray so the team band reads clearly
		desc = Instance.new("HumanoidDescription")
		local gray = Color3.fromRGB(190, 190, 195)
		desc.HeadColor = gray
		desc.TorsoColor = gray
		desc.LeftArmColor = gray
		desc.RightArmColor = gray
		desc.LeftLegColor = gray
		desc.RightLegColor = gray
	end
	S.CharacterService.spawn(c, desc, CFrame.new(spawn))
	if c.character then
		c.character:SetAttribute("BotDifficulty", level) -- shown in the F8 debug overlay
	end
	setupAnimation(c)
	c.inMatch = true
	table.insert(roster, c)
	S.CharacterService.setTeamVisual(c)
	return c
end

function BotService.fill(roster: { any }, teamSize: number)
	if not B.Enabled then
		return
	end
	local existing = #bots()
	-- bot difficulty follows the real players' average level
	local levels, count = 0, 0
	for _, c in roster do
		if c.player and c.profile then
			levels += c.profile.Level
			count += 1
		end
	end
	local avgLevel = if count > 0 then levels / count else 1
	for _, team in { "Red", "Blue" } do
		local n = 0
		for _, c in roster do
			if c.team == team then
				n += 1
			end
		end
		while n < teamSize and existing < B.MaxPerServer do
			BotService.create(team, roster, BotService.pickDifficulty(avgLevel))
			n += 1
			existing += 1
		end
	end
end

function BotService.botOnTeam(roster: { any }, team: string): any?
	for _, c in roster do
		if c.isBot and c.team == team then
			return c
		end
	end
	return nil
end

function BotService.remove(roster: { any }, c: any)
	local idx = table.find(roster, c)
	if idx then
		table.remove(roster, idx)
	end
	if c.heldBall then
		S.BallService.drop(c)
	end
	if c.character then
		c.character:Destroy()
	end
	S.PlayerStateService.remove(c)
end

function BotService.clear()
	for _, c in bots() do
		BotService.remove(S.MatchService.roster(), c)
	end
end

-- Facing is a physics constraint, not CFrame writes: snapping the root every decision tick fought
-- the Humanoid's AutoRotate (which turns toward the walk direction) and made strafing bots shake.
-- While a bot faces something, AutoRotate is off and an AlignOrientation turns it smoothly; the
-- Heartbeat keeps the goal on the target's live position between decision ticks.
local FACE_HOLD = 0.35 -- seconds a face() call keeps steering after the last request
local FACE_RESPONSIVENESS = 45

local function facer(c: any): AlignOrientation?
	local root = c.root :: BasePart?
	if not root or not root.Parent then
		return nil
	end
	local brain = c.bot
	local ao = brain.align :: AlignOrientation?
	if ao and ao.Parent == root then
		return ao
	end
	local att = Instance.new("Attachment")
	att.Name = "BotFaceAttachment"
	att.Parent = root
	local new = Instance.new("AlignOrientation")
	new.Name = "BotFace"
	new.Mode = Enum.OrientationAlignmentMode.OneAttachment
	new.Attachment0 = att
	new.Responsiveness = FACE_RESPONSIVENESS
	new.MaxTorque = 1e7
	new.RigidityEnabled = false
	new.Enabled = false
	new.CFrame = root.CFrame.Rotation
	new.Parent = root
	brain.align = new
	return new
end

local function setFaceGoal(c: any, ao: AlignOrientation, point: Vector3)
	local pos = (c.root :: BasePart).Position
	local flat = Vector3.new(point.X - pos.X, 0, point.Z - pos.Z)
	if flat.Magnitude > 0.1 then
		ao.CFrame = CFrame.lookAt(Vector3.zero, flat)
	end
end

-- Turn toward `point` (or `target`'s live position) for the next FACE_HOLD seconds.
local function face(c: any, point: Vector3, target: any?)
	local ao = facer(c)
	if not ao then
		return
	end
	local brain = c.bot
	brain.facePoint = point
	brain.faceTarget = target
	brain.faceUntil = now() + FACE_HOLD
	setFaceGoal(c, ao, point)
	if not ao.Enabled then
		ao.Enabled = true
	end
	if not brain.facing then
		brain.facing = true
		if c.humanoid then
			c.humanoid.AutoRotate = false
		end
	end
end

-- Per-frame facing upkeep: follow the target, release after FACE_HOLD, never fight a ragdoll.
local function updateFacing(c: any, t: number)
	local brain = c.bot
	local ao = brain.align :: AlignOrientation?
	if not ao or not brain.facing then
		return
	end
	local root = c.root :: BasePart?
	if not root or ao.Parent ~= root or c.action == "Ragdolled" or t > (brain.faceUntil or 0) then
		ao.Enabled = false
		brain.facing = false
		brain.faceTarget = nil
		if c.humanoid then
			c.humanoid.AutoRotate = true
		end
		return
	end
	local target = brain.faceTarget
	local troot = target and target.root :: BasePart?
	if troot and troot.Parent then
		brain.facePoint = troot.Position
	end
	setFaceGoal(c, ao, brain.facePoint)
end

local function profileOf(c: any): any
	return c.bot.profile or B.Profiles.Easy
end

local function between(range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

-- Pick a difficulty for a new bot from the mix row that fits the real players' average level.
function BotService.pickDifficulty(avgLevel: number): string
	local rows = (B.Mix :: any) :: { { MaxLevel: number, Weights: { [string]: number } } }
	local weights = rows[#rows].Weights
	for _, r in rows do
		if avgLevel <= r.MaxLevel then
			weights = r.Weights
			break
		end
	end
	local total = 0
	local names: { string } = {}
	for name, w in weights do
		total += w
		table.insert(names, name)
	end
	table.sort(names) -- deterministic order for the weighted pick
	local roll = rng:NextNumber() * total
	for _, name in names do
		roll -= weights[name]
		if roll <= 0 then
			return name
		end
	end
	return names[#names]
end

-- How far a court position is from the nearest edge it could fall off (sides and its back line).
local function edgeDistance(team: string, pos: Vector3): number
	local rel = pos - Config.Arena.Origin
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps())
	local depth = rel.Z * ArenaLayout.teamSign(team)
	return math.min(hw - math.abs(rel.X), ArenaLayout.HalfLength - depth)
end
BotService.edgeDistance = edgeDistance

-- One shared params object; its filter is only re-marshalled when the court scenery folder changes.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include
local sightScenery: Instance? = nil

local function visible(from: Vector3, to: Vector3): boolean
	local scenery = S.ArenaService.sceneryList("Match")[1]
	if scenery ~= sightScenery then
		sightScenery = scenery
		sightParams.FilterDescendantsInstances = if scenery then { scenery } else {}
	end
	return Workspace:Raycast(from + Vector3.new(0, 1.5, 0), to - from, sightParams) == nil
end

-- Lower is better. Smart picks favour enemies near an edge (a hit can knock them off), enemies who
-- just got up, and avoid empty-handed players facing us (they might catch it; bots never do).
function BotService.targetScore(c: any, o: any, smart: boolean): number
	local d = (o.root.Position - c.root.Position).Magnitude
	if not smart then
		return d
	end
	local score = d
	local edge = edgeDistance(o.team, o.root.Position)
	score -= B.TargetEdgeBonus * math.clamp(1 - edge / B.EdgeBonusRange, 0, 1)
	if o.recoveredAt and now() - o.recoveredAt < 1.5 then
		score -= B.TargetGotUpBonus
	end
	if not o.heldBall and not o.isBot then
		local toUs = c.root.Position - o.root.Position
		local look = o.root.CFrame.LookVector
		if toUs.Magnitude > 0.1 and look:Dot(toUs.Unit) > 0.6 then
			score += B.TargetCatchPenalty
		end
	end
	return score
end

-- Best enemy to throw at: active, hittable (not immune), and in sight unless `anySight`.
function BotService.pickTarget(c: any, smart: boolean, anySight: boolean?): any?
	local best, bestScore = nil, math.huge
	local t = now()
	for _, o in S.MatchService.roster() do
		if
			o.team ~= c.team
			and o.status == "Active"
			and o.root
			and o.root.Parent
			and t >= o.immuneUntil
			and (anySight or visible(c.root.Position, o.root.Position))
		then
			local score = BotService.targetScore(c, o, smart)
			if score < bestScore then
				best, bestScore = o, score
			end
		end
	end
	return best
end

-- Inside the bot's safe zone: away from void edges (never deliberately within VoidAvoid).
local function safeFor(c: any, pos: Vector3): boolean
	if c.status == "Jailed" then
		return ArenaLayout.inJail(c.team, pos)
	end
	local rel = pos - Config.Arena.Origin
	local sign = ArenaLayout.teamSign(c.team)
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps())
	local z = rel.Z * sign
	return math.abs(rel.X) <= hw - B.VoidAvoid and z >= 0.5 and z <= ArenaLayout.HalfLength - B.VoidAvoid
end
BotService.safeFor = safeFor

local function wanderPoint(c: any): Vector3
	if c.status == "Jailed" then
		return ArenaLayout.jailCenter(c.team) + Vector3.new(rng:NextNumber(-24, 24), 3, 0)
	end
	return ArenaLayout.randomPointOnHalf(c.team, S.ArenaService.getOvertimeSteps(), B.EdgeAvoid, rng)
end

-- A point a few studs further from the edges than `pos` (toward the middle of the bot's half).
local function inward(c: any, pos: Vector3): Vector3
	local center = ArenaLayout.halfCenter(c.team)
	local dir = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
	return if dir.Magnitude > 0.1 then pos + dir.Unit * 8 else center
end

-- Walk speed while strafing (nil = normal). A frozen humanoid (WalkSpeed 0 in the countdown) is
-- left alone so this never unfreezes anyone.
local function setStrafePace(c: any, pace: number?)
	local humanoid = c.humanoid :: Humanoid?
	if not humanoid or humanoid.WalkSpeed <= 0 then
		return
	end
	local want = pace or Config.Player.WalkSpeed
	if humanoid.WalkSpeed ~= want then
		humanoid.WalkSpeed = want
	end
end

local function aimDirection(c: any, target: any, chargeHold: number): Vector3
	local root = c.root :: BasePart
	local ballType = if c.heldBall then c.heldBall.type else "Standard"
	local tp = target.root.Position + target.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.25
	local flatTo = Vector3.new(tp.X - root.Position.X, 0, tp.Z - root.Position.Z)
	local forward = if flatTo.Magnitude > 0.1 then flatTo.Unit else root.CFrame.LookVector
	local origin = root.Position + Vector3.new(0, Config.Ball.SpawnUp, 0) + forward * Config.Ball.SpawnForward
	local speed = ProjectileMath.throwSpeed(ProjectileMath.chargeFromHold(chargeHold), ballType)
	local g = ProjectileMath.gravity(ballType)
	local dir = (tp - origin).Unit
	for _ = 1, 2 do
		local t = (tp - origin).Magnitude / speed
		dir = (tp + Vector3.new(0, 0.5 * g * t * t, 0) - origin).Unit
	end
	return ProjectileMath.randomInCone(dir, profileOf(c).AimErrorDeg, rng)
end

-- Holding a ball: pick a target, aim (strafing a little), charge for a chosen time, release.
-- A bot never sits on a ball: with no clear shot it throws at the nearest enemy after StallThrow.
local function thinkHolding(c: any, t: number)
	local brain = c.bot
	local prof = profileOf(c)
	local humanoid = c.humanoid :: Humanoid
	if not brain.plan then
		local haste = if S.MatchService.isOvertime() then 1 - B.SuddenDeathHaste else 1
		local quick = rng:NextNumber() < prof.QuickThrowChance
		local aim = if quick then rng:NextNumber(0.15, 0.3) else between(prof.AimDelay) * haste
		local hold = math.min(between(prof.ChargeHold), aim)
		brain.plan = {
			heldAt = t,
			releaseAt = t + aim,
			chargeAt = t + aim - hold,
			hold = hold,
			strafeDir = if rng:NextNumber() < 0.5 then 1 else -1,
			target = nil,
			retargetAt = 0,
		}
	end
	local plan = brain.plan
	if t >= plan.retargetAt or not (plan.target and plan.target.status == "Active") then
		plan.retargetAt = t + 0.4
		plan.target = BotService.pickTarget(c, rng:NextNumber() < prof.TargetSmarts, false)
	end
	local stalled = t - plan.heldAt > B.StallThrow
	local target = plan.target or (if stalled then BotService.pickTarget(c, false, true) else nil)
	if not target then
		setStrafePace(c, nil)
		-- nobody in sight: drift toward the middle of our half for a better angle
		humanoid:MoveTo(
			if c.status == "Jailed" then wanderPoint(c) else ArenaLayout.halfCenter(c.team) + Vector3.new(0, 3, 0)
		)
		return
	end
	face(c, target.root.Position, target)
	-- sidestep while aiming (never toward an edge). The bot used to MoveTo a point 4 × Strafe studs
	-- aside every tick, which it reached (and stopped at) long before the next tick: a stop-go
	-- shuffle. Now it walks continuously at the same average pace toward a goal it can't reach
	-- before the next decision.
	if c.status == "Active" and prof.Strafe > 0 then
		local to = target.root.Position - c.root.Position
		local side = Vector3.new(-to.Z, 0, to.X)
		side = if side.Magnitude > 0.1 then side.Unit * plan.strafeDir else Vector3.zero
		local pace = math.min(Config.Player.WalkSpeed, 4 * prof.Strafe / B.TickInterval)
		local reach = pace * B.TickInterval * 2 + 1
		local probe = 4 * prof.Strafe
		if not safeFor(c, c.root.Position + side * probe) then
			plan.strafeDir = -plan.strafeDir
			side = -side
		end
		if safeFor(c, c.root.Position + side * probe) then
			setStrafePace(c, pace)
			humanoid:MoveTo(c.root.Position + side * reach)
		else
			setStrafePace(c, nil)
			humanoid:MoveTo(inward(c, c.root.Position))
		end
	else
		humanoid:MoveTo(c.root.Position)
	end
	if t >= plan.chargeAt and c.action == "Idle" and not c.chargeStart then
		S.CombatService.doChargeStart(c)
	end
	if t >= plan.releaseAt or stalled then
		local hold = if c.chargeStart then now() - c.chargeStart else 0
		S.CombatService.doThrow(c, aimDirection(c, target, hold), 0)
		brain.plan = nil
		brain.thrownAt = t
		setStrafePace(c, nil)
	end
end

-- Empty-handed: back off a dangerous edge first, then go for a ball nobody else is chasing,
-- otherwise wander the safe middle of the half.
local claims: { [number]: any } = {} -- ball id -> the bot chasing it

-- Does this bot's team have no real players? Only then may it go for power balls, so it never
-- takes the special ball from a human teammate.
local function allBotTeam(c: any): boolean
	for _, o in S.MatchService.roster() do
		if o.team == c.team and not o.isBot then
			return false
		end
	end
	return true
end

local function thinkFree(c: any, t: number)
	local brain = c.bot
	local prof = profileOf(c)
	local humanoid = c.humanoid :: Humanoid
	if c.status == "Active" and edgeDistance(c.team, c.root.Position) < math.min(prof.EdgeCaution, B.VoidAvoid + 3) then
		humanoid:MoveTo(inward(c, c.root.Position))
		return
	end
	local jailed = c.status == "Jailed"
	local allowPower = allBotTeam(c)
	local resting = brain.thrownAt ~= nil and t - brain.thrownAt < B.PickupAfterThrow
	-- in jail, a ball must have been in reach for JailPickupDelay before the bot goes for it (gives
	-- jailed players first go); rebuilt every tick so balls that leave are forgotten
	local seen = brain.jailSeen or {}
	local nextSeen = if jailed then {} else nil
	local bestBall, bestDist = nil, math.huge
	for _, ball in S.BallService.all() do
		if
			not resting
			and (ball.state == "Resting" or ball.state == "Spent")
			and ball.context == "Match"
			and (allowPower or not (ball.isPower or ball.type ~= "Standard"))
		then
			local pos = ball.part.Position
			local waiting = false
			if nextSeen and safeFor(c, pos) then
				local first = seen[ball.id] or t
				nextSeen[ball.id] = first
				waiting = t - first < B.JailPickupDelay
			end
			if not waiting and safeFor(c, pos) and S.CombatService.canPickup(c, ball, pos) then
				local d = (pos - c.root.Position).Magnitude
				-- leave it to a teammate who's already going for it, unless we're much closer
				local other = claims[ball.id]
				if other and other ~= c and other.root and other.bot and other.bot.claim == ball.id then
					local theirs = (pos - other.root.Position).Magnitude
					if theirs <= d + B.ClaimRadius then
						d = math.huge
					end
				end
				if d < bestDist then
					bestBall, bestDist = ball, d
				end
			end
		end
	end
	brain.jailSeen = nextSeen
	if brain.claim and claims[brain.claim] == c and (not bestBall or bestBall.id ~= brain.claim) then
		claims[brain.claim] = nil
	end
	if bestBall then
		brain.claim = bestBall.id
		claims[bestBall.id] = c
		humanoid:MoveTo(bestBall.part.Position)
		return
	end
	brain.claim = nil
	if t >= brain.nextWanderAt or not brain.wander then
		brain.wander = wanderPoint(c)
		brain.nextWanderAt = t + rng:NextNumber(B.WanderInterval[1], B.WanderInterval[2])
	end
	humanoid:MoveTo(brain.wander)
end

-- One decision step for one bot (also used directly by the F9 tests).
function BotService.tickOne(c: any)
	if not (c.isBot and (c.status == "Active" or c.status == "Jailed") and S.PlayerStateService.isAlive(c)) then
		return
	end
	local t = now()
	local brain = c.bot
	-- forget old reaction decisions (counted here rather than every frame in react)
	local n = 0
	for _ in brain.reacted do
		n += 1
	end
	if n > 40 then
		brain.reacted = {}
	end
	if c.action == "Ragdolled" then
		brain.plan = nil
		brain.wasDown = true
		return
	end
	if brain.wasDown then
		brain.wasDown = false
		c.recoveredAt = t
	end
	if c.heldBall then
		thinkHolding(c, t)
	else
		brain.plan = nil
		setStrafePace(c, nil)
		thinkFree(c, t)
	end
end

-- Every bot decides once per TickInterval, each on its own phase: all of them used to think on the
-- same frame (sight raycasts, target picks, MoveTo for every bot at once), a server spike every
-- 0.15 s. A bot that fell behind (paused, round not live) gets a fresh random phase.
function BotService.tick()
	if not S.MatchService.isRoundLive() then
		return
	end
	local t = now()
	for _, c in S.MatchService.roster() do
		local brain = c.isBot and c.bot
		if brain and t >= brain.nextThinkAt then
			if t - brain.nextThinkAt > B.TickInterval then
				brain.nextThinkAt = t + rng:NextNumber(0, B.TickInterval)
			else
				brain.nextThinkAt += B.TickInterval
			end
			BotService.tickOne(c)
		end
	end
end

-- Per-frame reactions to incoming balls. Each throw gets one decision per bot, made after the
-- bot's reaction time: dodge sideways (toward the middle) or do nothing. Bots never catch. A ball
-- that arrives before the bot reacts just hits.
local flying: { any } = {} -- reused every frame: the in-flight balls
function BotService.react()
	if not S.MatchService.isRoundLive() then
		return
	end
	table.clear(flying)
	for _, ball in S.BallService.all() do
		if ball.state == "InFlight" then
			table.insert(flying, ball)
		end
	end
	if #flying == 0 then
		return
	end
	local t = now()
	for _, c in S.MatchService.roster() do
		if c.isBot and c.status == "Active" and c.root and c.action ~= "Ragdolled" then
			local brain = c.bot
			local prof = profileOf(c)
			for _, ball in flying do
				if ball.lastTeam ~= c.team then
					local rel = c.root.Position - ball.pos
					local v = ball.vel
					local vv = v:Dot(v)
					if vv > 1 and rel.Magnitude < B.ReactRange then
						local tc = rel:Dot(v) / vv -- seconds until closest approach
						local miss = (rel - v * tc).Magnitude
						if tc > 0 and tc < 1 and miss < 4.5 then
							-- one number per launch: this used to format a string key per ball, per
							-- bot, every frame
							local r = brain.reacted[ball.launchSeq]
							if r == nil then
								-- first sight of this throw: decide now, act after the reaction time
								local roll = rng:NextNumber()
								r = {
									at = t + between(prof.ReactionTime),
									choice = if roll < prof.DodgeChance then "Dodge" else "None",
								}
								brain.reacted[ball.launchSeq] = r
							end
							if t >= r.at and r.choice == "Dodge" then
								r.choice = "Done"
								local side = Vector3.new(-v.Z, 0, v.X)
								if side.Magnitude > 0.1 then
									side = side.Unit
									-- dodge toward the middle of the half when both sides are safe
									local toMid = ArenaLayout.halfCenter(c.team) - c.root.Position
									if side:Dot(toMid) < 0 then
										side = -side
									end
									if not safeFor(c, c.root.Position + side * 8) then
										side = -side
									end
									if safeFor(c, c.root.Position + side * 8) then
										S.CombatService.doDodge(c, side)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

-- Smoothed locomotion speed per bot (the raw physics speed flickers frame to frame, which made the
-- walk/run tracks speed up and slow down visibly and flip between walk and run near the threshold).
local function smoothSpeed(brain: any, speed: number, dt: number): number
	local prev = brain.animSpeed or speed
	local k = 1 - math.exp(-dt * 12)
	local s = prev + (speed - prev) * k
	brain.animSpeed = s
	return s
end

function BotService.animate(dt: number)
	local t = now()
	for _, c in S.PlayerStateService.all() do
		local brain = c.isBot and c.bot
		local humanoid = c.humanoid :: Humanoid?
		if brain and humanoid then
			updateFacing(c, t)
		end
		if brain and humanoid and brain.anims then
			local state = humanoid:GetState()
			local root = c.root :: BasePart?
			local v = if root then root.AssemblyLinearVelocity else Vector3.zero
			local speed = smoothSpeed(brain, Vector3.new(v.X, 0, v.Z).Magnitude, dt)
			local playing = brain.playing
			-- hysteresis: start moving above 1.5, stop below 0.8; run above 11, walk below 9
			local moving = speed > (if playing == "walk" or playing == "run" then 0.8 else 1.5)
			local running = speed > (if playing == "run" then 9 else 11)
			if c.action == "Ragdolled" then
				playAnim(c, "none") -- limp: no animation fights the ragdoll
			elseif state == Enum.HumanoidStateType.Jumping then
				playAnim(c, "jump")
			elseif state == Enum.HumanoidStateType.Freefall then
				playAnim(c, "fall")
			elseif moving then
				-- (bots walk with MoveTo, which leaves MoveDirection at zero, so go by actual speed)
				-- walk below jogging pace, run above it, sped up/slowed to match the actual speed
				if running then
					playAnim(c, "run", speed / WALK_SPEED_REF)
				else
					playAnim(c, "walk", math.max(0.4, speed / (WALK_SPEED_REF / 2)))
				end
			else
				playAnim(c, "idle")
			end
		end
	end
end

return BotService
