# MODULE: ui

**Depends on: `core`, `contracts`, ImGui.** Reads contracts, never `src/sim/`.

## Purpose

Dear ImGui panels: the HUD, instrument controls, the cell inspector, the parameter table with provenance badges, charts, scenario objectives, and the tool brushes.

## Files

| File | Owns | Milestone |
|---|---|---|
| `hud.cpp` | ✅ clock, counts, fps, scope controls, population, energy ledger, and the **NON-CANON RUN badge** (M11d) | M1 |
| `scale_bar.h` | ✅ pure length-snapping function — header-only so `test_scope` can check it with no GL | M1 |
| `instrument_panel.cpp` | overlays, clock presets, the tool brushes | M5 |
| `params_panel.cpp` | ✅ provenance badges over `core/params.h`'s `ParamSet` + the canon lock toggles (M11d, ADR-034). Value editing pending the runtime read path (M11e) | M11d |
| `chart_panel.cpp` | population, energy, temperature, tolerance time series | M9 |
| `inspector_panel.cpp` | clicked-cell readout including the buoyancy line | M11e (not built) |
| `scenario_panel.cpp` | scenario picker, objective text, acceptance checkmarks (view onto `sim/accept.cpp`) | M11e (not built) |

## Contracts

Consumes `telemetry_v1.h`, `render_view_v2.h`, `scenario_v2.h`. The panels also read
`core/params.h` (the `ParamSet` overlay) and `sim/accept.cpp` (the objective checkmarks).

## Things that will bite you

- **This module owns SI → display conversion.** Everything arrives in metres, kelvin, joules, kilograms; the user sees μm, °C, mW, ng. Use `core/units.h` helpers — never open-code a factor.
- **The HUD must always be honest.** Simulated time in real units (never a bare tick count), both clock multipliers, and the total stored energy ledger permanently visible. The default 200k population fully charged is ~72 kt TNT equivalent inside a droplet; showing that is the point, not a gimmick.
- **Canon locks are default-on.** Breaking one sets a persistent `NON-CANON RUN` flag that must appear in both the HUD and every telemetry export header. A run that quietly changed a canon number and looks canon is the worst failure this UI can have.
- **The buoyancy line in the inspector is what teaches P1** — `"SINKING — 31,915 kg/m³, 32× water"`. Make it prominent, not a footnote.
- Throttle panels to ~15 Hz; the frame budget allows 0.5 ms for ImGui.

## Status

**M1 complete.** Scope panel (objective, zoom, focal plane, view mode), population
controls with respawn, and the scale bar. Full panels at M9/M11.

The HUD deliberately shows `(focus has no visual effect until M3)` and
`(only Charge is populated at M1)` rather than presenting inert controls as working.
A control that silently does nothing is worse than one labelled as pending.

The length-snapping half of the scale bar lives in `scale_bar.h` as a pure function so
`test_scope` can verify it at all three objectives across the whole zoom range without
a GL context. A gate you can only check by squinting at a screenshot is not a gate.
