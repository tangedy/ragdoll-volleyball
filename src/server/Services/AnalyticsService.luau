--!strict
-- Thin wrapper over Roblox AnalyticsService (spec §14, Amendment A analytics additions).
--
-- Three funnels for the Creator Dashboard (Analytics > Funnels):
-- 1. Onboarding (LogOnboardingFunnelStepEvent): a player's first session only (c.firstSession, set
--    by DataService.load), from joining through the tutorial and their first two games to the
--    "Play 12 minutes" quest.
-- 2. "CoinPurchases": a player's 1st to 8th coin purchase (shop items and coin spins) over their
--    whole life, for accounts created since it shipped (profile.FirstJoinAt > 1).
-- 3. "PlayAfterLoss": every lost game opens a new run of it (its own funnel session id); step 2 is
--    starting another match in the same session.
-- Onboarding steps are logged strictly in order: a step that comes early (12 minutes played before
-- the 2nd game ends) waits until the one before it is logged, and no step is logged twice.

local Analytics = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnalyticsService = {}

local ONBOARDING = {
	{ key = "Joined", name = "Joined" },
	{ key = "Objective1", name = "Tutorial 1/6 · Grab a ball" },
	{ key = "Objective2", name = "Tutorial 2/6 · Hit the dummy" },
	{ key = "Objective3", name = "Tutorial 3/6 · Knock it off" },
	{ key = "Objective4", name = "Tutorial 4/6 · Heavy ball" },
	{ key = "Objective5", name = "Tutorial 5/6 · Special balls" },
	{ key = "FinishedTutorial", name = "Tutorial 6/6 · Finished tutorial" },
	{ key = "StartedFirstMatch", name = "Started 1st match" },
	{ key = "FinishedFirstRound", name = "Finished 1st round of 1st match" },
	{ key = "FinishedFirstGame", name = "Finished 1st game" },
	{ key = "StartedSecondMatch", name = "Started 2nd match" },
	{ key = "FinishedSecondMatchRound", name = "Finished 1st round of 2nd match" },
	{ key = "FinishedSecondGame", name = "Finished 2nd game" },
	{ key = "Played12Minutes", name = "Played 12 minutes" },
}
local STEP_INDEX: { [string]: number } = {}
for i, step in ONBOARDING do
	STEP_INDEX[step.key] = i
end
AnalyticsService.Onboarding = ONBOARDING

local COIN_FUNNEL = "CoinPurchases"
local COIN_STEPS = { "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th" }
local LOSS_FUNNEL = "PlayAfterLoss"

function AnalyticsService.init(_services: any) end

-- Studio: workspace:SetAttribute("RD_AnalyticsLog", true) prints every funnel and event call.
local function log(...: any)
	if RunService:IsStudio() and Workspace:GetAttribute("RD_AnalyticsLog") == true then
		print("[Analytics]", ...)
	end
end

-- The player, while they're still in the game.
local function live(c: any): Player?
	local player = c and c.player
	if player and player.Parent then
		return player
	end
	return nil
end

-- Onboarding funnel step `key` (a key of ONBOARDING), first session only.
function AnalyticsService.funnel(c: any, key: string)
	local player = live(c)
	local idx = STEP_INDEX[key]
	if not player or not c.firstSession or not idx then
		return
	end
	c.funnelStep = c.funnelStep or 0
	if idx <= c.funnelStep then
		return
	end
	c.funnelPending = c.funnelPending or {}
	c.funnelPending[idx] = true
	while c.funnelPending[c.funnelStep + 1] do
		local i = c.funnelStep + 1
		c.funnelPending[i] = nil
		c.funnelStep = i
		local name = ONBOARDING[i].name
		pcall(function()
			Analytics:LogOnboardingFunnelStepEvent(player, i, name)
		end)
		log("onboarding", player.Name, i, name)
	end
end

