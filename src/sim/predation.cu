// src/sim/predation.cu -- Taumoeba crawl and engulfment (M10a). docs/PHYSICS.md Sec 11.
//
// Runs as a tick stage before lifecycle: it kills prey, and lifecycle then disposes
// of the corpses. The cell spatial hash it senses is built at stage 1, so prey
// positions carry the same one-tick lag the CO2 sample does (ADR-022) -- sub-micron
// against a 25 um engulf radius, negligible.
#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include "fields/grid.cuh"       // grid_sample (N2 read, M10b)
#include "sim/hash.cuh"
#include "sim/lifecycle.cuh"     // corpse_energy, division_axis
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
    // DRY biomass, the growth variable it divides on; the water-blob mass TAU_MASS is
    // used only for drag/inertia (ADR-030). It grows by eating and divides at 2x.
    v.biomass[slot] = canon::TAU_MASS_DRY;
    v.prey_biomass[slot] = 0.0;
    v.digest_timer[slot] = 0.0f;
    v.tolerance[slot] = static_cast<float>(canon::TAU_N2_TOLERANCE_INIT);
    v.generation[slot] = 0u;                // founders are generation 0
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

// Stage 10c (M10b). N2 lethality. Every alive Taumoeba draws ONE uniform from its own
// stream -- UNCONDITIONALLY, whether it dies or survives -- so the stream stays a pure
// function of state (ADR-022: both branches draw, or neither). Its tolerance raises the
// concentration it can withstand; above threshold the Poisson hazard kills it. The N2
// read is bilinear, in kg/m^3, matching TAU_N2_LETHAL_CONC's units (meta-lesson 9).
__global__ void nitrogen_kernel(TaumoebaStore t, FieldView n2, double dt_bio) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= t.count) return;
    const uint32_t f = t.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;

    Pcg32 rng = cell_rng(t.rng_state[i], t.id[i]);
    const double u = uniform01d(rng);                  // ALWAYS drawn (ADR-022)
    t.rng_state[i] = rng.state;

    const double n2_local = static_cast<double>(astro::fields::grid_sample(
        n2, static_cast<float>(t.x[i]), static_cast<float>(t.y[i])));
    const double hazard = tau_n2_hazard(n2_local, static_cast<double>(t.tolerance[i]));
    if (u < tau_n2_death_prob(hazard, dt_bio))
        t.flags[i] = f & ~static_cast<uint32_t>(CELL_FLAG_ALIVE);   // nitrogen kill
}

// Stage 10d, pass 1 (M10b). Mark the Taumoeba that divide (dry biomass >= 2x initial)
// into the scan buffer and count both divisions and reclaimable dead slots -- exactly
// the cell mitosis structure (ADR-025). COUNTS via atomicAdd are order-free (integer
// addition is associative); the ordered SLOT assignment below is what needs the scan.
__global__ void tau_mark_kernel(TaumoebaStore t, int32_t* flagsum, int32_t* total,
                                int32_t* dead) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= t.count) return;
    const uint32_t f = t.flags[i];
    const bool occupied = (f & CELL_FLAG_OCCUPIED) != 0u;
    const bool alive    = (f & CELL_FLAG_ALIVE) != 0u;
    const bool divides  = occupied && alive && tau_ready_to_divide(t.biomass[i]);
    flagsum[i] = divides ? 1 : 0;
    if (divides) atomicAdd(total, 1);
    if (occupied && !alive) atomicAdd(dead, 1);
}

