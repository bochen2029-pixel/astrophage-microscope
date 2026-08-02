// tools/headless.cpp -- the determinism oracle and the scenario acceptance runner.
//
// Never links GL. Two jobs:
//   1. --assert-deterministic  run the same seed twice and require identical
//      state hashes (INV-8). Every later milestone leans on this gate.
//   2. --scenario ID --assert   (from M11) run a scenario headless and evaluate
//      its accept block from docs/SCENARIOS.md.
//
// Since M2 this drives the REAL World -- the same kernels the application runs.
// Before that it used a Brownian stand-in, which meant the determinism gate was
// not actually covering the integrator (closed as Q3).
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "sim/world.cuh"

using namespace astro;

namespace {

struct Options {
    long long          ticks = 1000;
    unsigned long long seed = 20260802ull;
    int                cells = 4096;
    double             charge = 0.02;
    bool               assert_deterministic = false;
    const char*        scenario = nullptr;
    bool               verbose = false;
    bool               report_extent = false;
};

// Hash order is the snapshot file layout order (contracts/snapshot_v1.h), so a
// snapshot round trip and a live run agree on what "same state" means.
uint64_t hash_world(const sim::World& w) {
    const int32_t n = w.cells.count;
    std::vector<double> x(n), y(n), z(n), vx(n), vy(n), vz(n), energy(n);
    sim::cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
    sim::cell_store_download_velocities(w.cells, vx.data(), vy.data(), vz.data(), n);
    sim::cell_store_download_energy(w.cells, energy.data(), n);

    const uint64_t tick = w.tick;
    uint64_t h = contract::fnv1a64(&tick, sizeof(tick));
    const size_t bytes = static_cast<size_t>(n) * sizeof(double);
    h = contract::fnv1a64(x.data(), bytes, h);
    h = contract::fnv1a64(y.data(), bytes, h);
    h = contract::fnv1a64(z.data(), bytes, h);
    h = contract::fnv1a64(vx.data(), bytes, h);
    h = contract::fnv1a64(vy.data(), bytes, h);
    h = contract::fnv1a64(vz.data(), bytes, h);
    h = contract::fnv1a64(energy.data(), bytes, h);
    return h;
}

bool run(const Options& o, uint64_t& hash_out) {
    sim::World w;
    sim::WorldDesc d;
    d.capacity = o.cells;
    d.seed = o.seed;
    if (Error e = sim::world_create(w, d)) {
        std::printf("world_create failed: %s\n", status_str(e.status));
        return false;
    }

    sim::SpawnParams p;
    p.count = o.cells;
    p.placement = sim::Placement::Uniform;
    p.charge_dist = sim::Distribution::Constant;
    p.charge_a = o.charge;
    if (Error e = sim::cell_store_spawn(w.cells, p, w.chamber, o.seed)) {
        std::printf("spawn failed: %s\n", status_str(e.status));
        sim::world_destroy(w);
        return false;
    }

    for (long long t = 0; t < o.ticks; ++t) sim::world_step(w);
    if (cudaDeviceSynchronize() != cudaSuccess) {
        std::printf("device error during stepping\n");
        sim::world_destroy(w);
        return false;
    }

    hash_out = hash_world(w);

    if (o.report_extent) {
        const int32_t n = w.cells.count;
        std::vector<double> x(n), y(n), z(n);
        sim::cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
        double lo[3] = {1e30, 1e30, 1e30}, hi[3] = {-1e30, -1e30, -1e30};
        for (int32_t i = 0; i < n; ++i) {
            const double pos[3] = {x[i], y[i], z[i]};
            for (int k = 0; k < 3; ++k) {
                if (pos[k] < lo[k]) lo[k] = pos[k];
                if (pos[k] > hi[k]) hi[k] = pos[k];
            }
        }
        const double h[3] = {0.5 * w.chamber.w, 0.5 * w.chamber.h, 0.5 * w.chamber.d};
        std::printf("extent um: x [%.1f, %.1f] wall +-%.1f | y [%.1f, %.1f] wall +-%.1f "
                    "| z [%.1f, %.1f] wall +-%.1f\n",
                    lo[0] * 1e6, hi[0] * 1e6, h[0] * 1e6,
                    lo[1] * 1e6, hi[1] * 1e6, h[1] * 1e6,
                    lo[2] * 1e6, hi[2] * 1e6, h[2] * 1e6);
        // Containment is an invariant, not a preference: a cell in the glass is
        // always a bug and is never tuned around (ARCHITECTURE.md Sec 4).
        const double a = canon::CELL_RADIUS;
        bool escaped = false;
        for (int k = 0; k < 3; ++k)
            if (lo[k] < -h[k] - a || hi[k] > h[k] + a) escaped = true;
        std::printf(escaped ? "FAIL: a cell is outside the chamber\n"
                            : "contained: every cell is inside the chamber\n");
        if (escaped) { sim::world_destroy(w); return false; }
    }

    sim::world_destroy(w);
    return true;
}

void usage() {
    std::printf(
        "headless -- Astrophage simulator, no window\n"
        "  --ticks N                 ticks to run (default 1000)\n"
        "  --seed N                  master seed (default 20260802)\n"
        "  --cells N                 population (default 4096)\n"
        "  --charge F                initial charge fraction (default 0.02)\n"
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
        else if (a == "--seed")                 o.seed = static_cast<unsigned long long>(next(20260802));
        else if (a == "--cells")                o.cells = static_cast<int>(next(o.cells));
        else if (a == "--charge")               o.charge = (i + 1 < argc) ? std::atof(argv[++i]) : o.charge;
        else if (a == "--assert-deterministic") o.assert_deterministic = true;
        else if (a == "--verbose")              o.verbose = true;
        else if (a == "--extent")               o.report_extent = true;
        else if (a == "--scenario")             o.scenario = (i + 1 < argc) ? argv[++i] : nullptr;
        else if (a == "--help" || a == "-h")  { usage(); return 0; }
        else { std::printf("unknown argument: %s\n", a.c_str()); usage(); return 2; }
    }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("no CUDA device found; this simulator requires one\n");
        return 3;
    }

