--!strict
-- Slow-Mo Replay (Rare), played as a time stop: the enemy winds up to throw, ball in hand, and time
-- stops. The world drains to grey and holds still while the winner walks across the court, plucks
-- the ball out of the enemy's frozen hand and smashes it into them point-blank. The ball stays
-- squashed against them, frozen mid-hit, until time starts again and they rocket off the arena.
--
--   0.00-0.70  over the winner's shoulder, long lens: the enemy winds up, ball cocked; a clock ticks
--   0.70       TIME STOP: a ripple sweeps out from the winner and the color drains; dust hangs still
--   0.70-1.00  hold on the frozen shot
--   1.00-1.90  low tracking shot beside the winner as they set off walking
--   1.90-2.60  over the frozen enemy's shoulder (the ball in the foreground): the last strides
--   2.60-3.00  side two-shot: the winner plucks the ball out of their hand
--   3.00-3.35  low behind the winner: the wind-up
--   3.35       the hit, point-blank: the ball squashes flat on them, and stays there
--   3.35-3.90  slow orbit round the frozen impact; the winner folds their arms
--   3.90       TIME RESUMES: the ripple pulls back in, the color floods back, they rocket away
--   3.90-5.00  wide, the winner in the foreground as the enemy sails off the arena
--
-- The halves are 72 studs apart, so the walk is two shots with a cut between them: it keeps a real
-- walking pace and still fits in the finisher's 5 s. Both are local stand-ins (the real ones are
-- hidden, and the server doesn't launch the victim).

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local STOP = 0.7
local WALK_A = 1.0
local WALK_B = 1.9
local PLUCK = 2.6
local WIND = 3.0
local HIT = 3.35
local RESUME = 3.9

local PACE = 14 -- walking speed, studs/s
local REACH = 3 -- how far in front of the enemy the winner stops
local FLY_DIST = 190
local FLY_UP = 70

