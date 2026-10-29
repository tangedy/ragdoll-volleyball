--!strict
-- The info column every wheel sheet shares (the daily spin and the quest chests), right of the wheel:
--
--   status card  a disc (a count or a glyph on a fill) beside a title and a detail line, with an
--                optional progress bar: the free-spin / quest-progress indicator
--   odds card    one row per rarity: sticker, slots on the wheel, a chance bar, the percent and the
--                coins it pays instead if you already own it
--   cost row     coin, price, and a note on the right (spins left, region...)
--   buttons      the primary action and an optional secondary one
--   caption      one muted line under the buttons (your balance)
--
-- Layout and type follow the Toybox tokens (Theme.Space, Theme.TextSize) so both sheets match the
-- rest of the hub. This only draws; the controllers decide what it says.

local Theme = require(script.Parent.Theme)

local T = Theme.Toybox
local new = Theme.new
local SPACE = Theme.Space
local SIZE = Theme.TextSize

local WheelSheet = {}

-- Fixed size of a wheel sheet (scaled to the screen by ShopController.sheet).
WheelSheet.SIZE = Vector2.new(840, 580)
WheelSheet.WHEEL = 380 -- the wheel's diameter (SpinController.wheelFrame)

local RARITIES = { "Legendary", "Epic", "Rare", "Common" }
local STATUS_H = 72
local DISC = 44
local ROW_H = 22
local ROW_GAP = 6
local HEADER_H = 16
local ODDS_H = SPACE.M * 2 + HEADER_H + ROW_GAP + #RARITIES * ROW_H + (#RARITIES - 1) * ROW_GAP
local COST_H = 28
local PRIMARY_H = 56
local SECONDARY_H = 48

