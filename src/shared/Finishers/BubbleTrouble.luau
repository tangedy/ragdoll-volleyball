--!strict
-- Bubble Trouble: the winner pulls out a bubble wand and blows a stream of bubbles across the court.
-- One of them keeps growing as it drifts, swallows the victim whole, and floats them up and off the
-- platform, the victim pounding on the walls, until it pops over the void and drops them.
--
--   0.00-0.70  front three-quarter on the winner: the wand pops into their hand
--   0.70-1.15  profile: they blow, and a stream of bubbles pours out across the frame
--                (reduced motion: stays on the first angle)
--   1.15-2.10  over the winner's shoulder, chasing the one bubble that keeps growing
--   2.10       engulf: it settles over the victim and lifts them off their feet with a wobble
--   2.10-4.30  wide: the bubble rises and drifts off the far edge, the victim struggling inside
--   4.30       pop over the void: a splash of droplets, a beat of cartoon hang time, then the drop
--
-- The victim is a local stand-in (the real one is hidden and the server doesn't launch them).

local BLOW = 0.7
local BIG_SPAWN = 1.15
local ENGULF = 2.1
local POP = 4.3

local BIG_D = 9 -- the big bubble's diameter once it has the victim
local LIFT = 9 -- how far it rises by the time it pops
local PAST_EDGE = 10 -- how far past the court's back edge it pops

local FILM = Color3.fromRGB(190, 235, 255)
local WAND = Color3.fromRGB(255, 95, 162)
local DROP = Color3.fromRGB(205, 240, 255)

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

-- A soap-film pastel that drifts through the rainbow over time (`seed` offsets the hue).
local function sheen(t: number, seed: number): Color3
	return Color3.fromHSV((seed + t * 0.25) % 1, 0.28, 1)
end

-- A small bubble: a shimmering ForceField ball.
local function makeBubble(ctx: any, d: number): Part
	return part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * d,
		Material = Enum.Material.ForceField,
		Color = FILM,
	}, ctx.folder)
end

-- The wand: a pink handle with a ring of beads on top and a soap film across the ring. Returns a
-- function that places it for a frame, given the hand position and the direction to blow.
local function makeWand(ctx: any): (Vector3, Vector3) -> Vector3
	local handle = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 0.2, 0.2),
		Material = Enum.Material.SmoothPlastic,
		Color = WAND,
	}, ctx.folder)
	local film = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, 1.1, 1.1),
		Material = Enum.Material.ForceField,
		Color = FILM,
	}, ctx.folder)
	local beads: { Part } = {}
	local N = 14
	for i = 1, N do
		beads[i] = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.22,
			Material = Enum.Material.SmoothPlastic,
			Color = WAND,
		}, ctx.folder)
	end
	return function(hand: Vector3, dir: Vector3): Vector3
		local ringAt = hand + Vector3.new(0, 1.15, 0) + dir * 0.25
		local ring = CFrame.lookAt(ringAt, ringAt + dir)
		handle.CFrame = CFrame.lookAt(hand:Lerp(ringAt, 0.4), ringAt) * CFrame.Angles(0, math.rad(90), 0)
		film.CFrame = ring * CFrame.Angles(0, math.rad(90), 0)
		for i, b in beads do
			local a = (i / N) * math.pi * 2
			b.CFrame = ring * CFrame.new(math.cos(a) * 0.55, math.sin(a) * 0.55, 0)
		end
		return ringAt
	end
end

