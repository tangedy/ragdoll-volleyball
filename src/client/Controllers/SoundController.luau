--!strict
-- Plays layered sound cues from Shared/Sounds.luau, either positional (in the world) or as 2D UI
-- sounds. Each play builds its layers and destroys them when done. Every cue's audio is preloaded at
-- start, and a layer's stopAfter only starts counting once it is really playing: UI layers are cut
-- to 60-80 ms, so timing them from Play() let a slow load swallow the whole sound.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local SoundController = {}

local rng = Random.new()
local uiGroup: SoundGroup
local sfxGroup: SoundGroup

local function build(layer: Sounds.Layer, parent: Instance, group: SoundGroup): Sound
	local s = Instance.new("Sound")
	s.SoundId = layer.id
	s.Volume = layer.volume
	local jitter = layer.jitter or 0
	s.PlaybackSpeed = layer.pitch * (1 + rng:NextNumber(-jitter, jitter))
	s.SoundGroup = group
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 300
	if layer.startAt then
		s.TimePosition = layer.startAt
	end
	if layer.eq then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = layer.eq.low
		eq.MidGain = layer.eq.mid
		eq.HighGain = layer.eq.high
		eq.Parent = s
	end
	if layer.distortion and layer.distortion > 0 then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = layer.distortion
		d.Parent = s
	end
	if layer.reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = 1.2
		r.WetLevel = -8
		r.Parent = s
	end
	s.Parent = parent
	return s
end

-- A fresh Sound may still be loading its audio; wait for it (briefly) so it isn't cut before it
-- starts. Preloaded ids are normally ready at once.
local LOAD_WAIT = 0.5
local function waitLoaded(s: Sound)
	if s.IsLoaded then
		return
	end
	local deadline = os.clock() + LOAD_WAIT
	while not s.IsLoaded and s.Parent and os.clock() < deadline do
		task.wait()
	end
end

-- Play a cue. With `at`, it is positional; otherwise it plays as a 2D sound.
function SoundController.play(cue: string, at: Vector3?, volumeScale: number?)
	local layers = Sounds.Cues[cue]
	if not layers then
		return
	end
	local holder: Instance
	if at then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = Workspace.Terrain
		holder = a
	else
		holder = SoundService
	end
	local group = if at then sfxGroup else uiGroup
	local longest = 0
	for _, layer in layers do
		local s = build(layer, holder, group)
		s.Volume *= volumeScale or 1
		local delay = layer.delay or 0
		local life = delay + (layer.stopAfter or 3)
		longest = math.max(longest, life)
		task.delay(delay, function()
			waitLoaded(s)
			if not s.Parent then
				return
			end
			s:Play()
			local curve = layer.gamma
			if curve and layer.stopAfter then
				-- drive the volume along the gamma curve until the layer stops
				local full, length = s.Volume, layer.stopAfter
				local peak = math.max((curve.shape - 1) * curve.scale, 1e-3)
				local started = os.clock()
				s.Volume = 0
				local conn: RBXScriptConnection
				conn = RunService.Heartbeat:Connect(function()
					local t = os.clock() - started
					if t >= length or not s.Parent then
						conn:Disconnect()
						return
					end
					local g = (math.max(t, 1e-6) / peak) ^ (curve.shape - 1) * math.exp(-(t - peak) / curve.scale)
					s.Volume = full * math.min(g, 1) * math.clamp((length - t) / curve.tail, 0, 1)
				end)
			end
			-- timed from the real start, then cleaned up
			task.delay(layer.stopAfter or 3, function()
				s:Stop()
				task.delay(0.1, function()
					s:Destroy()
				end)
			end)
		end)
		-- backstop in case the layer never got to play
		task.delay(life + LOAD_WAIT + 0.5, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	if at then
		task.delay(longest + LOAD_WAIT + 0.3, function()
			holder:Destroy()
		end)
	end
end

function SoundController.init()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFX"
	sfxGroup.Volume = 1
	sfxGroup.Parent = SoundService
	uiGroup = Instance.new("SoundGroup")
	uiGroup.Name = "UI"
	uiGroup.Volume = 0.9
	uiGroup.Parent = SoundService
	-- light bus compression so layered hits don't clip
	local comp = Instance.new("CompressorSoundEffect")
	comp.Threshold = -12
	comp.Ratio = 3
	comp.Parent = sfxGroup
	-- preload every sound file the cues use, so the first press of anything is heard in full
	task.spawn(function()
		local seen: { [string]: boolean } = {}
		local preload: { Instance } = {}
		local folder = Instance.new("Folder")
		folder.Name = "SoundPreload"
		for _, layers in Sounds.Cues do
			for _, layer in layers do
				if not seen[layer.id] then
					seen[layer.id] = true
					local snd = Instance.new("Sound")
					snd.SoundId = layer.id
					snd.Parent = folder
					table.insert(preload, snd)
				end
			end
		end
		folder.Parent = SoundService
		pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
	end)
	-- the signature sound, once, when the loading screen lifts and the game is ready to play
	local player = Players.LocalPlayer
	local function booted()
		if player:GetAttribute("Booted") == true and not player:GetAttribute("BootSoundPlayed") then
			player:SetAttribute("BootSoundPlayed", true)
			SoundController.play("Signature")
		end
	end
	player:GetAttributeChangedSignal("Booted"):Connect(booted)
	task.defer(booted)
end

return SoundController
