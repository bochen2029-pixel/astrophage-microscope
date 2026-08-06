# Astrophage Microscope Simulator — User Guide

A physics-based, GPU-accelerated simulation of **Astrophage** — the fictional organism from Andy Weir's
*Project Hail Mary* — seen **through a microscope**. Every behaviour you see emerges from honest equations,
not scripts: cells rise or sink by real buoyancy, a culture pins its water to 96.415 °C and cannot boil it,
awake cells shadow each other perfectly because their albedo is exactly zero, and a predator population
breeds a nitrogen-tolerant strain by genuine selection. Every constant carries its provenance — which
numbers Weir wrote, which are real material constants, which we invented — into the UI.

This is a **simulator and visualisation, not a game**. There is no win state and no story mode; there are
no asset files — every pixel is procedural.

---

## Running it

The download is a self-contained folder. **Extract the `.zip` and run `astrophage.exe`** from the extracted
folder. It needs nothing installed — no CUDA toolkit, no runtime — just a GPU with OpenGL 4.6 (any recent
NVIDIA/AMD/Intel). The `scenarios/` folder must sit next to the executable (it does, in the zip).

- **`astrophage.exe`** — opens an empty sandbox culture you can play with.
- **`astrophage.exe --scenario first-light`** — loads a scenario that drives itself and grades its own
  objectives live.

## The eight scenarios (`--scenario <id>`)

| id | What it shows |
|---|---|
| `first-light` | **Ignition.** Heat a slide of inert black powder past 96.415 °C and the culture wakes, irreversibly. |
| `three-percent-line` | **Buoyancy.** Empty cells rise, charged cells sink; neutral buoyancy at exactly 3.006 % charge. |
| `komorov` | Dimitri's 1 kW laser on a microbalance — a dormant cell absorbing a beam as stored energy. |
| `shadow-garden` | **Absolute shadows.** A lit dense culture: the front row shadows everything behind it perfectly. |
| `bloom` | Population dynamics — a culture doubling on its CO₂ supply. |
| `taumoeba` | **Predation + evolution.** Taumoeba eat the culture and breed the Taumoeba-82.5 strain by selection. |
| `spin-drive-face` | The one place the ship intrudes — a spin drive is a cell-scale machine, so the scope fits. |
| `sandbox` | Free play. |

## View modes

Astrophage is jet black in visible light and emits where no eye can see, so *switching modes is the core
verb* — the gap between what a human sees and what the cell is doing is the whole subject.

- **Brightfield** — what a human sees: black discs on warm white. Charge is invisible.
- **Darkfield** — bright edge-scatter on black; live and dead are legible.
- **Petrovascope** — the 25.984 μm emission band; only emitting cells glow (magenta, with a soft bloom),
  everything else is black. The canon instrument.
- **Thermal IR** — the medium false-coloured by its real temperature field; the albedo-0 cells are black
  absorbers, and awake or heated cells glow warm. A hot plume reads as a bright region.
- **Analysis** — flat discs coloured by a channel (charge, temperature, …).

A **"blend to" slider** cross-fades between any two modes so you can see the correspondence.

## Interacting with the slide

- **Right-drag** pans the stage; **scroll** zooms; the **focal-plane** slider racks focus (only ~2.5 % of
  the 60 μm chamber is sharp at a time — racking focus is how you find things).
- **Left-drag drives the active tool** (bottom panel):
  - **Inspect** — click a cell for its full state and the buoyancy line that teaches P1.
  - **Heat / Chill / CO₂ / N₂** — paint a field brush. Heat a dormant culture past the setpoint to ignite it.
  - **Light** — drag a spotlight; awake cells herd toward it (emergent, nothing scripted).
  - **Grab** — an optical trap that tows a cell, holding it against gravity.

## The HUD

Always honest: simulated time in real units, live/dead/Taumoeba counts, mean charge, medium temperature,
both clock multipliers, and the **total stored energy** in joules and TNT-equivalent (a full default culture
holds ~72 kt inside a droplet — that is the real ledger, shown on purpose). A `NON-CANON RUN` badge appears
if you ever unlock a canon constant in the parameter inspector.

## Demo / screensaver mode

**`astrophage.exe --demo`** cycles a playlist of the self-driving scenarios with camera and view
choreography, looping — a living screensaver. It yields to the mouse: interact, and it holds; go quiet, and
it resumes.

## Headless & reproducible runs (for the curious)

Everything is deterministic: the same seed and scenario always produce the same result. Useful flags:

- `--headless` — no window (still a real GL context); pair with `--screenshot out.ppm` to capture a frame.
- `--frames N --ticks-per-frame T` — fixed simulation steps, independent of wall-clock, so a capture is
  reproducible on any machine.
- `--cells N --charge F --awake` — spawn a population of your own.
- `--mode NAME`, `--objective 0|1|2` (10× / 40× / 100×), `--zoom F`, `--focus μm`.
- `--colorblind` (perceptually-uniform LUT), `--no-bloom`, `--no-field` (fall back to the pre-render-polish
  look).

Run `astrophage.exe --help` for the full list.

---

*Astrophage, Taumoeba, the Petrova line, and the Hail Mary are Andy Weir's, from Project Hail Mary (2021).
This is an unaffiliated, non-commercial fan simulation. The code is MIT-licensed; the fiction is not — see
`NOTICE.md`.*
