--!strict
-- Smash-style damage % over every opponent's head (Config.Damage). The server keeps the % in each
-- character's Damage attribute; this only draws it. Your own % is on the HUD (HUDController).
-- Shown only for enemies on court: teammates, jailed players and the hub stay clean.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProjectileMath = require(Shared.ProjectileMath)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer

local DamageController = {}

local tags: { [Model]: { board: BillboardGui, label: TextLabel, shown: number } } = {}

local function refresh(model: Model)
	local t = tags[model]
	if not t then
		return
	end
	local myTeam = player:GetAttribute("Team")
	local team = model:GetAttribute("Team")
	local damage = tonumber(model:GetAttribute("Damage")) or 0
	t.board.Enabled = type(myTeam) == "string"
		and myTeam ~= ""
		and type(team) == "string"
		and team ~= ""
		and team ~= myTeam
		and model:GetAttribute("Status") == "Active"
	t.label.Text = ("%d%%"):format(damage)
	t.label.TextColor3 = ProjectileMath.damageColor(damage)
	if damage > t.shown and t.board.Enabled and not Theme.settings.reducedMotion then
		Theme.pop(t.label, 1.5, Theme.Motion.Base)
	end
	t.shown = damage
end

local function track(model: Model)
	if tags[model] or model == player.Character then
		return
	end
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if not head or not model.Parent then
		return
	end
	-- sits just above the name tag (CharacterService), shrinking with distance like it does
	local board = Theme.new("BillboardGui", {
		Name = "DamageTag",
		Size = UDim2.new(2.4, 48, 1, 22),
		StudsOffset = Vector3.new(0, 4, 0),
		MaxDistance = 110,
		LightInfluence = 0,
		Enabled = false,
	}, nil)
	local label = Theme.label(board, { Size = UDim2.fromScale(1, 1) }, 3)
	board.Adornee = head
	board.Parent = head
	tags[model] = { board = board, label = label, shown = tonumber(model:GetAttribute("Damage")) or 0 }
	for _, key in { "Damage", "Team", "Status" } do
		model:GetAttributeChangedSignal(key):Connect(function()
			refresh(model)
		end)
	end
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			tags[model] = nil
		end
	end)
	refresh(model)
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(model)
		task.spawn(track, model)
	end)
	if other.Character then
		task.spawn(track, other.Character)
	end
end

function DamageController.start()
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	-- bots live in the Bots folder (ArenaService makes it)
	task.spawn(function()
		local bots = Workspace:WaitForChild("Bots", 30)
		if not bots then
			return
		end
		bots.ChildAdded:Connect(function(m)
			if m:IsA("Model") then
				task.spawn(track, m)
			end
		end)
		for _, m in bots:GetChildren() do
			if m:IsA("Model") then
				task.spawn(track, m)
			end
		end
	end)
	-- joining or leaving a team flips who counts as an opponent
	player:GetAttributeChangedSignal("Team"):Connect(function()
		for model in tags do
			refresh(model)
		end
	end)
end

return DamageController
