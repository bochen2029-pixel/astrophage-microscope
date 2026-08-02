// tests/physics/test_rng.cpp -- INV-1 / ADR-014.
//
// The RNG is load-bearing for determinism, so it is tested against the
// published PCG32 reference vectors rather than against itself.
#include <cmath>
#include <cstdint>
#include <vector>

#include "core/rng.cuh"
#include "test_util.h"

using namespace astro;

int main() {
    // --- reference vectors ---------------------------------------------------
    // pcg32_srandom_r(&rng, 42, 54) then six draws, from the PCG reference demo.
    {
        Pcg32 r = pcg32_seed(42u, 54u);
        const uint32_t want[6] = {0xa15c02b7u, 0x7b47f409u, 0xba1d3330u,
                                  0x83d2f293u, 0xbfa4784bu, 0xcbed606eu};
        for (int i = 0; i < 6; ++i) CHECK_EQ_U64(pcg32_next(r), want[i]);
    }

    // --- stream independence (the whole point of ADR-014) --------------------
    // Two cells with adjacent ids must not produce correlated sequences, and a
    // cell's sequence must not depend on how many other cells exist.
    {
        const uint64_t seed = 20260802ull;
        Pcg32 a = cell_rng(cell_rng_init(seed, 1000), 1000);
        Pcg32 b = cell_rng(cell_rng_init(seed, 1001), 1001);
        int collisions = 0;
        for (int i = 0; i < 4096; ++i) {
            if (pcg32_next(a) == pcg32_next(b)) ++collisions;
        }
        CHECK(collisions <= 2);   // expected ~0; 2^-32 per draw

        // Reconstructing a cell's stream from its stored state + id must be exact.
        const uint64_t s0 = cell_rng_init(seed, 777);
        Pcg32 c1 = cell_rng(s0, 777);
        for (int i = 0; i < 100; ++i) pcg32_next(c1);
        Pcg32 c2 = cell_rng(c1.state, 777);          // as if reloaded from the store
        Pcg32 c3 = cell_rng(s0, 777);
        for (int i = 0; i < 100; ++i) pcg32_next(c3);
        CHECK_EQ_U64(pcg32_next(c2), pcg32_next(c3));
    }

    // --- division splitting --------------------------------------------------
    // A daughter must diverge from her mother, and the split must depend only on
    // (parent_state, daughter_id) -- never on birth order or thread index.
    {
        const uint64_t parent = cell_rng_init(1234ull, 9ull);
        const uint64_t d1 = pcg_split(parent, 100ull);
        const uint64_t d2 = pcg_split(parent, 101ull);
        CHECK(d1 != parent);
        CHECK(d1 != d2);
        CHECK_EQ_U64(pcg_split(parent, 100ull), d1);   // reproducible
    }

    // --- uniform01 range and mean --------------------------------------------
    {
        Pcg32 r = pcg32_seed(7u, 11u);
        double sum = 0.0;
        double lo = 2.0, hi = -1.0;
        const int n = 1000000;
        for (int i = 0; i < n; ++i) {
            const double u = uniform01d(r);
            CHECK(u >= 0.0 && u < 1.0);
            sum += u;
            if (u < lo) lo = u;
            if (u > hi) hi = u;
        }
        CHECK_CLOSE(sum / n, 0.5, 3e-3);
        CHECK(lo < 1e-4);
        CHECK(hi > 1.0 - 1e-4);
    }

    // --- gaussian moments ----------------------------------------------------
    // The OU integrator's noise amplitude is only correct if these are.
    {
        Pcg32 r = pcg32_seed(99u, 3u);
        const int n = 1000000;
        double s1 = 0.0, s2 = 0.0, s4 = 0.0;
        for (int i = 0; i < n; ++i) {
            const double z = gaussian(r);
            s1 += z;
            s2 += z * z;
            s4 += z * z * z * z;
        }
        const double mean = s1 / n;
        const double var  = s2 / n - mean * mean;
        const double kurt = (s4 / n) / (var * var);
        CHECK_CLOSE(mean, 0.0, 5e-3);
        CHECK_CLOSE(var, 1.0, 1e-2);
        CHECK_CLOSE(kurt, 3.0, 3e-2);      // catches a truncated or clipped tail
    }

    // gaussian3 must give three usable, uncorrelated variates.
    {
        Pcg32 r = pcg32_seed(5u, 5u);
        const int n = 200000;
        double sx = 0, sy = 0, sz = 0, vxx = 0, vyy = 0, vzz = 0, cxy = 0;
        for (int i = 0; i < n; ++i) {
            double x, y, z;
            gaussian3(r, x, y, z);
            sx += x; sy += y; sz += z;
            vxx += x * x; vyy += y * y; vzz += z * z;
            cxy += x * y;
        }
        CHECK_CLOSE(sx / n, 0.0, 1e-2);
        CHECK_CLOSE(sy / n, 0.0, 1e-2);
        CHECK_CLOSE(sz / n, 0.0, 1e-2);
        CHECK_CLOSE(vxx / n, 1.0, 2e-2);
        CHECK_CLOSE(vyy / n, 1.0, 2e-2);
        CHECK_CLOSE(vzz / n, 1.0, 2e-2);
        CHECK(std::fabs(cxy / n) < 1e-2);
    }

    return astro::test::finish("test_rng");
}
