# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **The content backend is complete (M11a–M11c).** Scenarios load, drive, pass their
> objectives, and export telemetry; the runtime-parameter overlay + canon locks guarantee a
> run cannot quietly go non-canon. The next milestone is **M11d — the ImGui panels + app
> auto-play**: the parameter inspector, cell inspector, objective/acceptance panel, the HUD
> non-canon badge, and wiring the app to auto-play a scenario's drive script so the eight
> scenarios can be **watched**, not just asserted. See the M11 section of `docs/MILESTONES.md`
> (M11d) and **ADR-034** (the runtime-param overlay). `CONTINUATION_PROMPT.md` §4 has the
> meta-lessons.

> **⚠ M11d needs a display.** M11c did the headless-verifiable backend; M11d is ImGui panels
> that a screenshot/golden-capture and, ideally, a human eye should check. Prefer a session
> where the app window is visible. Offscreen golden capture (`scripts/goldens.ps1`) is the
> headless oracle; use it, but *look* at the panels too (meta-lesson: look at the output).

---

## Where the build stands

**Last green: `m11c-green`. Next milestone: M11d — the inspector/objective UI + app auto-play.**

**All content + telemetry backend is live and headless-verified.** 26 tests green, 12 goldens,
10 audit checks, 34 ADRs.

| | measured |
|---|---|
| **M11a** | all 8 scenarios load + instantiate + run bit-reproducibly (`test_scenario`) |
| **M11b** | all 8 pass `--assert` (T24): velocities/correlations/doubling/tolerance/impulse |
| **M11c** | `test_param_locks`: CANON locked by default, breaking a lock sets sticky `non_canon_run`; overlay == `PARAM_TABLE`; `headless --csv` writes valid telemetry |
| **P1–P5** | all five phenomena live and asserted through the scenarios |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11c
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` (esp. §6 provenance) → `docs/RENDERING.md` (you are in `ui`/`render`) → **the M11 section only** of `docs/MILESTONES.md` (M11d) → **ADR-034** → `src/core/params.h` (the `ParamSet` the panels drive) → `src/sim/accept.cpp` (the objective panel is a view onto it) → `src/ui/hud.cpp` + `src/ui/MODULE.md` + the existing `chart_panel.cpp` (the panel pattern) → `src/app/application.cpp` (the tick loop, to wire auto-play).

## What M11d is — the ImGui panels and app auto-play

**M11c gave the backend; M11d gives it controls and pixels.** Five pieces (no test oracle beyond
build + goldens + the reused `accept.cpp` — so *watch it*):

1. **`params_panel.cpp`** — `PARAM_TABLE` rows with provenance badges (`CANON` gold/locked,
   `DERIVED` blue/read-only, `REAL` grey, `INVENTED` orange) and lock toggles that drive the
   `core/params.h` `ParamSet`. Unlocking a CANON row flips the non-canon badge (already wired to
   `Stats.non_canon_run`).
2. **`inspector_panel.cpp`** — click a cell → its state, with the **buoyancy line that teaches P1**
   (`"SINKING — 31,915 kg/m³, 32× water"`), prominent, not a footnote.
3. **`scenario_panel.cpp`** — scenario picker + objective text + **acceptance checkmarks**, a view
   onto `sim/accept.cpp`'s `metric_measure`/`accept_eval` (do not re-implement).
4. **The HUD non-canon badge + energy ledger** (`hud.cpp`) — the `NON-CANON RUN` badge from
   `Stats.non_canon_run`, and the permanent stored-energy readout (~72 kt TNT at full 200k).
5. **App auto-play** — call `scenario_apply_drive` in `application.cpp`'s tick loop when a scenario
   is loaded, so `astrophage.exe --scenario first-light` actually ignites (not just loads). Then
   **the sim reads overridden param values** for a curated tunable set (via `World` fields), so
   `param_overrides` finally affect physics, not only the flag (ADR-034).

## What already exists that M11d builds on

- **`core/params.h` (M11c):** `ParamSet`, `param_set_init/unlock/set/index`. The panel is a view + editor.
- **`Stats.non_canon_run`** is set (`World.non_canon_run` → `world_stats`). The HUD/panel just displays it.
- **`sim/accept.cpp`:** `accept_eval`, `metric_measure`, `metric_name`, `RunAggregates` — the objective panel's engine.
- **`scenario_apply_drive` (M11b):** the driver the app reuses for auto-play.
- **`headless --csv` (M11c):** the export path; the app's "Export CSV" button reuses the same columns.
- **`chart_panel.cpp` / `hud.cpp`:** the established ImGui panel + SI→display idiom (use `core/units.h`, never open-code a factor).

## The meta-lessons (full text: CONTINUATION_PROMPT.md §4)

- **Look at the output.** M11d is UI — a golden that passes can still look wrong. Run the app and watch a scenario play.
- **A control that silently does nothing is worse than one labelled pending** (`ui/MODULE.md`). Wire the lock toggles to the real `ParamSet`, or label them pending.
- **A gate that passes while the thing is broken is worse than one that fails.** The non-canon badge must be impossible to miss; that is the whole point of the flag.

## Deferred, with reasons

- **The sim reads only `canon::` today** — M11d adds a curated runtime-override read path (ADR-034); the full `constexpr`→runtime refactor stays deferred (no use case, high cost).
- **`scope` is parsed, not applied** — render-only; M11d/app.
- **CSV `git_describe`** is a placeholder — packaging (M12) injects it.
- **M7b render remainder** — bloom over Petrova, the cross-fade slider, the T-field false-colour; pre-ignition warm-up needs `temp_cell` in the render instance → `render_view_v3`. Fits M12.
- **Q9** (27→8 bucket walk), **Q18** (Poisson tumble), **Q7/ADR-017** (GLSL mirrored formulas). Test suite ~5–6 min.
- After M11: **M12 Ship** — snapshot/replay, perf pass, packaging, the M7b remainder, `v1.0`.
