--!strict
-- Victory moment (client). When the server lines the winning team up (state "Victory", after the
-- finisher and the "WINS!" banner), every client plays each winner's equipped victory pose on
-- their character, bots included. Players who were in the match also get a short camera move: a
-- letterboxed push-in from in front of the line, with a caption. Everything is restored when it
-- ends (or if anything errors), before the results card arrives. Also powers the shop's pose TRY.

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
local V = Config.Victory

local VictoryController = {}

VictoryController.playing = false

local function ease(a: number): number
	return if a < 0.5 then 4 * a * a * a else 1 - (-2 * a + 2) ^ 3 / 2
end

-- Caption under the letterbox: "RED TEAM WINS".
local function caption(text: string, color: Color3): () -> ()
	local gui = Theme.new("ScreenGui", {
		Name = "VictoryCaption",
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 16,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	local label = Theme.label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromScale(0.6, 0.07),
		Text = text,
		TextTransparency = 1,
	}, 3)
	Theme.gradient(label, Theme.lighten(color, 0.6), color)
	Theme.tween(label, 0.4, { TextTransparency = 0 })
	Theme.pop(label, 1.4, 0.4)
	return function()
		Theme.tween(label, 0.25, { TextTransparency = 1 })
		task.delay(0.3, function()
			gui:Destroy()
		end)
	end
end

local function cameraMoment(d: any): () -> ()
	local camera = Workspace.CurrentCamera
	local fov = camera.FieldOfView
	HUDController.setCinematic(true)
	camera.CameraType = Enum.CameraType.Scriptable
	local closeBars = FinisherController.letterbox()
	local team = Config.Teams[d.winner]
	local closeCaption = caption(("%s TEAM WINS"):format(if team then team.Name else "?"), if team then team.Color else Color3.new(1, 1, 1))
	local center: Vector3 = d.center
	local facing: Vector3 = d.facing
	local side = facing:Cross(Vector3.yAxis)
	local look = center + Vector3.new(0, 1.5, 0)
	local reduced = HUDController.settings.ReducedMotion
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / math.max(d.duration, 0.1), 0, 1)
		local e = if reduced then 0.5 else ease(a)
		local back = V.CameraFrom.Back + (V.CameraTo.Back - V.CameraFrom.Back) * e
		local up = V.CameraFrom.Up + (V.CameraTo.Up - V.CameraFrom.Up) * e
		-- a gentle arc across the line while pushing in
		local arc = if reduced then 0 else math.sin(e * math.pi - math.pi / 2) * 6
		camera.CFrame = CFrame.lookAt(center + facing * back + Vector3.new(0, up, 0) + side * arc, look)
		camera.FieldOfView = fov - 8 * e
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

function VictoryController.play(d: any)
	if VictoryController.playing or type(d.members) ~= "table" then
		return
	end
	VictoryController.playing = true
	local stops = {}
	for _, m in d.members do
		if typeof(m.model) == "Instance" then
			table.insert(stops, PoseKit.playSequence(m.model, m.pose))
		end
	end
	SoundController.play("Victory")
	local endCamera: (() -> ())? = nil
	if d.cinematic and not FinisherController.playing then
		local ok, result = pcall(cameraMoment, d)
		endCamera = if ok then result else nil
	end
	task.delay(math.max(d.duration or V.Duration, 0.5), function()
		for _, stop in stops do
			stop()
		end
		if endCamera then
			endCamera()
		end
		VictoryController.playing = false
	end)
end

-- Shop TRY button: strike a pose on your own character for a moment (local only).
function VictoryController.preview(poseId: string)
	local character = player.Character
	if not character or VictoryController.playing then
		return
	end
	local stop = PoseKit.playSequence(character, poseId)
	task.delay(2.6, stop)
end

function VictoryController.init() end

function VictoryController.start()
	Net.on("Victory", VictoryController.play)
end

return VictoryController
