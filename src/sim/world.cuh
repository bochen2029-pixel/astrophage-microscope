// src/sim/world.cuh -- everything one simulation owns.
//
// The tick sequence is ARCHITECTURE.md Sec 3.4. At M1 `world_step` only advances
// the clock; each later milestone inserts its stage at the documented position
// rather than restructuring the loop.
#pragma once

#include <cstdint>

#include "contracts/telemetry_v1.h"
#include "core/canon_generated.h"
#include "core/result.h"
#include "sim/cell_store.cuh"
#include "sim/integrator.cuh"

namespace astro::sim {

// Everything the motion stages need. Passed by value into kernels, so POD.
struct MotionConfig {
    Boundary    boundary_x = Boundary::Reflecting;
    Boundary    boundary_y = Boundary::Reflecting;
    GravityAxis gravity_axis = GravityAxis::Y;   // ADR-006
    // Off only for analytic tests, where a terminal velocity must be exact.
    bool        thermal_noise = true;
    double      ambient_temp = canon::AMBIENT_TEMP_DEFAULT;
};

struct WorldDesc {
    Chamber  chamber{canon::CHAMBER_W, canon::CHAMBER_H, canon::CHAMBER_D};
    int32_t  capacity = 0;          // 0 = size to the initial population
    uint64_t seed = 20260802ull;
    MotionConfig motion{};
};

struct World {
    CellStore    cells;
    Chamber      chamber{};
    MotionConfig motion{};
    uint64_t     tick = 0;
    uint64_t     seed = 0;
    double       physics_rate = 1.0;
    double       biology_rate = 1.0;
};

// Tick stages 2, 5, 6 (src/sim/integrator.cu).
void motion_step(World& w, double dt);

Error world_create(World& w, const WorldDesc& d);
void  world_destroy(World& w);

// One fixed tick. Called only from app's accumulator (src/app/MODULE.md).
void  world_step(World& w);

// Simulated time in seconds. The ONLY clock the simulation has (INV-3).
double world_sim_time(const World& w);

// Snapshot of what the UI shows. Cheap at M1; becomes a device reduction in M6.
contract::Stats world_stats(const World& w);

} // namespace astro::sim
