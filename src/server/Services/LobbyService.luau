--!strict
-- Player join/leave, lobby spawning, the hub leaderboard, auto-queue toggle. The practice dummy and
-- practice balls are client-side (PracticeController); the server only builds the dummy's look as a
-- template in ReplicatedStorage and advances the tutorial from the client's practice events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ArenaLayout = require(Shared.ArenaLayout)
local NetSchema = require(Shared.NetSchema)

local LobbyService = {}

local S: any
local rng = Random.new()

function LobbyService.init(services: any)
	S = services
end

-- The practice dummy's rig, built once (a standard R15 in dummy colors). Each client clones it into
-- its own hub and simulates it locally.
local function buildDummyTemplate()
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = Color3.fromRGB(240, 200, 90)
	desc.TorsoColor = Color3.fromRGB(240, 200, 90)
	desc.LeftArmColor = Color3.fromRGB(240, 200, 90)
	desc.RightArmColor = Color3.fromRGB(240, 200, 90)
	desc.LeftLegColor = Color3.fromRGB(200, 160, 70)
	desc.RightLegColor = Color3.fromRGB(200, 160, 70)
	desc.BodyTypeScale = 0 -- same normalized proportions as every other rig
	desc.ProportionScale = 0
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Lobby] couldn't build the practice dummy template")
		return
	end
	model.Name = Config.Practice.TemplateName
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
	model:PivotTo(CFrame.lookAt(ArenaLayout.DummyHome, ArenaLayout.DummyFacing))
	model.Parent = ReplicatedStorage
end

