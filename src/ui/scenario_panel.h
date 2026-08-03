// src/ui/scenario_panel.h -- the objective/acceptance panel (M11e).
//
// The accept checkmarks for a loaded scenario. `ui` may not include `sim` (ui/MODULE.md),
// and accept_eval / metric_measure live in `sim`, so the APP (which links both) evaluates
// the checks and hands this plain-data array to the panel. No sim type crosses the boundary.
#pragma once

namespace astro::ui {

struct ObjectiveCheck {
    const char* metric;    // metric name (from sim::metric_name)
    const char* op;        // comparison symbol (==, ~=, <, >= ...)
    double      measured;  // valid only when `live`
    double      target;
    bool        pass;
    bool        live;      // false: a derived metric only meaningful at run end
};

// Draws the objective text and one row per accept check. `checks`/`count` and the objective
// text are supplied by the app; a null/empty scenario shows the idle state.
void scenario_panel_draw(const char* objective, const ObjectiveCheck* checks, int count,
                         bool has_scenario);

} // namespace astro::ui
