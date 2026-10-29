# Ball cosmetics expansion: chat prompts

Run these **in order, one fresh chat each**, committing after each one. They all edit
`src/shared/Catalog.luau`, so don't run two at the same time in the same checkout.
Prompt 1 is the foundation; every other prompt depends on it.

Tiers stay as they are in the game (Common, Rare, Epic, Legendary; no Uncommon).

Each prompt names the files to start from, so the chat doesn't have to explore the repo.
Suggested effort: 1 = medium, 2 = medium, 3 = high, 4 = medium, 5 = high, 6 = medium, 7 = high.

---

## 1. Foundation: Robux-exclusive cosmetics

```
Roblox/Luau project (Rojo). Add Robux-exclusive cosmetics to the cosmetic system. No real
items yet.

Add a new optional Item field `Exclusive: boolean?` in src/shared/Catalog.luau with a real
`RobuxProductId`. Exclusive items:
- are never on the spin wheel or in chests (Catalog.isOffered already excludes Bundle/Unlock
  items; follow that pattern) and are never sold for coins;
- ARE shown in the shop with a Robux price button (79 R$ for Epic, 199 R$ for Legendary; put
  these in src/shared/Config.luau Economy as RobuxPriceByRarity) and an EXCLUSIVE tag;
- are granted through src/server/Services/PurchaseService.luau: register one handler per
  exclusive item's RobuxProductId that adds it to OwnedCosmetics (look at how CoinShop bundles
  grant cosmetics there and reuse it). The client prompts with MarketplaceService
  PromptProductPurchase. Product ids stay 0 as placeholders; leave a comment saying so.
- Add one placeholder exclusive ball skin so the flow can be checked; later prompts replace it.

Update docs/ECONOMY.md (the exclusive rules) and add a TestService check that no Exclusive
item can come out of a spin or chest pool. Keep the existing code style.
```

---

## 2. Common + Rare ball skins

```
Roblox/Luau project. Add ball skins in src/shared/Catalog.luau (BallSkin section, same shape
as Skin_Bubblegum).

- Default: make Skin_Classic red (keep its Id and Default = true).
- 7 Commons: Orange, Yellow, Green, Blue, Purple, Dark Gray, White. SmoothPlastic, bright
  readable colors, Price = Config.Economy.PriceByRarity.Common. Keep the existing Bubblegum
  and Lime as extra Commons.
- 4 Rares: Zebra, Rainbow, Silver, Gold. Price = Config.Economy.PriceByRarity.Rare.
  - Silver and Gold must look metallic and shiny: Enum.Material.Metal or Foil with high
    Reflectance (and a highlight sheen if cheap). The existing Skin_Gold is Epic: move it to
    Rare and restyle it, keeping Id "Skin_Gold" so owners keep it. Keep the existing Ice Rare.
  - Zebra and Rainbow need a pattern, not a flat color. Add a Data field (e.g. Data.Pattern =
    "Zebra" | "Rainbow") and render it where skins are applied: start at
    src/server/Services/ShopService.luau:231 (sets ball attributes) and follow those attributes
    to the client (BallVisualController.luau, PracticeController.luau:73). Use Decals/Textures
    on the sphere or a rainbow color cycle; keep it cheap per frame.
- Also update the shop preview (ShopController.luau around line 310) so the new skins preview.
Update the skins table in docs/ECONOMY.md.
```

---

## 3. Epic skins: 3D ball-shaped models

```
Roblox/Luau project. Add a "model skin" pipeline, then 4-5 Epic ball skins that use it.

Pipeline: a skin can set Data.Model = "<name>": the Standard ball's sphere part keeps its
physics/size (cosmetics must never change radius, speed or hitbox, see the header of
src/shared/Catalog.luau) but becomes transparent and a welded visual model is shown instead.
The existing Jack-o'-Lantern skin (Data.Pumpkin, rendered by
src/client/Controllers/HalloweenController.luau, built from src/shared/JackOLantern.luau) is
exactly this idea: generalize it into a small shared module (e.g. src/shared/BallModels.luau)
of builder functions that make the model from Parts/MeshParts in code, and have Pumpkin use
it too. Hook it into the same places that apply skins (ShopService.luau:231,
BallVisualController.luau, PracticeController.luau, ShopController.luau shop preview).

Epic skins (built from parts, no external assets): Basketball, Soccer Ball, Tennis Ball,
Beach Ball, Eight Ball (pick ones that read well at ball size). Rarity = "Epic",
Price = Config.Economy.PriceByRarity.Epic. Add them to docs/ECONOMY.md.
```

