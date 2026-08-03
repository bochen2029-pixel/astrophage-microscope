# ARCHITECTURE — canon

**Load this every session.** It defines the module boundaries, the invariants, the mandatory vocabulary, and the machinery that keeps a dozens-of-sessions build from drifting. It does not contain physics equations (see `PHYSICS.md`) or milestone scope (see `MILESTONES.md`).

---

## 1. What is being built

A deterministic, GPU-accelerated simulation of an Astrophage culture in a sealed **chamber** of water, observed through a **scope** — a movable, focusable microscope view. Cells are 10 μm; the chamber is 4 mm × 4 mm × 60 μm; the scope at 40× sees 550 μm of it. Physics is real (Stokes drag, Langevin dynamics, Fickian diffusion, conduction, photon momentum); the one fictional element is Astrophage's mass–energy store, and it is canon-locked.

### The five signature phenomena

These are why the project exists. Each **emerges** from the equations in `PHYSICS.md` — none is special-cased anywhere in the code. If you find yourself writing an `if` to make one of these happen, you have made a mistake.

| | Phenomenon | Emerges from |
|---|---|---|
| **P1** | **The 3% line.** Canon mass in a 10 μm sphere ⇒ ρ = 40 kg/m³, so an empty cell *rises* at 52 μm/s; a full cell is 32× denser than water and *sinks* at 1681 μm/s. Neutral buoyancy at exactly 3.006 % charge. Charge state is readable from vertical drift. | mass = biomass + E/c², plus Stokes |
| **P2** | **The perfect thermostat.** 96.415 °C sits 3.585 K below water's boiling point, and heat output → 0 as the medium approaches the setpoint. A culture pins its medium to 96.415 °C and **can never boil it at 1 atm**. Overheat it externally and the cells absorb the excess and drag it back. | bidirectional thermostat + conduction |
| **P3** | **Ignition.** Dormant cells are inert powder. Cross the setpoint once and the culture wakes irreversibly, then holds temperature even as you chill it. | the dormancy latch |
| **P4** | **Live cells move.** A live cell warms its neighbourhood, viscosity drops 3.4×, Brownian diffusivity rises 4.24×. Live and dead are distinguishable by eye, exactly as in the novel. | temperature-dependent viscosity |
| **P5** | **Absolute shadows.** Albedo is exactly 0 at all wavelengths, so cells shadow each other perfectly. A lit monolayer forms and everything behind it starves. | occluded irradiance field |

---

## 2. Glossary — mandatory vocabulary

Using a forbidden synonym fails review. This exists because across dozens of sessions, drifting names silently fork the design.

| Term | Means | Never say |
|---|---|---|
| **Cell** | one Astrophage organism | particle, agent, dot, sphere, bug |
| **Taumoeba** | the predator organism (singular and plural) | amoeba, predator agent, taumoebas |
| **Chamber** | the simulated volume, 4 mm × 4 mm × 60 μm | world, box, domain, scene, slide |
| **Scope** | the microscope view onto the chamber | camera, viewport, window |
| **Charge** | stored energy as a fraction of `CELL_ENERGY_MAX` | energy level, fuel, battery, power |
| **Store** | the joules held as neutrino mass; also a SoA container (`CellStore`) | reservoir, tank |
| **Awake / Dormant** | thermostat engaged / inert powder | active/inactive, on/off, alive/dead |
| **Alive / Dead / Corpse** | biological state; orthogonal to awake | — |
| **Petrova** | the 25.984 μm emission, and anything about it | IR, infrared, laser, glow |
| **Field** | a grid-resident scalar quantity (T, CO₂, N₂, irradiance) | map, texture, buffer, grid (as a noun for the quantity) |
| **Deposit / Sample** | a cell writing to / reading from a field | splat, gather, scatter |
| **Ignition** | the dormant → awake transition | activation, waking up, boot |
| **Tick** | one fixed physics step of `DT_PHYSICS` | frame, update, iteration |
| **Frame** | one rendered image; N ticks per frame is variable | tick, update |

---

## 3. System architecture

### 3.1 Where data lives

**Simulation state lives in device memory and never round-trips to the host in the steady state.** This is the central performance decision and it shapes everything else.

```
                         HOST (C++20)                      DEVICE (CUDA, sm_89)
  app ──── main loop ──────────────────────────────┐
   │        │  fixed-tick accumulator              │   ┌──────────────────────────┐
   │        │                                      ├──▶│  CellStore   (SoA, d_*)  │
   │        └── sim::step(world, dt) ──────────────┤   │  TaumoebaStore (SoA)     │
   │              launches ~12 kernels             │   │  Field grids  T/CO2/N2/E │
   │                                               │   │  Spatial hash + sort     │
   │  ui  ─── ImGui panels ◀── Stats (small D2H) ──┤   │  Deposit accumulators    │
   │                                               │   │      (fixed-point i64)   │
   └─ render ── GL 4.6 ◀── CUDA-GL interop ────────┘   └──────────────────────────┘
                 │            (instance VBO written by a kernel; zero host copy)
                 └── instanced draw, 1 call for N cells
```

