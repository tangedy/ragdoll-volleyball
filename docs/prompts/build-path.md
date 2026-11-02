# Build path: chat prompts

This covers the next set of work: the guided hub tutorial and the big PLAY button (prompts 2–6
and 9), and the lobby, retention and shop changes from the Nov 1 review (prompts 1, 7, 8, 10,
11 and 12). Every prompt below is complete on its own: the shared preamble is already inside
each code block, so copy one block into a fresh chat and send it. Nothing else needs pasting.

Spirits (collectible characters with activated abilities) are shelved. None of these prompts
include them, and each prompt tells its chat not to add them.

Left out on purpose:
- **Cosmetics with stat tradeoffs:** paid cosmetics would turn pay-to-win.
- **A 60-player hub that splits into small matches:** it rewrites the match flow for little
  gain right now.

## How the game flows today

1. **Join:** loading screen → hub. The daily rewards sheet opens by itself
   (`ShopController`, `autoOpened`). Play again (`AutoQueue`) is on by default, so a new player
   goes into the queue straight away.
2. **Hub practice** (`PracticeController`, all on the client): 2 Standard practice balls and a
   practice dummy at the open end of the deck. The dummy keeps its own `dummyDamage` %, which
   makes each hit throw it harder (`ProjectileMath.escalation`), but **the % isn't shown
   anywhere**. A dummy knocked into the void comes back at 0% after 0.75 s. Practice balls are
   always Standard.
3. **Tutorial** (`TutorialService` on the server, `TutorialController` on the client): saved as
   `TutorialStep` with 6 steps. 1 walk to a ball (floor arrows) → 2 throw → 3 hit the dummy or an
   enemy → 4 "Stay on the court!" for 4 s → 5 a catch tip during downtime → 6 done. It shows as a
   small tip card, nothing blocks you, and it carries on into real matches.
4. **Intermission** (`MatchService.run`): when someone is queued, a 25 s countdown starts
   (`Config.Match.LobbyMaxWait`). The bottom-right corner (`HUDController`, "Ready") shows
   "Ready" and an "N/M ready" pill. Once everyone queued has pressed Ready, the match starts
   early. Bots fill the rest of a 3v3.
5. **Match** → results card → back to the hub. With Play again on, the next intermission starts.
6. **Daily quests** (reworked Nov 1, see the top of `docs/STATUS.md`): the hub panel shows two
   random daily quests (knock out 3, hit 10 players, dodge 5 balls, win 1 game; each pays a quest
   chest) and "Play 12 minutes", which ticks up live and pays 100 coins, over and over.

## The guided tutorial (prompts 2–6 and 9)

A guided, step-by-step tutorial in the hub that a new player must finish before they get into
a match:

1. Pick up a ball.
2. Hit the dummy. Point out that the dummy's % went up, and where the player's own % is shown.
3. Keep hitting the dummy until it's knocked off.
4. The dummy comes back at 50%, and the player gets a **Heavy** practice ball. One Heavy throw
   knocks it off.
5. Tell the player there are more special balls to find (Rocket and Pop).
6. The dummy throws at the player, and the player dodges (Q, the Dodge button or the gamepad).
7. Done: show the rewards. The corner button is now a big **PLAY** button. Pressing it changes
   it to "Waiting for next match · 25", counting down.

**Where it plays (Nov 2):** not in the hub but on the player's own client-only copy of the real
court (`PracticeController`, `Config.Tutorial.Court`, 800 studs out in −Z). The player stands on
the Red half, the dummy on the far half, and the dummy is out once it's off the court, as in a
match. `TutorialController` draws a step card at the top centre (counter, headline, help line),
a bouncing 3D arrow over the next target and the floor chevrons. Closing the Done card moves the
player to the hub, where hub practice carries on as before. Prompts 3 and 4 were both built in
the prompt 3 chat.

**Shared contract** (prompt 2 builds it; prompts 3–6 and 9 rely on it, so don't rename
anything):

| Step | Name | Moves on when (Practice event from the client) |
| --- | --- | --- |
| 1 | Grab | `Pickup` |
| 2 | FirstHit | `HitDummy` |
| 3 | KnockOff | `DummyOut` (the dummy falls into the void) |
| 4 | Heavy | `HeavyOut` (the Heavy ball knocks the 50% dummy off) |
| 5 | Discover | Moves on by itself after `Config.Tutorial.DiscoverSeconds` (4 s) |
| 6 | Dodge | `Dodged` (a drill ball misses after the player dodged) |
| 7 | Done | Reward granted; `TutorialDone` player attribute = true |

