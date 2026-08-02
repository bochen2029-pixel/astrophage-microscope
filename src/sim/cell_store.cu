// src/sim/cell_store.cu -- allocation, spawning, and compaction. See MODULE.md.
#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "core/rng.cuh"
#include "core/units.h"
#include "core/vec.cuh"
#include "sim/cell_store.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

constexpr size_t ALIGN = 256;   // CUDA global-load alignment

inline size_t aligned(size_t n) { return (n + ALIGN - 1) / ALIGN * ALIGN; }

// Carve one array out of the blob and advance the cursor. Templated on element
// type so the arithmetic cannot silently use the wrong stride.
template <typename T>
T* carve(char*& cursor, int32_t capacity) {
    T* p = reinterpret_cast<T*>(cursor);
    cursor += aligned(sizeof(T) * static_cast<size_t>(capacity));
    return p;
}

template <typename T>
size_t span(int32_t capacity) { return aligned(sizeof(T) * static_cast<size_t>(capacity)); }

__device__ inline double sample_charge(Pcg32& r, Distribution d, double a, double b) {
    switch (d) {
        case Distribution::Uniform: return uniform_range(r, a, b);
        case Distribution::Normal:  return a + b * gaussian(r);
        case Distribution::Constant:
        default:                    return a;
    }
}

__global__ void spawn_kernel(CellStoreView v, SpawnParams p, Chamber c,
                             int32_t base, uint64_t first_id, uint64_t seed) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= p.count) return;

    const int32_t  slot = base + i;
    const uint64_t id   = first_id + static_cast<uint64_t>(i);

    // The cell's stream depends only on (seed, id) -- never on slot or thread
    // index, so the trajectory survives compaction and launch-config changes.
    uint64_t state = cell_rng_init(seed, id);
    Pcg32 r = cell_rng(state, id);

    double x = 0.0, y = 0.0;
    switch (p.placement) {
        case Placement::Gaussian: {
            double gx, gy;
            gaussian_pair(r, gx, gy);
            x = p.place_x + p.place_radius * gx;
            y = p.place_y + p.place_radius * gy;
            break;
        }
        case Placement::Disc: {
            // sqrt of the radial variate, or the disc is centre-heavy.
            const double rad = p.place_radius * sqrt(uniform01d(r));
            const double ang = uniform_range(r, 0.0, TWO_PI);
            x = p.place_x + rad * cos(ang);
            y = p.place_y + rad * sin(ang);
            break;
        }
        case Placement::Grid: {
            const int side = static_cast<int>(ceil(sqrt(static_cast<double>(p.count))));
            const int gx = i % side;
            const int gy = i / side;
            x = (static_cast<double>(gx) / side - 0.5) * c.w * 0.98;
            y = (static_cast<double>(gy) / side - 0.5) * c.h * 0.98;
            break;
        }
        case Placement::Uniform:
        default:
            x = uniform_range(r, -0.5 * c.w, 0.5 * c.w);
            y = uniform_range(r, -0.5 * c.h, 0.5 * c.h);
            break;
    }

    // Clamp into the chamber: a Gaussian tail must not place a cell in the glass.
    const double a = canon::CELL_RADIUS;
    x = clamp(x, -0.5 * c.w + a, 0.5 * c.w - a);
    y = clamp(y, -0.5 * c.h + a, 0.5 * c.h - a);
    const double z = uniform_range(r, -0.5 * c.d + a, 0.5 * c.d - a);

    const double charge = clamp01(sample_charge(r, p.charge_dist, p.charge_a, p.charge_b));

    v.id[slot]    = id;
    v.flags[slot] = CELL_FLAG_OCCUPIED | CELL_FLAG_ALIVE | (p.awake ? CELL_FLAG_AWAKE : 0u);
    v.death_cause[slot] = static_cast<uint8_t>(DeathCause::None);

    v.x[slot] = x;  v.y[slot] = y;  v.z[slot] = z;
    v.vx[slot] = 0.0; v.vy[slot] = 0.0; v.vz[slot] = 0.0;

    v.energy[slot]    = charge * canon::CELL_ENERGY_MAX;
    // A dormant cell tracks ambient; an awake one clamps to the setpoint
    // (ADR-003). The real ambient comes from the temperature field once M6
    // exists; until then the canon default stands in.
    v.temp_cell[slot] = static_cast<float>(p.awake ? canon::CELL_TEMP_SETPOINT
                                                   : canon::AMBIENT_TEMP_DEFAULT);

    v.emit_power[slot] = 0.0f;
    // Isotropic initial emission axis, so nothing is biased before taxis exists.
    double dx, dy, dz;
    gaussian3(r, dx, dy, dz);
    const Vec3 dir = normalize(Vec3{dx, dy, dz});
    v.dir_x[slot] = static_cast<float>(dir.x);
    v.dir_y[slot] = static_cast<float>(dir.y);
    v.dir_z[slot] = static_cast<float>(dir.z);

    v.biomass[slot]  = canon::CELL_MASS_DRY;
    v.co2_held[slot] = 0.0;
    v.age_s[slot]    = 0.0f;

    v.rng_state[slot]    = r.state;
    v.taxis_memory[slot] = 0.0f;
    v.run_timer[slot]    = 0.0f;

    v.t_local[slot]    = v.temp_cell[slot];
    v.irradiance[slot] = 0.0f;
    v.co2_local[slot]  = 0.0f;
    v.n2_local[slot]   = 0.0f;
}

