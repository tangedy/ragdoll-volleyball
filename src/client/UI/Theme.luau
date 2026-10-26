--!strict
-- Shared UI look: chunky rounded type with ink outlines, gradient panels, 3D "lip" buttons that
-- squash on press, and pop-in animations. Every screen builds from these helpers so the game has
-- one consistent, playful style.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Theme = {}

Theme.Colors = {
	Ink = Color3.fromRGB(16, 12, 34),
	Panel = Color3.fromRGB(30, 24, 58),
	PanelLight = Color3.fromRGB(58, 46, 104),
	Card = Color3.fromRGB(44, 36, 82),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(190, 182, 230),
	Gold = Color3.fromRGB(255, 204, 64),
	GoldDark = Color3.fromRGB(230, 140, 20),
	Green = Color3.fromRGB(80, 224, 120),
	GreenDark = Color3.fromRGB(30, 150, 70),
	Danger = Color3.fromRGB(255, 84, 84),
	Purple = Color3.fromRGB(160, 100, 255),
	Red = Config.Teams.Red.Color,
	Blue = Config.Teams.Blue.Color,
}

Theme.Display = Enum.Font.FredokaOne
Theme.Body = Enum.Font.GothamBold

local C = Theme.Colors

function Theme.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(inst: Instance, radius: number?): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, radius or 14) }, inst)
end

function Theme.round(inst: Instance): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(1, 0) }, inst)
end

function Theme.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

-- Outline around text (the "sticker" look).
function Theme.textStroke(label: Instance, thickness: number?, color: Color3?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end

function Theme.gradient(inst: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Theme.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, inst)
end

function Theme.padding(inst: Instance, px: number)
	Theme.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	}, inst)
end

function Theme.lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), t)
end

function Theme.darken(c: Color3, t: number): Color3
	return c:Lerp(C.Ink, t)
end

-- Display text: rounded font, scaled, white with an ink outline.
function Theme.label(parent: Instance?, props: { [string]: any }?, strokeThickness: number?): TextLabel
	local l = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Display,
		TextScaled = true,
		TextColor3 = C.Text,
		Text = "",
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	Theme.textStroke(l, strokeThickness)
	l.Parent = parent
	return l
end

-- Small body text without the heavy outline.
function Theme.body(parent: Instance?, props: { [string]: any }?): TextLabel
	local l = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Body,
		TextScaled = true,
		TextColor3 = C.Muted,
		Text = "",
	}, nil)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

-- A panel: purple-ink gradient, rounded, thin light rim and a soft drop shadow.
function Theme.panel(parent: Instance?, props: { [string]: any }?, radius: number?): Frame
	local f = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Theme.corner(f, radius or 18)
	Theme.gradient(f, C.PanelLight, C.Panel)
	Theme.stroke(f, Color3.new(1, 1, 1), 2, 0.82)
	f.Parent = parent
	if parent then
		Theme.shadow(f, radius or 18)
	end
	return f
end

-- Soft shadow behind a frame (a dark rounded copy offset down).
function Theme.shadow(f: GuiObject, radius: number?)
	local parent = f.Parent
	if not parent then
		return
	end
	local sh = Theme.new("Frame", {
		Name = f.Name .. "_Shadow",
		AnchorPoint = f.AnchorPoint,
		Position = f.Position + UDim2.fromOffset(0, 5),
		Size = f.Size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = math.max(0, f.ZIndex - 1),
		Visible = f.Visible,
	}, parent)
	Theme.corner(sh, radius or 18)
	-- keep the shadow glued to its frame
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		sh.Visible = f.Visible
	end)
	f:GetPropertyChangedSignal("Position"):Connect(function()
		sh.Position = f.Position + UDim2.fromOffset(0, 5)
	end)
	-- follow the frame's rendered size, so size constraints on the frame apply to the shadow too
	local function syncSize()
		sh.Size = UDim2.fromOffset(f.AbsoluteSize.X, f.AbsoluteSize.Y)
	end
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncSize)
	task.defer(syncSize)
	f.AncestryChanged:Connect(function()
		if not f.Parent then
			sh:Destroy()
		end
	end)
end

-- Every element has at most one UIScale (Roblox applies only one). Its "Base" attribute is the
-- element's resting scale (set by Theme.autoScale); animations scale relative to it.
local function scaleOf(inst: GuiObject): UIScale
	local sc = inst:FindFirstChildOfClass("UIScale")
	if not sc then
		sc = Theme.new("UIScale", nil, inst)
	end
	return sc :: UIScale
end
local function baseOf(sc: UIScale): number
	local b = sc:GetAttribute("Base")
	return if type(b) == "number" then b else 1
