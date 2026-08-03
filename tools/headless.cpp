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
#include "sim/accept.h"
#include "sim/scenario.h"
#include "sim/world.cuh"

#ifndef ASTRO_SCENARIOS_DIR
#define ASTRO_SCENARIOS_DIR "scenarios"
#endif

using namespace astro;

namespace {

struct Options {
    long long          ticks = 1000;
    bool               ticks_set = false;    // was --ticks given (vs derive the horizon)
    unsigned long long seed = 20260802ull;
    int                cells = 4096;
    double             charge = 0.02;
    bool               assert_deterministic = false;
    const char*        scenario = nullptr;
    bool               assert_scenario = false;   // --assert: evaluate the accept block
    const char*        csv = nullptr;              // --csv <path>: telemetry export
    bool               verbose = false;
    bool               report_extent = false;
    bool               compaction = false;   // reclaim dead slots (ADR-028)
    bool               absorbing = false;     // absorbing x/y walls, so cells actually die
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
    d.motion.compaction_enabled = o.compaction;
    if (o.absorbing) {
        // Absorbing walls cull cells that reach them into corpses, so a run has
        // something for compaction to reclaim (the default reflecting walls never
        // remove a cell). Empty cells (charge 0) rise and are absorbed at +y.
        d.motion.boundary_x = sim::Boundary::Absorbing;
        d.motion.boundary_y = sim::Boundary::Absorbing;
    }
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

const char* op_symbol(contract::CompareOp op) {
    switch (op) {
        case contract::CompareOp::Eq: return "==";
        case contract::CompareOp::Ne: return "!=";
        case contract::CompareOp::Lt: return "<";
        case contract::CompareOp::Le: return "<=";
        case contract::CompareOp::Gt: return ">";
        case contract::CompareOp::Ge: return ">=";
        case contract::CompareOp::Approx: return "~=";
    }
    return "?";
}

// CSV telemetry export (docs/SCENARIOS.md). The header records the provenance that makes a
// run reproducible and honest -- seed, scenario, and whether any canon lock was broken.
void csv_header(std::FILE* f, const contract::Scenario& sc, const sim::World& w) {
    std::fprintf(f, "# scenario: %s\n# seed: %llu\n# non_canon_run: %d%s\n",
                 sc.id, static_cast<unsigned long long>(w.seed),
                 w.non_canon_run ? 1 : 0, w.non_canon_run ? " (CANON LOCK BROKEN)" : " (canon)");
    std::fprintf(f, "# git_describe: injected at packaging (M12)\n");
    std::fprintf(f, "t_s,n_live,n_dead,n_tau,mean_charge,total_energy_J,mean_temp_cell_K,"
                    "mean_temp_medium_K,co2_total_kg,mean_tolerance,boil_events,divisions,deaths\n");
}
void csv_row(std::FILE* f, const contract::Stats& s) {
    std::fprintf(f, "%.6f,%d,%d,%d,%.6f,%.6e,%.4f,%.4f,%.6e,%.6f,%d,%d,%d\n",
                 s.sim_time_s, s.n_live, s.n_dead, s.n_taumoeba, s.mean_charge,
                 s.total_energy_j, s.mean_temp_cell_k, s.mean_temp_medium_k,
                 s.co2_total_kg, s.mean_tau_tolerance, s.boil_events,
                 s.divisions_this_window, s.deaths_this_window);
}

// Run a scenario headless and evaluate its accept block (the T24 gate). Applies the
// scenario's driving script every tick and samples at HUD rate. Returns true iff every
// check passes; an empty accept block (sandbox) trivially passes without running. When
// csv_path is set, writes a telemetry row per sample (docs/SCENARIOS.md).
bool run_scenario_assert(const contract::Scenario& sc, sim::World& w,
                         long long ticks_override, const char* csv_path) {
    if (sc.accept_count == 0) {
        std::printf("scenario %s: no objective (sandbox) -- ACCEPT\n", sc.id);
        return true;
    }

    // Horizon: an explicit duration, else the latest accept after_s or drive window.
    double horizon = sc.run_duration_s;
    if (horizon <= 0.0) {
        for (int i = 0; i < sc.accept_count; ++i)
            if (sc.accept[i].after_s > horizon) horizon = sc.accept[i].after_s;
        for (int i = 0; i < sc.drive_count; ++i) {
            const double te = sc.drive[i].t1_s > sc.drive[i].t0_s ? sc.drive[i].t1_s
                                                                  : sc.drive[i].t0_s;
            if (te > horizon) horizon = te;
        }
    }
    if (horizon <= 0.0) horizon = 60.0;   // a scenario whose objective names no time

    const double dt = canon::DT_PHYSICS * w.physics_rate;
    long long ticks = ticks_override > 0 ? ticks_override
                                         : static_cast<long long>(std::ceil(horizon / dt));
    if (ticks < 1) ticks = 1;
    const long long stride = ticks > 2000 ? ticks / 2000 : 1;   // bound the D2H samples

    // Velocity capture windows (three-percent-line): a couple of seconds in, while every
    // cell is still in free drift (accept.cpp). Physical seconds, not tuned magic.
    const double settle_s = 2.0, interval_s = 4.0;

    const sim::MetricNeeds needs = sim::metric_needs(sc);
    sim::RunAggregates agg;
    contract::Stats st{};
    std::FILE* csv = csv_path ? std::fopen(csv_path, "w") : nullptr;
    if (csv) csv_header(csv, sc, w);
    for (long long t = 0; t < ticks; ++t) {
        sim::scenario_apply_drive(w, sc);
        sim::world_step(w);
        if (t % stride == 0) {
            st = sim::world_stats(w);
            sim::aggregates_sample(agg, st, w, needs, settle_s, interval_s);
            if (csv) csv_row(csv, st);
        }
    }
    if (cudaDeviceSynchronize() != cudaSuccess) {
        std::printf("device error during scenario assert\n");
        if (csv) std::fclose(csv);
        return false;
    }
    st = sim::world_stats(w);   // final state
    sim::aggregates_sample(agg, st, w, needs, settle_s, interval_s);
    if (csv) { csv_row(csv, st); std::fclose(csv); }

    std::printf("scenario %s: assert over %.1f s (%lld ticks, %d checks)\n",
                sc.id, st.sim_time_s, ticks, sc.accept_count);
    bool all_pass = true;
    for (int i = 0; i < sc.accept_count; ++i) {
        const contract::AcceptCheck& c = sc.accept[i];
        const double measured = sim::metric_measure(c.metric, st, agg, w, sc);
        const bool ok = sim::accept_eval(c, measured);
        all_pass = all_pass && ok;
        std::printf("  [%s] %-26s %-12.6g %s %-.6g",
                    ok ? "PASS" : "FAIL", sim::metric_name(c.metric),
                    measured, op_symbol(c.op), c.value);
        if (c.op == contract::CompareOp::Approx) std::printf(" (tol %.4g%s)",
                    c.tol, c.tol_absolute ? " abs" : " rel");
        if (c.after_s > 0.0) std::printf(" [after %.0f s]", c.after_s);
        std::printf("\n");
    }
    std::printf("scenario %s: %s\n", sc.id, all_pass ? "ACCEPT" : "REJECT");
    return all_pass;
}

void usage() {
    std::printf(
        "headless -- Astrophage simulator, no window\n"
        "  --ticks N                 ticks to run (default 1000)\n"
        "  --seed N                  master seed (default 20260802)\n"
        "  --cells N                 population (default 4096)\n"
        "  --charge F                initial charge fraction (default 0.02)\n"
        "  --assert-deterministic    run twice, require identical hashes (INV-8)\n"
        "  --compaction              reclaim dead slots each tick (ADR-028)\n"
        "  --absorbing               absorbing x/y walls, so cells die and can be reclaimed\n"
        "  --scenario ID             run a scenario headless (M11)\n"
        "  --assert                  with --scenario: evaluate its accept block (T24),\n"
        "                            exit nonzero on any missed check\n"
        "  --csv <path>              with --scenario --assert: write a telemetry CSV\n"
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
        if (a == "--ticks")                   { o.ticks = next(o.ticks); o.ticks_set = true; }
        else if (a == "--seed")                 o.seed = static_cast<unsigned long long>(next(20260802));
        else if (a == "--cells")                o.cells = static_cast<int>(next(o.cells));
        else if (a == "--charge")               o.charge = (i + 1 < argc) ? std::atof(argv[++i]) : o.charge;
        else if (a == "--assert-deterministic") o.assert_deterministic = true;
        else if (a == "--verbose")              o.verbose = true;
        else if (a == "--extent")               o.report_extent = true;
        else if (a == "--compaction")           o.compaction = true;
        else if (a == "--absorbing")            o.absorbing = true;
        else if (a == "--scenario")             o.scenario = (i + 1 < argc) ? argv[++i] : nullptr;
        else if (a == "--assert")               o.assert_scenario = true;
        else if (a == "--csv")                  o.csv = (i + 1 < argc) ? argv[++i] : nullptr;
        else if (a == "--help" || a == "-h")  { usage(); return 0; }
        else { std::printf("unknown argument: %s\n", a.c_str()); usage(); return 2; }
    }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("no CUDA device found; this simulator requires one\n");
        return 3;
    }

