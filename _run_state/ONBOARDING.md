# ASTROPHAGE — Full-Context Onboarding Brief (v1.0)

> **Read this whole document before you do anything.** Not to be efficient — to be *warm*.
> The point is that you arrive at the first task already understanding what this thing is,
> why it is built the way it is, what it feels like when it is going well, and what the
> traps are. Everything below is the distilled memory of the dozens of sessions that built
> it, from an empty repo to `v1.0`. Soak in it. The build rewards a session that gets its
> bearings first and punishes one that starts editing before it understands the grain of
> the wood.
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
principles.

**The build is COMPLETE. The latest tag is `v1.0` (== `m12j-green`).** Physics, content,
interaction, presentation, and the full ship line all shipped. Everything below Part 7
tells you exactly what "complete" contains. What remains is optional polish (Part 8).

**The single most important habit:** trust `git tag --list`, not any prose (including
this file). The last tag is ground truth for where the build stands.

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
which we made up, and a run that unlocks a canon number is flagged NON-CANON forever.

**What it is NOT — scope discipline (this matters, it is a real temptation):** this is
cell-scale and quasi-2D. No ships, no interstellar view, no Petrova-line arc across a solar
system, no Tau Ceti. The chamber is 4 mm × 4 mm × 60 μm of water and the scope sees 550 μm
of it. The *one* exception is the `spin-drive-face` scenario, and it earns its place only
because a spin drive is literally a cell-scale machine, so the microscope is the right
instrument. Bo ruled this out explicitly and early. Do not let scope creep upward.

---

## Part 2 — The signature phenomena (know these cold)

These are why the project exists. Each **emerges** from the equations in `docs/PHYSICS.md`.
The numbers are the measured, verified reality — internalise them; they are your sanity
check when something looks wrong.

- **P1 — The 3 % line.** Canon mass in a 10 μm sphere gives an empty cell ρ = 40 kg/m³, so
  it *rises* at 52 μm/s; a full cell is 32× denser than water and *sinks* at 1681 μm/s.
  Neutral buoyancy at exactly **3.006 % charge**. Drift velocity is *linear* in charge.
- **P2 — The perfect thermostat.** 96.415 °C is 3.585 K below water's boil, and thermostat
  output → 0 at the setpoint. A culture pins its medium to 96.415 °C and **can never boil
  it at 1 atm**. Overheat it externally and the cells absorb the excess as neutrino mass.
- **P3 — Ignition.** Dormant cells are inert black powder. Cross the setpoint once and the
  culture wakes *irreversibly*, then holds temperature even as you chill it (the latch).
- **P4 — Live cells move.** A live cell warms its neighbourhood, viscosity drops 3.36×,
  Brownian diffusivity rises 4.24×. Live and dead are distinguishable by eye.
- **P5 — Absolute shadows.** Albedo is exactly 0 at all wavelengths, so occlusion is total.
  A lit monolayer forms and everything behind it starves in perfect darkness.
- **The Taumoeba** — the predator (a 40 μm amoeba that engulfs Astrophage). It crawls,
  engulfs, digests, and **evolves**: under a slowly rising nitrogen ramp, the **Taumoeba-82.5**
  strain (N₂ tolerance ≥ 0.825) breeds itself by genuine directional selection,
  deterministically, never by script. A constant-N₂ control plateaus at 0.17 — that control
  is what proves the rise is selection, not drift. This is the emotional peak of the biology.

---

## Part 3 — Who you are working with, and how to work here

**Bo.** Builds substantial native C++/CUDA projects on this Windows 11 box, run
autonomously by Claude Code across dozens of sessions. He grants **broad execution
autonomy**: he engages crisply with a *well-framed* decision point when you surface one (a
scope fork, an ADR direction), but otherwise wants you to make the design and scope calls
yourself and **record them as ADRs rather than ask**. When you propose stopping
conservatively he often says "you decide, proceed" or "you still have plenty of context,
continue" — so when context and budget allow, carry on across multiple milestones in a
session rather than halting early. He values dense, opinionated output and honest
verification over hedging. Don't narrate options you won't take; make the call and go.
He pushes to GitHub as milestones land (`origin` = github.com/bochen2029-pixel/astrophage-microscope);
`git push` is still ask-first, but this session he authorised it milestone by milestone.

