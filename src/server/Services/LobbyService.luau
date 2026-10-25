--!strict
-- Player join/leave, lobby spawning, the practice dummy and practice balls, auto-queue toggle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local NetSchema = require(Shared.NetSchema)

local LobbyService = {}

local S: any
local rng = Random.new()
local dummy: any = nil

function LobbyService.init(services: any)
	S = services
end

local function spawnDummy()
	if not dummy then
		dummy = S.PlayerStateService.create("Practice Dummy", nil, false, true)
	end
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = Color3.fromRGB(240, 200, 90)
	desc.TorsoColor = Color3.fromRGB(240, 200, 90)
	desc.LeftArmColor = Color3.fromRGB(240, 200, 90)
	desc.RightArmColor = Color3.fromRGB(240, 200, 90)
	desc.LeftLegColor = Color3.fromRGB(200, 160, 70)
	desc.RightLegColor = Color3.fromRGB(200, 160, 70)
	local home = ArenaLayout.DummyHome
	S.CharacterService.spawn(dummy, desc, CFrame.lookAt(home, home - Vector3.zAxis))
	dummy.immuneUntil = 0
	S.PlayerStateService.setAction(dummy, "Idle")
	if dummy.humanoid then
		dummy.humanoid.WalkSpeed = 0
		dummy.humanoid.JumpPower = 0
	end
end

local function onPlayerAdded(player: Player)
	local c = S.PlayerStateService.create(player.DisplayName, player, false, false)
	c.joinedAt = os.clock()
	S.CharacterService.spawnPlayer(c, CFrame.new(ArenaLayout.lobbySpawn(rng)))
	S.DataService.load(c)
	if player.Parent ~= Players then
		return
	end
	c.funnelEligible = c.profile.Matches == 0
	S.AnalyticsService.funnel(c, "Joined")
	S.TutorialService.sync(c)
end

local function onPlayerRemoving(player: Player)
	local c = S.PlayerStateService.get(player)
	if not c then
		return
	end
	-- analytics: departure after elimination (spec §14)
	if c.inMatch and (c.status == "Jailed" or c.status == "Spectating") then
		S.AnalyticsService.event(c, "LeftWhileOut_" .. c.status)
	end
	S.MatchService.onLeave(c)
	if c.heldBall then
		S.BallService.drop(c)
	end
	S.DataService.save(c, true)
	if c.character then
		c.character:Destroy()
	end
	S.PlayerStateService.remove(c)
end

function LobbyService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	spawnDummy()

	S.NetService.on(NetSchema.Actions.SetAutoQueue, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c then
			c.autoQueue = p.value
			player:SetAttribute("AutoQueue", p.value)
		end
	end)
	S.NetService.on(NetSchema.Actions.ReportDevice, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c and not (c.devicesSeen and c.devicesSeen[p.kind]) then
			c.devicesSeen = c.devicesSeen or {}
			c.devicesSeen[p.kind] = true
			S.AnalyticsService.event(c, "Device_" .. p.kind)
		end
	end)
	S.NetService.on(NetSchema.Actions.SetSetting, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c then
			c.settings[p.key] = p.value
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			LobbyService.tick()
		end
	end)
end

function LobbyService.tick()
	S.BallService.ensurePracticeBall()
	local t = Workspace:GetServerTimeNow()
	-- Dummy: respawn at home after flying off.
	if dummy then
		local root = dummy.root
		if not S.PlayerStateService.isAlive(dummy) or (root and root.Position.Y < ArenaLayout.LobbyVoidY) then
			if not dummy.respawnAt then
				dummy.respawnAt = t + 2
			elseif t >= dummy.respawnAt then
				dummy.respawnAt = nil
				spawnDummy()
			end
		end
	end
	-- Lobby players and spectators who fall off get put back; lost characters are rebuilt.
	for _, c in S.PlayerStateService.realPlayers() do
		if not S.PlayerStateService.isAlive(c) then
			if c.inMatch and c.status == "Active" then
				S.MatchService.onCharacterLost(c)
			end
			local pos = if c.inMatch and c.status == "Jailed"
				then ArenaLayout.jailCenter(c.team) + Vector3.new(0, 3, 0)
				else ArenaLayout.lobbySpawn(rng)
			S.CharacterService.spawnPlayer(c, CFrame.new(pos))
		elseif (c.status == "Lobby" or c.status == "Spectating") and c.root.Position.Y < ArenaLayout.LobbyVoidY then
			if math.abs(c.root.Position.Z - Config.Arena.LobbyOrigin.Z) < 200 then
				S.CharacterService.teleport(c, ArenaLayout.lobbySpawn(rng))
			end
		end
	end
end

return LobbyService
