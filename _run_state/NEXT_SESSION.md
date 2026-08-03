# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Last green: `m12c-green`. Next milestone: M12d — the render remainder + the time scrubber.**

Physics and content are complete; M12 (Ship) is well underway, split M12a–e (Iron Rule 9).
Done: **M12a** (snapshot save/load + bit-identical replay), **M12b** (Taumoeba rendering),
**M12c** (the perf pass: the tick loop is provably zero-allocation, and it runs at the 2.7 ms
budget). 31 tests, 12 goldens, 37 ADRs. Remaining: **M12d** (this), then **M12e** (package → `v1.0`).

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12c
```

Then read `CONTINUATION_PROMPT.md`, the **M12d** section of `docs/MILESTONES.md`, and — since M12d is
entirely render/UI — `docs/RENDERING.md` (esp. §5 LUTs, §7), `src/render/MODULE.md`,
`contracts/render_view_v2.h`, and the passes (`cells_pass.cpp`, `field_pass.cpp`, `bloom.cpp`,
`luts.cpp`, `post_pass.cpp`). **It is a big milestone — split it** (the `render_view_v3` bump is
delicate enough to be its own gate; bloom + cross-fade + LUT + scrubber are separable).

## What M12d is

1. **The `render_view_v3` bump** — the crux. Pre-ignition warm-up (a heated dormant cell glows in
   Thermal IR before it ignites) needs per-cell `temp_cell` in the render instance; `CellInstance`
   has no room. Add `float temp_c` (or K), grow the struct (re-`static_assert` its size), update the
   **vertex attribute bindings in `cells_pass.cpp` AND the interop fill in `interop.cu` in the SAME
   commit** (ADR, `_v2`→`_v3`; `_v1`/`_v2` are frozen — nothing may include two versions). **Goldens
   risk: high** — the layout/stride change is exactly what can render cells wrong. Verify M3.2 after,
   and keep the bit-15 predator marker (ADR-037) working. Then the Thermal-IR shader reads `temp_c`
   for a real warm-cell rim instead of the AWAKE-latch stand-in.
2. **The real T-field false-colour behind Thermal IR** (`field_pass.cpp` → R32F texture + a warm LUT
   under the cells) and **bloom over the Petrova emission** (`bloom.cpp` exists; wire it into the
   Petrovascope compose).
3. **The cross-fade slider** (`ScopeState::mode_blend`/`mode_blend_to` already carried) and the
   **colourblind LUT toggle** (`ScopeState::colorblind_safe`, swaps petrova-film for magma).
4. **The time scrubber** over M12a's snapshots — record a ring of `snapshot_save`s, scrub back with
   `snapshot_load` (motion config is the caller's to restore, ADR-036).

**Gate.** M12c gate + a screenshot of each new affordance + **the goldens still match** (the
`render_view_v3` bump must not move a measurement golden). Verify UI by screenshot (meta-lesson 11):
`astrophage --scenario first-light --mode thermal --headless --screenshot out.ppm`, PPM→PNG, look.

## After M12d

**M12e** — `scripts/package.ps1` (static-runtime `.zip` on a scrubbed-PATH clean machine), the user
guide, CSV `git_describe` injection, then tag **`v1.0`**.

## Loose ends (non-blocking)

- Taumoeba reuse the cell morphology and show in every mode; a tolerance-coloured Analysis channel is
  easy (`TaumoebaView` carries `tolerance`, ADR-037). `test_perf`'s T29 catches leak-shaped
  allocation, not malloc-then-free churn (the design forbids both).
- Scenario `param_overrides` unapplied (ADR-035); `snapshot_v1` has no `next_taumoeba_id`/motion
  config (ADR-036). `scope` center/focal_plane parsed but only view mode + objective applied.
