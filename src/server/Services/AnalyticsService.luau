--!strict
-- Thin wrapper over Roblox AnalyticsService (spec §14, Amendment A analytics additions).
-- Funnel steps are monotonic: logging a later step fills any earlier gaps server-side.

local Analytics = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AnalyticsService = {}

local FUNNEL = {
	"Joined",
	"PickedUpFirstBall",
	"ThrewFirstBall",
	"LandedFirstHit",
	"EnteredFirstRound",
	"CompletedFirstRound",
	"CompletedFirstMatch",
	"StartedSecondMatch",
}
local STEP_INDEX: { [string]: number } = {}
for i, name in FUNNEL do
	STEP_INDEX[name] = i
end

local VERBOSE = false -- set true to print analytics calls in Studio

function AnalyticsService.init(_services: any) end

local function log(...: any)
	if VERBOSE and RunService:IsStudio() then
		print("[Analytics]", ...)
	end
end

-- Onboarding funnel, fresh saves only (Matches == 0 at join).
function AnalyticsService.funnel(c: any, step: string)
	local player = c and c.player
	if not player or not c.funnelEligible then
		return
	end
	local idx = STEP_INDEX[step]
	if not idx then
		return
	end
	c.funnelStep = c.funnelStep or 0
	if idx <= c.funnelStep then
		return
	end
	for i = c.funnelStep + 1, idx do
		local name = FUNNEL[i]
		pcall(function()
			Analytics:LogOnboardingFunnelStepEvent(player, i, name)
		end)
		log("funnel", player.Name, i, name)
	end
	c.funnelStep = idx
	if step == "ThrewFirstBall" and c.joinedAt then
		AnalyticsService.event(c, "TimeToFirstThrow", os.clock() - c.joinedAt)
	elseif step == "LandedFirstHit" and c.joinedAt then
		AnalyticsService.event(c, "TimeToFirstHit", os.clock() - c.joinedAt)
	end
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

function AnalyticsService.matchStarted(c: any)
	if not c.player then
		return
	end
	c.matchesThisSession = (c.matchesThisSession or 0) + 1
	if c.matchesThisSession == 2 then
		AnalyticsService.funnel(c, "StartedSecondMatch")
	end
	if c.joinedAt and c.matchesThisSession == 1 then
		AnalyticsService.event(c, "JoinToFirstMatch", os.clock() - c.joinedAt)
	end
end

function AnalyticsService.roundStarted(_roster: { any }) end

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

function AnalyticsService.matchEnded(roster: { any }, info: { aborted: boolean, bots: number, duration: number })
	for _, c in roster do
		if c.player then
			AnalyticsService.funnel(c, "CompletedFirstMatch")
			AnalyticsService.event(c, if info.aborted then "MatchAborted" else "MatchCompleted", info.duration)
			AnalyticsService.event(c, "MatchBotCount", info.bots)
		end
	end
end

return AnalyticsService
