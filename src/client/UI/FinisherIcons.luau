--!strict
-- Finisher icons for the shop cards, the spin wheel and the chest picks: little sticker
-- illustrations built from plain frames (nothing to upload), one per finisher module.
--
-- An icon is drawn in a 100x100 box as a list of layers, back to front. A layer is a list of shapes
-- read as one silhouette: with `o` set, the toy outline (o/100 of the box) goes round the union of
-- its shapes. The outlines are drawn first and the fills over them, so no seams show inside.
--
-- A shape is centred on (x, y) and w x h in its parent's 100x100 space:
--   k     "c" a circle (a pill when w ~= h), "r" a rectangle, "t" text
--   c     fill color (hex, or "ink" for the theme outline); c2 fades to it from top to bottom
--   rot   degrees, clockwise; it turns the shape's kids too
--   r     corner rounding, 0 (square) to 1 (fully round ends)
--   t, t2 transparency (t2 fades to it from top to bottom)
--   s     an outline of its own (for shapes in a layer without `o`)
--   text, font   for "t": the text, and "label" for the rounder label font (else the display font)
--   kids  shapes drawn on top of this one, in its own 100x100 space
--
-- The data is plain so tools can render it outside Roblox (see tools/preview_finisher_icons.luau).

export type Shape = {
	k: string,
	x: number,
	y: number,
	w: number,
	h: number,
	c: string,
	c2: string?,
	rot: number?,
	r: number?,
	t: number?,
	t2: number?,
	s: number?,
	text: string?,
	font: string?,
	kids: { Shape }?,
}
export type Layer = { [number]: Shape, o: number? }
export type Icon = { Layer }

local FinisherIcons = {}

-- palette
local RED, RED_D = "#ff4d4d", "#d42a3a"
local GOLD, GOLD_D = "#ffd23f", "#f29e1f"
local YELLOW = "#ffe14d"
local ORANGE = "#ff8a2a"
local PINK = "#ff5fa2"
local BLUE, BLUE_D = "#4dc3ff", "#1f84e0"
local GREEN = "#7ee36b"
local VIOLET = "#8c4bff"
local LILAC = "#c9a6ff"
local WHITE = "#ffffff"
local STEEL, STEEL_D = "#6d7388", "#474c5e"
local SILVER = "#d6d9e4"
local WOOD, WOOD_D = "#e0a868", "#b97a40"

local function circle(x: number, y: number, d: number, c: string, extra: { [string]: any }?): Shape
	local s: any = { k = "c", x = x, y = y, w = d, h = d, c = c }
	if extra then
		for key, v in extra do
			s[key] = v
		end
	end
	return s
end

local function rect(x: number, y: number, w: number, h: number, c: string, extra: { [string]: any }?): Shape
	local s: any = { k = "r", x = x, y = y, w = w, h = h, c = c }
	if extra then
		for key, v in extra do
			s[key] = v
		end
	end
	return s
end

-- a pill (fully round ends)
local function pill(
	x: number,
	y: number,
	w: number,
	h: number,
	c: string,
	rot: number?,
	extra: { [string]: any }?
): Shape
	local s: any = { k = "r", x = x, y = y, w = w, h = h, c = c, r = 1, rot = rot }
	if extra then
		for key, v in extra do
			s[key] = v
		end
	end
	return s
end

-- a four-point twinkle: two crossed pills
local function twinkle(x: number, y: number, size: number, c: string): { Shape }
	return { pill(x, y, size * 0.24, size, c, 0), pill(x, y, size * 0.24, size, c, 90) }
end

-- a shine dot for round things
local function shine(x: number, y: number, w: number, h: number, rot: number?): Shape
	return pill(x, y, w, h, WHITE, rot, { t = 0.25 })
end

local function layer(o: number?, shapes: { Shape }): Layer
	local l: any = table.clone(shapes)
	l.o = o
	return l
end

local function join(...: { Shape }): { Shape }
	local out = {}
	for _, list in { ... } do
		for _, s in list do
			table.insert(out, s)
		end
	end
	return out
end

