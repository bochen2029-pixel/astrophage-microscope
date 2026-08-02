# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m2-green`. Next milestone: M3 — Optics.**

Cells move, and **P1 is live**. 200,000 cells at ~795 fps, 10 tests green, 7 audit checks clean.

```
test_canon ......... generated constants consistent; the right params carry the canon lock
test_rng ........... PCG32 vs reference vectors, stream independence, gaussian moments
test_contracts ..... POD/layout/version guards, FNV-1a, deposit headroom
test_fixed_atomic .. identical sums across 4 block sizes (INV-2, INV-4)
test_octahedral .... direction packing round trip, <0.05 deg worst case
test_cell_store .... spawn placement, INV-1 stream independence, capacity, id monotonicity
test_scope ......... scale bar at 3 objectives across the zoom range, true cell size
test_motion ........ T1-T4, T6, T8 against the oracle; OU branches; boundaries
test_buoyancy ...... T14: drift velocity linear in charge, zero crossing at 3.00577%
determinism_replay . real World, 10k ticks, seed-sensitive, population-sensitive (INV-8)
```

Measured this session: T1 −1681.5 μm/s, T2 +52.1 μm/s, T3 hovering, T4 MSD/4Dt = 1.020, T6 35.33 μm/s, drift-vs-charge Pearson −1.000000.

## Start here

```bash
git -C C:\Astrophage tag --list
```

Read, in order:

1. `CLAUDE.md`
2. `docs/ARCHITECTURE.md`
3. `docs/MILESTONES.md` — **the M3 section only**
4. `docs/RENDERING.md` — **§3 especially**, that is the whole milestone
5. `src/render/MODULE.md` and `contracts/render_view_v1.h`

You do **not** need `PHYSICS.md` for M3 — optics changes nothing about the simulation.

Verify the baseline, then look at it:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M2
```

```bash
build/astrophage.exe
```

Drag the "charge" slider under **P1: the 3% line** past 3.0058 % and the culture reverses direction. `--ticks-per-frame 200` fast-forwards; the chamber stratifies fully in about two simulated minutes.

## What M3 is

`docs/MILESTONES.md` §M3 and `docs/RENDERING.md` §3. The renderer currently draws flat discs; M3 makes it a microscope.

- Per-instance circle of confusion `r_coc = |z − z_focus| · NA / n`, quad expansion, analytic Gaussian-convolved SDF.
- Diffraction ring: two `smoothstep` bands, amplitude scaled by `(1 − r_coc/a)`. **This does more for the microscopy read than anything else in the milestone.**
- Defocus polarity flip above vs below focus (`sign(z − z_focus)`) — the cue that tells a viewer which way to rack focus.
- Condenser vignette.
- The focal-plane slider already exists in the HUD and is labelled `(focus has no visual effect until M3)`. **Delete that label as part of this milestone.**

**Gate:** M2 gate + golden-image comparison against `goldens/m3_*.png` at three objectives and three focal depths.

**Do not** add a screen-space depth-of-field pass. Cells overlap in projection and a screen-space pass gets overlapping depths wrong; it must be per-instance.

**Capture goldens with `--ticks-per-frame`,** not the real-time accumulator, or the images are machine-dependent. `--objective`, `--zoom`, `--screenshot`, `--seed`, and `--frames` are all already wired for exactly this. `tools/goldgen` does not exist yet; M3 should add it, and `.gitattributes` already marks `goldens/**` binary.

**The depth of field is 1.53 μm inside a 60 μm chamber.** Most cells will be badly out of focus and only a thin layer sharp. That is correct and is the entire point — resist the urge to soften it.

## Traps worth knowing

- **`build.ps1 -App`** whenever the executable matters. `gate.ps1` handles this itself from M1 on.
- **No physical literals in `src/sim` or `src/fields`** — `audit.ps1` A9 greps three patterns. Maths constants go in `core/units.h`, not canon. (`src/render` is not scanned, but A10 checks it for cell size fudging.)
- **`<glad/gl.h>` before `<cuda_gl_interop.h>`.**
- **The oracle is authoritative.** `docs/VERIFICATION.md` is computed independently of the simulator; if they disagree, the simulator is wrong. It has already caught two real errors (ADR-016, and the split viscosity model).
- **Do not weaken a gate to pass it.** When T14's threshold did not hold, the answer was that the *statistic* was wrong, and the corrected test is stricter. That is the usual shape of these.

## Open questions carried forward

- **Q1** — App `--headless` (hidden window) and `tools/headless` (never links GL) stay separate deliberately; merging would drag GL into the determinism oracle.
- **Q4** — Benchmark worst-frame ~13 ms against a 1.26 ms mean. Almost certainly first-touch or driver hitching. If it survives into M5, take a Nsight look.
- **Q5 (new)** — Nothing zeroes cell velocity when `world_create` re-spawns into an existing store, because M2 always spawns into a fresh world. When M9 adds slot reuse, confirm `spawn_kernel` clears `vx/vy/vz` — it does today, but only incidentally.
- **Q6 (new)** — `MotionConfig::thermal_noise` is off only in tests. If a scenario ever wants it off, it needs plumbing through `scenario_v1.h`, which currently has no field for it.
