// tests/physics/test_cell_store.cu -- allocation, spawning, and INV-1/INV-4.
//
// The store is the substrate every later milestone builds on, so the properties
// pinned here are the ones whose violation would be hardest to notice later:
// that a cell's random stream depends only on its id, and that spawning is
// independent of launch configuration and of population size.
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/cell_store.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

Chamber chamber() {
    return Chamber{canon::CHAMBER_W, canon::CHAMBER_H, canon::CHAMBER_D};
}

std::vector<double> positions_x(const CellStore& s) {
    std::vector<double> x(static_cast<size_t>(s.count));
    std::vector<double> y(x.size()), z(x.size());
    cell_store_download_positions(s, x.data(), y.data(), z.data(),
                                  static_cast<int32_t>(x.size()));
    return x;
}

void download_xyz(const CellStore& s, std::vector<double>& x, std::vector<double>& y,
                  std::vector<double>& z) {
    x.resize(static_cast<size_t>(s.count));
    y.resize(x.size());
    z.resize(x.size());
    cell_store_download_positions(s, x.data(), y.data(), z.data(),
                                  static_cast<int32_t>(x.size()));
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_cell_store: no CUDA device; skipping\n");
        return 0;
    }

    // --- lifetime ------------------------------------------------------------
    {
        CellStore s;
        CHECK(!cell_store_create(s, 1000));
        CHECK(s.capacity == 1000);
        CHECK(s.count == 0);
        CHECK(s.blob != nullptr);
        cell_store_destroy(s);
        CHECK(s.blob == nullptr);

        CHECK(static_cast<bool>(cell_store_create(s, 0)));                    // rejected
        CHECK(static_cast<bool>(cell_store_create(s, canon::MAX_CELLS + 1))); // rejected
    }

    // --- spawn stays inside the chamber --------------------------------------
    {
        CellStore s;
        CHECK(!cell_store_create(s, 20000));
        SpawnParams p;
        p.count = 20000;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Uniform;
        p.charge_a = 0.0; p.charge_b = 1.0;
        CHECK(!cell_store_spawn(s, p, chamber(), 12345ull));
        CHECK(s.count == 20000);

        std::vector<double> x, y, z;
        download_xyz(s, x, y, z);
        const double a = canon::CELL_RADIUS;
        int outside = 0;
        for (size_t i = 0; i < x.size(); ++i) {
            if (x[i] < -0.5 * canon::CHAMBER_W - a || x[i] > 0.5 * canon::CHAMBER_W + a) ++outside;
            if (y[i] < -0.5 * canon::CHAMBER_H - a || y[i] > 0.5 * canon::CHAMBER_H + a) ++outside;
            if (z[i] < -0.5 * canon::CHAMBER_D - a || z[i] > 0.5 * canon::CHAMBER_D + a) ++outside;
        }
        CHECK(outside == 0);

        // Uniform placement must actually fill the chamber, not clump at centre.
        double mean = 0.0, var = 0.0;
        for (double v : x) mean += v;
        mean /= static_cast<double>(x.size());
        for (double v : x) var += (v - mean) * (v - mean);
        var /= static_cast<double>(x.size());
        const double expect_var = canon::CHAMBER_W * canon::CHAMBER_W / 12.0;
        CHECK_CLOSE(var, expect_var, 5e-2);
        CHECK(std::fabs(mean) < canon::CHAMBER_W * 0.02);
        cell_store_destroy(s);
    }

    // --- INV-1: a cell's stream depends only on (seed, id) --------------------
    // Spawning 5000 cells and spawning 1000 then 4000 must give identical
    // positions. With a global RNG this fails, which is the entire reason for
    // per-cell streams (ADR-014).
    {
        CellStore one, split;
        CHECK(!cell_store_create(one, 5000));
        CHECK(!cell_store_create(split, 5000));

        SpawnParams p;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Constant;
        p.charge_a = 0.25;

        p.count = 5000;
        CHECK(!cell_store_spawn(one, p, chamber(), 777ull));

        p.count = 1000;
        CHECK(!cell_store_spawn(split, p, chamber(), 777ull));
        p.count = 4000;
        CHECK(!cell_store_spawn(split, p, chamber(), 777ull));

        CHECK(one.count == split.count);
        std::vector<double> ax, ay, az, bx, by, bz;
        download_xyz(one, ax, ay, az);
        download_xyz(split, bx, by, bz);
        int mismatches = 0;
        for (size_t i = 0; i < ax.size(); ++i) {
            if (ax[i] != bx[i] || ay[i] != by[i] || az[i] != bz[i]) ++mismatches;
        }
        CHECK(mismatches == 0);
        cell_store_destroy(one);
        cell_store_destroy(split);
    }

    // --- seed sensitivity ----------------------------------------------------
    // Without this, "deterministic" could mean "ignores the seed".
    {
        CellStore a, b;
        CHECK(!cell_store_create(a, 2000));
        CHECK(!cell_store_create(b, 2000));
        SpawnParams p;
        p.count = 2000;
        CHECK(!cell_store_spawn(a, p, chamber(), 1ull));
        CHECK(!cell_store_spawn(b, p, chamber(), 2ull));
        const std::vector<double> xa = positions_x(a);
        const std::vector<double> xb = positions_x(b);
        int same = 0;
        for (size_t i = 0; i < xa.size(); ++i) if (xa[i] == xb[i]) ++same;
        CHECK(same < 10);
        cell_store_destroy(a);
        cell_store_destroy(b);
    }

    // --- capacity is enforced ------------------------------------------------
    {
        CellStore s;
        CHECK(!cell_store_create(s, 100));
        SpawnParams p;
        p.count = 101;
        CHECK(static_cast<bool>(cell_store_spawn(s, p, chamber(), 1ull)));
        CHECK(s.count == 0);        // a rejected spawn must not partially commit
        cell_store_destroy(s);
    }

    // --- ids are unique and monotonic ---------------------------------------
    {
        CellStore s;
        CHECK(!cell_store_create(s, 4096));
        SpawnParams p;
        p.count = 2048;
        CHECK(!cell_store_spawn(s, p, chamber(), 5ull));
        CHECK(!cell_store_spawn(s, p, chamber(), 5ull));
        std::vector<uint64_t> ids(static_cast<size_t>(s.count));
        cudaMemcpy(ids.data(), s.view.id, ids.size() * sizeof(uint64_t), cudaMemcpyDeviceToHost);
        bool monotonic = true;
        for (size_t i = 0; i < ids.size(); ++i) {
            if (ids[i] != static_cast<uint64_t>(i) + 1) monotonic = false;
        }
        CHECK(monotonic);
        CHECK(s.next_id == 4097ull);   // 0 is reserved as "no cell"
        cell_store_destroy(s);
    }

    return astro::test::finish("test_cell_store");
}
