--!strict
-- Loot chests on the hub deck (presentation only; ChestService decides and saves everything).
--
--  * Idle: each chest's lid peeks open now and then with a glow leaking out, and the gem above it
--    turns and bobs.
--  * Walk up and use the prompt: a sheet shows the exact wheel this chest will spin (any cosmetic),
--    its odds and the price.
--  * Open: the sheet steps aside and the camera frames the chest, which rattles until the server
--    answers, then the lid bursts open (light pillar, shockwave, sparkles, a fountain of coins).
--    The sheet comes back and the wheel lands on the prize; the chest flashes the prize's rarity.
--  * Everyone else in the hub sees that chest rattle and burst open too.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local HUDController = require(script.Parent.HUDController)
local HubController = require(script.Parent.HubController)
local ShopController = require(script.Parent.ShopController)
local SoundController = require(script.Parent.SoundController)
local SpinController = require(script.Parent.SpinController)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer
local T = Theme.Toybox
local CH = Config.Chest
local new = Theme.new

local ChestController = {}

local SHEET_SIZE = Vector2.new(820, 536)
local OPEN_ANGLE = math.rad(112)
local OPEN_TIME = 0.55
local CLOSE_TIME = 0.45
local MIN_RATTLE = 1.1 -- the chest always rattles at least this long before it bursts
local SHOT_HOLD = 1.15 -- seconds the camera stays on the open chest before the wheel comes back
local PEEK_EVERY = 7
local PEEK_TIME = 1.1

type ChestState = {
	index: number,
	model: Model,
	lid: Model?,
	lidHome: CFrame?,
	gem: Model?,
	gemHome: CFrame?,
	light: PointLight?,
	burst: ParticleEmitter?,
	glowPart: BasePart?,
	color: Color3,
	mode: string, -- "idle" | "rattle" | "open"
	since: number,
	openAt: number,
	closeAt: number,
	fromAngle: number,
	angle: number,
	nextRattleSound: number,
}

local chests: { [number]: ChestState } = {}

