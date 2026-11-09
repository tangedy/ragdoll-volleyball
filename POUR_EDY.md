# Pour Edy: where Ragdoll Dodgeball is now (Nov 8, 2026)

Hey Edy. Your last commit was `3910e2a` ("mobile UX", Oct 30). Since then there have been 21 commits on `main` (75 files, about +14,900 / −1,500 lines). This doc covers the game as it plays today, what changed since you left, and what still needs a person.

`main` is at `bde21a9` and pushed. The `feature/equippable-powers` branch is merged into it (a fast-forward, no merge commit).

For setup, controls and dev keys, see the [README](README.md). For the full history, see [docs/STATUS.md](docs/STATUS.md). The working notes for Claude sessions are in [docs/HANDOFF.md](docs/HANDOFF.md).

---

## The 30-second version

- **The game:** throw balls at the other team to build their damage %, like Smash. A hit launches them in a ragdoll, and the higher their %, the further they fly. Knock them off the floating court and they go to jail. It's best of 3 rounds, and bots fill the teams.
- **New players** play a 6-step guided tutorial on their own copy of the court before they reach the hub.
- **The hub** has a big **PLAY** button. A player alone in the hub is queued automatically. You can **join a match in progress** in place of a bot, and **Leave Match** hands your slot to a bot that takes your name.
- **Powers are the big new system.** The random power-ball dispensers are gone. Every player equips a **power**, modelled on Racket Rivals: an active on a cooldown, plus its own ultimate that charges up. There are 16 powers across 6 rarities, a **Power Wheel**, an **Extra Power Slot** game pass, and **mastery** levels for each power.
- **Spending coins** got a lot of work: daily deals, a saving-for goal chip, collection titles, level rewards, and a Starter Pack plus VIP and 2× Coins passes.

---

## What changed since your last commit, by area

### 1. Combat feel (Oct 30 – Nov 1, the "tizzy" commits and `db1a74e`)
- **No more charging.** Every throw is instant and full power: tap to throw (`Config.Player.ThrowSpeed` = 170). Throw recovery went from 0.4 s to 0.25 s. Bots throw at 0.75× speed.
- **Damage % replaces hit counting.** Each hit adds `Config.Damage.PerHit` (24) × the ball type's `DamageScale`, scaled up to 1.6× for close-range hits. Knockback escalates with your % (`Config.Knockback.Escalation`), and a new `DamageController` draws a % billboard over every opponent.
- **Homing:** a player's throw bends gently toward the enemy nearest its line (`Config.AimAssist.Homing`). The server broadcasts `BallCourse` so clients blend onto the new arc. A well-timed dodge breaks the homing; walking away doesn't.
- **Instant local throw feedback:** the sound, an FOV kick and a little shake play on your own client right away. Haptics were added on Nov 4.
- **Court changes:** 8 balls per court (was 6). The match flow and spectator were also reworked in these commits.

### 2. Onboarding (Nov 2: `7410bc8`, `44f41d3`, `bb544c4`)
- **Guided tutorial:** 7 steps (Grab → Hit → Knock off → Heavy ball → Discover → Dodge drill → Done). It runs on a **client-only copy of the court** (`PracticeController`). The server only moves you forward on each step's own event, never more than one step a burst. The Done step pays a 500-coin reward once.
- **The PLAY button replaced Ready:** pressing it queues you and shows "Waiting for next match · N" with Cancel. Nobody is queued until they press PLAY.
- **The Dodge drill** (`TutorialDrillController`): the dummy throws practice balls at you until you dodge one.
- **Playtest checklist:** [docs/TESTING.md](docs/TESTING.md).

### 3. Hub, matches and joining (Nov 2 – Nov 6)
- **Join in progress** (`32ee463`): after the tutorial, joining or pressing PLAY during a live round drops you in place of a bot. You keep its spot and damage %, and get 2 s of hit immunity. PLAY reads **JOIN MATCH** while a bot slot is open.
- **Leave Match:** a top-left button with a confirm card takes you back to the hub. Anyone who leaves (by the button or by quitting) is replaced by a **stand-in bot** with their name, avatar and state.
- **Solo auto-queue** (`76dcc7a`): a lone player in an idle hub is queued automatically. Right after the tutorial the match starts within about 5 s. Cancel or Leave opts you out until you press PLAY again.
- **Hub dressing:** string lights on corner masts, a group-reward kiosk by the shop, and a featured stand that shows a **ball skin of the day** (its prompt opens the shop on that skin).
- **Combat buttons in the hub:** Dodge, Catch and Lock are hidden in the hub, and Throw only shows while you hold a ball. A credited dodge in a match shows a **NICE DODGE!** banner and pays coins.

