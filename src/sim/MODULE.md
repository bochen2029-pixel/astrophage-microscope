# MODULE: sim

**Depends on: `core`, `fields`.** No GL, no GLFW, no ImGui, no windowing — ever (INV-5, grep-gated by `audit.ps1`).

## Purpose

The simulation itself: the cell and Taumoeba stores, the integrator, and every per-tick physics stage. Runs entirely in device memory; the only routine host traffic is the `Stats` struct.

## Files

| File | Owns | Milestone |
|---|---|---|
| `cell_store.{cuh,cu}` | ✅ SoA allocation, spawn, prefix-sum slots, stable compaction (ADR-028) | M1/M9c |
| `world.cuh` + `step.cu` | ✅ world lifetime, the tick sequence, `Stats` | M1 |
| `integrator.{cuh,cu}` | ✅ exact joint position–velocity OU propagator, buoyancy, boundaries (PHYSICS.md §3, ADR-016) | M2 |
| `hash.cu` | spatial hash by counting sort; SoA reorder | M4 |
| `contact.cu` | soft-sphere repulsion, wall adhesion | M4 |
| `thermal.cu` | ignition latch, thermostat, conduction (PHYSICS.md §5) | M6 |
| `emission.cu` | Petrova emission, directionality, photon thrust | M7 |
| `taxis.{cuh,cu}` | ✅ run-and-tumble FEED/BREED/IDLE controller, emission discharge (PHYSICS.md §8, ADR-022) | M8 |
| `lifecycle.{cuh,cu}` | ✅ CO₂ uptake, mitosis, prefix-sum slots (ADR-025); overheat death and store disposition (ADR-004) | M9a/M9b |
| `stats.cu` | ✅ tick stage 11, fixed-point telemetry reduction (ADR-026) | M9b |
| `json.h` + `scenario.{h,cpp}` | ✅ hand-rolled jsonc reader; scenario load, world instantiation, and the v2 driving script `scenario_apply_drive` (docs/SCENARIOS.md, ADR-032) | M11a/M11b |
| `accept.{h,cpp}` | ✅ acceptance evaluation + derived metrics (displacement velocities, correlations, `biology_rate`-scaled doubling, flash impulse) shared by headless and the UI (ADR-032) | M11b |
| `flash.cu` | ✅ the spin-drive flash: stimulated full-rate discharge, fixed-point momentum/energy audit (PHYSICS.md §6, ADR-033) | M11b |
| `step.cu` | ✅ tick sequence, the multi-rate clock and its presets (ADR-011, ADR-027) | M1/M9c |
| `predation.{cuh,cu}` | ✅ TaumoebaStore, crawl, deterministic engulfment, digestion (M10a); N₂ lethality, heritable tolerance, division + stable compaction, the Taumoeba-82.5 arc (M10b) | M10b |
| `snapshot.cpp` | serialise/restore, FNV-1a state hash | M12 |

## Contracts

Produces `cell_store_v1.h`, `snapshot_v1.h`. Consumes `fields_v1.h`, `scenario_v2.h`, `telemetry_v1.h`.

## Invariants owned

**INV-1, INV-3, INV-4, INV-5, INV-6, INV-7, INV-8** — essentially all of them. `sim` is where determinism is won or lost.

## Things that will bite you

- **Kernel bodies must be thin loops over `__host__ __device__` functions.** Physics that exists only inside a `__global__` body is untestable and violates Iron Rule 5. This is why `test_motion` can verify the real integrator on the host.
- **`lifecycle` runs last** in the tick. It mutates the store; anything after it reads stale indices.
- **`mass` is never stored.** It is `biomass + energy/c²`, recomputed. An accumulating mass field drifts and silently breaks the energy ledger.
- **The 800× mass spread** between empty and full cells is why the integrator is an exact-propagator OU update rather than anything simpler. Read PHYSICS.md §3.1 before touching it.
- **Never special-case P1–P5** — or the Taumoeba-82.5 arc. If you are writing an `if` to make a signature phenomenon or the 0.825 strain happen, the model is wrong somewhere upstream. Selection does the work.
- **The Taumoeba `biomass` field is DRY biomass** (`TAU_MASS_DRY`), the growth variable it divides on — NOT the water-blob mass `TAU_MASS`, which sets only its drag. They are as distinct as a cell's `CELL_MASS_DRY` and total mass. Conflating them makes a division need ~2655 prey instead of ~8, and no evolution arc can run (ADR-030).
- **The N₂ death draws one uniform *unconditionally*** from each alive Taumoeba's stream — survivor and dier alike. Drawing only in the death branch would make the stream depend on the N₂ history and silently break the determinism the gate rests on (ADR-022).

