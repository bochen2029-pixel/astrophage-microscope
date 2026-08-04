// src/app/cli.cpp
#include "app/cli.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace astro::app {

void print_usage() {
    std::printf(
        "astrophage -- Astrophage Microscope Simulator\n"
        "\n"
        "  --cells N          initial population (default: canon DEFAULT_CELLS)\n"
        "  --seed N           master seed\n"
        "  --charge F         initial charge fraction, 0..1\n"
        "  --objective N      0 = 10x survey, 1 = 40x working, 2 = 100x detail\n"
        "  --zoom F           digital zoom on top of the objective\n"
        "  --focus F          focal plane in micrometres from chamber centre\n"
        "  --no-ui            suppress all ImGui drawing (for golden captures)\n"
        "  --mode NAME        brightfield | darkfield | petrovascope | thermal | analysis\n"
        "  --awake            spawn the population awake (glows in Thermal IR)\n"
        "  --colorblind       colourblind-safe LUT (magma instead of petrova-film)\n"
        "  --morphology M     sphere | irregular  (appearance only; goldens pin sphere)\n"
        "  --aperture F       field diaphragm radius, 0 = full rectangle\n"
        "  --ticks-per-frame N  fixed ticks per frame, ignoring wall clock;\n"
        "                       makes a capture reproducible on any machine\n"
        "  --clock NAME       realtime | motion | metabolic | generational | custom\n"
        "  --physics-rate F   physics clock multiplier (implies --clock custom)\n"
        "  --biology-rate F   biology clock multiplier (implies --clock custom)\n"
        "  --width N          window width\n"
        "  --height N         window height\n"
        "  --frames N         run N frames then exit (0 = until closed)\n"
        "  --headless         hidden window; still a real GL context\n"
        "  --gl-debug         enable GL debug output; any error fails the run\n"
        "  --benchmark        timed run; exits nonzero below the fps target\n"
        "  --vsync            cap to the display refresh (off by default)\n"
        "  --screenshot PATH  write a PPM of the last frame\n"
        "  --scenario ID      load a scenario and auto-play its drive script\n"
        "  --inspect N        pre-select cell slot N in the inspector (headless picking)\n"
        "  --scrub-to N       on the last frame, rewind to recorded timeline frame N\n"
        "  --help\n");
}

