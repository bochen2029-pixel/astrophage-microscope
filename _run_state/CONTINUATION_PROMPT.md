# CONTINUATION PROMPT

**Paste this whole file as the first message of a new session.** It is written to be
self-contained: everything a cold session needs to be productive within one read,
without loading the repo.

---

## What you are picking up

`C:\Astrophage` is the **Astrophage Microscope Simulator** — a physics-based,
GPU-accelerated simulation of Astrophage, the fictional organism from Andy Weir's
*Project Hail Mary*, viewed **through a microscope**. C++20 + CUDA 13.1, OpenGL 4.6
interop, Dear ImGui, CMake/Ninja, targeting `sm_89` on Windows 11.

A sealed 4 mm × 4 mm × 60 μm chamber of water. Cells 10 μm across, black at every
wavelength, each holding up to 1.5 MJ as neutrino mass. Real Stokes drag, Langevin
dynamics, Fickian diffusion, conduction, photon momentum. Public repo:
https://github.com/bochen2029-pixel/astrophage-microscope (MIT).

**Scope is deliberately cell-level and quasi-2D.** No ships, no Petrova arc, no
Tau Ceti, no interstellar view. The single exception is a planned `spin-drive-face`
scenario, which belongs because a spin drive *is* a cell-scale machine and the
microscope is the right instrument for it. Do not let scope creep upward.

---

## Step 1 — orient yourself against reality, not against docs

```bash
git -C C:\Astrophage tag --list
```

**The last `m<N>-green` tag is the ground truth.** Not a doc, not a log, not this
file. If anything here disagrees with the tags, believe the tags and fix the doc.

As of writing: **`m0-green` … `m8-green`**. Eight of twelve milestones done.
**Next up: M9 — Life.**

