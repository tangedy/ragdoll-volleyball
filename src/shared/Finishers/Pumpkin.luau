--!strict
-- Pumpkin Reaper (Halloween): the winner catches a jack-o-lantern, crowns themselves with it
-- (head bowed, face hidden), then looks up to reveal the glowing carved face. Cut to the victim:
-- undead arms burst from the ground, grab their ankles and drag them, flailing, off the arena
-- and under while bats swirl.
--
--   0.0-2.5  shot 1, slow pan-in on the winner: toss -> catch -> raise -> on the head (bowed)
--            -> 1.9 looks up, face flares, fast zoom-in
--   2.5-5.0  shot 2, slow zoom the whole time: arms rise (2.5), grab (3.0), drag + sink (3.25-5.0)
--
-- The victim's drag is played on a local puppet (a copy of the victim) so the limbs can be
-- choreographed; the real victim is hidden for the shot and the server doesn't launch them.

local CUT = 2.5
local REVEAL = 1.9
local PUMPKIN_R = 1.35

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local ORANGE = Color3.fromRGB(255, 118, 18)
local CARVE = Color3.fromRGB(255, 205, 70)
local PURPLE = Color3.fromRGB(150, 80, 255)
local ZOMBIE = Color3.fromRGB(150, 185, 120)
local DIRT = Color3.fromRGB(90, 62, 40)

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- A small rig of anchored parts: each child carries its offset from the base; place() moves all.
type Rig = { base: Part, parts: { { p: BasePart, off: CFrame } } }

local function rigAdd(rig: Rig, p: BasePart, off: CFrame)
	table.insert(rig.parts, { p = p, off = off })
end

local function place(rig: Rig, cf: CFrame)
	rig.base.CFrame = cf
	for _, e in rig.parts do
		e.p.CFrame = cf * e.off
	end
end

-- Jack-o-lantern: carved face on the local -Z side, glowing from inside.
local function makePumpkin(ctx: any): (Rig, PointLight, { BasePart })
	local body = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * PUMPKIN_R * 2,
		Color = ORANGE,
	}, ctx.folder)
	local rig: Rig = { base = body, parts = {} }
	-- ribs: slightly darker discs around the vertical axis read as pumpkin segments
	for i = 0, 2 do
		local rib = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, PUMPKIN_R * 2.03, PUMPKIN_R * 2.03),
			Color = ORANGE:Lerp(Color3.new(0.4, 0.15, 0), 0.35),
		}, ctx.folder)
		rigAdd(rig, rib, CFrame.Angles(0, math.rad(60 * i), 0) * CFrame.Angles(0, math.rad(90), 0))
	end
	local stem = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 0.35, 0.35),
		Color = Color3.fromRGB(80, 110, 40),
	}, ctx.folder)
	rigAdd(rig, stem, CFrame.new(0, PUMPKIN_R + 0.2, 0) * CFrame.Angles(0, 0, math.rad(80)))
	local carved: { BasePart } = {}
	local function feature(x: number, y: number, size: Vector3, rotZ: number)
		local z = -math.sqrt(math.max(0.05, PUMPKIN_R ^ 2 - x * x - y * y)) + 0.02
		local pos = Vector3.new(x, y, z)
		local f = part({
			Size = size,
			Color = Color3.fromRGB(120, 60, 10),
			Material = Enum.Material.Neon,
		}, ctx.folder)
		rigAdd(rig, f, CFrame.lookAt(pos, pos * 2) * CFrame.Angles(0, 0, math.rad(rotZ)))
		table.insert(carved, f)
	end
	-- eyes (diamonds), nose, jagged grin
	feature(-0.48, 0.32, Vector3.new(0.42, 0.42, 0.06), 45)
	feature(0.48, 0.32, Vector3.new(0.42, 0.42, 0.06), 45)
	feature(0, 0.02, Vector3.new(0.2, 0.2, 0.06), 45)
	for i = -2, 2 do
		feature(i * 0.27, -0.42 + (if i % 2 == 0 then 0.06 else -0.06), Vector3.new(0.26, 0.2, 0.06), 0)
	end
	local light = Instance.new("PointLight")
	light.Color = CARVE
	light.Range = 6
	light.Brightness = 1
	light.Parent = body
	return rig, light, carved
end

-- Bat: a small dark body and two flapping wings. Each one bursts from just behind the camera and
-- flies to a perch spot on one side of the frame, behind the victim, then flutters there.
type Bat = { body: Part, wings: { Part }, phase: number, from: Vector3, to: Vector3, launch: number, travel: number }

