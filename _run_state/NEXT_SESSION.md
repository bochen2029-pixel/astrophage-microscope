# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Last green: `m12e-green`. Next: M12f — the render remainder. Then M12g — package → `v1.0`.**

Physics and content are complete; M12 (Ship) is nearly done, split M12a–g (Iron Rule 9). Done:
**M12a** snapshot save/load + bit-identical replay, **M12b** Taumoeba rendering, **M12c** the perf pass
(zero steady-state allocation, at budget), **M12d** the time scrubber, **M12e** render legibility
(Taumoeba coloured by N2 tolerance — the evolution arc visible — + the colourblind LUT). 31 tests,
12 goldens, 39 ADRs. **The repo remote was pushed current this session** (through m12e-green + fresh
screenshots).

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12e
```

Then read `CONTINUATION_PROMPT.md`, the **M12f** section of `docs/MILESTONES.md`, and — M12f is all
render — `docs/RENDERING.md`, `src/render/MODULE.md`, `contracts/render_view_v2.h`, and the passes
(`cells_pass.cpp`, `field_pass.cpp`, `bloom.cpp`, `luts.cpp`). **Split it** — the contract bump is its
own gate.

## What M12f is — the cascade you MUST plan for first

1. **The `render_view_v3` → `scenario_v3` cascade (its own commit + gate).** Pre-ignition Thermal-IR
   warm-up needs per-cell `temp_c` in the render instance; `CellInstance` has no room. Bumping
   `render_view_v2` → `_v3` **cascades into `scenario_v3`**, because `contracts/scenario_v2.h` includes
   `render_view_v2.h` and no TU may include two versions of a contract (same names, same namespace).
   Both `_v3` are complete copies of their `_v2` (with `CellInstance` gaining `temp_c`), every consumer
   switches its include, the vertex bindings in `cells_pass.cpp` + the interop fill in `interop.cu`
   change, one commit, an ADR. **Goldens risk: high** (the vertex stride/offset change) — verify M3.2
   after; keep the bit-15 predator marker (ADR-037) and the tolerance colour (ADR-039) working. Then the
   Thermal-IR shader reads `temp_c` for a real warm-cell rim.
2. **The render polish** (defaults preserve goldens): bloom over the Petrova emission (`bloom.cpp`
   exists → wire into the Petrovascope compose — note it will move the `m7b_petrova` golden, so
   regenerate it with an ADR), the cross-fade slider (`ScopeState::mode_blend`/`mode_blend_to`,
   carried), the real T-field false-colour behind Thermal IR (`field_pass.cpp` → R32F texture + a warm
   LUT).

**Gate.** M12e gate + a screenshot of each affordance + **the goldens still match** (or are regenerated
with an ADR for bloom). Verify UI by screenshot (meta-lesson 11).

## After M12f

**M12g** — `scripts/package.ps1` (static-runtime `.zip` on a scrubbed-PATH clean machine), the user
guide, CSV `git_describe` injection, then tag **`v1.0`**.

## Loose ends (non-blocking)

- Taumoeba show in every mode and reuse the cell morphology; a tolerance-keyed Analysis channel is easy.
  Colourblind LUT applies to Petrovascope only today (extend to Thermal IR in M12f if wanted).
- Scenario `param_overrides` unapplied (ADR-035); snapshot has no `next_taumoeba_id`/motion config
  (ADR-036/038); scrubber rewind is linear, not branching. `scope` center/focal_plane parsed, only
  view mode + objective applied.
