--!strict
-- Studio-only debug overlay (F8): leak counters and the hit-outcome tally used for knockback
-- tuning. Reads ReplicatedStorage.DebugStats, which the server only publishes in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local DebugController = {}

-- Studio UI gallery: pins one pop-up at a time for review/screenshots.
-- From the client command bar: game.Players.LocalPlayer:SetAttribute("RD_Gallery", "<item>")
local function gallery(item: string)
	local Controllers = script.Parent
	local HUD = require(Controllers.HUDController) :: any
	local Shop = require(Controllers.ShopController) :: any
	local Tutorial = require(Controllers.TutorialController) :: any
	local Effects = require(Controllers.EffectsController) :: any
	local Config = require(ReplicatedStorage.Shared.Config) :: any
	local red, blue = Config.Teams.Red.Color, Config.Teams.Blue.Color
	local banners: { [string]: { any } } = {
		Go = { "GO!", Color3.fromRGB(120, 255, 140) },
		KnockedOut = { "KNOCKED OUT!", Color3.fromRGB(255, 90, 80) },
		Elimination = { "ELIMINATION!", Color3.fromRGB(255, 225, 90) },
		LastPlayer = { "LAST PLAYER!", Color3.fromRGB(255, 220, 60) },
		Revenge = { "REVENGE!", Color3.fromRGB(255, 200, 40) },
		Caught = { "YOU CAUGHT IT!", Color3.fromRGB(120, 255, 140) },
		SuddenDeath = { "SUDDEN DEATH!", Color3.fromRGB(255, 80, 60) },
		JailClosed = { "JAIL CLOSED!", Color3.fromRGB(255, 200, 60) },
		RoundWin = { "RED WINS THE ROUND!", red },
		MatchWin = { "BLUE WINS!", blue },
		Draw = { "DRAW! REPLAY!", Color3.new(1, 1, 1) },
		Unlocked = { "UNLOCKED GOLD!", Color3.fromRGB(255, 204, 64) },
		Daily = { "DAY 3: +200 PTS", Color3.fromRGB(255, 215, 80) },
		FinalKnockout = { "FINAL KNOCKOUT!", red },
	}
	HUD.hideResults()
	Shop.openShop(false)
	Shop.openDaily(false)
	Tutorial.debugStep(0)
	local b = banners[item]
	if b then
		HUD.banner(b[1], b[2], 999, "Banner")
		return
	end
	local stats = { hits = 6, catches = 2, knockouts = 3, revenges = 1 }
	local results: { [string]: any } = {
		ResultsFinalKnockout = { won = true, winner = "Red", pts = 600, tier = "Final Knockout", xp = 112, level = 4, leveledUp = true, streak = 3, stats = stats, persistent = true },
		ResultsFlawless = { won = true, winner = "Red", pts = 500, tier = "Flawless Win", xp = 96, level = 4, leveledUp = false, streak = 1, stats = stats, persistent = true },
		ResultsWin = { won = true, winner = "Red", pts = 200, tier = "Win", xp = 80, level = 3, leveledUp = false, streak = 0, casual = true, stats = stats, persistent = true },
		ResultsLoss = { won = false, winner = "Blue", pts = 50, tier = "Good Game", xp = 52, level = 3, leveledUp = false, streak = 0, stats = { hits = 2, catches = 0, knockouts = 1, revenges = 0 }, persistent = true },
		ResultsAborted = { won = false, aborted = true, pts = 0, tier = "Match Aborted", xp = 0, level = 3, leveledUp = false, streak = 0, stats = { hits = 0, catches = 0, knockouts = 0, revenges = 0 }, persistent = false },
	}
	local r = results[item]
	if r then
		HUD.showResults(r, true)
		return
	end
	local tut = string.match(item, "^Tutorial(%d)$")
	if tut then
		Tutorial.debugStep(tonumber(tut))
		return
	end
	if item == "Shop" then
		Shop.openShop(true)
	elseif item == "Daily" or item == "DailyPanel" then
		Shop.openDaily(true)
	elseif item == "Hint" then
		HUD.hint("Throw it!", 999)
	elseif item == "Feed" then
		HUD.feed('<b><font color="#E8463C">Tangedy</font></b> 💥 launched <b><font color="#3C78EB">Bot Zoom</font></b> off the court!')
		HUD.feed('<b><font color="#3C78EB">Bot Pop</font></b> 🧤 caught <b><font color="#E8463C">Bot Bonk</font></b>\'s throw!')
		HUD.feed("ROCKET balls dropped!")
		HUD.feed('<b><font color="#E8463C">Tangedy</font></b> got REVENGE on <b><font color="#3C78EB">Bot Wobble</font></b>!')
	elseif item == "HitPop" then
		-- replay for a few seconds so a screenshot can catch it
		task.spawn(function()
			for _ = 1, 25 do
				local cam = workspace.CurrentCamera
				local pos = cam.CFrame.Position + cam.CFrame.LookVector * 14
				Effects.previewHit(pos, player.Character)
				task.wait(0.2)
			end
		end)
	elseif item == "EliminationFX" then
		task.spawn(function()
			for _ = 1, 12 do
				Effects.previewElimination(player:GetAttribute("Team") ~= "" and player:GetAttribute("Team") or "Red")
				task.wait(0.4)
			end
		end)
	elseif item == "Clear" then
		HUD.hint("", 0.01)
		HUD.banner("", nil, 0.01)
	end
