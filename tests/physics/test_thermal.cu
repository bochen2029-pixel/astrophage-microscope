// tests/physics/test_thermal.cu -- P2, P3, P4. T5, T7, T9, T10, T11, T12, T19.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "fields/grid.cuh"
#include "golden/expected_values.h"
#include "sim/thermal.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;
namespace ex = astro::expected;

namespace {

struct Stat { double mean, max, min; };

Stat field_stats(const World& w) {
    const auto& g = w.fields.temperature;
    std::vector<float> v(static_cast<size_t>(g.n) * g.n);
    fields::grid_download(g, v.data());
    Stat s{0.0, -1e30, 1e30};
    for (float f : v) {
        s.mean += f;
        if (f > s.max) s.max = f;
        if (f < s.min) s.min = f;
    }
    s.mean /= v.size();
    return s;
}

double total_cell_energy(const World& w) {
    std::vector<double> e(static_cast<size_t>(w.cells.count));
    cell_store_download_energy(w.cells, e.data(), w.cells.count);
    double s = 0.0;
    for (double v : e) s += v;
    return s;
}

int count_flag(const World& w, uint32_t flag) {
    std::vector<uint32_t> f(static_cast<size_t>(w.cells.count));
    cudaMemcpy(f.data(), w.cells.view.flags, sizeof(uint32_t) * f.size(),
               cudaMemcpyDeviceToHost);
    int n = 0;
    for (uint32_t v : f) if (v & flag) ++n;
    return n;
}

Error make_world(World& w, int32_t n, double charge, bool awake, double ambient) {
    WorldDesc d;
    d.capacity = n;
    d.seed = 20260802ull;
    d.motion.ambient_temp = ambient;
    d.motion.contact_enabled = false;    // isolating the thermal behaviour
    d.motion.adhesion_enabled = false;
    ASTRO_TRY(world_create(w, d));
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = charge;
    p.awake = awake;
    return cell_store_spawn(w.cells, p, w.chamber, d.seed);
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_thermal: no CUDA device; skipping\n");
        return 0;
    }
    const double T_ROOM = canon::AMBIENT_TEMP_DEFAULT;

    // --- T7: conduction, and the shell conductance is self-consistent --------
    {
        CHECK_CLOSE(conduction_power(canon::CELL_TEMP_SETPOINT, T_ROOM),
                    ex::T7_CONDUCTION_20C, ex::T7_CONDUCTION_20C_TOL);
        CHECK_CLOSE(canon::CELL_ENERGY_MAX / conduction_power(canon::CELL_TEMP_SETPOINT, T_ROOM),
                    ex::T7_ENDURANCE_20C, ex::T7_ENDURANCE_20C_TOL);

        // The whole justification for the shell form: substituting the analytic
        // profile T(R) = T_inf + dT*a/R must return exactly the free-space flux.
        const double dx = canon::CHAMBER_W / canon::FIELD_N_TEMP;
        const double G = shell_conductance(dx);
        const double t_at_dx = near_field_temperature(canon::CELL_TEMP_SETPOINT, T_ROOM, dx);
        std::printf("  shell conductance %.4e W/K, grid steady state %.1f K (%.1f C)\n",
                    G, t_at_dx, t_at_dx - 273.15);
        CHECK_CLOSE(G * (canon::CELL_TEMP_SETPOINT - t_at_dx),
                    conduction_power(canon::CELL_TEMP_SETPOINT, T_ROOM), 1e-9);
        CHECK(G > canon::CONDUCTION_COEFF);       // shorter path, higher conductance
        CHECK(t_at_dx < canon::WATER_BOILING_POINT);

        // The analytic near field, quoted in VERIFICATION.md Sec 5.
        const double a = canon::CELL_RADIUS;
        CHECK_CLOSE(near_field_temperature(canon::CELL_TEMP_SETPOINT, T_ROOM, 2 * a) - T_ROOM,
                    38.2, 1e-2);
        CHECK_CLOSE(near_field_temperature(canon::CELL_TEMP_SETPOINT, T_ROOM, 10 * a) - T_ROOM,
                    7.64, 1e-2);
    }

