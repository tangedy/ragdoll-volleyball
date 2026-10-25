# Ragdoll Dodgeball: release plan

Three stages take the MVP in this repo to a public launch. Each stage has a goal, a scope, a definition of done and the risks to watch. The order follows the spec's working method: prove the fun, then retention and money, then launch and live-ops. Sizes assume one engineer working with Claude Code; treat them as rough.

Starting point: see [STATUS.md](STATUS.md).

---

## Stage 1: Core loop complete, then a closed playtest

*Redefined on Oct 24, 2026. The first version of this stage only polished what existed. A playtest is only informative once the designer's full loop exists: earn coins, spend them in the hub, come back daily, and get sudden death and the final-knockout moment. So Stage 1 now finishes that loop first, then playtests it.*

### 1a. Finish the core loop (done in Studio, solo plus bots)

- [x] **Coins currency.** It replaces coins, and a v2 → v3 save migration converts coins to coins 1:1. Match pays the single highest tier:
  - 600 for the final knockout.
  - 500 for never being eliminated.
  - 300 for being on the court at the win.
  - 200 for a win.
  - 50 for playing on the losing team.

  Any payout needs at least one throw, catch or dodge, so AFK players earn nothing.
- [x] **Daily login rewards.** A 7-day ladder (100 → 750 coins). It's claimed once per UTC day with a button, never auto-claimed. A missed day resets it to day 1.
- [x] **Sudden death.** When the timer ends, the round no longer ends on a head count. Jail closes (no returns, and new knockouts spectate) and the court keeps shrinking until a team is out. A fallback ends it if it still stalls after the court has fully shrunk.
- [x] **7 s hub intermission.** You can talk (default chat), practice on the dummy, and use the SHOP & LOCKER (buy and equip ball skins, trails, titles and finishers with coins) and DAILY. Both open from HUD buttons or kiosks in the hub. Keeping the shop open holds you in the hub.
- [x] **Finisher system.** The match-ending knockout plays a cutscene for everyone in the match. Finishers are modules in `src/shared/Finishers/` with a documented contract. The server stages the victim and each client plays the camera and effects. Two exist so far: Default and Spotlight (for sale). Designing the real finishers is Stage 2.
- [x] **Hardening already done.**
  - Smooth client-rendered ball flight with thrower prediction.
  - A Studio test suite (F9) covering spec §16 plus the new rules: 15/15 passing.
  - Hit-outcome tuning data (F8).
  - Device, spectate-time and leave-while-out analytics.

### 1b. Closed playtest prep (remaining)

1. **Multi-client run.** Use Studio's 2–4 client local server and check the rows in [ACCEPTANCE_TESTS.md](ACCEPTANCE_TESTS.md) the bot-driven suite can't cover. Examples: real players replacing bots between rounds, two humans in the shop at once, everyone in the match watching the finisher.
2. **Mobile pass on 3+ physical phones.** Check button sizes, safe areas, throwing while dragging the camera, the hub buttons and shop panel at phone size, and the finisher camera.
3. **Knockback tuning.** Use the F8 hit-outcome data. The target is that center hits usually recover and edge hits are dangerous.
4. **Audio and VFX pass.** Throw, hit, catch, splash, jail, sudden death and the finisher sting. The built-in sounds that actually load were checked in Studio.
5. **Economy sanity check.** Hold the shop prices against the coins rate: about 200–600 per win plus the dailies. Target: a first skin within 2–3 matches, and the 2,000–3,000 coins items in a few days.
6. **Bot quality.** Use Easy/Normal per match size and stop bots crowding onto one ball.
7. **Cleanup.** Remove the template Baseplate and SpawnLocation, and turn on Studio API access to test real saving.

### Definition of done

- Every v0.1 §17 item and every Amendment A acceptance test that needs no Robux passes. Each is recorded as passed in Studio, on device, or both.
- A playtest of 10–20 players on phones runs over 2+ sessions. Targets:
  - Time to first throw under 30 s.
  - Most first hits are funny recoveries.
  - Fewer than 20% leave during their first jail stint.
  - Most players buy something in their first session.
- No physics explosions or stuck characters across 50 consecutive rounds.

### Risks

- Network-ownership hand-offs during ragdoll can rubber-band on high ping. Test with Studio's network simulator at 200 ms.
- Server-only hit detection feels unfair on high latency. The spec accepts this for the MVP; document it, and only add rewind if playtests demand it.

---

## Stage 2: Retention and monetization beta

*About 3–4 weeks. Goal: there's a reason to come back tomorrow, and every Robux product can be test-bought safely. Implements Amendment A4 and A5 in full.*

### Scope

