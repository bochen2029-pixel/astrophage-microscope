# DECISIONS — architecture decision record

Append-only. Every contradiction in the source material and every non-obvious engineering choice is adjudicated here, with the reasoning and the escape hatch.

**Read this before overriding anything.** Re-litigating a settled decision costs a session; reading costs a minute. If you do decide to override one, add a new ADR that supersedes it rather than editing the old one.

---

## ADR-001 — Two canon errors in the original brief, corrected

**Status:** accepted, 2026-08-02.
**Context.** The brief that started this project stated that 96.415 was a frequency in THz and that the Petrova emission was at 3.11 μm / 96.415 THz.
**Decision.** Both are wrong and are corrected at the source. **96.415 is a temperature in degrees Celsius** — Weir derived it from a root-mean-square proton-velocity calculation, and it happens to land just below water's boiling point. **The Petrova line is 25.984 μm (11.538 THz)**. The 4.26 μm and 18.31 μm figures are the **CO₂ bands Astrophage navigates by**, not what it emits.
**Consequences.** `CELL_TEMP_SETPOINT` is 369.565 K. `PETROVA_WAVELENGTH` is 2.5984e-5 m. The near-coincidence of the setpoint with water's boiling point is not a coincidence we engineered — it is canon, and it produces P2.
**Escape hatch.** None. These are corrections, not choices.

---

## ADR-002 — Cell density: honour the canon mass, accept 40 kg/m³

**Status:** accepted. **This is the most consequential decision in the project.**
**Context.** Canon states three things that cannot all be true: the cell is 10 μm across, it masses 0.021 ng, and it is "mostly water". A 10 μm sphere at 0.021 ng has a density of **40.1 kg/m³** — 25× *lighter* than water. Water density would require 0.523 ng.
**Decision.** Honour the two hard numbers (diameter and mass) and treat density as derived. An empty cell is therefore strongly buoyant and rises at 52 μm/s; a fully charged cell is 32× denser than water and sinks at 1681 μm/s; neutral buoyancy falls at 3.006 % charge. The "mostly water" statement is read as compositional, not densitometric.
**Consequences.** This generates **P1**, the most legible mechanic in the simulator, directly from canon numbers rather than from invention. Charge state becomes readable at a glance from vertical drift.
**Escape hatch.** `medium.density_model: 'canon-mass' | 'water-density'` as a scenario switch. Under `water-density`, `CELL_MASS_DRY` becomes 5.227e-13 kg, empty cells are neutrally buoyant, and P1 degrades to a sinking-only effect. Both are playable; `canon-mass` is default.

---

## ADR-003 — Dormancy vs. constant temperature: the ignition latch

**Status:** accepted.
**Context.** Canon says the internal temperature is always 96.415 °C regardless of environment, *and* that Astrophage is inert unless heated above 96.415 °C. As written these contradict.
**Decision.** A one-way latch. A **dormant** cell tracks ambient and does nothing. Crossing the setpoint wakes it **irreversibly**. An **awake** cell clamps to the setpoint forever, even if the medium is then chilled.
**Consequences.** Satisfies both canon statements. Produces **P3** — a dramatic, canon-faithful ignition moment that is also the tutorial beat.
**Escape hatch.** `thermal.relatch_on_cooling: bool` for the reading where a cell can go dormant again.

---

## ADR-004 — Where a dead cell's 1.5 MJ goes

**Status:** accepted.
**Context.** Canon is silent. Weir's only stated resolution is that Taumoeba consumes the chemical energy, not the neutrino store — which leaves the store unaccounted for.
**Decision.** A three-way scenario toggle, default `void`.
- `void` — the store vanishes silently. Canon-lite; nothing detonates.
- `flash` — discharged as Petrova photons over 1 ms. Physically conserving. One full cell is 358.5 g TNT equivalent, so a mass death event triggers a scripted **containment failure** end state rather than pretending a microscope slide survives it.
- `retain` — the store persists as inert ballast, so corpses stay at 32,000 kg/m³ and rain to the coverslip.
**Consequences.** The energy-scale problem is confronted rather than ignored, which is both more honest and more interesting. The permanent HUD energy ledger exists for the same reason.

---

## ADR-005 — Petrova discharge rate = 50 mW

**Status:** accepted.
**Context.** Canon gives the *capacity* (1.5 MJ) but never a maximum emission power. Every velocity in the simulator depends on this number.
**Decision.** `PETROVA_MAX_POWER` = 50 mW, `INVENTED`, tunable across eight decades.
**Rationale.** 47.59 mW is exactly the power a fully charged cell needs to hover against its own weight. Setting the maximum just above that puts "can just barely hold itself up when full" at the top of the dial, which is both dramatically and pedagogically ideal — and it makes 1 mW (35 μm/s, crossing a field of view in 16 s) a natural mid-scale.
**Consequences.** Flagged loudly in the parameter inspector because so much depends on it.

---

## ADR-006 — Gravity acts along −y, not −z

**Status:** accepted.
**Context.** A real upright microscope has a vertical optical axis, so sedimentation runs straight through the focal plane and is invisible — cells would simply drift out of focus.
**Decision.** Model a side-mounted / inverted stage so buoyant drift is in-plane and legible.
**Consequences.** P1 is directly observable. This is disclosed in the UI rather than hidden.
**Escape hatch.** `gravity_axis: 'y' | 'z'`.

---

## ADR-007 — Temporal-comparison taxis, not spatial gradients

**Status:** accepted.
**Context.** Two problems with spatial gradient climbing: a 10 μm cell cannot meaningfully finite-difference a 7.8 μm grid across its own body, and a smooth gradient-glide reads as a video game rather than as an organism.
**Decision.** Run-and-tumble with a `TAXIS_MEMORY_TIME` temporal comparison, exactly as real chemotactic bacteria do.
**Consequences.** Cheaper (no gradient sampling), robust to field noise, biologically defensible, and it looks alive.

---

## ADR-008 — Explicit diffusion at 512², not implicit ADI

**Status:** accepted. **Supersedes the ADI decision in the archived v0 spec.**
**Context.** The v0 (CPU) spec chose Peaceman–Rachford ADI because explicit stability at 1.5 μm grid spacing demanded a 4.2 μs timestep — 240 substeps per tick, impossible on a CPU.
**Decision.** On GPU with a 4 mm chamber at 512², `dx` = 7.8 μm and the explicit limit is 1.06e-4 s — **10 substeps per tick**, costing well under 0.1 ms on sm_89. Use explicit red-black. An ADI path would need batched tridiagonal solves (cuSPARSE `gtsv2StridedBatch`) for no practical gain.
**Consequences.** Simpler, deterministic, fast enough. **Do not raise the grid to 1024²** without re-deriving: substeps quadruple to 38 and memory traffic becomes the dominant cost.
**Escape hatch.** If a scenario ever needs 1024²+, add the cuSPARSE ADI path behind a solver-selection flag rather than raising the substep count.

---

## ADR-009 — A large chamber with a movable scope, not a single field of view

**Status:** accepted.
**Context.** A 40× field of view is 550 μm. At close packing that volume holds only about 5,000 cells — which would waste the GPU and make "population dynamics" meaningless.
**Decision.** The simulated **chamber** is 4 mm × 4 mm × 60 μm; the **scope** is a movable, focusable window onto it showing 550 μm at 40×.
**Consequences.** The chamber holds ~200k cells at a few percent packing and up to ~2M at dense packing, which is a real workload for sm_89. Panning the stage to look around is also exactly what using a microscope is like, so the constraint improves the product. Drives the `Chamber` / `Scope` glossary split.

---

## ADR-010 — Analytic near-field, grid far-field

**Status:** accepted.
**Context.** At `dx` = 7.8 μm the grid cannot resolve the thermal halo within a few radii of a cell, where the profile is steepest — but that near field is analytically known: `T(r) = T∞ + ΔT·a/r`.
**Decision.** A cell's `T_local` is the bilinear grid sample **plus** the analytic contribution of hash-neighbours within 4a, minus those neighbours' already-smeared grid contribution to avoid double counting.
**Consequences.** Removes all resolution pressure from the grid, which is what makes ADR-008 viable. Standard practice for point-source problems.

---

## ADR-011 — Decoupled physics and biology clocks

**Status:** accepted.
**Context.** The processes span nine orders of magnitude, from 2.2e-7 s momentum relaxation to 6.9e5 s mitosis. A single global time-scale slider cannot work: at 10⁶× the integrator explodes, at 1× nothing ever divides.
**Decision.** Two independent multipliers — `physics_rate ∈ [0.1, 100]` (stiff, stays near 1) and `biology_rate ∈ [1, 1e6]` (non-stiff, free) — plus four named presets that drive both.
**Consequences.** Do not replace this with one slider, however much simpler it looks. The HUD must always show both and the elapsed time in real units.

---

## ADR-012 — C++20 + CUDA, superseding the TypeScript/WebGL v0 spec

**Status:** accepted, 2026-08-02.
**Context.** The initial spec (archived at `_brainstorm/SPEC_v0_webgl_superseded.md`) targeted TypeScript + WebGL2 + Web Workers, budgeting 20,000 cells at 60 fps. The machine has CUDA 13.1 and an RTX 4070 Ti SUPER (sm_89, 16 GB), and three existing projects on it (`Buddhabrot_CUDA`, `backrooms`, `Booster_Lander_Simulator`) establish a proven C++20/CUDA/CMake toolchain and process.
**Decision.** C++20 + CUDA 13.1 + OpenGL 4.6 interop + GLFW/GLAD/Dear ImGui + CMake, mirroring `Buddhabrot_CUDA`'s stack and `backrooms`' contracts-and-gates process.
**Consequences.** Cell budget rises from 20k to 200k default / 2M maximum, which is what makes ADR-009's chamber-scale simulation possible at all. Determinism becomes harder and is addressed by ADR-013 and ADR-014. The v0 spec's physics model survives essentially unchanged — it was renderer-agnostic — and its solver choice is superseded by ADR-008.

---

## ADR-013 — Fixed-point integer atomics for all deposits and reductions

**Status:** accepted. **This is what makes GPU determinism achievable at all.**
**Context.** `atomicAdd(float*)` produces results that depend on warp scheduling, because float addition is not associative. Any field deposit or statistic accumulated that way breaks INV-8 on every run.
**Decision.** All field deposits and all statistics accumulate into **64-bit fixed-point integers** via `atomicAdd(unsigned long long*)`, converted to float after the kernel. Per-field scale factors live in `contracts/fields_v1.h`.
**Consequences.** Integer addition is associative and commutative, so the result is independent of execution order. Costs one multiply and one round per deposit. Range and precision must be checked per field when a scale is chosen — an overflowing accumulator is a silent correctness bug, so `fields_v1.h` documents the safe range for each.

