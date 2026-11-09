--!strict
-- Equippable powers (Config.Powers, PowerDefinitions). Every combatant in a match has one or two
-- powers: slot 1 (its active and its ultimate) and, with the Extra Power Slot pass, slot 2 (an active
-- only). Actives run on cooldowns; the ultimate needs a full meter, which fills from hits, catches,
-- knockouts, dodges and a slow trickle (Config.Powers.Meter) and resets every round. Players ask
-- with UsePower / UseUltimate; bots decide in tick(). Everything is decided here.
--
-- Player attributes for the HUD (PowerController): Powers ("Heavy" or "Heavy,Blink"), PowerReadyAt1,
-- PowerReadyAt2 (server-time timestamps), UltCharge (0..Meter.Max) and Frozen / Phantom flags.
--
-- Ball powers turn the held ball into a power ball type (BallDefinitions) — the same balls the old
-- dispensers dropped, plus Curve, Bounce, Gravity and Thunder. An ultimate ball also carries
-- ball.power = { ult, owner, ... }: its effect fires on launch (onLaunch) or impact (onImpact);
-- dropping it or having it caught turns it back to Standard.
--
-- Timed effects on a combatant (all cleared by clearEffects at a round reset or elimination):
-- frozenUntil (ice), phantomUntil, shieldUntil (bubble), hiddenUntil / ghostUntil (Decoy, Void),
-- giantUntil (Giant, Titan), tetherUntil (Tether). c.history keeps the last few seconds of
-- positions and damage % for Rewind.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local NetSchema = require(Shared.NetSchema)
local ArenaLayout = require(Shared.ArenaLayout)
local PowerDefinitions = require(Shared.PowerDefinitions)
local ProjectileMath = require(Shared.ProjectileMath)

local PowerService = {}

local S: any
local PW = Config.Powers
local M = PW.Meter
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

function PowerService.init(services: any)
	S = services
end

local function setAttr(c: any, key: string, value: any)
	S.PlayerStateService.setAttr(c, key, value)
end

local function alive(c: any): boolean
	return S.PlayerStateService.isAlive(c)
end

local function ragdolled(c: any): boolean
	return c.character ~= nil and S.RagdollService.isRagdolled(c.character)
end

local function inLiveMatch(c: any): boolean
	return PW.Enabled and c.inMatch and c.status == "Active" and S.MatchService.isRoundLive()
end

local function tell(c: any, text: string)
	if c.player then
		S.NetService.send(c.player, "Hint", { text = text, duration = 1.2 })
	end
end

-- A bot's power: rolled once per bot by catalog rarity (Config.Powers.BotRarityWeights).
local function rollBotPower(): string
	local w = PW.BotRarityWeights
	local list, total = {}, 0
	for _, item in Catalog.inCategory("Power") do
		local weight = (w :: any)[Catalog.rarity(item)] or 0
		total += weight
		table.insert(list, { id = Catalog.powerOf(item) :: string, w = weight })
	end
	local roll = rng:NextNumber() * total
	for _, e in list do
		roll -= e.w
		if roll <= 0 then
			return e.id
		end
	end
	return list[1].id
end

-- The combatant's equipped power ids (slot 1 first).
function PowerService.powersOf(c: any): { string }
	if not c.powers then
		PowerService.reset(c)
	end
	return c.powers
end

-- Mastery ------------------------------------------------------------------------------------------

local MASTERY = PW.Mastery

-- c's mastery level with power `id` (1 for bots and anyone unsaved).
function PowerService.masteryLevel(c: any, id: string?): number
	local p = c.profile
	if not id or not p or c.isBot or type(p.PowerMastery) ~= "table" then
		return 1
	end
	return PowerDefinitions.masteryLevel(tonumber(p.PowerMastery[id]) or 0)
end

-- Slot `slot`'s active cooldown for `c`, after its mastery perk.
function PowerService.cooldownFor(c: any, slot: number): number
	local id = PowerService.powersOf(c)[slot]
	local def = PowerDefinitions.get(id)
	if not def then
		return 0
	end
	return def.Cooldown * PowerDefinitions.masteryPerks(PowerService.masteryLevel(c, id)).cooldown
end

local function publish(c: any)
	setAttr(c, "Powers", table.concat(c.powers or {}, ","))
	setAttr(c, "PowerReadyAt1", (c.powerReadyAt or {})[1] or 0)
	setAttr(c, "PowerReadyAt2", (c.powerReadyAt or {})[2] or 0)
	setAttr(c, "UltCharge", math.floor(c.ult or 0))
	-- each slot's mastery level and its cooldown after the perk (the HUD's stars and cooldown sweep)
	for slot = 1, 2 do
		local id = (c.powers or {})[slot]
		setAttr(c, "PowerMastery" .. slot, if id then PowerService.masteryLevel(c, id) else 0)
		setAttr(c, "PowerCooldown" .. slot, if id then PowerService.cooldownFor(c, slot) else 0)
	end
end

-- Add `amount` mastery XP to each power `c` has equipped (a real, loaded player in a match). A level
-- up is announced and saved. Returns the levels gained by slot 1's power (for tests).
function PowerService.gainMastery(c: any, amount: number): number
	local p = c.profile
	if c.isBot or not c.player or not c.profileLoaded or not p or amount <= 0 then
		return 0
	end
	if type(p.PowerMastery) ~= "table" then
		p.PowerMastery = {}
	end
	local gained = 0
	local levelled = false
	for slot, id in PowerService.powersOf(c) do
		local before = tonumber(p.PowerMastery[id]) or 0
		local after = before + amount
		p.PowerMastery[id] = after
		local from, to = PowerDefinitions.masteryLevel(before), PowerDefinitions.masteryLevel(after)
		if to > from then
			levelled = true
			if slot == 1 then
				gained += to - from
			end
			local def = PowerDefinitions.get(id) :: any
			local mastered = to >= MASTERY.MaxLevel
			S.NetService.send(c.player, "Banner", {
				text = if mastered
					then ("🌟 %s MASTERED!"):format(string.upper(def.Name))
					else ("%s MASTERY %d"):format(string.upper(def.Name), to),
				color = if mastered then Color3.fromRGB(255, 215, 80) else def.Color,
				duration = 1.8,
				sound = "JailEscape",
			})
			S.AnalyticsService.event(c, ("Mastery_%s_%d"):format(id, to))
		end
	end
	if levelled then
		publish(c)
		S.DataService.push(c)
		task.spawn(S.DataService.save, c, false)
	end
	return gained
end

