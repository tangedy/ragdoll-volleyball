--!strict
-- Outlines that make players and balls stand out from the court (client only). Each team is
-- outlined in the other team's color, so a blue player on the blue floor still pops, and every
-- ball gets a dark ink outline. Outline only: no fill and no glow. Hub players (no team) aren't
-- outlined. Roblox draws at most 31 Highlights at once, which a full match stays well under.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local OutlineController = {}

local NAME = "RD_Outline"

local function outline(target: Instance): Highlight
	local h = target:FindFirstChild(NAME) :: Highlight?
	if h then
		return h
	end
	local new = Instance.new("Highlight")
	new.Name = NAME
	new.FillTransparency = 1
	new.OutlineTransparency = 0
	new.DepthMode = Enum.HighlightDepthMode.Occluded
	new.Parent = target
	return new
end

-- Show or hide a ball's outline (BallVisualController hides the server ball while it draws the
-- flight itself).
function OutlineController.setBallShown(part: BasePart, shown: boolean)
	local h = part:FindFirstChild(NAME) :: Highlight?
	if h then
		h.Enabled = shown
	end
end

local function watchCharacter(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function refresh()
		local team = model:GetAttribute("Team")
		local color = if type(team) == "string" then Config.Visuals.TeamOutline[team] else nil
		if color then
			local h = outline(model)
			h.OutlineColor = color
			h.Enabled = true
		else
			local h = model:FindFirstChild(NAME) :: Highlight?
			if h then
				h.Enabled = false
			end
		end
	end
	model:GetAttributeChangedSignal("Team"):Connect(refresh)
	refresh()
end

local function isBall(d: Instance): boolean
	return d:IsA("BasePart")
		and (d.Name == "BallVisual" or d.Name == "PracticeBall" or type(d:GetAttribute("BallId")) == "number")
end

local function onDescendant(d: Instance)
	if isBall(d) then
		outline(d).OutlineColor = Config.Visuals.BallOutline
	end
end

function OutlineController.init() end

function OutlineController.start()
	for _, m in Workspace:GetChildren() do
		watchCharacter(m)
	end
	Workspace.ChildAdded:Connect(watchCharacter)
	task.spawn(function()
		local bots = Workspace:WaitForChild("Bots", 60)
		if bots then
			for _, m in bots:GetChildren() do
				watchCharacter(m)
			end
			bots.ChildAdded:Connect(watchCharacter)
		end
	end)
	for _, d in Workspace:GetDescendants() do
		onDescendant(d)
	end
	Workspace.DescendantAdded:Connect(onDescendant)
end

return OutlineController
