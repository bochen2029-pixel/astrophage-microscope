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
| M9b | Life: death | overheat death, corpses, store disposition, stage-11 stats reduction | M9b | ✅ `m9b-green` |
| M9c | Life: clock | multi-rate presets, Q19 decision, compaction, charts | M9c | ✅ `m9c-green` |
| M7b | View modes | Petrovascope, Thermal IR, Darkfield (deferred render; bloom still pending) | M7b | ✅ `m7b-green` |
| M10a | Predation | Taumoeba store, crawl, engulfment, digestion | M10a | ✅ `m10a-green` |
| M10b | Evolution | N₂ field lethality, heritable tolerance, Taumoeba-82.5 arc | M10b | ✅ `m10b-green` |
| M11a | Content: scenario spine | JSON loader, schema, world instantiation, accept eval, headless runner | M11a | ☐ |
| M11b | Content: metrics + scenarios | derived accept metrics, spin-drive flash, all 8 scenarios pass T24 | M11b | ☐ |
| M11c | Content: inspector UI | parameter inspector + canon locks, cell inspector, objective panel, CSV export | M11c | ☐ |
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

### M9b — Life: death, disposition, and the stats reduction

**Split again before starting.** The original M9b carried a determinism problem (the reduction), a physics problem (death and disposition), a risky SoA reorder (compaction) and a UI problem (charts). The first two belong together; the last two do not.

**Scope.** `PHYSICS.md` §10, death half. Death by overheating (`temp_cell > CELL_LETHAL_TEMP`; starvation already lands via the M6 path), corpses that stop emitting, stop taxis and let the thermostat disengage, the three-way store-disposition toggle (ADR-004), and **tick stage 11 (`stats`) — which has never shipped in nine milestones.**

**Gate.** M9a gate + T23: the stats reduction is **bit-identical across block sizes** (INV-2: fixed-point or tree, never `atomicAdd` on float) and its energy ledger matches a host-side sum; `retain` disposition leaves corpses at ~32,000 kg/m³ while `void` leaves them at the dry density and they stop sinking.

### M9c — Life: clock, compaction, charts

**Scope.** `PHYSICS.md` §12. The multi-rate clock with its four presets (ADR-011), **the Q19 decision** — whether fast presets scale CO₂ diffusion alongside biology, or whether the HUD simply states the limitation — slot reuse and compaction, and the population/energy/temperature charts.

**Gate.** M9b gate + each preset advances biology and physics at its stated ratio; a run with compaction enabled is still bit-reproducible (T22 re-run) — compaction reorders the SoA, which reorders contact-force summation, and that is ADR-018's hazard, so it needs its own argument rather than riding along with mitosis.

**✅ Delivered 2026-08-02.** `physics_rate` is wired into the physics dt with the diffusion substeps derived from that dt and contact stiffness scaled as `1/physics_rate`, so a fast clock stays stable and contained; at `physics_rate = 1` the state is **bit-identical to M9b**. `test_clock` asserts the preset ratios and that the two rates compound exactly. Compaction (ADR-028) is stable, prefix-sum-allocated and out-of-place, opt-in via `compaction_enabled`; T22b re-runs T22 with corpses reclaimed **and contact on** and gets an identical hash. The serial birth scan is now `cub::DeviceScan` (Q20). Charts (population / energy / temperature), both clock multipliers, and the permanent energy ledger are in the HUD.

**Q19 — decided (ADR-027): `biology_rate` does NOT scale CO₂ diffusion.** The transport limit is real physics, not a defect; faking a faster diffusivity would violate the oracle and blow the CO₂ stability budget. The honest lever is `physics_rate`, which scales diffusion correctly; the HUD states the limitation.

---

## M7b — View modes (deferred render work, done after M9c)

**Split from the deferred render work (the M8b note).** M8b took the silhouette half; this is the view-mode half.

**Scope.** `RENDERING.md` §4. Darkfield, Petrovascope, and Thermal IR drawn distinctly in the fragment shader, each with its own background — **without a contract bump** (ADR-029). Petrovascope glows by `emit_power`; Thermal IR glows by the `AWAKE` latch, which is an exact proxy for the setpoint (ADR-003). `--mode` and `--awake` CLI flags so the modes are capturable headless.

**Gate.** M9c gate + the `m7b_thermal_awake` vs `m7b_petrova_awake` must-differ golden (a live idle cell is bright in Thermal, dark in the Petrovascope), and every existing measurement golden **unchanged** (Brightfield is untouched, so the optics oracle cannot move).

**✅ Delivered 2026-08-02.** Measured: thermal vs petrova mean **34.1**, max **252** — the glow is unmistakable, and the two modes can never collapse into one another while that golden holds.

