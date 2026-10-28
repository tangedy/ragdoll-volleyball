--!strict
-- The dev room (Config.DevRoom): a dark hall far above the map for looking at work in progress,
-- today the Haunted Wheel (HauntedWheelBuilder). ";" takes you there and ";" again brings you back
-- to the hub, for whoever may flip Halloween (Studio, or the game's owner on a live server). The
-- room is built when the first visitor arrives and taken down when the last one leaves.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local HauntedWheelBuilder = require(script.Parent.HauntedWheelBuilder)

local D = Config.DevRoom

local DevRoomService = {}

local S: any
local room: Folder? = nil
local visitors: { [Player]: boolean } = {}
local rng = Random.new()

function DevRoomService.init(services: any)
	S = services
end

-- Room frame: the booth stands at the far (-Z) end and faces the visitors at the near end.
local function frame(): CFrame
	return CFrame.new(D.Origin)
end

local function build(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "DevRoom"
	local f = frame()
	local w, h, d = D.Size.X, D.Size.Y, D.Size.Z
	-- dusky purple, so the black mist shows against it
	local shell = { Color = Color3.fromRGB(58, 44, 78), Material = Enum.Material.Slate }
	local function slab(name: string, cf: CFrame, size: Vector3)
		local props = table.clone(shell)
		props.Name = name
		props.CFrame = cf
		props.Size = size
		LobbyBuilder.solid(props, folder)
	end
	slab("Floor", f * CFrame.new(0, -0.5, 0), Vector3.new(w, 1, d))
	slab("Ceiling", f * CFrame.new(0, h + 0.5, 0), Vector3.new(w, 1, d))
	slab("WallBack", f * CFrame.new(0, h / 2, -d / 2 - 0.5), Vector3.new(w, h, 1))
	slab("WallFront", f * CFrame.new(0, h / 2, d / 2 + 0.5), Vector3.new(w, h, 1))
	slab("WallLeft", f * CFrame.new(-w / 2 - 0.5, h / 2, 0), Vector3.new(1, h, d))
	slab("WallRight", f * CFrame.new(w / 2 + 0.5, h / 2, 0), Vector3.new(1, h, d))
	-- a sign over the way out
	local sign = LobbyBuilder.decor({
		Name = "Sign",
		Size = Vector3.new(16, 2.4, 0.2),
		CFrame = f * CFrame.new(0, 9, d / 2 - 0.2),
		Transparency = 1,
	}, folder)
	LobbyBuilder.paint(sign, Enum.NormalId.Front, "DEV ROOM  ·  press ; to leave", Color3.fromRGB(255, 150, 40))
	HauntedWheelBuilder.build(f * CFrame.new(0, 0, -d / 2 + 8) * CFrame.Angles(0, math.pi, 0), folder)
	folder.Parent = Workspace
	return folder
end

local function leave(player: Player)
	visitors[player] = nil
	player:SetAttribute("InDevRoom", nil)
	if next(visitors) == nil and room then
		room:Destroy()
		room = nil
	end
end

function DevRoomService.toggle(player: Player)
	if not S.HalloweenService.canToggle(player) then
		S.NetService.reject(player, "devroom-denied")
		return
	end
	local c = S.PlayerStateService.get(player)
	if not (c and c.root) then
		return
	end
	if visitors[player] then
		leave(player)
		-- a match that started meanwhile already took them to the court: leave them there
		if not c.inMatch then
			S.CharacterService.placeFacing(c, ArenaLayout.lobbySpawn(rng), ArenaLayout.CourtFocus)
		end
		return
	end
	if c.inMatch then
		S.NetService.send(player, "Hint", { text = "Leave the match first", duration = 1.5 })
		return
	end
	room = room or build()
	visitors[player] = true
	player:SetAttribute("InDevRoom", true)
	local f = frame()
	local spot = (f * CFrame.new(rng:NextNumber(-3, 3), 3, D.Size.Z / 2 - 10)).Position
	S.CharacterService.placeFacing(c, spot, (f * CFrame.new(0, 6, -D.Size.Z / 2)).Position)
end

function DevRoomService.start()
	Players.PlayerRemoving:Connect(leave)
end

return DevRoomService
