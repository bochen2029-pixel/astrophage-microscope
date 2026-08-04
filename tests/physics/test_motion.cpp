// tests/physics/test_motion.cpp -- the M2 physics oracle. T1-T4, T6, T8.
//
// Every expected value comes from tests/golden/expected_values.h, computed by
// scripts/derive.py from first principles INDEPENDENTLY of the simulator. If
// these disagree, the simulator is wrong -- do not adjust the oracle.
//
// Host-side, exercising the same __host__ __device__ functions the kernels call.
#include <cmath>
#include <cstdio>
#include <vector>

#include "core/canon_generated.h"
#include "golden/expected_values.h"
#include "sim/integrator.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;
namespace ex = astro::expected;

namespace {

constexpr double T_ROOM = canon::AMBIENT_TEMP_DEFAULT;

// Runs a single cell to terminal velocity with noise off, and returns the
// signed y velocity. Sign convention: gravity is along -y, so a sinking cell
// has NEGATIVE vy. The oracle reports settling as positive ("down positive"),
// hence the negation at the call sites.
double terminal_vy(double charge, double emit_power = 0.0, double seconds = 4.0) {
    const double energy = charge * canon::CELL_ENERGY_MAX;
    const double mass = cell_mass(canon::CELL_MASS_DRY, energy);
    const double gamma = drag_coefficient(T_ROOM);
    const Vec3 force = cell_force(mass, emit_power, Vec3{0, 1, 0}, GravityAxis::Y);

    Vec3 pos{0, 0, 0}, vel{0, 0, 0};
    Pcg32 rng = pcg32_seed(1u, 1u);
    const int steps = static_cast<int>(seconds / canon::DT_PHYSICS);
    for (int i = 0; i < steps; ++i)
        integrate_cell(pos, vel, force, mass, gamma, T_ROOM, canon::DT_PHYSICS, false, rng);
    return vel.y;
}

} // namespace