Options parse_args(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        const char* a = argv[i];
        auto want = [&](const char* name) { return std::strcmp(a, name) == 0; };
        auto next_int = [&](long long dflt) -> long long {
            if (i + 1 >= argc) { o.bad = true; return dflt; }
            return std::atoll(argv[++i]);
        };
        if      (want("--cells"))      o.cells  = static_cast<int32_t>(next_int(o.cells));
        else if (want("--seed"))       o.seed   = static_cast<uint64_t>(next_int(20260802));
        else if (want("--width"))      o.width  = static_cast<int>(next_int(o.width));
        else if (want("--height"))     o.height = static_cast<int>(next_int(o.height));
        else if (want("--frames"))     o.frames = static_cast<int>(next_int(o.frames));
        else if (want("--objective")) o.objective = static_cast<int>(next_int(-1));
        else if (want("--ticks-per-frame")) o.ticks_per_frame = static_cast<int>(next_int(0));
        else if (want("--charge")) {
            if (i + 1 >= argc) o.bad = true;
            else o.charge = static_cast<float>(std::atof(argv[++i]));
        }
        else if (want("--zoom")) {
            if (i + 1 >= argc) o.bad = true;
            else o.zoom = static_cast<float>(std::atof(argv[++i]));
        }
        else if (want("--no-ui"))      o.no_ui     = true;
        else if (want("--morphology")) {
            if (i + 1 >= argc) { o.bad = true; }
            else {
                const char* m = argv[++i];
                if (std::strcmp(m, "sphere") == 0)         o.morphology = contract::Morphology::Sphere;
                else if (std::strcmp(m, "irregular") == 0) o.morphology = contract::Morphology::Irregular;
                else                                       o.bad = true;
            }
        }
        else if (want("--aperture")) {
            if (i + 1 >= argc) o.bad = true;
            else {
                const double v = std::atof(argv[++i]);
                if (v < 0.0 || v > 2.0) o.bad = true;
                else o.aperture = static_cast<float>(v);
            }
        }
        else if (want("--focus")) {
            if (i + 1 >= argc) o.bad = true;
            else o.focus_um = static_cast<float>(std::atof(argv[++i]));
        }
        else if (want("--clock")) {
            if (i + 1 >= argc) { o.bad = true; }
            else {
                const char* m = argv[++i];
                if      (std::strcmp(m, "realtime") == 0)     o.clock_preset = 0;
                else if (std::strcmp(m, "motion") == 0)       o.clock_preset = 1;
                else if (std::strcmp(m, "metabolic") == 0)    o.clock_preset = 2;
                else if (std::strcmp(m, "generational") == 0) o.clock_preset = 3;
                else if (std::strcmp(m, "custom") == 0)       o.clock_preset = 4;
                else                                          o.bad = true;
            }
        }
        else if (want("--physics-rate")) {
            if (i + 1 >= argc) o.bad = true;
            else { o.physics_rate = std::atof(argv[++i]); o.clock_preset = 4; }
        }
        else if (want("--biology-rate")) {
            if (i + 1 >= argc) o.bad = true;
            else { o.biology_rate = std::atof(argv[++i]); o.clock_preset = 4; }
        }
        else if (want("--mode")) {
            if (i + 1 >= argc) { o.bad = true; }
            else {
                const char* m = argv[++i];
                o.view_mode_set = true;   // explicit --mode overrides a scenario's scope.mode
                if      (std::strcmp(m, "brightfield") == 0)  o.view_mode = contract::ViewMode::Brightfield;
                else if (std::strcmp(m, "darkfield") == 0)    o.view_mode = contract::ViewMode::Darkfield;
                else if (std::strcmp(m, "petrovascope") == 0) o.view_mode = contract::ViewMode::Petrovascope;
                else if (std::strcmp(m, "thermal") == 0)      o.view_mode = contract::ViewMode::ThermalIR;
                else if (std::strcmp(m, "analysis") == 0)     o.view_mode = contract::ViewMode::Analysis;
                else                                          o.bad = true;
            }
        }
        else if (want("--awake"))      o.awake     = true;
        else if (want("--colorblind")) o.colorblind = true;
        else if (want("--headless"))   o.headless  = true;
        else if (want("--gl-debug"))   o.gl_debug  = true;
        else if (want("--benchmark"))  o.benchmark = true;
        else if (want("--vsync"))      o.vsync     = true;
        else if (want("--screenshot")) {
            if (i + 1 >= argc) o.bad = true; else o.screenshot = argv[++i];
        }
        else if (want("--scenario")) {
            if (i + 1 >= argc) o.bad = true; else o.scenario = argv[++i];
        }
        else if (want("--inspect")) o.inspect_slot = static_cast<int32_t>(next_int(-1));
        else if (want("--scrub-to")) o.scrub_to = static_cast<int32_t>(next_int(-1));
        else if (want("--help") || want("-h")) o.help = true;
        else { std::printf("unknown argument: %s\n", a); o.bad = true; }
    }
    // A benchmark that runs forever measures nothing; give it a default length.
    if (o.benchmark && o.frames == 0) o.frames = 600;
    // vsync would cap the measurement at the refresh rate.
    if (o.benchmark) o.vsync = false;
    // A benchmark MUST NOT use the real-time accumulator. Slower frames make it
    // request more substeps, which makes frames slower still, until it pins at
    // the 8-substep cap -- so it reports a feedback equilibrium rather than
    // throughput. One tick per frame measures the thing we actually want.
    if (o.benchmark && o.ticks_per_frame == 0) o.ticks_per_frame = 1;
    return o;
}

} // namespace astro::app
