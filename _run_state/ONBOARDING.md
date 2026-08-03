# ASTROPHAGE — Full-Context Onboarding Brief

> **Read this whole document before you do anything.** Not to be efficient — to be *warm*.
> The point is that you arrive at the first task already understanding what this thing is,
> why it is built the way it is, what it feels like when it is going well, and what the
> traps are. Everything below is the distilled memory of the sessions that built it. Soak
> in it. The build rewards a session that gets its bearings first and punishes one that
> starts editing before it understands the grain of the wood.
>
> When you finish this, do the **bootstrap ritual** in Part 10, then read
> `_run_state/NEXT_SESSION.md` for the immediate task, and only then start.

---

## Part 0 — One breath

`C:\Astrophage` is a **deterministic, GPU-accelerated simulation of Astrophage** — the
fictional organism from Andy Weir's *Project Hail Mary* — seen **through a microscope**.
It is C++20 + CUDA (sm_89) + OpenGL 4.6 interop + Dear ImGui, built on Windows 11,
milestone by milestone, across dozens of autonomous Claude Code sessions, with
machine-checkable gates. **It is a simulator and a visualisation, not a game.** No win
state, no story, no asset files — every pixel is procedural or generated from first
principles. The build is currently at **`m11e-green`**: physics complete, eight
self-verifying scenarios that pass their objectives *and* play in the app with a live
inspector and objective panel. Next is M11f (cell inspector + live param tuning), then
M12 (ship → `v1.0`).

**The single most important habit:** trust `git tag --list`, not any prose (including
this file). The last `m<N>-green` tag is ground truth for where the build stands.

---

## Part 1 — The gist: what this really is

Astrophage in the novel is a microbe that stores staggering energy, migrates toward heat
and CO₂ by light it emits in a band no eye can see, holds a fixed internal temperature,
is jet black at every wavelength, and breeds explosively. This project asks: *if you put
that organism under a real microscope and simulated the actual physics, what would you
see?* And the answer is built so that the answer **emerges** — nothing is faked.

The emotional core, the thing that makes this worth doing well: **the signature behaviours
are not scripted; they fall out of honest equations.** A cell rises or sinks because of
Archimedes acting on `mass = biomass + energy/c²`. A culture pins its water to 96.415 °C
and *cannot boil it* because Weir happened to choose a setpoint 3.585 K below boiling and
the thermostat's heat output goes to zero as it approaches the setpoint. Cells shadow each
other perfectly because albedo is exactly zero. If you ever find yourself writing an `if`
to *make* one of these happen, you have made a mistake — the model is wrong upstream.
That discipline is the whole aesthetic of the codebase. Guard it.

The second thing that makes it special: **honesty about fiction.** Weir wrote some numbers;
we invented others where the novel is silent; some are real material constants. Every
single parameter carries a provenance tag (`CANON` / `DERIVED` / `REAL` / `INVENTED`)
through the entire stack, and that honest bookkeeping became a *shipped feature* — the
parameter inspector shows you, in gold and orange, exactly which numbers Weir wrote and
which we made up, and a run that unlocks a canon number is flagged NON-CANON forever. The
project treats "we don't actually know this, here's our guess and why" as a feature, not
an embarrassment.

**What it is NOT — scope discipline (this matters, it is a real temptation):** this is
cell-scale and quasi-2D. No ships, no interstellar view, no Petrova-line arc across a solar
system, no Tau Ceti. The chamber is 4 mm × 4 mm × 60 μm of water and the scope sees 550 μm
of it. The *one* exception is the `spin-drive-face` scenario, and it earns its place only
because a spin drive is literally a cell-scale machine, so the microscope is the right
instrument. Do not let scope creep upward. Bo ruled this out explicitly and early.

---

## Part 2 — The five signature phenomena (know these cold)

These are why the project exists. Each **emerges** from the equations in `docs/PHYSICS.md`.
The numbers below are the measured, verified reality — internalise them; they are your
sanity check when something looks wrong.

- **P1 — The 3 % line.** Canon mass in a 10 μm sphere gives an empty cell ρ = 40 kg/m³, so
  it *rises* at 52 μm/s; a full cell is 32× denser than water and *sinks* at 1681 μm/s.
  Neutral buoyancy at exactly **3.006 % charge**. Charge is readable from vertical drift.
  Drift velocity is *linear* in charge (Pearson −1.000000).
