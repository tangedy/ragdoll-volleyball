--!strict
-- Destiny Arrives: a portal tears open beside the winner and a purple titan in gold-trimmed armor
-- steps out of it. He raises his gauntleted left hand and snaps his fingers. Cut to the
-- victim, who fades away into drifting dust.
--
--   0.00-2.00  shot 1, wide from the victim's side: the portal opens (0.0-0.6), he walks out (0.7-1.9)
--   2.00-2.95  shot 2, close on his raised hand: SnapReady, the snap at 2.65 (flash)
--   2.95-5.00  shot 3, a still shot of the victim's whole body crumbling to dust (3.2-4.7)
--
-- The server leaves the victim standing (Stage.Launch = false); the fade plays on a local copy, and
-- the titan is a local copy of the avatar the server builds from Config.Finisher.DestinyAvatar,
-- scaled up; without it, the practice dummy re-dressed in the titan's colors. He walks and idles
-- with Roblox's own R15 animations, so the motion fits any avatar's joints.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SHOT2 = 2.0
local SNAP = 2.65
local SHOT3 = 2.95
local SCALE = 1 -- player-sized

local SKIN = Color3.fromRGB(142, 104, 168)
local SKIN_SHADE = Color3.fromRGB(110, 78, 136)
local ARMOR = Color3.fromRGB(52, 66, 108)
local TROUSERS = Color3.fromRGB(34, 40, 70)
local GOLD = Color3.fromRGB(222, 172, 58)
local GEMS = { -- space, mind, reality, power, time, soul
	Color3.fromRGB(60, 120, 255),
	Color3.fromRGB(255, 220, 60),
	Color3.fromRGB(230, 40, 50),
	Color3.fromRGB(170, 70, 255),
	Color3.fromRGB(60, 220, 90),
	Color3.fromRGB(255, 140, 30),
}
local SNAP_FLASH = Color3.fromRGB(255, 240, 210)
local PORTAL_RIM = Color3.fromRGB(120, 150, 255)
local PORTAL_CORE = Color3.fromRGB(10, 6, 24)
local DUST = Color3.fromRGB(120, 104, 92)

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

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

