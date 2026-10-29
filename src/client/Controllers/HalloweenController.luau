--!strict
-- The client half of the Halloween event (Config.Halloween), driven by the "Halloween" attribute the
-- server keeps on ReplicatedStorage (HalloweenService handles the lighting and hub props):
--
--  * UI palette: every Day color in the HUD and menus is swapped for its Halloween twin
--    (Theme.HalloweenToybox), including anything built or recolored later, and swapped back after.
--  * Music: the event tracks loop in turn, quieter while you're on the court.
--  * Jack-o-lantern balls: every Standard ball (match, in flight, practice) wears a carved pumpkin a
--    little bigger than the ball, so the sphere stays hidden inside. It's a look only: the ball's
--    size, physics and hit checks never change, and power-up balls keep their own colors. A ball
--    wearing a skin (held or thrown by someone with one equipped) turns its pumpkin that color.
--    The Jack-o'-Lantern skin (Haunted Bundle) keeps the classic pumpkin on its owner's balls all
--    year, event or not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallDefinitions = require(Shared:WaitForChild("BallDefinitions"))
local Config = require(Shared:WaitForChild("Config"))
local JackOLantern = require(Shared:WaitForChild("JackOLantern"))
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

-- A carved pumpkin around `ball` (face on its -Z side), welded to it so it follows every move.
local function makePumpkin(ball: BasePart): Model
	local model = JackOLantern.build(ball.CFrame, ball.Size.X / 2 * B.Scale, PUMPKIN)
	JackOLantern.weld(model, ball)
	model.Parent = ball
	return model
end

local decorated: { [BasePart]: { model: Model, conns: { RBXScriptConnection } } } = {}

-- The pumpkin takes the ball's skin: the body in the skin's color and material, the ribs a shade
-- darker. A ball in the plain Standard look stays a classic orange pumpkin. Neon skins keep a
-- matte body so the carved face still glows brighter than the shell.
local STANDARD = BallDefinitions.get("Standard")
local function tint(model: Model, ball: BasePart)
	local skinned = ball:GetAttribute("Pumpkin") ~= true -- the Jack-o'-Lantern skin is the classic pumpkin
		and (ball.Color:ToHex() ~= STANDARD.Color:ToHex() or ball.Material ~= STANDARD.Material)
	local color = if skinned then ball.Color else B.Body
	local material = if skinned and ball.Material ~= Enum.Material.Neon
		then ball.Material
		else Enum.Material.SmoothPlastic
	for _, p in model:GetChildren() do
		if not p:IsA("BasePart") then
			continue
		end
		if p.Name == "Body" then
			p.Color = color
			p.Material = material
		elseif p.Name == "Rib" then
			p.Color = if skinned then color:Lerp(Color3.new(0, 0, 0), 0.18) else B.Rib
			p.Material = material
		end
	end
end

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
	tint(model, ball)
	local function retint()
		tint(model, ball)
	end
	decorated[ball] = {
		model = model,
		conns = {
			ball:GetPropertyChangedSignal("Color"):Connect(retint),
			ball:GetPropertyChangedSignal("Material"):Connect(retint),
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

-- Does this ball wear a pumpkin now? Every Standard ball while the event is on, and all year a
-- Standard ball whose owner has the Jack-o'-Lantern skin (the "Pumpkin" attribute: BallService on
-- server balls, BallVisualController on flying visuals, PracticeController on practice balls).
local function wantsPumpkin(ball: BasePart): boolean
	return isStandard(ball) and (HalloweenController.on or ball:GetAttribute("Pumpkin") == true)
end

local function refresh(ball: BasePart)
	if wantsPumpkin(ball) then
		decorate(ball)
		local d = decorated[ball]
		if d then
			tint(d.model, ball)
		end
	else
		undecorate(ball)
	end
end

-- a ball changing type (picked up a power-up, spent back to Standard) or skin gains or loses its pumpkin
local tracked: { [BasePart]: { RBXScriptConnection } } = {}
local function track(ball: Instance)
	if not ball:IsA("BasePart") then
		return
	end
	if not tracked[ball] then
		local function changed()
			refresh(ball)
		end
		local conns = {
			ball:GetAttributeChangedSignal("BallType"):Connect(changed),
			ball:GetAttributeChangedSignal("Pumpkin"):Connect(changed),
		}
		tracked[ball] = conns
		table.insert(
			conns,
			ball.Destroying:Connect(function()
				tracked[ball] = nil
				for _, c in conns do
					c:Disconnect()
				end
			end)
		)
	end
	refresh(ball)
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
			refresh(ball) -- a Jack-o'-Lantern skin keeps its pumpkin
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
	-- (tracked whether or not the event is on: a Jack-o'-Lantern skin wears its pumpkin all year)
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
	ReplicatedStorage:GetAttributeChangedSignal("Halloween"):Connect(apply)
	task.defer(apply)
end

return HalloweenController
