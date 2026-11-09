# Retention pass (Nov 8, 2026)

Why: the Nov 5–7 funnels showed D1 retention at 3.06% (the genre median is 8.26%). Players dropped hardest between finishing the tutorial and starting a match (−28.6%), and between finishing game 2 and playing 12 minutes (−69%). This pass ran 10 rounds of "list 10 ideas, build the best 3", aimed at three things:

1. getting players into a match sooner
2. giving them a reason to play one more game
3. giving them a reason to come back tomorrow

Every number lives in `Config.luau` and is a first guess to tune.

**Checks:** `lune run tests/offline/run` passes 96/97. The one failure ("playtime pays 1st then repeat coins") also fails on the code from before this pass; it comes from the playtime quest's first-claim goal. `selene src` is clean. **Not verified in Studio** (the Studio MCP wasn't connected): playtest before publishing.

## What changed

### Getting into a match sooner
| Change | Where | Config |
|---|---|---|
| Finishing the tutorial queues you after a 5 s beat, even with other players in the server. A live match with a bot slot pulls you straight in. | `TutorialService.complete` | `Match.QueueAfterTutorial`, `QueueAfterTutorialDelay` |
| A queued player fresh out of the tutorial starts their match after 5 s (this used to apply only to a player alone in the server) | `MatchService.run` | `SoloAfterTutorialWait` / `Window` |
| Lobby wait 20 s → 10 s | — | `Match.LobbyMaxWait` |
| A match of only brand-new players (0 finished games) is a single round | `MatchService.runMatch`, plus the `RoundsToWin` match attribute that hides the HUD's extra star | `Match.FirstMatchRounds` |
| The intro runs at half length once every real player in the match has finished a game this session | `playIntro` | `Intro.RepeatScale` |
| A "press PLAY / JOIN MATCH" hint after 25 s idle in the hub, once per visit | `LobbyService.idleNudges` | `Match.IdleNudgeAfter` |

### First matches that feel winnable
| Change | Where | Config |
|---|---|---|
| Rookie bots (slow, wide aim, rarely target real players) on the team facing a player with fewer than 3 finished games | `BotService.fill` | `Bots.Profiles.Rookie`, `Bots.Rookie` |
| Rookie bots never fire their ultimate | `PowerService.addMeter` | `Bots.Rookie.NoUltimates` |
| The team behind on rounds starts the next round with 35% ultimate meter | `PowerService.comeback` | `Powers.ComebackUlt` |

### A reason to play one more game
The results card is taller. It now shows:
- an animated XP bar
- **one next-goal line**, the first of these that applies:
  - the day's first-win bonus, until you've won today
  - "next game pays the play streak"
  - a quest that's ready to claim, half done, or the "Play 3 games" quest under way
  - XP to the next level, and what that level pays
- a **daily-reward line**: either "today's reward is waiting in the hub" or "come back tomorrow for…"

New payouts, all in `RewardService.awardMatch`. Each needs the anti-AFK participation rule, and boosts apply:

| Payout | Config |
|---|---|
| First win of each UTC day: +150 coins and +30 XP | `Rewards.FirstWinBonus` / `FirstWinXP` |
| First win ever: +300 coins, once; the card says "Your first win!" | `Rewards.FirstEverWinBonus` |
| Every 3rd finished game in a session: +100 coins | `Rewards.PlayStreak` |
| Daily XP rush: the first 3 games each UTC day earn 2× XP | `Rewards.XPRush`, `profile.XPRush` |
| MVP (the clear top scorer, if a real player): +50 coins, a sticker and a feed line | `Rewards.MVP` |
| Personal bests (KOs, hits, catches per match) get a sticker | `profile.Best` |

Other changes:
- **New quest:** "Play 3 games" (event `Game`, `Always = true`, so it's picked every day).
- **Friend invites:** an invite prompt once per session, after the 2nd game, in the hub. It defers to the favourite prompt (`InviteController`, `Config.Social`).
- **Bot chat:** bots say "gg"-style lines in chat bubbles as the match is decided (`MatchService.botBanter`, `Bots.Banter`).
- **Leave Match confirm:** now says what you'd miss.

### Measurement
- **"Played 12 minutes" fixed:** the onboarding step now means 12 real active minutes. It used to fire when the playtime quest completed, and since Nov 6 that quest's first goal has been 8 minutes (`Config.Analytics.FunnelPlaySeconds`).
- **New `PlayAfterWin` funnel:** pairs with `PlayAfterLoss`.
- **New custom events:**
  - `SessionAccountDay` on join: days since the account's first join. This gives a D1/D7 read without the dashboard.
  - `SessionGames` and `SessionActiveMinutes` on leave.

### Analytics splits
Every funnel step and custom event now carries Roblox custom fields. Break down by them in Analytics → Funnels and Analytics → Events.

| Field | Values | Where it comes from |
|---|---|---|
| `CustomField01` (device) | Phone, Tablet, Desktop, Console, Unknown | The client's first `ReportDevice` (`InputController.formFactor`). A touch screen whose shorter side is under 500 points counts as a phone. |
| `CustomField02` (how they arrived) | Invite, Friend, Solo | `AnalyticsService.detectSource`. Invite: `GetJoinData().ReferredByPlayerId`. Friend: a friend was already in the server. Ads vs home recommendations aren't visible in-game; use Acquisition for that. |
| `CustomField03` (first match) | Bots, Mixed, Real, None | The account's first match: Bots = over half bots. Saved as `profile.FirstMatchType`. **Events only:** funnel steps leave it out because it's unknown until the first match. |

To show the same device on every step, the onboarding "Joined" step waits up to 4 s for the device report (`Config.Analytics.DeviceWait`). Later steps queue behind it.

**Retention by split (custom events):**
- **`NewPlayer`:** once, in the account's first session. This is the denominator.
- **`ReturnedD1` / `ReturnedD7`:** the first session 1 or 7 days (24-hour periods) after the first join, once per account. This is the numerator.

So D1 by device = `ReturnedD1` ÷ `NewPlayer`, both broken down by CustomField01. Days count in 24-hour periods from the first join, so this won't exactly match the dashboard's D1, but the splits compare fairly with each other.

**First match:** `FirstMatch` logs once per account; its CustomField03 says which kind. D1 by first match = `ReturnedD1` ÷ `FirstMatch`, both broken down by CustomField03.

## Reading the next funnel
- **Compare cohorts.** Compare players who joined after the publish with Nov 5–7.
- **Steps 7 → 8** (tutorial → 1st match) should rise the most.
- **Steps 9 and 10 now match for first matches.** A first match is one round, so "Finished 1st round of 1st match" and "Finished 1st game" are the same for those players.
- **"Played 12 minutes" isn't comparable** with older data: it means something different now.
- **Win vs loss:** compare the `PlayAfterWin` and `PlayAfterLoss` step-2 rates.

## Ideas listed but not built
- Keeping players on the court between matches instead of sending them back to the hub (MatchService change; needs Studio).
- A daily free-trial power (it touches shop ownership and the Power Wheel).
- A hub "next level" chip next to the saving chip (needs a Studio layout pass).
- Experience notifications (need an Open Cloud sender).
