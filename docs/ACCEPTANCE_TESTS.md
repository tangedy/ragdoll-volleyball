# Manual acceptance tests

Mark each row with how it was verified: **S** = Studio (state the number of clients), **D** = device (state which), **A** = automated. Leave it blank until it has actually been run.

## Milestone acceptance (spec §15)

| # | Test | Result |
| --- | --- | --- |
| M1 | Two clients repeatedly pick up, throw, hit, fall, recover and reset with no duplicated balls or broken characters | |
| M2 | A full match completes and the next one starts without developer intervention | S (1 client + bots), Oct 24 |
| M3 | PC, mobile and controller can each do every action without menus and without blocking camera control | |
| M4 | Players can identify the incoming ball type before impact; every type follows the same ownership, catch and cleanup rules | |
| M5 | A new player discovers the core actions, finishes a match, equips an earned cosmetic and keeps it after rejoining | Partial S: earned coins bought and equipped a skin; keeping it after rejoining needs Studio API access (untested) |

## Required edge cases (spec §16)

| Test | Result |
| --- | --- |
| Two players pick up one ball at the same time | A (F9 suite, bots) |
| A catch and another throw's hit land in the same step | A (ownership stays consistent) |
| Hit while charging: throw cancelled, ball dropped | A |
| Disconnect while holding a ball | A (bot removal) |
| Reset during a ragdoll (the reset button is disabled; also check an engine-removed character) | |
| Dying or respawning during round transitions | |
| Simultaneous final-player eliminations give a draw and a replay | A |
| A power-up despawns while someone tries to pick it up | |
| High-speed ball contact at a low frame rate (Studio FPS cap) | |
| Malformed vectors, action spam, stale round requests | S: NaN, huge, wrong type, unknown action and 60/s spam all dropped, no errors |
| A character tries to cross the center line (walk, dodge, jump) | A (teleport case; walk/dodge/jump not yet) |
| A player idles while holding a ball: warning at 8 s, drop at 12 s | A (drop) |
| Data loading or saving fails: HUD warns and combat still works | S: API access off, so "Progress not saving" shows |
| Many rounds with no build-up of constraints, connections or visual balls | S: socket count stable across 2 matches |

## Amendment A

| Test | Result |
| --- | --- |
| A solo player starts a bot-filled 3v3 within 15 s of joining | S: about 12 s |
| Real players joining between rounds replace bots, starting with the smaller team | |
| Jail respawn, return after a jail hit, the 2-return cap, and jail closed in sudden death (F7) | A |
| A team with only jailed players loses the round | |
| Revenge counts only for a hit on the player's own eliminator | A (positive case) |
| XP and quest rewards respect the per-match caps; bot actions don't count for players-only quests | XP cap implemented, untested; quests are Stage 2 |
| A bot-heavy match neither advances nor breaks win streaks | |
| A failed or duplicated purchase receipt never grants twice or loses an item | Stage 2 |
| A limited's stock never drops below 0 across servers | Stage 2 |
| No purchase prompt can appear during an active round | Stage 2 |
| Event modifiers apply equally to both teams and fully reset afterwards | Stage 3 |

## Designer loop (Stage 1a)

**A** = the F9 Studio suite with bots, one client.

| Test | Result |
| --- | --- |
| Coins pay the single highest tier (600/500/300/200) and 50 to losers who played; idle players and aborted matches get 0 | A |
| Daily reward pays once per UTC day, advances the ladder, resets on a missed day, wraps after day 7 | A |
| A daily claim through the UI updates coins and clears the badge | S |
| Sudden death: timer end never decides on a count; jail closes; prisoners stay in jail; knockouts spectate | A |
| The court keeps shrinking in sudden death until a team is out | S (strips retract; fallback path not yet hit) |
| Shop: buy deducts coins, duplicate refused, unaffordable refused, equip works, hub-only | S (hub-only refusal not yet exercised) |
| Ball skin shows on your Standard ball and never on power-up balls | S (Standard); power-up exclusion is by code |
| The finisher plays for everyone in the match on the match-ending knockout, then the match ends | A + S (one client) |
| Two clients both see the same finisher | |
| The shop panel and hub buttons fit on a phone screen | |

## Oct 27 verification sweep

**S** = Studio, one client plus bots, driven through the MCP. Studio was unfocused (about 15 FPS), so these are numeric checks, not visual ones.

| Test | Result |
| --- | --- |
| Every finisher preview (all 8) plays, keeps the dummy on screen most of the time, and cleans up (court, actors, FX, camera) | S |
| A preview's dummy flies the same arc as a real finisher victim | S after two fixes: the preview court was outside the client's physics range, so the dummy froze; and the launch wasn't speed-capped like the server's, so Default landed in the jail. Default now peaks at 215 (server: 214) and falls into the void |
| A cheer plays on an enemy elimination, never on a teammate's or your own | S: 4 of 4 enemy eliminations cheered, 0 of 2 Red eliminations |
| An open menu keeps you in the hub and the pill says to close it | S |
| Play again off: no match starts and the pill says so | S in the hub. The "during a live match" case needs a second real player |
| Performance mode: on by itself at graphics quality 1; ⚙ off restores shadows, bloom and lights; ⚙ on removes them | S after a fix: turning it off used to bring back only 1 of 101 lights |
| Throwing with 300 ms incoming lag | Partial: a throw went through. Arc smoothness wasn't judged (15 FPS) |
| Neon shows at half brightness | S: 48 of 48 arena neon parts are exactly 0.5× the server colour |
| Practice is private | S: the client has its own dummy and 2 balls, the server has none. Launching the dummy wasn't driven |
| Intro: 2 s per team, then 3-2-1 | S: Intro 4.0 s, countdown 3.1 s (timing only) |