Error cuda_check(cudaError_t e, const char* what) {
    if (e != cudaSuccess) return fail(Status::CudaError, what);
    return ok();
}

} // namespace

Error cell_store_create(CellStore& s, int32_t capacity) {
    if (capacity <= 0 || capacity > canon::MAX_CELLS)
        return fail(Status::InvalidArgument, "capacity out of range");

    // One term per array, in carve order. An under-allocation here is an
    // out-of-bounds device write, which is silent -- so the tally is spelled out
    // rather than summarised, and the carve is bounds-checked below.
    const size_t exact =
        span<uint64_t>(capacity)      // id
      + span<uint32_t>(capacity)      // flags
      + span<uint8_t>(capacity)       // death_cause
      + span<double>(capacity) * 6    // x,y,z,vx,vy,vz
      + span<double>(capacity)        // energy
      + span<float>(capacity)         // temp_cell
      + span<float>(capacity)         // emit_power
      + span<float>(capacity) * 3     // dir_x,y,z
      + span<double>(capacity) * 2    // biomass, co2_held
      + span<float>(capacity)         // age_s
      + span<uint64_t>(capacity)      // rng_state
      + span<float>(capacity) * 2     // taxis_memory, run_timer
      + span<float>(capacity) * 4;    // t_local, irradiance, co2_local, n2_local

    void* blob = nullptr;
    ASTRO_TRY(cuda_check(cudaMalloc(&blob, exact), "cudaMalloc cell store"));
    ASTRO_TRY(cuda_check(cudaMemset(blob, 0, exact), "cudaMemset cell store"));

    char* cur = static_cast<char*>(blob);
    CellStoreView v{};
    v.id          = carve<uint64_t>(cur, capacity);
    v.flags       = carve<uint32_t>(cur, capacity);
    v.death_cause = carve<uint8_t>(cur, capacity);
    v.x           = carve<double>(cur, capacity);
    v.y           = carve<double>(cur, capacity);
    v.z           = carve<double>(cur, capacity);
    v.vx          = carve<double>(cur, capacity);
    v.vy          = carve<double>(cur, capacity);
    v.vz          = carve<double>(cur, capacity);
    v.energy      = carve<double>(cur, capacity);
    v.temp_cell   = carve<float>(cur, capacity);
    v.emit_power  = carve<float>(cur, capacity);
    v.dir_x       = carve<float>(cur, capacity);
    v.dir_y       = carve<float>(cur, capacity);
    v.dir_z       = carve<float>(cur, capacity);
    v.biomass     = carve<double>(cur, capacity);
    v.co2_held    = carve<double>(cur, capacity);
    v.age_s       = carve<float>(cur, capacity);
    v.rng_state   = carve<uint64_t>(cur, capacity);
    v.taxis_memory= carve<float>(cur, capacity);
    v.run_timer   = carve<float>(cur, capacity);
    v.t_local     = carve<float>(cur, capacity);
    v.irradiance  = carve<float>(cur, capacity);
    v.co2_local   = carve<float>(cur, capacity);
    v.n2_local    = carve<float>(cur, capacity);
    v.count       = 0;
    v.capacity    = capacity;

    const size_t used = static_cast<size_t>(cur - static_cast<char*>(blob));
    if (used > exact) {   // belt and braces: carve order must match the tally
        cudaFree(blob);
        return fail(Status::OutOfMemory, "cell store carve overran its allocation");
    }

    // Scan and compaction scratch, sized once at capacity so the tick loop never
    // allocates (T29 / RENDERING.md Sec 7). The CUB temp size is queried the same
    // way the spatial hash sizes its radix-sort scratch (hash.cu).
    const size_t cap = static_cast<size_t>(capacity);
    size_t scan_bytes = 0;
    cub::DeviceScan::ExclusiveSum(nullptr, scan_bytes, static_cast<int32_t*>(nullptr),
                                  static_cast<int32_t*>(nullptr), capacity);
    int32_t* scan_flags = nullptr;
    int32_t* birth_prefix = nullptr;
    int32_t* birth_count = nullptr;
    int32_t* dead_count = nullptr;
    int32_t* compact_src = nullptr;
    void*    compact_scratch = nullptr;
    void*    cub_temp = nullptr;
    const bool alloc_ok =
        cudaMalloc(&scan_flags,      sizeof(int32_t) * cap) == cudaSuccess &&
        cudaMalloc(&birth_prefix,    sizeof(int32_t) * cap) == cudaSuccess &&
        cudaMalloc(&birth_count,     sizeof(int32_t))       == cudaSuccess &&
        cudaMalloc(&dead_count,      sizeof(int32_t))       == cudaSuccess &&
        cudaMalloc(&compact_src,     sizeof(int32_t) * cap) == cudaSuccess &&
        // 8 bytes = the widest SoA element (double / uint64), so one scratch serves
        // every array in the gather.
        cudaMalloc(&compact_scratch, sizeof(double) * cap)  == cudaSuccess &&
        cudaMalloc(&cub_temp,        scan_bytes ? scan_bytes : 1) == cudaSuccess;
    if (!alloc_ok) {
        cudaFree(blob);
        cudaFree(scan_flags); cudaFree(birth_prefix); cudaFree(birth_count);
        cudaFree(dead_count); cudaFree(compact_src); cudaFree(compact_scratch);
        cudaFree(cub_temp);
        return fail(Status::OutOfMemory, "cudaMalloc cell store scan/compaction buffers");
    }

    s.view = v;
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

void cell_store_destroy(CellStore& s) {
    if (s.blob) cudaFree(s.blob);
    if (s.d_scan_flags) cudaFree(s.d_scan_flags);
    if (s.d_birth_prefix) cudaFree(s.d_birth_prefix);
    if (s.d_birth_count) cudaFree(s.d_birth_count);
    if (s.d_dead_count) cudaFree(s.d_dead_count);
    if (s.d_compact_src) cudaFree(s.d_compact_src);
    if (s.d_compact_scratch) cudaFree(s.d_compact_scratch);
    if (s.d_cub_temp) cudaFree(s.d_cub_temp);
    s = CellStore{};
}

Error cell_store_spawn(CellStore& s, const SpawnParams& p, const Chamber& c, uint64_t seed) {
    if (p.count <= 0) return ok();
    if (s.count + p.count > s.capacity)
        return fail(Status::CapacityExceeded, "spawn exceeds cell store capacity");

    const int block = 256;
    const int grid  = (p.count + block - 1) / block;
    spawn_kernel<<<grid, block>>>(s.view, p, c, s.count, s.next_id, seed);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "spawn_kernel launch"));
    ASTRO_TRY(cuda_check(cudaDeviceSynchronize(), "spawn_kernel"));

    s.count   += p.count;
    s.next_id += static_cast<uint64_t>(p.count);
    s.view.count = s.count;
    return ok();
}