`Throw` and `GotHit` are also sent. They're only for analytics and don't move a step on.

## Run order

Use a fresh chat for each prompt. Commit, or at least check the diff, between waves. Chats in
the same wave edit different files, but they all share **one Studio**: let one chat drive a
playtest at a time.

| Wave | Prompts | Why this order |
| --- | --- | --- |
| 1 | **1** Quest rework check | The quest rework isn't tested in Studio yet. Commit it before building on top. |
| 2 | **2** Tutorial: server step machine | Bumps the save schema and sets the step contract the others use. |
| 3 | **3** Dummy and Heavy ball, **4** Tutorial UI, **5** PLAY button, **7** Homing telegraph, **8** Bundle value tags | Each one has its own files. |
| 4 | **6** Dodge drill, **10** Level rewards | 6 edits `PracticeController` again after 3. 10 needs 2's schema bump. Both may add one line to `Bootstrap.client.luau`: merge that line by hand if both do. |
| 5 | **9** Tutorial playtest and polish | Needs everything above merged. |
| 6 | **11** Group reward kiosk | Edits the same save, reward and config code as 10. |
| 7 | **12** Lobby sightline and first-visit guidance | Starts where the finished tutorial ends and reuses the floor arrows the tutorial uses. Shares hub layout with 11. |

Suggested effort: 1 medium, 2 high, 3 high, 4 medium, 5 medium, 6 high, 7 medium, 8 medium,
9 high, 10 high, 11 medium, 12 medium.

---

## 1. Quest rework: Studio check

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Task: check the Nov 1 daily quest rework in Studio and fix what's broken. Make no design
changes. Read the "Nov 1 daily quest rework" section at the top of docs/STATUS.md first.
Files: src/server/Services/QuestService.luau, src/client/Controllers/QuestController.luau,
CombatService.creditDodges, and the Config.Quests block.

- The hub quest panel shows exactly 3 rows: two daily picks, plus "Play 12 minutes" at the
  bottom with a coin disc.
- The playtime count (m:ss) climbs about once a second while you move, and pauses about 30 s
  after you stand still (the QuestPlaytime player attribute).
- To test the playtime claim quickly, set the progress from the server command bar
  (QuestService.daily(c).progress.Playtime = 715). Claim appears; claiming pops +1000 coins into
  the counter (+500 on the 2nd-4th claims that day) and the count restarts at 0:00. After the
  4th claim the row folds to the slim line with a timer to the UTC reset.
- In a bot match: hits raise "Hit 10 players"; pressing dodge as an enemy ball flies past
  raises "Dodge 5 balls"; dodging with no ball nearby doesn't. If neither quest was picked
  today, set its picks/progress the same way.
- Tapping a chest quest's icon opens the chest sheet; tapping the playtime icon shows a hint
  and no sheet.
- Does the 7-stud / 0.6 s dodge rule (Config.Quests.Dodge) feel fair? Report it; don't retune
  without saying why.
- Run the F9 suite and the offline tests (61/61 passed at hand-off; Lune is already trusted in
  Rokit). Both must pass.