return {
	Id = "BubbleTrouble",
	Name = "Bubble Trouble",
	Duration = 5,
	-- the server leaves the victim standing; the bubble carries a local puppet
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local baseFov = cam.FieldOfView
		local rng = Random.new()
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		if not killerRoot or not victimRoot then
			task.wait(ctx.duration)
			return
		end
		local function now(): number
			return os.clock() - t0
		end

		-- geometry: the winner faces the victim across the net
		local K = killerRoot.Position
		local V = victimRoot.Position
		local f = Vector3.new(V.X - K.X, 0, V.Z - K.Z)
		f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
		local side = f:Cross(Vector3.yAxis)
		local G = V - Vector3.new(0, 3, 0) -- court under the victim
		local o = ctx.outward :: Vector3

		local hero = ctx.standIn(ctx.killer) or ctx.killer
		pcall(function()
			hero:PivotTo(CFrame.lookAt(K, K + f))
		end)
		local heroHand = hero:FindFirstChild("RightHand") :: BasePart?
		local puppet = ctx.standIn(ctx.victim)
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		if proot then
			proot.CFrame = CFrame.lookAt(V, V - f)
		end

		-- the wand follows the winner's right hand
		local placeWand = makeWand(ctx)
		local function handPos(): Vector3
			return if heroHand then heroHand.Position else K + f * 1.8 + side * 0.6 + Vector3.new(0, 0.6, 0)
		end
		local ringAt = placeWand(handPos(), f)

		-- the stream of small bubbles: each drifts toward the victim with a wobble, then pops
		local bubbles: { { p: Part, pos: Vector3, vel: Vector3, age: number, life: number, seed: number } } = {}
		local popped = 0
		local function popBubble(i: number)
			local b = bubbles[i]
			popped += 1
			if popped % (if ctx.reducedMotion then 4 else 2) == 0 then
				ctx.fx.burst(b.pos, DROP, 4, 8, 0.25)
			end
			if popped % 3 == 0 then
				ctx.sound("BubblePop", b.pos)
			end
			b.p:Destroy()
			table.remove(bubbles, i)
		end
		local spawnEvery = if ctx.reducedMotion then 0.1 else 0.045
		local nextSpawn = BLOW
		local streamTo = V + Vector3.new(0, 1, 0)
		local function stepBubbles(t: number, dt: number, spawning: boolean)
			if spawning and t >= nextSpawn then
				nextSpawn = t + spawnEvery
				local d = rng:NextNumber(0.4, 1.3)
				local aim = (streamTo + rng:NextUnitVector() * Vector3.new(4, 2.5, 4) - ringAt).Unit
				table.insert(bubbles, {
					p = makeBubble(ctx, d),
					pos = ringAt + aim * 0.4,
					vel = aim * rng:NextNumber(10, 18),
					age = 0,
					life = rng:NextNumber(0.8, 2.2),
					seed = rng:NextNumber(),
				})
			end
			for i = #bubbles, 1, -1 do
				local b = bubbles[i]
				b.age += dt
				-- air drag and a little buoyancy, then a lazy figure-eight wobble on top
				b.vel = b.vel * math.max(0, 1 - dt * 0.9) + Vector3.new(0, 1.2 * dt, 0)
				b.pos += b.vel * dt
				local w = b.seed * 10 + b.age * 5
				local wobble = side * math.sin(w) * 0.25 + Vector3.new(0, math.sin(w * 2) * 0.15, 0)
				b.p.CFrame = CFrame.new(b.pos + wobble)
				b.p.Color = sheen(t, b.seed)
				if b.age >= b.life or (b.pos - streamTo).Magnitude < 1.5 then
					popBubble(i)
				end
			end
		end

		-- Shot 1: the wand pops into the winner's hand ----------------------------------------------
		ctx.pose(hero, "ReachOut", 0.2)
		local camA = K + f * 8 + side * 3 + Vector3.new(0, 1, 0)
		local camB = K + f * 6 + side * 2.2 + Vector3.new(0, 0.7, 0)
		local sparkled = false
		ctx.runFor(BLOW, function(alpha: number)
			ringAt = placeWand(handPos(), f)
			cam.CFrame = CFrame.lookAt(camA:Lerp(camB, ctx.ease(alpha)), K + f * 0.6 + Vector3.new(0, 1.2, 0))
			if not sparkled and alpha > 0.25 then
				sparkled = true
				ctx.fx.burst(ringAt, Color3.new(1, 1, 1), 10, 10, 0.4)
				ctx.sound("BubbleWand", ringAt)
			end
		end)

		-- Shot 2: the blowing, and a cloud of bubbles across the frame --------------------------------
		ctx.sound("BubbleBlow", ringAt)
		local profile = K + side * 9 + f * 3 + Vector3.new(0, 0.8, 0)
		ctx.runFor(BIG_SPAWN - BLOW, function(alpha: number, dt: number)
			ringAt = placeWand(handPos(), f)
			stepBubbles(BLOW + alpha * (BIG_SPAWN - BLOW), dt, true)
			if not ctx.reducedMotion then
				cam.FieldOfView = 70
				cam.CFrame =
					CFrame.lookAt(profile + f * alpha * 1.5, K + f * (3.5 + alpha * 2) + Vector3.new(0, 1.3, 0))
			end
		end)

		-- Shot 3: the one bubble that keeps growing ------------------------------------------------------
		local big = part({
			Size = Vector3.one,
			Material = Enum.Material.ForceField,
			Color = FILM,
		}, ctx.folder)
		local bigMesh = Instance.new("SpecialMesh")
		bigMesh.MeshType = Enum.MeshType.Sphere
		bigMesh.Parent = big
		-- the window highlight, kept on the camera side of the bubble
		local shine = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.2, 0.2, 0.2),
			Material = Enum.Material.Neon,
			Color = Color3.new(1, 1, 1),
			Transparency = 0.35,
		}, ctx.folder)
		local bigLight = Instance.new("PointLight")
		bigLight.Color = FILM
		bigLight.Range = 10
		bigLight.Brightness = 1.2
		bigLight.Parent = big
		local function placeBig(at: Vector3, d: number, t: number, squash: number)
			big.Size = Vector3.one * d
			bigMesh.Scale = Vector3.new(1 + squash, 1 - squash, 1 + squash)
			big.CFrame = CFrame.new(at)
			big.Color = sheen(t, 0.55)
			local toCam = cam.CFrame.Position - at
			toCam = if toCam.Magnitude > 0.1 then toCam.Unit else -f
			local dir = (toCam + Vector3.new(0, 0.55, 0) - cam.CFrame.RightVector * 0.4).Unit
			shine.Size = Vector3.new(d * 0.16, d * 0.1, d * 0.03)
			shine.CFrame = CFrame.lookAt(at + dir * d * 0.46, at + dir * d) * CFrame.Angles(0, 0, math.rad(-35))
		end

		local holdAt = G + Vector3.new(0, BIG_D / 2 + 0.2, 0) -- resting on the court over the victim
		local bigFrom = ringAt + f * 0.6
		local shoulder = K - f * 5 + side * 2.5 + Vector3.new(0, 2.2, 0)
		ctx.pose(hero, "PointForward", 0.25)
		ctx.sound("BubbleGrow", bigFrom)
		local bigAt = bigFrom
		ctx.runFor(ENGULF - BIG_SPAWN, function(alpha: number, dt: number)
			local t = BIG_SPAWN + alpha * (ENGULF - BIG_SPAWN)
			ringAt = placeWand(handPos(), f)
			stepBubbles(t, dt, alpha < 0.6)
			-- glides out quickly, then slows as it settles over the victim, swelling all the way
			local e = 1 - (1 - alpha) ^ 2
			bigAt = bigFrom:Lerp(holdAt, e) + Vector3.new(0, math.sin(alpha * math.pi) * 2.5, 0)
			local d = 0.8 + (BIG_D - 0.8) * alpha ^ 1.6
			placeBig(bigAt, d, t, math.sin(t * 9) * 0.04)
			-- chase it from behind the winner's shoulder
			cam.FieldOfView = 70
			local chase = bigAt - f * (8 + d) + side * 3 + Vector3.new(0, 2.5, 0)
			cam.CFrame = CFrame.lookAt(shoulder:Lerp(chase, ctx.ease(math.min(1, alpha * 1.4))), bigAt:Lerp(V, 0.3))
		end)

		-- Engulf: it closes over the victim and lifts them off their feet with a wobble ---------------
		ctx.sound("BubbleEngulf", holdAt)
		ctx.fx.burst(holdAt, DROP, if ctx.reducedMotion then 6 else 16, 12, 0.35)
		ctx.pose(hero, "CrossArms", 0.3)
		if puppet then
			ctx.pose(puppet, "ArmsSpread", 0.12)
		end
		local engulfT = now()

		-- Drift: up and off the far edge -----------------------------------------------------------------
		local pastEdge = if ctx.toEdge then ctx.toEdge(G, o) + PAST_EDGE else 30
		local popAt = G + o * pastEdge + Vector3.new(0, BIG_D / 2 + LIFT, 0)
		local engulfCam = holdAt + side * 13 - f * 2 + Vector3.new(0, 1, 0)
		local struggle = 0
		local nextStruggle = 0
		ctx.runFor(math.max(0.3, POP - now()), function(_alpha: number, dt: number)
			local t = now()
			local since = t - engulfT
			stepBubbles(t, dt, false)
			-- the first half second stays put while the bubble jiggles closed; then it floats away
			local k = math.clamp((since - 0.45) / math.max(0.3, POP - ENGULF - 0.45), 0, 1)
			local along = ctx.ease(k)
			local rise = math.sqrt(k)
			local at = holdAt:Lerp(Vector3.new(popAt.X, holdAt.Y, popAt.Z), along)
				+ Vector3.new(0, (popAt.Y - holdAt.Y) * rise + math.sin(since * 3) * 0.35, 0)
				+ side * math.sin(since * 1.7) * 0.8 * k
			-- jelly wobble from closing on them, fading out, plus a slow breathing pulse
			local jiggle = if ctx.reducedMotion then 0.04 else 0.16
			local squash = math.sin(since * 22) * jiggle * math.exp(-since * 4) + math.sin(since * 4) * 0.025
			placeBig(at, BIG_D, t, squash)

			-- the victim: lifted to the middle, slowly tumbling, pounding on the film now and then
			if proot then
				local lift = math.min(1, since / 0.35)
				local inside = V:Lerp(at - Vector3.new(0, 0.4, 0), lift)
				local tumble = CFrame.Angles(math.sin(since * 1.3) * 0.5, since * 0.9, math.sin(since * 1.9) * 0.35)
				proot.CFrame = CFrame.lookAt(inside, inside - f) * tumble
			end
			if puppet and since > 0.4 and since >= nextStruggle then
				nextStruggle = since + 0.32
				struggle += 1
				ctx.pose(puppet, if struggle % 2 == 0 then "ArmsUp" else "ArmsSpread", 0.12)
				if struggle % 2 == 0 then
					ctx.sound("BubbleBoing", at)
				end
			end

			-- camera: close on the engulf, then pull wide and follow it out over the void
			cam.FieldOfView = 70
			local wide = at + side * 17 - o * 10 + Vector3.new(0, 3, 0)
			local c = math.clamp((since - 0.3) / 0.9, 0, 1)
			cam.CFrame = CFrame.lookAt(engulfCam:Lerp(wide, ctx.ease(c)), at - Vector3.new(0, 1.5 * c, 0))
		end)

		-- Pop! -----------------------------------------------------------------------------------------
		for i = #bubbles, 1, -1 do
			popBubble(i)
		end
		local burstAt = big.Position
		big:Destroy()
		shine:Destroy()
		ctx.sound("BubbleBigPop", burstAt)
		ctx.fx.burst(burstAt, DROP, if ctx.reducedMotion then 20 else 60, 30, 0.6)
		ctx.fx.shockwave(burstAt, (cam.CFrame.Position - burstAt).Unit, FILM, BIG_D * 2.2, 0.3)
		ctx.fx.flash(burstAt, Color3.new(1, 1, 1), BIG_D)
		ctx.fx.shake(0.25)
		if puppet then
			ctx.pose(puppet, "ArmsUp", 0.08)
		end

		-- a beat of cartoon hang time, then the drop
		local fallFrom = if proot then proot.Position else burstAt
		local fallCF = if proot then proot.CFrame else CFrame.new(burstAt)
		local holdCam = cam.CFrame.Position
		ctx.runFor(math.max(0.2, ctx.duration - now()), function()
			local s = now() - POP
			local fallT = math.max(0, s - 0.18)
			local pos = fallFrom + o * fallT * 4 - Vector3.new(0, 45 * fallT * fallT, 0)
			if proot then
				proot.CFrame = CFrame.new(pos) * fallCF.Rotation * CFrame.Angles(fallT * 6, 0, fallT * 3)
				if s < 0.18 then
					-- the hang: a tiny shiver in mid-air
					proot.CFrame *= CFrame.new(math.sin(s * 120) * 0.05, 0, 0)
				end
			end
			cam.CFrame = CFrame.lookAt(holdCam, burstAt:Lerp(pos, 0.7))
		end)
		cam.FieldOfView = baseFov
	end,
}
