// src/sim/integrator.cu -- tick stages 2, 5 and 6 (ARCHITECTURE.md Sec 3.4).
//
// Kernel bodies are thin loops over the __host__ __device__ functions in
// integrator.cuh (Iron Rule 5). Physics that only exists inside a __global__
// body is untestable.
#include <cuda_runtime.h>

#include "fields/grid.cuh"
#include "sim/integrator.cuh"
#include "sim/thermal.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Stage 2, field_sample.
__global__ void field_sample_kernel(CellStoreView v, FieldView temp, FieldView co2,
                                    FieldView n2) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    if (!(v.flags[i] & CELL_FLAG_OCCUPIED)) return;
    const float x = static_cast<float>(v.x[i]);
    const float y = static_cast<float>(v.y[i]);
    v.t_local[i]   = astro::fields::grid_sample(temp, x, y);
    v.co2_local[i] = astro::fields::grid_sample(co2, x, y);
    v.n2_local[i]  = astro::fields::grid_sample(n2, x, y);
}

// Stage 5, forces. SEPARATE FROM STAGE 6 ON PURPOSE.
//
// Contact reads neighbouring positions. If this ran in the same kernel that
// writes positions, cell i would see some neighbours pre-step and some
// post-step depending on scheduling -- a read/write race that makes the whole
// run nondeterministic. Measured before the split: 2709 of 3000 positions
// differed between two identical runs. ARCHITECTURE.md Sec 3.4 lists forces and
// integrate as separate stages for exactly this reason (ADR-018).
__global__ void forces_kernel(CellStoreView v, HashView hash, MotionConfig cfg,
                              double* fx, double* fy, double* fz) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t flags = v.flags[i];
    if (!(flags & CELL_FLAG_OCCUPIED)) { fx[i] = fy[i] = fz[i] = 0.0; return; }

    const double mass = cell_mass(v.biomass[i], v.energy[i]);
    // A corpse still sediments -- it has mass and drag. It just does not thrust.
    const bool alive = (flags & CELL_FLAG_ALIVE) != 0u;
    const double emit = alive ? static_cast<double>(v.emit_power[i]) : 0.0;
    const Vec3 dir{v.dir_x[i], v.dir_y[i], v.dir_z[i]};

    Vec3 force = cell_force(mass, emit, dir, cfg.gravity_axis);

    // The neighbour walk order is fixed (hash.cuh) and each thread writes only
    // its own force, so this sum needs neither atomics nor fixed point.
    if (cfg.contact_enabled && hash.vals_sorted != nullptr) {
        const Vec3 pos{v.x[i], v.y[i], v.z[i]};
        ASTRO_FOR_EACH_NEIGHBOUR(hash, pos.x, pos.y, pos.z, j, {
            if (j != i && (v.flags[j] & CELL_FLAG_OCCUPIED)) {
                force += contact_force(pos, Vec3{v.x[j], v.y[j], v.z[j]});
            }
        });
    }
    fx[i] = force.x; fy[i] = force.y; fz[i] = force.z;
}

// Stage 6, integrate.
__global__ void integrate_kernel(CellStoreView v, MotionConfig cfg, Chamber chamber,
                                 const double* fx, const double* fy, const double* fz,
                                 double dt) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t flags = v.flags[i];
    if (!(flags & CELL_FLAG_OCCUPIED)) return;

    const double t_local = static_cast<double>(v.t_local[i]);
    const double mass  = cell_mass(v.biomass[i], v.energy[i]);
    // P4. An awake cell holds its SURFACE at the setpoint however cold the bulk
    // is, and Stokes drag is set by the boundary layer at that surface -- so a
    // live cell is genuinely more mobile than a dead one sitting in the same
    // water. Using the far-field grid value instead would understate it (2.87x
    // rather than 4.36x). See ADR-020 and thermal.cuh.
    const bool awake = (flags & CELL_FLAG_AWAKE) != 0u;
    const double t_drag = viscosity_temperature(awake, t_local);
    double gamma = drag_coefficient(t_drag);

    const Vec3 force{fx[i], fy[i], fz[i]};

    Vec3 pos{v.x[i], v.y[i], v.z[i]};
    Vec3 vel{v.vx[i], v.vy[i], v.vz[i]};

    // An adhered cell drags far harder until something pulls it free.
    if (flags & CELL_FLAG_STUCK) gamma *= canon::WALL_STUCK_DRAG_MULT;

    Pcg32 rng = cell_rng(v.rng_state[i], v.id[i]);
    integrate_cell(pos, vel, force, mass, gamma, t_drag, dt, cfg.thermal_noise, rng);
    v.rng_state[i] = rng.state;

    const double a = canon::CELL_RADIUS;
    bool kept = apply_boundary_axis(pos.x, vel.x, 0.5 * chamber.w, a, cfg.boundary_x);
    kept = apply_boundary_axis(pos.y, vel.y, 0.5 * chamber.h, a, cfg.boundary_y) && kept;
    // z is the slide and the coverslip: always reflecting, never configurable.
    const double z_before = pos.z;
    apply_boundary_axis(pos.z, vel.z, 0.5 * chamber.d, a, Boundary::Reflecting);
    const bool touched_glass = (pos.z != z_before);

    // Adhesion. Only at the z walls -- those are the actual glass; x and y are
    // the chamber sides and may even be periodic. Gravity runs along -y
    // (ADR-006), so cells reach the glass by diffusion rather than by settling,
    // which makes adhesion a slow accumulation rather than an immediate carpet.
    uint32_t new_flags = flags;
    if (cfg.adhesion_enabled) {
        if (touched_glass && !(flags & CELL_FLAG_STUCK)) {
            Pcg32 ar = cell_rng(v.rng_state[i], v.id[i]);
            const bool sticks = uniform01d(ar) < canon::WALL_STICKINESS;
            v.rng_state[i] = ar.state;
            if (sticks) new_flags |= CELL_FLAG_STUCK;
        } else if (flags & CELL_FLAG_STUCK) {
            // Freed only by a normal force pulling away from the glass. Whether a
            // cell can free itself therefore depends on its charge, since that is
            // what sets its buoyant weight.
            const double away = (pos.z < 0.0) ? force.z : -force.z;
            if (away > canon::WALL_RELEASE_FORCE) new_flags &= ~CELL_FLAG_STUCK;
        }
    }
    v.flags[i] = new_flags;

    if (!kept) {
        // Absorbed at a wall. Lifecycle owns slot reclamation (M9); until then
        // the cell becomes an inert corpse so nothing downstream sees a hole.
        v.flags[i] = new_flags & ~static_cast<uint32_t>(CELL_FLAG_ALIVE);
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
                                         astro::fields::grid_view(w.fields.temperature),
                                         astro::fields::grid_view(w.fields.co2),
                                         astro::fields::grid_view(w.fields.n2));
    forces_kernel<<<grid, block>>>(w.cells.view, hash_view(w.hash), w.motion,
                                   w.d_fx, w.d_fy, w.d_fz);
    integrate_kernel<<<grid, block>>>(w.cells.view, w.motion, w.chamber,
                                      w.d_fx, w.d_fy, w.d_fz, dt);
}

} // namespace astro::sim