Report what you checked numerically and what you only saw in a screenshot.
```

## 2. Tutorial: server step machine, save migration, queue gate, reward

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Rewrite the tutorial's server side for the new guided hub tutorial in
docs/prompts/build-path.md (the 7-step table there is the contract).

Files: src/server/Services/TutorialService.luau (rewrite), src/server/Services/DataService.luau
(TutorialStep default and migration), src/shared/NetSchema.luau (the Practice validator only
allows Pickup/Throw/HitDummy today; add DummyOut, HeavyOut, Dodged, GotHit),
src/server/Services/LobbyService.luau (the Practice handler, ~line 265, and the queue),
src/shared/Config.luau (add Config.Tutorial).

- TutorialService.Done = 7. Steps only move forward and only on the event for the current
  step (a DummyOut sent during step 1 is ignored). Step 5 moves to 6 on a timer
  (Config.Tutorial.DiscoverSeconds = 4). The old Hit/Catch/match-based steps go away: the
  tutorial is hub-only now. Keep the Tutorial net message ({ step = n }) and add
  { reward = ... } when step 7 is reached.
- Throttle: at most one step change per 0.5 s per player. It's practice and nothing pays out
  except the one-time completion reward, but don't let a spammed remote skip the whole thing
  in one frame.
- Completion: grant Config.Tutorial.Reward once (start with 250 coins; use
  RewardService.grant like other one-off grants and follow its result shape). Save it so it can
  never be granted twice, then set the player attribute TutorialDone = true. Also set
  TutorialDone on join for players who have already finished.
- Migration: bump the save schema the way DataService already does. Old saves with
  TutorialStep >= 6, or Matches >= 1, become Done (returning players never see the tutorial).
  Anyone else restarts at 1.
- Queue gate: a player with TutorialDone ~= true is never queued for a match, whatever
  AutoQueue says (look at how MatchService.queuedPlayers / LobbyService decide this, and how
  DevRoomService keeps visitors out of the queue). Bots and TestService fixtures must still
  work.
- Add a dev shortcut next to the existing RD_Gallery / Dev command handling: reset my tutorial
  to step 1, and skip it to Done. Both Studio-only.
- Add TestService checks: steps advance only in order, the reward is paid once, the
  migration maps old steps correctly, and an unfinished player isn't queued.
Run the offline tests and update any that the change breaks.
```

## 3. Tutorial: practice dummy % billboard, 50% respawn, Heavy practice ball

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Client hub practice changes for the guided tutorial (docs/prompts/build-path.md, steps 2–4).
The server side (prompt 2) is done: the Tutorial net message tells you the current step, and
the Practice remote accepts DummyOut and HeavyOut.

Files: src/client/Controllers/PracticeController.luau (main), plus maybe
src/shared/ProjectileMath.luau and src/shared/Config.luau (Config.Practice / Config.Tutorial).
Don't edit TutorialController.luau or HUDController.luau (other chats own those).

1. Damage % over the practice dummy: a billboard like DamageController's enemy tags (same
   font, white → sun → red from ProjectileMath.damageColor, and the same pop when it goes up).
   Show it always, not just during the tutorial. Today the % is only the local dummyDamage.
2. When the dummy falls below ArenaLayout.LobbyVoidY, send Practice { event = "DummyOut" }.
   Send it only for a dummy the player knocked off, not one that respawned or was cleared.
3. Heavy step (tutorial step 4): the next dummy stands up at 50%
   (Config.Tutorial.HeavyDummyDamage = 50) and one practice ball turns into a Heavy ball
   (BallDefinitions Heavy: its colour, material and RadiusScale, and the server's
   BallVisualController look if that's easy to reuse; the Halloween pumpkin rule says power
   balls keep their colours). Practice flight, damage and knockback must use the ball's own
   type: today launchDummy and stepFlight hard-code "Standard". Make it type-aware.
4. One Heavy hit from 50% must reliably knock the dummy off the deck. Work it out from
   ProjectileMath.escalation / knockback / maxKnockbackSpeed and the deck size, and check it in
   Studio from short, medium and long range. If it doesn't reliably knock it off, add a
   tutorial-only boost (Config.Tutorial.HeavyLaunchScale) rather than changing match balance.
   When it goes off, send Practice { event = "HeavyOut" }. If the player misses or the dummy
   stays on, the Heavy ball comes back so they can try again.
