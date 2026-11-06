--!strict
-- Equipped powers in a match (Config.Powers, PowerService): the POWER button (slot 1), POWER 2 (the
-- Extra Power Slot pass) and ULT, with their cooldowns and the ultimate meter, plus every power's
-- effects. Keys: F / V / R on PC, Y / D-pad up / B on a controller; on touch they sit left of the
-- action cluster. The server decides everything; this only asks and draws.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerDefinitions = require(Shared.PowerDefinitions)
local Net = require(script.Parent.Net)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AimController = require(script.Parent.AimController)
local InputController = require(script.Parent.InputController)
local HUDController = require(script.Parent.HUDController)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer
local T = Theme.Toybox
local MAX = Config.Powers.Meter.Max

local PowerController = {}

local KEYS = {
	Power1 = { "F", "Y" },
	Power2 = { "V", "↑" },
	Ult = { "R", "B" },
}

local ULT_SOUNDS: { [string]: string } = {
	Meteor = "MeteorCharge",
	Barrage = "BarrageWhoosh",
	Geyser = "BubbleBlow",
	Phantom = "DestinyPortal",
	BallStorm = "StandSummon",
	TimeStop = "TimeStop",
}

local gui: ScreenGui
local row: Frame
local buttons: { [string]: any } = {}

local function powers(): { string }
	local s = player:GetAttribute("Powers")
	local list = {}
	if type(s) == "string" then
		for id in string.gmatch(s, "[^,]+") do
			table.insert(list, id)
		end
	end
	return list
end

local function inMatch(): boolean
	return (player:GetAttribute("Team") or "") ~= "" and player:GetAttribute("Status") == "Active"
end

local function moveDirection(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.MoveDirection else Vector3.zero
end

function PowerController.use(slot: number)
	if not inMatch() then
		return
	end
	Net.request(Net.Actions.UsePower, { slot = slot, dir = moveDirection() })
end

function PowerController.ultimate()
	if not inMatch() then
		return
	end
	local charge = player:GetAttribute("UltCharge")
	if type(charge) ~= "number" or charge < MAX then
		SoundController.play("UIError")
		HUDController.hint("Ultimate isn't charged yet: hit, catch and dodge to fill it", 1.4)
		return
	end
	Net.request(Net.Actions.UseUltimate)
end

-- Buttons ------------------------------------------------------------------------------------------

-- A round power button: the power's colour, its icon, a shrinking cooldown disc and a key tag.
local function makeButton(name: string, size: number, order: number): any
	local b = Theme.new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
	}, row)
	local scale = Theme.new("UIScale", { Scale = 1 }, b)
	local face = Theme.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.surface,
		BackgroundTransparency = 0.2,
	}, b)
	Theme.round(face)
	local outline = Theme.stroke(face, T.outline, 3, 0.1)
	local fill = Theme.new("UIGradient", {
		Rotation = -90,
		Enabled = false,
	}, face)
	local cooldown = Theme.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = T.outline,
		BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(0, 0),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, face)
	Theme.round(cooldown)
	local icon = Theme.text(b, math.floor(size * 0.42), {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(1, 0.6),
		TextColor3 = T.paper,
		ZIndex = 3,
	})
	local caption = Theme.text(b, 12, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.fromScale(1, 0.2),
		TextColor3 = T.paper,
		ZIndex = 3,
	})
	Theme.textStroke(caption, 2, T.outline)
	local tag = Theme.text(b, 13, {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.outline,
		BackgroundTransparency = 0.3,
		TextColor3 = T.paper,
		ZIndex = 4,
	})
	Theme.round(tag)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, tag)
	b.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			scale.Scale = 0.9
		end
	end)
	b.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			Theme.tween(scale, Theme.Motion.Slow, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	local refs = {
		button = b,
		face = face,
		outline = outline,
		fill = fill,
		cooldown = cooldown,
		icon = icon,
		caption = caption,
		tag = tag,
		scale = scale,
		lastFrac = -1,
	}
	buttons[name] = refs
	return refs
end

local function setKeys()
	for name, refs in buttons do
		local keys = KEYS[name]
		refs.tag.Text = if AimController.lastInput == "Gamepad" then keys[2] else keys[1]
		refs.tag.Visible = AimController.lastInput ~= "Touch"
	end
	-- touch: left of the action cluster; otherwise beside the key bar at the bottom centre
	if AimController.lastInput == "Touch" then
		row.AnchorPoint = Vector2.new(1, 1)
		row.Position = UDim2.new(1, -250, 1, -24)
	else
		row.AnchorPoint = Vector2.new(0, 1)
		row.Position = UDim2.new(0.5, 160, 1, -Theme.Space.L - 6)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PowerControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	row = Theme.new("Frame", {
		Name = "Row",
		Size = UDim2.fromOffset(240, 84),
		BackgroundTransparency = 1,
		Active = false,
	}, gui)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.Space.M),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	Theme.autoScale(row, 0.95)
	local p2 = makeButton("Power2", 58, 1)
	local p1 = makeButton("Power1", 66, 2)
	local ult = makeButton("Ult", 78, 3)
	ult.icon.Text = "⚡"
	ult.fill.Enabled = true
	p1.button.Activated:Connect(function()
		PowerController.use(1)
	end)
	p2.button.Activated:Connect(function()
		PowerController.use(2)
	end)
	ult.button.Activated:Connect(function()
		PowerController.ultimate()
	end)
	setKeys()
	InputController.changed.Event:Connect(setKeys)
