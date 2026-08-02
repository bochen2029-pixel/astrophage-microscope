# CONTINUATION PROMPT — Astrophage Microscope Simulator

**Paste this whole file as the first message of a new session.** It is written to be
self-contained: everything a cold session needs to be productive within one read,
without loading the repo.

Last rewritten: 2026-08-02, after **M7b** (M9c then the deferred view modes).

---

## 0. The thirty-second version

`C:\Astrophage` is a physics-based, GPU-accelerated simulation of **Astrophage** —
the fictional organism from Andy Weir's *Project Hail Mary* — seen **through a
microscope**. C++20 + CUDA 13.1, OpenGL 4.6 interop, Dear ImGui, CMake/Ninja,
`sm_89`, Windows 11. Public repo (MIT):
https://github.com/bochen2029-pixel/astrophage-microscope

A sealed 4 mm × 4 mm × 60 μm chamber of water. Cells 10 μm across, black at every
wavelength, each holding up to 1.5 MJ as neutrino mass. Real Stokes drag, Langevin
dynamics, Fickian diffusion, conduction, photon momentum.

**M0 through M9c are green, plus the deferred M7b view modes.** All five signature
phenomena are live; cells behave, look like organisms, divide reproducibly, die,
report telemetry, run on a multi-rate clock with slot compaction, and all five
view modes (Brightfield, Darkfield, Petrovascope, Thermal IR, Analysis) draw
distinctly. **Next up: M10 — Predation** (Taumoeba, N₂ lethality, the
Taumoeba-82.5 evolution arc).

**This is a simulator and visualisation, not a game.** No win state, no story mode,
no asset files — everything procedural or generated.

**Scope is deliberately cell-level and quasi-2D.** No ships, no Petrova arc, no Tau
Ceti, no interstellar view. The single exception is a planned `spin-drive-face`
scenario, which belongs because a spin drive *is* a cell-scale machine and the
microscope is the right instrument for it. Do not let scope creep upward.

---

## 1. Orient against reality, not against docs

```bash
git -C C:\Astrophage tag --list
```

**The last `m<N>-green` tag is ground truth.** Not a doc, not a log, not this file.
If anything here disagrees with the tags, believe the tags and fix the doc.

As of writing: `m0-green` … `m8-green`, `m8b-green`, `m9a-green`, `m9b-green`.

Then verify the baseline **before changing anything**:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M9b
```

That does a clean rebuild and re-runs every gate M0–M9b plus the golden images.
It takes ~12–15 minutes. **Run it in the background** and read while it goes.

Then look at the thing:

```bash
build/astrophage.exe
```

Drag to pan the stage, scroll to zoom (cursor-anchored), `Home` to reset. Rack the
**focal plane** slider and watch cells resolve and dissolve. Drag the **charge**
slider past 3.0058 % and the culture reverses direction. `--ticks-per-frame 200`
fast-forwards.

---

## 2. Read these, in this order, and nothing else

Context discipline is what makes this build converge across many sessions. A
correct session loads roughly 25–50k tokens of documentation and spends the rest
on code. **Never load the whole repo.**

1. **`CLAUDE.md`** — the operating contract. Session ritual, ten Iron Rules, module
   map, code standards, authority boundaries. Always.
2. **`docs/ARCHITECTURE.md`** — module map, invariants INV-1…INV-8, the mandatory
   glossary, the tick sequence, the anti-drift machinery. Always.
3. **`docs/MILESTONES.md` — the active milestone section only.** Not the file.
4. **`docs/DECISIONS.md`** — 26 ADRs. Skim the index; read any ADR a task touches.
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
**Read the last two entries.** It is the most useful file in the repo.

---

## 3. The state, in numbers

**21 tests green, 12 golden images, 10 audit invariant checks, 29 ADRs.**

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
test_taxis ......... T26: run-and-tumble, state machine, emission ledger, migration
                     at 26.0 sigma, darkness bit-identical to the null
test_morphology .... T27: area-preserving silhouettes to 1.6e-14, bounded, distinct
test_lifecycle ..... T18 doubling 1.996, CO2 exhaustion, T22 bit-reproducible division
test_stats ......... T23: reduction bit-identical across 8 runs, energy ledger vs host,
                     death paths, store disposition (void 40 kg/m^3 vs retain 25,500)
determinism_replay . real World, seed- and population-sensitive (INV-8)
```

