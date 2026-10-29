# Economy

Audit as of Oct 28, 2026 (save schema v10). **Coins** are the only currency. XP and levels exist, but leveling up grants nothing.

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
| Ball Skin | Bubblegum | 500 | Common |
| Ball Skin | Lime | 500 | Common |
| Ball Skin | Ice | 1,200 | Rare |
| Ball Skin | Gold | 2,500 | Epic |
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

Without Pumpkin Reaper there are 23 prize items (6 Common, 7 Rare, 5 Epic, 5 Legendary), worth 49,350 coins.

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
| Common | Bubblegum, Lime, Sparkle, Flame, Rookie, Big Wave |
| Rare | Ice, Rainbow, Dodge Master, Sky Launcher, Spotlight, Flex, You're Next |
| Epic | Gold, Untouchable, Meteor Strike, Purple Flash, Black Hole, Dodgeball Rush, Take a Bow, Dab, (Pumpkin Reaper) |
| Legendary | Destiny Arrives, Out of the Park! |

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
| Gesture (12) | Big Wave, Thumbs Up, Shrug, Clap | Flex, You're Next, Salute, Air Guitar | Take a Bow, Dab, Robot | Trophy Lift (confetti burst) |
| Finisher (13) | Confetti Pop, Air Horn, Sad Trombone, BONK! | Spotlight, Slow-Mo Replay, Paparazzi | Meteor Strike, Purple Flash, Black Hole, Dodgeball Rush | Destiny Arrives, Out of the Park! |

With items in every rarity, each chest rolls its configured weights as they are (no renormalizing).

**Power Ball Mastery** gives power balls a long-term point. Each credited knockout with a Heavy, Rocket or Pop ball (bot victims included, as with the KO quest) counts toward earn-only cosmetics. These are never sold, spun or rolled, so they sit outside every pool and price table above:

| Item | Rarity | Goal |
| --- | --- | --- |
| Title: Heavyweight | Rare | 10 Heavy KOs |
| Title: Rocketeer | Rare | 10 Rocket KOs |
| Title: Pop Star | Rare | 10 Pop KOs |
| Trail: Power Surge | Epic | 25 KOs with each type |

**Featured ball of the day:** one power type per UTC day, rotating Heavy → Rocket → Pop. It drops 3x as often (about 60% of drops) and its knockouts count x2 toward mastery (`Config.PowerUps.Featured`). Both teams still always get the same type.