-- The Destiny Arrives titan: built once from the items in Config.Finisher.DestinyAvatar and parked
-- in ReplicatedStorage for the clients' finisher (loading the items is a web call, so it never
-- blocks start-up).
local DESC_FIELDS =
	{ "Head", "Face", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Shirt", "Pants", "GraphicTShirt" }
local ACCESSORY_FIELDS: { [Enum.AccessoryType]: string } = {
	[Enum.AccessoryType.Hat] = "HatAccessory",
	[Enum.AccessoryType.Hair] = "HairAccessory",
	[Enum.AccessoryType.Face] = "FaceAccessory",
	[Enum.AccessoryType.Neck] = "NeckAccessory",
	[Enum.AccessoryType.Shoulder] = "ShouldersAccessory",
	[Enum.AccessoryType.Front] = "FrontAccessory",
	[Enum.AccessoryType.Back] = "BackAccessory",
	[Enum.AccessoryType.Waist] = "WaistAccessory",
}
local function buildDestinyTemplate()
	local F = Config.Finisher
	local look = F.DestinyAvatar
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		for _, field in DESC_FIELDS do
			local id = look[field]
			if type(id) == "number" then
				(desc :: any)[field] = id
			end
		end
		if look.SkinColor then
			for _, field in
				{ "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }
			do
				(desc :: any)[field] = look.SkinColor
			end
		end
		-- rigid accessories go in the per-type id lists (SetAccessories on a fresh description builds a
		-- model without them)
		local byType: { [string]: { string } } = {}
		local list: { any } = look.Accessories or {}
		for _, a in list do
			local field = ACCESSORY_FIELDS[a.AccessoryType]
			if field then
				byType[field] = byType[field] or {}
				table.insert(byType[field], tostring(a.AssetId))
			end
		end
		for field, ids in byType do
			(desc :: any)[field] = table.concat(ids, ",")
		end
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Lobby] couldn't build the Destiny Arrives avatar: " .. tostring(model))
		return
	end
	model.Name = F.DestinyTemplateName
	-- accessories that should ride on a body part instead of where they're hung (the gauntlet on the
	-- hand): the model is built in the rest pose, so keep each exactly where it sits now and just weld
	-- it to that part, matched by accessory type
	local hung: { any } = look.Accessories or {}
	for _, spec in hung do
		local target = if spec.AttachTo then model:FindFirstChild(spec.AttachTo) :: BasePart? else nil
		if not target then
			continue
		end
		for _, acc in model:GetChildren() do
			if acc:IsA("Accessory") and acc.AccessoryType == spec.AccessoryType then
				local handle = acc:FindFirstChild("Handle") :: BasePart?
				if handle then
					-- the model isn't simulated yet, so the handle still sits where it was loaded: first put
					-- it where its own joint holds it (Weld offsets, or a RigidConstraint's attachments),
					-- then swap that joint for a weld to the part, which keeps the offset it has now
					for _, j in handle:GetChildren() do
						if j:IsA("JointInstance") and j.Part0 and j.Part1 then
							if j.Part0 == handle then
								handle.CFrame = j.Part1.CFrame * j.C1 * j.C0:Inverse()
							else
								handle.CFrame = j.Part0.CFrame * j.C0 * j.C1:Inverse()
							end
						elseif j:IsA("RigidConstraint") and j.Attachment0 and j.Attachment1 then
							local mine = if j.Attachment0.Parent == handle then j.Attachment0 else j.Attachment1
							local other = if mine == j.Attachment0 then j.Attachment1 else j.Attachment0
							handle.CFrame = other.WorldCFrame * mine.CFrame:Inverse()
						end
					end
					for _, j in handle:GetChildren() do
						if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("RigidConstraint") then
							j:Destroy()
						end
					end
					-- a Weld with its offset written down, not a WeldConstraint: the model's joints only settle
					-- once a copy is in the workspace (the hand drops about a stud), and a WeldConstraint
					-- would take its offset from that moment, leaving the gauntlet up the forearm
					local weld = Instance.new("Weld")
					weld.Name = "AttachWeld"
					weld.Part0 = target
					weld.Part1 = handle
					weld.C0 = target.CFrame:ToObjectSpace(handle.CFrame)
					weld.Parent = handle
					-- no longer an Accessory: a Humanoid re-joins accessories to their stock attachment
					-- on every copy, and that joint would fight the weld (it pinned the hand in place)
					handle.Name = acc.Name
					handle.Parent = model
					acc:Destroy()
				end
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d.Name == "HumanoidRootPart"
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
	model.Parent = ReplicatedStorage
end

local function onPlayerAdded(player: Player)
	local c = S.PlayerStateService.create(player.DisplayName, player, false, false)
	c.joinedAt = os.clock()
	-- load the save while the avatar downloads, so coins, the daily reward and the spin are ready
	-- the moment the player spawns (the loading screen waits for both)
	local loading = true
	task.spawn(function()
		S.DataService.load(c)
		loading = false
	end)
	task.spawn(S.ComplianceService.load, c)
	local spawn = ArenaLayout.lobbySpawn(rng)
	S.CharacterService.spawnPlayer(
		c,
		CFrame.lookAt(spawn, Vector3.new(ArenaLayout.CourtFocus.X, spawn.Y, ArenaLayout.CourtFocus.Z))
	)
	S.CharacterService.faceCamera(c, ArenaLayout.CourtFocus)
	while loading and player.Parent == Players do
		task.wait()
	end
	if player.Parent ~= Players then
		return
	end
	-- the save may have landed before the character existed: push again so its name tag gets the badge
	S.DataService.push(c)
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
	buildDummyTemplate()
	task.spawn(buildDestinyTemplate)

	S.NetService.on(NetSchema.Actions.SetAutoQueue, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c then
			c.autoQueue = p.value
			player:SetAttribute("AutoQueue", p.value)
		end
	end)
	S.NetService.on(NetSchema.Actions.SetBusy, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c then
			c.busy = p.value
			player:SetAttribute("Busy", p.value)
		end
	end)
	-- Player.DevTouchCameraMode can only be set from the server (LockController asks for Shift lock)
	S.NetService.on(NetSchema.Actions.SetTouchCamera, function(player, p)
		player.DevTouchCameraMode = if p.classic
			then Enum.DevTouchCameraMovementMode.Classic
			else game:GetService("StarterPlayer").DevTouchCameraMovementMode
	end)
	S.NetService.on(NetSchema.Actions.ReportDevice, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c and not (c.devicesSeen and c.devicesSeen[p.kind]) then
			c.devicesSeen = c.devicesSeen or {}
			c.devicesSeen[p.kind] = true
			S.AnalyticsService.event(c, "Device_" .. p.kind)
		end
	end)
	-- Practice (client-side dummy and balls): only advances the tutorial and the onboarding funnel,
	-- never anything that pays or owns. Hub only.
	S.NetService.on(NetSchema.Actions.Practice, function(player, p)
		local c = S.PlayerStateService.get(player)
		if not c or c.inMatch or c.status ~= "Lobby" then
			return
		end
		if p.event == "Pickup" then
			S.AnalyticsService.funnel(c, "PickedUpFirstBall")
		elseif p.event == "Throw" then
			S.AnalyticsService.funnel(c, "ThrewFirstBall")
		elseif p.event == "HitDummy" then
			S.AnalyticsService.funnel(c, "LandedFirstHit")
		end
		S.TutorialService.onEvent(c, p.event)
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

-- Hub leaderboard: everyone on this server, most wins first (then level).
function LobbyService.refreshLeaderboard()
	local stations = S.ArenaService.lobbyFolder():FindFirstChild("Stations")
	local board = stations and stations:FindFirstChild("Leaderboard")
	local gui = board and board:FindFirstChild("Board")
	if not gui then
		return
	end
	local list = {}
	for _, c in S.PlayerStateService.realPlayers() do
		if c.profileLoaded and c.profile then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		if a.profile.Wins ~= b.profile.Wins then
			return a.profile.Wins > b.profile.Wins
		end
		if a.profile.Level ~= b.profile.Level then
			return a.profile.Level > b.profile.Level
		end
		return a.name < b.name
	end)
	for i = 1, Config.Lobby.Leaderboard.Rows do
		local row = gui:FindFirstChild("Row" .. i)
		local c = list[i]
		if row then
			row.Visible = c ~= nil
			if c then
				local function set(column: string, text: string)
					local label = row:FindFirstChild(column)
					if label and label:IsA("TextLabel") then
						label.Text = text
					end
				end
				set("PlayerName", c.name)
				set("Level", tostring(c.profile.Level))
				set("Wins", tostring(c.profile.Wins))
			end
		end
	end
end

local nextBoardAt = 0
function LobbyService.tick()
	if os.clock() >= nextBoardAt then
		nextBoardAt = os.clock() + Config.Lobby.Leaderboard.Refresh
		LobbyService.refreshLeaderboard()
	end
	-- Lobby players and spectators who fall off get put back; lost characters are rebuilt.
	for _, c in S.PlayerStateService.realPlayers() do
		if c.spawning then
			continue -- a character is already being built (avatar download in flight)
		elseif not S.PlayerStateService.isAlive(c) then
			if c.inMatch and c.status == "Active" then
				S.MatchService.onCharacterLost(c)
			end
			local pos = if c.inMatch and (c.status == "Jailed" or c.status == "Spectating")
				then ArenaLayout.jailCenter(c.team) + Vector3.new(0, 3, 0)
				else ArenaLayout.lobbySpawn(rng)
			local focus = ArenaLayout.CourtFocus
			S.CharacterService.spawnPlayer(c, CFrame.lookAt(pos, Vector3.new(focus.X, pos.Y, focus.Z)))
			S.CharacterService.faceCamera(c, focus)
		elseif (c.status == "Lobby" or c.status == "Spectating") and c.root.Position.Y < ArenaLayout.LobbyVoidY then
			-- only falls from the hub deck (spectators following the court fall with the court rules)
			if ArenaLayout.inLobby(c.root.Position, 60) then
				S.CharacterService.placeFacing(c, ArenaLayout.lobbySpawn(rng), ArenaLayout.CourtFocus)
			end
		end
	end
end

return LobbyService
