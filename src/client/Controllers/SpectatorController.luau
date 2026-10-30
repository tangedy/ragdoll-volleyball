--!strict
-- Simple spectating (spec §10 "Elimination"): after the fall, follow a living teammate and allow
-- switching. Kept separate from active-player controls.
-- The same view also serves the hub: while a match is running, the Spectate action lets a lobby
-- player watch everyone on the court. That mode is purely client-side (the server still sees a
-- "Lobby" player), so it never holds anyone out of the next match: it ends on its own when the match
-- does, or the moment the player is pulled onto the court.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local ShopController = require(script.Parent.ShopController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer

local SpectatorController = {}

-- MatchState phases with a match on the court (anything but WaitingForPlayers / Intermission)
local LIVE = { Intro = true, RoundCountdown = true, RoundActive = true, RoundResolution = true, Finisher = true }

local index = 1
local active = false
local hubWatching = false -- watching from the hub (the Spectate action) rather than knocked out
local gui: ScreenGui
local nameLabel: TextLabel
local exitButton: TextButton
local spectateAction: TextButton

local function matchLive(): boolean
	return LIVE[Net.MatchState:GetAttribute("State") :: any] == true
end

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

-- Who can be watched: living teammates when knocked out, anyone on the court from the hub.
local function targets(): { Model }
	local team = player:GetAttribute("Team")
	local list = {}
	local function scan(parent: Instance)
		for _, m in parent:GetChildren() do
			if
				m:IsA("Model")
				and m ~= player.Character
				and (hubWatching or m:GetAttribute("Team") == team)
				and m:GetAttribute("Status") == "Active"
			then
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
		local ta, tb = tostring(a:GetAttribute("Team")), tostring(b:GetAttribute("Team"))
		if ta ~= tb then
			return ta < tb
		end
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
	ShopController.hubHidden = on and hubWatching
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
	-- a surface pill: round back/next buttons either side of who you're watching
	local bar = Theme.panel(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(400, 68),
	}, 34)
	Theme.autoScale(bar)
	local function arrow(glyph: string, left: boolean, delta: number)
		local b = Theme.iconButton(bar, glyph, "secondary", 48, {
			AnchorPoint = Vector2.new(if left then 0 else 1, 0.5),
			Position = if left then UDim2.new(0, 10, 0.5, 0) else UDim2.new(1, -10, 0.5, 0),
		})
		b.Activated:Connect(function()
			switch(delta)
		end)
	end
	arrow("back", true, -1)
	arrow("next", false, 1)
	Theme.body(bar, {
		Position = UDim2.fromOffset(70, 10),
		Size = UDim2.new(1, -140, 0, 16),
		FontFace = Theme.TextFace,
		Text = "Spectating",
	})
	nameLabel = Theme.label(bar, {
		Position = UDim2.fromOffset(70, 28),
		Size = UDim2.new(1, -140, 0, 28),
		Text = "",
	}, 0)
	-- back to the hub (hub watchers only: the knocked-out wait for the next round)
	exitButton = Theme.iconButton(bar, "close", "secondary", 40, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 2),
		Visible = false,
		back = true,
	})
	exitButton.Activated:Connect(function()
		SpectatorController.setHubWatching(false)
	end)
end

function SpectatorController.setHubWatching(on: boolean)
	on = on and matchLive() and inHub()
	if on == hubWatching then
		return
	end
	if active then
		setActive(false) -- hands the camera back before the mode changes
	end
	hubWatching = on
	index = 1
	exitButton.Visible = on
end

function SpectatorController.start()
	-- the hub's Spectate action: on the touch row it folds behind the hamburger like the rest
	spectateAction = ShopController.addAction("Spectate", Theme.Toybox.sky, "eye", -2, function()
		SpectatorController.setHubWatching(true)
	end)
	spectateAction.Visible = false
	local spectateSince = 0
	RunService.RenderStepped:Connect(function()
		local status = player:GetAttribute("Status")
		local live = matchLive()
		spectateAction.Visible = live and not active
		-- the match ending, or the lobby pulling you in, ends hub watching on its own
		if hubWatching and not (live and inHub()) then
			SpectatorController.setHubWatching(false)
		end
		local spectating = status == "Spectating"
		if spectating and spectateSince == 0 then
			spectateSince = os.clock()
		elseif not spectating then
			spectateSince = 0
		end
		-- briefly show the launch and fall before switching to a teammate
		local want = hubWatching or (spectating and os.clock() - spectateSince > 1.6)
		local list = if want then targets() else {}
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
