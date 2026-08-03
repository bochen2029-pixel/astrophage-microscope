# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Last green: `m11f-green`. Next milestone: M12 — Ship (→ v1.0). It is big; split it first.**

M11 is DONE. All eight scenarios load, drive themselves, pass their accept blocks, and are fully
playable: auto-play, the parameter inspector (provenance + canon locks + **live sliders for a curated
set that now move physics**), the objective panel (live checkmarks), and the **cell inspector** (click a
cell → its state + the P1 buoyancy line). 29 tests, 12 goldens, 35 ADRs.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M11f
```

Then read `CONTINUATION_PROMPT.md` (full ritual + roadmap) and the **M12** section of `docs/MILESTONES.md`.

## What M12 is — and split it before starting (Iron Rule 9)

M12's gate names five tests that **do not exist yet** (`test_snapshot`, `test_perf`) plus `package.ps1`,
and `src/sim/snapshot.cpp` is listed in the inventory but is **not built**. This is two or three sessions,
not one. A sane split:

- **M12a — Snapshot + replay.** `src/sim/snapshot.{h,cpp}` (ASPH: magic, version, seed, tick, the 3
  override fields from ADR-035, SoA buffers, field grids), save/load bit-identical within a build, and
  the time scrubber. Gate: `test_snapshot` (T21) — restore reproduces the FNV-1a hash, and a run
  replayed across a save/restore boundary is bit-identical (INV-8).
- **M12b — Perf + render remainder.** The perf pass to budget (`RENDERING.md §7`; `test_perf` = T27-T29),
  **Taumoeba rendering** (the app draws only Astrophage today — the predators run but are invisible), the
  M7b render remainder (bloom over Petrova, the cross-fade slider, the real T-field false-colour behind
  Thermal IR; pre-ignition warm-up needs `temp_cell` in the render instance → a **`render_view_v3`** bump),
  and the colourblind LUT toggle.
- **M12c — Package + v1.0.** Static-runtime `.zip` that runs on a scrubbed-PATH clean machine
  (`package.ps1`), the user guide, then tag `v1.0`.

Decide the split in `MILESTONES.md` first, each half with its own gate.

## Loose ends (non-blocking)

- `_run_state/*.log` is now gitignored, so gate/audit logs no longer clutter `git status`.
- Scenario `param_overrides` (parsed since M11a) still **unapplied** — deferred with the full
  `constexpr`→runtime refactor (ADR-035). No scenario sets one, so nothing is broken; wire it when a
  scenario needs it (it would flow through the ParamSet overlay → the ADR-035 World fields).
- `scope` center/focal_plane parsed but the app applies only the view mode + objective.
- CSV `git_describe` is a placeholder (packaging, M12c, injects it).
- The curated live-override set is 3 params (ADR-035). Adding one is 4 edits: a `World` field
  (default `canon::`), one kernel read-site, one app push line in `apply_param_overrides`, the
  `param_live` flag. `CELL_TEMP_SETPOINT` (CANON, tunable) would be a great P2 demo but threads
  `thermal.cuh` — do it behind its canon lock.
