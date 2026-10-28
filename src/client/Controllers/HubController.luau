--!strict
-- Hub presentation (client only):
--  * The hub sits beside the court. While you're on the court (Active / Jailed / Returning) the whole
--    hub disappears for you: the deck and everything on it, the practice balls, the dummy and the
--    people standing in the hub. It can't distract you, block your camera or be clicked. It comes
--    back the moment you're in the hub again (eliminated for the round, or the match is over).
--  * Animated rooftop props: the prize wheel on the spin station, the antenna beacon, AC fans.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local player = Players.LocalPlayer

local HubController = {}

HubController.lobbyHidden = false

-- players knocked out for the round (Spectating) wait in their jail, not the hub
local ON_COURT: { [string]: boolean } = { Active = true, Jailed = true, Returning = true, Spectating = true }
local IN_HUB: { [string]: boolean } = { Lobby = true }

local lobbyFolder: Instance? = nil
local hiddenParts: { [BasePart]: boolean } = {}
local hiddenGuis: { [BillboardGui]: boolean } = {}

local IDLE_WHEEL_SPEED = 0.6 -- rad/s while nobody is spinning
local wheelBoostUntil = 0
local wheelHome: { [Model]: CFrame } = {}
local fanHome: { [BasePart]: CFrame } = {}
local wheelAngle = 0
local fanAngle = 0

-- Make the hub's prize wheel whirl for a few seconds (when you spin the daily wheel).
function HubController.boostWheel(seconds: number)
	wheelBoostUntil = os.clock() + seconds
end

-- Tagged props, kept current from CollectionService signals instead of re-fetched (a fresh array
-- per tag) every frame.
local tagged: { [string]: { Instance } } = {}
local beaconOn: boolean? = nil -- last beacon state written (nil = write on the next frame)
local function taggedList(tag: string): { Instance }
	local list = tagged[tag]
	if list then
		return list
	end
	local fresh = CollectionService:GetTagged(tag)
	tagged[tag] = fresh
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		table.insert(fresh, inst)
		beaconOn = nil
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		local i = table.find(fresh, inst)
		if i then
			table.remove(fresh, i)
		end
	end)
	return fresh
end

local function animateProps(dt: number)
	local boost = math.max(0, wheelBoostUntil - os.clock())
	wheelAngle += dt * (IDLE_WHEEL_SPEED + boost * 4)
	for _, m in taggedList("HubWheel") do
		if m:IsA("Model") and m.PrimaryPart then
			local home = wheelHome[m]
			if not home then
				home = m:GetPivot()
				wheelHome[m] = home
			end
			-- the pivot is the disc, whose axis (local X) points out of the wall
			local rate = m:GetAttribute("SpinRate")
			m:PivotTo(home * CFrame.Angles(wheelAngle * (if type(rate) == "number" then rate else 1), 0, 0))
		end
	end
	-- firelight (the haunted wheel's pumpkins, candles and braziers) flickers about its Base brightness
	local now = os.clock()
	for i, l in taggedList("HubFlicker") do
		local base = l:GetAttribute("Base")
		if l:IsA("Light") and type(base) == "number" then
			l.Brightness = base * (0.8 + 0.45 * math.noise(now * 6, i * 3.1))
		end
	end
	-- beacons only change twice per blink: write them then, not every frame
	local on = (os.clock() % Config.Lobby.BeaconBlink) < Config.Lobby.BeaconBlink * 0.35
	if on ~= beaconOn then
		beaconOn = on
		for _, b in taggedList("HubBeacon") do
			if b:IsA("BasePart") then
				b.Transparency = if on then 0 else 0.85
				local light = b:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = on
				end
			end
		end
	end
	fanAngle += dt * 9
	local fans = taggedList("HubFan")
	if #fans > 0 then
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for _, f in fans do
			if f:IsA("BasePart") then
				local home = fanHome[f]
				if not home then
					home = f.CFrame
					fanHome[f] = home
				end
				table.insert(parts, f)
				table.insert(cframes, home * CFrame.Angles(fanAngle, 0, 0)) -- cylinder axis is its local X
			end
		end
		-- one engine call for every fan instead of a CFrame write each
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Should the hub be hidden for the local player right now?
function HubController.shouldHide(): boolean
	local team = player:GetAttribute("Team")
	local status = player:GetAttribute("Status")
	return type(team) == "string" and team ~= "" and type(status) == "string" and ON_COURT[status] == true
end

local function restorePart(p: BasePart)
	if p.Parent then
		p.LocalTransparencyModifier = 0
	end
end

local function restoreAll()
	for p in hiddenParts do
		restorePart(p)
	end
	for g in hiddenGuis do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hiddenParts)
	table.clear(hiddenGuis)
end

-- Everything that lives in the hub but isn't part of Workspace.Lobby: practice balls, the dummy and
-- anyone standing in the hub (lobby players and eliminated spectators). People come and go all
-- match long, so this rebuilds the hidden set each scan and un-hides whoever left the hub.
local function hideHubOccupants()
	local wantParts: { [BasePart]: boolean } = {}
	local wantGuis: { [BillboardGui]: boolean } = {}
	local balls = Workspace:FindFirstChild("Balls")
	if balls then
		for _, b in balls:GetChildren() do
			if b:IsA("BasePart") and b:GetAttribute("Context") == "Lobby" then
				wantParts[b] = true
			end
		end
	end
	local function scan(parent: Instance)
		for _, m in parent:GetChildren() do
			if m:IsA("Model") and m ~= player.Character and m:FindFirstChildOfClass("Humanoid") then
				local status = m:GetAttribute("Status")
				if type(status) == "string" and IN_HUB[status] then
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then
							wantParts[d] = true
						elseif d:IsA("BillboardGui") then
							wantGuis[d] = true
						end
					end
				end
			end
		end
	end
	scan(Workspace)
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		scan(bots)
	end
	for p in hiddenParts do
		if not wantParts[p] then
			restorePart(p)
			hiddenParts[p] = nil
		end
	end
	for g in hiddenGuis do
		if not wantGuis[g] then
			if g.Parent then
				g.Enabled = true
			end
			hiddenGuis[g] = nil
		end
	end
	for p in wantParts do
		hiddenParts[p] = true
		p.LocalTransparencyModifier = 1
	end
	for g in wantGuis do
		if g.Enabled or hiddenGuis[g] then
			hiddenGuis[g] = true
			g.Enabled = false
		end
	end
end

local function setHidden(hide: boolean)
	if hide == HubController.lobbyHidden then
		return
	end
	HubController.lobbyHidden = hide
	local lobby = lobbyFolder
	if lobby then
		-- out of the Workspace: not rendered, no collisions, no prompts, no lights (local only)
		lobby.Parent = if hide then nil else Workspace
	end
	if not hide then
		restoreAll()
	end
end

function HubController.init() end

function HubController.start()
	task.spawn(function()
		lobbyFolder = Workspace:WaitForChild("Lobby", 30)
	end)
	local nextOccupantScan = 0
	RunService.RenderStepped:Connect(function(dt)
		setHidden(HubController.shouldHide())
		local lobby = lobbyFolder
		if lobby and HubController.lobbyHidden and lobby.Parent ~= nil then
			lobby.Parent = nil -- the folder arrived after we started hiding
		end
		if HubController.lobbyHidden then
			-- people walk in and out of the hub all match long; keep up with them
			if os.clock() >= nextOccupantScan then
				nextOccupantScan = os.clock() + 0.2
				hideHubOccupants()
			end
		else
			animateProps(dt)
		end
	end)
end

return HubController