- **P2 — The perfect thermostat.** 96.415 °C is 3.585 K below water's boil, and thermostat
  output → 0 at the setpoint. A culture pins its medium to 96.415 °C and **can never boil
  it at 1 atm**. Overheat it externally and the cells absorb the excess as neutrino mass and
  drag it back down.
- **P3 — Ignition.** Dormant cells are inert black powder. Cross the setpoint once and the
  culture wakes *irreversibly*, then holds temperature even as you chill it (the latch).
- **P4 — Live cells move.** A live cell warms its neighbourhood, viscosity drops 3.36×,
  Brownian diffusivity rises 4.24×. Live and dead are distinguishable by eye — exactly the
  tell used in the novel.
- **P5 — Absolute shadows.** Albedo is exactly 0 at all wavelengths, so occlusion is total.
  A lit monolayer forms and everything behind it starves in perfect darkness.

There is also the **Taumoeba** — the predator (a 40 μm amoeba that engulfs Astrophage). It
crawls, engulfs, digests, and **evolves**: under a slowly rising nitrogen ramp, the
**Taumoeba-82.5** strain (N₂ tolerance ≥ 0.825) breeds itself by *genuine directional
selection*, deterministically, never by script. A constant-N₂ control plateaus at 0.17 —
that control is what proves the rise is selection, not drift. This is the emotional peak of
the biology and it is emergent. Protect it the same way you protect P1–P5.

---

## Part 3 — Who you are working with, and how to work here

**Bo.** Builds substantial native C++/CUDA projects on this Windows 11 box, run
autonomously by Claude Code across dozens of sessions. He has converged on a scaffolding
(see below) and expects it. His working style, observed: he grants **broad execution
autonomy** — he engages crisply with a *well-framed* decision point when you surface one
(a scope fork, an ADR direction), but otherwise wants you to make the design and scope
calls yourself and **record them as ADRs rather than ask**. When you propose stopping
conservatively he will often say "you decide, proceed" or "you still have plenty of
context, continue" — so when context and budget allow, carry on across multiple milestones
in a session rather than halting early. He values dense, opinionated output and honest
verification over hedging. Don't narrate options you won't take; make the call and go.

**The machine:** RTX 4070 Ti SUPER (sm_89, 16 GB), CUDA 13.1, MSVC 14.44 (VS 2022), CMake,
Python 3.13. `ninja` is not on PATH but VS bundles it. Everything is native — no web tech,
no second windowing framework, no networking.

**The discipline that makes a dozens-of-sessions build actually converge** (this is not
bureaucracy — it is what keeps the build from thrashing itself apart):
- **The tag is the truth.** Docs describe intent; tags describe reality. Believe the tag.
- **One milestone per session**, with a cold read-in ritual, split if it won't fit.
- **Never load the whole repo.** `ARCHITECTURE.md` + one milestone + one `MODULE.md` + the
  contracts it uses ≈ the correct 25–50k-token working set. If you're at 200k of docs, you
  loaded the wrong things.
- **The gate is law.** A milestone is done only when `gate.ps1 -Milestone M<N>` exits 0.
  No green, no tag, no moving on. Never relax a threshold to pass — fix the code or file an
  ADR. Every gate re-runs all earlier gates, so a regression in M2 fails the M11 gate.
- **Leave the build green.** A session that ends red costs the next one its entire budget on
  archaeology. If you can't finish, revert to the last green tag and log what you learned.

---

## Part 4 — The lay of the land (where everything is)

**Modules** (`src/`), dependency arrows point downward only; `core` depends on nothing:

| Module | Owns |
|---|---|
| `core` | generated canon (`canon_generated.h`), the runtime `ParamSet` overlay (`params.h`), units, PCG32 RNG, vec math, fixed-point atomics, `Result`/`Error` |
| `fields` | `Grid2D`, diffusion solvers, irradiance + occlusion sweep |
| `sim` | cell + Taumoeba SoA stores, the OU integrator, thermal, emission, taxis, lifecycle, predation, the spin-drive flash, snapshot, stats, the scenario loader + driver, acceptance evaluation |
| `render` | GL context, CUDA-GL interop, instanced cell pass, optics, post/bloom, LUTs, camera |
| `ui` | ImGui panels: HUD, parameter inspector, objective panel, charts, (coming: cell inspector) |
| `app` | Win32/GLFW shell, the fixed-tick main loop, CLI, the composition root — the only place globals live |
| `tools` | `headless` (the determinism oracle + `--scenario --assert` acceptance runner + `--csv`), `goldgen`, `imgdiff` |

