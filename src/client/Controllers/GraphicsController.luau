--!strict
-- Performance mode (client only). On slower machines the expensive extras are switched off locally:
-- global shadows, sun rays, bloom, the court's rising sparkles, and the scenery's dynamic lights
-- (neon parts still glow, so the look survives). Nothing on the server changes.
--
-- It turns on by itself when the player's Roblox graphics quality is set low, or when the game has
-- run below Config.Graphics.LowFps for a while. A manual choice in ⚙ Settings always wins.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local G = Config.Graphics

local GraphicsController = {}

GraphicsController.low = false
GraphicsController.manual = false -- the player picked a mode in Settings: stop auto-detecting

local listeners: { (boolean) -> () } = {}
-- what the server (or the scenery) last asked each managed instance to be, so turning performance
-- mode off restores exactly that, even if the server changed it meanwhile (court rims toggling)
local wanted: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local writing = false

local function managed(d: Instance): boolean
	if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then
		return true
	end
	-- the court's ambient sparkles; one-shot hit bursts are parented to Terrain and stay
	return d:IsA("ParticleEmitter") and d.Name == "Sparks"
end

local function applyTo(d: Instance)
	local want = wanted[d]
	if want == nil then
		return
	end
	writing = true
	(d :: any).Enabled = want and not GraphicsController.low
	writing = false
end

local function track(d: Instance)
	if wanted[d] ~= nil or not managed(d) then
		return
	end
	local inst = d :: any
	wanted[d] = inst.Enabled
	inst:GetPropertyChangedSignal("Enabled"):Connect(function()
		if writing then
			return
		end
		wanted[d] = (d :: any).Enabled
		if GraphicsController.low and (d :: any).Enabled then
			applyTo(d)
		end
	end)
	if GraphicsController.low then
		applyTo(d)
	end
end

local function scenery(root: Instance)
	for _, d in root:GetDescendants() do
		track(d)
	end
	root.DescendantAdded:Connect(track)
end

-- Lighting extras: remember the server's values once, then toggle against them.
local lightingHome: { shadows: boolean, effects: { [Instance]: boolean } }? = nil
local function applyLighting()
	if not lightingHome then
		local effects = {}
		for _, name in { "RD_Bloom", "RD_SunRays" } do
			local e = Lighting:FindFirstChild(name)
			if e then
				effects[e] = (e :: any).Enabled
			end
		end
		lightingHome = { shadows = Lighting.GlobalShadows, effects = effects }
	end
	local home = lightingHome :: any
	local low = GraphicsController.low
	Lighting.GlobalShadows = home.shadows and not low
	for e, on in home.effects do
		(e :: any).Enabled = on and not low
	end
end

function GraphicsController.set(low: boolean, manual: boolean?)
	if manual then
		GraphicsController.manual = true
	end
	if low == GraphicsController.low then
		return
	end
	GraphicsController.low = low
	applyLighting()
	for d in wanted do
		if d.Parent then
			applyTo(d)
		end
	end
	for _, fn in listeners do
		task.spawn(fn, low)
	end
end

-- Settings toggles follow automatic switches too.
function GraphicsController.onChanged(fn: (boolean) -> ())
	table.insert(listeners, fn)
end

-- Particle counts for one-shot effects: fewer in performance mode.
function GraphicsController.particles(count: number): number
	return if GraphicsController.low then math.max(1, math.floor(count * G.LowParticleScale)) else count
end

local function savedQualityIsLow(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or level == Enum.SavedQualitySetting.Automatic then
		return false
	end
	local n = tonumber(string.match(tostring(level), "%d+"))
	return n ~= nil and n <= G.LowQualityLevel
end

function GraphicsController.init() end

function GraphicsController.start()
	for _, name in { "Arena", "Lobby" } do
		task.spawn(function()
			local root = Workspace:WaitForChild(name, 30)
			if root then
				scenery(root)
			end
		end)
	end
	-- Lighting effects are created by the server before clients load; give them a moment
	task.delay(2, function()
		if GraphicsController.low then
			applyLighting()
		end
	end)
	if savedQualityIsLow() then
		GraphicsController.set(true)
	end

	-- frame-rate watch: a few slow windows in a row switch performance mode on (never back off
	-- automatically, so it doesn't flicker on a machine that sits right at the threshold)
	local frames, elapsed, slowWindows = 0, 0, 0
	local warmup = os.clock() + G.WarmupTime -- loading hitches aren't representative
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if GraphicsController.manual or GraphicsController.low then
			conn:Disconnect()
			return
		end
		if os.clock() < warmup then
			return
		end
		frames += 1
		elapsed += dt
		if elapsed >= G.SampleWindow then
			local fps = frames / elapsed
			frames, elapsed = 0, 0
			slowWindows = if fps < G.LowFps then slowWindows + 1 else 0
			if slowWindows >= G.SlowWindowsToSwitch then
				GraphicsController.set(true)
			end
		end
	end)
end

return GraphicsController
