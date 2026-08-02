# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m1-green`. Next milestone: M2 — Motion.**

The simulator draws. 200,000 cells in one instanced draw at ~795 fps on the reference GPU (target 144), zero GL debug errors, 8 tests green, 7 audit invariant checks clean.

```
test_canon ......... generated constants internally consistent; the right params carry the canon lock
test_rng ........... PCG32 vs reference vectors, stream independence, gaussian moments
test_contracts ..... POD/layout/version guards, FNV-1a, deposit headroom
test_fixed_atomic .. identical sums across 4 block sizes (INV-2, INV-4)
test_octahedral .... direction packing round trip, <0.05 deg worst case
test_cell_store .... spawn placement, INV-1 stream independence, capacity, id monotonicity
test_scope ......... scale bar at 3 objectives across the zoom range, true cell size, cursor-anchored zoom
determinism_replay . 10k ticks, same hash twice, seed-sensitive (INV-8)
```

## Start here

```bash
git -C C:\Astrophage tag --list
```

Then read, in order:

1. `CLAUDE.md` — operating contract.
2. `docs/ARCHITECTURE.md` — module map, INV-1..INV-8, glossary.
3. `docs/MILESTONES.md` — **the M2 section only**.
4. `docs/PHYSICS.md` — **§1–§4 only**. §3 is the integrator; read §3.1 before writing a line of it.
5. `src/sim/MODULE.md` and `contracts/cell_store_v1.h`.

You do **not** need `RENDERING.md` for M2 — the renderer already draws whatever the store contains, and motion needs no render change.

Verify the baseline before changing anything:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M1
```

Run it and look at it — the app is real now:

```bash
build/astrophage.exe
```

## What M2 is

`docs/MILESTONES.md` §M2 plus `docs/PHYSICS.md` §3 and §4.

- **`src/sim/integrator.cuh`** — the exact-propagator Ornstein–Uhlenbeck velocity update, as a `__host__ __device__` function so `test_motion` exercises the real code path on the host. **Read PHYSICS.md §3.1 first:** the 800× mass spread between an empty and a full cell means a naive overdamped update is wrong for charged cells and Verlet-with-drag is unstable for empty ones. One exact-propagator path covers both.
- Buoyant weight `−(mass − ρ_w·V)·g·ŷ`, with `mass = biomass + energy/c²` recomputed, never stored.
- Vogel–Fulcher viscosity `μ(T)`, which is what makes P4 work later.
- Boundary handling: reflecting / periodic / absorbing on x,y; reflecting on z.
- Insert `forces` and `integrate` at stages 5 and 6 of `world_step` — the comment list is already there.
- `T_local` is a scenario constant at M2; the temperature field is M5.

**Gate:** M1 gate + T1, T2, T3, T4, T6, T8, T14 against `tests/golden/expected_values.h`. Add `test_motion` and `test_buoyancy` via the `astro_test()` helper; `gate.ps1` already references both names.

**The payoff:** set charge below 3.006 % and the culture rises; above it, it sinks; at 3.006 % it hovers. That is **P1**, and the HUD already prints the neutral-buoyancy figure next to the charge slider.

**Not in M2:** no thermal model, no emission, no fields, no contact.

## Traps worth knowing

- **`build.ps1 -App`** is needed whenever the executable matters. The plain form configures with `ASTRO_BUILD_APP=OFF`. `gate.ps1` handles this itself from M1 on.
- **No physical literals in `src/sim` or `src/fields`.** `audit.ps1` A9 greps three patterns and will catch you. Add to `scripts/canon.py` with a provenance tag and re-run `derive.py`. Maths constants (π) go in `core/units.h`, not canon.
- **Never store `mass`.** It is `biomass + energy/c²`. An accumulating field drifts and silently breaks the energy ledger.
- **Kernel bodies stay thin** — loops over `__host__ __device__` functions. Physics that only exists inside a `__global__` body is untestable and violates Iron Rule 5.
- **`expm1` for `(1 − exp(−dt/τ))`** when `dt/τ` is tiny, or the empty-cell case loses all precision.
- The oracle in `docs/VERIFICATION.md` is computed independently of the simulator. **If they disagree, the simulator is wrong** — do not adjust the oracle.

## Open questions carried forward

- **Q1** — The app's `--headless` (hidden window) and `tools/headless.cpp` (never links GL) remain separate, deliberately: merging them would drag GL into the determinism oracle. Revisit only if the duplication actually hurts.
- **Q3 (new)** — `tools/headless.cpp` still runs the M0 `StubWorld` rather than the real `World`. M2 should switch it over, so the determinism oracle covers the actual integrator instead of a Brownian stand-in. This is the single highest-value cleanup available right now.
- **Q4 (new)** — Benchmark worst-frame is ~13 ms against a 1.26 ms mean. Almost certainly first-touch or driver hitching, not a steady-state problem, but if it survives into M5 it is worth a Nsight look.
