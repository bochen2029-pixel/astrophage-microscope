// src/sim/step.cu -- world lifetime and the tick sequence.
#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/world.cuh"

namespace astro::sim {

Error world_create(World& w, const WorldDesc& d) {
    const int32_t cap = d.capacity > 0 ? d.capacity : canon::DEFAULT_CELLS;
    ASTRO_TRY(cell_store_create(w.cells, cap));
    ASTRO_TRY(hash_create(w.hash, d.chamber, cap));
    const size_t fbytes = sizeof(double) * static_cast<size_t>(cap);
    if (cudaMalloc(&w.d_fx, fbytes) != cudaSuccess ||
        cudaMalloc(&w.d_fy, fbytes) != cudaSuccess ||
        cudaMalloc(&w.d_fz, fbytes) != cudaSuccess) {
        world_destroy(w);
        return fail(Status::OutOfMemory, "cudaMalloc force scratch");
    }
    using astro::contract::BoundaryCondition;
    using astro::contract::DEPOSIT_SCALE_CO2;
    using astro::contract::DEPOSIT_SCALE_N2;
    using astro::contract::DEPOSIT_SCALE_TEMPERATURE;
    ASTRO_TRY(fields::grid_create(w.fields.temperature, canon::FIELD_N_TEMP, d.chamber.w,
                                  canon::WATER_THERMAL_DIFFUSIVITY, d.motion.ambient_temp,
                                  DEPOSIT_SCALE_TEMPERATURE, BoundaryCondition::Robin,
                                  canon::DT_PHYSICS));
    ASTRO_TRY(fields::grid_create(w.fields.co2, canon::FIELD_N_CO2, d.chamber.w,
                                  canon::CO2_DIFFUSIVITY_WATER, 0.0,
                                  DEPOSIT_SCALE_CO2, BoundaryCondition::Neumann,
                                  canon::DT_PHYSICS));
    ASTRO_TRY(fields::grid_create(w.fields.n2, canon::FIELD_N_N2, d.chamber.w,
                                  2.0e-9, 0.0, DEPOSIT_SCALE_N2,
                                  BoundaryCondition::Neumann, canon::DT_PHYSICS));
    // Diffusivity is nominal: irradiance is rebuilt each tick and never diffused.
    // The deposit scale must resolve a single cell's cross-section (7.85e-11 m^2).
    ASTRO_TRY(fields::grid_create(w.fields.irradiance, canon::FIELD_N_IRRAD, d.chamber.w,
                                  contract::IRRADIANCE_NOMINAL_DIFFUSIVITY, 0.0,
                                  contract::DEPOSIT_SCALE_IRRADIANCE,
                                  BoundaryCondition::Neumann, canon::DT_PHYSICS));

    w.chamber = d.chamber;
    w.motion = d.motion;
    w.seed = d.seed;
    w.tick = 0;
    w.physics_rate = 1.0;
    w.biology_rate = 1.0;
    return ok();
}

Error world_apply_brush(World& w, BrushKind kind, double x, double y,
                        double radius, double strength) {
    switch (kind) {
        case BrushKind::Heat:      return fields::grid_brush(w.fields.temperature, x, y, radius,  strength);
        case BrushKind::Chill:     return fields::grid_brush(w.fields.temperature, x, y, radius, -strength);
        case BrushKind::InjectCO2: return fields::grid_brush(w.fields.co2, x, y, radius, strength);
        case BrushKind::InjectN2:  return fields::grid_brush(w.fields.n2, x, y, radius, strength);
    }
    return fail(Status::InvalidArgument, "unknown brush");
}

void world_destroy(World& w) {
    fields::grid_destroy(w.fields.temperature);
    fields::grid_destroy(w.fields.co2);
    fields::grid_destroy(w.fields.n2);
    fields::grid_destroy(w.fields.irradiance);
    cudaFree(w.d_fx);
    cudaFree(w.d_fy);
    cudaFree(w.d_fz);
    hash_destroy(w.hash);
    cell_store_destroy(w.cells);
    w = World{};
}

void world_step(World& w) {
    // ARCHITECTURE.md Sec 3.4. Stages land here in milestone order:
    //   1 hash_build      M4
    //   2 field_sample    M2 (ambient stand-in) -> M5 (real fields)
    // NOTE: the SoA is deliberately NOT reordered by bucket (ADR-018).
    //   3 taxis           M8
    //   4 thermal         M6
    //   5 forces          M2/M4  \_ SEPARATE KERNELS. Fusing them makes contact
    //   6 integrate       M2      /  a read/write race and breaks INV-8 (ADR-018)
    //   7 field_deposit   M5
    //   8 field_diffuse   M5
    //   9 irradiance      M7
    //  10 lifecycle       M9   (mutates the store; must stay last)
    //  11 stats           M6
    hash_build(w.hash, w.cells.view, w.cells.count);

    // Stage 4 is interleaved with the temperature field's own substeps, so it
    // owns stages 7 and 8 for that field. One cell deposits ~188 K into a single
    // grid cell per tick; applied all at once it would sail past boiling
    // (ADR-020). Do NOT diffuse temperature again below.
    thermal_step(w, canon::DT_PHYSICS);

    // Stage 9. Rebuilt from scratch every tick -- irradiance is never
    // accumulated. Runs before motion so feeding and thrust see the same field.
    if (w.motion.emission_enabled) emission_step(w, canon::DT_PHYSICS);

    motion_step(w, canon::DT_PHYSICS);

    // Stages 7 and 8 for the slow fields. Deposits fold in before diffusing, so
    // a source added this tick spreads this tick.
    fields::grid_flush_deposits(w.fields.co2);
    fields::grid_flush_deposits(w.fields.n2);
    fields::grid_diffuse(w.fields.co2, canon::DT_PHYSICS);
    fields::grid_diffuse(w.fields.n2, canon::DT_PHYSICS);

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
