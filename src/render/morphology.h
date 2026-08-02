// src/render/morphology.h -- irregular cell silhouettes. docs/RENDERING.md Sec 8,
// ADR-023.
//
// Pure functions, host-testable (tests/physics/test_morphology.cpp). The fragment
// shader in cells_pass.cpp MIRRORS shape_radius() -- if you change one, change
// both. That mirror is now the FIFTH formula duplicated across the GLSL boundary
// (ADR-017, Q7); the next one should generate the GLSL from this header instead.
//
// APPEARANCE ONLY. The physics body is a sphere of CELL_RADIUS everywhere in
// sim/ -- Stokes drag, CELL_CROSS_SECTION, contact, disc_overlap_fraction. Nothing
// here may ever be consulted by a simulation kernel.
#pragma once

#include <cmath>
#include <cstdint>

#include "core/units.h"

namespace astro::render {

// Radial harmonics k = 3..8. k = 1 is a pure translation of the outline and k = 2
// only makes it an ellipse, so neither reads as "crumpled". The upper end is what
// separates a faceted grain from a smooth lobed blob: with only k <= 6 the
// silhouette is recognisably a rounded pebble.
inline constexpr int MORPH_HARMONICS = 6;
inline constexpr int MORPH_K_MIN = 3;

// Amplitude of harmonic k. Falls as 1/k so low-order lobes set the gross shape and
// high-order terms only crinkle the edge -- the same spectral falloff that makes
// procedural terrain read as terrain rather than as noise. The 0.28 is chosen so
// the total excursion stays ~0.34 of the radius while being spread over six
// frequencies instead of four: same silhouette amplitude, more edge detail.
ASTRO_HD inline double morph_amplitude(int k) {
    return 0.28 / static_cast<double>(k);
}

// Cheap integer hash, so a cell's shape is a pure function of its seed and needs
// no storage beyond the seed itself. Not a simulation RNG -- never used for
// anything that reaches a snapshot hash.
ASTRO_HD inline uint32_t morph_hash(uint32_t x) {
    x ^= x >> 16; x *= 0x7FEB352Du;
    x ^= x >> 15; x *= 0x846CA68Bu;
    x ^= x >> 16;
    return x;
}

ASTRO_HD inline double morph_phase(uint32_t seed, int k) {
    return TWO_PI * static_cast<double>(morph_hash(seed + static_cast<uint32_t>(k) * 0x9E3779B9u))
           * (1.0 / 4294967296.0);
}

// `w` is how much shape survives the optics: 1 in focus, falling to 0 as defocus
// swamps the geometry. Blur genuinely destroys shape detail, so a heavily
// defocused cell SHOULD image as a featureless disc; carrying the full silhouette
// into a 40 um blur disc would be an optical lie.
//
// AREA PRESERVATION IS THE POINT, and it is why the normalisation is not
// cosmetic. For r(t) = a(1 + w * sum A_k cos(k t + phi_k)) the enclosed area is
//
//     (1/2) * integral r^2 dt = pi a^2 (1 + (1/2) w^2 sum A_k^2)
//
// so an un-normalised irregular cell would be ~4 % larger in projected area than
// the sphere it stands for, and would therefore absorb ~4 % more light than the
// physics says it does. Dividing by sqrt(1 + (1/2) w^2 sum A_k^2) restores the
// area exactly -- and it must carry the same `w`, or the area drifts back off as
// the cell defocuses. Without this the renderer quietly stops agreeing with sim/.
ASTRO_HD inline double morph_area_normalisation(double w) {
    double s = 0.0;
    for (int i = 0; i < MORPH_HARMONICS; ++i) {
        const double A = morph_amplitude(MORPH_K_MIN + i);
        s += A * A;
    }
    return 1.0 / sqrt(1.0 + 0.5 * w * w * s);
}

// The silhouette: effective radius at angle `theta`, in units of the true radius.
// Returns exactly 1.0 at every angle when `seed` is 0 or `w` is 0, which is how
// Sphere morphology and the fully-defocused limit both fall out of this one code
// path instead of branching around it.
ASTRO_HD inline double shape_radius(double theta, uint32_t seed, double w) {
    if (seed == 0u || w <= 0.0) return 1.0;
    if (w > 1.0) w = 1.0;
    double sum = 0.0;
    for (int i = 0; i < MORPH_HARMONICS; ++i) {
        const int k = MORPH_K_MIN + i;
        sum += morph_amplitude(k) * cos(static_cast<double>(k) * theta + morph_phase(seed, k));
    }
    const double r = (1.0 + w * sum) * morph_area_normalisation(w);
    // The amplitudes sum to 0.34*(1/3+1/4+1/5+1/6) = 0.31 < 1, so r is always
    // positive; the floor is belt-and-braces against a future amplitude change
    // making the outline self-intersect.
    return r > 0.05 ? r : 0.05;
}

// Largest value shape_radius can take, so the vertex stage can size the quad
// without evaluating the shape. Conservative by construction: the harmonics
// cannot all peak at once, but assuming they do is safe and costs a few percent
// of quad area.
ASTRO_HD inline double shape_radius_max(double w) {
    if (w <= 0.0) return 1.0;
    if (w > 1.0) w = 1.0;
    double sum = 0.0;
    for (int i = 0; i < MORPH_HARMONICS; ++i) sum += morph_amplitude(MORPH_K_MIN + i);
    return (1.0 + w * sum) * morph_area_normalisation(w);
}

// Opacity across the profile, as a fraction of peak. The reference imagery shows
// a dense black core with a soft ruffled skirt rather than a clean edge, so the
// core is flat out to CORE_FRAC and only the rim falls off.
inline constexpr double MORPH_CORE_FRAC = 0.72;

ASTRO_HD inline double morph_core_falloff(double r_over_edge) {
    if (r_over_edge <= MORPH_CORE_FRAC) return 1.0;
    if (r_over_edge >= 1.0) return 0.0;
    const double t = (r_over_edge - MORPH_CORE_FRAC) / (1.0 - MORPH_CORE_FRAC);
    return 1.0 - t * t * (3.0 - 2.0 * t);      // smoothstep
}

} // namespace astro::render
