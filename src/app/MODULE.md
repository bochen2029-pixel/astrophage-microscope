# MODULE: app

**Depends on: everything.** The composition root — the only place globals are permitted.

## Purpose

Window, main loop, CLI, and the wiring that connects `sim`, `fields`, `render`, and `ui`. Owns the fixed-tick accumulator.

## Files

| File | Owns | Milestone |
|---|---|---|
| `main.cpp` | entry point, CLI parsing, composition | M1 |
| `application.cpp` | GLFW window, fixed-tick accumulator, input, tool brushes | M1 |
| `cli.cpp` | flags: `--scenario`, `--seed`, `--benchmark`, `--headless`, `--gl-debug`, `--frames`, `--snapshot` | M1 |

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

Not started. Begins at M1.