end

local gui: ScreenGui
local text: TextLabel

local ORDER = { "Rigs", "Sockets", "Balls", "BotModels", "Instances", "Hits" }

local function render()
	local folder = ReplicatedStorage:FindFirstChild("DebugStats")
	if not folder then
		text.Text = "no DebugStats yet"
		return
	end
	local attrs = folder:GetAttributes()
	local lines = {}
	for _, k in ORDER do
		table.insert(lines, ("%s: %s"):format(k, tostring(attrs[k] or 0)))
	end
	-- hit outcomes by distance to the void edge when hit
	for _, bucket in { "Center", "Mid", "Edge" } do
		local rec = attrs["Recovered_" .. bucket] or 0
		local void = attrs["Void_" .. bucket] or 0
		local total = rec + void
		local pct = if total > 0 then math.floor(void / total * 100 + 0.5) else 0
		table.insert(lines, ("%s hits: %d recovered / %d void (%d%% void)"):format(bucket, rec, void, pct))
	end
	local keys = {}
	for k in attrs do
		if string.sub(k, 1, 7) == "VoidKO_" or string.sub(k, 1, 5) == "Hits_" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	for _, k in keys do
		table.insert(lines, ("%s: %s"):format(k, tostring(attrs[k])))
	end
	text.Text = table.concat(lines, "\n")
end

function DebugController.init()
	if not RunService:IsStudio() then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Debug"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	text = Instance.new("TextLabel")
	text.Position = UDim2.new(0, 10, 0.3, 0)
	text.Size = UDim2.fromOffset(360, 300)
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.BackgroundTransparency = 0.35
	text.TextColor3 = Color3.fromRGB(180, 255, 180)
	text.Font = Enum.Font.Code
	text.TextSize = 14
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Parent = gui
end

function DebugController.start()
	if not RunService:IsStudio() then
		return
	end
	player:GetAttributeChangedSignal("RD_Gallery"):Connect(function()
		local item = player:GetAttribute("RD_Gallery")
		if type(item) == "string" and item ~= "" then
			local ok: boolean, err: any = pcall(gallery :: any, item)
			if not ok then
				warn("[Gallery] " .. tostring(err))
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F8 then
			gui.Enabled = not gui.Enabled
		end
	end)
	task.spawn(function()
		while true do
			if gui.Enabled then
				render()
			end
			task.wait(0.5)
		end
	end)
end

return DebugController
