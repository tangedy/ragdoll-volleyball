--!strict
-- The client half of the Halloween event (Config.Halloween), driven by the "Halloween" attribute the
-- server keeps on ReplicatedStorage (HalloweenService handles the lighting and hub props):
--
--  * UI palette: every Day color in the HUD and menus is swapped for its Halloween twin
--    (Theme.HalloweenToybox), including anything built or recolored later, and swapped back after.
--  * Music: the event tracks loop in turn, quieter while you're on the court.
--  * Jack-o-lantern balls: every Standard ball (match, in flight, practice) wears a carved pumpkin a
--    little bigger than the ball, so the sphere stays hidden inside. It's a look only: the ball's
--    size, physics and hit checks never change, and power-up balls keep their own colors.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local H = Config.Halloween
local player = Players.LocalPlayer

local HalloweenController = {}

HalloweenController.on = false

-- UI palette ---------------------------------------------------------------------------------------

local toHalloween: { [string]: Color3 } = {}
local toDay: { [string]: Color3 } = {}
for role, value in Theme.Toybox :: { [string]: Color3 } do
	local day = value :: Color3
	local spooky = (Theme.HalloweenToybox :: any)[role] :: Color3?
	if spooky then
		toHalloween[day:ToHex()] = spooky
		toDay[spooky:ToHex()] = day
	end
end

local COLOR_PROPS = { "BackgroundColor3", "TextColor3", "TextStrokeColor3", "ImageColor3", "PlaceholderColor3" }
local WATCHED: { [string]: boolean } = { Color = true }
for _, prop in COLOR_PROPS do
	WATCHED[prop] = true
end

local function remap(inst: Instance, map: { [string]: Color3 })
	if inst:IsA("UIStroke") then
		local m = map[inst.Color:ToHex()]
		if m then
			inst.Color = m
		end
	elseif inst:IsA("GuiObject") then
		for _, prop in COLOR_PROPS do
			local ok, value = pcall(function()
				return (inst :: any)[prop]
			end)
			if ok and typeof(value) == "Color3" then
				local m = map[value:ToHex()]
				if m then
					(inst :: any)[prop] = m
				end
			end
		end
	end
end

-- while the event is on, anything the UI recolors back to a Day token is swapped again at once
local watchers: { [Instance]: RBXScriptConnection } = {}
local addedConn: RBXScriptConnection? = nil

local function watch(inst: Instance)
	if watchers[inst] or not (inst:IsA("GuiObject") or inst:IsA("UIStroke")) then
		return
	end
	remap(inst, toHalloween)
	watchers[inst] = inst.Changed:Connect(function(prop: string)
		if WATCHED[prop] then
			remap(inst, toHalloween) -- our own write maps to a Halloween color, which isn't a key: no loop
		end
	end)
end

local function setPalette(on: boolean)
	local pg = player:WaitForChild("PlayerGui")
	if on then
		for _, d in pg:GetDescendants() do
			watch(d)
		end
		addedConn = pg.DescendantAdded:Connect(watch)
	else
		if addedConn then
			addedConn:Disconnect()
			addedConn = nil
		end
		for inst, conn in watchers do
			conn:Disconnect()
			if inst.Parent then
				remap(inst, toDay)
			end
		end
		table.clear(watchers)
	end
end

-- Music --------------------------------------------------------------------------------------------

local music: Sound? = nil
local track = 0

local function musicVolume(): number
	return if player:GetAttribute("Status") == "Lobby" then H.MusicVolume.Hub else H.MusicVolume.Match
end

local function nextTrack()
	local s = music
	if not s or #H.Music == 0 then
		return
	end
	track = track % #H.Music + 1
	s.SoundId = H.Music[track]
	s.TimePosition = 0
	s:Play()
end

local function setMusic(on: boolean)
	if on and not music then
		local group = SoundService:FindFirstChild("Music") :: SoundGroup?
		if not group then
			local made = Instance.new("SoundGroup")
			made.Name = "Music"
			made.Volume = 1
			made.Parent = SoundService
			group = made
		end
		local s = Instance.new("Sound")
		s.Name = "RD_HalloweenMusic"
		s.Volume = 0
		s.SoundGroup = group
		s.Parent = SoundService
		s.Ended:Connect(nextTrack)
		music = s
		nextTrack()
		TweenService:Create(s, TweenInfo.new(2), { Volume = musicVolume() }):Play()
	elseif not on and music then
		local s = music
		music = nil
		TweenService:Create(s, TweenInfo.new(1), { Volume = 0 }):Play()
		task.delay(1.1, function()
			s:Destroy()
		end)
	end
end

player:GetAttributeChangedSignal("Status"):Connect(function()
	if music then
		TweenService:Create(music, TweenInfo.new(1.2), { Volume = musicVolume() }):Play()
	end
end)

-- Jack-o-lantern balls -----------------------------------------------------------------------------

local PUMPKIN = "RD_Pumpkin"
local B = H.Ball