### 4. Economy and monetization (Nov 2 – Nov 6: `44668cc`, `47b581f`)
- **Level rewards** for every level from 2 to 100 (`LevelRewardsController`), banked as you reach each one.
- **Starter Pack:** a one-time product for 99 R (developer product `3727439082`). It gives the Galaxy skin, the Neon Ace title, 5,000 coins and 30 min of 2× coins.
- **Game passes:** **VIP** (a gold name tag, plus a free spin and 150 coins every day) and **2× Coins Forever** (`GamePassService`). Both have real pass ids.
- **Value tags** on Robux bundles (`BundleValue`): the bonus %, "Best value" and what it's worth.
- **Daily deals:** one unowned item per shop tab at 25% off, picked per player per UTC day.
- **Saving-for chip** (`SavingController`) over the hub coin card: the item you're saving for, with a "+" that opens the Coins sheet.
- **Shop dot** on the Shop button when there's something new you can afford.
- **Four collection titles**, earned by owning a whole set.
- **Quests:** the tutorial reward is now 500. The playtime quest has a shorter first goal each day (8 min, then 12).
- **Analytics funnels** (`AnalyticsService`): onboarding (through your first two games and 12 minutes played), coin purchases, and play-after-loss.
- Full details are in [docs/ECONOMY.md](docs/ECONOMY.md).

### 5. Powers (Nov 6: `b12d7df`, `bde21a9`), the big one

**How it plays**
- Everyone equips a **power**. Its **active** is on a cooldown: **F** on PC, **Y** on a controller, the **POWER** button on touch.
- Each power comes with its own **ultimate**: **R**, **B** on a controller, or the **ULT** button. A meter fills from hits (closer hits give more), catches, knockouts, dodges, taking hits, and a slow trickle. The meter resets every round.
- An ultimate starts with a 0.9 s **wind-up**: the caster's camera pushes in, everyone sees a banner, and the caster can't be hit. The match never pauses.
- **Ball powers** turn the ball you're holding into a power ball. An ultimate ball turns back to a plain ball if it's dropped or **caught**, so catching is the counter.
- **Self powers** act on you or the court.
- **Bots** get a random power, weighted by rarity, and use both their active and their ultimate.

**The 16 powers**

| Rarity | Power | Active | Ultimate |
|---|---|---|---|
| Free starter | Heavy | Heavy ball | **Meteor**: a giant ball whose shockwave hits everyone near the impact |
| Common | Rocket | Rocket ball | **Barrage**: your throw plus 2 homing rockets |
| Common | Curve | The ball bends hard onto its target | **Boomerang**: the ball comes back to your hand |
| Common | Bounce | The ball ricochets into a second enemy | **Pinball**: it bounces through up to 4 enemies |
| Rare | Pop | Pop ball (launches the target upward) | **Geyser**: launches everyone near the landing spot |
| Rare | Blink | A short teleport, briefly untouchable | **Phantom**: 4 s untouchable and faster |
| Rare | Shield | A 1.5 s bubble that catches (or blocks) the next ball | **Fortress**: a wall on your side of the line stops enemy balls for 4 s |
| Rare | Grapple | Yanks the nearest enemy toward the centre line | **Tether**: chains two enemies; hit one and both fly |
| Epic | Magnet | Pulls the nearest loose ball into your hand | **Ball Storm**: 5 extra balls drop on your side |
| Epic | Decoy | Vanish for 2 s, leaving an afterimage (homing, aim assist and bots lose you) | **Mirror Squad**: 3 copies of you each throw a real ball |
| Epic | Gravity | The ball drags nearby enemies in | **Black Hole**: a vortex behind the enemy line pulls them toward the edge |
| Legendary | Frost | The ball freezes its target (they can still be hit) | **Time Stop**: freezes every enemy for 2.5 s |
| Legendary | Giant | 1.5× size for 5 s, taking only 45% knockback | **Titan**: 2× size; every step sends out a shockwave |
| Legendary | Thunder | The hit chains lightning to 2 nearby enemies | **Storm Cloud**: 5 lightning strikes |
| **Mythic** | Rewind | Back to where you were 3 s ago, with that damage %. Works mid-tumble. | **Replay**: your whole team rewinds |
| **Secret** | Void | Balls pass through you for 1 s | **Edge Collapse**: anyone near the enemy court's edges gets flung off for 4 s |

**Getting powers**
- **Shop:** a new **Powers** tab, with prices by rarity from 500 to 25,000 coins.
- **Power Wheel** (a new hub button, "Power Wheel"): 2,500 coins a spin, 3 spins a day, and a power you already own pays duplicate coins. It's never available where paid random items aren't allowed (`ComplianceService`).
- **Mythic and Secret** are new power-only tiers above Legendary, on the Power Wheel at 0.8% and 0.2%. Winning one is announced to the whole server. Secret powers can only be won on the wheel.

**Extra Power Slot pass:** a second active on **V** (D-pad up on a controller). The ultimate always comes from slot 1, to keep the pay-to-win edge small. With the pass, equipping a new power moves your previous one to slot 2.

**Mastery:** each power levels from 1 to 5 using XP it earns while equipped: +1 per hit, +4 per knockout, +1 per active used, +3 per ultimate used.
- Levels cut the cooldown (−8% at level 2, −15% at level 4) and speed up the ultimate meter (+10% at level 3, +15% at level 5).
- At level 5 the power is **Mastered** and its ultimate goes off in gold.
- Levels show as stars on the HUD button and the shop card.

