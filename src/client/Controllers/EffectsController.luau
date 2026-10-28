--!strict
-- Game feel: hit impacts (white flash on the target, spark burst, shockwave ring, comic pop text,
-- layered hit sound, camera kick), eliminations (screen flash + "ELIMINATED <name>" for the
-- eliminator; white rim flash, KO light beam and void splash for everyone) and the ambient match
-- sounds. Respects the
-- reduced-motion and camera-shake settings. All visuals are original placeholder geometry.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallDefinitions = require(Shared.BallDefinitions)
local ArenaLayout = require(Shared.ArenaLayout)
local Sounds = require(Shared.Sounds)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)
local GraphicsController = require(script.Parent.GraphicsController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer

local EffectsController = {}

local shake = 0
local fovKick = 0
local fxFolder: Folder
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local POPS = { "POW!", "BAM!", "WHAM!", "BONK!", "SMACK!", "BOOM!" }

local function reduced(): boolean
	return HUDController.settings.ReducedMotion
end

function EffectsController.addShake(amount: number)
	if not HUDController.settings.CameraShake or reduced() then
		return
	end
	shake = math.min(Config.Camera.MaxShake, shake + amount)
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tw =
		TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function anchorAt(pos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	return a
end

-- One-shot particle burst.
local function burst(pos: Vector3, color: Color3, count: number, speed: number, size: number)
	local a = anchorAt(pos)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 6
	e.Rate = 0
	e.Parent = a
	e:Emit(GraphicsController.particles(count))
	task.delay(1, function()
		a:Destroy()
	end)
end

-- Expanding glowing ring facing along `normal`.
local function shockwave(pos: Vector3, normal: Vector3, color: Color3, maxSize: number, duration: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.2, 1, 1)
	local n = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	-- a cylinder's axis is its X axis: point X along the normal
	ring.CFrame = CFrame.lookAt(pos, pos + n) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = fxFolder
	tween(ring, duration, { Size = Vector3.new(0.05, maxSize, maxSize), Transparency = 1 })
	task.delay(duration + 0.05, function()
		ring:Destroy()
	end)
end

local function flashSphere(pos: Vector3, color: Color3, size: number)
	local s = Instance.new("Part")
	s.Shape = Enum.PartType.Ball
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Material = Enum.Material.Neon
	s.Color = color
	s.Size = Vector3.one
	s.Position = pos
	s.Transparency = 0
	s.Parent = fxFolder
	tween(s, 0.22, { Size = Vector3.one * size, Transparency = 1 })
	task.delay(0.25, function()
		s:Destroy()
	end)
end

-- Comic pop text above the impact ("POW!").
local function popText(pos: Vector3, color: Color3)
	-- sits above the impact flash; depth-tested (AlwaysOnTop billboards proved unreliable to render)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one * 0.2
	a.Position = pos + Vector3.new(0, 4.5, 0)
	a.Parent = fxFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 74)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 150
	bb.Adornee = a
	bb.Parent = player:FindFirstChildOfClass("PlayerGui") or a
	a.Destroying:Connect(function()
		bb:Destroy()
	end)
	local l = Theme.label(bb, {
		Size = UDim2.fromScale(1, 1),
		Text = POPS[math.random(1, #POPS)],
		Rotation = math.random(-14, 14),
	}, 4)
	Theme.gradient(l, Color3.fromRGB(255, 250, 200), color)
	Theme.pop(l, 0.3, 0.25)
	tween(bb, 0.6, { StudsOffset = Vector3.new(0, 2, 0) })
	task.delay(0.45, function()
		tween(l, 0.2, { TextTransparency = 1 })
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			tween(st, 0.2, { Transparency = 1 })
		end
	end)
	task.delay(0.8, function()
		a:Destroy()
	end)
end

-- Flash a character pure white for a beat.
local function whiteFlash(model: Instance?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.OutlineColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = fxFolder
	task.delay(0.08, function()
		tween(h, 0.25, { FillTransparency = 1, OutlineTransparency = 1 })
	end)
	task.delay(0.4, function()
		h:Destroy()
	end)
end

-- Shared with finisher cutscenes (FinisherController's ctx.fx).
EffectsController.burst = burst
EffectsController.shockwave = shockwave
EffectsController.flashSphere = flashSphere

-- Arena rims: flash white and brighter, then settle back to their team color over `duration`
-- (team = nil flashes every rim). The rim bar, its light curtain and its glow all go white.
local rimBase: { [SurfaceGui]: number } = {}
function EffectsController.pulseRims(team: string?, strength: number, duration: number)
	local white = Color3.new(1, 1, 1)
	for _, rim in CollectionService:GetTagged("CourtRim") do
		if rim:IsA("BasePart") and (team == nil or rim:GetAttribute("Team") == team) and rim.Transparency < 1 then
			local baseColor = rim:GetAttribute("RimColor")
			local hasColor = typeof(baseColor) == "Color3"
			for _, d in rim:GetDescendants() do
				if d:IsA("SurfaceGui") and d.Enabled then
					local base = rimBase[d] or d.Brightness
					rimBase[d] = base
					d.Brightness = base * strength
					tween(d, duration, { Brightness = base }, Enum.EasingStyle.Sine)
				elseif hasColor and d:IsA("Frame") then
					d.BackgroundColor3 = white
					tween(d, duration, { BackgroundColor3 = baseColor }, Enum.EasingStyle.Sine)
				elseif hasColor and d:IsA("SurfaceLight") then
					d.Color = white
					tween(d, duration, { Color = baseColor }, Enum.EasingStyle.Sine)
				end
			end
			if hasColor then
				rim.Color = white
				tween(rim, duration, { Color = baseColor }, Enum.EasingStyle.Sine)
			end
		end
	end
end

-- Where a KO beam rises: off the court, just past the side the player went over. `edge` is the last
-- spot they stood on; the nearest boundary of their half (a side line, or the back line) picks the
-- side, and the beam starts `push` studs out from it, square to that side.
local function koBeamBase(edge: Vector3, push: number): Vector3
	local o = Config.Arena.Origin
	local rel = edge - o
	local steps = tonumber(Net.MatchState:GetAttribute("OvertimeSteps")) or 0
	local hw = ArenaLayout.safeHalfWidth(steps)
	local hl = ArenaLayout.HalfLength
	local toSide = hw - math.abs(rel.X)
	local toBack = hl - math.abs(rel.Z)
	local x, z
	if toSide <= toBack then
		local s = if rel.X >= 0 then 1 else -1
		x, z = s * (hw + push), math.clamp(rel.Z, -hl, hl)
	else
		local s = if rel.Z >= 0 then 1 else -1
		x, z = math.clamp(rel.X, -hw, hw), s * (hl + push)
	end
	return Vector3.new(o.X + x, o.Y - 14, o.Z + z)
end

-- Super Smash Bros-style KO beam: a near-white column of light that shoots up from below the
-- court edge, flares, and breaks into frayed streaks at the top before fading. Built from Beams
-- (camera-facing ribbons that taper and fade along their length), so it reads as light, not a tube.
local WHITE = Color3.new(1, 1, 1)
local function koBeam(base: Vector3, color: Color3)
	local soft = reduced()
	local height = if soft then 90 else 150
	local life = if soft then 0.55 else 0.85
	local tint = color:Lerp(WHITE, 0.78) -- only a hint of the team color
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(base)
	holder.Parent = fxFolder
	local rng = Random.new()
	-- each streak: a start height and end height (fractions of the full beam), a sideways drift at
	-- its tip (the fray), base/tip widths, and how opaque it is
	type Streak = {
		beam: Beam,
		a0: Attachment,
		a1: Attachment,
		from: number,
		to: number,
		drift: Vector3,
		w0: number,
		w1: number,
		alpha: number,
	}
	local streaks: { Streak } = {}
	local function streak(from: number, to: number, drift: Vector3, w0: number, w1: number, col: Color3, alpha: number)
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 4
		b.Color = ColorSequence.new(col)
		b.Segments = 2
		b.Parent = holder
		table.insert(
			streaks,
			{ beam = b, a0 = a0, a1 = a1, from = from, to = to, drift = drift, w0 = w0, w1 = w1, alpha = alpha }
		)
	end
	local scale = if soft then 0.65 else 1
	-- soft tinted glow, the white body and a hot core
	streak(0, 0.9, Vector3.zero, 16 * scale, 7 * scale, tint, 0.55)
	streak(0, 0.95, Vector3.zero, 7 * scale, 3 * scale, WHITE, 0.05)
	streak(0, 0.7, Vector3.zero, 3 * scale, 1.2 * scale, WHITE, 0)
	-- the fray: thin streaks peeling off the top at different heights, spreading out
	for _ = 1, (if soft then 6 else 13) do
		local ang = rng:NextNumber(0, math.pi * 2)
		local spread = rng:NextNumber(4, 14) * scale
		local drift = Vector3.new(math.cos(ang) * spread, 0, math.sin(ang) * spread)
		streak(
			rng:NextNumber(0.35, 0.65),
			rng:NextNumber(0.85, 1.25),
			drift,
			rng:NextNumber(0.8, 2.6) * scale,
			0,
			if rng:NextNumber() < 0.3 then tint else WHITE,
			rng:NextNumber(0, 0.3)
		)
	end
	local light = Instance.new("PointLight")
	light.Color = tint
	light.Range = 50
	light.Brightness = 8
	light.Parent = holder
	-- shoot up fast and flare, then thin out and fade (streak tips always fade to nothing)
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / life
		if t >= 1 then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local rise = 1 - (1 - math.min(1, t / 0.16)) ^ 3 -- full height in the first ~16%
		local flare = if t < 0.12 then t / 0.12 else 1 - ((t - 0.12) / 0.88) ^ 1.5
		local fade = t ^ 1.6
		for _, s in streaks do
			local y0 = height * s.from * rise
			local y1 = height * s.to * rise
			s.a0.Position = Vector3.new(0, y0, 0)
			s.a1.Position = Vector3.new(0, y1, 0) + s.drift * rise
			s.beam.Width0 = math.max(0.05, s.w0 * flare)
			s.beam.Width1 = math.max(0, s.w1 * flare)
			local a = s.alpha + (1 - s.alpha) * fade
			s.beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, a),
				NumberSequenceKeypoint.new(0.6, a + (1 - a) * 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
		light.Brightness = 8 * (1 - t)
	end)
	-- a bright pop at the base
	flashSphere(base + Vector3.new(0, 8, 0), WHITE, if soft then 6 else 11)
	if not soft then
		burst(base + Vector3.new(0, 8, 0), tint, 34, 70, 1.4)
	end
end
EffectsController.koBeam = koBeam

local function onImpact(d: any)
	if typeof(d.position) ~= "Vector3" then
		return
	end
	local pos = d.position :: Vector3
	if d.kind == "Hit" then
		local def = BallDefinitions.get(d.ballType or "Standard")
		local dir = if typeof(d.direction) == "Vector3" then d.direction :: Vector3 else Vector3.zAxis
		whiteFlash(d.targetModel)
		burst(pos, def.Color, if reduced() then 10 else 28, 45, 0.9)
		flashSphere(pos, Color3.new(1, 1, 1), 7)
		if not reduced() then
			shockwave(pos, dir, def.Color:Lerp(Color3.new(1, 1, 1), 0.5), 14, 0.3)
			popText(pos, def.Color)
		end
		SoundController.play(if d.ballType == "Heavy" then "HitHeavy" else "Hit", pos)
		if d.target == player then
			EffectsController.addShake(0.6)
			HUDController.vignette(0.55, 0.45)
			fovKick = 6
		elseif d.thrower == player then
			HUDController.hitmarker()
			EffectsController.addShake(0.15)
			fovKick = 3
		else
			local cam = Workspace.CurrentCamera
			if (cam.CFrame.Position - pos).Magnitude < 40 then
				EffectsController.addShake(0.12)
			end
		end
	elseif d.kind == "Catch" then
		burst(pos, Color3.fromRGB(120, 255, 140), 18, 25, 0.7)
		if not reduced() then
			shockwave(pos, Vector3.yAxis, Color3.fromRGB(140, 255, 160), 9, 0.25)
		end
		SoundController.play("Catch", pos)
	end
end

-- names go inside rich text; keep < > & in them from being read as markup
local function escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function onElimination(d: any)
	local pos = if typeof(d.position) == "Vector3" then d.position :: Vector3 else nil
	local edge = if typeof(d.edge) == "Vector3" then d.edge :: Vector3 else pos
	-- everyone: every rim flashes white, a KO beam shoots up where they went out, plus a splash
	EffectsController.pulseRims(nil, 4, 0.9)
	if edge then
		local victimColor = if d.victimTeam and Config.Teams[d.victimTeam]
			then Config.Teams[d.victimTeam].Color
			else Color3.new(1, 1, 1)
		koBeam(koBeamBase(edge, 6), victimColor)
		local splash = Vector3.new(edge.X, Config.Arena.Origin.Y - 6, edge.Z)
		burst(splash, Color3.fromRGB(190, 120, 255), if reduced() then 12 else 40, 35, 1.2)
		if not reduced() then
			shockwave(splash, Vector3.yAxis, Color3.fromRGB(200, 140, 255), 22, 0.5)
		end
		SoundController.play("VoidFall", splash)
	end
	-- an enemy went out: the crowd cheers for your team (one of the cheers at random)
	local myTeam = player:GetAttribute("Team")
	if type(myTeam) == "string" and myTeam ~= "" and d.victimTeam and d.victimTeam ~= myTeam then
		if #Sounds.Cheers > 0 then
			SoundController.play(Sounds.Cheers[math.random(1, #Sounds.Cheers)])
		end
	end
	-- the eliminator: ELIMINATION! + screen flash + every rim flares
	if d.killer == player then
		local teamColor = if d.killerTeam and Config.Teams[d.killerTeam]
			then Config.Teams[d.killerTeam].Color
			else Color3.new(1, 1, 1)
		HUDController.flash(Color3.new(1, 1, 1), 0.55, 0.12)
		task.delay(0.08, function()
			HUDController.flash(teamColor, 0.35, 0.5)
		end)
		local victimColor = if d.victimTeam and Config.Teams[d.victimTeam]
			then Config.Teams[d.victimTeam].Color
			else Color3.new(1, 1, 1)
		-- "ELIMINATED <name>", the name in the victim's team color
		local text = ('<font color="#FFE15A">ELIMINATED</font> <font color="#%s">%s</font>'):format(
			victimColor:ToHex(),
			escapeRich(tostring(d.victimName or "?"))
		)
		HUDController.banner(text, nil, 1.4, "Elimination", { scale = 0.8, rich = true })
		if type(d.coins) == "number" and d.coins > 0 then
			task.delay(0.25, function()
				HUDController.coinPop(d.coins)
			end)
		end
		EffectsController.addShake(0.35)
		fovKick = 8
	end
end

-- Client-side hits (hub practice dummy) get the same impact effects as server hits.
function EffectsController.localImpact(d: any)
	onImpact(d)
end

-- Studio UI gallery hooks: replay effects with fake event data.
function EffectsController.previewHit(pos: Vector3, model: Instance?)
	onImpact({ kind = "Hit", position = pos, ballType = "Standard", direction = Vector3.zAxis, targetModel = model })
end

function EffectsController.previewElimination(team: string)
	onElimination({
		victimName = "Bot",
		victimTeam = if team == "Red" then "Blue" else "Red",
		killer = player,
		killerTeam = team,
		coins = 25,
	})
end

function EffectsController.init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "FX"
	fxFolder.Parent = Workspace
end

function EffectsController.start()
	Net.on("Impact", onImpact)
	Net.on("Elimination", onElimination)
	Net.on("Sound", function(d)
		if type(d.cue) == "string" then
			SoundController.play(d.cue, if typeof(d.position) == "Vector3" then d.position else nil)
		end
	end)
	Net.on("BallLaunched", function(d)
		if typeof(d.origin) == "Vector3" then
			SoundController.play("Throw", d.origin, if d.thrower == player then 1 else 0.7)
		end
	end)
	Net.on("DodgeAccepted", function()
		SoundController.play("Dodge")
	end)
	Net.on("Finisher", function()
		SoundController.play("Finisher")
	end)

	-- state-driven cues: pickups, jail, escapes, court strips dropping
	local lastHeld = ""
	local lastStatus = player:GetAttribute("Status")
	local lastSteps = 0
	RunService.Heartbeat:Connect(function()
		local held = player:GetAttribute("HeldBall")
		held = if type(held) == "string" then held else ""
		if held ~= "" and lastHeld == "" then
			SoundController.play("Pickup")
		end
		lastHeld = held
		local status = player:GetAttribute("Status")
		if status ~= lastStatus then
			if status == "Jailed" then
				task.delay(Config.Jail.RespawnDelay, function()
					if player:GetAttribute("Status") == "Jailed" then
						SoundController.play("Jail")
					end
				end)
			elseif status == "Returning" then
				SoundController.play("JailEscape")
			end
			lastStatus = status
		end
		local rawSteps = Net.MatchState:GetAttribute("OvertimeSteps")
		local steps: number = if type(rawSteps) == "number" then rawSteps else 0
		if steps > lastSteps then
			SoundController.play("StripDrop")
			EffectsController.addShake(0.2)
		end
		lastSteps = steps
	end)

	-- camera: capped shake + quick FOV kick, applied after the default camera
	local baseFov = 70
	RunService:BindToRenderStep("RD_Shake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local cam = Workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			if fovKick > 0.01 and not reduced() then
				cam.FieldOfView = baseFov + fovKick
				fovKick = math.max(0, fovKick - dt * 40)
			elseif cam.FieldOfView ~= baseFov and fovKick <= 0.01 then
				cam.FieldOfView = baseFov
			end
		end
		if shake <= 0.001 then
			shake = 0
			return
		end
		local s = shake
		cam.CFrame = cam.CFrame
			* CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * s * 0.03)
		shake = math.max(0, shake - Config.Camera.ShakeDecay * dt * shake - dt * 0.2)
	end)
end

return EffectsController
