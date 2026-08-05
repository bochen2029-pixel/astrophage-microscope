# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Three arcs, all branched off `m12e-green`. The ship line is moving again.** Believe `git tag --list`.

- **The ship line (M12) -> v1.0. Last green: `m12f-green`.** The render remainder is being finished as a
  four-step split (kickoff + per-step manifests in [`M12F_PLAN.md`](M12F_PLAN.md)):
  **M12f DONE** = the view cross-fade (a mode's cell appearance + background is a `ViewMode` function,
  evaluated for `mode` and `mode_blend_to` and dissolved in premultiplied alpha; HUD "blend to" + slider,
  `--mode-blend-to`/`--mode-blend`; no contract change). **Remaining: M12g** (the `render_view_v3 ->
  scenario_v3` cascade + per-cell `temp_c` pre-ignition warm-up), **M12h** (real T-field false-colour
  behind Thermal IR), **M12i** (bloom over Petrova), **M12j** (package -> `v1.0`).
- **The presentation arc (M14). Last green: `m14b-green`.** `--demo` is the living screensaver: caption,
  drift, idle-yield, and a light-leash "herding" act. **Next: M14c** (view cross-fades + a cold-start
  trigger) -- and M12f just built the `mode_blend` shader path M14c's cross-fades need, so M14c is closer.
- **The interaction arc (M13). Last green: `m13b-green`.** Brushes + light-leash + tweezers. **Next: M13c**
  (record interactions to the snapshot ring) -- *optional*.

Pick any. 32 tests, 12 goldens, 42 ADRs. (M13/M14 gates re-run M0..M14b but NOT M12f+, which is scoped to
the M12 ship line only -- M13/M14 branched from m12e-green before the render remainder.)

**Recommended next: M12g** -- the highest-structural-risk step, so isolate it. Plan the multi-contract
change FIRST (see below), then M12h, M12i, M12j.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12f
```

Then `CONTINUATION_PROMPT.md`, `M12F_PLAN.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M12g (the cascade + pre-ignition warm-up, RECOMMENDED)** -- add `float temp_c` to `CellInstance`
  (36 -> 40 bytes). `scenario_v2.h` includes `render_view_v2.h`, so **both bump to v3 together**; swap
  ~14 consumer includes v2 -> v3 (a missed one is a *compile* error, not silent). The interop kernel
  samples the T grid to fill `temp_c` (no `sim/`/`cell_store` change). The Thermal-IR branch already has an
  `appearance()` seam (M12f) to add the continuous dormant-warmth glow to. **ADR-043**, same commit. High
  goldens risk (GL layout) -- but measurement goldens are Brightfield/Sphere and never read `temp_c`, so
  they must not move. `contracts/render_view_v2.h`, `src/render/interop.cu`, `src/render/cells_pass.cpp`.
- **M12h (T-field false-colour)** -- reuse `field_pass` + `RenderFrame.temperature` (already carried).
  DELIBERATELY moves the `m7b_thermal_*` goldens (regen via `tools/goldgen` + ADR-044).
- **M12i (bloom)** -- build `src/render/bloom.cpp` (it does NOT exist despite MODULE.md); perf-sensitive.
- **M12j (package -> v1.0)** -- after M12i.
- **M14c / M13c** -- the parallel arcs; M14c's cross-fades are unblocked once M12g/M12h land the render.

## Loose ends (non-blocking)

- **M12f is unpushed** (`git push origin main --tags` when ready -- remote `origin` =
  github.com/bochen2029-pixel/astrophage-microscope). M13a/b + M14a/b were pushed this session. Ask Bo
  before pushing.
- **The cross-fade at blend 0 is bit-identical to the primary mode** (premultiplied round-trip stays under
  8-bit quantization; M3.2 goldens confirmed unmoved). A future blend-0-guard is unnecessary -- verified.
- **`--gl-debug` + `--screenshot` together emit one benign glReadPixels GL-debug warning** (pre-existing).
  Gates never combine them: GL-error checks omit `--screenshot`, screenshot checks omit `--gl-debug`.
- **Thermal-density gotcha (M13b):** herding a LARGE culture (~2000+ cells) into a tight pile drives the
  explicit thermal solver negative (an ADR-008-class limit; awake+no-light is stable). Keep interaction
  piles modest / thermal-off. A substep-vs-density guard would fix it.
- The M12 ship loose ends still stand (snapshot has no next_taumoeba_id/motion, ADR-036; scenario
  `param_overrides` unapplied, ADR-035). Demo caveats: interop sized at init (ADR-042).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
