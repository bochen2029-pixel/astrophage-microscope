// tests/physics/test_morphology.cpp -- T27. Irregular cell silhouettes.
// docs/RENDERING.md Sec 8, ADR-023.
//
// Host-only: morphology.h is pure and has no GL and no CUDA. The shader mirror in
// cells_pass.cpp is guarded by the irregular golden, not by this file.
#include <cmath>
#include <cstdio>

#include "core/units.h"
#include "render/morphology.h"
#include "test_util.h"

using namespace astro;
using namespace astro::render;

namespace {

// Enclosed area of the closed curve r(theta), by direct quadrature of
// (1/2) * integral r^2 dtheta. In units of pi a^2, so a perfect circle gives 1.
double enclosed_area(uint32_t seed, double w, int samples = 200000) {
    double acc = 0.0;
    const double dt = TWO_PI / samples;
    for (int i = 0; i < samples; ++i) {
        const double r = shape_radius((i + 0.5) * dt, seed, w);
        acc += r * r;
    }
    return 0.5 * acc * dt / PI;
}

} // namespace

int main() {
    // --- T27.1: Sphere morphology is EXACTLY circular ------------------------
    {
        // Seed 0 is the sentinel the shader reads as "perfectly circular", and it
        // must be exact rather than nearly so -- Sphere morphology is what every
        // measurement golden is pinned to, so any drift there silently moves an
        // oracle.
        for (int i = 0; i < 64; ++i) {
            const double theta = TWO_PI * i / 64.0;
            CHECK(shape_radius(theta, 0u, 1.0) == 1.0);
        }
        // A zero blur weight collapses to a circle for ANY seed: heavy defocus
        // genuinely destroys shape detail, and carrying a silhouette into a 40 um
        // blur disc would be an optical lie.
        for (uint32_t s = 1u; s <= 8u; ++s) CHECK(shape_radius(1.0, s, 0.0) == 1.0);
        CHECK(shape_radius_max(0.0) == 1.0);
    }

    // --- T27.2 (GATE): the shape is AREA-PRESERVING --------------------------
    {
        // This is the property that keeps the renderer agreeing with sim/. An
        // irregular cell stands for a sphere of CELL_RADIUS and must absorb
        // exactly as much light as that sphere -- so its projected area must equal
        // pi a^2 at EVERY blur weight, not just in focus.
        double worst = 0.0;
        uint32_t worst_seed = 0;
        double worst_w = 0.0;
        for (uint32_t s = 1u; s <= 200u; ++s) {
            for (int wi = 0; wi <= 10; ++wi) {
                const double w = wi / 10.0;
                const double err = std::fabs(enclosed_area(s * 2654435761u + 1u, w, 20000) - 1.0);
                if (err > worst) { worst = err; worst_seed = s; worst_w = w; }
            }
        }
        std::printf("  area: worst relative error %.3e (seed #%u, w = %.1f)\n",
                    worst, worst_seed, worst_w);
        CHECK(worst < 1.0e-3);
    }

    // --- T27.3: bounded, and the quad bound actually bounds ------------------
    {
        // The vertex stage sizes the quad from shape_radius_max without evaluating
        // the shape. If that bound is ever exceeded the silhouette is clipped by
        // its own quad, which reads as a cell with a straight razor-cut edge.
        double worst_over = 0.0, smallest = 1e30;
        for (uint32_t s = 1u; s <= 500u; ++s) {
            const uint32_t seed = s * 2654435761u + 1u;
            for (int wi = 1; wi <= 10; ++wi) {
                const double w = wi / 10.0;
                const double bound = shape_radius_max(w);
                for (int i = 0; i < 512; ++i) {
                    const double r = shape_radius(TWO_PI * i / 512.0, seed, w);
                    if (r - bound > worst_over) worst_over = r - bound;
                    if (r < smallest) smallest = r;
                }
            }
        }
        std::printf("  bound: worst overshoot %.3e, smallest radius %.4f\n",
                    worst_over, smallest);
        CHECK(worst_over <= 0.0);
        CHECK(smallest > 0.3);          // never pinches to a spike or self-intersects
    }

    // --- T27.4: periodic, and deterministic in the seed alone ----------------
    {
        for (uint32_t s = 1u; s <= 50u; ++s) {
            const uint32_t seed = s * 7919u + 1u;
            for (int i = 0; i < 32; ++i) {
                const double t = TWO_PI * i / 32.0;
                CHECK_CLOSE(shape_radius(t, seed, 1.0),
                            shape_radius(t + TWO_PI, seed, 1.0), 1e-9);
            }
            // Same seed, same shape -- every time. A cell's silhouette is stable
            // for its whole life, so this cannot depend on call order or state.
            CHECK(shape_radius(0.7, seed, 1.0) == shape_radius(0.7, seed, 1.0));
        }
    }

    // --- T27.5: different seeds give visibly different shapes ----------------
    {
        // A morphology that produced near-identical blobs would be a waste of the
        // contract bump. Measure how far apart two silhouettes are, averaged over
        // angle, and require it to be a real fraction of the radius.
        double total = 0.0;
        int pairs = 0;
        for (uint32_t s = 1u; s <= 60u; ++s) {
            const uint32_t a = s * 2654435761u + 1u;
            const uint32_t b = (s + 977u) * 2654435761u + 1u;
            double diff = 0.0;
            for (int i = 0; i < 256; ++i) {
                const double t = TWO_PI * i / 256.0;
                diff += std::fabs(shape_radius(t, a, 1.0) - shape_radius(t, b, 1.0));
            }
            total += diff / 256.0;
            ++pairs;
        }
        const double mean_sep = total / pairs;
        std::printf("  distinctness: mean |r_a - r_b| = %.4f of the radius\n", mean_sep);
        CHECK(mean_sep > 0.10);
    }

    // --- T27.6: the rim profile ---------------------------------------------
    {
        // A dense black core out to CORE_FRAC, then a soft skirt -- not a linear
        // ramp from the centre, which would read as fog.
        CHECK(morph_core_falloff(0.0) == 1.0);
        CHECK(morph_core_falloff(MORPH_CORE_FRAC) == 1.0);
        CHECK(morph_core_falloff(1.0) == 0.0);
        CHECK(morph_core_falloff(1.5) == 0.0);
        const double mid = morph_core_falloff(0.5 * (MORPH_CORE_FRAC + 1.0));
        CHECK(mid > 0.4 && mid < 0.6);
        // Monotone across the skirt.
        double prev = 1.0;
        for (int i = 0; i <= 100; ++i) {
            const double v = morph_core_falloff(i / 100.0);
            CHECK(v <= prev + 1e-12);
            prev = v;
        }
    }

    return astro::test::finish("test_morphology");
}