// Stage 10d, pass 2 (M10b). Split. Parent keeps its slot and id; the daughter takes
// base + the parent's exclusive prefix, so the parent->daughter map is a pure function
// of the population, not of execution order (ADR-025). Biomass is split in half
// (conserved); the daughter inherits a MUTATED tolerance drawn from its OWN stream, so
// the parent's trajectory never depends on whether it divided.
__global__ void tau_divide_kernel(TaumoebaStore t, const int32_t* prefix, int32_t base,
                                  int32_t old_count, uint64_t first_id, Chamber c) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= old_count) return;
    const uint32_t f = t.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;
    if (!tau_ready_to_divide(t.biomass[i])) return;

    const int32_t slot = base + prefix[i];
    if (slot >= t.capacity) return;                    // store full: skip, do not wrap
    const uint64_t did = first_id + static_cast<uint64_t>(prefix[i]);

    // Biomass split in half: the accumulated growth built the daughter (conserved).
    const double half = 0.5 * t.biomass[i];
    t.biomass[i] = half;
    t.biomass[slot] = half;

    // The daughter's stream depends only on (parent state, daughter id) -- ADR-014/025.
    // The mutation is the FIRST draw from THAT stream, so the parent consumes none.
    const uint64_t dstate = pcg_split(t.rng_state[i], did);
    Pcg32 dr = cell_rng(dstate, did);
    const double mutation = gaussian(dr);
    t.tolerance[slot] = tau_daughter_tolerance(t.tolerance[i], mutation);
    t.rng_state[slot] = dr.state;
    t.generation[slot] = t.generation[i] + 1u;         // lineage depth

    // Placed one radius either side along an axis hashed from the daughter id, so
    // placement consumes no draw (ADR-025) and the pair starts just touching.
    double ax, ay, az;
    division_axis(did, ax, ay, az);
    const double a = canon::TAU_RADIUS;
    t.x[slot] = t.x[i] + a * ax;  t.x[i] -= a * ax;
    t.y[slot] = t.y[i] + a * ay;  t.y[i] -= a * ay;
    t.z[slot] = t.z[i] + a * az;  t.z[i] -= a * az;
    const double hx = 0.5 * c.w - a, hy = 0.5 * c.h - a, hz = 0.5 * c.d - a;
    t.x[slot] = t.x[slot] < -hx ? -hx : (t.x[slot] > hx ? hx : t.x[slot]);
    t.y[slot] = t.y[slot] < -hy ? -hy : (t.y[slot] > hy ? hy : t.y[slot]);
    t.z[slot] = t.z[slot] < -hz ? -hz : (t.z[slot] > hz ? hz : t.z[slot]);
    t.x[i] = t.x[i] < -hx ? -hx : (t.x[i] > hx ? hx : t.x[i]);
    t.y[i] = t.y[i] < -hy ? -hy : (t.y[i] > hy ? hy : t.y[i]);
    t.z[i] = t.z[i] < -hz ? -hz : (t.z[i] > hz ? hz : t.z[i]);

    t.id[slot] = did;
    t.flags[slot] = t.flags[i];                        // inherits OCCUPIED | ALIVE
    t.vx[slot] = t.vx[i]; t.vy[slot] = t.vy[i]; t.vz[slot] = t.vz[i];
    t.dir_x[slot] = t.dir_x[i]; t.dir_y[slot] = t.dir_y[i]; t.dir_z[slot] = t.dir_z[i];
    t.prey_biomass[slot] = 0.0;                        // daughter starts hunting
    t.digest_timer[slot] = 0.0f;
    t.density_ema[slot] = 0.0f;
    t.run_timer[slot] = 0.0f;
    t.target[slot] = -1;
}

// --- Compaction (ADR-028), mirroring cell_store.cu. A pure function of the flags, so
// it cannot perturb determinism even though it reorders the SoA. Out-of-place, because
// an in-place parallel compaction is a read/write race.
__global__ void tau_keep_flags_kernel(TaumoebaStore t, int32_t* keep, int32_t cnt) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= cnt) return;
    const uint32_t f = t.flags[i];
    keep[i] = ((f & CELL_FLAG_OCCUPIED) && (f & CELL_FLAG_ALIVE)) ? 1 : 0;
}

__global__ void tau_scatter_src_kernel(const int32_t* keep, const int32_t* prefix,
                                       int32_t* src, int32_t cnt) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= cnt) return;
    if (keep[i]) src[prefix[i]] = i;
}

__global__ void tau_live_count_kernel(const int32_t* keep, const int32_t* prefix,
                                      int32_t cnt, int32_t* out) {
    *out = prefix[cnt - 1] + keep[cnt - 1];
}

template <typename T>
__global__ void tau_gather_kernel(const T* src_arr, const int32_t* idx, T* dst, int32_t live) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k < live) dst[k] = src_arr[idx[k]];
}

