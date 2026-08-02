// src/sim/integrator.cuh -- motion. docs/PHYSICS.md Sec 3 and Sec 4.
//
// Everything here is __host__ __device__ and pure, so tests/physics/test_motion
// exercises the real code path on the host against the independently-computed
// oracle in docs/VERIFICATION.md (ARCHITECTURE.md Sec 3.3).
//
// READ PHYSICS.md Sec 3.1 BEFORE CHANGING ANY OF THIS. The 800x mass spread
// between an empty and a fully charged cell rules out every simpler scheme:
// a naive overdamped update is wrong for charged cells, Verlet-with-drag is
// unstable for empty ones, and propagating velocity alone then writing
// r += v*dt gives 47x too much diffusion (ADR-016).
#pragma once

#include <cmath>

#include "core/canon_generated.h"
#include "core/rng.cuh"
#include "core/units.h"
#include "core/vec.cuh"

namespace astro::sim {

// ---------------------------------------------------------------------------
// Material and cell properties
// ---------------------------------------------------------------------------

// Vogel-Fulcher viscosity of water. Temperature dependence is not a refinement:
// it is what makes live cells visibly more mobile than dead ones (P4).
ASTRO_HD inline double water_viscosity(double t_kelvin) {
    return canon::VF_A * exp(canon::VF_B / (t_kelvin - canon::VF_C));
}

// Stokes drag coefficient. Scales with size, NOT mass -- which is why a charged
// cell and an empty one share a gamma but differ 800x in relaxation time.
ASTRO_HD inline double drag_coefficient(double t_kelvin) {
    return 6.0 * PI * water_viscosity(t_kelvin) * canon::CELL_RADIUS;
}

// The most consequential line in the codebase (PHYSICS.md Sec 4).
// Never store this -- an accumulating mass field drifts and silently breaks the
// energy ledger.
ASTRO_HD inline double cell_mass(double biomass, double energy) {
    return biomass + energy / (canon::C_LIGHT * canon::C_LIGHT);
}

ASTRO_HD inline double cell_density(double mass) { return mass / canon::CELL_VOLUME; }

// Archimedes. CELL_VOLUME is constant: an enriched cell gains MASS, not volume,
// because the neutrino store has no volume. This term alone produces P1.
// Returns a signed magnitude along the gravity axis; negative = downward.
ASTRO_HD inline double buoyant_weight(double mass) {
    return -(mass - canon::WATER_DENSITY * canon::CELL_VOLUME) * canon::G_ACCEL;
}

ASTRO_HD inline double photon_thrust(double emit_power) {
    return emit_power / canon::C_LIGHT;
}

// Terminal velocity under a constant force. Signed, along the force.
ASTRO_HD inline double terminal_velocity(double force, double gamma) {
    return force / gamma;
}

// Einstein-Stokes. Emergent, never hardcoded -- test T4 checks the simulation
// reproduces it rather than reading it back.
ASTRO_HD inline double diffusivity(double t_kelvin, double gamma) {
    return canon::K_BOLTZ * t_kelvin / gamma;
}

// ---------------------------------------------------------------------------
// The exact Ornstein-Uhlenbeck propagator (ADR-016)
// ---------------------------------------------------------------------------

// g(x) = 2x - 3 + 4e^-x - e^-2x, the position-variance shape function.
//
// The first three orders cancel EXACTLY, so for small x the direct form is
// catastrophic cancellation and returns garbage (or zero) instead of the true
// (2/3)x^3. Getting this wrong gives an empty cell zero diffusion at small dt,
// silently. The crossover and both branches are pinned by test_motion.
ASTRO_HD inline double ou_position_shape(double x) {
    if (x < 1.0e-2) {
        // (2/3)x^3 - (1/2)x^4 + (7/30)x^5 - (1/12)x^6 - ...
        // Coefficient of x^n is 4(-1)^n/n! - (-2)^n/n!, which vanishes for
        // n < 3. Truncating at x^6 leaves ~1e-8 relative error at the crossover,
        // where the direct form still retains ~11 significant digits.
        const double x3 = x * x * x;
        return x3 * (2.0 / 3.0 + x * (-0.5 + x * (7.0 / 30.0 + x * (-1.0 / 12.0))));
    }
    const double e = exp(-x);
    return 2.0 * x - 3.0 + 4.0 * e - e * e;
}

struct OuCoefficients {
    double e1;            // exp(-x)
    double one_minus_e1;  // computed with expm1
    double inv_beta;      // 1/beta = tau = mass/gamma
    double sigma_rr;      // position noise stdev
    double sigma_vv;      // velocity noise stdev
    double sigma_rv;      // position-velocity covariance
};

// x = beta*dt = gamma*dt/mass = dt/tau.
ASTRO_HD inline OuCoefficients ou_coefficients(double mass, double gamma,
                                              double t_kelvin, double dt) {
    const double beta = gamma / mass;
    const double x = beta * dt;

    OuCoefficients c;
    c.one_minus_e1 = -expm1(-x);
    c.e1 = 1.0 - c.one_minus_e1;
    c.inv_beta = 1.0 / beta;

    const double kT_over_m = canon::K_BOLTZ * t_kelvin / mass;
    const double var_vv = kT_over_m * (-expm1(-2.0 * x));
    const double var_rr = kT_over_m * c.inv_beta * c.inv_beta * ou_position_shape(x);

    c.sigma_vv = sqrt(var_vv > 0.0 ? var_vv : 0.0);
    c.sigma_rr = sqrt(var_rr > 0.0 ? var_rr : 0.0);
    c.sigma_rv = kT_over_m * c.inv_beta * c.one_minus_e1 * c.one_minus_e1;
    return c;
}

// One axis of the joint propagator. `force` is the constant force on this axis.
// z1, z2 are independent standard normals.
//
// Position and velocity noise are CORRELATED; the 2x2 Cholesky below is not
// optional. Dropping it breaks fluctuation-dissipation balance.
ASTRO_HD inline void ou_advance_axis(double& pos, double& vel, double force,
                                     double gamma, const OuCoefficients& c,
                                     double dt, bool thermal_noise,
                                     double z1, double z2) {
    const double v_term = force / gamma;

    // Deterministic part. Position uses the PRE-step velocity, integrated
    // exactly over the interval -- not the post-step velocity times dt.
    const double dpos = v_term * dt + (vel - v_term) * c.one_minus_e1 * c.inv_beta;
    double dvel = (v_term - vel) * c.one_minus_e1;

    double npos = pos + dpos;
    double nvel = vel + dvel;

    if (thermal_noise && c.sigma_rr > 0.0) {
        const double a = c.sigma_rv / c.sigma_rr;
        const double b2 = c.sigma_vv * c.sigma_vv - a * a;
        const double b = sqrt(b2 > 0.0 ? b2 : 0.0);
        npos += c.sigma_rr * z1;
        nvel += a * z1 + b * z2;
    } else if (thermal_noise) {
        nvel += c.sigma_vv * z2;   // degenerate: no position spread this step
    }

    pos = npos;
    vel = nvel;
}

// Full 3D step. Six gaussian variates (two per axis) come from the cell's own
// PCG32 stream, so the trajectory depends only on (seed, cell_id, tick).
ASTRO_HD inline void integrate_cell(Vec3& pos, Vec3& vel, Vec3 force,
                                    double mass, double gamma, double t_kelvin,
                                    double dt, bool thermal_noise, Pcg32& rng) {
    const OuCoefficients c = ou_coefficients(mass, gamma, t_kelvin, dt);
    double z1, z2, z3, z4, z5, z6;
    gaussian_pair(rng, z1, z2);
    gaussian_pair(rng, z3, z4);
    gaussian_pair(rng, z5, z6);
    ou_advance_axis(pos.x, vel.x, force.x, gamma, c, dt, thermal_noise, z1, z2);
    ou_advance_axis(pos.y, vel.y, force.y, gamma, c, dt, thermal_noise, z3, z4);
    ou_advance_axis(pos.z, vel.z, force.z, gamma, c, dt, thermal_noise, z5, z6);
}

// ---------------------------------------------------------------------------
// Forces
// ---------------------------------------------------------------------------

enum class GravityAxis : unsigned char { Y = 0, Z = 1 };

// Buoyant weight plus photon recoil. Contact arrives at M4, thermophoresis is
// implemented but off by default (PHYSICS.md Sec 3.4).
ASTRO_HD inline Vec3 cell_force(double mass, double emit_power,
                                Vec3 emit_dir, GravityAxis axis) {
    Vec3 f{0.0, 0.0, 0.0};
    const double w = buoyant_weight(mass);
    if (axis == GravityAxis::Y) f.y += w; else f.z += w;
    // Recoil is opposite the emission direction.
    const double thrust = photon_thrust(emit_power);
    if (thrust != 0.0) f -= emit_dir * thrust;
    return f;
}

// ---------------------------------------------------------------------------
// Boundaries
// ---------------------------------------------------------------------------

// Soft-sphere pair repulsion, the only cell-cell mechanical interaction.
// Returns the force on `self` from a neighbour at `other`, zero beyond contact.
ASTRO_HD inline Vec3 contact_force(Vec3 self, Vec3 other) {
    const Vec3 d = self - other;
    const double r2 = length_sq(d);
    const double two_a = canon::CELL_DIAMETER;
    if (r2 >= two_a * two_a || r2 <= 0.0) return Vec3{0.0, 0.0, 0.0};
    const double r = sqrt(r2);
    const double overlap = two_a - r;
    return d * (canon::CONTACT_STIFFNESS * overlap / r);
}

// Rest overlap of two cells pressed together by a steady force. The M4 gate
// requires this under 5 % of a diameter, which is what sets CONTACT_STIFFNESS.
ASTRO_HD inline double rest_overlap_fraction(double applied_force) {
    return (applied_force / canon::CONTACT_STIFFNESS) / canon::CELL_DIAMETER;
}

enum class Boundary : unsigned char { Reflecting = 0, Periodic = 1, Absorbing = 2 };

// A cell that reaches a wall comes to rest against it. True mirror reflection
// would be unphysical at Re << 1 -- there is no inertia to bounce with -- so
// "reflecting" here means: clamp the position, zero the normal velocity.
// Returns false if the cell was absorbed.
ASTRO_HD inline bool apply_boundary_axis(double& p, double& v, double half_extent,
                                         double radius, Boundary mode) {
    const double lo = -half_extent + radius;
    const double hi = half_extent - radius;
    if (p >= lo && p <= hi) return true;

    switch (mode) {
        case Boundary::Periodic: {
            const double span = 2.0 * half_extent;
            while (p < -half_extent) p += span;
            while (p > half_extent) p -= span;
            return true;
        }
        case Boundary::Absorbing:
            return false;
        case Boundary::Reflecting:
        default:
            p = (p < lo) ? lo : hi;
            v = 0.0;
            return true;
    }
}

} // namespace astro::sim