- The only per-tick host↔device traffic is a small `Stats` struct (counts, means, energy ledger) copied D2H at ~30 Hz, not every tick.
- Render instance data is written **by a CUDA kernel directly into a GL buffer** registered via `cudaGraphicsGLRegisterBuffer`. Cell positions never touch host memory.
- Snapshots (§5.4) are the deliberate exception: a full D2H copy, only on demand.

### 3.2 Thread and process model

Single process, single host thread for the main loop. Concurrency is on the GPU. No CPU worker pool — it would buy nothing and cost determinism.

- **Fixed-tick accumulator.** Render frame rate floats; `DT_PHYSICS` never does. Max 8 ticks per frame (drop simulated time rather than spiral).
- **Render interpolation** between the last two tick states via an `alpha` blend in the vertex shader.

### 3.3 Host/device shared code

Pure math and per-cell physics kernels are written as `__host__ __device__` inline functions in headers under `core/` and `sim/`. This is deliberate and load-bearing:

- Device code calls them from kernels.
- **Unit tests call the exact same functions on the host**, so `tests/physics/` verifies the real code path with no GPU required for the analytic tests.
- Integration and determinism tests do require a CUDA device.

Any physics that exists only inside a `__global__` kernel body is untestable and violates Iron Rule 5. Kernel bodies should be thin loops over `__host__ __device__` functions.

### 3.4 Tick sequence

Fixed order. Do not reorder — fields are read and written within a single tick.

| # | Stage | Kernel(s) | Notes |
|---|---|---|---|
| 1 | `hash_build` | count, prefix-sum, scatter | counting sort by chamber grid cell; deterministic |
| 2 | `field_sample` | one kernel | bilinear sample of T, CO₂, N₂, E into per-cell scratch; **plus the analytic near-field halo correction** (ADR-010) |
| 3 | `taxis` | one kernel | run-and-tumble state machine; sets `emit_power`, emission axis |
| 4 | `thermal` | one kernel | conduction Q, energy transfer, ignition latch, deposit accumulation |
| 5 | `forces` | one kernel | buoyant weight, photon thrust, contact (uses the hash), adhesion |
| 6 | `integrate` | one kernel | OU velocity update, position update, boundary handling |
| 7 | `field_deposit` | one kernel | fixed-point atomic scatter into T/CO₂/N₂ accumulators |
| 8 | `field_diffuse` | substepped stencil | explicit red-black; substep counts in `VERIFICATION.md` §6 |
| 9 | `irradiance` | occlusion sweep + march | rebuilt from scratch each tick |
| 10 | `predation` | crawl, engulf, N₂ death, Taumoeba division + compaction | mutates the **Taumoeba** store; kills prey before lifecycle disposes of them |
| 11 | `lifecycle` | uptake, division, death, compaction | **mutates the cell store; must be last** |
| 12 | `stats` | deterministic tree reduction | run at HUD rate from `world_stats`, not every tick; never `atomicAdd` on float (INV-2) |

---

## 4. Invariants

These override convenience, performance, and elegance. `audit.ps1` mechanically checks INV-1, INV-2, INV-5, INV-6, INV-7; INV-3, INV-4, INV-8 are checked by the determinism test.

