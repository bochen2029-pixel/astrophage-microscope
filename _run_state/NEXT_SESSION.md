# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Last green: `m12b-green`. Next milestone: M12c — perf pass + the render remainder + the scrubber.**

Physics and content are complete; M12 (Ship) is well underway, split M12a/b/c/d (Iron Rule 9).
Done: **M12a** (snapshot save/load + bit-identical replay), **M12b** (Taumoeba rendering — the
predators finally draw, as marked `CellInstance`s appended after the cells). 30 tests, 12 goldens,
37 ADRs.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12b
```

Then read `CONTINUATION_PROMPT.md`, the **M12c** section of `docs/MILESTONES.md`, and — since M12c is
render/perf-heavy — `docs/RENDERING.md` (esp. §5 LUTs, §7 perf), `src/render/MODULE.md`,
`contracts/render_view_v2.h`, and the render passes (`field_pass.cpp`, `bloom.cpp`, `luts.cpp`,
`cells_pass.cpp`). It is a big milestone — consider splitting it (perf / render-remainder / scrubber).

## What M12c is

1. **The perf pass** (`RENDERING.md §7`): build `test_perf` (T27-T29). The headline is **T29 —
   zero device allocation in the steady-state tick loop** (all scratch is preallocated at
   world_create); a `cudaMemGetInfo` delta over N warmed-up steps at 200k cells catches a leak
   regression. The render frame budget (T27) is already gated by M1.5's `--benchmark`; T28 is
   sim-tick throughput (keep any timing floor generous — timing gates are flaky).
2. **The M7b render remainder** — bloom over the Petrova emission (`bloom.cpp` exists), the
   cross-fade slider (`ScopeState::mode_blend`/`mode_blend_to` already in render_view_v2), the real
   T-field false-colour behind Thermal IR (`field_pass.cpp` + a LUT). **Pre-ignition warm-up needs
   `temp_cell` in the render instance → a `render_view_v3` bump**: add the field to `CellInstance`
   (it grows 36→40 bytes, re-`static_assert`), update the vertex attribute bindings in
   `cells_pass.cpp` AND the interop fill in the SAME commit (ADR + `_v2`→`_v3`; nothing may include
   both — same names, same namespace). The bit-15 predator marker (ADR-037) stays as-is.
3. **The colourblind LUT toggle** (`ScopeState::colorblind_safe` already carried) and **the time
   scrubber** over M12a's snapshots (record a ring of `snapshot_save`s, scrub back with
   `snapshot_load`; motion config is the caller's to restore, ADR-036).

**Gate.** M12b gate + `test_perf` (T27-T29) + a screenshot of the new view affordances. Verify UI by
screenshot (meta-lesson 11).

## After M12c

**M12d** — `scripts/package.ps1` (static-runtime `.zip` that runs on a scrubbed-PATH clean machine),
the user guide, CSV `git_describe` injection, then tag **`v1.0`**.

## Loose ends (non-blocking)

- Taumoeba reuse the cell morphology (green blobs, not a distinct amoeba silhouette) and are shown in
  every view mode. A tolerance-coloured Analysis channel is easy — `TaumoebaView` already carries
  `tolerance` (ADR-037).
- Scenario `param_overrides` still unapplied (ADR-035); `snapshot_v1` carries no `next_taumoeba_id`
  or motion config (ADR-036). Neither blocks M12c.
- `scope` center/focal_plane parsed but the app applies only the view mode + objective.
