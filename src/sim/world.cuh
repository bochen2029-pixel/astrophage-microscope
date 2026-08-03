// src/sim/world.cuh -- everything one simulation owns.
//
// The tick sequence is ARCHITECTURE.md Sec 3.4. At M1 `world_step` only advances
// the clock; each later milestone inserts its stage at the documented position
// rather than restructuring the loop.
#pragma once

#include <cstdint>

#include "contracts/scenario_v1.h"
#include "contracts/telemetry_v1.h"
#include "core/canon_generated.h"
#include "core/result.h"
#include "fields/grid.cuh"
#include "sim/cell_store.cuh"
#include "sim/hash.cuh"
#include "sim/integrator.cuh"
#include "sim/predation.cuh"

namespace astro::sim {

// The chamber's scalar fields. Cell coupling arrives at M6; at M5 the only
// sources are tool brushes.
struct Fields {
    fields::Grid2D temperature;
    fields::Grid2D co2;
    fields::Grid2D n2;
    // Rebuilt from scratch every tick, never accumulated, so it has no diffusion
    // and its deposit accumulator is reused as an occlusion buffer.
    fields::Grid2D irradiance;
};

enum class BrushKind : uint8_t { Heat = 0, Chill = 1, InjectCO2 = 2, InjectN2 = 3 };

// Device-side telemetry accumulators, all 64-bit FIXED POINT (INV-2). Float
// atomicAdd is order-dependent, so a float reduction would report a different mean
// depending on how blocks retired. Counts are plain integers, which are already
// order-independent.
struct StatsAccum {
    unsigned long long energy = 0, temp_cell = 0, temp_medium = 0;
    unsigned long long co2 = 0, n2 = 0, max_temp = 0;
    unsigned long long tau_tolerance = 0;    // fixed-point sum over alive Taumoeba (M10b)
    unsigned int n_alive = 0, n_dead = 0, n_awake = 0, n_dormant = 0;
    unsigned int n_taumoeba = 0;             // alive Taumoeba (the Taumoeba-82.5 readout)
};

// Everything the motion stages need. Passed by value into kernels, so POD.
struct MotionConfig {
    Boundary    boundary_x = Boundary::Reflecting;
    Boundary    boundary_y = Boundary::Reflecting;
    GravityAxis gravity_axis = GravityAxis::Y;   // ADR-006
    // Off only for analytic tests, where a terminal velocity must be exact.
    bool        thermal_noise = true;
    bool        contact_enabled = true;
    bool        adhesion_enabled = true;
    bool        thermal_enabled = true;
    bool        emission_enabled = true;
    // Off supplies the null for the M8 migration gate: the identical run with the
    // controller disabled. In darkness the two are bit-identical by construction,
    // because the Idle path draws no random numbers (taxis.cu).
    bool        taxis_enabled = true;
    // Exact per-cell 3D shadowing on top of the grid's far-field extinction.
    bool        occlusion_exact = true;
    double      ambient_temp = canon::AMBIENT_TEMP_DEFAULT;
    // Where a dead cell's 1.5 MJ goes. Canon is silent, so all three readings ship
    // and `void` is the default (ADR-004).
    contract::StoreDisposition store_disposition = contract::StoreDisposition::Void;
    // Reclaim the slots of dead cells (corpses, wall-culls) by stable compaction
    // (ADR-028). OFF by default so an untouched run is bit-identical to M9b; ON
    // trades the persistent graveyard for unbounded growth and lower iteration cost.
    bool        compaction_enabled = false;
    // Same, for the Taumoeba store (M10b). N2 death and division churn it; ON reclaims
    // dead-predator slots so the population can turn over at a bounded capacity. OFF by
    // default keeps M10a bit-identical.
    bool        tau_compaction_enabled = false;
};

struct WorldDesc {
    Chamber  chamber{canon::CHAMBER_W, canon::CHAMBER_H, canon::CHAMBER_D};
    int32_t  capacity = 0;          // 0 = size to the initial population
    int32_t  tau_capacity = 0;      // Taumoeba store capacity; 0 = a small default
    uint64_t seed = 20260802ull;
    MotionConfig motion{};
    // Initial CO2 concentration [kg/m^3]. Zero until something adds some, which
    // before M9a meant only a brush; growth needs a medium to grow in.
    double   co2_init = 0.0;
};

struct World {
    CellStore    cells;
    TaumoebaStore taumoeba;      // the predator population (M10)
    SpatialHash  hash;
    Fields       fields;
    // Per-cell claim buffer for engulfment: a predator atomicMins its id here so
    // the lowest-id predator wins a shared prey deterministically (predation.cu).
    unsigned long long* d_predator_claim = nullptr;
    // Tick stage 5 writes these; stage 6 reads them. They exist SPECIFICALLY so
    // that contact reads every neighbour's position from before the step --
    // computing forces and positions in one kernel is a read/write race and
    // makes the run nondeterministic (ADR-018).
    double*      d_fx = nullptr;
    double*      d_fy = nullptr;
    double*      d_fz = nullptr;
    // Per-CO2-grid-cell uptake demand for the tick, fixed point (INV-2). Exists so
    // an over-subscribed grid cell can be RATIONED: a per-cell clamp still lets N
    // cells sharing one grid cell take N times its contents and drive the field
    // negative (ADR-025).
    unsigned long long* d_co2_demand = nullptr;
    StatsAccum*  d_stats = nullptr;      // tick stage 11
    StatsAccum   stats_host{};           // last D2H copy
    int32_t      divisions_this_window = 0;
    // Deaths are counted cumulatively so compaction (which reclaims corpses,
    // ADR-028) cannot make the per-window count go negative. `deaths_total` is
    // monotonic; world_stats differences it against `deaths_reported`.
    // `dead_slots_prev` is the occupied-dead count carried into the next tick,
    // which is 0 right after a compaction and `deads` otherwise.
    int64_t      deaths_total = 0;
    int64_t      deaths_reported = 0;
    int32_t      dead_slots_prev = 0;
    Chamber      chamber{};
    MotionConfig motion{};
    uint64_t     tick = 0;
    uint64_t     seed = 0;
    double       physics_rate = 1.0;
    double       biology_rate = 1.0;
    // Elapsed SIMULATED time, accumulated per tick. Accumulated rather than
    // tick*DT*physics_rate so that changing the clock mid-run stays correct --
    // dragging the rate slider must not rewrite how much culture time has passed.
    double       sim_time_s = 0.0;