Then verify the baseline before changing anything:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M8
```

That does a clean rebuild and re-runs every gate M0–M7 plus the golden images. It
takes ~12 minutes. **Run it in the background** and read while it goes.

Then look at the thing:

```bash
build/astrophage.exe
```

Drag to pan the stage, scroll to zoom (cursor-anchored), `Home` to reset. Rack the
**focal plane** slider and watch cells resolve and dissolve. Drag the **charge**
slider past 3.0058 % and the culture reverses direction. `--ticks-per-frame 200`
fast-forwards; the chamber stratifies fully in about two simulated minutes.

---

## Step 2 — read these, in this order, and nothing else

Context discipline is what makes this build converge across many sessions. A
correct session loads roughly 25–50k tokens of documentation and spends the rest
on code. **Never load the whole repo.**

1. **`CLAUDE.md`** — the operating contract. Session ritual, ten Iron Rules,
   module map, code standards, authority boundaries. Always.
2. **`docs/ARCHITECTURE.md`** — module map, invariants INV-1…INV-8, the mandatory
   glossary, the tick sequence, the anti-drift machinery. Always.
3. **`docs/MILESTONES.md` — the active milestone section only.** Not the file.
4. **`docs/DECISIONS.md`** — 21 ADRs. Skim the index; read any ADR a task touches.
   **Every contradiction in the source material has already been adjudicated here,
   with reasoning and an escape hatch.** Re-litigating costs a session.
5. **`docs/PHYSICS.md`** — only if touching `src/sim/` or `src/fields/`, and only
   the relevant section.
6. **`docs/RENDERING.md`** — only if touching `src/render/` or `src/ui/`.
7. **`src/<module>/MODULE.md`** for the module you are in, plus **only the
   `contracts/*.h` it uses.**

**Do not read another module's source to learn its interface.** That is what
`contracts/` exists for. If you find yourself needing to, the contract is wrong —
fix the contract.

`docs/SESSION_LOG.md` holds one entry per milestone with what went wrong and why.
Read the last two entries. It is the most useful file in the repo for avoiding
repeats.

---

## Step 3 — the state, in numbers

**17 tests green, 8 golden images, 10 audit invariant checks.**

```
test_canon ......... generated constants consistent; the right params carry the canon lock
test_rng ........... PCG32 vs published reference vectors, stream independence, moments
test_contracts ..... POD/layout/version guards, FNV-1a, deposit overflow headroom
test_fixed_atomic .. identical sums across 4 block sizes (INV-2, INV-4)
test_octahedral .... direction packing round trip, <0.05 deg worst case
test_cell_store .... spawn placement, INV-1 stream independence, capacity, id monotonicity
test_scope ......... scale bar at 3 objectives across the zoom range, true cell size
test_motion ........ T1-T4, T6, T8 against the oracle; OU branches; boundaries
test_buoyancy ...... T14: drift velocity linear in charge, zero crossing at 3.00577%
test_optics ........ DOF, energy conservation under defocus, polarity, sharp fraction
test_hash .......... neighbour query vs O(n^2) brute force, INV-4, rebuild timing
test_contact ....... pair force, packed cluster, containment, adhesion, determinism
test_fields ........ stability, T25 conservation, 2D Gaussian oracle, BCs, deposits
test_thermal ....... P2 thermostat, P3 latch, P4 motility, T5/T7/T9/T10/T12/T19
test_emission ...... P5 exact + statistical, Komorov T15, band separation T16/T17/T20
test_taxis ......... T26: run-and-tumble, the state machine, the emission ledger,
                     migration at 20.3 sigma, darkness bit-identical to the null
determinism_replay . real World, seed- and population-sensitive (INV-8)
```

### All five signature phenomena are live

These **emerge** from the physics. None is special-cased. **If you find yourself
writing an `if` to make one happen, stop — the model is wrong upstream.**

| | claim | measured |
|---|---|---|
| **P1** | canon mass in a 10 μm sphere ⇒ 40 kg/m³, so an empty cell *rises* at 52 μm/s and a full one (32× water) *sinks* at 1681 μm/s; neutral at 3.006 % charge | drift velocity linear in charge to Pearson **−1.000000**, zero crossing **3.00577 %** |
| **P2** | 96.415 °C is 3.585 K below boiling and heat output → 0 at the setpoint, so a culture pins its medium there and **can never boil it** | 2000 awake cells, 60 s insulated: max **369.56 K** vs setpoint 369.565. Driven to 400 K it relaxes back **while cell energy rises** |
| **P3** | dormant cells are inert powder; crossing the setpoint wakes them **irreversibly** | 2000/2000 wake within 50 ms; still 2000 awake after being chilled to 20 °C |
| **P4** | a live cell holds its *surface* at the setpoint, so viscosity drops 3.4× and mobility rises | motility ratio **4.357**, matching the oracle |
| **P5** | albedo is exactly 0, so shadowing is **total** | adjacent collinear pair: rear cell at **bitwise `0.0`**. 8000 cells: charge-vs-depth **r = −0.879**, 8× lit/far |

### Performance

200k cells at ~281 ticks/s (**0.28× real time**) as of M4; M6 and M7 added stages
on top. The frame rate is comfortably above target; the *real-time factor* is the
number that matters and it is below 1.

---

## Step 4 — the meta-lessons. Read these twice.

These are worth more than any individual fact in the codebase. Each was paid for.

### 1. When a claim is about individual bodies, the grid is the wrong instrument

**This pattern has produced three separate bugs (ADR-019, ADR-020, ADR-021).** The
field grids are depth-averaged, 2D, and represent the **far field**. So:

- A 2D grid **cannot** reproduce a 3D `1/r` point-source profile — it relaxes
  logarithmically (ADR-019).
- A grid cell **cannot** hold the near-field temperature — its thermal time
  constant equals the diffusion substep, so diffusion drains it as fast as a
  source fills it. Conducting against it with a "corrected" shell conductance
  produced a **1.76 × 10⁶ K runaway** (ADR-020).
- A depth-averaged grid **cannot** produce an exact shadow — one cell blocks only
  16.8 % of a grid column's face (ADR-021).

The answer every time: **exact per-cell physics via the spatial hash for the near
field, statistical grid behaviour for the far field.**

**M8 will meet this again.** A cell's own CO₂ uptake will contaminate the grid cell
it samples, exactly as its own heat did in M6. Decide up front whether the taxis
signal is far-field (grid) or near-field (per-cell), and **do not let a cell chase
its own depletion halo.**

### 2. Do not guess a numeric threshold — derive it

Every invented cutoff in this build has been wrong. `r > 4a` failed at the true
3.9a. `peak < 0.06` failed at 0.0617. `CONTACT_STIFFNESS` was off by 1587 %. Size
a test from the physics: run length from `store / conduction rate`, blur from
`dz·NA/n`, stiffness from the stability bound `γ/dt`.

### 3. When a gate fails, first ask whether it asks the right question

**Four times now the failing threshold was the *test's* fault, and each corrected
test came out stricter, not looser.**

- T14's Pearson correlation capped at 0.84 — not from wall saturation (my first
  guess, which Spearman disproved in one run) but because cells near neutral
  buoyancy have near-zero drift and never leave their spawn point. Correct physics.
  Replaced with a velocity test that is immune to initial conditions.
- The M5 gate asked a 2D grid for a 3D law. Replaced with the exact 2D Gaussian
  solution, which pins the diffusivity itself.
- T13's "exactly zero" survives one tick and not two hundred: integration drifts a
  collinear pair apart by ~1e-13 m. That residual is *correct*.
- The starvation test needed a perfect cold bath, because an ordinary chamber
  **cannot** starve a culture — the cells warm their own medium to the setpoint and
  stop spending. That is P2 doing its job.

**Never weaken a gate to pass it** (Iron Rule 1). If a gate seems wrong, fix it
with an ADR.

### 4. The oracle is authoritative

`docs/VERIFICATION.md` is **generated** by `scripts/derive.py` from first
principles, independently of the simulator. **If they disagree, the simulator is
wrong.** It has caught five real errors, including one where the integrator this
project's own spec called for gave **47× too much diffusion** (ADR-016) — caught by
arithmetic before a line of it was written.

### 5. Fusing across a documented tick-stage boundary is a correctness change

Not an optimisation. M2 fused stages 5 and 6 for register reuse; when M4 added
contact, that kernel read neighbour positions the same kernel was writing and
**2709 of 3000 positions differed between two identical runs** (ADR-018). The stage
boundaries in `ARCHITECTURE.md` §3.4 are load-bearing.

### 6. Match the sample to the source

A **lumped** exchange needs `grid_sample_nearest` / `grid_deposit_nearest`.
Bilinear spreads a deposit over four cells but reads back only `Σw²` of it — 0.25
at a grid node — so a lumped model sees a quarter of its feedback. Bilinear is
correct for smooth sources.

### 7. Determinism on a GPU is not free

Three decisions exist purely to buy it, and all three are non-negotiable:

- **Per-cell PCG32 streams** keyed on a stable cell `id`, never a slot or thread
  index. A global generator makes any run with a division irreproducible
  (ADR-014).
- **64-bit fixed-point accumulation** for every field deposit and statistic.
  `atomicAdd(float*)` is order-dependent (ADR-013).
- **A stable radix sort** for the spatial hash. The textbook `atomicAdd` counting
  scatter randomises within-bucket order, which sets contact-force summation
  order, which breaks reproducibility *intermittently* (ADR-018).

---

## Step 5 — the process rules that are actually enforced

- **A milestone is done only when `gate.ps1 -Milestone M<N>` exits 0.** Then
  `git tag m<N>-green`. Every gate re-runs all earlier gates. Gates never weaken.
- **Run `scripts/audit.ps1` before and after each step.** Ten checks: canon
  freshness, warnings-as-errors, ctest, determinism replay, no presentation code
  in `sim`/`fields`, no host RNG, no fast-math, module inventory, **no physical
  literals in `sim`/`fields`**, no render size fudge.
- **No physical literal outside `scripts/canon.py`.** Every constant is generated
  into `src/core/canon_generated.h`. A9 greps three patterns and *will* catch you.
  Maths constants (π) go in `core/units.h`, not canon.
- **`build.ps1 -App`** whenever the executable matters. Without `-App` the core and
  tests build with no network and no dependencies.
- **Regenerating goldens requires a `DECISIONS.md` entry in the same commit**
  (Iron Rule 10). Never edit goldens by hand.
- **Diff budget ≤ 600 LOC** per change unless the milestone authorises more.
- **Spec reconciliation in the same commit** as any contract or boundary change.
- **One milestone per session.** If it will not fit, split it in `MILESTONES.md`
  *before* starting and give each half a gate.
- **End every session** by running the gate, appending a `SESSION_LOG.md` entry,
  tagging if green, and **rewriting `_run_state/NEXT_SESSION.md`**. That last one is
  the most valuable thing you do.

**Ask before:** `git push` to any remote, anything outside `C:\Astrophage\`,
network access beyond dependency fetch, Windows settings, spending money.

---

## Step 6 — what is next

### M9 — Life (the immediate milestone)

`docs/PHYSICS.md` §10 and §12. Biomass, CO₂ uptake, mitosis with energy halving and
RNG splitting, death paths, corpse rendering, the store-disposition toggle (ADR-004),
the multi-rate clock (ADR-011), charts.

**Gate:** M8 gate + T18 (doubling matches `LIFE_DOUBLING_TIME` within 2 % under
non-limiting CO₂); growth halts within one doubling of CO₂ exhaustion; **T22 — a run
in which cells divide is bit-reproducible**, which is the real test of ADR-014.

**Three things M9 inherits from M8, all in ADR-022:**

1. **CO₂ uptake is the depletion halo M8 guarded against in advance.** Two protections
   exist and must survive: taxis samples at stage 3 *before* the cell's own deposit at
   stage 7, and temporal comparison is blind to a roughly-constant self-offset.
   `TAXIS_RUN_MAX` is the backstop for a cell that outruns its own halo — it is not
   decoration.
2. **Stage 2 (`field_sample`) is fused into `motion_step`**, so taxis reads a
   `co2_local` one tick old. Negligible at M8; re-examine when uptake lands. Unfusing
   a stage is a correctness change in *both* directions (ADR-018).
3. **Stage 11 (`stats`) has never shipped.** `world_stats` returns only tick, time and
   counts. M9's charts are its first consumer. Needs a deterministic device reduction
   — tree or fixed-point, **never `atomicAdd` on float** (INV-2).

**Read ADR-022 before touching `src/sim/taxis.*`.** M8 met the grid-vs-per-cell pattern
a fourth time and **decided the other way on purpose**: BREED is a region-scale claim,
so the grid is the right instrument there. That is a decision, not an oversight.

**M8's own known defect, Q16, is written up in `NEXT_SESSION.md` with the numbers** —
`TAXIS_MEMORY_TIME` is 3.1× the time an awake cell takes to cross the whole chamber, so
over half the population reorients every tick. The gate passes at 20σ regardless. The
fix is a constants decision needing its own ADR, not a controller change.

### Then M10 → M12

- **M10 Predation** — Taumoeba, engulfment, N₂ lethality, heritable tolerance.
  The gate wants the **Taumoeba-82.5** strain to emerge by genuine directional
  selection, not by script.
- **M11 Content** — scenario loader, all eight scenarios from `docs/SCENARIOS.md`,
  the parameter inspector with provenance badges and canon locks, the cell
  inspector, charts, CSV telemetry.
- **M12 Ship** — snapshot/replay, performance pass, packaging, v1.0.

---

## Step 7 — deferred work, with reasons

**Recorded rather than glossed. Any of these is a legitimate thing to pick up.**

### M7b — the view modes that did not land

**Bloom and the Petrovascope / Thermal-IR view modes were in M7's scope and are not
done.** The physics gate took the milestone. The enum values and the `u_mode`
uniform are plumbed; `src/render/cells_pass.cpp` currently renders modes 1–4
through the Analysis branch. Spec is `docs/RENDERING.md` §4–§5.

**The constraint that matters:** Thermal IR and Petrovascope must read
*differently*. The Petrova line is a discrete quantum annihilation line at
25.984 μm; the thermal blackbody peak at the setpoint is 7.841 μm — **3.31× apart**.
A live idle cell glows in Thermal and is **dark** in Petrovascope; a discharging
cell blazes in Petrovascope. If the two modes ever collapse into one another, a
real physical distinction has been lost. This is the simulator's best teaching
moment and it is currently missing.

Do it as a standalone M7b, or fold it into M11 with the rest of the UI.

### Performance levers, both untouched

- **Q9 — the best lever available.** The neighbour walk visits **27 buckets when 8
  would do**: the hash cell is 22 μm and the contact/occlusion range is 10 μm, so a
  2×2×2 walk is correct whenever `cell_size ≥ 2 × range`, which holds. ~3.4× on the
  dominant cost — and it is now used by **both** contact and occlusion, so the win
  has doubled since it was first identified.
- **Q8** — defocus is fill rate, not shader complexity. A cell 30 μm out of focus
  covers 64× the area and every fragment is shaded and blended (795 → 426 fps at
  M3). Cull cells whose peak opacity is below the fragment discard threshold, in
  the vertex stage. **Bloom will land on top of this.**

### Open questions

- **Q1** — App `--headless` (hidden window) and `tools/headless` (never links GL)
  stay separate deliberately; merging would drag GL into the determinism oracle.
- **Q5** — When M9 adds slot reuse, confirm `spawn_kernel` clears `vx/vy/vz`. It
  does today, but only incidentally.
- **Q6** — `MotionConfig` flags (`thermal_noise`, `contact_enabled`,
  `adhesion_enabled`, `thermal_enabled`, `emission_enabled`, `occlusion_exact`) are
  test-only. A scenario wanting them needs fields in `contracts/scenario_v1.h`.
- **Q7** — `src/render/optics.h` and the GLSL in `cells_pass.cpp` duplicate four
  formulas with no compiler check between them (ADR-017). If a third consumer
  appears, generate the GLSL from the header rather than adding another copy.
- **Q10** — Contact **cannot** hold a fully charged cell at `dt` = 1 ms: stability
  caps stiffness 3.36× below what rigidity needs (ADR-018 §3). Bounded and tested
  at < 200 % overlap. Needs contact substepping or `dt ≤ 0.3 ms` if M9 produces
  dense charged cultures.
- **Q11** — The SoA is **not** reordered by bucket, contrary to M4's stated scope: a
  determinism hazard for a speculative gain. Revisit only with profiling evidence.
- **Q12** — `shell_conductance` is kept in `thermal.cuh` but **deliberately
  unused**, with its reasoning preserved. Read ADR-020 before reaching for it.
- **Q13** — Light is axis-aligned only (ADR-021). A sheared sweep collides threads
  on shared cells and needs atomics or a rotated buffer. Fine for P5; revisit only
  if a scenario needs oblique illumination.
- **Q14** — Dormant cells **charge**: `feed_kernel` checks `OCCUPIED|ALIVE` only.
  Absorption is not optional (albedo 0), but the consistent alternative is that
  absorbed light *warms* a dormant cell and ignites it at 96.415 °C — light-driven
  ignition, canon-consistent and lovely. New behaviour; needs its own ADR.
- **Q15** — Re-aiming is **instantaneous**; `PETROVA_SLEW_RATE` is unused by taxis.
  Rate-limiting needs the commanded heading stored apart from the current axis, and
  `cell_store_v1.h` has no such field — a v2 bump. Error direction is known:
  instantaneous re-aim makes taxis *strictly more effective*, so M8's 20.3σ is an
  upper bound.
- **Q16 — the taxis controller is mistuned, with numbers.** An awake cell swims at
  6105 μm/s and crosses the whole 4 mm chamber in **0.66 s**, but
  `TAXIS_MEMORY_TIME` is **2 s** — 3.1× a full crossing. Measured consequence:
  **54.2 % of cells reorient within 2 ticks**, mean run age 0.185 s against an 8 s
  cap, bias efficiency 0.4 %. Criterion for the fix: **τ ≲ the e-folding traversal
  time** (~0.3 s here); 0.05 s is already inside the canon range. Touches ADR-005
  and ADR-007, so it needs its own ADR. Resolve with Q15.

### Known flake

`gate.ps1`'s **M0.2** step does a clean reconfigure, which re-fetches
GLFW/GLAD/ImGui over the network. It has failed transiently twice (once as
`ninja: failed recompaction: Permission denied`) while every later gate passed on
the resulting artifacts. If it recurs, make `build.ps1` retry the reconfigure
rather than let a file-lock or network hiccup read as a milestone failure.

---

## Step 8 — what NOT to do

- No interstellar, solar-system, or spacecraft scale. No orbital mechanics. No
  relativistic travel. The `spin-drive-face` scenario is the sole exception and is
  cell-scale by nature.
- No game mechanics or objectives beyond scenario acceptance checks.
- No asset files — everything procedural or generated.
- No web/browser tech. No Vulkan, no D3D, no second windowing framework.
- No `-use_fast_math` in `sim`/`fields` (INV-6).
- No new dependency without an ADR. Current allowed set: CUDA Toolkit (incl. CUB),
  GLFW, GLAD, Dear ImGui.
- No skipping the change manifest. No loading the entire repo into context.
- No forbidden synonyms — the glossary in `ARCHITECTURE.md` §2 is mandatory. It is
  **Cell**, **Chamber**, **Scope**, **Charge**, **Petrova**, **Tick**, never
  particle / world / camera / fuel / IR / frame.

---

## Step 9 — how the repo generates itself

Worth understanding before touching anything, because it is the mechanism that
keeps a dozens-of-sessions build honest.

```
scripts/canon.py ──derive.py──┬──▶ src/core/canon_generated.h     constexpr + provenance table
                              ├──▶ tests/golden/expected_values.h  oracle expectations
                              └──▶ docs/VERIFICATION.md            derivation report
```

**None of the three is hand-written**, so a constant cannot drift between code,
test, and documentation. `audit.ps1` runs `derive.py --check` and fails if any is
stale. Every parameter carries a provenance tag — `CANON`, `DERIVED`, `REAL`,
`INVENTED` — and that tag follows it into the UI. Canon values are locked;
unlocking one flags the run as non-canon in the HUD and in every telemetry export.

The novel contradicts itself twice, materially, and **both readings ship as
playable options** rather than as silent decisions (ADR-002 cell density, ADR-003
dormancy). That honesty is a feature of the product, not just of the docs.

---

## Suggested first message back

State which milestone you are taking, produce the **change manifest** Iron Rule 7
requires (files to touch, contract changes y/n, tests to add, rollback plan, diff
budget), and confirm the M7 gate is green before you change anything.
