--!strict
-- Shared type and enum-like string definitions.

export type TeamName = "Red" | "Blue"

-- Where a combatant is in the match.
export type Status = "Lobby" | "Active" | "Jailed" | "Returning" | "Spectating"

-- What a combatant is doing. Only one at a time (spec §12 "explicit action states").
export type Action = "Idle" | "Charging" | "Recovering" | "Dodging" | "Catching" | "Ragdolled"

export type MatchStateName =
	"WaitingForPlayers"
	| "Intermission"
	| "RoundCountdown"
	| "RoundActive"
	| "RoundResolution"
	| "Finisher"

export type BallState = "Resting" | "Held" | "InFlight" | "Spent" | "Resetting"

local Types = {}

Types.Attr = {
	-- character model attributes (replicated)
	Team = "Team",
	Status = "Status",
	Action = "Action",
	IsBot = "IsBot",
	HeldBall = "HeldBall", -- ball type or ""
	Level = "Level",
	Streak = "Streak",
	DodgeReadyAt = "DodgeReadyAt", -- workspace:GetServerTimeNow() timestamps
	CatchReadyAt = "CatchReadyAt",
	-- ball attributes
	BallId = "BallId",
	BallType = "BallType",
	BallState = "BallState",
	ThrowerTeam = "ThrowerTeam",
}

return Types
