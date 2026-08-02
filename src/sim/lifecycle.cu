// src/sim/lifecycle.cu -- tick stage 10. docs/PHYSICS.md Sec 10, ADR-025.
//
// MUTATES THE STORE, so it runs last (ARCHITECTURE.md Sec 3.4). Anything after it
// reads stale indices.
#include <cuda_runtime.h>

#include "fields/grid.cuh"
#include "sim/lifecycle.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Stage 10a. Feeding: bank CO2 from the field, and take the same mass out of it.
// Deposit is NEAREST, not bilinear: uptake is a lumped exchange between one cell
// and the medium around it, and bilinear reads back only sum(w^2) of what it
// writes -- 0.25 at a grid node (ADR-020's supporting decision).
// What a cell WANTS this tick. Nearest sampling throughout, not the bilinear
// `co2_local`: this is a lumped exchange, and the demand must be booked against
// exactly the grid cell the deposit will come out of (meta-lesson: match the
// sample to the source).
ASTRO_HD inline double co2_demand(const CellStoreView& v, int i, const FieldView& co2,
                                  double dt_bio) {
    const double here = static_cast<double>(
        astro::fields::grid_sample_nearest(co2, static_cast<float>(v.x[i]),
                                                static_cast<float>(v.y[i])));
    return co2_uptake_rate(here) * dt_bio;
}

// Pass 1. Book every cell's demand against its grid cell, in FIXED POINT so the
// total is independent of the order the cells are summed (INV-2).
// UNITS: demand is booked as a CONCENTRATION (kg/m^3), not a mass, because
// `deposit_scale` is calibrated for the field's own units. Booking kilograms
// against a concentration scale rounds a 6e-16 kg demand to zero in fixed point,
// the rationing below then never triggers, and every cell takes its full draw --
// which is what drove the field negative even with the ration in place (ADR-025).
__global__ void demand_kernel(CellStoreView v, FieldView co2, double dt_bio,
                              double grid_volume, unsigned long long* demand) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;
    const double want = co2_demand(v, i, co2, dt_bio);
    if (want <= 0.0) return;
    astro::atomic_deposit(&demand[astro::fields::grid_index_nearest(
                              co2, static_cast<float>(v.x[i]), static_cast<float>(v.y[i]))],
                          want / grid_volume, co2.deposit_scale);
}

// Pass 2. Take demand x scale, where scale rations a grid cell that has been
// over-subscribed.
//
// A PER-CELL CLAMP IS NOT ENOUGH, and that is the whole reason this is two passes.
// Each cell individually taking no more than the grid cell holds still lets N
// cells sharing that grid cell take N times its contents, and the field goes
// NEGATIVE -- which diffusion then cheerfully spreads. Michaelis-Menten limits the
// RATE; this failure is about the STEP. Measured before the fix: -0.128 kg/m^3.
__global__ void uptake_kernel(CellStoreView v, FieldView co2, double dt_bio,
                              double grid_volume, const unsigned long long* demand) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;

    const double want = co2_demand(v, i, co2, dt_bio);
    if (want <= 0.0) return;

    // Both sides in CONCENTRATION, matching the field and its deposit scale.
    const int32_t idx = astro::fields::grid_index_nearest(
        co2, static_cast<float>(v.x[i]), static_cast<float>(v.y[i]));
    const double asked = astro::from_fixed(demand[idx], co2.deposit_scale);
    const double available = static_cast<double>(co2.value[idx]);

    double taken = want;
    if (asked > available && asked > 0.0) taken = want * (available / asked);
    if (taken <= 0.0) return;

    v.co2_held[i] += taken;
    astro::fields::grid_deposit_nearest(co2, static_cast<float>(v.x[i]),
                                        static_cast<float>(v.y[i]),
                                        -taken / grid_volume);
}

__global__ void clear_u64_kernel(unsigned long long* p, int32_t n) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) p[i] = 0ull;
}

// Stage 10b, pass 1. Mark who divides, and count them with a DETERMINISTIC
// exclusive prefix sum -- never atomicAdd. The snapshot hash is taken over the SoA
// in slot order, so an order-dependent slot assignment would make the hash vary
// run to run (ADR-025). This is INV-2's reasoning one level up: it is not the
// arithmetic that must be associative here, it is the allocation.
__global__ void mark_kernel(CellStoreView v, int32_t* flagsum) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    const bool divides = (f & CELL_FLAG_OCCUPIED) && (f & CELL_FLAG_ALIVE) &&
                         ready_to_divide(v.co2_held[i]);
    flagsum[i] = divides ? 1 : 0;
}

// Single-block exclusive scan. The population that can divide in one tick is
// bounded by the live count, and this runs once per tick over a small array; a
// multi-block scan is a later optimisation, not a correctness question.
__global__ void scan_kernel(int32_t* v, int32_t n, int32_t* total) {
    int32_t acc = 0;
    for (int32_t i = 0; i < n; ++i) {
        const int32_t x = v[i];
        v[i] = acc;              // exclusive
        acc += x;
    }
    *total = acc;
}