end

local function paintCooldown(refs: any, readyAt: any, duration: number, t: number)
	local frac = if type(readyAt) == "number" then math.clamp((readyAt - t) / math.max(duration, 0.01), 0, 1) else 0
	if refs.lastFrac ~= frac then
		refs.lastFrac = frac
		refs.cooldown.Size = UDim2.fromScale(frac, frac)
	end
end

local pulseAt = 0
local function paint()
	local list = powers()
	local show = inMatch() and #list > 0 and Config.Powers.Enabled
	gui.Enabled = show
	if not show then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local held = player:GetAttribute("HeldBall")
	local hasBall = type(held) == "string" and held ~= ""
	for slot = 1, 2 do
		local refs = buttons["Power" .. slot]
		local def = PowerDefinitions.get(list[slot])
		refs.button.Visible = def ~= nil
		if def then
			refs.face.BackgroundColor3 = def.Color
			refs.icon.Text = def.Icon
			refs.caption.Text = string.upper(def.Name)
			paintCooldown(refs, player:GetAttribute("PowerReadyAt" .. slot), def.Cooldown, t)
			-- a ball power needs a ball in your hand, Magnet an empty one
			local usable = if def.Kind == "Ball" then hasBall elseif def.Id == "Magnet" then not hasBall else true
			refs.face.BackgroundTransparency = if usable then 0.15 else 0.55
		end
	end
	local ult = buttons.Ult
	local def = PowerDefinitions.get(list[1])
	local charge = player:GetAttribute("UltCharge")
	local frac = if type(charge) == "number" then math.clamp(charge / MAX, 0, 1) else 0
	local ready = frac >= 1
	if def then
		ult.face.BackgroundColor3 = def.Color
		ult.caption.Text = if ready then def.Ult.Name else ("%d%%"):format(math.floor(frac * 100))
	end
	-- the meter: the face fills from the bottom as it charges
	local edge = math.clamp(frac, 0.001, 0.998)
	ult.fill.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(edge, 0),
		NumberSequenceKeypoint.new(math.min(edge + 0.001, 0.999), 0.75),
		NumberSequenceKeypoint.new(1, 0.75),
	})
	ult.outline.Color = if ready then T.sun else T.outline
	ult.outline.Thickness = if ready then 5 else 3
	if ready and t >= pulseAt and not HUDController.settings.ReducedMotion then
		pulseAt = t + 1.2
		ult.scale.Scale = 1.12
		Theme.tween(ult.scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

-- Effects ------------------------------------------------------------------------------------------

local fxFolder: Folder

local function fxPart(props: { [string]: any }, life: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder
	Debris:AddItem(p, life)
	return p
end

-- A flat expanding ring on the floor (Meteor's shockwave, Geyser, Time Stop).
local function ring(pos: Vector3, radius: number, color: Color3, life: number)
	local p = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.2,
	}, life)
	Theme.tween(p, life, { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 })
end

local function burst(pos: Vector3, color: Color3, size: number, life: number)
	local p = fxPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1,
		CFrame = CFrame.new(pos),
		Color = color,
		Transparency = 0.2,
	}, life)
	Theme.tween(p, life, { Size = Vector3.one * size, Transparency = 1 })
end

local function column(pos: Vector3, radius: number, color: Color3)
	local p = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, radius * 1.4, radius * 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.35,
	}, 0.7)
	Theme.tween(p, 0.7, {
		Size = Vector3.new(40, radius * 0.6, radius * 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
	})
end

local function beam(from: Vector3, to: Vector3, color: Color3)
	local d = (to - from).Magnitude
	if d < 0.5 then
		return
	end
	local p = fxPart({
		Size = Vector3.new(0.5, 0.5, d),
		CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -d / 2),
		Color = color,
		Transparency = 0.2,
	}, 0.35)
	Theme.tween(p, 0.35, { Size = Vector3.new(0.05, 0.05, d), Transparency = 1 })
end

local function rootOf(model: any): BasePart?
	if typeof(model) == "Instance" and model:IsA("Model") then
		return model:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return nil
end

-- The caster's own camera pushes in over the wind-up (Racket Rivals' awakening cutscene, kept short
-- because the match never stops).
local function pushCamera(windup: number)
	if HUDController.settings.ReducedMotion then
		return
	end
	local cam = Workspace.CurrentCamera
	local fov = cam.FieldOfView
	Theme.tween(cam, windup * 0.45, { FieldOfView = fov - 16 }, Enum.EasingStyle.Quad)
	task.delay(windup * 0.7, function()
		Theme.tween(cam, 0.35, { FieldOfView = fov }, Enum.EasingStyle.Back)
	end)
