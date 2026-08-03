# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Last green: `m12a-green`. Next milestone: M12b — perf, Taumoeba rendering, the render remainder, the scrubber.**

The physics and content are complete; M12 (Ship) is underway, split M12a/b/c (Iron Rule 9). **M12a is done:**
a run saves and resumes bit-identically (`src/sim/snapshot.cu`, the ASPH full-state dump), and the
snapshot `state_hash` is now the INV-8 oracle at full resolution. 30 tests, 12 goldens, 36 ADRs.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12a
```

Then read `CONTINUATION_PROMPT.md`, the **M12b** section of `docs/MILESTONES.md`, and — since M12b is
render/UI-heavy — `docs/RENDERING.md`, `src/render/MODULE.md`, `contracts/render_view_v2.h`, and the
render passes (`cells_pass.cpp`, `field_pass.cpp`, `bloom.cpp`, `post_pass.cpp`, `luts.cpp`).

## What M12b is (a big milestone — consider splitting again if it won't fit)

1. **The perf pass to budget** (`RENDERING.md §7`): `test_perf` (T27-T29) does not exist yet — build it.
   The app already has `--benchmark` (M1.5 renders 200k cells at target fps); T27-T29 formalise the
   frame/memory/throughput budgets. Q9 (the 27→8 bucket neighbour walk) is the best remaining perf lever
   and only worth it once a scenario stresses throughput.
2. **Taumoeba rendering** — the app draws only Astrophage today; the predators run but are **invisible**.
   They need an instanced pass like the cells (40 um, distinct morphology/colour), fed from the
   TaumoebaStore via interop.
3. **The M7b render remainder** — bloom over Petrova, the cross-fade slider, the real T-field
   false-colour behind Thermal IR. Pre-ignition warm-up needs `temp_cell` in the render instance →
   a **`render_view_v3`** bump (add `_v3.h`, update every consumer, ADR, one commit; `_v1`/`_v2` are
   frozen — nothing may include two versions).
4. **The colourblind LUT toggle** (`luts.cpp`) and **the time scrubber** over M12a's snapshots (record a
   ring of snapshots, scrub back — `snapshot_save`/`snapshot_load` are ready; motion config is the
   caller's to restore, ADR-036).

**Gate.** M12a gate + `test_perf` (T27-T29) + a screenshot showing Taumoeba rendered and the new view
affordances. Verify UI by screenshot (meta-lesson 11): `astrophage --scenario taumoeba --headless
--screenshot out.ppm`, PPM→PNG, look.

## After M12b

**M12c** — `scripts/package.ps1` (static-runtime `.zip` that runs on a scrubbed-PATH clean machine), the
user guide, CSV `git_describe` injection, then tag **`v1.0`**.

## Loose ends (non-blocking)

- Scenario `param_overrides` (parsed since M11a) still unapplied — deferred with the full
  `constexpr`→runtime refactor (ADR-035). They would flow through the ParamSet overlay → the ADR-035
  World fields; wire it if a scenario needs one.
- `snapshot_v1` carries no `next_taumoeba_id` (reconstructed `max(id)+1`, exact unless the top-id predator
  was culled) and no motion config (the caller restores it). A `snapshot_v2` would close the first;
  neither blocks M12b (ADR-036).
- `scope` center/focal_plane parsed but the app applies only the view mode + objective.
