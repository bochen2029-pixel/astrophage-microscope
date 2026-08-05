# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Three arcs, all branched off `m12e-green`. The ship line is closing on v1.0.** Believe `git tag --list`.

- **The ship line (M12) -> v1.0. Last green: `m12g-green`.** The render remainder, a four-step split
  (kickoff + per-step manifests in [`M12F_PLAN.md`](M12F_PLAN.md)):
  **M12f DONE** = the view cross-fade (premultiplied dissolve between two modes; `mode_blend`, no contract
  change). **M12g DONE** = `render_view_v3` (`CellInstance` gains `temp_c`, 36->40) + the pre-ignition
  Thermal-IR warm-up; cascaded `scenario_v2 -> v3`; interop fills temp_c from `CellStoreView::temp_cell`,
  no sim change (ADR-043). **Remaining: M12h** (real T-field false-colour behind Thermal IR), **M12i**
  (bloom over Petrova), **M12j** (package -> `v1.0`).
- **The presentation arc (M14). Last green: `m14b-green`.** The living-screensaver demo. **Next: M14c**
  (view cross-fades + a cold-start trigger) -- M12f's `mode_blend` shader path is exactly what its
  cross-fades need, so M14c is unblocked now.
- **The interaction arc (M13). Last green: `m13b-green`.** Brushes + light-leash + tweezers. **Next: M13c**
  (record interactions to the snapshot ring) -- *optional*.

Pick any. 32 tests, 12 goldens, **43 ADRs**. (M13/M14 gates re-run M0..M14b but NOT M12f+, which is scoped
to the M12 ship line only -- M13/M14 branched from m12e-green before the render remainder.)

**Recommended next: M12h** (the T-field) -- it is more tractable than M12i (bloom), which needs a real
emission-buffer render pass (see below; a crude whole-frame bloom was tried 2026-08-05 and reverted). M12h
deliberately moves the m7b_thermal goldens, so it wants care (a fresh ADR + `scripts/goldens.ps1 -Generate`).
Then M12i, M12j.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12g
```

Then `CONTINUATION_PROMPT.md`, `M12F_PLAN.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M12h (T-field false-colour, RECOMMENDED)** -- replace the flat `ThermalIR` clear colour with the
  diffused T-field. `RenderFrame.temperature` is already a live device pointer, but **`field_pass.cpp` does
  NOT exist** (the module docs list it aspirationally, like bloom.cpp) -- so the grid -> R32F texture -> LUT
  path must be BUILT (copy the fullscreen-pass idiom from `post_pass.cpp`). Wire it as the ThermalIR
  background under the M12f cross-fade background seam. DELIBERATELY moves the `m7b_thermal_*` goldens (flat
  wash -> spatial field): regenerate via `scripts/goldens.ps1 -Generate` + a `DECISIONS.md` line (Rule 10;
  a fresh ADR). New `src/render/field_pass.cpp`, `cells_pass.cpp`/compose, `luts.cpp`.
- **M12i (bloom) -- ATTEMPTED 2026-08-05 and REVERTED; read this before retrying.** A crude
  whole-backbuffer mip-bloom (glCopyTexImage2D + glGenerateMipmap + an additive bright-pass, no FBO) is a
  DEAD END, for two reasons found by looking at the output: (1) it cannot isolate "Petrova emission only" --
  it blooms ANY bright pixel, so on the taumoeba scene it blooms the bright green PREDATORS into a wash, not
  the emission; (2) the Petrova emission renders too DIM (below any sane bright threshold) to bloom in most
  scenes, so it is a no-op everywhere else. Do it RIGHT: render the Petrova EMISSION to a SEPARATE additive
  target (RENDERING.md Sec 2 already shows "petrova emission lobes, additive" as its own pipeline input) and
  bloom THAT -- excluding the cell silhouettes and the teal Taumoeba -- and brighten the emission so it
  clears the threshold. `bloom.cpp` does not exist. Goldens stay safe by capturing `--no-bloom` (the ADR-023
  appearance precedent; the m7b_petrova golden is a non-emitting black frame anyway). This is a real
  render-architecture task (an emission buffer), NOT a post-process tweak -- give it fresh context.
- **M12j (package -> v1.0)** -- `scripts/package.ps1`, clean-machine `.zip`, tag `v1.0`.
- **M14c / M13c** -- the parallel arcs; M14c's cross-fades are unblocked by M12f.

## Contracts state (post-M12g)

Live contracts are now **`render_view_v3.h`** + **`scenario_v3.h`**. `render_view_v1/v2` and
`scenario_v1/v2` are frozen and included by nothing live. `CellInstance` is 40 bytes (x/y/z, radius,
charge, emit, flags, dir, shape_seed, **temp_c**); the vertex bindings in `cells_pass.cpp` run locations
0-4. Any further per-cell render field is a `render_view_v4` bump + the same cascade.

## Loose ends (non-blocking)

- **M12f + M12g are unpushed** (`git push origin main --tags` when ready -- remote `origin` =
  github.com/bochen2029-pixel/astrophage-microscope). M13a/b + M14a/b + m12f were pushed earlier this
  session. Ask Bo before pushing.
- **temp_c is Celsius, filled from `temp_cell` [K] - 273.15.** The Thermal warm-up floor is a shader
  constant 20 C (room temp); the ceiling is `u_setpoint_c` = canon `CELL_TEMP_SETPOINT`. Awake cells force
  `warm = 1.0` so the old latch rim is bit-identical.
- **`--gl-debug` + `--screenshot` together emit one benign glReadPixels GL-debug warning** (pre-existing).
  Gates never combine them.
- **Thermal-density gotcha (M13b):** herding a LARGE culture (~2000+ cells) into a tight pile drives the
  explicit thermal solver negative (ADR-008-class; awake+no-light is stable). Keep interaction piles modest.
- The M12 ship loose ends still stand (snapshot has no next_taumoeba_id/motion, ADR-036; scenario
  `param_overrides` unapplied, ADR-035). Demo caveats: interop sized at init (ADR-042).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
