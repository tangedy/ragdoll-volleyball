--!strict
-- Sad Trombone (Common): the world drains of color and the camera holds on the victim for a
-- "wah, wah, wah, waaah", and the last note sends them off with a weak little launch.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

return {
	Id = "SadTrombone",
	Name = "Sad Trombone",
	Duration = 4.4,
	-- the launch lands on the last, long note (the cue's 4th note starts 1.5 s in)
	Stage = { LaunchDelay = 2.6, Up = 55, Out = 35 },
	play = function(ctx: any)
		FinisherKit.heroShot(ctx, 1.0)
		local victimRoot = ctx.rootOf(ctx.victim)
		local cc = FinisherKit.tint(-0.85, -0.05, Color3.fromRGB(200, 210, 255))
		if victimRoot then
			ctx.sound("SadTrombone", victimRoot.Position)
			-- a slow push-in on the victim's face, from the side they're facing
			local base = victimRoot.Position + Vector3.new(0, 1.5, 0)
			local flat = FinisherKit.facing(victimRoot)
			ctx.runFor(1.6, function(alpha: number)
				local camPos = base + flat * (8 - 2.5 * alpha) + Vector3.new(0, 0.5, 0)
				ctx.camera.CFrame = CFrame.lookAt(camPos, base)
			end)
		end
		FinisherKit.followLaunch(ctx, ctx.duration - 2.6)
		cc:Destroy()
	end,
}