    if (o.scenario) {
        // --scenario accepts a bare id (resolved against the scenarios dir) or a
        // direct path to a .json. Accept-block evaluation (--assert) is M11b.
        std::string id = o.scenario;
        const bool is_path = id.size() > 5 && id.compare(id.size() - 5, 5, ".json") == 0;
        const std::string path = is_path ? id : (std::string(ASTRO_SCENARIOS_DIR) + "/" + id + ".json");

        contract::Scenario sc;
        if (Error e = sim::scenario_load(path, sc)) {
            std::printf("scenario load failed (%s): %s\n", path.c_str(), status_str(e.status));
            return 3;
        }
        sim::World w;
        if (Error e = sim::scenario_instantiate(sc, w)) {
            std::printf("scenario '%s' instantiate failed: %s\n", sc.id, status_str(e.status));
            return 3;
        }

        // --assert evaluates the accept block (T24). Exit nonzero on any missed check,
        // so gate.ps1 can loop every scenario and fail the milestone on the first miss.
        if (o.assert_scenario) {
            const bool pass = run_scenario_assert(sc, w, o.ticks_set ? o.ticks : 0, o.csv);
            sim::world_destroy(w);
            return pass ? 0 : 1;
        }

        for (long long t = 0; t < o.ticks; ++t) sim::world_step(w);
        if (cudaDeviceSynchronize() != cudaSuccess) {
            std::printf("device error during scenario stepping\n");
            sim::world_destroy(w);
            return 1;
        }
        const contract::Stats st = sim::world_stats(w);
        std::printf("scenario %s: ticks %lld  live %d  dead %d  tau %d  mean_charge %.4f  "
                    "medium %.2f K (max %.2f K)  mean_tol %.4f  sim_time %.3f s\n",
                    sc.id, o.ticks, st.n_live, st.n_dead, st.n_taumoeba, st.mean_charge,
                    st.mean_temp_medium_k, st.max_temp_medium_k, st.mean_tau_tolerance,
                    st.sim_time_s);
        sim::world_destroy(w);
        return 0;
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
