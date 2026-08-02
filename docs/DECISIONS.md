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
