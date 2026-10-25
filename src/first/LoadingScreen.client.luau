--!strict
-- Custom loading screen from ReplicatedFirst: no blank world or empty HUD on join.
-- Styled inline (the client UI theme isn't loaded yet this early).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local INK = Color3.fromRGB(16, 12, 34)
local player = Players.LocalPlayer

local function stroke(inst: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(1, 1, 1)
bg.BorderSizePixel = 0
bg.Parent = gui
local g = Instance.new("UIGradient")
g.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(232, 70, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 50, 190)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 120, 235)),
})
g.Rotation = 35
g.Parent = bg

local ball = Instance.new("Frame")
ball.AnchorPoint = Vector2.new(0.5, 0.5)
ball.Position = UDim2.fromScale(0.5, 0.3)
ball.Size = UDim2.fromOffset(84, 84)
ball.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
ball.Parent = bg
local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(1, 0)
bc.Parent = ball
stroke(ball, 5).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local shine = Instance.new("Frame")
shine.Position = UDim2.fromScale(0.2, 0.15)
shine.Size = UDim2.fromScale(0.3, 0.22)
shine.BackgroundColor3 = Color3.new(1, 1, 1)
shine.BackgroundTransparency = 0.3
shine.Parent = ball
local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(1, 0)
sc.Parent = shine

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromScale(0.85, 0.16)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "SMASH YOUR FRIENDS"
title.Rotation = -3
title.Parent = bg
stroke(title, 6)

local sub = Instance.new("TextLabel")
sub.AnchorPoint = Vector2.new(0.5, 0.5)
sub.Position = UDim2.fromScale(0.5, 0.63)
sub.Size = UDim2.fromScale(0.6, 0.05)
sub.BackgroundTransparency = 1
sub.Font = Enum.Font.FredokaOne
sub.TextScaled = true
sub.TextColor3 = Color3.fromRGB(255, 225, 120)
sub.Text = "Grab a ball. Smash your friend. Watch them fly."
sub.Parent = bg
stroke(sub, 3)

local dots = sub:Clone()
dots.Position = UDim2.fromScale(0.5, 0.75)
dots.Size = UDim2.fromScale(0.3, 0.04)
dots.TextColor3 = Color3.new(1, 1, 1)
dots.Text = "Loading"
dots.Parent = bg

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local conn = RunService.RenderStepped:Connect(function()
	local t = os.clock()
	ball.Position = UDim2.new(0.5, 0, 0.3, -math.abs(math.sin(t * 4)) * 40)
	ball.Rotation = (t * 220) % 360
	dots.Text = "Loading" .. string.rep(".", math.floor(t * 3) % 4)
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local deadline = os.clock() + 15
while not player.Character and os.clock() - deadline < 0 do
	task.wait(0.1)
end
task.wait(0.3)
conn:Disconnect()
local fade = TweenInfo.new(0.45)
TweenService:Create(bg, fade, { BackgroundTransparency = 1 }):Play()
for _, d in bg:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, fade, { Transparency = 1 }):Play()
	end
end
task.wait(0.5)
gui:Destroy()
