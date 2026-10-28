--!strict
-- The Halloween event (Config.Halloween). One switch: the "Halloween" attribute on ReplicatedStorage,
-- which servers start from Config.Halloween.Enabled and the dev toggle flips at runtime. The server
-- owns the shared world changes: dusk lighting, the asset-pack props around the hub, and the Haunted
-- Wheel standing in for the spin station's booth. Clients do
-- the rest from the attribute (HalloweenController: UI palette, music, jack-o-lantern balls), and
-- the shop only offers Halloween cosmetics while it's on (Catalog.isOffered).
--
-- Dev toggle: H in Studio (or for the game's owner on a live server), or
-- workspace:SetAttribute("RD_Halloween", true/false) from the server command bar. A live toggle only
-- changes that server; change Config.Halloween.Enabled and publish to switch every server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local HauntedWheelBuilder = require(script.Parent.HauntedWheelBuilder)

local H = Config.Halloween

local HalloweenService = {}

local S: any
local on = false
local propsFolder: Folder? = nil
local voidGlowDay: Color3? = nil
local spinBooth: Folder? = nil -- the regular spin booth's parts, put away while the haunted wheel stands in

function HalloweenService.init(services: any)
	S = services
end

function HalloweenService.isOn(): boolean
	return on
end

-- Lighting -----------------------------------------------------------------------------------------

local function applyLighting()
	local Lighting = game:GetService("Lighting")
	local L = H.Lighting
	Lighting.ClockTime = L.ClockTime
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	local atmo = Lighting:FindFirstChild("RD_Atmosphere") :: Atmosphere?
	if atmo then
		for k, v in L.Atmosphere do
			(atmo :: any)[k] = v
		end
	end
	local bloom = Lighting:FindFirstChild("RD_Bloom") :: BloomEffect?
	if bloom then
		bloom.Intensity = L.Bloom.Intensity
		bloom.Size = L.Bloom.Size
		bloom.Threshold = L.Bloom.Threshold
	end
	local cc = Lighting:FindFirstChild("RD_Color") :: ColorCorrectionEffect?
	if cc then
		cc.Saturation = L.Color.Saturation
		cc.Contrast = L.Color.Contrast
		cc.Brightness = L.Color.Brightness
		cc.TintColor = L.Color.Tint
	end
end

local function voidGlow(): BasePart?
	local arena = Workspace:FindFirstChild("Arena")
	return arena and arena:FindFirstChild("VoidGlow", true) :: BasePart?
end

-- Props --------------------------------------------------------------------------------------------

-- The pack model at "Folder/Model" in ServerStorage.HalloweenAssets.
local function asset(path: string): Model?
	local node: Instance? = ServerStorage:FindFirstChild("HalloweenAssets")
	for part in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return if node and node:IsA("Model") then node else nil
end

-- Is anything solid or visible already standing in `box`?
local function occupied(cf: CFrame, size: Vector3, lobby: Instance): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lobby }
	for _, p in Workspace:GetPartBoundsInBox(cf, size, params) do
		if propsFolder and p:IsDescendantOf(propsFolder) then
			return true -- another Halloween prop
		end
		if p.CanCollide or p.Transparency < 1 then
			return true
		end
	end
	return false
end

-- Put one prop on the deck at its spot, standing on whatever floor is there. Returns false (and
-- places nothing) if the spot is over the void or something already stands there.
local function place(spot: any, lobby: Instance, folder: Folder): boolean
	local template = asset(spot.Asset)
	if not template then
		warn("[Halloween] missing asset " .. tostring(spot.Asset))
		return false
	end
	local at = ArenaLayout.lobbyPoint(spot.X, 0, spot.F)
	-- the deck surface under the spot (props never hang over the edge)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { lobby }
	local hit = Workspace:Raycast(at + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), ray)
	if not hit then
		return false
	end
	local model = template:Clone()
	if spot.Scale and spot.Scale ~= 1 then
		model:ScaleTo(spot.Scale)
	end
	model:PivotTo(
		CFrame.new(hit.Position) * ArenaLayout.LobbyFrame.Rotation * CFrame.Angles(0, math.rad(spot.Yaw or 0), 0)
	)
	-- sit its bottom on the surface
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, hit.Position.Y - bottom, 0))
	box, size = model:GetBoundingBox()
	-- check the space it takes, lifted clear of the floor tiles it stands on
	local probeSize = Vector3.new(size.X * 0.9, math.max(size.Y - 1, 0.5), size.Z * 0.9)
	if occupied(box + Vector3.new(0, 0.5, 0), probeSize, lobby) then
		model:Destroy()
		return false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		end
	end
	model.Parent = folder
	return true
