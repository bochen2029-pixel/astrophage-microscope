// src/app/cli.h -- command line. The M1 gate drives the app through these.
#pragma once

#include <cstdint>

#include "contracts/render_view_v2.h"

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

    bool     headless   = false;     // hidden window; still a real GL context
    bool     gl_debug   = false;     // GL_DEBUG_OUTPUT; nonzero errors fail
    bool     benchmark  = false;     // timed run, exits nonzero if below target
    int      frames     = 0;         // 0 = run until the window closes
    bool     vsync      = false;     // off by default so --benchmark is honest

    const char* screenshot = nullptr; // write a PPM of the final frame and exit
    // Suppress all ImGui drawing. Golden images must test the RENDERER, not the
    // panel layout -- otherwise every HUD tweak invalidates every golden.
    bool     no_ui      = false;
    float    focus_um   = 0.0f;      // focal plane, micrometres

    // Appearance only -- neither can reach sim/ (ADR-023). Goldens used as
    // measurement oracles pin morphology to Sphere and the aperture to 0.
    contract::Morphology morphology = contract::Morphology::Irregular;
    float    aperture   = 0.92f;     // field diaphragm radius; 0 = full rectangle
    bool     help       = false;
    bool     bad        = false;
};

Options parse_args(int argc, char** argv);
void    print_usage();

} // namespace astro::app
