# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **The content is watchable (M11a–M11d).** Scenarios load, drive, pass their objectives, export
> telemetry; the app **auto-plays** any scenario (`--scenario ID`) and the **parameter inspector**
> shows every canon value with a provenance badge + the lock guard. The next milestone is
> **M11e — the objective panel, the cell inspector, and live overrides**: the acceptance
> checkmarks (computed app-side against a live `RunAggregates`, since `ui` may not include `sim`),
> click-a-cell inspection with the P1 buoyancy line, and the sim reading *overridden* param values
> for a curated set so the inspector's sliders affect physics. See the M11 section of
> `docs/MILESTONES.md` (M11e), **ADR-034** (the ParamSet), and `CONTINUATION_PROMPT.md` §4.

> **You can verify UI without a display.** `--headless` is a hidden window with a real GL context;
> `--screenshot out.ppm` captures the full frame (ImGui included). Convert PPM→PNG
> (`python -c "from PIL import Image; Image.open('out.ppm').save('out.png')"`) and look. That is how
> M11d's panels + auto-play were checked. Use it — meta-lesson: look at the output.

---

## Where the build stands

**Last green: `m11d-green`. Next milestone: M11e — objective panel + cell inspector + live overrides.**

27 tests green, 12 goldens, 11 audit checks, 34 ADRs.

| | measured |
|---|---|
| **M11b** | all 8 scenarios pass `--assert` (T24) |
| **M11c** | `test_param_locks`: CANON locked by default, breaking a lock sets sticky `non_canon_run`; `headless --csv` telemetry |
| **M11d** | `M11d.1`: `astrophage --scenario <id> --headless` auto-plays all 8 cleanly. first-light ignites (medium chart 96.35 °C); params panel shows the gold CANON locks; spin-drive flash empties the store |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11d
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → `docs/RENDERING.md` (you are in `ui`/`app`) → **the M11 section only** of `docs/MILESTONES.md` (M11e) → **ADR-034** → `src/ui/params_panel.cpp` (the panel pattern to copy) → `src/sim/accept.h` (the objective engine — `metric_measure`/`accept_eval`/`RunAggregates`) → `src/app/application.cpp` (the loop + where to sample aggregates and draw panels).

## What M11e is — the objective panel, the cell inspector, live overrides

1. **`scenario_panel.cpp` — the objective/acceptance panel.** The scenario's `objective_text` + a
   checkmark per accept check. **The app computes the results** (it links `sim`: sample a
   `RunAggregates` each HUD tick as `run_scenario_assert` does, call `sim::metric_measure` +
   `sim::accept_eval`) and hands a small results array (name, measured, target, op, pass) to the
   panel — `ui` may not include `sim` (`ui/MODULE.md`). It should agree with `headless --assert`.
2. **`inspector_panel.cpp` — the cell inspector.** Click a cell (mouse → chamber coord via the
   camera → nearest cell from a hash/positions download) → its state, with the **P1 buoyancy line**
   prominent (density, sink/rise). The HUD Charge section already computes that line — reuse it.
3. **The sim reads overridden param values** for a curated tunable set (`PETROVA_MAX_POWER`,
   `LIFE_DOUBLING_TIME`, …) via `World` fields the app fills from the `ParamSet`, so the inspector's
   sliders finally affect physics (ADR-034). Then the params panel's value editing becomes real (it
   is labelled pending in M11d). The full `constexpr`→runtime refactor stays deferred.

## What already exists that M11e builds on

- **`src/ui/params_panel.cpp` (M11d):** the ImGui panel + provenance-badge idiom to copy.
- **`sim/accept.{h,cpp}`:** `metric_measure`, `accept_eval`, `metric_name`, `RunAggregates`, `metric_needs` — the objective engine. `tools/headless.cpp`'s `run_scenario_assert` is the reference for sampling aggregates.
- **App auto-play (M11d):** `a.scenario` / `a.has_scenario` + `scenario_apply_drive`; the app already runs the scenario.
- **`a.params` (`ParamSet`, M11d):** owned by the app, non-canon mirrored into the World; M11e adds the sim-side override read.
- **Screenshot verify:** `--headless --screenshot` + PPM→PNG (above).

## The meta-lessons (full text: CONTINUATION_PROMPT.md §4)

- **Look at the output.** Screenshot each new panel and view it. A golden that passes can still look wrong.
- **A control that silently does nothing is worse than one labelled pending.** M11e makes the inspector sliders real (sim reads overrides) OR keeps them labelled — never a slider that moves and changes nothing.
- **A gate that passes while the thing is broken is worse than one that fails.** The objective panel must agree with `headless --assert`, or it is theatre.

## Deferred, with reasons

- **The sim reads only `canon::` today** — M11e adds the curated override read path (ADR-034).
- **`scope` center/focal_plane** are parsed but the app applies only the view mode + objective — M11e/M12.
- **Taumoeba are not rendered** in the app (only Astrophage) — the taumoeba scenario runs but its predators are invisible; a render pass is M12.
- **CSV `git_describe`** placeholder — packaging (M12) injects it.
- **M7b render remainder** (bloom over Petrova, cross-fade, T-field false-colour; pre-ignition warm-up needs `temp_cell` in the render instance → `render_view_v3`). **Q9/Q18/Q7.** Test suite ~5–6 min.
- After M11: **M12 Ship** — snapshot/replay, perf pass, packaging, Taumoeba render, the M7b remainder, `v1.0`.
