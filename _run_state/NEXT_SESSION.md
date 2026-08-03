# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Predation is complete (M10a + M10b).** The next milestone is **M11a — Content: the
> scenario spine** (the JSON loader, world instantiation, accept evaluation, headless
> runner). M11 was **split into M11a/M11b/M11c** (Iron Rule 9) because it bundled a whole
> greenfield scenario/JSON system, a set of *derived* accept metrics plus one bit of new
> physics (the spin-drive flash), and an entire inspector/telemetry UI — three sessions.
> See the M11 section of `docs/MILESTONES.md`. [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> is the standing handoff (its §4 has the eleven meta-lessons — read them).

---

## Where the build stands

**Last green: `m10b-green`. Next milestone: M11a — Content: the scenario spine.**

**All five phenomena live. Cells behave, divide, die, run on a multi-rate clock; all five view modes draw distinctly; the Taumoeba predator crawls, engulfs, and now EVOLVES.** 23 tests green, 12 goldens, 10 audit checks, 30 ADRs.

| | measured |
|---|---|
| **P1** | drift velocity linear in charge, zero crossing at 3.00577 % |
| **P2** | 2000 awake cells pin the medium at max 369.56 K; never boils |
| **P3** | ignition latch survives cooling to 20 °C |
| **P4** | motility ratio 4.357, matching the oracle |
| **P5** | adjacent collinear pair: rear cell at bitwise `0.0`; 8000 cells: charge-vs-depth r = −0.879 |
| **M8** | migration **26.0σ**; darkness bit-identical to the taxis-off null |
| **M9a/b** | doubling **1.996**; 2,000 → 50,508 bit-reproducible (T22); void corpses 40.1 kg/m³ |
| **M9c** | clock ratios exact (physics 10.0000, biology 2.00000, compounding 1.00000); compaction T22b 914 deaths reclaimed, hash `42d459c3` |
| **M7b** | Thermal vs Petrovascope mean 34.1 / max 252 — live idle cell dark in IR, invisible in Petrovascope |
| **M10a** | T30 bit-reproducible (`5301212a`); 150 predators thin 6,000 → 5,898, all contained |
| **M10b** | T31 evolution run bit-reproducible; **Taumoeba-82.5 at lineage generation 36** (budget 40) by directional selection; constant-N₂ control plateaus at max tol **0.17** |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M10b
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M11 section only** of `docs/MILESTONES.md` (M11a/M11b/M11c) → **`docs/SCENARIOS.md`** (the eight scenarios and their accept blocks) → `contracts/scenario_v1.h` + `contracts/telemetry_v1.h` → `tools/headless.cpp` (the runner, currently a `--scenario` stub) → `src/app/cli.cpp` and `src/app/MODULE.md`.

## What M11a is — the scenario spine (headless), and the two decisions it must make

**The whole scenario system is a stub today** — `tools/headless.cpp` prints "scenario running arrives in M11" and returns. `contracts/scenario_v1.h` (the `Scenario` struct) is frozen and ready; nothing loads, instantiates, or evaluates it.

**M11a builds the spine:** a JSON loader → `Scenario`; **scenario → world instantiation** (populations, fields, lights, clock, boundaries, param overrides → a `WorldDesc` + spawns); the **accept-evaluation framework** (`AcceptCheck` + `Stats` → pass/fail, vocab already in `telemetry_v1.h`); and the `headless --scenario ID --assert` runner. Only the scenarios that clear with existing `Stats` metrics: **first-light**, **bloom**, **taumoeba** (its accept *is* `test_evolution`'s), **sandbox** (no accept).

**Two design decisions, each an ADR (resolve these BEFORE coding — they shape everything):**
1. **How does a headless run *drive* an interactive scenario?** first-light starts cold and dormant; its accept ("all awake within 5 s of crossing the setpoint") needs the heat brush applied. The schema has `tools` (what's *available*) but no scripted *events*. Either add a minimal scripted-stimulus list to the scenario schema (a `_v2` bump) or restrict headless accept to self-driving scenarios and drive the rest only in the UI. This is the crux of M11a.
2. **Hand-roll the JSON parser (no dependency, no ADR) or take one (ADR, Iron Rule 8).** A hand-rolled recursive-descent parser for this fixed schema is ~200 LOC and avoids the dependency — likely the right call, but decide and record.

**Gate (`gate.ps1 -Milestone M11a`, already wired):** M10b gate + `test_scenario` (every scenario JSON loads + instantiates deterministically) + `headless --scenario <id> --assert` green for first-light, bloom, taumoeba.

**M11b** then adds the derived metrics (velocities, correlations, doubling-time, impulse) + the **spin-drive flash** (new physics, own ADR) + the remaining four scenarios (the full T24). **M11c** is the inspector/canon-lock/cell-inspector/CSV-export UI.

## What already exists that M11 builds on

- **`contracts/scenario_v1.h`** defines the scenario struct; **`contracts/telemetry_v1.h`** defines `Stats`, the `Metric` enum, `AcceptCheck`, `CompareOp`, and `non_canon_run` — the acceptance vocabulary is frozen and shared by the UI and headless runner *by design* (a scenario cannot rot).
- **`world_stats`** returns a `contract::Stats` at HUD rate (fixed-point reductions, INV-2). M11 reads it; it does not add device work.
- **The provenance system** (`ARCHITECTURE.md §6`): `PARAM_TABLE` carries every parameter's tag and tunable range straight from `canon.py`. The inspector is a view onto it.
- **The multi-rate clock** (`world_set_clock`, presets) is wired; scenarios select a preset.
- **`WorldDesc`** already carries chamber, capacity, seed, `MotionConfig`, `co2_init` — scenarios populate it. `MotionConfig` now also has `tau_compaction_enabled` (M10b).

## The meta-lessons this build keeps re-learning (full text: CONTINUATION_PROMPT.md §4)

- **A gate that PASSES while the thing is broken is worse than one that fails.** For scenarios: assert the *metric the scenario is about*, and check a control/null where you can. Ask what the assertion cannot see.
- **Do not guess a threshold — derive it, or invent nothing.** Scenario accept thresholds should trace to a physical value or a canon constant, not a magic number.
- **A measured symptom is not a diagnosis.** Predict, change, re-measure.
- **Correctness tests cannot see performance** — the 200k benchmark (M1.5) is the guard. Loading scenarios must not add per-tick host traffic.
- **Look at the output.** A scenario that "passes" headless can still look wrong; run the app (`build/astrophage.exe --scenario <name>`) and watch it.

## Deferred, with reasons

- **M7b render remainder** — bloom over Petrova (the swirling pink points), the cross-fade mode slider, the real T-field false-colour behind Thermal IR. The one piece needing a contract change: **pre-ignition warm-up** of a heated dormant cell needs `temp_cell` in the render instance → `render_view_v3`. Fits M12.
- **Q9 / the 27→8 bucket neighbour walk** (`cell_size` 22 μm ≥ 2× range). Best remaining perf lever; used by contact, occlusion, and Taumoeba prey-sensing. A pure win once a scenario stresses throughput.
- **Q18 — no refractory period in the tumble rule** (3.6 % of cells on a real run); fix is a rate-based Poisson tumble. The Taumoeba crawl reuses the same rule, so it inherits this.
- **Q7 / ADR-017** — six formulas mirrored across the GLSL boundary with no compiler check. Generate the GLSL from the header.
- **Q14** — dormant cells charge; light-driven ignition is the canon-consistent alternative; own ADR. **Q15** — instantaneous re-aim (26.0σ is an upper bound).
- **Test-suite cost** — `ctest` ~4–6 min (`test_evolution` adds ~18 s of a real breeding run). Kept deliberately.
- After M11: **M12 Ship** — snapshot/replay, the perf pass, packaging, the M7b render remainder, `v1.0`.
