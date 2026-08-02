// src/sim/step.cu -- world lifetime and the tick sequence.
#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/world.cuh"

namespace astro::sim {

Error world_create(World& w, const WorldDesc& d) {
    const int32_t cap = d.capacity > 0 ? d.capacity : canon::DEFAULT_CELLS;
    ASTRO_TRY(cell_store_create(w.cells, cap));
    w.chamber = d.chamber;
    w.motion = d.motion;
    w.seed = d.seed;
    w.tick = 0;
    w.physics_rate = 1.0;
    w.biology_rate = 1.0;
    return ok();
}

void world_destroy(World& w) {
    cell_store_destroy(w.cells);
    w = World{};
}

void world_step(World& w) {
    // ARCHITECTURE.md Sec 3.4. Stages land here in milestone order:
    //   1 hash_build      M4
    //   2 field_sample    M2 (ambient stand-in) -> M5 (real fields)
    //   3 taxis           M8
    //   4 thermal         M6
    //   5 forces          M2  \_ fused in motion_step: they share mass, gamma
    //   6 integrate       M2  /  and the OU coefficients
    //   7 field_deposit   M5
    //   8 field_diffuse   M5
    //   9 irradiance      M7
    //  10 lifecycle       M9   (mutates the store; must stay last)
    //  11 stats           M6
    motion_step(w, canon::DT_PHYSICS);
    ++w.tick;
}

double world_sim_time(const World& w) {
    return static_cast<double>(w.tick) * canon::DT_PHYSICS * w.physics_rate;
}

contract::Stats world_stats(const World& w) {
    contract::Stats s{};
    s.tick = w.tick;
    s.sim_time_s = world_sim_time(w);
    s.n_live = w.cells.count;
    s.physics_rate = w.physics_rate;
    s.biology_rate = w.biology_rate;
    // Energy, temperature, and charge means arrive with the M6 device reduction.
    // Reporting a plausible-looking zero would be worse than reporting nothing,
    // so the HUD hides fields that are not yet computed.
    return s;
}

} // namespace astro::sim