    // --- the lumped exchange cannot overshoot (the second law, not a clamp) ---
    {
        const double C = 1.0e-8, G = 1.0e-4;
        // Even over an absurd dt the medium only approaches the cell temperature.
        for (double dt : {1e-6, 1e-3, 1.0, 1e3}) {
            const double e = lumped_exchange_energy(370.0, 293.0, G, C, dt);
            const double t_new = 293.0 + e / C;
            CHECK(t_new <= 370.0 + 1e-9);
            CHECK(t_new >= 293.0 - 1e-9);
        }
        // Reversed: a hotter medium gives the cell energy, not the reverse.
        CHECK(lumped_exchange_energy(293.0, 370.0, G, C, 1e-3) < 0.0);
        // Small dt reduces to the explicit rate, short by the second-order term
        // of 1 - exp(-x): the deficit is x/2 = G*dt/(2C), which is the whole
        // point of using the exponential rather than the explicit form.
        const double dt = 1e-9;
        const double x = G * dt / C;
        CHECK_CLOSE(lumped_exchange_energy(370.0, 293.0, G, C, dt) / dt,
                    G * 77.0 * (1.0 - 0.5 * x), 1e-9);
        CHECK_CLOSE(lumped_exchange_energy(370.0, 293.0, G, C, dt) / dt, G * 77.0, 1e-4);
    }

    // --- T5: mass-energy bookkeeping ----------------------------------------
    {
        CHECK_CLOSE(cell_mass(canon::CELL_MASS_DRY, canon::CELL_ENERGY_MAX) -
                    canon::CELL_MASS_DRY, ex::T5_DELTA_MASS_FULL, ex::T5_DELTA_MASS_FULL_TOL);
    }

