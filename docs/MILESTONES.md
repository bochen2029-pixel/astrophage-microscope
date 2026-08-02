# MILESTONES

**Read only the active milestone's section.** Each is scoped to fit one session. Each ends with a machine-checkable gate; green → `git tag m<N>-green`.

Every gate re-runs all earlier gates. Gates never weaken.

| M | Name | Delivers | Gate | State |
|---|---|---|---|---|
| M0 | Harness | build system, generated canon, RNG, determinism skeleton, scripts | `gate.ps1 -Milestone M0` | ✅ `m0-green` |
| M1 | Cell store & first pixels | GPU SoA, spawn, CUDA-GL interop, instanced discs, camera, scale bar | M1 | ✅ `m1-green` |
| M2 | Motion | OU integrator, buoyancy, boundaries → **P1** | M2 | ✅ `m2-green` |
| M3 | Optics | defocus, DOF, objectives, diffraction ring, focal plane | M3 | ☐ |
| M4 | Neighbourhood | spatial hash, contact, adhesion | M4 | ☐ |
| M5 | Fields | Grid2D, explicit diffusion, fixed-point deposit, brushes, overlays | M5 | ☐ |
| M6 | Thermal | mass–energy, ignition latch, thermostat → **P2 P3 P4** | M6 | ☐ |
| M7 | Light | Petrova emission, thrust, irradiance + occlusion, view modes, bloom → **P5** | M7 | ☐ |
| M8 | Taxis | run-and-tumble, phototaxis, CO₂ field, chemotaxis | M8 | ☐ |
| M9 | Life | biomass, mitosis, death, corpses, multi-rate clock | M9 | ☐ |
| M10 | Predation | Taumoeba, N₂, heritable tolerance, evolution | M10 | ☐ |
| M11 | Content | scenario system, all 8 scenarios, UI panels, charts, telemetry | M11 | ☐ |
| M12 | Ship | snapshot/replay, perf pass, packaging | `v1.0` | ☐ |

**M7 is the "it feels real" line** — all five signature phenomena are live. M8–M12 add depth and content.

---

## M0 — Harness

*The harness comes before the product.*

**Scope.** `CMakeLists.txt` (C++20, CUDA 17, `sm_89`, static MSVC + CUDA runtimes, warnings-as-errors). Two target groups: a dependency-free `astro_core` + `astro_sim` + `astro_fields` static library set and a `tests` executable that link with **no** GL/GLFW/ImGui; and an `astrophage` app target that fetches GLFW/GLAD/ImGui. `scripts/{build,gate,audit}.ps1`. `scripts/derive.py` wired into the build as a pre-step. `core/rng.cuh` (PCG32 + split + Box–Muller gaussian). `core/vec.cuh`. `core/fixed_atomic.cuh`. `core/units.h`. An empty deterministic tick loop with an FNV-1a snapshot hash. `tools/headless.cpp` that runs N ticks and prints the hash.

**Contracts produced.** `cell_store_v1.h`, `snapshot_v1.h` (skeleton; fields may be empty).

**Gate.**
1. `derive.py --check` clean.
2. Clean configure + build, zero warnings.
3. `ctest` green: PCG32 reproduces known vectors; gaussian has correct mean/variance over 1e6 draws; fixed-point atomic round-trips; `headless --ticks 10000` prints the same hash twice.
4. Module inventory matches the directory listing.

**Do not.** Do not write physics. Do not open a window. Do not add a dependency beyond CUDA.

---

## M1 — Cell store & first pixels

**Scope.** `CellStore` device SoA with capacity `MAX_CELLS`, free-list, counting-sort-friendly layout. Spawn kernels (uniform, gaussian, grid placement) with per-cell RNG streams. GLFW window + GL 4.6 + ImGui bootstrap in `app`. `cudaGraphicsGLRegisterBuffer` interop: a kernel writes instance attributes into a GL VBO. One instanced draw for N cells, disc rendered as an SDF in the fragment shader. Camera: pan, zoom, objective presets from `canon::OBJECTIVES`. Scale bar snapping to 10/20/50/100/200/500 μm. HUD stub showing tick, cell count, FPS.

**Contracts.** Consumes `cell_store_v1.h`; produces `render_view_v1.h`.

**Gate.** M0 gate + window opens; `BENCH_CELLS` render at ≥ `TARGET_FPS`; cells drawn at true relative size; scale bar correct at all three objectives; zero GL debug-output errors.

