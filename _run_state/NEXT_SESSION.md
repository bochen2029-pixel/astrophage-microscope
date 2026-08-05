# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Three arcs, all branched off `m12e-green`. The ship line is one step from packaging.** Believe the tags.

- **The ship line (M12) -> v1.0. Last green: `m12h-green`.** The render remainder is **3/4 done** (kickoff +
  per-step manifests in [`M12F_PLAN.md`](M12F_PLAN.md)): **M12f** = the view cross-fade (premultiplied
  dissolve, no contract change); **M12g** = `render_view_v3` (`CellInstance` +`temp_c`, 36->40) + the
  pre-ignition Thermal-IR warm-up (ADR-043); **M12h** = bloom over the Petrova emission from a SEPARATE
  emission buffer (ADR-044). **Remaining: M12i** (real T-field false-colour behind Thermal IR), then
  **M12j** (package -> `v1.0`).
- **The presentation arc (M14). Last green: `m14b-green`.** The living-screensaver demo. **Next: M14c**
  (view cross-fades + a cold-start trigger) -- M12f's `mode_blend` shader path is what its cross-fades need.
- **The interaction arc (M13). Last green: `m13b-green`.** Brushes + light-leash + tweezers. **Next: M13c**
  (record interactions to the snapshot ring) -- *optional*.

Pick any. 32 tests, 12 goldens, **44 ADRs**. (M13/M14 gates re-run M0..M14b but NOT M12f+, which is scoped
to the M12 ship line only -- M13/M14 branched from m12e-green before the render remainder.)

**Recommended next: M12i** (the T-field) -- the last render-remainder step, then M12j packages `v1.0`.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12h
```

Then `CONTINUATION_PROMPT.md`, `M12F_PLAN.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M12i (T-field false-colour, RECOMMENDED)** -- replace the flat `ThermalIR` clear colour with the
  diffused T-field. `RenderFrame.temperature` is already a live device pointer, but **`field_pass.cpp` does
  NOT exist** (the module docs list it aspirationally) -- so the grid -> R32F texture -> LUT path must be
  BUILT. Copy the fullscreen-pass idiom from `post_pass.cpp`, or better the **M12h emission-FBO idiom in
  `bloom.cpp`** (render a field into an FBO, sample it). Wire it as the ThermalIR background under the M12f
  cross-fade background seam. DELIBERATELY moves the `m7b_thermal_*` goldens (flat wash -> spatial field):
  regenerate via `scripts/goldens.ps1 -Generate` + a `DECISIONS.md` line (Rule 10; a fresh ADR-045).
- **M12j (package -> v1.0)** -- `scripts/package.ps1`, clean-machine `.zip`, user guide, tag `v1.0`.
- **M14c / M13c** -- the parallel arcs; M14c's cross-fades are unblocked by M12f.

## Contracts state

Live contracts are **`render_view_v3.h`** + **`scenario_v3.h`** (v1/v2 frozen). `CellInstance` is 40 bytes
(x/y/z, radius, charge, emit, flags, dir, shape_seed, temp_c); the vertex bindings in `cells_pass.cpp` run
locations 0-4. Any further per-cell render field is a `render_view_v4` bump + the same ~12-consumer cascade.

## Render pipeline note (post-M12h)

`bloom.cpp` introduced the renderer's **first FBO**. Pattern to reuse (M12i wants it): a `BloomPass`-style
struct owns an FBO + a colour texture; `bloom_pass_apply` binds the FBO, re-draws content into it
(bloom re-draws the Astrophage via `cells_pass_draw` with `count = cell_count`, so the Taumoeba are
excluded), then samples it in an additive/textured fullscreen pass. The composite pass is the
`post_pass.cpp` fullscreen-triangle idiom.

## Loose ends (non-blocking)

- **Everything is pushed through `m12h-green`** (remote `origin` =
  github.com/bochen2029-pixel/astrophage-microscope). Ask Bo before pushing future work.
- **Bloom is Petrovascope-only + default-on**, intensity 2.0 (a hardcoded arg in `application.cpp`; a HUD
  intensity slider + toggle is a nice future tweak). A crude whole-backbuffer bloom was tried first and
  reverted -- do NOT revisit it; the emission-buffer approach (ADR-044) is the right one.
- **`--gl-debug` + `--screenshot` together emit one benign glReadPixels GL-debug warning** (pre-existing).
  Gates never combine them.
- **Thermal-density gotcha (M13b):** herding a LARGE awake culture (~2000+ cells) into a tight pile drives
  the explicit thermal solver to blow up (`--auto-light --awake` at 3000 cells ran the medium to 8e6 K;
  1000 cells is stable at the setpoint -- the M12h/M13b gates use 1000). Keep interaction piles modest.
- The M12 ship loose ends still stand (snapshot has no next_taumoeba_id/motion, ADR-036; scenario
  `param_overrides` unapplied, ADR-035). Demo caveats: interop sized at init (ADR-042).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
