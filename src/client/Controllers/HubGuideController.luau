--!strict
-- First-visit guidance in the hub, once per account (the profile's HubGuideSeen; the server saves
-- it as soon as the guidance starts). After the tutorial's Done card and the daily sheet have
-- closed, the floor chevrons (BallGuideController.goal) lead you to the Shop kiosk, with a small
-- "SHOP" arrow on the side edge while the kiosk is off screen (it's behind the spawn camera).
-- Reaching the kiosk turns it into a callout beside the daily quest panel for a few seconds.
-- Opening the shop (kiosk or hub icon) or pressing PLAY ends it at once, and so does leaving the
-- hub. While a sheet is up it just waits. Nothing is drawn over the middle of the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Config = require(Shared.Config)
local Theme = require(script.Parent.Parent.UI.Theme)
local Net = require(script.Parent.Net)
local BallGuideController = require(script.Parent.BallGuideController)
local HubController = require(script.Parent.HubController)
local PracticeController = require(script.Parent.PracticeController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer
local T = Theme.Toybox
local G = Config.Lobby.Guide

local HubGuideController = {}

type Phase = "Idle" | "Shop" | "Quests" | "Done"
local phase: Phase = "Idle"
local seen: boolean? = nil -- from the Profile push; nil until it arrives
local clearSince: number? = nil -- when the hub last became clear to start in
local questsUntil = 0
local arrow: Frame -- the edge arrow toward the kiosk
local callout: TextButton -- the sticker beside the quest panel
local ring: Frame -- the pulsing outline round the quest panel

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby"
		and (player:GetAttribute("Team") or "") == ""
		and not HubController.lobbyHidden
		and not ShopController.hubHidden
		and not PracticeController.onCourt()
end

-- Something the guidance waits behind: the tutorial's Done card or any hub sheet.
local function blocked(): boolean
	local gui = player:FindFirstChildOfClass("PlayerGui")
	return (gui ~= nil and gui:FindFirstChild("TutorialDone") ~= nil) or ShopController.getBackdrop().Visible
end

local function queued(): boolean
	return player:GetAttribute("AutoQueue") == true
end

-- The Shop kiosk's prompt spot (where its prompt opens), or the station's spot from Config.
local function kioskSpot(): Vector3
	local lobby = Workspace:FindFirstChild("Lobby")
	local station = lobby and lobby:FindFirstChild("Stations")
	local shop = station and station:FindFirstChild("ShopStation")
	local anchor = shop and shop:FindFirstChild("PromptAnchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	for _, def in Config.Lobby.Stations do
		if def.Id == "Shop" then
			return ArenaLayout.lobbyPoint(def.X, 0, def.F)
		end
	end
	return ArenaLayout.lobbyPoint(0, 0, 0)
end

-- The quest panel as it shows now (open or folded into its chest disc), if it's up.
local function questPanel(): GuiObject?
	local gui = ShopController.gui
	for _, name in { "Quests", "QuestsFolded" } do
		local f = gui and gui:FindFirstChild(name)
		if f and f:IsA("GuiObject") and f.Visible then
			return f
		end
	end
	return nil
end

local function hideVisuals()
	arrow.Visible = false
	callout.Visible = false
	ring.Visible = false
end

local function finish()
	if phase == "Done" then
		return
	end
	phase = "Done"
	BallGuideController.goal = nil
	hideVisuals()
end

local function start()
	phase = "Shop"
	seen = true
	Net.request(Net.Actions.HubGuideSeen)
	BallGuideController.goal = function(): Vector3?
		return if phase == "Shop" and inHub() and not blocked() then kioskSpot() else nil
	end
end

-- A sun sticker with display text and a turned-square point on one side (-1 = left, 1 = right).
local function sticker(parent: Instance, name: string, text: string, className: string): GuiObject
	local f = Theme.new(className, {
		Name = name,
		AnchorPoint = Vector2.new(0, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		BackgroundColor3 = T.sun,
		Visible = false,
		ZIndex = 3,
	}, parent)
	if f:IsA("TextButton") then
		f.Text = ""
		f.AutoButtonColor = false
	end
	Theme.corner(f, Theme.Radius.M)
	Theme.stroke(f, T.outline, Theme.StrokeToy)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, f)
	Theme.text(f, 20, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		FontFace = Theme.DisplayFace,
		Text = text,
		ZIndex = 5,
	})
	local point = Theme.new("Frame", {
		Name = "Point",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		Rotation = 45,
		BackgroundColor3 = T.sun,
		ZIndex = 4,
	}, f)
	Theme.stroke(point, T.outline, Theme.StrokeToy)
	Theme.autoScale(f, 0.8, 0.85)
	return f
end

-- Put the point on the side the sticker aims at. The point is laid out inside the sticker's
-- padding, so push it back out onto the edge, and pad that side wider so its inner half (about
-- 13px with the stroke) clears the text.
local function aim(f: GuiObject, side: number)
	local point = f:FindFirstChild("Point") :: Frame
	local pad = f:FindFirstChildOfClass("UIPadding") :: UIPadding
	local near, far = 24, 14
	pad.PaddingLeft = UDim.new(0, if side < 0 then near else far)
	pad.PaddingRight = UDim.new(0, if side < 0 then far else near)
	point.Position = UDim2.new(if side < 0 then 0 else 1, if side < 0 then -near else near, 0.5, 0)
	f.AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0.5)
end

local function build()
	local gui = ShopController.gui
	arrow = sticker(gui, "HubGuideArrow", "🛒 SHOP", "Frame") :: Frame
	callout = sticker(gui, "HubGuideQuests", "Daily quests pay chests!", "TextButton") :: TextButton
	aim(callout, -1)
	callout.Activated:Connect(function()
		if phase == "Quests" then
			finish()
		end
	end)
	ring = Theme.new("Frame", {
		Name = "HubGuideRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, gui)
	Theme.corner(ring, Theme.Radius.L)
	Theme.stroke(ring, Theme.Colors.Select, 4)
end

-- Whatever sits on the right edge at height `y` (absolute): the hub's action column, or the touch
-- controls. Returns the leftmost absolute X of those, or nil.
local function rightEdgeAt(y: number, half: number): number?
	local edge: number? = nil
	local gui = player:FindFirstChildOfClass("PlayerGui")
	local touch = gui and gui:FindFirstChild("MobileControls")
	local cluster = touch and touch:IsA("ScreenGui") and touch.Enabled and touch:FindFirstChild("Cluster")
	local actions = ShopController.gui and ShopController.gui:FindFirstChild("Actions")
	for _, f in { actions, cluster } do
		if f and f:IsA("GuiObject") and f.Visible then
			local top, bottom = f.AbsolutePosition.Y, f.AbsolutePosition.Y + f.AbsoluteSize.Y
			if top < y + half and bottom > y - half then
				edge = math.min(edge or math.huge, f.AbsolutePosition.X)
			end
		end
	end
	return edge
end

-- The edge arrow: shown on the left or right edge while the kiosk is off screen. It sits below the
-- quest panel on the left, and inside the action column or touch controls on the right, so it
-- never covers them.
local function drawArrow(t: number)
	local camera = Workspace.CurrentCamera
	local gui = ShopController.gui
	if not camera or not gui then
		arrow.Visible = false
		return
	end
	local spot = kioskSpot() + Vector3.new(0, 3, 0)
	local view, onScreen = camera:WorldToViewportPoint(spot)
	local size = camera.ViewportSize
	if onScreen and view.X > 40 and view.X < size.X - 40 then
		arrow.Visible = false -- you can see it: the chevrons and its sign do the rest
		return
	end
	local side = if camera.CFrame:PointToObjectSpace(spot).X < 0 then -1 else 1
	aim(arrow, side)
	local origin = gui.AbsolutePosition
	local width = gui.AbsoluteSize.X
	local y = gui.AbsoluteSize.Y * 0.62
	local panel = questPanel()
	if side < 0 and panel then
		y = math.max(y, panel.AbsolutePosition.Y - origin.Y + panel.AbsoluteSize.Y + 34)
	end
	local bob = if Theme.settings.reducedMotion then 0 else math.sin(t * 6) * 5
	local inset = Theme.Space.M + 10
	local right = width - inset
	local blocker = if side > 0 then rightEdgeAt(origin.Y + y, arrow.AbsoluteSize.Y / 2 + 6) else nil
	if blocker then
		right = math.min(right, blocker - origin.X - 24)
	end
	arrow.Position = UDim2.fromOffset(if side < 0 then inset + bob else right - bob, y)
	arrow.Visible = true
end

-- The quest callout: a pulsing outline round the panel and the sticker just right of it.
local function drawQuests(t: number)
	local gui = ShopController.gui
	local panel = questPanel()
	if not panel or not gui then
		callout.Visible = false
		ring.Visible = false
		return
	end
	local origin = gui.AbsolutePosition
	local at = panel.AbsolutePosition - origin
	local size = panel.AbsoluteSize
	ring.Position = UDim2.fromOffset(at.X + size.X / 2, at.Y + size.Y / 2)
	ring.Size = UDim2.fromOffset(size.X + 14, size.Y + 14)
	local stroke = ring:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = if Theme.settings.reducedMotion then 4 else 4 + 2 * math.sin(t * 8)
	end
	local bob = if Theme.settings.reducedMotion then 0 else math.sin(t * 6) * 4
	callout.Position = UDim2.fromOffset(at.X + size.X + 30 + bob, at.Y + math.min(size.Y / 2, 60))
	if not callout.Visible then
		callout.Visible = true
		ring.Visible = true
		Theme.pop(callout, 0.6)
	end
end

local function step()
	if phase == "Done" then
		return
	end
	if phase == "Idle" then
		-- start once the hub has been clear for a moment: tutorial done, no card or sheet up, not queued
		local ready = seen == false
			and player:GetAttribute("TutorialDone") == true
			and inHub()
			and not blocked()
			and not queued()
		if not ready then
			clearSince = nil
			return
		end
		clearSince = clearSince or os.clock()
		if os.clock() - (clearSince :: number) < G.Settle then
			return
		end
		start()
	end
	-- the shop opened or PLAY was pressed: they've found their way
	if ShopController.isShopOpen() or queued() or not inHub() then
		finish()
		return
	end
	if blocked() then
		hideVisuals()
		return
	end
	local t = os.clock()
	if phase == "Shop" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local spot = kioskSpot()
		local flat = if root then Vector3.new(root.Position.X - spot.X, 0, root.Position.Z - spot.Z) else nil
		if flat and flat.Magnitude <= Config.Lobby.StationPromptDistance - 2 then
			phase = "Quests"
			questsUntil = t + G.QuestSeconds
			arrow.Visible = false
			SoundController.play("UIStep")
		else
			drawArrow(t)
			return
		end
	end
	if t >= questsUntil then
		finish()
		return
	end
	drawQuests(t)
end

function HubGuideController.init() end

function HubGuideController.start()
	build()
	Net.on("Profile", function(d)
		if type(d.hubGuide) == "boolean" and phase == "Idle" then
			seen = d.hubGuide
		end
	end)
	-- Studio: RD_Gallery = "HubGuide" plays it again (the saved flag stays set)
	player:GetAttributeChangedSignal("RD_Gallery"):Connect(function()
		if RunService:IsStudio() and player:GetAttribute("RD_Gallery") == "HubGuide" then
			finish()
			phase = "Idle"
			seen = false
			clearSince = nil
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return HubGuideController
