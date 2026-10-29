--!strict
-- Asks winners to favourite the game. Only from a player's 2nd lifetime win (Results.wins), at most
-- once a session, and only once the results card is gone and they're back in the hub, so it never
-- covers a match. Players who already favourited are never asked.

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)

local player = Players.LocalPlayer

local FavoriteController = {}

local MIN_WINS = 2
local HUB_WAIT = 15 -- seconds to wait for the hub after the results card; else try on the next win

local done = false -- asked (or found already favourited) this session
local pending = false -- a win is waiting for the results card to clear

local function inHub(): boolean
	return player:GetAttribute("Status") == "Lobby" and (player:GetAttribute("Team") or "") == ""
end

local function alreadyFavorited(): boolean?
	local ok, fav = pcall(function()
		return AvatarEditorService:GetFavorite(game.PlaceId, Enum.AvatarItemType.Asset)
	end)
	return if ok then fav == true else nil
end

local function tryPrompt()
	pending = true
	task.wait(Config.Match.ResultsOverlay + 1)
	local t0 = os.clock()
	while not inHub() do
		if os.clock() - t0 > HUB_WAIT then
			pending = false
			return
		end
		task.wait(0.5)
	end
	pending = false
	if done then
		return
	end
	local fav = alreadyFavorited()
	if fav == nil then
		return -- couldn't tell (e.g. Studio / unpublished place): try again on the next win
	end
	done = true
	if fav then
		return
	end
	pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
end

function FavoriteController.start()
	Net.on("Results", function(data: any)
		if done or pending or game.PlaceId == 0 then
			return
		end
		if data.won and not data.aborted and (tonumber(data.wins) or 0) >= MIN_WINS then
			tryPrompt()
		end
	end)
end

return FavoriteController
