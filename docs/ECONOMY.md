# Economy

Audit as of Oct 28, 2026 (save schema v10). **Coins** are the only currency. XP and levels exist, but leveling up grants nothing. (Since Nov 2 every level pays a reward: see §8.)

Already decided (not open for discussion here): the lobby chests are removed, and chests come only from daily quests. Knocking out 3 opponents earns a Title Chest, playing 2 games a Gesture Chest, and winning 1 game a Finisher Chest.

## 1. Current state

### Coin sources

| Source | Amount | Where | Notes |
| --- | --- | --- | --- |
| Match win, best tier only | 200 win · 300 alive at the win · 500 flawless · 600 final KO | `Config.Coins`, `RewardService.coins` | Needs ≥1 action (anti-AFK). ×2 with a boost. |
| Match loss | 50 | `Config.Coins.LossParticipation` | Only for finished, non-aborted matches. ×2 with a boost. |
| Elimination | 25 per KO, paid instantly | `MatchService.eliminate` | A bot KO pays the full 25 (bot XP is halved, bot coins aren't). ×2 with a boost. |
| Daily login ladder | 250 / 400 / 600 on days 2, 4 and 6 (1,250 a week) | `Config.DailyRewards`, `ShopService.claimDaily`, `RewardService.grant` | Typed rewards since save schema v11 (section 3): the other days give bonus spins, a boost and an Epic pick. A missed day resets you to day 1. |
| Spin duplicate | 100 / 250 / 500 / 1,000 (C/R/E/L) | `Config.Spin.DuplicateCoins` | |
| Chest duplicate | 250 / 400 / 700 / 1,200 | `Config.Chest.DuplicateCoins` | A different table from the spin's. |
| Robux bundles | 1,000 / 2,750 / 6,000 / 16,000 / 35,000 coins for 49 / 99 / 199 / 499 / 999 R | `Config.CoinShop.Bundles` | Boosts never double these. |
| Robux spin in a restricted region | 1,000 | `SpinService` receipt fallback | Edge case. |
| Dev `GiveCoins` | 1,000,000 | `MatchService` | Studio only. |

**Earn rate** (from STATUS.md): a solo bot match takes about 4–5 minutes and averages about 250 coins at a 50% win rate. That's about 3,000–3,750 coins an hour.

### Item sources (non-coin)

| Source | Gives | Limit |
| --- | --- | --- |
| Free daily spin | 1 cosmetic (wheel 60/28/10/2) | 1 per UTC day |
| Paid spin | 1 cosmetic | 1,000 coins each, 5 a day; or Robux (product 3723376241; the Config comment says 35 R and STATUS.md says 25 R, which needs checking) |
| Common Chest (lobby) | Any rarity (60/28/10/2) | 1,200 coins; free once a day after 1 match |
| Rare Chest (lobby) | Rare+ (70/24/6) | 2,200 coins; free once a day after 3 matches |
| Epic Chest (lobby) | Epic+ (80/20) | 3,500 coins; never free |
| 2x Coins boost | Doubles match and KO coins | 19 R per 30 min, or 199 R forever |
| Haunted Bundle (`Config.CoinShop.Offers`) | Jack-o'-Lantern skin (the carved pumpkin ball, kept all year), Pumpkin Head pose, Pumpkin Reaper finisher, Ghost title (special name tag), Witch's Brew skin, Ectoplasm trail, Pumpkin King title (all bundle-only Limited items) + 5,000 coins | 299 R, Oct 28 – Nov 3 UTC. Developer product 3723612223 (created Oct 29). |

Bundle-only items (`Item.Bundle`) are never sold for coins and never appear on the wheels, so they're left out of the cosmetics table and the chest pools below.

| Robux-exclusive cosmetic (`Item.Exclusive`) | 1 cosmetic | Ball skins and trails 79 R (Epic) or 199 R (Legendary), `Config.Economy.RobuxPriceByRarity`; titles and gestures 39 R or 99 R, `RobuxPriceByCategory`. One developer product per item (`Item.RobuxProductId`). |

Robux-exclusive items are also never sold for coins and never appear on the wheels or in the chest pools (`Catalog.isOffered`, `SpinService.pool`). Unlike bundle items, they're always on the shelf, with an EXCLUSIVE tag and a Robux button that prompts the item's own product, once Robux buttons are unlocked (the same `RobuxOk` rule as the Coins sheet). `PurchaseService` registers one handler per exclusive, which adds the item to `OwnedCosmetics` the same way bundles do. Exclusives are Epic or Legendary only. Their `Price` is only their value. The F9 suite checks that no exclusive can come out of a spin or chest. Each exclusive is a clear step above the coin items of its tier:
- **Ball skins** have their own light and particles. The two Legendaries also shift between the Nice, Evil and Glitched forms on every pickup, like the Legendary set (Oracle, Masquerade, Heartbreaker, Maw).
- **Trails** last longer, draw wider and glow (`Data.Lifetime`, `Width`, `Glow`), and shed sparkles along the throw (`Data.Sparkle`, client only, fewer in performance mode).
- **Titles** color each letter along a gradient on the name tag (`Data.Gradient`, `TitleStyle`). The Legendary ones shimmer: each client re-draws them about 10 times a second (`TitleFxController`), skipping tags too far away to be seen.

### Robux-exclusive products

Every product id is still the placeholder 0, so none is registered or on sale yet. Create each developer product at its price, then put its id in that item's `RobuxProductId` in `Catalog.luau`.

| Item id | Name | Category | Rarity | Price | Developer product id |
| --- | --- | --- | --- | --- | --- |
| `Skin_Galaxy` | Galaxy | Ball skin | Epic | 79 R | 0 (to create) |
| `Skin_StormCore` | Storm Core | Ball skin | Epic | 79 R | 0 (to create) |
| `Skin_Sovereign` | Sovereign (shifting forms) | Ball skin | Legendary | 199 R | 0 (to create) |
| `Skin_Phoenix` | Phoenix (shifting forms) | Ball skin | Legendary | 199 R | 0 (to create) |
| `Trail_Aurora` | Aurora | Trail | Epic | 79 R | 0 (to create) |
| `Trail_NeonPulse` | Neon Pulse | Trail | Epic | 79 R | 0 (to create) |
| `Trail_Stardust` | Stardust | Trail | Legendary | 199 R | 0 (to create) |
| `Trail_VoidRift` | Void Rift | Trail | Legendary | 199 R | 0 (to create) |
| `Title_NeonAce` | Neon Ace | Title | Epic | 39 R | 0 (to create) |
| `Title_MidnightMenace` | Midnight Menace | Title | Epic | 39 R | 0 (to create) |
| `Title_TheChosenOne` | The Chosen One (shimmering) | Title | Legendary | 99 R | 0 (to create) |
| `Title_MainCharacter` | Main Character (shimmering) | Title | Legendary | 99 R | 0 (to create) |
| `Finisher_Meteor` | Meteor Strike (was coins) | Finisher | Epic | 79 R | 0 (to create) |
| `Finisher_BlackHole` | Black Hole (was coins) | Finisher | Epic | 79 R | 0 (to create) |
| `Finisher_DestinyArrives` | Destiny Arrives (was coins) | Finisher | Legendary | 199 R | 0 (to create) |
| `Finisher_OutOfThePark` | Out of the Park! (was coins) | Finisher | Legendary | 199 R | 0 (to create) |
| `Pose_Robot` | Robot (was coins) | Gesture | Epic | 39 R | 0 (to create) |
| `Pose_Dab` | Dab (was coins) | Gesture | Epic | 39 R | 0 (to create) |
| `Pose_TrophyLift` | Trophy Lift (was coins) | Gesture | Legendary | 99 R | 0 (to create) |

The placeholder Prism skin these replace was never on sale, so no one owns it.

**Finishers and gestures moved to Robux (Oct 29).** The two showiest Epic finishers (Meteor Strike, Black Hole), both Legendary finishers (Destiny Arrives, Out of the Park!), two Epic gestures (Robot, Dab) and the only Legendary gesture (Trophy Lift) are now Robux exclusives, so there's one Legendary gesture, not two. Players who already own them keep them. They're no longer sold for coins, spun or rolled, and bots don't use the finishers. New coin items refill the quest chests, so each one again has every rarity and rolls its configured weights:
- **Supernova** (Legendary finisher, 12,000 coins). The world goes dark, sparks spiral into a star over the winner's raised hands, and the star bursts on the victim as a white-gold supernova. It's the Finisher Chest's Legendary (11 items).
- **Power Up** (Legendary gesture, 12,000 coins). The winner crouches and charges, then throws their arms wide as a golden aura flares (IntroPoses `Fx = "Aura"`). It's the Gesture Chest's Legendary.
- **The Floss** and **Heart Hands** (Epic gestures, 5,000 coins each) bring the Gesture Chest back to 3 Epics and 12 items.

### Coin sinks

| Sink | Cost | Cap |
| --- | --- | --- |
| Shop purchase | Item price | Once per item |
| Paid spin | 1,000 | 5 a day |
| Lobby chests | 1,200 / 2,200 / 3,500 | None |

There are no consumable sinks. Once someone owns the catalog, coins have no use.

### Cosmetics

Rarity is **derived from price** (`Config.Spin.RarityByPrice`): Legendary is ≥4,000, Epic ≥2,500, Rare ≥1,000, and anything cheaper is Common. Defaults (price 0) are never prizes.

| Category | Item | Price | Rarity |
| --- | --- | --- | --- |
| Ball Skin | Classic (red, default) | 0 | Free |
| Ball Skin | Orange, Yellow, Green, Blue, Purple, Dark Gray, White, Bubblegum, Lime | 500 | Common |
| Ball Skin | Ice, Zebra (black bands), Rainbow (cycles through the hues), Silver (shiny metal), Gold (shiny metal) | 1,750 | Rare |
| Ball Skin | Basketball, Soccer Ball, Tennis Ball, Eight Ball (model skins) | 5,000 | Epic |
| Ball Skin | Meteor (lava seams, embers), Disco Ball (mirror tiles, sparkles), Planet (glowing ring), Bomb (sparking fuse) (effect skins) | 5,000 | Epic |
| Ball Skin | Oracle (an eye in gold hoops), Masquerade (a two-faced mask), Heartbreaker (a cracked heart), Maw (a fanged mouth): the Legendary set, a new form each pickup | 12,000 | Legendary |
| Trail | Sparkle | 400 | Common |
| Trail | Flame | 800 | Common |
| Trail | Rainbow | 1,500 | Rare |
| Title | Rookie | 150 | Common |
| Title | Dodge Master | 1,000 | Rare |
| Title | Sky Launcher | 1,500 | Rare |
| Title | Untouchable | 3,000 | Epic |
| Finisher | Spotlight | 2,000 | Rare |
| Finisher | Meteor Strike | 3,000 | Epic |
| Finisher | Pumpkin Reaper (Halloween, Limited; Haunted Bundle only since Oct 29) | 2,500 | Epic |
| Finisher | Purple Flash | 4,000 | Legendary |
| Finisher | Black Hole | 4,000 | Legendary |
| Finisher | Dodgeball Rush | 4,500 | Legendary |
| Finisher | Destiny Arrives | 5,000 | Legendary |
| Finisher | Out of the Park! | 5,000 | Legendary |
| Intro Pose | Big Wave | 600 | Common |
| Intro Pose | Flex | 1,200 | Rare |
| Intro Pose | You're Next | 1,500 | Rare |
| Intro Pose | Take a Bow | 2,500 | Epic |
| Intro Pose | Dab | 3,000 | Epic |

The ball skin rows are the Oct 29 lineup at the flat `Config.Economy.PriceByRarity` prices (Gold moved from Epic to Rare then, and owners kept it); the other rows are the original audit. Model skins (`Data.Model`) swap the ball's look for a model built from parts in `BallModels.luau`; the ball itself keeps its size and physics. Effect skins add a light, embers or sparkles, which follow the neon setting and performance mode. Beach Ball was left out because its tapered stripes don't build well from parts. The Legendary set shows one of three forms each time you pick a ball up: **Nice** (brighter colors, a glowing halo, a soft light and gentle sparkles), **Evil** (a dark palette, black spikes, glowing red cracks and smoke) or **Glitched** (the skin's colors with flickering red and cyan copies, stray pixels and a scanline). The server picks the form (`ShopService.pickForm`, never the same one twice in a row) and sets it as the ball's `SkinVariant` attribute. A thrown ball keeps its form, practice balls pick theirs on the client, and the holder's screen glows briefly in the form's color on each swap. Without Pumpkin Reaper there were 23 prize items (6 Common, 7 Rare, 5 Epic, 5 Legendary), worth 49,350 coins.

**Category gaps for the quest chests:**
- **Titles** exist, but only 4 are for sale. That's too thin for a daily chest: you'd own them all in about a week.
- **Gestures** don't exist as a category. The nearest thing is **Intro Poses**: short looping arm-frame sequences in `IntroPoses.luau`, played during the match-start camera pan. There are 5 for sale.
- **Finishers** exist, but none is Common, so a daily Finisher Chest would hand out mostly Epic and Legendary items.

## 2. Rarity tiers

**"Normal play"** means 30 minutes a day: about 6 finished matches, or about 1,500 coins, plus about 180 a day from the new login ladder. That's **about 1,700 coins a day**.

| Rarity | Price | Earn-time target | Duplicate value (20%) | Color |
| --- | --- | --- | --- | --- |
| Common | 500 | About 2 matches | 100 | Sky `#8ed2ef` |
| Rare | 1,750 | About 1 day | 350 | Leaf `#7cc47f` |
| Epic | 5,000 | About 3 days | 1,000 | Candy `#ff9cc0` |
| Legendary | 12,000 | About 1 week | 2,400 | Sun `#f7cd46` |

**Recommendations:**
- **Give each item an explicit `Rarity` and charge one flat price per rarity** (a `Config.Economy.PriceByRarity` table). Today price decides rarity, so any price change silently moves items between tiers and changes the wheel odds. Flat prices also make the shop easy to read.
- **Use one duplicate table, at 20% of the tier price, for every random source** (spin, quest chests, login spins), replacing the two tables that exist now.
- **Raise the paid spin to 1,500 coins.** At the new prices a standard wheel is worth about 1,530 in shop value, so 1,000 would bring back the "wheels beat the shop" problem from STATUS.md.
- **Pumpkin Reaper moved into the Haunted Bundle (Oct 29).** It's no longer sold for coins; 2,500 is now only its value, like the other bundle items. Players who already bought it keep it.

**Re-tiering the current items**, mostly keeping today's order:

| Rarity | Items |
| --- | --- |
| Common | Orange, Yellow, Green, Blue, Purple, Dark Gray, White, Bubblegum, Lime, Sparkle, Flame, Rookie, Big Wave |
| Rare | Ice, Zebra, Rainbow skin, Silver, Gold, Rainbow trail, Dodge Master, Sky Launcher, Spotlight, Flex, You're Next |
| Epic | Basketball, Soccer Ball, Tennis Ball, Eight Ball, Meteor, Disco Ball, Planet, Bomb, Untouchable, Meteor Strike, Purple Flash, Black Hole, Dodgeball Rush, Take a Bow, Dab, The Floss, Heart Hands, (Pumpkin Reaper) |
| Legendary | Oracle, Masquerade, Heartbreaker, Maw, Supernova, Power Up (Destiny Arrives and Out of the Park! are Robux exclusives now) |

Legendary should stay rare, so only the two showpiece finishers stay there. The catalog becomes 79,250 coins (before the starter sets), about 45 days of normal play.

At these prices, the Sack bundle (6,000 coins for 199 R) buys about one Epic, and the Chest bundle (16,000 for 499 R) buys one Legendary plus change.

## 3. Daily login ladder (7 days, loops)

| Day | Reward | Approx. value |
| --- | --- | --- |
| 1 | **Bonus spin on a Rare-or-better wheel** (70/24/6) | ~3,150 |
| 2 | 250 coins | 250 |
| 3 | **2x Coins for 30 minutes** (the Boost30 grant, free) | ~750 if played |
| 4 | 400 coins | 400 |
| 5 | Bonus spin on the standard wheel | ~1,530 |
| 6 | 600 coins | 600 |
| 7 | **Pick 1 of 3 unowned Epic cosmetics** (1,000 coins if you own every Epic) | 5,000 |

**Recommendations:**
- **Keep "a missed day resets to day 1."** Because day 1 is the big Rare+ spin, a lapsed player gets a strong welcome back, while a full streak is still always worth more. One ladder claim stays one claim per UTC day, as now.
- **Bonus spins are free, so they're allowed where paid random items are restricted**, the same way the free daily spin is. They stack with the daily free spin rather than replacing it.
- Day 3 gives away a taste of a 19 R product, which supports the boost upsell without cutting into bundles.

## 4. Daily quest chests

Each chest rolls **one item of its category**. A quest's chest is claimable once per UTC day. Quest chests are free, so they're allowed in restricted regions.

### Roll rule (all three chests)
1. Roll a rarity by the chest's weights, skipping any rarity the category has no items in and renormalizing the rest (as `SpinService.wheel` already does).
2. Pick uniformly among the items of that rarity you **don't own yet**.
3. **Duplicate rule:** if you already own every item of that rarity, you get that rarity's duplicate coins instead (100 / 350 / 1,000 / 2,400).

**Recommendation:** build the 12-slot reveal wheel from unowned items, filling with "+coins" duplicate slots when a rarity is exhausted. That keeps the existing "the odds are exactly what the wheel shows" rule from Spin and Chest.

**Recommendation:** count bot knockouts toward the 3-KO quest. Solo players always get bot-filled matches, so a players-only rule would lock most of them out of the Title Chest.

### Title Chest (knock out 3 opponents)

| Rarity | Weight |
| --- | --- |
| Common | 55 |
| Rare | 30 |
| Epic | 12 |
| Legendary | 3 |

Titles are text-only and cheap to make, so they can flow faster than the other categories. Expected shop value is about 1,760.

**Starter set (16 titles, 12 new):**

| Rarity | Titles |
| --- | --- |
| Common | Rookie, Bonk, Wobbly, Benchwarmer, Butterfingers, Ball Hog |
| Rare | Dodge Master, Sky Launcher, Catch King, Jailbreaker, Bullseye |
| Epic | Untouchable, Void Walker, Showstopper |
| Legendary | Ragdoll Royalty, The Final Boss |

**Recommendation:** color the name-tag title by its rarity (`Config.Spin.RarityColors`). Today the badge is plain text (`ShopService.applyCosmetics`), so an Epic title looks the same as a Common one.

### Gesture Chest (play 2 games)

| Rarity | Weight |
| --- | --- |
| Common | 60 |
| Rare | 28 |
| Epic | 10 |
| Legendary | 2 |

These are the same weights as the daily spin. Expected value is about 1,530.

**Recommendation:** gestures = the existing **Pose** category, renamed "Gestures" in `Catalog.CategoryNames`. Poses are already frame-based and per-player, so new ones only need new frames in `IntroPoses.luau`.

**Starter set (11 gestures, 6 new):**

| Rarity | Gestures |
| --- | --- |
| Common | Big Wave, Thumbs Up, Shrug, Clap |
| Rare | Flex, You're Next, Salute, Air Guitar |
| Epic | Take a Bow, Dab |
| Legendary | Champion's Trophy Lift |

### Finisher Chest (win 1 game)

| Rarity | Weight |
| --- | --- |
| Common | 60 |
| Rare | 30 |
| Epic | 9 |
| Legendary | 1 |

For a player who wins every day, that's an Epic about every 11 days and a Legendary about every 100, so the shop stays the way to get the finisher you want. Expected value is about 1,395.

**Recommendation:** add **4 Common and 1 Rare finisher** built as cheap variants of `Finishers/Default.luau` (color, sound and text changes, no new set pieces), so the chest has a real floor.

**Starter set (12 finishers, 5 new):**

| Rarity | Finishers |
| --- | --- |
| Common | Confetti Pop, Air Horn, Sad Trombone, BONK! |
| Rare | Spotlight, Slow-Mo Replay |
| Epic | Meteor Strike, Purple Flash, Black Hole, Dodgeball Rush |
| Legendary | Destiny Arrives, Out of the Park! |

### Daily totals
- Doing all three quests yields about 4,700 in shop value a day while the pools are fresh.
- With duplicate protection, Commons fill up within about a week. After that, most rolls pay 100 coins, while Epic and Legendary items stay gated by their weights.

## 5. What this changes (for whoever implements it)
- **Removed:** the lobby chests, `Config.Chest.Spots`, paid chest opens, the `ChestDaily` free opens, and the "Free chest ready" hint.
- **Reused:** the chest wheel and reveal (`ChestService.wheel` and `ChestController`) for the quest chests, `BoostService.grant` for day 3, and the seeded spin wheel for the bonus spins.
- **New data:**
  - `Rarity` on each Catalog item, `Config.Economy` (prices and duplicate values), and the quest state.
  - The ladder entries become typed rewards (`{ Kind = "Coins" | "Spin" | "Boost" | "PickEpic", ... }`).
  - This needs a save schema bump.

## 6. Implemented: full chest pools and Power Ball Mastery (Oct 28)

The §4 starter sets are in the Catalog, plus a few extras so every rarity has items:

| Chest | Common | Rare | Epic | Legendary |
| --- | --- | --- | --- | --- |
| Title (19) | Rookie, Bonk, Wobbly, Benchwarmer, Butterfingers, Ball Hog, Noodle Arms | Dodge Master, Sky Launcher, Catch King, Jailbreaker, Bullseye, Comeback Kid | Untouchable, Void Walker, Showstopper, Iron Wall | Ragdoll Royalty, The Final Boss |
| Gesture (12) | Big Wave, Thumbs Up, Shrug, Clap | Flex, You're Next, Salute, Air Guitar | Take a Bow, The Floss, Heart Hands | Power Up (golden aura) |
| Finisher (11) | Confetti Pop, Air Horn, Sad Trombone, BONK! | Spotlight, Slow-Mo Replay, Paparazzi | Purple Flash, Dodgeball Rush, Bubble Trouble | Supernova |

With items in every rarity, each chest rolls its configured weights as they are (no renormalizing). Robux-exclusive items are never in the chests. Supernova, Power Up, The Floss and Heart Hands keep the chests full after the Oct 29 exclusives.

**Power Ball Mastery** gives power balls a long-term point. Each credited knockout with a Heavy, Rocket or Pop ball (bot victims included, as with the KO quest) counts toward earn-only cosmetics. These are never sold, spun or rolled, so they sit outside every pool and price table above:

| Item | Rarity | Goal |
| --- | --- | --- |
| Title: Heavyweight | Rare | 10 Heavy KOs |
| Title: Rocketeer | Rare | 10 Rocket KOs |
| Title: Pop Star | Rare | 10 Pop KOs |
| Trail: Power Surge | Epic | 25 KOs with each type |

**Featured ball of the day:** one power type per UTC day, rotating Heavy → Rocket → Pop. It drops 3x as often (about 60% of drops) and its knockouts count x2 toward mastery (`Config.PowerUps.Featured`). Both teams still always get the same type.

## 7. Value tags on Robux bundles (Nov 2)

Every value the shop shows is worked out from `Config.CoinShop` and the Catalog by `shared/BundleValue.luau`; nothing is typed in by hand. The offline test "value tags" checks the figures against Config.

- **Coin bundles:** each card shows "+X% BONUS", its coins per Robux over the smallest bundle's, **rounded down** so the tag never claims more than the real bonus. Today that's +36% / +47% / +57% / +71% for the Pouch, Sack, Chest and Vault (the Vault's exact figure is +71.7%). The smallest bundle is the baseline and shows none.
- **BEST VALUE** goes on whichever bundle has the most coins per Robux (today the Vault). Config's own `Tag = "Best value"` is ignored so the two can't disagree; other tags ("Popular") still show.
- Once a product's real price loads from the dashboard, the bonus and the ribbon are worked out again from that price, so they always match the Buy button.
- **Limited offers:** "Worth N coins" is the catalog `Price` of every item plus the bundle's coins. The Haunted Bundle is worth 21,500 (six items at 2,500, Pumpkin King at 1,500, plus 5,000 coins) for 299 R. It shows on the offer strip (Coins sheet, Bundles sheet and Shop shelf), the bundle page's summary and the hub stand's sign.
- **No crossed-out prices.** None of these Robux prices was ever higher, so a strike-through "was" price would be a made-up discount. Add one only if a product really sold at the higher price first.

## 8. Level rewards (Nov 2)

Every level from 2 to 100 pays one typed reward (`Config.Progression.Rewards`, granted through `RewardService.grant`). Level 1 is where everyone starts, so it pays nothing. Rewards **bank the moment you reach the level** (`RewardService.payLevels`, called at the end of a match and on join); there's nothing to claim. The profile keeps the highest banked level (`LevelRewardsPaid`, an additive field, no schema bump), so a level never pays twice. A save from before level rewards starts at 1 and gets every level it has already passed, once, on its next join. The tutorial's completion reward is a separate grant.

| Levels | Reward |
| --- | --- |
| Most levels | Coins: 50 at levels 2–9, then 25 more every ten levels (75 in the teens … 275 in the 90s) |
| 5, 25, 45, 65, 85 | A Rare+ bonus spin (queued in `BonusSpins`, used from the Spin sheet) |
| 15, 35, 55, 75, 95 | A quest chest, opened on the spot: Finisher, Gesture, Title, Finisher, Gesture |
| Every 10th | An earn-only title (`Unlock = { Level = n }`): never sold, spun or rolled |

**Level titles:** Warmed Up (10), Court Regular (20), Seasoned Pro (30) are Rare; Veteran (40), Half Century (50), Ball Whisperer (60), Juggernaut (70) are Epic; Hall of Famer (80), Living Legend (90), Centurion (100) are Legendary (framed in ✦ on the name tag). They sit on the Titles shelf locked, showing "🔒 Level n".

**Against the earn rate.** XP per match isn't measured yet. Estimating about 70 (40 for finishing, 20 for half the wins, plus hits, catches and knockouts at the bot rate) and normal play at 6 matches a day:

| Reach | Total XP | About | Coins banked | Plus (so far) |
| --- | --- | --- | --- | --- |
| Level 5 | 650 | 1.5 days | 150 | a Rare+ spin |
| Level 10 | 2,025 | 5 days | 350 | a Rare+ spin, a Rare title |
| Level 20 | 6,650 | 16 days | 950 | 1 spin, 1 chest, 2 titles |
| Level 30 | 13,775 | 33 days | 1,750 | 2 spins, 1 chest, 3 titles |
| Level 50 | 35,525 | 85 days | 3,950 | 3 spins, 2 chests, 5 titles |
| Level 100 | 133,650 | about 320 days | 12,950 | 5 spins, 5 chests, 10 titles |

- **Coins barely move the economy:** 12,950 over the whole climb is under 8 days of normal play (about 1,700 a day) spread over most of a year, about 2.4% on top of match coins.
- **The value is in the spins, chests and titles,** and it's front-loaded on purpose: the first 10 levels (about 5 days) pay a Rare+ spin (about 3,150 in shop value) and a title, roughly two days' earnings, as a new player is deciding whether to stay. Over the first month (to about level 30) it adds about 17% to what matches pay; over the whole climb about 7% (about 36,000 in spins, chests and coins, at §3–4's expected values).
- **Titles aren't in that total:** they can't be bought, so their tier prices (61,250 for all ten) are only their value. The Legendary three are the long-term chase, like Power Ball Mastery.
- **If levels turn out faster or slower** than the 70 XP estimate, the coin amounts can be retuned in `LEVEL_COINS` without touching saves; the banked mark only records which levels have paid.

## 9. Starter Pack, VIP and the 2x Coins pass (Nov 2)

The quick wins from the monetization review. Everything is code-complete and covered by offline tests; nothing is on sale until the ids below are filled in.

- **Starter Pack** (`Config.CoinShop.Starter`, a developer product, 99 R): Galaxy ball skin, Neon Ace title, 5,000 coins and 30 minutes of 2x coins. Shown as a strip on the Coins sheet once Robux buttons unlock, gone for good once bought (`profile.StarterBought`, additive, no schema bump). `PurchaseService.grantStarter`. It's worth far more than 99 R on purpose: it exists to turn a player into a payer.
- **VIP** (`Config.CoinShop.Passes.VIP`, a game pass, 299 R): a gold VIP tag on the name tag and a daily gift the first time a VIP is here each UTC day: a free bonus spin and 150 coins (`GamePassService.dailyGift`, `profile.VipGiftDate`). Nothing that changes a match.
- **2x Coins Forever** becomes the `DoubleCoins` game pass (199 R). The old BoostForever developer product stays registered so its buyers keep it; once the pass has an id, the lifetime boost card prompts the pass instead.
- Pass ownership comes from Roblox, not the save: checked on join (`UserOwnsGamePassAsync`) and marked live on purchase. A player owns it this session if `c.passes[id]`; the client sees `Pass_<id>`.
- The Coins sheet's strip stack shows at most two strips: limited offers first, then the Starter Pack, then VIP. Strips whose product doesn't exist yet are hidden in live servers and show "Soon" in Studio.

### Dashboard checklist

| Create | Where | Price | Then paste the id into |
| --- | --- | --- | --- |
| Starter Pack | Monetization > Developer Products | 99 R | `Config.CoinShop.Starter.ProductId` |
| VIP | Monetization > Passes | 299 R | `Config.CoinShop.Passes.VIP.PassId` |
| 2x Coins Forever | Monetization > Passes | 199 R | `Config.CoinShop.Passes.DoubleCoins.PassId` |
| The 19 Robux exclusives | Monetization > Developer Products | 39 / 79 / 99 / 199 R (table in §1) | each item's `RobuxProductId` in `Catalog.luau` |
| Private servers | Experience settings > Access | 99 R a month | (no code) |

Once the DoubleCoins pass is on sale, take the old "2x Coins Forever" developer product off sale in the dashboard (don't delete it).
