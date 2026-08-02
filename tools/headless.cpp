// tools/headless.cpp -- the determinism oracle and the scenario acceptance runner.
//
// Never links GL. Two jobs:
//   1. --assert-deterministic  run the same seed twice and require identical
//      state hashes (INV-8). This is the gate that every later milestone leans on.
//   2. --scenario X --assert    (from M11) run a scenario headless and evaluate
//      its accept block from docs/SCENARIOS.md.
//
// At M0 the "world" is a stand-in: per-cell PCG32 streams advancing a tiny state
// vector. That is deliberate -- it exercises the real RNG, the real hash, and
// the real replay harness, so M1 only has to swap in the real store.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "core/rng.cuh"
#include "core/units.h"

using namespace astro;

namespace {

struct Options {
    long long   ticks  = 1000;
    unsigned long long seed = 20260802ull;
    int         cells  = 4096;
    bool        assert_deterministic = false;
    const char* scenario = nullptr;
    bool        verbose = false;
};

// M0 stand-in for the world. Replaced by CellStore in M1; the hash contract and
// the replay loop below survive that change unaltered.
struct StubWorld {
    std::vector<double>   x, y, z;
    std::vector<uint64_t> id, rng_state;
    unsigned long long    tick = 0;

    void init(int n, unsigned long long seed) {
        x.resize(n); y.resize(n); z.resize(n); id.resize(n); rng_state.resize(n);
        for (int i = 0; i < n; ++i) {
            id[i] = static_cast<uint64_t>(i) + 1;
            rng_state[i] = cell_rng_init(seed, id[i]);
            Pcg32 r = cell_rng(rng_state[i], id[i]);
            x[i] = uniform_range(r, -canon::CHAMBER_W * 0.5, canon::CHAMBER_W * 0.5);
            y[i] = uniform_range(r, -canon::CHAMBER_H * 0.5, canon::CHAMBER_H * 0.5);
            z[i] = uniform_range(r, -canon::CHAMBER_D * 0.5, canon::CHAMBER_D * 0.5);
            rng_state[i] = r.state;
        }
    }

    // A Brownian stand-in with the real diffusivity, so the numbers are at least
    // physically plausible while the actual integrator is still unwritten.
    void step() {
        const double sigma = std::sqrt(2.0 * canon::DIFFUSIVITY_20C * canon::DT_PHYSICS);
        for (size_t i = 0; i < x.size(); ++i) {
            Pcg32 r = cell_rng(rng_state[i], id[i]);
            double gx, gy, gz;
            gaussian3(r, gx, gy, gz);
            x[i] += sigma * gx;
            y[i] += sigma * gy;
            z[i] += sigma * gz;
            rng_state[i] = r.state;
        }
        ++tick;
    }

    // Hash order is the snapshot file layout order (contracts/snapshot_v1.h).
    uint64_t hash() const {
        uint64_t h = contract::fnv1a64(&tick, sizeof(tick));
        h = contract::fnv1a64(x.data(), x.size() * sizeof(double), h);
        h = contract::fnv1a64(y.data(), y.size() * sizeof(double), h);
        h = contract::fnv1a64(z.data(), z.size() * sizeof(double), h);
        h = contract::fnv1a64(rng_state.data(), rng_state.size() * sizeof(uint64_t), h);
        return h;
    }
};

uint64_t run(const Options& o) {
    StubWorld w;
    w.init(o.cells, o.seed);
    for (long long t = 0; t < o.ticks; ++t) w.step();
    return w.hash();
}

void usage() {
    std::printf(
        "headless -- Astrophage simulator, no window\n"
        "  --ticks N                 ticks to run (default 1000)\n"
        "  --seed N                  master seed (default 20260802)\n"
        "  --cells N                 stand-in population (default 4096)\n"
        "  --assert-deterministic    run twice, require identical hashes (INV-8)\n"
        "  --scenario ID             run a scenario headless (M11)\n"
        "  --verbose\n");
}

} // namespace

int main(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&](long long dflt) -> long long {
            return (i + 1 < argc) ? std::atoll(argv[++i]) : dflt;
        };
        if (a == "--ticks")                     o.ticks = next(o.ticks);
        else if (a == "--seed")                 o.seed  = static_cast<unsigned long long>(next(20260802));
        else if (a == "--cells")                o.cells = static_cast<int>(next(o.cells));
        else if (a == "--assert-deterministic") o.assert_deterministic = true;
        else if (a == "--verbose")              o.verbose = true;
        else if (a == "--scenario")             o.scenario = (i + 1 < argc) ? argv[++i] : nullptr;
        else if (a == "--help" || a == "-h")  { usage(); return 0; }
        else { std::printf("unknown argument: %s\n", a.c_str()); usage(); return 2; }
    }

    if (o.scenario) {
        std::printf("headless: scenario running arrives in M11 (docs/MILESTONES.md)\n");
        return 3;
    }

    const uint64_t h1 = run(o);
    std::printf("hash %016llx  ticks %lld  cells %d  seed %llu  sim_time %.6f s\n",
                static_cast<unsigned long long>(h1), o.ticks, o.cells, o.seed,
                static_cast<double>(o.ticks) * canon::DT_PHYSICS);

    if (o.assert_deterministic) {
        const uint64_t h2 = run(o);
        std::printf("hash %016llx  (replay)\n", static_cast<unsigned long long>(h2));
        if (h1 != h2) {
            std::printf("FAIL: INV-8 violated -- replay hash differs.\n");
            return 1;
        }
        // A different seed must give a different trajectory, or the harness is
        // trivially "deterministic" because nothing depends on the seed.
        Options other = o;
        other.seed ^= 0xFFFFFFFFull;
        if (run(other) == h1) {
            std::printf("FAIL: seed has no effect on the trajectory.\n");
            return 1;
        }
        std::printf("PASS: deterministic, and seed-sensitive.\n");
    }
    return 0;
}
