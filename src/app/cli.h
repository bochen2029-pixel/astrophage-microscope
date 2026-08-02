// src/app/cli.h -- command line. The M1 gate drives the app through these.
#pragma once

#include <cstdint>

namespace astro::app {

struct Options {
    int32_t  cells      = 0;         // 0 = canon::DEFAULT_CELLS
    uint64_t seed       = 20260802ull;
    float    charge     = 0.0f;      // initial charge fraction for every cell
    int      width      = 1600;
    int      height     = 1000;

    bool     headless   = false;     // hidden window; still a real GL context
    bool     gl_debug   = false;     // GL_DEBUG_OUTPUT; nonzero errors fail
    bool     benchmark  = false;     // timed run, exits nonzero if below target
    int      frames     = 0;         // 0 = run until the window closes
    bool     vsync      = false;     // off by default so --benchmark is honest

    const char* screenshot = nullptr; // write a PPM of the final frame and exit
    bool     help       = false;
    bool     bad        = false;
};

Options parse_args(int argc, char** argv);
void    print_usage();

} // namespace astro::app