-- a comic impact burst: squares set corner-out round a solid core read as sharp spikes
local function burst(x: number, y: number, d: number, points: number, c: string): { Shape }
	local out = {}
	for i = 0, points - 1 do
		local a = math.rad(i * 360 / points)
		local reach = d * (if i % 2 == 0 then 0.3 else 0.26)
		local size = d * 0.26
		table.insert(
			out,
			rect(x + reach * math.sin(a), y - reach * math.cos(a), size, size, c, { rot = i * 360 / points + 45 })
		)
	end
	table.insert(out, circle(x, y, d * 0.66, c))
	return out
end

local icons: { [string]: Icon } = {}

-- Final Knockout (the default): a yellow impact burst stamped "KO!"
icons.Default = {
	layer(4, burst(50, 50, 100, 12, GOLD)),
	layer(nil, { circle(50, 50, 50, YELLOW) }),
	layer(nil, {
		{ k = "t", x = 50, y = 52, w = 84, h = 46, c = RED, text = "KO!", rot = -8, s = 3.5 },
	}),
}

-- Confetti Pop: a striped party popper firing confetti
icons.ConfettiPop = {
	layer(3.5, {
		rect(64, 22, 11, 7, BLUE, { rot = 30, r = 0.3 }),
		rect(84, 36, 11, 7, YELLOW, { rot = -20, r = 0.3 }),
		rect(72, 52, 11, 7, GREEN, { rot = 60, r = 0.3 }),
		rect(90, 60, 10, 6, PINK, { rot = 10, r = 0.3 }),
		rect(46, 18, 10, 6, LILAC, { rot = -40, r = 0.3 }),
		rect(86, 12, 10, 6, ORANGE, { rot = 45, r = 0.3 }),
		circle(56, 36, 8, PINK),
		circle(76, 24, 7, GREEN),
		circle(92, 44, 7, BLUE),
		circle(68, 8, 6, YELLOW),
	}),
	layer(4, {
		rect(36, 67, 30, 50, PINK, {
			rot = 40,
			r = 0.35,
			c2 = "#e83e86",
			kids = {
				rect(50, 32, 100, 14, YELLOW),
				rect(50, 66, 100, 14, YELLOW),
			},
		}),
	}),
	layer(3, { pill(52, 48, 32, 11, "#8a2a5e", 40) }),
}

-- Air Horn: a red canister with a yellow horn, blasting
icons.AirHorn = {
	layer(3.5, {
		pill(82, 18, 7, 18, WHITE, 40),
		pill(87, 41, 7, 22, WHITE, 0),
		pill(82, 64, 7, 18, WHITE, -40),
	}),
	layer(4, {
		rect(24, 30, 14, 14, SILVER, { r = 0.3 }),
		rect(44, 40, 30, 12, YELLOW),
		rect(58, 40, 14, 24, YELLOW),
		pill(68, 40, 12, 44, GOLD),
		rect(24, 63, 32, 56, RED, {
			r = 0.4,
			c2 = RED_D,
			kids = { rect(50, 36, 100, 18, WHITE), shine(26, 70, 14, 26) },
		}),
	}),
}

-- Sad Trombone: a gold trombone with a droopy blue note
icons.SadTrombone = {
	layer(4, {
		pill(46, 66, 76, 9, GOLD),
		pill(46, 82, 76, 9, GOLD),
		pill(9, 74, 10, 25, GOLD),
		pill(66, 56, 10, 26, GOLD, 40),
		circle(76, 42, 40, GOLD, { c2 = GOLD_D }),
	}),
	layer(nil, { circle(76, 42, 26, "#b8701c", { kids = { circle(50, 50, 52, "#7a4510") } }) }),
	layer(nil, { shine(66, 30, 8, 5, -30) }),
	layer(3.5, {
		circle(22, 40, 17, BLUE, { c2 = BLUE_D }),
		rect(29, 24, 5, 32, BLUE, { r = 1 }),
		pill(36, 16, 6, 16, BLUE, -55),
	}),
	layer(3, { circle(12, 22, 8, "#9fe0ff") }),
}

