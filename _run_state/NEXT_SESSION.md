# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Predation is complete (M10a + M10b); the scenario spine is in (M11a).** The next
> milestone is **M11b — Content: acceptance, driving, and the physics scenarios**. M11 was
> split into M11a/M11b/M11c (Iron Rule 9). M11a built the spine: scenarios load, instantiate,
> and run. M11b makes them *pass their objectives*. See the M11 section of
> `docs/MILESTONES.md` and **ADR-031** (the scenario-loader decisions).
> [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md) is the standing handoff (its §4 has the
> eleven meta-lessons — read them).

---

## Where the build stands

**Last green: `m11a-green`. Next milestone: M11b — Content: acceptance + driving + physics scenarios.**

**All five phenomena live. Cells behave, divide, die, run on a multi-rate clock; all five view modes draw distinctly; the Taumoeba predator crawls, engulfs, and evolves; and scenarios load, instantiate, and run.** 24 tests green, 12 goldens, 10 audit checks, 31 ADRs.

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
| **M11a** | all 8 scenarios load + instantiate + run bit-reproducibly (`test_scenario`); `headless --scenario ID` runs; populations match the spec exactly |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11a
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M11 section only** of `docs/MILESTONES.md` (M11b) → **`docs/SCENARIOS.md`** (the eight scenarios and their accept blocks — this is the spec you make pass) → **ADR-031** (the M11a decisions) → `src/sim/scenario.{h,cpp}` + `src/sim/json.h` (the spine you extend) → `contracts/telemetry_v1.h` (`Metric`, `AcceptCheck`) → `tools/headless.cpp` (the `--scenario` runner).

## What M11b is — acceptance, driving, and the physics scenarios

**M11a built the spine** (scenarios load, instantiate, run — `test_scenario` green). M11b makes each scenario **pass its `accept` block** (the full T24 gate). Three pieces, and two of them are ADRs to settle *before* coding:

1. **The accept-evaluation framework + the `--assert` runner.** `AcceptCheck` + measured metrics → pass/fail; `headless --scenario ID --assert` exits nonzero on a missed metric. The vocabulary (`Metric`, `CompareOp`) is in `telemetry_v1.h`. The `Metric`-name→enum map already exists in `scenario.cpp`.
2. **Scenario *driving* (an ADR).** first-light needs the heat brush applied; taumoeba needs the N₂ ramp. The schema has `tools` (availability) but no scripted *events*. Add a minimal scripted-stimulus list — almost certainly a **`scenario_v2` bump** (the current struct is frozen `v1`) — that the runner applies at the right ticks. This is the crux of M11b.
3. **The derived metrics (from full state, not just `Stats`) + the spin-drive flash.** `RiseVelocityEmpty`/`FallVelocityFull` (three-percent-line), `ChargeDepthCorrelation` (shadow-garden), `ChargeHeightCorrelation`, `DoublingTimeS` (bloom), `ImpulsePerCycle` (spin-drive-face). The **spin-drive flash** — an external high-intensity `PETROVA_WAVELENGTH` pulse forcing full-rate discharge (PHYSICS.md §6) — is **new physics**, its own ADR. `test_evolution` already proves the taumoeba arc, so wiring its accept is mostly reuse.

**Gate (`gate.ps1 -Milestone M11b`, already wired):** M11a gate + **T24 — every `scenarios/*.json` passes `headless --scenario <id> --assert`.** Tune each scenario's parameters + accept thresholds until it lands (the M10b arc is the model for this empirical loop); the thresholds must trace to a physical value or a canon constant, not a magic number (meta-lesson 2).

**M11c** is then the parameter inspector + canon locks (`test_param_locks`, `non_canon_run`), the cell inspector, the objective panel, and CSV export — and the runtime-param system that lets `param_overrides` actually apply.

## What already exists that M11b builds on

- **The spine (M11a):** `scenario_load`/`scenario_parse`/`scenario_instantiate` in `src/sim/scenario.{h,cpp}`, the jsonc reader in `src/sim/json.h`, all 8 `scenarios/*.json` (accept blocks already parsed into the struct), and `headless --scenario ID`. The scenarios load by `ASTRO_SCENARIOS_DIR` (a compile define).

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