local function makeBat(ctx: any, rng: Random, from: Vector3, to: Vector3, launch: number): Bat
	local dark = Color3.fromRGB(46, 30, 62) -- deep purple reads against the night sky
	local body = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, Color = dark }, ctx.folder)
	local wings = {}
	for _ = 1, 2 do
		table.insert(wings, part({ Size = Vector3.new(0.95, 0.05, 0.42), Color = dark }, ctx.folder))
	end
	local eye = part(
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.12,
			Color = Color3.fromRGB(255, 40, 40),
			Material = Enum.Material.Neon,
		},
		ctx.folder
	)
	table.insert(wings, eye) -- moved with the body below
	return {
		body = body,
		wings = wings,
		phase = rng:NextNumber(0, math.pi * 2),
		from = from,
		to = to,
		launch = launch,
		travel = rng:NextNumber(0.7, 1.05),
	}
end

local function moveBat(b: Bat, t: number)
	local u = math.clamp((t - b.launch) / b.travel, 0, 1)
	local e = 1 - (1 - u) ^ 2
	-- arc slightly upward on the way, then hover-flutter at the perch
	local pos = b.from:Lerp(b.to, e) + Vector3.new(0, math.sin(u * math.pi) * 2, 0)
	if u >= 1 then
		pos = b.to
			+ Vector3.new(
				math.cos(t * 3 + b.phase) * 0.8,
				math.sin(t * 5 + b.phase) * 0.5,
				math.sin(t * 3 + b.phase) * 0.8
			)
	end
	local dir = (b.to - b.from).Unit
	local cf = CFrame.lookAt(pos, pos + dir)
	b.body.CFrame = cf
	b.body.Transparency = if t < b.launch then 1 else 0
	local flap = math.sin(t * 30 + b.phase) * 0.9
	for i, w in b.wings do
		if i > 2 then
			w.CFrame = cf * CFrame.new(0, 0.08, -0.2) -- eyes, facing the way it flies
		else
			local sgn = if i == 1 then 1 else -1
			w.CFrame = cf
				* CFrame.new(0.15 * sgn, 0, 0)
				* CFrame.Angles(0, 0, flap * sgn)
				* CFrame.new(0.47 * sgn, 0, 0)
		end
		w.Transparency = b.body.Transparency
	end
end

-- Undead arm: ragged sleeve, rotting forearm, clawed hand. Returns a rig based at the elbow end.
local function makeArm(ctx: any, rng: Random): Rig
	local sleeve = part(
		{ Size = Vector3.new(1.15, 1.4, 1.15), Color = Color3.fromRGB(70, 55, 85), Material = Enum.Material.Fabric },
		ctx.folder
	)
	local rig: Rig = { base = sleeve, parts = {} }
	local forearm = part({ Size = Vector3.new(0.8, 2.3, 0.8), Color = ZOMBIE }, ctx.folder)
	rigAdd(rig, forearm, CFrame.new(0, 1.7, 0))
	-- rotting patches
	for i = 1, 2 do
		local patch = part({ Size = Vector3.new(0.3, 0.45, 0.06), Color = Color3.fromRGB(70, 90, 55) }, ctx.folder)
		rigAdd(rig, patch, CFrame.new(rng:NextNumber(-0.2, 0.2), 1.2 + i * 0.5, -0.42))
	end
	local hand =
		part({ Size = Vector3.new(1.05, 0.75, 0.5), Color = ZOMBIE:Lerp(Color3.new(1, 1, 1), 0.08) }, ctx.folder)
	rigAdd(rig, hand, CFrame.new(0, 3.2, 0))
	-- clawed fingers and a thumb, curled toward the grab
	for i = -1.5, 1.5 do
		local finger = part({ Size = Vector3.new(0.2, 0.85, 0.2), Color = ZOMBIE }, ctx.folder)
		rigAdd(
			rig,
			finger,
			CFrame.new(i * 0.24, 3.85, -0.12)
				* CFrame.Angles(math.rad(-38 + rng:NextNumber(-12, 12)), 0, math.rad(i * 8))
		)
		local claw = part({ Size = Vector3.new(0.14, 0.25, 0.14), Color = Color3.fromRGB(40, 35, 30) }, ctx.folder)
		rigAdd(rig, claw, CFrame.new(i * 0.24, 4.25, -0.42) * CFrame.Angles(math.rad(-70), 0, 0))
	end
	local thumb = part({ Size = Vector3.new(0.2, 0.6, 0.2), Color = ZOMBIE }, ctx.folder)
	rigAdd(rig, thumb, CFrame.new(0.6, 3.35, -0.1) * CFrame.Angles(0, 0, math.rad(-50)))
	return rig
