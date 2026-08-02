// tests/physics/test_optics.cpp -- the microscope model, headless.
//
// The golden images guard the SHADER. This guards the model the shader mirrors,
// which is the part that can be reasoned about: energy conservation under
// defocus, the depth-of-field arithmetic, and the focus-polarity inversion.
#include <cmath>
#include <cstdio>
#include <initializer_list>

#include "core/canon_generated.h"
#include "render/optics.h"
#include "test_util.h"

using namespace astro;
using namespace astro::render;

int main() {
    const auto& working = canon::OBJECTIVES[canon::OBJECTIVE_DEFAULT];
    const double a = canon::CELL_RADIUS;

    // --- depth of field must match the generated objective table -------------
    for (int i = 0; i < canon::OBJECTIVE_COUNT; ++i) {
        const auto& o = canon::OBJECTIVES[i];
        const double dof = depth_of_field(canon::OPTICS_LAMBDA_VIS, o.na, o.immersion,
                                          o.magnification, canon::OPTICS_SENSOR_PIXEL);
        CHECK_CLOSE(dof, o.depth_of_field_m, 1e-9);
    }

    // --- circle of confusion -------------------------------------------------
    {
        CHECK_CLOSE(circle_of_confusion(0.0, working.na, working.immersion), 0.0, 1e-12);
        // Symmetric about focus: only |dz| matters for the blur SIZE. The SIDE
        // matters only for the ring polarity.
        CHECK_CLOSE(circle_of_confusion(1e-5, working.na, working.immersion),
                    circle_of_confusion(-1e-5, working.na, working.immersion), 1e-12);

        // 10 um out of focus at NA 0.65 blurs to 6.5 um -- larger than the cell.
        const double r = circle_of_confusion(1.0e-5, working.na, working.immersion);
        std::printf("  40x, 10 um defocus: r_coc = %.2f um (cell radius %.1f um)\n",
                    r * 1e6, a * 1e6);
        CHECK_CLOSE(r, 6.5e-6, 1e-6);
        CHECK(r > a);

        // Oil immersion reduces the blur for a given defocus, despite the higher
        // NA, because the ray angles in the medium are smaller.
        const auto& detail = canon::OBJECTIVES[2];
        CHECK(detail.immersion > 1.0);
        CHECK_CLOSE(circle_of_confusion(1e-5, detail.na, detail.immersion),
                    1e-5 * detail.na / detail.immersion, 1e-12);
    }

    // --- energy conservation, the thing that makes blur read as blur ---------
    {
        CHECK_CLOSE(peak_opacity(a, 0.0), 1.0, 1e-12);      // in focus: fully opaque

        // Total absorption is invariant: peak * area stays constant as the cell
        // defocuses. Without this a defocused cell stays black and merely grows,
        // which reads as fog.
        const double reference = peak_opacity(a, 0.0) * blurred_radius(a, 0.0) *
                                                        blurred_radius(a, 0.0);
        for (double r_coc : {0.0, 1e-6, 5e-6, 2e-5, 1e-4}) {
            const double R = blurred_radius(a, r_coc);
            CHECK_CLOSE(peak_opacity(a, r_coc) * R * R, reference, 1e-12);
        }

        // Monotone falloff, and a heavily defocused cell is genuinely faint.
        CHECK(peak_opacity(a, 1e-6) > peak_opacity(a, 5e-6));
        CHECK(peak_opacity(a, 5e-6) > peak_opacity(a, 2e-5));
        const double far = peak_opacity(a, 3.0e-5);   // 30 um blur radius
        std::printf("  peak opacity at 30 um blur: %.4f\n", far);
        CHECK(far < 0.05);

        // blurred_radius degrades correctly at both ends.
        CHECK_CLOSE(blurred_radius(a, 0.0), a, 1e-12);
        CHECK_CLOSE(blurred_radius(a, 1.0e-3), 1.0e-3, 1e-4);   // blur dominates
    }

    // --- the Becke line fades out with defocus, then stops -------------------
    {
        CHECK_CLOSE(ring_amplitude(a, 0.0), 1.0, 1e-12);
        CHECK_CLOSE(ring_amplitude(a, a * 0.5), 0.5, 1e-12);
        CHECK(ring_amplitude(a, a) <= 0.0);           // gone by one radius
        CHECK(ring_amplitude(a, a * 10.0) >= 0.0);    // never negative
    }

    // --- polarity inverts across focus; that IS the focusing cue -------------
    {
        CHECK(focus_polarity(1e-6) > 0.0);
        CHECK(focus_polarity(-1e-6) < 0.0);
        CHECK(focus_polarity(1e-6) == -focus_polarity(-1e-6));
    }

    // --- in_focus and the sharp fraction -------------------------------------
    {
        const double dof = working.depth_of_field_m;
        CHECK(in_focus(0.0, dof));
        CHECK(in_focus(0.49 * dof, dof));
        CHECK(!in_focus(0.51 * dof, dof));

        // The premise of the milestone: at the working objective only ~2.5 % of
        // a 60 um chamber is sharp at once. If this ever climbs, either the
        // chamber got thinner or the optics stopped being a microscope.
        const double f = sharp_fraction(dof, canon::CHAMBER_D);
        std::printf("  sharp fraction of a %.0f um chamber at 40x: %.2f%%\n",
                    canon::CHAMBER_D * 1e6, f * 100.0);
        CHECK(f < 0.05);
        CHECK(f > 0.005);

        // The 100x objective is shallower still; the 10x survey much deeper.
        CHECK(sharp_fraction(canon::OBJECTIVES[2].depth_of_field_m, canon::CHAMBER_D) < f);
        CHECK(sharp_fraction(canon::OBJECTIVES[0].depth_of_field_m, canon::CHAMBER_D) > f);
    }

    // --- a cell at the chamber wall is very defocused when centred -----------
    // This is why racking focus matters, and why a sedimented monolayer at the
    // coverslip is invisible until you focus on it.
    {
        const double dz = 0.5 * canon::CHAMBER_D;
        const double r = circle_of_confusion(dz, working.na, working.immersion);
        const double pk = peak_opacity(a, r);
        std::printf("  cell at the coverslip, focus centred: r_coc = %.1f um (%.2f cell radii),"
                    " peak %.4f\n", r * 1e6, r / a, pk);

        // Assert the derived values, not invented thresholds: the blur is
        // dz*NA/n and the opacity follows from energy conservation. Both fall
        // straight out of the chamber depth and the objective.
        CHECK_CLOSE(r, dz * working.na / working.immersion, 1e-12);
        CHECK_CLOSE(r / a, 3.9, 1e-3);
        CHECK_CLOSE(pk, 1.0 / (1.0 + (r / a) * (r / a)), 1e-12);
        CHECK_CLOSE(pk, 0.0617, 1e-2);

        // The qualitative claim that matters: such a cell is a faint smudge, so
        // a monolayer settled on the glass is invisible until you focus on it.
        CHECK(r > 3.0 * a);
        CHECK(pk < 0.10);
    }

    return astro::test::finish("test_optics");
}
