--!strict
-- Floor arrows from the player to the nearest ball they can pick up (replaces the "Walk over a
-- ball." text for the first tutorial step). A chain of glowing chevrons is laid on the floor and
-- pulses toward the ball, which gets a pulsing ring. Client-only visuals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)

local player = Players.LocalPlayer

local BallGuideController = {}

BallGuideController.enabled = false -- driven by TutorialController

local MAX_CHEVRONS = 14
local SPACING = 3
local GOLD = Color3.fromRGB(255, 214, 70)

local folder: Folder
local chevrons: { { a: Part, b: Part } } = {}
local ring: Part
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include

local function bar(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = GOLD
	p.Transparency = 1
	p.Parent = folder
	return p
end

-- Is this ball one the player could pick up right now (same rules as the server, roughly)?
local function eligible(ball: BasePart): boolean
	local state = ball:GetAttribute("BallState")
	if state ~= "Resting" and state ~= "Spent" then
		return false
	end
	local team = player:GetAttribute("Team")
	local status = player:GetAttribute("Status")
	local inMatch = type(team) == "string" and team ~= ""
	if ball:GetAttribute("Context") == "Lobby" then
		return not inMatch
	end
	if not inMatch then
		return false
	end
	if status == "Jailed" then
		return ArenaLayout.inJail(team, ball.Position)
	end
	return status == "Active" and ArenaLayout.onHalf(team, ball.Position, 0, -2)
end

local function nearestBall(from: Vector3): BasePart?
	local balls = Workspace:FindFirstChild("Balls")
	if not balls then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, b in balls:GetChildren() do
		if b:IsA("BasePart") and b.LocalTransparencyModifier < 1 and b.Transparency < 1 and eligible(b) then
			local d = (b.Position - from).Magnitude
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

local function floorAt(pos: Vector3): number?
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), floorParams)
	return if hit then hit.Position.Y else nil
end

local function hideAll()
	for _, c in chevrons do
		c.a.Transparency = 1
		c.b.Transparency = 1
	end
	ring.Transparency = 1
end

function BallGuideController.init()
	folder = Instance.new("Folder")
	folder.Name = "BallGuide"
	folder.Parent = Workspace
	for _ = 1, MAX_CHEVRONS do
		table.insert(chevrons, { a = bar(), b = bar() })
	end
	ring = bar()
	ring.Shape = Enum.PartType.Cylinder
end

function BallGuideController.start()
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local held = player:GetAttribute("HeldBall")
		if not BallGuideController.enabled or not root or (type(held) == "string" and held ~= "") then
			hideAll()
			return
		end
		local arena = Workspace:FindFirstChild("Arena")
		local collidable = arena and arena:FindFirstChild("Collidable")
		floorParams.FilterDescendantsInstances = if collidable then { collidable } else {}
		local ball = nearestBall(root.Position)
		if not ball then
			hideAll()
			return
		end
		local from = Vector3.new(root.Position.X, 0, root.Position.Z)
		local to = Vector3.new(ball.Position.X, 0, ball.Position.Z)
		local delta = to - from
		local dist = delta.Magnitude
		local t = os.clock()
		if dist < 0.5 then
			hideAll()
			return
		end
		local f = delta.Unit
		local r = f:Cross(Vector3.yAxis)
		local count = math.clamp(math.floor((dist - 3) / SPACING), 0, MAX_CHEVRONS)
		for i, c in chevrons do
			if i > count then
				c.a.Transparency = 1
				c.b.Transparency = 1
				continue
			end
			local flat = from + f * (2 + i * SPACING)
			local y = floorAt(Vector3.new(flat.X, root.Position.Y, flat.Z)) or (root.Position.Y - 3)
			local center = Vector3.new(flat.X, y + 0.08, flat.Z)
			-- a ">" chevron: two bars meeting at the tip, pointing toward the ball
			local tip = center + f * 0.55
			local wave = 0.5 + 0.5 * math.sin(t * 7 - i * 0.9) -- pulse travels toward the ball
			local transparency = 0.05 + 0.55 * (1 - wave)
			for side, p in { c.a, c.b } do
				local tail = center - f * 0.55 + r * (if side == 1 then 0.75 else -0.75)
				local mid = (tail + tip) / 2
				local len = (tip - tail).Magnitude
				p.Size = Vector3.new(0.32, 0.06, len)
				p.CFrame = CFrame.lookAt(mid, tip)
				p.Transparency = transparency
			end
		end
		-- pulsing ring under the target ball
		local by = floorAt(ball.Position) or (ball.Position.Y - 1)
		local s = 3.2 + 0.5 * math.sin(t * 6)
		ring.Size = Vector3.new(0.06, s, s)
		ring.CFrame = CFrame.new(ball.Position.X, by + 0.07, ball.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.25
	end)
end

return BallGuideController
