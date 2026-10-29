--!strict
-- Camera beats shared by the simple finishers (Default and its Common/Rare variants): a hero shot
-- on the winner, then the camera follows the victim's re-launch. Each beat yields for its length.

local FinisherKit = {}

-- The horizontal direction the winner faces (toward the victim once staged).
function FinisherKit.facing(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
end

-- Low-angle push-in on the winner from the front for `seconds`. `onFrame(alpha)` runs each frame.
function FinisherKit.heroShot(ctx: any, seconds: number, onFrame: ((number) -> ())?)
	local killerRoot = ctx.rootOf(ctx.killer)
	if not killerRoot then
		return
	end
	local base = killerRoot.Position
	local flat = FinisherKit.facing(killerRoot)
	ctx.runFor(seconds, function(alpha: number)
		local dist = 9 - 3 * alpha
		local camPos = base + flat * dist + Vector3.new(0, 1 + alpha, 0)
		ctx.camera.CFrame = CFrame.lookAt(camPos, base + Vector3.new(0, 1.5, 0))
		if onFrame then
			onFrame(alpha)
		end
	end)
end

-- Trail behind and above the flying victim for `seconds`. `onFrame(alpha)` runs each frame.
function FinisherKit.followLaunch(ctx: any, seconds: number, onFrame: ((number) -> ())?)
	local victimRoot = ctx.rootOf(ctx.victim)
	if not victimRoot then
		return
	end
	local start = ctx.camera.CFrame.Position
	ctx.runFor(seconds, function(alpha: number)
		local target = victimRoot.Position
		local desired = target + Vector3.new(0, 10, 0) + (start - target).Unit * 18
		local camPos = start:Lerp(desired, math.min(1, alpha * 3))
		ctx.camera.CFrame = CFrame.lookAt(camPos, target)
		if onFrame then
			onFrame(alpha)
		end
	end)
end

-- A ColorCorrectionEffect on Lighting for tinting the world; destroy it when done.
function FinisherKit.tint(saturation: number, brightness: number, color: Color3?): ColorCorrectionEffect
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = saturation
	cc.Brightness = brightness
	cc.TintColor = color or Color3.new(1, 1, 1)
	cc.Parent = game:GetService("Lighting")
	return cc
end

return FinisherKit
