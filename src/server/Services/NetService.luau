--!strict
-- Creates remotes, validates every client request against NetSchema, rate-limits, and dispatches.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local NetSchema = require(Shared.NetSchema)

type Handler = (player: Player, payload: any) -> ()

local NetService = {}

local handlers: { [string]: Handler } = {}
local rate: { [Player]: { windowStart: number, count: number, suspicion: number } } = {}
local feedbackRemote: RemoteEvent
local actionRemote: RemoteEvent
local S: any

local function suspicious(player: Player, reason: string)
	local r = rate[player]
	if not r then
		return
	end
	r.suspicion += 1
	-- throttled: one log line and one analytics event per SuspicionLogThreshold requests
	if r.suspicion % Config.Net.SuspicionLogThreshold ~= 1 then
		return
	end
	if Config.Debug.LogSuspiciousRemotes then
		warn(("[Net] suspicious request from %s: %s (count %d)"):format(player.Name, reason, r.suspicion))
	end
	if S and S.AnalyticsService then
		S.AnalyticsService.invalidRemote(player, reason)
	end
end

function NetService.init(services: any)
	S = services
	local folder = ReplicatedStorage:FindFirstChild(NetSchema.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = NetSchema.FolderName
		folder.Parent = ReplicatedStorage
	end
	local function remote(name: string): RemoteEvent
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
		return r
	end
	actionRemote = remote(NetSchema.ActionRemote)
	feedbackRemote = remote(NetSchema.FeedbackRemote)
end

function NetService.start()
	actionRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
		local r = rate[player]
		if not r then
			r = { windowStart = os.clock(), count = 0, suspicion = 0 }
			rate[player] = r
		end
		local now = os.clock()
		if now - r.windowStart >= 1 then
			r.windowStart = now
			r.count = 0
		end
		r.count += 1
		if r.count > Config.Net.MaxActionsPerSecond then
			suspicious(player, "rate")
			return
		end
		if type(action) ~= "string" then
			suspicious(player, "action-type")
			return
		end
		local validator = NetSchema.Validators[action]
		local handler = handlers[action]
		if not validator or not handler then
			suspicious(player, "unknown-action")
			return
		end
		local clean = validator(payload)
		if clean == nil then
			suspicious(player, "payload:" .. action)
			return
		end
		handler(player, clean)
	end)
	Players.PlayerRemoving:Connect(function(player)
		rate[player] = nil
	end)
end

function NetService.on(action: string, handler: Handler)
	handlers[action] = handler
end

function NetService.reject(player: Player, reason: string)
	suspicious(player, reason)
end

function NetService.send(player: Player, kind: string, data: any?)
	feedbackRemote:FireClient(player, kind, data)
end

function NetService.broadcast(kind: string, data: any?)
	feedbackRemote:FireAllClients(kind, data)
end

return NetService