5. Outside the tutorial, practice behaves the same as before (Standard balls, 0% respawn).
Expose a small API that prompt 6 (the dodge drill) will need: PracticeController.dummyModel()
and a way to pause the player's practice balls (PracticeController.setBallsEnabled(bool)).
Verify in Studio with the Studio MCP and report what you measured.
```

## 4. Tutorial: step cards, callouts and the completion screen

**Done (Nov 2) in the prompt 3 chat; don't run this prompt.** Built there: the step card, the
3D arrows, the "Nice!" beat, the Heavy and Discover ball stickers, the Done celebration (coins
count up, confetti, "Let's play!" → hub → daily sheet), the in-match catch hint and the
RD_Gallery `Tutorial1`..`Tutorial7` hooks. Left for prompt 9: the "This is YOUR %" callout. The
HUD's own % (`HUDController`, "Damage") only shows in a match, and that file belongs to prompt 5.

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Rebuild the tutorial's client presentation for the guided hub tutorial
(docs/prompts/build-path.md). The server (prompt 2) sends Tutorial { step = 1..7 } and
{ reward } on completion.

Files: src/client/Controllers/TutorialController.luau (rewrite), plus small additions in
src/client/UI/Theme.luau only if a helper you need is missing. Find other UI by name under
PlayerGui (for example the HUD's "Damage" frame); don't edit HUDController.luau or
PracticeController.luau.

It should feel engaging, not like a tip card: a bold step card at the top centre with a step
counter (1/6 … 6/6), a short headline and one line of help (<= 10 words each, adapted to
mouse/touch/gamepad as text() does today), and a "got it" pop and UIStep sound between steps.
- 1 Grab: keep the floor arrows (BallGuideController). "Grab a ball!"
- 2 FirstHit: "Hit the dummy!". Once the hit lands, briefly call out the dummy's % billboard
  ("Their % goes up with every hit") and then the player's own HUD % ("This is YOUR %. Higher %
  = you fly further"), with an arrow or ring pulsing on each. The HUD % may be hidden in the hub
  today: make it visible during the tutorial from here (by name) if you can, or list it for
  prompt 9.
- 3 KnockOff: "Knock it off the edge!"
- 4 Heavy: "You got a HEAVY ball!" and a ball sticker in the Heavy colour. "One throw does it."
- 5 Discover: a short card showing Heavy (found) and Rocket and Pop as "?" silhouettes in their
  colours: "More special balls to discover in matches!"
- 6 Dodge: "Dodge it!" with the input's dodge key (Q / Dodge button pulse / gamepad), using the
  same pulsing touch-button outline as today.
- 7 Done: a celebration overlay (confetti if Theme has it, the success sound) showing the reward
  (count the coins up like the results card does), "You're ready!" and one button that closes
  it. Closing it hands over to the PLAY button (prompt 5).
- The catch tip is no longer a tutorial step. Keep it as a one-time in-match hint for a
  player's first few matches (follow the Config.Damage.HintMatches pattern).
- Don't auto-open the daily rewards sheet (ShopController's autoOpened) while TutorialDone
  isn't true; open it after the Done card closes. This is the one change allowed outside
  TutorialController.
- The daily quest panel (QuestController, left edge) stays where it is; make sure the step
  card doesn't cover it.
- Phones: the cards must fit next to the touch controls (see the HANDOFF "Phone layout" notes).
Update the RD_Gallery Tutorial1..TutorialN hooks (DebugController) so every step can be
screenshotted. Take screenshots of each step in Studio.
```

## 5. Big PLAY button and the "Waiting for next match" countdown

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Replace the hub's Ready button with a big PLAY button (docs/prompts/build-path.md, last
tutorial step).

Files: src/client/Controllers/HUDController.luau (the "Corner" Ready block ~line 567 and its
update ~line 1222), src/server/Services/MatchService.luau (setReady / the intermission loop
~line 1196), src/server/Services/LobbyService.luau (the SetAutoQueue handler only; prompt 2
owns the Practice handler and the queue gate), src/shared/NetSchema.luau if you need a new
action.

How it works:
- In the hub, not in a match, with the TutorialDone attribute true and not queued: a big,
  loud PLAY button (much bigger than Ready is today: leaf green, chunky ledge, a gentle
  breathing pulse; Toybox button style). The TutorialDone attribute comes from prompt 2.
  Hide the button while it's not true.
- Pressing PLAY puts you in the queue (AutoQueue true). The button then reads "Waiting for next
  match · 25" and counts down the real intermission time (the timer the phase pill uses), in a
  calmer sun style, with a small "Cancel" that takes you out of the queue.
- The countdown always runs the full intermission: remove "everyone ready → start early" and
  the N/M ready pill (one player pressing PLAY would otherwise start at once).
  IntermissionSkipWhenFull stays. Keep the ready code only if something else still uses it;
  otherwise delete it, along with the Ready attribute plumbing.
- If you press PLAY with no intermission running (state WaitingForPlayers), one starts as
  soon as you're queued. Show "Waiting for next match · 25" from the moment you press.
- After a match: if Play again is on, you come back already queued and see the countdown. If
  it's off, you see PLAY. The phase pill's "Play again is off · press Ready to play" text must
  say PLAY.
