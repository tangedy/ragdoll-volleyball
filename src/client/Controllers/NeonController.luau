--!strict
-- Global neon intensity (client only). Every Neon part in the Workspace shows its color scaled by
-- Config.Visuals.NeonIntensity: court rims and curtains, the hub, effects, power balls, team bands,
-- finishers. Parts that change color later (server rim pulses, warning strips, tweens) are re-scaled
-- on each change. The glow panels (light curtains, signs) and lights of the arena and hub are
-- dimmed by the same factor. A folder with a NeonScale attribute (finisher effects) dims its neon
-- and lights by that much more. Nothing on the server changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local NeonController = {}

local K = Config.Visuals.NeonIntensity
local ATTR = "NeonShown" -- the dimmed color we last applied (clones carry it, so never dim twice)
local watched: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Extra dimming from an enclosing NeonScale folder (1 when there's none).
local function extraScale(d: Instance): number
	local f = d:FindFirstAncestor("FinisherFX")
	local s = f and f:GetAttribute("NeonScale")
	return if type(s) == "number" then s else 1
end

local function scale(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local busy = false
local function apply(p: BasePart)
	if busy or p.Material ~= Enum.Material.Neon then
		return
	end
	if p:GetAttribute(ATTR) == p.Color then
		return -- already showing the dimmed color
	end
	busy = true -- our own write fires Color-changed (immediately or deferred)
	p.Color = scale(p.Color, K * extraScale(p))
	-- remember the color as stored (part colors are 8-bit), so the check above matches exactly
	p:SetAttribute(ATTR, p.Color)
	busy = false
end

-- Color is only watched once a part is (or becomes) Neon: most of the map never is, and two
-- signals on every part in the Workspace adds up.
local colorWatched: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function watchColor(p: BasePart)
	if colorWatched[p] or p.Material ~= Enum.Material.Neon then
		return
	end
	colorWatched[p] = true
	p:GetPropertyChangedSignal("Color"):Connect(function()
		apply(p)
	end)
end

local function watch(p: BasePart)
	if watched[p] then
		return
	end
	watched[p] = true
	apply(p)
	watchColor(p)
	p:GetPropertyChangedSignal("Material"):Connect(function()
		watchColor(p)
		apply(p)
	end)
end

-- Glow panels and lights in the built scenery: scaled once.
local function dimGlow(d: Instance)
	if d:GetAttribute("GlowDimmed") then
		return
	end
	local glow = (d:IsA("SurfaceGui") and d.LightInfluence == 0)
		or d:IsA("PointLight")
		or d:IsA("SurfaceLight")
		or d:IsA("SpotLight")
	if glow then
		d:SetAttribute("GlowDimmed", true);
		(d :: any).Brightness *= K
	end
end

-- Lights inside a NeonScale folder: dimmed by its factor, and again whenever the effect sets a new
-- brightness. Brightness is stored as a float, so we remember the value as read back.
local LIGHT_ATTR = "BrightnessShown"
local function dimLight(l: Light, k: number)
	local function apply()
		if l:GetAttribute(LIGHT_ATTR) == l.Brightness then
			return
		end
		l.Brightness *= k
		l:SetAttribute(LIGHT_ATTR, l.Brightness)
	end
	apply()
	l:GetPropertyChangedSignal("Brightness"):Connect(apply)
end

local function onDescendant(d: Instance)
	if d:IsA("BasePart") then
		watch(d)
	elseif d:IsA("Light") then
		local k = extraScale(d)
		if k < 1 then
			dimLight(d, k)
		end
	end
end

local function scenery(root: Instance)
	for _, d in root:GetDescendants() do
		dimGlow(d)
	end
	root.DescendantAdded:Connect(dimGlow)
end

function NeonController.init() end

function NeonController.start()
	if K >= 1 then
		return
	end
	for _, d in Workspace:GetDescendants() do
		onDescendant(d)
	end
	Workspace.DescendantAdded:Connect(onDescendant)
	for _, name in { "Arena", "Lobby" } do
		task.spawn(function()
			local root = Workspace:WaitForChild(name, 30)
			if root then
				scenery(root)
				-- the hub folder is taken out of the Workspace while you're on the court
				if name == "Lobby" then
					for _, d in root:GetDescendants() do
						onDescendant(d)
					end
					root.DescendantAdded:Connect(onDescendant)
				end
			end
		end)
	end
end

return NeonController