end

local function timeStopTint(duration: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PowerTimeStop"
	cc.Saturation = -0.7
	cc.TintColor = Color3.fromRGB(200, 220, 255)
	cc.Contrast = 0.1
	cc.Parent = Lighting
	task.delay(duration, function()
		Theme.tween(cc, 0.3, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
		Debris:AddItem(cc, 0.35)
	end)
end

local function onFx(d: any)
	local kind = d.kind
	if kind == "UltReady" then
		SoundController.play("Banner")
		HUDController.hint("⚡ ULTIMATE READY!", 1.6)
	elseif kind == "Active" then
		local def = PowerDefinitions.get(d.power)
		if def and typeof(d.position) == "Vector3" then
			burst(d.position, def.Color, 7, 0.35)
			SoundController.play("PowerUp", d.position, 0.7)
		end
	elseif kind == "Ult" then
		local def = PowerDefinitions.get(d.power)
		local color = if def then def.Color else T.sun
		local mine = d.casterPlayer == player
		local name = if mine then "" else (tostring(d.casterName) .. ": ")
		HUDController.banner(name .. tostring(d.name), color, 1.4, nil, { scale = if mine then 1 else 0.7 })
		SoundController.play(ULT_SOUNDS[d.ult] or "PowerUp")
		local root = rootOf(d.caster)
		if root then
			ring(root.Position - Vector3.new(0, 2.5, 0), 14, color, 0.6)
			burst(root.Position, color, 12, 0.5)
		end
		if mine then
			pushCamera(tonumber(d.windup) or 0.9)
		end
	elseif kind == "UltEffect" then
		if d.ult == "TimeStop" then
			local def = PowerDefinitions.get("Frost") :: any
			timeStopTint(def.Ult.Duration)
		end
	elseif kind == "Blink" then
		if typeof(d.from) == "Vector3" and typeof(d.to) == "Vector3" then
			burst(d.from, Color3.fromRGB(120, 255, 200), 6, 0.3)
			burst(d.to, Color3.fromRGB(120, 255, 200), 6, 0.3)
			beam(d.from, d.to, Color3.fromRGB(120, 255, 200))
			SoundController.play("Dodge", d.to)
		end
	elseif kind == "Magnet" then
		if typeof(d.from) == "Vector3" and typeof(d.to) == "Vector3" then
			beam(d.from, d.to, Color3.fromRGB(255, 80, 110))
			SoundController.play("BlackHoleSuck", d.to, 0.6)
		end
	elseif kind == "Shockwave" then
		if typeof(d.position) == "Vector3" then
			ring(d.position, tonumber(d.radius) or 18, Color3.fromRGB(255, 120, 40), 0.5)
			burst(d.position, Color3.fromRGB(255, 90, 30), 10, 0.4)
			SoundController.play("MeteorImpact", d.position)
		end
	elseif kind == "Geyser" then
		if typeof(d.position) == "Vector3" then
			column(d.position, tonumber(d.radius) or 14, Color3.fromRGB(190, 110, 255))
			ring(d.position, tonumber(d.radius) or 14, Color3.fromRGB(170, 70, 230), 0.45)
			SoundController.play("BubbleBigPop", d.position)
		end
	elseif kind == "Shatter" or kind == "Poof" or kind == "Smothered" then
		if typeof(d.position) == "Vector3" then
			local color = if kind == "Shatter"
				then Color3.fromRGB(170, 230, 255)
				elseif kind == "Smothered" then Color3.fromRGB(120, 255, 140)
				else Color3.new(1, 1, 1)
			burst(d.position, color, 5, 0.3)
			SoundController.play("BubblePop", d.position, 0.6)
		end
	end
end

function PowerController.init() end

function PowerController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "PowerFx"
	fxFolder.Parent = Workspace
	build()
	local function bind(name: string, fn: () -> (), ...: Enum.KeyCode)
		ContextActionService:BindAction(name, function(_, state)
			if not inMatch() then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				fn()
			end
			return Enum.ContextActionResult.Sink
		end, false, ...)
	end
	bind("RD_Power1", function()
		PowerController.use(1)
	end, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	bind("RD_Power2", function()
		PowerController.use(2)
	end, Enum.KeyCode.V, Enum.KeyCode.DPadUp)
	bind("RD_Ult", PowerController.ultimate, Enum.KeyCode.R, Enum.KeyCode.ButtonB)
	Net.on("PowerFx", onFx)
	player:GetAttributeChangedSignal("Frozen"):Connect(function()
		if player:GetAttribute("Frozen") == true then
			HUDController.hint("❄️ FROZEN!", 1.2)
		end
	end)
	RunService.RenderStepped:Connect(paint)
end

return PowerController
