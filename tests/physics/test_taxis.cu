// tests/physics/test_taxis.cu -- T26. Run-and-tumble taxis, the darkness rule,
// and the emission energy ledger. docs/PHYSICS.md Sec 8, ADR-007, ADR-022.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "golden/expected_values.h"
#include "sim/taxis.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;
namespace ex = astro::expected;

namespace {

struct Run {
    std::vector<double> x, y, z;
    std::vector<float>  emit;
    std::vector<float>  run_timer;
    double mean_x = 0.0, sd_x = 0.0;
};

// A culture lit along +x. The source sits at the -x boundary, so irradiance is
// highest at low x and attenuates with depth -- cells that climb it migrate
// toward -x. Charge sits at neutral buoyancy so sedimentation cannot masquerade
// as taxis: the only systematic force is thrust.
Error make_lit_world(World& w, int32_t n, bool taxis_on, float irradiance) {
    WorldDesc d;
    d.capacity = n;
    d.seed = 20260802ull;
    d.motion.taxis_enabled = taxis_on;
    ASTRO_TRY(world_create(w, d));
    w.light = contract::LightSource{1.0f, 0.0f, irradiance,
                                    static_cast<float>(canon::PETROVA_WAVELENGTH),
                                    static_cast<uint8_t>(irradiance > 0.0f ? 1 : 0)};
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = canon::CHARGE_NEUTRAL_BUOYANCY;
    p.awake = true;                       // dormant cells do not taxis (M8 gate)
    return cell_store_spawn(w.cells, p, w.chamber, d.seed);
}

Run advance(World& w, int ticks) {
    for (int t = 0; t < ticks; ++t) world_step(w);
    const int32_t n = w.cells.count;
    Run r;
    r.x.resize(n); r.y.resize(n); r.z.resize(n); r.emit.resize(n); r.run_timer.resize(n);
    cell_store_download_positions(w.cells, r.x.data(), r.y.data(), r.z.data(), n);
    cudaMemcpy(r.emit.data(), w.cells.view.emit_power, sizeof(float) * n,
               cudaMemcpyDeviceToHost);
    cudaMemcpy(r.run_timer.data(), w.cells.view.run_timer, sizeof(float) * n,
               cudaMemcpyDeviceToHost);
    for (double v : r.x) r.mean_x += v;
    r.mean_x /= n;
    for (double v : r.x) r.sd_x += (v - r.mean_x) * (v - r.mean_x);
    r.sd_x = std::sqrt(r.sd_x / n);
    return r;
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_taxis: no CUDA device; skipping\n");
        return 0;
    }

    // --- T26.2: the temporal lag is exact -----------------------------------
    {
        // A step input must reach 1 - 1/e at exactly TAXIS_MEMORY_TIME, whatever
        // dt is. That is the property that makes "memory time" mean what it says,
        // and it is why the update uses the exact discretisation rather than the
        // Euler approximation alpha = dt/tau.
        for (double dt : {1.0e-3, 1.0e-2, 1.0e-1}) {
            float ema = 0.0f;
            const int steps = static_cast<int>(canon::TAXIS_MEMORY_TIME / dt + 0.5);
            for (int i = 0; i < steps; ++i) ema = taxis_ema_update(ema, 1.0, dt);
            CHECK_CLOSE(ema, ex::T26_EMA_STEP_RESPONSE, 1e-5);
        }
        // A constant signal drives delta to zero, which is what forces a tumble.
        float ema = 0.0f;
        for (int i = 0; i < 20000; ++i) ema = taxis_ema_update(ema, 1.0, 1.0e-3);
        CHECK(std::fabs(1.0 - ema) < 1e-4);
    }

    // --- T26.3: the state machine -------------------------------------------
    {
        const double lit = 10.0 * canon::TAXIS_DARK_THRESHOLD;
        const double dark = 0.5 * canon::TAXIS_DARK_THRESHOLD;
        CHECK(taxis_select_state(0.5, lit, 0.0) == TaxisState::Feed);
        CHECK(taxis_select_state(0.99, lit, 1.0) == TaxisState::Breed);
        // Between the thresholds: charged enough not to feed, no CO2 to breed on.
        CHECK(taxis_select_state(0.96, lit, 0.0) == TaxisState::Idle);
        CHECK(taxis_select_state(0.99, lit, 0.0) == TaxisState::Idle);
        // Darkness with nothing to smell: idle regardless of charge. Feed
        // additionally requires light -- the documented deviation from Sec 8's
        // pseudocode, which would otherwise burn store climbing a gradient that
        // does not exist (ADR-022).
        CHECK(taxis_select_state(0.5, dark, 0.0) == TaxisState::Idle);
        CHECK(taxis_select_state(0.5, dark, 1.0) == TaxisState::Idle);
        // A charged cell in the dark can still follow CO2.
        CHECK(taxis_select_state(0.99, dark, 1.0) == TaxisState::Breed);
        // Emission is exactly zero when idle, not merely small.
        CHECK(taxis_emit_power(TaxisState::Idle, canon::CELL_ENERGY_MAX, 1e-3) == 0.0);
        CHECK(taxis_emit_power(TaxisState::Feed, canon::CELL_ENERGY_MAX, 1e-3)
              == canon::PETROVA_MAX_POWER);
        // An almost-empty cell cannot emit more than it holds.
        CHECK(taxis_emit_power(TaxisState::Feed, 1.0e-9, 1e-3) < canon::PETROVA_MAX_POWER);
        CHECK(taxis_emit_power(TaxisState::Feed, 0.0, 1e-3) == 0.0);
    }

