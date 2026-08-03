# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Predation is complete (M10a + M10b).** The next milestone is **M11 — Content**, a
> different kind of work: scenario loading, inspector/instrument UI, and telemetry export,
> not new physics. There is no dedicated M11 kickoff file;
> [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md) is the standing handoff (its §4 has the
> eleven meta-lessons in full — read them). This file is the terse status.

---

## Where the build stands

**Last green: `m10b-green`. Next milestone: M11 — Content.**

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

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M11 section only** of `docs/MILESTONES.md` → **`docs/SCENARIOS.md`** (the eight scenarios and their accept blocks) → `contracts/scenario_v1.h` + `contracts/telemetry_v1.h` → `src/ui/MODULE.md` and `src/app/MODULE.md` → the last two `SESSION_LOG.md` entries.

## What M11 is

**Content — the milestone that turns the engine into an instrument.** No new physics.

1. **Scenario loader + schema.** A JSON loader validating against `contracts/scenario_v1.h`; all **eight** scenarios from `SCENARIOS.md`, each with its `accept` block (the acceptance-metric vocabulary is already in `telemetry_v1.h` — `Metric`, `AcceptCheck`). New dependency (a JSON parser) needs an ADR (Iron Rule 8); a hand-rolled parser avoids one — decide and record.
2. **The headless runner executes every `accept` block (T24) — this is the gate.** `tools/headless.cpp` already runs scenarios by name; wire the accept evaluation so `--scenario <name> --assert` exits nonzero on a missed metric. `gate.ps1` M11.1 already loops every `scenarios/*.json`.
3. **The parameter inspector** with provenance badges (the `PARAM_TABLE` in `canon_generated.h` already carries `CANON`/`DERIVED`/`REAL`/`INVENTED` + tunable ranges): **every CANON parameter is locked by default; unlocking sets the persistent `NON-CANON RUN` flag** in both the HUD and the telemetry header (`Stats.non_canon_run` is already declared). `test_param_locks` is the M11.2 gate.
4. **The cell inspector** (click a cell → its state, including the buoyancy readout that teaches P1), instrument panels, and **CSV telemetry export**.

**Gate.** M10b gate + T24 (every scenario passes its accept block) + canon locks default-on with the non-canon flag.

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