**Do not.** No motion. No fields. No optics beyond a flat disc.

**✅ Delivered 2026-08-02.** 200,000 cells at ~795 fps (5.5× target), zero GL errors. Scale-bar and true-size conditions are verified headless by `test_scope` rather than by eye. `DEFAULT_CELLS` dropped to 25,000 — see ADR-015, projected coverage is not volume fraction.

---

## M2 — Motion → P1

**Scope.** `PHYSICS.md` §3 and §4. Exact-propagator OU integrator as a `__host__ __device__` function (so tests exercise the real code path). Buoyant weight, mass–energy coupling for `mass`, boundary handling (reflecting/periodic/absorbing), Vogel–Fulcher viscosity. A charge slider that sets every cell's charge so P1 is directly observable.

**Gate.** M1 gate + tests T1, T2, T3, T4, T6, T8, T14 green against `tests/golden/expected_values.h`. Visually: set charge below 3.006 % and the culture rises; above, it sinks; at 3.006 % it hovers.

**Do not.** No thermal model yet — `T_local` is a scenario constant. No thrust source yet; T6 drives `emit_power` directly.

**✅ Delivered 2026-08-02.** T1 −1681.5 μm/s, T2 +52.1 μm/s, T3 hovering, T4 MSD/4Dt = 1.020, T6 35.33 μm/s. Drift velocity is linear in charge to **Pearson −1.000000** and crosses zero at **3.00577 %** against a canon-derived 3.00577 %.

Two corrections landed with it, both found by the oracle before any code shipped:
- **ADR-016** — the integrator in the original spec (`v` propagated exactly, then `r += v·dt`) gives **47× too much diffusion** for an empty cell. Replaced with the exact joint position–velocity propagator.
- The oracle and the simulator were using **two different viscosity models** (tabulated vs. Vogel–Fulcher). Unified on VF, which the simulator has no choice about; the tabulated values stay as cross-checks on the fit.

**T14's statistic changed, and became stricter.** A whole-population position correlation saturates near 0.84 no matter which statistic is used — not from wall pile-up, but because cells within a hair of 3.006 % have near-zero drift and simply stay where they spawned. That is correct physics. T14 now asserts the sharp form of P1 — drift *velocity* linear in charge with the zero crossing at the canon value — plus group separation (> 1 mm gap after 60 s; measured 3.26 mm).

---

## M3 — Optics

**Scope.** `RENDERING.md` §3. Per-instance circle-of-confusion `r_coc = |z - z_focus| * NA / n`, quad expansion, analytic Gaussian-convolved SDF. Diffraction ring (two `smoothstep` bands, amplitude scaled by focus). Defocus polarity flip above vs below focus. Focal-plane control (scroll/keys) with an on-screen depth indicator. Condenser vignette. Sub-pixel cell handling: clamp rendered radius to 0.75 px, modulate alpha by area ratio.

**Gate.** M2 gate + golden-image comparison against `goldens/m3_*.png` within tolerance, at all three objectives and three focal depths. Racking focus visibly resolves and blurs cells.

**Do not.** No screen-space depth-of-field pass — per-instance only (cells overlap in projection; a screen-space pass gets it wrong).

---

## M4 — Neighbourhood

**Scope.** Spatial hash over chamber cells of 2.2 × `CELL_DIAMETER`: count → prefix sum → scatter (counting sort, order-stable). Soft-sphere contact (`PHYSICS.md` §9). Wall adhesion with `WALL_STICKINESS`. Reorder the SoA by hash cell each tick for coalescing.

**Gate.** M3 gate + rest overlap < 5 % of diameter in a packed cluster; no cell escapes the chamber over 10⁵ ticks; determinism hash unchanged when block size is varied (INV-4); hash rebuild < 0.5 ms at 200k cells.

---

## M5 — Fields

**Scope.** `PHYSICS.md` §7. `Grid2D<float>` in device memory with bilinear sample and scatter. Explicit red-black diffusion with the substep counts from `VERIFICATION.md` §6. Fixed-point i64 deposit accumulators (INV-2). Boundary conditions: dirichlet/neumann/robin. Field overlay render pass with LUTs. Heat and chill brushes.

**Contracts.** Produces `fields_v1.h`.

