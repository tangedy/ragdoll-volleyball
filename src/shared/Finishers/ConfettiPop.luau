--!strict
-- Confetti Pop (Common): the default hero shot, then the victim goes off in a burst of party
-- confetti.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local CONFETTI = {
	Color3.fromRGB(255, 90, 120),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(120, 230, 120),
	Color3.fromRGB(190, 120, 255),
}

return {
	Id = "ConfettiPop",
	Name = "Confetti Pop",
	Duration = 3.6,
	Stage = { LaunchDelay = 1.1, Up = 85, Out = 45 },
	play = function(ctx: any)
		FinisherKit.heroShot(ctx, 1.1)
		local victimRoot = ctx.rootOf(ctx.victim)
		if victimRoot then
			local at = victimRoot.Position + Vector3.new(0, 1.5, 0)
			ctx.sound("ConfettiPop", at)
			for _, color in CONFETTI do
				ctx.fx.burst(at, color, 14, 40, 0.8)
			end
			ctx.fx.shockwave(at, Vector3.yAxis, Color3.new(1, 1, 1), 14, 0.35)
		end
		FinisherKit.followLaunch(ctx, ctx.duration - 1.1)
	end,
}
