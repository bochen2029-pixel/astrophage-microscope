// tests/physics/test_contact.cu -- soft-sphere contact, adhesion, containment.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_contact: no CUDA device; skipping\n");
        return 0;
    }

    // --- the pair force, analytically ---------------------------------------
    {
        const double two_a = canon::CELL_DIAMETER;
        // Beyond contact: nothing at all. Contact must be strictly local, or the
        // 27-cell neighbour walk would be silently truncating a longer-range force.
        CHECK(length(contact_force(Vec3{0, 0, 0}, Vec3{two_a * 1.001, 0, 0})) == 0.0);
        CHECK(length(contact_force(Vec3{0, 0, 0}, Vec3{two_a, 0, 0})) == 0.0);

        // Overlapping: repulsive, along the line of centres, linear in overlap.
        const double overlap = 0.1 * two_a;
        const Vec3 f = contact_force(Vec3{0, 0, 0}, Vec3{two_a - overlap, 0, 0});
        CHECK(f.x < 0.0);                                   // pushed away from the neighbour
        CHECK(std::fabs(f.y) < 1e-30 && std::fabs(f.z) < 1e-30);
        CHECK_CLOSE(-f.x, canon::CONTACT_STIFFNESS * overlap, 1e-12);

        // Newton's third law.
        const Vec3 g = contact_force(Vec3{two_a - overlap, 0, 0}, Vec3{0, 0, 0});
        CHECK_CLOSE(g.x, -f.x, 1e-12);

        // Linear in overlap, so rest overlap is force/stiffness.
        const Vec3 f2 = contact_force(Vec3{0, 0, 0}, Vec3{two_a - 2.0 * overlap, 0, 0});
        CHECK_CLOSE(-f2.x, 2.0 * (-f.x), 1e-12);

        // Stiffness is STABILITY-limited, not rigidity-tuned (ADR-018). In an
        // overdamped medium an explicit spring moves k*d*dt/gamma per step, so
        // k must stay under gamma/dt or contact overshoots and rings.
        std::printf("  contact stability ratio k*dt/gamma = %.4f\n",
                    canon::CONTACT_STABILITY_RATIO);
        CHECK(canon::CONTACT_STABILITY_RATIO < 0.25);   // monotone convergence
        CHECK(canon::CONTACT_STABILITY_RATIO > 0.01);   // and not needlessly soft

        const double m_empty = cell_mass(canon::CELL_MASS_DRY, 0.0);
        const double m_full  = cell_mass(canon::CELL_MASS_DRY, canon::CELL_ENERGY_MAX);
        const double frac_empty = rest_overlap_fraction(fabs(buoyant_weight(m_empty)));
        const double frac_full  = rest_overlap_fraction(fabs(buoyant_weight(m_full)));
        std::printf("  rest overlap: empty cell %.2f%%, full cell %.1f%% of a diameter\n",
                    frac_empty * 100.0, frac_full * 100.0);
        CHECK_CLOSE(frac_empty, canon::CONTACT_REST_OVERLAP_EMPTY, 1e-9);
        CHECK(frac_empty < 0.05);

        // KNOWN LIMIT, documented in ADR-018 rather than hidden. Holding a fully
        // charged cell (32x water) within 5 % would need 3.36x the stability
        // limit, i.e. dt <= 0.3 ms or contact substepping. Bounded here so it
        // cannot silently get worse.
        CHECK(frac_full < 2.0);
    }

    // --- two overlapping cells separate -------------------------------------
    {
        World w;
        WorldDesc d;
        d.capacity = 2;
        d.motion.thermal_noise = false;
        d.motion.adhesion_enabled = false;
        CHECK(!world_create(w, d));

        SpawnParams p;
        p.count = 2;
        p.placement = Placement::Grid;    // deterministic, and they land apart
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, 1ull));

        // Place them overlapping by hand.
        const double half = 0.25 * canon::CELL_DIAMETER;
        double px[2] = {-half, +half};
        double zero[2] = {0.0, 0.0};
        cudaMemcpy(w.cells.view.x, px, sizeof(px), cudaMemcpyHostToDevice);
        cudaMemcpy(w.cells.view.y, zero, sizeof(zero), cudaMemcpyHostToDevice);
        cudaMemcpy(w.cells.view.z, zero, sizeof(zero), cudaMemcpyHostToDevice);

        std::vector<double> x(2), y(2), z(2);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), 2));
        const double gap0 = std::fabs(x[1] - x[0]);

        for (int t = 0; t < 2000; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), 2));
        const double gap1 = std::fabs(x[1] - x[0]);

        std::printf("  overlapping pair: gap %.2f -> %.2f um (contact %.1f um)\n",
                    gap0 * 1e6, gap1 * 1e6, canon::CELL_DIAMETER * 1e6);
        CHECK(gap1 > gap0);                          // they pushed apart
        CHECK(gap1 <= canon::CELL_DIAMETER * 1.05);  // and stopped at contact, not beyond
        world_destroy(w);
    }

    // --- a packed cluster settles without interpenetrating -------------------
    {
        const int32_t n = 3000;
        World w;
        WorldDesc d;
        d.capacity = n;
        d.seed = 4242ull;
        CHECK(!world_create(w, d));
        SpawnParams p;
        p.count = n;
        p.placement = Placement::Gaussian;
        p.place_radius = 8.0e-5;      // dense enough that contacts matter
        p.charge_dist = Distribution::Constant;
        p.charge_a = canon::CHARGE_NEUTRAL_BUOYANCY;   // hover, so it stays clustered
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));

        for (int t = 0; t < 20000; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> x(n), y(n), z(n);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n));

        double worst_overlap = 0.0;
        int deep = 0;
        for (int i = 0; i < n; ++i) {
            for (int j = i + 1; j < n; ++j) {
                const double dx = x[i] - x[j], dy = y[i] - y[j], dz = z[i] - z[j];
                const double r = std::sqrt(dx * dx + dy * dy + dz * dz);
                if (r < canon::CELL_DIAMETER) {
                    const double ov = (canon::CELL_DIAMETER - r) / canon::CELL_DIAMETER;
                    if (ov > worst_overlap) worst_overlap = ov;
                    if (ov > 0.05) ++deep;
                }
            }
        }
        std::printf("  packed cluster: worst overlap %.2f%% of a diameter, %d pairs over 5%%\n",
                    worst_overlap * 100.0, deep);
        CHECK(worst_overlap < 0.05);
        CHECK(deep == 0);

        // Nothing escaped and nothing went non-finite.
        int bad = 0;
        for (int i = 0; i < n; ++i) {
            if (!std::isfinite(x[i]) || !std::isfinite(y[i]) || !std::isfinite(z[i])) ++bad;
            if (std::fabs(x[i]) > 0.5 * canon::CHAMBER_W) ++bad;
            if (std::fabs(y[i]) > 0.5 * canon::CHAMBER_H) ++bad;
            if (std::fabs(z[i]) > 0.5 * canon::CHAMBER_D) ++bad;
        }
        CHECK(bad == 0);
        world_destroy(w);
    }

    // --- containment over a long run ----------------------------------------
    {
        const int32_t n = 2000;
        World w;
        WorldDesc d;
        d.capacity = n;
        CHECK(!world_create(w, d));
        SpawnParams p;
        p.count = n;
        p.charge_dist = Distribution::Uniform;
        p.charge_a = 0.0; p.charge_b = 0.5;    // some sink hard, some rise
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, 909ull));

        for (int t = 0; t < 100000; ++t) world_step(w);    // 100 s
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> x(n), y(n), z(n);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n));
        int escaped = 0;
        for (int i = 0; i < n; ++i) {
            if (!std::isfinite(x[i]) || !std::isfinite(y[i]) || !std::isfinite(z[i])) ++escaped;
            if (std::fabs(x[i]) > 0.5 * canon::CHAMBER_W) ++escaped;
            if (std::fabs(y[i]) > 0.5 * canon::CHAMBER_H) ++escaped;
            if (std::fabs(z[i]) > 0.5 * canon::CHAMBER_D) ++escaped;
        }
        CHECK(escaped == 0);
        world_destroy(w);
    }

    // --- adhesion --------------------------------------------------------
    // Gravity runs along -y (ADR-006), so cells reach the glass by diffusion,
    // not by settling. Adhesion is therefore a slow accumulation. Verify it
    // happens at all, and that disabling it stops it entirely.
    {
        int stuck_counts[2] = {0, 0};
        for (int mode = 0; mode < 2; ++mode) {
            const int32_t n = 4000;
            World w;
            WorldDesc d;
            d.capacity = n;
            d.motion.adhesion_enabled = (mode == 1);
            CHECK(!world_create(w, d));
            SpawnParams p;
            p.count = n;
            p.charge_dist = Distribution::Constant;
            p.charge_a = canon::CHARGE_NEUTRAL_BUOYANCY;   // stay suspended
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, 77ull));
            for (int t = 0; t < 60000; ++t) world_step(w);
            CHECK(cudaDeviceSynchronize() == cudaSuccess);

            std::vector<uint32_t> flags(n);
            cudaMemcpy(flags.data(), w.cells.view.flags, sizeof(uint32_t) * n,
                       cudaMemcpyDeviceToHost);
            for (int i = 0; i < n; ++i)
                if (flags[i] & contract::CELL_FLAG_STUCK) ++stuck_counts[mode];
            world_destroy(w);
        }
        std::printf("  adhered after 60 s: %d with adhesion off, %d with it on\n",
                    stuck_counts[0], stuck_counts[1]);
        CHECK(stuck_counts[0] == 0);      // off means off
        CHECK(stuck_counts[1] > 0);       // and on means something actually sticks
    }

    // --- determinism survives contact (INV-8) --------------------------------
    // Contact sums forces over neighbours, so if the neighbour ORDER were
    // nondeterministic this would drift. It is the real test of ADR-018.
    {
        const int32_t n = 3000;
        std::vector<double> ya(n), yb(n), t1(n), t2(n);
        for (int run = 0; run < 2; ++run) {
            World w;
            WorldDesc d;
            d.capacity = n;
            d.seed = 31337ull;
            CHECK(!world_create(w, d));
            SpawnParams p;
            p.count = n;
            p.placement = Placement::Gaussian;
            p.place_radius = 6.0e-5;      // packed, so contact is active
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
            for (int t = 0; t < 4000; ++t) world_step(w);
            CHECK(cudaDeviceSynchronize() == cudaSuccess);
            CHECK(!cell_store_download_positions(w.cells, t1.data(),
                                                 run == 0 ? ya.data() : yb.data(),
                                                 t2.data(), n));
            world_destroy(w);
        }
        int mismatches = 0;
        for (int i = 0; i < n; ++i) if (ya[i] != yb[i]) ++mismatches;
        std::printf("  determinism through contact: %d/%d positions differ\n", mismatches, n);
        CHECK(mismatches == 0);
    }

    return astro::test::finish("test_contact");
}
