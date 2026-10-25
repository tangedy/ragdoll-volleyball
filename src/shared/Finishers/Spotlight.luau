--!strict
-- Spotlight finisher (purchasable example): the world dims, a spotlight hits the winner and the
-- camera orbits them, then the victim is sent extra high.

local Lighting = game:GetService("Lighting")

return {
	Id = "Spotlight",
	Name = "Spotlight",
	Duration = 4.2,
	Stage = { LaunchDelay = 2.2, Up = 90, Out = 30 },
	play = function(ctx: any)
		local killerRoot = ctx.rootOf(ctx.killer)
		local victimRoot = ctx.rootOf(ctx.victim)
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Brightness = -0.25
		cc.Saturation = -0.4
		cc.Parent = Lighting
		local light: Part? = nil
		if killerRoot then
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.Transparency = 1
			p.CFrame = CFrame.new(killerRoot.Position + Vector3.new(0, 14, 0))
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Bottom
			spot.Angle = 35
			spot.Range = 30
			spot.Brightness = 8
			spot.Color = Color3.fromRGB(255, 240, 200)
			spot.Parent = p
			p.Parent = workspace
			light = p
		end
		ctx.banner(("%s TAKES THE SPOTLIGHT!"):format(string.upper(ctx.killerName)), ctx.winnerColor, 2)
		if killerRoot then
			local base = killerRoot.Position + Vector3.new(0, 1.5, 0)
			local turns = if ctx.reducedMotion then 0.25 else 0.75
			ctx.runFor(2.2, function(alpha: number)
				local angle = alpha * math.pi * 2 * turns
				local camPos = base + Vector3.new(math.sin(angle) * 10, 3, math.cos(angle) * 10)
				ctx.camera.CFrame = CFrame.lookAt(camPos, base)
			end)
		end
		cc:Destroy()
		if light then
			light:Destroy()
		end
		if victimRoot then
			ctx.banner(("Bye, %s!"):format(ctx.victimName), Color3.new(1, 1, 1), 1.5)
			local start = ctx.camera.CFrame.Position
			ctx.runFor(ctx.duration - 2.2, function()
				ctx.camera.CFrame = CFrame.lookAt(start + Vector3.new(0, 4, 0), victimRoot.Position)
			end)
		end
	end,
}
