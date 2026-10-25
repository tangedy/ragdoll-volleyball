--!strict
-- Pts shop, cosmetic equip and daily login rewards. Everything is decided here; the client only
-- sends requests. Buying and equipping are hub-only (never during a match), and pts are never
-- spent without the server confirming ownership, price and balance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

-- Daily ladder state for the HUD: which day is next, how much it pays, whether today is claimed.
function ShopService.dailyStatus(c: any): { day: number, amount: number, claimed: boolean }
	local ladder = Config.DailyRewards.Ladder
	local ls = c.profile and c.profile.LoginStreak or { day = 0, claimedDate = "" }
	local today = dateOf(os.time())
	if ls.claimedDate == today then
		local nextDay = ls.day % #ladder + 1
		return { day = ls.day, amount = ladder[nextDay], claimed = true }
	end
	local yesterday = dateOf(os.time() - 86400)
	local nextDay = if ls.claimedDate == yesterday then ls.day % #ladder + 1 else 1
	return { day = nextDay, amount = ladder[nextDay], claimed = false }
end

function ShopService.claimDaily(c: any): boolean
	if not c.profileLoaded or not c.profile then
		return false
	end
	local status = ShopService.dailyStatus(c)
	if status.claimed then
		return false -- one claim per UTC day; repeated requests never pay twice
	end
	local ls = c.profile.LoginStreak
	local today = dateOf(os.time())
	ls.day = status.day
	ls.claimedDate = today
	ls.lastDate = today
	c.profile.Pts += status.amount
	if c.player then
		S.NetService.send(c.player, "Banner", {
			text = ("DAY %d: +%d PTS"):format(status.day, status.amount),
			color = Color3.fromRGB(255, 215, 80),
			duration = 1.6,
		})
	end
	S.AnalyticsService.event(c, "DailyClaim", status.day)
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return true
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
	if c.profile.Pts < item.Price then
		return false, ("Need %d more pts"):format(item.Price - c.profile.Pts)
	end
	c.profile.Pts -= item.Price
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

-- Name-tag badge: level, win-streak flame and title.
function ShopService.applyCosmetics(c: any)
	if not c.profile then
		return
	end
	local p = c.profile
	local badge = ("Lv %d"):format(p.Level)
	if p.CurrentWinStreak >= Config.Progression.StreakFlameAt then
		badge ..= (" 🔥%d"):format(p.CurrentWinStreak)
	end
	local title = Catalog.equipped(p.Equipped, "Title").Data.Text
	if title and title ~= "" then
		badge ..= " · " .. title
	end
	S.CharacterService.setBadge(c, badge)
end

-- Cosmetic look for a Standard ball owned by this combatant, or nil for the default look.
function ShopService.ballLook(c: any): { color: Color3?, material: Enum.Material?, trail: { Color3 }? }?
	if not c or not c.profile then
		return nil
	end
	local skin = Catalog.equipped(c.profile.Equipped, "BallSkin")
	local trail = Catalog.equipped(c.profile.Equipped, "Trail")
	if skin.Default and trail.Default then
		return nil
	end
	return { color = skin.Data.Color, material = skin.Data.Material, trail = trail.Data.Colors }
end

function ShopService.finisherModule(c: any): string
	local item = if c and c.profile then Catalog.equipped(c.profile.Equipped, "Finisher") else Catalog.default("Finisher")
	return item.Data.Module or Config.Finisher.DefaultId
end

function ShopService.start()
	local A = NetSchema.Actions
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
			ShopService.claimDaily(c)
		end
	end)
end

return ShopService
