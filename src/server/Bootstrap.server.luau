--!strict
-- Server entry point. Services are small modules wired through one shared table; each exposes
-- init(services) for setup and an optional start() once everything is initialized.

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"NetService",
	"AnalyticsService",
	"PlayerStateService",
	"ArenaService",
	"RagdollService",
	"CharacterService",
	"BallService",
	"CombatService",
	"TeamService",
	"BotService",
	"MatchService",
	"RewardService",
	"DataService",
	"TutorialService",
	"ShopService",
	"SpinService",
	"ChestService",
	"LobbyService",
	"TestService",
}

local S: { [string]: any } = {}
for _, name in ORDER do
	S[name] = require(Services:WaitForChild(name)) :: any
end
for _, name in ORDER do
	S[name].init(S)
end
for _, name in ORDER do
	if S[name].start then
		S[name].start()
	end
end
print("[RagdollDodgeball] server started")
