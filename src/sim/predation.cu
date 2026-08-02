// src/sim/predation.cu -- Taumoeba crawl and engulfment (M10a). docs/PHYSICS.md Sec 11.
//
// Runs as a tick stage before lifecycle: it kills prey, and lifecycle then disposes
// of the corpses. The cell spatial hash it senses is built at stage 1, so prey
// positions carry the same one-tick lag the CO2 sample does (ADR-022) -- sub-micron
// against a 25 um engulf radius, negligible.
#include <cuda_runtime.h>

#include "sim/hash.cuh"
#include "sim/lifecycle.cuh"     // corpse_energy
#include "sim/predation.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

constexpr size_t ALIGN = 256;
inline size_t aligned(size_t n) { return (n + ALIGN - 1) / ALIGN * ALIGN; }
template <typename T> T* carve(char*& c, int32_t cap) {
    T* p = reinterpret_cast<T*>(c);
    c += aligned(sizeof(T) * static_cast<size_t>(cap));
    return p;
}
template <typename T> size_t span(int32_t cap) { return aligned(sizeof(T) * static_cast<size_t>(cap)); }

Error cuda_check(cudaError_t e, const char* what) { return e == cudaSuccess ? ok() : fail(Status::CudaError, what); }

__global__ void spawn_kernel(TaumoebaStore v, int32_t base, uint64_t first_id, uint64_t seed,
                             int32_t count, Chamber c) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;
    const int32_t slot = base + i;
    const uint64_t id = first_id + static_cast<uint64_t>(i);

    // Disjoint seed space from the cells: double-mix the master seed rather than
    // salt it with a magic literal (A9), so a Taumoeba and a cell of the same id do
    // not share a PCG32 stream.
    uint64_t state = cell_rng_init(splitmix64(seed), id);
    Pcg32 r = cell_rng(state, id);

    const double a = canon::TAU_RADIUS;
    v.x[slot] = uniform_range(r, -0.5 * c.w + a, 0.5 * c.w - a);
    v.y[slot] = uniform_range(r, -0.5 * c.h + a, 0.5 * c.h - a);
    v.z[slot] = uniform_range(r, -0.5 * c.d + a, 0.5 * c.d - a);
    v.vx[slot] = 0.0; v.vy[slot] = 0.0; v.vz[slot] = 0.0;

    double dx, dy, dz;
    gaussian3(r, dx, dy, dz);
    const Vec3 dir = normalize(Vec3{dx, dy, dz});
    v.dir_x[slot] = static_cast<float>(dir.x);
    v.dir_y[slot] = static_cast<float>(dir.y);
    v.dir_z[slot] = static_cast<float>(dir.z);

    v.id[slot] = id;
    v.flags[slot] = CELL_FLAG_OCCUPIED | CELL_FLAG_ALIVE;
    v.biomass[slot] = canon::TAU_MASS;      // starts as a water-density blob
    v.prey_biomass[slot] = 0.0;
    v.digest_timer[slot] = 0.0f;
    v.tolerance[slot] = static_cast<float>(canon::TAU_N2_TOLERANCE_INIT);
    v.rng_state[slot] = r.state;
    v.density_ema[slot] = 0.0f;
    v.run_timer[slot] = 0.0f;
    v.target[slot] = -1;
}