end

-- A dirt mound where an arm breaks through the ground.
local function mound(ctx: any, at: Vector3)
	local m = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 0.1, 0.1),
		CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = DIRT,
		Material = Enum.Material.Ground,
	}, ctx.folder)
	game:GetService("TweenService")
		:Create(m, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = Vector3.new(0.5, 3.2, 3.2) })
		:Play()
end

-- Local forward kinematics for the puppet: place every limb from the root through its joints.
type Joint = { name: string, p0: BasePart, p1: BasePart, f0: CFrame, f1: CFrame }

local function puppetJoints(model: Model): { Joint }
	local joints = {}
	for _, d in model:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			local a0, a1 = d.Attachment0 :: Attachment, d.Attachment1 :: Attachment
			table.insert(
				joints,
				{ name = d.Name, p0 = a0.Parent :: BasePart, p1 = a1.Parent :: BasePart, f0 = a0.CFrame, f1 = a1.CFrame }
			)
		elseif d:IsA("JointInstance") and d.Part0 and d.Part1 then
			-- Motor6D limbs (classic rigs) and Welds (accessories) both carry C0/C1
			table.insert(joints, { name = d.Name, p0 = d.Part0, p1 = d.Part1, f0 = d.C0, f1 = d.C1 })
		elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 then
			-- team band / hit proxy: keep their current offset
			table.insert(
				joints,
				{
					name = d.Name,
					p0 = d.Part0,
					p1 = d.Part1,
					f0 = d.Part0.CFrame:ToObjectSpace(d.Part1.CFrame),
					f1 = CFrame.identity,
				}
			)
		end
	end
	return joints
end

local function solveFK(root: BasePart, joints: { Joint }, transforms: { [string]: CFrame })
	local placed: { [BasePart]: boolean } = { [root] = true }
	local remaining = #joints
	local guard = 0
	while remaining > 0 and guard < 20 do
		guard += 1
		for _, j in joints do
			if placed[j.p0] and not placed[j.p1] then
				j.p1.CFrame = j.p0.CFrame * j.f0 * (transforms[j.name] or CFrame.identity) * j.f1:Inverse()
				placed[j.p1] = true
				remaining -= 1
			end
		end
	end
end

local function axisRot(j: Joint, axis: Vector3, deg: number): CFrame
	return CFrame.fromAxisAngle(j.f0:VectorToObjectSpace(axis), math.rad(deg))
end

