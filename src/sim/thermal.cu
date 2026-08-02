// src/sim/thermal.cu -- tick stage 4, substepped against the temperature field.
#include <cuda_runtime.h>

#include "fields/grid.cuh"
#include "sim/thermal.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// One thermal substep. Runs INSIDE the diffusion substep loop: the deposit from
// a single cell is large next to one grid cell's heat capacity, so dumping a
// whole tick's worth at once and diffusing afterwards overshoots badly. Spread
// across the substeps it is a source term in the heat equation, which is what it
// physically is.
__global__ void thermal_kernel(CellStoreView v, FieldView temp, double dt_sub,
                               double grid_capacity, double conductance,
                               unsigned char thermostat_enabled) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t flags = v.flags[i];
    if (!(flags & CELL_FLAG_OCCUPIED)) return;

    // NEAREST, not bilinear. The exchange below is a lumped two-body problem
    // between the cell and the grid cell it occupies, so the value it reads and
    // the value it feeds must be the same cell (ADR-020).
    const float t_grid = astro::fields::grid_sample_nearest(temp, static_cast<float>(v.x[i]),
                                                                  static_cast<float>(v.y[i]));
    bool awake = (flags & CELL_FLAG_AWAKE) != 0u;

    // P3: the latch. One way, forever.
    if (!awake && should_ignite(false, t_grid)) {
        awake = true;
        v.flags[i] = flags | CELL_FLAG_AWAKE;
    }

    const double t_cell = cell_temperature(awake, t_grid);
    v.temp_cell[i] = static_cast<float>(t_cell);
    if (!awake || !(flags & CELL_FLAG_ALIVE) || !thermostat_enabled) return;

    // P2: bidirectional. A positive result means the cell spent store to hold
    // its setpoint; a negative one means the medium was hotter and the cell
    // absorbed the excess as neutrino mass. Both are the same equation.
    const double e = lumped_exchange_energy(t_cell, static_cast<double>(t_grid),
                                            conductance, grid_capacity, dt_sub);

    double energy = v.energy[i] - e;
    double actually_moved = e;
    if (energy < 0.0) { actually_moved = v.energy[i]; energy = 0.0; }
    else if (energy > canon::CELL_ENERGY_MAX) {
        actually_moved = v.energy[i] - canon::CELL_ENERGY_MAX;
        energy = canon::CELL_ENERGY_MAX;
    }
    v.energy[i] = energy;

    // Equal and opposite into the field, through the fixed-point accumulator so
    // overlapping cells sum deterministically (INV-2).
    astro::fields::grid_deposit_nearest(temp, static_cast<float>(v.x[i]),
                                        static_cast<float>(v.y[i]),
                                        actually_moved / grid_capacity);

    // Starved: it can no longer hold the setpoint.
    if (energy <= 0.0) {
        v.flags[i] = (v.flags[i] & ~static_cast<uint32_t>(CELL_FLAG_ALIVE));
        v.death_cause[i] = static_cast<uint8_t>(DeathCause::Starved);
        v.emit_power[i] = 0.0f;
    }
}

} // namespace

void thermal_step(World& w, double dt) {
    const int32_t n = w.cells.count;
    auto& temp = w.fields.temperature;
    // Substeps follow the ACTUAL dt (physics_rate scales it), not the count baked
    // for a 1 ms tick -- otherwise a fast clock overshoots the stability bound and
    // the near-field deposit sails past boiling (ADR-020, ADR-027). At DT_PHYSICS
    // this is the baked count, so physics_rate == 1 is unchanged.
    const int32_t substeps = astro::fields::substeps_for_dt(temp.dx, temp.diffusivity, dt);
    const double dt_sub = dt / substeps;

    // The heat capacity of one grid cell of medium: dx^2 * chamber depth.
    const double grid_capacity = canon::WATER_DENSITY * canon::WATER_SPECIFIC_HEAT *
                                 temp.dx * temp.dx * w.chamber.d;
    // Free-space conduction. The grid is the FAR field; the sub-grid 1/r near
    // field is not resolved and must not be double-counted (ADR-020).
    const double conductance = canon::CONDUCTION_COEFF;

    const int block = 256;
    const int grid = (n + block - 1) / block;

    for (int32_t s = 0; s < substeps; ++s) {
        if (n > 0 && w.motion.thermal_enabled) {
            thermal_kernel<<<grid, block>>>(w.cells.view, astro::fields::grid_view(temp),
                                            dt_sub, grid_capacity, conductance, 1);
            astro::fields::grid_flush_deposits(temp);
        }
        astro::fields::grid_diffuse_substep(temp, dt_sub);
    }
}

} // namespace astro::sim
