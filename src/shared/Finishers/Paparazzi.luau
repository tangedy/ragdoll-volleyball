--!strict
-- Paparazzi (Rare): the winner strikes a pose while camera flashes go off all around them and the
-- shot cuts between press angles. Then the victim is sent off.

local FinisherKit = require(script.Parent.Parent.FinisherKit)

local CUTS = 5 -- press angles around the winner during the photo call

return {
	Id = "Paparazzi",
	Name = "Paparazzi",
	Duration = 4.4,
	Stage = { LaunchDelay = 2.6, Up = 85, Out = 45 },
	play = function(ctx: any)
		local killerRoot = ctx.rootOf(ctx.killer)
		if killerRoot then
			local unpose = ctx.pose(ctx.killer, "CrossArms", 0.2)
			local base = killerRoot.Position + Vector3.new(0, 1.5, 0)
			local flat = FinisherKit.facing(killerRoot)
			local side = flat:Cross(Vector3.yAxis)
			local rng = Random.new()
			-- reduced motion: one slow push-in, no cuts or screen flashes (the clicks still play)
			local cuts = if ctx.reducedMotion then 1 else CUTS
			local each = 2.6 / cuts
			for i = 1, cuts do
				local swing = if cuts == 1 then 0 else (i / cuts - 0.5) * 1.6
				local dir = (flat + side * swing).Unit
				local height = rng:NextNumber(-0.5, 2)
				ctx.sound("ShutterClick", base)
				if not ctx.reducedMotion then
					ctx.fx.screenFlash(Color3.new(1, 1, 1), 0.55, 0.07)
				end
				-- a few camera flashes from the crowd around them
				for _ = 1, if ctx.reducedMotion then 1 else 3 do
					local at = base + (flat * rng:NextNumber(5, 9)) + side * rng:NextNumber(-6, 6)
					ctx.fx.flash(at + Vector3.new(0, rng:NextNumber(0, 3), 0), Color3.new(1, 1, 1), 2.5)
				end
				ctx.runFor(each, function(alpha: number)
					local dist = 8 - 1.5 * alpha
					ctx.camera.CFrame = CFrame.lookAt(base + dir * dist + Vector3.new(0, height, 0), base)
				end)
			end
			unpose()
		end
		FinisherKit.followLaunch(ctx, ctx.duration - 2.6)
	end,
}
