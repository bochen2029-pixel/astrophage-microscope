// src/fields/diffuse.cu -- explicit FTCS with ping-pong buffers.
#include <cuda_runtime.h>

#include <cmath>
#include <vector>

#include "fields/grid.cuh"

namespace astro::fields {

namespace {

Error cuda_check(cudaError_t e, const char* what) {
    return (e == cudaSuccess) ? ok() : fail(Status::CudaError, what);
}

// One explicit substep. Reads `src` only, writes `dst` only -- that separation
// is what makes the step both correct and deterministic.
__global__ void diffuse_kernel(const float* __restrict__ src, float* __restrict__ dst,
                               int32_t n, float coeff, int bc, float ambient,
                               float robin) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    const int32_t j = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= n || j >= n) return;

    const float c = src[j * n + i];

    // Ghost value outside the domain, per boundary condition:
    //   Neumann   zero flux  -> ghost = c, contributing nothing
    //   Dirichlet held value -> ghost = ambient
    //   Robin     convective -> ghost = c - robin * (c - ambient)
    auto ghost = [&]() -> float {
        if (bc == static_cast<int>(BoundaryCondition::Dirichlet)) return ambient;
        if (bc == static_cast<int>(BoundaryCondition::Robin)) return c - robin * (c - ambient);
        return c;
    };

    const float l = (i > 0)     ? src[j * n + (i - 1)] : ghost();
    const float r = (i < n - 1) ? src[j * n + (i + 1)] : ghost();
    const float d = (j > 0)     ? src[(j - 1) * n + i] : ghost();
    const float u = (j < n - 1) ? src[(j + 1) * n + i] : ghost();

    dst[j * n + i] = c + coeff * (l + r + d + u - 4.0f * c);
}

__global__ void fill_kernel(float* v, int32_t count, float value) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < count) v[i] = value;
}

__global__ void flush_kernel(float* value, unsigned long long* deposit, int32_t count,
                             double scale) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;
    const unsigned long long raw = deposit[i];
    if (raw != 0ull) {
        value[i] += static_cast<float>(astro::from_fixed(raw, scale));
        deposit[i] = 0ull;
    }
}

__global__ void brush_kernel(float* value, int32_t n, float dx, float cx, float cy,
                             float radius, float amount) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    const int32_t j = blockIdx.y * blockDim.y + threadIdx.y;
    if (i >= n || j >= n) return;
    const float half = 0.5f * n * dx;
    const float x = (i + 0.5f) * dx - half;
    const float y = (j + 0.5f) * dx - half;
    const float r = sqrtf((x - cx) * (x - cx) + (y - cy) * (y - cy));
    if (r > radius) return;
    // Smooth falloff, so a brush stroke does not leave a hard-edged disc that
    // the diffusion step then has to spend substeps smoothing out.
    const float t = r / radius;
    const float w = (1.0f - t * t) * (1.0f - t * t);
    value[j * n + i] += amount * w;
}

} // namespace

Error grid_brush(Grid2D& g, double x, double y, double radius, double amount) {
    if (radius <= 0.0) return ok();
    const dim3 block(16, 16);
    const dim3 grid((g.n + block.x - 1) / block.x, (g.n + block.y - 1) / block.y);
    brush_kernel<<<grid, block>>>(g.value, g.n, static_cast<float>(g.dx),
                                  static_cast<float>(x), static_cast<float>(y),
                                  static_cast<float>(radius), static_cast<float>(amount));
    return cuda_check(cudaGetLastError(), "brush_kernel");
}

