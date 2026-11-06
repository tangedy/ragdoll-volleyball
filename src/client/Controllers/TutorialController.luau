--!strict
-- The guided tutorial (docs/prompts/build-path.md). The server owns the step (the Tutorial
-- message); this shows it. You play it on your own copy of the court (PracticeController):
--  * a bold step card at the top centre: a step counter, a headline and one line of help adapted to
--    mouse, touch or gamepad, with a "Nice!" beat and the UIStep sound between steps
--  * a bouncing 3D arrow over what to go for next (a ball, the Heavy ball, the dummy), the floor
--    chevrons to a ball (BallGuideController) and a pulsing outline on the touch button to press
--  * the Done celebration with the reward; closing it takes you to the hub and the daily sheet
-- Afterwards, a catch hint once a match in a player's first few matches (Config.Damage.HintMatches).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallDefinitions = require(Shared.BallDefinitions)
local Net = require(script.Parent.Net)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AimController = require(script.Parent.AimController)
local InputController = require(script.Parent.InputController)
local BallGuideController = require(script.Parent.BallGuideController)
local SoundController = require(script.Parent.SoundController)
local HUDController = require(script.Parent.HUDController)
local PracticeController = require(script.Parent.PracticeController)

local player = Players.LocalPlayer
local TU = Config.Tutorial
local T = Theme.Toybox
local STEPS = TU.Done - 1 -- the counter's steps (Done is the celebration)
local CHEER = 0.8 -- seconds of "Nice!" between steps

local TutorialController = {}

local serverStep = 0
local step = 0 -- what's shown: the server's step, or an RD_Gallery one
local debugging = false
local stepAt = 0
local cheerUntil = 0
local profileMatches = math.huge -- until the Profile arrives, no match hints

type Card = {
	holder: Frame,
	badge: Frame,
	count: TextLabel,
	title: TextLabel,
	help: TextLabel,
	chips: Frame,
}
local gui: ScreenGui
local card: Card
local done: ScreenGui? = nil
local arrow: Model? = nil
local shownKey = ""

-- Words -------------------------------------------------------------------------------------------

local function holding(): string
	local held = player:GetAttribute("HeldBall")
	return if type(held) == "string" then held else ""
end

-- Step 3 opens with two callouts, CardSeconds each: the dummy's % ("Dummy"), then your own HUD %
-- ("Yours"). nil once both have shown.
local function callout(): string?
	if step ~= 3 or os.clock() < cheerUntil then
		return nil
	end
	local since = os.clock() - stepAt
	return if since < TU.CardSeconds then "Dummy" elseif since < 2 * TU.CardSeconds then "Yours" else nil
end

-- Headline, help line (each <= 10 words) and the touch button to point at.
local function copy(): (string, string, string?)
	local input = AimController.lastInput
	local touch, pad = input == "Touch", input == "Gamepad"
	local throwHelp = if touch
		then "Aim at it and tap THROW"
		elseif pad then "Aim at it and press RT"
		else "Aim at it and click to throw"
	if step == 1 then
		return "Grab a ball!", "Follow the arrows and walk over it", nil
	elseif step == 2 then
		if holding() == "" then
			return "Hit the dummy!", "First, grab a ball", nil
		end
		return "Hit the dummy!", throwHelp, "Throw"
	elseif step == 3 then
		local c = callout()
		if c == "Dummy" then
			return "Its % went up!", "It goes up with every hit", nil
		elseif c == "Yours" then
			return "This is YOUR %!", "Higher % = you fly further", nil
		end
		return "Knock it off the court!", "Keep hitting it until it falls off", "Throw"
	elseif step == 4 then
		if holding() == "Heavy" then
			return "Throw the HEAVY ball!", "One hit knocks it off", "Throw"
		end
		return "You got a HEAVY ball!", "Grab the big orange ball", nil
	elseif step == 5 then
		-- in matches the Heavy power (F / Y / POWER) makes them; the shop sells more powers
		return "That was your HEAVY power!", "Use it in matches, and unlock more in the shop", nil
	elseif step == 6 then
		return "Dodge a close call!",
			if touch
				then "Tap DODGE just before the ball hits you"
				elseif pad then "Press X just before the ball hits you"
				else "Press Q just before the ball hits you",
			"Dodge"
	end
	return "", "", nil
end

local function catchHint(): string
	local input = AimController.lastInput
	if input == "Touch" then
		return "Tap CATCH as a ball arrives to catch it!"
	elseif input == "Gamepad" then
		return "Press LB as a ball arrives to catch it!"
	end
	return "Press E as a ball arrives to catch it!"
