--!strict
-- Gradient titles (Catalog Data.Gradient): the name-tag badge is one RichText TextLabel, so a title
-- gets its gradient as a color per letter. `phase` (0-1) slides the gradient along the title: the
-- server draws phase 0 (ShopService.applyCosmetics), and TitleFxController re-draws animated titles
-- (Data.Animated) with a moving phase on each client, a few times a second.

local TitleStyle = {}

-- The CollectionService tag on a name-tag badge showing an animated title.
TitleStyle.Tag = "AnimatedTitle"

-- Rich-text-safe text.
function TitleStyle.escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- The gradient's color at `t` (0-1, wrapping), looping back to the first color.
local function sample(colors: { Color3 }, t: number): Color3
	local n = #colors
	if n == 1 then
		return colors[1]
	end
	local x = (t % 1) * n
	local i = math.floor(x)
	return colors[i % n + 1]:Lerp(colors[(i + 1) % n + 1], x - i)
end

-- `text` (plain) as RichText, each letter in its gradient color. Spaces aren't wrapped.
function TitleStyle.render(text: string, colors: { Color3 }, phase: number?): string
	if #colors == 0 then
		return TitleStyle.escape(text)
	end
	local letters = {}
	for _, code in utf8.codes(text) do
		table.insert(letters, utf8.char(code))
	end
	local out = {}
	local n = #letters
	for i, ch in letters do
		if ch == " " then
			table.insert(out, ch)
		else
			local c = sample(colors, (i - 1) / math.max(n, 1) + (phase or 0))
			table.insert(out, ('<font color="#%s">%s</font>'):format(c:ToHex(), TitleStyle.escape(ch)))
		end
	end
	return table.concat(out)
end

-- A gradient title inside its frame (rich text, e.g. a colored ✦ for Legendaries; "" for none).
function TitleStyle.framed(text: string, colors: { Color3 }, frame: string, phase: number?): string
	local body = TitleStyle.render(text, colors, phase)
	return if frame ~= "" then ("%s %s %s"):format(frame, body, frame) else body
end

return TitleStyle
