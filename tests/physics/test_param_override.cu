// tests/physics/test_param_override.cu -- M11f (ADR-035).
//
// The sim reads the curated live-tunable overrides (World fields the inspector fills from
// the ParamSet), so a tuned parameter actually changes the physics -- and an UNTOUCHED
// override is bit-identical to canon, so no earlier gate moved (INV-8). Each override is
// verified end-to-end (a stepped world), which is stronger than a wiring inspection.
#include <cmath>
#include <cstdio>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/taxis.cuh"     // taxis_emit_power: taxis.cu is a thin loop over it
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

// A growth world like test_lifecycle's: saturating CO2, dormant cells, mechanics off,
// biology compressed by the clock. `quota` overrides the division threshold; leaving it at
// canon reproduces the M9a doubling by construction.
Error make_growth_world(World& w, int32_t n, double biology_rate, double quota,
                        uint64_t seed = 20260802ull) {
    WorldDesc d;
    d.capacity = 1 << 20;                     // append-only room to grow
    d.seed = seed;
    d.co2_init = canon::CO2_SAT_CONC_1ATM;
    d.motion.contact_enabled = false;
    d.motion.adhesion_enabled = false;
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    ASTRO_TRY(world_create(w, d));
    w.biology_rate = biology_rate;
    w.co2_mass_per_division = quota;          // the override under test
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 0.5;
    p.awake = false;                          // dormant: no thermostat spend
    return cell_store_spawn(w.cells, p, w.chamber, seed);
}

int32_t grow_and_count(int32_t n0, double quota, int ticks, double rate) {
    World w{};
    if (make_growth_world(w, n0, rate, quota)) return -1;
    for (int t = 0; t < ticks; ++t) world_step(w);
    cudaDeviceSynchronize();
    const int32_t c = w.cells.count;
    world_destroy(w);
    return c;
}

// Discharge a population of full, awake cells through the spin-drive flash for a short
// window and return the audited discharged store [J]. Thermal/emission/taxis are off so
// the ONLY thing that touches the store is the flash -- isolating the flash-power override.
double flash_discharge(double flash_power, int ticks) {
    World w{};
    WorldDesc d;
    d.capacity = 4096;
    d.seed = 20260802ull;
    d.motion.thermal_enabled = false;
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    if (world_create(w, d)) return -1.0;
    w.petrova_flash_power = flash_power;      // the override under test
    w.flash_active = true;
    SpawnParams p;
    p.count = 1000;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 1.0;                         // full store: nobody empties in the window
    p.awake = true;                           // the flash only discharges AWAKE cells
    if (cell_store_spawn(w.cells, p, w.chamber, d.seed)) { world_destroy(w); return -1.0; }
    for (int t = 0; t < ticks; ++t) world_step(w);
    cudaDeviceSynchronize();
    double imp = 0.0, dis = 0.0;
    world_flash_audit(w, imp, dis);
    world_destroy(w);
    return dis;
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_param_override: no CUDA device; skipping\n");
        return 0;
    }

    const double rate = 2.0e7;                              // compress 8 days into ~35 ticks
    const int32_t n0 = 2000;
    // Comfortably past one canon doubling (~35 ticks) so the canon arm has clearly divided.
    const int ticks = 50;

    // --- Override 1 (GATE): the division quota changes doubling ---------------
    // Halving CO2_MASS_PER_DIVISION halves the CO2 a cell must bank before mitosis, so it
    // divides sooner and the population is larger after the same ticks; doubling it makes
    // the arm slower. The uptake rate reads canon throughout, so this isolates the quota.
    {
        const int32_t c_canon  = grow_and_count(n0, canon::CO2_MASS_PER_DIVISION,       ticks, rate);
        const int32_t c_half   = grow_and_count(n0, 0.5 * canon::CO2_MASS_PER_DIVISION, ticks, rate);
        const int32_t c_double = grow_and_count(n0, 2.0 * canon::CO2_MASS_PER_DIVISION, ticks, rate);
        std::printf("  quota: %d start -> canon %d, half-quota %d, double-quota %d\n",
                    n0, c_canon, c_half, c_double);
        CHECK(c_canon > n0);           // the canon arm actually divides -- not a vacuous test
        CHECK(c_half > c_canon);       // less CO2 per split -> faster -> more cells
        CHECK(c_double < c_canon);     // more CO2 per split -> slower -> fewer cells
    }

    // --- The default override is bit-identical to canon (INV-8) ---------------
    // A World override left at its default value must reproduce M11e exactly -- if it did
    // not, every earlier gate would already have shifted. Passing the canon value explicitly
    // must equal the untouched default.
    {
        const int32_t explicit_canon = grow_and_count(n0, canon::CO2_MASS_PER_DIVISION, ticks, rate);
        World w{};
        CHECK(!make_growth_world(w, n0, rate, w.co2_mass_per_division));   // untouched default
        for (int t = 0; t < ticks; ++t) world_step(w);
        cudaDeviceSynchronize();
        std::printf("  default==canon: %d vs %d\n", w.cells.count, explicit_canon);
        CHECK(w.cells.count == explicit_canon);
        world_destroy(w);
    }

    // --- Override 2 (GATE): the flash discharge rate changes energy discharged -
    // Over a window short enough that no cell empties, the discharged store is power*dt per
    // cell, so twice the flash power discharges twice the energy (a linear, exact relation).
    {
        const int fticks = 40;
        const double d_canon  = flash_discharge(canon::PETROVA_FLASH_POWER,       fticks);
        const double d_double = flash_discharge(2.0 * canon::PETROVA_FLASH_POWER, fticks);
        const double ratio = d_canon > 0.0 ? d_double / d_canon : 0.0;
        std::printf("  flash: canon %.4e J, 2x-power %.4e J (ratio %.4f)\n",
                    d_canon, d_double, ratio);
        CHECK(d_canon > 0.0);                 // the flash actually fired
        CHECK_CLOSE(ratio, 2.0, 0.02);        // discharge is linear in the overridden rate
    }

    // --- Override 3 (GATE): the emission cap threads through taxis_emit_power --
    // taxis.cu is a thin loop over taxis_emit_power (ARCHITECTURE Sec 3.3), so exercising
    // that function on the host with the override argument IS the kernel physics. With
    // energy/dt far above any cap, the cap binds and must move with the override.
    {
        const double avail = 1.0e6;           // energy/dt >> any cap, so the cap decides
        CHECK(taxis_emit_power(TaxisState::Feed, avail, 1.0, canon::PETROVA_MAX_POWER)
              == canon::PETROVA_MAX_POWER);
        CHECK(taxis_emit_power(TaxisState::Feed, avail, 1.0, 2.0 * canon::PETROVA_MAX_POWER)
              == 2.0 * canon::PETROVA_MAX_POWER);
        // The defaulted argument equals canon, so a 3-arg call (every existing caller) is
        // unchanged -- the bit-identity that keeps the taxis gate green.
        CHECK(taxis_emit_power(TaxisState::Feed, avail, 1.0)
              == taxis_emit_power(TaxisState::Feed, avail, 1.0, canon::PETROVA_MAX_POWER));
    }

    return astro::test::finish("test_param_override");
}
