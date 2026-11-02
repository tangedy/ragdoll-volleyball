--!strict
-- Game passes (Config.CoinShop.Passes). Roblox keeps pass ownership, not the profile: each pass with
-- a real PassId is checked on join (UserOwnsGamePassAsync) and marked the moment it's bought here
-- (PromptGamePassPurchaseFinished). What a player owns this session is c.passes[id] and the player
-- attribute "Pass_<id>" (the client hides that pass's Buy). The perks:
--   DoubleCoins: lifetime 2x coins, the same as the BoostForever product (BoostService.multiplier).
--   VIP: a gold VIP tag on the name tag (ShopService.applyCosmetics) and a daily gift the first time
--        a VIP is here each UTC day: a free bonus spin and some coins (dailyGift).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local GamePassService = {}

local S: any
local PASSES = Config.CoinShop.Passes

function GamePassService.init(services: any)
	S = services
end

function GamePassService.owns(c: any, id: string): boolean
	return c.passes ~= nil and c.passes[id] == true
end

local function today(): string
	return os.date("!%Y-%m-%d", os.time()) :: string
end

-- VIP's daily gift, once per UTC day (profile.VipGiftDate). Returns whether it paid.
function GamePassService.dailyGift(c: any): boolean
	local p = c.profile
	if not p or not GamePassService.owns(c, "VIP") then
		return false
	end
	local d = today()
	if p.VipGiftDate == d then
		return false
	end
	local vip = PASSES.VIP
	p.VipGiftDate = d
	p.Coins += vip.DailyCoins
	table.insert(S.SpinService.bonusSpins(c), vip.DailyWheel)
	if c.player then
		S.NetService.send(c.player, "VipGift", { coins = vip.DailyCoins, wheel = vip.DailyWheel })
	end
	return true
end

-- Mark a pass owned for this session, then apply what it gives right away.
function GamePassService.setOwned(c: any, id: string)
	if GamePassService.owns(c, id) then
		return
	end
	c.passes = c.passes or {}
	c.passes[id] = true
	if c.player then
		c.player:SetAttribute("Pass_" .. id, true)
	end
	if c.profileLoaded and c.profile then
		GamePassService.dailyGift(c)
		S.ShopService.applyCosmetics(c)
		S.DataService.push(c)
	end
end

-- Ask Roblox which passes this player owns (on join, after the profile loads). A failed lookup just
-- leaves the pass off this session; buying it again isn't possible, so the next join picks it up.
function GamePassService.refresh(c: any)
	local player = c.player
	if not player then
		return
	end
	for id, pass in PASSES do
		if pass.PassId > 0 then
			local ok, has =
				pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
			if ok and has then
				GamePassService.setOwned(c, id)
			elseif not ok then
				warn(("[Pass] ownership check for %s failed: %s"):format(id, tostring(has)))
			end
		end
	end
end

function GamePassService.start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local c = S.PlayerStateService.get(player)
			for id, pass in PASSES do
				if pass.PassId > 0 and pass.PassId == passId and c then
					GamePassService.setOwned(c, id)
				end
			end
		end
	)
	-- a VIP who stays past UTC midnight gets the next day's gift without rejoining
	task.spawn(function()
		while true do
			task.wait(60)
			for _, c in S.PlayerStateService.realPlayers() do
				if c.profileLoaded and GamePassService.dailyGift(c) then
					S.DataService.push(c)
				end
			end
		end
	end)
end

return GamePassService
