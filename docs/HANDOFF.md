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
- Lint: `selene src`. There are 2 known warnings that aren't ours: `BallService.luau:119` unused `ballType`, and `Theme.luau` `UDim2.new(0.5,0,0,0)`.
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
- `RD_Gallery` `Preview…` leaves the shop open (and `Busy` true) until you close it.
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
- **Touch controls** (`InputController.makeButton`): smoky dark discs with a thin white inner ring and white glyphs drawn from plain frames (`Glyphs.Dodge/Throw/Catch/Jump`). Big Throw in the middle, Dodge above it, Catch down-left, Jump below; our Jump hides Roblox's own touch jump button. On touch, Play again moves to the bottom row left of the cluster. Don't use CanvasGroup to clip glyphs: once the CanvasGroup GPU budget runs out it stops clipping. `RD_Gallery = "Touch"` shows the controls on a desktop until the mouse moves.

## What changed this session (all committed by the user)
- **KO effect:** a smash-style white frayed beam rises just off the court edge where the victim went out, and the rims flash white (`EffectsController.koBeam`, `pulseRims`).
- **Theme:** switched to the Day palette. HUD text over the world uses paper with an outline.
- **Daily rewards sheet:**
  - A row of toy day cards: a darker "Day N" strip, coin art, amount, and a status strip ("Today!", "Tomorrow", "Soon", "Claimed", "Big prize").
  - Today's card is bigger and has a glow, a spinning sunburst and a bobbing coin.
  - Day 7 has a "BONUS" sticker, and a shine sweeps across the Claim button.
- **Shop:** a 4-column grid of cards. Each card has a tier-colored art band with a tier sticker, the name, a ▶ preview button (finishers and poses), and its own Buy/Equip/Equipped button. Arrow keys move the selection (up/down move a row).
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

## Gotchas worth knowing
- `Theme.autoScale`, `Theme.pop` and `Theme.popIn` share one `UIScale` per element. Its `Base` attribute is the resting scale (the today card uses Base 1.08).
- `Theme.sheet` returns a `CanvasGroup`, which clips its children. Anything meant to break out of the edge needs to be a sibling outside it.
- `Workspace.StreamingEnabled` is on. The court and hub stream in fully near spawn (136 arena parts on both sides), but don't assume far content exists on the client.
- Bots are combatants with `c.isBot`. They have no `profile`, so anything profile-based needs a bot branch (see `ShopService.introPose` and `finisherModule`).
- Server → client events go through `NetService.send(player, name, payload)`; the client listens with `Net.on(name, fn)`. MatchState attributes are on `ReplicatedStorage.MatchState`.
