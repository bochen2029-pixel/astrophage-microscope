# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m3-green`. Next milestone: M4 — Neighbourhood.**

The renderer is a microscope and the physics is real. 200,000 cells with full defocus at ~426 fps, 11 tests green, 8 goldens, 7 audit checks clean.

```
test_canon ......... generated constants consistent; the right params carry the canon lock
test_rng ........... PCG32 vs reference vectors, stream independence, gaussian moments
test_contracts ..... POD/layout/version guards, FNV-1a, deposit headroom
test_fixed_atomic .. identical sums across 4 block sizes (INV-2, INV-4)
test_octahedral .... direction packing round trip
test_cell_store .... spawn placement, INV-1 stream independence, capacity
test_scope ......... scale bar at 3 objectives, true cell size, cursor-anchored zoom
test_motion ........ T1-T4, T6, T8 against the oracle; OU branches; boundaries
test_buoyancy ...... T14: drift velocity linear in charge, zero crossing at 3.00577%
test_optics ........ DOF, energy conservation under defocus, polarity, sharp fraction
determinism_replay . real World, seed- and population-sensitive (INV-8)
goldens ............ 8 images, bit-exact, plus 3 "must differ" pairs (ADR-017)
```

## Start here

```bash
git -C C:\Astrophage tag --list
```

Read, in order: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M4 section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§9 only** → `src/sim/MODULE.md` → `contracts/cell_store_v1.h`.

You do **not** need `RENDERING.md` for M4.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M3
```

```bash
build/astrophage.exe
```

Rack the **focal plane** slider and watch cells resolve and dissolve; the gauge under it shows how thin the sharp band is. Drag the **charge** slider past 3.0058 % and the culture reverses direction. `--ticks-per-frame 200` fast-forwards.

## What M4 is

`docs/MILESTONES.md` §M4 and `docs/PHYSICS.md` §9.

- **Spatial hash** over chamber cells of 2.2 × `CELL_DIAMETER`: count → prefix sum → scatter. Counting sort, so it is order-stable (INV-7). This is tick stage 1 and everything after M4 depends on it — contact, predation, the taxis density sense, and the M6 analytic near-field correction all need neighbours.
- **Soft-sphere contact**, `CONTACT_STIFFNESS · overlap`.
- **Wall adhesion** with `WALL_STICKINESS` / `WALL_STUCK_DRAG_MULT`.
- **Reorder the SoA by hash cell** each tick for coalescing.

**Gate:** M3 gate + rest overlap < 5 % of diameter in a packed cluster; no cell escapes over 10⁵ ticks; determinism hash unchanged when block size varies (INV-4); hash rebuild < 0.5 ms at 200k cells. `gate.ps1` already references `test_contact` and `test_hash`.

**The determinism trap in this milestone.** Reordering the SoA changes which slot a cell occupies. Per-cell RNG streams are keyed on `id`, not slot, so trajectories survive — **that is exactly what ADR-014 bought you** — but anything that accidentally keys on slot index will silently break INV-8. The `determinism_replay` gate already asserts that halving the population changes the hash; make sure it still passes *and* that a run with reordering enabled matches one without.

## Traps worth knowing

- **`build.ps1 -App`** whenever the executable matters.
- **No physical literals in `src/sim` or `src/fields`** — `audit.ps1` A9 greps three patterns. Maths constants go in `core/units.h`, not canon.
- **The oracle is authoritative.** `docs/VERIFICATION.md` is computed independently of the simulator. It has already caught three real errors (ADR-016, the split viscosity model, and a wrong tabulated viscosity).
- **Do not weaken a gate to pass it.** Three times now the failing threshold was the *test's* fault and the corrected test came out stricter. When a gate fails, first ask whether it is asking the right question.
- **Do not guess a numeric threshold.** Derive it, or assert the derived quantity and keep the qualitative bound loose. Two `test_optics` assertions failed this session purely because I invented cutoffs (`r > 4a`, `peak < 0.06`) that the real physics (3.9a, 0.0617) just missed.
- **Regenerating goldens requires a `DECISIONS.md` entry in the same commit** (Iron Rule 10). If an M4 change legitimately alters the render, say why.

## Open questions carried forward

- **Q1** — App `--headless` (hidden window) and `tools/headless` (never links GL) stay separate deliberately.
- **Q4** — Benchmark worst-frame was 13.5 ms at M1; with defocus it is now 3.5 ms, so the earlier hitch looks like first-touch allocation rather than a steady-state problem. Consider closed unless it returns.
- **Q5** — When M9 adds slot reuse, confirm `spawn_kernel` clears `vx/vy/vz`. It does today, but only incidentally.
- **Q6** — `MotionConfig::thermal_noise` is off only in tests. A scenario wanting it off needs a field in `scenario_v1.h`.
- **Q7 (new)** — `optics.h` and the GLSL in `cells_pass.cpp` duplicate four formulas with no compiler check between them (ADR-017). If a third consumer ever appears, generate the GLSL from the header rather than adding another copy.
- **Q8 (new)** — Defocus overdraw is the top performance risk for M7's bloom. The cheap fix is culling cells whose peak opacity is below the discard threshold in the vertex stage; worth doing opportunistically if M4/M5 touch the vertex path.
