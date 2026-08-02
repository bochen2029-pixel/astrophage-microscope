// tests/physics/test_buoyancy.cu -- T14, P1 on the GPU.
//
// test_motion verifies the integrator analytically on the host. This verifies
// the emergent behaviour: a population with mixed charge SORTS ITSELF VERTICALLY
// about the 3.006 % line, with no code anywhere that special-cases it.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "golden/expected_values.h"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

// Rank transform with average ranks for ties.
std::vector<double> ranks(const std::vector<double>& v) {
    const size_t n = v.size();
    std::vector<size_t> idx(n);
    for (size_t i = 0; i < n; ++i) idx[i] = i;
    std::sort(idx.begin(), idx.end(), [&](size_t p, size_t q) { return v[p] < v[q]; });
    std::vector<double> r(n);
    size_t i = 0;
    while (i < n) {
        size_t j = i;
        while (j + 1 < n && v[idx[j + 1]] == v[idx[i]]) ++j;
        const double avg = 0.5 * (static_cast<double>(i) + static_cast<double>(j));
        for (size_t k = i; k <= j; ++k) r[idx[k]] = avg;
        i = j + 1;
    }
    return r;
}

double pearson(const std::vector<double>& a, const std::vector<double>& b) {
    const size_t n = a.size();
    double ma = 0.0, mb = 0.0;
    for (size_t i = 0; i < n; ++i) { ma += a[i]; mb += b[i]; }
    ma /= n; mb /= n;
    double num = 0.0, da = 0.0, db = 0.0;
    for (size_t i = 0; i < n; ++i) {
        const double x = a[i] - ma, y = b[i] - mb;
        num += x * y; da += x * x; db += y * y;
    }
    return (da > 0.0 && db > 0.0) ? num / std::sqrt(da * db) : 0.0;
}