    // --- T26.1: the sign convention -----------------------------------------
    {
        // cell_force does `f -= emit_dir * thrust`, so a cell that wants to travel
        // along +x must aim its emission along -x. This is the error that silently
        // produces a culture migrating AWAY from the light, so assert it directly.
        const Vec3 heading{1.0, 0.0, 0.0};
        const Vec3 axis = taxis_emit_dir(heading);
        CHECK_CLOSE(axis.x, -1.0, 1e-12);
        CHECK(std::fabs(axis.y) < 1e-12 && std::fabs(axis.z) < 1e-12);
        // ... and that the resulting force really is +x.
        const Vec3 f = cell_force(canon::CELL_MASS_DRY, canon::PETROVA_MAX_POWER,
                                  axis, GravityAxis::Y);
        CHECK(f.x > 0.0);
        CHECK_CLOSE(f.x, canon::PETROVA_MAX_POWER / canon::C_LIGHT, 1e-9);
    }

    // --- T26.5: the tumble ---------------------------------------------------
    {
        Pcg32 rng = cell_rng(cell_rng_init(20260802ull, 7ull), 7ull);
        double sum = 0.0, worst_unit = 0.0;
        const int N = 200000;
        Vec3 h{1.0, 0.0, 0.0};
        for (int i = 0; i < N; ++i) {
            const Vec3 next = taxis_tumble(h, rng);
            const double off = std::fabs(length(next) - 1.0);
            if (off > worst_unit) worst_unit = off;
            double c = dot(normalize(h), next);
            c = c > 1.0 ? 1.0 : (c < -1.0 ? -1.0 : c);
            sum += std::acos(c);
            h = next;
        }
        // Every tumble yields a unit vector -- asserted once on the worst case
        // rather than 200k times, so the check count stays meaningful.
        CHECK(worst_unit < 1e-12);
        const double mean = sum / N;
        std::printf("  mean tumble angle %.2f deg (clamped expectation %.2f deg)\n",
                    mean * 180.0 / PI, ex::T26_TUMBLE_MEAN_CLAMPED * 180.0 / PI);
        CHECK_CLOSE(mean, ex::T26_TUMBLE_MEAN_CLAMPED, ex::T26_TUMBLE_MEAN_CLAMPED_TOL);
        // The run cap is what stops a cell that outruns its own halo (ADR-022).
        CHECK(taxis_should_tumble(1.0, canon::TAXIS_RUN_MAX) == true);
        CHECK(taxis_should_tumble(1.0, 0.5 * canon::TAXIS_RUN_MAX) == false);
        CHECK(taxis_should_tumble(-1.0, 0.0) == true);
        CHECK(taxis_should_tumble(0.0, 0.0) == true);
        CHECK(canon::TAXIS_RUN_MAX > canon::TAXIS_MEMORY_TIME);
    }

