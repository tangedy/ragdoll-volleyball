--!strict
-- Air Horn (Common): the default hero shot, then three air-horn blasts as the victim launches, each
-- one a shockwave off them.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

return {
	Id = "AirHorn",
	Name = "Air Horn",
	Duration = 3.6,
	Stage = { LaunchDelay = 1.1, Up = 80, Out = 50 },
	play = function(ctx: any)
		FinisherKit.heroShot(ctx, 1.1)
		local victimRoot = ctx.rootOf(ctx.victim)
		if victimRoot then
			ctx.sound("AirHorn", victimRoot.Position)
			-- one ring per blast (the cue goes short, short, long)
			for i, at in { 0, 0.3, 0.6 } do
				task.delay(at, function()
					if victimRoot.Parent then
						ctx.fx.shockwave(
							victimRoot.Position,
							Vector3.yAxis,
							Color3.fromRGB(255, 230, 120),
							10 + 4 * i,
							0.3
						)
						ctx.fx.shake(if i == 3 then 0.35 else 0.15)
					end
				end)
			end
		end
		FinisherKit.followLaunch(ctx, ctx.duration - 1.1)
	end,
}