-- A part riding on `on` (welded, so it follows the rig's kinematic joints).
local function attach(on: BasePart, props: { [string]: any }, offset: CFrame): Part
	local p = part(props, on)
	p.Anchored = false
	p.Massless = true
	p.CFrame = on.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = on
	w.Part1 = p
	w.Parent = p
	return p
end

-- Roblox's default R15 walk and idle (Roblox-owned, usable in any game).
local WALK_ANIM = "rbxassetid://507777826"
local IDLE_ANIM = "rbxassetid://507766388"

local function loadTrack(model: Model, id: string): AnimationTrack?
	local h = model:FindFirstChildOfClass("Humanoid")
	if not h then
		return nil
	end
	local animator = h:FindFirstChildOfClass("Animator")
	if not animator then
		local made = Instance.new("Animator")
		made.Parent = h
		animator = made
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	return if ok then track else nil
end

-- A light in the left (snapping) hand that flares on the snap.
local function snapGlow(giant: Model)
	local hand = giant:FindFirstChild("LeftHand") :: BasePart?
	if hand then
		local glow = Instance.new("PointLight")
		glow.Name = "SnapGlow"
		glow.Color = Color3.fromRGB(255, 240, 200)
		glow.Range = 0
		glow.Brightness = 5
		glow.Parent = hand
	end
	local h = giant:FindFirstChildOfClass("Humanoid")
	if h then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

-- Without the avatar, re-dress the dummy copy as the titan: purple skin and a ridged chin, blue armor with gold trim
-- and shoulder plates, and a gold gauntlet set with six colored gems on the left (snapping) hand.
local SKIN_PARTS = {
	Head = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperArm = true,
}
local function dress(giant: Model)
	for _, d in giant:GetDescendants() do
		if d:IsA("Decal") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Accessory") then
			d:Destroy()
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.SmoothPlastic
			if SKIN_PARTS[d.Name] then
				d.Color = SKIN
			elseif string.find(d.Name, "Torso") then
				d.Color = ARMOR
			elseif d.Name == "LeftLowerArm" or d.Name == "LeftHand" then
				d.Color = GOLD
				d.Material = Enum.Material.Metal
				d.Reflectance = 0.15
			else
				d.Color = TROUSERS
			end
		end
	end
	local head = giant:FindFirstChild("Head") :: BasePart?
	local torso = giant:FindFirstChild("UpperTorso") :: BasePart?
	local lower = giant:FindFirstChild("LowerTorso") :: BasePart?
	if head then
		local hs = head.Size
		local front = -hs.Z / 2 - 0.02
		-- deep-set eyes
		for _, x in { -0.2, 0.2 } do
			attach(head, {
				Size = Vector3.new(hs.X * 0.15, hs.Y * 0.07, 0.05),
				Color = Color3.fromRGB(40, 70, 110),
			}, CFrame.new(hs.X * x, hs.Y * 0.1, front))
		end
		-- the ridged chin
		for _, x in { -0.12, 0, 0.12 } do
			attach(head, {
				Size = Vector3.new(hs.X * 0.035, hs.Y * 0.3, 0.05),
				Color = SKIN_SHADE,
			}, CFrame.new(hs.X * x, -hs.Y * 0.28, front))
		end
	end
	if torso then
		local ts = torso.Size
		-- gold shoulder plates and a gold trim down the chest
		for _, x in { -1, 1 } do
			attach(torso, {
				Size = Vector3.new(ts.X * 0.42, ts.Y * 0.22, ts.Z * 1.3),
				Color = GOLD,
				Material = Enum.Material.Metal,
				Reflectance = 0.15,
			}, CFrame.new(x * ts.X * 0.55, ts.Y * 0.42, 0) * CFrame.Angles(0, 0, math.rad(x * -12)))
		end
		attach(torso, {
			Size = Vector3.new(ts.X * 0.16, ts.Y * 0.9, 0.06),
			Color = GOLD,
			Material = Enum.Material.Metal,
		}, CFrame.new(0, 0, -ts.Z / 2 - 0.03))
	end
	if lower then
		local ls = lower.Size
		attach(lower, {
			Size = Vector3.new(ls.X * 1.04, ls.Y * 0.35, ls.Z * 1.04),
			Color = GOLD,
			Material = Enum.Material.Metal,
		}, CFrame.new(0, ls.Y * 0.25, 0))
	end
	-- the gauntlet's six gems across the back of the hand, and a glow for the snap
	local hand = giant:FindFirstChild("LeftHand") :: BasePart?
	if hand then
		local hz = hand.Size
		for i, color in GEMS do
			local x = (i - 3.5) / 2.5 * hz.X * 0.42
			attach(hand, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * hz.X * 0.18,
				Color = color,
				Material = Enum.Material.Neon,
			}, CFrame.new(x, hz.Y * 0.15, hz.Z / 2 + 0.02))
		end
	end
	snapGlow(giant)
end

