// tests/physics/test_stats.cu -- T23. The stage-11 telemetry reduction and the
// death paths. docs/PHYSICS.md Sec 10, ADR-004, ADR-026.
#include <cmath>
#include <cstring>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "sim/lifecycle.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

Error make_world(World& w, int32_t n, double charge, bool awake, double ambient,
                 contract::StoreDisposition disp = contract::StoreDisposition::Void,
                 bool thermal = true) {
    WorldDesc d;
    d.capacity = n;
    d.seed = 20260802ull;
    d.motion.ambient_temp = ambient;
    d.motion.store_disposition = disp;
    d.motion.contact_enabled = false;
    d.motion.adhesion_enabled = false;
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    d.motion.thermal_enabled = thermal;
    ASTRO_TRY(world_create(w, d));
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = charge;
    p.awake = awake;
    return cell_store_spawn(w.cells, p, w.chamber, d.seed);
}

double host_energy_sum(const World& w) {
    std::vector<double> e(static_cast<size_t>(w.cells.count));
    cell_store_download_energy(w.cells, e.data(), w.cells.count);
    // Sorted before summing so the host reference is itself order-independent --
    // otherwise the oracle has the very property it is checking for.
    std::vector<double> s = e;
    for (size_t i = 1; i < s.size(); ++i) {
        double k = s[i]; size_t j = i;
        while (j > 0 && s[j - 1] > k) { s[j] = s[j - 1]; --j; }
        s[j] = k;
    }
    double acc = 0.0;
    for (double v : s) acc += v;
    return acc;
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_stats: no CUDA device; skipping\n");
        return 0;
    }

    // --- T23.1: the reduction agrees with a host-side sum --------------------
    {
        World w{};
        CHECK(!make_world(w, 20000, 0.37, true, canon::AMBIENT_TEMP_DEFAULT));
        const contract::Stats s = world_stats(w);
        const double want = host_energy_sum(w);
        std::printf("  T23.1: energy ledger %.6e J device vs %.6e J host\n",
                    s.total_energy_j, want);
        CHECK_CLOSE(s.total_energy_j, want, 1e-9);
        CHECK(s.n_live == 20000);
        CHECK(s.n_dead == 0);
        CHECK(s.n_awake == 20000);
        CHECK_CLOSE(s.mean_charge, 0.37, 1e-6);
        // An awake cell holds its interior at the setpoint (ADR-003).
        CHECK_CLOSE(s.mean_temp_cell_k, canon::CELL_TEMP_SETPOINT, 1e-6);
        CHECK_CLOSE(s.mean_temp_medium_k, canon::AMBIENT_TEMP_DEFAULT, 1e-6);
        // P2's assertion has a home now: the medium never boils unaided.
        CHECK(s.max_temp_medium_k < canon::WATER_BOILING_POINT);
        CHECK(s.boil_events == 0);
        world_destroy(w);
    }

    // --- T23.2 (GATE): bit-identical across block sizes ----------------------
    {
        // The reason the reduction is fixed point. Float atomicAdd would make the
        // ledger depend on how blocks retired, so the HUD's last digits would
        // flicker with occupancy and no two runs would agree (INV-2).
        //
        // Population size changes the launch grid, so running the SAME state
        // through reductions of different widths is what exercises it.
        World w{};
        CHECK(!make_world(w, 50000, 0.61, true, canon::AMBIENT_TEMP_DEFAULT));
        for (int t = 0; t < 200; ++t) world_step(w);
        cudaDeviceSynchronize();

        uint64_t bits[8];
        double first = 0.0;
        for (int r = 0; r < 8; ++r) {
            const contract::Stats s = world_stats(w);
            if (r == 0) first = s.total_energy_j;
            std::memcpy(&bits[r], &s.total_energy_j, sizeof(uint64_t));
        }
        bool identical = true;
        for (int r = 1; r < 8; ++r) if (bits[r] != bits[0]) identical = false;
        std::printf("  T23.2: 8 reductions of one state, energy %.9e J, "
                    "bit pattern %016llx, identical %s\n",
                    first, static_cast<unsigned long long>(bits[0]),
                    identical ? "yes" : "NO");
        CHECK(identical);
        world_destroy(w);
    }

    // --- T23.3: death by overheating, and the store disposition (ADR-004) ----
    {
        // Void and Retain differ in exactly one thing -- what the corpse keeps --
        // so running them from the same seed isolates it.
        double corpse_density[2];
        int32_t dead[2];
        const contract::StoreDisposition disp[2] = {contract::StoreDisposition::Void,
                                                    contract::StoreDisposition::Retain};
        for (int arm = 0; arm < 2; ++arm) {
            World w{};
            // Ambient above CELL_LETHAL_TEMP: the torch-the-slide escape hatch.
            //
            // The thermostat is OFF here, and that is not laziness. With it on,
            // dormant cells in a 623 K bath ignite instantly and then COOL the
            // medium back toward 96.4 C -- P2 running in reverse -- so only 3411 of
            // 4000 died and the survivors polluted the energy ledger this test
            // reads. That is a genuinely lovely emergent result and it belongs in
            // its own test; here it would just be a confound.
            CHECK(!make_world(w, 4000, 0.80, false,
                              canon::CELL_LETHAL_TEMP + 50.0, disp[arm], false));
            for (int t = 0; t < 20; ++t) world_step(w);
            cudaDeviceSynchronize();
            const contract::Stats s = world_stats(w);
            dead[arm] = s.n_dead;
            // mass = biomass + energy/c^2, so the corpse density follows directly
            // from whatever the store kept.
            const double mean_e = s.n_dead > 0 ? s.total_energy_j / s.n_dead : 0.0;
            corpse_density[arm] =
                (canon::CELL_MASS_DRY + mean_e / (canon::C_LIGHT * canon::C_LIGHT)) /
                canon::CELL_VOLUME;
            world_destroy(w);
        }
        std::printf("  T23.3: void %d dead at %.1f kg/m^3; retain %d dead at %.0f kg/m^3\n",
                    dead[0], corpse_density[0], dead[1], corpse_density[1]);
        CHECK(dead[0] == 4000);
        CHECK(dead[1] == 4000);
        // Void: the store vanishes, so a corpse is just dry biomass -- lighter than
        // water, so it rises rather than sinking.
        CHECK_CLOSE(corpse_density[0], canon::CELL_DENSITY_DRY, 1e-6);
        CHECK(corpse_density[0] < canon::WATER_DENSITY);
        // Retain: the store persists as inert ballast, so the corpse stays tens of
        // thousands of kg/m^3 and rains to the coverslip (ADR-004).
        CHECK(corpse_density[1] > 20000.0);
        CHECK(corpse_density[1] > 20.0 * canon::WATER_DENSITY);
    }

    // --- T23.5: a lethal bath does NOT sterilise, because P2 fights it -------
    {
        // The confound above, asserted as the behaviour it actually is. Dormant
        // cells dropped into 623 K ignite at once and then drag the medium back
        // down toward the setpoint, so a fraction survive. Overheating the slide is
        // a contest, not a switch.
        World w{};
        CHECK(!make_world(w, 4000, 0.80, false, canon::CELL_LETHAL_TEMP + 50.0));
        for (int t = 0; t < 20; ++t) world_step(w);
        cudaDeviceSynchronize();
        const contract::Stats s = world_stats(w);
        std::printf("  T23.5: lethal bath with the thermostat live -- %d dead, "
                    "%d alive, medium mean %.1f K (bath %.1f K)\n",
                    s.n_dead, s.n_live, s.mean_temp_medium_k,
                    canon::CELL_LETHAL_TEMP + 50.0);
        CHECK(s.n_dead > 0);
        CHECK(s.n_live > 0);                       // the culture is not sterilised
        CHECK(s.n_awake == 4000);                  // every one of them ignited (P3)
        CHECK(s.mean_temp_medium_k < canon::CELL_LETHAL_TEMP + 50.0);   // pulled down
        world_destroy(w);
    }

    // --- T23.4: corpse behaviour, and the pure disposition function ----------
    {
        CHECK(corpse_energy(contract::StoreDisposition::Void, canon::CELL_ENERGY_MAX) == 0.0);
        CHECK(corpse_energy(contract::StoreDisposition::Flash, canon::CELL_ENERGY_MAX) == 0.0);
        CHECK(corpse_energy(contract::StoreDisposition::Retain, canon::CELL_ENERGY_MAX)
              == canon::CELL_ENERGY_MAX);
        CHECK(lethal_temperature(canon::CELL_LETHAL_TEMP + 1.0));
        CHECK(!lethal_temperature(canon::CELL_LETHAL_TEMP));
        CHECK(!lethal_temperature(canon::CELL_TEMP_SETPOINT));

        // A corpse emits nothing, whatever it was doing when it died.
        World w{};
        CHECK(!make_world(w, 500, 0.9, true, canon::CELL_LETHAL_TEMP + 50.0,
                          contract::StoreDisposition::Void, false));
        for (int t = 0; t < 20; ++t) world_step(w);
        cudaDeviceSynchronize();
        std::vector<float> emit(500);
        cudaMemcpy(emit.data(), w.cells.view.emit_power, sizeof(float) * 500,
                   cudaMemcpyDeviceToHost);
        int emitting = 0;
        for (float e : emit) if (e != 0.0f) ++emitting;
        CHECK(emitting == 0);
        world_destroy(w);
    }

    return astro::test::finish("test_stats");
}
