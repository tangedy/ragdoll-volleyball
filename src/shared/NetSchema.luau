--!strict
-- Remote contract (see docs/REMOTES.md). Clients request actions; the server decides results.

local ProjectileMath = require(script.Parent.ProjectileMath)

local NetSchema = {}

NetSchema.FolderName = "Net"
NetSchema.ActionRemote = "Action" -- client -> server: (action: string, payload: table?)
NetSchema.FeedbackRemote = "Feedback" -- server -> client: (kind: string, data: table?)
NetSchema.MatchStateFolder = "MatchState" -- attributes mirror the server match state

NetSchema.Actions = {
	ChargeStart = "ChargeStart",
	Throw = "Throw",
	CancelAim = "CancelAim",
	Dodge = "Dodge",
	Catch = "Catch",
	SetAutoQueue = "SetAutoQueue",
	SetBusy = "SetBusy", -- a hub menu is open: don't pull this player into a match meanwhile
	SetTouchCamera = "SetTouchCamera", -- Shift lock on touch: the camera only turns when dragged
	SetSetting = "SetSetting",
	ReportDevice = "ReportDevice",
	BuyItem = "BuyItem",
	EquipItem = "EquipItem",
	ClaimDaily = "ClaimDaily",
	PickReward = "PickReward", -- choose one cosmetic from a waiting reward pick (day 7 of the ladder)
	Spin = "Spin",
	MarkSeen = "MarkSeen",
	ClaimQuest = "ClaimQuest", -- open a finished daily quest's chest (Config.Quests.List id)
	Practice = "Practice",
	Dev = "Dev",
}

NetSchema.Feedback = {
	Banner = "Banner",
	Feed = "Feed",
	Impact = "Impact",
	DodgeAccepted = "DodgeAccepted",
	Ragdoll = "Ragdoll",
	ThrowResult = "ThrowResult",
	Results = "Results",
	Tutorial = "Tutorial",
	Profile = "Profile",
	Possession = "Possession",
	Hint = "Hint",
}

export type ThrowPayload = { dir: Vector3, throwId: number }
export type DodgePayload = { dir: Vector3 }

local function isTable(v: any): boolean
	return type(v) == "table"
end

-- Each validator returns a sanitized payload or nil. Unknown fields are ignored.
NetSchema.Validators = {
	ChargeStart = function(_p: any): any
		return {}
	end,
	CancelAim = function(_p: any): any
		return {}
	end,
	Catch = function(_p: any): any
		return {}
	end,
	Throw = function(p: any): any
		if not isTable(p) or typeof(p.dir) ~= "Vector3" or type(p.throwId) ~= "number" then
			return nil
		end
		if p.throwId ~= p.throwId or p.throwId < 0 or p.throwId > 2 ^ 31 then
			return nil
		end
		local dir = ProjectileMath.sanitizeDirection(p.dir)
		if not dir then
			return nil
		end
		return { dir = dir, throwId = math.floor(p.throwId) }
	end,
	Dodge = function(p: any): any
		if not isTable(p) or typeof(p.dir) ~= "Vector3" or not ProjectileMath.isFiniteVector(p.dir) then
			return nil
		end
		local flat = Vector3.new(p.dir.X, 0, p.dir.Z)
		return { dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero }
	end,
	SetAutoQueue = function(p: any): any
		if not isTable(p) or type(p.value) ~= "boolean" then
			return nil
		end
		return { value = p.value }
	end,
	SetBusy = function(p: any): any
		if not isTable(p) or type(p.value) ~= "boolean" then
			return nil
		end
		return { value = p.value }
	end,
	SetTouchCamera = function(p: any): any
		if not isTable(p) or type(p.classic) ~= "boolean" then
			return nil
		end
		return { classic = p.classic }
	end,
	SetSetting = function(p: any): any
		if not isTable(p) or type(p.key) ~= "string" or type(p.value) ~= "boolean" then
			return nil
		end
		if p.key ~= "ReducedMotion" and p.key ~= "CameraShake" then
			return nil
		end
		return { key = p.key, value = p.value }
	end,
	ReportDevice = function(p: any): any
		if not isTable(p) or (p.kind ~= "Touch" and p.kind ~= "Mouse" and p.kind ~= "Gamepad") then
			return nil
		end
		return { kind = p.kind }
	end,
	BuyItem = function(p: any): any
		if not isTable(p) or type(p.id) ~= "string" or #p.id > 64 then
			return nil
		end
		return { id = p.id }
	end,
	EquipItem = function(p: any): any
		if not isTable(p) or type(p.id) ~= "string" or #p.id > 64 then
			return nil
		end
		return { id = p.id }
	end,
	ClaimDaily = function(_p: any): any
		return {}
	end,
	PickReward = function(p: any): any
		-- a catalog id from the oldest waiting pick; the server checks it's one of the choices
		if not isTable(p) or type(p.id) ~= "string" or #p.id > 64 then
			return nil
		end
		return { id = p.id }
	end,
	MarkSeen = function(p: any): any
		-- a shop category the player just looked at
		if not isTable(p) or type(p.category) ~= "string" or #p.category > 32 then
			return nil
		end
		return { category = p.category }
	end,
	Spin = function(p: any): any
		-- paid = true spends coins on an extra spin; otherwise it's the free daily spin
		if not isTable(p) or (p.paid ~= nil and type(p.paid) ~= "boolean") then
			return nil
		end
		return { paid = p.paid == true }
	end,
	ClaimQuest = function(p: any): any
		-- a Config.Quests.List id; the server checks the quest is done and unclaimed today
		if not isTable(p) or type(p.id) ~= "string" or #p.id > 32 then
			return nil
		end
		return { id = p.id }
	end,
	Practice = function(p: any): any
		if not isTable(p) or (p.event ~= "Pickup" and p.event ~= "Throw" and p.event ~= "HitDummy") then
			return nil
		end
		return { event = p.event }
	end,
	Dev = function(p: any): any
		if not isTable(p) or type(p.cmd) ~= "string" or #p.cmd > 32 then
			return nil
		end
		return { cmd = p.cmd }
	end,
}

return NetSchema
