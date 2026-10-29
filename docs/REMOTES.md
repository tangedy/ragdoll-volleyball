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
| `SetBusy` | `{ value: boolean }` | A hub menu (shop, daily, spin, quest chest, settings) is open. Busy players aren't pulled into a match. |
| `SetSetting` | `{ key: "ReducedMotion" \| "CameraShake", value: boolean }` | Stored per session. |
| `ReportDevice` | `{ kind: "Touch" \| "Mouse" \| "Gamepad" }` | Analytics only, logged once per kind per session. |
| `BuyItem` | `{ id: string }` | Hub only. The item must exist, cost more than 0, be unowned, be on sale (event items only during their event; bundle items never) and be affordable. It's equipped on purchase. |
| `EquipItem` | `{ id: string }` | Hub only. The item must be owned or a default. |
| `ClaimDaily` | `{}` | Once per UTC day; repeat requests are refused. The server grants today's rung of `Config.DailyRewards.Ladder` through `RewardService.grant` and answers with `DailyResult`. |
| `PickReward` | `{ id: string }` | `id` must be one of the choices in the player's oldest waiting pick (`profile.RewardPicks[1]`, e.g. day 7's Epic pick). The pick is spent before the item is granted, so a repeat never grants twice; an item owned meanwhile pays the pick's duplicate coins. Answered with `PickResult`. |
| `Practice` | `{ event: "Pickup" \| "Throw" \| "HitDummy" }` | Hub only. The practice dummy and balls are client-side; this only advances the tutorial and the onboarding funnel. |
| `Spin` | `{ paid: boolean? }` | Hub only. Free: uses the oldest bonus spin from the login ladder first (on its `Config.Spin.Wheels` wheel), then the daily one (once per UTC day); free and bonus spins are allowed in restricted regions. Paid: `Config.Spin.ExtraSpinCost` coins, at most `MaxPaidPerDay` per day. The server rolls, grants (or pays duplicate coins) and saves. |
| `ClaimQuest` | `{ id: string }` | Hub only. `id` is a `Config.Quests.List` id whose goal is reached today and whose chest isn't claimed yet (once per quest per UTC day; repeats are refused). The chest opens through `RewardService.grant` (`Kind = "Chest"`): the server rolls a rarity by the chest's odds, then an unowned item of it, or pays `Config.Economy.DuplicateCoins` when every item of that rarity is owned. The claim is marked in the same step and saved. Allowed in restricted regions (it isn't paid). Answered with `QuestResult`. |
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
| `Results` | `{ winner, won, aborted, casual, coins, tier, xp, level, leveledUp, streak, wins, stats, persistent }` | The 4 s results overlay. |
| `Profile` | `{ coins, owned, equipped, daily = { day, reward, claimed, pick? }, level, xp, xpNext, streak, persistent, tutorialStep }` | HUD chip, shop and daily panels. `daily.reward` is that day's `Config.DailyRewards.Ladder` entry; `daily.pick = { ids, rarity, coins }` is a cosmetic pick still waiting for `PickReward`. |
| `DailyResult` | `{ ok, day, kind, ... }` or `{ ok = false, message }` | The claimed reward, as `RewardService.grant` returns it: `Coins { coins }`, `Spin { wheel }` (queued as a bonus spin), `Boost { id }` (a `BoostBought` follows), `Cosmetic { id?, rarity, duplicate, coins }` or `Pick { ids, rarity }` (the choices, also in `daily.pick`). |
| `PickResult` | `{ ok, kind = "Cosmetic", id, rarity, duplicate, coins }` or `{ ok = false, message }` | The item taken from a pick (or its duplicate coins). |
| `ShopResult` | `{ id, ok, message?, equip? }` | Buy and equip outcome. |
| `CoinsBought` | `{ id, coins }` | A Robux coin bundle (or a restricted extra spin's coin refund) was granted: coin pop on the Coins sheet. |
| `BoostBought` | `{ id }` | A 2x coins boost was granted. |
| `BundleBought` | `{ id, coins, items }` | A limited-time cosmetic bundle (`Config.CoinShop.Offers[].Id`) was granted: `items` are the catalog ids now owned, `coins` the bonus. Sent once per receipt; the following `Profile` carries the new `owned` and `coins`. |
| `BallLaunched` | `{ id, origin, vel, ballType, t0, thrower, throwId, look? }` | Lets clients render the arc locally; `look` holds the owner's skin and trail (Standard balls only). |
| `Finisher` | `{ module, killer, victim, killerName, victimName, winner, duration }` | Plays the finisher cutscene; sent only to players in the match. |
| `Tutorial` | `{ step }` | Tutorial card. |
| `SpinResult` | `{ ok, index, slots, id, rarity, duplicate, coins, how, wheel? }` (`how` is `"Free"`, `"Bonus"`, `"Coins"` or `"Robux"`; `wheel` names a bonus spin's wheel) or `{ ok = false, message }` | Lands the spin wheel on `slots[index]` and reveals the prize. |
| `QuestResult` | `{ ok, quest, kind = "Chest", chest, id, rarity, duplicate, coins, slots, index }` or `{ ok = false, quest, message }` | The opened quest chest: `chest` is its `Config.Quests.Chests` id, `id` the prize (when `duplicate`, an owned item of the rolled rarity, paid as `coins`). `slots` is the reveal wheel (the chest's drops) and `slots[index]` is the prize the wheel lands on. |
| `FaceCourt` | `{ focus, from? }` | After a hub, jail or court placement: swing the camera behind the character to look at `focus`. `from` is the placed spot: the client waits for the body to arrive there, then turns it and the camera to face `focus`. |
| `Intro` | `{ teams = { [team] = { members = { { model, pose } }, center, facing, halfWidth } }, order, times, cinematic }` | Match-start intro poses on every client; the team pans only when `cinematic` (players in the match). |

`Profile` also carries `spin = { free, freeSpins, bonus?, paidLeft, cost, slots, robux, restricted }` (`freeSpins` counts bonus spins plus today's daily one, `bonus` is the wheel the next free spin is on, and `slots` is that wheel) and `quests = { resetsAt, quests = { { id, name, goal, progress, claimed, ready, chest, chestName, odds, drops } } }`: today's quests in `Config.Quests.List` order, `resetsAt` the next UTC midnight (unix seconds), `odds[rarity]` the chance of each rarity from that quest's chest (0 to 1) and `drops[rarity]` the catalog ids it can drop. `quests.featured` is today's featured power ball (`Config.PowerUps.Featured`, nil when off), and `powerKOs = { Heavy, Rocket, Pop }` is the player's lifetime Power Ball Mastery count (Catalog `Unlock` progress). `BallLaunched` also carries `context` (`"Match"` or `"Lobby"`).

## Replicated state (attributes)

- `ReplicatedStorage.MatchState` holds the match attributes: `State`, `PhaseEndsAt` (server time), `Round`, `RedWins`, `BlueWins`, `RedActive`, `BlueActive`, `RedJail`, `BlueJail`, `Overtime`, `OvertimeSteps`, `MatchId` and `TeamSize`.
- Character models and `Player` objects carry `Team`, `Status`, `Action`, `IsBot`, `HeldBall`, `DodgeReadyAt`, `CatchReadyAt`, `Level` and `Streak`.
- Ball parts in `Workspace.Balls` carry `BallId`, `BallType`, `BallState`, `ThrowerTeam` and `Context`.
