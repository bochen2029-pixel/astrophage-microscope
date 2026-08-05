// src/ui/hud.h -- M1 HUD: clock, counts, frame rate, scope controls, scale bar.
//
// This module owns SI -> display conversion. Everything arrives in metres,
// kelvin, joules; the user sees um, degC, mW, ng (src/ui/MODULE.md).
#pragma once

#include <cstdint>

#include "contracts/render_view_v3.h"
#include "contracts/telemetry_v1.h"
#include "render/camera.h"

namespace astro::ui {

// Interactive tools. Inspect picks a cell; Heat/Chill/CO2/N2 paint a field brush (M13a); Light
// drags a spotlight cells herd to and Grab tows a cell with an optical trap (M13b). Kept in ui
// because the tool -> sim mapping is done app-side (ui may not include sim). Heat..N2 keep the
// values --auto-poke maps to (1..4); Light/Grab are appended so those mappings are unchanged.
enum ToolKind : int {
    TOOL_INSPECT = 0, TOOL_HEAT, TOOL_CHILL, TOOL_CO2, TOOL_N2, TOOL_LIGHT, TOOL_GRAB, TOOL_COUNT
};

struct HudState {
    contract::ViewMode        mode    = contract::ViewMode::Brightfield;
    contract::AnalysisChannel channel = contract::AnalysisChannel::Charge;
    bool colorblind = false;   // swap the petrova-film LUT for magma (M12e)
    // Cross-fade (M12f): dissolve the view toward mode_blend_to. 0 = mode only, so an
    // untouched run renders exactly as before (every golden is captured at blend 0).
    contract::ViewMode        mode_blend_to = contract::ViewMode::Brightfield;
    float                     mode_blend    = 0.0f;

    // Interactive tools (M13a). The active tool, the brush geometry, and the pending poke the
    // input handler sets from the cursor -- applied at a tick boundary by the app, because
    // world_apply_brush must never be called from an input handler (it writes device memory).
    int    active_tool = TOOL_INSPECT;
    float  brush_radius_um = 180.0f;
    float  brush_strength  = 0.5f;     // normalised [0,1]; the app scales it per tool
    bool   poke_active = false;        // set each frame the left button paints a brush
    double poke_x = 0.0, poke_y = 0.0; // chamber coordinates [m]

    // Light and Grab tools (M13b). light_active: the Light tool is held, so the app parks a light
    // spot at (poke_x, poke_y) and awake cells herd to it. grab_active: the Grab tool is held, so
    // the app tows the picked cell toward (poke_x, poke_y). trap_strength scales the trap spring off
    // the stability-limited CONTACT_STIFFNESS (the app clamps it); poke_x/y are shared by all tools.
    bool   light_active  = false;
    bool   grab_active   = false;
    float  trap_strength = 1.5f;       // multiple of CONTACT_STIFFNESS

    // Set by the panel, consumed and cleared by the application.
    bool    respawn_requested = false;
    int32_t respawn_count = 0;
    float   respawn_charge = 0.0f;

    // Live charge control: recharges the whole population in place. This is how
    // P1 is demonstrated interactively -- sweep past the neutral line and the
    // culture stops rising and starts sinking.
    bool    set_charge_requested = false;
    float   live_charge = 0.0f;
    bool    paused = false;

    // Clock control (ADR-011, ADR-027). The panel sets these; the app applies them
    // via sim::world_set_clock at a tick boundary. `clock_preset` indexes
    // contract::ClockPreset; the custom rates are used only when it is Custom.
    int     clock_preset = 0;
    float   clock_physics = 1.0f;
    float   clock_biology = 1.0f;
    bool    clock_change_requested = false;

    float fps = 0.0f;
    float frame_ms = 0.0f;

    // The living-screensaver demo (M14a). The app mirrors its state here before hud_draw and reads
    // the toggles back: demo_active gates the panel, demo_paused freezes auto-advance, demo_next asks
    // for the next act. demo_act_name/index/count label the current act (app-owned strings).
    bool        demo_active = false;
    bool        demo_paused = false;
    bool        demo_next = false;
    const char* demo_act_name = nullptr;
    int         demo_act_index = 0;
    int         demo_act_count = 0;

    // Time scrubber (M12d). The app fills scrub_count and the selected frame's clock; the
    // Timeline slider sets scrub_selected + scrub_seek_requested when the user rewinds, and
    // scrub_live toggles between playing/recording and viewing a past frame.
    int    scrub_count = 0;          // frames available in the ring (app-filled)
    int    scrub_selected = 0;       // slider position, [0, scrub_count - 1]
    double scrub_sel_time_s = 0.0;   // sim time of the selected frame (app-filled)
    bool   scrub_seek_requested = false;
    bool   scrub_live = true;        // true: playing/recording; false: viewing a past frame
};

// A scrolling history of the telemetry for the population / energy / temperature
// charts (M9c). Fixed-size ring buffers -- no per-frame allocation, and the app
// owns one for the whole run so the history survives across frames.
struct ChartState {
    static constexpr int CAPACITY = 240;
    float live[CAPACITY]     = {};
    float dead[CAPACITY]     = {};
    float energy_gj[CAPACITY]= {};   // total store, gigajoules (kiloton scale)
    float temp_c[CAPACITY]   = {};   // medium temperature, degrees Celsius
    float tau_tol[CAPACITY]  = {};   // mean Taumoeba N2 tolerance -- the 82.5 arc (M10b)
    int      head  = 0;              // next write position
    int      count = 0;              // samples recorded so far (<= CAPACITY)
    uint64_t last_tick = ~0ull;      // append only when the sim tick advances
};

// The parameter inspector and cell inspector arrive at M11.
void hud_draw(HudState& hud, const contract::Stats& stats, render::Camera& cam,
              int32_t capacity, double chamber_w, double chamber_h, double chamber_d);

// Population / energy / temperature time series (M9c). Samples `stats` into the
// ring buffers when the tick advances, then plots them.
void chart_panel_draw(ChartState& charts, const contract::Stats& stats);

// Overlay, drawn on ImGui's foreground list so it sits above everything.
// A microscope without a scale bar is a lava lamp (docs/RENDERING.md Sec 7.6).
void draw_scale_bar(const render::Camera& cam, int fb_w, int fb_h);

// The active-tool brush ring at the cursor (M13a). Drawn at true brush size (µm → px via the
// camera), coloured by tool, so a poke lands where and how big the user expects. A no-op for the
// Inspect tool.
void draw_cursor_ring(const render::Camera& cam, int active_tool, float brush_radius_um,
                      int fb_w, int fb_h);

// Shows where the focal plane sits in the chamber and how thin the sharp band
// is. Drawn inline in the scope panel, under the focal-plane slider.
void draw_focus_gauge(const render::Camera& cam, double chamber_d);

// The demo act caption (M14b): a large fade-in title near the top, over the chamber, drawn on the
// foreground list like the scale bar. `alpha` in [0,1] fades it in at the act's start and out at its
// end. A no-op at alpha <= 0 or a null caption.
void draw_demo_caption(const char* caption, float alpha);

} // namespace astro::ui
