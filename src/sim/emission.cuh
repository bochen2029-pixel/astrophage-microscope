// src/sim/emission.cuh -- Petrova emission, photon thrust, and occlusion.
// docs/PHYSICS.md Sec 6 and Sec 7.5-7.6. Produces P5.
#pragma once

#include <cmath>

#include "core/canon_generated.h"
#include "core/units.h"
#include "core/vec.cuh"

namespace astro::sim {

// Fraction of a disc of radius a that is hidden by an identical disc whose
// centre is `p` away, measured perpendicular to the line of sight. The standard
// circle-circle intersection area over pi a^2.
//
// EXACTLY 1 at p = 0 and EXACTLY 0 at p >= 2a. Both are asserted: albedo is
// zero, so a directly-aligned cell casts a total shadow, not a deep one.
ASTRO_HD inline double disc_overlap_fraction(double p, double a) {
    if (p <= 0.0) return 1.0;
    if (p >= 2.0 * a) return 0.0;
    const double x = p / (2.0 * a);
    // 2/pi * (acos(x) - x*sqrt(1-x^2))
    return (2.0 / PI) * (acos(x) - x * sqrt(1.0 - x * x));
}

// How much of `self` is shadowed by `other` for light arriving along `light_dir`
// (a unit vector pointing the way the light travels). Zero unless `other` is
// genuinely upstream.
ASTRO_HD inline double shadow_fraction(Vec3 self, Vec3 other, Vec3 light_dir) {
    const Vec3 d = self - other;
    const double along = dot(d, light_dir);
    if (along <= 0.0) return 0.0;              // downstream or level: no shadow
    const double perp2 = length_sq(d) - along * along;
    const double perp = perp2 > 0.0 ? sqrt(perp2) : 0.0;
    return disc_overlap_fraction(perp, canon::CELL_RADIUS);
}

// Beer-Lambert extinction of one depth-averaged grid cell holding `n` cells.
// The grid can only ever give FRACTIONAL extinction -- one cell blocks 16.8 % of
// a grid cell's face. Exact shadowing is a 3D fact and is handled per-cell by
// shadow_fraction above; this is the far field (ADR-021).
ASTRO_HD inline double column_transmittance(double blocked_area, double face_area) {
    if (face_area <= 0.0) return 1.0;
    const double t = 1.0 - blocked_area / face_area;
    return t > 0.0 ? t : 0.0;
}

// Astrophage absorbs everything that reaches it -- albedo is exactly 0.
// Projected disc for a collimated beam, full sphere for isotropic light.
ASTRO_HD inline double absorbed_power(double directional, double ambient) {
    return directional * canon::CELL_CROSS_SECTION + ambient * canon::CELL_SURFACE_AREA;
}

// Photon rocket. Recoil is opposite the emission direction (PHYSICS.md Sec 6).
ASTRO_HD inline double photon_thrust_from(double emit_power) {
    return emit_power / canon::C_LIGHT;
}

ASTRO_HD inline double petrova_photons_per_second(double emit_power) {
    return emit_power / canon::PETROVA_PHOTON_ENERGY;
}

// A cell cannot re-aim instantly; the axis slews toward the commanded heading.
ASTRO_HD inline Vec3 slew_toward(Vec3 current, Vec3 target, double dt) {
    const double max_step = canon::PETROVA_SLEW_RATE * dt;
    const Vec3 c = normalize(current);
    const Vec3 t = normalize(target);
    double cosang = dot(c, t);
    cosang = cosang > 1.0 ? 1.0 : (cosang < -1.0 ? -1.0 : cosang);
    const double ang = acos(cosang);
    if (ang <= max_step || ang <= 0.0) return t;
    const double f = max_step / ang;
    return normalize(c * (1.0 - f) + t * f);
}

// Is a direction inside the emission cone? Used by the renderer for the lobe.
ASTRO_HD inline bool within_beam(Vec3 axis, Vec3 dir) {
    return dot(normalize(axis), normalize(dir)) >= cos(canon::PETROVA_BEAM_HALF_ANGLE);
}

} // namespace astro::sim
