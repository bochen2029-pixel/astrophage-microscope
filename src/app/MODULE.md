# MODULE: app

**Depends on: everything.** The composition root — the only place globals are permitted.

## Purpose

Window, main loop, CLI, and the wiring that connects `sim`, `fields`, `render`, and `ui`. Owns the fixed-tick accumulator.

## Files

| File | Owns | Milestone |
|---|---|---|
| `main.cpp` | ✅ entry point, CUDA device check, composition | M1 |
| `application.cpp` | ✅ window, fixed-tick accumulator, pan/zoom input, screenshot; tool brushes at M5 | M1 |
| `cli.cpp` | ✅ `--cells --seed --charge --frames --headless --gl-debug --benchmark --vsync --screenshot`; `--scenario` and `--snapshot` at M11/M12 | M1 |

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
- **Tool brushes are commands, not direct writes.** They enqueue into a command buffer consumed at a defined point in the tick, so a brush stroke lands at a deterministic tick boundary. Writing straight into device memory from the input handler breaks INV-8.
- `--benchmark` and `--headless` must work with no window for the M1 gate to be checkable in CI.

## Status

**M1 complete.** Window, main loop, pan/zoom, respawn, PPM screenshot, and the
benchmark path the gate drives.

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
