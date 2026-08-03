# M10b KICKOFF — paste this whole file as the first message of the new session

You are continuing a **multi-session, autonomous, gate-driven build** of the Astrophage
Microscope Simulator at `C:\Astrophage`. This file is your initialization prompt. **Do
not write any code until you have completed the READ-IN RITUAL in §2** — this build's
quality depends on loading real detail from the repo rather than guessing. The docs and
contracts are unusually complete; use them.

Your job this session: **land M10b (Evolution)** — the last piece of predation — to a
green gate, then tag it and rewrite the handoff. Everything below tells you the state, the
plan, the process, and the hard-won lessons. Read it, then read the files it points you
to, then produce a change manifest, then execute.

---

## 0. The thirty-second version

`C:\Astrophage` is a physics-based, GPU-accelerated simulation of **Astrophage** (Andy
Weir's *Project Hail Mary*) seen **through a microscope**. C++20 + CUDA 13.1, OpenGL 4.6
interop, Dear ImGui, CMake/Ninja, `sm_89` (RTX 4070 Ti SUPER), Windows 11. Public MIT
repo: https://github.com/bochen2029-pixel/astrophage-microscope

A sealed 4 mm × 4 mm × 60 μm chamber of water. Cells 10 μm across, **black at every
wavelength** (albedo 0), each holding up to 1.5 MJ as neutrino mass. Real Stokes drag,
Langevin dynamics, Fickian diffusion, conduction, photon momentum. The one fictional
element — the mass-energy store — is canon-locked. **This is a simulator, not a game**:
no win state, no assets, everything procedural.

**Scope is deliberately cell-level and quasi-2D.** No ships, no Petrova arc, no Tau Ceti,
no interstellar view. The sole exception is a planned `spin-drive-face` scenario, which
belongs because a spin drive *is* a cell-scale machine. Do not let scope creep upward.

**Where it stands: `m10a-green` is the last tag. M10b is next and is the whole job.** All
five signature phenomena are live; cells behave, divide, die, run on a multi-rate clock
with slot compaction; all five view modes draw distinctly; and the **Taumoeba predator
crawls and engulfs deterministically**. M10b makes the predator **evolve**.

---

## 1. Orient against the tags, not against any doc

```bash
git -C C:\Astrophage tag --list
```

**The last `m<N>-green` tag is ground truth.** As of writing: `m0-green` … `m9c-green`,
plus `m7b-green` (deferred view modes) and `m10a-green` (predation). If anything in this
file disagrees with the tags, believe the tags. Then verify the baseline **before changing
anything** — this rebuilds and re-runs every gate M0…M10a and takes ~12–15 min, so run it
in the background and read while it goes:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M10a
```

Then look at the thing (optional but grounding): `build/astrophage.exe`. Drag to pan,
scroll to zoom, `Home` resets, rack the focal-plane slider, drag charge past 3.0058 % to
reverse the culture. `--mode thermal --awake` shows the film's IR view; `--clock motion`
speeds physics 10×.

---

## 2. READ-IN RITUAL — do this, in this order, before writing code

A correct session loads ~25–50k tokens of docs and spends the rest on code. **Never load
the whole repo.** But do load these, because M10b extends real code you must not guess at:

1. **`CLAUDE.md`** — the operating contract: session ritual, the ten Iron Rules, module
   map, code standards, authority. Always.
2. **`docs/ARCHITECTURE.md`** (~200 lines) — module boundaries, invariants INV-1…INV-8,
   the mandatory glossary, the 11-stage tick sequence, the anti-drift machinery. Always.
3. **`docs/PHYSICS.md` §11 (Taumoeba)** — the predation/evolution model you are
   implementing. Also skim §10 (life cycle) — Taumoeba division mirrors cell mitosis.
4. **`docs/MILESTONES.md` — the M10b section only.** Not the whole file. It has the exact
   scope and gate.
5. **`docs/DECISIONS.md`** — 29 ADRs. Read the index, then read in full: **ADR-014**
   (per-cell PCG32 streams), **ADR-025** (mitosis: prefix-sum slots + the mutation-drawn-
   from-daughter-stream rule you will copy), **ADR-028** (the compaction primitive the
   Taumoeba store now needs), **ADR-022** (why a conditional RNG draw is still
   deterministic — the N₂ Poisson death is one), **ADR-013/INV-2** (fixed-point / order-
   free reasoning — the engulf claim uses it).
6. **`src/sim/predation.cuh` and `src/sim/predation.cu`** — **READ BOTH.** This is the
   M10a code you extend. The store is append-only; `tolerance` is a field already
   (initialised to `TAU_N2_TOLERANCE_INIT`); the crawl/engulf/digest kernels and the step
   are here. You will add N₂ death + division + compaction to this file.
7. **`src/sim/lifecycle.cu`** — the cell mitosis (`mark_kernel`/`scan`/`divide_kernel`
   via `cub::DeviceScan`) and `cell_store_compact` (in `cell_store.cu`) are the exact
   patterns Taumoeba division and reclamation copy. Read them; do not reinvent.
8. **`src/sim/MODULE.md`** — the module's owned files, invariants, and "things that will
   bite you". **`src/fields/MODULE.md`** and **`docs/PHYSICS.md §7`** for the N₂ field.
9. **`docs/SESSION_LOG.md` — the last 3 entries (M10a, M7b, M9c).** The most useful file
   in the repo: one entry per milestone with what went wrong and why.
10. **`_run_state/CONTINUATION_PROMPT.md`** — the fuller standing handoff. Its **§4 has the
    eleven accumulated meta-lessons**, each paid for. Read them twice.
11. **The contracts you touch**, and only those: `contracts/fields_v1.h` (the N₂ field +
    deposit scales), `contracts/telemetry_v1.h` (`Stats.mean_tau_tolerance`,
    `n_taumoeba` — already declared, unfilled). Read the contract, never another module's
    source, for an interface.

`docs/VERIFICATION.md` is **generated** from `scripts/canon.py` by `scripts/derive.py`; it
is the physics oracle. If the sim disagrees with it, the sim is wrong.

---

## 3. The state, in numbers

**22 tests green, 12 goldens, 10 audit invariant checks, 29 ADRs.** Reference GPU runs
200k cells at 185 fps.

```
test_canon test_rng test_contracts test_fixed_atomic test_octahedral test_cell_store
test_scope test_motion test_buoyancy test_optics test_hash test_contact test_fields
test_thermal test_emission test_taxis test_morphology test_lifecycle test_stats
test_clock  test_predation   + determinism_replay (headless, INV-8)
```

Signature phenomena (all live, all **emergent** — never special-cased): P1 the 3 % line
(charge readable from vertical drift), P2 the perfect thermostat (can't boil the medium),
P3 ignition latch, P4 live cells move (viscosity drop), P5 absolute shadows. Behaviour and
life on top: taxis migration 26.0σ; division doubling 1.996; T22 a 2,000→50,508 run is
bit-reproducible; M9c clock ratios exact and compaction bit-reproducible (T22b); M7b
Thermal-IR is the film's absorption view; **M10a T30 predation is bit-reproducible and a
predator introduction thins 6,000→5,898 cells, all contained.**

### The tick sequence (ARCHITECTURE.md §3.4) — do not reorder

1 hash_build · 2 field_sample · 3 taxis · 4 thermal · 5 forces · 6 integrate · 7
field_deposit · 8 field_diffuse · 9 irradiance · **10 predation** (crawl + engulf) · **11
lifecycle** (uptake, death, mitosis, compaction — MUTATES THE STORE, stays last) · stats
(run at HUD rate from `world_stats`, not every tick).

---

## 4. What M10b is — the exact task

**Scope (`PHYSICS.md` §11, evolution half):**
- **N₂ field lethality.** The N₂ field exists (`FIELD_N_N2` = 128², a tool brush since M5).
  A Taumoeba in nitrogen dies with a Poisson hazard: `hazard = max(0, N_local −
  TAU_N2_LETHAL_CONC · (1 + tolerance · k))`, death probability `1 − exp(−hazard · rate ·
  dt)` per tick. `k` and `rate` are your derived/invented choices — **derive them, don't
  guess** (see the "don't guess a threshold" lesson), and give them provenance in
  `canon.py`. The death draws **one uniform from the Taumoeba's own stream**; a survivor
  must draw the same so the stream stays a pure function of state (ADR-022's IDLE lesson —
  either both branches draw, or neither).
- **Taumoeba division.** A Taumoeba that reaches 2× its initial biomass (`TAU_MASS`)
  divides. **Copy the cell mitosis exactly (ADR-025):** daughter slots from an exclusive
  prefix sum (`cub::DeviceScan::ExclusiveSum`, never `atomicAdd`), daughter id
  `first_id + prefix[i]`, daughter stream `pcg_split(parent_state, daughter_id)`, biomass
  split, and the mutation drawn from the **daughter's** stream so the parent's trajectory
  never depends on whether it divided.
- **Heritable tolerance.** Daughter `tolerance = clamp(parent_tolerance + N(0,
  TAU_MUTATION_SIGMA), 0, 1)`. `TAU_MUTATION_SIGMA` and `TAU_N2_TOLERANCE_INIT` are canon
  already. This is the whole engine of the evolution arc.
- **Compaction for the Taumoeba store.** It is currently **append-only** (M10a). Death and
  division now churn it, so give `TaumoebaStore` the same scan/gather/CUB buffers
  `CellStore` has and call the stable prefix-sum, out-of-place `..._compact` (ADR-028 is
  the template — read `cell_store_compact` in `cell_store.cu`). Opt-in, default off, so
  M10a determinism is bit-preserved.
- **The mean-tolerance chart** (UI) and filling `Stats.mean_tau_tolerance` / `n_taumoeba`
  in the stage-11 reduction (`stats.cu`).

**Gate (add `test_evolution`, and the gate.ps1 step M10b.1 already references it):**
M10a gate + a predator introduction crashes the population; **under a slowly rising N₂
ramp the mean tolerance rises monotonically on a 5-generation moving average, and a strain
with tolerance ≥ 0.825 (Taumoeba-82.5) appears within 40 generations at default
`TAU_MUTATION_SIGMA`** — by genuine directional selection. And the run stays
bit-reproducible (T30 extended to a dividing/dying store — this is T22's argument a third
time). `gate.ps1` already has an `M10b.1` block calling `test_evolution`; you write that
test.

**The one rule that governs the whole milestone: it must EMERGE.** If you find yourself
writing an `if` that special-cases 0.825, or scripting the tolerance upward, stop — the
model is wrong. Selection does the work: high N₂ kills low-tolerance Taumoeba, survivors
divide and pass on (mutated) tolerance, the mean climbs. This is the P1–P5 discipline
applied to evolution. The gate exists to prove you did not cheat.

**Split if it will not fit (Iron Rule 9).** If M10b is too big for one session, split it
before starting (e.g. M10b = N₂ lethality + division determinism; M10c = the selection
arc + chart) in `MILESTONES.md`, each with its own gate. `gate.ps1` handles a trailing
letter. But try for one.

---

## 5. The M10a code you are extending (so you are not guessing)

- **`predation.cuh`** — `TaumoebaStore` (SoA: id, flags, x/y/z, vx/vy/vz, dir_x/y/z,
  biomass, prey_biomass, digest_timer, **tolerance**, rng_state, density_ema, run_timer,
  target). Pure `__host__ __device__` helpers: `tau_drag(T)`, `tau_overlaps_cell`,
  `tau_should_tumble`. `taumoeba_create/destroy/spawn` + downloads.
- **`predation.cu`** — `spawn_kernel` (seeds `cell_rng_init(splitmix64(seed), id)` — a
  **disjoint stream space** from the cells; keep that when you add division), `hunt_kernel`
  (senses prey density, run-and-tumble, crawl via `integrate_cell` with `TAU_MASS`/
  `tau_drag`, and claims the first overlapping prey via `atomicMin` into the per-cell
  claim buffer `w.d_predator_claim`), `resolve_kernel` (the lowest-id claimant engulfs:
  prey → dead/Predated with `corpse_energy`, predator starts digesting), and
  `predation_step` (stage 10). Digestion counts down on `dt_bio` (biology clock).
- **The store is append-only.** No compaction buffers yet — you add them (mirror
  `cell_store.cuh`/`cell_store.cu`). The predator is **neutrally buoyant** (water-density
  blob), so the crawl is a purely driven walk — no gravity term. Contact does not apply to
  Taumoeba.
- **Canon you have:** `TAU_DIAMETER, TAU_CRAWL_SPEED, TAU_DIGEST_TIME, TAU_N2_LETHAL_CONC,
  TAU_N2_TOLERANCE_INIT, TAU_MUTATION_SIGMA, TAU_BIOMASS_YIELD, MAX_TAUMOEBA,
  DEFAULT_TAUMOEBA` (base) and `TAU_RADIUS, TAU_VOLUME, TAU_MASS, TAU_DRAG_20C,
  TAU_CRAWL_THRUST` (derived). Any new number (the hazard `k`, `rate`, a division-biomass
  threshold) goes in `scripts/canon.py` with a provenance tag, then `python
  scripts/derive.py`. **No physical literal survives A9 in `sim/`** — a `1.0e30` sentinel
  tripped it in M10a; use the pattern, not a literal.

---

## 6. The process that is actually enforced (read `CLAUDE.md` for the full ten Iron Rules)

- **The gate is law.** A milestone is done only when `gate.ps1 -Milestone M<N>` exits 0 →
  `git tag m<N>-green`. Every gate re-runs all earlier gates; gates **never weaken** — if a
  gate seems wrong, fix it with an ADR, never relax a threshold.
- **`scripts/audit.ps1` before and AFTER every step.** Ten checks: canon freshness (A1),
  clean build /WX (A2), ctest (A3), determinism replay (A4), no presentation code in
  sim/fields (A5), no host RNG (A6), no fast-math (A7), module inventory (A8), **no
  physical literals in sim/fields (A9)**, no render size fudge (A10). Append the one-line
  verdict to `docs/CHANGE_AUDIT_LOG.md` (it does this itself).
- **Produce a change manifest BEFORE writing code:** files to touch, contract changes
  (y/n), tests to add, rollback plan, diff budget (≤ 600 LOC/change unless the milestone
  authorises more).
- **Spec reconciliation in the same commit:** touch a contract or a module boundary →
  update `contracts/`, the `MODULE.md`, and `ARCHITECTURE.md` together.
- **Determinism is sacred (INV-1..8).** Per-cell/-Taumoeba PCG32 streams keyed on a stable
  id; 64-bit fixed-point for deposits and stats; stable radix-sort hash; prefix-sum (not
  atomicAdd) allocation. The snapshot hash is over the SoA in slot order, so it is the
  *allocation* that must be order-free, not just the arithmetic.
- **Headless first.** Every feature ships a headless verification (a test, a hash) before
  pixels. `sim/` and `fields/` link and run with no GL.
- **Regenerating goldens needs a `DECISIONS.md` entry in the same commit** (Iron Rule 10),
  and after `-Generate` the pre-existing goldens show as modified from 1-LSB raster noise
  while `imgdiff` reports mean 0.0000 — revert those, keep only genuinely new ones. (M10b
  is unlikely to touch goldens; noted in case.)
- **Ask before:** `git push` (the user has standing approval this project — push after each
  green milestone), anything outside `C:\Astrophage\`, network beyond dependency fetch,
  Windows settings, spending money.
- **End the session** by running the gate, appending a `SESSION_LOG.md` entry (< 25 lines),
  tagging if green, updating the `README.md` status table, and **rewriting
  `_run_state/NEXT_SESSION.md` + `_run_state/CONTINUATION_PROMPT.md`** so the next session
  starts cold. This is the single most valuable thing you do at the end.

---

## 7. The meta-lessons (condensed — the full eleven are in `CONTINUATION_PROMPT.md` §4)

1. **When a claim is about individual bodies, the grid is the wrong instrument** (ADR-019/
   020/021) — except genuinely region-scale ones (ADR-022 §1). Engulfment is a contact
   event (per-cell via the hash), not a field one. N₂ lethality *is* a field read — that's
   fine, it's a concentration at the predator's location.
2. **Do not guess a numeric threshold — derive it, and assert it.** Every invented cutoff
   in this build has been wrong (`r > 4a` failed at 3.9a; contact stiffness off by 1587 %).
   The N₂ hazard `k`/`rate` must be derived so the 82.5 strain arrives in the gate's window
   by construction, not by luck.
3. **A gate that PASSES while the thing is broken is worse than one that fails.** Assert the
   thing you actually care about (the mean tolerance's *monotone rise*, the strain's
   *appearance*), and ask what your assertion cannot see.
4. **A measured symptom is not a diagnosis. Predict, change, re-measure.**
5. **Correctness tests cannot see performance; the 200k benchmark can.** A second store's
   per-tick D2H is exactly the kind of regression it catches — keep predation's host reads
   at HUD/decision cadence, not blind per-tick.
6. **The oracle is authoritative.** `VERIFICATION.md` is generated independently; if it
   disagrees, the sim is wrong.
7. **Match the sample AND the units to the source** (bilinear vs nearest; kg vs
   concentration — a units mismatch drove the CO₂ field negative at M9a).
8. **Determinism on a GPU is not free** — the four decisions in §6 are non-negotiable. A
   conditional RNG draw is fine *only* if it is a pure function of state (both branches
   draw, or neither).
9. **Look at the output.** Every test was green while the renderer drew snowflakes. For an
   evolution arc, plot the mean-tolerance-over-generations curve and eyeball that it climbs.
10. **The novel contradicts itself; ship both readings as options** (ADR-002/003/023/029).
    Weir's own resolution for the dead cell's store: Taumoeba eat only the **chemical**
    energy; the neutrino store is the §10 disposition toggle (`void` default) — M10a already
    does this in `resolve_kernel` via `corpse_energy`.

---

## 8. Open questions / deferred (any is a legitimate pickup after M10b)

- **M7b remainder (render polish, fits M12):** bloom over the Petrova emission (the film's
  swirling pink points), the cross-fade mode slider, the real T-field false-colour behind
  Thermal IR (needs the field pass), and **pre-ignition warm-up of a heated dormant cell —
  the one thing that genuinely needs `temp_cell` in the render instance → `render_view_v3`**.
- **Q9** — the neighbour walk visits 27 buckets when 8 would do (`cell_size` 22 μm ≥ 2 ×
  range). Used by contact, occlusion, **and now Taumoeba prey-sensing** — the single best
  remaining perf lever.
- **Q18** — the tumble rule has no refractory period (3.6 % of cells on a real run); fix is
  a rate-based Poisson tumble, not a hard minimum run. Taumoeba crawl reuses the same
  run-and-tumble, so it inherits this.
- **Q7 / ADR-017** — six formulas now mirrored across the GLSL boundary with no compiler
  check (`petrova` added at M7b). Q7's trigger is well past met: generate the GLSL from the
  header.
- **Q14** — dormant cells charge; light-driven ignition is the canon-consistent
  alternative; own ADR. **Q15** — instantaneous re-aim (26.0σ is an upper bound).
- After M10b: **M11 Content** (scenario loader, all 8 scenarios from `SCENARIOS.md`, the
  parameter inspector with provenance badges + canon locks, the cell inspector, CSV
  telemetry). **M12 Ship** (snapshot/replay, perf pass, packaging, the M7b render remainder,
  `v1.0`).

---

## 9. What NOT to do

- No interstellar/solar-system/spacecraft scale (spin-drive-face is the sole cell-scale
  exception). No game mechanics. No asset files. No web/browser tech, no Vulkan/D3D, no
  second windowing framework, no networking. No `-use_fast_math` in sim/fields (INV-6). No
  new dependency without an ADR (allowed: CUDA incl. CUB, GLFW, GLAD, Dear ImGui).
- **No forbidden synonyms** (ARCHITECTURE.md §2 glossary): it is **Cell**, **Taumoeba**,
  **Chamber**, **Scope**, **Charge**, **Petrova**, **Tick** — never particle / amoeba /
  world / camera / fuel / IR / frame.
- **Never special-case a signature phenomenon or the evolution arc.** If you are writing an
  `if` to make Taumoeba-82.5 happen, the model is wrong upstream.
- No skipping the change manifest. No loading the entire repo into context.

---

## 10. Suggested first message back

Say you are taking **M10b**. Kick off `gate.ps1 -Milestone M10a` in the background to
confirm the baseline is green before changing anything. Complete the READ-IN RITUAL (§2) —
especially `predation.cu`, `lifecycle.cu`, and ADR-025/028. Then produce the **change
manifest** (files to touch, contract changes y/n, the derived hazard constants and their
provenance, tests to add — `test_evolution` — rollback plan, diff budget), and state up
front how you will keep the evolution arc **emergent** and how you will make the dividing/
dying Taumoeba store **bit-reproducible** (T30 extended). Then execute, auditing before and
after each step, and finish with the gate, the tag, and the rewritten handoff.