-- odds columns (x offsets inside the card's padding): rarity, slots, bar, percent, coins if owned
local COL_SLOTS, COL_SLOTS_W = 104, 56
local COL_BAR = 164
local COL_PCT_W = 44
local COL_DUP_W = 56

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

export type Info = {
	column: Frame,
	statusCard: Frame,
	disc: Frame,
	discText: TextLabel,
	statusTitle: TextLabel,
	statusDetail: TextLabel,
	progress: Frame,
	progressFill: Frame,
	odds: Frame,
	price: TextLabel,
	priceNote: TextLabel,
	primary: TextButton,
	secondary: TextButton?,
	caption: TextLabel,
}

-- Build the column in `body` (a Theme.sheet body), right of the wheel. opts.primary is the main
-- button's starting text; opts.secondary (optional) adds a second, secondary button under it.
-- opts.countHeader and opts.dupHeader rename the odds card's "Slots" and "If owned" columns.
function WheelSheet.info(
	body: Frame,
	opts: { primary: string, secondary: string?, countHeader: string?, dupHeader: string? }
): Info
	local column = new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, -(WheelSheet.WHEEL + 8 + SPACE.XL), 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, body)
	new("UIListLayout", {
		Padding = UDim.new(0, SPACE.M),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, column)

	-- status card -----------------------------------------------------------------------------------
	local statusCard = Theme.well(column, {
		Name = "Status",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, STATUS_H),
		ZIndex = 4,
	}, Theme.Radius.M)
	Theme.padding(statusCard, SPACE.M)
	local disc = new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(DISC, DISC),
		BackgroundColor3 = T.surface,
		ZIndex = 5,
	}, statusCard)
	Theme.round(disc)
	Theme.stroke(disc, T.outline, Theme.StrokeToy)
	local discText = Theme.text(disc, SIZE.Heading, {
		Name = "Count",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.DisplayFace,
		TextColor3 = T.onFill,
		ZIndex = 6,
	})
	local textLeft = DISC + SPACE.M
	local statusTitle = Theme.text(statusCard, SIZE.Label, {
		Name = "Title",
		Position = UDim2.fromOffset(textLeft, 2),
		Size = UDim2.new(1, -textLeft, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	local statusDetail = Theme.text(statusCard, SIZE.Caption, {
		Name = "Detail",
		Position = UDim2.fromOffset(textLeft, 22),
		Size = UDim2.new(1, -textLeft, 0, 16),
		FontFace = Theme.TextFace,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})
	local progress = new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(textLeft, 42),
		Size = UDim2.new(1, -textLeft, 0, 6),
		BackgroundColor3 = T.line,
		Visible = false,
		ZIndex = 5,
	}, statusCard)
	Theme.round(progress)
	local progressFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.leaf,
		ZIndex = 6,
	}, progress)
	Theme.round(progressFill)

	-- odds card -------------------------------------------------------------------------------------
	local oddsCard = Theme.well(column, {
		Name = "Odds",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, ODDS_H),
		ZIndex = 4,
	}, Theme.Radius.M)
	Theme.padding(oddsCard, SPACE.M)
	new("UIListLayout", { Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder }, oddsCard)
	local header = new("Frame", {
		Name = "Header",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, oddsCard)
	Theme.text(header, SIZE.Label, {
		Size = UDim2.new(0, COL_SLOTS, 1, 0),
		Text = "Odds",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local function colCaption(text: string, x: UDim, w: number)
		Theme.text(header, SIZE.Micro, {
			AnchorPoint = Vector2.new(if x.Scale > 0 then 1 else 0, 0),
			Position = UDim2.new(x, UDim.new(0, 0)),
			Size = UDim2.new(0, w, 1, 0),
			FontFace = Theme.TextFace,
			Text = text,
			TextColor3 = T.inkMuted,
			TextXAlignment = if x.Scale > 0 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			ZIndex = 5,
		})
	end
	colCaption(opts.countHeader or "Slots", UDim.new(0, COL_SLOTS), COL_SLOTS_W)
	colCaption("Chance", UDim.new(1, -(COL_DUP_W + SPACE.S)), 80)
	colCaption(opts.dupHeader or "If owned", UDim.new(1, 0), COL_DUP_W)
	local odds = new("Frame", {
		Name = "Rows",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, #RARITIES * ROW_H + (#RARITIES - 1) * ROW_GAP),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, oddsCard)
	new("UIListLayout", { Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder }, odds)

	-- cost row --------------------------------------------------------------------------------------
	local costRow = new("Frame", {
		Name = "Cost",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, COST_H),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, column)
	Theme.coin(costRow, 24, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 5,
	})
	local price = Theme.text(costRow, SIZE.Heading, {
		Name = "Price",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24 + SPACE.S, 0.5, 0),
		Size = UDim2.fromScale(0.5, 1),
		FontFace = Theme.DisplayFace,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	local priceNote = Theme.text(costRow, SIZE.Caption, {
		Name = "Note",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.5, -SPACE.S, 1, 0),
		FontFace = Theme.TextFace,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
	})

	-- buttons and caption ---------------------------------------------------------------------------
	local primary = Theme.button(column, opts.primary, "primary", {
		Name = "Primary",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, PRIMARY_H),
		ZIndex = 4,
	})
	local secondary = if opts.secondary
		then Theme.button(column, opts.secondary, "secondary", {
			Name = "Secondary",
			LayoutOrder = 5,
			Size = UDim2.new(1, 0, 0, SECONDARY_H),
			Visible = false,
			ZIndex = 4,
		})
		else nil
	local caption = Theme.text(column, SIZE.Caption, {
		Name = "Caption",
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = Theme.TextFace,
		TextColor3 = T.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})

	return {
		column = column,
		statusCard = statusCard,
		disc = disc,
		discText = discText,
		statusTitle = statusTitle,
		statusDetail = statusDetail,
		progress = progress,
		progressFill = progressFill,
		odds = odds,
		price = price,
		priceNote = priceNote,
		primary = primary,
		secondary = secondary,
		caption = caption,
	}
end

-- Fill the status card. s.fill colors the disc, which shows s.count (a number, as text) or else
-- s.glyph; s.progress (0..1) shows the bar under the detail line, nil hides it.
function WheelSheet.setStatus(
	info: Info,
	s: {
		fill: Color3,
		count: number?,
		glyph: string?,
		title: string,
		detail: string,
		progress: number?,
	}
)
	info.disc.BackgroundColor3 = s.fill
	info.discText.Text = if s.count then tostring(s.count) else ""
	info.discText.TextColor3 = Theme.textOn(s.fill)
	-- the glyph is rebuilt only when it changes (this runs on every countdown tick)
	local current = info.disc:FindFirstChild("Glyph")
	local want = if s.count then nil else s.glyph
	if (current and current:GetAttribute("Name")) ~= want then
		if current then
			current:Destroy()
		end
		if want then
			local g = Theme.glyph(info.disc, want, Theme.textOn(s.fill), {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.56, 0.56),
				ZIndex = 6,
			})
			g:SetAttribute("Name", want)
		end
	end
	info.statusTitle.Text = s.title
	info.statusDetail.Text = s.detail
	info.progress.Visible = s.progress ~= nil
	info.progressFill.Size = UDim2.fromScale(math.clamp(s.progress or 0, 0, 1), 1)
end

-- "12%", or "2.5%" when it isn't a whole percent.
function WheelSheet.percent(share: number): string
	local pct = math.floor(share * 1000 + 0.5) / 10
	return if pct % 1 == 0 then ("%d%%"):format(pct) else ("%.1f%%"):format(pct)
end

-- Fill the odds rows: counts[rarity] slots out of `total`, and the coins each rarity pays instead
-- when it's already owned. Rarities this wheel can't land on stay listed, muted. opts.countText
-- replaces the "n of total" text per rarity, and opts.precise shows a tenth of a percent.
function WheelSheet.setOdds(
	list: Frame,
	counts: { [string]: number },
	total: number,
	dupCoins: { [string]: number },
	opts: { countText: ((rarity: string) -> string)?, precise: boolean? }?
)
	for _, f in list:GetChildren() do
		if f:IsA("Frame") then
			f:Destroy()
		end
	end
	total = math.max(total, 1)
	for i, r in RARITIES do
		local n = counts[r] or 0
		local share = n / total
		local live = n > 0
		local ink = if live then T.ink else T.inkMuted
		local row = new("Frame", {
			Name = r,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, list)
		local sticker = Theme.sticker(row, r, Theme.Rarity[r], {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			ZIndex = 6,
		})
		if not live then
			sticker.BackgroundTransparency = 0.6
		end
		Theme.text(row, SIZE.Caption, {
			Position = UDim2.fromOffset(COL_SLOTS, 0),
			Size = UDim2.new(0, COL_SLOTS_W, 1, 0),
			FontFace = Theme.TextFace,
			Text = if opts and opts.countText then opts.countText(r) else ("%d of %d"):format(n, total),
			TextColor3 = T.inkMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		})
		local track = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, COL_BAR, 0.5, 0),
			Size = UDim2.new(1, -(COL_BAR + COL_PCT_W + COL_DUP_W + SPACE.S * 2), 0, 8),
			BackgroundColor3 = T.line,
			ZIndex = 6,
		}, row)
		Theme.round(track)
		if live then
			local fill = new("Frame", {
				Size = UDim2.fromScale(math.max(share, 0.04), 1),
				BackgroundColor3 = Theme.Rarity[r],
				ZIndex = 7,
			}, track)
			Theme.round(fill)
			Theme.stroke(fill, T.outline, 1.5)
		end
		Theme.text(row, SIZE.Label, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(COL_DUP_W + SPACE.S), 0, 0),
			Size = UDim2.new(0, COL_PCT_W, 1, 0),
			Text = if not live
				then "–"
				elseif opts and opts.precise then WheelSheet.percent(share)
				else ("%d%%"):format(math.floor(share * 100 + 0.5)),
			TextColor3 = ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 6,
		})
		Theme.text(row, SIZE.Caption, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, COL_DUP_W, 1, 0),
			FontFace = Theme.TextFace,
			Text = "+" .. commas(dupCoins[r] or 0),
			TextColor3 = T.inkMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 6,
		})
	end
end

-- "05:12:33" until the next UTC midnight, when daily free spins and daily quests reset.
function WheelSheet.untilReset(): string
	local left = 86400 - (os.time() % 86400)
	return ("%02d:%02d:%02d"):format(left // 3600, (left // 60) % 60, left % 60)
end

return WheelSheet