### All five signature phenomena are live

These **emerge** from the physics. None is special-cased. **If you find yourself
writing an `if` to make one happen, stop — the model is wrong upstream.**

| | claim | measured |
|---|---|---|
| **P1** | canon mass in a 10 μm sphere ⇒ 40 kg/m³, so an empty cell *rises* at 52 μm/s and a full one (32× water) *sinks* at 1681 μm/s; neutral at 3.006 % charge | drift velocity linear in charge to Pearson **−1.000000**, zero crossing **3.00577 %** |
| **P2** | 96.415 °C is 3.585 K below boiling and heat output → 0 at the setpoint, so a culture pins its medium there and **can never boil it** | 2000 awake cells, 60 s insulated: max **369.56 K** vs setpoint 369.565. Driven to 400 K it relaxes back **while cell energy rises** |
| **P3** | dormant cells are inert powder; crossing the setpoint wakes them **irreversibly** | 2000/2000 wake within 50 ms; still awake after chilling to 20 °C |
| **P4** | a live cell holds its *surface* at the setpoint, so viscosity drops 3.4× and mobility rises | motility ratio **4.357**, matching the oracle |
| **P5** | albedo is exactly 0, so shadowing is **total** | adjacent collinear pair: rear cell at **bitwise `0.0`**. 8000 cells: charge-vs-depth **r = −0.879** |

### Behaviour and life, added since

| | measured |
|---|---|
| **taxis** | migration **−262.6 μm = 26.0σ** up-gradient; darkness **bit-identical** to the taxis-off null |
| **morphology** | irregular silhouettes, area-preserving to **1.6e-14**; all 8 measurement goldens **unchanged at mean 0.0000** |
| **division** | doubling **1.996** in one `LIFE_DOUBLING_TIME`; a 2,000 → **50,508** cell run is **bit-reproducible** |
| **death** | `void` corpses at **40.1 kg/m³** (rise), `retain` at **~25,500** (sink) |
| **telemetry** | 8 reductions of one state → **identical bit pattern**; ledger matches a host sum to 1e-9 |

### Performance

200k cells at **185.5 fps** (5.39 ms/frame) with the HUD live, against a 144 fps
target — 29 % margin. Real-time factor 0.19×, which is the number that actually
matters and is still below 1.

---

## 4. The meta-lessons. Read these twice.

These are worth more than any individual fact in the codebase. Each was paid for.

### 1. When a claim is about individual bodies, the grid is the wrong instrument

**This pattern produced three separate bugs (ADR-019, ADR-020, ADR-021).** The
field grids are depth-averaged, 2D, and represent the **far field**. So:

- A 2D grid **cannot** reproduce a 3D `1/r` point-source profile.
- A grid cell **cannot** hold the near-field temperature — its thermal time
  constant equals the diffusion substep. Conducting against it with a "corrected"
  shell conductance produced a **1.76 × 10⁶ K runaway**.
- A depth-averaged grid **cannot** produce an exact shadow — one cell blocks only
  16.8 % of a grid column's face.

The answer every time: **exact per-cell physics via the spatial hash for the near
field, statistical grid behaviour for the far field.**

**M8 met it a fourth time and decided the other way ON PURPOSE** (ADR-022 §1):
"follow the CO₂ lines to find breeding grounds" is a *region-scale* claim, so the
grid is the right instrument there. Knowing when the pattern does *not* apply is
part of the lesson.

### 2. Do not guess a numeric threshold — derive it

Every invented cutoff in this build has been wrong. `r > 4a` failed at the true
3.9a. `peak < 0.06` failed at 0.0617. `CONTACT_STIFFNESS` was off by 1587 %.

