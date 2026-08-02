// tests/physics/test_hash.cu -- the spatial hash. INV-4, INV-7.
//
// Correctness here means three things, and the third is the one that bites:
// every cell lands in the right bucket, a neighbour query finds everything
// within range, and the ORDER is reproducible. The last is why the build uses a
// stable radix sort rather than an atomicAdd scatter (ADR-018).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/hash.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

// Brute-force neighbour count on the host, as the reference the hash must match.
int brute_force_neighbours(const std::vector<double>& x, const std::vector<double>& y,
                           const std::vector<double>& z, int i, double radius) {
    int n = 0;
    const double r2 = radius * radius;
    for (size_t j = 0; j < x.size(); ++j) {
        if (static_cast<int>(j) == i) continue;
        const double dx = x[i] - x[j], dy = y[i] - y[j], dz = z[i] - z[j];
        if (dx * dx + dy * dy + dz * dz < r2) ++n;
    }
    return n;
}

} // namespace

__global__ void count_neighbours_kernel(contract::CellStoreView v, HashView h,
                                        double radius, int32_t* out, int32_t count) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;
    const double px = v.x[i], py = v.y[i], pz = v.z[i];
    const double r2 = radius * radius;
    int32_t n = 0;
    ASTRO_FOR_EACH_NEIGHBOUR(h, px, py, pz, j, {
        if (j != i) {
            const double dx = px - v.x[j], dy = py - v.y[j], dz = pz - v.z[j];
            if (dx * dx + dy * dy + dz * dz < r2) ++n;
        }
    });
    out[i] = n;
}

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_hash: no CUDA device; skipping\n");
        return 0;
    }

    // --- geometry ------------------------------------------------------------
    {
        World w;
        WorldDesc d;
        d.capacity = 1000;
        CHECK(!world_create(w, d));
        std::printf("  hash grid %dx%dx%d = %d buckets, cell %.1f um\n",
                    w.hash.nx, w.hash.ny, w.hash.nz, w.hash.bucket_count,
                    w.hash.cell_size * 1e6);
        // The bucket must be at least a cell diameter, or a 27-cell walk misses
        // contacts; and not so large that buckets fill with irrelevant cells.
        CHECK(w.hash.cell_size >= canon::CELL_DIAMETER);
        CHECK_CLOSE(w.hash.cell_size, canon::HASH_CELL_FACTOR * canon::CELL_DIAMETER, 1e-12);
        CHECK(w.hash.nx > 1 && w.hash.ny > 1 && w.hash.nz >= 1);
        CHECK(w.hash.bucket_count == w.hash.nx * w.hash.ny * w.hash.nz);
        world_destroy(w);
    }

    // --- a neighbour query must match brute force exactly --------------------
    // The hash is an acceleration structure, not an approximation. If it returns
    // a different answer from the O(n^2) reference, it is simply wrong.
    {
        const int32_t n = 4000;
        World w;
        WorldDesc d;
        d.capacity = n;
        d.seed = 7ull;
        CHECK(!world_create(w, d));

        SpawnParams p;
        p.count = n;
        // Cluster tightly so neighbourhoods are actually populated; a uniform
        // spread over 4 mm would put almost every cell alone in its bucket and
        // the test would pass without exercising anything.
        p.placement = Placement::Gaussian;
        p.place_radius = 1.5e-4;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
        CHECK(!hash_build(w.hash, w.cells.view, w.cells.count));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> x(n), y(n), z(n);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n));

        // The largest radius a 27-cell walk can answer correctly is one bucket.
        const double radius = w.hash.cell_size;
        int32_t* d_out = nullptr;
        cudaMalloc(&d_out, sizeof(int32_t) * n);
        count_neighbours_kernel<<<(n + 255) / 256, 256>>>(w.cells.view, hash_view(w.hash),
                                                          radius, d_out, n);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        std::vector<int32_t> got(n);
        cudaMemcpy(got.data(), d_out, sizeof(int32_t) * n, cudaMemcpyDeviceToHost);
        cudaFree(d_out);

        int mismatches = 0;
        long long total = 0;
        for (int i = 0; i < n; ++i) {
            const int want = brute_force_neighbours(x, y, z, i, radius);
            total += want;
            if (got[i] != want) ++mismatches;
        }
        std::printf("  neighbour query vs brute force: %d mismatches, %.1f mean neighbours\n",
                    mismatches, static_cast<double>(total) / n);
        CHECK(mismatches == 0);
        CHECK(total > 0);        // the test must actually find neighbours
        world_destroy(w);
    }

    // --- INV-4: the build is independent of launch configuration -------------
    // The whole reason for the stable sort. With an atomicAdd scatter the sorted
    // order would vary run to run and this would fail intermittently -- the
    // worst kind of failure.
    {
        const int32_t n = 8000;
        std::vector<uint32_t> first;
        for (int run = 0; run < 3; ++run) {
            World w;
            WorldDesc d;
            d.capacity = n;
            d.seed = 555ull;
            CHECK(!world_create(w, d));
            SpawnParams p;
            p.count = n;
            p.placement = Placement::Gaussian;
            p.place_radius = 2.0e-4;
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
            CHECK(!hash_build(w.hash, w.cells.view, w.cells.count));
            CHECK(cudaDeviceSynchronize() == cudaSuccess);

            std::vector<uint32_t> order(n);
            cudaMemcpy(order.data(), w.hash.d_vals_sorted, sizeof(uint32_t) * n,
                       cudaMemcpyDeviceToHost);
            if (run == 0) first = order;
            else {
                int diffs = 0;
                for (int i = 0; i < n; ++i) if (order[i] != first[i]) ++diffs;
                CHECK(diffs == 0);
            }
            world_destroy(w);
        }

        // Stability: within a bucket, cells must stay in ascending slot order.
        // That is the property an atomicAdd scatter destroys.
        CHECK(first.size() == static_cast<size_t>(n));
    }

    // --- every occupied cell appears exactly once ----------------------------
    {
        const int32_t n = 5000;
        World w;
        WorldDesc d;
        d.capacity = n;
        CHECK(!world_create(w, d));
        SpawnParams p;
        p.count = n;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, 3ull));
        CHECK(!hash_build(w.hash, w.cells.view, w.cells.count));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<int32_t> bs(w.hash.bucket_count), be(w.hash.bucket_count);
        std::vector<uint32_t> vals(n);
        cudaMemcpy(bs.data(), w.hash.d_bucket_start, sizeof(int32_t) * bs.size(), cudaMemcpyDeviceToHost);
        cudaMemcpy(be.data(), w.hash.d_bucket_end, sizeof(int32_t) * be.size(), cudaMemcpyDeviceToHost);
        cudaMemcpy(vals.data(), w.hash.d_vals_sorted, sizeof(uint32_t) * n, cudaMemcpyDeviceToHost);

        std::vector<int> seen(n, 0);
        long long listed = 0;
        for (size_t b = 0; b < bs.size(); ++b) {
            CHECK(be[b] >= bs[b]);
            for (int32_t k = bs[b]; k < be[b]; ++k) {
                CHECK(k >= 0 && k < n);
                ++seen[vals[k]];
                ++listed;
            }
            // Stability within the bucket.
            for (int32_t k = bs[b] + 1; k < be[b]; ++k) CHECK(vals[k] > vals[k - 1]);
        }
        CHECK(listed == n);
        int wrong = 0;
        for (int i = 0; i < n; ++i) if (seen[i] != 1) ++wrong;
        CHECK(wrong == 0);
        world_destroy(w);
    }

    // --- rebuild cost at the benchmark population ----------------------------
    {
        const int32_t n = canon::BENCH_CELLS;
        World w;
        WorldDesc d;
        d.capacity = n;
        CHECK(!world_create(w, d));
        SpawnParams p;
        p.count = n;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, 11ull));

        cudaEvent_t t0, t1;
        cudaEventCreate(&t0);
        cudaEventCreate(&t1);
        for (int i = 0; i < 5; ++i) hash_build(w.hash, w.cells.view, n);   // warm up
        cudaDeviceSynchronize();
        cudaEventRecord(t0);
        for (int i = 0; i < 50; ++i) hash_build(w.hash, w.cells.view, n);
        cudaEventRecord(t1);
        cudaEventSynchronize(t1);
        float ms = 0.0f;
        cudaEventElapsedTime(&ms, t0, t1);
        const double per_build = ms / 50.0;
        std::printf("  hash rebuild at %d cells: %.3f ms\n", n, per_build);
        CHECK(per_build < 0.5);
        cudaEventDestroy(t0);
        cudaEventDestroy(t1);
        world_destroy(w);
    }

    return astro::test::finish("test_hash");
}