-- sheet
local panel: CanvasGroup
local rotor: Frame
local oddsList: Frame
local openButton: TextButton
local balanceLabel: TextLabel
local reveal: Frame
local slotsShown: { string } = {}
local slotFrames: { Frame } = {}
local status: any = nil -- profile.chest from the server
local owned: { [string]: boolean } = {}
local coins = 0
local currentChest: number? = nil
local sheetRef: any -- Theme.Sheet (title and subtitle change with the chest's tier)
local priceLabel: TextLabel
local freeLabel: TextLabel

-- the open in progress
local opening = false
local openToken = 0
local savedCamera: CFrame? = nil
local hiddenBody: { BasePart } = {}
local rotation = 0
local spinConn: RBXScriptConnection? = nil
local lastTick = -1

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function reduced(): boolean
	return HUDController.settings.ReducedMotion == true
end

-- Chests in the world -------------------------------------------------------------------------------

local function stateOf(index: number): ChestState?
	local s = chests[index]
	if s and s.model.Parent ~= nil then
		return s
	end
	local lobby = Workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Chests")
	local model = folder and folder:FindFirstChild("LootChest" .. index)
	if not model or not model:IsA("Model") then
		return s -- the hub may just be hidden right now; keep what we had
	end
	local lid = model:FindFirstChild("Lid") :: Model?
	local gem = model:FindFirstChild("FloatingGem") :: Model?
	local glowPart = model:FindFirstChild("Glow") :: BasePart?
	local fx = model:FindFirstChild("FX")
	local style = (CH.Styles :: any)[model:GetAttribute("Style")] or CH.Styles.Gold
	s = {
		index = index,
		model = model,
		lid = lid,
		lidHome = lid and lid:GetPivot(),
		gem = gem,
		gemHome = gem and gem:GetPivot(),
		light = glowPart and glowPart:FindFirstChildOfClass("PointLight"),
		burst = fx and fx:FindFirstChild("Burst", true) :: ParticleEmitter?,
		glowPart = glowPart,
		color = style.Glow,
		mode = "idle",
		since = 0,
		openAt = 0,
		closeAt = 0,
		fromAngle = 0,
		angle = 0,
		nextRattleSound = 0,
	}
	chests[index] = s :: ChestState
	return s
end

local function chestPos(s: ChestState): Vector3
	return if s.glowPart then s.glowPart.Position else s.model:GetPivot().Position
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- Lid angle (radians, 0 = shut) and glow brightness for a chest right now.
local function lidPose(s: ChestState, t: number): (number, number)
	if s.mode == "rattle" then
		if reduced() then
			return math.rad(6), 1
		end
		return math.rad(5 + math.noise(t * 16, s.index * 3.7) * 7), 1 + math.noise(t * 9, s.index) * 0.6
	elseif s.mode == "open" then
		local a = t - s.openAt
		if a < OPEN_TIME then
			local k = if reduced() then a / OPEN_TIME else backOut(a / OPEN_TIME)
			return s.fromAngle + (OPEN_ANGLE - s.fromAngle) * k, 2.5 + 6 * (1 - a / OPEN_TIME)
		end
		local c = t - s.closeAt
		if c < 0 then
			return OPEN_ANGLE + math.sin(t * 2.2) * math.rad(1.5), 2.5 + math.sin(t * 5) * 0.4
		end
		if c < CLOSE_TIME then
			local k = (c / CLOSE_TIME) ^ 2
			return OPEN_ANGLE * (1 - k), 2.5 * (1 - k)
		end
		s.mode = "idle"
		SoundController.play("ChestThud", chestPos(s))
		return 0, 0
	end
	if reduced() then
		return 0, 0
	end
	-- idle: the lid lifts a crack every few seconds, glow leaking out (chests stay out of step)
	local phase = (t + s.index * 2.3) % PEEK_EVERY
	if phase < PEEK_TIME then
		local k = math.sin(phase / PEEK_TIME * math.pi)
		return math.rad(10) * k, 1.4 * k
	end
	return 0, 0
end

local function animateChest(s: ChestState, t: number)
	local angle, glow = lidPose(s, t)
	if s.lid and s.lidHome and math.abs(angle - s.angle) > 1e-4 then
		s.lid:PivotTo(s.lidHome * CFrame.Angles(angle, 0, 0))
	end
	s.angle = angle
	if s.light then
		s.light.Brightness = glow
	end
	if s.mode == "rattle" and t >= s.nextRattleSound then
		s.nextRattleSound = t + 0.2
		SoundController.play("ChestRattle", chestPos(s), 0.8)
	end
	-- the floating gem turns and bobs; it rises and whirls while the chest is open
	if s.gem and s.gemHome then
		local lift = if s.mode == "open" then math.min(1, (t - s.openAt) * 2) * 1.4 else 0
		local spin = t * (if s.mode == "idle" then 1.1 else 4)
		local bob = if reduced() then 0 else math.sin(t * 1.7 + s.index) * 0.3
		s.gem:PivotTo(
			CFrame.new(s.gemHome.Position + Vector3.new(0, bob + lift, 0))
				* CFrame.Angles(0, spin, 0)
				* s.gemHome.Rotation
		)
	end
end

-- A neon part that tweens away and cleans itself up.
local function flash(props: { [string]: any }, goal: { [string]: any }, life: number)
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
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, life + 0.1)
end

