# Ragdoll Dodgeball

A mobile-first Roblox dodgeball game: landing a throw launches the other player in a ragdoll, and falling off the floating court sends them to jail. It implements the v0.1 Design & Implementation Spec plus Spec Amendment A.

## Setup

The tools are pinned in `rokit.toml`: Rojo 7.7, selene, StyLua and luau-lsp.

```bash
rokit install
```

```bash
rojo serve default.project.json
```

In Roblox Studio, open a place, open the Rojo plugin and click **Connect**. The project syncs:

| Studio location | Source |
| --- | --- |
| `ReplicatedStorage.Shared` | `src/shared`: config, types, geometry, projectile math, net schema |
| `ServerScriptService.Server` | `src/server`: bootstrap and services |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client`: bootstrap and controllers |
| `ReplicatedFirst.LoadingScreen` | `src/first` |

It also sets `Players.CharacterAutoLoads = false` (the server spawns normalized R15 rigs) and the StarterPlayer walk and jump values.

The arena is built by the server at runtime (`ArenaBuilder`), so no manual place setup is needed. To preview it in Edit mode, run [tools/BuildGrayboxArena.luau](tools/BuildGrayboxArena.luau) from the command bar.

Optional place settings:
- Delete the template's `Baseplate` and `SpawnLocation`. They are harmless, but the court floats over the void.
- Turn on **Game Settings → Security → Enable Studio Access to API Services** to test saving. Without it, DataStore calls fail and the HUD shows "Progress not saving", which is the intended fallback.

## Testing in Studio

- **Solo:** press Play. You spawn in the lobby, and within about 6–12 s a bot-filled 3v3 starts.
- **Multiplayer:** Test → Clients and Servers → Local Server with 2–4 players.
- **Dev keys (Studio only):**
  - F6 skips the intermission.
  - F7 forces sudden death.
  - F8 toggles the debug overlay (leak counters and hit-outcome tuning data).
  - F9 runs the scenario test suite. Results print to Output and go to `workspace.RD_TestResults`. You can also start it from the server command bar with `workspace:SetAttribute("RD_RunTests", true)`.
  - F10 launches your own character with a full-charge hit, to feel the knockback.
  - Soak test: `workspace:SetAttribute("RD_Soak", 50)` from the server command bar plays 50 untouched rounds and writes PASS/FAIL to `workspace.RD_SoakResults`.
  - H toggles the Halloween event (also works for the game's owner on a live server, for that server only). From the server command bar: `workspace:SetAttribute("RD_Halloween", true)`. `Config.Halloween.Enabled` is what every server starts with.
- **Knockback escalates:** each hit you take launches you harder than the last (`Config.Knockback.Escalation`). Hits thrown from jail don't raise it. It resets each round and when you return from jail.
- **Hub (between matches, 15 s):** the SHOP and DAILY buttons, or the kiosks, open the coins shop and locker and the daily reward. Keeping the shop open holds you in the hub.
- **Robux buttons** (the Coins icon, the shop's "+", the Robux spin) show only after the tutorial plus 10 minutes of play. In Studio, `workspace:SetAttribute("RD_RobuxUnlocked", true)` from the server command bar shows them within 10 s.
- **Loot chests:** three tiers stand around the hub plaza: Common (1,200 coins, any rarity), Rare (2,200, Rare or better) and Epic (3,500, Epic or better). Each day the Common one is free after 1 match and the Rare one after 3 (`Config.Chest`). Walk up and press the prompt to see the wheel. Press G in Studio for dev coins.
- **Controls:**

| Action | PC | Mobile | Controller |
| --- | --- | --- | --- |
| Throw at the locked-on enemy | Click left mouse | Tap THROW | RT |
| Camera lock (Free / Shift / Aim) | Shift, or click the lock chip | LOCK button | R3 |
| Dodge | Q | DODGE | X |
| Catch | E | CATCH | LB |
| Spectator: switch player | Z / C | Arrow buttons | D-pad |

## Checks

Offline tests (server logic, no Studio needed; Lune is pinned in `rokit.toml`):

```bash
lune run tests/offline/run
```

They load the real server modules from `src/` with fakes for the engine (an in-memory DataStore, players, PolicyService, time) and cover saving, rewards, chests, spins, boosts, purchases, the shop, daily rewards and the Halloween schedule. Physics, UI and multiplayer still need the F9 suite in Studio.

```bash
rojo sourcemap default.project.json -o sourcemap.json
```

```bash
selene src
```

```bash
luau-lsp analyze --defs=.luau-lsp/globalTypes.d.luau --sourcemap=sourcemap.json --platform=roblox src
```

The Roblox type definitions file comes from `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau`.

## Docs

- [docs/STATUS.md](docs/STATUS.md): what's implemented, what was actually tested, and known limitations.
- [docs/ACCEPTANCE_TESTS.md](docs/ACCEPTANCE_TESTS.md): the manual acceptance checklist (spec §16 plus Amendment A).
- [docs/REMOTES.md](docs/REMOTES.md): the remote-event contract.
- [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md): the 3-stage plan to release.

All balance values live in [src/shared/Config.luau](src/shared/Config.luau). Every number is a starting value to tune from playtests.

UI follows the Toybox Island design system: <https://claude.ai/artifact/TLBxDxpwHmPBUoqdTAZ8Kq#readme>. Read its project/README.md before any UI work.