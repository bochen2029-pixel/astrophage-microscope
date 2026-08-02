# MILESTONES

**Read only the active milestone's section.** Each is scoped to fit one session. Each ends with a machine-checkable gate; green → `git tag m<N>-green`.

Every gate re-runs all earlier gates. Gates never weaken.

| M | Name | Delivers | Gate | State |
|---|---|---|---|---|
| M0 | Harness | build system, generated canon, RNG, determinism skeleton, scripts | `gate.ps1 -Milestone M0` | ✅ `m0-green` |
| M1 | Cell store & first pixels | GPU SoA, spawn, CUDA-GL interop, instanced discs, camera, scale bar | M1 | ✅ `m1-green` |
| M2 | Motion | OU integrator, buoyancy, boundaries → **P1** | M2 | ✅ `m2-green` |
| M3 | Optics | defocus, DOF, objectives, diffraction ring, focal plane | M3 | ✅ `m3-green` |
| M4 | Neighbourhood | spatial hash, contact, adhesion | M4 | ✅ `m4-green` |
| M5 | Fields | Grid2D, explicit diffusion, fixed-point deposit, brushes, overlays | M5 | ✅ `m5-green` |
| M6 | Thermal | mass–energy, ignition latch, thermostat → **P2 P3 P4** | M6 | ✅ `m6-green` |
| M7 | Light | Petrova emission, thrust, irradiance + occlusion → **P5** | M7 | ✅ `m7-green` |
| M8 | Taxis | run-and-tumble, phototaxis, CO₂ field, chemotaxis | M8 | ✅ `m8-green` |
| M8b | Presentation | irregular morphology, field diaphragm, defocus culling | M8b | ✅ `m8b-green` |
| M9a | Life: division | biomass, CO₂ uptake, mitosis, RNG splitting, prefix-sum slots | M9a | ✅ `m9a-green` |
| M9b | Life: content | corpses, disposition, multi-rate clock, stats reduction, compaction, charts | M9b | ☐ |
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

**Gate.** M2 gate + `test_optics` (the model) + `scripts/goldens.ps1 -Verify` (the shader), across three objectives and five focal depths.

**Do not.** No screen-space depth-of-field pass — per-instance only (cells overlap in projection; a screen-space pass gets it wrong).

**✅ Delivered 2026-08-02.** Rendering is bit-exact on a fixed driver (mean 0.0000, max 0), so golden tolerances are tight enough to catch a **2 μm focus change at 100×**. Cost: 200k cells fell from 795 fps to 426 fps at 40× — defocus is fill rate, not shader complexity (`RENDERING.md` §7).

**ADR-017** adds "must differ" golden pairs, because a golden suite proves the renderer is *stable*, not that it *does anything* — a shader ignoring the focal plane would pass one forever. The sharpest pair is focus **+2 vs −2** at 100×: identical `|dz|`, so identical blur radius and peak opacity, differing only in sign. If the polarity inversion were dropped they would be byte-identical, so that comparison is a headless test of the Becke-line inversion.

Also corrected: a comment in `optics.h` claimed sedimentation concentrates cells into a focal plane. It does not — gravity runs along −y (ADR-006), so cells pile against a side wall while their `z` stays uniformly spread. A settled monolayer only happens under `gravity_axis: z`.

---

## M4 — Neighbourhood

**Scope.** Spatial hash over chamber cells of 2.2 × `CELL_DIAMETER`: count → prefix sum → scatter (counting sort, order-stable). Soft-sphere contact (`PHYSICS.md` §9). Wall adhesion with `WALL_STICKINESS`. Reorder the SoA by hash cell each tick for coalescing.

**Gate.** M3 gate + rest overlap < 5 % of diameter in a packed cluster; no cell escapes the chamber over 10⁵ ticks; determinism hash unchanged when block size is varied (INV-4); hash rebuild < 0.5 ms at 200k cells.

**✅ Delivered 2026-08-02.** Hash rebuild **0.110 ms** at 200k cells; neighbour query matches an O(n²) brute-force reference **exactly**; packed-cluster overlap **0.55 %**; determinism through contact **0/3000** positions differing.