// Stage 11a. Every alive predator crawls; a hunting (not digesting) one also finds
// and CLAIMS its nearest overlapping prey. The claim is an atomicMin of the
// predator id, so when two predators reach one cell the lowest id wins -- an
// order-free resolution, the same reasoning as the fixed-point deposits (INV-2).
__global__ void hunt_kernel(TaumoebaStore t, CellStoreView cells, HashView hash,
                            MotionConfig cfg, Chamber chamber, double dt, double dt_bio,
                            unsigned long long* claim) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= t.count) return;
    const uint32_t f = t.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;

    Vec3 pos{t.x[i], t.y[i], t.z[i]};
    const bool digesting = t.digest_timer[i] > 0.0f;

    // Sense local live-cell density (the run-and-tumble signal) and the first
    // OVERLAPPING live cell (the prey), in one hash walk. First-in-hash-order is
    // deterministic because the hash is a stable sort (INV-7); a nearest-distance
    // search would only add a tie-break with no behavioural gain.
    int prey_count = 0;
    int32_t prey = -1;
    ASTRO_FOR_EACH_NEIGHBOUR(hash, pos.x, pos.y, pos.z, j, {
        const uint32_t cf = cells.flags[j];
        if ((cf & CELL_FLAG_OCCUPIED) && (cf & CELL_FLAG_ALIVE)) {
            ++prey_count;
            if (prey < 0 && tau_overlaps_cell(pos, Vec3{cells.x[j], cells.y[j], cells.z[j]}))
                prey = j;
        }
    });

    // Claim that prey (hunting predators only).
    if (!digesting && prey >= 0) {
        t.target[i] = prey;
        atomicMin(&claim[prey], t.id[i]);
    } else {
        t.target[i] = -1;
    }

    // Run-and-tumble on the prey signal (ADR-007), then crawl.
    Pcg32 rng = cell_rng(t.rng_state[i], t.id[i]);
    float ema = t.density_ema[i];
    float run = t.run_timer[i];
    Vec3 dir{t.dir_x[i], t.dir_y[i], t.dir_z[i]};
    if (tau_should_tumble(static_cast<float>(prey_count), ema, run, dt)) {
        double dx, dy, dz;
        gaussian3(rng, dx, dy, dz);
        dir = normalize(Vec3{dx, dy, dz});
        run = 0.0f;
    } else {
        run += static_cast<float>(dt);
    }
    t.density_ema[i] = ema;
    t.run_timer[i] = run;
    t.dir_x[i] = static_cast<float>(dir.x);
    t.dir_y[i] = static_cast<float>(dir.y);
    t.dir_z[i] = static_cast<float>(dir.z);

    // Driven persistent walk: TAU_CRAWL_THRUST along the heading gives TAU_CRAWL_SPEED
    // as the terminal velocity. Neutrally buoyant (water density), so no gravity term.
    Vec3 vel{t.vx[i], t.vy[i], t.vz[i]};
    const double t_amb = cfg.ambient_temp;
    const Vec3 force = dir * canon::TAU_CRAWL_THRUST;
    integrate_cell(pos, vel, force, canon::TAU_MASS, tau_drag(t_amb), t_amb, dt,
                   cfg.thermal_noise, rng);
    t.rng_state[i] = rng.state;

    const double a = canon::TAU_RADIUS;
    apply_boundary_axis(pos.x, vel.x, 0.5 * chamber.w, a, cfg.boundary_x);
    apply_boundary_axis(pos.y, vel.y, 0.5 * chamber.h, a, cfg.boundary_y);
    apply_boundary_axis(pos.z, vel.z, 0.5 * chamber.d, a, Boundary::Reflecting);
    t.x[i] = pos.x; t.y[i] = pos.y; t.z[i] = pos.z;
    t.vx[i] = vel.x; t.vy[i] = vel.y; t.vz[i] = vel.z;

    // Digestion runs on the biology clock (ADR-011). On completion the predator
    // banks TAU_BIOMASS_YIELD of the prey biomass.
    if (digesting) {
        float d = t.digest_timer[i] - static_cast<float>(dt_bio);
        if (d <= 0.0f) {
            t.biomass[i] += t.prey_biomass[i] * canon::TAU_BIOMASS_YIELD;
            t.prey_biomass[i] = 0.0;
            d = 0.0f;
        }
        t.digest_timer[i] = d;
    }
}

// Stage 11b. Resolve the claims: the winning predator engulfs its prey. The cell
// dies (Predated) and its store goes to the disposition toggle; the predator starts
// digesting. Exactly one predator wins each claimed cell, so there is no race.
__global__ void resolve_kernel(TaumoebaStore t, CellStoreView cells, unsigned char disposition,
                               const unsigned long long* claim) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= t.count) return;
    const int32_t prey = t.target[i];
    if (prey < 0) return;
    if (claim[prey] != t.id[i]) return;                    // lost the claim
    const uint32_t cf = cells.flags[prey];
    if (!(cf & CELL_FLAG_OCCUPIED) || !(cf & CELL_FLAG_ALIVE)) return;

    cells.flags[prey] = cf & ~static_cast<uint32_t>(CELL_FLAG_ALIVE);
    cells.death_cause[prey] = static_cast<uint8_t>(DeathCause::Predated);
    cells.emit_power[prey] = 0.0f;
    cells.energy[prey] = corpse_energy(static_cast<StoreDisposition>(disposition), cells.energy[prey]);

    t.digest_timer[i] = static_cast<float>(canon::TAU_DIGEST_TIME);
    t.prey_biomass[i] = cells.biomass[prey];
}

} // namespace

