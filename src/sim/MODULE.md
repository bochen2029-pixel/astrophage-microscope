# MODULE: sim

**Depends on: `core`, `fields`.** No GL, no GLFW, no ImGui, no windowing — ever (INV-5, grep-gated by `audit.ps1`).

## Purpose

The simulation itself: the cell and Taumoeba stores, the integrator, and every per-tick physics stage. Runs entirely in device memory; the only routine host traffic is the `Stats` struct.

## Files

| File | Owns | Milestone |
|---|---|---|
| `sim_placeholder.cu` | M0 scaffold — **delete when `cell_store.cu` lands** | M0 |
| `cell_store.cu` | SoA allocation, spawn, free list, compaction | M1 |
| `integrator.cu` | exact-propagator OU update (PHYSICS.md §3) | M2 |
| `hash.cu` | spatial hash by counting sort; SoA reorder | M4 |
| `contact.cu` | soft-sphere repulsion, wall adhesion | M4 |
| `thermal.cu` | ignition latch, thermostat, conduction (PHYSICS.md §5) | M6 |
| `emission.cu` | Petrova emission, directionality, photon thrust | M7 |
| `taxis.cu` | run-and-tumble FEED/BREED/IDLE controller | M8 |
| `lifecycle.cu` | mitosis, death, corpses, store disposition | M9 |
| `predation.cu` | Taumoeba store, engulfment, N₂ lethality, evolution | M10 |
| `snapshot.cpp` | serialise/restore, FNV-1a state hash | M12 |
| `step.cu` | the tick sequence (ARCHITECTURE.md §3.4) | M1+ |

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

M0 scaffold only. Physics begins at M2.