-- BONK!: a cartoon mallet and impact twinkles
icons.Bonk = {
	layer(4, { rect(62, 71, 13, 52, WOOD, { rot = -30, r = 0.5, c2 = WOOD_D }) }),
	layer(4, {
		rect(40, 36, 62, 36, "#c9874a", {
			rot = -30,
			r = 0.35,
			c2 = "#9b5e30",
			kids = {
				rect(9, 50, 12, 100, "#7a4520"),
				rect(91, 50, 12, 100, "#7a4520"),
				shine(40, 26, 40, 14),
			},
		}),
	}),
	layer(3, join(twinkle(84, 20, 26, YELLOW), twinkle(16, 74, 18, YELLOW), twinkle(86, 52, 14, WHITE))),
}

-- Slow-Mo Replay (a time stop): a stopwatch with a pause badge
icons.SlowMoReplay = {
	layer(4, {
		rect(50, 10, 18, 10, SILVER, { r = 0.3 }),
		rect(50, 18, 9, 10, SILVER),
		rect(79, 24, 11, 9, SILVER, { rot = 45, r = 0.3 }),
		circle(50, 56, 76, BLUE, { c2 = BLUE_D }),
	}),
	layer(nil, {
		circle(50, 56, 58, WHITE, {
			kids = {
				pill(50, 12, 5, 12, "ink"),
				pill(88, 50, 5, 12, "ink", 90),
				pill(50, 88, 5, 12, "ink"),
				pill(12, 50, 5, 12, "ink", 90),
			},
		}),
	}),
	layer(nil, {
		pill(50, 44, 5, 26, "ink"),
		pill(58, 61, 4, 20, RED, 120),
		circle(50, 56, 8, "ink"),
	}),
	layer(3.5, {
		circle(80, 82, 32, YELLOW, {
			kids = { rect(37, 50, 14, 46, "ink", { r = 0.4 }), rect(63, 50, 14, 46, "ink", { r = 0.4 }) },
		}),
	}),
}

-- Paparazzi: a press camera going off
icons.Paparazzi = {
	layer(4, {
		rect(34, 30, 28, 14, STEEL_D, { r = 0.3 }),
		rect(50, 60, 86, 52, STEEL, { r = 0.25, c2 = STEEL_D, kids = { rect(50, 14, 100, 10, "#5a5f73") } }),
	}),
	layer(3.5, {
		circle(52, 60, 42, SILVER, {
			kids = {
				circle(50, 50, 72, "#2b2f3d", { kids = { circle(50, 50, 50, "#3c4560") } }),
				shine(34, 32, 26, 18, -30),
				circle(66, 68, 12, "#7ab8ff"),
			},
		}),
	}),
	layer(nil, { circle(16, 46, 8, RED) }),
	layer(3, join(twinkle(82, 18, 34, YELLOW), { pill(82, 18, 7, 20, YELLOW, 45), pill(82, 18, 7, 20, YELLOW, 135) })),
}

-- Spotlight: a stage lamp throwing a beam onto a star
icons.Spotlight = {
	layer(nil, {
		rect(45, 54, 44, 80, "#fff6b0", { rot = -32, t = 0.55, t2 = 0.8 }),
		rect(45, 54, 24, 80, "#fff6b0", { rot = -32, t = 0.3, t2 = 0.6 }),
	}),
	layer(3.5, { pill(64, 84, 66, 20, "#fff1a0") }),
	layer(nil, {
		{ k = "t", x = 64, y = 74, w = 34, h = 34, c = GOLD, text = "★", font = "label", s = 3 },
	}),
	layer(4, {
		rect(14, 10, 7, 16, STEEL_D, { r = 0.5 }),
		rect(24, 24, 34, 28, STEEL, {
			rot = -32,
			r = 0.3,
			c2 = STEEL_D,
			kids = { rect(50, 92, 84, 18, "#fff6b0", { r = 0.5 }) },
		}),
	}),
}

