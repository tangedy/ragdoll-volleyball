-- Renders every finisher icon (src/client/UI/FinisherIcons.luau) to an HTML page of SVGs, so the
-- art can be checked without Studio. Run from the repo root:
--   lune run tools/preview_finisher_icons [out.html]
-- The SVG follows the Roblox renderer: outlines are drawn under the fills (a stroke twice as wide,
-- half of it covered), rounded corners are a fraction of the short side, gradients run top to
-- bottom in the shape's own (rotated) frame.

local fs = require("@lune/fs")
local process = require("@lune/process")

local FinisherIcons = require("../src/client/UI/FinisherIcons")

local INK = "#4a3423"
local TIERS = {
	{ "Common", "#8ed2ef" },
	{ "Rare", "#7cc47f" },
	{ "Epic", "#ff9cc0" },
	{ "Legendary", "#f7cd46" },
}
-- which shop tier each icon sits on
local TIER_OF = {
	Default = "#ece3cc",
	ConfettiPop = "#8ed2ef",
	AirHorn = "#8ed2ef",
	SadTrombone = "#8ed2ef",
	Bonk = "#8ed2ef",
	SlowMoReplay = "#7cc47f",
	Paparazzi = "#7cc47f",
	Spotlight = "#7cc47f",
	Meteor = "#ff9cc0",
	Pumpkin = "#ff9cc0",
	PurpleFlash = "#ff9cc0",
	BlackHole = "#ff9cc0",
	DodgeballRush = "#ff9cc0",
	BubbleTrouble = "#ff9cc0",
	DestinyArrives = "#f7cd46",
	OutOfThePark = "#f7cd46",
}

local gradId = 0
local defs = {}

local function color(c: string): string
	return if c == "ink" then INK else c
end

local function fmt(n: number): string
	return string.format("%.2f", n)
end

local function shapeSvg(s: any, W: number, H: number, px: number, outline: number?): string
	local cx, cy = s.x / 100 * W, s.y / 100 * H
	local sw, sh = s.w / 100 * W, s.h / 100 * H
	local out = { `<g transform="translate({fmt(cx)} {fmt(cy)}) rotate({fmt(s.rot or 0)})">` }
	local units = outline or s.s
	local stroke = if units
		then ` stroke="{INK}" stroke-width="{fmt(units * px * 2)}" stroke-linejoin="round" paint-order="stroke"`
		else ""
	local fill = color(s.c)
	local opacity = 1 - (s.t or 0)
	if (s.c2 or s.t2) and not outline then
		gradId += 1
		local id = "g" .. gradId
		table.insert(
			defs,
			`<linearGradient id="{id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{color(s.c)}" stop-opacity="{fmt(
				1 - (s.t or 0)
			)}"/><stop offset="1" stop-color="{color(s.c2 or s.c)}" stop-opacity="{fmt(1 - (s.t2 or s.t or 0))}"/></linearGradient>`
		)
		fill = `url(#{id})`
		opacity = 1
	end
	if s.k == "t" then
		local len = math.max(1, utf8.len(s.text or "") or 1)
		local size = math.min(sh * 0.9, sw / len * 1.5)
		local family = if s.font == "label" then "Nunito" else "Fredoka One"
		table.insert(
			out,
			`<text x="0" y="0" font-family="{family}" font-weight="900" font-size="{fmt(size)}" text-anchor="middle" dominant-baseline="central" fill="{fill}"{stroke}>{s.text}</text>`
		)
	else
		local rx = if s.k == "c" then math.min(sw, sh) / 2 else (s.r or 0) * math.min(sw, sh) / 2
		table.insert(
			out,
			`<rect x="{fmt(-sw / 2)}" y="{fmt(-sh / 2)}" width="{fmt(sw)}" height="{fmt(sh)}" rx="{fmt(rx)}" fill="{fill}" fill-opacity="{fmt(
				opacity
			)}"{stroke}/>`
		)
	end
	if not outline and s.kids then
		table.insert(out, `<g transform="translate({fmt(-sw / 2)} {fmt(-sh / 2)})">`)
		for _, kid in s.kids do
			table.insert(out, shapeSvg(kid, sw, sh, px, nil))
		end
		table.insert(out, "</g>")
	end
	table.insert(out, "</g>")
	return table.concat(out)
end

local function iconSvg(icon: any, size: number, bg: string?, bandW: number?): string
	table.clear(defs)
	local body = {}
	local w = bandW or size
	local ox = (w - size) / 2
	for _, l in icon do
		if l.o then
			for _, s in ipairs(l) do
				table.insert(body, shapeSvg(s, size, size, size / 100, l.o))
			end
		end
		for _, s in ipairs(l) do
			table.insert(body, shapeSvg(s, size, size, size / 100, nil))
		end
	end
	local back = if bg then `<rect width="{w}" height="{size / 0.92}" rx="12" fill="{bg}"/>` else ""
	local inset = size * (1 / 0.92 - 1) / 2
	return `<svg width="{w}" height="{fmt(size / 0.92)}" xmlns="http://www.w3.org/2000/svg"><defs>{table.concat(defs)}</defs>{back}<g transform="translate({fmt(
		ox
	)} {fmt(inset)})">{table.concat(body)}</g></svg>`
end

local names = {}
for name in FinisherIcons.Icons do
	table.insert(names, name)
end
table.sort(names)

local rows = {}
for _, name in names do
	local icon = FinisherIcons.Icons[name]
	local cells = { `<div class="name">{name}</div>` }
	table.insert(cells, iconSvg(icon, 132, TIER_OF[name] or "#ece3cc"))
	local small = {}
	for _, t in TIERS do
		table.insert(small, iconSvg(icon, 30, t[2]))
	end
	table.insert(cells, `<div class="tiers">{table.concat(small)}</div>`)
	table.insert(rows, `<div class="row">{table.concat(cells)}</div>`)
end

local html = '<!doctype html><html><head><meta charset="utf-8"><title>Finisher Icons</title>'
	.. '<link href="https://fonts.googleapis.com/css2?family=Fredoka+One&family=Nunito:wght@900&display=swap" rel="stylesheet">'
	.. "<style>body{background:#fffcf2;font-family:Nunito,sans-serif;color:#4a3423;margin:16px}"
	.. ".grid{display:flex;flex-wrap:wrap;gap:12px}.row{display:flex;flex-direction:column;align-items:center;gap:4px}"
	.. ".tiers{display:flex;gap:2px}.name{font-weight:900;font-size:12px}</style></head><body><div class=grid>"
	.. table.concat(rows)
	.. "</div>"
	.. "</body></html>"

local outPath = process.args[1] or "finisher_icons_preview.html"
fs.writeFile(outPath, html)
print(`wrote {outPath} ({#names} icons)`)
