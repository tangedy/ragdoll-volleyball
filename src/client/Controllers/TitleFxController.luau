--!strict
-- Animated titles (Catalog Data.Animated, the Legendary Robux-exclusive titles): their gradient
-- slides along the letters on every name tag showing one. The server tags those badges
-- (TitleStyle.Tag) and leaves what goes before the title and the title's id on them as attributes;
-- this re-draws their text locally FPS times a second. Only a handful of tags ever animate, and a
-- badge too far away to be drawn (past its BillboardGui's MaxDistance) is skipped.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local TitleStyle = require(Shared:WaitForChild("TitleStyle"))
local GraphicsController = require(script.Parent.GraphicsController)

local TitleFxController = {}

local FPS = 10
local SPEED = 0.35 -- gradient loops a second

local function draw(badge: Instance, phase: number)
	if not badge:IsA("TextLabel") then
		return
	end
	local item = Catalog.get(badge:GetAttribute("TitleItem") :: string?)
	local gradient = item and item.Data.Gradient
	local prefix = badge:GetAttribute("TitlePrefix")
	if not item or not gradient or type(prefix) ~= "string" then
		return
	end
	local bb = badge:FindFirstAncestorOfClass("BillboardGui")
	local head = bb and bb.Parent
	local cam = Workspace.CurrentCamera
	if bb and head and head:IsA("BasePart") and cam then
		if (head.Position - cam.CFrame.Position).Magnitude > bb.MaxDistance then
			return
		end
	end
	local frame = badge:GetAttribute("TitleFrame")
	badge.Text = prefix
		.. TitleStyle.framed(item.Data.Text, gradient, if type(frame) == "string" then frame else "", phase)
end

function TitleFxController.init() end

function TitleFxController.start()
	local nextAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextAt then
			return
		end
		-- each redraw rebuilds the rich text and re-lays out the label: fewer in performance mode
		nextAt = now + 1 / (if GraphicsController.low then Config.Graphics.LowTitleFps else FPS)
		local phase = (now * SPEED) % 1
		for _, badge in CollectionService:GetTagged(TitleStyle.Tag) do
			draw(badge, phase)
		end
	end)
end

return TitleFxController
