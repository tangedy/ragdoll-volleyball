--!strict
-- Contextual, learn-by-doing tutorial (spec §10 "Onboarding"). The server owns progress and saves
-- it; the client only renders the card for the current step. Steps advance on real actions in any
-- context, so actions done early still count.
--
-- 1 Walk over a ball -> 2 Hold to aim, release to throw -> 3 Launch the dummy / hit someone
-- -> 4 Stay on the court! -> 5 Catch tip (downtime) -> 6 done

local TutorialService = {}

local S: any

TutorialService.Done = 6

function TutorialService.init(services: any)
	S = services
end

local function setStep(c: any, step: number)
	local p = c.profile
	if not p or step <= p.TutorialStep then
		return
	end
	p.TutorialStep = step
	if c.player then
		S.NetService.send(c.player, "Tutorial", { step = step })
	end
	if step == 4 then
		-- "Stay on the court!" is a short beat, then the catch tip waits for downtime
		task.delay(4, function()
			if p.TutorialStep == 4 then
				setStep(c, 5)
			end
		end)
	end
end

function TutorialService.onEvent(c: any, kind: string)
	if not c.player or not c.profile then
		return
	end
	local step = c.profile.TutorialStep
	if step >= TutorialService.Done then
		return
	end
	if kind == "Pickup" and step <= 1 then
		setStep(c, 2)
	elseif kind == "Throw" and step <= 2 then
		setStep(c, 3)
	elseif (kind == "Hit" or kind == "HitDummy") and step <= 3 then
		setStep(c, 4)
	elseif kind == "Catch" then
		setStep(c, TutorialService.Done)
	end
end

-- Resend the current step (on join, after the profile loads).
function TutorialService.sync(c: any)
	if c.player and c.profile then
		S.NetService.send(c.player, "Tutorial", { step = c.profile.TutorialStep })
	end
end

return TutorialService
