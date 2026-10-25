--!strict
-- Studio-only debug overlay (F8): leak counters and the hit-outcome tally used for knockback
-- tuning. Reads ReplicatedStorage.DebugStats, which the server only publishes in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local DebugController = {}

local gui: ScreenGui
local text: TextLabel

local ORDER = { "Rigs", "Sockets", "Balls", "BotModels", "Instances", "Hits" }

local function render()
	local folder = ReplicatedStorage:FindFirstChild("DebugStats")
	if not folder then
		text.Text = "no DebugStats yet"
		return
	end
	local attrs = folder:GetAttributes()
	local lines = {}
	for _, k in ORDER do
		table.insert(lines, ("%s: %s"):format(k, tostring(attrs[k] or 0)))
	end
	-- hit outcomes by distance to the void edge when hit
	for _, bucket in { "Center", "Mid", "Edge" } do
		local rec = attrs["Recovered_" .. bucket] or 0
		local void = attrs["Void_" .. bucket] or 0
		local total = rec + void
		local pct = if total > 0 then math.floor(void / total * 100 + 0.5) else 0
		table.insert(lines, ("%s hits: %d recovered / %d void (%d%% void)"):format(bucket, rec, void, pct))
	end
	local keys = {}
	for k in attrs do
		if string.sub(k, 1, 7) == "VoidKO_" or string.sub(k, 1, 5) == "Hits_" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	for _, k in keys do
		table.insert(lines, ("%s: %s"):format(k, tostring(attrs[k])))
	end
	text.Text = table.concat(lines, "\n")
end

function DebugController.init()
	if not RunService:IsStudio() then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Debug"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	text = Instance.new("TextLabel")
	text.Position = UDim2.new(0, 10, 0.3, 0)
	text.Size = UDim2.fromOffset(360, 300)
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.BackgroundTransparency = 0.35
	text.TextColor3 = Color3.fromRGB(180, 255, 180)
	text.Font = Enum.Font.Code
	text.TextSize = 14
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Parent = gui
end

function DebugController.start()
	if not RunService:IsStudio() then
		return
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			gui.Enabled = not gui.Enabled
		end
	end)
	task.spawn(function()
		while true do
			if gui.Enabled then
				render()
			end
			task.wait(0.5)
		end
	end)
end

return DebugController