Recent practice: the clamped tumble mean is **derived** in `derive.py` and asserted
directly rather than hidden behind a wide tolerance; `TAXIS_RUN_MAX` is derived
from `TAXIS_MEMORY_TIME` so the two cannot drift apart; `LIFE_CO2_UPTAKE_MAX` is
derived from the canon doubling time so T18 asserts the implementation reproduces
its own definition. **And sometimes the answer is to invent nothing at all** — CO₂
availability is just `co2 > 0`, because a temporal comparison on an identically
zero field is identically zero.

### 3. When a gate fails, first ask whether it asks the right question

**Five times now the failing threshold was the *test's* fault, and each corrected
test came out stricter, not looser.** T14's Pearson cap, the M5 3D-law-on-a-2D-grid,
T13's "exactly zero" across 200 ticks, the starvation test needing a perfect cold
bath, and T18.3's absolute growth bound.

**Never weaken a gate to pass it** (Iron Rule 1). If a gate seems wrong, fix it
with an ADR.

### 4. …and the inverse, which is worse: a gate that PASSES while the thing is broken

M9a's CO₂ test asserted the **total** field stayed positive. Negative pockets clear
that trivially by hiding behind positive ones elsewhere — the field was at
**−0.128 kg/m³** the whole time and the suite was green. It asserts the **minimum**
now.

**Ask what your assertion cannot see.**

### 5. A measured symptom is not a diagnosis

M8 measured 54 % of cells reorienting every tick and blamed the memory window.
Retuning the window **raised** it to 69 % — because a shorter memory makes the EMA
track more closely, so Δ crosses zero more often. The tumble rate is set by the
*rule*, not the window. The number was real; the causal story attached to it was
not, and only **re-measuring after the change** exposed it.

**Predict, change, re-measure.** The prediction is not the result.

### 6. The oracle is authoritative

`docs/VERIFICATION.md` is **generated** by `scripts/derive.py` from first
principles, independently of the simulator. **If they disagree, the simulator is
wrong.** It has caught five real errors, including an integrator this project's own
spec called for that gave **47× too much diffusion** (ADR-016) — caught by
arithmetic before a line of it was written.

### 7. Correctness tests cannot see performance, and the benchmark can

M9b went RED on **M1.5** (the 200k-cell render benchmark) with all 13 correctness
checks green. Two real regressions: `world_stats` called every frame (it ends in a
*synchronous* D2H), and `scan_kernel` — which is `<<<1,1>>>`, a serial loop over the
whole population — running unconditionally to build a prefix that is almost always
all zeros. Fixing both took 145.2 → **185.5 fps**, and **T22's hash was unchanged**,
which is what proves an optimisation behaviour-preserving rather than merely
plausible.

### 8. Fusing across a documented tick-stage boundary is a correctness change

Not an optimisation. M2 fused stages 5 and 6 for register reuse; when M4 added
contact, that kernel read neighbour positions the same kernel was writing and
**2709 of 3000 positions differed between two identical runs** (ADR-018). The stage
boundaries in `ARCHITECTURE.md` §3.4 are load-bearing.

### 9. Match the sample — and the UNITS — to the source

A **lumped** exchange needs `grid_sample_nearest` / `grid_deposit_nearest`.
Bilinear spreads a deposit over four cells but reads back only `Σw²` of it — 0.25
at a grid node — so a lumped model sees a quarter of its feedback.

M9a added the harder half: CO₂ demand was booked in **kilograms** against a
`deposit_scale` calibrated for **concentration**. A 6e-16 kg demand rounds to zero
in fixed point, so the rationing silently never fired and the field went negative
*with the ration in place*. **Check the units of the accumulator, not just the
sampling mode.**

### 10. Determinism on a GPU is not free

Four decisions exist purely to buy it, and none is negotiable:

- **Per-cell PCG32 streams** keyed on a stable cell `id`, never a slot or thread
  index (ADR-014).
- **64-bit fixed-point accumulation** for every field deposit and statistic.
  `atomicAdd(float*)` is order-dependent (ADR-013).
