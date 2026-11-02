# Playtest checklist: tutorial, PLAY button, dodge drill

Thanks for testing! This covers three new things that nobody has watched in a real game yet:
- **The guided tutorial:** 6 steps on your own practice court before your first match.
- **The dodge drill:** step 6, where the dummy throws balls at you.
- **The big PLAY button:** it replaces the old Ready button in the hub.

Work through the list and note anything that looks wrong, feels unfair, or confuses you. Screenshots
or a short clip help a lot. There's a report template at the bottom.

## How to play it

**Live game (easiest).** The developer has to publish the latest build first, so ask them. Then join
**Ragdoll Dodgeball** with an account that has **never played it**: only brand-new players get the
tutorial. If you've played before, use Studio below or ask the developer to reset you.

**Studio** (if you have the project). Open the place with Rojo running and press Play. Studio
can't save, so you start as a new player every time. Two shortcuts, typed into the client command
bar:
```lua
game.Players.LocalPlayer:SetAttribute("RD_Gallery", "TutorialReset") -- back to step 1
game.Players.LocalPlayer:SetAttribute("RD_Gallery", "TutorialSkip")  -- skip to done (no reward)
```
Set it to `""` between uses.

Please test once with a **mouse and keyboard**. If you can, also test on a **phone** or with a
**gamepad**.

## 1. Joining

- [ ] The loading screen lifts and you're on a court (not the busy hub), facing a dummy on the far
      side.
- [ ] The daily rewards sheet does **not** pop up yet.
- [ ] A step card at the top centre reads "Grab a ball!" with a counter (1/6).
- [ ] There's **no** PLAY button and no "Getting a match ready..." text: you can't get into a match
      yet.

## 2. The tutorial steps

| Step | Card says | Do this | Expect |
| --- | --- | --- | --- |
| 1 | Grab a ball! | Walk over a ball | Floor arrows lead you to it; picking it up moves you on |
| 2 | Hit the dummy! | Throw at the dummy | A % over its head goes up |
| 3 | Its % went up! → Knock it off the court! | Keep hitting it | Each hit throws it further; it flies off the court |
| 4 | You got a HEAVY ball! | Grab the big orange ball and throw it | The dummy comes back at 50%; one Heavy hit knocks it off. Miss, and the Heavy ball comes back to try again |
| 5 | More special balls to find! | Nothing | Moves on by itself after about 4 s |
| 6 | Dodge it! | See section 3 | |
| Done | Celebration | Press the button | Coins count up, confetti; you're moved to the hub and the daily sheet opens |

- [ ] Each step change has a "Nice!" beat and a sound.
- [ ] The step card never covers the quest panel (left edge) or anything you need.
- [ ] Throwing lots of balls quickly never skips a step.

## 3. The dodge drill (step 6)

The dummy turns to you, shows a red **!** over its head and a glowing ball in its hand, then throws
at you. Dodge with **Q**, the **DODGE** button on touch, or **X** on a gamepad.

- [ ] Your own practice balls disappear for this step.
- [ ] The **!** and glowing ball give you enough warning to react.
- [ ] The throw is fair: dodgeable, but not so slow that it's boring.
- [ ] **Dodge it once.** You should see "NICE DODGE!" and go straight to the Done celebration.
- [ ] **Let it hit you once first** (stand still, don't press anything). Expect a small knock (no
      ragdoll), a "See? YOUR % went up!" hint, and another throw about 1.5 s later.
- [ ] Get hit 3 times in a row. The 4th throw should be noticeably slower.
- [ ] Walk out of the way without dodging. That shouldn't count: expect "Dodge it as it comes!" and
      another throw.
- [ ] Dodge while standing still (no direction held). It should still count as a dodge.
- [ ] After Done, your practice balls come back in the hub.

## 4. The PLAY button (in the hub, after the tutorial)

- [ ] A big green **PLAY** button sits bottom right (top right on a phone). It gently pulses.
- [ ] Text at the top says "Press PLAY to join a match".
- [ ] Press PLAY. The button turns yellow and reads **"Waiting for next match · 25"**, counting down.
      A small **Cancel** appears.
- [ ] The countdown runs the **full** 25 s (it doesn't jump early), then the match starts.
- [ ] **Cancel** puts it back to PLAY and stops the countdown.
- [ ] In Settings, turn **Play again on**, play a match, then go back to the hub. You should come back
      already counting down.
- [ ] Turn **Play again off**, play a match. You should come back to the PLAY button, not a
      countdown.
- [ ] Gamepad: you can select PLAY and press it with A.
- [ ] Phone: PLAY is easy to tap and doesn't overlap the touch controls, the quest panel or the hub
      icons.

## 5. Things that shouldn't happen

- [ ] Being put in a match before finishing the tutorial.
- [ ] Getting the tutorial reward twice (rejoin after finishing to check).
- [ ] Getting stuck on a step: try walking away mid-step, falling off the court, or leaving and
      rejoining mid-tutorial. You should resume on the same step.
- [ ] The daily quest "Dodge 5 balls" going up from the tutorial drill (it should only count match
      balls).

## Report template

```
Device / input: (PC mouse, phone, gamepad)
Live or Studio:
Steps that worked:
Bugs (what you did -> what happened -> what you expected):
Confusing or unfair moments:
Drill: too fast / too slow / about right
Screenshots / clips:
```