---

## ADR-037 — Taumoeba rendering: appended instances, a view contract, and a marker bit

**Status:** accepted, 2026-08-03 (M12b).

**Context.** The predators ran but were invisible — the app filled the instance buffer from the cell store only. `render_view_v2`'s `RenderFrame` already anticipated the fix (`taumoeba_offset`: instances `[taumoeba_offset, count)` are Taumoeba), so the intended design is to append the predators as `CellInstance`s after the cells and draw them in the same instanced pass. Three things had to be settled to build it.

**A `TaumoebaView` contract, symmetric with `CellStoreView`.** `render/` may not include `src/sim/` (it reads contracts), so it cannot see the `TaumoebaStore`. The interop kernel that turns a predator into a `CellInstance` needs a device view, exactly as `fill_instances` reads a `CellStoreView`. New frozen contract `contracts/taumoeba_view_v1.h` exposes only what the draw needs (id, flags, position, tolerance). The app (which links both) builds one from the store and hands it to render — the same shape as passing `w.cells.view`. A per-array download or a host round-trip was never on the table: positions must not touch host memory (ARCHITECTURE §3.1).

**One map, not two.** The GL buffer is registered `WriteDiscard`, so mapping it a second time to add the predators would discard the cells the first kernel just wrote. `interop_fill_frame` therefore maps once, launches `fill_instances` into `[0, cell_count)` and `fill_taumoeba` into `[cell_count, total)`, and unmaps. The instance buffer is sized `cell_capacity + tau_capacity`; `CellsPass::capacity` still reports the *cell* capacity so the HUD and the respawn clamp keep meaning what they meant (the larger buffer is an internal detail).

**A render-only marker bit, not a `CellInstance` field.** The predators must draw distinctly (they are 4× a cell and are amoebae, not powder), but `CellInstance` is a frozen 36-byte GL contract and adding a field would be a `render_view_v3` bump for one bit. Instead `fill_taumoeba` sets `RENDER_FLAG_TAUMOEBA` (bit 15 of `flags_packed`) — a bit in the `CellFlags` region that sim never sets — and the fragment shader branches on it into a translucent teal membrane. Because a cell always reads 0 there, the branch is a no-op for cells and every measurement golden is byte-identical (the M3 goldens carry no predators; the gate re-verifies them). The bit crosses the GLSL boundary uncompiler-checked, the same hazard class as ADR-017's duplicated optics formulas — hence the shared constant and the change-one-change-both comment.

**Consequences / the gate.** `M12b.1`: the app renders the `taumoeba` scenario headless with zero GL errors, and the goldens still match. Verified by screenshot: at the predator swarm's peak the green membranes tile the field, and early on individual irregular blobs consume the black culture. Deferred: a distinct amoeba *silhouette* (they reuse the cell morphology today), a tolerance-coloured Analysis channel (the view already carries `tolerance`), and hiding non-emitters in Petrovascope (the predators show in every mode as a visualization aid).

---

## ADR-036 — The snapshot: a full-state oracle, a `.cu`, and what snapshot_v1 does not carry

**Status:** accepted, 2026-08-03 (M12a).

**Context.** `contracts/snapshot_v1.h` has been the frozen shape of the ASPH dump since M0, but nothing wrote or read it — `src/sim/snapshot.cpp` was an inventory placeholder. M12a builds it, and four things had to be settled.

