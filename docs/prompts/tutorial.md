# First-time tutorial + Play button: chat prompts

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

## What we're building

A guided, step-by-step tutorial in the hub that a new player must finish before they get into
a match. The steps:

1. Pick up a ball.
2. Hit the dummy. Point out that the dummy's % went up, and where the player's own % is shown.
3. Keep hitting the dummy until it's knocked off.
4. The dummy comes back at 50%, and the player gets a **Heavy** practice ball. One Heavy throw
   knocks it off.
5. Tell the player there are more special balls to find (Rocket and Pop).
6. The dummy throws at the player, and the player dodges (Q, the Dodge button or the gamepad).
7. Done: show the rewards. The corner button is now a big **PLAY** button. Pressing it changes
   it to "Waiting for next match · 25", counting down.

## Run order

Run each prompt in a fresh chat. Commit, or at least check the diff, between waves.

| Wave | Chats | Why |
| --- | --- | --- |
| 1 | **A** (server step machine) | Sets up the step numbers and event names the others use |
| 2 | **B** (dummy and Heavy ball), **C** (tutorial UI), **D** (Play button), in parallel | Each one has its own files |
| 3 | **E** (dodge drill) | Edits `PracticeController.luau` again after B |
| 4 | **F** (Studio playtest and polish) | Needs everything merged |

Suggested effort: A high, B high, C medium, D medium, E high, F high.

