--!strict
-- Fill-in bots (Amendment A2). Simple and beatable; they act only through CombatService's do*
-- functions, so they follow the same rules, projectile pipeline and knockback as players.

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
local profiles: { { name: string, desc: HumanoidDescription } } = {}

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
	local ids = B.Avatars or {}
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
			table.insert(loaded, { name = name, desc = desc })
		else
			warn(("[Bots] couldn't load avatar for user %d"):format(id))
		end
	end
	profiles = loaded
end

function BotService.start()
	task.spawn(loadProfiles)
	task.spawn(function()
		while true do
			task.wait(B.TickInterval)
			if not paused then
				BotService.tick()
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not paused then
			BotService.react()
		end
		BotService.animate()
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
	end
	if track and speed then
		track:AdjustSpeed(speed)
	end
end

function BotService.create(team: string, roster: { any }): any
	local profile = nil
	if #profiles > 0 then
		nameIndex = nameIndex % #profiles + 1
		profile = profiles[nameIndex]
	else
		nameIndex = nameIndex % #B.Names + 1
	end
	local c = S.PlayerStateService.create(if profile then profile.name else B.Names[nameIndex], nil, true, false)
	c.bot = {
		aimUntil = nil,
		nextWanderAt = 0,
		wander = nil,
		reacted = {},
		catchFor = nil,
		difficulty = B.Difficulty,
	}
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
	for _, team in { "Red", "Blue" } do
		local n = 0
		for _, c in roster do
			if c.team == team then
				n += 1
			end
		end
		while n < teamSize and existing < B.MaxPerServer do
			BotService.create(team, roster)
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

local function face(c: any, point: Vector3)
	local root = c.root :: BasePart?
	if not root then
		return
	end
	local pos = root.Position
	local flat = Vector3.new(point.X, pos.Y, point.Z)
	if (flat - pos).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(pos, flat)
	end
end

local function nearestEnemy(c: any): any?
	local best, bestDist = nil, math.huge
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = S.ArenaService.sceneryList()
	for _, o in S.MatchService.roster() do
		if o.team ~= c.team and o.status == "Active" and o.root and o.root.Parent then
			local d = (o.root.Position - c.root.Position).Magnitude
			if d < bestDist then
				-- visible: no scenery between bot and target
				local hit = Workspace:Raycast(
					c.root.Position + Vector3.new(0, 1.5, 0),
					o.root.Position - c.root.Position,
					params
				)
				if not hit then
					best, bestDist = o, d
				end
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

local function wanderPoint(c: any): Vector3
	if c.status == "Jailed" then
		return ArenaLayout.jailCenter(c.team) + Vector3.new(rng:NextNumber(-24, 24), 3, 0)
	end
	return ArenaLayout.randomPointOnHalf(c.team, S.ArenaService.getOvertimeSteps(), B.EdgeAvoid, rng)
end

local function aimDirection(c: any, target: any): Vector3
	local root = c.root :: BasePart
	local ballType = if c.heldBall then c.heldBall.type else "Standard"
	local tp = target.root.Position + target.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.25
	local flatTo = Vector3.new(tp.X - root.Position.X, 0, tp.Z - root.Position.Z)
	local forward = if flatTo.Magnitude > 0.1 then flatTo.Unit else root.CFrame.LookVector
	local origin = root.Position + Vector3.new(0, Config.Ball.SpawnUp, 0) + forward * Config.Ball.SpawnForward
	local hold = if c.chargeStart then now() - c.chargeStart else 0
	local speed = ProjectileMath.throwSpeed(ProjectileMath.chargeFromHold(hold), ballType)
	local g = ProjectileMath.gravity(ballType)
	local dir = (tp - origin).Unit
	for _ = 1, 2 do
		local t = (tp - origin).Magnitude / speed
		dir = (tp + Vector3.new(0, 0.5 * g * t * t, 0) - origin).Unit
	end
	local err = (B.AimErrorDeg :: any)[c.bot.difficulty] or 8
	return ProjectileMath.randomInCone(dir, err, rng)
end

function BotService.tick()
	if not S.MatchService.isRoundLive() then
		return
	end
	local t = now()
	for _, c in S.MatchService.roster() do
		if c.isBot and (c.status == "Active" or c.status == "Jailed") and S.PlayerStateService.isAlive(c) then
			local brain = c.bot
			local humanoid = c.humanoid :: Humanoid
			if c.action == "Ragdolled" then
				brain.aimUntil = nil
				continue
			end
			if c.heldBall then
				if brain.aimUntil == nil then
					brain.aimUntil = t + rng:NextNumber(B.AimDelayMin, B.AimDelayMax)
					S.CombatService.doChargeStart(c)
					humanoid:MoveTo(c.root.Position)
				end
				local target = nearestEnemy(c)
				if target then
					face(c, target.root.Position)
					if t >= brain.aimUntil then
						S.CombatService.doThrow(c, aimDirection(c, target), 0)
						brain.aimUntil = nil
					end
				end
				continue
			end
			brain.aimUntil = nil
			-- walk to the nearest free, safely placed ball
			local bestBall, bestDist = nil, math.huge
			for _, ball in S.BallService.all() do
				if ball.state == "Resting" and ball.context == "Match" then
					local pos = ball.part.Position
					if safeFor(c, pos) and S.CombatService.canPickup(c, ball, pos) then
						local d = (pos - c.root.Position).Magnitude
						if d < bestDist then
							bestBall, bestDist = ball, d
						end
					end
				end
			end
			if bestBall then
				humanoid:MoveTo(bestBall.part.Position)
			else
				if t >= brain.nextWanderAt or not brain.wander then
					brain.wander = wanderPoint(c)
					brain.nextWanderAt = t + rng:NextNumber(B.WanderInterval[1], B.WanderInterval[2])
				end
				humanoid:MoveTo(brain.wander)
			end
		end
	end
end

-- Per-frame reactions to incoming balls: dodge 25%, catch 10% (decided once per throw).
function BotService.react()
	if not S.MatchService.isRoundLive() then
		return
	end
	for _, c in S.MatchService.roster() do
		if c.isBot and c.status == "Active" and c.root and c.action ~= "Ragdolled" then
			local brain = c.bot
			for _, ball in S.BallService.all() do
				if ball.state == "InFlight" and ball.lastTeam ~= c.team then
					local rel = c.root.Position - ball.pos
					local v = ball.vel
					local vv = v:Dot(v)
					if vv > 1 and rel.Magnitude < B.ReactRange then
						local tc = rel:Dot(v) / vv
						local miss = (rel - v * tc).Magnitude
						if tc > 0 and tc < 0.7 and miss < 4 then
							local key = ball.id
								.. ":"
								.. tostring(ball.lastThrower and ball.lastThrower.id)
								.. ":"
								.. math.floor(ball.stateAt * 10)
							if brain.reacted[key] == nil then
								local roll = rng:NextNumber()
								brain.reacted[key] = if roll < B.DodgeChance
									then "Dodge"
									elseif roll < B.DodgeChance + B.CatchChance then "Catch"
									else "None"
								if brain.reacted[key] == "Dodge" then
									local side = Vector3.new(-v.Z, 0, v.X)
									if side.Magnitude > 0.1 then
										side = side.Unit * (if rng:NextNumber() < 0.5 then 1 else -1)
										-- prefer the side that keeps the bot away from the edge
										if not safeFor(c, c.root.Position + side * 8) then
											side = -side
										end
										S.CombatService.doDodge(c, side)
									end
								end
							end
							if brain.reacted[key] == "Catch" and not c.heldBall then
								face(c, ball.pos)
								if tc < 0.15 then
									S.CombatService.doCatch(c)
									brain.reacted[key] = "Done"
								end
							end
						end
					end
				end
			end
			-- forget old decisions
			local n = 0
			for _ in brain.reacted do
				n += 1
			end
			if n > 40 then
				brain.reacted = {}
			end
		end
	end
end

function BotService.animate()
	for _, c in bots() do
		local brain = c.bot
		local humanoid = c.humanoid :: Humanoid?
		if brain and humanoid and brain.anims then
			local state = humanoid:GetState()
			if c.action == "Ragdolled" then
				playAnim(c, "none") -- limp: no animation fights the ragdoll
			elseif state == Enum.HumanoidStateType.Jumping then
				playAnim(c, "jump")
			elseif state == Enum.HumanoidStateType.Freefall then
				playAnim(c, "fall")
			elseif c.root and (c.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 1.5 then
				-- (bots walk with MoveTo, which leaves MoveDirection at zero, so go by actual speed)
				-- walk below jogging pace, run above it, sped up/slowed to match the actual speed
				local speed = (c.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
				if speed < 10 then
					playAnim(c, "walk", math.max(0.4, speed / (WALK_SPEED_REF / 2)))
				else
					playAnim(c, "run", speed / WALK_SPEED_REF)
				end
			else
				playAnim(c, "idle")
			end
		end
	end
end

return BotService