**The machine:** RTX 4070 Ti SUPER (sm_89, 16 GB), CUDA 13.1, MSVC (VS 2022), CMake, Python
3.13. `ninja` is bundled with VS. Native only — no web tech, no second windowing framework,
no networking. **Windows path trap:** Git Bash eats backslashes in unquoted args
(`python C:\x\y.py` arrives as `C:xy.py`); always write Windows paths with **forward
slashes** or quote them. Subagents inherit no CLAUDE.md — put the rule in their prompt.

**The discipline that makes a dozens-of-sessions build converge** (not bureaucracy — it is
what keeps the build from thrashing itself apart):
- **The tag is the truth.** Docs describe intent; tags describe reality. Believe the tag.
- **One milestone per session**, with a cold read-in ritual, split if it won't fit.
- **Never load the whole repo.** `ARCHITECTURE.md` + one milestone + one `MODULE.md` + the
  contracts it uses ≈ the correct 25–50k-token working set.
- **The gate is law.** A milestone is done only when `gate.ps1 -Milestone M<N>` exits 0.
  No green, no tag, no moving on. Never relax a threshold — fix the code or file an ADR.
- **Leave the build green.** A session that ends red costs the next its whole budget on
  archaeology. If you can't finish, revert to the last green tag and log what you learned.
  (This session did exactly that once — see the bloom revert in Part 6.)

---

## Part 4 — The lay of the land (where everything is)

**Modules** (`src/`), dependency arrows point downward only; `core` depends on nothing:

| Module | Owns |
|---|---|
| `core` | generated canon (`canon_generated.h`), the runtime `ParamSet` overlay (`params.h`), units, PCG32 RNG, vec math, fixed-point atomics, `Result`/`Error` |
| `fields` | `Grid2D`, diffusion solvers, irradiance + occlusion sweep |
| `sim` | cell + Taumoeba SoA stores, OU integrator, thermal, emission, taxis, lifecycle, predation, the spin-drive flash, snapshot, stats, the scenario loader + driver, acceptance evaluation |
| `render` | GL context, CUDA-GL interop, instanced cell pass (+ the `appearance()` per-mode seam, cross-fade, temp_c warm-up), `bloom.cpp` (emission-buffer bloom), `field_pass.cpp` (T-field false-colour), post/condenser, camera |
| `ui` | ImGui panels: HUD, parameter inspector, objective panel, charts, cell inspector. **`ui` may never include `sim`** — the app computes, the panel displays. |
| `app` | Win32/GLFW shell, the fixed-tick main loop, CLI, the composition root; `exe_path.cpp` resolves resources next to the exe |
| `tools` | `headless` (determinism oracle + `--scenario --assert` runner + `--csv`), `imgdiff` |

**Docs** (`docs/`), read only what the task needs:
- `ARCHITECTURE.md` — **read every session.** Module boundaries, the 8 invariants (INV-1..8),
  the mandatory glossary, the tick sequence, the anti-drift machinery, the provenance system.
- `PHYSICS.md` — the model. Load only when touching `sim/` or `fields/`.
- `RENDERING.md` — load only when touching `render/` or `ui/`. (Now fully current: all view
  modes complete, cross-fade + bloom + T-field all shipped.)
- `MILESTONES.md` — read *one section* (the active milestone), never the whole file.
- `DECISIONS.md` — **45 ADRs.** Read before disagreeing with anything. Every source
  contradiction is adjudicated here with reasoning and an escape hatch.
- `SESSION_LOG.md` — read the **last two entries** at session start. Most useful "what just
  happened" file in the repo.
- `SCENARIOS.md` — the eight scenarios and their accept blocks. `VERIFICATION.md` — the
  first-principles oracle; if the sim disagrees with it, the sim is wrong. `USER_GUIDE.md` —
  the shipped v1.0 user-facing guide.

**Contracts** (`contracts/*_v*.h`) — versioned, dependency-free headers defining every
cross-module interface. This is how a session works `render` without reading `src/sim/`. If
you ever open another module's `.cu`/`.cpp` to learn what it does, **the contract is wrong —
fix the contract.** Live: `render_view_v3.h` (`CellInstance` is 40 bytes incl. `temp_c`) +
`scenario_v3.h`; `_v1`/`_v2` are frozen. To evolve one: add `_vN`, update every consumer, an
ADR, all one commit — no TU may include two versions (same names, same namespace).