end

-- Scale-pop an element (uses/creates its UIScale).
function Theme.pop(inst: GuiObject, from: number?, duration: number?)
	local scale = scaleOf(inst)
	local base = baseOf(scale)
	scale.Scale = (from or 0.6) * base
	TweenService:Create(scale, TweenInfo.new(duration or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
end

local clickSound: ((string) -> ())? = nil
function Theme.setClickSound(fn: (string) -> ())
	clickSound = fn
end

-- A chunky 3D button: gradient face, darker "lip" underneath, ink outline, squash on press,
-- grow on hover, click sound. Returns the TextButton (face).
function Theme.button(parent: Instance?, text: string, color: Color3, props: { [string]: any }?): TextButton
	local b = Theme.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, nil)
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	Theme.corner(b, 14)
	local grad = Theme.gradient(b, Theme.lighten(color, 0.25), color)
	grad.Name = "Face"
	Theme.stroke(b, Theme.darken(color, 0.55), 3)
	local lip = Theme.new("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.darken(color, 0.35),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = b.ZIndex,
	}, b)
	Theme.corner(lip, 14)
	Theme.label(b, {
		Name = "Label",
		Size = UDim2.new(1, -16, 1, -12),
		Position = UDim2.fromOffset(8, 3),
		Text = text,
		ZIndex = b.ZIndex + 1,
	}, 2.5)
	local scale = Theme.new("UIScale", nil, b)
	local function to(v: number, t: number)
		TweenService:Create(scale, TweenInfo.new(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = v }):Play()
	end
	b.MouseEnter:Connect(function()
		to(1.05, 0.15)
	end)
	b.MouseLeave:Connect(function()
		to(1, 0.15)
	end)
	b.MouseButton1Down:Connect(function()
		to(0.92, 0.08)
	end)
	b.MouseButton1Up:Connect(function()
		to(1, 0.2)
	end)
	b.Activated:Connect(function()
		if clickSound then
			clickSound("UIClick")
		end
	end)
	b.Parent = parent
	return b
end

-- Layout tokens -------------------------------------------------------------------------------------
-- One spacing / radius / type scale for every screen, so gaps and corners line up everywhere.

Theme.Space = { XS = 4, S = 8, M = 12, L = 18, XL = 24 }
Theme.Radius = { S = 10, M = 14, L = 18, XL = 22 }
Theme.TextSize = { Caption = 13, Body = 16, Title = 22 }
Theme.Motion = { Fast = 0.12, Base = 0.22, Slow = 0.4 }

-- Rarity colors come from Config so the hub wheel, the shop and the spin panel always agree.
Theme.Rarity = Config.Spin.RarityColors :: { [string]: Color3 }

function Theme.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Responsive scale: 1 on a 1280x720-or-bigger screen, down to 0.62 on small phones. Elements
-- registered with Theme.autoScale keep a UIScale in sync as the window/device changes.
local scaled: { [UIScale]: number } = {}
function Theme.uiScale(): number
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X / 1280, vp.Y / 720) * 1.08, 0.62, 1)
end

-- Is this a small (phone-sized) screen? Layouts switch to their compact arrangement.
function Theme.isCompact(): boolean
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return vp.X < 900 or vp.Y < 520
end

local function rescaleAll()
	local s = Theme.uiScale()
	for sc, factor in scaled do
		if sc.Parent then
			sc:SetAttribute("Base", s * factor)
			sc.Scale = s * factor
		else
			scaled[sc] = nil
		end
	end
end

-- Keep `inst` scaled to the screen (factor lets an element shrink a bit more or less than the rest).
function Theme.autoScale(inst: GuiObject, factor: number?): UIScale
	local sc = scaleOf(inst)
	scaled[sc] = factor or 1
	sc:SetAttribute("Base", Theme.uiScale() * (factor or 1))
	sc.Scale = baseOf(sc)
	return sc
end

task.defer(function()
	local function watch(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleAll)
		end
		rescaleAll()
	end
	watch(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watch(workspace.CurrentCamera)
	end)
end)

-- Panel transitions -----------------------------------------------------------------------------------
-- Every pop-up opens and closes the same way: a quick scale + fade in with a little overshoot, and a
-- faster shrink + fade out. The optional backdrop dims the game behind modal panels.

