--!strict
-- Simple spectating (spec §10 "Elimination"): after the fall, follow a living teammate and allow
-- switching. Kept separate from active-player controls.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer

local SpectatorController = {}

local index = 1
local active = false
local gui: ScreenGui
local nameLabel: TextLabel

local function teammates(): { Model }
	local team = player:GetAttribute("Team")
	local list = {}
	local function scan(parent: Instance)
		for _, m in parent:GetChildren() do
			if m:IsA("Model") and m ~= player.Character and m:GetAttribute("Team") == team and m:GetAttribute("Status") == "Active" then
				table.insert(list, m)
			end
		end
	end
	scan(Workspace)
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		scan(bots)
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function switch(delta: number)
	index += delta
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	gui.Enabled = on
	if on then
		ContextActionService:BindAction("RD_SpecPrev", function(_, s)
			if s == Enum.UserInputState.Begin then
				switch(-1)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Z, Enum.KeyCode.DPadLeft)
		ContextActionService:BindAction("RD_SpecNext", function(_, s)
			if s == Enum.UserInputState.Begin then
				switch(1)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.C, Enum.KeyCode.DPadRight)
	else
		ContextActionService:UnbindAction("RD_SpecPrev")
		ContextActionService:UnbindAction("RD_SpecNext")
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			Workspace.CurrentCamera.CameraSubject = h
		end
	end
end

function SpectatorController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Spectator"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")
	local bar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(380, 56),
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.25,
	}, gui)
	Theme.round(bar)
	Theme.stroke(bar, Color3.new(1, 1, 1), 2, 0.8)
	local function arrow(text: string, left: boolean, delta: number)
		local b = Theme.button(bar, text, Theme.Colors.Purple, {
			AnchorPoint = Vector2.new(if left then 0 else 1, 0.5),
			Position = if left then UDim2.new(0, 4, 0.5, 0) else UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(48, 48),
		})
		b.Activated:Connect(function()
			switch(delta)
		end)
	end
	arrow("<", true, -1)
	arrow(">", false, 1)
	Theme.body(bar, {
		Position = UDim2.fromOffset(60, 6),
		Size = UDim2.new(1, -120, 0, 14),
		Text = "SPECTATING",
		TextColor3 = Theme.Colors.Gold,
	})
	nameLabel = Theme.label(bar, {
		Position = UDim2.fromOffset(60, 20),
		Size = UDim2.new(1, -120, 0, 28),
		Text = "",
	}, 2.5)
end

function SpectatorController.start()
	local spectateSince = 0
	RunService.RenderStepped:Connect(function()
		local status = player:GetAttribute("Status")
		local spectating = status == "Spectating"
		if spectating and spectateSince == 0 then
			spectateSince = os.clock()
		elseif not spectating then
			spectateSince = 0
		end
		-- briefly show the launch and fall before switching to a teammate
		local want = spectating and os.clock() - spectateSince > 1.6
		local list = if want then teammates() else {}
		setActive(want and #list > 0)
		if active then
			index = ((index - 1) % #list) + 1
			local target = list[index]
			local h = target:FindFirstChildOfClass("Humanoid")
			if h and Workspace.CurrentCamera.CameraSubject ~= h then
				Workspace.CurrentCamera.CameraSubject = h
			end
			nameLabel.Text = target.Name
		end
	end)
end

return SpectatorController
