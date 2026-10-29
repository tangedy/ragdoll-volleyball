--!strict
-- Patterned and model ball skins, drawn on any Standard ball carrying a "SkinPattern" or "SkinModel"
-- attribute: BallService sets them on server balls, BallVisualController on flying visuals and
-- PracticeController on practice balls. All of them are cheap:
--   Zebra   - a few thin black bands welded around the white ball (built once, no per-frame work)
--   Rainbow - the ball's color steps through the hues (one Color write per rainbow ball per frame)
--   Model   - (Catalog Data.Model) a BallModels look welded on in place of the sphere, built once.
--             The sphere is hidden with a zero-scale mesh, never through Transparency or
--             LocalTransparencyModifier: those stay the ball's own "hidden" switches (a visual
--             flying in its place, a practice ball gone), and the model follows them.
-- Effect skins' lights and emitters (tagged "SkinFX" by BallModels) follow the player's settings: lights
-- show at Config.Visuals.NeonIntensity and go off in performance mode (as the scenery's do), emitters
-- keep Config.Graphics.LowParticleScale of their rate there, and both stop while the ball is hidden.
-- Legendary skins (Data.Variants) show the form in the "SkinVariant" attribute (picked per pickup by
-- the server, or by PracticeController); a Glitched form's parts are jittered GLITCH_HZ times a second
-- by moving their Welds (nothing is created per frame). The holder sees a brief glow on each swap.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallDefinitions = require(Shared:WaitForChild("BallDefinitions"))
local BallModels = require(Shared:WaitForChild("BallModels"))
local Config = require(Shared:WaitForChild("Config"))
local GraphicsController = require(script.Parent.GraphicsController)
local HUDController = require(script.Parent.HUDController)
local Net = require(script.Parent.Net)

local BallSkinController = {}

local STRIPES = "RD_Zebra"
local STRIPE_COLOR = Color3.fromRGB(25, 25, 28)
-- each band: its offset from the center along its axis and its width (both x the ball radius) and
-- the tilt of its axis, so the bands fan out like a zebra's instead of lying parallel
local BANDS = {
	{ h = -0.72, w = 0.14, tilt = -14 },
	{ h = -0.36, w = 0.2, tilt = 8 },
	{ h = 0.02, w = 0.13, tilt = -6 },
	{ h = 0.38, w = 0.19, tilt = 12 },
	{ h = 0.74, w = 0.12, tilt = -10 },
}
local RAINBOW_SPEED = 0.35 -- hue cycles a second
local STANDARD = BallDefinitions.get("Standard")
local HIDE = "RD_HideSphere"
local GLITCH_HZ = 12
-- the glow on the holder's screen when a Legendary skin swaps form
local FORM_GLOW = {
	Nice = Color3.fromRGB(255, 226, 140),
	Evil = Color3.fromRGB(200, 20, 30),
	Glitched = Color3.fromRGB(60, 230, 255),
}

type Glitch = { weld: Weld, part: BasePart, kind: string, base: CFrame }

-- `key`: "Zebra" / "Rainbow", or "Model:<name>:<form>" for a model skin
type Skinned = {
	glitch: { Glitch }?,
	key: string,
	pattern: string?,
	decor: Model?,
	hide: SpecialMesh?,
	last: Color3?,
	sync: (() -> ())?, -- re-applies hidden state and effect settings to the decor
	conns: { RBXScriptConnection },
}
local skinned: { [BasePart]: Skinned } = {}

local function isStandard(ball: BasePart): boolean
	local t = ball:GetAttribute("BallType")
	return t == nil or t == "Standard"
end

-- Thin disc bands around the ball, each sized to stick out just past the sphere at its offset, so
-- only its rim shows as a stripe. Welded and massless, so they follow every move for free.
local function makeStripes(ball: BasePart): Model
	local model = Instance.new("Model")
	model.Name = STRIPES
	local r = ball.Size.X / 2
	for _, band in BANDS do
		local h, w = band.h * r, band.w * r
		local inner = math.max(0, math.abs(h) - w / 2) -- the band's face nearest the center
		local radius = math.sqrt(math.max(r * r - inner * inner, 0)) + r * 0.03
		local p = Instance.new("Part")
		p.Name = "Stripe"
		p.Shape = Enum.PartType.Cylinder -- its axis is X
		p.Size = Vector3.new(w, radius * 2, radius * 2)
		p.CFrame = ball.CFrame * CFrame.Angles(0, 0, math.rad(band.tilt)) * CFrame.new(h, 0, 0)
		p.Color = STRIPE_COLOR
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ball
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	model.Parent = ball
	return model
end

local function unskin(ball: BasePart)
	local s = skinned[ball]
	if not s then
		return
	end
	skinned[ball] = nil
	for _, c in s.conns do
		c:Disconnect()
	end
	if s.decor then
		s.decor:Destroy()
	end
	if s.hide then
		s.hide:Destroy()
	end
	-- the rainbow's last hue is only ours: put the plain look back unless something set a new color
	if s.last and ball.Color == s.last then
		ball.Color = STANDARD.Color
	end
end

-- The sphere stays (its physics, size and outline are the ball's) but draws nothing.
local function hideSphere(ball: BasePart): SpecialMesh
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = HIDE
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.one * 0.001
	mesh.Parent = ball
	return mesh
end

-- A skin's lights and emitters for the ball's visibility and the player's settings.
local function applyFx(decor: Model, shown: boolean)
	local low = GraphicsController.low
	for _, d in decor:GetDescendants() do
		if not d:GetAttribute("SkinFX") then
			continue
		end
		if d:IsA("PointLight") then
			d.Brightness = (tonumber(d:GetAttribute("FullBrightness")) or 1) * Config.Visuals.NeonIntensity
			d.Enabled = shown and not low
		elseif d:IsA("ParticleEmitter") then
			local rate = tonumber(d:GetAttribute("FullRate")) or d.Rate
			d.Rate = if low then rate * Config.Graphics.LowParticleScale else rate
			d.Enabled = shown
		end
	end
end

local function skin(ball: BasePart, key: string, pattern: string?, model: string?, form: string?)
	local s: Skinned = { key = key, pattern = pattern, conns = {} }
	skinned[ball] = s
	if model then
		local decor = BallModels.build(model, ball.CFrame, ball.Size.X / 2, nil, form)
		if decor then
			BallModels.weld(decor, ball)
			decor.Parent = ball
			s.decor = decor
			s.hide = hideSphere(ball)
			local glitch: { Glitch } = {}
			for _, p in decor:GetChildren() do
				local w = p:FindFirstChild("GlitchWeld")
				local base = p:GetAttribute("GlitchBase")
				if p:IsA("BasePart") and w and w:IsA("Weld") and typeof(base) == "CFrame" then
					table.insert(glitch, { weld = w, part = p, kind = tostring(p:GetAttribute("Glitch")), base = base })
				end
			end
			s.glitch = if #glitch > 0 then glitch else nil
		end
	elseif pattern == "Zebra" then
		s.decor = makeStripes(ball)
	end
	local decor = s.decor
	if decor then
		local alpha: { [BasePart]: number } = {} -- each part's own see-through (the glitch copies)
		for _, p in decor:GetDescendants() do
			if p:IsA("BasePart") then
				alpha[p] = p.Transparency
			end
		end
		local function syncHidden()
			-- the ball is hidden locally while its client-drawn visual flies: hide its look with it
			for p, a in alpha do
				p.LocalTransparencyModifier = ball.LocalTransparencyModifier
				p.Transparency = math.max(a, ball.Transparency)
			end
			applyFx(decor, ball.LocalTransparencyModifier < 1 and ball.Transparency < 1)
		end
		s.sync = syncHidden
		syncHidden()
		table.insert(s.conns, ball:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(syncHidden))
		table.insert(s.conns, ball:GetPropertyChangedSignal("Transparency"):Connect(syncHidden))
	end
	table.insert(
		s.conns,
		ball.AncestryChanged:Connect(function()
			if ball.Parent == nil then
				unskin(ball)
			end
		end)
	)
end

local function refresh(ball: BasePart)
	local pattern = ball:GetAttribute("SkinPattern")
	local model = ball:GetAttribute("SkinModel")
	local form = ball:GetAttribute("SkinVariant")
	pattern = if pattern == "Zebra" or pattern == "Rainbow" then pattern else nil
	model = if type(model) == "string" and BallModels.Names[model] then model else nil
	form = if type(form) == "string" and table.find(BallModels.Forms, form) then form else nil
	-- a model replaces the sphere, so it wins over a pattern
	local key = if not isStandard(ball) then nil elseif model then ("Model:%s:%s"):format(model, form or "") else pattern
	local s = skinned[ball]
	if s and s.key == key then
		return
	end
	unskin(ball)
	if key then
		skin(ball, key, if model then nil else pattern, model, form)
	end
end

local tracked: { [BasePart]: boolean } = {}
local function track(ball: Instance)
	if not ball:IsA("BasePart") then
		return
	end
	if not tracked[ball] then
		tracked[ball] = true
		local function changed()
			refresh(ball)
		end
		local conns = {
			ball:GetAttributeChangedSignal("BallType"):Connect(changed),
			ball:GetAttributeChangedSignal("SkinPattern"):Connect(changed),
			ball:GetAttributeChangedSignal("SkinModel"):Connect(changed),
			ball:GetAttributeChangedSignal("SkinVariant"):Connect(changed),
		}
		table.insert(
			conns,
			ball.Destroying:Connect(function()
				tracked[ball] = nil
				unskin(ball)
				for _, c in conns do
					c:Disconnect()
				end
			end)
		)
	end
	refresh(ball)
end

-- One glitch step: the channel-split copies slip out of the body (or hide inside it), the pixels
-- jump to new spots (or vanish inside), and the scanline moves to a new height, resized to fit.
-- Lightning arcs (kind "Arc") turn as a group to a new random angle about the ball's center.
local rng = Random.new()
local function jitter(ball: BasePart, list: { Glitch })
	local r = ball.Size.X / 2
	local arcs: { [any]: CFrame } = {} -- one new turn per lightning arc (the Storm Core skin)
	for _, g in list do
		if g.kind == "Arc" then
			local group = g.part:GetAttribute("ArcGroup")
			local turn = arcs[group]
			if not turn then
				turn = CFrame.fromAxisAngle(rng:NextUnitVector(), rng:NextNumber(0, 2 * math.pi))
				arcs[group] = turn
			end
			g.weld.C0 = turn * g.base
		elseif g.kind == "Ghost" then
			g.weld.C0 = if rng:NextNumber() < 0.6
				then CFrame.new(rng:NextNumber(-0.14, 0.14) * r, rng:NextNumber(-0.05, 0.05) * r, 0)
				else CFrame.identity
		elseif g.kind == "Pixel" then
			if rng:NextNumber() < 0.3 then
				g.weld.C0 = CFrame.identity -- inside the body: gone for a tick
			else
				local dir = rng:NextUnitVector()
				g.weld.C0 = CFrame.lookAt(dir * r, dir * r * 2)
			end
		elseif g.kind == "Scan" then
			local h = rng:NextNumber(-0.8, 0.8) * r
			local d = BallModels.scanRadius(r, h) * 2
			g.part.Size = Vector3.new(g.part.Size.X, d, d)
			g.weld.C0 = g.base * CFrame.new(h, 0, 0)
		end
	end
end

-- A random form from `variants`, never `last` (unless it is the only one). PracticeController's
-- pickups use this; match pickups pick on the server (ShopService.pickForm).
function BallSkinController.pickForm(variants: { string }, last: string?): string
	local choices = {}
	for _, v in variants do
		if v ~= last then
			table.insert(choices, v)
		end
	end
	if #choices == 0 then
		choices = variants
	end
	return choices[rng:NextInteger(1, #choices)]
end

-- The swap flourish: a brief soft glow in the form's color over your screen.
function BallSkinController.flourish(form: string)
	local color = FORM_GLOW[form]
	if color then
		HUDController.flash(color, 0.22, 0.45)
	end
end

function BallSkinController.init() end

function BallSkinController.start()
	Net.on("SkinForm", function(d)
		if type(d) == "table" and type(d.form) == "string" then
			BallSkinController.flourish(d.form)
		end
	end)
	-- performance mode switched: effect skins' lights and particles follow
	GraphicsController.onChanged(function()
		for _, s in skinned do
			if s.sync then
				s.sync()
			end
		end
	end)
	-- the same balls HalloweenController follows: match balls, flying visuals and practice balls
	local function follow(folder: Instance, filter: ((Instance) -> boolean)?)
		local function add(b: Instance)
			if not filter or filter(b) then
				track(b)
			end
		end
		folder.ChildAdded:Connect(add)
		for _, b in folder:GetChildren() do
			add(b)
		end
	end
	task.spawn(function()
		for _, name in { "Balls", "BallVisuals" } do
			local f = Workspace:WaitForChild(name, 30)
			if f then
				follow(f)
			end
		end
	end)
	task.spawn(function()
		local lobby = Workspace:WaitForChild("Lobby", 30)
		local practice = lobby and lobby:WaitForChild("Practice", 30)
		if practice then
			follow(practice, function(b)
				return b.Name == "PracticeBall"
			end)
		end
	end)
	local nextGlitch = 0
	RunService.RenderStepped:Connect(function()
		local color = Color3.fromHSV((os.clock() * RAINBOW_SPEED) % 1, 0.75, 1)
		local glitchNow = os.clock() >= nextGlitch
		if glitchNow then
			nextGlitch = os.clock() + 1 / GLITCH_HZ
		end
		for ball, s in skinned do
			if s.pattern == "Rainbow" then
				ball.Color = color
				s.last = color
			end
			if glitchNow and s.glitch then
				jitter(ball, s.glitch)
			end
		end
	end)
end

return BallSkinController
