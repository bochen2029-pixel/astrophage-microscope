// tests/physics/test_fixed_atomic.cu -- INV-2 / INV-4 / ADR-013.
//
// The central determinism claim: the same deposits, accumulated by different
// numbers of threads in different orders, must produce a BIT-IDENTICAL result.
// This test also demonstrates the failure it prevents, by accumulating the same
// values in float and showing that the float sums disagree.
#include <cstdio>

#include "core/fixed_atomic.cuh"
#include "core/rng.cuh"
#include "test_util.h"

using namespace astro;

__global__ void deposit_fixed_kernel(unsigned long long* acc, int n, uint64_t seed, double scale) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    Pcg32 r = cell_rng(cell_rng_init(seed, static_cast<uint64_t>(i)), static_cast<uint64_t>(i));
    // Mixed signs and magnitudes -- the case where float ordering bites hardest.
    const double v = (uniform01d(r) - 0.5) * (1.0 + 1000.0 * uniform01d(r));
    atomic_deposit(acc, v, scale);
}

__global__ void deposit_float_kernel(float* acc, int n, uint64_t seed) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    Pcg32 r = cell_rng(cell_rng_init(seed, static_cast<uint64_t>(i)), static_cast<uint64_t>(i));
    const double v = (uniform01d(r) - 0.5) * (1.0 + 1000.0 * uniform01d(r));
    atomicAdd(acc, static_cast<float>(v));   // deliberately the WRONG way
}

static unsigned long long run_fixed(int n, int block, uint64_t seed, double scale) {
    unsigned long long* d_acc = nullptr;
    cudaMalloc(&d_acc, sizeof(unsigned long long));
    cudaMemset(d_acc, 0, sizeof(unsigned long long));
    deposit_fixed_kernel<<<(n + block - 1) / block, block>>>(d_acc, n, seed, scale);
    cudaDeviceSynchronize();
    unsigned long long h = 0;
    cudaMemcpy(&h, d_acc, sizeof(h), cudaMemcpyDeviceToHost);
    cudaFree(d_acc);
    return h;
}

static float run_float(int n, int block, uint64_t seed) {
    float* d_acc = nullptr;
    cudaMalloc(&d_acc, sizeof(float));
    cudaMemset(d_acc, 0, sizeof(float));
    deposit_float_kernel<<<(n + block - 1) / block, block>>>(d_acc, n, seed);
    cudaDeviceSynchronize();
    float h = 0.0f;
    cudaMemcpy(&h, d_acc, sizeof(h), cudaMemcpyDeviceToHost);
    cudaFree(d_acc);
    return h;
}

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_fixed_atomic: no CUDA device; skipping (this is a GPU test)\n");
        return 0;
    }

    // --- host-side round trip ------------------------------------------------
    CHECK_CLOSE(from_fixed(static_cast<uint64_t>(to_fixed(1.25, 1e9)), 1e9), 1.25, 1e-9);
    CHECK_CLOSE(from_fixed(static_cast<uint64_t>(to_fixed(-7.5e-4, 1e9)), 1e9), -7.5e-4, 1e-9);

    // Negative values must survive the unsigned atomicAdd as two's complement.
    {
        uint64_t acc = 0;
        deposit_host(&acc, 10.0, 1e6);
        deposit_host(&acc, -4.0, 1e6);
        CHECK_CLOSE(from_fixed(acc, 1e6), 6.0, 1e-12);
    }

    // --- the actual invariant -------------------------------------------------
    const int      n     = 1 << 20;
    const uint64_t seed  = 20260802ull;
    const double   scale = 1.0e9;

    const unsigned long long a = run_fixed(n, 32,   seed, scale);
    const unsigned long long b = run_fixed(n, 128,  seed, scale);
    const unsigned long long c = run_fixed(n, 256,  seed, scale);
    const unsigned long long d = run_fixed(n, 1024, seed, scale);

    CHECK_EQ_U64(a, b);
    CHECK_EQ_U64(a, c);
    CHECK_EQ_U64(a, d);   // INV-4: results independent of launch configuration
    std::printf("  fixed-point sum = %.9f (identical across 4 block sizes)\n",
                from_fixed(a, scale));

    // --- and the failure it prevents -----------------------------------------
    // Not an assertion about hardware -- just a demonstration. If float atomics
    // ever DID agree it would be luck, not a guarantee, so we only report.
    const float fa = run_float(n, 32,   seed);
    const float fb = run_float(n, 1024, seed);
    std::printf("  float sums: %.9f vs %.9f  %s\n", fa, fb,
                (fa == fb) ? "(agreed this run -- still not guaranteed)"
                           : "(DISAGREE -- this is why INV-2 exists)");

    // --- overflow headroom ----------------------------------------------------
    // A silent int64 overflow is a correctness bug, not a crash. Any new field
    // scale must clear this check (contracts/fields_v1.h).
    CHECK(deposit_headroom(2000000, 1.0e9) > 1.0e3);    // temperature: >1000 K per cell
    CHECK(deposit_headroom(2000000, 1.0e15) > 1.0e-3);  // CO2/N2: >1e-3 kg/m^3 per cell

    return astro::test::finish("test_fixed_atomic");
}
