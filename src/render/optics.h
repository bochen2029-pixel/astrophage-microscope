// src/render/optics.h -- the microscope. docs/RENDERING.md Sec 3.
//
// Pure functions, host-testable (tests/physics/test_optics.cpp). The fragment
// shader in cells_pass.cpp MIRRORS these formulas -- if you change one, change
// both. The golden images are what catch a divergence; there is no compiler
// check across the GLSL boundary.
//
// The premise of the whole milestone: at the working objective the depth of
// field is 1.53 um inside a 60 um chamber, so at any moment almost everything is
// out of focus and only a thin layer is sharp. That is not a limitation to be
// softened -- it is what looking down a microscope is.
#pragma once

#include <cmath>

#include "core/canon_generated.h"
#include "core/units.h"

namespace astro::render {

// Geometric circle of confusion. A cell `dz` from the focal plane images as a
// blur disc of this radius. At NA 0.65 a cell 10 um out of focus blurs to 6.5 um
// -- larger than the cell itself.
ASTRO_HD inline double circle_of_confusion(double dz, double na, double immersion) {
    return fabs(dz) * na / immersion;
}

// Radius of the blurred profile: a disc of radius `a` convolved with a blur of
// radius `r_coc`. Quadrature is the right combination because the two are
// independent spreads -- and it degrades correctly at both ends, giving `a` in
// focus and `r_coc` when heavily defocused.
ASTRO_HD inline double blurred_radius(double a, double r_coc) {
    return sqrt(a * a + r_coc * r_coc);
}

// Peak opacity of the blurred profile.
//
// ENERGY CONSERVATION IS THE POINT. A defocused cell absorbs exactly as much
// light as a focused one; the absorption is just spread over a larger area. So
// peak opacity falls as the area ratio. Without this a defocused cell would stay
// jet black and simply grow, which reads as fog rather than as blur.
ASTRO_HD inline double peak_opacity(double a, double r_coc) {
    const double R = blurred_radius(a, r_coc);
    return (R > 0.0) ? (a * a) / (R * R) : 1.0;
}

// The Becke line: a real diffraction artefact at the edge of a transparent-
// medium/opaque-object boundary, and the single cheapest thing that makes a
// render read as microscopy. It is only visible near focus, so it fades out
// over roughly one cell radius of defocus.
ASTRO_HD inline double ring_amplitude(double a, double r_coc) {
    const double t = 1.0 - r_coc / a;
    return t > 0.0 ? t : 0.0;
}

// Above and below focus the ring pattern INVERTS -- bright halo one side, dark
// the other. That inversion is the cue that tells a viewer which way to rack the
// focus, and without it focusing is a guessing game.
ASTRO_HD inline double focus_polarity(double dz) {
    return dz >= 0.0 ? 1.0 : -1.0;
}

// Berek depth of field, matching canon::OBJECTIVES[i].depth_of_field_m.
ASTRO_HD inline double depth_of_field(double lambda, double na, double immersion,
                                      double magnification, double sensor_pixel) {
    return (lambda * immersion) / (na * na) +
           (immersion * sensor_pixel) / (magnification * na);
}

// Is this cell inside the depth of field -- i.e. actually sharp?
ASTRO_HD inline bool in_focus(double dz, double dof) {
    return fabs(dz) <= 0.5 * dof;
}

// Fraction of a uniformly-filled slab that is in focus at once. At the working
// objective in a 60 um chamber this is 2.5 %, so at any moment almost the whole
// culture is out-of-focus haze and a handful of cells are sharp.
//
// NOTE: sedimentation does NOT concentrate cells into a focal plane here.
// Gravity runs along -y (ADR-006) so cells pile against a side wall while their
// z stays uniformly spread. A settled monolayer against the coverslip would only
// happen under `gravity_axis: z`, which is the ADR-006 escape hatch and is not
// the default. Do not assume the culture ever becomes a single sharp layer.
ASTRO_HD inline double sharp_fraction(double dof, double slab_depth) {
    if (slab_depth <= 0.0) return 1.0;
    const double f = dof / slab_depth;
    return f > 1.0 ? 1.0 : f;
}

} // namespace astro::render
