--!strict
-- BONK! (Common): the default hero shot, then a cartoon bonk on the victim's head sends them extra
-- high.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

return {
	Id = "Bonk",
	Name = "BONK!",
	Duration = 3.8,
	Stage = { LaunchDelay = 1.1, Up = 110, Out = 40 },
	play = function(ctx: any)
		FinisherKit.heroShot(ctx, 1.1)
		local victimRoot = ctx.rootOf(ctx.victim)
		if victimRoot then
			local head = victimRoot.Position + Vector3.new(0, 2.5, 0)
			ctx.sound("Bonk", head)
			ctx.fx.flash(head, Color3.new(1, 1, 1), 6)
			ctx.fx.burst(head, Color3.fromRGB(255, 220, 60), 22, 30, 0.9)
			if not ctx.reducedMotion then
				ctx.fx.screenFlash(Color3.new(1, 1, 1), 0.35, 0.08)
			end
			ctx.fx.shake(0.5)
		end
		FinisherKit.followLaunch(ctx, ctx.duration - 1.1)
	end,
}
