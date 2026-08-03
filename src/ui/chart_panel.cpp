// src/ui/chart_panel.cpp -- population / energy / temperature time series (M9c).
//
// The data all comes from the stage-11 reduction (contract::Stats), which is
// already refreshed at HUD rate, so this panel adds no device work -- it only
// keeps a scrolling history and plots it.
#include "ui/hud.h"

#include <cstdio>

#include "imgui.h"

#include "core/canon_generated.h"

namespace astro::ui {

using contract::Stats;

namespace {

// Min/max over the used portion of a ring buffer, so each plot auto-scales to
// what it is actually showing rather than to a guessed fixed range.
void range_of(const float* v, int count, float& lo, float& hi) {
    lo = 0.0f;
    hi = 1.0f;
    if (count <= 0) return;
    lo = v[0];
    hi = v[0];
    for (int i = 1; i < count; ++i) {
        if (v[i] < lo) lo = v[i];
        if (v[i] > hi) hi = v[i];
    }
    if (hi <= lo) hi = lo + 1.0f;   // never a zero-height plot
}

} // namespace

void chart_panel_draw(ChartState& c, const Stats& stats) {
    // One sample per SIM tick, not per frame: a paused sim must not pack the
    // history with flat repeats, and this is what makes the x-axis simulated time.
    if (stats.tick != c.last_tick) {
        c.last_tick = stats.tick;
        c.live[c.head]      = static_cast<float>(stats.n_live);
        c.dead[c.head]      = static_cast<float>(stats.n_dead);
        c.energy_gj[c.head] = static_cast<float>(stats.total_energy_j / 1.0e9);
        c.temp_c[c.head]    = static_cast<float>(stats.mean_temp_medium_k - 273.15);
        c.tau_tol[c.head]   = static_cast<float>(stats.mean_tau_tolerance);
        c.head = (c.head + 1) % ChartState::CAPACITY;
        if (c.count < ChartState::CAPACITY) ++c.count;
    }

    ImGui::SetNextWindowPos(ImVec2(12, 470), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(360, 0), ImGuiCond_FirstUseEver);
    ImGui::Begin("Charts");

    // values_offset = head reads oldest-first in both the not-yet-full and the
    // wrapped case, since count == head until the buffer fills.
    const int n = c.count;
    const int off = c.head;
    const ImVec2 sz(0.0f, 58.0f);
    char overlay[80];
    float lo = 0.0f, hi = 1.0f;

    range_of(c.live, n, lo, hi);
    std::snprintf(overlay, sizeof(overlay), "live %d   dead %d", stats.n_live, stats.n_dead);
    ImGui::PlotLines("population", c.live, n, off, overlay, 0.0f, hi * 1.1f, sz);

    range_of(c.energy_gj, n, lo, hi);
    std::snprintf(overlay, sizeof(overlay), "%.3g GJ  (%.3g kt TNT)",
                  stats.total_energy_j / 1.0e9, stats.total_energy_j / canon::TNT_JOULE / 1.0e9);
    ImGui::PlotLines("energy", c.energy_gj, n, off, overlay, 0.0f, hi * 1.1f, sz);

    range_of(c.temp_c, n, lo, hi);
    std::snprintf(overlay, sizeof(overlay), "%.2f C medium  (max %.2f C)",
                  stats.mean_temp_medium_k - 273.15, stats.max_temp_medium_k - 273.15);
    ImGui::PlotLines("medium temp", c.temp_c, n, off, overlay, lo - 1.0f, hi + 1.0f, sz);

    // Only once predators exist: the mean N2 tolerance is the Taumoeba-82.5 readout,
    // and it climbs under a rising nitrogen ramp (M10b). Fixed 0..1 axis so the 0.825
    // strain sits at a legible height rather than auto-scaling away.
    if (stats.n_taumoeba > 0) {
        std::snprintf(overlay, sizeof(overlay), "%.3f mean tol   (%d Taumoeba)",
                      stats.mean_tau_tolerance, stats.n_taumoeba);
        ImGui::PlotLines("Taumoeba tol", c.tau_tol, n, off, overlay, 0.0f, 1.0f, sz);
    }

    ImGui::Text("this window:  +%d divisions   -%d deaths",
                stats.divisions_this_window, stats.deaths_this_window);
    ImGui::End();
}

} // namespace astro::ui