**Docs** (`docs/`), read only what the task needs:
- `ARCHITECTURE.md` — **read every session.** Module boundaries, the 8 invariants (INV-1..8),
  the mandatory glossary, the tick sequence, the anti-drift machinery, the provenance system.
- `PHYSICS.md` — the model. Load only when touching `sim/` or `fields/`. Every constant is
  generated; every quoted number is independently verified in `VERIFICATION.md`.
- `RENDERING.md` — load only when touching `render/` or `ui/`.
- `MILESTONES.md` — read *one section* (the active milestone), never the whole file.
- `DECISIONS.md` — the ADRs. **Read this before disagreeing with anything.** Every
  contradiction in the source material is already adjudicated here, with reasoning and an
  escape hatch. Re-litigating costs a session; reading costs a minute. Currently 34 ADRs.
- `SESSION_LOG.md` — read the **last two entries** at session start. Most useful file in the
  repo for "what just happened".
- `SCENARIOS.md` — the eight scenarios and their accept blocks (the content spec).
- `VERIFICATION.md` — generated from first principles, independent of the sim. If the sim
  disagrees with it, the **sim** is wrong.

**Contracts** (`contracts/*_v*.h`) — versioned, dependency-free headers defining every
cross-module interface. This is how a session works `render` without reading `src/sim/`. If
you ever open another module's `.cu`/`.cpp` to learn what it does, **the contract is wrong —
fix the contract.** To evolve one: add `_v2.h`, update every consumer, ADR, all one commit.
`scenario_v2.h` and `render_view_v2.h` exist; their `_v1` predecessors are frozen and unused
(nothing may include both — same names, same namespace).

**Handoff docs** (`_run_state/`): this file (deep immersion), `CONTINUATION_PROMPT.md`
(the comprehensive bootstrap — ritual + state + roadmap + the 11 meta-lessons in full),
`NEXT_SESSION.md` (one-screen "you are here" + the immediate task).

**Scripts** (`scripts/`, all PowerShell): `build.ps1` (add `-App` for the windowed exe,
`-Clean` to reconfigure), `audit.ps1` (fast continuous check — run before and after each
step), `gate.ps1 -Milestone M<N>` (the milestone gate), `canon.py` (**the sole source of
every physical number**), `derive.py` (regenerates the canon artifacts), `goldens.ps1`.

---

## Part 5 — The rules that are law

**Iron Rules** (from `CLAUDE.md` — these override convenience, performance, and elegance):
1. The gate is law. Green → tag. Never relax a threshold to pass.
2. Tag on green; revert on regression (two failed fix attempts → `git reset --hard` to the
   last green tag and re-approach; never debug forward from a broken state).
3. **No physical literal outside `scripts/canon.py`.** Constants are generated into
   `canon_generated.h`. `audit.ps1` (check A9) greps `src/sim` and `src/fields` for bare
   floats — scientific notation with a 2+ digit exponent, long mantissas, two-and-two
   decimals — and fails the build. Escape hatches: cite `canon::` on the line, or add an
   `ASTRO_LITERAL_OK` comment for genuine plumbing (fixed-point scales). `core/`, `tools/`,
   `tests/` are exempt. Small literals (`0.5`, `2.0`, indices) are fine.
4. **Determinism is sacred.** INV-1..8 override everything. Same seed + same scenario ⇒
   identical FNV-1a snapshot hash. GPU determinism rests on: one PCG32 per-cell stream
   (never `curand` defaults), fixed-point **integer** accumulation for all deposits and
   stats (float `atomicAdd` is order-dependent), stable counting-sort iteration, no
   fast-math. Hash drift, NaNs in a field, or a cell escaping the chamber are **always**
   bugs — never tuned around.