-- Fresh round (MatchService resetCombatant): re-read the equipped powers, empty the meter, clear
-- freezes and phantoms. Actives become ready RoundStartDelay after GO (roundStarted).
function PowerService.reset(c: any)
	PowerService.clearEffects(c)
	c.history = {}
	if c.isBot then
		c.botPower = c.botPower or rollBotPower()
		c.powers = { c.botPower }
	elseif c.profile then
		c.powers = S.ShopService.equippedPowers(c)
	else
		c.powers = { Catalog.powerOf(Catalog.get(PW.Starter)) :: string }
	end
	c.powerReadyAt = { 0, 0 }
	c.ult = 0
	c.ultCastUntil = 0
	c.botUltAt = nil
	publish(c)
end

-- Studio testing (the "Power:<id>" dev command): slot 1 becomes `id`, ready now.
function PowerService.devSet(c: any, id: string)
	if not PowerDefinitions.get(id) then
		return
	end
	PowerService.powersOf(c)[1] = id
	c.powerReadyAt = { 0, 0 }
	publish(c)
end

-- GO: every active comes off cooldown a moment after the round starts.
function PowerService.roundStarted(roster: { any })
	local t = now() + PW.RoundStartDelay
	for _, c in roster do
		PowerService.powersOf(c)
		c.powerReadyAt = { t, t }
		publish(c)
	end
end

-- The team behind on rounds starts the round with Config.Powers.ComebackUlt of a full meter.
function PowerService.comeback(roster: { any }, team: string)
	if not PW.Enabled or (PW.ComebackUlt or 0) <= 0 then
		return
	end
	local amount = M.Max * PW.ComebackUlt
	for _, c in roster do
		if c.team == team and c.inMatch and not c.isDummy and (c.ult or 0) < amount then
			c.ult = amount
			setAttr(c, "UltCharge", math.floor(amount))
		end
	end
end

-- Ultimate meter ---------------------------------------------------------------------------------

function PowerService.addMeter(c: any, amount: number)
	if not c or not PW.Enabled or not c.inMatch or not S.MatchService.isRoundLive() then
		return
	end
	if c.isDummy then
		return
	end
	local before = c.ult or 0
	-- slot 1's mastery perk speeds the meter up
	local scale = PowerDefinitions.masteryPerks(PowerService.masteryLevel(c, (c.powers or {})[1])).meter
	c.ult = math.clamp(before + amount * scale, 0, M.Max)
	if math.floor(c.ult) ~= math.floor(before) then
		setAttr(c, "UltCharge", math.floor(c.ult))
	end
	if before < M.Max and c.ult >= M.Max then
		if c.player then
			S.NetService.send(c.player, "PowerFx", { kind = "UltReady" })
		elseif
			c.isBot
			and not (c.bot and c.bot.difficulty == Config.Bots.Rookie.Profile and Config.Bots.Rookie.NoUltimates)
		then
			local d = PW.BotUltDelay
			c.botUltAt = now() + rng:NextNumber(d[1], d[2])
		end
	end
end

-- CombatService hooks.
function PowerService.onHit(thrower: any?, target: any, damage: number)
	if thrower and thrower.team ~= target.team then
		PowerService.addMeter(thrower, M.Hit * math.clamp(damage / Config.Damage.PerHit, 0.75, 2))
		if thrower.inMatch and not target.isDummy then
			PowerService.gainMastery(thrower, MASTERY.XP.Hit)
		end
	end
	PowerService.addMeter(target, M.GotHit)
end

function PowerService.onCatch(c: any)
	PowerService.addMeter(c, M.Catch)
end

function PowerService.onKnockout(c: any)
	PowerService.addMeter(c, M.Knockout)
	if c.inMatch then
		PowerService.gainMastery(c, MASTERY.XP.Knockout)
	end
end

function PowerService.onDodge(c: any)
	PowerService.addMeter(c, M.Dodge)
end

-- Freeze (Frost, Time Stop) ----------------------------------------------------------------------

local function restoreSpeed(c: any)
	local h = c.humanoid :: Humanoid?
	if not h or not S.MatchService.isRoundLive() then
		return
	end
	local scale = if c.phantomUntil and now() < c.phantomUntil then c.phantomSpeed or 1 else 1
	h.WalkSpeed = Config.Player.WalkSpeed * scale
	h.JumpPower = Config.Player.JumpPower
end

-- Encase `c` in ice for `duration`: no moving, throwing, dodging or catching. Frozen players are
-- still hittable (a hit shatters the ice and launches them as usual), so teammates can follow up.
function PowerService.freeze(c: any, duration: number)
	if not alive(c) or ragdolled(c) or c.status ~= "Active" then
		return
	end
	local root = c.root :: BasePart
	local t = now()
	c.frozenUntil = math.max(c.frozenUntil or 0, t + duration)
	local until_ = c.frozenUntil
	c.chargeStart = nil
	c.catchUntil = 0
	S.PlayerStateService.setAction(c, "Frozen")
	if c.humanoid then
		c.humanoid.WalkSpeed = 0
		c.humanoid.JumpPower = 0
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	if not c.iceBlock then
		local ice = Instance.new("Part")
		ice.Name = "PowerIce"
		ice.Size = Vector3.new(4.6, 6.4, 4.6)
		ice.Material = Enum.Material.Ice
		ice.Color = Color3.fromRGB(170, 230, 255)
		ice.Transparency = 0.35
		ice.Anchored = true
		ice.CanCollide = false
		ice.CanQuery = false
		ice.CanTouch = false
		ice.CastShadow = false
		ice.CFrame = root.CFrame * CFrame.new(0, -0.3, 0)
		ice.Parent = c.character
		c.iceBlock = ice
	end
	setAttr(c, "Frozen", true)
	task.delay(duration, function()
		if c.frozenUntil == until_ then
			PowerService.unfreeze(c)
		end
	end)
end

function PowerService.unfreeze(c: any)
	if not c.frozenUntil then
		return
	end
	c.frozenUntil = nil
	if c.iceBlock then
		c.iceBlock:Destroy()
		c.iceBlock = nil
	end
	if c.root and c.root.Parent then
		c.root.Anchored = false
	end
	setAttr(c, "Frozen", false)
	if c.action == "Frozen" then
		S.PlayerStateService.setAction(c, "Idle")
	end
	restoreSpeed(c)
	if c.root then
		S.NetService.broadcast("PowerFx", { kind = "Shatter", position = c.root.Position })
	end
end

-- How long a Frost ball's hit freezes (PowerDefinitions Frost.FreezeTime).
function PowerService.freezeTime(): number
	return (PowerDefinitions.get("Frost") :: any).FreezeTime
end

function PowerService.isFrozen(c: any): boolean
	return c.frozenUntil ~= nil
end

