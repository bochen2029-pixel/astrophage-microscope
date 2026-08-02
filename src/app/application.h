// src/app/application.h -- composition root. The only place globals are allowed.
#pragma once

#include "app/cli.h"
#include "core/result.h"
#include "render/camera.h"
#include "render/cells_pass.h"
#include "render/gl_context.h"
#include "sim/world.cuh"
#include "ui/hud.h"

namespace astro::app {

struct Application {
    Options            options;
    render::GlContext  gl;
    render::CellsPass  cells_pass;
    render::Camera     camera;
    sim::World         world;
    ui::HudState       hud;

    double accumulator = 0.0;   // fixed-tick residue, seconds
    int    frames_done = 0;

    // Benchmark accounting, in milliseconds.
    double bench_total_ms = 0.0;
    double bench_worst_ms = 0.0;
    int    bench_frames = 0;
};

Error app_init(Application& a, const Options& o);
void  app_shutdown(Application& a);

// Returns the process exit code: 0 = success, nonzero = a gate condition failed.
int   app_run(Application& a);

} // namespace astro::app
