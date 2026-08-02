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

## ADR-014 — Per-cell PCG32 streams, never a global generator

**Status:** accepted.
**Context.** With a single global RNG, adding or removing one cell shifts every subsequent cell's draws, so any run in which a division or death occurs is irreproducible. That is every interesting run. `curand` default sequences have the same problem in a worse form, since they key off thread index.
**Decision.** PCG32 with state stored per cell, seeded `seed_global ^ hash(cell_id)`. Daughters get `pcg_split(parent_state, daughter_id)`.
**Consequences.** Trajectories are invariant to population changes. This is what makes test T22 (bit-reproducibility across a run with divisions) possible. Costs 8 bytes per cell.