-- Meteor Strike: a cratered rock with a fiery tail
icons.Meteor = {
	layer(4, { pill(40, 40, 42, 86, ORANGE, -45) }),
	layer(nil, { pill(44, 44, 26, 66, YELLOW, -45), pill(50, 50, 12, 44, "#fff6c8", -45) }),
	layer(4, {
		circle(64, 64, 48, "#8a6a55", {
			c2 = "#5e4536",
			kids = {
				circle(34, 40, 24, "#5e4536"),
				circle(68, 66, 18, "#5e4536"),
				circle(62, 26, 11, "#5e4536"),
				shine(30, 24, 18, 10, -40),
			},
		}),
	}),
	layer(3, { circle(16, 62, 8, YELLOW), circle(64, 14, 7, ORANGE), circle(88, 30, 6, YELLOW) }),
}

-- Pumpkin Reaper: a glowing jack-o-lantern
icons.Pumpkin = {
	layer(4, { rect(52, 16, 12, 22, "#5f9a42", { rot = 15, r = 0.3 }), pill(68, 20, 22, 10, "#7ed957", -20) }),
	layer(4, {
		pill(29, 60, 38, 64, ORANGE, nil, { c2 = "#e8661a" }),
		pill(71, 60, 38, 64, ORANGE, nil, { c2 = "#e8661a" }),
		pill(50, 58, 46, 70, "#ff9a3a", nil, { c2 = "#f07a22" }),
	}),
	layer(nil, { pill(36, 60, 4, 50, "#d85f12", nil, { t = 0.3 }), pill(64, 60, 4, 50, "#d85f12", nil, { t = 0.3 }) }),
	layer(nil, {
		rect(37, 46, 16, 16, YELLOW, { rot = 45, r = 0.2 }),
		rect(63, 46, 16, 16, YELLOW, { rot = 45, r = 0.2 }),
		rect(50, 60, 8, 8, YELLOW, { rot = 45, r = 0.2 }),
		pill(50, 75, 50, 18, YELLOW),
	}),
	-- the grin: the top of the mouth cut away into a crescent, with one square tooth
	layer(nil, { pill(50, 69, 48, 10, "#f5852a"), rect(50, 79, 8, 8, "#f38027") }),
	layer(nil, { shine(36, 32, 12, 7, -20) }),
}

-- Destiny Arrives: a golden gauntlet snapping in front of a swirling portal
icons.DestinyArrives = {
	layer(4, {
		circle(50, 48, 88, "#4a1aa0", {
			c2 = "#2a0d66",
			kids = {
				circle(53, 47, 76, VIOLET),
				circle(56, 45, 52, "#a873ff"),
				circle(58, 44, 28, "#e6d4ff"),
			},
		}),
	}),
	layer(4, {
		pill(43, 50, 9, 24, GOLD),
		pill(51, 46, 9, 30, GOLD),
		pill(59, 47, 9, 28, GOLD),
		pill(67, 51, 8, 22, GOLD),
		pill(36, 66, 10, 24, GOLD, -50),
		rect(55, 68, 34, 30, GOLD, { r = 0.35, c2 = GOLD_D }),
		rect(56, 88, 32, 14, VIOLET, { r = 0.3 }),
	}),
	layer(2.5, { circle(55, 68, 11, "#ff4d8a"), circle(46, 80, 6, BLUE), circle(64, 80, 6, GREEN) }),
	layer(3, twinkle(24, 24, 28, WHITE)),
}

-- Purple Flash: a blue orb and a red orb clashing into violet
icons.PurpleFlash = {
	layer(nil, { circle(50, 50, 98, "#b07cff", { t = 0.6 }), circle(50, 50, 74, "#c79cff", { t = 0.4 }) }),
	layer(4, {
		circle(33, 56, 42, BLUE, { c2 = BLUE_D }),
		circle(67, 44, 42, RED, { c2 = RED_D }),
	}),
	layer(nil, { shine(24, 46, 12, 8, -30), shine(58, 34, 12, 8, -30) }),
	layer(3.5, { circle(50, 50, 28, VIOLET, { kids = { circle(50, 50, 44, WHITE) } }) }),
	layer(3, join(twinkle(84, 82, 22, WHITE), twinkle(16, 18, 16, WHITE))),
}

