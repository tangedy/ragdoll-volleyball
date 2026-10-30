# Handoff for the next Claude session (Oct 27, 2026)

Ragdoll Dodgeball is a Roblox game written in Luau and synced with Rojo. Read these first:
- [README.md](../README.md): setup, controls, dev keys, checks.
- [docs/STATUS.md](STATUS.md): what's built and tested, and known limits.
- The Toybox Island design system (`project/README.md` inside <https://claude.ai/artifact/TLBxDxpwHmPBUoqdTAZ8Kq#readme>) before any UI work.

This doc covers how to work on the project, what the user likes, what changed in the last long session, and what is still unverified.

## How to work here

**Code and sync**
- The code lives in `src/`. Rojo syncs it into Studio (see the README table).
- Rojo is `rojo serve default.project.json` on port 34872. The user often has their own server running already. If you get "address in use", that server is fine to use; don't start another.
- Rojo only syncs into the open Studio place. Publishing is a manual File → Publish from Studio. The published place is "Ragdoll Dodgeball", placeId 101235501560927.

**Checks** (run after every change):
- Lint: `selene src` should report 0 errors and 0 warnings. Strict `luau-lsp` should report 0 errors (as of Oct 28).
- Format: `stylua <files>`.
- Types: `luau-lsp analyze --sourcemap=sourcemap.json --definitions=.luau-lsp/globalTypes.d.luau src`. Regenerate the sourcemap with `rojo sourcemap default.project.json -o sourcemap.json` after adding files.

**Driving Studio through the MCP** (`mcp__Roblox_Studio__*`):
- Call `list_roblox_studios` first. The studio id changes whenever Studio restarts.
- `execute_luau` runs in Edit, Client or Server. Edit only works when not playing.
- After editing files, **stop and restart the playtest**. A running playtest keeps the old code. If you start Play right after an edit, Rojo may not have synced yet. Check a source string in Edit (`script.Source:find(...)`) before starting.
- Modules you `require` from the MCP context are separate copies. To drive the real game, use the `RD_Gallery` player attribute (DebugController), real mouse input (`user_mouse_input` with screen x/y from `AbsolutePosition`), or server attributes.
- **Screenshots can be stale.** If the Studio window isn't focused, `screen_capture` returns an old frame. Verify numerically when it matters: positions, `WorldToViewportPoint`, attributes.
- `SendMouseButtonEvent` isn't allowed from MCP code. Use `user_mouse_input`. Its `mouseButtonClick` often doesn't register: send `mouseButtonDown`, an 80 ms `wait`, then `mouseButtonUp`. Hub and HUD guis ignore the inset, so `AbsolutePosition + AbsoluteSize/2` is the click point. Throws from MCP are still unreliable (about 1 in 3 fired).
- Network lag for tests: `settings().Network.IncomingReplicationLag = 0.3` works from the Client context. Set it back to 0 afterwards.
- `RD_Gallery` `Preview…` leaves the shop open until you close it (or a match starts and closes it).
- Local parts more than about 1,000 studs from your character aren't simulated on the client, and change signals are deferred (a "writing" flag can't guard your own writes).
- Studio blocks DataStores ("API access is not enabled"). The game plays unsaved; that's expected.
- The daily rewards sheet auto-opens on join and blocks matchmaking until you close it. With Play again on, a 3v3 bot match starts about 7 s after the hub is clear.
- Useful `RD_Gallery` values: `Shop`, `DailyPanel`, `DailyClaim`, `Preview<FinisherModule>` (e.g. `PreviewMeteor`), `Tutorial1`..`Tutorial5`, `Hint`, `Feed`. Set `""` between repeats.
- Ask before stopping a playtest the user may be in.

**Commits:** the user commits by themselves. Don't commit unless asked.

