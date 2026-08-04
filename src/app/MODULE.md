# MODULE: app

**Depends on: everything.** The composition root — the only place globals are permitted.

## Purpose

Window, main loop, CLI, and the wiring that connects `sim`, `fields`, `render`, and `ui`. Owns the fixed-tick accumulator.

## Files

| File | Owns | Milestone |
|---|---|---|
| `main.cpp` | ✅ entry point, CUDA device check, composition | M1 |
| `application.cpp` | ✅ window, fixed-tick accumulator, pan/zoom input, screenshot; **scenario load + auto-play (`scenario_apply_drive`) and the `ParamSet` non-canon mirror (M11d)** | M1 |
| `cli.cpp` | ✅ `--cells --seed --charge --frames --headless --gl-debug --benchmark --vsync --screenshot --scenario`; `--snapshot` at M12 | M1 |

## The main loop

```
accumulate real elapsed time
while (accumulator >= dt_physics && substeps < 8)   // drop time rather than spiral
    sim::step(world)
    accumulator -= dt_physics
alpha = accumulator / dt_physics                    // render interpolation factor
render::draw(frame, alpha)
ui::draw(stats)
```

Render frame rate floats; `DT_PHYSICS` never does. Max 8 substeps per frame.

## Things that will bite you

- **`sim::step` is called from here and nowhere else.** No module self-schedules.
- **The `Stats` copy back from device is ~30 Hz, not per tick.** Per-tick D2H would stall the pipeline and dominate the frame budget.
- **Every interaction lands at a tick boundary, not in the input handler.** The field brushes (M13a), the light spot and the optical trap (M13b) all write device state — a brush deposit, the emission spot, a forces-kernel spring — and doing that mid-tick from the input handler breaks INV-8. The handler only records `{tool, cursor, picked slot}` into `HudState`; `apply_poke` / `apply_light` / `apply_grab` run from the tick loop before `world_step`. `--auto-poke` / `--auto-light` / `--auto-grab` are the headless stand-ins (a mouse drag is not expressible headless).
- `--benchmark` and `--headless` must work with no window for the M1 gate to be checkable in CI.

## Status

**M11d.** Window, main loop, pan/zoom, respawn, PPM screenshot, the benchmark path (M1), and
now **scenario auto-play**: `--scenario ID` loads + instantiates a scenario, takes its clock +
scope, and calls `sim::scenario_apply_drive` before every `world_step`, so the eight scenarios
play unattended in the app (verified by an offscreen screenshot — first-light ignites, the
spin-drive flash empties the store). The app owns the `core/params.h` `ParamSet` the inspector
edits and mirrors its `non_canon_run` into the World each frame (M11d, ADR-034).

**M13 interaction (parallel arc off m12e-green).** Direct mouse manipulation: right-drag pans,
left drives the active tool. M13a added the Inspect + Heat/Chill/CO₂/N₂ palette (field brushes,
ADR-040); M13b added **Light** (drag a spotlight — awake cells herd up its irradiance gradient)
and **Grab** (tow the picked cell with an optical trap), ADR-041. All applied at a tick boundary.

Notes for whoever extends this:

- **`--headless` is a hidden window, not offscreen GL.** A real headless GL context on
  Windows would need EGL; a hidden GLFW window gives a genuine GL 4.6 context and lets
  the gate run the same code path the user sees. It is not suitable for a machine with
  no display adapter, which the reference machine is not.
- **The screenshot is captured between `gl_context_render_ui` and
  `gl_context_present`.** That split exists solely so the capture includes ImGui and
  still precedes the swap. Capturing earlier silently omits the UI.
- **Frame 0 is excluded from the benchmark** — it carries shader compilation and
  first-touch allocation and is not representative.
- Tool brushes (M5) must enqueue commands consumed at a defined point in the tick, not
  write into device memory from the input handler; the latter breaks INV-8.
