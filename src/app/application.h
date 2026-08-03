// src/app/application.h -- composition root. The only place globals are allowed.
#pragma once

#include "app/cli.h"
#include "core/params.h"
#include "core/result.h"
#include "render/camera.h"
#include "render/cells_pass.h"
#include "render/gl_context.h"
#include "render/post_pass.h"
#include "sim/accept.h"
#include "sim/world.cuh"
#include "ui/hud.h"
#include "ui/scenario_panel.h"

namespace astro::app {

struct Application {
    Options            options;
    render::GlContext  gl;
    render::CellsPass  cells_pass;
    render::PostPass   post_pass;
    render::Camera     camera;
    sim::World         world;
    ui::HudState       hud;
    ui::ChartState     charts;   // scrolling population / energy / temperature history

    // A loaded scenario auto-plays its drive script in the tick loop (M11d). Zero-sized
    // accept/drive when none was requested, so has_scenario gates the extra work.
    contract::Scenario scenario{};
    bool               has_scenario = false;

    // The runtime-parameter overlay the inspector edits (ADR-034). Initialised from canon
    // in app_init; its non_canon_run flag is mirrored into the World each frame.
    astro::ParamSet    params{};

    // The objective panel evaluates the scenario's accept checks app-side each HUD tick
    // (ui may not include sim) and hands the results to scenario_panel_draw (M11e).
    sim::RunAggregates obj_agg;
    sim::MetricNeeds   obj_needs{};
    ui::ObjectiveCheck obj_checks[contract::MAX_ACCEPT_CHECKS]{};
    int                obj_count = 0;

    double accumulator = 0.0;   // fixed-tick residue, seconds
    int    frames_done = 0;
    // Refreshed at HUD rate, not per frame: the stage-11 reduction ends in a
    // synchronous D2H (ARCHITECTURE.md Sec 3.1).
    contract::Stats stats_cache{};

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
