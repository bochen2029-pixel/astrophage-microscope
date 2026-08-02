# Astrophage Microscope Simulator

A physics-based, GPU-accelerated simulation of **Astrophage** — the fictional organism from Andy Weir's *Project Hail Mary* — seen **through a microscope**.

A sealed 4 mm culture chamber of water. Cells 10 μm across, black at every wavelength, holding up to 1.5 MJ each as neutrino mass. Real Stokes drag, Langevin dynamics, Fickian diffusion, conduction, and photon momentum. Canon-locked constants with the provenance of every number visible in the UI.

**Not** a game, and **not** the interstellar scale — no ships, no Petrova arc, no Tau Ceti. Just what you would see down the eyepiece.

```
Status:  M2 green  ·  C++20 + CUDA 13.1  ·  sm_89  ·  Windows 11
         200,000 cells at 795 fps on an RTX 4070 Ti SUPER
         P1 live: drift velocity linear in charge, zero crossing at 3.00577%
```

---

## The five things worth building this for

Each **emerges** from the physics. None is special-cased anywhere in the code.

**P1 — The 3% line.** Canon says a cell is 10 μm across and masses 0.021 ng. That works out to 40 kg/m³ — twenty-five times *lighter* than water. So an empty cell floats up at 52 μm/s. Charge it fully and the 16.69 ng of stored mass makes it 32× *denser* than water, denser than osmium, and it sinks at 1681 μm/s. Neutral buoyancy lands at exactly **3.006 % charge**. You can read a cell's charge from which way it drifts.

**P2 — The perfect thermostat.** 96.415 °C sits 3.585 K below water's boiling point, and a cell's heat output falls to zero as the medium approaches its setpoint. So a live culture pins its water to 96.415 °C and **can never boil it**. Overheat the chamber from outside and the cells absorb the excess and drag it back down. Weir picked that temperature from an unrelated proton-collision calculation; this consequence is free.

**P3 — Ignition.** Below the setpoint Astrophage is inert black powder. Heat the chamber past 96.415 °C once and the culture wakes — irreversibly. Chill it back down and it holds its own temperature anyway.

**P4 — Live cells move.** A live cell warms the water around it, viscosity drops 3.4×, Brownian diffusivity rises 4.2×. Live and dead are distinguishable by eye — which is exactly the tell Ryland Grace uses.

**P5 — Absolute shadows.** Albedo is exactly zero at every wavelength. In a lit dense culture the front row shadows everything behind it perfectly, so a lit monolayer forms and the back starves.

---

## Build

Requires CUDA 13.1+, MSVC 2022, CMake 3.27+, Python 3.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
```

```bash
ctest --test-dir build --output-on-failure
```

`ASTRO_BUILD_APP` defaults to `OFF`, so the core library and the whole test suite build with no network and no external dependencies. Add `-App` to build the windowed application (first configure fetches GLFW, GLAD, and Dear ImGui):

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -App
```

Then run it. Drag to pan the stage, scroll to zoom (cursor-anchored), `Home` to reset, `Esc` to quit:

```bash
build/astrophage.exe
```

## Milestones

| M | Delivers | State |
|---|---|---|
| M0 | Harness: build system, generated canon, RNG, determinism oracle, gates | ✅ `m0-green` |
| M1 | Cell store, CUDA-GL interop, instanced discs, camera, scale bar | ✅ `m1-green` |
| M2 | Motion: OU integrator, buoyancy → **P1** | ✅ `m2-green` |
| M3 | Microscope optics: defocus, DOF, objectives, diffraction | ☐ |
| M4 | Spatial hash, contact, adhesion | ☐ |
| M5 | Fields: diffusion, fixed-point deposit, brushes | ☐ |
| M6 | Thermal: mass–energy, ignition latch, thermostat → **P2 P3 P4** | ☐ |
| M7 | Light: Petrova emission, thrust, occlusion → **P5** | ☐ |
| M8 | Taxis: run-and-tumble, phototaxis, chemotaxis | ☐ |
| M9 | Life: mitosis, death, multi-rate clock | ☐ |
| M10 | Predation: Taumoeba, nitrogen, evolution | ☐ |
| M11 | Content: scenarios, panels, telemetry | ☐ |
| M12 | Ship: snapshot/replay, perf, packaging | ☐ |

M7 is the line where all five signature phenomena are live.

## Repository

| Path | What |
|---|---|
| `CLAUDE.md` | operating contract — **read first** |
| `docs/ARCHITECTURE.md` | module map, invariants, glossary, anti-drift machinery |
| `docs/PHYSICS.md` | the model |
| `docs/VERIFICATION.md` | **generated** physics oracle — the numbers the sim must reproduce |
| `docs/MILESTONES.md` | scope and gate for each milestone |
| `docs/DECISIONS.md` | every canon contradiction and engineering choice, adjudicated |
| `docs/SCENARIOS.md` | the eight scenarios |
| `contracts/` | frozen cross-module interfaces |
| `scripts/canon.py` | **the single source of every physical number** |
| `_run_state/NEXT_SESSION.md` | cold-start handoff |
| `_brainstorm/` | source research and the superseded v0 spec |

Every physical constant originates in `scripts/canon.py`. `scripts/derive.py` generates the C++ header, the test goldens, and the verification doc from it, so a number cannot drift between code, test, and documentation.

## Canon and invention

Every parameter is tagged `CANON` (stated in the novel), `DERIVED`, `REAL`, or `INVENTED`, and that tag follows it into the UI. Canon values are locked; unlocking one flags the run as non-canon in the HUD and in every telemetry export. Where the novel contradicts itself — and it does, twice, materially — both readings ship as playable options rather than as a silent decision. See `docs/DECISIONS.md`.

## Credit

Astrophage, Taumoeba, the Petrova line, and the Hail Mary are Andy Weir's, from *Project Hail Mary* (2021). This is an unaffiliated fan simulation.
