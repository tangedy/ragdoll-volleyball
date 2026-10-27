# Implementation status (Oct 24, 2026)

## Oct 27 stability and performance pass

- **Matchmaking can't get stuck:** if a match throws a script error, `MatchService.recover()` sends everyone back to the hub, clears bots and balls, and the loop starts the next match. Before, one error stopped matches for the rest of the server's life.
- **No surprise teleports:** while any hub menu is open (shop, daily, spin, settings), the client reports `SetBusy` and the server won't start or late-join you into a match. This replaces the shop's old trick of switching Play again off and back on, which could leave it stuck off.
- **Clear hub status:** the phase pill says why you're waiting ("Play again is off…", "Close the menu to join…") instead of a silent "Getting a match ready...".
- **Network:**
  - In-flight balls write their server position at 10 Hz instead of 60 Hz. Clients already draw the arc from the launch record.
  - The action rate limit is a token bucket (20/s sustained, 40 burst), so inputs bunched up by a laggy connection aren't dropped.
  - Avatars are fetched once per visit and reused on every respawn.
- **Server CPU:** `PlayerStateService.all()` is cached (it ran several times per physics step), and ball sweeps reuse one `RaycastParams`.
- **Performance mode** (`GraphicsController`, `Config.Graphics`, ⚙ Settings): turns off global shadows, sun rays, bloom, the court sparkles and scenery lights on this client only, and cuts hit-effect particles by 60%. It switches on by itself if your Roblox graphics quality is 1–3, or after two 3-second samples below 38 FPS.
- **Lighting:** lighter haze so the court reads from the hub, a brighter ambient, a little more contrast and softer shadows. Lamp posts no longer cast shadows.
- **Name tags:** they shrink with distance, so a crowd doesn't stack into one pile, and your own tag is hidden.

### To check in Studio (Oct 27)

1. Open the shop during intermission. The pill should say to close the menu, and no match should start or pull you in until you close it.
2. Turn Play again off. The pill should say so in the hub and during a live match.
3. Set Roblox graphics quality to 1–3. Shadows and lamp lights should drop and the ⚙ Performance mode toggle should be on. Toggle it off and on.
4. Throw balls with the Network emulator set to 300 ms. Arcs should stay smooth and no throws should be lost.

## Oct 26 follow-ups (neon, practice, intro)

- **Neon at 50%:** a client `NeonController` shows every Neon part at `Config.Visuals.NeonIntensity` (0.5), including parts that change colour later (rim pulses, strip warnings, effects, power balls, team bands). The arena's and hub's glow panels and lights are halved too. The server's colours are unchanged.
- **Signpost:** the boards now hang on the helipad side of the pole, so the pole no longer shows through the text.
- **Client-side practice** (`PracticeController`, `Config.Practice`):
  - Each player has their own dummy and two practice balls, simulated locally inside `Workspace.Lobby.Practice`, so they vanish with the hub while you're on the court.
  - The dummy is built from a template the server parks in `ReplicatedStorage`. Hits ragdoll it locally, with the normal knockback and hit effects. It's in the Default collision group, so no hub wall stops it: it flies off the open end, falls, and a new one stands up after 2 s. If it lands on the deck it stands back up.
  - The server no longer runs a dummy or practice balls. The only network traffic is the `Practice` remote, which advances the tutorial and the funnel.
- **Intro poses replace victory poses:**
  - **When:** at the start of each match (first round only), everyone stands on their spawn doing their equipped intro pose. Match players get a letterboxed dolly across the **Blue** team (2 s), then the **Red** team (2 s), with a team caption and a stinger. Then the normal 3-2-1 countdown.
  - **End of match:** the old post-match victory moment is gone.
  - **Where:** `Config.Intro`, `Shared/IntroPoses`, `IntroController`; the shop tab is now "Intro Poses", and TRY still works.

### To check in Studio (follow-ups)

1. **Neon:** the rims, curtains, hub strips and balls should look about half as bright as before.
2. **Signpost:** the boards should sit in front of the pole when seen from the helipad.
3. **Practice:** walk to a practice ball, throw at the dummy, and watch it fly off the end and respawn. A second client shouldn't see your dummy or your balls. The tutorial should still advance on pickup, throw and hit.
4. **Intro:** start a match. You should get 2 s on Blue, 2 s on Red, then 3-2-1, with everyone posing during the pans.

