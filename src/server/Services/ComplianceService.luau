--!strict
-- Per-player Roblox policy checks (PolicyService). Chest opens and paid spins hand out random
-- cosmetics for coins, and coins can be bought with Robux, so Roblox counts them as paid random
-- items: they must be refused wherever `ArePaidRandomItemsRestricted` is true. The free daily spin
-- isn't paid, so it stays open to everyone.
--
-- Until a player's policy has loaded (or if every lookup fails), they're treated as restricted.
-- In Studio, `workspace:SetAttribute("RD_PaidRandomRestricted", true)` simulates a restricted region.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")

local ComplianceService = {}

local S: any
local RETRIES = 3

function ComplianceService.init(services: any)
	S = services
end

-- Look up the player's policy (yields). Pushes the profile afterwards so the client's chest and spin
-- buttons pick up the answer.
function ComplianceService.load(c: any)
	local player = c.player :: Player?
	if not player then
		return
	end
	for attempt = 1, RETRIES do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			c.paidRandomRestricted = info.ArePaidRandomItemsRestricted == true
			break
		end
		if player.Parent ~= Players then
			return
		end
		task.wait(attempt * 2)
	end
	if c.profileLoaded then
		S.DataService.push(c)
	end
end

-- True when this player can't be sold random items. Bots are never restricted.
function ComplianceService.paidRandomRestricted(c: any): boolean
	if not c.player then
		return false
	end
	if RunService:IsStudio() and workspace:GetAttribute("RD_PaidRandomRestricted") ~= nil then
		return workspace:GetAttribute("RD_PaidRandomRestricted") == true
	end
	return c.paidRandomRestricted ~= false
end

return ComplianceService
