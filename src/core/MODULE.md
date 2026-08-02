# MODULE: core

**Depends on: nothing.** Standard library and CUDA intrinsics only. If `core` ever gains a dependency, the layering has failed.

## Purpose

Generated canon, deterministic RNG, unit discipline, vector math, and the fixed-point accumulation that makes GPU determinism possible.

## Files

| File | Owns |
|---|---|
| `canon_generated.h` | **GENERATED — never edit.** Every physical constant + the `PARAM_TABLE` provenance table. Source: `scripts/canon.py`. |
| `units.h` | `ASTRO_HD` host/device bridge; SI ↔ display conversions (the only sanctioned conversion points) |
| `rng.cuh` | PCG32, per-cell streams, `pcg_split`, uniform and gaussian variates |
| `vec.cuh` | `Vec3` (f64) for kinematics |
| `fixed_atomic.cuh` | int64 fixed-point deposit and reduction (INV-2) |
| `result.h` | `Status` / `Error` typed results; `ASTRO_TRY` |

## Contracts

Produces none. Consumed by every other module.

## Invariants owned

- **INV-1** — PCG32 with per-cell streams is the *only* RNG. `rng.cuh` is the sole source; nothing else may generate randomness.
- **INV-2** — `fixed_atomic.cuh` is the only sanctioned accumulation path for deposits and statistics.
- **Units** — SI only. `units.h` conversions are for `ui/` and `render/`.

## Things that will bite you

- `ASTRO_HD` lets these headers compile under MSVC as well as nvcc, which is what allows `tests/` to exercise the real physics functions on the host (ARCHITECTURE.md §3.3). Do not add device-only code to a header without guarding it with `#if defined(__CUDACC__)`.
- Only 64 bits of RNG state are stored per cell. The stream selector is reconstructed from the cell's `id` via `cell_stream_inc`. If you ever change that derivation, every existing snapshot's trajectory changes.
- `Vec3` is f64 and on sm_89 fp64 runs at 1/64 rate. It belongs in the integrator and the energy ledger, nowhere else.

## Status

M0 complete. Tested by `test_canon`, `test_rng`, `test_fixed_atomic`.
