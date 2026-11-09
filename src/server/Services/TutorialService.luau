--!strict
-- The guided hub tutorial. A new player finishes it in the hub before they're ever queued for a
-- match (MatchService.queuedPlayers checks the TutorialDone player attribute). The server owns the
-- step and saves it; the client runs the practice (dummy, balls, dodge drill) and reports Practice
-- events, and renders the step it's told. The step contract is in docs/prompts/build-path.md:
--
-- 1 Grab (Pickup) -> 2 FirstHit (HitDummy) -> 3 KnockOff (DummyOut) -> 4 Heavy (HeavyOut)
-- -> 5 Discover (moves on by itself) -> 6 Dodge (Dodged) -> 7 Done (the one-time reward)
--
-- Steps only move forward, one at a time, and only on the current step's event. Throw and GotHit
-- are sent too but never move a step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local T = Config.Tutorial

local TutorialService = {}

local S: any

TutorialService.Done = T.Done
TutorialService.Discover = 5

-- the Practice event that finishes each step (5 has none: it runs on a timer)
local NEXT_ON: { [number]: string } = {
	[1] = "Pickup",
	[2] = "HitDummy",
	[3] = "DummyOut",
	[4] = "HeavyOut",
	[6] = "Dodged",
}

function TutorialService.init(services: any)
	S = services
end

function TutorialService.isDone(c: any): boolean
	return c.profile ~= nil and c.profile.TutorialStep >= T.Done
end

local function inHub(c: any): boolean
	return c.profileLoaded == true and c.profile ~= nil and not c.inMatch and c.status == "Lobby"
end

local function coolingDown(c: any): number
	return T.StepCooldown - (os.clock() - (c.tutorialChangedAt or -math.huge))
end

-- Reached Done: pay the reward if it was never paid, save, then open the queue. Returns the granted
-- reward (RewardService.grant's result), or nil when it was already paid.
local function complete(c: any): { [string]: any }?
	local p = c.profile
	local result: { [string]: any }? = nil
	if not p.TutorialRewarded then
		result = S.RewardService.grant(c, T.Reward, "Tutorial")
		if result then
			p.TutorialRewarded = true
		end
	end
	S.DataService.push(c)
	task.spawn(S.DataService.save, c, false)
	if c.player then
		c.player:SetAttribute("TutorialDone", true)
	end
	c.tutorialDoneAt = os.clock() -- the first match starts sooner (MatchService.run)
	-- straight into the queue (as if PLAY was pressed), whoever else is in the server, so nobody
	-- finishes the tutorial and stalls in the hub; a short beat first so the Done card can land.
	-- Cancel opts out as usual (queueDeclined).
	if Config.Match.QueueAfterTutorial then
		task.delay(Config.Match.QueueAfterTutorialDelay, function()
			if c.player and c.player.Parent and not c.queueDeclined and not c.inMatch then
				c.autoQueue = true
				c.player:SetAttribute("AutoQueue", true)
			end
		end)
	end
	return result
end

local setStep: (c: any, step: number) -> ()

-- Discover is a short beat: after DiscoverSeconds it moves on to the dodge drill.
local function scheduleDiscover(c: any)
	local p = c.profile
	task.delay(T.DiscoverSeconds, function()
		if c.profile == p and p.TutorialStep == TutorialService.Discover then
			setStep(c, TutorialService.Discover + 1)
		end
	end)
end

function setStep(c: any, step: number)
	local p = c.profile
	if step <= p.TutorialStep then
		return
	end
	p.TutorialStep = step
	c.tutorialChangedAt = os.clock()
	local message: { [string]: any } = { step = step }
	if step >= T.Done then
		message.reward = complete(c)
	end
	S.AnalyticsService.event(c, "TutorialStep" .. step)
	S.AnalyticsService.tutorialStep(c, step, T.Done)
	if c.player then
		S.NetService.send(c.player, "Tutorial", message)
	end
	if step == TutorialService.Discover then
		scheduleDiscover(c)
	end
end

-- A Practice event from the hub (LobbyService). Anything but the current step's event is ignored,
-- and the step moves at most once per StepCooldown: the right event arriving sooner is applied once
-- the cooldown is over, so a spammed remote can't run through the tutorial in one frame.
function TutorialService.onEvent(c: any, kind: string)
	if not inHub(c) then
		return
	end
	local p = c.profile
	local step = p.TutorialStep
	if step >= T.Done or NEXT_ON[step] ~= kind then
		return
	end
	local left = coolingDown(c)
	if left <= 0 then
		setStep(c, step + 1)
	elseif not c.tutorialDeferred then
		c.tutorialDeferred = true
		task.delay(left, function()
			c.tutorialDeferred = nil
			if c.profile == p and p.TutorialStep == step and inHub(c) and coolingDown(c) <= 0 then
				setStep(c, step + 1)
			end
		end)
	end
end

-- On join, after the profile loads: the current step, and TutorialDone for players who finished.
function TutorialService.sync(c: any)
	local p = c.profile
	if not p then
		return
	end
	if c.player then
		c.player:SetAttribute("TutorialDone", p.TutorialStep >= T.Done)
		S.NetService.send(c.player, "Tutorial", { step = p.TutorialStep })
	end
	if p.TutorialStep == TutorialService.Discover then
		scheduleDiscover(c) -- left during the beat: carry on from it
	end
end

-- Studio shortcuts (the Dev remote, Studio-only): back to step 1, or straight to Done. Neither
-- pays: the reward is still paid at most once per save, so a reset and replay doesn't pay again.
local function devSet(c: any, step: number)
	local p = c.profile
	if not p then
		return
	end
	p.TutorialStep = step
	c.tutorialChangedAt = nil
	if c.player then
		c.player:SetAttribute("TutorialDone", step >= T.Done)
		S.NetService.send(c.player, "Tutorial", { step = step })
	end
	S.DataService.push(c)
end

function TutorialService.devReset(c: any)
	devSet(c, 1)
end

function TutorialService.devSkip(c: any)
	devSet(c, T.Done)
end

return TutorialService