**Still deferred:** bloom over the Petrova emission, the cross-fade slider, the Thermal field-halo term, and pre-ignition warm-up of a heated-but-dormant cell (the one piece that genuinely needs `temp_cell` in the instance, i.e. `render_view_v3`).

---

## M10 — Predation

**Split into M10a and M10b before starting, per Iron Rule 9.** The original M10 carried a new organism store (its own determinism problem, T22 over again) *and* the evolution arc (N₂ lethality + heritable tolerance, whose gate demands emergent directional selection). Those want different sessions and different gates.

### M10a — Predation: the Taumoeba store, crawl, and engulfment

**Scope.** `PHYSICS.md` §11, predation half only. A `TaumoebaStore` (its own SoA, its own PCG32 streams keyed on a Taumoeba id, and the M9c compaction primitive for its dead), amoeboid **crawl** (run-and-tumble biased up the local cell-density gradient, sensing the cell spatial hash), **engulfment** on overlap with a live cell, and **digestion** (`TAU_DIGEST_TIME`, gaining `biomass × TAU_BIOMASS_YIELD`). Per Weir, a Taumoeba consumes only the **chemical** energy — the neutrino store goes to the §10 disposition toggle, `void` by default.

**Determinism is the crux, again.** Two predators overlapping one prey must resolve **order-independently**: the prey is claimed by `atomicMin` of the predator id, so the lowest-id Taumoeba wins deterministically (min is associative/commutative, the same reasoning as the fixed-point deposits — INV-2). A Taumoeba's crawl draws from its own stream; engulfment consumes no draw.

**Gate.** M9c gate + T30: a Taumoeba run is **bit-reproducible** (a new store exercising ADR-014 for the second organism), and a predator introduction into an established culture **reduces the live cell count** measurably (engulfment works) while every Taumoeba stays inside the chamber.

### M10b — Evolution: N₂ lethality and the Taumoeba-82.5 arc