end

-- Step card ---------------------------------------------------------------------------------------

-- the card hugs the top edge (the phase pill and quest panel are hidden until the tutorial is done)
local CARD_TOP = Theme.Space.S

local function buildCard(parent: ScreenGui): Card
	-- top centre: clear of the hub icons (right)
	local holder = Theme.panel(parent, {
		Name = "StepCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CARD_TOP),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 88),
		Visible = false,
	}, Theme.Radius.L)
	Theme.stroke(holder, T.outline, Theme.StrokeToy)
	Theme.padding(holder, Theme.Space.L, 0)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, holder)
	Theme.autoScale(holder)
	-- the step counter: a big sun disc (leaf with a check for the "Nice!" beat)
	local badge = Theme.new("Frame", {
		Name = "Badge",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = T.sun,
	}, holder)
	Theme.round(badge)
	Theme.stroke(badge, T.outline, Theme.StrokeToy)
	local count = Theme.label(badge, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.5),
		Text = "1/6",
	}, 0)
	local words = Theme.new("Frame", {
		Name = "Words",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 62),
	}, holder)
	Theme.new("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, words)
	local title = Theme.text(words, 30, {
		LayoutOrder = 1,
		FontFace = Theme.DisplayFace,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local help = Theme.text(words, 18, {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.inkMuted,
	})
	-- ball chips (the Heavy and Discover steps)
	local chips = Theme.new("Frame", {
		Name = "Chips",
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 70),
		Visible = false,
	}, holder)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, Theme.Space.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chips)
	return { holder = holder, badge = badge, count = count, title = title, help = help, chips = chips }
end

-- Top centre, unless that would cover the daily quest panel (phones, and the wider Heavy and Discover
-- cards): then just right of it, as far as the screen edge allows.
local function placeCard()
	local holder = card.holder
	local origin = gui.AbsolutePosition
	local width = gui.AbsoluteSize.X
	-- its resting width, so a pop doesn't slide it sideways (Theme.autoScale's UIScale and Base)
	local scale = holder:FindFirstChildOfClass("UIScale")
	local base = scale and scale:GetAttribute("Base")
	local w = holder.AbsoluteSize.X
	if scale and scale.Scale > 0 and type(base) == "number" then
		w = w / scale.Scale * base
	end
	local left = Theme.Space.M
	local hub = player.PlayerGui:FindFirstChild("Hub")
	local quests = hub and hub:FindFirstChild("Quests") :: GuiObject?
	if quests and quests.Visible then
		local qa, qs = quests.AbsolutePosition, quests.AbsoluteSize
		local top = holder.AbsolutePosition.Y
		if qa.Y < top + holder.AbsoluteSize.Y and qa.Y + qs.Y > top then
			left = qa.X + qs.X - origin.X + Theme.Space.S
		end
	end
	local x = math.max(width / 2, left + w / 2)
	x = math.min(x, math.max(left + w / 2, width - Theme.Space.M - w / 2))
	holder.Position = UDim2.fromOffset(math.floor(x + 0.5), CARD_TOP)
end

-- A ball type as a sticker: its colour in a toy disc, a mark on it ("✓" found, "?" still to find),
-- and its name under it. A ball still to find is a dark silhouette of its colour.
local function chip(parent: Instance, ballType: string, mark: string, order: number)
	local def = BallDefinitions.get(ballType)
	local found = mark ~= "?"
	local f = Theme.new("Frame", {
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(58, 70),
	}, parent)
	local disc = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = if found then def.Color else Theme.darken(def.Color, 0.45),
	}, f)
	Theme.round(disc)
	Theme.stroke(disc, T.outline, Theme.StrokeToy)
	if mark ~= "" then
		Theme.label(disc, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Text = mark,
		}, 2)
	end
	Theme.text(f, 13, {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 18),
		Text = if found then def.DisplayName else "???",
	})
end

local function setChips(kind: string)
	for _, c in card.chips:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	card.chips.Visible = kind ~= ""
	if kind == "Heavy" then
		chip(card.chips, "Heavy", "", 1)
	elseif kind == "Discover" then
		chip(card.chips, "Heavy", "✓", 1)
		chip(card.chips, "Rocket", "?", 2)
		chip(card.chips, "Pop", "?", 3)
	end
end

-- 3D arrow ----------------------------------------------------------------------------------------

