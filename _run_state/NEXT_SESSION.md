# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **For the full bootstrap, read [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md).** It is the
> comprehensive, self-contained handoff (ritual + state + roadmap + meta-lessons + gotchas). This
> file is the one-screen "you are here".

## Where the build stands

**Last green: `m11e-green`. Next milestone: M11f — the cell inspector + live param overrides.**

The content is complete, self-verifying, and **fully playable in the app**: `astrophage --scenario
first-light` ignites the culture, the parameter inspector shows every canon value with provenance
badges + the non-canon lock guard, and the objective panel grades the scenario live (3/3 for
first-light). Headless: all 8 scenarios pass `--assert` (T24), `--csv` exports telemetry. 28 tests,
12 goldens, 34 ADRs.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11e
```

Then read `CONTINUATION_PROMPT.md` (full ritual + roadmap), and for M11f specifically: the M11 section
of `docs/MILESTONES.md` (M11f), **ADR-034**, `src/ui/params_panel.cpp` + `src/ui/scenario_panel.cpp`
(the panel + app-side-eval patterns to copy), and `src/app/application.cpp` (the loop, picking, and
where to add the `World` override fields).

## What M11f is

1. **`inspector_panel.cpp` — the cell inspector.** Click a cell (mouse → chamber coord via the camera
   → nearest cell from a positions download) → its state, with the **P1 buoyancy line** (density,
   sink/rise). The HUD Charge section already computes that line — reuse it. Per-cell view.
2. **The sim reads overridden param values** for a curated tunable set (`PETROVA_MAX_POWER`,
   `LIFE_DOUBLING_TIME`, …) via `World` fields the app fills from `a.params` (`ParamSet`), so the
   inspector's sliders finally affect physics (ADR-034). Then `params_panel.cpp`'s value editing
   becomes real (labelled pending in M11d). The full `constexpr`→runtime refactor stays deferred.

**Gate.** M11e gate + a live-override check (override a param, run, confirm the physics changed).

## After M11f

**M12 Ship** — snapshot/replay + time scrubber, the perf pass to budget, colourblind LUT, packaging
(clean-machine `.zip`), **Taumoeba rendering** (the app draws only Astrophage today), the M7b render
remainder (bloom over Petrova, cross-fade, T-field false-colour; pre-ignition warm-up needs
`temp_cell` in the render instance → `render_view_v3`), then tag `v1.0`.

## Loose ends (non-blocking)

- Untracked `_run_state/*_gate.log` files clutter `git status` (a sandbox rule blocked deleting them;
  a `.gitignore` line — `_run_state/*.log` — would tidy it).
- `scope` center/focal_plane parsed but the app applies only the view mode + objective.
- CSV `git_describe` is a placeholder (packaging, M12, injects it).