Error grid_create(Grid2D& g, int32_t n, double extent, double diffusivity,
                  double ambient, double deposit_scale, BoundaryCondition bc,
                  double dt) {
    if (n <= 1 || extent <= 0.0) return fail(Status::InvalidArgument, "grid_create");
    g.n = n;
    g.extent = extent;
    g.dx = extent / static_cast<double>(n);
    g.diffusivity = diffusivity;
    g.ambient = ambient;
    g.deposit_scale = deposit_scale;
    g.bc = bc;
    g.robin_coeff = g.dx * canon::AIR_CONVECTION_H / canon::WATER_CONDUCTIVITY;

    // Substeps come from the stability criterion, never from a guess. At least 1
    // even when the field is barely diffusive.
    const double dt_max = g.dx * g.dx / (4.0 * diffusivity);
    g.substeps = static_cast<int32_t>(dt / dt_max) + 1;

    const size_t count = static_cast<size_t>(n) * n;
    if (cudaMalloc(&g.value,   sizeof(float) * count) != cudaSuccess ||
        cudaMalloc(&g.scratch, sizeof(float) * count) != cudaSuccess ||
        cudaMalloc(&g.deposit, sizeof(unsigned long long) * count) != cudaSuccess) {
        grid_destroy(g);
        return fail(Status::OutOfMemory, "cudaMalloc grid");
    }
    ASTRO_TRY(cuda_check(cudaMemset(g.deposit, 0, sizeof(unsigned long long) * count),
                         "memset deposit"));
    return grid_fill(g, static_cast<float>(ambient));
}

void grid_destroy(Grid2D& g) {
    cudaFree(g.value);
    cudaFree(g.scratch);
    cudaFree(g.deposit);
    g = Grid2D{};
}

Error grid_fill(Grid2D& g, float value) {
    const int32_t count = g.n * g.n;
    const int block = 256;
    fill_kernel<<<(count + block - 1) / block, block>>>(g.value, count, value);
    fill_kernel<<<(count + block - 1) / block, block>>>(g.scratch, count, value);
    return cuda_check(cudaGetLastError(), "fill_kernel");
}

Error grid_flush_deposits(Grid2D& g) {
    const int32_t count = g.n * g.n;
    const int block = 256;
    flush_kernel<<<(count + block - 1) / block, block>>>(g.value, g.deposit, count,
                                                         g.deposit_scale);
    return cuda_check(cudaGetLastError(), "flush_kernel");
}

Error grid_diffuse(Grid2D& g, double dt) {
    if (g.substeps <= 0) return ok();
    const double dt_sub = dt / g.substeps;
    const float coeff = static_cast<float>(g.diffusivity * dt_sub / (g.dx * g.dx));

    // The explicit stability bound. Tripping this means a resolution or timestep
    // changed without re-deriving the substep count -- fail loudly rather than
    // produce a field that quietly oscillates and then goes NaN.
    if (!(coeff <= 0.25f)) return fail(Status::InvalidArgument, "diffusion coefficient unstable");

    const dim3 block(16, 16);
    const dim3 grid((g.n + block.x - 1) / block.x, (g.n + block.y - 1) / block.y);
    for (int32_t s = 0; s < g.substeps; ++s) {
        diffuse_kernel<<<grid, block>>>(g.value, g.scratch, g.n, coeff,
                                        static_cast<int>(g.bc),
                                        static_cast<float>(g.ambient),
                                        static_cast<float>(g.robin_coeff));
        float* tmp = g.value;
        g.value = g.scratch;
        g.scratch = tmp;
    }
    return cuda_check(cudaGetLastError(), "diffuse_kernel");
}

Error grid_download(const Grid2D& g, float* out) {
    return cuda_check(cudaMemcpy(out, g.value, sizeof(float) * g.n * g.n,
                                 cudaMemcpyDeviceToHost), "grid_download");
}

FieldView grid_view(const Grid2D& g) {
    FieldView v{};
    v.value = g.value;
    v.deposit = g.deposit;
    v.n = g.n;
    v.dx = static_cast<float>(g.dx);
    v.diffusivity = static_cast<float>(g.diffusivity);
    v.substeps = g.substeps;
    v.bc = g.bc;
    v.ambient = static_cast<float>(g.ambient);
    v.deposit_scale = g.deposit_scale;
    return v;
}

} // namespace astro::fields
