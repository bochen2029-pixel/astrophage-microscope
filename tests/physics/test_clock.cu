// tests/physics/test_clock.cu -- the multi-rate clock. docs/PHYSICS.md Sec 12,
// ADR-011, ADR-027.
//
// The M9c gate wants "each preset advances biology and physics at its stated
// ratio". That splits cleanly:
//   * the physics clock is checked through the elapsed-time accumulator, which
//     must scale exactly with physics_rate;
//   * the biology clock is checked through one tick of CO2 uptake, whose banked
//     mass scales exactly with dt_bio = DT * physics_rate * biology_rate -- so it
//     also pins the compounding of the two rates.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;
using astro::contract::ClockPreset;

namespace {

Error make_world(World& w, int32_t n, double co2_init, uint64_t seed = 20260802ull) {
    WorldDesc d;
    d.capacity = n > 0 ? n : 1;
    d.seed = seed;
    d.co2_init = co2_init;
    // Isolate the clock: no mechanics, no emission, no taxis. Growth is the only
    // thing biology_rate should touch, and dormant cells never spend store.
    d.motion.contact_enabled = false;
    d.motion.adhesion_enabled = false;
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    ASTRO_TRY(world_create(w, d));
    if (n <= 0) return ok();
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 0.5;
    p.awake = false;
    return cell_store_spawn(w.cells, p, w.chamber, seed);
}

double mean_co2_held(const World& w) {
    const int32_t n = w.cells.count;
    std::vector<double> c(static_cast<size_t>(n));
    cudaMemcpy(c.data(), w.cells.view.co2_held, sizeof(double) * n, cudaMemcpyDeviceToHost);
    double s = 0.0;
    for (double v : c) s += v;
    return n > 0 ? s / n : 0.0;
}

} // namespace

