--!strict
-- Applies the controlled dodge displacement on whichever machine owns the character's physics:
-- the local client for player characters, the server for bots.

local Config = require(script.Parent.Config)

local DodgeMotion = {}

function DodgeMotion.apply(character: Model, dir: Vector3)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.1 then
		-- stationary: dodge backward relative to facing
		flat = -root.CFrame.LookVector
		flat = Vector3.new(flat.X, 0, flat.Z)
	end
	if flat.Magnitude < 0.1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "DodgeAttachment"
	attachment.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "DodgeVelocity"
	lv.Attachment0 = attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(flat.Unit.X, flat.Unit.Z) * Config.Player.DodgeSpeed
	lv.MaxForce = 1e5
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	task.delay(Config.Player.DodgeDuration, function()
		lv:Destroy()
		attachment:Destroy()
	end)
end

return DodgeMotion