- **A stable radix sort** for the spatial hash (ADR-018).
- **Prefix-sum slot allocation** for daughters, never `atomicAdd` (ADR-025). The
  snapshot hash is taken over the SoA *in slot order*, so it is the **allocation**
  that must be order-free, not just the arithmetic. Plain integer **counts** via
  `atomicAdd` are fine — addition of ones is associative.

### 11. Look at the output

Every test was green while the renderer drew a field of **snowflakes**. The rim
treatment modulated edge softness per angle, and a radially-varying falloff
distance renders as radial spokes. Plotting the pure `shape_radius` function in 20
lines of Python localised it immediately by showing the silhouette was already
correct.

---

## 5. The process rules that are actually enforced

- **A milestone is done only when `gate.ps1 -Milestone M<N>` exits 0.** Then
  `git tag m<N>-green`. Every gate re-runs all earlier gates. Gates never weaken.
- **Run `scripts/audit.ps1` before and after each step.** Ten checks: canon
  freshness, warnings-as-errors, ctest, determinism replay, no presentation code in
  `sim`/`fields`, no host RNG, no fast-math, module inventory, **no physical
  literals in `sim`/`fields`**, no render size fudge.
- **No physical literal outside `scripts/canon.py`.** A9 greps three patterns and
  *will* catch you. It has no waiver in use — if it flags something, prefer
  removing the need for it. (M8's `log(0)` guard vanished by sampling `1 − u`
  instead of `u`; M9a's hash salt vanished by double-mixing `splitmix64`.)
- **`build.ps1 -App`** whenever the executable matters. Without `-App` the core and
  tests build with no network and no dependencies.
- **Regenerating goldens requires a `DECISIONS.md` entry in the same commit**
  (Iron Rule 10). Never edit goldens by hand. Note: after `-Generate`, `git status`
  may show all goldens modified while `imgdiff` reports mean 0.0000 — that is 1-LSB
  raster noise. Revert them and keep only genuinely new ones; committing churn
  makes a future real change invisible in the diff.
- **Diff budget ≤ 600 LOC** per change unless the milestone authorises more.
- **Spec reconciliation in the same commit** as any contract or boundary change.
- **One milestone per session.** If it will not fit, split it in `MILESTONES.md`
  *before* starting and give each half a gate. `gate.ps1` accepts split names
  (`M8b`, `M9a`, `M9c`) — both its `ValidatePattern` and its parser handle a
  trailing letter.
- **End every session** by running the gate, appending a `SESSION_LOG.md` entry,
  tagging if green, and **rewriting `_run_state/NEXT_SESSION.md`**.

**Ask before:** `git push` to any remote, anything outside `C:\Astrophage\`,
network access beyond dependency fetch, Windows settings, spending money.

---

## 6. What is next — M10 (Predation)

M9c (the multi-rate clock, slot compaction, charts) and M7b (the Petrovascope and
Thermal-IR view modes) are both **done and green**. M10 is next.

**Scope.** `PHYSICS.md` §11. A `TaumoebaStore` (its own SoA, same patterns as the
cell store), amoeboid crawl biased up the local cell-density gradient, engulfment
on overlap with a live cell, digestion, the **N₂ field lethality**, and **heritable
N₂ tolerance with mutation**.

**Gate.** M9c gate + a predator introduction crashes the population; under a slowly
rising N₂ ramp the mean tolerance rises monotonically on a 5-generation moving
average, and a strain with tolerance ≥ 0.825 (**Taumoeba-82.5**) appears within 40
generations at default `TAU_MUTATION_SIGMA` — by genuine directional selection,
**not by script** (`SCENARIOS.md` §6).

**Three things M10 will confront:**

1. **A second organism store, and it evolves.** `predation.cu` is in the module map
   but empty. It gets its own OU integrator (γ from `TAU_DIAMETER`), its own PCG32
   streams keyed on a Taumoeba id, and — because Taumoeba divide and die — its own
   reproducible birth/death. That is **T22's argument all over again** for a new
   store, and it wants the M9c compaction primitive (`cell_store_compact` is the
   template; give the Taumoeba store the same scan/gather buffers).
2. **N₂ already exists as a field** (`FIELD_N_N2` = 128², a brush at M5). M10 adds
   the coupling: hazard `max(0, N − N_lethal·(1 + tol·k))` and a Poisson death, and
   a heritable `tolerance` drawn `parent + N(0, TAU_MUTATION_SIGMA)` clamped to
   [0,1] — a **real draw from the Taumoeba's stream**, so determinism must survive
   it. **Q19 stands:** `biology_rate` does not scale N₂ diffusion either.
3. **The 82.5 arc must EMERGE.** The gate forbids scripting it. If you find yourself
   special-casing 0.825, stop — that is the P1–P5 rule applied to evolution.

### Then M11 → M12

- **M11 Content** — scenario loader, all eight scenarios from `docs/SCENARIOS.md`,
  the parameter inspector with provenance badges and canon locks, the cell
  inspector, CSV telemetry.
- **M12 Ship** — snapshot/replay, performance pass, packaging, v1.0. The M7b
  remainder (bloom, cross-fade slider, Thermal field-halo) is render polish that
  fits M12's performance/packaging pass; pre-ignition warm-up needs
  `render_view_v3` and can ride a contract bump there.

---

## 7. Open questions, with reasons

**Recorded rather than glossed. Any of these is a legitimate thing to pick up.**

- **Q1** — App `--headless` (hidden window) and `tools/headless` (never links GL)
  stay separate deliberately; merging would drag GL into the determinism oracle.
- **Q5** — When M9c adds slot reuse, confirm `spawn_kernel` clears `vx/vy/vz`. It
  does today, but only incidentally.
- **Q6** — `MotionConfig` flags (`thermal_noise`, `contact_enabled`,
  `adhesion_enabled`, `thermal_enabled`, `emission_enabled`, `taxis_enabled`,
  `occlusion_exact`, `store_disposition`) are test-only. A scenario wanting them
  needs fields in `contracts/scenario_v1.h`.
- **Q7 / ADR-017** — `optics.h`, `morphology.h` and the GLSL in `cells_pass.cpp`
  duplicate **five** formulas with no compiler check between them. Q7's trigger has
  been met: the next consumer should **generate the GLSL from the header** rather
  than hand-keeping a sixth copy.
- **Q9** — the neighbour walk visits **27 buckets when 8 would do** (`cell_size`
  22 μm ≥ 2 × 10 μm range). Used by contact *and* occlusion. Still the single best
  remaining performance lever.
- **Q10** — contact cannot hold a fully charged cell at `dt` = 1 ms (ADR-018 §3);
  needs substepping if a scenario makes dense charged cultures.
- **Q11** — the SoA is **not** reordered by bucket, contrary to M4's stated scope: a
  determinism hazard for a speculative gain. Revisit only with profiling evidence.
- **Q12** — `shell_conductance` is kept in `thermal.cuh` but **deliberately
  unused**. Read ADR-020 before reaching for it.
- **Q13** — light is axis-aligned only (ADR-021). A sheared sweep collides threads
  on shared cells and needs atomics or a rotated buffer.
- **Q14** — dormant cells **charge**: `feed_kernel` checks `OCCUPIED|ALIVE` only.
  Absorption is not optional (albedo 0), but the consistent alternative is that
  absorbed light *warms* a dormant cell and ignites it at 96.415 °C —
  **light-driven ignition**, canon-consistent and lovely. Needs its own ADR.
- **Q15** — re-aiming is **instantaneous**; `PETROVA_SLEW_RATE` is unused by taxis.
  Rate-limiting needs the commanded heading stored apart from the current axis, and
  `cell_store_v1.h` has no such field — a v2 bump. Error direction is known:
  instantaneous re-aim makes taxis *strictly more effective*, so 26.0σ is an upper
  bound.
- **Q18** — the tumble rule has **no refractory period**: `Δ ≤ 0` fires on any tick,
  so motion is a biased random walk decorrelating every millisecond rather than
  run-and-tumble — only **3.6 %** of cells are on a run outlasting one comparison
  window. The fix is a **rate-based Poisson tumble**, NOT a hard minimum run: a
  floor at `TAXIS_TUMBLE_SLEW_TIME` = 1.19 s commits a cell to 7.3 mm of travel in a
  4 mm chamber. Entangled with Q15 and ADR-005.
- **Q19** — see §6.1. M9c's.
- **Q20** — `scan_kernel` is single-threaded. See §6.3.
- **Deferred render work** — bloom and the **Petrovascope / Thermal-IR view modes**
  were in M7's scope and are still not done. The enum values and `u_mode` are
  plumbed. The constraint that matters: Thermal IR and Petrovascope must read
  *differently* (7.841 μm blackbody vs a 25.984 μm quantum line — a live idle cell
  glows in one and is **dark** in the other). That is the simulator's best teaching
  moment and it is missing. `RENDERING.md` §4–§5.
- **Still open in `RENDERING.md` §8** — lateral chromatic aberration and procedural
  medium texture, both with honesty caveats (aberration displaces pixels and must
  never reach a measurement golden; a debris speck miscounted as a cell is a bug in
  a simulator built to count cells). Faceting too: silhouettes are lobed pebbles
  rather than the angular grains in the reference photography.
- **Test suite cost** — `ctest` is ~4 minutes; `test_taxis` alone is 41.5 s. Kept
  deliberately. If it becomes a problem that is an ADR, not a quiet trim.

### Known flake

`gate.ps1`'s **M0.2** does a clean reconfigure, re-fetching GLFW/GLAD/ImGui over the
network. It has failed transiently twice (once as `ninja: failed recompaction:
Permission denied`) while every later gate passed on the resulting artifacts. If it
recurs, make `build.ps1` retry the reconfigure rather than let a file-lock or
network hiccup read as a milestone failure.

---

## 8. What NOT to do

- No interstellar, solar-system, or spacecraft scale. No orbital mechanics. The
  `spin-drive-face` scenario is the sole exception and is cell-scale by nature.
- No game mechanics or objectives beyond scenario acceptance checks.
- No asset files — everything procedural or generated.
- No web/browser tech. No Vulkan, no D3D, no second windowing framework.
- No `-use_fast_math` in `sim`/`fields` (INV-6).
- No new dependency without an ADR. Allowed: CUDA Toolkit (incl. CUB), GLFW, GLAD,
  Dear ImGui.
- No skipping the change manifest. No loading the entire repo into context.
- **No forbidden synonyms** — the glossary in `ARCHITECTURE.md` §2 is mandatory. It
  is **Cell**, **Chamber**, **Scope**, **Charge**, **Petrova**, **Tick**, never
  particle / world / camera / fuel / IR / frame.
- **Never special-case a signature phenomenon.** If you are writing an `if` to make
  P1–P5 happen, the model is wrong upstream.

---

## 9. How the repo generates itself

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

**Provenance discipline matters and is easy to get wrong.** A behavioural
measurement of a *different organism* is `INVENTED`, not `REAL` — `REAL` means a
real-world *physical* constant. Both `TAXIS_TUMBLE_ANGLE_MEAN` (E. coli's 68°) and
`LIFE_CO2_HALF_SATURATION` (algal half-saturation) are tagged INVENTED with the
analogy spelled out in the note.

The novel contradicts itself twice, materially, and **both readings ship as
playable options** rather than as silent decisions (ADR-002 cell density, ADR-003
dormancy). ADR-023 added a third of the same kind: the novel says spheres, reference
photography shows irregular grains, so **both morphologies ship**.

---

## 10. Suggested first message back

State which milestone you are taking, produce the **change manifest** the session
ritual requires (files to touch, contract changes y/n, tests to add, rollback plan,
diff budget), and confirm the M9b gate is green before you change anything.

If you are picking up M9c, say up front which way you are going on **Q19** — it is a
decision, not a bug, and it needs an ADR either way.