5. **Headless first.** Every feature ships with a headless verification path before pixels.
   `sim/` and `fields/` link and test with no GL.
6. Diff budget ≤ 600 LOC per change unless the milestone authorises more.
7. Spec reconciliation in the same commit (contract change → update `contracts/`, the
   `MODULE.md`, `ARCHITECTURE.md`).
8. New dependency = an ADR. Allowed set: CUDA Toolkit, GLFW, GLAD, Dear ImGui. Nothing else.
9. One milestone per session; split before starting if it won't fit.
10. Never edit goldens by hand.

**The anti-drift machinery** (why this build doesn't rot): generated canon (one source for
every number), versioned contracts (module isolation), gates (kill "I think it works"),
snapshots (kill irreproducibility). Understand these four and you understand why the repo
survives being built by a different session every time.

---

## Part 6 — The hard-won wisdom (read `CONTINUATION_PROMPT.md` §4 for all 11 in full)

These are the lessons the build kept *re-learning* the expensive way. They are the most
valuable thing in the handoff. The condensed set:

1. **When a claim is about individual bodies, the grid is the wrong instrument.** P5's total
   occlusion is a fact about two discs, resolved per-cell against hash neighbours, not from a
   depth-averaged grid.
2. **Do not guess a numeric threshold — derive it.** Every scenario accept threshold traces
   to a physical value or a canon constant (the beam is `1 kW / CELL_CROSS_SECTION`; the N₂
   ramp frontier is `N/N_lethal − 1`; the flash impulse is `ΣE/c`). The scenario *parameters*
   get tuned; the *assertions* do not.
4. **A gate that PASSES while the thing is broken is worse than one that fails.** This bit us
   in M11b: `medium_temp_mean` "passed" at 361 K on a 50 %-relative-tolerance bug; the honest
   fix was `tol_absolute` plus a null (no cells → medium stays at the heated value and fails).
   Always ask what your assertion cannot see, and check a control where you can.
5. **A measured symptom is not a diagnosis.** three-percent-line's 3.25× velocity error looked
   like a metric bug; it was awake cells warming the medium and dropping viscosity. Predict,
   change, re-measure — don't pattern-match a fix.
6. **The oracle is authoritative.** If the sim disagrees with `VERIFICATION.md`, the sim is
   wrong. Do not adjust the oracle to match the sim.
9. **Match the sample — and the UNITS — to the source.** The Taumoeba divides on *dry*
   biomass, not the water-blob mass; conflating them makes a division need 2655 prey instead
   of 8 and no evolution arc can run. Currency mismatches hide as plausible physics.
11. **Look at the output.** A test or golden that passes can still *look* wrong. The app's
    `--headless` mode is a real hidden GL context, so `--screenshot out.ppm` captures the full
    frame (ImGui included); convert PPM→PNG (`python -c "from PIL import Image;
    Image.open('out.ppm').save('out.png')"`) and actually look. That is how every UI panel
    this project has was verified — you are **not blind** without a display.

---

## Part 7 — Where the build stands, in detail (`m11e-green`)

**28 tests green, 12 golden images, 10 audit checks, 34 ADRs.** Everything below is done,
gated, and tagged. The measured phenomena:

- **P1:** drift velocity linear in charge, zero crossing at 3.00577 %.
- **P2:** 2000 awake cells pin the medium at max 369.56 K; never boils.
- **P3:** ignition latch survives cooling to 20 °C.
- **P4:** motility ratio 4.357, matching the oracle.
- **P5:** adjacent collinear pair — rear cell at bitwise `0.0`; 8000 cells — charge-vs-depth
  r = −0.879.
- **Life:** doubling 1.996; 2000 → 50,508 cells bit-reproducible; the multi-rate clock and
  slot compaction close the cycle.
- **Predation + evolution:** 150 predators thin a culture, contained; under the N₂ ramp
  **Taumoeba-82.5 breeds at lineage generation 36** (budget 40); constant-N₂ control plateaus
  at 0.17.