- **INV-1 — One RNG, per-cell streams.** PCG32 only, state stored per cell, seeded `seed_global ^ hash(cell_id)`. Never `curand` default sequences (they key off thread index, so a population change reshuffles every cell's draws), never `rand()`, never any host RNG in `sim`. Daughters get `pcg_split(parent_state, daughter_id)`.
- **INV-2 — No float atomics where order matters.** Field deposits and statistics accumulate into **64-bit fixed-point integers** (`atomicAdd` on `unsigned long long`), converted at the end. Integer addition is associative; float addition is not, so `atomicAdd(float*)` makes results depend on warp scheduling. This single rule is what makes GPU determinism achievable at all.
- **INV-3 — No wall clock in the simulation.** Simulated time is `tick_index * DT_PHYSICS`. `sim/` and `fields/` never call any clock.
- **INV-4 — Results are independent of launch configuration.** Block size, grid size, and occupancy may change freely without changing output. No inter-block ordering assumptions.
- **INV-5 — `sim/` and `fields/` contain no presentation code.** No GL, GLFW, ImGui, or windowing header may appear. Grep-gated. They must link and run headless.
- **INV-6 — No fast-math in the simulation.** `-use_fast_math`, `--ftz=true`, and `--prec-div=false` are forbidden in `sim`/`fields` targets. FMA contraction is permitted (determinism is guaranteed *within a build*, not across compiler versions).
- **INV-7 — Stable iteration order.** Iterate SoA by index. No hash-map or set iteration in the hot path. The spatial hash is built by counting sort, which is order-stable.
- **INV-8 — The snapshot hash is the determinism oracle.** Same seed + same scenario + same tick count ⇒ identical FNV-1a hash of the full state. The determinism test asserts it, including across runs where cells divide and die.

---

## 5. Anti-drift machinery

Four mechanisms, each targeting a specific way long multi-session builds decay.

### 5.1 Generated canon — kills constant drift

`scripts/canon.py` is the sole source of every physical number. `scripts/derive.py` computes all derived quantities and emits three artifacts:

```
scripts/canon.py ──derive.py──┬──▶ src/core/canon_generated.h     (constexpr + provenance table)
                              ├──▶ tests/golden/expected_values.h (oracle expectations)
                              └──▶ docs/VERIFICATION.md           (derivation report)
```

A hand-copied constant cannot drift between doc, code, and test because none of the three is hand-written. `audit.ps1` runs `derive.py --check` and fails if any artifact is stale.

### 5.2 Contracts — kills interface drift and enables module-scoped sessions

`contracts/*_v1.h` are versioned, dependency-free C/C++ headers defining every cross-module interface. **A session working on `render` reads `contracts/`, never `src/sim/`.** This is what makes it possible to work one module per session without loading the rest.

Changing a contract is a deliberate act: bump to `_v2.h`, update every consumer, note it in `DECISIONS.md`, all in one commit.

### 5.3 Gates — kills "I think it works"

`gate.ps1 -Milestone M<N>` is a script that exits 0 or nonzero. Green → `git tag m<N>-green`. `git tag --list` is therefore a complete, trustworthy, zero-context status report for any cold session. Milestone gates never weaken: every gate re-runs all earlier gates.

### 5.4 Snapshots — kills irreproducibility

Binary full-state dump (`ASPH` magic, version, seed, tick, param overrides, SoA buffers, field grids). Restores bit-identically within one build. Used for save/load, the time scrubber, regression fixtures, and the INV-8 determinism oracle.

---

## 6. The provenance system

Every parameter carries a tag through the entire stack: `canon.py` → `canon_generated.h` `PARAM_TABLE` → the UI parameter inspector.

| Tag | Meaning | UI treatment |
|---|---|---|
| `CANON` | stated in *Project Hail Mary* | gold badge, **locked**; unlocking sets a persistent `NON-CANON RUN` flag on the HUD and in telemetry exports |
| `DERIVED` | computed from canon + real physics | blue badge, read-only, shows the formula |
| `REAL` | real-world constant or material property | grey badge, unlocked |
| `INVENTED` | our choice; canon is silent | orange badge, unlocked, freely tunable |

This turns the honest bookkeeping of the source research into a feature: a user can always see which numbers Weir wrote and which we made up. It is also the mechanism by which the two unresolvable canon contradictions (ADR-002, ADR-003) ship as *playable options* rather than as silent decisions.

---

## 7. Module inventory

Must match the directory listing exactly — `audit.ps1` checks this.

```
src/core     canon_generated.h, units.h, rng.cuh, vec.cuh, fixed_atomic.cuh, result.h
src/fields   grid.cuh, diffuse.cu, irradiance.cu
src/sim      cell_store.cu, integrator.cu, thermal.cu, emission.cu, taxis.cu,
             contact.cu, lifecycle.cu, predation.cu, hash.cu, snapshot.cpp, stats.cu, step.cu
src/render   gl_context.cpp, interop.cu, cells_pass.cpp, field_pass.cpp,
             optics.cpp, morphology.h, post_pass.cpp, bloom.cpp, luts.cpp, camera.cpp
src/ui       hud.cpp, inspector_panel.cpp, params_panel.cpp, instrument_panel.cpp,
             chart_panel.cpp, scenario_panel.cpp
src/app      main.cpp, application.cpp, cli.cpp
tools        headless.cpp, goldgen.cpp
contracts    cell_store_v1.h, fields_v1.h, render_view_v1.h, render_view_v2.h,
             scenario_v1.h, telemetry_v1.h, snapshot_v1.h
```

Each `src/<module>/MODULE.md` states: purpose, owned files, contracts consumed and produced, invariants it is responsible for, current milestone status, and known gaps.

---

## 8. Multi-session working agreement

- **One milestone per session.** If it will not fit, split it in `MILESTONES.md` before starting and give each half a gate.
- **The tag is the truth.** Docs describe intent; tags describe reality. When they disagree, believe the tag and fix the doc.
- **`_run_state/NEXT_SESSION.md` is written at the end of every session**, not the beginning of the next one. It is the handoff, and writing it is the last thing you do.
- **Never load the whole repo.** `ARCHITECTURE.md` + one milestone + one `MODULE.md` + the contracts it uses is the correct working set.
- **When you disagree with a decision, read `DECISIONS.md` first.** Every contradiction in the source material has already been adjudicated there, with the reasoning and the escape hatch. Re-litigating costs a session; reading costs a minute.
- **Leave the build green.** A session that ends red costs the next session its entire budget on archaeology. If you cannot finish, revert to green and log what you learned.