-- Black Hole: a black hole inside its glowing accretion disk
icons.BlackHole = {
	layer(4, { pill(50, 52, 96, 34, ORANGE, -18, { c2 = PINK }) }),
	layer(nil, { pill(50, 52, 74, 18, "#ffd06b", -18) }),
	layer(nil, { circle(50, 50, 56, VIOLET) }),
	layer(4, { circle(50, 50, 46, "#1a1026") }),
	layer(3, { pill(54, 70, 50, 7, "#ffd06b", -18) }),
	layer(3, {
		rect(14, 20, 9, 9, SILVER, { rot = 20 }),
		rect(86, 22, 7, 7, SILVER, { rot = 40 }),
		rect(84, 84, 8, 8, SILVER, { rot = 15 }),
	}),
}

-- Dodgeball Rush: a barrage of red dodgeballs and one giant golden ball
icons.DodgeballRush = {
	layer(3, { pill(16, 30, 26, 6, WHITE), pill(12, 52, 22, 6, WHITE), pill(18, 76, 26, 6, WHITE) }),
	layer(4, {
		circle(42, 30, 30, RED, { c2 = RED_D, kids = { shine(32, 30, 30, 18, -30) } }),
		circle(38, 76, 26, RED, { c2 = RED_D, kids = { shine(32, 30, 30, 18, -30) } }),
	}),
	layer(4, {
		circle(66, 56, 54, YELLOW, { c2 = GOLD_D, kids = { shine(30, 28, 30, 18, -30) } }),
	}),
	layer(3, twinkle(88, 16, 24, WHITE)),
}

-- Bubble Trouble: a bubble wand blowing one giant rainbow bubble with someone trapped inside
icons.BubbleTrouble = {
	layer(3, {
		circle(13, 26, 13, "#d7f3ff", { kids = { shine(34, 32, 34, 22, -35) } }),
		circle(26, 9, 8, "#e9dcff", { kids = { shine(34, 32, 34, 22, -35) } }),
		circle(92, 86, 9, "#ffe1f1", { kids = { shine(34, 32, 34, 22, -35) } }),
		-- the stream from the wand up to the big one
		circle(31, 63, 9, "#e9dcff", { kids = { shine(34, 32, 34, 22, -35) } }),
		circle(42, 79, 7, "#ffe1f1", { kids = { shine(34, 32, 34, 22, -35) } }),
		circle(12, 51, 6, "#d7f3ff"),
	}),
	layer(4, {
		circle(63, 40, 64, "#c4ecff", {
			c2 = "#e2ccff",
			kids = {
				-- the victim, flailing
				pill(32, 42, 8, 24, RED, -40, { s = 2 }),
				pill(68, 42, 8, 24, RED, 40, { s = 2 }),
				pill(44, 78, 9, 20, BLUE_D, 15, { s = 2 }),
				pill(56, 78, 9, 20, BLUE_D, -15, { s = 2 }),
				pill(50, 60, 20, 30, RED, 0, { s = 2 }),
				circle(50, 34, 22, "#ffd9b0", { s = 2 }),
				-- soap-film sheen
				pill(78, 70, 9, 36, PINK, 40, { t = 0.45 }),
				pill(84, 56, 6, 22, YELLOW, 20, { t = 0.45 }),
				shine(26, 24, 30, 13, -40),
				shine(16, 40, 7, 7),
			},
		}),
	}),
	-- the wand: a beaded ring on a stick, held low in the corner
	layer(3.5, {
		pill(24, 90, 7, 22, PINK, -20, { c2 = "#e83e86" }),
		circle(
			18,
			76,
			19,
			PINK,
			{ kids = { circle(50, 50, 56, "#d7f3ff", { kids = { shine(34, 32, 34, 22, -35) } }) } }
		),
	}),
	layer(3, twinkle(90, 14, 20, WHITE)),
}