-- The tutorial reached `step` (TutorialService): objective step - 1 is done. Reaching `done` means
-- the last objective (6, the dodge) is done: the tutorial is finished.
function AnalyticsService.tutorialStep(c: any, step: number, done: number)
	if step >= done then
		AnalyticsService.funnel(c, "FinishedTutorial")
	elseif step >= 2 then
		AnalyticsService.funnel(c, "Objective" .. (step - 1))
	end
end

-- The "Play 12 minutes" quest reached its goal (QuestService).
function AnalyticsService.played12Minutes(c: any)
	AnalyticsService.funnel(c, "Played12Minutes")
end

-- A coin purchase went through (a shop item, or a spin bought with coins). The count is saved
-- (profile.CoinPurchases), so the funnel follows a player across sessions; only accounts created
-- since it shipped log it, so an older account's next buy never shows up as a "1st".
function AnalyticsService.coinPurchase(c: any)
	local p = c and c.profile
	if not p then
		return
	end
	p.CoinPurchases = (tonumber(p.CoinPurchases) or 0) + 1
	local n = p.CoinPurchases
	local player = live(c)
	if not player or (tonumber(p.FirstJoinAt) or 0) <= 1 or n > #COIN_STEPS then
		return
	end
	local name = COIN_STEPS[n] .. " coin purchase"
	pcall(function()
		Analytics:LogFunnelStepEvent(player, COIN_FUNNEL, nil, n, name)
	end)
	log("coins", player.Name, n, name)
end

function AnalyticsService.event(c: any, name: string, value: number?)
	local player = c and c.player
	if not player then
		log("event", name, value)
		return
	end
	pcall(function()
		Analytics:LogCustomEvent(player, name, value or 1)
	end)
	log("event", player.Name, name, value)
end

function AnalyticsService.invalidRemote(player: Player, reason: string)
	pcall(function()
		Analytics:LogCustomEvent(player, "InvalidRemote_" .. string.sub(reason, 1, 24), 1)
	end)
end

-- Session firsts, timed from join.
function AnalyticsService.first(c: any, what: "Throw" | "Hit")
	if not c or not c.player or not c.joinedAt then
		return
	end
	c.firsts = c.firsts or {}
	if c.firsts[what] then
		return
	end
	c.firsts[what] = true
	AnalyticsService.event(c, "TimeToFirst" .. what, os.clock() - c.joinedAt)
end

-- A real player starts a match (at its start, or admitted between rounds). Which of their games it
-- is counts finished games only, so after an aborted match the next one is still that game.
function AnalyticsService.matchStarted(c: any)
	local player = live(c)
	if not player then
		return
	end
	c.matchesThisSession = (c.matchesThisSession or 0) + 1
	local finished = c.gamesFinished or 0
	c.funnelGame = finished + 1
	if finished == 0 then
		AnalyticsService.funnel(c, "StartedFirstMatch")
	elseif finished == 1 then
		AnalyticsService.funnel(c, "StartedSecondMatch")
	end
	-- the loss funnel: they played again after losing
	local lossId = c.lossFunnelId
	if lossId then
		c.lossFunnelId = nil
		pcall(function()
			Analytics:LogFunnelStepEvent(player, LOSS_FUNNEL, lossId, 2, "Played another game")
		end)
		log("loss", player.Name, lossId, 2)
	end
	if c.joinedAt and c.matchesThisSession == 1 then
		AnalyticsService.event(c, "JoinToFirstMatch", os.clock() - c.joinedAt)
	end
end

function AnalyticsService.roundStarted(_roster: { any }) end

-- A round of the match ended (won or drawn).
function AnalyticsService.roundEnded(roster: { any })
	for _, c in roster do
		if c.funnelGame == 1 then
			AnalyticsService.funnel(c, "FinishedFirstRound")
		elseif c.funnelGame == 2 then
			AnalyticsService.funnel(c, "FinishedSecondMatchRound")
		end
	end
end

