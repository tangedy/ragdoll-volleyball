--!strict
-- Default finisher: hero shot on the player who scored the final knockout, then the camera
-- follows the victim's re-launch off the court.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

return {
	Id = "Default",
	Name = "Final Knockout",
	Duration = 3.6,
	Stage = { LaunchDelay = 1.1, Up = 80, Out = 45 },
	play = function(ctx: any)
		ctx.banner("FINAL KNOCKOUT!", ctx.winnerColor, 1.6)
		FinisherKit.heroShot(ctx, 1.1)
		ctx.banner(("%s finished %s!"):format(ctx.killerName, ctx.victimName), Color3.new(1, 1, 1), 1.8)
		FinisherKit.followLaunch(ctx, ctx.duration - 1.1)
	end,
}
