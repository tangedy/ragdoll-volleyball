--!strict
-- Slow-Mo Replay (Rare): the victim's launch plays once at full speed, then again as a slow-motion,
-- desaturated replay: a stand-in retraces the recorded flight at a third of the speed while the
-- camera orbits it.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local LIVE = 0.9 -- seconds of the real launch recorded
local SLOW = 3 -- replay speed divisor

return {
	Id = "SlowMoReplay",
	Name = "Slow-Mo Replay",
	Duration = 4.8,
	Stage = { LaunchDelay = 0.9, Up = 80, Out = 45 },
	play = function(ctx: any)
		FinisherKit.heroShot(ctx, 0.9)
		local victimRoot = ctx.rootOf(ctx.victim)
		if not victimRoot then
			return
		end
		ctx.sound("Hit", victimRoot.Position)
		-- live: follow the launch and record where the victim goes
		local path: { CFrame } = {}
		FinisherKit.followLaunch(ctx, LIVE, function()
			table.insert(path, victimRoot.CFrame)
		end)
		local puppet = ctx.standIn(ctx.victim)
		if #path < 2 or not puppet then
			FinisherKit.followLaunch(ctx, ctx.duration - 0.9 - LIVE)
			return
		end
		-- replay: the stand-in retraces the path slowly, in a washed-out "replay" grade
		ctx.hide(ctx.victim)
		local cc = FinisherKit.tint(-0.6, 0.05, Color3.fromRGB(255, 240, 215))
		ctx.sound("BallWhoosh", path[1].Position)
		local replay = math.min(LIVE * SLOW, ctx.duration - 0.9 - LIVE)
		local turn = if ctx.reducedMotion then 0.15 else 0.45
		ctx.runFor(replay, function(alpha: number)
			local f = alpha * (#path - 1) + 1
			local i = math.min(#path - 1, math.floor(f))
			local cf = path[i]:Lerp(path[i + 1], f - i)
			puppet:PivotTo(cf)
			local angle = alpha * math.pi * 2 * turn
			local offset = Vector3.new(math.sin(angle) * 12, 4, math.cos(angle) * 12)
			ctx.camera.CFrame = CFrame.lookAt(cf.Position + offset, cf.Position)
		end)
		cc:Destroy()
	end,
}
