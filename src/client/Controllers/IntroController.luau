--!strict
-- Match intro (client), Splatoon-style. At the start of a match the server lines both teams up on
-- their spawns (state "Intro") and every client plays each player's equipped intro pose, bots
-- included. Players in the match get the camera: a letterboxed dolly across the BLUE team for
-- Config.Intro.BlueTime seconds, then across the RED team for RedTime, then the normal 3-2-1
-- countdown takes over. Everything is restored when the countdown starts (or if anything errors).
-- Also powers the shop's pose TRY button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local FinisherController = require(script.Parent.FinisherController)
local PoseKit = require(script.Parent.PoseKit)
local SoundController = require(script.Parent.SoundController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local I = Config.Intro

local IntroController = {}

IntroController.playing = false

local finish: (() -> ())? = nil

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

-- Team name caption under the letterbox ("BLUE TEAM").
local function caption(): (TextLabel, () -> ())
	local gui = Theme.new("ScreenGui", {
		Name = "IntroCaption",
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 16,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	local label = Theme.label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromScale(0.6, 0.07),
		Text = "",
		TextTransparency = 1,
	}, 3)
	local grad = Theme.gradient(label, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	grad.Name = "TeamTint"
	return label, function()
		gui:Destroy()
	end
end

local function showTeam(label: TextLabel, team: string)
	local t = Config.Teams[team]
	local grad = label:FindFirstChild("TeamTint") :: UIGradient?
	if grad then
		grad.Color = ColorSequence.new(Theme.lighten(t.Color, 0.6), t.Color)
	end
	label.Text = ("%s TEAM"):format(t.Name)
	label.TextTransparency = 1
	Theme.tween(label, 0.25, { TextTransparency = 0 })
	Theme.pop(label, 1.4, 0.35)
end

-- One shot along a team's line-up: in front of them at chest height, sliding from one end to the
-- other while looking slightly ahead.
local function panShot(camera: Camera, team: any, a: number)
	local center: Vector3 = team.center
	local facing: Vector3 = team.facing
	local side = facing:Cross(Vector3.yAxis)
	local half = (team.halfWidth or 8) + I.PanOvershoot
	local e = smooth(a)
	local x = -half + 2 * half * e
	local pos = center + facing * I.CameraBack + Vector3.new(0, I.CameraUp, 0) + side * x
	local look = center + Vector3.new(0, 1.2, 0) + side * (x + I.LookAhead)
	camera.CFrame = CFrame.lookAt(pos, look)
end

local function cameraMoment(d: any): () -> ()
	local camera = Workspace.CurrentCamera
	local fov = camera.FieldOfView
	HUDController.setCinematic(true)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = I.FieldOfView
	local closeBars = FinisherController.letterbox()
	local label, closeCaption = caption()
	local t0 = os.clock()
	local shown = ""
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		-- shot 1: the first team, shot 2: the second; hold the last frame if we're early
		local acc = 0
		for i, teamName in d.order do
			local dur = d.times[i]
			local team = d.teams[teamName]
			if team and (t < acc + dur or i == #d.order) then
				if shown ~= teamName then
					shown = teamName
					showTeam(label, teamName)
					SoundController.play("IntroStinger")
				end
				panShot(camera, team, math.clamp((t - acc) / dur, 0, 1))
				break
			end
			acc += dur
		end
	end)
	return function()
		conn:Disconnect()
		closeBars()
		closeCaption()
		camera.FieldOfView = fov
		camera.CameraType = Enum.CameraType.Custom
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			camera.CameraSubject = h
		end
		HUDController.setCinematic(false)
	end
end

local function stop()
	local f = finish
	finish = nil
	if f then
		f()
	end
end

function IntroController.play(d: any)
	if type(d.teams) ~= "table" or type(d.order) ~= "table" or type(d.times) ~= "table" then
		return
	end
	stop()
	IntroController.playing = true
	local stops = {}
	for _, team in d.teams do
		for _, m in team.members do
			if typeof(m.model) == "Instance" then
				table.insert(stops, PoseKit.playSequence(m.model, m.pose))
			end
		end
	end
	local endCamera: (() -> ())? = nil
	if d.cinematic and not FinisherController.playing then
		local ok, result = pcall(cameraMoment, d)
		endCamera = if ok then result else nil
	end
	finish = function()
		for _, s in stops do
			s()
		end
		if endCamera then
			endCamera()
		end
		IntroController.playing = false
	end
	local total = 0
	for _, t in d.times do
		total += t
	end
	local mine = finish
	task.delay(total + 0.5, function()
		if finish == mine then
			stop() -- safety net; normally the countdown starting ends it
		end
	end)
end

-- Shop TRY button: strike a pose on your own character for a moment (local only).
function IntroController.preview(poseId: string)
	local character = player.Character
	if not character or IntroController.playing then
		return
	end
	local s = PoseKit.playSequence(character, poseId)
	task.delay(2.6, s)
end

function IntroController.init() end

function IntroController.start()
	Net.on("Intro", IntroController.play)
	-- the countdown starting ends the intro immediately, before the round-start camera swing
	Net.MatchState:GetAttributeChangedSignal("State"):Connect(function()
		if Net.MatchState:GetAttribute("State") ~= "Intro" then
			stop()
		end
	end)
end

return IntroController
