// tests/physics/test_predation.cu -- T30. docs/PHYSICS.md Sec 11, ADR-014 (M10a).
//
// The second organism store, so the T22 argument runs again: a run with predators
// crawling, engulfing, and digesting must be bit-reproducible. Plus the physical
// claim -- a predator introduction reduces the live cell count -- and containment.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "sim/predation.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

Error make_world(World& w, int32_t n_cells, int32_t n_tau, double biology_rate,
                 uint64_t seed = 20260802ull) {
    WorldDesc d;
    d.capacity = 1 << 19;
    d.tau_capacity = 4096;
    d.seed = seed;
    d.co2_init = 0.0;                     // no CO2 -> no growth: isolate predation
    d.motion.emission_enabled = false;    // no light source, so this only costs time
    d.motion.taxis_enabled = false;
    ASTRO_TRY(world_create(w, d));
    w.biology_rate = biology_rate;
    SpawnParams p;
    p.count = n_cells;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 0.03;                    // near neutral buoyancy: prey stay in the field
    p.awake = false;
    ASTRO_TRY(cell_store_spawn(w.cells, p, w.chamber, seed));
    return taumoeba_spawn(w.taumoeba, n_tau, w.chamber, seed);
}

// Full state hash: the predators AND the cells they hunt.
uint64_t hash_world(World& w) {
    const int32_t nc = w.cells.count;
    const int32_t nt = w.taumoeba.count;
    std::vector<double> cx(nc), cy(nc), cz(nc), ce(nc), tx(nt), ty(nt), tz(nt), tb(nt);
    std::vector<uint32_t> cf(nc);
    cell_store_download_positions(w.cells, cx.data(), cy.data(), cz.data(), nc);
    cell_store_download_energy(w.cells, ce.data(), nc);
    cudaMemcpy(cf.data(), w.cells.view.flags, sizeof(uint32_t) * nc, cudaMemcpyDeviceToHost);
    taumoeba_download_positions(w.taumoeba, tx.data(), ty.data(), tz.data(), nt);
    taumoeba_download_biomass(w.taumoeba, tb.data(), nt);
    uint64_t h = contract::fnv1a64(&nc, sizeof(nc));
    h = contract::fnv1a64(&nt, sizeof(nt), h);
    h = contract::fnv1a64(cx.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(cy.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(cz.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(ce.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(cf.data(), sizeof(uint32_t) * nc, h);
    h = contract::fnv1a64(tx.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(ty.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(tz.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(tb.data(), sizeof(double) * nt, h);
    return h;
}

bool all_contained(World& w) {
    const int32_t n = w.taumoeba.count;
    std::vector<double> x(n), y(n), z(n);
    taumoeba_download_positions(w.taumoeba, x.data(), y.data(), z.data(), n);
    const double a = canon::TAU_RADIUS;
    const double hx = 0.5 * w.chamber.w + a, hy = 0.5 * w.chamber.h + a, hz = 0.5 * w.chamber.d + a;
    for (int32_t i = 0; i < n; ++i)
        if (std::fabs(x[i]) > hx || std::fabs(y[i]) > hy || std::fabs(z[i]) > hz) return false;
    return true;
}

} // namespace

int main() {
    // --- T30.1 (pure): the predator's physics helpers ------------------------
    {
        CHECK(tau_drag(canon::AMBIENT_TEMP_DEFAULT) > 0.0);
        // The crawl thrust yields the canon crawl speed as a terminal velocity.
        CHECK_CLOSE(canon::TAU_CRAWL_THRUST / tau_drag(canon::AMBIENT_TEMP_DEFAULT),
                    canon::TAU_CRAWL_SPEED, 1e-6);
        // Overlap: touching bodies engulf, distant ones do not.
        CHECK(tau_overlaps_cell(Vec3{0, 0, 0}, Vec3{canon::TAU_RADIUS, 0, 0}));
        CHECK(!tau_overlaps_cell(Vec3{0, 0, 0},
                                 Vec3{2.0 * (canon::TAU_RADIUS + canon::CELL_RADIUS), 0, 0}));
        // Tumble rule: a rising prey signal keeps the run, a falling one tumbles.
        float ema_up = 0.0f, ema_dn = 10.0f;
        CHECK(!tau_should_tumble(5.0f, ema_up, 0.0f, canon::DT_PHYSICS));   // signal > ema: run
        CHECK(tau_should_tumble(5.0f, ema_dn, 0.0f, canon::DT_PHYSICS));    // signal < ema: tumble
    }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_predation: no CUDA device; ran the pure checks only\n");
        return astro::test::finish("test_predation");
    }

    // --- T30.2 (GATE): a predation run is bit-reproducible -------------------
    {
        const int ticks = 2000;
        const double rate = 1.0e5;        // fast digestion, so predators cycle quickly
        uint64_t h[2] = {0, 0};
        for (int pass = 0; pass < 2; ++pass) {
            World w{};
            CHECK(!make_world(w, 6000, 150, rate));
            for (int t = 0; t < ticks; ++t) world_step(w);
            cudaDeviceSynchronize();
            h[pass] = hash_world(w);
            world_destroy(w);
        }
        std::printf("  T30.2: predation hash %016llx vs %016llx\n",
                    static_cast<unsigned long long>(h[0]),
                    static_cast<unsigned long long>(h[1]));
        CHECK(h[0] == h[1]);

        // A different seed diverges, or "deterministic" is vacuous.
        World w2{};
        CHECK(!make_world(w2, 6000, 150, rate, 13579ull));
        for (int t = 0; t < 2000; ++t) world_step(w2);
        cudaDeviceSynchronize();
        CHECK(hash_world(w2) != h[0]);
        world_destroy(w2);
    }

    // --- T30.3 (GATE): predators reduce the live cell count, and stay inside --
    {
        const double rate = 1.0e5;
        World w{};
        CHECK(!make_world(w, 6000, 150, rate));
        const int32_t n0 = w.cells.count;
        const contract::Stats s0 = world_stats(w);
        for (int t = 0; t < 4000; ++t) world_step(w);
        cudaDeviceSynchronize();
        const contract::Stats s1 = world_stats(w);
        std::printf("  T30.3: live %d -> %d, dead %d, predators %d, contained %d\n",
                    s0.n_live, s1.n_live, s1.n_dead, w.taumoeba.count, all_contained(w) ? 1 : 0);
        CHECK(s0.n_live == n0);           // nothing died before the predators worked
        CHECK(s1.n_live < s0.n_live);     // the culture was thinned
        CHECK(s1.n_dead > 0);             // by engulfment (no other death path is on)
        CHECK(all_contained(w));          // containment is an invariant (ARCHITECTURE Sec 4)
        world_destroy(w);
    }

    return astro::test::finish("test_predation");
}