template <typename T>
void tau_compact_field(T* arr, const int32_t* src, void* scratch, int32_t live) {
    if (live <= 0) return;
    T* sc = reinterpret_cast<T*>(scratch);
    const int block = 256;
    const int grid = (live + block - 1) / block;
    tau_gather_kernel<<<grid, block>>>(arr, src, sc, live);
    cudaMemcpy(arr, sc, sizeof(T) * static_cast<size_t>(live), cudaMemcpyDeviceToDevice);
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
      + span<uint32_t>(capacity)        // generation
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
    s.generation  = carve<uint32_t>(cur, capacity);
    s.rng_state   = carve<uint64_t>(cur, capacity);
    s.density_ema = carve<float>(cur, capacity);
    s.run_timer   = carve<float>(cur, capacity);
    s.target      = carve<int32_t>(cur, capacity);

    if (static_cast<size_t>(cur - static_cast<char*>(blob)) > exact) {
        cudaFree(blob);
        return fail(Status::OutOfMemory, "taumoeba store carve overran its allocation");
    }

    // Scan + compaction scratch, sized once at capacity so the tick loop never
    // allocates (ADR-028). CUB temp size is queried the way cell_store.cu does it.
    const size_t cap = static_cast<size_t>(capacity);
    size_t scan_bytes = 0;
    cub::DeviceScan::ExclusiveSum(nullptr, scan_bytes, static_cast<int32_t*>(nullptr),
                                  static_cast<int32_t*>(nullptr), capacity);
    int32_t *scan_flags = nullptr, *birth_prefix = nullptr, *birth_count = nullptr;
    int32_t *dead_count = nullptr, *compact_src = nullptr;
    void *compact_scratch = nullptr, *cub_temp = nullptr;
    const bool alloc_ok =
        cudaMalloc(&scan_flags,      sizeof(int32_t) * cap) == cudaSuccess &&
        cudaMalloc(&birth_prefix,    sizeof(int32_t) * cap) == cudaSuccess &&
        cudaMalloc(&birth_count,     sizeof(int32_t))       == cudaSuccess &&
        cudaMalloc(&dead_count,      sizeof(int32_t))       == cudaSuccess &&
        cudaMalloc(&compact_src,     sizeof(int32_t) * cap) == cudaSuccess &&
        // 8 bytes = the widest SoA element (double / uint64), so one scratch serves all.
        cudaMalloc(&compact_scratch, sizeof(double) * cap)  == cudaSuccess &&
        cudaMalloc(&cub_temp,        scan_bytes ? scan_bytes : 1) == cudaSuccess;
    if (!alloc_ok) {
        cudaFree(blob);
        cudaFree(scan_flags); cudaFree(birth_prefix); cudaFree(birth_count);
        cudaFree(dead_count); cudaFree(compact_src); cudaFree(compact_scratch);
        cudaFree(cub_temp);
        return fail(Status::OutOfMemory, "cudaMalloc taumoeba scan/compaction buffers");
    }

    s.blob = blob;
    s.blob_bytes = exact;
    s.capacity = capacity;
    s.count = 0;
    s.next_id = 1;
    s.d_scan_flags = scan_flags;
    s.d_birth_prefix = birth_prefix;
    s.d_birth_count = birth_count;
    s.d_dead_count = dead_count;
    s.d_compact_src = compact_src;
    s.d_compact_scratch = compact_scratch;
    s.d_cub_temp = cub_temp;
    s.cub_temp_bytes = scan_bytes;
    return ok();
}

void taumoeba_destroy(TaumoebaStore& s) {
    if (s.blob) cudaFree(s.blob);
    if (s.d_scan_flags) cudaFree(s.d_scan_flags);
    if (s.d_birth_prefix) cudaFree(s.d_birth_prefix);
    if (s.d_birth_count) cudaFree(s.d_birth_count);
    if (s.d_dead_count) cudaFree(s.d_dead_count);
    if (s.d_compact_src) cudaFree(s.d_compact_src);
    if (s.d_compact_scratch) cudaFree(s.d_compact_scratch);
    if (s.d_cub_temp) cudaFree(s.d_cub_temp);
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

    // Stage 10c (M10b). N2 lethality: one uniform per alive predator, deterministic
    // death. Runs after the engulf so a predator that dies this tick still ate its
    // last meal.
    nitrogen_kernel<<<grid, block>>>(w.taumoeba, fields::grid_view(w.fields.n2), dt_bio);

    // Stage 10d (M10b). Division at 2x dry biomass, mirroring cell mitosis (ADR-025).
    // One pass marks divisions and counts dead slots; both D2H reads are small and only
    // run while predators exist (the 200k render benchmark spawns none, so it pays
    // nothing -- meta-lesson 7).
    cudaMemset(w.taumoeba.d_birth_count, 0, sizeof(int32_t));
    cudaMemset(w.taumoeba.d_dead_count, 0, sizeof(int32_t));
    tau_mark_kernel<<<grid, block>>>(w.taumoeba, w.taumoeba.d_scan_flags,
                                     w.taumoeba.d_birth_count, w.taumoeba.d_dead_count);
    int32_t births = 0, deads = 0;
    cudaMemcpy(&births, w.taumoeba.d_birth_count, sizeof(int32_t), cudaMemcpyDeviceToHost);
    cudaMemcpy(&deads,  w.taumoeba.d_dead_count,  sizeof(int32_t), cudaMemcpyDeviceToHost);

    if (births > 0) {
        // Daughter slots come from an exclusive prefix sum over the divides flag, never
        // atomicAdd, so the parent->daughter map is order-free and the hash is stable.
        size_t tb = w.taumoeba.cub_temp_bytes;
        cub::DeviceScan::ExclusiveSum(w.taumoeba.d_cub_temp, tb, w.taumoeba.d_scan_flags,
                                      w.taumoeba.d_birth_prefix, n);
        int32_t base = n;
        if (base + births > w.taumoeba.capacity) births = w.taumoeba.capacity - base;
        if (births > 0) {
            tau_divide_kernel<<<grid, block>>>(w.taumoeba, w.taumoeba.d_birth_prefix, base, n,
                                               w.taumoeba.next_id, w.chamber);
            w.taumoeba.next_id += static_cast<uint64_t>(births);
            w.taumoeba.count += births;
        }
    }

    // Reclaim dead predator slots (ADR-028), opt-in and only when there is something to
    // reclaim. After division, so daughters born this tick are packed in too. Off by
    // default keeps M10a bit-identical.
    if (w.motion.tau_compaction_enabled && deads > 0) taumoeba_store_compact(w.taumoeba);
}

