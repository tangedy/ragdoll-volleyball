--!strict
-- Dodgeball Rush: a golden spirit of the winner manifests behind them, rushes the victim and buries
-- them under a nonstop barrage of dodgeballs (the world's palette flips while it lasts), juggling
-- them in mid-air. Dead silence for the wind-up, one colossal golden ball, impact frames, and the
-- victim sails off the court into a giant ball cart whose lid slams shut.
--
--   0.00-0.80  shot 1, over the winner's shoulder: the world freezes, the spirit materializes
--   0.80-3.20  the barrage, three cuts (reduced motion: one steady angle)
--                0.80-1.60  side tracking: victim held up in the air by the sheer volume of balls
--                1.60-2.35  victim's point of view: a wall of balls and trails
--                2.35-3.20  low dutch angle: the victim pinballed higher and higher
--   3.20-3.50  wind-up: silence, the spirit draws back a giant charging golden ball
--   3.50       impact: monochrome impact frames, boom
--   3.50-5.00  the victim arcs off the court and drops into a ball cart; the lid slams shut
--
-- The victim is a local stand-in (the real one is hidden and the server doesn't launch them).

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local MANIFEST = 0.8
local BARRAGE_END = 3.2
local IMPACT = 3.5
local LAND = 4.3
local CUTS = { 1.6, 2.35 } -- barrage camera cuts

local GOLD = Color3.fromRGB(255, 214, 70)
local IVORY = Color3.fromRGB(255, 246, 210)
local BALL_RED = Color3.fromRGB(214, 48, 49)
local VIOLET = Color3.fromRGB(150, 80, 255)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

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

-- Turn a stand-in copy of the winner into a glowing gold-and-ivory spirit.
local function spiritify(ctx: any, model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.Neon
			d.Color = if d.Name == "Head" or d.Name:find("Hand") then IVORY else GOLD
			d.Transparency = 1
			pcall(function()
				(d :: any).TextureID = ""
			end)
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Transparency = 1
		local a = Instance.new("Attachment")
		a.Parent = root
		local e = Instance.new("ParticleEmitter")
		e.Texture = SPARK
		e.Color = ColorSequence.new(GOLD, IVORY)
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.35, 0)
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(1, 3)
		e.Rate = if ctx.reducedMotion then 15 else 50
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 2, 0)
		e.Parent = a
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 16
		light.Brightness = 3
		light.Parent = root
	end
end

local function fadeSpirit(model: Model, to: number, t: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			tween(d, t, { Transparency = to })
		end
	end
end

-- A small dodgeball with a gold streak behind it.
local function makeBall(ctx: any, size: number): Part
	local ball = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		Material = Enum.Material.SmoothPlastic,
		Color = BALL_RED,
	}, ctx.folder)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.4, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.4, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.12
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(IVORY, GOLD)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = ball
	return ball
end

-- The giant ball cart the victim is disposed into: open box of bars, heaped with dodgeballs, and a
-- lid hinged on the far edge (returned so it can slam shut).
local function ballCart(ctx: any, at: Vector3, facing: Vector3, rng: Random): (Part, CFrame, CFrame)
	local W, D, H = 14, 10, 7
	local frame = CFrame.lookAt(at, at + facing)
	local METAL = Color3.fromRGB(70, 75, 85)
	local function bar(size: Vector3, offset: Vector3)
		part(
			{ Size = size, CFrame = frame * CFrame.new(offset), Material = Enum.Material.DiamondPlate, Color = METAL },
			ctx.folder
		)
	end
	bar(Vector3.new(W, 0.6, D), Vector3.new(0, 0.3, 0)) -- floor
	for _, sx in { -1, 1 } do
		bar(Vector3.new(0.5, H, D), Vector3.new(sx * W / 2, H / 2, 0))
	end
	for _, sz in { -1, 1 } do
		bar(Vector3.new(W, H, 0.5), Vector3.new(0, H / 2, sz * D / 2))
	end
	-- wheels
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.8, 2, 2),
				CFrame = frame
					* CFrame.new(sx * (W / 2 - 1.5), 0, sz * (D / 2 + 0.4))
					* CFrame.Angles(0, math.rad(90), 0),
				Color = Color3.fromRGB(25, 25, 28),
			}, ctx.folder)
		end
	end
	-- heaped dodgeballs
	for _ = 1, (if ctx.reducedMotion then 14 else 30) do
		local r = rng:NextNumber(1.6, 2.4)
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * r,
			CFrame = frame * CFrame.new(
				rng:NextNumber(-W / 2 + 1.2, W / 2 - 1.2),
				rng:NextNumber(1, H - 1.5),
				rng:NextNumber(-D / 2 + 1.2, D / 2 - 1.2)
			),
			Color = BALL_RED:Lerp(Color3.fromRGB(255, 120, 60), rng:NextNumber(0, 0.35)),
		}, ctx.folder)
	end
	-- lid: hinged along the far top edge, flipped open (standing up and leaning back)
	local hinge = frame * CFrame.new(0, H, D / 2)
	local closed = hinge * CFrame.new(0, 0, -D / 2)
	local open = hinge * CFrame.Angles(math.rad(-110), 0, 0) * CFrame.new(0, 0, -D / 2)
	local lid = part({
		Size = Vector3.new(W + 0.6, 0.5, D + 0.4),
		CFrame = open,
		Material = Enum.Material.DiamondPlate,
		Color = METAL,
	}, ctx.folder)
	return lid, open, closed
