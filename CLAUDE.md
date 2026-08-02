# CLAUDE.md — Astrophage Microscope Simulator (`C:\Astrophage`)

A physics-based, GPU-accelerated simulation of **Astrophage** (Andy Weir, *Project Hail Mary*) seen **through a microscope**. Quasi-2D culture chamber, 10 μm cells, real Stokes/Langevin/diffusion physics, canon-locked constants. Native Windows, C++20 + CUDA 13.1, OpenGL 4.6 interop, Dear ImGui. Built autonomously, milestone by milestone, with machine-checkable gates.

**This is a simulator and visualization, not a game.** No win state, no story mode, no asset files — everything is procedural or generated.

---

## Session start ritual — do this every session, in this order

This project spans dozens of sessions. **Context discipline is the difference between a build that converges and one that thrashes.** Never load the whole repo.

1. **`git tag --list`** — the last `m<N>-green` tag is the ground truth for where the build stands. Not a doc. Not a log. The tag.
2. Read **`docs/ARCHITECTURE.md`** (canon: module map, invariants, data flow, glossary). ~6k tokens. Always.
3. Read **only the active milestone section** of `docs/MILESTONES.md`. Not the whole file.
4. Read the **last two entries** of `docs/SESSION_LOG.md`. Not the whole file.
5. Load the target module's **`src/<module>/MODULE.md`** plus **only the `contracts/*.h` it uses**. Do not read another module's source to understand its interface — that is what contracts are for. If you find yourself needing to, the contract is wrong: fix the contract.
6. Load **`docs/PHYSICS.md`** only if touching `sim/` or `fields/`. Load **`docs/RENDERING.md`** only if touching `render/` or `ui/`.
7. **Produce a change manifest before writing code**: files to touch, contract changes (y/n), tests to add, rollback plan, diff budget.

A correct session loads roughly 25–50k tokens of documentation and spends the rest on code. If you are at 200k tokens of docs, you have loaded the wrong things.

## Session end ritual

1. Run `scripts/gate.ps1 -Milestone M<N>`. Green or not, run it.
2. Append a **`docs/SESSION_LOG.md`** entry: milestone, what landed, what is pending, open questions, gotchas. Keep it under 25 lines.
3. If green: `git tag m<N>-green`, and update the status table in `README.md`.
4. Rewrite **`_run_state/NEXT_SESSION.md`** so the next session can start cold. This is the single most valuable thing you do at the end of a session.

## Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1              # incremental build
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Clean       # clean reconfigure + build
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit.ps1              # fast continuous check (run pre- and post-step)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M2 # milestone completion gate
ctest --test-dir build --output-on-failure                                         # tests only
python scripts/derive.py                                                           # regenerate canon artifacts
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/goldens.ps1 -Verify    # golden images
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/goldens.ps1 -Generate  # regenerate (needs an ADR)
```

Add `-App` to `build.ps1` whenever the executable matters; the plain form configures with `ASTRO_BUILD_APP=OFF` so the core and tests build with no network and no dependencies.

## Iron Rules

1. **The gate is law.** A milestone is done only when `gate.ps1 -Milestone M<N>` exits 0. No green, no tag, no moving on. Never relax a threshold to pass — fix the code or file an ADR.
2. **Tag on green; revert on regression.** Green gate → `git tag m<N>-green`. If a change breaks an earlier gate and two fix attempts fail, `git reset --hard` to the last green tag and re-approach. Never debug forward from a broken state.
3. **No physical literal outside `scripts/canon.py`.** Every constant is generated into `src/core/canon_generated.h`. `audit.ps1` greps for bare floats in `src/sim` and `src/fields` and fails. If you need a new number, add it to `canon.py` with a provenance tag and re-run `derive.py`.
4. **Determinism is sacred.** INV-1..INV-8 in `docs/ARCHITECTURE.md` §4 override convenience, performance, and elegance. Same seed + same scenario ⇒ same snapshot hash.
5. **Headless first.** Every feature ships with a headless verification path (a test, a telemetry assertion, a snapshot hash) *before* it gets pixels. `sim/` and `fields/` link and test with no GL, no window, no ImGui — CI greps for it.
6. **Diff budget ≤ 600 LOC per change** unless the milestone scope authorizes more. No "while I'm here" refactors, no new features outside the manifest.
7. **Spec reconciliation in the same commit.** Change a contract or a module boundary → update `contracts/`, the relevant `MODULE.md`, and `ARCHITECTURE.md` in that same commit. The module inventory in `ARCHITECTURE.md` must match the directory listing (audit-checked).
8. **New dependency = an ADR** in `docs/DECISIONS.md`. Current allowed set: CUDA Toolkit, GLFW, GLAD, Dear ImGui. Nothing else without an entry.
9. **One milestone per session.** If a milestone will not fit, split it (`M5a`, `M5b`) in `MILESTONES.md` *before* starting, and give each half its own gate.
10. **Never edit `goldens/` or `tests/golden/` by hand.** Goldens change only via `tools/goldgen` or `scripts/derive.py`, plus a `DECISIONS.md` entry in the same commit.

## Module map

Dependency arrows point downward only. **`core` depends on nothing.**

| Module | Owns | May include |
|---|---|---|
| `src/core` | generated canon, units, PCG32 RNG, vec math, fixed-point atomics, error type | nothing but the C++/CUDA standard library |
| `src/fields` | Grid2D, diffusion solvers, irradiance + occlusion sweep | `core` |
| `src/sim` | cell/taumoeba stores, OU integrator, thermal, emission, taxis, lifecycle, predation, snapshot | `core`, `fields` |
| `src/render` | GL context, CUDA-GL interop, instanced cell pass, optics, LUTs, bloom | `core`, `contracts` |
| `src/ui` | ImGui panels: instruments, inspector, parameter table, charts | `core`, `contracts` |
| `src/app` | Win32/GLFW shell, main loop, composition root, CLI flags | everything |
| `tools` | headless runner, goldgen, telemetry dump | `core`, `sim`, `fields` |

Details live in each module's `MODULE.md`. Interfaces live in `contracts/`.

## Code standards

- C++20 (MSVC), CUDA 17 device code, warnings-as-errors. Target `sm_89` (RTX 4070 Ti SUPER).
- `snake_case` for variables and functions, `PascalCase` for types, `SCREAMING_CASE` for constants.
- Files: `*.cpp/*.h` host, `*.cu/*.cuh` device. One translation unit per concern.
- **SI units everywhere in `core`/`sim`/`fields`.** Metres, kilograms, seconds, kelvin, joules, watts. Display units (μm, °C, ng, mW) exist only in `ui/` and `render/`.
- Errors cross module boundaries as typed results, never exceptions. No globals outside the `app` composition root.
- Comments are load-bearing only; prefer explaining *why*. Physics code cites `docs/PHYSICS.md` by section number.
- Glossary terms in `ARCHITECTURE.md` §2 are mandatory. Forbidden synonyms (particle, agent, world, box, energy level…) fail review.
- No emojis in code or commit messages.

## Verification etiquette

- **Run `scripts/audit.ps1` before and after each step.** It is the fast oracle: build with `/WX`, ctest, canon-artifact freshness (`derive.py --check`), determinism replay hash, module-inventory match, and the `sim`-has-no-GL isolation grep. Append the one-line verdict to `docs/CHANGE_AUDIT_LOG.md`.
- `gate.ps1` is the milestone gate; `audit.ps1` is the continuous check between gates.
- **Never self-assert "done."** Let an oracle say so. "It should work" is not a verification result.
- Physics disagreements are resolved by `docs/VERIFICATION.md`, which is generated from first principles independently of the simulator. If the sim disagrees with the oracle, the sim is wrong — do not adjust the oracle.
- Determinism hash drift, NaNs in a field, or cells escaping the chamber are **always** bugs. Never tune around them.

## What NOT to do

No game mechanics or objectives beyond scenario acceptance checks. No interstellar/solar-system/spacecraft scale — this is a microscope (the one exception is the `spin-drive-face` scenario, which is cell-scale by nature). No asset files. No web/browser tech. No Vulkan, no D3D, no second windowing framework. No networking. No `-use_fast_math` in `sim`/`fields`. No skipping the change manifest. No loading the entire repo into context.

## Authority

**Autonomous:** read/write/delete anything under `C:\Astrophage\`; configure and build; run the executable and tests locally; fetch GLFW/GLAD/ImGui via CMake FetchContent; profile with Nsight; tune kernels; create local git commits and `m<N>-green` tags.

**Document in `docs/DECISIONS.md`:** new dependencies; architectural choices the spec did not pin down; any deviation from `PHYSICS.md`.

**Ask first:** `git push` to any remote; anything outside `C:\Astrophage\`; network access beyond dependency fetch; Windows settings or registry; spending money.