-- A chunky sun-yellow arrow pointing down, drawn with an ink outline that shows through walls.
local function buildArrow(): Model
	local m = Instance.new("Model")
	m.Name = "TutorialArrow"
	local function part(className: string, size: Vector3, cf: CFrame)
		Theme.new(className, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.SmoothPlastic,
			Color = T.sun,
			Size = size,
			CFrame = cf,
		}, m)
	end
	-- big enough to read from the far side of the court; its tip sits 0.8 under the pivot
	part("Part", Vector3.new(1.5, 3, 1.5), CFrame.new(0, 3.1, 0))
	-- the head: two wedges back to back make a triangle, turned over so it points down
	local flip = CFrame.Angles(0, 0, math.pi)
	part("WedgePart", Vector3.new(1.7, 2.4, 2), flip * CFrame.new(0, -0.4, -1))
	part("WedgePart", Vector3.new(1.7, 2.4, 2), flip * CFrame.new(0, -0.4, 1) * CFrame.Angles(0, math.pi, 0))
	m.WorldPivot = CFrame.new()
	Theme.new("Highlight", {
		FillTransparency = 1,
		OutlineColor = T.outline,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	}, m)
	return m
end

-- Where the arrow points now: a ball to grab (the Heavy one at the Heavy step), else the dummy.
local function arrowTarget(): Vector3?
	if not PracticeController.onCourt() or step < 1 or step >= TU.Done or step == 5 then
		return nil
	end
	local held = holding()
	local wantBall = step == 1 or (held == "" and step <= 4) or (step == 4 and held ~= "Heavy")
	if wantBall then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local best: BasePart? = nil
		local bestD = math.huge
		for _, b in PracticeController.ballParts() do
			local free = b.state == "Resting" or b.state == "Loose"
			if free and (step ~= 4 or b.ballType == "Heavy") then
				local d = if root then (b.part.Position - root.Position).Magnitude else 0
				if d < bestD then
					best, bestD = b.part, d
				end
			end
		end
		return if best then best.Position + Vector3.new(0, best.Size.Y / 2 + 2, 0) else nil
	end
	local dummy = PracticeController.dummyModel()
	local head = dummy and dummy:FindFirstChild("Head") :: BasePart?
	-- above the dummy's % and name tags (PracticeController: 2.2 and 4.4 studs over the head)
	return if head then head.Position + Vector3.new(0, 6.6, 0) else nil
end

local function updateArrow()
	local at = arrowTarget()
	if not at then
		if arrow then
			arrow.Parent = nil
		end
		return
	end
	local m = arrow or buildArrow()
	arrow = m
	local t = os.clock()
	local bob = if Theme.settings.reducedMotion then 0 else 0.5 * math.sin(t * 5)
	m:PivotTo(CFrame.new(at + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * 2.5, 0))
	m.Parent = Workspace
end

-- % callouts --------------------------------------------------------------------------------------

-- A breathing select-coloured ring round a % (the dummy's billboard, or your HUD %). The "Yours" ring
-- also wears a sun "YOU" sticker pointing down at the number.
local rings: { [string]: Frame } = {}

local function makeRing(parent: GuiObject, sticker: boolean): Frame
	local ring = Theme.new("Frame", {
		Name = "TutorialRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 16, 1, 10),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, parent)
	Theme.corner(ring, Theme.Radius.L)
	Theme.stroke(ring, Theme.Colors.Select, 4)
	if sticker then
		local tag = Theme.new("Frame", {
			Name = "You",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, -10),
			Size = UDim2.fromOffset(78, 32),
			BackgroundColor3 = T.sun,
		}, ring)
		Theme.corner(tag, Theme.Radius.M)
		Theme.stroke(tag, T.outline, Theme.StrokeToy)
		Theme.text(tag, 20, { Size = UDim2.fromScale(1, 1), FontFace = Theme.DisplayFace, Text = "YOU" })
		-- the point: a turned square tucked under the sticker
		local point = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			BackgroundColor3 = T.sun,
			ZIndex = 0,
		}, tag)
		Theme.stroke(point, T.outline, Theme.StrokeToy)
	end
	Theme.pop(ring, 1.3, Theme.Motion.Base)
	return ring
end

local function setRing(key: string, parent: GuiObject?)
	local ring: Frame? = rings[key]
	if ring and (parent == nil or ring.Parent ~= parent) then
		ring:Destroy()
		rings[key] = nil
		ring = nil
	end
	if parent and not ring then
		ring = makeRing(parent, key == "Yours")
		rings[key] = ring
	end
	if ring then
		local stroke = ring:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if Theme.settings.reducedMotion then 4 else 4 + 2 * math.sin(os.clock() * 8)
		end
	end