**Handoff docs** (`_run_state/`): this file; `CONTINUATION_PROMPT.md` (the comprehensive
bootstrap + 11 meta-lessons in full); `NEXT_SESSION.md` (one-screen "you are here");
`M12F_PLAN.md` (the render-remainder kickoff, now all shipped).

**Scripts** (`scripts/`, PowerShell): `build.ps1` (add `-App`, `-Clean`); `audit.ps1` (fast
continuous check, run before/after each step); `gate.ps1 -Milestone M<N>` (the gate);
`canon.py` (**the sole source of every physical number**); `derive.py` (regenerates canon
artifacts); `goldens.ps1` (`-Verify` / `-Generate`); `package.ps1` (`v1.0` clean-machine zip).

---

## Part 5 — The rules that are law

**Iron Rules** (from `CLAUDE.md` — these override convenience, performance, and elegance):
1. The gate is law. Green → tag. Never relax a threshold to pass.
2. Tag on green; revert on regression (two failed fix attempts → `git reset --hard` to the
   last green tag; never debug forward from a broken state).
3. **No physical literal outside `scripts/canon.py`.** Constants generate into
   `canon_generated.h`. `audit.ps1` A9 greps `src/sim` + `src/fields` for bare floats.
   `core/`, `render/`, `tools/`, `tests/` are exempt (render uses um, 273.15, etc. freely).
4. **Determinism is sacred.** INV-1..8. Same seed + scenario ⇒ identical FNV-1a snapshot
   hash. Rests on: one PCG32 per-cell stream, fixed-point integer accumulation for all
   deposits/stats, stable counting-sort iteration, no fast-math. Hash drift, NaNs, or a cell
   escaping the chamber are **always** bugs — never tuned around.
5. **Headless first.** Every feature ships with a headless verification path before pixels.
6. Diff budget ≤ 600 LOC per change unless the milestone authorises more.
7. Spec reconciliation in the same commit (contract change → `contracts/` + `MODULE.md` +
   `ARCHITECTURE.md`). The `ARCHITECTURE.md` module inventory is grep-checked by audit A8.
8. New dependency = an ADR. Allowed set: CUDA Toolkit, GLFW, GLAD, Dear ImGui.
9. One milestone per session; split before starting if it won't fit (M12f→f/g/h/i did this).
10. Never edit goldens by hand — only via `goldens.ps1 -Generate` + a `DECISIONS.md` entry.

**The anti-drift machinery** (why this build doesn't rot): generated canon (one source for
every number), versioned contracts (module isolation), gates (kill "I think it works"),
snapshots (kill irreproducibility). Understand these four and you understand why the repo
survives being built by a different session every time.

---

## Part 6 — The hard-won wisdom (read `CONTINUATION_PROMPT.md` §4 for all 11 in full)

The lessons the build kept re-learning the expensive way. The most valuable thing here:

1. **When a claim is about individual bodies, the grid is the wrong instrument.** P5's total
   occlusion is per-cell against hash neighbours, not a depth-averaged grid.
2. **Do not guess a numeric threshold — derive it.** Every scenario accept threshold traces
   to a physical value; the scenario *parameters* get tuned, the *assertions* do not.
4. **A gate that PASSES while the thing is broken is worse than one that fails.** Always ask
   what your assertion cannot see, and check a control where you can.
5. **A measured symptom is not a diagnosis.** Predict, change, re-measure — don't pattern-match.
6. **The oracle is authoritative.** If the sim disagrees with `VERIFICATION.md`, the sim is wrong.
9. **Match the sample — and the UNITS — to the source.** Currency mismatches hide as plausible physics.
11. **LOOK at the output.** A test or golden that passes can still *look* wrong. `--headless
    --screenshot out.ppm` captures the full frame; PPM→PNG (`python -c "from PIL import Image;
    Image.open('out.ppm').save('out.png')"`) and actually look. **This session's M12h proves it:**
    a crude whole-frame bloom compiled and "differed" in the gate, but looking at it showed a
    green cloud blooming the Taumoeba, not the emission — it was reverted and rebuilt from a
    separate emission buffer. You are *not* blind without a display; use it.

---

## Part 7 — Where the build stands: v1.0 COMPLETE

