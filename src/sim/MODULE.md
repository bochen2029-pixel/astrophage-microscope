# MODULE: sim

**Depends on: `core`, `fields`.** No GL, no GLFW, no ImGui, no windowing — ever (INV-5, grep-gated by `audit.ps1`).

## Purpose

The simulation itself: the cell and Taumoeba stores, the integrator, and every per-tick physics stage. Runs entirely in device memory; the only routine host traffic is the `Stats` struct.

## Files

| File | Owns | Milestone |
|---|---|---|
| `cell_store.{cuh,cu}` | ✅ SoA allocation, spawn, free list (compaction at M9) | M1 |
| `world.cuh` + `step.cu` | ✅ world lifetime, the tick sequence, `Stats` | M1 |
| `integrator.{cuh,cu}` | ✅ exact joint position–velocity OU propagator, buoyancy, boundaries (PHYSICS.md §3, ADR-016) | M2 |
| `hash.cu` | spatial hash by counting sort; SoA reorder | M4 |
| `contact.cu` | soft-sphere repulsion, wall adhesion | M4 |
| `thermal.cu` | ignition latch, thermostat, conduction (PHYSICS.md §5) | M6 |
| `emission.cu` | Petrova emission, directionality, photon thrust | M7 |
| `taxis.{cuh,cu}` | ✅ run-and-tumble FEED/BREED/IDLE controller, emission discharge (PHYSICS.md §8, ADR-022) | M8 |
| `lifecycle.cu` | mitosis, death, corpses, store disposition | M9 |
| `predation.cu` | Taumoeba store, engulfment, N₂ lethality, evolution | M10 |
| `snapshot.cpp` | serialise/restore, FNV-1a state hash | M12 |

## Contracts

Produces `cell_store_v1.h`, `snapshot_v1.h`. Consumes `fields_v1.h`, `scenario_v1.h`, `telemetry_v1.h`.

## Invariants owned

**INV-1, INV-3, INV-4, INV-5, INV-6, INV-7, INV-8** — essentially all of them. `sim` is where determinism is won or lost.

## Things that will bite you

- **Kernel bodies must be thin loops over `__host__ __device__` functions.** Physics that exists only inside a `__global__` body is untestable and violates Iron Rule 5. This is why `test_motion` can verify the real integrator on the host.
- **`lifecycle` runs last** in the tick. It mutates the store; anything after it reads stale indices.
- **`mass` is never stored.** It is `biomass + energy/c²`, recomputed. An accumulating mass field drifts and silently breaks the energy ledger.
- **The 800× mass spread** between empty and full cells is why the integrator is an exact-propagator OU update rather than anything simpler. Read PHYSICS.md §3.1 before touching it.
- **Never special-case P1–P5.** If you are writing an `if` to make a signature phenomenon happen, the model is wrong somewhere upstream.

## Status

**M8 complete.** All five signature phenomena are live (M2–M7), and cells now behave:
run-and-tumble taxis climbs the culture's own self-shadowing gradient, and emission
finally debits the store.

`world_stats` still returns only tick, time, and counts. The means and the energy ledger
need a deterministic device reduction (INV-2: tree or fixed-point, never `atomicAdd` on
float) and land with **M9**, whose charts are their first real consumer. The HUD hides
what is not yet computed rather than displaying a plausible-looking zero.

Two things to know before touching `taxis.{cuh,cu}` — both are in ADR-022:
- **The IDLE path must never draw a random number.** That is what makes a dark chamber
  *bit-identical* to a taxis-disabled run (T26.8) instead of merely similar to it.
- **`TAXIS_RUN_MAX` is not decoration.** It is what stops a cell that outruns its own
  depletion halo from running forever once M9 adds CO₂ uptake.

**Before you touch `integrator.cuh`, read ADR-016.** The obvious scheme — propagate
velocity exactly, then `r += v·dt` — is wrong by 47× in diffusion for an empty cell,
because velocity fully decorrelates inside one timestep at `dt/τ = 4497`. The joint
position–velocity propagator with its correlated 2×2 noise is not decoration.

Two further traps in that file:
- **`ou_position_shape` has two branches.** `2x − 3 + 4e⁻ˣ − e⁻²ˣ` cancels to zero in
  its first three orders, so below `x ≈ 1e-2` the direct form returns noise instead of
  `(2/3)x³`. Both branches and the crossover are pinned by `test_motion`.
- **"Reflecting" means rest, not bounce.** At Re ≪ 1 there is no inertia to rebound
  with; a mirror reflection would inject energy that does not exist. Clamp the
  position, zero the normal velocity.