**The state hash is over the WHOLE state, and it supersedes the subset `headless` hashes.** `tools/headless.cpp` hashes only position/velocity/energy for its fast replay gate — enough to catch an integrator regression, but blind to ids, flags, biomass, taxis memory, the RNG streams, the predators, and the fields. The snapshot `state_hash` is FNV-1a over every serialised byte (both SoA stores + the T/CO₂/N₂ fields, in the contract's file order), so `test_snapshot` (T21) is the INV-8 oracle at full resolution. The two hashes coexist: the cheap one guards every earlier gate, the full one guards the round trip.

**It is a `.cu`, not the `.cpp` the inventory named.** The `.cpp` files in `astro_sim` (`accept.cpp`, `scenario.cpp`) reach the device only through the `_download_*` helpers — they never include `cuda_runtime.h`. Snapshot copies *every* SoA array (25 cell + 20 predator + 3 fields); adding a download/upload helper per array would be a hundred lines of boilerplate in the `.cu` files plus a hundred more of calls. Making snapshot itself a `.cu` lets it `cudaMemcpy` each array directly, and the array list is written once per store (`collect_*_spans`) and reused for both save and load, so the two directions can never disagree about layout. The inventory and `sim/MODULE.md` are updated to `snapshot.cu` in the same commit (Iron Rule 7).

**The ADR-035 overrides ride the `ParamOverride` array; determinism-irrelevant scalars are not serialised.** A curated override that differs from canon is emitted as a `{key, value}` entry (zero-initialised, so the hashed padding is deterministic) and re-applied by key on load; the sticky `non_canon_run` rides the header. Motion configuration (boundaries, which stages are enabled, compaction) is deliberately NOT in the file — it is *how a run was set up*, not its state, and the caller (a scenario, the app) restores it exactly as it set it originally, the same way a game reloads its rules from the executable, not the save. The field values overwrite whatever ambient/CO₂ `world_create` seeded, so the create-time config does not leak in. The per-tick scratch (`t_local…`) IS serialised (the contract lists it, and it makes the round trip bit-identical) even though it is recomputed next tick; the irradiance FIELD is not (rebuilt from scratch every tick, per the contract).

**One snapshot_v1 gap, handled and flagged.** The header carries `next_cell_id` but no `next_taumoeba_id`. IDs are monotonic and never reused, so load reconstructs it as `max(id)+1` — exact unless the highest-id predator was already culled, in which case a post-restore predator division could reuse a retired id's RNG stream and diverge from a never-saved run. `test_snapshot`'s replay-across-the-boundary arm is therefore cells-only (predators are exercised by the round-trip-fidelity arm, where next_id is not hashed). A `next_taumoeba_id` field in a future `snapshot_v2` closes it; it is not worth a contract bump for M12a.

---

## ADR-035 — Curated live-tunable overrides, and the cell inspector

**Status:** accepted, 2026-08-03 (M11f).

**Context.** ADR-034 built the `ParamSet` overlay and deferred two things to a later milestone: making the inspector's value editing *actually affect physics*, and the cell inspector itself. The sim reads `constexpr canon::` at every use site (Iron Rule 3), so for an edit to bite, the sim must read the overlay's value instead. The tempting move -- thread a `ParamSet` through every kernel signature -- is exactly the `constexpr`->runtime refactor ADR-034 warned against: it touches every hot path, for a feature no scenario uses today, and multiplies the determinism surface.

**Decision -- a small CURATED set of overrides, one `World` field each.** A handful of parameters get a `double` field on `World`, defaulted to *exactly* their `canon::` value; the kernel that needs one reads `w.<field>` instead of `canon::<CONST>` (passed as a kernel argument, the flash's existing idiom). The app fills these fields from the `ParamSet` every frame. Adding a parameter to the set is four edits: a `World` field, one kernel read-site, one app push line, and the `param_live` flag. The M11f set is `PETROVA_MAX_POWER` (emission cap), `PETROVA_FLASH_POWER` (spin-drive discharge rate), and `CO2_MASS_PER_DIVISION` (mitosis quota) -- one per touched kernel (taxis, flash, lifecycle), spanning the emission, discharge, and growth phenomena. The physics functions (`taxis_emit_power`, `ready_to_divide`) take the value as a **defaulted** argument (`= canon::...`), so every other caller -- the tests, any future kernel -- is unchanged and bit-identical.

**Determinism is preserved by construction, and that is half the gate.** Each field's default is the canon constant, and the kernel does the identical arithmetic on the identical `double`, so an untouched run is bit-identical to M11e (INV-8). `test_param_override` asserts both directions: a tuned parameter changes the population/discharge in the predicted direction, AND the default reproduces the canon run exactly (4000 == 4000). A gate that only checked "the override changes something" could pass while silently perturbing M9a/M11b; the default-equals-canon half is the honest guard (meta-lesson: what can your assertion not see).

**The panel stays honest.** The inspector draws a real editable slider ONLY for the curated `param_live` set (range and log-scale from the canon table); every other parameter stays read-only, because a control that silently does nothing is worse than one labelled pending (`ui/MODULE.md`). A `CANON` parameter in the set (none today) still sits behind its lock -- unlocking it flags the run non-canon (ADR-034), then it becomes editable. The full `constexpr`->runtime refactor stays deferred: it is only worth doing when a scenario or a use case needs a parameter outside this set.

**The cell inspector.** Click a cell -> its state with the P1 buoyancy line prominent (`ui/MODULE.md`: the buoyancy line is what teaches P1). Picking is app-side: cursor -> chamber coordinate via the camera, nearest cell from a positions download, the slot latched with its id so a recycled slot drops the pick rather than showing a stranger. The per-cell state is read at HUD rate through a new `cell_store_sample` (one small D2H for one cell), converted to display units, and handed to the panel as plain data -- `ui` may not include `sim` (the same boundary the objective panel uses). `--inspect N` pre-selects a slot so the panel is verifiable in a headless screenshot, since a click is not expressible headless.

**Consequences / the gate.** `M11f.1` (`test_param_override`) + `M11f.2` (the app renders a picked cell headless with zero GL errors). No contract change: `CellSample` is a sim-internal read type, `CellReadout` is ui-internal display data, and picking reuses the existing `CellStoreView`. Scenario `param_overrides` (parsed since ADR-031, still unapplied) would now flow through this overlay, but no scenario sets one, so wiring that path stays deferred with the full refactor.

---

## ADR-032 — Scenario driving and acceptance: a scripted-stimulus list, derived metrics, two schema affordances

**Status:** accepted, 2026-08-03 (M11b).

**Context.** M11a loaded and ran scenarios but evaluated nothing. Every `accept` block needs either *driving* (first-light's heat, taumoeba's N2 ramp, the spin-drive flash) or a *derived* metric (velocities, correlations, doubling, impulse) computed from full state over time. The schema had `tools` (availability) but no way to say *when* a stimulus fires.

**Decision -- driving is a scripted-stimulus list (`scenario_v2`).** A `drive[]` of `Stimulus{t0_s, t1_s, kind, x, y, radius, v0, v1}`, applied every tick by `scenario_apply_drive` (sim, shared by headless and, later, the app). One struct covers a held heat brush, an N2 ramp, illumination, and the flash. Brush strengths are RATES (x dt), so a dose is invariant to `physics_rate`; `t1<=t0` is an open-ended window. `SetN2` is an absolute uniform `grid_fill` (not an additive brush), mirroring `test_evolution`'s `set_n2` so the ramp frontier `tol* = N/N_lethal - 1` is exact; `SeedCells` maintains a prey target (its `top_up_prey`). This bumps the frozen v1 to v2 (contract rule 1); nothing else changed -- `telemetry_v1.h` had already frozen the full `Metric`/`AcceptCheck` vocabulary.

**Decision -- acceptance is measured in `sim/accept.cpp`.** `accept_eval` (the compare ops; `Approx` relative unless `tol_absolute`) plus `metric_measure` from a HUD-rate `Stats` and a `RunAggregates`. Two derived metrics needed care. The **velocity fit is displacement-based** (two free-cell position snapshots a few seconds apart): a cell's *instantaneous* velocity is dominated by thermal noise (+-440 vs 52 um/s of drift), but drift over seconds swamps Brownian diffusion, so `v_settle` vs charge fits cleanly (Pearson ~ -1) and its endpoints give the empty/full velocities although no cell is full. **Doubling time is scaled by `biology_rate`** (`dt_bio = dt*biology_rate`, so culture time = sim_time * biology_rate) to report the canon 6.912e5 s. Correlations and max tolerance come from a full-state download.

**Decision -- two schema affordances the tuning forced, both physics, not fudge.** (1) `thermal_active`: `thermal_step` always ran the 512^2 diffusion, which a uniform-medium scenario (komorov: a dormant cell absorbing a beam as store, not heat) pays for nothing -- a flag skips the stage, and with `physics_rate 100` komorov drops from ~44 min to ~25 s, exact for a non-moving cell. (2) The global brush uses a radius 10x the chamber: `grid_brush`'s `(1-t^2)^2` falloff otherwise peaks at the centre and under-heats the edges, waking centre cells first (measured 665/800); a radius that keeps the whole field in the flat top of the falloff is a near-uniform fill.

**Consequences / the gate.** `headless --scenario ID --assert` runs to the objective horizon (explicit `duration_s`, else the latest `after_s`/drive window), applies the drive, evaluates every check, exits nonzero on a miss. **T24: all eight pass.** Every threshold traces to a physical value or canon (-52.1/+1681 um/s, 369.565 K +- 0.5, r < -0.8, 6.912e5 s, >= 0.825, impulse == E/c), not a magic number (meta-lesson 2). The per-scenario reconciliations (first-light dormant buffer + neumann, three-percent-line dormant, shadow-garden dormant + bright source, taumoeba's `test_evolution` mirror) are in `docs/SCENARIOS.md`.

---

## ADR-034 — The runtime-parameter overlay: a ParamSet over constexpr canon, and a sticky non-canon flag

**Status:** accepted, 2026-08-03 (M11c). Splits the original M11c into M11c (this) + M11d (the panels).

**Context.** The parameter inspector must lock every `CANON` value, let the user unlock and tune, and flag any run that broke a lock (`Stats.non_canon_run`). But canon is `constexpr` (`canon::PETROVA_MAX_POWER`), read at compile time across all of sim/fields — that is the anti-drift machinery (Iron Rule 3, `ARCHITECTURE.md §5.1`), the whole point of which is that no value drifts between doc, code, and test. A runtime override is in tension with it, and doing it wrong (forking every value between a constexpr default and a mutable copy) would undermine the discipline.

**Decision -- a runtime OVERLAY, not a replacement.** `src/core/params.h` defines a `ParamSet`: `value[PARAM_COUNT]` initialised from `PARAM_TABLE`, `locked[PARAM_COUNT]` (`CANON` locked by default, everything else unlocked), and a **sticky** `non_canon_run` bool. It does not replace the `constexpr` canon — the sim still reads `canon::` by default; the overlay is what the inspector edits and (from M11d) the sim reads *overridden* values from, for the curated tunable set. Generated canon stays the source of truth and the default; the overlay is a deliberate, flagged departure from it.

**The flag is set on UNLOCK, not on change, and is sticky.** Touching a canon lock flags the run non-canon even if you then change nothing, or change the value back. `ui/MODULE.md` states the worst failure the inspector can have is a run that quietly changed a canon number and still looks canon; a conservative, irreversible-for-the-session flag is the honest guard. Only `CANON` params are locked, so unlocking any of them is the non-canon event; non-canon params (`INVENTED`/`REAL`/`DERIVED`) are freely tunable and never trip it.

**Consequences / the gate.** `test_param_locks`: `CANON` locked by default, breaking a lock sets `non_canon_run` (sticky), the overlay's values equal `PARAM_TABLE`. The flag flows `World.non_canon_run` → `world_stats` → `Stats.non_canon_run` → the HUD and every CSV export header (`headless --csv`). **M11d** wires the UI toggles and makes the sim read overridden values for a curated set via `World` fields; the full `constexpr`→runtime refactor of *every* use site is deliberately NOT done — it would thread a `ParamSet` through every kernel signature for little gain, and no scenario overrides a param today. `param_overrides` (parsed since M11a, ADR-031 §3) apply through this overlay when M11d lands.

---

## ADR-033 — The spin-drive flash: stimulated full-rate discharge, accounted not applied

**Status:** accepted, 2026-08-03 (M11b).

**Context.** `spin-drive-face` needs the flash of `PHYSICS.md` Sec 6 -- "an external high-intensity pulse at `PETROVA_WAVELENGTH` forces full-rate discharge" -- which M11a did not have. It is the one piece of genuinely new physics in M11.

**Decision.** A `flash` stimulus arms `World::flash_active`; while set, `flash_step` (tick stage 9b, `src/sim/flash.cu`) overrides taxis emission: every awake charged cell discharges its store at `PETROVA_FLASH_POWER` (new INVENTED canon, 3 MW -- canon gives no discharge rate, so it is chosen to empty a full cell in ~0.5 s), `dE/dt = -power`, clamped to the store. The discharged energy and the net recoil impulse accumulate into a fixed-point `d_flash_accum` (INV-2), and `impulse_per_cycle = |impulse| * C_LIGHT / discharged` -- a photon-momentum identity (F = P/c).

**The recoil is accounted, not applied to the free cell.** A full cell holds 16.7 ng of mass-energy; discharged as photons it would recoil a lone 10 um cell at ~c (terminal velocity ~1e5 m/s), flinging it out of the chamber. But the cell is fixed to the drive face -- the recoil drives the *ship*, not the free cell -- so `emit_power` stays 0 (no OU thrust) and the impulse is booked for the HUD. Every cell discharges along +z, so the recoils add coherently along -z, which is the point of a spin drive.

**Consequences / the gate.** `impulse_per_cycle ~= 1` (+-1 %), `total_energy_j ~= 0` (no cell retains its store), `boil == 0`. The identity is definitional in the kernel, so the gate's real content is that the flash *fires and fully discharges* while conserving momentum-energy -- the honest check meta-lesson 1 asks for. No determinism impact on any earlier gate: `flash_active` defaults false, so `world_step` is bit-identical to M11a unless a scenario arms it.

---

## ADR-031 — The scenario spine: hand-rolled JSON, loader in sim, and the M11 split

**Status:** accepted, 2026-08-02 (M11a).

**Context.** M11 (Content) was a stub: `contracts/scenario_v1.h` (the `Scenario` struct) was frozen but nothing loaded, instantiated, or evaluated it. M11a builds the spine and had to settle four things.

1. **JSON is hand-rolled, not a dependency.** The scenario schema is fixed and small, so a ~200-line recursive-descent reader (`src/sim/json.h`, jsonc — it skips `//` and `/* */` comments) buys us out of a new dependency and its ADR (Iron Rule 8). It is permissive on input and strict at exactly one point: an unknown `accept` metric is rejected, because a silently-dropped objective is worse than a load failure.

2. **The loader lives in `sim`, not `app`/`tools`.** `scenario_instantiate` builds a `World` — a sim object, exactly as `snapshot.cpp` restores one — and both the headless runner (`tools/`) and the app (`src/app/`) link `sim` but not each other. Putting it in `app` would have hidden it from `headless`, which the T24 gate drives. It is host C++ (a `.cpp`, the first in `astro_sim`), compiling under MSVC like `headless.cpp` does with the same sim headers.

3. **`scope` and `param_overrides` are parsed but not applied (yet).** `scope` is render-only — headless has nothing to point. `param_overrides` cannot be applied at all until a **runtime-parameter system** exists: canon is `constexpr`, so overriding `PETROVA_MAX_POWER` at load time is not expressible today. That system is M11c's (it is the same machinery the parameter inspector and the canon lock need). Both fields are parsed into the struct so the app and a later milestone consume them without a re-parse.

4. **M11 splits into M11a / M11b / M11c** (Iron Rule 9). Every scenario's `accept` block needs either **driving** (first-light's heat, taumoeba's N₂ ramp — the schema has `tools` availability but no scripted *events*) or a **derived metric** (velocities, correlations, doubling-time, impulse) computed from full state. Both belong with M11b, alongside the spin-drive-flash physics. So **M11a is load + instantiate + run**, gated on `test_scenario` (all eight load and instantiate into a `World` bit-reproducibly, populations matching the spec); **M11b** adds acceptance + driving + derived metrics + the flash and drives every scenario's `accept` to green (T24); **M11c** is the inspector/lock/CSV UI.

**Consequences.** No contract change — `Scenario`, `ScopeState`, `ParamOverride`, `AcceptCheck`, `Metric` all pre-existed. The scenarios load by absolute path (`ASTRO_SCENARIOS_DIR`, a compile define) so ctest and headless find them without a working-directory assumption; a relocatable path is M12's packaging concern. `test_scenario` re-airs INV-8 for scenario-built worlds: same scenario ⇒ same hash, a different scenario diverges.

---

## ADR-030 — Evolution: dry biomass, a derived hazard, and the Taumoeba-82.5 arc as pure selection

**Status:** accepted, 2026-08-02 (M10b).

**Context.** M10a gave the Taumoeba a store, a crawl, and engulfment. M10b makes it **evolve**: `PHYSICS.md` §11's N₂ lethality, heritable tolerance, and division, whose gate demands the **Taumoeba-82.5** strain emerge by *directional selection*, never by script. Three model choices had to be settled, each with a trap.

### 1. The division biomass is DRY biomass, not the water-blob mass

`PHYSICS.md` §11 says "divide at 2× initial biomass," and M10a initialised the Taumoeba `biomass` field to `TAU_MASS` — the full water-density mass of a 40 μm blob (3.345e-11 kg). But a Taumoeba eats 10 μm cells whose *dry* biomass is `CELL_MASS_DRY` = 2.1e-14 kg, 1593× lighter. Doubling the **water mass** would take ~2655 prey per division, and no evolution arc could run in any finite test.

This is **meta-lesson 9 (match the units to the source)** in a new guise: `biomass` (water mass) and the prey it banks (dry mass) were different currencies. A 40 μm amoeba is *mostly water*, exactly as a cell is — so, as `CELL_MASS_DRY` is to a cell's total mass, `TAU_MASS_DRY` (INVENTED, 1e-13 kg) is the Taumoeba's **dry/organic biomass**, and `TAU_MASS` sets only its drag/inertia. The `biomass` field now initialises to `TAU_MASS_DRY`, division fires at `TAU_DIVIDE_BIOMASS` = 2× that (DERIVED, faithful to "2× initial biomass"), reachable in ~8 prey. The integrator already used the `TAU_MASS` *constant*, never the field, so this is a pure biomass-semantics change; M10a's engulfment is untouched.

### 2. `k` is a modelling choice; the lethality *rate* is derived, not guessed

`hazard = max(0, N_local − TAU_N2_LETHAL_CONC·(1 + tolerance·k))`. `TAU_N2_TOLERANCE_K` = 1 (INVENTED): full tolerance doubles the survivable concentration, so the survival frontier is `tol* = N/N_lethal − 1` and breeding Taumoeba-82.5 needs the ramp to reach 1.825·`N_lethal` — **the target emerges from the ramp, not from a cutoff** (meta-lesson 2). The death probability `1 − exp(−hazard·rate·dt_bio)` uses `TAU_N2_HAZARD_RATE` **DERIVED** = `1/(TAU_N2_LETHAL_CONC·TAU_N2_LETHAL_TIME)` from an interpretable survival time, rather than a bare coefficient. The fictional lethality has no physical derivation, so `TAU_N2_LETHAL_TIME` (2000 s) is honestly INVENTED and **tuned**, and the gate is what validates it: my first value (120 s, "equal to digest time") drove the population **extinct in six rounds** — death outran reproduction before tolerance could climb. Weakening it 17× rescued the population. Recorded because the seductively-clean "equal to digest time" derivation was simply wrong, and only running the arc exposed it (meta-lesson 5).

The death draws **one uniform unconditionally** per alive Taumoeba, survivor and dier alike (ADR-022): drawing only in the death branch would couple the stream to the N₂ history and break determinism.

### 3. Division mirrors mitosis; the store now compacts

Daughter slots come from `cub::DeviceScan::ExclusiveSum` (never atomicAdd), daughter id = `first_id + prefix`, daughter stream = `pcg_split(parent, id)`, biomass split in half, and the **mutation is the daughter's first draw** — `clamp(parent_tol + N(0, TAU_MUTATION_SIGMA), 0, 1)` — so the parent's trajectory never depends on whether it divided (ADR-025). A per-Taumoeba `generation` counter records lineage depth. Death and division churn the store, so it gets the ADR-028 primitive: a stable, prefix-sum, out-of-place `taumoeba_store_compact`, opt-in via `MotionConfig::tau_compaction_enabled`, default off so M10a is bit-preserved. Reordering the Taumoeba SoA is determinism-safe because engulf claims key on predator *id*, not slot.

**Consequences / the gate.** `test_evolution` (T31–T33): the dividing/dying/compacting store is bit-reproducible (T31, a third airing of T22's argument); under a slow N₂ ramp the mean tolerance rises monotonically on a 5-round moving average and **Taumoeba-82.5 appears at lineage generation 36** — within the 40-generation budget — while the population is decimated by selection (2748 → 119) and then *recovers* once the tolerant strain stops dying (T32); and a **constant-N₂ control** plateaus at max tolerance 0.17, proving the rise is the rising ramp's directional selection and not mutation drift or the [0,1]-clamp (T33, meta-lesson 4). Nothing special-cases 0.825: high N₂ kills the intolerant, survivors divide and pass on mutated tolerance, the frontier climbs, the population tracks it. No contract change — `Stats.mean_tau_tolerance` and `n_taumoeba` were already declared.

---

## ADR-029 — The two IR view modes, implemented without a contract bump

**Status:** accepted, 2026-08-02 (M7b).

**Context.** Petrovascope and Thermal IR were plumbed but never drawn — deferred from
M7 as the "M7b" slot. The fragment shader distinguished only Brightfield; Darkfield,
Petrovascope, and Thermal IR all fell through to an Analysis-style ramp tinted by
**charge**, which for an uncharged culture is near-black on a dark background. Selecting
Thermal IR therefore showed a black screen — a mode that silently does nothing, which
`ui/MODULE.md` calls out as worse than one labelled pending. Surfaced by a user report.

**Decision.** Implement Darkfield, Petrovascope, and Thermal IR distinctly in the
fragment shader, each with its own background, and **without bumping `render_view_v2.h`**:

- **Petrovascope** (novel-faithful): glows by `emit_power_norm` (already in the instance)
  through the petrova-film magenta LUT; a non-emitting cell is invisible. This is the
  novel's instrument — Astrophage "emits where no eye can see", so you see only what is
  emitting.
- **Thermal IR** (2026-film-faithful): the warm medium is false-coloured pink/red and the
  albedo-0 cells are **black absorbing silhouettes** on it — the film's IR look, *not* a
  glowing thermogram. This is an *absorption* view: a cell absorbs at every wavelength, so
  under IR illumination it is dark. An awake cell is a heat *source* (its surface is at the
  369.565 K setpoint by definition, the latch ADR-003), so it takes a hot rim; a dormant or
  dead cell is just black. The `AWAKE` flag, already in `flags_packed`, carries that with no
  `temp_cell`. Being an illuminated view, it also gets the circular field diaphragm that
  Brightfield gets.
- **Darkfield** shows the cells as bright edge-scatter on black.

**The two IR modes are the novel-vs-film split, shipped both ways.** The novel's
Petrovascope detects *emission*; the film's IR is an *absorption* image. They are genuinely
different physics, so — as with ADR-002, ADR-003, ADR-023 — both ship rather than one being
silently chosen. That they must **read differently** (RENDERING.md §4) is now a
**must-differ golden pair** (`m7b_thermal_awake` vs `m7b_petrova_awake`): the same awake,
half-charged (so it does not instantly starve), idle (so it is not emitting) cell is a
visible dark absorber with a hot rim in Thermal and invisible in the Petrovascope. A
`render_view_v3` with per-cell `temp_cell` buys nothing for this contrast, since the awake
latch is exact for it.

**What is deliberately deferred.** Bloom over the Petrova emission (the swirling-points
look) is still M7b-remainder. And a *heated-but-still-dormant* cell warming before it
ignites would need real `temp_cell` in the instance (`render_view_v3`); the awake flag is
exact for awake-vs-dormant but binary, so pre-ignition warm-up does not yet show. Both are
refinements, not the phenomenon.

**Golden safety.** Brightfield (mode 0) is untouched, so every existing `m3_*` and `m8b_*`
measurement golden verifies **unchanged** — the mode work cannot move an optics oracle,
the same guarantee ADR-023 established for morphology. Only the three new `m7b_*` captures
are added (Iron Rule 10: this entry is their record).

---

## ADR-028 — Compaction: stable, prefix-sum, out-of-place, opt-in — and CUB for Q20

**Status:** accepted, 2026-08-02 (M9c).

**Context.** Allocation has been append-only since M9a (ADR-025). Death only clears
`ALIVE`; corpses keep their slots, and cells culled at an absorbing wall
(`integrator.cu`) become corpses too. Nothing has ever reclaimed a slot, so the live
count and the iteration bound `count` diverge over a long run: every kernel then wastes
threads on dead slots, and the store marches toward `MAX_CELLS` while the living
population may be small. M9c owns the reclamation that M9a and M9b each deferred.

**Decision.** A **stable, prefix-sum, out-of-place stream compaction**, opt-in via
`MotionConfig::compaction_enabled` (default **off**, so an untouched run is bit-identical
to M9b). When on, `lifecycle_step` — after division — packs the survivors
(`OCCUPIED && ALIVE`) into `[0, live)` and sets `count = live`.

Three properties make it safe, and each is load-bearing:

1. **The map is a pure function of the population, never of execution order.** The new
   slot of survivor `i` is the exclusive prefix sum of the keep-flags at `i`
   (`cub::DeviceScan::ExclusiveSum`). This is INV-2 one level up, exactly as daughter
   slots are (ADR-025): it is the *allocation* that must be order-free, not just the
   arithmetic. An `atomicAdd`-allocated compaction would reorder within-bucket contact
   summation and drift the hash run to run — ADR-018's hazard, which is the whole reason
   compaction was kept out of M9a/M9b.
2. **It is stable.** Survivors keep their relative order, so the spatial hash's stable
   radix sort produces the same within-bucket order it would have without the removed
   corpses, and per-thread contact force sums stay reproducible.
3. **It is out-of-place.** A parallel in-place compaction is a read/write race — thread
   `i` writing slot `prefix[i] <= i` can clobber a source slot another thread has not yet
   read. Survivors are gathered into a scratch buffer, then copied back, one SoA array at
   a time, reusing a single `capacity`-sized scratch across all arrays.

**Q20 falls out of the same primitive.** The serial `scan_kernel<<<1,1>>>` that computes
the daughter birth prefix — a single-threaded loop over the whole population — is
replaced by `cub::DeviceScan::ExclusiveSum`, which compaction needs anyway. CUB is
already an allowed dependency (the hash uses `SortPairs`, ADR-018). The exclusive-sum
values are identical, so the daughter slots and therefore T22's hash are unchanged.

**What compaction reclaims, and the tradeoff.** Corpses are removed. Under `void`/`flash`
their store is already gone; under `retain` they were inert ballast raining to the
coverslip. Keeping every corpse forever and reusing its slot are mutually exclusive, so
the toggle is the honest resolution: **leave compaction off to study a graveyard; turn it
on for unbounded growth or throughput.** The HUD reports which.

**Gate.** M9b's T22 re-run with `compaction_enabled` **and** absorbing walls (so deaths
actually occur) is bit-reproducible, and `count` collapses from its peak to the live
population. A different seed still diverges. `headless --compaction --absorbing
--assert-deterministic` carries the same check into the continuous audit.

**Deferred, on purpose.** A free-list that lets *daughters* reuse corpse slots without a
full compaction pass (no survivor movement at all, so even cheaper) is a further step;
compaction is the general primitive and ships first. Compaction runs only when there is
something to reclaim (a dead-slot count piggybacked on the existing `mark_kernel` D2H),
so a run with no deaths pays nothing beyond that count.

---

## ADR-027 — The multi-rate clock, and Q19: biology_rate does not scale CO₂ diffusion

**Status:** accepted, 2026-08-02 (M9c). Implements ADR-011; resolves Q19.

**Context.** ADR-011 specified two independent clock multipliers and four presets, but at
M9b only `biology_rate` was wired (into `lifecycle`'s `dt_bio`) and `physics_rate` scaled
nothing but the *reported* `world_sim_time` — the physics stages all ran at raw
`DT_PHYSICS`. M9c wires the clock for real, and that forces two questions the earlier
milestones could leave alone.

### physics_rate scales the physics dt — and two things have to move with it

`world_step` now advances every physics stage by `dt = DT_PHYSICS * physics_rate`. Two
couplings make a naive multiply wrong, and both are handled at the source rather than
clamped:

- **Field diffusion substeps are derived from the actual dt, not baked.** Explicit FTCS
  is stable only for `coeff = D*dt_sub/dx^2 <= 0.25`, and the substep count was fixed at
  `grid_create` for a 1 ms tick. `grid_diffuse` and `thermal_step` now compute the count
  from the dt they are handed (`fields::substeps_for_dt`), so a 10x dt runs 10x the
  substeps and stays stable. At `physics_rate == 1` this returns exactly the baked count,
  so the result is bit-identical to M9b.
- **Contact stiffness scales as 1/physics_rate.** An overdamped explicit spring moves
  `k*delta*dt/gamma` per step, so stability caps `k` at `gamma/dt` (ADR-018). Raising dt
  without touching `k` pushes the stability ratio past 1 and, near `physics_rate = 100`,
  past 2 — a divergent spring that *ejects cells from the chamber*, and containment is a
  hard invariant that is never tuned around. So the integrator uses
  `k_eff = CONTACT_STIFFNESS / physics_rate`, holding ADR-018's ratio fixed at every
  rate. The honest cost is softer contact — dense packing overlaps more at high
  `physics_rate` — which is squarely the "bounded, not exact" contact ADR-018 already
  ships. At `physics_rate == 1`, `k_eff == CONTACT_STIFFNESS` exactly.

`biology_rate` continues to scale only the biology dt, now compounding with physics:
`dt_bio = DT_PHYSICS * physics_rate * biology_rate`. At the default `physics_rate = 1`
this is unchanged from M9a, so T18 and T22 are untouched.

### Presets

`INVENTED`, from ADR-011's table, carried in canon so nothing reads a bare literal:

| Preset | physics_rate | biology_rate | What you watch |
|---|---|---|---|
| Realtime | 1 | 1 | Brownian jitter, thrust, honest microscopy |
| Motion | 10 | 1 | sedimentation, taxis, migration |
| Metabolic | 1 | 1e4 | charging, thermal equilibrium, feeding |
| Generational | 0.5 | 1e6 | division, population curves, evolution |

Ranges `physics_rate in [0.1, 100]`, `biology_rate in [1, 1e6]`. The HUD always shows both
multipliers and the elapsed **simulated** time in real units.

### Q19 — biology_rate does NOT scale CO₂ diffusion. Decided.

ADR-011 assumed biology clocks are "local and non-stiff", but CO₂ uptake is an exchange
with a field that diffuses on *physics* time (ADR-025). At `biology_rate = 2e7` a cell
eats 2e4 s of CO₂ per tick while the medium diffuses 1e-3 s worth, so growth goes locally
diffusion-limited long before the medium is globally exhausted.

The decision is to **leave it that way and state it, not to scale the diffusivity.**

- **It is real physics, not a defect.** A culture that metabolises far faster than CO₂ can
  resupply *is* transport-limited. ADR-025 already measured it (25 % consumed at a full
  stall) and T18.3 already compares against a control for exactly this reason. Hiding it
  behind a multiplied diffusivity would make the sim disagree with the transport it
  claims to model — the failure the VERIFICATION oracle exists to prevent.
- **There is already an honest lever.** To move the medium faster, raise `physics_rate`,
  which scales CO₂ diffusion *correctly*, substeps and all. The two-knob design is the
  escape hatch; a hidden third coupling would be the dishonest one.
- **Scaling it is untenable anyway.** Matching diffusion to `biology_rate = 1e6` would
  demand ~1e6x the CO₂ substeps or an unstable field.

The HUD notes "biology outpaces CO₂ transport" whenever `biology_rate > 1`, so growth
that stalls in a dense patch reads as the transport limit it is rather than as a bug.

**Escape hatch.** Both multipliers stay `INVENTED` and tunable across their ADR-011
ranges; a scenario or the sandbox may set any `physics_rate`/`biology_rate` via the
`Custom` preset.

---

## ADR-026 — The stage-11 reduction, and what a lethal bath actually does

**Status:** accepted, 2026-08-02 (M9b).

### Why the reduction is fixed point

Tick stage 11 went unshipped for nine milestones while `contract::Stats` sat fully specified and entirely unfilled. It is now a **64-bit fixed-point** reduction (INV-2), not because a float sum would be inaccurate but because it would be **order-dependent**: the same population would report a different total depending on how the blocks happened to retire, so the HUD's last digits would flicker with occupancy and no two runs would agree on the energy ledger.

Measured (T23): eight reductions of one identical state produce an **identical bit pattern**, and the ledger matches a sorted host-side sum to 1e-9. `atomicMax` on the fixed-point representation is used for the medium's peak temperature — max is associative and commutative over integers too, and temperatures are positive so unsigned ordering matches signed.

**It is not free, so it does not run every tick.** `world_stats` ends in a D2H copy and nothing inside the tick consumes the result, so it is called at HUD rate — which is what `ARCHITECTURE.md` §3.1 always said ("~30 Hz, not every tick").

**Window counters avoid a second device buffer.** Divisions are already known on the host inside `lifecycle_step`, and deaths are differenced against the previous reduction's dead count. A per-tick death counter would have needed either its own allocation or a D2H every tick.

### Two performance regressions the M1.5 benchmark caught, and it was right to

**Neither showed up in any correctness test**, which is exactly what a render benchmark is for.

1. **`world_stats` was called every frame.** It runs the reduction and ends in a *synchronous* D2H, which stalls the pipeline. The fix is what `ARCHITECTURE.md` §3.1 has said all along -- HUD rate, not frame rate -- and the HUD cannot tell the difference.
2. **`scan_kernel` is `<<<1,1>>>`, a serial loop over the whole population, and it ran unconditionally.** At 200k cells that is a 200,000-iteration single-threaded pass *every tick*, to compute a prefix that is almost always all zeros. Divisions are rare -- one per cell per doubling time -- so `mark_kernel` now also accumulates a plain integer **count** (associative, so `atomicAdd` is safe here where an ordered slot assignment would not be), and the scan and divide passes are skipped entirely when it is zero.

Measured: **145.2 → 185.5 fps** at 200k cells, taking the margin over the 144 target from 0.8 % to 29 %. **T22's hash is unchanged**, which is the proof the optimisation is behaviour-preserving rather than merely plausible.

**Q20** — the scan is still single-threaded when divisions *do* occur. A CUB `DeviceScan` is the right answer and CUB is already an allowed dependency; it belongs with M9c's compaction work, which needs the same primitive.

### The store disposition is now observable

ADR-004's three readings are distinguishable rather than nominal (T23.3): under `void` a corpse falls to `CELL_DENSITY_DRY` = **40.1 kg/m³** and *rises*, and under `retain` it stays at **~25,500 kg/m³** and rains to the coverslip. Both are just `mass = biomass + energy/c²` with the store either gone or kept — no special case anywhere.

`AWAKE` is deliberately **not** cleared on death. The glossary makes alive/dead orthogonal to awake/dormant, and a corpse that *was* awake is a fact about its history. Corpses stop emitting and stop taxis for free, because both stages already gate on `ALIVE`, and the thermostat disengages because `thermal.cu` returns early for dead cells.

### A lethal bath does not sterilise a culture, and that is P2

Dropping 4,000 dormant cells into a **623 K** bath — 50 K above `CELL_LETHAL_TEMP` — kills only **3,411** of them. Every cell ignites instantly (P3), and the awake survivors then drag the medium *down* from 623 K to **601 K**, because the thermostat is bidirectional: at temperatures above the setpoint cells **absorb** heat. Some cells end up in pockets below lethal and live.

This surfaced as a confound — the survivors polluted an energy ledger that a disposition test was reading — and the right response was to isolate the disposition test (thermostat off) **and assert the contest separately** (T23.5) rather than to suppress it. Overheating the slide is a fight the culture partly wins, which is a far better property than a kill switch.

---

## ADR-025 — Division: prefix-sum slots, and two unit bugs in one exchange

**Status:** accepted, 2026-08-02 (M9a).

### Daughter slots come from a prefix sum, never `atomicAdd`

The snapshot hash is taken over the SoA **in slot order**, so if a daughter's slot depended on the order blocks happened to retire, the hash would vary run to run and T22 could never pass. Slots are therefore allocated by an **exclusive prefix sum over the "divides this tick" flags**: the mapping from parent to daughter slot is a pure function of the population, not of execution order.

This is INV-2's reasoning one level up. INV-2 says the *arithmetic* must be associative; here it is the *allocation* that must be order-independent.

Supporting rules, all of which T22 would catch:
- The daughter's `id` is `first_id + prefix[i]` — likewise order-free.
- Its RNG stream is `pcg_split(parent_state, daughter_id)`, depending on nothing but those two (ADR-014).
- Its division axis is hashed from the daughter id, so it consumes **no draw** from either cell's stream. Consuming one would make a parent's later trajectory depend on whether it happened to divide, which is exactly the coupling per-cell streams exist to prevent.

**Allocation is append-only.** Corpses keep their slots, so nothing needs reclaiming until `MAX_CELLS`. Compaction reorders the SoA, which reorders contact-force summation — ADR-018's hazard — and deserves its own determinism argument rather than riding along with mitosis. It is M9b's.

### The uptake rate is derived, not tuned

`LIFE_CO2_UPTAKE_MAX = CO2_MASS_PER_DIVISION / LIFE_DOUBLING_TIME`, so T18 asserts that the implementation reproduces its own definition rather than that a tuned number happens to land. Measured: 4000 → 7986 in one doubling time, a ratio of **1.996**.

`LIFE_CO2_HALF_SATURATION` is `INVENTED`, not `REAL` — informed by measured algal half-saturation constants but describing fictional machinery, the same reasoning as `TAXIS_TUMBLE_ANGLE_MEAN` (ADR-022 §4).

### A per-cell clamp is not enough, and then the units were wrong twice

Uptake drove the CO₂ field to **−0.128 kg/m³**. Two distinct bugs, and the second was hiding behind the first:

1. **Rationing has to be collective.** Clamping each cell to what its grid cell holds still lets N cells sharing that grid cell take N times its contents. Fixed by a two-pass demand/scale: book every cell's demand in fixed point, then take `demand × min(1, available/asked)`. Michaelis-Menten limits the *rate*; this failure is about the *step*.
2. **Demand must be booked in the field's own units.** The first version booked a demand in *kilograms* against `deposit_scale`, which is calibrated for *concentration*. A 6e-16 kg demand rounds to zero in fixed point, so `asked` came back ~0, the ration never triggered, and every cell took its full draw anyway. The field still went negative with the ration in place, which is what made this one hard to see.

**The test was also wrong.** It asserted the *total* CO₂ stayed positive, which negative pockets pass easily by hiding behind positive ones elsewhere. It now asserts the **minimum**. A gate that passes while the thing it guards is broken is worse than no gate.

### Q19 — biology_rate decouples uptake from diffusion

ADR-011 scales biology clocks and leaves physics alone, on the grounds that biology is "local and non-stiff". **CO₂ uptake is not purely local**: it is an exchange with a field that diffuses on *physics* time. At `biology_rate` = 2e7 a cell consumes 2×10⁴ s worth of CO₂ per tick while the medium diffuses 10⁻³ s worth, so a cell strips its own grid cell and then waits on resupply.

Consequences, both measured: growth becomes locally diffusion-limited long before the medium is globally exhausted (25 % consumed at a full stall), and even a *saturating* control slows once it is dense. It is why T18.3 compares against a control rather than asserting "growth proceeds then halts" — that shape is not constructible at a high biology rate.

T18's one-doubling claim is unaffected and exact. But M9b owns the clock presets and should decide whether high `biology_rate` presets need CO₂ diffusion scaled alongside, or whether this limitation is simply documented in the HUD. Do not treat the slowdown as a growth bug; it is the clock.

---

## ADR-024 — The taxis memory window, and a diagnosis that was half wrong

**Status:** accepted, 2026-08-02. Resolves Q16, and replaces it with a better-posed Q18.

**Context.** M8 shipped with `TAXIS_MEMORY_TIME` = 2 s and a diagnostic showing 54 % of cells reorienting within two ticks. The window was indefensible on its own terms: an **awake** cell swims at 6105 μm/s and crosses the whole 4 mm chamber in **0.655 s**, so a 2 s memory is **3.05 chamber crossings**. No gradient can be larger than the chamber, so the cell was comparing against a baseline older than any structure it could possibly be climbing.

**Decision.** `TAXIS_MEMORY_TIME` 2.0 → **0.1 s**, and the criterion is now *derived and asserted* rather than left as advice:

- `TAXIS_SWIM_SPEED` = `PETROVA_MAX_POWER / (c · DRAG_COEFF_SETPOINT)`. Carried explicitly because its absence caused a **3.46× error** at M8 — the first estimate used the 20 °C drag, forgetting that P4 applies to thrust exactly as it does to Brownian motion.
- `TAXIS_CHAMBER_TRAVERSAL` = `CHAMBER_W / TAXIS_SWIM_SPEED` = 0.655 s.
- `TAXIS_MEMORY_CHAMBER_RATIO` = the quotient, **asserted below 0.5 in `test_taxis`**. It was 3.05; it is now 0.153.

The assertion matters because this failure is invisible by inspection: it looks like a working controller with a weak bias, not like a bug.

**Result.** Migration improved from **20.3σ to 26.0σ**, a 28 % larger mean displacement on the identical scenario and seed.

### The prediction that was wrong, recorded because the reasoning was seductive

I expected the retune to *reduce* the tumble rate. **It increased it** — 54 % → 69 % of cells reorienting within two ticks.

The mechanism is the opposite of what I assumed. A *shorter* memory makes the EMA track the signal more closely, so `Δ = signal − ema` is *smaller* and crosses zero more often. A longer memory produces a larger, more persistent Δ. I had attributed the tumble rate to the memory mismatch; it is actually set by the **tumble rule**, which fires whenever `Δ ≤ 0` on any tick with no refractory period. The two are independent, and only one of them was the memory window's fault.

That the migration improved *while* the tumble rate rose is the tell: frequent reorientation with a correct sign is tighter gradient following, not jitter. The tumble rate was never the defect — it was a symptom I misread as one.

**Consequence — Q18, better posed than Q16 was.** With no refractory period the motion is a biased random walk that decorrelates every millisecond, not run-and-tumble: only **3.6 %** of cells are on a run that has outlasted one comparison window. Real reorientation takes time. The fix is a rate-based tumble (Poisson with an intensity modulated by Δ) rather than a per-tick threshold. A hard floor at `TAXIS_TUMBLE_SLEW_TIME` = 1.19 s is *not* the fix and would break the milestone: at 6105 μm/s that commits a cell to 7.3 mm of travel in a 4 mm chamber. Needs its own ADR, and it is entangled with Q15 (no commanded-heading field) and ADR-005 (why 50 mW makes cells this fast relative to the chamber).

**Escape hatch.** `TAXIS_MEMORY_TIME` stays `INVENTED` and tunable, with its range widened to (0.005, 60). The ratio assertion, not the value, is what must hold.

---

## ADR-023 — Cell morphology: irregular by default, and provably unable to move a measurement

**Status:** accepted, 2026-08-02 (M8b). Supersedes `render_view_v1.h` with `render_view_v2.h`.

**Context.** Cells rendered as perfect circles — `RENDERING.md` §2 said so outright. Reference photography of Astrophage under a lab scope shows irregular, faceted grains, each one different. Circles read as *notation*; irregular silhouettes read as *organisms*, and this is a visualisation as much as a simulator.

The novel describes small black spheres. That is a source contradiction of the kind this file exists to adjudicate, and the house answer (ADR-002, ADR-003) is to ship both readings rather than silently pick one.

**Decision.** A `Morphology` setting: `Sphere` (novel-faithful) or `Irregular` (reference-faithful, the application default). The silhouette is a sum of radial harmonics k = 3..8 with amplitudes falling as 1/k, phased from a per-cell seed.

### The invariant that makes this safe

**Morphology is appearance only, and it is now provable rather than promised.** The physics body remains a sphere of `CELL_RADIUS` everywhere in `sim/`. Two mechanisms enforce it:

- **Every measurement golden pins `--morphology sphere --aperture 0`.** After this change all eight M3 captures verify against the pre-existing goldens at **mean difference 0.0000** — the optics oracle measures exactly what it measured at M3. A ninth capture on `--morphology irregular` is a must-differ pair against `m3_working_focus0`, so if the shader mirror of `morphology.h` ever dies silently, the suite says so.
- `sim/` cannot see morphology at all; A5 already grep-gates presentation code out of `sim/` and `fields/`.

### Area preservation is the load-bearing property

An irregular cell stands for a sphere and must absorb **exactly** as much light as that sphere, or the renderer stops agreeing with the physics that computed the charge. For `r(t) = a(1 + w·Σ A_k cos(kt + φ_k))` the enclosed area is `π a² (1 + ½ w² Σ A_k²)`, so the radius is divided by `sqrt(1 + ½ w² Σ A_k²)`. Measured worst-case error over 200 seeds × 11 blur weights: **1.6 × 10⁻¹⁴** — machine precision, not a tolerance.

`w` is how much silhouette survives the optics, `a / r_eff`: 1 in focus, → 0 under heavy defocus. Blur genuinely destroys shape detail, so a badly defocused cell *should* image as a featureless disc. The normalisation carries the same `w`, or the area drifts back off as the cell defocuses.

### The trap, recorded because it cost a render cycle

**Do not ruffle the rim by modulating the edge softness per angle.** It is the obvious way to get the reference's frilled skirt and it is wrong: a radially-varying *falloff distance* renders as radial spokes, and cells come out as **starbursts**. The first implementation did exactly this and looked like a field of snowflakes. Crinkle belongs in `shape_radius`, where it perturbs where the outline is, not how fast it fades.

### Consequences

- **`render_view_v2.h`.** `CellInstance` gains `shape_seed` and grows 32 → 36 bytes (200k cells: 6.4 → 7.2 MB, immaterial). Nothing already in the struct was usable: position, charge, flags and the emission axis all vary over a cell's life. The seed is hashed from the cell's **monotonic id, never its slot** — a slot-derived seed would reshape every cell the instant M9's compaction moves it, the same class of mistake INV-1 forbids for the RNG. `scenario_v1.h` now includes v2 purely because v1 and v2 declare the same names in the same namespace and no translation unit may see both.
- **Q8 landed with it, and had to.** Irregular silhouettes need a slightly larger bounding quad, and defocus fill rate was already the first budget crisis (`RENDERING.md` §7). Cells whose peak opacity cannot clear the fragment discard threshold now degenerate their quad in the vertex stage. It is exactly equivalent — such a cell's Becke ring is also zero, so nothing was being drawn — which the byte-identical goldens confirm.
- **The field diaphragm** is a separate small win in `post_pass.cpp`: a real iris in the illumination path, and the reason every photograph down a microscope is a bright disc on black rather than a full rectangle.
- **ADR-017 got worse before it gets better.** `shape_radius` is now the fifth formula duplicated across the GLSL boundary with no compiler check. Q7's trigger has been met: the next consumer should **generate the GLSL from the header** rather than hand-keeping a sixth copy.

### What was deliberately not done

Lateral chromatic aberration and procedural medium texture, both specified in `RENDERING.md` §8 and both carrying honesty caveats — aberration displaces pixels and must never reach a measurement golden, and a debris speck that could be miscounted as a cell is a bug in a simulator whose purpose is counting cells. Faceting is a refinement: the current outlines are lobed rather than angular. **Clumping remains physics** — cell–cell adhesion does not exist, and faking clusters in the shader would be the special-casing `ARCHITECTURE.md` §1 forbids.

---

## ADR-022 — Taxis: what the controller climbs, and four things canon does not pin down

**Status:** accepted, 2026-08-02 (M8).

**Context.** `PHYSICS.md` §8 specifies run-and-tumble with temporal comparison (ADR-007) but leaves four things open, and M8 could not be written without settling them. Each is recorded here with its reasoning so none is re-litigated.

### 1. The BREED signal is far-field, and must stay far-field

Unlike temperature (ADR-020) and irradiance (ADR-021), where the claim was about an *individual body's own near field*, "follow the CO₂ lines to find breeding grounds" is a **region-scale** claim. The grid is the right instrument, and `co2_local`'s bilinear sample is the right sample.

M9 adds CO₂ uptake and with it a self-depletion halo — the same trap in new clothing. Two things already guard it, and both must survive M9:

- **Tick order.** Taxis is stage 3; the cell's own deposit lands at stage 7. A cell never samples its own contribution from the same tick.
- **Temporal comparison is blind to a constant self-offset.** A cell's own halo is roughly constant in its own frame, so it largely cancels in `signal_now − ema`. This is a real advantage of ADR-007 over spatial differencing, which would see the halo as a gradient pointing *away* from itself.

The residual failure mode is a cell **outrunning** its own halo: it then sees a rising signal in every direction and never tumbles. `TAXIS_RUN_MAX` forecloses it, which is why that cap is not decoration and must not be removed for looking arbitrary.

### 2. Feed additionally requires light — a documented deviation from §8

§8's literal pseudocode lets a dim, low-charge cell enter FEED whenever any CO₂ is present. That cell would burn store climbing an irradiance gradient that does not exist, and it contradicts canon's "does not move in darkness". FEED is gated on `!dark`. A charged cell in the dark can still BREED, since CO₂ is smelled, not seen.

### 3. No CO₂-availability constant was invented

The field is zero everywhere until something adds to it, and a temporal comparison on an identically-zero signal is identically zero, which yields IDLE anyway. So `co2 > 0` is the whole test. Canon is silent on a concentration cutoff and inventing one would have put a number with no provenance into the state machine — the failure mode of every invented cutoff in this build so far.

### 4. Provenance of the two new constants

- `TAXIS_TUMBLE_ANGLE_MEAN` = 68° is **INVENTED**, not REAL. `REAL` means a real-world *physical* constant. A behavioural measurement of *E. coli* — a different organism with flagella, where Astrophage re-aims by slewing an emission axis — is an invention informed by analogy, and mislabelling it would corrupt a provenance system that ships to the user.
- `TAXIS_RUN_MAX` = 8 s is **DERIVED** = 4 × `TAXIS_MEMORY_TIME`. A run must outlast the comparison window to carry information and must terminate so no cell runs forever. Deriving it means it cannot drift independently of the memory time.

The tumble angle is drawn exponential and **clamped to π**, which lowers the realised mean by 7 % to 63.18°. That clamped value is derived in `derive.py` as `T26_TUMBLE_MEAN_CLAMPED` and asserted directly, rather than asserting the unclamped mean with a tolerance wide enough to hide the difference.

### Consequences, including one that is not free

**Darkness is bit-identical, not merely similar.** The IDLE path draws **no random numbers**. A dark chamber with the controller enabled therefore produces positions identical to the taxis-disabled null, which is what T26.8 asserts. Any future edit that draws from the cell's stream on the IDLE path silently downgrades that assertion to a statistical one.

**Re-aiming is instantaneous at M8, and that is a known limitation (Q15).** Rate-limiting it with `PETROVA_SLEW_RATE` requires storing the *commanded* heading separately from the current axis, and `cell_store_v1.h` has no such field — `dir_*` holds the current axis and the heading is its negation, so a slew toward a target reconstructed from that axis is circular. Doing it properly is a `cell_store_v2.h` change and was out of M8's budget. The direction of the error is worth stating: instantaneous re-aim makes taxis **strictly more effective** than the slewed version, so M8's measured migration is an upper bound and adding the slew will reduce it. `TAXIS_TUMBLE_SLEW_TIME` (1.19 s) is derived and carried so the cost is visible.

**A one-tick CO₂ lag.** Stage 2 (`field_sample`) is fused into `motion_step` with stages 5 and 6, so taxis at stage 3 reads a `co2_local` sampled during the previous tick — 1 ms against a field whose diffusion time across one grid cell is ~0.1 s. Negligible at M8, where the only CO₂ source is a brush. M9 should re-examine whether stage 2 needs splitting out, bearing ADR-018 in mind: unfusing a stage is a correctness change in both directions.

---

## ADR-021 — Occlusion: exact in the near field, statistical in the far field

**Status:** accepted, 2026-08-02 (M7). The third instance of the same structural lesson, and the one that shows it is a pattern rather than a coincidence.

**Context.** P5 claims cells shadow each other *perfectly* — albedo is exactly 0, so a cell directly behind another receives **exactly** zero. The irradiance field is depth-averaged and therefore 2D, where one cell blocks only **16.8 %** of a grid column's face. A depth-averaged grid can never produce an exact zero from a single occluder; that is a three-dimensional fact about two discs.

This is the same shape as ADR-019 (a 2D grid cannot give a 3D 1/r profile) and ADR-020 (the grid is the far field, not the near field). **When a claim is about individual bodies, the grid is the wrong instrument.**

**Decision.** Split it.
- **Near field, exact, per cell.** For each cell, walk its hash neighbourhood and multiply by `1 − shadow_fraction` against every upstream neighbour. `disc_overlap_fraction` returns **exactly 1.0** at zero perpendicular offset and **exactly 0.0** beyond 2a, so a directly-aligned neighbour leaves exactly zero. Range is the 27-bucket walk, ±22 μm.
- **Far field, statistical, on the grid.** Cells stamp their cross-section into an occlusion buffer; an axis-aligned sweep accumulates Beer–Lambert transmittance. Fractional by construction, which is correct for a depth-averaged model.

**Consequences.** T13's "exactly zero" holds for an adjacent pair, which is the regime it describes. A pair 200 μm apart gets 0.832 transmittance — the single-cell far-field extinction, also correct. At population scale P5 shows as a gradient: 8,000 cells lit along +x give a charge-versus-depth correlation of **−0.879** and an 8× ratio between the lit face and the far side.

**Two smaller decisions.**
- **Axis-aligned light only.** A sheared sweep for arbitrary directions makes threads collide on shared cells and would need atomics or a rotated buffer. One thread per line means each thread owns its whole output line — deterministic by construction. Four directions demonstrate P5 completely and the physics is identical.
- **Dark chambers cost nothing.** With no source and no ambient, `emission_step` returns immediately rather than paying for a per-cell 27-bucket walk. Also what canon says: Astrophage does not move in darkness.

**A test-design note.** "Exactly zero" survives one tick and not two hundred: integration drifts a collinear pair apart by ~1e-13 m, which is enough to leave 1e-8 of the incident light. That residual is *correct* — they genuinely are not collinear any more. The exact assertion belongs on the pure function and on an undrifted pair; the drifted case gets a relative bound.

---

## ADR-020 — The grid is the far field; conduct against it at the free-space rate

**Status:** accepted, 2026-08-02 (M6). The hardest bug of the build so far, and worth the write-up.

### The trap

A cell holds 96.415 °C and conducts `Q = 4πka·(T_cell − T_∞)` into the medium. The obvious refinement looks compelling: the temperature *grid* does not sit at `T_∞`, it sits at the near-field value `T_∞ + ΔT·a/dx` = 342 K. So conducting against the grid with the free-space coefficient appears to under-report the flux, and the fix appears to be the **shell conductance** between radius `a` and radius `dx`:

```
G = 4πk / (1/a − 1/R)
```

That is exactly self-consistent on paper — substitute the analytic profile and it returns precisely `4πka·ΔT`. It is also completely wrong here, and it produced a **1.76 × 10⁶ K** runaway.

### Why it fails

The premise is that the grid cell holds the near-field temperature. It cannot. A grid cell's thermal time constant is `dx²/(4α)` = **1.06e-4 s**, which is *equal to the diffusion substep* — so diffusion drains the cell as fast as any source fills it, and it sits near the far-field value regardless. Conducting against it at 2.78× the free-space rate then pumps with no feedback at all.

**The grid represents the far field.** The sub-grid 1/r structure is not resolved and must not be double-counted. Conduct at the free-space rate against the grid sample, and the loop closes correctly: measured max **369.56 K** against a setpoint of 369.565, and the medium never approaches boiling.

### Two supporting decisions

**Lumped exponential exchange, not explicit.** One cell deposits ~188 K into a single grid cell per tick, so an explicit step sails past boiling on its own. `C·ΔT·(1 − exp(−G·dt/C))` is the exact solution of the two-body lumped ODE, so the medium *approaches* the cell temperature and cannot overshoot it. That is the second law, not a clamp. Applied per diffusion substep, since a whole tick at once is a source term far too large for one grid cell.

**Nearest-cell sample and deposit for the exchange, not bilinear.** Bilinear spreads a deposit over four cells with weights `w` but reads back only `Σw²` of it — 0.25 at a grid node. A lumped model that assumes the cell it heats reaches its own temperature then sees only a quarter of the feedback. Bilinear remains correct for smooth sources; lumped exchanges need the matched pair.

### P4's viscosity temperature

Three candidates for the temperature setting a live cell's drag, and they differ materially:

| choice | T | motility ratio |
|---|---|---|
| far field (grid) | 342.1 K | 2.87 |
| film mean | 331.4 K | 2.38 |
| **surface (setpoint)** | **369.6 K** | **4.36** |

Only the surface choice reproduces the independently-derived `T12_MOTILITY_RATIO` of 4.357, and it is also the physically right one: Stokes drag is set by the boundary layer at the sphere surface, and an awake cell holds that surface at the setpoint however cold the bulk is.

### A consequence worth knowing

**An ordinary chamber cannot starve a culture.** 500 cells warm their own medium to the setpoint within a second, at which point `Q → 0` and they stop spending — P2 doing its job. Isolating the starvation path in a test needs a perfect cold bath re-imposed every tick, not merely a Dirichlet boundary.

---

## ADR-019 — Two corrections to the M5 field spec

**Status:** accepted, 2026-08-02 (M5).

### 1. Ping-pong buffers, not "red-black"

`MILESTONES.md` §M5 and `PHYSICS.md` §7 both said "explicit red-black". Red-black is a **Gauss-Seidel ordering** — an implicit smoother that reads partially-updated neighbours *on purpose*, which is exactly what makes it converge. An explicit FTCS step must read the **old** value everywhere, so what it needs is a second buffer, not an ordering. A red-black explicit step would be neither scheme and would have no analytic justification.

**Decision.** Explicit FTCS with ping-pong buffers. Measured: FTCS coefficient 0.2347 against the 0.25 stability limit, conservation drift **−0.0001 %** over 10⁴ ticks under an insulated boundary, and no undershoot (an explicit step inside its bound is monotone).

### 2. The grid is 2D, so a point source is logarithmic, not 1/r

The M5 gate asked for "the analytic point-source steady state matching `T(r) = T∞ + ΔT·a/r` in the far field within 2 %". **That is the three-dimensional law**, and the field is depth-averaged over the chamber slab and therefore two-dimensional. A 2D point source relaxes logarithmically. The 1/r profile belongs to **ADR-010's per-cell analytic near field**, which operates on individual cells at M6 and is not a property this grid can or should reproduce.

**Decision.** Replace it with the exact 2D diffusion solution, which is a stronger test anyway because it pins the diffusivity itself rather than just "it spreads": a Gaussian stays Gaussian with variance `σ²(t) = σ₀² + 2·D·t` per axis. Measured over 0.5 s: σ went 100 → 391.5 μm against an analytic 391.5 μm, **error −0.00 %**.

**Consequences.** The gate is one test, not two. `PHYSICS.md` §7 and `MILESTONES.md` §M5 are corrected. Do not reintroduce a 1/r expectation for the grid at M6 — the near-field correction adds 1/r *per cell at sample time*, on top of a grid that is correctly logarithmic in the far field.

### 3. Boundary conditions, measured

| BC | uniform 350 K over 20 s, ambient 300 K | reading |
|---|---|---|
| Neumann | 350.000 | insulated; nothing escapes, exactly |
| Dirichlet | 301.03 | edge pinned to ambient; drains fast |
| Robin | 347.57 | convective; `dx·h/k` ≈ 5e-4, so a chamber edge is nearly insulating |

Robin being close to Neumann at this resolution is physically right, not a bug: a 31 μm cell of water loses very little to room air across its face.

---

## ADR-018 — Three constraints the spatial hash and contact had to satisfy

**Status:** accepted, 2026-08-02 (M4). Three findings, all determinism- or stability-driven.

### 1. The hash is built by a stable radix sort, not an atomicAdd counting scatter

**Context.** The textbook counting sort scatters with `slot = atomicAdd(&cursor[key], 1)`. That makes the order *within* a bucket depend on which thread wins a race. That order then sets the summation order of contact forces, and float addition is not associative — so INV-8 would break on every run, intermittently and invisibly.
**Decision.** `cub::DeviceRadixSort::SortPairs`, which is stable, so equal keys keep their input (slot) order. Bucket ranges then come from adjacent-key comparison, which also removes the need for a prefix scan. CUB ships with the CUDA Toolkit, so this adds no dependency beyond one already allowed.
**Consequences.** Neighbour iteration order is fixed, so a per-thread force sum is reproducible without fixed-point accumulation. Measured: 0.110 ms to rebuild at 200,000 cells, and the neighbour query matches an O(n²) brute-force reference exactly.

### 2. Forces and integrate must be separate kernels

**Context.** M2 fused tick stages 5 and 6 because they share `mass`, `gamma`, and the OU coefficients. Adding contact broke that: contact reads neighbours' positions from the same arrays the kernel writes, so cell *i* sees some neighbours pre-step and some post-step depending on scheduling.
**Measured before the split: 2709 of 3000 positions differed between two identical runs.**
**Decision.** Split them, with a `d_fx/fy/fz` scratch buffer between. `ARCHITECTURE.md` §3.4 already listed forces and integrate as separate stages — **this is exactly why**, and fusing them was the error. Cost: 4.8 MB and one extra kernel launch.
**Lesson worth keeping:** the documented stage boundaries are load-bearing. Fusing across one is a correctness change, not an optimisation.

### 3. Contact stiffness is stability-limited, and cannot hold a fully charged cell

**Context.** `CONTACT_STIFFNESS` was 1e-6 N/m, giving a rest overlap of **1587 % of a diameter** under a full cell's weight — cells passing straight through each other.

In an overdamped medium an explicit spring moves `k·δ·dt/γ` per step, so stability requires `k < γ/dt` = 9.44e-5 N/m. But resting a fully charged cell (32× water) within 5 % of a diameter requires `k > 3.18e-4` N/m — **3.36× over the stability limit.** The two constraints are incompatible at `DT_PHYSICS` = 1 ms.

**Decision.** `CONTACT_STIFFNESS = DRAG_COEFF_20C / (8·DT_PHYSICS)` = 1.1802e-5 N/m, a stability ratio of 0.125 (monotone convergence, no ringing). Rest overlap: **4.17 % for an empty cell** (inside the 5 % gate), **134 % for a fully charged one** (outside it).
**Consequences.** A deep pile of fully charged cells interpenetrates. In practice this is bounded — cells spread along a 4 mm wall rather than stacking deeply, and the measured packed-cluster overlap is 0.55 % — so it is recorded and bounded (`test_contact` asserts < 200 % so it cannot silently worsen) rather than papered over.
**The fix, deferred:** contact substepping, or `dt ≤ 0.3 ms`. Worth doing when dense charged cultures actually matter, which is M9 at the earliest.

### 4. What this cost, and the lever

Contact is the dominant per-tick cost: 200k cells run at **0.28× real time** (281 ticks/s). The benchmark also had to be fixed to measure this at all — under the real-time accumulator, slower frames request more substeps, which makes frames slower still, until it pins at the 8-substep cap and reports a feedback equilibrium instead of throughput. `--benchmark` now implies one tick per frame and reports a real-time factor.

**The named lever:** the neighbour walk visits 27 buckets, but the hash cell is 22 μm and the contact range is 10 μm — so a 2×2×2 walk of 8 buckets is sufficient and correct whenever `cell_size ≥ 2 × range`, which holds. That is a ~3.4× reduction and is the first thing to reach for.

### 5. Goldens regenerated (Iron Rule 10 record)

The M3 goldens capture 400 ticks of simulation, and M4 adds a real force to those ticks, so cell positions in the captures legitimately changed. **The optics themselves are untouched** — no shader, uniform, or `optics.h` formula was modified in M4. Regenerated under Iron Rule 10, with this entry as the required justification. The "must differ" pairs still hold, so the optics are still demonstrably doing something.

---

## ADR-017 — Golden images, plus "must differ" pairs to prove they test something

**Status:** accepted, 2026-08-02 (M3).
**Context.** The optics live in GLSL, which no C++ test can call. `test_optics` verifies the *model* in `src/render/optics.h`, but the shader only *mirrors* those formulas — nothing across the GLSL boundary is compiler-checked. Golden images are the guard.

But a golden suite has a well-known failure mode: it proves the renderer is **stable**, not that it **does anything**. A shader that ignored the focal plane entirely would pass a golden suite forever, as long as it did so consistently.

**Decision.** Two halves, both in `scripts/goldens.ps1`.
1. Eight goldens across three objectives and five focal depths, captured with `--no-ui` and `--ticks-per-frame` so they depend only on the renderer and not on the UI layout or the wall clock. Compared by `tools/imgdiff` on three statistics — mean absolute difference, worst single-channel difference, and the fraction of pixels past a threshold — because one number cannot distinguish an imperceptible global shift (usually a benign driver change) from a small region changing completely (the real regression).
2. **"Must differ" pairs.** Specific golden pairs that are asserted *not* to match.

**The sharpest of these is `focus +2` vs `focus −2` at 100×.** Identical `|dz|`, therefore identical blur radius, identical peak opacity, identical everything except the *sign*. If the defocus polarity inversion were dropped, the two images would be byte-identical. So that comparison is a headless test of the Becke-line inversion — a feature otherwise only checkable by eye. Measured: mean difference 9.8/255 across 21.6 % of pixels.

**Consequences.** Rendering is bit-exact on a fixed driver (verified: mean 0.0000, max 0 immediately after generation), so tolerances are set tight enough to catch a 2 μm focus change at 100×. Regenerating goldens requires a `DECISIONS.md` entry in the same commit, per Iron Rule 10.

**Residual risk, accepted.** `optics.h` and the GLSL in `cells_pass.cpp` duplicate the same four formulas and can silently diverge. The goldens catch a divergence only if it changes pixels — which, for these formulas, it always would. Noted in `src/render/MODULE.md`.

---

## ADR-016 — The integrator propagates position and velocity jointly, not velocity alone

**Status:** accepted, 2026-08-02 (M2). **Corrects the scheme originally written in `PHYSICS.md` §3.2.**
**Context.** The spec called for an exact Ornstein–Uhlenbeck update on velocity followed by `r += v·dt`. That is a standard-looking scheme and it is wrong here. When `dt ≫ τ` the velocity decorrelates completely *inside* one step, so the post-step velocity says nothing useful about the displacement across that step. Carrying it over the full `dt` inflates the position variance by `dt·γ/(2·mass)`.

Measured before writing any code:

| | τ | dt/τ | MSD ratio vs. truth | displacement error |
|---|---|---|---|---|
| empty cell | 2.22e-7 s | 4497 | 2248× | **47×** |
| full cell | 1.77e-4 s | 5.65 | 2.83× | 1.7× |

A 47× error in Brownian motion would have been invisible in a screenshot and would have quietly falsified every downstream result that depends on transport — taxis, mixing, encounter rates for predation.

**Decision.** Use the exact joint position–velocity OU propagator (Chandrasekhar 1943; Ermak & Buckholz 1980), with the correlated 2×2 noise given in `PHYSICS.md` §3.2. Verified: as `dt/τ → ∞` the position variance reduces to `2·D·dt` to four significant figures.
**Consequences.** Six gaussian variates per cell per tick instead of three, and a Cholesky factor per axis — a few dozen extra flops, entirely affordable. The `2x − 3 + 4E − E²` term needs a series expansion below `x ≈ 1e-2` or catastrophic cancellation silently returns zero diffusion; `test_motion` pins both branches and the crossover between them.
**Why it was caught.** `docs/VERIFICATION.md` states the Einstein diffusivity independently of the simulator, so the scheme could be checked against it arithmetically before a line of it was written. That is the entire purpose of the oracle.

---

## ADR-015 — Projected coverage, not volume fraction, sets the default population

**Status:** accepted, 2026-08-02 (M1).
**Context.** `DEFAULT_CELLS` was initially set to 200,000, the same number as the performance target. That is only ~11 % of the chamber **by volume** — a reasonable culture — but the scope looks down through the entire 60 μm slab, so every cell in a column overlaps in projection. Projected coverage came out at ~98 %: a solid black field with no distinguishable cells. The render was correct; the default was unusable.
**Decision.** Separate the two numbers. `DEFAULT_CELLS` = 25,000 (~12 % projected, ~300 cells in a 40× field, reads as a culture). `BENCH_CELLS` = 200,000 stays as the figure the performance gate runs at.
**Consequences.** When reasoning about how a population will *look*, compute `N · π a² / (chamber_w · chamber_h)`, not the volume fraction. The depth of field at M3 will partly relieve this — most cells will be defocused and only a thin layer sharp, which is exactly what a real dense culture looks like — but it does not remove the need for a sane default.
**Escape hatch.** Scenarios set their own populations; `SCENARIOS.md` already ranges from 800 (`first-light`) to 12,000 in a single field (`shadow-garden`).

---

## ADR-014 — Per-cell PCG32 streams, never a global generator

**Status:** accepted.
**Context.** With a single global RNG, adding or removing one cell shifts every subsequent cell's draws, so any run in which a division or death occurs is irreproducible. That is every interesting run. `curand` default sequences have the same problem in a worse form, since they key off thread index.
**Decision.** PCG32 with state stored per cell, seeded `seed_global ^ hash(cell_id)`. Daughters get `pcg_split(parent_state, daughter_id)`.
**Consequences.** Trajectories are invariant to population changes. This is what makes test T22 (bit-reproducibility across a run with divisions) possible. Costs 8 bytes per cell.