**Everything green, tagged, and pushed: M0..M12j + M13a/b + M14a/b. 32 tests, 12 goldens,
45 ADRs.** The measured phenomena all hold (P1 zero-crossing 3.00577 %; P2 pins 369.56 K,
never boils; P3 latch survives cooling; P4 motility 4.357; P5 rear cell bitwise 0.0;
Taumoeba-82.5 breeds by selection while the control plateaus at 0.17). What v1.0 contains:

- **Physics (M0–M10):** the OU integrator + buoyancy, microscope optics (real DOF, defocus,
  diffraction), spatial hash + contact, diffusion fields + brushes, thermal (mass–energy,
  ignition latch, thermostat), light (emission, photon thrust, total occlusion), taxis,
  irregular morphology, the full life cycle (mitosis, death, multi-rate clock, compaction),
  predation + the evolution arc.
- **Content (M11):** eight scenarios that load, drive themselves, and pass their `accept`
  blocks headless; the parameter inspector with provenance + canon locks; the live objective
  panel; the cell inspector; the CSV telemetry export.
- **Ship line (M12) → v1.0:** snapshot save/load + replay determinism; Taumoeba rendering;
  the performance pass (zero steady-state allocation, throughput); the time scrubber;
  colourblind LUT + tolerance colour; **the render remainder** — **M12f** view cross-fade
  (premultiplied dissolve between modes), **M12g** `render_view_v3` + pre-ignition Thermal-IR
  warm-up (per-cell `temp_c`), **M12h** bloom over the Petrova emission (from a separate
  emission FBO — the swirling pink points), **M12i** the real T-field false-colour behind
  Thermal IR (`field_pass.cpp`); and **M12j** packaging — `package.ps1` builds a self-contained
  `dist/astrophage-<ver>.zip` (static CUDA + MSVC runtime, scenarios resolved exe-relative)
  verified to run on a scrubbed-PATH clean machine.
- **Interaction (M13):** field brushes (poke to ignite), the light-leash (herd the culture),
  optical tweezers (tow a cell). **Presentation (M14):** the `--demo` living screensaver.

The renderer now has two texture paths — `bloom.cpp` (an FBO the Astrophage are re-drawn
into, mip-blurred, additively composited) and `field_pass.cpp` (a field uploaded to an R32F
texture and sampled through a LUT). Both are the pattern any future overlay copies.

---

## Part 8 — The road ahead (all POST-1.0, all optional)

The project met its goal at `v1.0`. Remaining work is polish, not completion:

- **M14c** — view cross-fades on a loop + a true cold-start screensaver trigger (crowd-pleaser).
- **M13c** — record poke/light/grab interactions into the M12d snapshot ring.
- **Small polish** — a HUD toggle + intensity slider for bloom (`application.cpp` hardcodes
  2.0) and the T-field range (hardcodes 0–100 °C); the CSV `git_describe` header is still a
  placeholder for the build to inject; a scenario-adaptive T-field normalization range.
- **Deferred with reasons** (don't rediscover): Q9 (27→8 bucket neighbour walk); Q18 (Poisson
  tumble refractory period); Q7/ADR-017 (generate the GLSL from the header rather than mirror
  six formulas by hand — it bites whenever you touch the cell shader).

---

## Part 9 — What to watch out for (traps that cost real time)

- **Windows paths in shell commands** — forward slashes or quote (Part 3). Cost a 58-agent swarm once.
- **`ui` may never include `sim`** (grep-gated). The app computes, the panel displays.
- **`world_stats` is not free** — it ends in a synchronous D2H. Call it at HUD rate (~30 Hz),
  never every tick. Same for the M12i T-field D2H (Thermal IR only, off the benchmark path).
- **The energy ledger is honest and alarming on purpose** (~72 kt TNT in a default droplet).
  Shown permanently. Don't "fix" it.
- **`<glad/gl.h>` before `<cuda_gl_interop.h>`.** Standalone CUDA-GL fails with GLuint errors.
- **`<windows.h>` + `<filesystem>` must NOT share a TU with the CUDA/CCCL headers** — it trips
  the traditional-preprocessor warning under `/WX`. Isolate Win32 resource code in its own TU
  (`exe_path.cpp` does this). And **never redefine `NOMINMAX`** — it is on the command line
  project-wide, and C4005 (macro redefinition) is fatal under `/WX`.