end

-- Monochrome impact frames (the uppercut moment), then snap back to color.
local function impactFrames(ctx: any)
	if ctx.reducedMotion then
		ctx.fx.screenFlash(Color3.new(1, 1, 1), 0.5, 0.3)
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
	task.delay(0.6, function()
		cc:Destroy()
	end)
	ctx.fx.screenFlash(Color3.new(1, 1, 1), 1, 0.05)
	task.wait(0.04)
	cc.Saturation = -1
	cc.Contrast = 3
	cc.Brightness = -0.2
	task.wait(0.08)
	cc.Brightness = 0.55
	cc.Contrast = 2.2
	task.wait(0.07)
	cc.Brightness = -0.3
	cc.Contrast = 3
	task.wait(0.06)
	cc:Destroy()
end

return {
	Id = "DodgeballRush",
	Name = "Dodgeball Rush",
	Duration = 5,
	-- the server leaves the victim standing; the beating is played on a local puppet
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

		-- geometry: the winner faces the victim across the net
		local K = killerRoot.Position
		local V = victimRoot.Position
		local f = Vector3.new(V.X - K.X, 0, V.Z - K.Z)
		f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
		local side = f:Cross(Vector3.yAxis)
		local G = V - Vector3.new(0, 3, 0) -- court under the victim

		local hero = ctx.standIn(ctx.killer) or ctx.killer
		pcall(function()
			hero:PivotTo(CFrame.lookAt(K, K + f))
		end)
		-- the spirit: a second copy of the winner, all glowing gold, behind their right shoulder
		local spirit = ctx.standIn(ctx.killer)
		local sroot = spirit and spirit:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- looming behind the winner's right shoulder
		local spiritHome = K - f * 3.2 + side * 1.4 + Vector3.new(0, 1.6, 0)
		if spirit and sroot then
			spiritify(ctx, spirit)
			sroot.CFrame = CFrame.lookAt(spiritHome, spiritHome + f)
		end

		local puppet = ctx.standIn(ctx.victim)
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		local victimCF = CFrame.lookAt(V, V - f)
		if proot then
			proot.CFrame = victimCF
		end

		-- the world stops: sound drops out and colors drain while the spirit appears
		local freeze = Instance.new("ColorCorrectionEffect")
		freeze.Parent = Lighting
		task.delay(ctx.duration + 0.3, function()
			freeze:Destroy() -- always cleaned up, even if the finisher errors
		end)
		ctx.pose(hero, "PointForward", 0.35)
		ctx.sound("StandSummon")

		-- Shot 1: low front three-quarter on the winner, the spirit fades in behind them ---------------
		local camA = K + f * 9 + side * 3.5 + Vector3.new(0, 1.2, 0)
		local camB = K + f * 6.5 + side * 2.5 + Vector3.new(0, 0.6, 0)
		local camLook = K:Lerp(spiritHome, 0.4) + Vector3.new(0, 1.4, 0)
		local manifested = false
		ctx.runFor(MANIFEST, function(alpha: number)
			local e = ctx.ease(alpha)
			cam.CFrame = CFrame.lookAt(camA:Lerp(camB, e), camLook)
			freeze.Saturation = -0.7 * math.min(1, alpha * 3)
			if not manifested and alpha > 0.3 then
				manifested = true
				if spirit and sroot then
					fadeSpirit(spirit, 0.25, 0.3)
					ctx.fx.flash(sroot.Position, IVORY, 9)
					ctx.fx.shockwave(sroot.Position, f, GOLD, 14, 0.4)
				end
				ctx.fx.shake(0.15)
			end
			if sroot then
				sroot.CFrame = CFrame.lookAt(spiritHome, spiritHome + f) * CFrame.new(0, math.sin(alpha * 6) * 0.15, 0)
			end
		end)

		-- The barrage --------------------------------------------------------------------------------
		-- palette flip: acid violet world, the spirit and its balls glowing gold against it
		freeze.Saturation = 0.6
		freeze.Contrast = 0.45
		freeze.TintColor = Color3.fromRGB(190, 140, 255)
		freeze.Brightness = -0.05
		if ctx.reducedMotion then
			freeze.Contrast = 0.15
			freeze.TintColor = Color3.fromRGB(215, 190, 255)
		end
		ctx.fx.screenFlash(VIOLET, 0.5, 0.15)
		ctx.pose(puppet, "ArmsSpread", 0.12)
		ctx.pose(hero, "CrossArms", 0.3)

		-- the spirit rushes to 9 studs from the victim and hovers there
		local spiritAt = G + Vector3.new(0, 3.6, 0) - f * 9
		local throwArm = { "RightHand", "LeftHand" }
		local hands: { BasePart? } = {}
		if spirit then
			for i, n in throwArm do
				hands[i] = spirit:FindFirstChild(n) :: BasePart?
			end
		end
		local balls: { { p: Part, from: Vector3, to: Vector3, t: number } } = {}
		local pool: { Part } = {}
		local fireEvery = if ctx.reducedMotion then 0.07 else 0.035
		local nextFire = 0
		local whichHand = 1
		local hits = 0
		-- victim juggle: lifted off the floor, knocked back and forth, slowly pushed back
		local jolt = Vector3.zero
		local joltVel = Vector3.zero
		local spin = Vector3.zero
		local function victimPos(t: number): Vector3
			local k = math.clamp((t - MANIFEST) / (BARRAGE_END - MANIFEST), 0, 1)
			local lift = 2.2 * math.min(1, k * 4) + 3.5 * k
			return V + f * (2.5 * k) + Vector3.new(0, lift, 0) + jolt
		end
		local lastCut = 0
		ctx.runFor(BARRAGE_END - MANIFEST, function(alpha: number, dt: number)
			local t = MANIFEST + alpha * (BARRAGE_END - MANIFEST)
			local vp = victimPos(t)

			-- spirit: dash in, then bob while throwing
			if sroot then
				local dash = 1 - (1 - math.min(1, (t - MANIFEST) / 0.15)) ^ 3
				local at = spiritHome:Lerp(spiritAt, dash) + Vector3.new(0, math.sin(t * 30) * 0.12, 0)
				sroot.CFrame = CFrame.lookAt(at, Vector3.new(vp.X, at.Y, vp.Z))
			end

			-- fire: alternating hands, aimed at a scatter around the victim's chest
			if t >= nextFire and t < BARRAGE_END - 0.06 then
				nextFire = t + fireEvery
				whichHand = 3 - whichHand
				if spirit then
					ctx.pose(spirit, if whichHand == 1 then "ThrowFollow" else "WindUp", 0.03)
				end
				local hand = hands[whichHand]
				local from = if hand
					then hand.Position
					else spiritAt + side * (if whichHand == 1 then 1 else -1) + Vector3.new(0, 1, 0)
				local to = vp + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 1.4), rng:NextNumber(-1, 1))
				local p = table.remove(pool) or makeBall(ctx, 1.4)
				p.Transparency = 0
				p.CFrame = CFrame.new(from)
				table.insert(balls, { p = p, from = from, to = to, t = 0 })
			end

			-- move balls; on arrival: pop, jolt the victim, recycle
			for i = #balls, 1, -1 do
				local b = balls[i]
				b.t += dt / 0.09
				if b.t >= 1 then
					hits += 1
					local dir = (b.to - b.from).Unit
					joltVel += dir * 9 + Vector3.new(0, 2, 0) + rng:NextUnitVector() * 3
					spin += rng:NextUnitVector() * 2.5
					if hits % (if ctx.reducedMotion then 4 else 2) == 0 then
						ctx.fx.burst(b.to, if hits % 3 == 0 then IVORY else GOLD, 5, 18, 0.5)
					end
					if hits % 3 == 0 then
						ctx.sound("BarrageHit", b.to)
					end
					if hits % 10 == 0 and not ctx.reducedMotion then
						ctx.fx.shockwave(b.to, -dir, IVORY, 6, 0.15)
					end
					b.p.Transparency = 1
					table.insert(pool, b.p)
					table.remove(balls, i)
				else
					b.p.CFrame = CFrame.new(b.from:Lerp(b.to, b.t)) * CFrame.Angles(b.t * 9, b.t * 5, 0)
				end
			end

			-- spring the victim back toward their track
			joltVel += (-jolt * 260 - joltVel * 16) * dt
			jolt += joltVel * dt
			spin *= math.max(0, 1 - dt * 6)
			if proot then
				local tumble = CFrame.Angles(spin.X * 0.25 + math.sin(t * 40) * 0.12, spin.Y * 0.25, spin.Z * 0.25)
				-- tipped backward, held up horizontally by the volley
				local tip = CFrame.Angles(math.rad(-55) * math.min(1, (t - MANIFEST) / 0.5), 0, 0)
				proot.CFrame = CFrame.lookAt(vp, vp - f) * tip * tumble
			end
			ctx.fx.shake(if ctx.reducedMotion then 0.01 else 0.05)

			-- camera
			local cut = if ctx.reducedMotion then 0 elseif t >= CUTS[2] then 2 elseif t >= CUTS[1] then 1 else 0
			if cut ~= lastCut then
				lastCut = cut
				ctx.sound("BarrageWhoosh")
			end
			if cut == 0 then
				-- side tracking: both of them in frame, drifting along with the victim
				local mid = spiritAt:Lerp(vp, 0.55)
				cam.FieldOfView = 70
				local k = (t - MANIFEST) / (CUTS[1] - MANIFEST)
				cam.CFrame = CFrame.lookAt(mid + side * (15 - 2 * k) + Vector3.new(0, 1.5, 0) + f * k, mid)
			elseif cut == 1 then
				-- the victim's eyes: a wall of balls coming straight in
				cam.FieldOfView = 95
				local eye = vp + Vector3.new(0, 1.6, 0) + f * 0.8
				cam.CFrame = CFrame.lookAt(eye, spiritAt + Vector3.new(0, 1.5, 0))
					* CFrame.Angles(0, 0, math.sin(t * 25) * 0.04)
			else
				-- low dutch angle from the ground behind the victim
				cam.FieldOfView = 80
				local k = (t - CUTS[2]) / (BARRAGE_END - CUTS[2])
				local low = G + f * 9 - side * 6 + Vector3.new(0, 0.6, 0)
				cam.CFrame = CFrame.lookAt(low, vp:Lerp(spiritAt, 0.25) + Vector3.new(0, 1 + k, 0))
					* CFrame.Angles(0, 0, math.rad(-22 + 6 * k))
			end
		end)
		for _, b in balls do
			b.p.Transparency = 1
		end

		-- Wind-up: total silence, the spirit draws back a giant charging golden ball -------------------
		local vp = victimPos(BARRAGE_END)
		if spirit then
			ctx.pose(spirit, "WindUp", 0.12)
		end
		local big = makeBall(ctx, 1)
		big.Material = Enum.Material.Neon
		big.Color = GOLD
		local bigLight = Instance.new("PointLight")
		bigLight.Color = GOLD
		bigLight.Range = 20
		bigLight.Brightness = 6
		bigLight.Parent = big
		cam.FieldOfView = 60
		local windCam = spiritAt + side * 7 - f * 2 + Vector3.new(0, 0.5, 0)
		ctx.runFor(IMPACT - BARRAGE_END, function(alpha: number)
			local hand = hands[1]
			local at = (if hand then hand.Position else spiritAt + Vector3.new(0, 3, 0) - f) + Vector3.new(0, 1, 0)
			big.Size = Vector3.one * (1 + 3 * alpha)
			big.CFrame = CFrame.new(at)
			bigLight.Range = 20 + 30 * alpha
			cam.CFrame = CFrame.lookAt(windCam:Lerp(windCam - side * 1.5, alpha), at:Lerp(vp, 0.3))
			if proot then
				-- hangs in the air, limp, for a beat
				proot.CFrame = CFrame.lookAt(vp, vp - f) * CFrame.Angles(math.rad(-55), 0, 0)
			end
		end)

		-- Impact -------------------------------------------------------------------------------------
		if spirit then
			ctx.pose(spirit, "ThrowFollow", 0.05)
		end
		big:Destroy()
		ctx.sound("BarrageFinal", vp)
		ctx.fx.flash(vp, IVORY, 16)
		ctx.fx.shockwave(vp, f, GOLD, 30, 0.4)
		ctx.fx.burst(vp, GOLD, if ctx.reducedMotion then 20 else 70, 60, 1.4)
		ctx.fx.shake(0.7)
		local impactCam = vp - f * 6 + side * 10 + Vector3.new(0, -1, 0)
		cam.CFrame = CFrame.lookAt(impactCam, vp)
		impactFrames(ctx)
		freeze.Saturation = 0
		freeze.Contrast = 0
		freeze.Brightness = 0
		freeze.TintColor = Color3.new(1, 1, 1)
		if spirit then
			fadeSpirit(spirit, 1, 0.4)
		end

		-- Disposal: arc off the court and into the ball cart -------------------------------------------
		local o = ctx.outward :: Vector3
		-- just past the back edge, over the void, whatever the court size
		local pastEdge = if ctx.toEdge then ctx.toEdge(G, o) + 6 else 30
		local cartAt = G + o * pastEdge + side * 4
		local lid, lidOpen, lidClosed = ballCart(ctx, cartAt, o, rng)
		local landAt = cartAt + Vector3.new(0, 4, 0)
		local launchFrom = vp
		local apex = 22
		local flyTime = LAND - (os.clock() - t0)
		local followFrom = cam.CFrame.Position
		local wideCam = cartAt - o * 22 + side * 20 + Vector3.new(0, 10, 0)
		ctx.runFor(math.max(0.3, flyTime), function(alpha: number)
			local pos = launchFrom:Lerp(landAt, alpha) + Vector3.new(0, 4 * apex * alpha * (1 - alpha), 0)
			if proot then
				proot.CFrame = CFrame.new(pos) * CFrame.Angles(alpha * 14, alpha * 5, alpha * 9)
			end
			cam.FieldOfView = 70
			cam.CFrame = CFrame.lookAt(
				followFrom:Lerp(wideCam, ctx.ease(math.min(1, alpha * 1.5))),
				pos:Lerp(cartAt, alpha * 0.6)
			)
		end)
		ctx.sound("CartCrash", landAt)
		ctx.fx.burst(landAt, BALL_RED, if ctx.reducedMotion then 10 else 30, 35, 1.2)
		ctx.fx.shake(0.4)
		if proot then
			proot.CFrame = CFrame.new(landAt - Vector3.new(0, 1, 0)) * CFrame.Angles(math.rad(70), 0, math.rad(20))
		end
		task.wait(0.15)
		-- the lid slams shut
		local slamTime = 0.18
		local slammed = false
		local hold = wideCam
		ctx.runFor(math.max(0.2, ctx.duration - (os.clock() - t0)), function(alpha: number)
			local el = (os.clock() - t0) - LAND - 0.15
			local u = math.clamp(el / slamTime, 0, 1)
			lid.CFrame = lidOpen:Lerp(lidClosed, u * u)
			if u >= 1 and not slammed then
				slammed = true
				ctx.sound("CartSlam", cartAt)
				ctx.fx.shake(0.5)
				ctx.fx.burst(cartAt + Vector3.new(0, 7, 0), Color3.fromRGB(200, 200, 200), 20, 20, 1)
			end
			cam.CFrame = CFrame.lookAt(hold:Lerp(hold + (cartAt - hold) * 0.15, alpha), cartAt + Vector3.new(0, 3, 0))
		end)
		cam.FieldOfView = baseFov
	end,
}
