// tests/physics/test_lifecycle.cu -- T18 and T22. docs/PHYSICS.md Sec 10, ADR-025.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "fields/grid.cuh"
#include "golden/expected_values.h"
#include "sim/lifecycle.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;
namespace ex = astro::expected;

namespace {

Error make_world(World& w, int32_t n, double co2_init, double biology_rate,
                 uint64_t seed = 20260802ull) {
    WorldDesc d;
    d.capacity = 1 << 20;                 // room to grow; allocation is append-only
    d.seed = seed;
    d.co2_init = co2_init;
    d.motion.contact_enabled = false;     // isolating growth from mechanics
    d.motion.adhesion_enabled = false;
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    ASTRO_TRY(world_create(w, d));
    w.biology_rate = biology_rate;
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 0.5;
    p.awake = false;                      // dormant: no thermostat spend, no taxis
    return cell_store_spawn(w.cells, p, w.chamber, seed);
}

double co2_min(const World& w) {
    const auto& g = w.fields.co2;
    std::vector<float> v(static_cast<size_t>(g.n) * g.n);
    fields::grid_download(g, v.data());
    double lo = 1e30;
    for (float f : v) if (f < lo) lo = f;
    return lo;
}

double co2_total(const World& w) {
    const auto& g = w.fields.co2;
    std::vector<float> v(static_cast<size_t>(g.n) * g.n);
    fields::grid_download(g, v.data());
    double s = 0.0;
    for (float f : v) s += f;
    return s * static_cast<double>(g.dx) * g.dx * w.chamber.d;
}

// Full state hash including id, flags and COUNT -- the fixed-population hash in
// tools/headless.cpp cannot see a division that produces the right positions in
// the wrong slots, or the right slots with the wrong ids.
uint64_t hash_population(const World& w) {
    const int32_t n = w.cells.count;
    std::vector<double> x(n), y(n), z(n), e(n);
    std::vector<uint64_t> id(n);
    std::vector<uint32_t> fl(n);
    cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
    cell_store_download_energy(w.cells, e.data(), n);
    cudaMemcpy(id.data(), w.cells.view.id, sizeof(uint64_t) * n, cudaMemcpyDeviceToHost);
    cudaMemcpy(fl.data(), w.cells.view.flags, sizeof(uint32_t) * n, cudaMemcpyDeviceToHost);
    uint64_t h = contract::fnv1a64(&n, sizeof(n));
    h = contract::fnv1a64(x.data(), sizeof(double) * n, h);
    h = contract::fnv1a64(y.data(), sizeof(double) * n, h);
    h = contract::fnv1a64(z.data(), sizeof(double) * n, h);
    h = contract::fnv1a64(e.data(), sizeof(double) * n, h);
    h = contract::fnv1a64(id.data(), sizeof(uint64_t) * n, h);
    h = contract::fnv1a64(fl.data(), sizeof(uint32_t) * n, h);
    return h;
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_lifecycle: no CUDA device; skipping\n");
        return 0;
    }

    // --- T18.1: the uptake rate reproduces the canon doubling time ------------
    {
        CHECK_CLOSE(canon::LIFE_CO2_UPTAKE_MAX, ex::T18_UPTAKE_MAX, ex::T18_UPTAKE_MAX_TOL);
        // Saturating: plentiful CO2 gives the full rate, none gives none.
        CHECK(co2_uptake_rate(0.0) == 0.0);
        CHECK_CLOSE(co2_uptake_rate(1000.0 * canon::LIFE_CO2_HALF_SATURATION),
                    canon::LIFE_CO2_UPTAKE_MAX, 2e-3);
        CHECK_CLOSE(co2_uptake_rate(canon::LIFE_CO2_HALF_SATURATION),
                    0.5 * canon::LIFE_CO2_UPTAKE_MAX, 1e-12);
        // Monotone in concentration -- a cell must never feed better on less.
        double prev = -1.0;
        for (int i = 0; i <= 100; ++i) {
            const double v = co2_uptake_rate(i * 0.01 * canon::CO2_SAT_CONC_1ATM);
            CHECK(v >= prev);
            prev = v;
        }
        // Energy is SPLIT, never duplicated.
        CHECK_CLOSE(daughter_energy(canon::CELL_ENERGY_MAX),
                    0.5 * canon::CELL_ENERGY_MAX, 1e-12);
        CHECK(daughter_energy(0.0) == 0.0);
    }

