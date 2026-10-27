--!strict
-- Builds standardized R15 characters for players, bots and the dummy (spec §11: consistent avatar
-- scaling so body size and accessories never decide competitive outcomes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local CharacterService = {}

local S: any

function CharacterService.init(services: any)
	S = services
end

local function normalize(desc: HumanoidDescription)
	desc.HeightScale = 1
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
end

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = "Characters"
	end
end

local function makeTag(character: Model, c: any)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	-- part studs, part pixels: tags shrink with distance (so a crowd across the court doesn't stack
	-- into one unreadable pile) but never below a legible floor
	bb.Size = UDim2.new(3.6, 70, 1, 20)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 110
	bb.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Name = "NameLabel"
	name.Size = UDim2.fromScale(1, 0.6)
	name.Position = UDim2.fromScale(0, 0.4)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.3
	name.Text = c.name
	name.Parent = bb
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Size = UDim2.fromScale(1, 0.38)
	badge.BackgroundTransparency = 1
	badge.Font = Enum.Font.GothamBlack
	badge.TextScaled = true
	badge.TextColor3 = Color3.fromRGB(255, 230, 120)
	badge.TextStrokeTransparency = 0.3
	badge.Text = if c.isBot then "BOT" elseif c.isDummy then "DUMMY" else ""
	badge.Parent = bb
	bb.Parent = head
end

-- Shared character preparation: collision groups, gameplay hit proxy, ragdoll rig, humanoid settings.
function CharacterService.prepare(character: Model, c: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Player.JumpPower
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)

	-- Separate gameplay hit proxy: a fixed box, independent of cosmetic limbs and accessories.
	local proxy = Instance.new("Part")
	proxy.Name = "HitProxy"
	proxy.Size = Config.Player.HitProxySize
	proxy.Transparency = 1
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = true
	proxy.Massless = true
	proxy.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = proxy
	weld.Parent = proxy
	proxy.Parent = character

	-- Team band so teams read clearly with default avatars.
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		local band = Instance.new("Part")
		band.Name = "TeamBand"
		band.Size = Vector3.new(2.2, 0.5, 1.3)
		band.CanCollide = false
		band.CanQuery = false
		band.CanTouch = false
		band.Massless = true
		band.Material = Enum.Material.Neon
		band.Color = Color3.fromRGB(200, 200, 200)
		band.CFrame = torso.CFrame * CFrame.new(0, -0.2, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = band
		w.Parent = band
		band.Parent = character
	end

	makeTag(character, c)
	S.RagdollService.prepare(character)
end

function CharacterService.setTeamVisual(c: any)
	local character = c.character
	if not character then
		return
	end
	local band = character:FindFirstChild("TeamBand") :: BasePart?
	local color = if c.team and Config.Teams[c.team] then Config.Teams[c.team].Color else Color3.fromRGB(200, 200, 200)
	if band then
		band.Color = color
	end
	local head = character:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("NameTag")
	local label = tag and tag:FindFirstChild("NameLabel") :: TextLabel?
	if label then
		label.TextColor3 = if c.team then color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1)
	end
end

function CharacterService.setBadge(c: any, text: string)
	local character = c.character
	local head = character and character:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("NameTag")
	local badge = tag and tag:FindFirstChild("Badge") :: TextLabel?
	if badge then
		badge.Text = text
	end
end

-- Build a normalized R15 rig from a description and attach it to the combatant.
function CharacterService.spawn(c: any, desc: HumanoidDescription, cf: CFrame)
	normalize(desc)
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = c.name
	model:PivotTo(cf)
	CharacterService.prepare(model, c)
	local old = c.character
	if c.player then
		model.Parent = Workspace
		c.player.Character = model
	else
		model.Parent = Workspace:FindFirstChild("Bots") or Workspace
		local animate = model:FindFirstChild("Animate")
		if animate then
			-- keep the avatar's animation pack (filled in from the description) for BotService
			c.animIds = {}
			for _, key in { "idle", "walk", "run", "jump", "fall" } do
				local slot = animate:FindFirstChild(key)
				local anim = slot and slot:FindFirstChildWhichIsA("Animation")
				if anim and anim.AnimationId ~= "" then
					c.animIds[key] = anim.AnimationId
				end
			end
			animate:Destroy() -- LocalScript cannot run on a server-owned rig; BotService animates
		end
	end
	S.PlayerStateService.attachCharacter(c, model)
	S.CharacterService.setTeamVisual(c)
	if c.isBot or c.isDummy then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	if old and old ~= model then
		old:Destroy()
	end
	return model
end

function CharacterService.spawnPlayer(c: any, cf: CFrame)
	local player = c.player :: Player
	-- the avatar is fetched from the web once per visit; respawns reuse it, so falling off the hub
	-- or rejoining a round never waits on (or gets throttled by) a web request
	local cached = c.avatarDesc :: HumanoidDescription?
	if not cached then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(math.max(1, player.UserId))
		end)
		if ok and desc then
			cached = desc
			c.avatarDesc = desc
		end
	end
	local d = if cached then cached:Clone() else Instance.new("HumanoidDescription")
	return CharacterService.spawn(c, d, cf)
end

function CharacterService.teleport(c: any, pos: Vector3, lookAt: Vector3?)
	local character = c.character
	if not character then
		return
	end
	local target = lookAt or (pos + Vector3.zAxis)
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.1 then
		flat = pos + Vector3.zAxis
	end
	if S.RagdollService.isRagdolled(character) then
		S.RagdollService.recover(character, pos)
	end
	local root = c.root
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	character:PivotTo(CFrame.lookAt(pos, flat))
end

-- Put someone in the hub (or jail) facing the court, and swing their camera round to look at it
-- too, so they see the action straight away instead of whatever way they were facing.
function CharacterService.placeFacing(c: any, pos: Vector3, focus: Vector3)
	CharacterService.teleport(c, pos, focus)
	CharacterService.faceCamera(c, focus)
end

function CharacterService.faceCamera(c: any, focus: Vector3)
	if c.player then
		S.NetService.send(c.player, "FaceCourt", { focus = focus })
	end
end

return CharacterService