namespace {

__global__ void set_charge_kernel(CellStoreView v, double energy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    if (!(v.flags[i] & CELL_FLAG_OCCUPIED)) return;
    v.energy[i] = energy;
}

} // namespace

Error cell_store_set_charge(CellStore& s, double charge) {
    if (s.count <= 0) return ok();
    const double energy = clamp01(charge) * canon::CELL_ENERGY_MAX;
    const int block = 256;
    set_charge_kernel<<<(s.count + block - 1) / block, block>>>(s.view, energy);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "set_charge_kernel launch"));
    return ok();
}

namespace {

Error download3(const double* dx, const double* dy, const double* dz,
                double* x, double* y, double* z, int32_t n, const char* what) {
    if (n <= 0) return ok();
    const size_t bytes = sizeof(double) * static_cast<size_t>(n);
    ASTRO_TRY(cuda_check(cudaMemcpy(x, dx, bytes, cudaMemcpyDeviceToHost), what));
    ASTRO_TRY(cuda_check(cudaMemcpy(y, dy, bytes, cudaMemcpyDeviceToHost), what));
    ASTRO_TRY(cuda_check(cudaMemcpy(z, dz, bytes, cudaMemcpyDeviceToHost), what));
    return ok();
}

} // namespace

Error cell_store_download_positions(const CellStore& s, double* x, double* y, double* z,
                                    int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    return download3(s.view.x, s.view.y, s.view.z, x, y, z, n, "download positions");
}

