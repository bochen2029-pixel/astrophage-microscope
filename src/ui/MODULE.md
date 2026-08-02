# MODULE: ui

**Depends on: `core`, `contracts`, ImGui.** Reads contracts, never `src/sim/`.

## Purpose

Dear ImGui panels: the HUD, instrument controls, the cell inspector, the parameter table with provenance badges, charts, scenario objectives, and the tool brushes.

## Files

| File | Owns | Milestone |
|---|---|---|
| `hud.cpp` | clock, counts, mean charge, medium temperature, **energy ledger**, non-canon badge | M1 |
| `instrument_panel.cpp` | view mode, objective, focal plane, overlays, clock presets | M1 |
| `inspector_panel.cpp` | clicked-cell readout including the buoyancy line | M11 |
| `params_panel.cpp` | `canon::PARAM_TABLE` with provenance badges and canon locks | M11 |
| `chart_panel.cpp` | population, energy, temperature, tolerance time series | M9 |
| `scenario_panel.cpp` | scenario picker, objective text, acceptance checkmarks | M11 |

## Contracts

Consumes `telemetry_v1.h`, `render_view_v1.h`, `scenario_v1.h`.

## Things that will bite you

- **This module owns SI → display conversion.** Everything arrives in metres, kelvin, joules, kilograms; the user sees μm, °C, mW, ng. Use `core/units.h` helpers — never open-code a factor.
- **The HUD must always be honest.** Simulated time in real units (never a bare tick count), both clock multipliers, and the total stored energy ledger permanently visible. The default 200k population fully charged is ~72 kt TNT equivalent inside a droplet; showing that is the point, not a gimmick.
- **Canon locks are default-on.** Breaking one sets a persistent `NON-CANON RUN` flag that must appear in both the HUD and every telemetry export header. A run that quietly changed a canon number and looks canon is the worst failure this UI can have.
- **The buoyancy line in the inspector is what teaches P1** — `"SINKING — 31,915 kg/m³, 32× water"`. Make it prominent, not a footnote.
- Throttle panels to ~15 Hz; the frame budget allows 0.5 ms for ImGui.

## Status

Not started. HUD stub at M1; full panels at M11.