Error taumoeba_create(TaumoebaStore& s, int32_t capacity) {
    if (capacity <= 0 || capacity > canon::MAX_TAUMOEBA)
        return fail(Status::InvalidArgument, "taumoeba capacity out of range");

    const size_t exact =
        span<uint64_t>(capacity)        // id
      + span<uint32_t>(capacity)        // flags
      + span<double>(capacity) * 6      // x,y,z,vx,vy,vz
      + span<float>(capacity) * 3       // dir_x,y,z
      + span<double>(capacity) * 2      // biomass, prey_biomass
      + span<float>(capacity)           // digest_timer
      + span<float>(capacity)           // tolerance
      + span<uint64_t>(capacity)        // rng_state
      + span<float>(capacity) * 2       // density_ema, run_timer
      + span<int32_t>(capacity);        // target

    void* blob = nullptr;
    ASTRO_TRY(cuda_check(cudaMalloc(&blob, exact), "cudaMalloc taumoeba store"));
    ASTRO_TRY(cuda_check(cudaMemset(blob, 0, exact), "cudaMemset taumoeba store"));

    char* cur = static_cast<char*>(blob);
    s.id          = carve<uint64_t>(cur, capacity);
    s.flags       = carve<uint32_t>(cur, capacity);
    s.x           = carve<double>(cur, capacity);
    s.y           = carve<double>(cur, capacity);
    s.z           = carve<double>(cur, capacity);
    s.vx          = carve<double>(cur, capacity);
    s.vy          = carve<double>(cur, capacity);
    s.vz          = carve<double>(cur, capacity);
    s.dir_x       = carve<float>(cur, capacity);
    s.dir_y       = carve<float>(cur, capacity);
    s.dir_z       = carve<float>(cur, capacity);
    s.biomass     = carve<double>(cur, capacity);
    s.prey_biomass= carve<double>(cur, capacity);
    s.digest_timer= carve<float>(cur, capacity);
    s.tolerance   = carve<float>(cur, capacity);
    s.rng_state   = carve<uint64_t>(cur, capacity);
    s.density_ema = carve<float>(cur, capacity);
    s.run_timer   = carve<float>(cur, capacity);
    s.target      = carve<int32_t>(cur, capacity);

    if (static_cast<size_t>(cur - static_cast<char*>(blob)) > exact) {
        cudaFree(blob);
        return fail(Status::OutOfMemory, "taumoeba store carve overran its allocation");
    }
    s.blob = blob;
    s.blob_bytes = exact;
    s.capacity = capacity;
    s.count = 0;
    s.next_id = 1;
    return ok();
}

void taumoeba_destroy(TaumoebaStore& s) {
    if (s.blob) cudaFree(s.blob);
    s = TaumoebaStore{};
}

Error taumoeba_spawn(TaumoebaStore& s, int32_t count, const Chamber& c, uint64_t seed) {
    if (count <= 0) return ok();
    if (s.count + count > s.capacity)
        return fail(Status::CapacityExceeded, "taumoeba spawn exceeds capacity");
    const int block = 256;
    const int grid = (count + block - 1) / block;
    spawn_kernel<<<grid, block>>>(s, s.count, s.next_id, seed, count, c);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "taumoeba spawn_kernel"));
    ASTRO_TRY(cuda_check(cudaDeviceSynchronize(), "taumoeba spawn"));
    s.count += count;
    s.next_id += static_cast<uint64_t>(count);
    return ok();
}

void predation_step(World& w, double dt) {
    const int32_t n = w.taumoeba.count;
    if (n <= 0) return;
    const int block = 256;
    const int grid = (n + block - 1) / block;
    const double dt_bio = dt * w.biology_rate;

    // Reset the per-cell claim to the sentinel (all-ones = max u64), so atomicMin
    // resolves to the lowest predator id. memset 0xFF gives exactly that.
    cudaMemset(w.d_predator_claim, 0xFF,
               sizeof(unsigned long long) * static_cast<size_t>(w.cells.capacity));

    hunt_kernel<<<grid, block>>>(w.taumoeba, w.cells.view, hash_view(w.hash), w.motion,
                                 w.chamber, dt, dt_bio, w.d_predator_claim);
    resolve_kernel<<<grid, block>>>(w.taumoeba, w.cells.view,
                                    static_cast<unsigned char>(w.motion.store_disposition),
                                    w.d_predator_claim);
}

namespace {
Error dl3(const double* dx, const double* dy, const double* dz,
          double* x, double* y, double* z, int32_t n) {
    const size_t b = sizeof(double) * static_cast<size_t>(n);
    ASTRO_TRY(cuda_check(cudaMemcpy(x, dx, b, cudaMemcpyDeviceToHost), "tau dl"));
    ASTRO_TRY(cuda_check(cudaMemcpy(y, dy, b, cudaMemcpyDeviceToHost), "tau dl"));
    ASTRO_TRY(cuda_check(cudaMemcpy(z, dz, b, cudaMemcpyDeviceToHost), "tau dl"));
    return ok();
}
} // namespace

Error taumoeba_download_positions(const TaumoebaStore& s, double* x, double* y, double* z,
                                  int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    if (n <= 0) return ok();
    return dl3(s.x, s.y, s.z, x, y, z, n);
}

Error taumoeba_download_biomass(const TaumoebaStore& s, double* biomass, int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    if (n <= 0) return ok();
    return cuda_check(cudaMemcpy(biomass, s.biomass, sizeof(double) * static_cast<size_t>(n),
                                 cudaMemcpyDeviceToHost), "tau dl biomass");
}

} // namespace astro::sim