Error cell_store_download_velocities(const CellStore& s, double* vx, double* vy, double* vz,
                                     int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    return download3(s.view.vx, s.view.vy, s.view.vz, vx, vy, vz, n, "download velocities");
}

Error cell_store_download_energy(const CellStore& s, double* energy, int32_t max_count) {
    const int32_t n = s.count < max_count ? s.count : max_count;
    if (n <= 0) return ok();
    return cuda_check(cudaMemcpy(energy, s.view.energy, sizeof(double) * static_cast<size_t>(n),
                                 cudaMemcpyDeviceToHost), "download energy");
}

// ---------------------------------------------------------------------------
// Compaction (ADR-028). Everything here is a pure function of the flags array,
// so the result is independent of execution order -- INV-2 one level up, the
// same reasoning that makes daughter slots safe (ADR-025).
// ---------------------------------------------------------------------------
namespace {

__global__ void keep_flags_kernel(CellStoreView v, int32_t* keep, int32_t cnt) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= cnt) return;
    const uint32_t f = v.flags[i];
    // A survivor is a live occupant. Corpses and free slots are dropped.
    keep[i] = ((f & CELL_FLAG_OCCUPIED) && (f & CELL_FLAG_ALIVE)) ? 1 : 0;
}

// Each survivor writes its own source slot to its unique destination (the
// exclusive prefix). Destinations are distinct, so there is no write collision
// and the map does not depend on which thread runs first.
__global__ void scatter_src_kernel(const int32_t* keep, const int32_t* prefix,
                                   int32_t* src, int32_t cnt) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= cnt) return;
    if (keep[i]) src[prefix[i]] = i;
}

