# Robux product icons

The game has no gamepasses: every Robux item is a **developer product**. That includes the lifetime
2x boost, which works like a pass but is sold as a product. Each one has an optional `Image` field
(an Image asset id) that swaps the card's drawn art for an uploaded icon:

| Product | Config field | Where it shows |
| --- | --- | --- |
| 2x Coins, 30 min | `Config.CoinShop.Boosts[1].Image` | Coins sheet, boost row (replaces the "2x" disc) |
| 2x Coins, Forever | `Config.CoinShop.Boosts[2].Image` | Coins sheet, boost row (replaces the "2x" disc) |
| Handful / Pouch / Sack / Chest / Vault | `Config.CoinShop.Bundles[i].Image` | Coins sheet, bundle card art band (replaces the coin heap) |
| Extra daily spin | `Config.Spin.RobuxImage` | Left edge of the "Extra spin with Robux" button |
| Haunted Bundle (offer) | `Config.CoinShop.Offers[i].Image` | Offer card (already had this field) |

While a field is `0`, the card keeps its current drawn art. To set one, upload the PNG as a decal in
Studio's Asset Manager, copy its **image** id (not the decal id), and paste it in. Upload the same
PNG as the product's icon in Creator Dashboard > Monetization > Developer Products as well, so
Roblox's purchase pop-up matches the card.

## Shared style (applies to every icon)

- **Size:** 512x512 PNG with a transparent background. Keep the subject inside the middle ~440px,
  because the cards scale it down to 56–150px.
- **Look:** "Toybox Island", the game's UI style. Chunky, rounded toy shapes, flat fills, no
  gradients, one soft highlight per shape at most, and a thick dark-plum outline (`#2E1A3A`,
  about 14px at 512) around every shape. It should read like a vinyl sticker.
- **Palette:** leaf `#8FDC5A`, sun `#FF9A2E`, sky `#B49CFF`, candy `#E07CFF`, peach `#FFC06B`,
  paper `#FFF0DC`, plum ink `#2E1A3A`. Coins are sun orange with a peach rim.
- **No text** except where a brief asks for "2x". No Robux logo, no prices, no real brands.
- It must read at 56px: one clear subject, a bold silhouette, little fine detail.

Prompt prefix for image generators:
> Flat vector game icon, chunky rounded toy style, thick dark plum outline, flat colors no
> gradients, transparent background, centered, 512x512, sticker look, palette orange #FF9A2E,
> peach #FFC06B, lime #8FDC5A, lavender #B49CFF, pink #E07CFF, cream #FFF0DC —

## Boosts

### 2x Coins · 30 minutes (`Boost30`, 19 R$)
- **Subject:** one big coin with a bold "2x" sticker slapped on its upper right, and a small
  stopwatch peeking out behind its lower left to say "timed".
- **Colors:** sun-orange coin, leaf-green "2x" sticker (the in-game disc is leaf), paper stopwatch
  face with a plum hand.
- **Feel:** a quick pick-me-up. Light and bouncy, no sparkle overload.

### 2x Coins · Forever (`BoostForever`, 199 R$)
- **Subject:** the same coin and "2x" sticker, now with a small gold crown on top and an
  infinity-loop ribbon wrapped around its base. It should look clearly "premium" next to the
  30-minute one.
- **Colors:** sun-orange coin, a sun/peach "2x" sticker (the in-game disc is sun), peach crown,
  candy-pink ribbon, 3–4 small paper sparkles.
- **Feel:** the best boost in the shop. Bigger and shinier, but still the same family as Boost30.

## Coin bundles

All five are one family, so the size of the pile has to carry the jump in value. Keep the camera
angle (slight three-quarter, from above) and the coin design the same on all five. Each card's art
band sits on its own fill color (sun, sky, leaf, candy, peach in order), so the icon itself stays
transparent.

### Handful of coins (`Handful`, 1,000 coins, 49 R$)
- **Subject:** a small open cartoon hand, or just a loose little stack of 3–4 coins.
- **Colors:** sun coins, paper highlight dots. Show nothing besides the coins. This card's band is
  sun orange too, so the coins need peach rims and the full-weight plum outline to stand out.

### Pouch of coins (`Pouch`, 2,750 coins, 99 R$)
- **Subject:** a cinched cloth drawstring pouch, slightly bulging, with 2–3 coins spilling from
  its mouth.
- **Colors:** sky-lavender pouch, candy-pink drawstring, sun coins.

### Sack of coins (`Sack`, 6,000 coins, 199 R$, tagged "Popular")
- **Subject:** a fat burlap-style sack tied at the top and stamped with a coin symbol, with a small
  heap of coins at its base.
- **Colors:** peach sack, plum stitching, sun coins, a leaf-green tie.

### Chest of coins (`Chest`, 16,000 coins, 499 R$)
- **Subject:** a chunky toy treasure chest with the lid open, coins heaped over the rim and a
  couple falling out the front.
- **Colors:** candy-pink chest body, sun-orange metal bands, sun coins, paper glints.
- **Note:** keep it distinct from the in-world loot chests. Show coins only, no item or prize
  silhouettes.

### Vault of coins (`Vault`, 35,000 coins, 999 R$, tagged "Best value")
- **Subject:** a round vault door swung half open, with a mountain of coins pouring out and
  sparkles bursting behind it. This is the biggest, most generous image of the set.
- **Colors:** leaf-green vault door with a peach dial, sun coins, paper and candy sparkles.

## Spin

### Extra daily spin (`Config.Spin.RobuxProductId`, ~35 R$)
- **Subject:** a mini prize wheel tilted toward the viewer, with a "+1" bubble at the upper right.
  It's shown at 36px on a button, so the wheel needs 6 chunky wedges at most and a big pointer.
- **Colors:** wedges alternating candy, sky, leaf, and sun; peach hub; plum pointer; paper "+1"
  bubble with plum text.
- **Note:** the "+1" may be the only text. Match the hub's Daily Spin kiosk (the 🎡 station,
  candy pink).