-- The lid bursting open: light pillar, a shockwave ring on the dais, sparkles and a coin fountain.
local function burstFx(s: ChestState, color: Color3, big: boolean)
	local at = chestPos(s)
	local up = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing upright
	if s.burst then
		s.burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		s.burst:Emit(if big then 70 else 35)
	end
	if s.light then
		s.light.Color = color
	end
	local height = if big then 34 else 22
	flash({
		Name = "ChestPillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 3.4, 3.4),
		CFrame = up * CFrame.new(0.5, 0, 0),
		Color = color,
		Transparency = 0.15,
	}, {
		Size = Vector3.new(height, 0.4, 0.4),
		CFrame = up * CFrame.new(height / 2, 0, 0),
		Transparency = 1,
	}, if big then 1.3 else 0.9)
	flash({
		Name = "ChestRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 3, 3),
		CFrame = up * CFrame.new(-2.55, 0, 0),
		Color = color,
		Transparency = 0.2,
	}, { Size = Vector3.new(0.1, if big then 22 else 14, if big then 22 else 14), Transparency = 1 }, 0.8)
	flash({
		Name = "ChestFlare",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.5,
		CFrame = CFrame.new(at + Vector3.new(0, 0.8, 0)),
		Color = Color3.new(1, 1, 1):Lerp(color, 0.4),
		Transparency = 0.1,
	}, { Size = Vector3.one * (if big then 9 else 6), Transparency = 1 }, 0.45)
	if not big or reduced() then
		return
	end
	-- coin fountain: loose client-only coins that bounce on the deck and vanish
	local rng = Random.new()
	for _ = 1, 16 do
		local coin = Instance.new("Part")
		coin.Name = "ChestCoin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.12, 0.6, 0.6)
		coin.Color = Color3.fromRGB(255, 205, 70)
		coin.Material = Enum.Material.Foil
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.CFrame = CFrame.new(at + Vector3.new(rng:NextNumber(-1, 1), 0.8, rng:NextNumber(-0.6, 0.6)))
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		coin.Parent = Workspace
		coin.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(30, 44), rng:NextNumber(-9, 9))
		coin.AssemblyAngularVelocity =
			Vector3.new(rng:NextNumber(-20, 20), rng:NextNumber(-20, 20), rng:NextNumber(-20, 20))
		Debris:AddItem(coin, rng:NextNumber(2.2, 3))
	end
end

-- Start a chest rattling (someone is opening it).
local function rattle(s: ChestState)
	s.mode = "rattle"
	s.since = os.clock()
	s.nextRattleSound = 0
end

-- Burst the lid open now; it stays open for `hold` seconds.
local function burstOpen(s: ChestState, hold: number)
	local now = os.clock()
	s.fromAngle = s.angle
	s.mode = "open"
	s.openAt = now
	s.closeAt = now + OPEN_TIME + hold
	burstFx(s, s.color, true)
	SoundController.play("ChestBurst", chestPos(s))
end

-- Flash the prize's rarity out of an open chest.
local function rarityFlash(s: ChestState, rarity: string)
	local col = Theme.Rarity[rarity] or s.color
	burstFx(s, col, false)
	if s.mode == "open" then
		-- a good prize keeps the chest open a little longer
		s.closeAt = math.max(s.closeAt, os.clock() + (if rarity == "Legendary" or rarity == "Epic" then 4 else 2.5))
	end
end

-- Camera shot ---------------------------------------------------------------------------------------

local function setBodyHidden(hide: boolean)
	for _, p in hiddenBody do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	table.clear(hiddenBody)
	local character = player.Character
	if not hide or not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0.8
			table.insert(hiddenBody, d)
		end
	end
end

local function cameraToChest(s: ChestState)
	local camera = Workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Custom or not s.model.PrimaryPart then
		return -- a cutscene owns the camera
	end
	savedCamera = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local core = (s.model.PrimaryPart :: BasePart).CFrame
	local focus = core.Position + Vector3.new(0, 1, 0)
	local eye = focus + core.LookVector * 9.5 + core.RightVector * 3 + Vector3.new(0, 4.2, 0)
	local goal = CFrame.lookAt(eye, focus)
	if reduced() then
		camera.CFrame = goal
	else
		TweenService
			:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal })
			:Play()
	end
	setBodyHidden(true)
end

