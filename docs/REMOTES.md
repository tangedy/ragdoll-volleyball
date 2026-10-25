# Remote contract

Source of truth: `src/shared/NetSchema.luau`. Remotes live in `ReplicatedStorage.Net`.

A client may **request** an action. It may never declare a result: hits, catches, eliminations, jail returns and rewards are all decided on the server.

## Client → server: `Net.Action` (RemoteEvent)

Signature: `FireServer(action: string, payload: table)`.

Every request is rate-limited to `Config.Net.MaxActionsPerSecond` per player and validated by `NetSchema.Validators[action]`. Invalid requests are dropped silently and counted as suspicious. Repeated suspicious requests are logged; nobody is auto-banned.

| Action | Payload | Server checks |
| --- | --- | --- |
| `ChargeStart` | `{}` | Holding a ball, action `Idle`, the ball belongs to the player's current context (lobby or a live round). The server records the charge start time. |
| `Throw` | `{ dir: Vector3, throwId: number }` | `dir` must be finite with magnitude 0.5–2. Pitch is clamped to `MaxPitchUp/DownDeg`. The player must be holding a ball, be `Charging` or `Idle`, not ragdolled, and in the matching context. Charge comes from the server-recorded hold time; the client never sends power. |
| `CancelAim` | `{}` | Only acts while `Charging`. The player keeps the ball. |
| `Dodge` | `{ dir: Vector3 }` | Flattened to the horizontal plane. Off cooldown, not ragdolled, catching or in throw recovery, and not frozen in the countdown. |
| `Catch` | `{}` | Empty hands, off cooldown, `Active` or `Lobby` status (jailed players can't catch). Opens a `CatchWindow` on the server. |
| `SetAutoQueue` | `{ value: boolean }` | The lobby "Play again" toggle. |
| `SetSetting` | `{ key: "ReducedMotion" \| "CameraShake", value: boolean }` | Stored per session. |
| `ReportDevice` | `{ kind: "Touch" \| "Mouse" \| "Gamepad" }` | Analytics only, logged once per kind per session. |
| `BuyItem` | `{ id: string }` | Hub only. The item must exist, cost more than 0, be unowned and be affordable. It's equipped on purchase. |
| `EquipItem` | `{ id: string }` | Hub only. The item must be owned or a default. |
| `ClaimDaily` | `{}` | Once per UTC day; repeat requests are refused. |
| `Dev` | `{ cmd: "SkipIntermission" \| "ForceOvertime" \| "RunTests" }` | Honoured only in Studio. Bound to F6, F7 (sudden death) and F9 (test suite). |

## Server → client: `Net.Feedback` (RemoteEvent)

Signature: `FireClient(kind: string, data: table)`.

| Kind | Data | Use |
| --- | --- | --- |
| `Banner` | `{ text, color?, duration? }` | Big centre text: "KNOCKED OUT!", "REVENGE!", "COURT SHRINKING!". |
| `Hint` | `{ text, duration? }` | Small centre text. |
| `Feed` | `{ text }` | Event feed line. |
| `Impact` | `{ kind: "Hit" \| "Catch", position, ballType?, target? }` | VFX, sound and camera shake. |
| `DodgeAccepted` | `{ dir }` | The client applies the dodge motion to its own character. |
| `Ragdoll` | `{ on }` | Mirrors the ragdoll state into the local humanoid. |
| `ThrowResult` | `{ throwId, ok }` | Reconciles the client's throw prediction. |
| `Possession` | `{ warn?, remaining?, dropped? }` | Holding warning at 8 s, forced drop at 12 s. |
| `Results` | `{ winner, won, aborted, casual, coins, tier, xp, level, leveledUp, streak, stats, persistent }` | The 4 s results overlay. |
| `Profile` | `{ coins, owned, equipped, daily = { day, amount, claimed }, level, xp, xpNext, streak, persistent, tutorialStep }` | HUD chip, shop and daily panels. |
| `ShopResult` | `{ id, ok, message?, equip? }` | Buy and equip outcome. |
| `BallLaunched` | `{ id, origin, vel, ballType, t0, thrower, throwId, look? }` | Lets clients render the arc locally; `look` holds the owner's skin and trail (Standard balls only). |
| `Finisher` | `{ module, killer, victim, killerName, victimName, winner, duration }` | Plays the finisher cutscene; sent only to players in the match. |
| `Tutorial` | `{ step }` | Tutorial card. |

## Replicated state (attributes)

- `ReplicatedStorage.MatchState` holds the match attributes: `State`, `PhaseEndsAt` (server time), `Round`, `RedWins`, `BlueWins`, `RedActive`, `BlueActive`, `RedJail`, `BlueJail`, `Overtime`, `OvertimeSteps`, `MatchId` and `TeamSize`.
- Character models and `Player` objects carry `Team`, `Status`, `Action`, `IsBot`, `HeldBall`, `DodgeReadyAt`, `CatchReadyAt`, `Level` and `Streak`.
- Ball parts in `Workspace.Balls` carry `BallId`, `BallType`, `BallState`, `ThrowerTeam` and `Context`.