## User preferences
- Wants bold, "poppy", attention-grabbing UI, built in the Toybox Island language. They rejected a first pass as "barely changed".
- Uses the design system's Day theme (white surfaces), not the gray Night theme.
- Prefers things to happen immediately; no artificial delays.
- Avoids custom asset uploads (too many hoops). Use existing Roblox asset ids or built-in `rbxasset://` sounds.
- Expects you to verify in Studio and be honest about what wasn't verified.

## UI system (src/client/UI/Theme.luau)
- **Tokens:** `Theme.Toybox` (T) holds Day chrome: surface `#fffcf2`, ink/outline `#4a3423`, sunk `#ece3cc`, shadowToy `#cbbd9c`, select `#0789b0`. It adds `paper` (outlined white text over the world) and `dim` (backdrop). Fills (leaf, sun, sky, candy, peach, joyBlue, joyRed) are the same in both themes.
- **Text and buttons:** `Theme.label` with a stroke draws paper text with the toy outline (world-facing text). Stroke 0 draws ink (titles on surfaces). Buttons are `Theme.button(parent, text, "primary"|"secondary"|"quiet"|Color3, props)`.
- **Sheets:** `Theme.sheet(..., {tone=Color3, glyph="bag"})` adds the loud colored header band (white outlined title, red close button, outline round the sheet). Shop is sun, Spin candy, Daily joyBlue, Settings sky.
- **Notification dot:** `Theme.dot` is a 24px joy-red dot with a white "!" and a gentle pulse.
- **Hub layout:**
  - The action column (Shop, Spin, Daily, Settings) is vertical on the right edge. Round icons use a dark ledge, since they sit over the night scene.
  - The Q Dodge / E Catch legends sit bottom center. Their key discs are joyRed and joyBlue.
  - Play again is bottom right. The tutorial tip card is bottom right, above Play again.
- **Touch controls** (`InputController.makeButton`): smoky dark discs with a thin white inner ring and white glyphs drawn from plain frames (`Glyphs.Dodge/Throw/Catch/Jump`). Big Throw in the middle, Dodge above it, Catch down-left, Jump below, tucked to the right edge; our Jump hides Roblox's own touch jump button and starts the jump with `ChangeState(Jumping)`, because the default control script resets `Humanoid.Jump` every frame. A yellow ring round Throw fills with the charge. Throw is an inactive Frame, not a button: `UserInputService` hit-tests touches against its circle, so the touch isn't held by the GUI and Roblox's own touch camera turns with the finger while you aim. (Setting `Camera.CFrame` from code doesn't work for this: the default camera overwrites it the next frame.) Dragging off Throw no longer cancels. On touch, the hub icons become a row along the bottom, sized to fit between the coins chip and the controls (`ShopController.layoutActions`), and Play again moves to the top right.
- **Crosshair and aim assist:** while charging the crosshair is drawn on the enemy that assist has locked on to (`AimController.assistModel`), or on `aimPoint` when there's none. The first pick in a charge stays locked while it's inside the cone × `KeepFactor`, so the arc, crosshair and release never split between two nearby players. The cones are per input in `Config.AimAssist` (mouse 6°, gamepad 10°, touch 14°). On touch and gamepad the crosshair only shows while charging; with a mouse it also follows the cursor while you hold a ball.
- **Screen edges on touch:** `MobileControls` and the coins chip (its own `Profile` gui) use `ScreenInsets.None`, so they sit in the real corners. In landscape a notch only cuts into the middle of the side edge. Don't use CanvasGroup to clip glyphs: once the CanvasGroup GPU budget runs out it stops clipping. `RD_Gallery = "Touch"` shows the controls on a desktop until the mouse moves.

## What changed this session (all committed by the user)
- **KO effect:** a smash-style white frayed beam rises just off the court edge where the victim went out, and the rims flash white (`EffectsController.koBeam`, `pulseRims`).
- **Theme:** switched to the Day palette. HUD text over the world uses paper with an outline.
- **Daily rewards sheet:**
  - A row of toy day cards: a darker "Day N" strip, coin art, amount, and a status strip ("Today!", "Tomorrow", "Soon", "Claimed", "Big prize").
  - Today's card is bigger and has a glow, a spinning sunburst and a bobbing coin.
  - Day 7 has a "BONUS" sticker, and a shine sweeps across the Claim button.
