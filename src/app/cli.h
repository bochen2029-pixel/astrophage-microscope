// src/app/cli.h -- command line. The M1 gate drives the app through these.
#pragma once

#include <cstdint>

#include "contracts/render_view_v3.h"

namespace astro::app {

struct Options {
    int32_t  cells      = 0;         // 0 = canon::DEFAULT_CELLS
    uint64_t seed       = 20260802ull;
    float    charge     = 0.0f;      // initial charge fraction for every cell
    int      width      = 1600;
    int      height     = 1000;
    // Scope state from the command line, so golden images (M3) are reproducible
    // without driving the UI.
    int      objective  = -1;        // -1 = canon::OBJECTIVE_DEFAULT
    float    zoom       = 1.0f;
    // Fixed ticks per frame decouples the simulation from wall-clock entirely:
    // the same command produces the same simulated time on any machine, which is
    // what golden captures (M3) require. 0 = real-time accumulator.
    int      ticks_per_frame = 0;

    // Multi-rate clock (ADR-011/ADR-027). clock_preset indexes ClockPreset
    // (0 Realtime, 1 Motion, 2 Metabolic, 3 Generational, 4 Custom); the explicit
    // rates apply only when Custom, and passing either flag selects Custom.
    int      clock_preset  = 0;
    double   physics_rate  = 1.0;
    double   biology_rate  = 1.0;

    bool     headless   = false;     // hidden window; still a real GL context
    bool     gl_debug   = false;     // GL_DEBUG_OUTPUT; nonzero errors fail
    bool     benchmark  = false;     // timed run, exits nonzero if below target
    int      frames     = 0;         // 0 = run until the window closes
    bool     vsync      = false;     // off by default so --benchmark is honest

    const char* screenshot = nullptr; // write a PPM of the final frame and exit
    const char* scenario   = nullptr; // load a scenario and auto-play its drive script (M11d)
    // Pre-select a cell slot for the inspector (M11f). Picking is a mouse click, which a
    // headless run cannot make, so this is how the inspector panel is verified in a
    // screenshot. -1 = no pre-pick (the normal interactive path clicks to select).
    int32_t  inspect_slot = -1;
    // On the final frame, rewind to recorded scrubber frame N (M12d), so the seek path is
    // verifiable in a headless screenshot (the Timeline slider is a mouse drag otherwise).
    // -1 = no seek.
    int32_t  scrub_to = -1;
    // Headless stand-in for a held mouse brush (M13a): apply the named tool at the chamber
    // centre every frame (a drag is not expressible headless, like --inspect). -1 = off, else a
    // ui::ToolKind int (1 Heat, 2 Chill, 3 CO2, 4 N2).
    int      auto_poke = -1;
    // Headless stand-in for the M13b light-leash: park a bright spot off-centre in +x every frame,
    // so awake sub-0.95-charge cells herd toward it; the end-state centroid readout is the gate.
    bool     auto_light = false;
    // Headless stand-in for the M13b optical tweezers: tow cell slot N to (auto_grab_x, auto_grab_y)
    // [m] every frame; the end-state distance-to-target readout is the gate. -1 = off.
    int32_t  auto_grab_slot = -1;
    double   auto_grab_x = 0.0, auto_grab_y = 0.0;
    // The living-screensaver demo (M14a): cycle a playlist of scenario acts with camera + view
    // choreography, looping. Default-off so every gate is unmoved; ignores --scenario.
    bool     demo = false;
    // Suppress all ImGui drawing. Golden images must test the RENDERER, not the
    // panel layout -- otherwise every HUD tweak invalidates every golden.
    bool     no_ui      = false;
    float    focus_um   = 0.0f;      // focal plane, micrometres

    // Appearance only -- neither can reach sim/ (ADR-023). Goldens used as
    // measurement oracles pin morphology to Sphere and the aperture to 0.
    contract::Morphology morphology = contract::Morphology::Irregular;
    float    aperture   = 0.92f;     // field diaphragm radius; 0 = full rectangle
    bool     no_bloom   = false;     // disable the Petrovascope emission bloom (M12h); goldens pin this

    // Initial view mode, and whether the population spawns awake -- both needed to
    // capture the non-brightfield modes headless (an awake idle cell glows in
    // Thermal IR and is dark in the Petrovascope).
    contract::ViewMode view_mode = contract::ViewMode::Brightfield;
    bool     view_mode_set = false;  // was --mode given (so it overrides a scenario's scope.mode)
    bool     awake      = false;
    bool     colorblind = false;     // colourblind-safe LUT (M12e); also a HUD toggle
    // Cross-fade (M12f), so a blended frame is capturable headless for the gate. mode_blend 0
    // renders `view_mode` alone (every golden is at 0); mode_blend_to defaults to Brightfield.
    contract::ViewMode mode_blend_to = contract::ViewMode::Brightfield;
    float    mode_blend = 0.0f;

    bool     help       = false;
    bool     bad        = false;
};

Options parse_args(int argc, char** argv);
void    print_usage();

} // namespace astro::app
