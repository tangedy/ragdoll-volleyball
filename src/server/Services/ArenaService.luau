--!strict
-- Owns the built arena and overtime court shrinking (spec §6 "Overtime").

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local LobbyBuilder = require(script.Parent.LobbyBuilder)

local ArenaService = {}

local arena: Folder
local lobby: Folder
local overtimeSteps = 0
local stripState: { [BasePart]: { color: Color3, cframe: CFrame } } = {}
local rimHome: { [BasePart]: CFrame } = {}

-- Show or hide one glowing rim piece (neon bar, light, sparks and curtain).
local function setRimVisible(rim: BasePart, on: boolean)
	rim.Transparency = if on then 0 else 1
	for _, d in rim:GetDescendants() do
		if d:IsA("SurfaceLight") or d:IsA("ParticleEmitter") or d:IsA("SurfaceGui") then
			(d :: any).Enabled = on
		end
	end
end

-- Only the current outer edge shows a side rim; back-rim pieces of dropped strips go dark.
local function syncRims(steps: number)
	for _, w in CollectionService:GetTagged("EdgeWall") do
		local level = w:GetAttribute("WallLevel")
		if w:IsA("BasePart") and level then
			w.CanCollide = level == steps + 1
		end
	end
	for rim in rimHome do
		local level = rim:GetAttribute("RimLevel")
		local stripIndex = rim:GetAttribute("StripIndex")
		if level then
			setRimVisible(rim, level == steps + 1)
		elseif stripIndex then
			local dropped = (stripIndex :: number) <= steps
			setRimVisible(rim, not dropped)
			rim.CFrame = if dropped then rimHome[rim] - Vector3.new(0, 40, 0) else rimHome[rim]
		end
	end
end
local S: any

ArenaService.Collidable = nil :: Folder?

function ArenaService.init(services: any)
	S = services
	arena = ArenaBuilder.build()
	lobby = LobbyBuilder.build()
	-- The default place template's Baseplate/SpawnLocation sit far below and ruin the floating-void
	-- look. Hide them for this session only (nothing in the saved place is changed).
	for _, name in { "Baseplate", "SpawnLocation" } do
		local p = Workspace:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false
			for _, d in p:GetChildren() do
				if d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = 1
				end
			end
		end
	end
	ArenaService.Collidable = arena:FindFirstChild("Collidable") :: Folder
	for _, p in CollectionService:GetTagged("CourtStrip") do
		if p:IsA("BasePart") and p:IsDescendantOf(arena) then
			stripState[p] = { color = p.Color, cframe = p.CFrame }
		end
	end
	for _, r in CollectionService:GetTagged("CourtRim") do
		if r:IsA("BasePart") and r:IsDescendantOf(arena) then
			rimHome[r] = r.CFrame
		end
	end
	syncRims(0)
	-- Balls, bots and the dummy live in their own folders.
	for _, name in { "Balls", "Bots" } do
		if not Workspace:FindFirstChild(name) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = Workspace
		end
	end
end

function ArenaService.getOvertimeSteps(): number
	return overtimeSteps
end

-- Parts a projectile treats as solid scenery: the court for match balls, the hub deck for
-- practice balls. The two never see each other's scenery.
function ArenaService.sceneryList(context: string?): { Instance }
	if context == "Lobby" then
		return { lobby:FindFirstChild("Collidable") :: Instance, lobby:FindFirstChild("Barriers") :: Instance }
	end
	return { arena:FindFirstChild("Collidable") :: Instance }
end

function ArenaService.lobbyFolder(): Folder
	return lobby
end

-- Highlight the next unsafe strips (one-second warning), then retract them.
function ArenaService.warnStrips(step: number)
	for p in stripState do
		if p:GetAttribute("StripIndex") == step then
			p.Color = Color3.fromRGB(255, 60, 60)
			p.Material = Enum.Material.Neon
		end
	end
end

function ArenaService.retractStrips(step: number)
	overtimeSteps = math.max(overtimeSteps, step)
	for p in stripState do
		if p:GetAttribute("StripIndex") == step then
			-- Visibly drop the strip rather than making an invisible floor change.
			p.CanCollide = false
			p.CanQuery = false
			p.Transparency = 0.6
			p.CFrame = p.CFrame - Vector3.new(0, 40, 0)
		end
	end
	syncRims(overtimeSteps)
	ArenaService.setAttr()
end

function ArenaService.resetCourt()
	overtimeSteps = 0
	for p, st in stripState do
		p.CanCollide = true
		p.CanQuery = true
		p.Transparency = 0
		p.Color = st.color
		p.Material = Enum.Material.WoodPlanks
		p.CFrame = st.cframe
	end
	syncRims(0)
	ArenaService.setAttr()
end

function ArenaService.setAttr()
	if S and S.MatchService then
		S.MatchService.setAttr("OvertimeSteps", overtimeSteps)
	end
end

function ArenaService.dispenserPad(team: string, slot: number): BasePart
	return (arena:FindFirstChild("Decor") :: Folder):FindFirstChild(("Dispenser_%s_%d"):format(team, slot)) :: BasePart
end

function ArenaService.dispenserPosition(team: string, slot: number): Vector3
	return ArenaService.dispenserPad(team, slot).Position + Vector3.new(0, 2, 0)
end

-- The text over a dispenser pad (the "?" BillboardGui ArenaBuilder puts on it).
function ArenaService.setDispenserLabel(team: string, slot: number, text: string, color: Color3?)
	local bb = ArenaService.dispenserPad(team, slot):FindFirstChildOfClass("BillboardGui")
	local t = bb and bb:FindFirstChildOfClass("TextLabel")
	if t and t.Text ~= text then
		t.Text = text
	end
	if t and color then
		t.TextColor3 = color
	end
end

return ArenaService