function Theme.show(panel: GuiObject, backdrop: GuiObject?)
	local closing = panel.Visible and panel:GetAttribute("ThemeOpen") == false
	local wasOpen = panel.Visible and not closing
	panel:SetAttribute("ThemeOpen", true)
	panel.Visible = true
	if backdrop then
		if not backdrop.Visible then
			backdrop.BackgroundTransparency = 1
		end
		backdrop.Visible = true
		Theme.tween(backdrop, Theme.Motion.Base, { BackgroundTransparency = 0.45 })
	end
	if wasOpen then
		return
	end
	local sc = scaleOf(panel)
	if not closing then
		sc.Scale = 0.82 * baseOf(sc)
	end
	Theme.tween(sc, Theme.Motion.Slow * 0.8, { Scale = baseOf(sc) }, Enum.EasingStyle.Back)
end

function Theme.hide(panel: GuiObject, backdrop: GuiObject?)
	if not panel.Visible or panel:GetAttribute("ThemeOpen") == false then
		return -- already closed or closing
	end
	panel:SetAttribute("ThemeOpen", false)
	if backdrop and backdrop.Visible then
		Theme.tween(backdrop, Theme.Motion.Fast, { BackgroundTransparency = 1 }).Completed:Once(function(state)
			-- a panel opening meanwhile restarts the backdrop tween, which cancels this one
			if state == Enum.PlaybackState.Completed then
				backdrop.Visible = false
			end
		end)
	end
	local sc = scaleOf(panel)
	local base = baseOf(sc)
	Theme.tween(sc, Theme.Motion.Fast, { Scale = 0.86 * base }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		-- only finish closing if nothing reopened it meanwhile
		if panel:GetAttribute("ThemeOpen") == false then
			panel.Visible = false
			sc.Scale = baseOf(sc)
		end
	end)
end

-- Full-screen dim layer behind modal panels; clicking it calls onClose.
function Theme.backdrop(parent: Instance, onClose: (() -> ())?): TextButton
	local b = Theme.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -60),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 0,
	}, parent)
	if onClose then
		b.Activated:Connect(onClose)
	end
	return b
end

-- Small widgets -----------------------------------------------------------------------------------------

-- Red "!" notification dot on the corner of a button.
function Theme.badge(parent: GuiObject, text: string?): Frame
	local dot = Theme.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = C.Danger,
		Visible = false,
		ZIndex = (parent.ZIndex or 1) + 5,
	}, parent)
	Theme.round(dot)
	Theme.stroke(dot, Color3.new(1, 1, 1), 2.5)
	Theme.label(dot, {
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.15, 0.15),
		Text = text or "!",
		ZIndex = dot.ZIndex + 1,
	}, 1.5)
	return dot
end

-- A rounded stat tile: big value over a small caption, tinted by color.
function Theme.statChip(parent: Instance, caption: string, color: Color3, props: { [string]: any }?): TextLabel
	local f = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, nil)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Theme.corner(f, Theme.Radius.S)
	Theme.gradient(f, Theme.darken(color, 0.35), Theme.darken(color, 0.7))
	Theme.stroke(f, Theme.lighten(color, 0.2), 2, 0.3)
	local value = Theme.label(f, {
		Name = "Value",
		Position = UDim2.fromOffset(Theme.Space.XS, Theme.Space.XS),
		Size = UDim2.new(1, -Theme.Space.S, 0.6, -Theme.Space.XS),
		Text = "0",
	}, 2)
	Theme.body(f, {
		Name = "Caption",
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.fromScale(1, 0.3),
		Text = caption,
		TextColor3 = Theme.lighten(color, 0.5),
	})
	f.Parent = parent
	return value
end

-- Coin icon (gold disc with a "C").
function Theme.coin(parent: Instance, size: number, props: { [string]: any }?): Frame
	local coin = Theme.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, nil)
	if props then
		for k, v in props do
			(coin :: any)[k] = v
		end
	end
	Theme.round(coin)
	Theme.gradient(coin, C.Gold, C.GoldDark)
	Theme.stroke(coin, Theme.darken(C.GoldDark, 0.5), math.max(1.5, size / 16))
	Theme.label(coin, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = "C", ZIndex = coin.ZIndex + 1 }, 1.5)
	coin.Parent = parent
	return coin
end

-- Recolor a Theme.button (e.g. owned -> equipped states).
function Theme.recolor(b: TextButton, color: Color3)
	local face = b:FindFirstChild("Face") :: UIGradient?
	if face then
		face.Color = ColorSequence.new(Theme.lighten(color, 0.25), color)
	end
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.darken(color, 0.55)
	end
	local lip = b:FindFirstChild("Lip") :: Frame?
	if lip then
		lip.BackgroundColor3 = Theme.darken(color, 0.35)
	end
end

function Theme.setText(b: TextButton, text: string)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Text = text
	end
end

return Theme
