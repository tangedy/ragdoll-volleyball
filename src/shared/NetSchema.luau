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
	UsePower = "UsePower", -- an equipped power's active ({ slot = 1 | 2 }); PowerService decides
	UseUltimate = "UseUltimate", -- slot 1's ultimate, once the meter is full
	SpinPower = "SpinPower", -- a coin spin on the Power Wheel
	SetAutoQueue = "SetAutoQueue", -- the hub PLAY button (true) and its Cancel (false); also Play again
	LeaveMatch = "LeaveMatch", -- the in-match Leave button: back to the hub, a bot takes your place
	SetTouchCamera = "SetTouchCamera", -- Shift lock on touch: the camera only turns when dragged
	SetSetting = "SetSetting",
	ReportDevice = "ReportDevice",
	BuyItem = "BuyItem",
	SetGoal = "SetGoal", -- the item you're saving for (the hub's goal chip); "" clears it
	EquipItem = "EquipItem",
	ClaimDaily = "ClaimDaily",
	PickReward = "PickReward", -- choose one cosmetic from a waiting reward pick (day 7 of the ladder)
	Spin = "Spin",
	MarkSeen = "MarkSeen",
	HubGuideSeen = "HubGuideSeen", -- the first-visit hub guidance has started (saved once per account)
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

local PRACTICE_EVENTS: { [string]: boolean } = {
	Pickup = true,
	Throw = true,
	HitDummy = true,
	DummyOut = true, -- the dummy fell into the void
	HeavyOut = true, -- the Heavy practice ball knocked the dummy off
	Dodged = true, -- a drill ball missed after the player dodged
	GotHit = true, -- a drill ball hit the player
}

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
	UsePower = function(p: any): any
		-- the move direction (Blink) is optional; slot 2 is the Extra Power Slot pass
		if not isTable(p) or (p.slot ~= 1 and p.slot ~= 2) then
			return nil
		end
		local dir = nil
		if typeof(p.dir) == "Vector3" and ProjectileMath.isFiniteVector(p.dir) then
			local flat = Vector3.new(p.dir.X, 0, p.dir.Z)
			dir = if flat.Magnitude > 0.1 then flat.Unit else nil
		end
		return { slot = p.slot, dir = dir }
	end,
	UseUltimate = function(_p: any): any
		return {}
	end,
	SpinPower = function(_p: any): any
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
	LeaveMatch = function(_p: any): any
		return {}
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
		-- the price the shop showed (a deal that ended meanwhile never charges more); optional
		local price = if type(p.price) == "number" and p.price == p.price and p.price >= 0 then p.price else nil
		return { id = p.id, price = price }
	end,
	SetGoal = function(p: any): any
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
	HubGuideSeen = function(_p: any): any
		return {} -- no payload
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
		-- hub practice events (TutorialService): the client simulates the dummy and practice balls
		if not isTable(p) or type(p.event) ~= "string" or not PRACTICE_EVENTS[p.event] then
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