---

## 4. More Epic skins: effect balls

```
Roblox/Luau project. The model-skin pipeline (Data.Model, src/shared/BallModels.luau) already
exists. Add 4 more Epic ball skins that are cooler, game-relevant takes on a ball, built from
parts with light effects (ParticleEmitter, PointLight, Neon) kept cheap: e.g. Meteor (molten
rock with embers, ties into the Meteor finisher), Disco Ball (mirror tiles, sparkles), Planet
(ringed), Bomb (fuse spark). Rarity = "Epic", Price = Config.Economy.PriceByRarity.Epic.
Respect Config.Graphics/NeonController settings like other effects do. Update docs/ECONOMY.md.
```

---

## 5. Legendary Verity balls (shifting each pickup)

```
Roblox/Luau project. The model-skin pipeline (Data.Model, src/shared/BallModels.luau) exists.
Add 4 Legendary ball skins: Verity, Falsity, Lovity, Cruelty (a matching set; each with its own
base look and color identity: e.g. Verity white/gold, Falsity masks, Lovity pink hearts,
Cruelty jagged red). Rarity = "Legendary".

The special rule: every time you pick up a ball, a Legendary skin shows as one of 3 forms
(Data.Variants):
- Nice: bright, warm, clean, soft glow and gentle particles (e.g. Nice Verity: radiant halo).
- Evil: dark, red/black, spikes or cracks, smoke/ember particles (e.g. Evil Verity: corrupted).
- Glitched: the skin's colors with digital glitch: flickering offset copies, pixel/static
  texture, jittering parts, color channel splits (keep it cheap; no per-frame part creation).
All 4 skins share these 3 forms, each in its own style, so forms read the same across the set.
On each pickup the server picks a form (not the same one twice in a row) and sets it as a ball
attribute next to the skin attributes (start at src/server/Services/ShopService.luau:231 and
find where a pickup happens in src/server/Services/BallService.luau); the client renders that
variant. Add a small flourish on the swap (brief glow) on the holder's screen. Update
docs/ECONOMY.md.
```

---

## 6. Robux exclusives: ball skins, trails, titles

```
Roblox/Luau project. Exclusive Robux cosmetics already work (Item.Exclusive, PurchaseService
handlers, 79 R$ Epic / 199 R$ Legendary, never on wheels or in chests). Replace the placeholder
exclusive skin and add, in src/shared/Catalog.luau, all with Exclusive = true and
RobuxProductId = 0 placeholders:
- BallSkin: 2 Epic + 2 Legendary (use the model pipeline in src/shared/BallModels.luau; the
  Legendaries may use the Data.Variants shifting system from the Verity balls).
- Trail: 2 Epic + 2 Legendary (see existing Trail entries for the Data shape).
- Title: 2 Epic + 2 Legendary (titles can get an animated/gradient color if the title renderer
  supports it cheaply; check where Data.Text is drawn).
They must look clearly better than coin items. List every new product in a table in
docs/ECONOMY.md with the Robux price, so real product ids can be filled in later.
```

---

## 7. Robux exclusives: finishers and poses

```
Roblox/Luau project. Exclusive Robux cosmetics already work (Item.Exclusive, PurchaseService,
79 R$ Epic / 199 R$ Legendary, never on wheels or in chests). Add 2 Epic + 2 Legendary
Finishers and 2 Epic + 2 Legendary Poses, all Exclusive = true, RobuxProductId = 0.
- Finishers: each is a module in src/shared/Finishers/ named by Data.Module. Read two
  existing ones first (one simple, e.g. ConfettiPop, and one big, e.g. the Meteor one) plus
  src/shared/FinisherKit.luau and match their structure; add icons in
  src/client/UI/FinisherIcons.luau.
- Poses: see src/shared/IntroPoses.luau and src/client/Controllers/PoseKit.luau.
Legendaries should be the most spectacular in the game. Add them to the docs/ECONOMY.md
exclusives table.
```
