--!strict
-- Client side of the remote contract. Requests only; the server decides every result.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetSchema = require(Shared.NetSchema)

local folder = ReplicatedStorage:WaitForChild(NetSchema.FolderName)
local actionRemote = folder:WaitForChild(NetSchema.ActionRemote) :: RemoteEvent
local feedbackRemote = folder:WaitForChild(NetSchema.FeedbackRemote) :: RemoteEvent

type Listener = (data: any) -> ()

local Net = {}

local listeners: { [string]: { Listener } } = {}

function Net.request(action: string, payload: any?)
	actionRemote:FireServer(action, payload or {})
end

function Net.on(kind: string, fn: Listener)
	listeners[kind] = listeners[kind] or {}
	table.insert(listeners[kind], fn)
end

feedbackRemote.OnClientEvent:Connect(function(kind: string, data: any)
	local list = listeners[kind]
	if list then
		for _, fn in list do
			task.spawn(fn, data)
		end
	end
end)

Net.MatchState = ReplicatedStorage:WaitForChild(NetSchema.MatchStateFolder) :: Folder
Net.Actions = NetSchema.Actions

return Net