    // --- T18.2 (GATE): population doubles in LIFE_DOUBLING_TIME ---------------
    {
        // Saturating CO2, so uptake runs at LIFE_CO2_UPTAKE_MAX throughout and the
        // doubling time is the canon value by construction. biology_rate compresses
        // 8 days into a testable number of ticks (ADR-011) -- at 1x this would take
        // 6.9e8 ticks.
        const double rate = 2.0e7;
        World w{};
        CHECK(!make_world(w, 4000, canon::CO2_SAT_CONC_1ATM, rate));
        const int32_t n0 = w.cells.count;

        // One doubling of BIOLOGY time.
        const double bio_per_tick = canon::DT_PHYSICS * rate;
        const int ticks = static_cast<int>(canon::LIFE_DOUBLING_TIME / bio_per_tick + 0.5);
        for (int t = 0; t < ticks; ++t) world_step(w);
        cudaDeviceSynchronize();

        const double ratio = static_cast<double>(w.cells.count) / n0;
        const double sim_bio_s = ticks * bio_per_tick;
        std::printf("  T18: %d -> %d in %.0f biology-seconds (%.3f doublings; "
                    "canon doubling %.0f s)\n",
                    n0, w.cells.count, sim_bio_s, ratio, canon::LIFE_DOUBLING_TIME);
        CHECK_CLOSE(ratio, 2.0, ex::T18_DOUBLING_TIME_TOL);
        world_destroy(w);
    }

    // --- T18.3 (GATE): growth halts when the CO2 runs out --------------------
    {
        // Measured against a CONTROL rather than against a guessed threshold: the
        // same population and duration on saturating CO2 versus a limited medium.
        // Picking an absolute growth bound would just be inventing a cutoff, and
        // Michaelis-Menten means a limited medium can never be fully stripped --
        // uptake tends to zero as it empties, which is the point.
        // Measured against a saturating CONTROL, not against a guessed population.
        //
        // The statistic is deliberately a comparison and not "growth proceeds then
        // stops", because that shape is not constructible at a high biology_rate:
        // uptake is scaled by biology_rate while the CO2 field diffuses on PHYSICS
        // time, so a cell strips its own grid cell and then waits on resupply. The
        // control slows for the same reason once it is dense. See Q19 -- it is a
        // real coupling in ADR-011's multi-rate clock, not a defect in this test.
        const double rate = 2.0e7;
        const int32_t n0 = 2000;
        const double bio_per_tick = canon::DT_PHYSICS * rate;
        const int ticks = static_cast<int>(2.0 * canon::LIFE_DOUBLING_TIME / bio_per_tick + 0.5);
        const double vol = canon::CHAMBER_W * canon::CHAMBER_H * canon::CHAMBER_D;

        int32_t end[2];
        double co2_0 = 0.0, co2_1 = 0.0, lo = 0.0;
        for (int arm = 0; arm < 2; ++arm) {
            const bool limited = (arm == 1);
            World w{};
            // A poor medium: 1.5 divisions' worth per starting cell, spread through
            // the chamber -- below the half-saturation constant, so uptake is
            // throttled from the outset and the budget runs out almost at once.
            const double conc = limited ? (1.5 * n0 * canon::CO2_MASS_PER_DIVISION / vol)
                                        : canon::CO2_SAT_CONC_1ATM;
            CHECK(!make_world(w, n0, conc, rate));
            if (limited) co2_0 = co2_total(w);
            for (int t = 0; t < ticks; ++t) world_step(w);
            cudaDeviceSynchronize();
            end[arm] = w.cells.count;
            if (limited) { co2_1 = co2_total(w); lo = co2_min(w); }
            world_destroy(w);
        }

        std::printf("  T18.3: control %d -> %d, CO2-limited %d -> %d over 2 doubling "
                    "times; CO2 %.1f%% consumed, min %.3e kg/m^3\n",
                    n0, end[0], n0, end[1], 100.0 * (1.0 - co2_1 / co2_0), lo);

        // The control grows; the limited arm is stopped by the medium.
        CHECK(end[0] > n0);
        CHECK(static_cast<double>(end[1] - n0) < 0.25 * (end[0] - n0));
        CHECK(co2_1 < co2_0);
        // THE MINIMUM, not the total. Asserting only the total is what let an
        // over-subscribed grid cell reach -0.128 kg/m^3 while this test passed:
        // negative pockets were masked by positive ones elsewhere (ADR-025).
        CHECK(lo >= 0.0);
    }