- **Shop:** a 4-column grid of cards. Each card has a tier-colored art band with a tier sticker, the name, a ▶ preview button (finishers and poses), and its own Buy/Equip/Equipped button. Arrow keys move the selection (up/down move a row). The shelf is grouped into tier sections (Free, Common, Rare, Epic, Legendary), each with a colored header and an owned count. Finisher cards draw their icon from `UI/FinisherIcons.luau` (frame-built sticker art, no uploads); `lune run tools/preview_finisher_icons out.html` renders them to SVG for checking without Studio.
- **Match scoreboard** (`HUDController`):
  - Team plates size to fit the team's headshots.
  - Headshots come from the server's `RedRoster`/`BlueRoster` MatchState attributes (`"userId|status;..."`). Bots use the avatar user id they wear.
  - On court: yellow ring. Jailed or returning: greyed with a normal ring. Out: removed from the plate.
- **Join timing:** the save loads in parallel with the avatar download (`LobbyService.onPlayerAdded`). The loading screen waits for `ProfileReady`. Studio stops retrying DataStores after the first refusal. The daily sheet opens with no delay.
- **Bot finishers:** a tier is drawn from a gamma distribution (`Config.Bots.FinisherGamma`, shape 2, scale 0.6, giving about 49/35/12/4% Common/Rare/Epic/Legendary), then a random finisher of that tier (`ShopService.pickBotFinisher`). The pick is cached per bot.
- **Crowd cheers:**
  - One of two existing tracks plays on your client when an enemy is eliminated. 7174628595 starts at 2.15 s; 7755719721 starts at 0.35 s.
  - The volume follows a gamma curve over 5 s. Any sound layer can take this through the new `gamma` field in `Sounds.luau`, applied in `SoundController`.
  - The pick is a fair 50/50 (checked). The user saw streaks of the same cheer. You could offer "no repeats", but they haven't asked.
- **Camera freeze fix:**
  - While the avatar downloaded, the lobby loop built a duplicate character. The client's handler for the deleted one then grabbed the camera.
  - Fix: `CharacterService.spawnPlayer` has a `c.spawning` guard and a pending `c.spawnCF`, and `LobbyService` skips players with `c.spawning` set.
  - `CharacterController.onCharacter` sets the camera right away and ignores a replaced character.
- **Finisher previews:**
  - They play on a client-only copy of `workspace.Arena`, offset 1,600 studs in +Z.
  - A copy of you stands on your half and the dummy on the other, staged like a match.
  - The real character stays in the hub with WalkSpeed 0. Everything is deleted afterwards.

## Oct 27 verification sweep
Results are in the "Oct 27 verification sweep" table in [ACCEPTANCE_TESTS.md](ACCEPTANCE_TESTS.md). Fixed along the way (not committed):
- **Finisher previews froze the dummy.** The client only simulates physics within about 1,000 studs of your character (`SimulationRadius` 992), and the preview court was 1,600 studs out. It's now at +800 Z, the closest spot clear of the real court's 800-stud `VoidGlow`.
- **Preview launch didn't match the server.** `localLaunch` now uses the same `MaxSpeed` cap, tumble and flail as `RagdollService.ragdoll`. Uncapped, Default's dummy landed in the jail strip.
- **Performance mode off didn't restore lights.** Signals are deferred, so `GraphicsController`'s `writing` flag was already cleared when the change handler ran, and our own writes were saved as the server's. It now remembers the value it wrote (`written`).

## Not yet verified
- **Finisher previews by eye.** The numbers are right, but nobody has watched one at full frame rate.
- **Throw smoothness at high ping**, the practice dummy launch and respawn, and Play again off during a live match (needs 2 players).
- **Phone layout:**
  - The right-side action column may overlap the mobile Throw/Catch buttons.
  - The tip card on touch sits at `(1,-12,1,-320)`, which isn't checked on a real phone size.
  - The headshot plates on narrow screens aren't checked.