end

local function updateCallouts(showing: boolean)
	local c = if showing then callout() else nil
	local dummy = PracticeController.dummyModel()
	local head = dummy and dummy:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("DamageTag")
	local label = tag and tag:FindFirstChildWhichIsA("TextLabel")
	setRing("Dummy", if c == "Dummy" then label else nil)
	setRing("Yours", if c == "Yours" then HUDController.damageFrame() else nil)
	-- your own % shows from the callout on (the dodge drill raises it when you're hit)
	HUDController.tutorialDamage = showing and step >= 3
end

-- Done --------------------------------------------------------------------------------------------

-- `toHub` is false when a match took you off first (the queue opens as the tutorial ends, and a
-- match can start while this card is up): no daily sheet then, and the server has moved you already.
local function closeDone(toHub: boolean)
	local g = done
	if not g then
		return
	end
	done = nil
	g:Destroy()
	PracticeController.finishTutorial()
	if toHub then
		-- the daily rewards sheet waits until now (ShopController only opens it by itself after a match)
		local ShopController = require(script.Parent.ShopController) :: any
		ShopController.openDaily(true)
	end
end

-- The celebration: confetti, the reward counting up, "You're ready!" and one button.
local function showDone(reward: any?)
	if done then
		return
	end
	local coins = if type(reward) == "table" and type(reward.coins) == "number" then reward.coins else 0
	local g = Theme.new("ScreenGui", {
		Name = "TutorialDone",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	done = g
	Theme.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.dim,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, g)
	local panel = Theme.panel(g, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, if coins > 0 then 330 else 260),
	}, Theme.Radius.XL)
	Theme.stroke(panel, T.outline, Theme.StrokeToy)
	Theme.autoScale(panel)
	-- a loud leaf band across the top with the sticker
	local band = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = T.leaf,
		BorderSizePixel = 0,
	}, panel)
	Theme.corner(band, Theme.Radius.XL)
	Theme.label(band, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 34),
		Text = "TUTORIAL COMPLETE!",
	}, 3)
	Theme.text(panel, 44, {
		FontFace = Theme.DisplayFace,
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 0, 52),
		Text = "You're ready!",
	})
	local y = 134
	if coins > 0 then
		local row = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 56),
			BackgroundTransparency = 1,
		}, panel)
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.Space.S),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		local disc = Theme.new("Frame", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = T.sun,
		}, row)
		Theme.round(disc)
		Theme.stroke(disc, T.outline, Theme.StrokeToy)
		Theme.glyph(disc, "coin", T.outline, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
		})
		local amount = Theme.text(row, 44, {
			LayoutOrder = 2,
			FontFace = Theme.DisplayFace,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 52),
			Text = "+0",
		})
		-- count up like the results card's coins
		task.spawn(function()
			SoundController.play("CoinGain")
			local t0 = os.clock()
			local length = if Theme.settings.reducedMotion then 0 else 0.9
			repeat
				local k = if length > 0 then math.clamp((os.clock() - t0) / length, 0, 1) else 1
				amount.Text = ("+%d"):format(math.floor(coins * (1 - (1 - k) ^ 3) + 0.5))
				RunService.RenderStepped:Wait()
			until k >= 1 or done ~= g
			Theme.pop(amount, 1.4, Theme.Motion.Base)
		end)
		y += 66
	end
	Theme.text(panel, 18, {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = T.inkMuted,
		Text = "Now knock real players off the court!",
	})
	local button = Theme.button(panel, "Let's play!", T.leaf, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.fromOffset(220, 58),
	})
	button.Activated:Connect(function()
		closeDone(true)
	end)
	Theme.pop(panel, 0.6, Theme.Motion.Slow)
	Theme.focus(button)
	SoundController.play("UISuccess")
	HUDController.confetti(T.leaf)
end

-- Gallery -----------------------------------------------------------------------------------------

-- Studio UI gallery hook (RD_Gallery "Tutorial1".."Tutorial7"; 0 goes back to the real step).
function TutorialController.debugStep(n: number)
	debugging = n > 0
	if done then
		done:Destroy()
		done = nil
	end
	step = if debugging then n else serverStep
	stepAt = os.clock()
	if n >= TU.Done then
		showDone({ kind = "Coins", coins = TU.Reward.Amount })
	end
end

-- Lifecycle ---------------------------------------------------------------------------------------

function TutorialController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")
	card = buildCard(gui)
end