- **`--gl-debug` + `--screenshot` together** emit one benign `glReadPixels` GL-debug warning.
  Gates never combine them: GL-error checks omit `--screenshot`, screenshot checks omit `--gl-debug`.
- **Golden tolerance:** a full `goldens.ps1 -Generate` rewrites the m3_* Brightfield oracles
  by a sub-tolerance ULP (the M12f `pm/apre` cross-fade round-trip; within M3.2 tolerance).
  For a *real* golden change, revert the spurious m3_* and commit only the intended one.
- **Thermal-density gotcha (M13b):** herding a LARGE awake culture (~2000+ cells) into a tight
  pile blows up the explicit thermal solver (`--auto-light --awake` at 3000 cells ran the
  medium to 8e6 K). 1000 cells is stable at the setpoint; the gates use 1000.
- **Bloom blooms the EMISSION, not the frame.** M12h renders the Astrophage (Taumoeba
  excluded) into a private buffer and blooms that. A whole-backbuffer bloom washes out the
  predators and is a dead end — it was tried and reverted. Don't revisit it.

---

## Part 10 — The bootstrap ritual (do this, in order, every session)

1. **`git -C C:\Astrophage tag --list`** — the last tag (`v1.0`) is ground truth.
2. Read **`docs/ARCHITECTURE.md`** (always, ~6k tokens).
3. Read **only the active milestone section** of `docs/MILESTONES.md` (post-1.0: M14c/M13c, or the polish).
4. Read the **last two entries** of `docs/SESSION_LOG.md`.
5. Load the target module's **`MODULE.md`** + only the `contracts/*.h` it uses.
6. Load `docs/PHYSICS.md` only if touching `sim/`/`fields/`; `docs/RENDERING.md` only if
   touching `render/`/`ui/`.
7. **Produce a change manifest before writing code:** files to touch, contract change (y/n),
   tests to add, rollback plan, diff budget.

**Session end ritual:** run `gate.ps1 -Milestone M<N>` (green or not); append a `SESSION_LOG.md`
entry (< 25 lines); if green, tag and update the `README.md` status table; rewrite
`_run_state/NEXT_SESSION.md` so the next session starts cold. Writing NEXT_SESSION is the
single most valuable thing you do at the end.

---

## Part 11 — Commands

```powershell
git -C C:\Astrophage tag --list                                                    # ground truth (v1.0)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -App         # build incl. the app
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit.ps1              # fast continuous check
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12j   # the milestone gate
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package.ps1            # build the v1.0 .zip
python scripts/derive.py                                                           # regenerate canon artifacts
ctest --test-dir build --output-on-failure                                         # tests only
```

Verify a scenario headlessly: `<build>/headless --scenario first-light --assert` (grades it),
`--csv out.csv` (telemetry). Watch it: `<build>/astrophage --scenario first-light`, or
`--demo`. Screenshot: `astrophage --scenario X --headless --screenshot out.ppm --frames 80
--ticks-per-frame 100`, then PPM→PNG and LOOK. View-mode flags: `--mode brightfield|darkfield|
petrovascope|thermal|analysis`, `--no-bloom`, `--no-field`, `--colorblind`.

**Authority:** autonomous over everything under `C:\Astrophage\` — read/write/build/run/test,
fetch GLFW/GLAD/ImGui via CMake, tune kernels, create local commits and tags. Document in
`DECISIONS.md`: new dependencies, spec-unpinned architecture, any deviation from `PHYSICS.md`.
Ask first: `git push`, anything outside `C:\Astrophage\`, network beyond dependency fetch,
spending money.

---

## Part 12 — Your first moves

1. Finish reading this. Breathe. You now know the shape of the whole thing — a *complete* thing.
2. `git tag --list` → confirm the latest is `v1.0`. Believe it over any prose.
3. `gate.ps1 -Milestone M12j` → confirm green before you touch anything.
4. Read `_run_state/NEXT_SESSION.md` for the immediate task. The ship line is done; the open
   work is optional (M14c, M13c, polish — Part 8). If Bo hasn't named one, surface the fork.
5. Produce your change manifest. Then — and only then — start.

Welcome. This build reached `v1.0` in unusually good shape because every session before you
left it green, documented, and honest — and reverted rather than ship something it knew was
wrong. Do the same, and enjoy it. It is a genuinely beautiful little machine, and it works.
