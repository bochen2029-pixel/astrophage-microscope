// src/ui/hud.h -- M1 HUD: clock, counts, frame rate, scope controls, scale bar.
//
// This module owns SI -> display conversion. Everything arrives in metres,
// kelvin, joules; the user sees um, degC, mW, ng (src/ui/MODULE.md).
#pragma once

#include <cstdint>

#include "contracts/render_view_v1.h"
#include "contracts/telemetry_v1.h"
#include "render/camera.h"

namespace astro::ui {

struct HudState {
    contract::ViewMode        mode    = contract::ViewMode::Brightfield;
    contract::AnalysisChannel channel = contract::AnalysisChannel::Charge;

    // Set by the panel, consumed and cleared by the application.
    bool    respawn_requested = false;
    int32_t respawn_count = 0;
    float   respawn_charge = 0.0f;

    float fps = 0.0f;
    float frame_ms = 0.0f;
};

// The parameter inspector, cell inspector, and charts arrive at M9/M11.
void hud_draw(HudState& hud, const contract::Stats& stats, render::Camera& cam,
              int32_t capacity, double chamber_w, double chamber_h, double chamber_d);

// Overlay, drawn on ImGui's foreground list so it sits above everything.
// A microscope without a scale bar is a lava lamp (docs/RENDERING.md Sec 7.6).
void draw_scale_bar(const render::Camera& cam, int fb_w, int fb_h);

} // namespace astro::ui