-- Tuning instrumentation (release plan Stage 1): does a hit end in a recovery or a void fall,
-- bucketed by how far from the nearest void edge the target was when hit? The tuning target is
-- "center hits usually recover, edge hits are dangerous".
local tally: { [string]: number } = {}
local function bump(key: string, n: number?)
	tally[key] = (tally[key] or 0) + (n or 1)
end

local function edgeBucket(edgeDist: number): string
	if edgeDist < 8 then
		return "Edge"
	elseif edgeDist < 18 then
		return "Mid"
	end
	return "Center"
end

function AnalyticsService.hitStarted(target: any, thrower: any, edgeDist: number, ballType: string)
	target.pendingHit = { bucket = edgeBucket(edgeDist), ballType = ballType, thrower = thrower, at = os.clock() }
	bump("Hits")
	bump("Hits_" .. ballType)
end

function AnalyticsService.hitResolved(target: any, outcome: string)
	local h = target.pendingHit
	if not h then
		return
	end
	target.pendingHit = nil
	bump(outcome .. "_" .. h.bucket)
	if outcome == "Void" then
		bump("VoidKO_" .. h.ballType)
	end
	-- attribute to whichever side is a real player, so bot-vs-bot hits still feed the tally only
	local who = if target.player then target else h.thrower
	AnalyticsService.event(who, ("HitOutcome_%s_%s"):format(outcome, h.bucket))
	if outcome == "Void" and h.ballType ~= "Standard" then
		AnalyticsService.event(who, "PowerKO_" .. h.ballType)
	end
end

function AnalyticsService.tally(): { [string]: number }
	return tally
end

-- Studio debug overlay data (F8). Counts that reveal leaks across rounds, plus the hit tally.
local function publishDebug()
	local folder = ReplicatedStorage:FindFirstChild("DebugStats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DebugStats"
		folder.Parent = ReplicatedStorage
	end
	local rigs, sockets = 0, 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Humanoid") then
			rigs += 1
		elseif d:IsA("BallSocketConstraint") then
			sockets += 1
		end
	end
	local balls = Workspace:FindFirstChild("Balls")
	local bots = Workspace:FindFirstChild("Bots")
	folder:SetAttribute("Rigs", rigs)
	folder:SetAttribute("Sockets", sockets)
	folder:SetAttribute("Balls", if balls then #balls:GetChildren() else 0)
	folder:SetAttribute("BotModels", if bots then #bots:GetChildren() else 0)
	folder:SetAttribute("Instances", #Workspace:GetDescendants())
	for k, v in tally do
		folder:SetAttribute(k, v)
	end
end

function AnalyticsService.start()
	if RunService:IsStudio() then
		task.spawn(function()
			while true do
				task.wait(1)
				publishDebug()
			end
		end)
	end
end

-- The match is over. A finished (not aborted) game counts toward the onboarding funnel, and a lost
-- one opens a new run of the loss funnel.
function AnalyticsService.matchEnded(
	roster: { any },
	info: { aborted: boolean, bots: number, duration: number, winner: string? }
)
	for _, c in roster do
		local player = live(c)
		if not player then
			continue
		end
		AnalyticsService.event(c, if info.aborted then "MatchAborted" else "MatchCompleted", info.duration)
		AnalyticsService.event(c, "MatchBotCount", info.bots)
		if info.aborted then
			continue
		end
		c.gamesFinished = (c.gamesFinished or 0) + 1
		if c.funnelGame == 1 then
			AnalyticsService.funnel(c, "FinishedFirstGame")
		elseif c.funnelGame == 2 then
			AnalyticsService.funnel(c, "FinishedSecondGame")
		end
		c.funnelGame = nil
		if info.winner and c.team and c.team ~= info.winner then
			c.lossCount = (c.lossCount or 0) + 1
			local id = ("%d_%d_%d"):format(player.UserId, os.time(), c.lossCount)
			c.lossFunnelId = id
			pcall(function()
				Analytics:LogFunnelStepEvent(player, LOSS_FUNNEL, id, 1, "Lost a game")
			end)
			log("loss", player.Name, id, 1)
		end
	end
end

return AnalyticsService
