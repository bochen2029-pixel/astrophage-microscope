// tests/physics/test_emission.cu -- P5, and T13/T15/T16/T17/T20.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "golden/expected_values.h"
#include "sim/emission.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;
namespace ex = astro::expected;

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_emission: no CUDA device; skipping\n");
        return 0;
    }
    const double a = canon::CELL_RADIUS;

    // --- T16, T17, T20: the Petrova line is a quantum line, not a blackbody ---
    {
        CHECK_CLOSE(canon::PETROVA_PHOTON_ENERGY, ex::T16_PHOTON_ENERGY, ex::T16_PHOTON_ENERGY_TOL);
        CHECK_CLOSE(canon::PETROVA_FREQUENCY, ex::T17_PETROVA_FREQ, ex::T17_PETROVA_FREQ_TOL);
        CHECK_CLOSE(canon::WIEN_LAMBDA_AT_SETPOINT, ex::T20_WIEN_SETPOINT, ex::T20_WIEN_SETPOINT_TOL);
        // T20: the thermal peak and the emission line are DIFFERENT BANDS. If
        // these ever coincide, Thermal IR and Petrovascope stop being distinct
        // views and a real physical distinction has been lost.
        const double ratio = canon::PETROVA_WAVELENGTH / canon::WIEN_LAMBDA_AT_SETPOINT;
        std::printf("  Petrova %.3f um vs thermal peak %.3f um (%.2fx apart)\n",
                    canon::PETROVA_WAVELENGTH * 1e6,
                    canon::WIEN_LAMBDA_AT_SETPOINT * 1e6, ratio);
        CHECK(ratio > 3.0);
        CHECK_CLOSE(petrova_photons_per_second(canon::PETROVA_MAX_POWER) *
                    (canon::CELL_ENERGY_MAX / canon::PETROVA_MAX_POWER),
                    canon::PETROVA_PHOTONS_PER_FULL_CELL, 1e-9);
    }

    // --- photon thrust, and the hover coincidence ADR-005 rests on -----------
    {
        CHECK_CLOSE(photon_thrust_from(1.0e-3), ex::T6_THRUST_1MW, ex::T6_THRUST_1MW_TOL);
        CHECK(ex::HOVER_POWER_FULL < canon::PETROVA_MAX_POWER);
    }

    // --- P5: shadowing is EXACT, not merely deep -----------------------------
    {
        // Directly aligned: total. Not 0.999 -- albedo is exactly zero.
        CHECK(disc_overlap_fraction(0.0, a) == 1.0);
        // Two diameters apart: nothing. Not 1e-6.
        CHECK(disc_overlap_fraction(2.0 * a, a) == 0.0);
        CHECK(disc_overlap_fraction(3.0 * a, a) == 0.0);
        // Half-overlap is monotone in between.
        CHECK(disc_overlap_fraction(a, a) > 0.0 && disc_overlap_fraction(a, a) < 1.0);
        CHECK(disc_overlap_fraction(0.5 * a, a) > disc_overlap_fraction(1.5 * a, a));

        const Vec3 light{1.0, 0.0, 0.0};
        // Perfectly collinear, downstream: fully shadowed.
        CHECK(shadow_fraction(Vec3{3 * a, 0, 0}, Vec3{0, 0, 0}, light) == 1.0);
        // The upstream cell is NOT shadowed by the one behind it.
        CHECK(shadow_fraction(Vec3{0, 0, 0}, Vec3{3 * a, 0, 0}, light) == 0.0);
        // Offset perpendicular by a full diameter: clear.
        CHECK(shadow_fraction(Vec3{3 * a, 2 * a, 0}, Vec3{0, 0, 0}, light) == 0.0);
        // Offset in z counts too -- the shadow is a cylinder, not a stripe.
        CHECK(shadow_fraction(Vec3{3 * a, 0, 2 * a}, Vec3{0, 0, 0}, light) == 0.0);
        CHECK(shadow_fraction(Vec3{3 * a, 0, 0.5 * a}, Vec3{0, 0, 0}, light) > 0.5);
    }

    // --- T13: a rear cell receives EXACTLY zero, and charges not at all ------
    {
        World w;
        WorldDesc d;
        d.capacity = 2;
        d.motion.thermal_noise = false;
        d.motion.thermal_enabled = false;      // isolate the light path
        d.motion.contact_enabled = false;
        d.motion.adhesion_enabled = false;
        CHECK(!world_create(w, d));
        w.light.dir_x = 1.0f; w.light.dir_y = 0.0f;
        w.light.irradiance = 1.0e4f;
        w.light.enabled = 1;

        SpawnParams p;
        p.count = 2;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, 1ull));
        // Collinear along the light and 15 um apart -- clear of contact (2a =
        // 10 um) but inside the hash neighbourhood (22 um), which is where exact
        // 3D shadowing lives. Beyond it the grid's statistical extinction takes
        // over and can only ever be fractional (ADR-021).
        const double px[2] = {-7.5e-6, 7.5e-6};
        const double zero[2] = {0.0, 0.0};
        cudaMemcpy(w.cells.view.x, px, sizeof(px), cudaMemcpyHostToDevice);
        cudaMemcpy(w.cells.view.y, zero, sizeof(zero), cudaMemcpyHostToDevice);
        cudaMemcpy(w.cells.view.z, zero, sizeof(zero), cudaMemcpyHostToDevice);
        const double e0[2] = {0.0, 0.0};
        cudaMemcpy(w.cells.view.energy, e0, sizeof(e0), cudaMemcpyHostToDevice);

        // ONE tick. "Exactly zero" is a statement about a perfectly collinear
        // pair, and integration does not preserve that: over 200 ticks the two
        // drift apart by ~1e-13 m, which is enough to leave 1e-8 of the incident
        // light. That residual is correct -- they genuinely are not collinear
        // any more -- so the exact claim is tested where it actually holds, and
        // the drifted case is checked below with a relative bound.
        world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> e(2);
        std::vector<float> ir(2);
        CHECK(!cell_store_download_energy(w.cells, e.data(), 2));
        cudaMemcpy(ir.data(), w.cells.view.irradiance, sizeof(float) * 2, cudaMemcpyDeviceToHost);
        std::printf("  collinear pair: front irradiance %.4g (E=%.4g J), "
                    "rear %.4g (E=%.4g J)\n", ir[0], e[0], ir[1], e[1]);
        CHECK(ir[0] > 0.0f);
        CHECK(e[0] > 0.0);
        CHECK(ir[1] == 0.0f);      // EXACTLY zero
        CHECK(e[1] == 0.0);        // and therefore dCharge/dt exactly zero

        // And it stays dark as the pair drifts: still under a millionth of the
        // front cell after 200 more ticks.
        for (int t = 0; t < 200; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!cell_store_download_energy(w.cells, e.data(), 2));
        cudaMemcpy(ir.data(), w.cells.view.irradiance, sizeof(float) * 2, cudaMemcpyDeviceToHost);
        std::printf("  after 200 ticks of drift: rear irradiance %.4g (%.1e of front)\n",
                    ir[1], ir[1] / ir[0]);
        CHECK(ir[1] < 1e-6f * ir[0]);
        CHECK(e[1] < 1e-6 * e[0]);
        world_destroy(w);
    }

    // --- T15: the Komorov experiment ----------------------------------------
    // 1 kW for 25 minutes is exactly the 1.5 MJ capacity, and 16.69 ng of mass.
    {
        CHECK_CLOSE(ex::T15_KOMOROV_ENERGY, canon::CELL_ENERGY_MAX, 1e-9);
        CHECK_CLOSE(ex::T15_KOMOROV_MASS, canon::CELL_MASS_STORE_MAX, 1e-9);

        // Absorbed on the geometric cross-section, so 1 kW must be focused to a
        // ~10 um spot. The novel skips this; the simulation cannot.
        const double beam_w = 1.0e3;
        const double intensity = beam_w / canon::CELL_CROSS_SECTION;
        std::printf("  Komorov: 1 kW on pi a^2 needs %.3e W/m^2 (a ~10 um spot)\n", intensity);
        CHECK_CLOSE(absorbed_power(intensity, 0.0), beam_w, 1e-9);

        // Integrate it: 1500 s of full absorption fills the store exactly.
        double energy = 0.0;
        const double dt = 1.0;
        for (int t = 0; t < 1500; ++t) {
            energy += absorbed_power(intensity, 0.0) * dt;
            if (energy > canon::CELL_ENERGY_MAX) energy = canon::CELL_ENERGY_MAX;
        }
        const double dmass = energy / (canon::C_LIGHT * canon::C_LIGHT);
        std::printf("  after 1 kW x 25 min: %.6g J, mass gain %.4f ng\n", energy, dmass * 1e12);
        CHECK_CLOSE(energy, ex::T15_KOMOROV_ENERGY, ex::T15_KOMOROV_ENERGY_TOL);
        CHECK_CLOSE(dmass, ex::T15_KOMOROV_MASS, ex::T15_KOMOROV_MASS_TOL);
    }

    // --- P5 at population scale: depth along the light decides who charges ---
    {
        const int32_t n = 8000;
        World w;
        WorldDesc d;
        d.capacity = n;
        d.seed = 4242ull;
        d.motion.thermal_enabled = false;
        d.motion.contact_enabled = false;
        d.motion.adhesion_enabled = false;
        CHECK(!world_create(w, d));
        w.light.dir_x = 1.0f; w.light.dir_y = 0.0f;
        w.light.irradiance = 5.0e3f;
        w.light.enabled = 1;

        SpawnParams p;
        p.count = n;
        p.placement = Placement::Uniform;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
        const std::vector<double> zeros(static_cast<size_t>(n), 0.0);
        cudaMemcpy(w.cells.view.energy, zeros.data(), sizeof(double) * n, cudaMemcpyHostToDevice);

        for (int t = 0; t < 500; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<double> x(n), y(n), z(n), e(n);
        CHECK(!cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n));
        CHECK(!cell_store_download_energy(w.cells, e.data(), n));

        // Charge must fall with depth along the light axis.
        double sx = 0, se = 0, sxx = 0, see = 0, sxe = 0;
        for (int i = 0; i < n; ++i) {
            sx += x[i]; se += e[i]; sxx += x[i] * x[i]; see += e[i] * e[i]; sxe += x[i] * e[i];
        }
        const double r = (n * sxe - sx * se) /
                         std::sqrt((n * sxx - sx * sx) * (n * see - se * se));
        // Compare the lit face against the far side. A sparse uniform population
        // is the FAR-field regime: cells average ~45 um apart, well outside each
        // other's hash neighbourhood, so extinction is the grid's Beer-Lambert
        // and is fractional by construction. Exact zeros belong to the adjacent
        // pair above; here the signature is the gradient.
        double front = 0.0, back = 0.0;
        int nf = 0, nb = 0;
        for (int i = 0; i < n; ++i) {
            if (x[i] < -0.3 * canon::CHAMBER_W) { front += e[i]; ++nf; }
            if (x[i] >  0.3 * canon::CHAMBER_W) { back  += e[i]; ++nb; }
        }
        CHECK(nf > 100 && nb > 100);
        front /= nf; back /= nb;
        std::printf("  8000 cells lit along +x: charge vs depth r = %+.4f, "
                    "lit face %.4g J vs far side %.4g J (%.0fx)\n",
                    r, front, back, front / (back > 0 ? back : 1e-300));
        CHECK(r < -0.5);              // deeper means less charged
        CHECK(front > 5.0 * back);    // and the far side is starved by comparison
        world_destroy(w);
    }

    // --- slew: a cell cannot re-aim instantly --------------------------------
    {
        const Vec3 from{1, 0, 0}, to{-1, 0, 0};
        const Vec3 one = slew_toward(from, to, 0.01);      // 0.01 rad of a pi turn
        CHECK(dot(one, from) > 0.9);                        // barely moved
        CHECK(dot(one, to) < 0.1);
        const Vec3 done = slew_toward(from, to, 100.0);     // plenty of time
        CHECK(dot(done, to) > 0.999);
        CHECK_CLOSE(length(one), 1.0, 1e-12);
    }

    // --- determinism through the light path (INV-8) --------------------------
    {
        double tot[2];
        for (int run = 0; run < 2; ++run) {
            World w;
            WorldDesc d;
            d.capacity = 3000;
            d.seed = 777ull;
            d.motion.thermal_enabled = false;
            CHECK(!world_create(w, d));
            w.light.dir_x = 1.0f; w.light.irradiance = 2.0e3f; w.light.enabled = 1;
            SpawnParams p;
            p.count = 3000;
            CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
            for (int t = 0; t < 1000; ++t) world_step(w);
            CHECK(cudaDeviceSynchronize() == cudaSuccess);
            std::vector<double> e(3000);
            CHECK(!cell_store_download_energy(w.cells, e.data(), 3000));
            tot[run] = 0.0;
            for (double v : e) tot[run] += v;
            world_destroy(w);
        }
        CHECK(tot[0] == tot[1]);
    }

    return astro::test::finish("test_emission");
}
