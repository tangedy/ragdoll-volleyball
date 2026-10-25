--!strict
-- Default finisher: hero shot on the player who scored the final knockout, then the camera
-- follows the victim's re-launch off the court.

return {
	Id = "Default",
	Name = "Final Knockout",
	Duration = 3.6,
	Stage = { LaunchDelay = 1.1, Up = 80, Out = 45 },
	play = function(ctx: any)
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		ctx.banner("FINAL KNOCKOUT!", ctx.winnerColor, 1.6)
		if killerRoot then
			local base = killerRoot.Position
			local look = killerRoot.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
			ctx.runFor(1.1, function(alpha: number)
				-- low-angle push-in from the front
				local dist = 9 - 3 * alpha
				local camPos = base + flat * dist + Vector3.new(0, 1 + alpha, 0)
				ctx.camera.CFrame = CFrame.lookAt(camPos, base + Vector3.new(0, 1.5, 0))
			end)
		end
		ctx.banner(("%s finished %s!"):format(ctx.killerName, ctx.victimName), Color3.new(1, 1, 1), 1.8)
		if victimRoot then
			local start = ctx.camera.CFrame.Position
			ctx.runFor(ctx.duration - 1.1, function(alpha: number)
				local target = victimRoot.Position
				-- trail behind and above the flying victim
				local desired = target + Vector3.new(0, 10, 0) + (start - target).Unit * 18
				local camPos = start:Lerp(desired, math.min(1, alpha * 3))
				ctx.camera.CFrame = CFrame.lookAt(camPos, target)
			end)
		end
	end,
}