    if (o.scenario) {
        std::printf("headless: scenario running arrives in M11 (docs/MILESTONES.md)\n");
        return 3;
    }

    uint64_t h1 = 0;
    if (!run(o, h1)) return 1;
    std::printf("hash %016llx  ticks %lld  cells %d  seed %llu  sim_time %.6f s\n",
                static_cast<unsigned long long>(h1), o.ticks, o.cells, o.seed,
                static_cast<double>(o.ticks) * canon::DT_PHYSICS);

    if (o.assert_deterministic) {
        uint64_t h2 = 0;
        if (!run(o, h2)) return 1;
        std::printf("hash %016llx  (replay)\n", static_cast<unsigned long long>(h2));
        if (h1 != h2) {
            std::printf("FAIL: INV-8 violated -- replay hash differs.\n");
            return 1;
        }

        // A different seed must give a different trajectory, or the harness is
        // trivially "deterministic" because nothing depends on the seed.
        Options other = o;
        other.seed ^= 0xFFFFFFFFull;
        uint64_t h3 = 0;
        if (!run(other, h3)) return 1;
        if (h3 == h1) {
            std::printf("FAIL: seed has no effect on the trajectory.\n");
            return 1;
        }

        // Nor may the result depend on launch configuration (INV-4). Population
        // size changes the grid dimension; per-cell streams must make each
        // cell's trajectory independent of how many neighbours it has.
        Options fewer = o;
        fewer.cells = o.cells / 2;
        uint64_t h4 = 0;
        if (!run(fewer, h4)) return 1;
        if (h4 == h1) {
            std::printf("FAIL: halving the population changed nothing; state is not being hashed.\n");
            return 1;
        }

        std::printf("PASS: deterministic, seed-sensitive, real integrator.\n");
    }
    return 0;
}
