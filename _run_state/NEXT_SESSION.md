# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Content is complete through acceptance (M11a + M11b).** The eight scenarios now load,
> drive themselves, and **pass their objectives** — `headless --scenario <id> --assert` is
> green for all eight (T24). The next milestone is **M11c — the inspector and telemetry
> UI**: the parameter inspector with provenance badges + canon locks, the cell inspector,
> the objective/acceptance panel, and CSV telemetry export. See the M11 section of
> `docs/MILESTONES.md` (M11c) and **ADR-032/033** (the M11b decisions).
> [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md) is the standing handoff (its §4 has the
> meta-lessons — read them).

---

## Where the build stands

**Last green: `m11b-green`. Next milestone: M11c — the inspector + telemetry UI.**

**All content is live: the eight scenarios load, drive, and pass their accept blocks.**
25 tests green, 12 goldens, 10 audit checks, 33 ADRs.

| | measured |
|---|---|
| **M11a** | all 8 scenarios load + instantiate + run bit-reproducibly (`test_scenario`) |
| **M11b** | **all 8 pass `--assert` (T24)**: three-percent-line −52.1/+1681 μm/s + r=−0.82; komorov 1.5 MJ; shadow-garden r=−0.88; first-light awake=1, medium 369.2 K, no boil; bloom doubling 706k s; taumoeba max-tol 0.99; spin-drive impulse/cycle 1.0, fully discharged |
| **M10b** | Taumoeba-82.5 by directional selection; constant-N₂ control plateaus at 0.17 |
| **P1–P5** | all five phenomena live and asserted through the scenarios |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11b
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` (esp. §6 the provenance system) → **the M11 section only** of `docs/MILESTONES.md` (M11c) → **ADR-032/033** (the M11b decisions) → `src/core/canon_generated.h`'s `PARAM_TABLE` (the inspector reads it) → `src/ui/MODULE.md` + `contracts/telemetry_v1.h` (`Stats.non_canon_run`) + the existing `src/ui/*_panel.cpp`.

## What M11c is — the inspector and telemetry UI

**M11b made the content pass headless; M11c gives it pixels and controls.** Four pieces,
gated on `test_param_locks` + the M11b gate:

1. **The parameter inspector** with provenance badges from `PARAM_TABLE` (`CANON` gold/locked,
   `DERIVED` blue/read-only, `REAL` grey, `INVENTED` orange). **Every `CANON` parameter
   locked by default; unlocking sets the persistent `NON-CANON RUN` flag** (`Stats.non_canon_run`)
   in the HUD and the telemetry header. This is `test_param_locks` (the gate) and needs the
   **runtime-parameter system** — canon is `constexpr`, so a param override is not expressible
   today (ADR-031 §3). That system is the crux of M11c; it is also what makes `param_overrides`
   (parsed since M11a) finally apply.
2. **The cell inspector** — click a cell → its state, including the buoyancy readout that
   teaches P1 (drift velocity vs charge, zero crossing at 3.006 %).
3. **The objective/acceptance panel** — the accept checkmarks. The vocabulary is already
   frozen and shared: `sim/accept.cpp`'s `accept_eval` / `metric_measure` / `metric_name`
   are the same functions the UI panel calls (one definition, two consumers, by design).
4. **CSV telemetry export** — the columns in `SCENARIOS.md` §"Telemetry export", header
   comments recording the seed, scenario id, git describe, and **every broken canon lock**.

## What already exists that M11c builds on

- **`sim/accept.{h,cpp}` (M11b):** `accept_eval`, `metric_measure`, `metric_name`, `metric_needs`,
  `RunAggregates`. The objective panel is a UI view onto these — do not re-implement them.
- **The provenance system** (`ARCHITECTURE.md §6`): `PARAM_TABLE` in `canon_generated.h` carries
  every parameter's tag, tunable range, and description straight from `canon.py`. The inspector
  is a view onto it; `derive.py` emits it.
- **`Stats.non_canon_run`** (`telemetry_v1.h`) is already declared — M11c sets it.
- **The driving script (M11b):** `scenario_apply_drive` + the `Stimulus` list. The app can reuse
  it to auto-play a scenario, or map the tools to interactive brushes.
- **Scenario `scope` + `tools` + `param_overrides`** are parsed but not applied — M11c is where
  `scope` (render) and `param_overrides` (runtime params) finally take effect.

## The meta-lessons this build keeps re-learning (full text: CONTINUATION_PROMPT.md §4)

- **A gate that PASSES while the thing is broken is worse than one that fails.** M11b's
  `medium_temp_mean` check would have "passed" at 361 K on a 50 %-relative tol bug; the honest
  fix was `tol_absolute` and a null (no cells → medium stays at 371 K, fails).
- **Do not guess a threshold — derive it.** Every M11b accept traces to a physical value or
  canon: the beam is 1 kW / `CELL_CROSS_SECTION`, the ramp frontier is `N/N_lethal − 1`, the
  impulse is `ΣE/c`. The scenario *parameters* (irradiance, heat rate) were tuned; the
  *assertions* were not.
- **A measured symptom is not a diagnosis.** three-percent-line's 3.25× velocity error looked
  like a metric bug; it was the awake-cell viscosity drop — predicted, then confirmed.
- **Look at the output.** The scenarios pass headless; run `build/astrophage.exe --scenario <name>`
  and watch one before trusting M11c's panels.

## Deferred, with reasons

- **`param_overrides` do not apply yet** — the runtime-param system is M11c's, and it is the
  same machinery the canon lock needs (ADR-031 §3).
- **`scope` is parsed, not applied** — render-only; M11c/app.
- **The `"schema": 1`** field in the JSONs is a soft marker; the authority is
  `SCENARIO_CONTRACT_VERSION == 2` in the header. Left as-is to avoid churn.
- **M7b render remainder** — bloom over Petrova, the cross-fade slider, the real T-field
  false-colour behind Thermal IR; pre-ignition warm-up needs `temp_cell` in the render instance
  → `render_view_v3`. Fits M12.
- **Q9** (27→8 bucket neighbour walk), **Q18** (Poisson tumble refractory), **Q7/ADR-017**
  (GLSL mirrored formulas), **Q14/Q15**. Test-suite cost ~5–6 min (`test_evolution` + the
  heavier `test_scenario`). Kept deliberately.
- After M11: **M12 Ship** — snapshot/replay, the perf pass, packaging, the M7b remainder, `v1.0`.