-- Out of the Park!: a wooden bat smashing a baseball
icons.OutOfThePark = {
	layer(3, burst(78, 26, 60, 10, ORANGE)),
	layer(4, {
		pill(50, 52, 22, 62, WOOD, 45, { c2 = WOOD_D }),
		pill(25, 76, 10, 36, "#c99050", 45),
		circle(15, 86, 15, "#c99050"),
	}),
	layer(4, {
		circle(78, 26, 34, WHITE, {
			kids = {
				pill(20, 50, 6, 60, RED, 15),
				pill(80, 50, 6, 60, RED, -15),
			},
		}),
	}),
}

FinisherIcons.Icons = icons

function FinisherIcons.has(module: string?): boolean
	return module ~= nil and icons[module] ~= nil
end

-- Draw the finisher's icon centred in `parent` (a square as tall as the parent allows), its first
-- layer at ZIndex `z`. Returns the holder, or nil when the module has no icon.
function FinisherIcons.draw(parent: GuiObject, module: string, z: number, fill: number?): Frame?
	local icon = icons[module]
	if not icon then
		return nil
	end
	local Theme = require(script.Parent.Theme)
	local ink = Theme.Toybox.outline
	local box = Instance.new("Frame")
	box.Name = "FinisherIcon"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromScale(fill or 0.88, fill or 0.88)
	box.BackgroundTransparency = 1
	box.ZIndex = z
	Instance.new("UIAspectRatioConstraint").Parent = box

	-- outlines are in 100ths of the box: rescale them as the box resizes
	local strokes: { { stroke: UIStroke, units: number } } = {}
	local function color(c: string): Color3
		return if c == "ink" then ink else Color3.fromHex(c)
	end
	local function make(shape: Shape, holder: GuiObject, zi: number, outline: number?): GuiObject
		local g: GuiObject
		if shape.k == "t" then
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.FontFace = if shape.font == "label" then Theme.LabelFace else Theme.DisplayFace
			label.TextScaled = true
			label.Text = shape.text or ""
			label.TextColor3 = color(shape.c)
			g = label
		else
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = if shape.c2 then Color3.new(1, 1, 1) else color(shape.c)
			f.BackgroundTransparency = shape.t or 0
			if shape.k == "c" then
				Theme.round(f)
			elseif shape.r and shape.r > 0 then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(shape.r * 0.5, 0)
				corner.Parent = f
			end
			if (shape.c2 or shape.t2) and not outline then
				local grad = Instance.new("UIGradient")
				grad.Rotation = 90
				grad.Color = ColorSequence.new(color(shape.c), color(shape.c2 or shape.c))
				if shape.t2 then
					grad.Transparency = NumberSequence.new(shape.t or 0, shape.t2)
				end
				grad.Parent = f
			elseif shape.c2 then
				f.BackgroundColor3 = color(shape.c)
			end
			g = f
		end
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(shape.x / 100, shape.y / 100)
		g.Size = UDim2.fromScale(shape.w / 100, shape.h / 100)
		g.Rotation = shape.rot or 0
		g.ZIndex = zi
		local units = outline or shape.s
		if units then
			local stroke = Instance.new("UIStroke")
			stroke.Color = ink
			stroke.LineJoinMode = Enum.LineJoinMode.Round
			stroke.Parent = g
			table.insert(strokes, { stroke = stroke, units = units })
		end
		g.Parent = holder
		return g
	end
	local function addKids(shape: Shape, holder: GuiObject, zi: number)
		if shape.kids then
			for _, kid in shape.kids do
				addKids(kid, make(kid, holder, zi, nil), zi + 1)
			end
		end
	end
	for i, l in icon do
		local base = z + (i - 1) * 4
		if l.o then
			for _, shape in ipairs(l) do
				make(shape, box, base, l.o)
			end
		end
		for _, shape in ipairs(l) do
			addKids(shape, make(shape, box, base + 1, nil), base + 2)
		end
	end
	local function rescale()
		local px = box.AbsoluteSize.X / 100
		for _, e in strokes do
			e.stroke.Thickness = math.max(1, e.units * px)
		end
	end
	box:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	box.Parent = parent
	rescale()
	return box
end

return FinisherIcons