function TutorialController.start()
	-- the court's practice balls come out as the card gets to them
	PracticeController.cardStep = function(): number
		return if os.clock() < cheerUntil or callout() ~= nil then step - 1 else step
	end
	Net.on("Tutorial", function(d)
		if type(d) ~= "table" or type(d.step) ~= "number" then
			return
		end
		local was = serverStep
		serverStep = d.step
		if debugging then
			return
		end
		local g = done
		if g and d.step < TU.Done then
			-- the dev reset (RD_Gallery "TutorialReset") while the Done card was up
			g:Destroy()
			done = nil
		end
		local finished = was >= 1 and was < TU.Done -- not just the sync on join
		step = d.step
		stepAt = os.clock()
		if finished and d.step > was then
			-- a "Nice!" beat on the card, then the next step (or the celebration)
			SoundController.play("UIStep")
			cheerUntil = os.clock() + CHEER
			stepAt = cheerUntil
			if d.step >= TU.Done then
				local reward = d.reward
				task.delay(CHEER, function()
					showDone(reward)
				end)
			end
		end
	end)
	Net.on("Profile", function(d)
		if type(d) == "table" then
			profileMatches = tonumber(d.matches) or 0
		end
	end)
	-- a player's first few matches: the catch hint, once a match, a little after the first round
	-- starts (the server's "Hit them off the court!" shows first)
	local hinted = false
	player:GetAttributeChangedSignal("Team"):Connect(function()
		if (player:GetAttribute("Team") or "") == "" then
			hinted = false
		end
	end)
	Net.MatchState:GetAttributeChangedSignal("State"):Connect(function()
		local inMatch = (player:GetAttribute("Team") or "") ~= ""
		if hinted or not inMatch or Net.MatchState:GetAttribute("State") ~= "RoundActive" then
			return
		end
		if profileMatches >= Config.Damage.HintMatches then
			return
		end
		hinted = true
		task.delay(6, function()
			if Net.MatchState:GetAttribute("State") == "RoundActive" then
				HUDController.hint(catchHint(), 3.5, true)
			end
		end)
	end)

	local lastPointer: string? = nil
	RunService.RenderStepped:Connect(function()
		if done and (player:GetAttribute("Team") or "") ~= "" then
			closeDone(false)
		end
		local showing = step >= 1 and step < TU.Done and done == nil and (debugging or PracticeController.onCourt())
		BallGuideController.enabled = showing and step <= 4 and (step == 1 or holding() == "")
		card.holder.Visible = showing
		updateArrow()
		updateCallouts(showing)
		local pointer: string? = nil
		if showing then
			local cheering = os.clock() < cheerUntil
			local title, help
			if cheering then
				title, help = "Nice!", ""
			else
				title, help, pointer = copy()
			end
			local chips = if cheering then "" elseif step == 4 then "Heavy" elseif step == 5 then "Discover" else ""
			local key = title .. "|" .. help .. "|" .. chips .. "|" .. step
			if key ~= shownKey then
				shownKey = key
				card.title.Text = title
				card.help.Text = help
				card.help.Visible = help ~= ""
				card.count.Text = if cheering then "✓" else ("%d/%d"):format(step, STEPS)
				card.badge.BackgroundColor3 = if cheering then T.leaf else T.sun
				setChips(chips)
				Theme.pop(card.holder, if cheering then 1.15 else 0.85, Theme.Motion.Base)
			end
			placeCard()
		else
			shownKey = ""
		end
		-- point at the exact touch button with a breathing select-colored outline
		if pointer == nil and lastPointer == nil then
			return -- nothing pointed at now or last frame: the outlines are already at rest
		end
		lastPointer = pointer
		for _, set in { InputController.buttons, InputController.keyButtons } do
			for name, b in set do
				local stroke = b:FindFirstChild("Outline", true) :: UIStroke?
				if stroke then
					local pulsing = pointer == name
					local restColor = stroke:GetAttribute("RestColor")
					local restThickness = stroke:GetAttribute("RestThickness")
					local restTransparency = stroke:GetAttribute("RestTransparency")
					stroke.Color = if pulsing
						then Theme.Colors.Select
						elseif typeof(restColor) == "Color3" then restColor
						else Theme.Colors.Outline
					stroke.Thickness = if pulsing
						then 5 + 2 * math.sin(os.clock() * 8)
						elseif type(restThickness) == "number" then restThickness
						else Theme.StrokeToy
					stroke.Transparency = if pulsing
						then 0
						elseif type(restTransparency) == "number" then restTransparency
						else 0
				end
			end
		end
	end)
end

return TutorialController
