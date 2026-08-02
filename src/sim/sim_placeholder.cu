// src/sim/sim_placeholder.cu -- M0 scaffold.
//
// Keeps astro_sim a valid target until M1/M2 populate it, and asserts at compile
// time that the module's headless invariant (INV-5) and precision policy hold.
//
// DELETE THIS FILE when cell_store.cu lands in M1. Remove it from CMakeLists.txt
// in the same commit.
#include "contracts/cell_store_v1.h"
#include "core/canon_generated.h"
#include "core/fixed_atomic.cuh"
#include "core/rng.cuh"
#include "core/vec.cuh"

// INV-5: sim/ must contain no presentation code. If someone includes a GL or
// ImGui header here, this file is where it will first be caught -- but the real
// gate is the grep in scripts/audit.ps1, because a missing include is invisible.
#if defined(GLFW_VERSION_MAJOR) || defined(IMGUI_VERSION) || defined(__gl_h_)
    #error "INV-5 violated: sim/ must not include presentation headers."
#endif

namespace astro::sim {

// The tick counter is the only clock the simulation has (INV-3). Simulated time
// is tick * DT_PHYSICS -- never a wall-clock read.
__host__ __device__ double sim_time_from_tick(unsigned long long tick, double physics_rate) {
    return static_cast<double>(tick) * astro::canon::DT_PHYSICS * physics_rate;
}

// Placeholder kernel so the translation unit produces device code and the CUDA
// toolchain is genuinely exercised by the M0 gate.
__global__ void noop_tick(int n, unsigned long long* touched) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) astro::atomic_deposit_fixed(touched, 1);
}

} // namespace astro::sim