    // --- T22 (GATE): a run in which cells divide is bit-reproducible ----------
    {
        // THE test ADR-014 exists for. Every earlier determinism result holds a
        // FIXED population, so nothing until now has exercised the case per-cell
        // streams were introduced to survive: daughters appearing mid-run must not
        // shift anybody else's draws, and slot assignment must not depend on the
        // order blocks happen to retire.
        const double rate = 2.0e7;
        const int ticks = 4000;
        uint64_t h[2] = {0, 0};
        int32_t counts[2] = {0, 0};
        for (int pass = 0; pass < 2; ++pass) {
            World w{};
            CHECK(!make_world(w, 2000, canon::CO2_SAT_CONC_1ATM, rate));
            for (int t = 0; t < ticks; ++t) world_step(w);
            cudaDeviceSynchronize();
            counts[pass] = w.cells.count;
            h[pass] = hash_population(w);
            world_destroy(w);
        }
        std::printf("  T22: %d cells, hash %016llx vs %016llx\n", counts[0],
                    static_cast<unsigned long long>(h[0]),
                    static_cast<unsigned long long>(h[1]));
        CHECK(counts[0] > 2000);            // divisions actually happened
        CHECK(counts[0] == counts[1]);
        CHECK(h[0] == h[1]);

        // ... and the seed must still matter, or "deterministic" is vacuous.
        World w2{};
        CHECK(!make_world(w2, 2000, canon::CO2_SAT_CONC_1ATM, rate, 987654321ull));
        for (int t = 0; t < ticks; ++t) world_step(w2);
        cudaDeviceSynchronize();
        const uint64_t h3 = hash_population(w2);
        CHECK(h3 != h[0]);
        world_destroy(w2);
    }

    // --- T22b (GATE): compaction is bit-reproducible (ADR-028) ----------------
    {
        // T22 re-run with slots reclaimed. Absorbing walls cull cells into corpses
        // while saturating CO2 makes them divide, so the store grows AND shrinks and
        // compaction runs on nearly every tick. Contact is ON on purpose: compaction
        // reorders the SoA, which reorders contact-force summation -- ADR-018's exact
        // hazard, and the whole reason compaction was kept out of M9a/M9b. Two runs
        // must still hash identically, and the count must reflect reclamation.
        const double rate = 2.0e7;
        const int ticks = 2500;
        uint64_t h[2] = {0, 0};
        int32_t counts[2] = {0, 0};
        int64_t deaths[2] = {0, 0};
        for (int pass = 0; pass < 2; ++pass) {
            World w{};
            WorldDesc d;
            d.capacity = 1 << 20;
            d.seed = 20260802ull;
            d.co2_init = canon::CO2_SAT_CONC_1ATM;
            d.motion.emission_enabled = false;
            d.motion.taxis_enabled = false;
            d.motion.boundary_x = Boundary::Absorbing;
            d.motion.boundary_y = Boundary::Absorbing;
            d.motion.compaction_enabled = true;   // contact stays ON (default)
            CHECK(!world_create(w, d));
            w.biology_rate = rate;
            SpawnParams p;
            p.count = 3000;
            p.placement = Placement::Uniform;
            p.charge_dist = Distribution::Constant;
            p.charge_a = 0.5;                      // sinks toward the -y wall and dies
            p.awake = false;
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
            for (int t = 0; t < ticks; ++t) world_step(w);
            cudaDeviceSynchronize();
            counts[pass] = w.cells.count;
            deaths[pass] = w.deaths_total;
            h[pass] = hash_population(w);
            world_destroy(w);
        }
        std::printf("  T22b: compacted count %d, deaths %lld, hash %016llx vs %016llx\n",
                    counts[0], static_cast<long long>(deaths[0]),
                    static_cast<unsigned long long>(h[0]),
                    static_cast<unsigned long long>(h[1]));
        CHECK(deaths[0] > 0);                 // cells died and their slots were reclaimed
        CHECK(deaths[0] == deaths[1]);        // the death count is itself reproducible
        CHECK(counts[0] != 3000);             // the population changed (grew and/or shrank)
        CHECK(counts[0] == counts[1]);
        CHECK(h[0] == h[1]);                  // bit-reproducible through compaction + contact
    }

    // --- T22.2: daughter streams are keyed on id, not on birth order ----------
    {
        // pcg_split must depend on (parent state, daughter id) alone. If it ever
        // picked up a slot index or a counter, two daughters of different parents
        // that happened to be born in the same tick would correlate.
        const uint64_t pa = 0x123456789ABCDEFull, pb = 0xFEDCBA987654321ull;
        CHECK(daughter_rng_state(pa, 7) == daughter_rng_state(pa, 7));
        CHECK(daughter_rng_state(pa, 7) != daughter_rng_state(pa, 8));
        CHECK(daughter_rng_state(pa, 7) != daughter_rng_state(pb, 7));
        // The division axis is likewise a pure function of the daughter id, so it
        // consumes no draw from either cell's stream -- consuming one would make a
        // parent's later trajectory depend on whether it happened to divide.
        double ax, ay, az, bx, by, bz;
        division_axis(11, ax, ay, az);
        division_axis(11, bx, by, bz);
        CHECK(ax == bx && ay == by && az == bz);
        CHECK_CLOSE(std::sqrt(ax * ax + ay * ay + az * az), 1.0, 1e-9);
        division_axis(12, bx, by, bz);
        CHECK(!(ax == bx && ay == by && az == bz));
    }

    return astro::test::finish("test_lifecycle");
}