    // --- T26.6: emission debits the store ------------------------------------
    {
        // Nothing subtracted emit_power * dt from `energy` before M8, because
        // nothing ever set emit_power nonzero. Thermal is off so the only two
        // terms are absorption and emission.
        World w{};
        WorldDesc d;
        d.capacity = 64;
        d.motion.thermal_enabled = false;
        d.motion.contact_enabled = false;
        d.motion.adhesion_enabled = false;
        CHECK(!world_create(w, d));
        w.light = contract::LightSource{1.0f, 0.0f, 1.0e3f,
                                        static_cast<float>(canon::PETROVA_WAVELENGTH), 1u};
        SpawnParams p;
        p.count = 64;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Constant;
        p.charge_a = 0.5;
        p.awake = true;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));

        std::vector<double> e0(64), e1(64);
        cell_store_download_energy(w.cells, e0.data(), 64);
        const int ticks = 100;
        for (int t = 0; t < ticks; ++t) world_step(w);
        cell_store_download_energy(w.cells, e1.data(), 64);

        // Absorption is 7.85e-8 W against 50 mW emitted, so the ledger is
        // dominated by emission but is asserted including both terms.
        double worst = 0.0;
        for (int i = 0; i < 64; ++i) {
            const double drop = e0[i] - e1[i];
            const double expect = canon::PETROVA_MAX_POWER * canon::DT_PHYSICS * ticks;
            const double rel = std::fabs(drop - expect) / expect;
            if (rel > worst) worst = rel;
        }
        std::printf("  emission ledger: worst relative error %.3e over %d ticks\n",
                    worst, ticks);
        CHECK(worst < 1.0e-5);
        world_destroy(w);
    }

    // --- T26.8 (GATE): the darkness rule -------------------------------------
    {
        // With no source and no ambient the Idle path draws no random numbers, so
        // a taxis-enabled run and the taxis-disabled null are BIT-IDENTICAL, not
        // merely similar. Canon: Astrophage does not move in darkness.
        World on{}, off{};
        CHECK(!make_lit_world(on, 2000, true, 0.0f));
        CHECK(!make_lit_world(off, 2000, false, 0.0f));
        const Run a = advance(on, 2000);
        const Run b = advance(off, 2000);

        int emitting = 0, differing = 0;
        for (size_t i = 0; i < a.x.size(); ++i) {
            if (a.emit[i] != 0.0f) ++emitting;
            if (a.x[i] != b.x[i] || a.y[i] != b.y[i] || a.z[i] != b.z[i]) ++differing;
        }
        std::printf("  darkness: %d cells emitting, %d positions differing from the null\n",
                    emitting, differing);
        CHECK(emitting == 0);
        CHECK(differing == 0);
        world_destroy(on);
        world_destroy(off);
    }

    // --- T26.7 (GATE): migration up the gradient -----------------------------
    {
        // The gradient is the culture's own shadow: Beer-Lambert on the grid plus
        // exact per-cell occlusion (ADR-021). The lit face is flat -- full
        // irradiance, no gradient -- so a cell that arrives stops sensing
        // anything, which is correct but means the metric must be population mean
        // depth, not a per-cell climbing rate.
        const int32_t N = 8000;
        const int ticks = 10000;
        World on{}, off{};
        CHECK(!make_lit_world(on, N, true, 1.0e3f));
        CHECK(!make_lit_world(off, N, false, 1.0e3f));
        const Run a = advance(on, ticks);
        const Run b = advance(off, ticks);

        // sigma of the NULL's mean, i.e. its standard error -- the right scale for
        // "could this shift have happened without the controller".
        const double se = b.sd_x / std::sqrt(static_cast<double>(N));
        const double shift = a.mean_x - b.mean_x;
        std::printf("  migration: mean x %.1f um (taxis) vs %.1f um (null), "
                    "shift %.1f um = %.1f sigma\n",
                    a.mean_x * 1e6, b.mean_x * 1e6, shift * 1e6, shift / se);
        // Light travels +x from the -x boundary, so irradiance falls with x and a
        // phototactic population moves toward -x. The sign is the assertion.
        CHECK(shift < 0.0);
        CHECK(std::fabs(shift) > 3.0 * se);

        // Diagnostic, not an assertion: what regime is the controller actually
        // in? `run_timer` is the age of the current run, so its distribution
        // reads the tumble rate directly. Reorientation costs no time at M8
        // (Q16), so a cell can tumble on consecutive ticks -- this reports how
        // often that actually happens rather than leaving it to argument.
        double mean_run = 0.0;
        int just_tumbled = 0;
        for (float t : a.run_timer) {
            mean_run += t;
            if (t <= 2.0f * static_cast<float>(canon::DT_PHYSICS)) ++just_tumbled;
        }
        mean_run /= a.run_timer.size();
        std::printf("  runs: mean age %.3f s (cap %.1f s), %.1f%% of cells tumbled "
                    "within the last 2 ticks\n",
                    mean_run, canon::TAXIS_RUN_MAX,
                    100.0 * just_tumbled / a.run_timer.size());
        world_destroy(on);
        world_destroy(off);
    }

    // --- T26.4: dormant cells are inert powder -------------------------------
    {
        World w{};
        WorldDesc d;
        d.capacity = 1000;
        CHECK(!world_create(w, d));
        w.light = contract::LightSource{1.0f, 0.0f, 1.0e3f,
                                        static_cast<float>(canon::PETROVA_WAVELENGTH), 1u};
        SpawnParams p;
        p.count = 1000;
        p.placement = Placement::Uniform;
        p.charge_dist = Distribution::Constant;
        p.charge_a = 0.5;
        p.awake = false;
        CHECK(!cell_store_spawn(w.cells, p, w.chamber, d.seed));
        const Run r = advance(w, 500);
        int emitting = 0;
        for (float e : r.emit) if (e != 0.0f) ++emitting;
        std::printf("  dormant: %d of %zu cells emitting\n", emitting, r.emit.size());
        CHECK(emitting == 0);
        world_destroy(w);
    }

    return astro::test::finish("test_taxis");
}
