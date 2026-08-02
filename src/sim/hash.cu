// src/sim/hash.cu -- build the spatial hash. See hash.cuh for why it is a
// stable radix sort and not the usual atomicAdd counting scatter.
#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/hash.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

__global__ void key_kernel(CellStoreView v, HashView h, uint32_t* keys, uint32_t* vals,
                           int32_t count) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;
    vals[i] = static_cast<uint32_t>(i);
    // Unoccupied slots go to a sentinel bucket past the end so they sort to the
    // back and are never visited by a neighbour query.
    keys[i] = (v.flags[i] & CELL_FLAG_OCCUPIED)
            ? hash_key(h, v.x[i], v.y[i], v.z[i])
            : static_cast<uint32_t>(h.bucket_count);
}

// Bucket ranges from adjacent-key comparison. Avoids a prefix scan entirely, and
// buckets with no members simply keep start == end == 0 from the memset.
__global__ void range_kernel(const uint32_t* keys_sorted, int32_t count,
                             int32_t* bucket_start, int32_t* bucket_end,
                             int32_t bucket_count) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;
    const uint32_t k = keys_sorted[i];
    if (k >= static_cast<uint32_t>(bucket_count)) return;   // sentinel
    if (i == 0 || keys_sorted[i - 1] != k) bucket_start[k] = i;
    if (i == count - 1 || keys_sorted[i + 1] != k) bucket_end[k] = i + 1;
}

Error cuda_check(cudaError_t e, const char* what) {
    return (e == cudaSuccess) ? ok() : fail(Status::CudaError, what);
}

} // namespace

Error hash_create(SpatialHash& h, const Chamber& c, int32_t capacity) {
    h.cell_size = canon::HASH_CELL_FACTOR * canon::CELL_DIAMETER;
    h.nx = static_cast<int32_t>(ceil(c.w / h.cell_size));
    h.ny = static_cast<int32_t>(ceil(c.h / h.cell_size));
    h.nz = static_cast<int32_t>(ceil(c.d / h.cell_size));
    if (h.nx < 1) h.nx = 1;
    if (h.ny < 1) h.ny = 1;
    if (h.nz < 1) h.nz = 1;
    h.bucket_count = h.nx * h.ny * h.nz;
    h.capacity = capacity;

    const size_t n = static_cast<size_t>(capacity);
    const size_t nb = static_cast<size_t>(h.bucket_count);
    if (cudaMalloc(&h.d_keys,         sizeof(uint32_t) * n)  != cudaSuccess ||
        cudaMalloc(&h.d_keys_sorted,  sizeof(uint32_t) * n)  != cudaSuccess ||
        cudaMalloc(&h.d_vals,         sizeof(uint32_t) * n)  != cudaSuccess ||
        cudaMalloc(&h.d_vals_sorted,  sizeof(uint32_t) * n)  != cudaSuccess ||
        cudaMalloc(&h.d_bucket_start, sizeof(int32_t) * nb)  != cudaSuccess ||
        cudaMalloc(&h.d_bucket_end,   sizeof(int32_t) * nb)  != cudaSuccess) {
        hash_destroy(h);
        return fail(Status::OutOfMemory, "cudaMalloc spatial hash");
    }

    // Size the sort scratch once, at capacity, so the tick loop never allocates
    // (test T29 / RENDERING.md Sec 7: zero steady-state device allocation).
    size_t bytes = 0;
    cub::DeviceRadixSort::SortPairs(nullptr, bytes, h.d_keys, h.d_keys_sorted,
                                    h.d_vals, h.d_vals_sorted, capacity);
    if (cudaMalloc(&h.d_temp, bytes) != cudaSuccess) {
        hash_destroy(h);
        return fail(Status::OutOfMemory, "cudaMalloc radix sort scratch");
    }
    h.temp_bytes = bytes;
    return ok();
}

void hash_destroy(SpatialHash& h) {
    cudaFree(h.d_keys);         cudaFree(h.d_keys_sorted);
    cudaFree(h.d_vals);         cudaFree(h.d_vals_sorted);
    cudaFree(h.d_bucket_start); cudaFree(h.d_bucket_end);
    cudaFree(h.d_temp);
    h = SpatialHash{};
}

HashView hash_view(const SpatialHash& h) {
    HashView v{};
    v.vals_sorted  = h.d_vals_sorted;
    v.bucket_start = h.d_bucket_start;
    v.bucket_end   = h.d_bucket_end;
    v.nx = h.nx; v.ny = h.ny; v.nz = h.nz;
    v.bucket_count = h.bucket_count;
    v.cell_size     = static_cast<float>(h.cell_size);
    v.inv_cell_size = static_cast<float>(1.0 / h.cell_size);
    // The chamber is centred on the origin; the hash indexes from its min corner.
    v.origin_x = static_cast<float>(-0.5 * h.nx * h.cell_size);
    v.origin_y = static_cast<float>(-0.5 * h.ny * h.cell_size);
    v.origin_z = static_cast<float>(-0.5 * h.nz * h.cell_size);
    return v;
}

Error hash_build(SpatialHash& h, const CellStoreView& cells, int32_t count) {
    if (count <= 0) return ok();
    if (count > h.capacity) return fail(Status::CapacityExceeded, "hash_build count > capacity");

    ASTRO_TRY(cuda_check(cudaMemset(h.d_bucket_start, 0, sizeof(int32_t) * h.bucket_count),
                         "memset bucket_start"));
    ASTRO_TRY(cuda_check(cudaMemset(h.d_bucket_end, 0, sizeof(int32_t) * h.bucket_count),
                         "memset bucket_end"));

    const int block = 256;
    const int grid = (count + block - 1) / block;
    const HashView view = hash_view(h);

    key_kernel<<<grid, block>>>(cells, view, h.d_keys, h.d_vals, count);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "key_kernel"));

    // Radix sort is STABLE, so equal keys keep their input (slot) order. That is
    // what makes the neighbour iteration order reproducible -- see hash.cuh.
    size_t bytes = h.temp_bytes;
    const cudaError_t se = cub::DeviceRadixSort::SortPairs(
        h.d_temp, bytes, h.d_keys, h.d_keys_sorted, h.d_vals, h.d_vals_sorted, count);
    ASTRO_TRY(cuda_check(se, "cub::DeviceRadixSort::SortPairs"));

    range_kernel<<<grid, block>>>(h.d_keys_sorted, count,
                                  h.d_bucket_start, h.d_bucket_end, h.bucket_count);
    ASTRO_TRY(cuda_check(cudaGetLastError(), "range_kernel"));
    return ok();
}

} // namespace astro::sim