## Oct 26 hub, bots, spin and victory pass

None of this has been run in Studio yet. It passes `selene` (0 errors, the same 6 style warnings as before) and the strict `luau-lsp` check (no new errors; the only errors left are the 10 that were already in `PurpleFlash.luau`). The F9 suite now has **30 tests** (11 new).

- **Rooftop hub** (`LobbyBuilder`, `Config.Lobby`): the hub is a neon rooftop at night. The deck is the top of a tower with lit windows that sinks into the void. It has paver tiles, parapets with purple neon, a glass railing on the court side with a cyan rail light, a water tower, a stairwell shed with an EXIT sign and a blinking antenna beacon, AC units, planters, benches, vending machines, lamp posts and party string lights. Everything is placed in a deck frame that faces the court (`ArenaLayout.LobbyFrame` / `lobbyPoint`), so moving `LobbyOrigin` moves the whole hub.
- **Hub zones:**
  - **Stations:** SHOP & LOCKER, DAILY SPIN (with a physical prize wheel) and DAILY REWARD are booth-style stations along the back, each with a canopy sign, a screen, a counter prompt and a "stand here" ring.
  - **Leaderboard:** on the right end, top 8 on this server by wins.
  - **Other zones:** bleachers ("watch zone") at the railing, a helipad spawn, a signpost, a practice banner and mat, and floor labels.
  - **Animation:** `HubController` animates the wheel, beacon and fans.
- **Hub beside the court:** `LobbyOrigin` is `(-110, 200, 0)`, level with the court, off its −X side across a 36-stud gap (`LobbyGap`). While you're on the court (Active, Jailed or Returning), the hub is taken out of your Workspace locally, so it doesn't render, collide, show prompts or light anything. Hub occupants (practice balls, the dummy, lobby players and spectators) are hidden too. Other changes:
  - **Practice balls:** they collide only with hub scenery, the court-side `LobbyNet` keeps them off the court, and their throws aren't drawn for on-court players.
  - **Match balls:** a match ball over the hub is out, and a stranded match ball is reset.
  - **Floor arrows:** they also find the hub floor.
- **UI:**
  - **Theme:** gains spacing, radius, type and motion tokens; `show` / `hide` transitions with a backdrop; responsive `autoScale` (1 at 1280×720 down to 0.62); and badge, stat-chip and coin widgets.
  - **HUD:** scales with the screen.
  - **Results card:** coins count-up, three stat tiles, a level / XP / streak footer.
  - **Settings:** camera shake and reduced motion moved behind a ⚙.
  - **Shop:** a responsive grid, scrolling tabs, rarity tags and ✓ owned marks.
  - **Daily ladder:** wraps to 4 + 3 on phones.
  - **Hub buttons:** move to the left edge on touch.
