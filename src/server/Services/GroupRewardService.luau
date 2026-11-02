--!strict
-- Group reward: the hub's chest kiosk (LobbyBuilder) pays Config.GroupReward.Reward once per account
-- to a member of the game's Roblox group. Roblox can't verify a like, so joining the group is what's
-- rewarded. Every press asks Roblox again; the flag (GroupRewardClaimed) is set before the grant, so
-- it can never pay twice. While GroupId is 0 the kiosk isn't built and claims are
-- refused. The answer goes to the client as a "GroupReward" message ({ ok, reason?, reward? }).

local GroupService = game:GetService("GroupService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local GroupRewardService = {}

local S: any
local G = Config.GroupReward

GroupRewardService.PROMPT = "GroupRewardPrompt"

function GroupRewardService.init(services: any)
	S = services
end

-- Is `player` in group `groupId`? true/false, or nil when Roblox couldn't be asked. Group checks can
-- be cached per server, so a "no" is checked again against the live group list: a player who joins
-- the group mid-session can claim without rejoining. Tests replace this.
function GroupRewardService.isMember(player: Player, groupId: number): boolean?
	local ok, member = pcall(player.IsInGroupAsync, player, groupId)
	if ok and member then
		return true
	end
	local listed, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if listed and type(groups) == "table" then
		for _, g in groups do
			if g.Id == groupId then
				return true
			end
		end
		return false
	end
	return if ok then false else nil
end

-- Claim the reward for combatant `c`. Returns what the client is told:
--   { ok = true, reward = RewardService.grant's result }
--   { ok = false, reason = "Off" | "NotReady" | "Tutorial" | "Claimed" | "Busy" | "NotMember" | "Error" }
function GroupRewardService.claim(c: any): { [string]: any }
	local player = c.player
	local p = c.profile
	if G.GroupId == 0 then
		return { ok = false, reason = "Off" }
	elseif not player or not c.profileLoaded or not p then
		return { ok = false, reason = "NotReady" }
	elseif player:GetAttribute("TutorialDone") ~= true then
		return { ok = false, reason = "Tutorial" }
	elseif p.GroupRewardClaimed then
		return { ok = false, reason = "Claimed" }
	end
	local now = os.clock()
	if c.groupChecking or (c.groupCheckedAt and now - c.groupCheckedAt < G.Cooldown) then
		return { ok = false, reason = "Busy" }
	end
	c.groupChecking = true
	c.groupCheckedAt = now
	local member = GroupRewardService.isMember(player, G.GroupId) -- yields
	c.groupChecking = nil
	if member == nil then
		return { ok = false, reason = "Error" }
	elseif not member then
		return { ok = false, reason = "NotMember" }
	elseif p.GroupRewardClaimed or c.profile ~= p then
		return { ok = false, reason = "Claimed" } -- settled while Roblox was asked
	end
	p.GroupRewardClaimed = true
	local result, why = S.RewardService.grant(c, G.Reward, "Group")
	if not result then
		p.GroupRewardClaimed = false
		warn("[GroupReward] grant failed: " .. tostring(why))
		return { ok = false, reason = "Error" }
	end
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	return { ok = true, reward = result }
end

function GroupRewardService.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= GroupRewardService.PROMPT then
			return
		end
		local c = S.PlayerStateService.get(player)
		if not c then
			return
		end
		local answer = GroupRewardService.claim(c)
		if answer.reason ~= "Busy" then
			S.NetService.send(player, "GroupReward", answer)
		end
	end)
end

return GroupRewardService
