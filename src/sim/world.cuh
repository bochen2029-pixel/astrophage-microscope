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
#include "fields/grid.cuh"
#include "sim/cell_store.cuh"
#include "sim/hash.cuh"
#include "sim/integrator.cuh"

namespace astro::sim {

// The chamber's scalar fields. Cell coupling arrives at M6; at M5 the only
// sources are tool brushes.
struct Fields {
    fields::Grid2D temperature;
    fields::Grid2D co2;
    fields::Grid2D n2;
};

enum class BrushKind : uint8_t { Heat = 0, Chill = 1, InjectCO2 = 2, InjectN2 = 3 };

// Everything the motion stages need. Passed by value into kernels, so POD.
struct MotionConfig {
    Boundary    boundary_x = Boundary::Reflecting;
    Boundary    boundary_y = Boundary::Reflecting;
    GravityAxis gravity_axis = GravityAxis::Y;   // ADR-006
    // Off only for analytic tests, where a terminal velocity must be exact.
    bool        thermal_noise = true;
    bool        contact_enabled = true;
    bool        adhesion_enabled = true;
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
    SpatialHash  hash;
    Fields       fields;
    // Tick stage 5 writes these; stage 6 reads them. They exist SPECIFICALLY so
    // that contact reads every neighbour's position from before the step --
    // computing forces and positions in one kernel is a read/write race and
    // makes the run nondeterministic (ADR-018).
    double*      d_fx = nullptr;
    double*      d_fy = nullptr;
    double*      d_fz = nullptr;
    Chamber      chamber{};
    MotionConfig motion{};
    uint64_t     tick = 0;
    uint64_t     seed = 0;
    double       physics_rate = 1.0;
    double       biology_rate = 1.0;
};

// Tick stages 2, 5, 6 (src/sim/integrator.cu).
void motion_step(World& w, double dt);

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

// Snapshot of what the UI shows. Cheap at M1; becomes a device reduction in M6.
contract::Stats world_stats(const World& w);

} // namespace astro::sim
