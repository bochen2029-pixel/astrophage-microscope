// src/sim/taxis.cuh -- run-and-tumble taxis. docs/PHYSICS.md Sec 8, ADR-007, ADR-022.
//
// Every decision a cell makes lives here as a pure __host__ __device__ function so
// tests exercise the real code path without a GPU (ARCHITECTURE.md Sec 3.3). The
// kernel in taxis.cu is a thin loop over these.
#pragma once

#include <cmath>
#include <cstdint>

#include "core/canon_generated.h"
#include "core/rng.cuh"
#include "core/units.h"
#include "core/vec.cuh"

namespace astro::sim {

enum class TaxisState : unsigned char { Idle = 0, Feed = 1, Breed = 2 };

// ---------------------------------------------------------------------------
// Temporal comparison
// ---------------------------------------------------------------------------

// The lagged signal is a first-order lag, not a delay line: `taxis_memory` is a
// single float (contracts/cell_store_v1.h) and real chemotactic response kernels
// are approximated by exactly this (ADR-007).
//
// The exact discretisation, not the Euler approximation -- so a step input reaches
// 1 - 1/e at exactly TAXIS_MEMORY_TIME regardless of dt, which is what makes the
// memory window mean what it says.
ASTRO_HD inline float taxis_ema_update(float ema, double signal, double dt) {
    const double alpha = 1.0 - exp(-dt / canon::TAXIS_MEMORY_TIME);
    return static_cast<float>(static_cast<double>(ema) + alpha * (signal - static_cast<double>(ema)));
}

// ---------------------------------------------------------------------------
// The state machine
// ---------------------------------------------------------------------------

// CO2 availability needs no threshold constant. The field is zero everywhere
// until something adds to it, and a temporal comparison on an identically-zero
// signal is identically zero -- which produces Idle anyway. Canon is silent on a
// concentration cutoff, so inventing one would be a number with no provenance
// (ADR-022).
ASTRO_HD inline bool taxis_co2_available(double co2) { return co2 > 0.0; }

ASTRO_HD inline bool taxis_is_dark(double irradiance) {
    return irradiance < canon::TAXIS_DARK_THRESHOLD;
}

// PHYSICS.md Sec 8, with one documented deviation: Feed additionally requires
// light. The literal pseudocode lets a dim, low-charge cell enter Feed whenever
// any CO2 is present, which would burn store climbing an irradiance gradient that
// does not exist and contradicts canon's "does not move in darkness" (ADR-022).
ASTRO_HD inline TaxisState taxis_select_state(double charge, double irradiance, double co2) {
    const bool dark = taxis_is_dark(irradiance);
    const bool co2_here = taxis_co2_available(co2);
    if (dark && !co2_here) return TaxisState::Idle;
    if (!dark && charge < canon::TAXIS_SEEK_FEED_BELOW) return TaxisState::Feed;
    if (charge > canon::TAXIS_SEEK_BREED_ABOVE && co2_here) return TaxisState::Breed;
    return TaxisState::Idle;
}

// The quantity a cell climbs in each seeking state.
ASTRO_HD inline double taxis_signal(TaxisState s, double irradiance, double co2) {
    if (s == TaxisState::Feed) return irradiance;
    if (s == TaxisState::Breed) return co2;
    return 0.0;
}

// ---------------------------------------------------------------------------
// Run and tumble
// ---------------------------------------------------------------------------

// A run ends when the signal stops improving, and ALWAYS ends by TAXIS_RUN_MAX.
// The cap is not decoration: a cell that outruns its own depletion halo sees a
// permanently rising signal in every direction and would otherwise never tumble
// (ADR-022). It is what keeps M9's CO2 uptake from breaking the controller.
ASTRO_HD inline bool taxis_should_tumble(double delta, double run_timer) {
    return delta <= 0.0 || run_timer >= canon::TAXIS_RUN_MAX;
}

// Any unit vector perpendicular to `v`. Picks the smallest component to cross
// against, so the result never degenerates.
ASTRO_HD inline Vec3 any_perpendicular(Vec3 v) {
    const double ax = fabs(v.x), ay = fabs(v.y), az = fabs(v.z);
    Vec3 axis = (ax <= ay && ax <= az) ? Vec3{1.0, 0.0, 0.0}
              : (ay <= az)             ? Vec3{0.0, 1.0, 0.0}
                                       : Vec3{0.0, 0.0, 1.0};
    return normalize(cross(v, axis));
}

// Rotate `h` by polar angle `theta` about a uniformly random azimuth.
ASTRO_HD inline Vec3 rotate_by(Vec3 h, double theta, double azimuth) {
    const Vec3 u = any_perpendicular(h);
    const Vec3 w = cross(h, u);          // already unit: h and u are orthonormal
    const Vec3 perp = u * cos(azimuth) + w * sin(azimuth);
    return normalize(h * cos(theta) + perp * sin(theta));
}

// The tumble angle. Exponential with mean TAXIS_TUMBLE_ANGLE_MEAN, clamped to pi
// because a rotation beyond pi is the same rotation the other way round. The
// clamp lowers the realised mean to mean*(1 - exp(-pi/mean)); that value is
// derived in derive.py as T26_TUMBLE_MEAN_CLAMPED rather than tolerated in a test.
// Inverse-transform sampled from `1 - u` rather than `u`: uniform01d returns
// [0,1), so `1 - u` is (0,1] and log() can never see zero. That removes the
// epsilon guard entirely instead of hiding a bare literal behind a waiver.
ASTRO_HD inline double taxis_tumble_angle(Pcg32& rng) {
    const double theta = -canon::TAXIS_TUMBLE_ANGLE_MEAN * log(1.0 - uniform01d(rng));
    return theta > PI ? PI : theta;
}

// A new heading, `theta` away from the old one about a random azimuth.
ASTRO_HD inline Vec3 taxis_tumble(Vec3 heading, Pcg32& rng) {
    const double theta = taxis_tumble_angle(rng);
    const double azimuth = TWO_PI * uniform01d(rng);
    return rotate_by(normalize(heading), theta, azimuth);
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

// Recoil is opposite the emission axis (integrator.cuh cell_force does
// `f -= emit_dir * thrust`), so a cell swimming toward the light emits DOWNSTREAM,
// into its own shadow. That is what a photon rocket does and it is the sign error
// most likely to pass a sloppy test -- T26.1 asserts it explicitly.
ASTRO_HD inline Vec3 taxis_emit_dir(Vec3 heading) { return -normalize(heading); }

// PHYSICS.md Sec 6: dE/dt = -emit_power. Clamped to what the store can actually
// supply this tick so energy cannot go negative; a cell that empties starves
// through the existing M6 path at stage 4.
// `max_power` is the emission cap. It defaults to canon so every existing caller (the
// tests, and any future kernel) is unchanged and bit-identical; taxis.cu passes the World
// override (ADR-035), which equals canon unless the inspector tuned it.
ASTRO_HD inline double taxis_emit_power(TaxisState s, double energy, double dt,
                                        double max_power = canon::PETROVA_MAX_POWER) {
    if (s == TaxisState::Idle || energy <= 0.0) return 0.0;
    const double avail = dt > 0.0 ? energy / dt : 0.0;
    return max_power < avail ? max_power : avail;
}

} // namespace astro::sim
