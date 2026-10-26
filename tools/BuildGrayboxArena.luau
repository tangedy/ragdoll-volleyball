-- Paste into the Studio command bar (Edit mode) to preview the graybox arena without playing.
-- The server rebuilds Workspace.Arena and Workspace.Lobby at runtime, so this is optional and idempotent.
-- Requires the Rojo project to be synced first (ServerScriptService.Server.Services.ArenaBuilder).
require(game:GetService("ServerScriptService").Server.Services.ArenaBuilder).build()
require(game:GetService("ServerScriptService").Server.Services.LobbyBuilder).build()
