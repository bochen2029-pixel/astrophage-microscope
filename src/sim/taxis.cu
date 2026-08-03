// src/sim/taxis.cu -- tick stage 3. docs/PHYSICS.md Sec 8, ADR-007, ADR-022.
#include <cuda_runtime.h>

#include "sim/taxis.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

__global__ void taxis_kernel(CellStoreView v, double dt, double max_power) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;

    // Dormant cells are inert powder: they neither tumble nor emit. They still
    // absorb, because albedo is zero and absorption is not a choice -- see Q14.
    if (!(f & CELL_FLAG_AWAKE)) {
        v.emit_power[i] = 0.0f;
        return;
    }

    const double irr = static_cast<double>(v.irradiance[i]);
    const double co2 = static_cast<double>(v.co2_local[i]);
    const double charge = v.energy[i] / canon::CELL_ENERGY_MAX;
    const TaxisState state = taxis_select_state(charge, irr, co2);

    if (state == TaxisState::Idle) {
        // The Idle path draws NO random numbers. That is what makes a dark
        // chamber BIT-IDENTICAL to a run with the controller disabled rather than
        // merely similar to it (T26.8) -- and it is what canon says a cell in
        // darkness does. Writing zeros over zeros costs nothing and diverges
        // nothing, because spawn already leaves both at zero.
        v.emit_power[i]   = 0.0f;
        v.run_timer[i]    = 0.0f;
        v.taxis_memory[i] = 0.0f;
        return;
    }

    // Temporal comparison (ADR-007): is the signal better than the lagged one?
    const double signal = taxis_signal(state, irr, co2);
    const double delta  = signal - static_cast<double>(v.taxis_memory[i]);
    v.taxis_memory[i]   = taxis_ema_update(v.taxis_memory[i], signal, dt);

    // The stored quantity is the emission axis; the heading is its negation.
    Vec3 heading = -Vec3{static_cast<double>(v.dir_x[i]),
                         static_cast<double>(v.dir_y[i]),
                         static_cast<double>(v.dir_z[i])};
    double run = static_cast<double>(v.run_timer[i]) + dt;

    if (taxis_should_tumble(delta, run)) {
        Pcg32 rng = cell_rng(v.rng_state[i], v.id[i]);
        heading = taxis_tumble(heading, rng);
        v.rng_state[i] = rng.state;
        run = 0.0;
    }
    v.run_timer[i] = static_cast<float>(run);

    // Re-aim is instantaneous at M8. Rate-limiting it with PETROVA_SLEW_RATE needs
    // the commanded heading stored SEPARATELY from the current axis, and there is
    // no such field in cell_store_v1.h -- see ADR-022 and Q15. The consequence is
    // one-directional and worth stating: instantaneous re-aim makes taxis strictly
    // MORE effective than the slewed version, so M8's migration figure is an upper
    // bound and adding the slew later will reduce it.
    const Vec3 axis = taxis_emit_dir(heading);
    v.dir_x[i] = static_cast<float>(axis.x);
    v.dir_y[i] = static_cast<float>(axis.y);
    v.dir_z[i] = static_cast<float>(axis.z);

    // dE/dt = -emit_power (PHYSICS.md Sec 6). Nothing debited the store for
    // emitting before M8 because nothing ever set emit_power nonzero.
    const double p = taxis_emit_power(state, v.energy[i], dt, max_power);
    v.emit_power[i] = static_cast<float>(p);
    v.energy[i] -= p * dt;
}

} // namespace

void taxis_step(World& w, double dt) {
    const int32_t n = w.cells.count;
    if (n <= 0) return;
    const int block = 256;
    taxis_kernel<<<(n + block - 1) / block, block>>>(w.cells.view, dt, w.petrova_max_power);
}

} // namespace astro::sim
