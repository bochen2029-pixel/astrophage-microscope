// src/sim/integrator.cu -- tick stages 2, 5 and 6 (ARCHITECTURE.md Sec 3.4).
//
// Kernel bodies are thin loops over the __host__ __device__ functions in
// integrator.cuh (Iron Rule 5). Physics that only exists inside a __global__
// body is untestable.
#include <cuda_runtime.h>

#include "sim/integrator.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Stage 2, field_sample. At M2 there is no temperature field, so every cell
// samples the scenario ambient. M5 replaces the body, not the stage.
__global__ void field_sample_kernel(CellStoreView v, float ambient_k) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    if (!(v.flags[i] & CELL_FLAG_OCCUPIED)) return;
    v.t_local[i] = ambient_k;
}

// Stages 5 and 6, forces and integrate. Fused: they share the mass, gamma and
// OU coefficients, and splitting them would mean recomputing all three or
// spilling them to global memory.
__global__ void integrate_kernel(CellStoreView v, MotionConfig cfg, Chamber chamber,
                                 double dt) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t flags = v.flags[i];
    if (!(flags & CELL_FLAG_OCCUPIED)) return;

    const double t_local = static_cast<double>(v.t_local[i]);
    const double mass  = cell_mass(v.biomass[i], v.energy[i]);
    const double gamma = drag_coefficient(t_local);

    // A corpse still sediments -- it has mass and drag. It just does not thrust.
    const bool alive = (flags & CELL_FLAG_ALIVE) != 0u;
    const double emit = alive ? static_cast<double>(v.emit_power[i]) : 0.0;
    const Vec3 dir{v.dir_x[i], v.dir_y[i], v.dir_z[i]};

    const Vec3 force = cell_force(mass, emit, dir, cfg.gravity_axis);

    Vec3 pos{v.x[i], v.y[i], v.z[i]};
    Vec3 vel{v.vx[i], v.vy[i], v.vz[i]};

    Pcg32 rng = cell_rng(v.rng_state[i], v.id[i]);
    integrate_cell(pos, vel, force, mass, gamma, t_local, dt, cfg.thermal_noise, rng);
    v.rng_state[i] = rng.state;

    const double a = canon::CELL_RADIUS;
    bool kept = apply_boundary_axis(pos.x, vel.x, 0.5 * chamber.w, a, cfg.boundary_x);
    kept = apply_boundary_axis(pos.y, vel.y, 0.5 * chamber.h, a, cfg.boundary_y) && kept;
    // z is the slide and the coverslip: always reflecting, never configurable.
    apply_boundary_axis(pos.z, vel.z, 0.5 * chamber.d, a, Boundary::Reflecting);

    if (!kept) {
        // Absorbed at a wall. Lifecycle owns slot reclamation (M9); until then
        // the cell becomes an inert corpse so nothing downstream sees a hole.
        v.flags[i] = flags & ~static_cast<uint32_t>(CELL_FLAG_ALIVE);
        v.death_cause[i] = static_cast<uint8_t>(DeathCause::Culled);
        v.emit_power[i] = 0.0f;
    }

    v.x[i] = pos.x;  v.y[i] = pos.y;  v.z[i] = pos.z;
    v.vx[i] = vel.x; v.vy[i] = vel.y; v.vz[i] = vel.z;
    v.age_s[i] += static_cast<float>(dt);
}

} // namespace

void motion_step(World& w, double dt) {
    const int32_t n = w.cells.count;
    if (n <= 0) return;
    const int block = 256;
    const int grid = (n + block - 1) / block;

    field_sample_kernel<<<grid, block>>>(w.cells.view,
                                         static_cast<float>(w.motion.ambient_temp));
    integrate_kernel<<<grid, block>>>(w.cells.view, w.motion, w.chamber, dt);
}

} // namespace astro::sim