-- The portal: a ring of light around a black core, facing `normal`, opening from nothing.
local function makePortal(ctx: any, at: Vector3, normal: Vector3): (BasePart, BasePart)
	local face = CFrame.lookAt(at, at + normal) * CFrame.Angles(0, math.rad(90), 0) -- cylinder axis = normal
	local rim = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 0.1, 0.1),
		Color = PORTAL_RIM,
		Material = Enum.Material.Neon,
		CFrame = face,
	}, ctx.folder)
	local core = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 0.1, 0.1),
		Color = PORTAL_CORE,
		Material = Enum.Material.Neon,
		CFrame = face,
	}, ctx.folder)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(PORTAL_RIM, Color3.fromRGB(220, 200, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Rate = if ctx.reducedMotion then 15 else 60
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = rim
	local light = Instance.new("PointLight")
	light.Color = PORTAL_RIM
	light.Range = 18
	light.Brightness = 3
	light.Parent = rim
	return rim, core
end

-- The victim crumbles: the whole body fades and sheds dust together (each part a touch out of step,
-- so it reads as crumbling rather than a plain fade).
local function crumble(ctx: any, model: Model, startIn: number, length: number)
	local parts: { BasePart } = {}
	local lags: { [BasePart]: number } = {}
	local rng = Random.new()
	local each = length * 0.85 -- one part's own fade; the small random offsets cover the rest
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			table.insert(parts, d)
			lags[d] = rng:NextNumber(0, length - each)
		end
	end
	-- Mesh heads (and some mesh limbs) paint only the face into the texture. The rest is see-through
	-- alpha that shows the part's colour only while the part is opaque. Once it fades, only the eyes
	-- would be left floating. A plain untextured copy just inside supplies the skin, and fades in step.
	for i = #parts, 1, -1 do
		local p = parts[i]
		if p:IsA("MeshPart") and p.TextureID ~= "" then
			local skin = p:Clone()
			skin:ClearAllChildren()
			skin.Name = "SkinShell"
			skin.TextureID = ""
			skin.Size = p.Size * 0.98
			skin.CFrame = p.CFrame
			skin.Anchored = false
			skin.CanCollide = false
			skin.CanQuery = false
			skin.CanTouch = false
			skin.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = p
			weld.Part1 = skin
			weld.Parent = skin
			skin.Parent = p
			table.insert(parts, skin)
			lags[skin] = lags[p]
		end
	end
	local emitters: { [BasePart]: ParticleEmitter } = {}
	for _, p in parts do
		if p.Name == "SkinShell" then
			continue -- its owner already sheds the dust
		end
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = SMOKE
		dust.Color = ColorSequence.new(DUST)
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.05) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime = NumberRange.new(1, 1.8)
		dust.Speed = NumberRange.new(1, 3)
		dust.SpreadAngle = Vector2.new(35, 35)
		dust.Acceleration = Vector3.new(2.5, 1.2, 0) -- drifting off on the breeze
		dust.Drag = 1.5
		dust.Rate = 0
		dust.Parent = p
		emitters[p] = dust
	end
	local start = os.clock() + startIn
	local conn
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local t = os.clock() - start
		if t < 0 then
			return
		end
		local alive = false
		for _, p in parts do
			if not p.Parent then
				continue
			end
			local a = math.clamp((t - lags[p]) / each, 0, 1)
			p.Transparency = a
			for _, dec in p:GetChildren() do
				if dec:IsA("Decal") then
					dec.Transparency = a
				end
			end
			local dust = emitters[p]
			if dust then
				dust.Rate = if a > 0 and a < 1 then (if ctx.reducedMotion then 12 else 40) else 0
			end
			alive = alive or a < 1
		end
		if not alive then
			conn:Disconnect()
		end
	end)
	task.delay(startIn + length + 2, function()
		conn:Disconnect()
	end)
end

