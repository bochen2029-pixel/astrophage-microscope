# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Last green: `m12d-green`. Next milestone: M12e — the render remainder. Then M12f — package → `v1.0`.**

Physics and content are complete; M12 (Ship) is nearly done, split M12a–f (Iron Rule 9). Done:
**M12a** snapshot save/load + bit-identical replay, **M12b** Taumoeba rendering, **M12c** the perf
pass (zero steady-state allocation, at budget), **M12d** the time scrubber (rewind a run through an
in-memory snapshot ring). 31 tests, 12 goldens, 38 ADRs.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12d
```

Then read `CONTINUATION_PROMPT.md`, the **M12e** section of `docs/MILESTONES.md`, and — M12e is all
render — `docs/RENDERING.md` (§5 LUTs, §8 morphology), `src/render/MODULE.md`,
`contracts/render_view_v2.h`, and the passes (`cells_pass.cpp`, `field_pass.cpp`, `bloom.cpp`,
`luts.cpp`, `post_pass.cpp`). **Split it** — the contract bump alone is its own gate.

## What M12e is — and the cascade you MUST plan for

1. **The `render_view_v3` → `scenario_v3` cascade (do this first, its own commit + gate).** Pre-ignition
   Thermal-IR warm-up needs per-cell `temp_c` in the render instance; `CellInstance` has no room.
   Adding it means bumping `render_view_v2` → `_v3`. **But `contracts/scenario_v2.h` includes
   `render_view_v2.h`, and nothing may include two versions of a contract** (same names, same
   namespace) — so this **cascades into a `scenario_v3` bump** too. Both `_v3` headers are complete
   copies of their `_v2` (with `CellInstance` gaining `temp_c`), every consumer switches its include,
   the vertex bindings in `cells_pass.cpp` + the interop fill in `interop.cu` change, one commit, an
   ADR. **Goldens risk: high** (the vertex stride/offset change is what renders cells wrong) — verify
   M3.2 after, and keep the bit-15 predator marker (ADR-037) working. Then the Thermal-IR shader reads
   `temp_c` for a real warm-cell rim instead of the AWAKE-latch stand-in.
2. **The render polish** (each low-risk, defaults preserve goldens): bloom over the Petrova emission
   (`bloom.cpp` exists → wire into the Petrovascope compose), the cross-fade slider
   (`ScopeState::mode_blend`/`mode_blend_to`, carried), the real T-field false-colour behind Thermal IR
   (`field_pass.cpp` → R32F texture + a warm LUT), and the colourblind LUT toggle
   (`ScopeState::colorblind_safe`, swaps petrova-film for magma). Add a must-differ golden pair for the
   LUT swap to prove it does something (like the morphology pair, ADR-017).

**Gate.** M12d gate + a screenshot of each affordance + **the goldens still match** (the v3 bump must
not move a measurement golden). Verify UI by screenshot (meta-lesson 11).

## After M12e

**M12f** — `scripts/package.ps1` (static-runtime `.zip` on a scrubbed-PATH clean machine), the user
guide, CSV `git_describe` injection, then tag **`v1.0`**.

## Loose ends (non-blocking)

- Taumoeba reuse the cell morphology and show in every mode; a tolerance-coloured Analysis channel is
  easy (`TaumoebaView` carries `tolerance`, ADR-037).
- Scrubber (ADR-038): resuming after a rewind overwrites the "future" frames — a linear rewind, not a
  branching timeline. Snapshot has no `next_taumoeba_id`/motion config (ADR-036, the scrubber
  re-applies motion). `param_overrides` unapplied (ADR-035). `scope` center/focal_plane parsed but
  only view mode + objective applied.