**Where the code lives**

| File | What it does |
|---|---|
| `src/shared/PowerDefinitions.luau` | The roster, each power's tuning, and the mastery maths |
| `src/server/Services/PowerService.luau` | All server logic: cooldowns, the meter, every active and ultimate, freezes and other timed effects, mastery, bots |
| `src/client/Controllers/PowerController.luau` | The buttons, keys, meter, and every effect |
| `Config.Powers` in `src/shared/Config.luau` | All the numbers: the meter, wind-up, Power Wheel, bot weights, mastery |
| Catalog category `"Power"` | The shop items. They're the one Catalog category that changes gameplay, and they never appear on the cosmetic wheels or in chests. |
| New ball types (`BallDefinitions`) | Frost, Meteor, Curve, Bounce, Gravity, Thunder |

**Other changes that came with powers**
- **Damage bug fixed:** power-ball hits used to add only normal damage %, because the ball switched back to Standard before damage was counted. Power balls now hit as hard as designed, so the game is a bit harsher than before.
- **New remotes:** `UsePower`, `UseUltimate` and `SpinPower`, plus the `PowerFx` feedback event ([docs/REMOTES.md](docs/REMOTES.md)).
- **Tutorial step 5** now says "That was your HEAVY power!" instead of promising random balls.
- **Studio dev commands** go through the `Dev` remote: `FillUlt`, `PowerSlot` (grants the pass), `AllPowers`, and `Power:<id>` (swaps your power mid-match, e.g. `Power:Thunder`).

---

## Things that need a person (no code can do these)

| What | Where | Why |
|---|---|---|
| Create the **Extra Power Slot** game pass | `Config.CoinShop.Passes.PowerSlot.PassId` (0 now) | Nobody can buy slot 2 until this exists (it works in Studio via the `PowerSlot` dev command) |
| Create the **Power Wheel spin** developer product | `Config.Powers.Wheel.RobuxProductId` (0 now) | Power Wheel spins are coins-only until then |
| Optional images (pass icons, spin button, card art) | the `PLACEHOLDER` comments in `Config.luau`, [docs/PASS_ICONS.md](docs/PASS_ICONS.md) | Cosmetic only |
| Balance pass on powers | `Config.Powers`, `PowerDefinitions` | Every number is a first guess |
| Publish | Studio → File → Publish | Rojo only syncs into the open place (placeId `101235501560927`) |

---

## How sure we are (testing)

- **Offline tests:** run `lune run tests/offline/run`. The result is **91 / 92 passing**. The one failure, "playtime pays 1st then repeat coins", predates powers (it fails on the pre-powers commit too) and comes from the playtime quest's new first-claim goal. It should get a look.
- **`selene src`:** 0 errors and 0 warnings.
- **`luau-lsp`:** a couple dozen type errors, all in older files (Config's quest table, JackOLantern, QuestService and others). The powers work added none.
- **Powers in a live Studio match (solo plus bots):** every one of the 16 actives and ultimates fired with no server errors, and bots used theirs. These were confirmed by numbers:
  - Heavy and Frost turned the held ball into a power ball, with cooldowns running.
  - Meteor's shockwave hit a second enemy; Time Stop froze 3 bots and the ice cleared afterwards.
  - Barrage launched 3 rockets; Pinball made 3 hits; Boomerang came back to my hand.
  - Fortress raised its wall; Giant scaled to 1.5× and back, Titan to 2×.
  - Rewind and Replay worked; Edge Collapse pulsed.
  - Mastery took Blink to level 2, and its cooldown went from 10 s to 9.2 s.
- **Not checked by eye:**
  - The power buttons' layout on a phone and with a gamepad.
  - The shop's Powers tab and the stars on its cards.
  - The Power Wheel sheet.
  - A full Grapple yank (enemies were always already near the line).
  - My own Thunder chain (my throw missed; a bot's chain did show up).
  - A Mastered gold ultimate.
  - Any of this with two or more real players.
- The tutorial, PLAY, join-in-progress and Leave flows were checked in Studio when they landed (details in STATUS.md, Nov 2 and Nov 5).

---

## Good next steps
1. **Playtest the powers on a phone.** The power buttons sit just left of the action cluster, and your mobile UX eye would help here.
2. **Fix the playtime quest test.**
3. **Create the two Robux items** above, then add a **pity counter** to the Power Wheel (a guaranteed Legendary by spin 50, Mythic by 150).
4. **Balance the powers** after real matches. Watch Frost/Time Stop, Black Hole and Edge Collapse; those are the strongest.
5. **The next planned system** is a second power layer, **Fruits**: one at a time, a passive plus a changed dodge, spawning from a hub fruit tree. The plan was drafted in chat but not started.

If anything here doesn't match what you see in Studio, trust the code and [docs/STATUS.md](docs/STATUS.md). This doc is a snapshot as of `bde21a9`.
