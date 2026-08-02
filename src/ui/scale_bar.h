// src/ui/scale_bar.h -- scale bar length selection, as a pure function.
//
// Split out of hud.cpp so it is testable without a GL context or ImGui
// (CLAUDE.md Iron Rule 5, headless first). "The scale bar reads correctly at all
// three objectives" is an M1 gate condition, and a gate you can only check by
// squinting at a screenshot is not a gate.
#pragma once

#include <cstddef>

namespace astro::ui {

struct ScaleBarChoice {
    double length_um = 0.0;   // the snapped physical length
    double length_px = 0.0;   // how wide that is on screen
};

// Snap points a microscopist would expect: 1-2-5 decades, nothing else.
// The table runs down to 0.1 um because at high digital zoom the field is
// narrower than a single cell, and the 100x objective resolves 268 nm -- so
// sub-micron bars are meaningful, not decoration. Without them the fallback
// below fires and the bar overflows its quarter-width budget.
inline constexpr double kScaleBarSteps_um[] = {
    0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000
};
inline constexpr int kScaleBarStepCount =
    static_cast<int>(sizeof(kScaleBarSteps_um) / sizeof(kScaleBarSteps_um[0]));

// Largest snap point that fits within max_px. If even the smallest overflows
// (absurdly deep zoom) the smallest is returned, so the bar is always drawn --
// a missing scale bar is worse than an oversized one.
inline ScaleBarChoice choose_scale_bar(double metres_per_pixel, double max_px) {
    ScaleBarChoice c;
    if (metres_per_pixel <= 0.0 || max_px <= 0.0) return c;
    c.length_um = kScaleBarSteps_um[0];
    c.length_px = (kScaleBarSteps_um[0] * 1e-6) / metres_per_pixel;
    for (int i = 0; i < kScaleBarStepCount; ++i) {
        const double px = (kScaleBarSteps_um[i] * 1e-6) / metres_per_pixel;
        if (px <= max_px) { c.length_um = kScaleBarSteps_um[i]; c.length_px = px; }
    }
    return c;
}

} // namespace astro::ui