// Stage 10b, pass 2. Split. Parent keeps its slot and its id; the daughter takes
// base + the parent's exclusive prefix, so the mapping from parent to daughter
// slot is a pure function of the population, not of execution order.
__global__ void divide_kernel(CellStoreView v, const int32_t* prefix, int32_t base,
                              int32_t old_count, uint64_t first_id, Chamber c) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= old_count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;
    if (!ready_to_divide(v.co2_held[i])) return;

    const int32_t slot = base + prefix[i];
    if (slot >= v.capacity) return;              // store full: skip, do not wrap

    const uint64_t did = first_id + static_cast<uint64_t>(prefix[i]);

    // Energy is SPLIT. Both cells end up with half; nothing is created.
    const double half = daughter_energy(v.energy[i]);
    v.energy[i] = half;
    v.energy[slot] = half;

    // The banked CO2 is spent building the daughter's biomass.
    v.co2_held[i] = 0.0;
    v.co2_held[slot] = 0.0;
    v.biomass[slot] = canon::CELL_MASS_DRY;

    double ax, ay, az;
    division_axis(did, ax, ay, az);
    const double a = canon::CELL_RADIUS;
    // Half a radius either way, so the pair starts in contact rather than
    // overlapping hard -- contact then pushes them apart over the next few ticks.
    v.x[slot] = v.x[i] + a * ax;  v.x[i] -= a * ax;
    v.y[slot] = v.y[i] + a * ay;  v.y[i] -= a * ay;
    v.z[slot] = v.z[i] + a * az;  v.z[i] -= a * az;

    // Containment is not negotiable: a daughter placed in the glass is a bug
    // (ARCHITECTURE.md Sec 4). Clamp rather than reject, so division never
    // silently fails near a wall.
    const double hx = 0.5 * c.w - a, hy = 0.5 * c.h - a, hz = 0.5 * c.d - a;
    v.x[slot] = v.x[slot] < -hx ? -hx : (v.x[slot] > hx ? hx : v.x[slot]);
    v.y[slot] = v.y[slot] < -hy ? -hy : (v.y[slot] > hy ? hy : v.y[slot]);
    v.z[slot] = v.z[slot] < -hz ? -hz : (v.z[slot] > hz ? hz : v.z[slot]);
    v.x[i] = v.x[i] < -hx ? -hx : (v.x[i] > hx ? hx : v.x[i]);
    v.y[i] = v.y[i] < -hy ? -hy : (v.y[i] > hy ? hy : v.y[i]);
    v.z[i] = v.z[i] < -hz ? -hz : (v.z[i] > hz ? hz : v.z[i]);

    v.vx[slot] = v.vx[i]; v.vy[slot] = v.vy[i]; v.vz[slot] = v.vz[i];

    v.id[slot] = did;
    v.flags[slot] = v.flags[i];                  // inherits ALIVE and AWAKE
    v.death_cause[slot] = static_cast<uint8_t>(DeathCause::None);
    v.temp_cell[slot] = v.temp_cell[i];
    v.emit_power[slot] = 0.0f;
    v.dir_x[slot] = v.dir_x[i];
    v.dir_y[slot] = v.dir_y[i];
    v.dir_z[slot] = v.dir_z[i];
    v.age_s[slot] = 0.0f;

    // INV-1: the daughter's stream depends on (parent state, daughter id) alone.
    v.rng_state[slot] = daughter_rng_state(v.rng_state[i], did);

    v.taxis_memory[slot] = 0.0f;
    v.run_timer[slot]    = 0.0f;
    v.t_local[slot]      = v.t_local[i];
    v.irradiance[slot]   = 0.0f;
    v.co2_local[slot]    = v.co2_local[i];
    v.n2_local[slot]     = v.n2_local[i];
}

} // namespace

void lifecycle_step(World& w, double dt) {
    const int32_t n = w.cells.count;
    if (n <= 0) return;
    const int block = 256;
    const int grid = (n + block - 1) / block;

    // Biology runs on its own clock (ADR-011). Only growth and division scale;
    // the integrator, thermal and emission stay on physics time.
    const double dt_bio = dt * w.biology_rate;

    // Volume of one CO2 grid cell: dx^2 through the full chamber depth, the same
    // lumped capacity the thermal stage uses.
    const double gv = static_cast<double>(w.fields.co2.dx) *
                      static_cast<double>(w.fields.co2.dx) * w.chamber.d;
    const FieldView co2 = fields::grid_view(w.fields.co2);
    const int32_t cells2 = w.fields.co2.n * w.fields.co2.n;
    clear_u64_kernel<<<(cells2 + block - 1) / block, block>>>(w.d_co2_demand, cells2);
    demand_kernel<<<grid, block>>>(w.cells.view, co2, dt_bio, gv, w.d_co2_demand);
    uptake_kernel<<<grid, block>>>(w.cells.view, co2, dt_bio, gv, w.d_co2_demand);

    // This stage owns the application of its OWN deposits, exactly as thermal_step
    // owns stage 7/8 for the temperature field. Stage 7's flush already ran back at
    // stage 7, so without this the uptake would land a tick late -- and then two
    // consecutive ticks would ration against the same stale concentration and each
    // take all of it, which is what drove the field to -0.128 kg/m^3. Rationing is
    // only sound if what it rations against is current.
    fields::grid_flush_deposits(w.fields.co2);

    mark_kernel<<<grid, block>>>(w.cells.view, w.cells.d_birth_prefix);
    scan_kernel<<<1, 1>>>(w.cells.d_birth_prefix, n, w.cells.d_birth_count);

    int32_t births = 0;
    cudaMemcpy(&births, w.cells.d_birth_count, sizeof(int32_t), cudaMemcpyDeviceToHost);
    if (births <= 0) return;

    const int32_t base = n;
    if (base + births > w.cells.capacity) births = w.cells.capacity - base;
    if (births <= 0) return;

    divide_kernel<<<grid, block>>>(w.cells.view, w.cells.d_birth_prefix, base, n,
                                   w.cells.next_id, w.chamber);

    w.cells.next_id += static_cast<uint64_t>(births);
    w.cells.count += births;
    w.cells.view.count = w.cells.count;
}

} // namespace astro::sim
