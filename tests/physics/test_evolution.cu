// tests/physics/test_evolution.cu -- M10b gate. docs/PHYSICS.md Sec 11, ADR-030.
//
// The evolution half of predation: N2 lethality, heritable tolerance, and the emergent
// Taumoeba-82.5 arc by DIRECTIONAL SELECTION -- never a script. It extends T30's
// determinism argument to a dividing-and-dying-and-compacting store, drives a rising N2
// ramp until a tolerant strain appears, and proves the rise is selection (not mutation
// drift) with a constant-N2 control that plateaus far below the target.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "fields/grid.cuh"
#include "sim/predation.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

// --- Scenario knobs (a breeding experiment, not physics -- tuned, not canon) --------
constexpr double CHAMBER_SIDE   = 1.0e-3;   // 1 mm: dense prey without a huge cell count
constexpr int32_t PREY_TARGET   = 24000;    // topped up each round; prey supply self-limits the pop
constexpr int32_t TAU_START     = 1024;
constexpr int32_t TAU_CAP       = 8192;     // hard cap; prey limits the pop well below it
constexpr double BIOLOGY_RATE   = 5.0e5;    // digestion/division/death cycle in ~2 ticks
constexpr int TICKS_PER_ROUND   = 50;       // >~ one feeding generation, so the pop turns over
constexpr int ROUNDS            = 55;
constexpr double N_LETHAL       = canon::TAU_N2_LETHAL_CONC;
constexpr double RAMP_SLOPE     = 0.02;     // frontier tol* = N/N_lethal - 1 rises per round
// The ramp holds once the frontier clears the target: pushing N past 2*N_lethal would
// kill even a fully tolerant (tol=1) strain, so it plateaus at a level the bred strain
// survives -- the experiment ends when the target is bred, it does not run to extinction.
constexpr double RAMP_CAP       = 0.87;
constexpr double CONTROL_N2     = 1.05 * N_LETHAL;  // constant, survivable: frontier fixed at 0.05
constexpr double TARGET_TOL     = 0.825;    // Taumoeba-82.5
constexpr int MAX_GENERATIONS   = 40;

Error spawn_prey(World& w, int32_t count, uint64_t seed) {
    if (count <= 0) return ok();
    SpawnParams p;
    p.count = count;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 0.03;                      // near neutral buoyancy: prey stay in the field
    p.awake = false;                        // inert powder -- static food, never divides
    return cell_store_spawn(w.cells, p, w.chamber, seed);
}

Error make_world(World& w, uint64_t seed) {
    WorldDesc d;
    d.chamber = Chamber{CHAMBER_SIDE, CHAMBER_SIDE, canon::CHAMBER_D};
    d.capacity = 1 << 16;
    d.tau_capacity = TAU_CAP;
    d.seed = seed;
    d.co2_init = 0.0;                       // no CO2 -> prey never divide; isolate predation
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    d.motion.thermal_enabled = false;       // prey are inert; skip the heat deposit
    d.motion.compaction_enabled = true;     // reclaim engulfed-prey corpses
    d.motion.tau_compaction_enabled = true; // reclaim dead predators -> the pop turns over
    ASTRO_TRY(world_create(w, d));
    w.biology_rate = BIOLOGY_RATE;
    ASTRO_TRY(spawn_prey(w, PREY_TARGET, seed));
    return taumoeba_spawn(w.taumoeba, TAU_START, w.chamber, seed);
}

// Uniform N2 across the chamber. Neumann BCs + no N2 source keep a uniform fill uniform
// under diffusion, so this is a clean, controllable environmental concentration.
Error set_n2(World& w, double conc) { return fields::grid_fill(w.fields.n2, static_cast<float>(conc)); }

Error top_up_prey(World& w, uint64_t seed) {
    // With cell compaction on, count == live, so the deficit is exactly what was eaten.
    return spawn_prey(w, PREY_TARGET - w.cells.count, seed);
}

struct Sample { double mean_tol; double max_tol; uint32_t gen_at_max; int32_t n_alive; };

Sample measure(World& w) {
    const int32_t n = w.taumoeba.count;
    std::vector<float> tol(n);
    std::vector<uint32_t> gen(n), flags(n);
    taumoeba_download_tolerance(w.taumoeba, tol.data(), n);
    taumoeba_download_generation(w.taumoeba, gen.data(), n);
    taumoeba_download_flags(w.taumoeba, flags.data(), n);
    double sum = 0.0, mx = 0.0;
    int32_t alive = 0;
    uint32_t mxgen = 0;
    for (int32_t i = 0; i < n; ++i) {
        if (!(flags[i] & contract::CELL_FLAG_OCCUPIED) ||
            !(flags[i] & contract::CELL_FLAG_ALIVE)) continue;
        ++alive;
        sum += static_cast<double>(tol[i]);
        if (static_cast<double>(tol[i]) > mx) { mx = tol[i]; mxgen = gen[i]; }
    }
    Sample s;
    s.mean_tol = alive > 0 ? sum / alive : 0.0;
    s.max_tol = mx;
    s.gen_at_max = mxgen;
    s.n_alive = alive;
    return s;
}