    contract::LightSource light{1.0f, 0.0f, 0.0f, 0.0f, 0};   // off by default
    float        ambient_irradiance = 0.0f;
};

// Tick stages 2, 5, 6 (src/sim/integrator.cu).
void motion_step(World& w, double dt);

// Tick stage 4 (src/sim/thermal.cu). Substepped against the temperature field
// and therefore owns its diffusion; do not diffuse temperature again after it.
void thermal_step(World& w, double dt);

// Tick stage 9 plus the feeding half of stage 3 (src/sim/emission.cu).
void emission_step(World& w, double dt);

// Tick stage 3 (src/sim/taxis.cu). Sets emit_power and the emission axis, and
// debits the store for what it emits.
void taxis_step(World& w, double dt);

// Tick stage 10 (src/sim/predation.cu). Taumoeba crawl and engulfment. Kills prey
// before lifecycle disposes of the corpses. docs/PHYSICS.md Sec 11.
void predation_step(World& w, double dt);

// Tick stage 11 (src/sim/lifecycle.cu). CO2 uptake, death and mitosis. MUTATES THE
// STORE -- it must stay last, because anything after it reads stale indices.
void lifecycle_step(World& w, double dt);

// Tick stage 11 (src/sim/stats.cu). Deterministic fixed-point reduction.
void stats_step(World& w);

// Applied at a tick boundary from the app, never from an input handler --
// writing device memory mid-tick would break INV-8 (src/app/MODULE.md).
Error world_apply_brush(World& w, BrushKind kind, double x, double y,
                        double radius, double strength);

Error world_create(World& w, const WorldDesc& d);
void  world_destroy(World& w);

// One fixed tick. Called only from app's accumulator (src/app/MODULE.md).
void  world_step(World& w);

// Simulated time in seconds. The ONLY clock the simulation has (INV-3).
double world_sim_time(const World& w);

// Named clock presets -> (physics_rate, biology_rate). ADR-011, ADR-027. Custom
// returns the Realtime identity; a caller supplies its own rates for Custom.
void clock_preset_rates(contract::ClockPreset preset, double& physics, double& biology);

// Set the clock from a preset, or from explicit rates when preset == Custom,
// clamping each to its ADR-011 range. The elapsed-time accumulator is untouched.
void world_set_clock(World& w, contract::ClockPreset preset,
                     double custom_physics = 1.0, double custom_biology = 1.0);

// Snapshot of what the UI shows. Cheap at M1; becomes a device reduction in M6.
// Runs the stage-11 reduction and copies the result D2H, so it is NOT free --
// call it at HUD rate, not every tick (ARCHITECTURE.md Sec 3.1).
contract::Stats world_stats(World& w);

} // namespace astro::sim