- **Content (M11a–e):** all eight scenarios load, drive themselves, and pass their `accept`
  blocks (`headless --scenario ID --assert`, the **T24** gate). first-light ignites the
  culture; three-percent-line reproduces −52.1 / +1681 μm/s from a displacement-based velocity
  fit; komorov reaches exactly 1.5 MJ; shadow-garden r = −0.88; bloom doubles at 706k s of
  culture time; taumoeba breeds the 0.99 strain; **the spin-drive flash** empties the store and
  the impulse-per-cycle identity holds. `headless --csv` exports telemetry.
- **App:** `astrophage --scenario <id>` **auto-plays** any scenario (first-light ignites on
  screen — the medium chart plateaus at 96.35 °C). The **parameter inspector** shows all 109
  canon values with provenance badges and the canon-lock guard; unlocking a CANON value flips
  the persistent NON-CANON RUN badge. The **objective panel** grades the loaded scenario live
  (3/3 for first-light), evaluated app-side and handed to the panel as plain data.

**The eight scenarios** (`SCENARIOS.md` is the spec): `first-light` (ignition, P3/P2),
`three-percent-line` (buoyancy, P1), `komorov` (Dimitri's 1 kW laser), `shadow-garden`
(absolute shadows, P5), `bloom` (population dynamics), `taumoeba` (predation + the 82.5
problem), `spin-drive-face` (the one place the ship intrudes, at cell scale), `sandbox`.

---

## Part 8 — The road ahead

**M11f — the cell inspector + live overrides** (the immediate next task; see `NEXT_SESSION.md`):
1. `src/ui/inspector_panel.cpp`: click a cell → its state + the P1 buoyancy line. Picking =
   mouse → chamber coord via the camera → nearest cell from a positions download. The HUD
   Charge section already computes the buoyancy line — reuse it. Copy the panel idiom from
   `params_panel.cpp` and the app-side-evaluation idiom from `scenario_panel.cpp` (**`ui` may
   not include `sim`** — the app computes, the panel displays).
2. The sim reads *overridden* param values for a **curated** tunable set (`PETROVA_MAX_POWER`,
   `LIFE_DOUBLING_TIME`, …) via `World` fields the app fills from the `ParamSet` (ADR-034), so
   the inspector's sliders finally affect physics. One `World` field per curated param, the
   kernel reads it instead of `canon::`. NOT a `constexpr`→runtime refactor of everything — no
   scenario overrides a param today and it buys little. Gate: override a param, run, confirm
   the physics changed.

**Then M12 — Ship → `v1.0`:** snapshot save/load + the time scrubber, replay determinism
across a save/restore boundary, the performance pass to budget, a colourblind LUT toggle,
**Taumoeba rendering** (the app draws only Astrophage today — the predators run but are
invisible), the M7b render remainder (bloom over Petrova, the cross-fade slider, the real
T-field false-colour behind Thermal IR; pre-ignition warm-up needs `temp_cell` in the render
instance → a `render_view_v3` bump), packaging into a clean-machine `.zip`, then tag `v1.0`.

**Deferred, with reasons** (don't rediscover these): Q9 (27→8 bucket neighbour walk — the best
remaining perf lever, only worth it once a scenario stresses throughput); Q18 (a rate-based
Poisson tumble to give the run-and-tumble a refractory period); Q7/ADR-017 (six formulas
mirrored across the GLSL boundary with no compiler check — generate the GLSL from the header).
`scope` center/focal-plane are parsed but the app applies only the view mode + objective. The
CSV `git_describe` header field is a placeholder for packaging to inject.

---

## Part 9 — What to watch out for (traps that cost real time)

- **Windows paths in shell commands.** Git Bash eats backslashes in unquoted args
  (`python C:\x\y.py` arrives as `C:xy.py`). Always write Windows paths with **forward
  slashes** (`C:/x/y.py`) or quote the whole thing. This once partitioned a 58-agent swarm on
  this machine. Subagents inherit no CLAUDE.md — put the rule in their prompt if you spawn any.
- **The grid brush has a `(1−t²)²` radial falloff.** A "global" brush whose radius merely
  covers the chamber peaks at the centre and under-heats the edges — which wakes centre cells
  first (we measured 665/800). For a near-uniform fill, use a radius ~10× the chamber so the
  whole field sits in the flat top of the falloff. (The scenario driver already does this.)
- **`ui` may never include `sim`** (`ui/MODULE.md`, grep-gated). The objective panel had to be
  evaluated app-side and handed plain data. Any future panel that needs a sim computation
  follows the same pattern: the app (which links both) computes, the panel displays.
- **Awake vs dormant changes the physics you're measuring.** three-percent-line must be
  *dormant* — the canonical −52.1/+1681 μm/s are at 293 K ambient viscosity; awake cells warm
  the medium and inflate every drift ~3.4×. And a 0-charge cell that *wakes* is an unstable
  heat sink that overcools itself and starves — first-light gives its cells a small store and
  an insulated (neumann) boundary so ignition doesn't kill them.
- **`world_stats` is not free** — it runs the stage-11 reduction and ends in a synchronous
  D2H. Call it at HUD rate (~30 Hz), never every tick. Calling it per frame failed the 200k
  benchmark outright.
- **The energy ledger is honest and alarming on purpose:** the default 200k population fully
  charged holds ~72 kt TNT inside a droplet. The HUD shows it permanently. Don't "fix" it.
- **A control that silently does nothing is worse than one labelled pending.** The parameter
  inspector shows values read-only + working lock toggles, and labels value-editing as pending,
  rather than showing a slider that moves and changes nothing. Hold that line in M11f.

---

## Part 10 — The bootstrap ritual (do this, in order, every session)

1. **`git -C C:\Astrophage tag --list`** — the last `m<N>-green` tag is ground truth.
2. Read **`docs/ARCHITECTURE.md`** (always, ~6k tokens).
3. Read **only the active milestone section** of `docs/MILESTONES.md`.
4. Read the **last two entries** of `docs/SESSION_LOG.md`.
5. Load the target module's **`MODULE.md`** + only the `contracts/*.h` it uses.
6. Load `docs/PHYSICS.md` only if touching `sim/`/`fields/`; `docs/RENDERING.md` only if
   touching `render/`/`ui/`.
7. **Produce a change manifest before writing code:** files to touch, contract change (y/n),
   tests to add, rollback plan, diff budget.

**Session end ritual:** run `gate.ps1 -Milestone M<N>` (green or not); append a `SESSION_LOG.md`
entry (< 25 lines); if green, `git tag m<N>-green` and update the `README.md` status table;
rewrite `_run_state/NEXT_SESSION.md` so the next session starts cold. Writing NEXT_SESSION is
the single most valuable thing you do at the end.

---

## Part 11 — Commands

```powershell
git -C C:\Astrophage tag --list                                                    # ground truth
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -App         # build incl. the app
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit.ps1              # fast continuous check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11e   # the milestone gate
python scripts/derive.py                                                           # regenerate canon artifacts
ctest --test-dir build --output-on-failure                                         # tests only
```

Verify a scenario headlessly: `<build>/headless --scenario first-light --assert` (grades it),
`--csv out.csv` (telemetry). Watch it in the app: `<build>/astrophage --scenario first-light`,
or headless + screenshot: `astrophage --scenario first-light --headless --screenshot out.ppm
--frames 80 --ticks-per-frame 100`, then PPM→PNG and look.

**Authority:** autonomous over everything under `C:\Astrophage\` — read/write/build/run/test,
fetch GLFW/GLAD/ImGui via CMake, tune kernels, create local commits and `m<N>-green` tags.
Document in `DECISIONS.md`: new dependencies, architectural choices the spec didn't pin down,
any deviation from `PHYSICS.md`. Ask first: `git push` to a remote, anything outside
`C:\Astrophage\`, network beyond dependency fetch, spending money.

---

## Part 12 — Your first moves

1. Finish reading this. Breathe. You now know the shape of the whole thing.
2. `git tag --list` → confirm the latest is `m11e-green`. Believe it over any prose.
3. `gate.ps1 -Milestone M11e` → confirm green before you touch anything.
4. Read `_run_state/NEXT_SESSION.md` for the immediate task (M11f), then the M11f section of
   `MILESTONES.md`, ADR-034, and `src/ui/params_panel.cpp` + `src/ui/scenario_panel.cpp` as the
   patterns to copy.
5. Produce your change manifest. Then — and only then — start.

Welcome. This build is in unusually good shape because every session before you left it green,
documented, and honest. Do the same, and enjoy it — it is a genuinely beautiful little machine.