## Status

**M11b complete.** All five signature phenomena are live (M2–M7), cells behave and live
(M8–M9c), the Taumoeba predator crawls, engulfs, and evolves (M10), and the eight scenarios
now load, drive themselves, and pass their acceptance blocks (M11).

**Driving and acceptance (M11b, ADR-032/033).** `scenario_apply_drive` applies a scripted
`Stimulus` list each tick (heat/N₂ ramp/flash); `accept.cpp` measures each objective from
`Stats` + a `RunAggregates`. Two subtleties: the velocity metric is **displacement-based**
(instantaneous velocity is 8× thermal noise), and doubling time scales by `biology_rate`
(sim time × biology_rate is culture time). `thermal_step` is now skippable (`thermal_enabled`)
for uniform-medium scenarios, and `flash_step` (stage 9b) is a no-op unless armed — both
default to the M9b/M11a behaviour, so determinism is preserved.

**The clock (ADR-011, ADR-027).** `world_step` advances every physics stage by
`dt = DT_PHYSICS * physics_rate`; `biology_rate` scales only the growth dt inside
`lifecycle_step`, compounding with physics. Two couplings are handled at the source, not
clamped: field diffusion substeps are derived from the actual dt (`substeps_for_dt`), and
contact stiffness scales as `1/physics_rate` so an explicit spring never diverges and
ejects a cell. **At `physics_rate == 1` every byte is identical to M9b** — that is the
regression guard. Q19 is decided: `biology_rate` does not scale CO₂ diffusion, so fast
biology is transport-limited by design, and the HUD says so.

**Compaction (ADR-028), off by default.** `cell_store_compact` packs live occupants into
`[0, live)` by an exclusive prefix sum (`cub::DeviceScan`, which also replaced the serial
birth scan — Q20). It is stable and out-of-place, so it is a pure function of the flags
and cannot perturb determinism even though it reorders the SoA (ADR-018's hazard). Deaths
are counted **cumulatively** on the host, because differencing the live dead count would
go negative the instant a corpse is reclaimed.

Earlier state, still true: run-and-tumble taxis climbs the culture's own self-shadowing
gradient, emission debits the store, cells divide bit-reproducibly (the claim ADR-014 was
made for), they die of heat, and their stores go somewhere the user chooses.

`world_stats` now runs the stage-11 reduction and ends in a D2H copy, so it is **not
free** — call it at HUD rate, never per tick (ARCHITECTURE.md §3.1). Everything
accumulates in fixed point because a float sum would be order-dependent, not because it
would be inaccurate (ADR-026).

Before touching `lifecycle.{cuh,cu}`, read ADR-025:
- **Daughter slots come from an exclusive prefix sum, never `atomicAdd`.** The snapshot
  hash is over the SoA in slot order, so order-dependent allocation breaks T22.
- **CO₂ uptake rations collectively.** A per-cell clamp still lets N cells in one grid
  cell take N times its contents; and demand must be booked in the field's own units,
  or fixed point rounds it to zero and the ration silently never fires.
- **`biology_rate` does not scale diffusion** (Q19), so at high rates growth becomes
  locally diffusion-limited. That is the clock, not a growth bug.

Two things to know before touching `taxis.{cuh,cu}` — both are in ADR-022:
- **The IDLE path must never draw a random number.** That is what makes a dark chamber
  *bit-identical* to a taxis-disabled run (T26.8) instead of merely similar to it.
- **`TAXIS_RUN_MAX` is not decoration.** It is what stops a cell that outruns its own
  depletion halo from running forever. M9a added that uptake, so it is live now.

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