1. **Finisher designs.** Design the real finisher cutscenes on the Stage 1 module contract and sell them for coins and Robux.
2. **More cosmetics.** KO effects and victory poses join the existing ball skins, trails, titles and finishers (`shared/Catalog.luau` already holds Robux product-id placeholders).
3. **Cosmetic index.** An INDEX grid grouped by category. Unowned items show a silhouette and how to get them. A completed category grants a title.
4. **Daily quests.** 3 quests per UTC day from a pool, paid in coins; `PlayersOnly` quests ignore bot actions; finishing all 3 pays a bonus. The daily login ladder already exists from Stage 1.
5. **Purchases** (`MarketplaceService.ProcessReceipt`):
   - Receipts are idempotent: purchase ids are stored in the profile, a failed or duplicate receipt never grants twice or loses an item, and the client shows a "Delivering…" state.
   - Products: Starter Bundle (once per account), coins packs, 2x Coins, 2x XP, VIP and Emote Pack game passes, Quest Reroll.
   - Limited items: stock is decremented atomically across servers (DataStore `UpdateAsync` on a stock key, or MemoryStore with a DataStore backstop). Stock never goes below 0.
   - Studio simulation of every product flow, as the amendment asks.
6. **Placement rules.**
   - No prompt ever opens during a round, or on its own.
   - All Robux surfaces stay hidden until the tutorial is done plus about 10 minutes.
   - The coin shop opens on the third failed coin purchase, at most once per session.
   - Every paid button shows its price.
7. **Compliance.** Use `PolicyService` where needed, and no paid random items. The developer signs off on any like or reward mechanics.
8. **Analytics.** Product views vs. purchases per product, first-purchase rate, D1/D7 level reached, quest completion rate, and retention split by first-match type (bots vs. all real players).

### Definition of done

- Every Amendment A acceptance test passes, including the purchase, limited-stock and "no prompt in a round" rows.
- Every product can be test-bought in Studio, and a forced failure mid-grant recovers on rejoin.
- Schema migration v1 → v2 → v3 is tested against saved sample profiles.

### Risks

- Monetization surfaces creeping into combat. Guard every prompt with a single `ShopGate.canPrompt(player)` checked on the server.
- DataStore budget pressure from quests plus receipts. Batch writes into the existing autosave and save receipts immediately.

---

## Stage 3: Launch and live-ops

*About 2 weeks to launch, then ongoing. Goal: a public release with packaging that converts and a weekly reason to return. Implements Amendment A6 and A7.*

### Scope

1. **Weekly events (A6).** A server-only `LiveOpsSchedule` config: Giant Ball Hour, Low Gravity, Power-Up Frenzy and Double Rewards, on Saturdays at 18:00 UTC for 30 minutes, with an in-lobby countdown during the hour before. Modifiers apply equally to both teams and fully reset afterwards. Add Events-row cosmetics in the index and a Studio dev key to start or stop any event.
2. **Packaging (A7).** Ad-test the titles "Smash Your Friends", "Dodgeball But You Fly" and "Don't Fall Off!". Keep "Ragdoll Dodgeball" as a description keyword. Make 10–20 thumbnails checked at mobile size, an icon, and experience-page scenes (launch, catch, jail revenge, Giant Ball Hour). Enable private servers at 99 Robux/month.
3. **Production hardening.**
   - Server performance at 12 players plus FX.
   - A memory and leak soak test over hours of rounds.
   - Exploit review of every remote, with a `Net` suspicion dashboard.
   - Behavior when DataStore is down.
   - Shutdown and save on `BindToClose` under load.
4. **Trust and safety.** Complete the maturity questionnaire, filter any player-visible text, and set up report and moderation paths.
5. **Rollout.** Soft launch with a small ad budget → read D1, session length, bounce and payer conversion → fix the top issue (one variable at a time) → scale the ad spend → full launch.
6. **Post-launch loop.** A weekly cadence: an event, one tuning change, one content drop (cosmetics), and a review of the funnel and product metrics. Keep a hotfix process: Studio pull and base-compare before every publish (design checklist "Process").

### Definition of done

- The release checklist in `design-checklist.html` passes in full: onboarding, first 10 minutes, progression, combat, monetization, analytics and process.
- The first event has run once in production and reset cleanly.
- Launch KPIs are set before scaling ads. Suggested starting targets, to be revised against your own data:
  - D1 ≥ 25%
  - Average session ≥ 12 min
  - Like ratio ≥ 80%

### Risks

- A crowded "dodgeball" category. Lead with the ragdoll launch in the title and thumbnails.
- A cold-start empty server. Bots already cover it; watch the share of bot-heavy matches as traffic grows.
