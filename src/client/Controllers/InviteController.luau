--!strict
-- Asks players to invite friends once a session, after their Nth finished game this session
-- (Config.Social.InviteAfterGames; Results.sessionGames), once the results card is gone and they're
-- back in the hub, so it never covers a match. If the favourite prompt (FavoriteController) is
-- waiting on the same results, this one waits for the next game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local FavoriteController = require(script.Parent.FavoriteController)

local player = Players.LocalPlayer

local InviteController = {}

local HUB_WAIT = 15 -- seconds to wait for the hub after the results card; else try after the next game

local done = false -- asked this session (or found invites aren't allowed)
local pending = false

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function tryPrompt()
	pending = true
	task.wait(Config.Match.ResultsOverlay + 1.5)
	local t0 = os.clock()
	while not inHub() do
		if os.clock() - t0 > HUB_WAIT then
			pending = false
			return
		end
		task.wait(0.5)
	end
	pending = false
	if done or FavoriteController.isPrompting() then
		return
	end
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not ok then
		return -- couldn't tell (e.g. Studio): try again after the next game
	end
	done = true
	if not can then
		return
	end
	pcall(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = Config.Social.InviteMessage
		SocialService:PromptGameInvite(player, options)
	end)
end

function InviteController.start()
	if not Config.Social.InviteEnabled then
		return
	end
	Net.on("Results", function(data: any)
		if done or pending or game.PlaceId == 0 or data.aborted then
			return
		end
		if (tonumber(data.sessionGames) or 0) >= Config.Social.InviteAfterGames then
			task.spawn(tryPrompt)
		end
	end)
end

return InviteController
