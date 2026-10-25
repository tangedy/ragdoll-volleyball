# Finishers

A finisher is the cutscene everyone in a match watches when the match-ending knockout lands. Each
finisher is one ModuleScript in this folder, named by `Catalog` item `Data.Module`.

```luau
return {
	Id = "MyFinisher",       -- must equal the module name
	Name = "Display Name",
	Duration = 3.5,          -- seconds; the server clamps to Config.Finisher.MaxDuration
	Stage = {                -- server-side staging of the victim (optional, all fields optional)
		LaunchDelay = 0.8,   -- seconds before the victim is re-launched
		Up = 60,             -- upward launch speed
		Out = 45,            -- outward launch speed (away from the court center)
	},
	play = function(ctx) end, -- client-side: camera, effects, text. May yield.
}
```

`ctx` (built by `FinisherController`):

| Field | Meaning |
| --- | --- |
| `camera` | `Workspace.CurrentCamera`, already set to `Scriptable` |
| `killer`, `victim` | character models (either may be nil) |
| `killerName`, `victimName`, `winnerColor` | strings / Color3 for text |
| `duration` | the clamped duration |
| `reducedMotion` | true if the viewer turned on Reduced motion: avoid fast cuts, shake and flashes |
| `banner(text, color?, seconds?)` | big centre text |
| `runFor(seconds, fn(alpha, dt))` | runs `fn` every frame for `seconds`, then returns |
| `rootOf(model)` | the model's HumanoidRootPart or nil |

The controller restores the normal camera and HUD afterwards, even if `play` errors, so a broken
finisher never breaks the match. Finishers are cosmetic only: they run after the match is decided.