local function piece(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.Massless = true
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

-- A carved pumpkin around `ball` (face on its -Z side), welded to it so it follows every move.
local function makePumpkin(ball: BasePart): Model
	local model = Instance.new("Model")
	model.Name = PUMPKIN
	local r = ball.Size.X / 2 * B.Scale
	local k = r / 1.35 -- the face layout is drawn for the Pumpkin finisher's 1.35-stud pumpkin
	local cf = ball.CFrame
	local parts: { BasePart } = {}
	local function add(p: BasePart, off: CFrame)
		p.CFrame = cf * off
		table.insert(parts, p)
	end
	-- a slightly squashed body with darker ribs round the vertical axis
	local body = piece({ Shape = Enum.PartType.Ball, Size = Vector3.one * r * 2, Color = B.Body }, model)
	local squash = Instance.new("SpecialMesh")
	squash.MeshType = Enum.MeshType.Sphere
	squash.Scale = Vector3.new(1, 0.88, 1)
	squash.Parent = body
	add(body, CFrame.identity)
	for i = 0, 2 do
		local rib = piece({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1 * k, r * 2.02 * 0.88, r * 2.02),
			Color = B.Rib,
		}, model)
		add(rib, CFrame.Angles(0, math.rad(60 * i), 0) * CFrame.Angles(0, math.rad(90), 0))
	end
	local stem = piece({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5 * k, 0.3 * k, 0.3 * k),
		Color = B.Stem,
	}, model)
	add(stem, CFrame.new(0, r * 0.88 + 0.15 * k, 0) * CFrame.Angles(0, 0, math.rad(80)))
	-- the glowing carved face: diamond eyes, a nose and a jagged grin
	local function feature(x: number, y: number, size: Vector3, rotZ: number)
		x, y = x * k, y * k * 0.88
		local z = -math.sqrt(math.max(0.05 * k, r * r - x * x - (y / 0.88) ^ 2)) * 1.0 + 0.02
		local pos = Vector3.new(x, y, z)
		local f = piece({ Size = size * k, Color = B.Carve, Material = Enum.Material.Neon }, model)
		add(f, CFrame.lookAt(pos, pos * 2) * CFrame.Angles(0, 0, math.rad(rotZ)))
	end
	feature(-0.48, 0.32, Vector3.new(0.42, 0.42, 0.06), 45)
	feature(0.48, 0.32, Vector3.new(0.42, 0.42, 0.06), 45)
	feature(0, 0.02, Vector3.new(0.2, 0.2, 0.06), 45)
	for i = -2, 2 do
		feature(i * 0.27, -0.42 + (if i % 2 == 0 then 0.06 else -0.06), Vector3.new(0.26, 0.2, 0.06), 0)
	end
	for _, p in parts do
		local w = Instance.new("WeldConstraint")
		w.Part0 = ball
		w.Part1 = p
		w.Parent = p
	end
	model.Parent = ball
	return model
end

local decorated: { [BasePart]: { model: Model, conns: { RBXScriptConnection } } } = {}

local function undecorate(ball: BasePart)
	local d = decorated[ball]
	if d then
		decorated[ball] = nil
		for _, c in d.conns do
			c:Disconnect()
		end
		d.model:Destroy()
	end
end

local function isStandard(ball: BasePart): boolean
	local t = ball:GetAttribute("BallType")
	return t == nil or t == "Standard"
end

local function decorate(ball: BasePart)
	if decorated[ball] or not ball:IsA("BasePart") or not isStandard(ball) then
		return
	end
	local model = makePumpkin(ball)
	local function syncHidden()
		-- the ball is hidden locally while its client-drawn visual flies: hide the pumpkin with it
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = ball.LocalTransparencyModifier
				p.Transparency = ball.Transparency
			end
		end
	end
	syncHidden()
	decorated[ball] = {
		model = model,
		conns = {
			ball:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(syncHidden),
			ball:GetPropertyChangedSignal("Transparency"):Connect(syncHidden),
			-- only when the ball itself goes (the hub, practice balls and all, is lifted out of the
			-- Workspace while you're on the court and put back after)
			ball.AncestryChanged:Connect(function()
				if ball.Parent == nil then
					undecorate(ball)
				end
			end),
		},
	}
end

-- a ball changing type (picked up a power-up, spent back to Standard) gains or loses its pumpkin
local typeConns: { [BasePart]: RBXScriptConnection } = {}
local function track(ball: Instance)
	if not ball:IsA("BasePart") then
		return
	end
	if not typeConns[ball] then
		typeConns[ball] = ball:GetAttributeChangedSignal("BallType"):Connect(function()
			if not HalloweenController.on then
				return
			end
			if isStandard(ball) then
				decorate(ball)
			else
				undecorate(ball)
			end
		end)
	end
	if HalloweenController.on then
		decorate(ball)
	end
end

local function ballFolders(): { Instance }
	local list = {}
	for _, name in { "Balls", "BallVisuals" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

local function setBalls(on: boolean)
	if on then
		for _, f in ballFolders() do
			for _, b in f:GetChildren() do
				track(b)
			end
		end
		local lobby = Workspace:FindFirstChild("Lobby")
		local practice = lobby and lobby:FindFirstChild("Practice")
		if practice then
			for _, b in practice:GetChildren() do
				if b.Name == "PracticeBall" then
					track(b)
				end
			end
		end
	else
		for ball in decorated do
			undecorate(ball)
		end
	end
end

-- Switch -------------------------------------------------------------------------------------------

local function apply()
	local on = ReplicatedStorage:GetAttribute("Halloween") == true
	if on == HalloweenController.on then
		return
	end
	HalloweenController.on = on
	setPalette(on)
	setMusic(on)
	setBalls(on)
end

function HalloweenController.init() end

function HalloweenController.start()
	-- new balls: match balls, the flying visuals, and practice balls (the hub can stream in late)
	local function follow(folder: Instance, filter: ((Instance) -> boolean)?)
		folder.ChildAdded:Connect(function(b)
			if not filter or filter(b) then
				track(b)
			end
		end)
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
	ReplicatedStorage:GetAttributeChangedSignal("Halloween"):Connect(apply)
	task.defer(apply)
end

return HalloweenController