local function cameraBack()
	setBodyHidden(false)
	local saved = savedCamera
	savedCamera = nil
	local camera = Workspace.CurrentCamera
	if not saved or camera.CameraType ~= Enum.CameraType.Scriptable then
		return
	end
	if reduced() then
		camera.CFrame = saved
		camera.CameraType = Enum.CameraType.Custom
		return
	end
	local tw = TweenService:Create(
		camera,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ CFrame = saved }
	)
	tw.Completed:Once(function()
		if camera.CameraType == Enum.CameraType.Scriptable and savedCamera == nil then
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
	tw:Play()
end

-- Sheet ---------------------------------------------------------------------------------------------

-- This chest's tier: its config, and its part of the server's status.
local function tierName(): string
	local spot = currentChest and CH.Spots[currentChest]
	return if spot then spot.Tier else "Common"
end
local function tierStatus(): any?
	return status and status.tiers and status.tiers[tierName()]
end

-- "Rare or better", or "Any cosmetic" for a tier that can drop everything.
local function guarantee(tier: any): string
	for _, r in { "Common", "Rare", "Epic", "Legendary" } do
		if (tier.RarityWeights[r] or 0) > 0 then
			return if r == "Common" then "Any cosmetic can drop" else ("Guaranteed %s or better"):format(r)
		end
	end
	return ""
end

-- The free-chest lines: "Common Chest: free after 1 match (done)" and so on.
local function renderFree()
	local lines = {}
	local matches = if status then tonumber(status.matches) or 0 else 0
	for _, f in (if status then status.free else nil) or {} do
		local line
		if f.claimed then
			line = ("%s: opened today ✓"):format(f.name)
		elseif matches >= f.need then
			line = ("%s: FREE now!"):format(f.name)
		else
			line = ("%s: free after %d match%s (%d/%d)"):format(
				f.name,
				f.need,
				if f.need == 1 then "" else "es",
				matches,
				f.need
			)
		end
		table.insert(lines, line)
	end
	freeLabel.Text = table.concat(lines, "\n")
end

local function buildWheel(slots: { string })
	slotsShown = slots
	slotFrames = SpinController.drawWheel(rotor, slots, owned, CH.DuplicateCoins)
	SpinController.drawOdds(oddsList, slots)
end

local function renderButtons()
	local tier = (CH.Tiers :: any)[tierName()]
	local ts = tierStatus()
	local cost = if ts then ts.cost else tier.Cost
	sheetRef.title.Text = tier.Name
	sheetRef.subtitle.Text = guarantee(tier) .. ". Every slot is equally likely."
	priceLabel.Text = ("%s coins"):format(ShopController.commas(cost))
	renderFree()
	if opening then
		Theme.setText(openButton, "Opening...")
		Theme.setEnabled(openButton, false)
	elseif ts and ts.free then
		Theme.setText(openButton, "Open for FREE")
		Theme.recolor(openButton, "primary")
		Theme.setEnabled(openButton, true)
	elseif status and status.restricted then
		Theme.setText(openButton, "Not available in your region")
		Theme.recolor(openButton, "secondary")
		Theme.setEnabled(openButton, false)
	elseif coins >= cost then
		Theme.setText(openButton, ("Open for %s coins"):format(ShopController.commas(cost)))
		Theme.recolor(openButton, "primary")
		Theme.setEnabled(openButton, true)
	else
		Theme.setText(openButton, ("Need %s more coins"):format(ShopController.commas(cost - coins)))
		Theme.recolor(openButton, "secondary")
		Theme.setEnabled(openButton, false)
	end
	balanceLabel.Text = ("You have %s coins"):format(ShopController.commas(coins))
end

local function backdrop(): GuiObject
	return ShopController.getBackdrop()
end

function ChestController.open(on: boolean)
	if on and not inHub() then
		return
	end
	if on then
		if not ShopController.isOpen(panel) then
			SoundController.play("UIOpen")
		end
		ShopController.closeAll()
		local ts = tierStatus()
		if ts then
			buildWheel(ts.slots or {})
		end
		Theme.show(panel, backdrop())
		renderButtons()
		Theme.focus(openButton)
	elseif not opening then
		if ShopController.isOpen(panel) then
			Theme.setHome(nil)
		end
		Theme.hide(panel, backdrop())
		Theme.hide(reveal)
	end
end

local function stopSpin()
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
end

local function setRotation(r: number)
	rotation = r
	rotor.Rotation = r % 360
	local n = math.max(#slotsShown, 1)
	local slot = math.floor((r + 180 / n) / (360 / n))
	if slot ~= lastTick then
		lastTick = slot
		SoundController.play("WheelTick")
	end
end

-- Spin up and ease out onto slot `index` under the pointer, at least 4 turns on.
local function landOn(index: number, onDone: () -> ())
	stopSpin()
	local n = #slotsShown
	local theta = (index - 1) * 360 / n
	local from = rotation
	local target = math.ceil((from + 4 * 360 + theta) / 360) * 360 - theta
	target += Random.new():NextNumber(-0.3, 0.3) * 360 / n
	local duration = if reduced() then 1.2 else CH.SpinDuration
	local t0 = os.clock()
	spinConn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		setRotation(from + (target - from) * (1 - (1 - a) ^ 4))
		if a >= 1 then
			stopSpin()
			onDone()
		end
	end)
end

-- Give the camera and the sheet back (the open finished, failed or was cut short).
local function endShot()
	cameraBack()
	HUDController.setCinematic(false)
end

local function finishOpen()
	opening = false
	renderButtons()
end

local function abortOpen(message: string?)
	openToken += 1
	stopSpin()
	local s = currentChest and stateOf(currentChest)
	if s and s.mode == "rattle" then
		s.mode = "idle"
	end
	endShot()
	finishOpen()
	if message then
		SoundController.play("UIError")
		HUDController.hint(message, 1.6)
	end
	if inHub() then
		Theme.show(panel, backdrop())
		Theme.focus(openButton)
	end
end

function ChestController.openChest()
	if opening or not currentChest or not inHub() then
		return
	end
	local ts = tierStatus()
	local free = ts ~= nil and ts.free == true
	if status and status.restricted and not free then
		SoundController.play("UIError")
		HUDController.hint("Chests aren't available in your region", 1.5)
		return
	end
	local cost = if ts then ts.cost else (CH.Tiers :: any)[tierName()].Cost
	if not free and coins < cost then
		SoundController.play("UIError")
		HUDController.hint(("Need %s more coins"):format(ShopController.commas(cost - coins)), 1.5)
		return
	end
	local s = stateOf(currentChest)
	if not s then
		return
	end
	opening = true
	openToken += 1
	local token = openToken
	renderButtons()
	Theme.hide(reveal)
	-- the sheet steps aside but the backdrop stays up (clear), so the server keeps us in the hub
	Theme.hide(panel)
	local bd = backdrop()
	TweenService:Create(bd, TweenInfo.new(Theme.Motion.Base), { BackgroundTransparency = 1 }):Play()
	HUDController.setCinematic(true)
	cameraToChest(s)
	rattle(s)
	Net.request(Net.Actions.OpenChest, { chest = currentChest })
	-- if the server never answers, don't leave the chest rattling forever
	task.delay(7, function()
		if opening and token == openToken and s.mode == "rattle" then
			abortOpen("Couldn't open the chest, try again")
		end
	end)
end

local function onResult(d: any)
	local s = d.chest and stateOf(d.chest)
	if not opening or d.chest ~= currentChest or not s then
		return
	end
	if d.ok == false then
		abortOpen(tostring(d.message or "Can't open the chest right now"))
		return
	end
	local token = openToken
	-- keep rattling a beat for the drama, then burst
	task.wait(math.max(0, MIN_RATTLE - (os.clock() - s.since)))
	if token ~= openToken then
		return
	end
	burstOpen(s, CH.LidOpenTime + CH.SpinDuration)
	task.wait(SHOT_HOLD)
	if token ~= openToken then
		return
	end
	endShot()
	if not inHub() then
		finishOpen()
		return
	end
	-- the wheel shown should already be this one; rebuild if anything changed
	local same = #d.slots == #slotsShown
	for i, id in d.slots do
		same = same and slotsShown[i] == id
	end
	if not same then
		buildWheel(d.slots)
	end
	Theme.show(panel, backdrop())
	SoundController.play("SpinStart")
	landOn(d.index, function()
		if token ~= openToken then
			return
		end
		local slot = slotFrames[d.index]
		if slot then
			Theme.pop(slot, 1.5, 0.4)
		end
		rarityFlash(s, d.rarity)
		task.delay(0.35, function()
			if token ~= openToken then
				return
			end
			finishOpen()
			SpinController.drawReveal(reveal, d, openButton)
			-- the next wheel (from the profile push) appears once the reveal is up
			local ts = tierStatus()
			if ts then
				buildWheel(ts.slots or {})
			end
		end)
	end)
end

function ChestController.init()
	local sheet = ShopController.sheet(
		"Chest",
		"Loot chest",
		SHEET_SIZE,
		"Any cosmetic can drop. Every slot is equally likely.",
		{ tone = T.sun, glyph = "star" }
	)
	sheetRef = sheet
	panel = sheet.frame
	sheet.close.Activated:Connect(function()
		ChestController.open(false)
	end)
	local body = sheet.body :: Frame
	rotor = SpinController.wheelFrame(body, "Loot", T.sun)

	-- info column: price, odds, open button, balance
	local infoCol = new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -420, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, body)
	new("UIListLayout", {
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, infoCol)
	local priceRow = new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, infoCol)
	Theme.coin(priceRow, 30, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 5,
	})
	priceLabel = Theme.label(priceRow, {
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, 0)
	-- today's free chests, under the price
	freeLabel = Theme.body(infoCol, {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = Theme.LabelFace,
		Text = "",
		TextColor3 = T.success,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	local oddsWell = Theme.well(infoCol, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 4 * 26 + 3 * 6 + 24 + 36),
		ZIndex = 4,
	}, Theme.Radius.M)
	Theme.padding(oddsWell, Theme.Space.L, Theme.Space.M)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, oddsWell)
	Theme.body(oddsWell, {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.LabelFace,
		Text = "Odds in this chest",
		TextColor3 = T.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	oddsList = new("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 4 * 26 + 3 * 6),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, oddsWell)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, oddsList)
	openButton = Theme.button(infoCol, "Open", "primary", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 60),
		ZIndex = 4,
	})
	openButton.Activated:Connect(ChestController.openChest)
	balanceLabel = Theme.body(infoCol, {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = Theme.BodyFace,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	Theme.body(infoCol, {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = Theme.TextFace,
		Text = "Prizes you already own pay coins instead.",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})

	-- prize reveal card (over the sheet's content)
	reveal = new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 400),
		BackgroundColor3 = T.surfaceSunk,
		Visible = false,
		ZIndex = 20,
		Active = true,
		ClipsDescendants = true,
	}, body)
	Theme.corner(reveal, Theme.Radius.L)
	Theme.stroke(reveal, T.sun, 4)

	ShopController.onCloseAll(function()
		ChestController.open(false)
	end)
end

function ChestController.start()
	Net.on("Profile", function(d)
		status = d.chest
		owned = d.owned or {}
		coins = tonumber(d.coins) or 0
		local ts = tierStatus()
		if ts and not opening then
			buildWheel(ts.slots or {})
		end
		renderButtons()
	end)
	Net.on("ChestResult", onResult)
	Net.on("ChestOpened", function(d)
		if d.userId == player.UserId or HubController.lobbyHidden then
			return
		end
		local s = stateOf(d.chest)
		if not s or s.mode ~= "idle" then
			return
		end
		-- someone else's open: the same rattle, burst and rarity flash, without the camera
		rattle(s)
		task.wait(MIN_RATTLE)
		burstOpen(s, CH.LidOpenTime + CH.SpinDuration)
		task.wait(SHOT_HOLD + (tonumber(d.delay) or CH.SpinDuration))
		rarityFlash(s, tostring(d.rarity))
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "ChestPrompt" or opening then
			return
		end
		local index = prompt:GetAttribute("ChestIndex")
		if type(index) == "number" then
			currentChest = index
			ChestController.open(true)
		end
	end)
	RunService.RenderStepped:Connect(function()
		-- leaving the hub (pulled into a match) cuts any open short; the prize is already saved
		if opening and not inHub() then
			abortOpen(nil)
		end
		if not inHub() and panel.Visible and not opening then
			ChestController.open(false)
		end
		if HubController.lobbyHidden then
			return
		end
		local t = os.clock()
		for _, m in CollectionService:GetTagged("LootChest") do
			local index = m:GetAttribute("ChestIndex")
			if type(index) == "number" then
				local s = stateOf(index)
				if s then
					animateChest(s, t)
				end
			end
		end
	end)
end

return ChestController