end

-- The Haunted Wheel stands in for the spin station's booth. Everything of the regular booth but
-- its prompt is put away in ServerStorage, so the Daily Spin prompt keeps working from the same spot.
local function hauntSpinBooth(lobby: Instance, folder: Folder)
	local stations = lobby:FindFirstChild("Stations")
	local station = stations and stations:FindFirstChild("SpinStation")
	local platform = station and station:FindFirstChild("Platform") :: BasePart?
	if not station or not platform or spinBooth then
		return
	end
	local stash = Instance.new("Folder")
	stash.Name = "SpinBoothStash"
	for _, child in station:GetChildren() do
		if child.Name ~= "PromptAnchor" then
			child.Parent = stash
		end
	end
	stash.Parent = ServerStorage
	spinBooth = stash
	-- both booths stand on the same 12x9 platform: the station's base is under its middle
	HauntedWheelBuilder.build(platform.CFrame * CFrame.new(0, -0.2, -0.5), folder)
end

local function restoreSpinBooth()
	local stash = spinBooth
	spinBooth = nil
	if not stash then
		return
	end
	local lobby = Workspace:FindFirstChild("Lobby")
	local stations = lobby and lobby:FindFirstChild("Stations")
	local station = stations and stations:FindFirstChild("SpinStation")
	if station then
		for _, child in stash:GetChildren() do
			child.Parent = station
		end
	end
	stash:Destroy()
end

local function placeProps()
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Halloween"
	-- parented under the hub, so it hides with the hub for players on the court
	folder.Parent = lobby
	propsFolder = folder
	-- first, so the props below make room for it
	hauntSpinBooth(lobby, folder)
	local placed, skipped = 0, {}
	for _, spot in H.Props do
		if place(spot, lobby, folder) then
			placed += 1
		else
			table.insert(skipped, spot.Asset)
		end
	end
	if #skipped > 0 and RunService:IsStudio() then
		print(
			("[Halloween] placed %d props; skipped (blocked or missing): %s"):format(
				placed,
				table.concat(skipped, ", ")
			)
		)
	end
end

local function clearProps()
	if propsFolder then
		propsFolder:Destroy()
		propsFolder = nil
	end
	restoreSpinBooth()
end

-- Switch -------------------------------------------------------------------------------------------

function HalloweenService.set(value: boolean)
	if value == on and ReplicatedStorage:GetAttribute("Halloween") == value then
		return
	end
	on = value
	ReplicatedStorage:SetAttribute("Halloween", value)
	-- keep the command-bar switch in step, so setting it after an H toggle always registers
	Workspace:SetAttribute("RD_Halloween", value)
	local glow = voidGlow()
	if value then
		applyLighting()
		if glow then
			voidGlowDay = voidGlowDay or glow.Color
			glow.Color = H.Lighting.VoidGlow
		end
		clearProps()
		placeProps()
	else
		ArenaBuilder.setupLighting() -- the normal day, exactly as the arena builds it
		if glow and voidGlowDay then
			glow.Color = voidGlowDay
		end
		clearProps()
	end
end

-- Studio, or the game's owner (the user, or the owner of the group that owns it).
function HalloweenService.canToggle(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

function HalloweenService.devToggle(player: Player)
	if not HalloweenService.canToggle(player) then
		S.NetService.reject(player, "halloween-toggle-denied")
		return
	end
	HalloweenService.set(not on)
	for _, p in Players:GetPlayers() do
		S.NetService.send(p, "Hint", { text = if on then "Halloween is ON" else "Halloween is off", duration = 1.6 })
	end
end

function HalloweenService.start()
	-- the command bar switch
	Workspace:GetAttributeChangedSignal("RD_Halloween"):Connect(function()
		local v = Workspace:GetAttribute("RD_Halloween")
		if type(v) == "boolean" then
			HalloweenService.set(v)
		end
	end)
	ReplicatedStorage:SetAttribute("Halloween", false)
	if H.Enabled then
		task.spawn(function()
			-- the props need the hub deck to exist first
			Workspace:WaitForChild("Lobby", 30)
			HalloweenService.set(true)
		end)
	end
end

return HalloweenService