__global__ void live_count_kernel(const int32_t* keep, const int32_t* prefix,
                                  int32_t cnt, int32_t* out) {
    // Exclusive prefix of the last element plus the last flag = total survivors.
    *out = prefix[cnt - 1] + keep[cnt - 1];
}

// Gather one SoA array by the source map into scratch. OUT-OF-PLACE: an in-place
// parallel compaction is a read/write race, because a thread writing slot
// prefix[i] <= i can clobber a source another thread has not yet read (ADR-028).
template <typename T>
__global__ void gather_kernel(const T* src_arr, const int32_t* src_idx, T* dst, int32_t live) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k < live) dst[k] = src_arr[src_idx[k]];
}

template <typename T>
void compact_field(T* arr, const int32_t* src, void* scratch, int32_t live) {
    if (live <= 0) return;
    T* sc = reinterpret_cast<T*>(scratch);
    const int block = 256;
    const int grid = (live + block - 1) / block;
    gather_kernel<<<grid, block>>>(arr, src, sc, live);
    // Default stream: the copy is ordered after the gather that filled `sc`.
    cudaMemcpy(arr, sc, sizeof(T) * static_cast<size_t>(live), cudaMemcpyDeviceToDevice);
}

} // namespace

Error cell_store_compact(CellStore& s) {
    const int32_t cnt = s.count;
    if (cnt <= 0) return ok();
    const int block = 256;
    const int grid = (cnt + block - 1) / block;

    keep_flags_kernel<<<grid, block>>>(s.view, s.d_scan_flags, cnt);
    size_t tb = s.cub_temp_bytes;
    cub::DeviceScan::ExclusiveSum(s.d_cub_temp, tb, s.d_scan_flags, s.d_birth_prefix, cnt);
    scatter_src_kernel<<<grid, block>>>(s.d_scan_flags, s.d_birth_prefix, s.d_compact_src, cnt);
    live_count_kernel<<<1, 1>>>(s.d_scan_flags, s.d_birth_prefix, cnt, s.d_birth_count);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "compaction scan"));

    int32_t live = 0;
    ASTRO_TRY(cuda_check(cudaMemcpy(&live, s.d_birth_count, sizeof(int32_t),
                                    cudaMemcpyDeviceToHost), "compaction live count"));
    if (live >= cnt) return ok();   // no dead slots -- nothing to reclaim

    const int32_t* src = s.d_compact_src;
    void* sc = s.d_compact_scratch;
    CellStoreView& v = s.view;
    // Every per-cell array moves, including the field-sample scratch: taxis reads
    // co2_local from the previous tick (ADR-022), so a stale value at a reused slot
    // would be a real bug, not just a cosmetic one.
    compact_field(v.id, src, sc, live);          compact_field(v.flags, src, sc, live);
    compact_field(v.death_cause, src, sc, live); compact_field(v.x, src, sc, live);
    compact_field(v.y, src, sc, live);           compact_field(v.z, src, sc, live);
    compact_field(v.vx, src, sc, live);          compact_field(v.vy, src, sc, live);
    compact_field(v.vz, src, sc, live);          compact_field(v.energy, src, sc, live);
    compact_field(v.temp_cell, src, sc, live);   compact_field(v.emit_power, src, sc, live);
    compact_field(v.dir_x, src, sc, live);       compact_field(v.dir_y, src, sc, live);
    compact_field(v.dir_z, src, sc, live);       compact_field(v.biomass, src, sc, live);
    compact_field(v.co2_held, src, sc, live);    compact_field(v.age_s, src, sc, live);
    compact_field(v.rng_state, src, sc, live);   compact_field(v.taxis_memory, src, sc, live);
    compact_field(v.run_timer, src, sc, live);   compact_field(v.t_local, src, sc, live);
    compact_field(v.irradiance, src, sc, live);  compact_field(v.co2_local, src, sc, live);
    compact_field(v.n2_local, src, sc, live);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "compaction gather"));

    s.count = live;
    s.view.count = live;
    return ok();
}

} // namespace astro::sim