**Shared contract** (A builds it; B–E rely on it, so don't rename anything):

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

Every prompt starts with the same preamble. Paste it above the prompt.

```
Roblox/Luau project (Rojo), Ragdoll Dodgeball. Read docs/HANDOFF.md first (how to work here,
checks, Studio MCP tips, user preferences) and docs/prompts/tutorial.md (the plan and the
shared step contract; don't change the contract). UI work follows the Toybox Island design
system and src/client/UI/Theme.luau: bold and poppy, Day theme. Run selene, stylua and
luau-lsp after changes. Don't commit. The working tree may already have uncommitted changes to
other files: leave them alone. Stay inside the files this prompt names; if you must touch
another file, keep it minimal and say so.
```

---

## A. Server tutorial step machine, save migration, queue gate, reward

```
Rewrite the tutorial's server side for the new guided hub tutorial in docs/prompts/tutorial.md
(the 7-step table there is the contract).

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
  DevRoomService keeps visitors out of the queue). Bots and TestService fixtures must still work.
- Add a dev shortcut next to the existing RD_Gallery / Dev command handling: reset my tutorial
  to step 1, and skip it to Done. Both Studio-only.
- Add TestService checks: steps advance only in order, the reward is paid once, the
  migration maps old steps correctly, and an unfinished player isn't queued.
Run the offline tests (lune run tests/offline/run) and update any that the change breaks.
```

## B. Practice dummy % billboard, 50% respawn, Heavy practice ball

```
Client hub practice changes for the guided tutorial (docs/prompts/tutorial.md, steps 2–4).
The server side (prompt A) is done: the Tutorial net message tells you the current step, and
the Practice remote accepts DummyOut and HeavyOut.

Files: src/client/Controllers/PracticeController.luau (main), plus maybe
src/shared/ProjectileMath.luau and src/shared/Config.luau (Config.Practice / Config.Tutorial).
Don't edit TutorialController.luau or HUDController.luau (other chats own those).

1. Damage % over the practice dummy: a billboard like DamageController's enemy tags (same
   font, white → sun → red from ProjectileMath.damageColor, and the same pop when it goes up).
   Show it always, not just during the tutorial. Today the % is only the local dummyDamage.
2. When the dummy falls below ArenaLayout.LobbyVoidY, send Practice { event = "DummyOut" }.
   Send it only for a dummy the player knocked off, not one that respawned or was cleared.
3. Heavy step (tutorial step 4): the next dummy stands up at 50% (Config.Tutorial.HeavyDummyDamage
   = 50) and one practice ball turns into a Heavy ball (BallDefinitions Heavy: its colour,
   material and RadiusScale, and the server's BallVisualController look if that's easy to reuse;
   the Halloween pumpkin rule says power balls keep their colours). Practice flight, damage and
   knockback must use the ball's own type: today launchDummy and stepFlight hard-code
   "Standard". Make it type-aware.
4. One Heavy hit from 50% must reliably knock the dummy off the deck. Work it out from
   ProjectileMath.escalation / knockback / maxKnockbackSpeed and the deck size, and check it in
   Studio from short, medium and long range. If it doesn't reliably knock it off, add a
   tutorial-only boost (Config.Tutorial.HeavyLaunchScale) rather than changing match balance.
   When it goes off, send Practice { event = "HeavyOut" }. If the player misses or the dummy
   stays on, the Heavy ball comes back so they can try again.
5. Outside the tutorial, practice behaves the same as before (Standard balls, 0% respawn).
Expose a small API that prompt E (the dodge drill) will need: PracticeController.dummyModel()
and a way to pause the player's practice balls (PracticeController.setBallsEnabled(bool)).
Verify in Studio with the Studio MCP and report what you measured.
```

## C. Tutorial cards, callouts and the completion screen

```
Rebuild the tutorial's client presentation for the guided hub tutorial (docs/prompts/tutorial.md).
The server (prompt A) sends Tutorial { step = 1..7 } and { reward } on completion.

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
  prompt F.
- 3 KnockOff: "Knock it off the edge!"
- 4 Heavy: "You got a HEAVY ball!" and a ball sticker in the Heavy colour. "One throw does it."
- 5 Discover: a short card showing Heavy (found) and Rocket and Pop as "?" silhouettes in their
  colours: "More special balls to discover in matches!"
- 6 Dodge: "Dodge it!" with the input's dodge key (Q / Dodge button pulse / gamepad), using the
  same pulsing touch-button outline as today.
- 7 Done: a celebration overlay (confetti if Theme has it, the success sound) showing the reward
  (count the coins up like the results card does), "You're ready!" and one button that closes it.
  Closing it hands over to the PLAY button (prompt D).
- The catch tip is no longer a tutorial step. Keep it as a one-time in-match hint for a
  player's first few matches (follow the Config.Damage.HintMatches pattern).
- Don't auto-open the daily rewards sheet (ShopController's autoOpened) while TutorialDone
  isn't true; open it after the Done card closes. This is the one change allowed outside
  TutorialController.
- Phones: the cards must fit next to the touch controls (see the HANDOFF "Phone layout" notes).
Update the RD_Gallery Tutorial1..TutorialN hooks (DebugController) so every step can be
screenshotted. Take screenshots of each step in Studio.
```

## D. Big PLAY button and the "Waiting for next match" countdown

```
Replace the hub's Ready button with a big PLAY button (docs/prompts/tutorial.md, last step).

Files: src/client/Controllers/HUDController.luau (the "Corner" Ready block ~line 567 and its
update ~line 1222), src/server/Services/MatchService.luau (setReady / the intermission loop
~line 1196), src/server/Services/LobbyService.luau (the SetAutoQueue handler only; prompt A
owns the Practice handler and the queue gate), src/shared/NetSchema.luau if you need a new
action.

How it works:
- In the hub, not in a match, with the TutorialDone attribute true and not queued: a big,
  loud PLAY button (much bigger than Ready is today: leaf green, chunky ledge, a gentle
  breathing pulse; Toybox button style). The TutorialDone attribute comes from prompt A.
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
Check it in Studio: a fresh join after skipping the tutorial (dev skip from prompt A), the
countdown, cancel, and coming back after a match with Play again on and off.
```

## E. Dodge drill: the dummy throws at the player

```
Build the tutorial's dodge step (docs/prompts/tutorial.md step 6). Prompts A–C are merged:
PracticeController has dummyModel() and setBallsEnabled(), the Practice remote accepts Dodged
and GotHit, and TutorialController shows the "Dodge it!" card.

Files: a new src/client/Controllers/TutorialDrillController.luau (wire it up in
src/client/Bootstrap.client.luau like the other controllers), and small hooks in
PracticeController.luau if needed. Dodging itself is server-side
(CombatService.doDodge allows status "Lobby"); the client gets DodgeAccepted and DodgeMotion
moves the character. Read src/shared/DodgeMotion.luau and CharacterController's dodge
prediction.

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
Check in Studio with mouse, touch (RD_Gallery "Touch") and gamepad prompts. Use the MCP to
trigger dodges (see the HANDOFF notes on reliable input) and report what you verified by eye
and what you only checked numerically.
```

## F. Full playtest, polish and docs

```
All tutorial prompts (A–E in docs/prompts/tutorial.md) are merged. Do an end-to-end Studio
playtest as a brand-new player (dev reset tutorial to 1) and fix what's rough.

Walk the whole flow at least twice, once with mouse and once with touch (RD_Gallery "Touch"):
join → no daily sheet → grab → first hit and both % callouts → knock off → 50% dummy and Heavy
ball one-shot → discover card → dodge drill (dodge once, then get hit once) → completion and
reward → daily sheet → PLAY → "Waiting for next match · 25" counting down → match → back to
the hub.
Check: the step order can't be broken (spam throws, walk away mid-step, die in the void
during the drill, rejoin mid-tutorial and resume on the right step), a returning player
(migrated save) never sees it and gets PLAY at once, the reward is paid exactly once, no new
player is ever put in a match before finishing, and nothing overlaps on a phone-sized
viewport.
Fix the bugs you find. Then update docs/STATUS.md (a new dated section on what's built and
verified) and docs/HANDOFF.md (the new flow, dev shortcuts and RD_Gallery hooks). Say plainly
what you verified by eye, what only numerically, and what you couldn't check.
```