Error taumoeba_store_compact(TaumoebaStore& s) {
    const int32_t cnt = s.count;
    if (cnt <= 0) return ok();
    const int block = 256;
    const int grid = (cnt + block - 1) / block;

    tau_keep_flags_kernel<<<grid, block>>>(s, s.d_scan_flags, cnt);
    size_t tb = s.cub_temp_bytes;
    cub::DeviceScan::ExclusiveSum(s.d_cub_temp, tb, s.d_scan_flags, s.d_birth_prefix, cnt);
    tau_scatter_src_kernel<<<grid, block>>>(s.d_scan_flags, s.d_birth_prefix, s.d_compact_src, cnt);
    tau_live_count_kernel<<<1, 1>>>(s.d_scan_flags, s.d_birth_prefix, cnt, s.d_birth_count);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "taumoeba compaction scan"));

    int32_t live = 0;
    ASTRO_TRY(cuda_check(cudaMemcpy(&live, s.d_birth_count, sizeof(int32_t),
                                    cudaMemcpyDeviceToHost), "taumoeba compaction live count"));
    if (live >= cnt) return ok();                       // nothing dead -- nothing to do

    const int32_t* src = s.d_compact_src;
    void* sc = s.d_compact_scratch;
    tau_compact_field(s.id, src, sc, live);           tau_compact_field(s.flags, src, sc, live);
    tau_compact_field(s.x, src, sc, live);            tau_compact_field(s.y, src, sc, live);
    tau_compact_field(s.z, src, sc, live);            tau_compact_field(s.vx, src, sc, live);
    tau_compact_field(s.vy, src, sc, live);           tau_compact_field(s.vz, src, sc, live);
    tau_compact_field(s.dir_x, src, sc, live);        tau_compact_field(s.dir_y, src, sc, live);
    tau_compact_field(s.dir_z, src, sc, live);        tau_compact_field(s.biomass, src, sc, live);
    tau_compact_field(s.prey_biomass, src, sc, live); tau_compact_field(s.digest_timer, src, sc, live);
    tau_compact_field(s.tolerance, src, sc, live);    tau_compact_field(s.generation, src, sc, live);
    tau_compact_field(s.rng_state, src, sc, live);    tau_compact_field(s.density_ema, src, sc, live);
    tau_compact_field(s.run_timer, src, sc, live);    tau_compact_field(s.target, src, sc, live);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "taumoeba compaction gather"));

    s.count = live;
    return ok();
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

Error taumoeba_download_tolerance(const TaumoebaStore& s, float* tolerance, int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    if (n <= 0) return ok();
    return cuda_check(cudaMemcpy(tolerance, s.tolerance, sizeof(float) * static_cast<size_t>(n),
                                 cudaMemcpyDeviceToHost), "tau dl tolerance");
}

Error taumoeba_download_generation(const TaumoebaStore& s, uint32_t* generation, int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    if (n <= 0) return ok();
    return cuda_check(cudaMemcpy(generation, s.generation, sizeof(uint32_t) * static_cast<size_t>(n),
                                 cudaMemcpyDeviceToHost), "tau dl generation");
}

Error taumoeba_download_flags(const TaumoebaStore& s, uint32_t* flags, int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    if (n <= 0) return ok();
    return cuda_check(cudaMemcpy(flags, s.flags, sizeof(uint32_t) * static_cast<size_t>(n),
                                 cudaMemcpyDeviceToHost), "tau dl flags");
}

} // namespace astro::sim
