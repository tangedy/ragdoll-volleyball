--!strict
-- Plays layered sound cues from Shared/Sounds.luau, either positional (in the world) or as 2D UI
-- sounds. Each play builds its layers and destroys them when done.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
			s:Play()
			if layer.stopAfter then
				task.delay(layer.stopAfter, function()
					s:Stop()
				end)
			end
		end)
		task.delay(life + 0.1, function()
			s:Destroy()
		end)
	end
	if at then
		task.delay(longest + 0.2, function()
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
end

return SoundController
