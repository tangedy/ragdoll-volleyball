--!strict
-- Coins shop, cosmetic equip and the daily login ladder (its rewards land through
-- RewardService.grant). Everything is decided here; the client only sends requests. Buying and
-- equipping are hub-only (never during a match), and coins are never spent without the server
-- confirming ownership, price and balance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallDefinitions = require(Shared.BallDefinitions)
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local NetSchema = require(Shared.NetSchema)

local ShopService = {}

local S: any

function ShopService.init(services: any)
	S = services
end

local function dateOf(t: number): string
	return os.date("!%Y-%m-%d", t) :: string
end

function ShopService.owns(c: any, id: string): boolean
	local item = Catalog.get(id)
	if not item or not c.profile then
		return false
	end
	return item.Default == true or c.profile.OwnedCosmetics[id] == true
end

-- Daily ladder state for the HUD: which day is next (or was claimed today), its typed reward
-- (Config.DailyRewards), whether today is claimed, and the cosmetic pick still waiting, if any.
function ShopService.dailyStatus(c: any): { day: number, reward: any, claimed: boolean, pick: any? }
	local ladder = Config.DailyRewards.Ladder
	local ls = c.profile and c.profile.LoginStreak or { day = 0, claimedDate = "" }
	local today = dateOf(os.time())
	local pending = S.RewardService.pendingPick(c)
	local pick = if pending then { ids = pending.ids, rarity = pending.rarity, coins = pending.coins } else nil
	if ls.claimedDate == today and ls.day >= 1 then
		return { day = ls.day, reward = ladder[ls.day], claimed = true, pick = pick }
	end
	local yesterday = dateOf(os.time() - 86400)
	local nextDay = if ls.claimedDate == yesterday then ls.day % #ladder + 1 else 1
	return { day = nextDay, reward = ladder[nextDay], claimed = false, pick = pick }
end

-- Claim today's rung. Returns the granted result (RewardService.grant) with `day`, or nil and a reason.
function ShopService.claimDaily(c: any): ({ [string]: any }?, string?)
	if not c.profileLoaded or not c.profile then
		return nil, "Not ready yet"
	end
	local status = ShopService.dailyStatus(c)
	if status.claimed then
		return nil, "Already claimed today" -- one claim per UTC day; repeated requests never pay twice
	end
	local result, why = S.RewardService.grant(c, status.reward, "Daily" .. status.day)
	if not result then
		return nil, why
	end
	local ls = c.profile.LoginStreak
	local today = dateOf(os.time())
	ls.day = status.day
	ls.claimedDate = today
	ls.lastDate = today
	result.ok = true
	result.day = status.day
	S.AnalyticsService.event(c, "DailyClaim", status.day)
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return result, nil
end

local function inHub(c: any): boolean
	return not c.inMatch and c.status == "Lobby"
end

function ShopService.buy(c: any, id: string): (boolean, string?)
	local item = Catalog.get(id)
	if not item or not c.profileLoaded then
		return false, "Not available"
	end
	if not inHub(c) then
		return false, "Shop is open in the hub"
	end
	if ShopService.owns(c, id) then
		return false, "Already owned"
	end
	if item.Price <= 0 then
		return false, "Not for sale"
	end
	if item.Bundle then
		return false, "Only in a bundle"
	end
	if item.Unlock then
		return false, "Earn it with power-ball knockouts"
	end
	if not Catalog.isOffered(item) then
		return false, ("Only during %s"):format(item.Event or "its event")
	end
	if c.profile.Coins < item.Price then
		return false, ("Need %d more coins"):format(item.Price - c.profile.Coins)
	end
	c.profile.Coins -= item.Price
	c.profile.OwnedCosmetics[id] = true
	c.profile.Equipped[item.Category] = id -- equip on purchase
	S.AnalyticsService.event(c, "ShopBuy_" .. id, item.Price)
	ShopService.applyCosmetics(c)
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return true, nil
end

function ShopService.equip(c: any, id: string): (boolean, string?)
	local item = Catalog.get(id)
	if not item or not ShopService.owns(c, id) then
		return false, "Not owned"
	end
	if not inHub(c) then
		return false, "Change cosmetics in the hub"
	end
	c.profile.Equipped[item.Category] = id
	ShopService.applyCosmetics(c)
	S.DataService.push(c)
	return true, nil
end

-- Power Ball Mastery ------------------------------------------------------------------------------