Three findings, all in ADR-018:
- **The hash is a stable radix sort, not an atomicAdd scatter** — the usual scatter randomises within-bucket order, which sets contact-force summation order, which breaks INV-8 intermittently.
- **Forces and integrate had to be un-fused.** M2 merged tick stages 5 and 6; contact reads neighbour positions the same kernel writes. 2709 of 3000 positions differed between identical runs before the split. §3.4 listed them separately for exactly this reason.
- **Contact stiffness is stability-limited and cannot hold a fully charged cell.** Stability caps `k` at `γ/dt`; resting a 32×-water cell within 5 % needs 3.36× that. Documented and bounded rather than hidden; the fix is contact substepping or `dt ≤ 0.3 ms`.

**The SoA is deliberately NOT reordered by bucket**, contrary to the scope above: a determinism hazard for a speculative gain. Neighbour access goes through an indirection instead. Revisit if profiling justifies it.

**Cost:** 200k cells now run at **0.28× real time** (281 ticks/s). The benchmark had to be fixed to measure that at all — under the real-time accumulator it pinned at the 8-substep cap and reported a feedback equilibrium rather than throughput.

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

**Gate.** M7 gate + a population migrates measurably up-gradient; cells in darkness emit exactly zero and their displacement distribution matches the taxis-off null.

**Clarifications the M8 session asked for, answered here so the gate is unambiguous:**

- **The gradient is the culture's own self-shadowing** — Beer–Lambert plus exact per-cell occlusion. It is real and strong: 8,000 cells lit along one axis already measure an 8× energy ratio between the lit face and the far side (M7). No contract change. A spatial profile on `LightSource` (Gaussian spot, linear ramp) is **out of M8's budget**; it needs `fields_v2.h` and belongs with `shadow-garden` at M11.
- **The null is the identical scenario with the taxis controller disabled**, same seed, same tick count, with 3σ measured from that. "Pure Brownian" was sloppy wording on my part — buoyancy still sediments cells in darkness, so the null is never zero drift.
- **Emission must discharge the store.** `dE/dt = −emit_power` (PHYSICS.md §6) is **not implemented** — nothing subtracts it today, because nothing set `emit_power` nonzero before M8. It is in M8's scope.
- **Gate the controller on `CELL_FLAG_AWAKE`.** Dormant cells are inert powder: no tumbling, no emission.
- **CO₂ uptake stays in M9.** With no sink there is no depletion halo at M8, so BREED climbs a brush-injected blob. M8 must still *fix the sampling policy* (near-field per-cell vs far-field grid) so M9's uptake cannot reintroduce the ADR-019/020/021 trap.

---

## M8b — Presentation: morphology, aperture, and the culling that pays for it

**Split from the deferred render work before starting, per Iron Rule 9.** M7b (bloom, Petrovascope and Thermal IR) keeps its own name and its own later slot; this is the silhouette work only.

**Scope.** `RENDERING.md` §8. `render_view_v2.h` adds a per-cell `shape_seed`; irregular cell silhouettes from area-preserving radial harmonics with a dense core and a ruffled rim; the circular field aperture; Q8 vertex-stage culling of sub-threshold cells, which pays for the extra fill.

**Out of scope**, deliberately: lateral chromatic aberration and medium texture (both optional in §8 and both carry honesty caveats), bloom, and the two missing view modes.

**Gate.** M8 gate + T27: the shape function is area-preserving to 0.1 % (an irregular cell absorbs exactly as much light as the disc it replaces — otherwise the render stops matching the physics), bounded, periodic, and deterministic in the seed; `Sphere` morphology reproduces the circular profile exactly. Existing goldens are pinned to `--morphology sphere` and must be **unchanged**, so the M3 optics gate keeps measuring what it always measured; one new golden on `--morphology irregular` plus a must-differ pair proves morphology does something.

---

## M9 — Life

**Split into M9a and M9b before starting, per Iron Rule 9.** The original scope carried the hardest determinism problem in the build *and* four pieces of content; those want different sessions and different gates.

