--!strict
-- Plays the finisher cutscene for the match-ending knockout (server event "Finisher"). Loads the
-- named module from ReplicatedStorage.Shared.Finishers and always restores the camera and HUD,
-- even if a finisher errors. See Shared/Finishers/README.md for the module contract.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)

local player = Players.LocalPlayer
local Finishers = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Finishers")

local FinisherController = {}

FinisherController.playing = false

local function rootOf(model: any): BasePart?
	if typeof(model) == "Instance" and model:IsA("Model") then
		return model:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

local function runFor(seconds: number, fn: (number, number) -> ())
	local start = os.clock()
	local done = false
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local alpha = math.clamp((os.clock() - start) / math.max(seconds, 1e-3), 0, 1)
		local ok: boolean, err: any = pcall(fn :: any, alpha, dt)
		if not ok then
			warn("[Finisher] " .. tostring(err))
			done = true
		end
		if alpha >= 1 then
			done = true
		end
		if done then
			conn:Disconnect()
		end
	end)
	while not done do
		task.wait()
	end
end

local function restore()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then
		camera.CameraSubject = h
	end
	HUDController.setCinematic(false)
	FinisherController.playing = false
end

local function play(d: any)
	local moduleScript = Finishers:FindFirstChild(tostring(d.module)) or Finishers:FindFirstChild("Default")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return
	end
	local ok, def = pcall(require, moduleScript)
	if not ok or type(def) ~= "table" or type(def.play) ~= "function" then
		return
	end
	FinisherController.playing = true
	HUDController.setCinematic(true)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local Config = require(ReplicatedStorage.Shared.Config)
	local ctx = {
		camera = camera,
		killer = d.killer,
		victim = d.victim,
		killerName = tostring(d.killerName or "?"),
		victimName = tostring(d.victimName or "?"),
		winnerColor = if d.winner and Config.Teams[d.winner] then Config.Teams[d.winner].Color else Color3.new(1, 1, 1),
		duration = tonumber(d.duration) or 3,
		reducedMotion = HUDController.settings.ReducedMotion,
		banner = function(text: string, color: Color3?, seconds: number?)
			HUDController.banner(text, color, seconds)
		end,
		runFor = runFor,
		rootOf = rootOf,
	}
	local finished = false
	task.spawn(function()
		local okPlay, err = pcall(def.play, ctx)
		if not okPlay then
			warn("[Finisher] " .. tostring(err))
		end
		finished = true
	end)
	-- hard stop at the server's duration so the next phase is never blocked
	local deadline = os.clock() + ctx.duration + 0.2
	while not finished and os.clock() < deadline do
		task.wait()
	end
	restore()
end

function FinisherController.init() end

function FinisherController.start()
	Net.on("Finisher", function(d)
		if not FinisherController.playing then
			play(d)
		end
	end)
end

return FinisherController