int main() {
    const double gamma = drag_coefficient(T_ROOM);

    // --- the drag coefficient underpins everything below ---------------------
    CHECK_CLOSE(gamma, canon::DRAG_COEFF_20C, 1e-9);
    CHECK_CLOSE(water_viscosity(T_ROOM), canon::WATER_VISCOSITY_20C, 2e-3);
    CHECK_CLOSE(water_viscosity(canon::CELL_TEMP_SETPOINT), canon::WATER_VISCOSITY_SETPOINT, 1e-9);

    // --- T1: a fully charged cell sinks at 1681 um/s -------------------------
    {
        const double vy = terminal_vy(1.0);
        std::printf("  T1 full-cell terminal: %+.1f um/s (sinking)\n", vy * 1e6);
        CHECK(vy < 0.0);                                  // it SINKS
        CHECK_CLOSE(-vy, ex::T1_V_SETTLE_FULL, ex::T1_V_SETTLE_FULL_TOL);
    }

    // --- T2: an empty cell RISES at 52 um/s ----------------------------------
    // This is P1, and it follows from canon mass alone (ADR-002).
    {
        const double vy = terminal_vy(0.0);
        std::printf("  T2 empty-cell terminal: %+.1f um/s (rising)\n", vy * 1e6);
        CHECK(vy > 0.0);                                  // it RISES
        CHECK_CLOSE(-vy, ex::T2_V_RISE_EMPTY, ex::T2_V_RISE_EMPTY_TOL);
    }

    // --- T3: neutral buoyancy at 3.006 % charge ------------------------------
    {
        const double vy = terminal_vy(canon::CHARGE_NEUTRAL_BUOYANCY);
        std::printf("  T3 at %.4f%% charge: %+.4f um/s (hovering)\n",
                    canon::CHARGE_NEUTRAL_BUOYANCY * 100.0, vy * 1e6);
        // Hovering means "negligible next to both extremes", not bitwise zero.
        CHECK(std::fabs(vy) < 1e-3 * ex::T1_V_SETTLE_FULL);
        CHECK_CLOSE(canon::CHARGE_NEUTRAL_BUOYANCY, ex::T3_CHARGE_NEUTRAL, ex::T3_CHARGE_NEUTRAL_TOL);

        // And the sign must actually flip across that line -- the whole mechanic.
        CHECK(terminal_vy(canon::CHARGE_NEUTRAL_BUOYANCY * 0.5) > 0.0);   // rises
        CHECK(terminal_vy(canon::CHARGE_NEUTRAL_BUOYANCY * 2.0) < 0.0);   // sinks
    }

    // --- T4: Einstein diffusion, MSD = 4Dt in 2D -----------------------------
    // The real test of ADR-016. The superseded scheme (propagate velocity, then
    // r += v*dt) overshoots this by 47x for an empty cell.
    {
        const double D = diffusivity(T_ROOM, gamma);
        CHECK_CLOSE(D, ex::T4_DIFFUSIVITY_20C, 1e-9);

        const int n_cells = 4000;
        const double t_total = 1.0;
        const int steps = static_cast<int>(t_total / canon::DT_PHYSICS);
        const double mass = cell_mass(canon::CELL_MASS_DRY, 0.0);

        double msd2d = 0.0;
        for (int c = 0; c < n_cells; ++c) {
            Vec3 pos{0, 0, 0}, vel{0, 0, 0};
            Pcg32 rng = cell_rng(cell_rng_init(20260802ull, static_cast<uint64_t>(c) + 1),
                                 static_cast<uint64_t>(c) + 1);
            for (int i = 0; i < steps; ++i)
                integrate_cell(pos, vel, Vec3{0, 0, 0}, mass, gamma, T_ROOM,
                               canon::DT_PHYSICS, true, rng);
            msd2d += pos.x * pos.x + pos.y * pos.y;
        }
        msd2d /= n_cells;

        const double expect = 4.0 * D * t_total;
        std::printf("  T4 MSD(2D, 1 s) = %.4e m^2, expected 4Dt = %.4e (ratio %.4f)\n",
                    msd2d, expect, msd2d / expect);
        CHECK_CLOSE(msd2d, expect, ex::T4_DIFFUSIVITY_20C_TOL);
        CHECK_CLOSE(std::sqrt(msd2d), ex::T4_RMS_DISP_1S_20C, ex::T4_RMS_DISP_1S_20C_TOL);
    }

    // A charged cell is 800x heavier, so at dt/tau = 5.65 its diffusion is
    // genuinely sub-Einstein within one step. Assert the code reproduces the
    // exact shape function rather than the asymptote.
    {
        const double mass_full = cell_mass(canon::CELL_MASS_DRY, canon::CELL_ENERGY_MAX);
        const double beta = gamma / mass_full;
        const double x = beta * canon::DT_PHYSICS;
        const OuCoefficients c = ou_coefficients(mass_full, gamma, T_ROOM, canon::DT_PHYSICS);
        const double var_direct = (canon::K_BOLTZ * T_ROOM / mass_full) / (beta * beta) *
                                  (2.0 * x - 3.0 + 4.0 * std::exp(-x) - std::exp(-2.0 * x));
        CHECK_CLOSE(c.sigma_rr * c.sigma_rr, var_direct, 1e-9);
        CHECK(c.sigma_rr * c.sigma_rr < 2.0 * diffusivity(T_ROOM, gamma) * canon::DT_PHYSICS);
    }

    // --- the series branch of the shape function -----------------------------
    // Small x is catastrophic cancellation in the direct form; if the series is
    // wrong, a small dt silently yields zero diffusion.
    {
        for (double x : {1e-8, 1e-6, 1e-4, 1e-3, 5e-3}) {
            const double series = ou_position_shape(x);
            const double leading = (2.0 / 3.0) * x * x * x;
            CHECK_CLOSE(series, leading, 1e-2);
            CHECK(series > 0.0);
        }
        // Continuity across the crossover at x = 1e-2: the two branches must
        // agree there, or diffusion jumps when dt or mass drifts past it.
        // The series truncates at x^6, so ~1e-8 residual is expected and is the
        // more accurate of the two at this point -- the direct form has already
        // lost ~4.5 digits to cancellation here.
        const double below = ou_position_shape(1e-2 * (1.0 - 1e-12));
        const double above = ou_position_shape(1e-2 * (1.0 + 1e-12));
        CHECK_CLOSE(below, above, 1e-6);
        // Large x reduces to 2x - 3.
        CHECK_CLOSE(ou_position_shape(50.0), 2.0 * 50.0 - 3.0, 1e-12);
    }

    // --- T6: photon thrust ---------------------------------------------------
    {
        const double F = photon_thrust(1.0e-3);
        CHECK_CLOSE(F, ex::T6_THRUST_1MW, ex::T6_THRUST_1MW_TOL);
        CHECK_CLOSE(terminal_velocity(F, gamma), ex::T6_VTERM_1MW, ex::T6_VTERM_1MW_TOL);

        // Driven end to end: an emitting cell in zero gravity must reach it.
        const double mass = cell_mass(canon::CELL_MASS_DRY, 0.0);
        Vec3 pos{0, 0, 0}, vel{0, 0, 0};
        Pcg32 rng = pcg32_seed(3u, 7u);
        // Emission along +x means recoil along -x.
        const Vec3 force = Vec3{-photon_thrust(1.0e-3), 0.0, 0.0};
        for (int i = 0; i < 4000; ++i)
            integrate_cell(pos, vel, force, mass, gamma, T_ROOM, canon::DT_PHYSICS, false, rng);
        std::printf("  T6 thrust terminal: %.2f um/s\n", -vel.x * 1e6);
        CHECK_CLOSE(-vel.x, ex::T6_VTERM_1MW, ex::T6_VTERM_1MW_TOL);
        CHECK(vel.x < 0.0);
    }

    // A full cell needs 47.6 mW just to hover -- the coincidence ADR-005 rests on.
    {
        const double mass_full = cell_mass(canon::CELL_MASS_DRY, canon::CELL_ENERGY_MAX);
        const double hover_force = -buoyant_weight(mass_full);
        CHECK_CLOSE(hover_force * canon::C_LIGHT, ex::HOVER_POWER_FULL, ex::HOVER_POWER_FULL_TOL);
        CHECK(ex::HOVER_POWER_FULL < canon::PETROVA_MAX_POWER);   // it CAN hover
    }

    // --- T8: Stokes stays valid ---------------------------------------------
    {
        const double v_max = ex::T1_V_SETTLE_FULL;
        const double re = canon::WATER_DENSITY * v_max * canon::CELL_DIAMETER /
                          canon::WATER_VISCOSITY_20C;
        CHECK_CLOSE(re, ex::T8_REYNOLDS_FULL, ex::T8_REYNOLDS_FULL_TOL);
        CHECK(re < 0.1);
    }

    // --- momentum relaxation spans 800x, which is why ADR-016 exists ---------
    {
        const double m_empty = cell_mass(canon::CELL_MASS_DRY, 0.0);
        const double m_full  = cell_mass(canon::CELL_MASS_DRY, canon::CELL_ENERGY_MAX);
        CHECK_CLOSE(m_empty / gamma, ex::TAU_MOMENTUM_EMPTY, ex::TAU_MOMENTUM_EMPTY_TOL);
        CHECK_CLOSE(m_full / gamma, ex::TAU_MOMENTUM_FULL, ex::TAU_MOMENTUM_FULL_TOL);
        CHECK(m_full / m_empty > 700.0);
    }

    // --- boundaries ----------------------------------------------------------
    {
        const double half = 0.5 * canon::CHAMBER_H;
        const double a = canon::CELL_RADIUS;

        // Reflecting: the cell rests against the wall. At Re << 1 there is no
        // inertia to bounce with, so the normal velocity must go to zero, not
        // reverse -- a mirror bounce would inject energy that does not exist.
        double p = -half - 1e-6, v = -1.0;
        CHECK(apply_boundary_axis(p, v, half, a, Boundary::Reflecting));
        CHECK_CLOSE(p, -half + a, 1e-12);
        CHECK(v == 0.0);

        // Periodic wraps and preserves velocity.
        p = half + 1e-5; v = 2.0;
        CHECK(apply_boundary_axis(p, v, half, a, Boundary::Periodic));
        CHECK(p < half && p > -half);
        CHECK(v == 2.0);

        // Absorbing reports the cell gone.
        p = half + 1e-5; v = 2.0;
        CHECK(!apply_boundary_axis(p, v, half, a, Boundary::Absorbing));

        // Interior positions are untouched by every mode.
        for (Boundary m : {Boundary::Reflecting, Boundary::Periodic, Boundary::Absorbing}) {
            p = 0.25 * half; v = 0.5;
            CHECK(apply_boundary_axis(p, v, half, a, m));
            CHECK_CLOSE(p, 0.25 * half, 1e-15);
            CHECK(v == 0.5);
        }
    }

    // --- containment: no cell escapes over a long run ------------------------
    {
        const double half = 0.5 * canon::CHAMBER_H;
        const double mass = cell_mass(canon::CELL_MASS_DRY, canon::CELL_ENERGY_MAX);
        Vec3 pos{0, 0, 0}, vel{0, 0, 0};
        Pcg32 rng = pcg32_seed(11u, 13u);
        const Vec3 force = cell_force(mass, 0.0, Vec3{0, 0, 1}, GravityAxis::Y);
        bool escaped = false;
        for (int i = 0; i < 200000; ++i) {   // 200 s: 100x the fall time
            integrate_cell(pos, vel, force, mass, gamma, T_ROOM, canon::DT_PHYSICS, true, rng);
            apply_boundary_axis(pos.y, vel.y, half, canon::CELL_RADIUS, Boundary::Reflecting);
            if (pos.y < -half || pos.y > half) escaped = true;
            if (!std::isfinite(pos.y) || !std::isfinite(vel.y)) escaped = true;
        }
        CHECK(!escaped);
        CHECK_CLOSE(pos.y, -half + canon::CELL_RADIUS, 1e-6);   // settled on the floor
    }

    // --- optical tweezers: the trap pulls a cell to its target (M13b) --------
    {
        // Direction: the force on an offset cell points toward the target, in-plane only.
        const Vec3 f = trap_force(Vec3{0, 0, 0}, 100e-6, -50e-6, canon::CONTACT_STIFFNESS);
        CHECK(f.x > 0.0);          // target is +x of the cell
        CHECK(f.y < 0.0);          // target is -y of the cell
        CHECK(f.z == 0.0);         // z is left to buoyancy -- the trap is in-plane

        // Convergence: under the trap alone (noise off), a near-neutral cell reaches the target.
        // (Behaviour with buoyancy and a real population is covered by the --auto-grab gate.)
        const double tx = 500e-6, ty = -300e-6;
        const double mass = cell_mass(canon::CELL_MASS_DRY,
                                      canon::CHARGE_NEUTRAL_BUOYANCY * canon::CELL_ENERGY_MAX);
        const double k = 2.0 * canon::CONTACT_STIFFNESS;   // the app's default trap_strength range
        Vec3 pos{0, 0, 0}, vel{0, 0, 0};
        Pcg32 rng = pcg32_seed(7u, 9u);
        for (int i = 0; i < 4000; ++i)
            integrate_cell(pos, vel, trap_force(pos, tx, ty, k), mass, gamma, T_ROOM,
                           canon::DT_PHYSICS, false, rng);
        std::printf("  trap: cell at (%+.1f, %+.1f) um, target (%+.1f, %+.1f) um\n",
                    pos.x * 1e6, pos.y * 1e6, tx * 1e6, ty * 1e6);
        CHECK_CLOSE(pos.x, tx, 1e-6);
        CHECK_CLOSE(pos.y, ty, 1e-6);
    }

    return astro::test::finish("test_motion");
}