    // --- T3/P3: the ignition latch, and that it survives cooling -------------
    {
        World w;
        CHECK(!make_world(w, 2000, 0.5, /*awake=*/false, T_ROOM));
        CHECK(count_flag(w, contract::CELL_FLAG_AWAKE) == 0);

        // Cold: nothing wakes, however long you wait.
        for (int t = 0; t < 2000; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(count_flag(w, contract::CELL_FLAG_AWAKE) == 0);

        // Heat the whole chamber past the setpoint.
        CHECK(!fields::grid_fill(w.fields.temperature,
                                 static_cast<float>(canon::CELL_TEMP_SETPOINT + 2.0)));
        for (int t = 0; t < 50; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        const int awake_hot = count_flag(w, contract::CELL_FLAG_AWAKE);
        std::printf("  ignition: %d of 2000 awake after crossing the setpoint\n", awake_hot);
        CHECK(awake_hot == 2000);

        // Now chill it hard. P3: the latch is one-way.
        CHECK(!fields::grid_fill(w.fields.temperature, static_cast<float>(T_ROOM)));
        for (int t = 0; t < 5000; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(count_flag(w, contract::CELL_FLAG_AWAKE) == 2000);
        std::printf("  latch survived cooling to %.1f C: still 2000 awake\n", T_ROOM - 273.15);
        world_destroy(w);
    }

    // --- T9 / T19 / P2: the medium pins to the setpoint and never boils ------
    {
        World w;
        WorldDesc d;
        d.capacity = 2000;
        d.motion.ambient_temp = T_ROOM;
        d.motion.contact_enabled = false;
        d.motion.adhesion_enabled = false;
        CHECK(!world_create(w, d));
        // Insulated, so nothing escapes and the asymptote is unambiguous.
        w.fields.temperature.bc = contract::BoundaryCondition::Neumann;
        SpawnParams p;
        p.count = 2000;
        p.charge_dist = Distribution::Constant;
        p.charge_a = 1.0;
        p.awake = true;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, 5ull));

        double worst_max = -1e30;
        for (int t = 0; t < 60000; ++t) {          // 60 s
            world_step(w);
            if (t % 5000 == 0) {
                CHECK(cudaDeviceSynchronize() == cudaSuccess);
                const Stat s = field_stats(w);
                if (s.max > worst_max) worst_max = s.max;
            }
        }
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        const Stat s = field_stats(w);
        if (s.max > worst_max) worst_max = s.max;
        std::printf("  60 s insulated, 2000 awake cells: mean %.2f K, max %.2f K "
                    "(setpoint %.3f, boiling %.2f)\n",
                    s.mean, worst_max, canon::CELL_TEMP_SETPOINT, canon::WATER_BOILING_POINT);

        // P2. The medium may not exceed the setpoint, and therefore cannot boil.
        CHECK(worst_max <= canon::CELL_TEMP_SETPOINT + 0.2);
        CHECK(worst_max < canon::WATER_BOILING_POINT);
        CHECK(s.mean > T_ROOM);                    // it did heat up
        CHECK(std::isfinite(s.mean));
        world_destroy(w);
    }

    // --- T10: driven above the setpoint, cells ABSORB and pull it back -------
    {
        World w;
        CHECK(!make_world(w, 2000, 0.5, /*awake=*/true, T_ROOM));
        w.fields.temperature.bc = contract::BoundaryCondition::Neumann;
        // Drive the whole chamber to 400 K -- well past the setpoint.
        CHECK(!fields::grid_fill(w.fields.temperature, 400.0f));
        const double e0 = total_cell_energy(w);

        for (int t = 0; t < 20000; ++t) world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        const Stat s = field_stats(w);
        const double e1 = total_cell_energy(w);
        std::printf("  driven to 400 K: relaxed to mean %.2f K, cell energy %.4g -> %.4g J "
                    "(+%.2f%%)\n", s.mean, e0, e1, (e1 - e0) / e0 * 100.0);
        CHECK(s.mean < 400.0);        // it came down
        CHECK(e1 > e0);               // and the cells took the heat as neutrino mass
        world_destroy(w);
    }

    // --- T12 / P4: live cells are more mobile than dead ones -----------------
    // Only the SURFACE-temperature choice reproduces the oracle (ADR-020).
    {
        CHECK_CLOSE(viscosity_temperature(true, T_ROOM), canon::CELL_TEMP_SETPOINT, 1e-12);
        CHECK_CLOSE(viscosity_temperature(false, T_ROOM), T_ROOM, 1e-12);
        const double d_live = diffusivity(viscosity_temperature(true, T_ROOM),
                                          drag_coefficient(viscosity_temperature(true, T_ROOM)));
        const double d_dead = diffusivity(T_ROOM, drag_coefficient(T_ROOM));
        std::printf("  motility ratio live/dead = %.3f (oracle %.3f)\n",
                    d_live / d_dead, ex::T12_MOTILITY_RATIO);
        CHECK_CLOSE(d_live / d_dead, ex::T12_MOTILITY_RATIO, ex::T12_MOTILITY_RATIO_TOL);
        CHECK(d_live / d_dead > 3.5);
    }

    // --- starvation ----------------------------------------------------------
    // A cell that cannot hold its setpoint dies. With a nearly empty store in
    // cold water that should happen quickly.
    {
        // Endurance is store / conduction rate, so size the run from that rather
        // than guessing: at 1e-9 charge a cell holds 1.5 mJ and sheds 2.871 mW,
        // giving 0.52 s. Three seconds is comfortably past it.
        const double charge = 1.0e-9;
        const double endurance = charge * canon::CELL_ENERGY_MAX /
                                 conduction_power(canon::CELL_TEMP_SETPOINT, T_ROOM);
        World w;
        CHECK(!make_world(w, 500, charge, /*awake=*/true, T_ROOM));
        const int ticks = static_cast<int>(6.0 * endurance / canon::DT_PHYSICS);
        for (int t = 0; t < ticks; ++t) {
            // An infinite cold reservoir, re-imposed every tick. A Dirichlet
            // boundary is not enough: it pins only the chamber edge, and 500
            // cells warm the interior to the setpoint within a second, at which
            // point Q -> 0 and they stop spending. That is P2 doing its job --
            // correct, but it means an ordinary chamber cannot starve a culture,
            // so isolating the starvation path needs a perfect bath.
            fields::grid_fill(w.fields.temperature, static_cast<float>(T_ROOM));
            world_step(w);
        }
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        const int alive = count_flag(w, contract::CELL_FLAG_ALIVE);
        std::printf("  starvation: endurance %.2f s, ran %.2f s, %d of 500 still alive\n",
                    endurance, ticks * canon::DT_PHYSICS, alive);
        CHECK(alive == 0);
        world_destroy(w);
    }

    // --- determinism survives the thermal stage (INV-8) ----------------------
    {
        double e[2];
        for (int run = 0; run < 2; ++run) {
            World w;
            CHECK(!make_world(w, 1500, 0.5, true, T_ROOM));
            for (int t = 0; t < 3000; ++t) world_step(w);
            CHECK(cudaDeviceSynchronize() == cudaSuccess);
            e[run] = total_cell_energy(w);
            world_destroy(w);
        }
        CHECK(e[0] == e[1]);
    }

    return astro::test::finish("test_thermal");
}