**Scope.** `PHYSICS.md` §11, evolution half. The **N₂ field lethality** (`hazard = max(0, N − N_lethal·(1 + tol·k))`, Poisson death), Taumoeba **division** at 2× initial biomass, **heritable tolerance** (`parent + N(0, TAU_MUTATION_SIGMA)` clamped to [0,1] — a real draw from the Taumoeba's stream), and the mean-tolerance chart.

**Gate.** M10a gate + a predator introduction crashes the population; under a slowly rising N₂ ramp the mean tolerance rises monotonically on a 5-generation moving average and a strain with tolerance ≥ 0.825 (**Taumoeba-82.5**) appears within 40 generations at default `TAU_MUTATION_SIGMA` — by directional selection, **not by script**.

---

## M11 — Content

**Split into M11a / M11b / M11c before starting, per Iron Rule 9.** The original M11 bundled an entire greenfield scenario/JSON system, a set of *derived* acceptance metrics (velocities, correlations, doubling-time, impulse) plus one piece of genuinely new physics (the spin-drive flash), and a whole inspector/telemetry UI layer. Those are three sessions and three gates. The scenario system is a stub today (`tools/headless.cpp` prints "arrives in M11"); nothing is loaded, instantiated, or evaluated yet.

### M11a — Content: the scenario spine (headless)

**Scope.** A dependency-free hand-rolled JSON (jsonc) loader parsing `scenarios/*.json` into `contracts/scenario_v1.h`'s `Scenario` (all fields, incl. the accept blocks — *parsed*, evaluated at M11b); **scenario → world instantiation** (`WorldDesc` + boundaries + medium fields + populations + lights + clock); the `headless --scenario ID [--ticks N]` runner (load, instantiate, run, print stats — no accept yet); and all eight `scenarios/*.json`.

**Two decisions, settled:** (1) **JSON is hand-rolled** (~200 LOC over a fixed schema), so no dependency and no ADR (Iron Rule 8). (2) **Accept-evaluation and scenario *driving* move to M11b** — every accept block needs either driving (first-light's heat, taumoeba's N₂ ramp) or a derived metric, and those belong with M11b's metric machinery. `scope` (render-only) and `param_overrides` (need a runtime-param system, M11c) are parsed but not applied.

**Gate.** M10b gate + `test_scenario`: every scenario JSON loads and instantiates into a `World` deterministically (same scenario ⇒ same state hash; a different scenario differs), populations spawn, and fields set.

### M11b — Content: acceptance, derived metrics, and the physics scenarios

**Scope.** The **accept-evaluation framework** (`AcceptCheck` + measured metrics → pass/fail) and the `headless --scenario ID --assert` runner; the **scenario driving** mechanism (a headless run must apply first-light's heat and taumoeba's N₂ ramp — resolve via a scripted-stimulus list, likely a `scenario_v2` bump, its own ADR). The **derived** metrics computed from full state, not just `Stats`: `RiseVelocityEmpty`/`FallVelocityFull` (three-percent-line), `ChargeDepthCorrelation` (shadow-garden), `ChargeHeightCorrelation`, `DoublingTimeS` (bloom), `ImpulsePerCycle` (spin-drive-face). The **spin-drive flash** — an external high-intensity `PETROVA_WAVELENGTH` pulse forcing full-rate discharge (PHYSICS.md §6) — is new physics and gets its own ADR.

**Gate.** M11a gate + **T24: the headless runner executes *every* scenario's `accept` block and all eight pass.**

### M11c — Content: the runtime-parameter system, canon locks, and telemetry export

**Split from the original M11c (Iron Rule 9).** The original bundled a whole runtime-parameter
system, the canon-lock guarantee, CSV export, AND four ImGui panels. The first three are
headless-verifiable (a unit test, a written file); the panels are pixels. They are two
sessions and two gates — and the panels are best built where a display can check them.

**Scope.** The **runtime-parameter overlay** (`src/core/params.h`): a `ParamSet` over `PARAM_TABLE`'s
109 parameters, values initialised from canon, **every `CANON` parameter locked by default**,
and a sticky `non_canon_run` flag set the moment a canon lock is broken. The `Stats.non_canon_run`
plumbing (`World` → `world_stats`) so the flag reaches the HUD and every export. **CSV telemetry
export** (`headless --csv`): the `SCENARIOS.md` columns, one row per sampled tick, a header
recording seed / scenario / `git describe` / and every broken canon lock. This is the anti-drift
backbone of the UI — *a run that quietly changed a canon number and looks canon is the worst
failure the inspector can have* — and it is the architectural crux (canon is `constexpr`).

**Gate.** M11b gate + `test_param_locks`: a `CANON` parameter is locked by default and breaking
that lock sets `non_canon_run` (sticky); the overlay's values match `PARAM_TABLE`.

### M11d — Content: app auto-play and the parameter inspector

**Split from the original M11d (Iron Rule 9).** Two of the four panels (params inspector, the HUD
badge) plus auto-play are self-contained and verifiable by an offscreen screenshot; the other two
(cell inspector, objective panel) need cell picking and a live `RunAggregates`, and the objective
panel bumps the `ui`-never-includes-`sim` boundary (`accept_eval` lives in `sim`). Those go to M11e.

**Scope.** Wiring the app to **auto-play** a loaded scenario's drive script (`--scenario`;
`scenario_apply_drive` in the tick loop, the scenario's own clock + scope) so the eight scenarios
can be **watched**, not just asserted. The **parameter inspector** (`params_panel.cpp`): every
`PARAM_TABLE` entry with its provenance badge, over the `core/params.h` `ParamSet`, with the canon
locks — unlocking a `CANON` parameter flips the persistent **NON-CANON RUN** badge (HUD + panel).
Live *value* editing is labelled pending (it needs the runtime read path, M11e); the inspector is a
provenance view plus the lock guard, never an editor that does nothing.

**Gate.** M11c gate + `astrophage --scenario <id> --headless --gl-debug` auto-plays every scenario
cleanly (exit 0, no GL errors, containment held).

### M11e — Content: the objective panel, the cell inspector, and live overrides

**Scope.** The **objective/acceptance panel** (`scenario_panel.cpp`) — the accept checkmarks, live,
against a `RunAggregates` sampled in the app loop; the results are computed app-side (which links
`sim`) and passed to the panel, since `ui` may not include `sim`. The **cell inspector**
(`inspector_panel.cpp`, click a cell → its state + the P1 buoyancy line; the HUD Charge section
already teaches P1, so this is the per-cell view). And **the sim reading overridden param values**
for a curated tunable set (via `World` fields), so the inspector's sliders finally affect physics.

**Gate.** M11d gate + a live-override check (override a param, run, confirm the physics changed) and
the objective panel agreeing with `headless --assert`.

---

## M12 — Ship

**Scope.** Snapshot save/load and the time scrubber, replay determinism across a save/restore boundary, a performance pass to budget (`RENDERING.md` §7), colourblind LUT toggle, packaging (static runtimes, clean-machine `.zip`), `README.md` and a user guide.

**Gate.** M11 gate + T21, T23, T27, T28, T29 green; the packaged `.zip` runs on a scrubbed-PATH clean environment. Tag `v1.0`.