- **Bots** (`Config.Bots.Profiles`, `Mix`): Easy, Normal and Hard profiles, mixed by the real players' average level.
  - **Reacting:** they react after a human reaction time. Dodges go toward the middle. Catches are pressed with a timing error, so they really fail.
  - **Balls and edges:** they go for the nearest safe ball (teammates don't chase the same one) and back off edges.
  - **Targeting:** they pick smart targets (enemies near an edge or just recovered; they avoid enemies who could catch).
  - **Throwing:** they aim, then charge for a chosen time, sometimes snap-throw, and sidestep while aiming.
  - **No stalling:** a held ball is always thrown within `StallThrow` (4 s), and aim time shrinks in sudden death.
- **Daily spin** (`SpinService`, `SpinController`, `Config.Spin`):
  - **How you spin:** one free spin per UTC day, plus up to 5 extra spins at 750 coins each. A Robux extra spin is built but stays off until `RobuxProductId` is set.
  - **Fair odds:** the wheel has 12 slots drawn by rarity weight (60 / 28 / 10 / 2). It is seeded per player, day and spin, so the client shows exactly the wheel the server spins, and the server picks a slot uniformly.
  - **Duplicates:** a prize you already own pays 100 / 250 / 500 / 1000 coins by rarity.
  - **Saving:** save **schema v5** adds `Spin` (with a migration).
  - **Presentation:** the panel shows that wheel's odds, a free-spin countdown, an ease-out spin with ticks, and a reveal with rays, confetti and an EQUIP button.
- **Facing the court:** joining, respawning in the hub, falling off it, returning after a match, being sent to the hub after your last elimination and jail respawns all face the court. The camera swings in behind you (`FaceCourt`).
- **Victory poses:**
  - **Catalog:** a new Pose category: Fist Pump (free default), Big Wave, Flex, You're Next, Take a Bow and Dab. Each has a TRY button in the shop.
  - **When it plays:** after the finisher and the "WINS!" banner, the new `Victory` state (4 s) lines the winning team up on its half, bots included. Everyone sees the poses; players in the match also get a letterboxed push-in. Then the results card.
  - **How:** poses come from the shared `VictoryPoses` data and the new client `PoseKit`, which finishers now share. It solves arms, head and waist on the R15 AnimationConstraint rigs.

### To check in Studio

1. **Hub art:** play solo, then look around the deck, the tower edge and the lights. Set `Lighting.Technology = Future` for the neon.
2. **Zones:** walk to each station. The prompts should open SHOP, SPIN and DAILY. Check the leaderboard fills in within 5 s and the floor labels read the right way round.
3. **Beside the court:** from the bleachers you should watch the match across the gap. Once you're in a match, the hub, the dummy and lobby players should be gone. When you're eliminated for the round, they should come back. In a two-client test, check that someone in the hub can't be hit and doesn't see on-court players vanish.
4. **UI:** resize the window and use the device emulator (phone landscape) on the HUD, results card (`RD_Gallery` `ResultsFinalKnockout`), shop, daily, spin and the ⚙ settings.
5. **Bots:** watch a few matches. They should dodge some throws, sometimes whiff catches, avoid edges, focus players near edges, and vary their throws. Check the `BotDifficulty` attributes on bot models.
6. **Spin:** spin free, then a paid spin with G dev coins. The wheel should land on the revealed prize. Owning everything should pay coins.
7. **Facing:** join, fall off the hub, get eliminated twice in sudden death, and finish a match. Each time the camera should face the court.
8. **Victory:** win a match (or press T). After the finisher you should see the line-up, the poses and the camera move, then the results card. Try each pose with TRY.

## Oct 25 polish pass

- **Currency:** it's called coins everywhere: UI, code and save data (schema v4 migrates the v3 "Pts" field).
- **Eliminations:** +25 coins, paid instantly to the credited player, with a "+25" coin pop under "ELIMINATION!" that flies into the coin counter.
- **Sudden death:** only the "SUDDEN DEATH!" banner (no jail-closed or court-shrinking text).
- **Match end:** the final round shows "RED/BLUE WINS!" once; the results card follows after it. In Studio the banner showed for 2.4 s and the results arrived 3.1 s later.
- **Match summary:** the title, the coins earned (tier plus elimination coins), and hits / catches / knockouts.
- **Daily claim:** today's box pops with a check, the button reads "COME BACK TOMORROW!", then the panel closes itself and the coins fly to the counter.
- **Tutorial step 1:** "Walk over a ball." is replaced by gold chevron arrows on the floor from the player to the nearest ball they can pick up, with a pulsing ring under it (`BallGuideController`).
- **Loading screen:** "FLING YOUR FRIENDS!".
- **Tests:** the F9 suite is 19/19 (adds the elimination-coins test).


## Visual, audio and feel pass (Oct 25)

- **Arena:** neon team rims with light curtains and rising sparks; rims move inward as the court shrinks. The jail is glass with a neon trim, the hub has a purple trim, and the night lighting has bloom. Set `Lighting.Technology = Future` by hand in Studio; scripts and Rojo can't set it.
- **Hits:** the target flashes white, plus a spark burst, shockwave, comic "POW/BAM/SMACK!" pop, layered hit sound, a camera kick and a red vignette for the person hit, and a hitmarker for the thrower.
- **Eliminations:** "ELIMINATION!" plus a team-colored screen flash for the eliminator, a rim pulse on the victim's side and a void splash for everyone.
- **Sound:** every cue is a layered stack of built-in engine sounds in `shared/Sounds.luau`, so each can be swapped for uploaded audio. The mix hasn't been listened to yet.
- **UI:** a shared `client/UI/Theme.luau` (outlined rounded type, gradient panels, 3D buttons) restyles the HUD, results card, shop, daily panel, mobile buttons, tutorial, spectator bar and loading screen. Every pop-up is captured in `docs/screenshots/`.
- **Ragdoll fix (Oct 25):** the R15 rigs use Roblox's newer joint system (AnimationConstraints plus built-in limited BallSocketConstraints), so the old Motor6D-only ragdoll never loosened a joint and bodies flew rigid. Ragdoll now disables the AnimationConstraints (all except Root) so the built-in sockets take over; arms swing up to about 156° and legs about 87° mid-flight. Classic Motor6D rigs still work.
- **Fling feel:** natural slide is back (no added friction) and the full-body tumble about a random axis is back, with per-limb spin and flail. Knockback is 28 (quick) to 44 (full charge) horizontal and 26 up. Spawns moved to 24 studs from the center line.
- **Court edges:**
  - The jail is now 8 studs out (wider than a lying body), so no one can rest across the court edge and the jail anymore.
  - The jail's court-facing wall blocks walkers and ragdolls both ways, while balls pass through.
  - One-way edge walls 2.5 studs outside every court edge only affect bodies already flung 5+ studs out, so they can leave but never bounce back.
  - Anyone hanging past the edge for 3 s without falling is out.
- **Countdown:** the server sends 3-2-1 directly to the players in the match, and a big number pops for each tick (verified in Studio: received 3,2,1 and displayed 3,2,1).
- **Pickup:** landed-but-still-rolling balls can be grabbed, pickup uses horizontal distance within 6 studs, it works during throw recovery, and it checks 20 times a second. After a 12 s forced drop, that player can't pick up for 2 s, so the timeout can't be dodged by re-grabbing.
- **Knockback probe** (`workspace:SetAttribute("RD_KnockbackProbe", true)`): number of throws (out of 3) where the target fell off.

| Where the target stands | Quick throw | Full charge |
| --- | --- | --- |
| Middle of their half (34 from the back edge) | 0 | 0 |
| 18 from the back edge | 1 of 2 hits | 3 |
| 10 from the back edge | 3 | 3 |
| 10 from a side edge | 0 | 3 |
| 5 from a side edge | 3 | fell (1 hit) |

- **Tests:** the F9 suite is 18/18, including new tests for the jail wall, the one-way edge and rolling pickup.
- **Dev key:** F10 (Studio) launches your own character with a full-charge hit so you can feel the knockback.
- **Studio UI gallery:** `game.Players.LocalPlayer:SetAttribute("RD_Gallery", "<item>")` pins any pop-up for review.

## Stage 1a: designer loop

- **Coins economy.** Coins replace coins everywhere (save schema v3 migrates coins to coins 1:1). A match pays the single highest tier: 600 final knockout / 500 never eliminated / 300 on court at the win / 200 win / 50 losing-team participation. Every payout needs at least one action (anti-AFK). XP, levels and win streaks are unchanged. Values are in `Config.Coins`.
- **Daily login rewards.** A 7-day ladder in `Config.DailyRewards`. Claimed with a button once per UTC day; a missed day resets to day 1; never auto-claimed. The DAILY panel shows a "!" badge and opens once per session when there's something to claim.
- **Sudden death.** When the timer ends, the round no longer ends on a head count: jail closes, the court shrinks every 5 s, and the round ends when a team is out. A fallback (`SuddenDeathFallback`) ends it if it still stalls after the court has fully shrunk.
- **Hub intermission of 7 s.** The lobby is the hub: chat, practice dummy, SHOP & LOCKER (buy and equip with coins, server-validated, hub-only) and DAILY, opened from the HUD buttons or the kiosks. While the shop is open you stay in the hub; auto-queue is restored when you close it.
- **Cosmetics.** `shared/Catalog.luau` holds ball skins (Standard balls only, so power-up types stay readable), trails, titles (on the name tag) and finishers, each with Robux product-id placeholders.
- **Finishers.** The match-ending knockout triggers a `Finisher` phase. Play freezes, the server re-stages and re-launches the victim, and every player in the match sees the killer's equipped finisher cutscene. Modules live in `src/shared/Finishers/` (the contract is in its README). Default and Spotlight exist; real designs come later.
- **Stage 1 hardening.**
  - Client-rendered ball flight with thrower prediction (`BallVisualController`).
  - The F9 Studio test suite.
  - F8 debug overlay with hit-outcome tuning data.
  - Device, spectate-time and leave-while-out analytics.

### Verified in Studio (one client plus bots, Oct 24)

- The F9 suite passed 15/15 on four separate runs. It covers:
  - Every spec §16 row a bot can drive.
  - Jail, revenge and the return cap.
  - The coins tiers, including idle winners.
  - The daily ladder.
  - Sudden death closing the jail.
  - The finisher phase leading to the end of the match.
- **Shop through the real remotes:** a buy deducts coins, a duplicate is refused, an unaffordable item is refused with the shortfall, equip switches work, and the held ball shows the equipped skin.
- **Daily claim:** 500 → 600 coins, and the badge cleared.
- **Finisher, observed on the client:** Scriptable camera, HUD hidden, "FINAL KNOCKOUT!" and "X finished Y!" banners, the victim re-launched off the court, then the camera and HUD restored.
- **Ball visuals:** 16 client visuals during bot play, the server parts hidden while in flight, and cleanup afterwards.

### Not yet verified

- Two or more real clients.
- Phones.
- Real DataStore saving: Studio API access is off, so profiles are in-memory.
- How the finishers *look* is placeholder camera work.



## Implemented

The milestones are listed in spec order, with the amendment's additions under each.

### M1: Combat sandbox

- **Arena:** a graybox court of 96 × 64 studs floating at Y=200. It has a center barrier that stops characters but not balls, team-tinted halves and an elimination plane 25 studs below the court.
- **Collision groups:** Characters (no body-blocking), Ragdoll, Barrier and Ball.
- **Pickup:** automatic pickup within a 5-stud radius. Ownership is resolved once per ball per tick, so a ball can't be assigned twice. There's a pickup lockout and a thrower lockout.
- **Ball flight:** server-simulated at a fixed 60 Hz step with a bounded catch-up budget. Collision uses swept `Spherecast` (never `Touched`) and handles initial overlap explicitly. Each throw has one terminal outcome.
- **Hit targets:** a separate `HitProxy` box per character, so accessories and body shape don't matter. Teammates are never in the query, so they can't block their own team's shots.
- **Ragdoll:** an R15 ragdoll with constraints prepared once per character. The Root joint is kept and server network ownership is temporary. Knockback is one bounded velocity change, independent of mass. Recovery puts the player at a valid point on their own half and never rescues a real void fall.
- **Avatars:** everyone spawns as a normalized R15 rig (scale 1, proportions 0).

### M2: Match loop

- **State machine:** WaitingForPlayers → Intermission (6 s) → Countdown (3 s, frozen) → RoundActive (75 s) → overtime (up to 20 s) → Resolution (3 s). Matches are best of three.
- **Overtime:** "COURT SHRINKING!" with a 1 s red warning on the outer strips before each one drops away (visibly, every 5 s), plus "JAIL CLOSED!". The tiebreak is confirmed hits, then a draw replays the round. Draws are capped at 2.
- **Eliminations:** void eliminations found in the same server step are resolved together. Knockout credit goes to the last enemy hit within 4 s.
- **Jail and revenge (A1):** a 1.5 s fall beat, then the jail strip behind the enemy half. A jail hit sets Returning, then after 1 s the player respawns with 1.5 s immunity. Returns are capped at 2 per round; the third elimination spectates. "REVENGE!" fires on a hit against your own eliminator. Jail counts show on the HUD.
- **Results (A3):** a 4 s non-blocking overlay shown over the live lobby. "Play again" auto-queue is on by default, with a lobby toggle.
- **Population:** joiners mid-match wait in the lobby. Between rounds, waiting players replace bots, starting with the smaller team. A match aborts if no real players remain or a team empties.
- **Spectating:** shows the fall briefly, then follows living teammates. Switch with Z/C, the arrows or the D-pad.

### M3: Skill and mobile controls

- **Charge:** the server records the charge start; a quick release gives the minimum-power throw.
- **Dodge:** 0.28 s with no i-frames. It is server-approved and then applied by the physics owner, and can't cross the barrier.
- **Catch:** a 0.22 s window inside a forward cone. A catch is evaluated before a hit in the same step.
- **Possession timeout:** a warning at 8 s and a forced drop at 12 s.
- **Input:** PC, controller and mobile. Mobile buttons respect safe insets, dragging off THROW cancels, and a second finger can still move the camera.
- **Aiming:** a center reticle on touch and controller, and a mouse reticle on PC. Mild aim assist works only inside a 6° cone with line of sight. Gravity is compensated, and there's a short arc preview rather than a laser.
- **Bots (A2):** scaled to the real player count (3v3 / 5v5 / 6v6), capped at 5. They go for balls, wander their own half away from edges, throw after a 0.6–1.4 s aim delay with an 8° error cone, dodge 25% of the time and catch 10% of the time. They use the same `CombatService` entry points as players and carry a "BOT" tag.

### M4: Power-ups and feedback

- **Ball types:** Heavy, Rocket and Pop, each with its own color, size, material, trail or light. Mirrored dispensers give both teams the same type every 12 s. A catch keeps the type; a spent ball reverts to standard.
- **Feedback:** an impact burst, sound and capped camera shake. The settings include reduced motion and a camera-shake toggle.
- **Not done:** the A6 weekly events, which are in Stage 3 of the release plan.

### M5: Onboarding, rewards and persistence (partial)

- **Loading screen:** a custom screen in ReplicatedFirst.
- **Lobby:** a practice ball and a launchable practice dummy.
- **Tutorial:** server-owned steps that advance on real actions: walk over a ball → hold to aim → launch the dummy or hit someone → stay on the court → catch tip during downtime.
- **Rewards (superseded by coins, see above):** coins per spec §13, with a per-match performance cap and a participation requirement. Bots pay 50%. XP and level follow the A4 curve, with the level badge over the head. Win streaks have a flame at 3+; casual matches with more than half bots don't change them. A "STREAK ENDED!" bonus is included.
- **Saving:** a DataStore profile with `UpdateAsync`, a session lock, retries, autosave and `BindToClose`. The v1 → v2 migration adds the A4 fields. If loading fails, the defaults never overwrite a real save and the HUD says progress isn't saving.
- **Analytics:** a monotonic onboarding funnel for fresh saves only, plus custom events for catches, jail, revenge, match duration, bot count and invalid remotes.
- **Not done:** cosmetic inventory and equip, daily quests, the login streak, the cosmetic index, and the catalog with simulated purchases (A4/A5). These are Stage 2 of the release plan.

## Testing

### Automated (run on this machine)

- `selene src`: 0 errors. 7 style-only warnings remain: `UDim2.fromScale` suggestions.
- `luau-lsp analyze` in strict mode against the Roblox definitions: 0 errors.

### Studio, one client against the Studio server (run via MCP, Oct 24)

- A solo join started a bot-filled 3v3 within about 12 s.
- Bots knocked players into jail, and jail escapes happened (seen in the feed and HUD).
- Match 1 completed and match 2 started with no intervention.
- 98 ball-socket constraints were present across 7 rigs after the second match started, which means no constraint leak.
- A client-driven pickup → charge → throw through the real remotes ragdolled a bot.
- NaN, huge, wrong-type and unknown-action payloads were dropped, and 60 requests in one burst were rate-limited. There were no server errors.

### Not yet tested

- Two or more real clients (Studio local server).
- A physical phone, tablet or controller.
- High latency.
- DataStore saving with API access enabled.
- Every row of [ACCEPTANCE_TESTS.md](ACCEPTANCE_TESTS.md) not listed above.

## Known limitations

- **Ball visuals:** balls are server-moved anchored parts, so they can look steppy at replication rate. The client prediction and visual reconciliation that `ThrowResult` is reserved for is planned in Stage 1.
- **Latency:** catch eligibility uses server receipt time with no historical rewind, as the spec allows for the MVP. High-ping players will see some late catches and hits.
- **Ragdoll ownership:** the server takes ownership of a player's limbs during a ragdoll, which can rubber-band at high ping.
- **Ball count:** a power ball reverts to standard after it's thrown, so the court can hold up to 8 balls (6 standard plus 2). Conservation trims beyond that.
- **Bot animations:** bots use the default R15 walk and idle animations loaded on the server.
- **Sounds:** they use built-in `rbxasset://sounds` placeholders.
- **Avatar warning:** the console shows "Asset type does not match" for one item in the test account's avatar. It's harmless.