-- Today's featured power ball (Config.PowerUps.Featured), or nil when the feature is off. Rotates
-- through BallDefinitions.PowerTypes one UTC day at a time.
function ShopService.featuredBall(): string?
	if not Config.PowerUps.Featured.Enabled then
		return nil
	end
	local types = BallDefinitions.PowerTypes
	return types[(os.time() // 86400) % #types + 1]
end

-- Grant every Unlock cosmetic whose mastery goal is met and isn't owned yet. Returns the new ids.
function ShopService.checkUnlocks(c: any): { string }
	local granted = {}
	if not c.profile then
		return granted
	end
	for _, item in Catalog.Items do
		if item.Unlock and not ShopService.owns(c, item.Id) then
			local have, need = Catalog.unlockProgress(item, c.profile.PowerKOs)
			if have >= need then
				c.profile.OwnedCosmetics[item.Id] = true
				table.insert(granted, item.Id)
				S.AnalyticsService.event(c, "MasteryUnlock_" .. item.Id)
				if c.player then
					S.NetService.send(c.player, "Banner", {
						text = "🔓 UNLOCKED: " .. item.Name,
						color = Config.Spin.RarityColors[Catalog.rarity(item)],
						duration = 2.2,
						sound = "JailEscape",
					})
				end
			end
		end
	end
	return granted
end

-- Count a credited knockout made with `ballType` toward Power Ball Mastery (Standard balls don't
-- count; the featured ball counts MasteryBonus times). Real, loaded players only; grants any
-- unlock it completes. The caller pushes the profile; a new unlock also saves.
function ShopService.recordPowerKO(c: any, ballType: string?): { string }
	if not c.player or not c.profileLoaded or not c.profile or not BallDefinitions.Defs[ballType or ""] then
		return {}
	end
	if ballType == "Standard" then
		return {}
	end
	local kos = c.profile.PowerKOs
	local amount = if ballType == ShopService.featuredBall() then Config.PowerUps.Featured.MasteryBonus else 1
	kos[ballType] = (tonumber(kos[ballType]) or 0) + amount
	local granted = ShopService.checkUnlocks(c)
	if #granted > 0 then
		task.spawn(S.DataService.save, c, false)
	end
	return granted
end

-- Name-tag badge (RichText): level, win-streak flame and title, the title in its rarity's color
-- (Legendary ones framed in ✦). The Ghost title (Data.Style "Ghost") is its own special tag: pale,
-- see-through and framed in ghosts.
function ShopService.applyCosmetics(c: any)
	if not c.profile then
		return
	end
	local p = c.profile
	local badge = ("Lv %d"):format(p.Level)
	if p.CurrentWinStreak >= Config.Progression.StreakFlameAt then
		badge ..= (" 🔥%d"):format(p.CurrentWinStreak)
	end
	local item = Catalog.equipped(p.Equipped, "Title")
	local title = item.Data.Text
	if title and title ~= "" then
		local rarity = Catalog.rarity(item)
		title = string.gsub(string.gsub(string.gsub(title, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		if item.Data.Style == "Ghost" then
			badge ..= (' · %s <font color="#D6FFF4" transparency="0.3"><i>%s</i></font> %s'):format(
				item.Data.Icon,
				title,
				item.Data.Icon
			)
		else
			if rarity == "Legendary" then
				title = "✦ " .. title .. " ✦"
			end
			badge ..= (' · <font color="#%s">%s</font>'):format(Config.Spin.RarityColors[rarity]:ToHex(), title)
		end
	end
	S.CharacterService.setBadge(c, badge)
end

-- Cosmetic look for a Standard ball owned by this combatant, or nil for the default look.
-- `pumpkin`: the Jack-o'-Lantern skin, drawn as a carved pumpkin all year (HalloweenController).
function ShopService.ballLook(
	c: any
): { color: Color3?, material: Enum.Material?, trail: { Color3 }?, pumpkin: boolean? }?
	if not c or not c.profile then
		return nil
	end
	local skin = Catalog.equipped(c.profile.Equipped, "BallSkin")
	local trail = Catalog.equipped(c.profile.Equipped, "Trail")
	if skin.Default and trail.Default then
		return nil
	end
	return {
		color = skin.Data.Color,
		material = skin.Data.Material,
		trail = trail.Data.Colors,
		pumpkin = if skin.Data.Pumpkin then true else nil,
	}
end

-- The intro pose a combatant strikes in the match-start camera pan. Bots show off a random one.
function ShopService.introPose(c: any): string
	if c and c.isBot then
		local poses = Catalog.inCategory("Pose")
		c.botPose = c.botPose or poses[math.random(1, #poses)].Data.Pose
		return c.botPose
	end
	local item = if c and c.profile then Catalog.equipped(c.profile.Equipped, "Pose") else Catalog.default("Pose")
	return item.Data.Pose or "Cheer"
end

-- Bot finishers ------------------------------------------------------------------------------------

local TIERS = { "Common", "Rare", "Epic", "Legendary" }
local rng = Random.new()

-- Standard normal (Box-Muller).
local function normal(): number
	local u = math.max(rng:NextNumber(), 1e-12)
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * rng:NextNumber())
end

-- Gamma(shape, scale) by Marsaglia-Tsang (shape < 1 boosted through shape + 1).
local function gamma(shape: number, scale: number): number
	if shape < 1 then
		return gamma(shape + 1, scale) * rng:NextNumber() ^ (1 / shape)
	end
	local d = shape - 1 / 3
	local c = 1 / math.sqrt(9 * d)
	while true do
		local x, v
		repeat
			x = normal()
			v = 1 + c * x
		until v > 0
		v = v * v * v
		local u = rng:NextNumber()
		if u < 1 - 0.0331 * x ^ 4 or math.log(u) < 0.5 * x * x + d * (1 - v + math.log(v)) then
			return d * v * scale
		end
	end
end

-- A tier index (1 Common .. 4 Legendary) drawn from Config.Bots.FinisherGamma.
function ShopService.botFinisherTier(): number
	local g = Config.Bots.FinisherGamma
	return math.min(math.floor(gamma(g.Shape, g.Scale)), #TIERS - 1) + 1
end

-- A finisher for a bot: a gamma-drawn tier, then a random finisher of it (stepping down a tier if
-- the catalog has none there).
function ShopService.pickBotFinisher(): Catalog.Item
	local byTier: { [string]: { Catalog.Item } } = {}
	for _, item in Catalog.inCategory("Finisher") do
		if item.Event then
			continue -- bots don't show off event limiteds
		end
		local tier = Catalog.rarity(item)
		byTier[tier] = byTier[tier] or {}
		table.insert(byTier[tier], item)
	end
	for i = ShopService.botFinisherTier(), 1, -1 do
		local pool = byTier[TIERS[i]]
		if pool and #pool > 0 then
			return pool[rng:NextInteger(1, #pool)]
		end
	end
	return Catalog.default("Finisher")
end

function ShopService.finisherModule(c: any): string
	if c and c.isBot then
		c.botFinisher = c.botFinisher or ShopService.pickBotFinisher()
		return c.botFinisher.Data.Module or Config.Finisher.DefaultId
	end
	local item = if c and c.profile
		then Catalog.equipped(c.profile.Equipped, "Finisher")
		else Catalog.default("Finisher")
	return item.Data.Module or Config.Finisher.DefaultId
end

function ShopService.start()
	local A = NetSchema.Actions
	-- the player opened a shop tab: everything on sale there is no longer NEW! (saved with the profile)
	S.NetService.on(A.MarkSeen, function(player, p)
		local c = S.PlayerStateService.get(player)
		if not c or not c.profile or not c.profileLoaded then
			return
		end
		local seen = c.profile.ShopSeen
		if type(seen) ~= "table" then
			seen = {}
			c.profile.ShopSeen = seen
		end
		local events = Catalog.activeEvents()
		for _, item in Catalog.inCategory(p.category) do
			if Catalog.isOffered(item, events) then
				seen[item.Id] = true
			end
		end
	end)
	S.NetService.on(A.BuyItem, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c then
			local ok, why = ShopService.buy(c, p.id)
			S.NetService.send(player, "ShopResult", { id = p.id, ok = ok, message = why })
		end
	end)
	S.NetService.on(A.EquipItem, function(player, p)
		local c = S.PlayerStateService.get(player)
		if c then
			local ok, why = ShopService.equip(c, p.id)
			S.NetService.send(player, "ShopResult", { id = p.id, ok = ok, message = why, equip = true })
		end
	end)
	S.NetService.on(A.ClaimDaily, function(player, _p)
		local c = S.PlayerStateService.get(player)
		if c then
			local result, why = ShopService.claimDaily(c)
			S.NetService.send(player, "DailyResult", result or { ok = false, message = why })
		end
	end)
end

return ShopService