- Touch layout: keep the existing top-right placement on phones, sized as a thumb target.
- Gamepad: PLAY can be selected and pressed with A.
Check it in Studio: a fresh join after skipping the tutorial (dev skip from prompt 2), the
countdown, cancel, and coming back after a match with Play again on and off.
```

## 6. Tutorial: dodge drill (the dummy throws at the player)

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Build the tutorial's dodge step (docs/prompts/build-path.md step 6). Prompts 2–5 are merged:
PracticeController has dummyModel() and setBallsEnabled(), the Practice remote accepts Dodged
and GotHit, and TutorialController shows the "Dodge it!" card. The tutorial plays on the
player's own copy of the court (PracticeController.onCourt(); the player is on the Red half and
the dummy on the far half, Config.Tutorial.Court), so the drill ball crosses the centre line
like a real throw.

Files: a new src/client/Controllers/TutorialDrillController.luau (wire it up in
src/client/Bootstrap.client.luau like the other controllers; a parallel chat may add its own
controller line there too, so add only yours), and small hooks in PracticeController.luau if
needed. Dodging itself is server-side (CombatService.doDodge allows status "Lobby"); the
client gets DodgeAccepted and DodgeMotion moves the character. Read
src/shared/DodgeMotion.luau and CharacterController's dodge prediction.

- On step 6: pause the player's practice balls. The dummy stands up facing the player, winds
  up (a short telegraph: a raised arm or glowing ball, and a "!" over its head) and throws a
  client-side practice ball straight at the player at a speed that's fair to dodge on reaction
  (start slower than a match throw; Config.Tutorial.DrillSpeed). It should feel like a real
  incoming ball, using the same hit and whoosh effects and sounds.
- Dodged: the ball passes within ~4 studs while the player is dodging (or dodged in the last
  0.4 s) and doesn't touch them → send Practice { event = "Dodged" } with a big "NICE DODGE!"
  hint. One clean dodge finishes the step.
- Hit: the player's own character gets a small client-side knock (no real ragdoll, no server
  damage), their HUD % goes up locally so the lesson from step 2 lands ("See? YOUR % went
  up"), send GotHit, and the dummy throws again after ~1.5 s. After 3 misses, slow the next
  throw down.
- The drill only runs while the player is in the hub (inHub()) and at step 6. Clean up on
  leaving or on reaching Done, and put the practice balls back.
- This is a client-side drill ball, so it must not count toward the daily "Dodge 5 balls"
  quest (that one is server-side, CombatService.creditDodges, match balls only). Leave the
  quest alone.
Check in Studio with mouse, touch (RD_Gallery "Touch") and gamepad prompts. Use the MCP to
trigger dodges (see the HANDOFF notes on reliable input) and report what you verified by eye
and what you only checked numerically.
```

## 7. Homing lock-on telegraph

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Problem: player throws now bend toward an enemy (Config.AimAssist.Homing, BallService's
steer/homingTarget, the BallCourse broadcast; see git show db1a74e), but nothing tells the
target that a ball is homing on them, so getting hit feels random.

Files: src/server/Services/BallService.luau (the launch/course payloads only),
src/client/Controllers/BallVisualController.luau, src/client/Controllers/EffectsController.luau,
src/shared/Sounds.luau. Don't edit PracticeController, TutorialController or HUDController
(other chats own those in this wave).

Build a readable telegraph:
- Server: include the homing target in BallLaunched/BallCourse, if it isn't already there.
- Target's client: a short, sharp lock-on cue, e.g. a red ring snapping under their feet plus
  a distinct sound from the existing Sounds.luau vocabulary or a built-in rbxasset sound. It
  should sit alongside the existing incoming-ball "!" warning (Config.AimAssist.WarnRadius),
  not duplicate it.
- Everyone else: the homing ball's trail tints slightly toward the target's team colour, kept
  subtle.
- Respect performance mode and reduced motion.
- Check in Studio. Homing is players-only, so throw at a bot to see the trail, and use a 2-player
  local server to see the target's cue. Report what you actually saw versus measured.
