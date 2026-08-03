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
    const size_t co2_cells = static_cast<size_t>(canon::FIELD_N_CO2) * canon::FIELD_N_CO2;
    if (cudaMalloc(&w.d_co2_demand, sizeof(unsigned long long) * co2_cells) != cudaSuccess ||
        cudaMalloc(&w.d_stats, sizeof(StatsAccum)) != cudaSuccess) {
        world_destroy(w);
        return fail(Status::OutOfMemory, "cudaMalloc co2 demand / stats");
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
                                  canon::CO2_DIFFUSIVITY_WATER, d.co2_init,
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

    // The predator store and the per-cell engulfment claim buffer (M10). The claim
    // is sized to the cell capacity, since any live cell may be a prey.
    const int32_t tau_cap = d.tau_capacity > 0 ? d.tau_capacity : canon::DEFAULT_TAUMOEBA;
    ASTRO_TRY(taumoeba_create(w.taumoeba, tau_cap));
    if (cudaMalloc(&w.d_predator_claim,
                   sizeof(unsigned long long) * static_cast<size_t>(cap)) != cudaSuccess) {
        world_destroy(w);
        return fail(Status::OutOfMemory, "cudaMalloc predator claim");
    }

    w.chamber = d.chamber;
    w.motion = d.motion;
    w.seed = d.seed;
    w.tick = 0;
    w.sim_time_s = 0.0;
    w.physics_rate = 1.0;
    w.biology_rate = 1.0;
    w.divisions_this_window = 0;
    w.deaths_total = 0;
    w.deaths_reported = 0;
    w.dead_slots_prev = 0;
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
    taumoeba_destroy(w.taumoeba);
    cudaFree(w.d_predator_claim);
    cudaFree(w.d_stats);
    cudaFree(w.d_co2_demand);
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
    //  10 predation       M10  (crawl, engulf, N2 death, Taumoeba division/compaction;
    //                           mutates the Taumoeba store, kills prey for lifecycle)
    //  11 lifecycle       M9   (mutates the cell store; must stay last)
    //  12 stats           M9b  (src/sim/stats.cu). Run from world_stats at HUD
    //                           rate rather than every tick: it ends in a D2H copy
    //                           and nothing in the tick consumes it.
    // The multi-rate clock (ADR-011, ADR-027). physics_rate scales the physics
    // dt; every stage below advances by it. The diffusion substeps and the contact
    // stiffness track this dt at their own source, so a fast clock stays stable and
    // contained; at physics_rate == 1, dt == DT_PHYSICS and the tick is bit-
    // identical to M9b. biology_rate scales only the growth clock, inside
    // lifecycle_step, and compounds with this dt.
    const double dt = canon::DT_PHYSICS * w.physics_rate;

    hash_build(w.hash, w.cells.view, w.cells.count);

    // Stage 4 is interleaved with the temperature field's own substeps, so it
    // owns stages 7 and 8 for that field. One cell deposits ~188 K into a single
    // grid cell per tick; applied all at once it would sail past boiling
    // (ADR-020). Do NOT diffuse temperature again below.
    thermal_step(w, dt);

    // Stage 9. Rebuilt from scratch every tick -- irradiance is never
    // accumulated. Runs before motion so feeding and thrust see the same field.
    if (w.motion.emission_enabled) emission_step(w, dt);

    // Stage 3. Pinned BETWEEN those two by two hard data dependencies: it reads
    // the irradiance emission_step just wrote, and motion_step consumes the
    // emit_power it writes. Both are one-way, so the position is forced.
    //
    // KNOWN LAG: `co2_local` is sampled inside motion_step (stage 2 is fused into
    // stages 5 and 6 there), so the CO2 the BREED state climbs is one tick old --
    // 1 ms against a field whose diffusion time across one grid cell is ~0.1 s,
    // i.e. negligible, and at M8 the only CO2 source is a brush. M9 adds uptake
    // and should re-examine whether stage 2 needs splitting out (ADR-022).
    if (w.motion.taxis_enabled) taxis_step(w, dt);

    motion_step(w, dt);

    // Stages 7 and 8 for the slow fields. Deposits fold in before diffusing, so
    // a source added this tick spreads this tick.
    fields::grid_flush_deposits(w.fields.co2);
    fields::grid_flush_deposits(w.fields.n2);
    fields::grid_diffuse(w.fields.co2, dt);
    fields::grid_diffuse(w.fields.n2, dt);

    // Stage 10. Predators crawl and engulf, killing prey. Uses the cell hash from
    // stage 1 (a one-tick lag, negligible against the engulf radius) and runs before
    // lifecycle so the corpses it makes are disposed of this tick.
    predation_step(w, dt);

    // Stage 11. LAST, and it must stay last: it appends daughters and moves
    // `count`, so any stage reading indices after it would read stale ones.
    lifecycle_step(w, dt);

    ++w.tick;
    w.sim_time_s += dt;
}

double world_sim_time(const World& w) {
    return w.sim_time_s;
}

void clock_preset_rates(contract::ClockPreset preset, double& physics, double& biology) {
    using CP = contract::ClockPreset;
    switch (preset) {
        case CP::Motion:
            physics = canon::CLOCK_MOTION_PHYSICS;       biology = canon::CLOCK_MOTION_BIOLOGY;       break;
        case CP::Metabolic:
            physics = canon::CLOCK_METABOLIC_PHYSICS;    biology = canon::CLOCK_METABOLIC_BIOLOGY;    break;
        case CP::Generational:
            physics = canon::CLOCK_GENERATIONAL_PHYSICS; biology = canon::CLOCK_GENERATIONAL_BIOLOGY; break;
        case CP::Realtime:
        case CP::Custom:
        default:
            physics = canon::CLOCK_REALTIME_PHYSICS;     biology = canon::CLOCK_REALTIME_BIOLOGY;     break;
    }
}

void world_set_clock(World& w, contract::ClockPreset preset,
                     double custom_physics, double custom_biology) {
    double physics = custom_physics, biology = custom_biology;
    if (preset != contract::ClockPreset::Custom) clock_preset_rates(preset, physics, biology);
    // Clamp to the ADR-011 ranges: physics is stiff, biology is free but bounded.
    w.physics_rate = physics < canon::CLOCK_PHYSICS_MIN ? canon::CLOCK_PHYSICS_MIN
                   : (physics > canon::CLOCK_PHYSICS_MAX ? canon::CLOCK_PHYSICS_MAX : physics);
    w.biology_rate = biology < canon::CLOCK_BIOLOGY_MIN ? canon::CLOCK_BIOLOGY_MIN
                   : (biology > canon::CLOCK_BIOLOGY_MAX ? canon::CLOCK_BIOLOGY_MAX : biology);
}

} // namespace astro::sim