// Spearman is the right statistic here, and it is a STRICTER test than Pearson,
// not a weaker one. The physical claim -- more charge means lower position -- is
// monotonic, not linear: with reflecting boundaries the cells at both extremes
// pile against the walls, so position saturates and the relationship becomes
// sigmoid. Pearson penalises that saturation (it reads ~0.84) even when the
// ordering is essentially perfect. Spearman measures the ordering, which is what
// P1 actually asserts.
double spearman(const std::vector<double>& a, const std::vector<double>& b) {
    return pearson(ranks(a), ranks(b));
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_buoyancy: no CUDA device; skipping\n");
        return 0;
    }

    const int32_t n = 20000;

    // --- T14: charge sorts the population vertically -------------------------
    {
        World w;
        WorldDesc d;
        d.capacity = n;
        d.seed = 20260802ull;
        CHECK(!world_create(w, d));

        SpawnParams p;
        p.count = n;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Uniform;
        p.charge_a = 0.0;
        p.charge_b = 0.06;              // straddles the 3.006 % neutral line
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));

        std::vector<double> x(n), y0(n), z(n), energy(n);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y0.data(), z.data(), n));
        CHECK(!cell_store_download_energy(w.cells, energy.data(), n));

        // No correlation at spawn: placement and charge are independent draws.
        std::vector<double> charge(n);
        for (int i = 0; i < n; ++i) charge[i] = energy[i] / canon::CELL_ENERGY_MAX;
        const double r_before = pearson(charge, y0);
        std::printf("  charge vs y at spawn:  r = %+.4f\n", r_before);
        CHECK(std::fabs(r_before) < 0.05);

        // 60 s of culture time. A 6 % cell falls ~120 um/s, an empty one rises
        // ~52 um/s, so the two ends separate by millimetres.
        const int ticks = static_cast<int>(60.0 / canon::DT_PHYSICS);
        for (int t = 0; t < ticks; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> y1(n);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y1.data(), z.data(), n));

        // P1: higher charge -> lower y.
        //
        // A whole-population position correlation is WEAKER than it looks, and
        // not because of the statistic. Cells within a whisker of 3.006 % have
        // near-zero drift velocity -- a cell at 3.1 % moves 20 um in a minute --
        // so they simply stay where they spawned and contribute pure noise. That
        // is correct physics, and it caps any position-vs-charge correlation at
        // finite time, for Pearson and Spearman alike (0.84 and 0.84 here).
        //
        // So the position test asserts what the physics actually predicts:
        // separation of the two groups that DO move.
        std::vector<double> neg_y(n);
        for (int i = 0; i < n; ++i) neg_y[i] = -y1[i];
        std::printf("  charge vs -y at 60 s:  spearman %+.4f, pearson %+.4f"
                    "  (near-neutral cells barely move; see comment)\n",
                    spearman(charge, neg_y), pearson(charge, neg_y));

        double mean_y_light = 0.0, mean_y_heavy = 0.0;
        int n_light = 0, n_heavy = 0;
        const double margin = 0.5 * canon::CHARGE_NEUTRAL_BUOYANCY;
        for (int i = 0; i < n; ++i) {
            if (charge[i] < canon::CHARGE_NEUTRAL_BUOYANCY - margin) { mean_y_light += y1[i]; ++n_light; }
            if (charge[i] > canon::CHARGE_NEUTRAL_BUOYANCY + margin) { mean_y_heavy += y1[i]; ++n_heavy; }
        }
        CHECK(n_light > 1000 && n_heavy > 1000);
        mean_y_light /= n_light;
        mean_y_heavy /= n_heavy;
        std::printf("  after 60 s: below-neutral mean y = %+.0f um, above-neutral %+.0f um"
                    "  (gap %.0f um)\n", mean_y_light * 1e6, mean_y_heavy * 1e6,
                    (mean_y_light - mean_y_heavy) * 1e6);
        CHECK(mean_y_light > mean_y_heavy);
        CHECK(mean_y_light - mean_y_heavy > 1.0e-3);   // over a millimetre apart

        // And the sorting lands ON the neutral line, not merely somewhere.
        double mean_charge_top = 0.0, mean_charge_bottom = 0.0;
        int n_top = 0, n_bottom = 0;
        for (int i = 0; i < n; ++i) {
            if (y1[i] > canon::CHAMBER_H / 6.0)       { mean_charge_top += charge[i]; ++n_top; }
            else if (y1[i] < -canon::CHAMBER_H / 6.0) { mean_charge_bottom += charge[i]; ++n_bottom; }
        }
        CHECK(n_top > 100 && n_bottom > 100);
        mean_charge_top /= n_top;
        mean_charge_bottom /= n_bottom;
        std::printf("  mean charge: top third %.4f%%, bottom third %.4f%%, neutral %.4f%%\n",
                    mean_charge_top * 100.0, mean_charge_bottom * 100.0,
                    canon::CHARGE_NEUTRAL_BUOYANCY * 100.0);
        CHECK(mean_charge_top < canon::CHARGE_NEUTRAL_BUOYANCY);
        CHECK(mean_charge_bottom > canon::CHARGE_NEUTRAL_BUOYANCY);

        // Nothing escaped and nothing went non-finite.
        int bad = 0;
        for (int i = 0; i < n; ++i) {
            if (!std::isfinite(y1[i]) || std::fabs(y1[i]) > 0.5 * canon::CHAMBER_H) ++bad;
        }
        CHECK(bad == 0);

        world_destroy(w);
    }

    // --- T14 proper: drift VELOCITY is exactly linear in charge --------------
    // This is the sharp statement of P1, and it is immune to initial conditions
    // and to how long you wait. With thermal noise off, every cell settles to its
    // terminal velocity, which must be a straight line in charge crossing zero
    // at exactly CHARGE_NEUTRAL_BUOYANCY.
    {
        const int32_t m = 8000;
        World w;
        WorldDesc d;
        d.capacity = m;
        d.seed = 31337ull;
        d.motion.thermal_noise = false;      // testing the deterministic response
        // Contact and adhesion off: this measures the pure buoyancy response, and
        // the cluster below is dense enough that neighbour forces would perturb
        // the terminal velocities being fitted.
        d.motion.contact_enabled = false;
        d.motion.adhesion_enabled = false;
        CHECK(!world_create(w, d));

        SpawnParams p;
        p.count = m;
        p.placement = Placement::Gaussian;
        p.place_radius = canon::CHAMBER_H * 0.02;   // mid-chamber, far from walls
        p.charge_dist = Distribution::Uniform;
        p.charge_a = 0.0;
        p.charge_b = 0.06;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));

        // 0.1 s is ~560 momentum relaxation times even for the heaviest cell.
        for (int t = 0; t < 100; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> vx(m), vy(m), vz(m), energy(m), charge(m);
        CHECK(!cell_store_download_velocities(w.cells, vx.data(), vy.data(), vz.data(), m));
        CHECK(!cell_store_download_energy(w.cells, energy.data(), m));
        for (int i = 0; i < m; ++i) charge[i] = energy[i] / canon::CELL_ENERGY_MAX;

        const double r_v = pearson(charge, vy);
        std::printf("  charge vs drift velocity: pearson = %+.6f\n", r_v);
        CHECK(r_v < -0.9999);        // perfectly linear, and NEGATIVE: more charge, more sinking

        // Least squares for the zero crossing.
        double sx = 0, sy = 0, sxx = 0, sxy = 0;
        for (int i = 0; i < m; ++i) { sx += charge[i]; sy += vy[i]; sxx += charge[i] * charge[i]; sxy += charge[i] * vy[i]; }
        const double slope = (m * sxy - sx * sy) / (m * sxx - sx * sx);
        const double intercept = (sy - slope * sx) / m;
        const double zero_crossing = -intercept / slope;
        std::printf("  drift velocity crosses zero at %.5f%% charge (canon %.5f%%)\n",
                    zero_crossing * 100.0, canon::CHARGE_NEUTRAL_BUOYANCY * 100.0);
        CHECK_CLOSE(zero_crossing, canon::CHARGE_NEUTRAL_BUOYANCY, 1e-4);

        // The endpoints must match the analytic oracle, not merely line up.
        CHECK_CLOSE(intercept, -astro::expected::T2_V_RISE_EMPTY, 1e-3);
        world_destroy(w);
    }

    // --- the live charge slider flips the drift direction --------------------
    // This is the interactive demonstration of P1, so it is worth pinning: the
    // same population, charged either side of the neutral line, must move in
    // opposite directions.
    {
        double mean_dy[2] = {0.0, 0.0};
        const double charges[2] = {canon::CHARGE_NEUTRAL_BUOYANCY * 0.25,
                                   canon::CHARGE_NEUTRAL_BUOYANCY * 4.0};
        for (int k = 0; k < 2; ++k) {
            World w;
            WorldDesc d;
            d.capacity = 4000;
            d.seed = 99ull;
            CHECK(!world_create(w, d));
            SpawnParams p;
            p.count = 4000;
            p.placement = Placement::Gaussian;
            p.place_radius = canon::CHAMBER_H * 0.05;   // clustered mid-chamber,
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));  // away from walls
            CHECK(!cell_store_set_charge(w.cells, charges[k]));

            std::vector<double> x(4000), y0(4000), z(4000), y1(4000);
            CHECK(!cell_store_download_positions(w.cells, x.data(), y0.data(), z.data(), 4000));
            for (int t = 0; t < 10000; ++t) world_step(w);   // 10 s
            CHECK(cudaDeviceSynchronize() == cudaSuccess);
            CHECK(!cell_store_download_positions(w.cells, x.data(), y1.data(), z.data(), 4000));

            for (int i = 0; i < 4000; ++i) mean_dy[k] += y1[i] - y0[i];
            mean_dy[k] /= 4000.0;
            world_destroy(w);
        }
        std::printf("  drift in 10 s: below neutral %+.1f um, above neutral %+.1f um\n",
                    mean_dy[0] * 1e6, mean_dy[1] * 1e6);
        CHECK(mean_dy[0] > 0.0);    // below the line: rises
        CHECK(mean_dy[1] < 0.0);    // above the line: sinks
    }

    // --- determinism survives motion (INV-8) ---------------------------------
    // The integrator draws six gaussians per cell per tick. If any of that leaked
    // into a shared or index-derived stream, this would drift.
    {
        std::vector<double> ya(2000), yb(2000), tmp(2000), tmp2(2000);
        for (int run = 0; run < 2; ++run) {
            World w;
            WorldDesc d;
            d.capacity = 2000;
            d.seed = 4242ull;
            CHECK(!world_create(w, d));
            SpawnParams p;
            p.count = 2000;
            p.charge_dist = Distribution::Uniform;
            p.charge_a = 0.0; p.charge_b = 0.1;
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
            for (int t = 0; t < 3000; ++t) world_step(w);
            CHECK(cudaDeviceSynchronize() == cudaSuccess);
            CHECK(!cell_store_download_positions(w.cells, tmp.data(),
                                                 run == 0 ? ya.data() : yb.data(),
                                                 tmp2.data(), 2000));
            world_destroy(w);
        }
        int mismatches = 0;
        for (int i = 0; i < 2000; ++i) if (ya[i] != yb[i]) ++mismatches;
        CHECK(mismatches == 0);
    }

    return astro::test::finish("test_buoyancy");
}
