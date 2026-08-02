# MODULE: fields

**Depends on: `core`.** Headless by construction — no presentation headers (INV-5).

## Purpose

The four grid-resident scalar fields — temperature, CO₂, N₂, irradiance — their diffusion solvers, and the occlusion sweep that produces P5.

## Files

| File | Owns | Milestone |
|---|---|---|
| `fields_placeholder.cu` | M0 scaffold; carries the ADR-008 substep `static_assert`s — **delete when `grid.cuh` lands, but move those asserts** | M0 |
| `grid.cuh` | `Grid2D<float>`, bilinear sample and scatter, fixed-point deposit | M5 |
| `diffuse.cu` | explicit red-black FTCS, substepped; Dirichlet/Neumann/Robin BCs | M5 |
| `irradiance.cu` | occlusion raster + directional march; total shadowing | M7 |

## Contracts

Produces `fields_v1.h`. Consumes nothing but `core`.

## Invariants owned

- **INV-2** — deposits go through `atomic_deposit`, never `atomicAdd(float*)`.
- **INV-4** — diffusion and deposit results are independent of block size.

## Things that will bite you

- **Do not raise a grid resolution casually.** Explicit stability is `dt < dx²/(4α)`; substeps scale as N². At 512² the temperature field needs 10 substeps per tick; at 1024² it needs ~38 and memory traffic becomes the dominant cost. `fields_placeholder.cu` has `static_assert`s that turn this into a build break — **keep them alive when that file is deleted**.
- **The near field is analytic, not gridded** (ADR-010). `dx` = 7.8 μm is comparable to a cell diameter, so the thermal halo within a few radii is added at sample time from `T(r) = T∞ + ΔT·a/r`, with the neighbours' already-smeared grid contribution subtracted. Forgetting the subtraction double-counts and the culture runs hot.
- **Irradiance is rebuilt from scratch every tick**, never accumulated. It has no deposit accumulator.
- **Occlusion is total.** Albedo is exactly 0 (canon super cross-sectionality), so irradiance behind a live cell is exactly zero — not "very small". Tests assert exact zero.
- Deposit scales have audited overflow margins in `fields_v1.h`, backed by `static_assert`. Changing one means redoing the arithmetic.

## Status

M0 scaffold only. Real fields begin at M5.