```

## 8. Honest value tags on Robux bundles

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Task: show players the value they get from each Robux bundle, using only numbers that are
true. Read docs/ECONOMY.md first.

Files: src/client/Controllers/CoinShopController.luau,
src/client/Controllers/BundleDisplayController.luau, tests/offline/tests.luau, and a short
note in docs/ECONOMY.md. Don't edit ShopController.luau (another chat owns it in this wave).

- Coin bundles (Config.CoinShop.Bundles): compute each bundle's coins per Robux against the
  smallest bundle and show "+X% BONUS" (e.g. 999 R → 35,000 coins is about +72%). Put a
  "BEST VALUE" ribbon on the best ratio. Compute everything from Config; never hard-code it.
- Limited offers (Config.CoinShop.Offers, e.g. the Haunted Bundle): show "Worth N coins", the
  sum of the items' catalog Price values plus the bundle's coins. Item Price is already
  documented as their value.
- Don't show a crossed-out Robux price unless that Robux price really existed. Explain this
  choice in a code comment.
- Apply it in the Coins sheet, the offer strip on the Shop shelf, and the hub stand's sign.
- Add an offline test that the bonus % and "worth" figures match Config.
Check in Studio with workspace:SetAttribute("RD_RobuxUnlocked", true), including a
phone-sized layout.
```

## 9. Tutorial: full playtest, polish and docs

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

All tutorial prompts (2–6 in docs/prompts/build-path.md) are merged, along with the homing
telegraph (7), bundle value tags (8) and level rewards (10). Do an end-to-end Studio playtest
as a brand-new player (dev reset tutorial to 1) and fix what's rough. Any file may need a fix
here; keep each fix small and list them. The tutorial plays on a client-only copy of the court
(PracticeController); also add the "This is YOUR %" callout at step 3, which needs the HUD's own
% (HUDController "Damage") visible during the tutorial.

Walk the whole flow at least twice, once with mouse and once with touch (RD_Gallery "Touch"):
join → no daily sheet → grab → first hit and both % callouts → knock off → 50% dummy and
Heavy ball one-shot → discover card → dodge drill (dodge once, then get hit once) →
completion and reward → daily sheet → PLAY → "Waiting for next match · 25" counting down →
match → back to the hub.
Check:
- The step order can't be broken: spam throws, walk away mid-step, die in the void during
  the drill, rejoin mid-tutorial and resume on the right step.
- A returning player (migrated save) never sees it and gets PLAY at once.
- The tutorial reward is paid exactly once.
- No new player is ever put in a match before finishing.
- Nothing overlaps on a phone-sized viewport: the step card, the quest panel, the level
  rewards button and the touch controls.
- The daily quest playtime counter keeps ticking during the tutorial, but the drill ball
  doesn't count as a quest dodge.
Fix the bugs you find. Then update docs/STATUS.md (a new dated section on what's built and
verified) and docs/HANDOFF.md (the new flow, dev shortcuts and RD_Gallery hooks). Say plainly
what you verified by eye, what only numerically, and what you couldn't check.
```

## 10. Level rewards

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Problem: XP and levels exist (Config.Progression, src/shared/Progression.luau,
RewardService.awardMatch), but leveling up grants nothing (docs/ECONOMY.md says so). Read
docs/ECONOMY.md first.

Files: src/shared/Config.luau (Config.Progression), src/server/Services/RewardService.luau,
src/server/Services/DataService.luau (an additive profile field; the tutorial already bumped
the schema, so don't bump it again unless a migration really needs it), src/shared/Catalog.luau
(earn-only titles), a new src/client/Controllers/LevelRewardsController.luau wired up in
src/client/Bootstrap.client.luau (a parallel chat may add its own controller line there too, so
add only yours), tests/offline/tests.luau, docs/ECONOMY.md. Don't edit PracticeController or
TutorialController (another chat owns them in this wave).

Build:
- A reward table for levels 1–100, using the typed rewards RewardService.grant already
  supports (Coins, Spin, Chest, Boost, Cosmetic). Proposed pattern: most levels about 50
  coins; every 5th a quest chest or a Rare+ bonus spin; every 10th an earn-only title (a
  Catalog `Unlock` item, like the Power Ball Mastery titles: never sold, spun or rolled). Check
  the totals against the earn rate in ECONOMY.md and add a short section there.
- Server: grant on level-up. Players can claim, or rewards auto-bank (your call; the user
  prefers things to happen immediately). Save the claimed levels in the profile (additive,
  like PowerKOs). Existing players get every level they've already passed, once, without
  double-paying. The tutorial's one-time completion reward (TutorialService) is a separate
  grant: don't fold it in.
- Client: a "Level rewards" sheet (Theme.sheet) reachable from the level display. It's a paged
  grid of level cards: claimed ones get a check, locked ones a lock, and the big milestones
  stand out. Use the Theme.dot notification when something is claimable. Use no uploaded
  images: frame-built art or built-in glyphs only. It must not open during the tutorial
  (TutorialDone ~= true) or a match.
- Add a level-up banner/feed moment when you cross a level in a match.
- Tests: offline tests for the table (every reward valid), the grants, existing players'
  back-pay and no double-pay. Then check in Studio and say what you verified.
```

