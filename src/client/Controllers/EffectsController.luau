--!strict
-- Game feel: hit impacts (white flash on the target, spark burst, shockwave ring, comic pop text,
-- layered hit sound, camera kick), eliminations (screen flash + "ELIMINATION!" for the eliminator,
-- arena rim pulse and void splash for everyone) and the ambient match sounds. Respects the
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
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)
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
	e:Emit(count)
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

-- Arena rims: pulse brighter for a second (team = nil pulses every rim).
local rimBase: { [SurfaceGui]: number } = {}
function EffectsController.pulseRims(team: string?, strength: number, duration: number)
	for _, rim in CollectionService:GetTagged("CourtRim") do
		if rim:IsA("BasePart") and (team == nil or rim:GetAttribute("Team") == team) and rim.Transparency < 1 then
			for _, sg in rim:GetDescendants() do
				if sg:IsA("SurfaceGui") and sg.Enabled then
					local base = rimBase[sg] or sg.Brightness
					rimBase[sg] = base
					sg.Brightness = base * strength
					tween(sg, duration, { Brightness = base }, Enum.EasingStyle.Sine)
				end
			end
			local baseColor = rim:GetAttribute("RimColor")
			if typeof(baseColor) == "Color3" then
				rim.Color = Color3.new(1, 1, 1)
				tween(rim, duration, { Color = baseColor })
			end
		end
	end
end

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
	-- everyone: the victim's side of the arena glows hot for a second, a splash where they went down
	EffectsController.pulseRims(d.victimTeam, 3, 1)
	if edge then
		local splash = Vector3.new(edge.X, Config.Arena.Origin.Y - 6, edge.Z)
		burst(splash, Color3.fromRGB(190, 120, 255), if reduced() then 12 else 40, 35, 1.2)
		if not reduced() then
			shockwave(splash, Vector3.yAxis, Color3.fromRGB(200, 140, 255), 22, 0.5)
		end
		SoundController.play("VoidFall", splash)
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
		EffectsController.pulseRims(nil, 5, 1)
		EffectsController.addShake(0.35)
		fovKick = 8
	end
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
	Net.on("ShopResult", function(d)
		-- purchases play their sting with the UNLOCKED banner
		if d.ok and d.equip then
			SoundController.play("UIClick")
		elseif not d.ok then
			SoundController.play("UIError")
		end
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