-- Phantom (Blink's ultimate) ---------------------------------------------------------------------

function PowerService.endPhantom(c: any)
	if not c.phantomUntil then
		return
	end
	c.phantomUntil = nil
	if c.phantomFx then
		c.phantomFx:Destroy()
		c.phantomFx = nil
	end
	setAttr(c, "Phantom", false)
	if not c.frozenUntil then
		restoreSpeed(c)
	end
end

local function startPhantom(c: any, ult: any)
	local t = now()
	c.phantomUntil = t + ult.Duration
	c.phantomSpeed = ult.SpeedScale
	c.immuneUntil = math.max(c.immuneUntil, c.phantomUntil)
	local until_ = c.phantomUntil
	if c.character and not c.phantomFx then
		local h = Instance.new("Highlight")
		h.Name = "PowerPhantom"
		h.FillColor = Color3.fromRGB(200, 255, 240)
		h.FillTransparency = 0.45
		h.OutlineColor = Color3.fromRGB(120, 255, 200)
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = c.character
		c.phantomFx = h
	end
	setAttr(c, "Phantom", true)
	restoreSpeed(c)
	task.delay(ult.Duration, function()
		if c.phantomUntil == until_ then
			PowerService.endPhantom(c)
		end
	end)
end

-- Shield (a bubble that catches from any side; CombatService) -----------------------------------------

function PowerService.endShield(c: any)
	c.shieldUntil = nil
	if c.shieldFx then
		c.shieldFx:Destroy()
		c.shieldFx = nil
	end
end

local function startShield(c: any, duration: number)
	local root = c.root :: BasePart
	c.shieldUntil = now() + duration
	local until_ = c.shieldUntil
	if not c.shieldFx then
		local bubble = Instance.new("Part")
		bubble.Name = "PowerShield"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.one * 8
		bubble.Material = Enum.Material.ForceField
		bubble.Color = Color3.fromRGB(120, 200, 255)
		bubble.Transparency = 0.2
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.Massless = true
		bubble.CastShadow = false
		bubble.CFrame = root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = bubble
		weld.Parent = bubble
		bubble.Parent = c.character
		c.shieldFx = bubble
	end
	task.delay(duration, function()
		if c.shieldUntil == until_ then
			PowerService.endShield(c)
		end
	end)
end

-- Ghost (Decoy: hidden from homing, aim and bots; Void: balls pass through) -------------------------

function PowerService.endGhost(c: any)
	if not c.ghostUntil then
		return
	end
	c.ghostUntil = nil
	c.hiddenUntil = nil
	if c.character then
		c.character:SetAttribute("Hidden", nil)
	end
	for inst, was in c.ghostSaved or {} do
		if inst.Parent then
			(inst :: any).Transparency = was
		end
	end
	c.ghostSaved = nil
end

-- Fade `c` out for `duration`. `hidden`: lost from homing, aim assist and bots (Decoy); otherwise
-- immune, so balls pass through (Void).
local function startGhost(c: any, duration: number, hidden: boolean)
	local t = now()
	PowerService.endGhost(c)
	c.ghostUntil = t + duration
	local until_ = c.ghostUntil
	if hidden then
		c.hiddenUntil = c.ghostUntil
		c.character:SetAttribute("Hidden", true)
	else
		c.immuneUntil = math.max(c.immuneUntil, c.ghostUntil)
	end
	local saved = {}
	for _, d in (c.character :: Model):GetDescendants() do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Name ~= "HitProxy") or d:IsA("Decal") then
			saved[d] = (d :: any).Transparency
			if (d :: any).Transparency < 1 then
				(d :: any).Transparency = if hidden then 0.92 else 0.7
			end
		end
	end
	c.ghostSaved = saved
	task.delay(duration, function()
		if c.ghostUntil == until_ then
			PowerService.endGhost(c)
		end
	end)
end

-- Giant / Titan -------------------------------------------------------------------------------------

-- A thrown or area hit's knockback on `c` (Giant shrugs most of it off).
function PowerService.knockbackScale(c: any): number
	if c.giantUntil and now() < c.giantUntil then
		return c.giantKb or 1
	end
	return 1
end

function PowerService.endGiant(c: any)
	if not c.giantUntil then
		return
	end
	c.giantUntil = nil
	c.giantKb = nil
	c.stomp = nil
	setAttr(c, "Giant", false)
	local character = c.character
	if not character then
		return
	end
	-- shrinking mid-tumble would fight the ragdoll: wait until they're up (or gone)
	task.spawn(function()
		for _ = 1, 25 do
			if character.Parent == nil or not S.RagdollService.isRagdolled(character) then
				break
			end
			task.wait(0.2)
		end
		if character.Parent and not c.giantUntil then
			pcall(function()
				character:ScaleTo(1)
			end)
		end
	end)
end

local function startGiant(c: any, scale: number, kb: number, duration: number, stomp: any?)
	local character = c.character :: Model
	c.giantUntil = now() + duration
	c.giantKb = kb
	c.stomp = stomp
	local until_ = c.giantUntil
	pcall(function()
		character:ScaleTo(scale)
	end)
	setAttr(c, "Giant", true)
	task.delay(duration, function()
		if c.giantUntil == until_ then
			PowerService.endGiant(c)
		end
	end)
end

-- Tether (Grapple's ultimate) -------------------------------------------------------------------------

function PowerService.endTether(c: any)
	local other = c.tetherWith
	c.tetherWith = nil
	c.tetherUntil = nil
	if c.tetherFx then
		for _, inst in c.tetherFx do
			inst:Destroy()
		end
		c.tetherFx = nil
	end
	if other and other.tetherWith == c then
		PowerService.endTether(other)
	end
end

local function tether(a: any, b: any, duration: number)
	PowerService.endTether(a)
	PowerService.endTether(b)
	local until_ = now() + duration
	a.tetherWith, b.tetherWith = b, a
	a.tetherUntil, b.tetherUntil = until_, until_
	local a0 = Instance.new("Attachment")
	a0.Name = "PowerTether"
	a0.Parent = a.root
	local a1 = Instance.new("Attachment")
	a1.Name = "PowerTether"
	a1.Parent = b.root
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.fromRGB(230, 180, 110))
	beam.Width0, beam.Width1 = 0.5, 0.5
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.Segments = 12
	beam.CurveSize0, beam.CurveSize1 = 2, -2
	beam.Parent = a0
	a.tetherFx = { a0, a1 }
	task.delay(duration, function()
		if a.tetherUntil == until_ then
			PowerService.endTether(a)
		end
	end)
end