local BALL_RED = Color3.fromRGB(214, 48, 49)
local WHITE = Color3.new(1, 1, 1)
local FROZEN_TINT = Color3.fromRGB(205, 218, 255)
local RIPPLE = Color3.fromRGB(170, 195, 255)
local DUST = Color3.fromRGB(235, 228, 210)

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function flat(v: Vector3, fallback: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	return if h.Magnitude > 0.1 then h.Unit else fallback
end

-- Where a held ball sits on a hand (the same grip the game uses for a held ball).
local function inHand(hand: BasePart?, fallback: Vector3): CFrame
	return if hand then hand.CFrame * CFrame.new(0, -0.6, -0.4) else CFrame.new(fallback)
end

-- The time-stop ripple: a shimmering sphere sweeping out from (or, reversed, back into) `at`.
local function ripple(ctx: any, at: Vector3, outward: boolean)
	local big, small = Vector3.one * 240, Vector3.one * 2
	local dome = part({
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = RIPPLE,
		Size = if outward then small else big,
		Transparency = if outward then 0 else 0.6,
		Position = at,
	}, ctx.folder)
	local t = if outward then 0.5 else 0.35
	tween(dome, t, {
		Size = if outward then big else small,
		Transparency = if outward then 1 else 0,
	}, if outward then Enum.EasingStyle.Quad else Enum.EasingStyle.Quint)
	task.delay(t + 0.05, function()
		dome:Destroy()
	end)
	ctx.fx.shockwave(at, Vector3.yAxis, RIPPLE, if outward then 40 else 20, t)
end

return {
	Id = "SlowMoReplay",
	Name = "Slow-Mo Replay",
	Duration = 5,
	-- the server leaves the victim standing; the hit and the launch are played on local stand-ins
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local reduced = ctx.reducedMotion
		local rng = Random.new()
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		local hero = ctx.standIn(ctx.killer)
		local puppet = ctx.standIn(ctx.victim)
		local hroot = hero and hero:FindFirstChild("HumanoidRootPart") :: BasePart?
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (killerRoot and victimRoot and hero and puppet and hroot and proot) then
			task.wait(ctx.duration)
			return
		end
		local function phase(tEnd: number, fn: (number) -> ())
			ctx.runFor(math.max(0.01, tEnd - (os.clock() - t0)), function()
				fn(os.clock() - t0)
			end)
		end
		local poseHero: (() -> ())? = nil
		local function heroPose(name: string?, blend: number?)
			if poseHero then
				poseHero()
				poseHero = nil
			end
			if name then
				poseHero = ctx.pose(hero, name, blend)
			end
		end

		-- geometry: the winner faces the victim across the court; `side` is the winner's right
		local up = Vector3.yAxis
		local K = killerRoot.Position
		local V = victimRoot.Position
		local f = flat(V - K, Vector3.zAxis)
		local side = f:Cross(up)
		-- the winner stops just in front of the enemy, a little to the side of their throwing hand
		local stopAt = V - f * REACH - side * 1.1
		local walkDir = flat(stopAt - K, f)
		local face = flat(V - stopAt, f)
		local launchDir = flat(face + (ctx.outward :: Vector3), face)

		hroot.CFrame = CFrame.lookAt(K, K + f)
		proot.CFrame = CFrame.lookAt(V, V - f)
		local heroHand = hero:FindFirstChild("RightHand") :: BasePart?
		local victimHand = puppet:FindFirstChild("RightHand") :: BasePart?

		-- the enemy winds up to throw, the ball cocked behind their head
		ctx.pose(puppet, "WindUp", 0.5)
		local ball =
			part({ Size = Vector3.one * 1.6, Material = Enum.Material.SmoothPlastic, Color = BALL_RED }, ctx.folder)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = ball
		-- who has the ball: it rides on that hand every frame until it's thrown
		local holder: BasePart? = victimHand
		local function carryBall()
			if holder then
				ball.CFrame = inHand(holder, V + up * 2)
			end
		end
		ball.CFrame = inHand(victimHand, V - side * 1.2 + up * 2)

		local idle = FinisherKit.loadTrack(hero, FinisherKit.IdleAnim)
		local walking = FinisherKit.loadTrack(hero, FinisherKit.WalkAnim)
		if idle then
			idle.Looped = true
			idle:Play(0)
		end

		-- dust drifting in the air between them: it hangs still while time is stopped
		local frozen = false
		local motes: { { p: Part, v: Vector3 } } = {}
		for _ = 1, (if reduced then 10 else 26) do
			local along = rng:NextNumber(0.1, 1)
			local at = K:Lerp(V, along) + side * rng:NextNumber(-7, 7) + up * rng:NextNumber(-1, 5)
			local p = part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(0.1, 0.22),
				Material = Enum.Material.Neon,
				Color = DUST,
				Transparency = 0.35,
				Position = at,
			}, ctx.folder)
			table.insert(motes, { p = p, v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.6), 0) })
		end
		local lastT = 0
		local function drift(t: number)
			local dt = t - lastT
			lastT = t
			if frozen then
				return
			end
			for _, m in motes do
				m.p.Position += m.v * dt
			end
		end

		local cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = Lighting
		ctx.folder.Destroying:Connect(function()
			cc:Destroy() -- always cleaned up, even if the finisher errors
		end)

		-- Shot 0: over the winner's shoulder, long lens: the enemy about to throw ----------------------
		ctx.sound("TimeTick")
		local camA0 = K - f * 6 + side * 2.2 + up * 2.4
		local camA1 = K - f * 5.2 + side * 2 + up * 2.2
		cam.FieldOfView = 22
		phase(STOP, function(t: number)
			drift(t)
			carryBall()
			cam.CFrame = CFrame.lookAt(camA0:Lerp(camA1, ctx.ease(t / STOP)), V + up * 1.2)
		end)

		-- TIME STOP -----------------------------------------------------------------------------------
		frozen = true
		ctx.sound("TimeStop")
		ripple(ctx, K + up * 1.5, true)
		ctx.fx.screenFlash(FROZEN_TINT, if reduced then 0.3 else 0.7, 0.3)
		tween(cc, 0.3, { Saturation = -1, Contrast = 0.2, Brightness = -0.04, TintColor = FROZEN_TINT })
		if not reduced then
			tween(cam, 0.35, { FieldOfView = 30 }, Enum.EasingStyle.Back)
		end
		local held = cam.CFrame
		phase(WALK_A, function(t: number)
			drift(t)
			carryBall()
			cam.CFrame = held
		end)

		-- the walk -------------------------------------------------------------------------------------
		if idle then
			idle:Stop(0.15)
		end
		if walking then
			walking.Looped = true
			walking:Play(0.15)
			walking:AdjustSpeed(PACE / 16)
		end
		local nextStep = WALK_A + 0.1
		local function stepSound(t: number, pos: Vector3)
			if t >= nextStep then
				nextStep = t + 0.36
				ctx.sound("TimeStep", pos)
			end
		end

		-- Shot A: low, tracking beside the winner as they set off
		cam.FieldOfView = 50
		phase(WALK_B, function(t: number)
			drift(t)
			carryBall()
			local pos = K + walkDir * PACE * (t - WALK_A)
			hroot.CFrame = CFrame.lookAt(pos, pos + walkDir)
			stepSound(t, pos)
			cam.CFrame = CFrame.lookAt(pos + side * 7.5 + walkDir * 2.5 - up * 0.6, pos + up * 0.4)
		end)

		-- Shot B: over the frozen enemy's shoulder, the ball in the foreground; the last strides
		local lastLeg = PACE * (PLUCK - WALK_B)
		local camB = V + f * 4.5 - side * 1.9 + up * 2.3
		cam.FieldOfView = 45
		phase(PLUCK, function(t: number)
			drift(t)
			carryBall()
			local u = math.min(1, (t - WALK_B) / (PLUCK - WALK_B))
			local pos = stopAt - walkDir * lastLeg * (1 - u)
			hroot.CFrame = CFrame.lookAt(pos, pos + walkDir:Lerp(face, u))
			if u < 0.95 then
				stepSound(t, pos)
			elseif walking and walking.IsPlaying then
				walking:Stop(0.15)
				if idle then
					idle:Play(0.2)
				end
			end
			cam.CFrame = CFrame.lookAt(camB, pos + up * 1.1)
		end)
		if walking then
			walking:Stop(0.1)
		end
		hroot.CFrame = CFrame.lookAt(stopAt, stopAt + face)

		-- Shot C: side two-shot: the winner plucks the ball out of the frozen hand ----------------------
		local mid = (stopAt + V) / 2
		local camC = mid - side * 8 - face * 0.5 + up * 1.4
		cam.FieldOfView = 42
		heroPose("ReachOut", 0.12)
		local grabFrom = ball.CFrame
		local grabbed = false
		phase(WIND, function(t: number)
			drift(t)
			local u = math.clamp((t - PLUCK - 0.1) / 0.22, 0, 1)
			if u < 1 then
				holder = nil
				local e = ctx.ease(u)
				ball.CFrame = grabFrom:Lerp(inHand(heroHand, stopAt + face + up), e)
			else
				if not grabbed then
					grabbed = true
					ctx.sound("Pickup", ball.Position)
				end
				holder = heroHand
				carryBall()
			end
			cam.CFrame = CFrame.lookAt(camC:Lerp(camC + face * 0.6, (t - PLUCK) / (WIND - PLUCK)), mid + up * 1.2)
		end)

		-- Shot D: low behind the winner: the wind-up ---------------------------------------------------
		holder = heroHand
		heroPose("WindUp", 0.15)
		ctx.sound("ParkBatLoad")
		local camD = stopAt - face * 4.2 + side * 2.4 - up * 0.4
		cam.FieldOfView = 55
		phase(HIT, function(t: number)
			drift(t)
			carryBall()
			local u = (t - WIND) / (HIT - WIND)
			cam.CFrame = CFrame.lookAt(camD - face * 0.5 * u, V + up * 1)
		end)

		-- the hit, point-blank: the ball squashes flat on them and freezes there -------------------------
		holder = nil
		heroPose("ThrowFollow", 0.05)
		local impact = V + up * 0.8 - face * 0.95
		local throwFrom = ball.Position
		ctx.runFor(0.06, function(alpha: number)
			ball.CFrame = CFrame.new(throwFrom:Lerp(impact, alpha))
		end)
		ball.CFrame = CFrame.lookAt(impact, impact + face)
		mesh.Scale = Vector3.new(1.45, 1.45, 0.45)
		ctx.sound("HitHeavy", impact)
		ctx.sound("ParkSmack")
		ctx.fx.flash(impact, WHITE, 4)
		ctx.fx.screenFlash(WHITE, if reduced then 0.25 else 0.8, 0.12)
		ctx.fx.shake(0.5)
		-- the blow's shock, stopped in time: rings and speed lines hanging around the hit
		local frozenFx: { Part } = {}
		for i, r in { 2.6, 4.2 } do
			table.insert(
				frozenFx,
				part({
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.08, r, r),
					Material = Enum.Material.Neon,
					Color = WHITE,
					Transparency = 0.25 + i * 0.15,
					CFrame = CFrame.lookAt(impact - face * 0.2 * i, impact + face) * CFrame.Angles(0, math.rad(90), 0),
				}, ctx.folder)
			)
		end
		for i = 1, (if reduced then 5 else 10) do
			local a = (i / (if reduced then 5 else 10)) * math.pi * 2
			local dir = (side * math.cos(a) + up * math.sin(a)).Unit
			local len = rng:NextNumber(1.2, 2.4)
			table.insert(
				frozenFx,
				part({
					Size = Vector3.new(0.07, 0.07, len),
					Material = Enum.Material.Neon,
					Color = WHITE,
					CFrame = CFrame.lookAt(impact + dir * (1.4 + len / 2), impact + dir * 5),
				}, ctx.folder)
			)
		end
		-- Shot E: a slow orbit round the frozen impact; the winner folds their arms
		local orbitFrom = math.atan2(-side.Z, -side.X)
		local folded = false
		cam.FieldOfView = 48
		phase(RESUME, function(t: number)
			drift(t)
			local u = (t - HIT) / (RESUME - HIT)
			if not folded and t >= HIT + 0.22 then
				folded = true
				heroPose("CrossArms", 0.25)
			end
			local a = orbitFrom + (if reduced then 0.25 else 0.7) * u
			local camPos = impact + Vector3.new(math.cos(a), 0, math.sin(a)) * 7.5 - face * 1.5 + up * 1.4
			cam.CFrame = CFrame.lookAt(camPos, (impact + stopAt) / 2 + up * 0.6)
		end)

		-- TIME RESUMES: the stored blow lands all at once ------------------------------------------------
		frozen = false
		ctx.sound("TimeResume")
		ctx.sound("HitHeavy", impact)
		ctx.sound("ParkLaunch")
		ripple(ctx, stopAt + up * 1.5, false)
		tween(cc, 0.2, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE })
		ctx.fx.shockwave(impact, face, WHITE, 12, 0.3)
		ctx.fx.burst(impact, WHITE, if reduced then 6 else 18, 28, 0.7)
		ctx.fx.shake(0.6)
		for _, p in frozenFx do
			tween(p, 0.25, { Transparency = 1, Size = p.Size * 1.8 })
		end
		-- the ball pops back to round and bounces away
		mesh.Scale = Vector3.one
		local ballFrom = ball.Position
		local ballVel = -face * 14 + up * 18 + side * rng:NextNumber(-4, 4)
		do
			-- a white streak behind them as they fly
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 1, 0)
			a0.Parent = proot
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -1, 0)
			a1.Parent = proot
			local tr = Instance.new("Trail")
			tr.Attachment0 = a0
			tr.Attachment1 = a1
			tr.Lifetime = 0.6
			tr.LightEmission = 1
			tr.FaceCamera = true
			tr.Transparency = NumberSequence.new(0, 1)
			tr.Parent = proot
		end
		local launchFrom = proot.Position
		local function flyPos(u: number): Vector3
			local e = 1 - (1 - u) ^ 2.2
			return launchFrom + launchDir * FLY_DIST * e + up * FLY_UP * e
		end
		-- Shot F: wide, from behind the winner (arms folded, in the foreground) as the enemy sails off
		local camF = stopAt - face * 7 - side * 3.2 + up * 2.6
		cam.FieldOfView = 60
		local flailAt = 0
		local flailArms = false
		local flyTime = ctx.duration - RESUME
		phase(ctx.duration - 0.05, function(t: number)
			drift(t)
			local s = t - RESUME
			local u = math.min(1, s / flyTime)
			local pos = flyPos(u)
			proot.CFrame = CFrame.lookAt(pos, pos - launchDir) * CFrame.Angles(u * 14, u * 6, u * 9)
			ball.Position = ballFrom + ballVel * s + Vector3.new(0, -35, 0) * s * s
			if t >= flailAt then
				flailAt = t + 0.13
				flailArms = not flailArms
				ctx.pose(puppet, if flailArms then "ArmsUp" else "ArmsSpread", 0.08)
			end
			local pull = ctx.ease(math.min(1, s / 0.35))
			cam.CFrame = CFrame.lookAt(camF:Lerp(camF - face * 3 + up * 1.5, pull), pos:Lerp(stopAt + up, 0.25))
		end)
	end,
}