return {
	Id = "DestinyArrives",
	Name = "Destiny Arrives",
	Duration = 5,
	-- nobody is launched: the victim fades away on a local copy
	Stage = { Launch = false },
	play = function(ctx: any)
		local t0 = os.clock()
		local cam = ctx.camera
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		local avatar = ReplicatedStorage:FindFirstChild(Config.Finisher.DestinyTemplateName)
		local template = avatar or ReplicatedStorage:FindFirstChild(Config.Practice.TemplateName)
		if not killerRoot or not victimRoot or not template then
			task.wait(ctx.duration)
			return
		end

		-- geometry: the winner faces the victim across the net
		local K = killerRoot.Position
		local V = victimRoot.Position
		local f = Vector3.new(V.X - K.X, 0, V.Z - K.Z)
		f = if f.Magnitude > 0.1 then f.Unit else Vector3.zAxis
		local side = f:Cross(Vector3.yAxis)
		local ground = K.Y - 3

		-- the warlord, standing inside the portal to begin with
		local giant = ctx.standIn(template)
		local groot = giant and giant:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not giant or not groot then
			task.wait(ctx.duration)
			return
		end
		pcall(function()
			giant:ScaleTo(SCALE)
		end)
		if avatar then
			snapGlow(giant) -- the avatar keeps its own look
		else
			dress(giant)
		end
		-- the portal opens behind and to the right of the winner, facing the way the winner faces, and
		-- he walks straight out of it to stand at the winner's side
		local P = K + side * 3.6 - f * 3.5
		local S = K + side * 3.6 + f * 0.6
		local walk = f
		-- root height: stand his feet on the court
		-- measured on the template: the stand-in's pinned accessories only catch up with the body on the
		-- next frame, so measuring the copy now would count the gauntlet still sitting where it was cloned
		local box, size = template:GetBoundingBox()
		local troot = template:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hip = (if troot then troot.Position.Y - (box.Position.Y - size.Y / 2) else size.Y / 2) * SCALE
		size *= SCALE
		local function rootAt(pos: Vector3, facing: Vector3): CFrame
			local at = Vector3.new(pos.X, ground + hip, pos.Z)
			return CFrame.lookAt(at, at + facing)
		end
		local startAt = P - walk * 2.2 -- far enough back that all of him starts behind the portal
		groot.CFrame = rootAt(startAt, walk)
		-- he only exists on this side of the portal: any part still behind its surface is hidden, so
		-- he steps out of it rather than standing there before it opens
		local revealParts: { BasePart } = {}
		local revealDecals: { [Decal]: number } = {}
		for _, d in giant:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				table.insert(revealParts, d)
			elseif d:IsA("Decal") then
				revealDecals[d] = d.Transparency
			end
		end
		local function reveal()
			for _, p in revealParts do
				local through = (p.Position - P):Dot(walk) > 0
				p.LocalTransparencyModifier = if through then 0 else 1
			end
			for dec, rest in revealDecals do
				local on = dec.Parent and dec.Parent:IsA("BasePart") and (dec.Parent.Position - P):Dot(walk) > 0
				dec.Transparency = if on then rest else 1
			end
		end
		reveal()

		-- he idles inside the portal, walks out, and idles again beside the winner
		local idle = loadTrack(giant, IDLE_ANIM)
		local walking = loadTrack(giant, WALK_ANIM)
		if idle then
			idle.Looped = true
			idle:Play(0)
		end

		local portal, core = makePortal(ctx, Vector3.new(P.X, ground + hip * 1.25, P.Z), walk)
		local portalD = size.Y * 1.25
		ctx.sound("DestinyPortal", P)

		-- the winner turns to watch; the victim's copy waits for its moment
		local puppet = ctx.standIn(ctx.victim)
		local proot = puppet and puppet:FindFirstChild("HumanoidRootPart") :: BasePart?
		if proot then
			proot.CFrame = CFrame.lookAt(V, V - f)
		end
		ctx.hide(ctx.victim)

		-- Shot 1: wide, from the victim's side of the court ------------------------------------------
		local camA = K + f * 15 - side * 3 + Vector3.new(0, 4.5, 0)
		local camB = K + f * 12.5 - side * 1.5 + Vector3.new(0, 4, 0)
		local stepCount = 0
		ctx.runFor(SHOT2, function(alpha: number)
			local t = alpha * SHOT2
			-- the portal opens
			local open = math.clamp(t / 0.6, 0, 1)
			open = 1 - (1 - open) ^ 3
			local d = math.max(portalD * open, 0.1)
			portal.Size = Vector3.new(0.2, d * 1.06, d * 1.06)
			core.Size = Vector3.new(0.3, d * 0.92, d * 0.92)
			-- he walks out: 0.7 to 1.9
			local w = math.clamp((t - 0.7) / 1.2, 0, 1)
			local pos = startAt:Lerp(S, w)
			groot.CFrame = rootAt(pos, walk)
			reveal()
			if w > 0 and w < 1 then
				if walking and not walking.IsPlaying then
					walking.Looped = true
					walking:Play(0.2)
					walking:AdjustSpeed(0.4) -- matched to his pace (the animation is made for 16 studs/s)
				end
				-- a footfall thud and a small shake on each of his three steps
				local n = math.floor(w * 3)
				if n >= stepCount then
					stepCount = n + 1
					ctx.sound("DestinyStep", Vector3.new(pos.X, ground, pos.Z))
					ctx.fx.shake(if ctx.reducedMotion then 0.1 else 0.35)
				end
			elseif w >= 1 and walking and walking.IsPlaying then
				walking:Stop(0.25)
			end
			local e = ctx.ease(t / SHOT2)
			cam.CFrame = CFrame.lookAt(camA:Lerp(camB, e), (K + P) / 2 + Vector3.new(0, size.Y * 0.45, 0))
		end)

		-- Shot 2: close on the raised hand, the snap ---------------------------------------------------
		groot.CFrame = rootAt(S, f)
		for _, p in revealParts do
			p.LocalTransparencyModifier = 0
		end
		for dec, rest in revealDecals do
			dec.Transparency = rest
		end
		if walking then
			walking:Stop(0.1)
		end
		ctx.pose(giant, "SnapReady", 0.3) -- the pose holds the arms and head over the idle
		local hand = giant:FindFirstChild("LeftHand") :: BasePart?
		local head = giant:FindFirstChild("Head") :: BasePart?
		local snapped = false
		ctx.runFor(SHOT3 - SHOT2, function(alpha: number)
			local t = SHOT2 + alpha * (SHOT3 - SHOT2)
			local focus = if hand then hand.Position else S + Vector3.new(0, size.Y * 0.7, 0)
			local faceAt = if head then head.Position else focus
			local look = focus:Lerp(faceAt, 0.35)
			local camPos = look + f * (5 - alpha * 1) - side * 1.6 + Vector3.new(0, -0.4, 0) -- off his left, by the gauntlet
			cam.CFrame = CFrame.lookAt(camPos, look)
			if not snapped and t >= SNAP then
				snapped = true
				ctx.pose(giant, "Snap", 0.05)
				ctx.sound("DestinySnap")
				if hand then
					local glow = hand:FindFirstChild("SnapGlow") :: PointLight?
					if glow then
						glow.Range = 14
					end
					ctx.fx.flash(hand.Position, SNAP_FLASH, 4)
				end
				if not ctx.reducedMotion then
					ctx.fx.screenFlash(Color3.new(1, 1, 1), 0.6, 0.12)
				end
			end
		end)
		-- the portal closes behind him
		task.spawn(function()
			local from = portal.Size
			local fromCore = core.Size
			ctx.runFor(0.5, function(a: number)
				portal.Size = from:Lerp(Vector3.new(0.2, 0.1, 0.1), a)
				core.Size = fromCore:Lerp(Vector3.new(0.3, 0.1, 0.1), a)
			end)
			portal.Transparency = 1
			core.Transparency = 1
		end)

		-- Shot 3: the victim fades away ---------------------------------------------------------------
		if puppet then
			crumble(ctx, puppet, 0.25, 1.5)
		end
		ctx.sound("DestinyDust")
		-- a still camera: nothing moves but the dust
		cam.CFrame = CFrame.lookAt(V - f * 7 + side * 1.2 + Vector3.new(0, 2, 0), V + Vector3.new(0, 0.6, 0))
		task.wait(math.max(0.3, ctx.duration - (os.clock() - t0)))
	end,
}