// Full-state hash: the cells AND the evolving predators, tolerance and lineage included.
uint64_t hash_world(World& w) {
    const int32_t nc = w.cells.count, nt = w.taumoeba.count;
    std::vector<double> cx(nc), cy(nc), cz(nc), tx(nt), ty(nt), tz(nt), tb(nt);
    std::vector<float> ttol(nt);
    std::vector<uint32_t> cf(nc), tg(nt), tf(nt);
    cell_store_download_positions(w.cells, cx.data(), cy.data(), cz.data(), nc);
    cudaMemcpy(cf.data(), w.cells.view.flags, sizeof(uint32_t) * nc, cudaMemcpyDeviceToHost);
    taumoeba_download_positions(w.taumoeba, tx.data(), ty.data(), tz.data(), nt);
    taumoeba_download_biomass(w.taumoeba, tb.data(), nt);
    taumoeba_download_tolerance(w.taumoeba, ttol.data(), nt);
    taumoeba_download_generation(w.taumoeba, tg.data(), nt);
    taumoeba_download_flags(w.taumoeba, tf.data(), nt);
    uint64_t h = contract::fnv1a64(&nc, sizeof(nc));
    h = contract::fnv1a64(&nt, sizeof(nt), h);
    h = contract::fnv1a64(cx.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(cy.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(cz.data(), sizeof(double) * nc, h);
    h = contract::fnv1a64(cf.data(), sizeof(uint32_t) * nc, h);
    h = contract::fnv1a64(tx.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(ty.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(tz.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(tb.data(), sizeof(double) * nt, h);
    h = contract::fnv1a64(ttol.data(), sizeof(float) * nt, h);
    h = contract::fnv1a64(tg.data(), sizeof(uint32_t) * nt, h);
    h = contract::fnv1a64(tf.data(), sizeof(uint32_t) * nt, h);
    return h;
}

// Run `rounds` of the breeding loop. n2_of(round) supplies the environment; the caller
// gets the per-round mean/max tolerance curve back. `verbose` prints it.
void breed(World& w, int rounds, double (*n2_of)(int), uint64_t seed_base,
           std::vector<Sample>& out, bool verbose) {
    for (int r = 0; r < rounds; ++r) {
        set_n2(w, n2_of(r));
        top_up_prey(w, seed_base + static_cast<uint64_t>(r) + 1ull);
        for (int t = 0; t < TICKS_PER_ROUND; ++t) world_step(w);
        cudaDeviceSynchronize();
        const Sample s = measure(w);
        out.push_back(s);
        if (verbose)
            std::printf("   r%02d  N/Nl %5.3f  alive %5d  mean %.4f  max %.4f (gen %u)\n",
                        r, n2_of(r) / N_LETHAL, s.n_alive, s.mean_tol, s.max_tol, s.gen_at_max);
    }
}

double ramp_n2(int round) {
    const double frontier = RAMP_SLOPE * static_cast<double>(round);
    return N_LETHAL * (1.0 + (frontier < RAMP_CAP ? frontier : RAMP_CAP));
}
double const_n2(int) { return CONTROL_N2; }

} // namespace

int main() {
    // --- pure helpers (no GPU needed) ---------------------------------------
    {
        // Hazard is zero at/below the tolerance-scaled threshold and rises above it.
        CHECK(tau_n2_hazard(0.5 * N_LETHAL, 0.0) == 0.0);
        CHECK(tau_n2_hazard(2.0 * N_LETHAL, 0.0) > 0.0);
        // A more tolerant Taumoeba has a strictly lower hazard at the same concentration.
        CHECK(tau_n2_hazard(2.0 * N_LETHAL, 0.9) < tau_n2_hazard(2.0 * N_LETHAL, 0.1));
        // At tolerance 1 and k=1 the lethal threshold doubles: 2*N_lethal is the edge.
        CHECK(tau_n2_hazard(2.0 * N_LETHAL, 1.0) == 0.0);
        // Death probability is a probability, monotone in hazard.
        CHECK(tau_n2_death_prob(0.0, 1.0) == 0.0);
        const double p = tau_n2_death_prob(N_LETHAL, 100.0);
        CHECK(p > 0.0 && p < 1.0);
        CHECK(tau_n2_death_prob(2.0 * N_LETHAL, 100.0) > p);
        // Division threshold and the clamped, heritable mutation.
        CHECK(!tau_ready_to_divide(canon::TAU_MASS_DRY));
        CHECK(tau_ready_to_divide(2.0 * canon::TAU_MASS_DRY));
        CHECK(tau_daughter_tolerance(0.0f, -10.0) == 0.0f);   // clamps at 0
        CHECK(tau_daughter_tolerance(1.0f, 10.0) == 1.0f);    // clamps at 1
        CHECK(tau_daughter_tolerance(0.5f, 0.0) == 0.5f);     // no mutation -> inherit
    }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_evolution: no CUDA device; ran the pure checks only\n");
        return astro::test::finish("test_evolution");
    }

    // --- T31 (GATE): the dividing/dying/compacting store is bit-reproducible --
    {
        const int rounds = 12;
        uint64_t h[2] = {0, 0};
        for (int pass = 0; pass < 2; ++pass) {
            World w{};
            CHECK(!make_world(w, 20260802ull));
            std::vector<Sample> curve;
            breed(w, rounds, ramp_n2, 20260802ull, curve, false);
            h[pass] = hash_world(w);
            world_destroy(w);
        }
        std::printf("  T31: evolution hash %016llx vs %016llx\n",
                    static_cast<unsigned long long>(h[0]),
                    static_cast<unsigned long long>(h[1]));
        CHECK(h[0] == h[1]);

        World w2{};
        CHECK(!make_world(w2, 13579ull));
        std::vector<Sample> curve2;
        breed(w2, rounds, ramp_n2, 13579ull, curve2, false);
        CHECK(hash_world(w2) != h[0]);
        world_destroy(w2);
    }

    // --- T32 (GATE): directional selection -> Taumoeba-82.5 within 40 generations
    std::vector<Sample> arc;
    {
        std::printf("  T32: rising N2 ramp --\n");
        World w{};
        CHECK(!make_world(w, 20260802ull));
        breed(w, ROUNDS, ramp_n2, 20260802ull, arc, true);
        world_destroy(w);

        // The population survived the ramp (evolutionary rescue, not extinction).
        int survived = 1;
        for (const Sample& s : arc) if (s.n_alive <= 0) survived = 0;
        CHECK(survived == 1);

        // A strain reached the target, and its lineage depth is within the budget.
        int reached_round = -1;
        uint32_t reached_gen = 0;
        for (int i = 0; i < static_cast<int>(arc.size()); ++i) {
            if (arc[i].max_tol >= TARGET_TOL) { reached_round = i; reached_gen = arc[i].gen_at_max; break; }
        }
        std::printf("  T32: Taumoeba-82.5 at round %d, lineage generation %u\n",
                    reached_round, reached_gen);
        CHECK(reached_round >= 0);
        CHECK(reached_gen <= static_cast<uint32_t>(MAX_GENERATIONS));

        // The mean tolerance rises monotonically on a 5-round moving average (the trend
        // is directional, not drift). A small epsilon absorbs per-round stochasticity.
        std::vector<double> ma;
        for (int i = 4; i < static_cast<int>(arc.size()); ++i) {
            double a = 0.0;
            for (int k = i - 4; k <= i; ++k) a += arc[k].mean_tol;
            ma.push_back(a / 5.0);
        }
        int monotone = 1;
        for (int i = 1; i < static_cast<int>(ma.size()); ++i)
            if (ma[i] < ma[i - 1] - 1.0e-3) monotone = 0;
        CHECK(monotone == 1);
        CHECK(ma.back() - ma.front() > 0.3);              // and it rose substantially

        // world_stats' mean tolerance must agree with the host reduction (task: stats).
        World wv{};
        CHECK(!make_world(wv, 20260802ull));
        set_n2(wv, ramp_n2(0));
        for (int t = 0; t < TICKS_PER_ROUND; ++t) world_step(wv);
        cudaDeviceSynchronize();
        const contract::Stats st = world_stats(wv);
        const Sample sm = measure(wv);
        CHECK(st.n_taumoeba == sm.n_alive);
        CHECK_CLOSE(st.mean_tau_tolerance, sm.mean_tol, 1.0e-4);
        world_destroy(wv);
    }

    // --- T33 (GATE): control -- a CONSTANT nitrogen level does not reach the target.
    // Same death/division machinery; only the rising ramp is removed. Tolerance rises to
    // clear the fixed frontier, then plateaus far below Taumoeba-82.5. This is what makes
    // the T32 rise directional selection rather than mutation drift (meta-lesson 4).
    {
        std::printf("  T33: constant N2 control --\n");
        World w{};
        CHECK(!make_world(w, 20260802ull));
        std::vector<Sample> ctrl;
        breed(w, ROUNDS, const_n2, 20260802ull, ctrl, true);
        world_destroy(w);
        double ctrl_max = 0.0;
        for (const Sample& s : ctrl) if (s.max_tol > ctrl_max) ctrl_max = s.max_tol;
        std::printf("  T33: control max tolerance %.4f (target %.3f)\n", ctrl_max, TARGET_TOL);
        CHECK(ctrl_max < TARGET_TOL);
    }

    return astro::test::finish("test_evolution");
}