- **Gamepad navigation** through the new shop grid and the daily sheet.
- **Live publish:** the user publishes manually. Remind them that running servers keep old code until restarted ("Restart servers for updates").

## UI sound vocabulary (`uiCues` in `Sounds.luau`)
From the Nintendo UX audio study: a few short, dry sounds that each mean one thing, pitched on one scale (`note()` = semitones above the UI root).
- **Move** (tick, under 100 ms, jittered), **Tab**, **Select** (`UIClick`, rising fifth), **Back** (falling), **Open** (rising three-step, played as a sheet starts to rise).
- **Edge** (dull bump: end of a grid or list, d-pad that can't move), **Error** (two dull bumps: disabled button, too few coins).
- **Toggle on/off** (up/down), **Equip**, **Step** (tutorial step done), and the success family (`UISuccess`, `Purchase`, `CoinGain`, `DailyClaim`, `SpinReveal`, `SpinLegendary`).
- **Signature** (pop-ding) plays once when the loading screen lifts (`Booted` attribute). Reuse it in trailers.
- Closing a sheet plays Back from whatever closed it (✕, backdrop tap, gamepad B, tapping its hub icon again). Switching straight to another sheet plays only Open. Hub icons have no click of their own.
- In-match cues (combat, round flow, intro, banners, finishers, cheers) are separate and unchanged.

## Finishers on the 144 × 96 court
- Launch finishers (`Stage.Launch ~= false`) use `ArenaLayout.finisherLaunch`: the module's `Up` stays, and `Out` becomes at least whatever clears the gap, the jail strip and its wall on the current court size. The server and the shop preview both call it.
- The real victim flies in the Default collision group (`RagdollService.markFinisherFlight`) and is marked ejected. Ragdoll and Characters collide with the jail's 40-stud `JailBarrier`, which stopped them dead about 78 studs out.
- Finishers get `ctx.toEdge(pos, dir)` (distance to the back edge on whichever court they play on) and `ctx.courtOrigin`. Dodgeball Rush uses it to put the cart just past the edge.
- `Config.Visuals.FinisherNeonExempt` lists the finishers spared the extra finisher-neon dimming: Purple Flash, and Pumpkin, whose carved face must glow.

## Halloween event (`Config.Halloween`)
- **Switch:** `Config.Halloween.Enabled` is the starting state. The live state is the `Halloween` attribute on ReplicatedStorage.
- **Dev toggles:** H (Studio, or the game's owner live), or `workspace:SetAttribute("RD_Halloween", bool)` from the server command bar.
- **Server (`HalloweenService`):**
  - Dusk lighting; `ArenaBuilder.setupLighting()` restores the day, and the void glow turns orange.
  - Props from `ServerStorage.HalloweenAssets`, which syncs from `assets/HalloweenAssetPack.rbxm` (no scripts inside). They're placed on the hub deck at `Config.Halloween.Props`, and a spot that overlaps anything already there is skipped: today the cauldron and the lantern well.
- **Client (`HalloweenController`):**
  - The UI palette swap: `Theme.HalloweenToybox`, every Day token remapped, including later recolours.
  - The music (two DistroKid tracks), quieter in matches.
  - Jack-o-lanterns: carved pumpkins welded onto every Standard ball, match, visual and practice. Look only; power-up balls keep their colours.
  - A ball wearing a skin turns its pumpkin that colour (ribs a shade darker; Neon skins stay matte so the face still glows). Practice balls wear your equipped skin while you hold or throw them (`PracticeController.applySkin`).
- **Haunted Bundle in the Shop:** while the offer is live and `RobuxOk` is set, its bundle-only items sit on the Shop shelf with a "Bundle · R$" button, and the offer strip sits above the tier sections (`CoinShopController` builds a second copy on `ShopController.shelf()`). Its developer product is 3723612223 (`Config.CoinShop.Offers`); an offer at `ProductId = 0` says "Soon".
- **Haunted Bundle stand in the hub (`BundleDisplayController`):** a client-built plinth at the offer's `Display` spot (deck X/F) while the offer is live and `RobuxOk` is set: the practice dummy in the Pumpkin Head pose, a turning Jack-o'-Lantern ball, a floating ghost wearing the Ghost tag, a sign, and a `BundlePrompt` that calls `CoinShopController.buyOffer`. Owning everything turns the sign to Owned and hides the prompt. Its spot (X 12, F -14) hasn't been checked in Studio against the Halloween props yet.
- **New bundle items:** Jack-o'-Lantern skin (`Data.Pumpkin`: BallService, BallVisualController and PracticeController set a `Pumpkin` attribute, and HalloweenController draws the carved pumpkin all year), Pumpkin Head pose (`IntroPoses` `Prop = "PumpkinHead"`: a Frankenstein shuffle with a jack-o-lantern over the head, from `JackOLantern.onHead`), Ghost title (`Data.Style = "Ghost"`: a pale, see-through tag framed in 👻, in `ShopService.applyCosmetics`).
- **Pumpkin Reaper** is Halloween-exclusive (`Event = "Halloween"`, `Limited = true`) and now Haunted Bundle only (`Bundle = "Halloween2026"`). Its sounds are free Creator Store assets: an APM "Horror Tools" riser and screamer stab, plus Pro Sound Effects violin scrape, squeaks and wing flaps.
- **Event cosmetics:** give a catalog item `Event = "Halloween"` (and `Limited = true`). It's sold and shown only during the event (kept once owned), never on the spin or chest wheels, and bots don't use it.
- **Haunted Wheel (`HauntedWheelBuilder`):** a showpiece booth (black/orange wheel, bat wings, pumpkin heap, braziers, particle mist). No prompt or prizes. It turns via the `HubWheel` tag at its `SpinRate`; `HubFlicker` lights flicker in `HubController`; mist emitters marked `Scenery` switch off in performance mode. For now it only stands in the dev room.

## Dev room (`DevRoomService`, `Config.DevRoom`)
- **;** (same permission as H) teleports you to a hall far above the map and back. It's built on the first visitor and torn down when the last leaves; visitors are kept out of the match queue.

## Shop NEW! tags
- Each shop tab wears a red NEW! sticker while it holds something on sale the player hasn't seen and doesn't own. Opening the shop on a tab, or switching to it, marks it seen (`MarkSeen` remote, saved as `ShopSeen` in schema v8; v7 is the Robux receipts list; v9 adds the coin boosts and `PlaySeconds`).
- New players see every tab as NEW!. Saves migrated from v7 or older are pre-marked with the catalog as it stood, so only items added later (and event items while their event runs) light the tag again.

## Gotchas worth knowing
- `SoundController` preloads every cue's audio and only starts a layer's `stopAfter` once it's really playing. UI layers are cut to 60–80 ms, so timing them from `Play()` used to let a slow load swallow them.
- `Theme.autoScale`, `Theme.pop` and `Theme.popIn` share one `UIScale` per element. Its `Base` attribute is the resting scale (the today card uses Base 1.08).
- `Theme.sheet` returns a `CanvasGroup`, which clips its children. Anything meant to break out of the edge needs to be a sibling outside it.
- `Workspace.StreamingEnabled` is on. The court and hub stream in fully near spawn (136 arena parts on both sides), but don't assume far content exists on the client.
- Bots are combatants with `c.isBot`. They have no `profile`, so anything profile-based needs a bot branch (see `ShopService.introPose` and `finisherModule`).
- Server → client events go through `NetService.send(player, name, payload)`; the client listens with `Net.on(name, fn)`. MatchState attributes are on `ReplicatedStorage.MatchState`.
