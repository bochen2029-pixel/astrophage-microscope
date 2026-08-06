// src/app/application.h -- composition root. The only place globals are allowed.
#pragma once

#include <cstdint>
#include <vector>

#include "app/cli.h"
#include "core/params.h"
#include "core/result.h"
#include "render/bloom.h"
#include "render/camera.h"
#include "render/cells_pass.h"
#include "render/field_pass.h"
#include "render/gl_context.h"
#include "render/post_pass.h"
#include "sim/accept.h"
#include "sim/world.cuh"
#include "ui/hud.h"
#include "ui/inspector_panel.h"
#include "ui/scenario_panel.h"

namespace astro::app {

struct Application {
    Options            options;
    render::GlContext  gl;
    render::CellsPass  cells_pass;
    render::PostPass   post_pass;
    render::BloomPass  bloom;
    render::FieldPass  field;              // T-field false-colour behind Thermal IR (M12i)
    std::vector<float> field_host;         // T-grid D2H scratch for the field pass
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

    // The curated live-tunable overrides (ADR-035): the ParamSet indices the sim reads,
    // resolved once, and the per-index "the sim reads this" flags the parameter panel uses
    // to decide which parameters get an editable slider. The app pushes params.value into
    // the matching World fields each frame.
    int32_t param_idx_max_power   = -1;
    int32_t param_idx_flash_power = -1;
    int32_t param_idx_co2_quota   = -1;
    bool    param_live[canon::PARAM_COUNT] = {};

    // The cell inspector (M11f): the picked slot and the id latched at pick time (so a
    // recycled slot drops the pick rather than showing a different cell), plus the plain-
    // data readout the app fills at HUD rate and hands to inspector_panel_draw.
    bool             has_pick = false;
    int32_t          pick_slot = -1;
    uint64_t         pick_id = 0;
    ui::CellReadout  cell_readout{};

    // The objective panel evaluates the scenario's accept checks app-side each HUD tick
    // (ui may not include sim) and hands the results to scenario_panel_draw (M11e).
    sim::RunAggregates obj_agg;
    sim::MetricNeeds   obj_needs{};
    ui::ObjectiveCheck obj_checks[contract::MAX_ACCEPT_CHECKS]{};
    int                obj_count = 0;

    // The time scrubber (M12d): a rolling ring of full-state snapshots the user rewinds through.
    // Bounded by total bytes so a large population can't exhaust host memory; recorded during live
    // play (never under --benchmark). Seeking restores a past frame and re-applies the motion
    // config snapshot_v1 does not carry (ADR-036/038).
    struct ScrubFrame { std::vector<char> bytes; uint64_t tick = 0; double sim_time_s = 0.0; };
    std::vector<ScrubFrame> scrub_ring;
    size_t            scrub_bytes = 0;
    uint64_t          scrub_last_tick = 0;
    sim::MotionConfig scrub_motion{};

    // The living-screensaver demo (M14a): a playlist of scenario "acts" cycled with camera + view
    // choreography. Populated only under --demo; the interop VBO was sized to the playlist's max
    // capacity at init, so the world rebuild each act does always fits. `act` indexes DEMO_PLAYLIST.
    struct DemoState {
        bool active = false;
        int  act = -1;                  // current playlist index, -1 before the first load
        bool paused = false;            // freeze auto-advance on the current act (HUD toggle)
        bool advance_requested = false; // HUD "next act" button
    };
    DemoState demo;

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