int main() {
    // --- Section 1 (pure): presets map to the canon table, ranges clamp --------
    {
        double p = 0.0, b = 0.0;
        clock_preset_rates(ClockPreset::Realtime, p, b);
        CHECK(p == canon::CLOCK_REALTIME_PHYSICS && b == canon::CLOCK_REALTIME_BIOLOGY);
        clock_preset_rates(ClockPreset::Motion, p, b);
        CHECK(p == canon::CLOCK_MOTION_PHYSICS && b == canon::CLOCK_MOTION_BIOLOGY);
        clock_preset_rates(ClockPreset::Metabolic, p, b);
        CHECK(p == canon::CLOCK_METABOLIC_PHYSICS && b == canon::CLOCK_METABOLIC_BIOLOGY);
        clock_preset_rates(ClockPreset::Generational, p, b);
        CHECK(p == canon::CLOCK_GENERATIONAL_PHYSICS && b == canon::CLOCK_GENERATIONAL_BIOLOGY);

        // The four presets, as documented in ADR-011: only Motion speeds physics,
        // and biology climbs 1 -> 1e4 -> 1e6.
        CHECK(canon::CLOCK_MOTION_PHYSICS == 10.0);
        CHECK(canon::CLOCK_METABOLIC_BIOLOGY == 1.0e4);
        CHECK(canon::CLOCK_GENERATIONAL_BIOLOGY == 1.0e6);
        CHECK(canon::CLOCK_GENERATIONAL_PHYSICS < canon::CLOCK_REALTIME_PHYSICS);

        // world_set_clock clamps a Custom clock into the ADR-011 ranges.
        World w{};
        CHECK(!make_world(w, 1, 0.0));
        world_set_clock(w, ClockPreset::Custom, 1.0e9, 1.0e12);   // absurd, must clamp
        CHECK(w.physics_rate == canon::CLOCK_PHYSICS_MAX);
        CHECK(w.biology_rate == canon::CLOCK_BIOLOGY_MAX);
        world_set_clock(w, ClockPreset::Custom, -5.0, 0.0);       // below range
        CHECK(w.physics_rate == canon::CLOCK_PHYSICS_MIN);
        CHECK(w.biology_rate == canon::CLOCK_BIOLOGY_MIN);
        world_set_clock(w, ClockPreset::Generational);            // named preset ignores customs
        CHECK(w.physics_rate == canon::CLOCK_GENERATIONAL_PHYSICS);
        CHECK(w.biology_rate == canon::CLOCK_GENERATIONAL_BIOLOGY);
        world_destroy(w);
    }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_clock: no CUDA device; ran the pure checks only\n");
        return astro::test::finish("test_clock");
    }

    // --- Section 2 (GATE): the physics clock advances at the preset ratio ------
    {
        const int ticks = 100;
        World wr{}, wm{};
        CHECK(!make_world(wr, 64, 0.0));
        CHECK(!make_world(wm, 64, 0.0));
        world_set_clock(wr, ClockPreset::Realtime);
        world_set_clock(wm, ClockPreset::Motion);
        for (int t = 0; t < ticks; ++t) { world_step(wr); world_step(wm); }
        cudaDeviceSynchronize();

        const double t_real = world_sim_time(wr);
        const double t_motion = world_sim_time(wm);
        std::printf("  clock physics: realtime %.4f s, motion %.4f s over %d ticks "
                    "(ratio %.4f)\n", t_real, t_motion, ticks, t_motion / t_real);
        // The accumulator reproduces ticks * DT * physics_rate exactly, and the
        // Motion preset runs physics 10x faster than Realtime.
        CHECK_CLOSE(t_real, ticks * canon::DT_PHYSICS * canon::CLOCK_REALTIME_PHYSICS, 1e-12);
        CHECK_CLOSE(t_motion, ticks * canon::DT_PHYSICS * canon::CLOCK_MOTION_PHYSICS, 1e-12);
        CHECK_CLOSE(t_motion / t_real,
                    canon::CLOCK_MOTION_PHYSICS / canon::CLOCK_REALTIME_PHYSICS, 1e-9);
        world_destroy(wr);
        world_destroy(wm);
    }

    // --- Section 3 (GATE): the biology clock, and the compounding of the two ---
    {
        // One tick of uptake on a saturating, undepleted medium. Both arms read the
        // same initial CO2 for their demand, so the uptake RATE is identical and the
        // banked mass differs only by dt_bio = DT * physics_rate * biology_rate.
        // One tick keeps division and cross-arm depletion out of it, so the ratios
        // are exact rather than approximate.
        const double conc = canon::CO2_SAT_CONC_1ATM;

        World a{}, b{};
        CHECK(!make_world(a, 2000, conc));
        CHECK(!make_world(b, 2000, conc));
        a.physics_rate = 1.0; a.biology_rate = 1.0e4;
        b.physics_rate = 1.0; b.biology_rate = 2.0e4;
        world_step(a); world_step(b);
        cudaDeviceSynchronize();
        const double ca = mean_co2_held(a), cb = mean_co2_held(b);
        std::printf("  clock biology: co2_held %.4e vs %.4e (ratio %.5f, expected 2)\n",
                    ca, cb, cb / ca);
        CHECK(ca > 0.0);
        CHECK_CLOSE(cb / ca, 2.0, 1e-6);      // biology_rate doubled -> uptake doubled
        world_destroy(a);
        world_destroy(b);

        // Compounding: physics_rate and biology_rate enter the biology clock as a
        // product, so (physics 2, biology 1) and (physics 1, biology 2) bank the
        // same CO2 in one tick.
        World c{}, e{};
        CHECK(!make_world(c, 2000, conc));
        CHECK(!make_world(e, 2000, conc));
        c.physics_rate = 2.0; c.biology_rate = 1.0;
        e.physics_rate = 1.0; e.biology_rate = 2.0;
        world_step(c); world_step(e);
        cudaDeviceSynchronize();
        const double cc = mean_co2_held(c), ce = mean_co2_held(e);
        std::printf("  clock compounding: co2_held %.4e vs %.4e (ratio %.5f, expected 1)\n",
                    cc, ce, cc / ce);
        CHECK_CLOSE(cc / ce, 1.0, 1e-6);
        world_destroy(c);
        world_destroy(e);
    }

    return astro::test::finish("test_clock");
}