-- CombatService: `target` was just launched by a thrown hit. A tethered partner goes flying too.
function PowerService.onLaunched(thrower: any?, target: any, vel: Vector3, damage: number, ballType: string)
	local other = target.tetherWith
	if not thrower or not other or not target.tetherUntil or now() >= target.tetherUntil then
		return
	end
	PowerService.endTether(target)
	if other.root and alive(other) and other.status == "Active" then
		local flat = Vector3.new(vel.X, 0, vel.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
		S.CombatService.areaHit(thrower, other, other.root.Position, dir, damage, ballType)
		S.NetService.broadcast(
			"PowerFx",
			{ kind = "Snap", from = target.root and target.root.Position, to = other.root.Position }
		)
	end
end

-- Walls (Shield's ultimate) ---------------------------------------------------------------------------

local walls: { { part: BasePart, team: string, owner: any } } = {}
local wallFolder: Folder? = nil

-- The walls that stop a ball thrown by `team` (every other team's).
function PowerService.wallsAgainst(team: string?): { Instance }
	local list = {}
	if not team then
		return list
	end
	for _, w in walls do
		if w.team ~= team and w.part.Parent then
			table.insert(list, w.part)
		end
	end
	return list
end

local function removeWall(part: BasePart)
	for i, w in walls do
		if w.part == part then
			table.remove(walls, i)
			break
		end
	end
	part:Destroy()
end

local function raiseWall(c: any, duration: number)
	if not wallFolder then
		local f = Instance.new("Folder")
		f.Name = "PowerWalls"
		f.Parent = Workspace
		wallFolder = f
	end
	local o = Config.Arena.Origin
	local sign = ArenaLayout.teamSign(c.team)
	local team = Config.Teams[c.team]
	local wall = Instance.new("Part")
	wall.Name = "PowerWall"
	wall.Anchored = true
	wall.CanCollide = false -- players walk through; only enemy balls stop (BallService sweeps)
	wall.CanTouch = false
	wall.CanQuery = true
	wall.CastShadow = false
	wall.Material = Enum.Material.ForceField
	wall.Color = if team then team.Color else Color3.fromRGB(120, 200, 255)
	wall.Transparency = 0.15
	wall.Size = Vector3.new(Config.Arena.CourtWidth + 6, 14, 1.5)
	wall.CFrame = CFrame.new(o.X, o.Y + 7, o.Z + sign * 3)
	wall.Parent = wallFolder
	table.insert(walls, { part = wall :: BasePart, team = c.team, owner = c })
	task.delay(duration, function()
		if wall.Parent then
			removeWall(wall)
		end
	end)
end

-- Rewind ----------------------------------------------------------------------------------------------

-- Record where `c` is (on their own half, upright) for Rewind: the last 4 s, every tick.
local function remember(c: any, t: number)
	local root = c.root
	if not root or ragdolled(c) or c.status ~= "Active" or not c.team then
		return
	end
	local pos = root.Position
	if
		not ArenaLayout.onHalf(c.team, pos, S.ArenaService.getOvertimeSteps(), 1)
		or pos.Y < ArenaLayout.SurfaceY - 2
	then
		return
	end
	local h = c.history
	if not h then
		h = {}
		c.history = h
	end
	table.insert(h, { t = t, pos = pos, damage = c.damage })
	while #h > 18 do
		table.remove(h, 1)
	end
end

-- Send `c` back to where they were `seconds` ago with the damage % they had then (never more than
-- now). Works mid-tumble. Returns whether there was somewhere to go.
local function rewind(c: any, seconds: number): boolean
	local h = c.history
	if not h or #h == 0 or not c.root then
		return false
	end
	local t = now()
	local pick = nil
	for _, e in h do
		if e.t <= t - seconds then
			pick = e -- the latest one at least `seconds` old
		end
	end
	pick = pick or h[1]
	if t - pick.t < 0.75 then
		return false
	end
	local from = c.root.Position
	local look = c.root.CFrame.LookVector
	S.PowerService.unfreeze(c)
	S.CharacterService.teleport(c, pick.pos, pick.pos + Vector3.new(look.X, 0, look.Z))
	if c.action == "Ragdolled" then
		S.PlayerStateService.setAction(c, "Idle")
	end
	S.PlayerStateService.setDamage(c, math.min(c.damage, pick.damage))
	c.immuneUntil = math.max(c.immuneUntil, t + 0.5)
	c.history = {}
	S.NetService.broadcast("PowerFx", { kind = "Rewind", from = from, to = pick.pos })
	return true
end

-- Every timed power effect off (a round reset, an elimination, leaving the match).
function PowerService.clearEffects(c: any)
	PowerService.unfreeze(c)
	PowerService.endPhantom(c)
	PowerService.endShield(c)
	PowerService.endGhost(c)
	PowerService.endGiant(c)
	PowerService.endTether(c)
	for i = #walls, 1, -1 do
		if walls[i].owner == c then
			removeWall(walls[i].part)
		end
	end
end

-- Court helpers ----------------------------------------------------------------------------------

-- The nearest point to `pos` on c's own half, `margin` studs in from the edges and the centre line.
local function clampToHalf(c: any, pos: Vector3, margin: number): Vector3
	local o = Config.Arena.Origin
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps()) - margin
	local sign = ArenaLayout.teamSign(c.team)
	local rel = pos - o
	local x = math.clamp(rel.X, -hw, hw)
	local z = sign * math.clamp(rel.Z * sign, margin, ArenaLayout.HalfLength - margin)
	return Vector3.new(o.X + x, pos.Y, o.Z + z)
end

local function enemiesOf(c: any): { any }
	local list = {}
	for _, e in S.MatchService.roster() do
		if e.inMatch and e.status == "Active" and e.team and e.team ~= c.team and alive(e) then
			table.insert(list, e)
		end
	end
	return list
end

-- The enemy of `c` nearest `pos` within `range` (not `skip`, not immune or hidden).
local function nearestEnemy(c: any, pos: Vector3, range: number, skip: any?): any?
	local t = now()
	local best, bestD = nil, range
	for _, e in enemiesOf(c) do
		if e ~= skip and e.root and t >= e.immuneUntil and not (e.hiddenUntil and t < e.hiddenUntil) then
			local d = (e.root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = e, d
			end
		end
	end
	return best
end

-- A lob from `from` that lands on `to`, `speed` studs/s along the ground under `gravity`.
local function lob(from: Vector3, to: Vector3, speed: number, gravity: number): Vector3
	local d = to - from
	local flat = Vector3.new(d.X, 0, d.Z)
	local dist = math.max(flat.Magnitude, 1)
	local time = dist / speed
	local vy = d.Y / time + 0.5 * gravity * time
	return flat.Unit * speed + Vector3.new(0, vy, 0)
end

-- Knock every enemy of `owner` within `radius` of `pos` (but `skip`) away (`upward` for straight up)
-- with an area hit (CombatService.areaHit).
local function blast(
	owner: any,
	pos: Vector3,
	radius: number,
	damage: number,
	ballType: string,
	upward: boolean,
	skip: any?
)
	for _, e in enemiesOf(owner) do
		if e ~= skip and e.root then
			local to = e.root.Position - pos
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude <= radius and math.abs(to.Y) < radius then
				local dir = if upward
					then Vector3.new(flat.X * 0.15, 0, flat.Z * 0.15) + Vector3.yAxis * 0.01
					elseif flat.Magnitude > 0.5 then flat.Unit
					else Vector3.zAxis
				S.CombatService.areaHit(owner, e, pos, dir, damage, ballType)
			end
		end
	end
end

-- Actives ----------------------------------------------------------------------------------------

local function useBall(c: any, def: any): (boolean, string?)
	local ball = c.heldBall
	if not ball or ball.context ~= "Match" then
		return false, "Grab a ball first!"
	end
	if ball.power then
		return false, "Your ball is already powered up"
	end
	S.BallService.setType(ball, def.Ball)
	setAttr(c, "HeldBall", def.Ball)
	return true, nil
end

local function useBlink(c: any, def: any, dir: Vector3?): (boolean, string?)
	local root = c.root :: BasePart
	local look = root.CFrame.LookVector
	local d = dir or Vector3.new(look.X, 0, look.Z)
	if d.Magnitude < 0.1 then
		d = Vector3.zAxis
	end
	local from = root.Position
	local to = clampToHalf(c, from + d.Unit * def.Distance, 3)
	local character = c.character :: Model
	character:PivotTo(CFrame.new(to) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	c.immuneUntil = math.max(c.immuneUntil, now() + def.Immunity)
	S.NetService.broadcast("PowerFx", { kind = "Blink", from = from, to = to })
	return true, nil
end

local function useMagnet(c: any, def: any): (boolean, string?)
	if c.heldBall then
		return false, "Your hands are full"
	end
	if c.action ~= "Idle" and c.action ~= "Dodging" and c.action ~= "Recovering" then
		return false, nil
	end
	local root = c.root :: BasePart
	local best, bestD = nil, def.Range
	for _, ball in S.BallService.all() do
		if ball.context == "Match" and (ball.state == "Resting" or ball.state == "Spent") and not ball.holder then
			local pos = ball.part.Position
			local d = (pos - root.Position).Magnitude
			if d < bestD and ArenaLayout.onHalf(c.team, pos, 0, -2) then
				best, bestD = ball, d
			end
		end
	end
	if not best then
		return false, "No loose ball on your side"
	end
	local from = best.part.Position
	S.BallService.give(best, c)
	S.CombatService.onPickup(c, best)
	S.NetService.broadcast("PowerFx", { kind = "Magnet", from = from, to = root.Position })
	return true, nil
end

local function useShield(c: any, def: any): (boolean, string?)
	startShield(c, def.Duration)
	return true, nil
end

local function useGrapple(c: any, def: any): (boolean, string?)
	local root = c.root :: BasePart
	local target = nearestEnemy(c, root.Position, def.Range, nil)
	if not target or ragdolled(target) then
		return false, "No enemy in reach"
	end
	local sign = ArenaLayout.teamSign(target.team)
	local depth = (target.root.Position - Config.Arena.Origin).Z * sign -- studs from the centre line
	if depth < 14 then
		return false, "They're already at the line"
	end
	-- a short yank that never carries them across the line (a body over the wrong half can't stand up)
	local dir = Vector3.new(0, 0, -sign)
	local pull = math.min(def.Pull, (depth - 8) * 1.1)
	S.CombatService.areaHit(c, target, target.root.Position, dir, 0, "Standard", dir * pull + Vector3.new(0, 16, 0))
	S.NetService.broadcast("PowerFx", { kind = "Grapple", from = root.Position, to = target.root.Position })
	return true, nil
end

local function useDecoy(c: any, def: any): (boolean, string?)
	local root = c.root :: BasePart
	S.NetService.broadcast("PowerFx", { kind = "Decoy", position = root.Position, caster = c.character })
	startGhost(c, def.Duration, true)
	return true, nil
end

local function useGiant(c: any, def: any): (boolean, string?)
	if c.giantUntil then
		return false, "You're already huge"
	end
	startGiant(c, def.Scale, def.KnockbackScale, def.Duration, nil)
	S.NetService.broadcast("PowerFx", { kind = "Grow", position = c.root.Position })
	return true, nil
end

local function useRewind(c: any, def: any): (boolean, string?)
	if not rewind(c, def.Seconds) then
		return false, "Nothing to rewind to yet"
	end
	return true, nil
end

local function useVoid(c: any, def: any): (boolean, string?)
	startGhost(c, def.Duration, false)
	S.NetService.broadcast("PowerFx", { kind = "Phase", position = c.root.Position })
	return true, nil
end

local SELF_ACTIVES: { [string]: (any, any) -> (boolean, string?) } = {
	Magnet = useMagnet,
	Shield = useShield,
	Grapple = useGrapple,
	Decoy = useDecoy,
	Giant = useGiant,
	Rewind = useRewind,
	Void = useVoid,
}

-- Use slot `slot`'s active. `dir` is the move direction (Blink). Returns whether it fired.
function PowerService.use(c: any, slot: number, dir: Vector3?): boolean
	if not inLiveMatch(c) or not alive(c) or c.frozenUntil then
		return false
	end
	if c.action == "Casting" then
		return false
	end
	local id = PowerService.powersOf(c)[slot]
	local def = PowerDefinitions.get(id)
	if not def or (ragdolled(c) and not def.WhileRagdolled) then
		return false
	end
	local t = now()
	if t < (c.powerReadyAt[slot] or 0) then
		return false
	end
	local ok, why
	if def.Kind == "Ball" then
		ok, why = useBall(c, def)
	elseif def.Id == "Blink" then
		ok, why = useBlink(c, def, dir)
	elseif SELF_ACTIVES[def.Id] then
		ok, why = SELF_ACTIVES[def.Id](c, def)
	end
	if not ok then
		if why then
			tell(c, why)
		end
		return false
	end
	c.powerReadyAt[slot] = t + PowerService.cooldownFor(c, slot)
	setAttr(c, "PowerReadyAt" .. slot, c.powerReadyAt[slot])
	S.NetService.broadcast("PowerFx", {
		kind = "Active",
		power = def.Id,
		caster = c.character,
		position = c.root and c.root.Position,
	})
	S.AnalyticsService.event(c, "PowerUse_" .. def.Id)
	PowerService.gainMastery(c, MASTERY.XP.Active)
	return true
end

-- Ultimates --------------------------------------------------------------------------------------

local function stormBalls(c: any, ult: any)
	local o = Config.Arena.Origin
	local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps()) - 6
	local sign = ArenaLayout.teamSign(c.team)
	for i = 1, ult.Count do
		task.delay((i - 1) * 0.12, function()
			if not S.MatchService.isRoundLive() then
				return
			end
			local x = rng:NextNumber(-hw, hw)
			local z = sign * rng:NextNumber(8, ArenaLayout.HalfLength - 8)
			local ball = S.BallService.spawn("Standard", Vector3.new(o.X + x, o.Y + 28, o.Z + z), "Match", true)
			ball.temporary = true
			ball.expiresAt = now() + PW.ExtraBallLife + 3
		end)
	end
end

-- Black Hole: a vortex just past the enemy back line, pulling them toward it in pulses.
local function blackHole(c: any, ult: any)
	local o = Config.Arena.Origin
	local enemySign = -ArenaLayout.teamSign(c.team)
	local point = o + Vector3.new(0, 3, enemySign * (ArenaLayout.HalfLength + 4))
	S.NetService.broadcast(
		"PowerFx",
		{ kind = "Vortex", position = point, duration = ult.Duration, radius = ult.Radius }
	)
	for i = 1, ult.Pulses do
		task.delay((i - 0.5) * ult.Duration / ult.Pulses, function()
			if not S.MatchService.isRoundLive() then
				return
			end
			for _, e in enemiesOf(c) do
				if e.root then
					local to = point - e.root.Position
					local flat = Vector3.new(to.X, 0, to.Z)
					if flat.Magnitude <= ult.Radius and flat.Magnitude > 0.5 then
						S.CombatService.areaHit(c, e, point, flat.Unit, ult.Damage, "Standard")
					end
				end
			end
		end)
	end
end

-- Edge Collapse: every second, anyone of the enemy team within Band of their side or back edge is
-- flung outward.
local function edgeCollapse(c: any, ult: any)
	local enemyTeam = if c.team == "Red" then "Blue" else "Red"
	local sign = ArenaLayout.teamSign(enemyTeam)
	S.NetService.broadcast(
		"PowerFx",
		{ kind = "EdgeCollapse", team = enemyTeam, band = ult.Band, duration = ult.Duration }
	)
	for i = 1, math.floor(ult.Duration) do
		task.delay(i - 0.2, function()
			if not S.MatchService.isRoundLive() then
				return
			end
			local hw = ArenaLayout.safeHalfWidth(S.ArenaService.getOvertimeSteps())
			for _, e in enemiesOf(c) do
				if e.root then
					local rel = e.root.Position - Config.Arena.Origin
					local side = hw - math.abs(rel.X)
					local back = ArenaLayout.HalfLength - rel.Z * sign
					if math.min(side, back) < ult.Band then
						local dir = if side < back then Vector3.new(math.sign(rel.X), 0, 0) else Vector3.new(0, 0, sign)
						S.CombatService.areaHit(c, e, e.root.Position, dir, ult.Damage, "Heavy")
					end
				end
			end
			S.NetService.broadcast("PowerFx", { kind = "EdgePulse", team = enemyTeam, band = ult.Band })
		end)
	end
end

local function stormCloud(c: any, ult: any)
	for i = 1, ult.Strikes do
		task.delay((i - 1) * ult.Duration / ult.Strikes, function()
			if not S.MatchService.isRoundLive() then
				return
			end
			local list = {}
			local t = now()
			for _, e in enemiesOf(c) do
				if t >= e.immuneUntil and e.root then
					table.insert(list, e)
				end
			end
			local e = list[rng:NextInteger(1, math.max(#list, 1))]
			if e then
				local pos = e.root.Position
				S.NetService.broadcast("PowerFx", { kind = "Lightning", position = pos })
				S.CombatService.areaHit(c, e, pos, Vector3.new(0, 0, 0.01), ult.Damage, "Pop")
			end
		end)
	end
end

local function mirrorSquad(c: any, ult: any)
	local root = c.root :: BasePart
	local enemies = enemiesOf(c)
	table.sort(enemies, function(a, b)
		return (a.root.Position - root.Position).Magnitude < (b.root.Position - root.Position).Magnitude
	end)
	if #enemies == 0 then
		return
	end
	local offsets = { Vector3.new(-6, 0, 0), Vector3.new(6, 0, 0), Vector3.new(0, 0, 6) }
	local spots = {}
	for i = 1, ult.Count do
		local spot = (root.CFrame * CFrame.new(offsets[(i - 1) % #offsets + 1])).Position
		spot = clampToHalf(c, spot, 2) + Vector3.new(0, Config.Ball.SpawnUp, 0)
		table.insert(spots, spot)
		local target = enemies[(i - 1) % #enemies + 1]
		local to = target.root.Position - spot
		local vel = (to.Unit + Vector3.new(0, 0.12, 0)).Unit * Config.Player.ThrowSpeed
		local ball = S.BallService.fireFrom(c, "Standard", vel, spot)
		if ball then
			S.BallService.boostHoming(ball, 90, 45, target)
		end
	end
	S.NetService.broadcast("PowerFx", { kind = "Mirror", positions = spots, caster = c.character })
end

-- After the wind-up: the self ultimates take effect (the ball ones powered the ball at once).
local function ultEffect(c: any, def: any)
	local ult = def.Ult
	if not inLiveMatch(c) or not alive(c) then
		return
	end
	if ult.Id == "Phantom" then
		startPhantom(c, ult)
	elseif ult.Id == "BallStorm" then
		stormBalls(c, ult)
	elseif ult.Id == "TimeStop" then
		for _, e in enemiesOf(c) do
			if not e.phantomUntil then -- a phantom is out of time's reach
				PowerService.freeze(e, ult.Duration)
			end
		end
	elseif ult.Id == "Fortress" then
		raiseWall(c, ult.Duration)
	elseif ult.Id == "Tether" then
		local root = c.root :: BasePart
		local first = nearestEnemy(c, root.Position, 400, nil)
		local second = first and nearestEnemy(c, first.root.Position, 400, first)
		if first and second then
			tether(first, second, ult.Duration)
		end
	elseif ult.Id == "MirrorSquad" then
		mirrorSquad(c, ult)
	elseif ult.Id == "BlackHole" then
		blackHole(c, ult)
	elseif ult.Id == "Titan" then
		PowerService.endGiant(c)
		startGiant(c, ult.Scale, ult.KnockbackScale, ult.Duration, {
			every = ult.StompEvery,
			radius = ult.StompRadius,
			damage = ult.StompDamage,
			nextAt = now(),
		})
	elseif ult.Id == "StormCloud" then
		stormCloud(c, ult)
	elseif ult.Id == "Replay" then
		for _, m in S.MatchService.roster() do
			if m.inMatch and m.team == c.team and m.status == "Active" and alive(m) then
				rewind(m, 3)
			end
		end
	elseif ult.Id == "EdgeCollapse" then
		edgeCollapse(c, ult)
	end
	S.NetService.broadcast("PowerFx", { kind = "UltEffect", ult = ult.Id, caster = c.character, team = c.team })
end

function PowerService.useUltimate(c: any): boolean
	if not inLiveMatch(c) or not alive(c) or c.frozenUntil then
		return false
	end
	if (c.ult or 0) < M.Max then
		return false
	end
	local def = PowerDefinitions.get(PowerService.powersOf(c)[1])
	if not def then
		return false
	end
	local ult = def.Ult
	local tumbling = ragdolled(c)
	if tumbling and not ult.WhileRagdolled then
		return false
	end
	if not tumbling and c.action ~= "Idle" and c.action ~= "Charging" and c.action ~= "Recovering" then
		return false
	end
	if ult.NeedsBall then
		local ball = c.heldBall
		if not ball or ball.context ~= "Match" then
			tell(c, "Grab a ball first!")
			return false
		end
		ball.power = { ult = ult.Id, owner = c, bounces = ult.Bounces }
		local ballType = ult.BallType or "Rocket"
		S.BallService.setType(ball, ballType)
		setAttr(c, "HeldBall", ballType)
	end
	local t = now()
	c.ult = 0
	setAttr(c, "UltCharge", 0)
	c.botUltAt = nil
	c.chargeStart = nil
	-- the wind-up: untouchable and still for a beat while the camera pushes in
	c.ultCastUntil = t + PW.UltWindup
	c.immuneUntil = math.max(c.immuneUntil, t + PW.UltWindup)
	if not tumbling then -- (a tumbling caster stays ragdolled: their recovery waits on that action)
		S.PlayerStateService.setAction(c, "Casting", PW.UltWindup)
	end
	S.NetService.broadcast("PowerFx", {
		kind = "Ult",
		ult = ult.Id,
		name = ult.Name,
		power = def.Id,
		caster = c.character,
		casterPlayer = c.player,
		casterName = c.name,
		team = c.team,
		windup = PW.UltWindup,
		mastered = PowerService.masteryLevel(c, def.Id) >= MASTERY.MaxLevel,
	})
	S.MatchService.feed(("%s ⚡ used <b>%s</b>!"):format(S.MatchService.tag(c), ult.Name))
	S.AnalyticsService.event(c, "UltUse_" .. ult.Id)
	PowerService.gainMastery(c, MASTERY.XP.Ult)
	if not ult.NeedsBall then
		task.delay(PW.UltWindup, ultEffect, c, def)
	end
	return true
end

-- Ultimate balls -----------------------------------------------------------------------------------

-- Called right after `ball` was thrown by `c` (CombatService.doThrow). Barrage splits off extra
-- homing rockets, one at each other enemy.
function PowerService.onLaunch(c: any, ball: any)
	local power = ball.power
	if ball.type == "Curve" then
		-- Curve (and Boomerang): bend hard onto the target, or the nearest enemy ahead
		local def = PowerDefinitions.get("Curve") :: any
		local target = ball.homing or nearestEnemy(c, ball.pos + ball.vel.Unit * 30, 70, nil)
		S.BallService.boostHoming(ball, def.TurnDegPerSec, def.MaxTurnDeg, target)
		return
	end
	if not power or power.ult ~= "Barrage" then
		return
	end
	local ult = (PowerDefinitions.get("Rocket") :: any).Ult
	local main = ball.homing
	S.BallService.boostHoming(ball, ult.TurnDegPerSec, ult.MaxTurnDeg, main)
	local others = {}
	for _, e in enemiesOf(c) do
		if e ~= main then
			table.insert(others, e)
		end
	end
	local speed = ball.vel.Magnitude
	for i = 1, ult.Extra do
		local target = others[i]
		local spread = CFrame.Angles(0, math.rad(if i % 2 == 1 then 18 else -18) * math.ceil(i / 2), 0)
		local vel = spread:VectorToWorldSpace(ball.vel)
		if target and target.root then
			local to = target.root.Position - ball.pos
			vel = (to.Unit + Vector3.new(0, 0.12, 0)).Unit * speed
		end
		local extra = S.BallService.fireExtra(c, "Rocket", vel)
		if extra then
			S.BallService.boostHoming(extra, ult.TurnDegPerSec, ult.MaxTurnDeg, target)
		end
	end
	ball.power = nil -- the main rocket is a normal (strongly homing) rocket from here
end

-- Bounce / Pinball: send the ball on to the next enemy near where it landed.
local function bounceOn(ball: any, owner: any, pos: Vector3, skip: any?, left: number)
	local def = PowerDefinitions.get("Bounce") :: any
	local target = nearestEnemy(owner, pos, def.Range, skip)
	if not target or not target.root then
		return
	end
	task.delay(0.08, function()
		if ball.state ~= "Spent" or ball.holder or not S.MatchService.isRoundLive() or not target.root then
			return
		end
		local more = left - 1
		S.BallService.setType(ball, if more > 0 then "Bounce" else "Standard")
		local from = pos + Vector3.new(0, 2.5, 0)
		local vel = lob(from, target.root.Position, 95, ProjectileMath.gravity(ball.type))
		if S.BallService.relaunch(ball, owner, from, vel) then
			S.BallService.boostHoming(ball, 120, 60, target)
			if more > 0 then
				ball.power = { ult = "Pinball", owner = owner, bounces = more }
			end
			S.NetService.broadcast("PowerFx", { kind = "Bounce", position = pos })
		end
	end)
end

-- A power ball landed: on a target (`target`) or on the court / scenery (nil). `ballType` and
-- `power` are what it was before it landed (spend has already reset the ball). The ball's own hit
-- has already been applied; this adds each power's effect.
function PowerService.onImpact(ball: any, ballType: string, power: any?, thrower: any?, pos: Vector3, target: any?)
	local owner = if power then power.owner else thrower
	if not owner or not owner.team or not S.MatchService.isRoundLive() then
		return
	end
	if power and power.ult == "Pinball" then
		bounceOn(ball, owner, pos, target, power.bounces or 1)
		return
	elseif power and power.ult == "Boomerang" then
		local ult = (PowerDefinitions.get("Curve") :: any).Ult
		task.delay(ult.ReturnDelay, function()
			if
				S.BallService.isLive(ball)
				and (ball.state == "Spent" or ball.state == "Resting")
				and not ball.holder
				and owner.inMatch
				and owner.status == "Active"
				and alive(owner)
				and not owner.heldBall
				and not ragdolled(owner)
				and not owner.frozenUntil
			then
				local from = ball.part.Position
				S.BallService.give(ball, owner)
				S.NetService.broadcast("PowerFx", { kind = "Return", from = from, to = owner.root.Position })
			end
		end)
		return
	end
	if ballType == "Bounce" then
		bounceOn(ball, owner, pos, target, 1)
	elseif ballType == "Gravity" then
		local def = PowerDefinitions.get("Gravity") :: any
		for _, e in enemiesOf(owner) do
			if e ~= target and e.root then
				local to = pos - e.root.Position
				local flat = Vector3.new(to.X, 0, to.Z)
				if flat.Magnitude <= def.Radius and flat.Magnitude > 1 then
					local dir = flat.Unit
					S.CombatService.areaHit(
						owner,
						e,
						pos,
						dir,
						def.Damage,
						"Standard",
						dir * 26 + Vector3.new(0, 10, 0)
					)
				end
			end
		end
		S.NetService.broadcast("PowerFx", { kind = "GravityPull", position = pos, radius = def.Radius })
	elseif ballType == "Thunder" and target and target.root then
		local def = PowerDefinitions.get("Thunder") :: any
		local hits = {}
		local skip = target
		local from = target.root.Position
		for _ = 1, def.Chains do
			local e = nearestEnemy(owner, from, def.ChainRange, skip)
			if not e or table.find(hits, e) then
				break
			end
			table.insert(hits, e)
			local to = e.root.Position
			local away = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
			S.CombatService.areaHit(
				owner,
				e,
				from,
				if away.Magnitude > 0.5 then away.Unit else Vector3.zAxis,
				def.ChainDamage,
				"Standard"
			)
			S.NetService.broadcast("PowerFx", { kind = "Chain", from = from, to = to })
			skip = e
			from = to
		end
	end
	if not power then
		return
	end
	if power.ult == "Meteor" then
		local ult = (PowerDefinitions.get("Heavy") :: any).Ult
		blast(owner, pos, ult.ShockRadius, ult.ShockDamage, "Heavy", false, target)
		S.NetService.broadcast("PowerFx", { kind = "Shockwave", position = pos, radius = ult.ShockRadius })
	elseif power.ult == "Geyser" then
		local ult = (PowerDefinitions.get("Pop") :: any).Ult
		blast(owner, pos, ult.Radius, ult.Damage, "Pop", true, target)
		S.NetService.broadcast("PowerFx", { kind = "Geyser", position = pos, radius = ult.Radius })
	end
end

-- Bots -------------------------------------------------------------------------------------------

local function incomingBall(c: any): any?
	local root = c.root
	if not root then
		return nil
	end
	for _, ball in S.BallService.all() do
		if ball.state == "InFlight" and ball.context == "Match" and ball.lastTeam ~= c.team then
			local to = root.Position - ball.pos
			if to.Magnitude < 24 and ball.vel:Dot(to) > 0 then
				return ball
			end
		end
	end
	return nil
end

local function botThink(c: any, t: number)
	if not inLiveMatch(c) or not alive(c) or c.frozenUntil then
		return
	end
	local id = PowerService.powersOf(c)[1]
	local def = PowerDefinitions.get(id)
	if not def then
		return
	end
	if ragdolled(c) then
		-- only Rewind works mid-tumble: worth it once the tumble is a dangerous one
		if def.WhileRagdolled and c.damage >= 50 and t >= (c.powerReadyAt[1] or 0) then
			PowerService.use(c, 1)
		end
		return
	end
	if c.botUltAt and t >= c.botUltAt and (c.ult or 0) >= M.Max then
		if not def.Ult.NeedsBall or c.heldBall then
			PowerService.useUltimate(c)
			return
		end
	end
	if t < (c.powerReadyAt[1] or 0) or rng:NextNumber() > PW.BotUseChance then
		return
	end
	if def.Kind == "Ball" then
		if c.heldBall and not c.heldBall.power and c.heldBall.type == "Standard" then
			PowerService.use(c, 1)
		end
	elseif def.Id == "Blink" then
		local ball = incomingBall(c)
		if ball then
			local side = ball.vel:Cross(Vector3.yAxis)
			PowerService.use(c, 1, if rng:NextNumber() < 0.5 then side else -side)
		end
	elseif def.Id == "Magnet" then
		if not c.heldBall then
			PowerService.use(c, 1)
		end
	elseif def.Id == "Shield" or def.Id == "Decoy" or def.Id == "Void" then
		if incomingBall(c) then
			PowerService.use(c, 1)
		end
	elseif def.Id == "Grapple" or def.Id == "Giant" then
		PowerService.use(c, 1)
	end
end

-- Every 0.25 s: the meter's trickle, bot decisions, and extra balls that have lain around too long.
function PowerService.tick(dt: number)
	local t = now()
	if S.MatchService.isRoundLive() then
		for _, c in S.MatchService.roster() do
			if c.inMatch and c.status == "Active" then
				if not c.powers then
					PowerService.reset(c)
				end
				PowerService.addMeter(c, M.Passive * dt)
				remember(c, t)
				local stomp = c.stomp
				if stomp and c.giantUntil and t >= stomp.nextAt and c.root and not ragdolled(c) then
					local v = c.root.AssemblyLinearVelocity
					if Vector3.new(v.X, 0, v.Z).Magnitude > 3 then
						stomp.nextAt = t + stomp.every
						blast(c, c.root.Position, stomp.radius, stomp.damage, "Heavy", false, nil)
						S.NetService.broadcast(
							"PowerFx",
							{ kind = "Stomp", position = c.root.Position, radius = stomp.radius }
						)
					end
				end
				if c.isBot then
					botThink(c, t)
				end
			end
		end
	end
	for _, ball in S.BallService.all() do
		if
			ball.temporary
			and ball.expiresAt
			and t >= ball.expiresAt
			and (ball.state == "Resting" or ball.state == "Spent")
			and not ball.holder
		then
			S.NetService.broadcast("PowerFx", { kind = "Poof", position = ball.part.Position })
			S.BallService.destroy(ball)
		end
	end
end

function PowerService.start()
	local PS = S.PlayerStateService
	S.NetService.on(NetSchema.Actions.UsePower, function(player, p)
		local c = PS.get(player)
		if c then
			if p.slot == 2 and #PowerService.powersOf(c) < 2 then
				return
			end
			PowerService.use(c, p.slot, p.dir)
		end
	end)
	S.NetService.on(NetSchema.Actions.UseUltimate, function(player, _p)
		local c = PS.get(player)
		if c then
			PowerService.useUltimate(c)
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local n = os.clock()
			PowerService.tick(n - last)
			last = n
		end
	end)
end

return PowerService