## 11. Group-join reward kiosk

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Context: Roblox can't verify a "like", so we reward joining the game's Roblox group instead
(verifiable with Player:IsInGroup). FavoriteController already asks winners to favourite;
leave it as is. Read docs/RELEASE_PLAN.md (compliance: like/reward mechanics need the
developer's sign-off) and docs/ECONOMY.md first.

Files: src/shared/Config.luau (Config.GroupReward), src/server/Services/LobbyBuilder.luau
(the kiosk prop), a small server handler (RewardService or a new GroupRewardService wired up in
src/server/Bootstrap.server.luau), src/server/Services/DataService.luau (an additive profile
flag), src/client/Controllers/PromptController.luau if prompts route through it,
tests/offline/tests.luau.

Build:
- Config: Config.GroupReward = { GroupId = 0, Reward = a typed reward, e.g. a Rare+ bonus
  spin or coins }. GroupId 0 is a placeholder: ask me for the real id, and keep the kiosk
  hidden and disabled while it's 0.
- Hub kiosk: a chest prop on the deck, matching the existing Stations/kiosk style
  (Config.Lobby.Stations, LobbyBuilder), with a ProximityPrompt "Group reward · Claim". Use no
  uploaded meshes. Keep it clear of the practice area where the tutorial runs, the Halloween
  props and the bundle stand.
- Server: check IsInGroup on claim (pcall, re-check on every press), then grant once per
  account through RewardService.grant (save a flag in the profile). If they're not in the
  group, the client shows a friendly hint ("Join the group, then come back!"). Blocked while
  TutorialDone ~= true.
- Offline tests: granted once, refused when not a member, the flag survives migration. Check
  in Studio as far as Studio allows (IsInGroup may need a real group id) and say what you
  couldn't verify.
```

## 12. Lobby sightline and first-visit guidance

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/build-path.md (the run order and
the tutorial's shared step contract; don't change the contract). UI work follows the Toybox
Island design system (link in README.md) and src/client/UI/Theme.luau: bold and poppy, Day
theme, no uploaded assets. After changes run selene src, stylua on the files you touched,
lune run tests/offline/run and luau-lsp (it needs .luau-lsp/globalTypes.d.luau; if that file
is missing, say so instead of skipping quietly). Don't commit. Don't add anything about
"spirits" (that idea is shelved). The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.

Context: players spawn facing the live court (LobbyService uses ArenaLayout.CourtFocus), a
deliberate "watch the match" design. A competitor spawns players facing their shop packs. We
want the benefit of that without losing the court view. The guided tutorial (practice end of
the deck) and the group reward kiosk are already built; read the Halloween and Haunted Bundle
stand sections of docs/HANDOFF.md.

Files: src/client/Controllers/BundleDisplayController.luau, src/shared/Config.luau (Display
spots, Config.Lobby), src/client/Controllers/BallGuideController.luau (reuse only: it also
drives the tutorial's step 1 and jail arrows, so don't break those),
src/server/Services/DataService.luau (an additive "seen" flag), and a small client controller
for the guidance if needed.

- Move or extend the featured-offer display so it sits on the spawn → court sightline, in view
  on spawn without blocking the court: the Haunted Bundle stand while an offer is live, else a
  turning "featured ball of the day" plinth using ShopService.featuredBall. Check it doesn't
  overlap the Halloween props (Config.Halloween.Props), the group kiosk or the practice area;
  the stand's current spot (X 12, F -14) was never checked.
- First-visit guidance: after the tutorial's Done card and the daily sheet have closed, reuse
  BallGuideController's floor chevrons to lead the player once to the Shop kiosk, then point at
  the quest panel. Show it once per account (saved flag) and cancel it as soon as they open the
  shop or press PLAY.
- Keep the hub uncluttered: nothing new over the centre of the screen.
- Check in Studio from a fresh save (dev reset tutorial, then finish it) and a returning save.
  Take screenshots from the spawn camera, and verify positions numerically, since screenshots
  can be stale.
```