return {
	Id = "Pumpkin",
	Name = "Pumpkin Reaper",
	Duration = 5.0,
	-- the server leaves the victim standing; the drag is a client-side puppet
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local rng = Random.new()
		local cam = ctx.camera
		-- the winner is played by a stand-in wearing their avatar (the real character is hidden)
		local killerRoot = ctx.rootOf(ctx.killer)
		local killer = if killerRoot then (ctx.standIn(ctx.killer) or ctx.killer) else ctx.killer
		local victimRoot = ctx.rootOf(ctx.victim)
		local baseFov = cam.FieldOfView

		-- Shot 1: the winner and the jack-o-lantern ---------------------------------------------
		ctx.banner("PUMPKIN REAPER!", ORANGE, 1.4)
		if killerRoot then
			local K = killerRoot.Position
			local look = killerRoot.CFrame.LookVector
			local f = Vector3.new(look.X, 0, look.Z)
			f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
			local side = f:Cross(Vector3.yAxis)
			local pumpkin, light, carved = makePumpkin(ctx)
			local tossFrom = K + side * 13 + f * 3 + Vector3.new(0, 9, 0)
			place(pumpkin, CFrame.new(tossFrom))
			local head = killer:FindFirstChild("Head") :: BasePart?
			local rHand = killer:FindFirstChild("RightHand") :: BasePart?
			local lHand = killer:FindFirstChild("LeftHand") :: BasePart?
			local function handsMid(): Vector3
				if rHand and lHand then
					return (rHand.Position + lHand.Position) / 2
				end
				return K + Vector3.new(0, 1, 0) + f * 1.5
			end
			-- slightly above eye level so the bowed carved face stays hidden until the reveal
			local camA = K + f * 12.5 + side * 1.2 + Vector3.new(0, 3.4, 0)
			local camB = K + f * 6.8 + side * 0.8 + Vector3.new(0, 2.7, 0)
			local lookAt = K + Vector3.new(0, 1.9, 0)
			local stage = 0
			local placeFrom: CFrame? = nil
			ctx.sound("SpookyToss")
			ctx.pose(killer, "Catch", 0.3)
			ctx.runFor(CUT, function(alpha: number)
				local t = alpha * CUT
				-- slow pan-in, then a fast zoom on the look-up
				local e = ctx.ease(math.min(1, t / REVEAL))
				local camPos = camA:Lerp(camB, e)
				if t >= REVEAL then
					local z = math.min(1, (t - REVEAL) / 0.16)
					z = 1 - (1 - z) ^ 3
					cam.FieldOfView = baseFov + (40 - baseFov) * z
					camPos = camPos:Lerp(lookAt + f * 4.5 + Vector3.new(0, 0.6, 0), z * 0.35)
				end
				-- on the reveal the frame also rolls ~35 degrees, like rotating the picture
				local roll = 0
				if t >= REVEAL then
					local r = math.min(1, (t - REVEAL) / 0.22)
					roll = math.rad(35) * (1 - (1 - r) ^ 3)
				end
				cam.CFrame = CFrame.lookAt(camPos, lookAt + Vector3.new(0, if t >= REVEAL then 0.3 else 0, 0))
					* CFrame.Angles(0, 0, roll)

				-- choreography
				if stage == 0 and t >= 0.55 then
					stage = 1
					ctx.sound("PumpkinCatch", handsMid())
				elseif stage == 1 and t >= 0.75 then
					stage = 2
					ctx.pose(killer, "RaiseOverhead", 0.4)
				elseif stage == 2 and t >= 1.15 then
					stage = 3
					placeFrom = pumpkin.base.CFrame
				elseif stage == 3 and t >= 1.35 then
					stage = 4
					ctx.hideHead(killer)
					ctx.pose(killer, "BowHead", 0.3)
					ctx.sound("PumpkinCatch", handsMid())
				elseif stage == 4 and t >= REVEAL then
					stage = 5
					ctx.pose(killer, "LookUp", 0.12)
					ctx.sound("PumpkinReveal")
					light.Range = 14
					light.Brightness = 6
					for _, c in carved do
						c.Color = CARVE
					end
					if head then
						ctx.fx.burst(head.Position, PURPLE, if ctx.reducedMotion then 10 else 35, 18, 0.7)
					end
				end

				-- where the pumpkin is
				if t < 0.55 then
					local a = t / 0.55
					local pos = tossFrom:Lerp(handsMid(), a) + Vector3.new(0, 4 * math.sin(a * math.pi), 0)
					place(pumpkin, CFrame.new(pos) * CFrame.Angles(a * 9, a * 4, 0))
				elseif stage <= 2 then
					-- held: stem up, carved face turned toward the holder (hidden from the camera)
					local hp = handsMid() + Vector3.new(0, 0.35, 0)
					place(pumpkin, CFrame.lookAt(hp, Vector3.new(K.X, hp.Y, K.Z)))
				elseif head then
					local onHead = head.CFrame * CFrame.new(0, 0.3, 0)
					if stage == 3 and placeFrom then
						local a = math.clamp((t - 1.15) / 0.2, 0, 1)
						place(pumpkin, placeFrom:Lerp(onHead, a * a * (3 - 2 * a)))
					else
						place(pumpkin, onHead)
					end
				end
				-- carved glow flickers once revealed
				if stage >= 5 then
					light.Brightness = 5 + math.sin(t * 40) * 1.5
				end
			end)
		else
			task.wait(CUT)
		end
		cam.FieldOfView = baseFov

		-- Shot 2: the undead take the victim ---------------------------------------------------
		if not victimRoot then
			task.wait(math.max(0, ctx.duration - (os.clock() - t0)))
			return
		end
		local victim = ctx.victim :: Model
		local G = victimRoot.Position - Vector3.new(0, 3, 0)
		local o = ctx.outward :: Vector3
		local s = o:Cross(Vector3.yAxis)
		local tint = Instance.new("ColorCorrectionEffect")
		tint.TintColor = Color3.fromRGB(200, 185, 255)
		tint.Saturation = -0.3
		tint.Contrast = 0.2
		tint.Parent = cam
		task.delay(ctx.duration + 0.5, function()
			tint:Destroy()
		end)
		-- creeping ground fog
		for i = 1, (if ctx.reducedMotion then 2 else 5) do
			local anchor = part(
				{
					Size = Vector3.one * 0.2,
					Transparency = 1,
					CFrame = CFrame.new(G + o * (i * 4 - 4) + s * rng:NextNumber(-4, 4)),
				},
				ctx.folder
			)
			local a = Instance.new("Attachment")
			a.Parent = anchor
			local fog = Instance.new("ParticleEmitter")
			fog.Texture = SMOKE
			fog.Color = ColorSequence.new(Color3.fromRGB(120, 160, 130))
			fog.LightInfluence = 0.5
			fog.Size = NumberSequence.new(6, 10)
			fog.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			})
			fog.Lifetime = NumberRange.new(2, 3)
			fog.Speed = NumberRange.new(0.5, 1.2)
			fog.Rate = 6
			fog.SpreadAngle = Vector2.new(180, 10)
			fog.Parent = a
			fog:Emit(4)
		end
		-- camera: head-on in front of the victim, at foot level, tilted slightly up; slow push-in
		local camA = G - o * 13 + Vector3.new(0, 0.7, 0)
		local camB = G - o * 9.5 + Vector3.new(0, 0.7, 0)
		-- bats burst from just behind the camera and split to two perches either side of the frame,
		-- behind the victim
		local bats: { Bat } = {}
		local n = if ctx.reducedMotion then 4 else 10
		for i = 1, n do
			local left = i % 2 == 0
			local from = camA - o * 3 + Vector3.new(0, rng:NextNumber(0.5, 2), 0) + s * rng:NextNumber(-0.8, 0.8)
			local perch = G + o * 5 + s * (if left then 7.5 else -7.5) + Vector3.new(0, 3.6, 0)
			local to = perch + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-1, 1), rng:NextNumber(-1.2, 1.2))
			table.insert(bats, makeBat(ctx, rng, from, to, 0.05 + (i - 1) * 0.08))
		end
		-- undead arms: two grabbers at the feet, the rest clawing out to the sides and behind (never
		-- between the camera and the victim)
		local clawSpots =
			{ Vector2.new(0.3, 3.3), Vector2.new(0.3, -3.3), Vector2.new(2.6, 2.3), Vector2.new(2.6, -2.3) }
		local arms: { { rig: Rig, at: Vector3, grab: boolean, phase: number } } = {}
		for i = 1, 6 do
			local grab = i <= 2
			local spot = clawSpots[i - 2]
			local at = if grab then G + o * 0.9 + s * (if i == 1 then 0.45 else -0.45) else G + o * spot.X + s * spot.Y
			table.insert(arms, { rig = makeArm(ctx, rng), at = at, grab = grab, phase = rng:NextNumber(0, 6) })
		end
		ctx.sound("UndeadRise", G)
		ctx.fx.burst(G, DIRT, if ctx.reducedMotion then 15 else 45, 22, 1.2)
		ctx.fx.shake(0.25)

		local puppet: Model? = nil
		local proot: BasePart? = nil
		local joints: { Joint } = {}
		local byName: { [string]: Joint } = {}
		local standCF = victimRoot.CFrame
		local dragged = false
		local shotStart = os.clock()
		local shotLen = math.max(0.5, ctx.duration - (shotStart - t0))
		ctx.runFor(shotLen, function(alpha: number)
			local t = os.clock() - shotStart
			-- slow zoom for the whole shot
			local e = ctx.ease(alpha)
			cam.FieldOfView = baseFov + (55 - baseFov) * e

			-- the grab: swap in the puppet and pull the victim down onto their front
			if not puppet and t >= 0.5 then
				local wasArchivable = victim.Archivable
				victim.Archivable = true
				local copy = victim:Clone()
				victim.Archivable = wasArchivable
				for _, d in copy:GetDescendants() do
					if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("BallSocketConstraint") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.LocalTransparencyModifier = 0
					end
				end
				local h = copy:FindFirstChildOfClass("Humanoid")
				if h then
					h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
				copy.Parent = ctx.folder
				ctx.hide(victim)
				puppet = copy
				proot = copy:FindFirstChild("HumanoidRootPart") :: BasePart?
				joints = puppetJoints(copy)
				for _, j in joints do
					byName[j.name] = j
				end
				ctx.sound("Drag", G)
				ctx.banner(("%s sent %s to the grave!"):format(ctx.killerName, ctx.victimName), PURPLE, 1.8)
			end

			-- body: tip over onto the front (0.5-0.75), then dragged feet-first and sunk under
			local feet = G
			if proot and puppet then
				local u = math.clamp((t - 0.75) / (shotLen - 0.85), 0, 1)
				local dist = 22 * u ^ 1.7
				-- dragged along the surface first (the flailing reads), pulled under only at the end
				local sink = -9 * math.max(0, (u - 0.72) / 0.28) ^ 1.6
				feet = G + o * dist + Vector3.new(0, sink, 0)
				local up = -o -- head trails back toward the court
				local back = Vector3.yAxis -- face down
				local lyingPos = feet - o * 2.9 + Vector3.new(0, 0.75, 0)
				local lying = CFrame.fromMatrix(lyingPos, up:Cross(back), up, back)
				local tip = math.clamp((t - 0.5) / 0.25, 0, 1)
				proot.CFrame = if tip < 1 then standCF:Lerp(lying, tip * tip) else lying
				-- flailing limbs (only once they're down)
				local fl = math.clamp((t - 0.6) / 0.3, 0, 1)
				local tf: { [string]: CFrame } = {}
				local X, Z = Vector3.xAxis, Vector3.zAxis
				for _, side in { "Right", "Left" } do
					local sgn = if side == "Right" then 1 else -1
					local sh, el = byName[side .. "Shoulder"], byName[side .. "Elbow"]
					if sh then
						tf[sh.name] = axisRot(sh, X, fl * (150 + 25 * math.sin(t * 13 + sgn)))
							* axisRot(sh, Z, fl * sgn * (25 + 25 * math.sin(t * 9 + sgn * 2)))
					end
					if el then
						tf[el.name] = axisRot(el, X, fl * (35 + 35 * math.sin(t * 15 + sgn * 1.5)))
					end
				end
				local neck = byName["Neck"]
				if neck then
					tf[neck.name] = axisRot(neck, X, fl * 35 * math.sin(t * 11))
						* axisRot(neck, Z, fl * 30 * math.sin(t * 7.5))
				end
				local waist = byName["Waist"]
				if waist then
					tf[waist.name] = axisRot(waist, Z, fl * 12 * math.sin(t * 9))
				end
				solveFK(proot, joints, tf)
				if not dragged and t > 0.8 then
					dragged = true
					ctx.fx.shake(0.2)
				end
			end

			-- arms: burst out of the ground, claw; the grabbers ride along holding the ankles
			for i, arm in arms do
				local rise = math.clamp((t - 0.05 * i) / 0.35, 0, 1)
				local base: Vector3
				local tilt: CFrame
				if arm.grab and puppet then
					-- rooted just past the feet, leaning back over them so the hands clamp the ankles
					base = feet + o * 1.6 + s * (if i == 1 then 0.5 else -0.5) + Vector3.new(0, -1.5, 0)
					tilt = CFrame.Angles(math.rad(38), 0, 0)
				else
					base = arm.at + Vector3.new(0, -3.2 + 2.4 * rise ^ 0.5, 0)
					tilt = CFrame.Angles(
						math.rad(12 * math.sin(t * 6 + arm.phase)),
						0,
						math.rad(10 * math.sin(t * 4 + arm.phase))
					)
					if t > 1.6 then
						-- the clawing arms sink back down once the victim is gone
						base -= Vector3.new(0, 4 * math.clamp((t - 1.6) / 0.6, 0, 1), 0)
					end
				end
				local facing = CFrame.lookAt(base, base + Vector3.new(-o.X, 0, -o.Z))
				place(arm.rig, facing * tilt)
				if rise > 0 and not (arm :: any).burst then
					(arm :: any).burst = true
					ctx.fx.burst(arm.at + Vector3.new(0, 0.5, 0), DIRT, if ctx.reducedMotion then 6 else 16, 14, 0.8)
					if not arm.grab then
						mound(ctx, arm.at)
					end
				end
			end

			-- bats circle the scene, drifting along with the drag
			for _, b in bats do
				moveBat(b, t)
			end

			-- camera: slow zoom in the whole shot, eyes on the victim
			local focus = if proot then proot.Position + Vector3.new(0, 0.6, 0) else G + Vector3.new(0, 3.2, 0)
			cam.CFrame = CFrame.lookAt(camA:Lerp(camB, e), focus)
		end)
		tint:Destroy()
	end,
}