**Gate.** M4 gate + T25: 512² field, 10⁴ ticks with strong sources → no NaN, no oscillation, energy conserved to 0.1 % under insulated BC; analytic point-source steady state matches `T(r) = T∞ + ΔT·a/r` in the far field within 2 %; deposit determinism hash stable across block sizes.

**Do not.** No cell–field coupling yet — sources are brush-only. No irradiance field (that is M7).

---

## M6 — Thermal → P2, P3, P4

**Scope.** `PHYSICS.md` §5. Energy/mass bookkeeping, ignition latch, bidirectional thermostat, conduction, cell→field deposit, the analytic near-field halo correction (ADR-010), death by starvation. Thermal-IR view mode.

**Gate.** M5 gate + T5, T7, T9, T10, T11, T12, T19 green. Specifically: a 2,000-cell insulated chamber asymptotes to 369.565 ± 0.2 K and **never exceeds 373.15 K**; externally driving it to 400 K returns it to setpoint with total cell energy increasing; the ignition latch survives cooling; live/dead MSD ratio > 3.5.

**Do not.** No emission. Cells do not move toward anything yet.

---

## M7 — Light → P5

**Scope.** `PHYSICS.md` §6 and §7.5–7.6. Petrova emission with directional lobe and slew, photon thrust, irradiance field with total occlusion sweep, feeding absorption, Petrovascope + Brightfield + Darkfield view modes, bloom chain on Petrova emission only, the film-magenta/false-IR/magma LUTs.

**Gate.** M6 gate + T13 (rear cell in a collinear pair has irradiance exactly 0 and dCharge/dt exactly 0), T15 (Komorov: 1 kW × 1500 s ⇒ 1.5 MJ and 16.69 ng, within 0.1 %), T16, T17, T20. Charged-fraction/depth correlation r < −0.8 in a dense lit culture.

**This is the "it feels real" milestone.** All five signature phenomena are live at the end of it.

---

## M8 — Taxis

**Scope.** `PHYSICS.md` §8. Run-and-tumble with temporal comparison, FEED/BREED/IDLE state machine, the darkness rule, CO₂ field and chemotaxis, the CO₂ injection brush.

**Gate.** M7 gate + a population in a light gradient migrates measurably up-gradient (mean position shift > 3σ of the null over 10⁴ ticks); cells in darkness show zero emission and pure Brownian statistics.

---

## M9 — Life

**Scope.** `PHYSICS.md` §10 and §12. Biomass, CO₂ uptake, mitosis with energy halving and RNG splitting, death paths, corpse rendering, store-disposition toggle, the multi-rate clock with the four presets, population/energy/temperature charts.

**Gate.** M8 gate + T18 (doubling matches `LIFE_DOUBLING_TIME` within 2 % under non-limiting CO₂); growth halts within one doubling of CO₂ exhaustion; T22 (a run in which cells divide is bit-reproducible — this is the real test of INV-1).

---

## M10 — Predation

**Scope.** `PHYSICS.md` §11. `TaumoebaStore`, crawl, engulfment, digestion, N₂ field and lethality, heritable tolerance with mutation, the mean-tolerance chart.

**Gate.** M9 gate + a predator introduction crashes the population; under a slowly rising N₂ ramp the mean tolerance rises monotonically on a 5-generation moving average and a strain with tolerance ≥ 0.825 appears within 40 generations at default `TAU_MUTATION_SIGMA`.

---

## M11 — Content

**Scope.** Scenario JSON loader + schema (`contracts/scenario_v1.h`), all eight scenarios from `SCENARIOS.md` with their acceptance blocks, the objective/acceptance UI, the parameter inspector with provenance badges and the canon lock, the cell inspector (including the buoyancy readout that teaches P1), instrument panels, CSV telemetry export.

**Gate.** M10 gate + T24: the headless runner executes every scenario's `accept` block and all pass. Every `CANON` parameter is locked by default and unlocking sets the `NON-CANON RUN` flag in both the HUD and the telemetry header.

---

## M12 — Ship

**Scope.** Snapshot save/load and the time scrubber, replay determinism across a save/restore boundary, a performance pass to budget (`RENDERING.md` §7), colourblind LUT toggle, packaging (static runtimes, clean-machine `.zip`), `README.md` and a user guide.

**Gate.** M11 gate + T21, T23, T27, T28, T29 green; the packaged `.zip` runs on a scrubbed-PATH clean environment. Tag `v1.0`.
