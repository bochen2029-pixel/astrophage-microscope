// tests/physics/test_perf.cu -- T28 and T29. docs/RENDERING.md Sec 7.
//
// T29 is the load-bearing one: the tick loop must allocate NOTHING in the steady state -- all
// scratch is carved once at world_create. A per-tick cudaMalloc is a correctness-adjacent
// regression (it stalls, and it defeats the zero-allocation budget), and the paths most likely
// to sneak one in are division (the scan buffers) and compaction (the gather). T28 is a sim
// throughput sanity check against the 2.7 ms/tick budget; the render frame budget (T27) is the
// app's --benchmark (gate M1.5), so it is not duplicated in this headless test.
#include <cstdio>
#include <cstdint>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_perf: no CUDA device; skipping\n");
        return 0;
    }

    // --- T29 (GATE): zero device allocation in the steady-state tick loop ------
    // A world that divides AND compacts drives the lifecycle scan buffers and the compaction
    // gather -- the paths most likely to allocate. Free device memory must not fall across the
    // loop even as the population grows: division appends into the capacity carved up front,
    // never reallocates. cudaMemGetInfo catches a leak-shaped regression (the common one).
    {
        World w{};
        WorldDesc d;
        d.capacity = 1 << 20;                       // room to grow, all carved now
        d.seed = 20260802ull;
        d.co2_init = canon::CO2_SAT_CONC_1ATM;      // saturating -> cells divide
        d.motion.boundary_x = Boundary::Absorbing;  // some sink into the wall and die...
        d.motion.boundary_y = Boundary::Absorbing;
        d.motion.compaction_enabled = true;         // ...so compaction runs and reclaims them
        CHECK(!world_create(w, d));
        w.biology_rate = 2.0e7;
        SpawnParams p;
        p.count = 40000;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Constant;
        p.charge_a = 0.5;
        p.awake = false;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));

        // Warm up: first-touch allocation, lazy CUDA module load, the CUB scan's one-time setup.
        for (int t = 0; t < 25; ++t) world_step(w);
        cudaDeviceSynchronize();
        size_t free_before = 0, total = 0;
        CHECK(cudaMemGetInfo(&free_before, &total) == cudaSuccess);

        const int32_t pop_before = w.cells.count;
        for (int t = 0; t < 500; ++t) world_step(w);
        cudaDeviceSynchronize();
        size_t free_after = 0;
        CHECK(cudaMemGetInfo(&free_after, &total) == cudaSuccess);

        const long long dropped = static_cast<long long>(free_before) -
                                  static_cast<long long>(free_after);
        std::printf("  T29: free %.1f -> %.1f MB over 500 ticks (delta %lld KB); pop %d -> %d\n",
                    free_before / 1048576.0, free_after / 1048576.0, dropped / 1024,
                    pop_before, w.cells.count);
        CHECK(w.cells.count != pop_before);   // the store churned (divisions/deaths) -- not vacuous
        // A per-tick allocation drops free by MB over 500 ticks; the margin absorbs only CUDA
        // context bookkeeping, not a real leak (a grid or scan realloc would be far larger).
        CHECK(dropped < (8 << 20));           // < 8 MB drop across the whole loop
        world_destroy(w);
    }

    // --- T28 (GATE): sim tick throughput at the reference population ----------
    // 200k dormant cells: a stable population (no growth to skew the timing). The sim budget is
    // 2.7 ms/tick (RENDERING.md Sec 7); the ceiling here is deliberately generous -- it exists to
    // catch a gross regression, not to police the budget (M1.5's fps target does that with the
    // renderer in the loop). Timed with CUDA events, which measure device time directly.
    {
        const int32_t N = 200000;
        World w{};
        WorldDesc d;
        d.capacity = N;
        d.seed = 20260802ull;
        CHECK(!world_create(w, d));
        SpawnParams p;
        p.count = N;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Constant;
        p.charge_a = 0.02;                    // near-empty: rises slowly, no division
        p.awake = false;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));

        for (int t = 0; t < 10; ++t) world_step(w);   // warm up
        cudaDeviceSynchronize();

        cudaEvent_t a, b;
        cudaEventCreate(&a);
        cudaEventCreate(&b);
        const int ticks = 300;
        cudaEventRecord(a);
        for (int t = 0; t < ticks; ++t) world_step(w);
        cudaEventRecord(b);
        cudaEventSynchronize(b);
        float ms = 0.0f;
        cudaEventElapsedTime(&ms, a, b);
        cudaEventDestroy(a);
        cudaEventDestroy(b);

        const double per_tick = static_cast<double>(ms) / ticks;
        std::printf("  T28: %d cells, %.3f ms/tick (%.0f ticks/s); sim budget 2.7 ms\n",
                    N, per_tick, 1000.0 / per_tick);
        CHECK(per_tick > 0.0);
        CHECK(per_tick < 25.0);   // a gross-regression ceiling, ~9x the 2.7 ms budget
        world_destroy(w);
    }

    return astro::test::finish("test_perf");
}