### M9a — Life: division and determinism

**Scope.** `PHYSICS.md` §10, division half only. Biomass, CO₂ uptake (the field's first cell-driven sink), mitosis with energy halving and `pcg_split` RNG splitting, starvation death.

**Daughter slots are allocated by an exclusive prefix sum over the dividing flags, never by `atomicAdd`.** The snapshot hash is taken over the SoA in slot order, so if slot assignment depended on execution order the hash would vary run to run — the same reasoning as INV-2, one level up. This is the single design decision M9a turns on.

**Allocation is append-only; slot reuse and compaction are deliberately NOT in this half.** Corpses keep their slots (they already do — death only clears `ALIVE`), so nothing needs reclaiming until the store fills at `MAX_CELLS` = 2M. Compaction reorders the SoA, which reorders contact-force summation, which is exactly the hazard ADR-018 was written about; it deserves its own determinism argument rather than riding along with mitosis.

**Gate.** M8b gate + T18 (doubling matches `LIFE_DOUBLING_TIME` within 2 % under non-limiting CO₂); growth halts within one doubling of CO₂ exhaustion; **T22 — a run in which cells divide is bit-reproducible.** T22 is the real test of ADR-014 and the reason this half stands alone: every earlier determinism result holds a *fixed* population, so nothing until now has exercised the case per-cell streams exist to survive.

**The trap M8 left for it (ADR-022 §1).** CO₂ uptake creates the depletion halo the taxis controller was built to tolerate. Two guards exist and must survive: taxis samples at stage 3 *before* the cell's own deposit at stage 7, and temporal comparison is blind to a roughly-constant self-offset. `TAXIS_RUN_MAX` is the backstop for a cell that outruns its own halo — it is not decoration.

### M9b — Life: disposition, clock, charts

**Scope.** `PHYSICS.md` §10 death half and §12. Corpse rendering, the three-way store-disposition toggle (ADR-004), the multi-rate clock with its four presets (ADR-011), **tick stage 11 (`stats`) — which has never shipped** and whose first real consumer is here, slot reuse and compaction (deferred out of M9a because reordering the SoA reorders contact-force summation — ADR-018's hazard), plus the population/energy/temperature charts.

**Gate.** M9a gate + the stats reduction is deterministic across block sizes (INV-2: tree or fixed-point, never `atomicAdd` on float); each clock preset advances biology and physics at its stated ratio; `retain` disposition leaves corpses at ~32,000 kg/m³ and `void` does not.

---

## M10 — Predation

**Scope.** `PHYSICS.md` §11. `TaumoebaStore`, crawl, engulfment, digestion, N₂ field and lethality, heritable tolerance with mutation, the mean-tolerance chart.

**Gate.** M9b gate + a predator introduction crashes the population; under a slowly rising N₂ ramp the mean tolerance rises monotonically on a 5-generation moving average and a strain with tolerance ≥ 0.825 appears within 40 generations at default `TAU_MUTATION_SIGMA`.

---

## M11 — Content

**Scope.** Scenario JSON loader + schema (`contracts/scenario_v1.h`), all eight scenarios from `SCENARIOS.md` with their acceptance blocks, the objective/acceptance UI, the parameter inspector with provenance badges and the canon lock, the cell inspector (including the buoyancy readout that teaches P1), instrument panels, CSV telemetry export.

**Gate.** M10 gate + T24: the headless runner executes every scenario's `accept` block and all pass. Every `CANON` parameter is locked by default and unlocking sets the `NON-CANON RUN` flag in both the HUD and the telemetry header.

---

## M12 — Ship

**Scope.** Snapshot save/load and the time scrubber, replay determinism across a save/restore boundary, a performance pass to budget (`RENDERING.md` §7), colourblind LUT toggle, packaging (static runtimes, clean-machine `.zip`), `README.md` and a user guide.

**Gate.** M11 gate + T21, T23, T27, T28, T29 green; the packaged `.zip` runs on a scrubbed-PATH clean environment. Tag `v1.0`.
