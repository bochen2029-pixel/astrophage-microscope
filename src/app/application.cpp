// src/app/application.cpp
#include "app/application.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include <glad/gl.h>
#include <GLFW/glfw3.h>

#include "imgui.h"

#include "core/canon_generated.h"
#include "core/units.h"
#include "sim/scenario.h"
#include "ui/params_panel.h"

#ifndef ASTRO_SCENARIOS_DIR
#define ASTRO_SCENARIOS_DIR "scenarios"
#endif

namespace astro::app {

namespace {

// GLFW has no polling API for scroll, so it must come through a callback.
// Single window, single context: a file-scope accumulator inside the
// composition root is the right amount of machinery here.
double g_scroll_y = 0.0;
void scroll_callback(GLFWwindow*, double, double yoff) { g_scroll_y += yoff; }

Error spawn_population(sim::World& w, int32_t count, float charge, uint64_t seed,
                       bool awake = false) {
    sim::SpawnParams p;
    p.count       = count;
    p.placement   = sim::Placement::Uniform;
    p.charge_dist = sim::Distribution::Constant;
    p.charge_a    = charge;
    p.awake       = awake;
    return sim::cell_store_spawn(w.cells, p, w.chamber, seed);
}

// PPM, because it needs no image library and Iron Rule 8 makes every dependency
// an ADR. Screenshots are for eyeballing a build, not for shipping.
bool write_ppm(const char* path, int w, int h) {
    std::vector<unsigned char> px(static_cast<size_t>(w) * h * 3);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, w, h, GL_RGB, GL_UNSIGNED_BYTE, px.data());

    std::FILE* f = std::fopen(path, "wb");
    if (!f) { std::printf("[app] cannot open %s\n", path); return false; }
    std::fprintf(f, "P6\n%d %d\n255\n", w, h);
    // glReadPixels returns bottom-up; PPM is top-down.
    for (int y = h - 1; y >= 0; --y)
        std::fwrite(px.data() + static_cast<size_t>(y) * w * 3, 1, static_cast<size_t>(w) * 3, f);
    std::fclose(f);
    std::printf("[app] wrote %s (%dx%d)\n", path, w, h);
    return true;
}

const char* op_symbol(contract::CompareOp op) {
    switch (op) {
        case contract::CompareOp::Eq: return "==";
        case contract::CompareOp::Ne: return "!=";
        case contract::CompareOp::Lt: return "<";
        case contract::CompareOp::Le: return "<=";
        case contract::CompareOp::Gt: return ">";
        case contract::CompareOp::Ge: return ">=";
        case contract::CompareOp::Approx: return "~=";
    }
    return "?";
}

// Metrics that need the whole run (a velocity fit, a doubling series, the flash total) are
// not meaningful live; the panel shows those as "measured at run end" rather than a
// misleading cross. Everything else reads straight from the current Stats or a live download.
bool metric_is_live(contract::Metric m) {
    switch (m) {
        case contract::Metric::RiseVelocityEmpty:
        case contract::Metric::FallVelocityFull:
        case contract::Metric::DoublingTimeS:
        case contract::Metric::ImpulsePerCycle: return false;
        default: return true;
    }
}

// Evaluate the loaded scenario's accept block app-side (ui may not include sim) and fill the
// plain-data array the objective panel displays. Called at HUD rate, so the per-check
// downloads (correlations, max tolerance) cost a D2H a few times a second, not per frame.
void evaluate_objective(Application& a) {
    sim::aggregates_sample(a.obj_agg, a.stats_cache, a.world, a.obj_needs, 2.0, 4.0);
    a.obj_count = a.scenario.accept_count < contract::MAX_ACCEPT_CHECKS
                      ? a.scenario.accept_count : contract::MAX_ACCEPT_CHECKS;
    for (int i = 0; i < a.obj_count; ++i) {
        const contract::AcceptCheck& chk = a.scenario.accept[i];
        const double m = sim::metric_measure(chk.metric, a.stats_cache, a.obj_agg, a.world, a.scenario);
        a.obj_checks[i].metric   = sim::metric_name(chk.metric);
        a.obj_checks[i].op       = op_symbol(chk.op);
        a.obj_checks[i].measured = m;
        a.obj_checks[i].target   = chk.value;
        a.obj_checks[i].pass     = sim::accept_eval(chk, m);
        a.obj_checks[i].live     = metric_is_live(chk.metric);
    }
}

// The curated live-tunable overrides (ADR-035): copy the inspector's ParamSet values into
// the World fields the sim reads. Called every frame -- three assignments, and with no
// edits the values equal canon exactly, so world_step stays bit-identical to M11e.
void apply_param_overrides(Application& a) {
    if (a.param_idx_max_power   >= 0) a.world.petrova_max_power     = a.params.value[a.param_idx_max_power];
    if (a.param_idx_flash_power >= 0) a.world.petrova_flash_power   = a.params.value[a.param_idx_flash_power];
    if (a.param_idx_co2_quota   >= 0) a.world.co2_mass_per_division = a.params.value[a.param_idx_co2_quota];
}

const char* death_cause_name(uint8_t c) {
    switch (static_cast<contract::DeathCause>(c)) {
        case contract::DeathCause::Starved:    return "starved";
        case contract::DeathCause::Predated:   return "predated";
        case contract::DeathCause::Overheated: return "overheated";
        case contract::DeathCause::Culled:     return "culled";
        case contract::DeathCause::None:
        default:                               return "";
    }
}

// Download the picked cell and fill the display readout (M11f). At HUD rate for ONE cell.
// The buoyancy line reuses hud.cpp's exact density formula so the inspector and the HUD
// Charge section teach the same P1. A recycled slot (id changed) drops the pick.
void read_picked_cell(Application& a) {
    a.cell_readout.valid = false;
    if (!a.has_pick) return;
    sim::CellSample s;
    if (Error e = sim::cell_store_sample(a.world.cells, a.pick_slot, s)) {
        std::printf("[app] cell sample failed: %s\n", status_str(e.status));
        a.has_pick = false; a.pick_slot = -1; return;
    }
    if (!s.valid) { a.has_pick = false; a.pick_slot = -1; return; }   // slot emptied
    if (a.pick_id == 0) a.pick_id = s.id;                             // latch on first read
    else if (a.pick_id != s.id) { a.has_pick = false; a.pick_slot = -1; return; }  // recycled

    ui::CellReadout& r = a.cell_readout;
    r.valid = true;
    r.id = s.id;
    r.slot = a.pick_slot;
    r.x_um = m_to_um(s.x);  r.y_um = m_to_um(s.y);  r.z_um = m_to_um(s.z);
    r.vy_um_s = m_to_um(s.vy);                                        // gravity is along Y
    r.speed_um_s = m_to_um(std::sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz));
    r.charge_pct = s.energy / canon::CELL_ENERGY_MAX * 100.0;
    r.energy_j = s.energy;
    r.temp_c = k_to_c(static_cast<double>(s.temp_cell));
    r.biomass_ng = kg_to_ng(s.biomass);
    r.age_s = static_cast<double>(s.age_s);
    r.awake  = (s.flags & contract::CELL_FLAG_AWAKE) != 0u;
    r.alive  = (s.flags & contract::CELL_FLAG_ALIVE) != 0u;
    r.corpse = (s.flags & contract::CELL_FLAG_OCCUPIED) != 0u && !r.alive;
    r.death_cause = death_cause_name(s.death_cause);

    // P1 buoyancy line -- IDENTICAL formula to hud.cpp: mass = dry + E/c^2.
    const double mass = canon::CELL_MASS_DRY + s.energy / (canon::C_LIGHT * canon::C_LIGHT);
    r.density = mass / canon::CELL_VOLUME;
    r.density_ratio = r.density / canon::WATER_DENSITY;
    r.neutral_pct = canon::CHARGE_NEUTRAL_BUOYANCY * 100.0;
    r.sinking = r.charge_pct > r.neutral_pct;
}

// Mouse click -> chamber coordinate -> nearest cell (M11f). Picking is a click event, so a
// full positions download here is fine; the live readout then reads one cell at HUD rate.
void try_pick(Application& a, double px, double py) {
    const int32_t n = a.world.cells.count;
    if (n <= 0) return;
    double wx = 0.0, wy = 0.0;
    a.camera.screen_to_world(px, py, a.gl.fb_width, a.gl.fb_height, wx, wy);

    std::vector<double> x(n), y(n), z(n);
    if (Error e = sim::cell_store_download_positions(a.world.cells, x.data(), y.data(),
                                                     z.data(), n)) {
        std::printf("[app] pick download failed: %s\n", status_str(e.status));
        return;
    }
    // Accept a click within a generous radius of a cell; nearest wins. Scaled by the view,
    // with a metric floor so a zoomed-in click near a 10 um cell still lands.
    const double mpp = a.camera.metres_per_pixel(a.gl.fb_width, a.gl.fb_height);
    const double reach = astro_max(16.0 * mpp, 3.0 * canon::CELL_RADIUS);
    double best = reach * reach;
    int32_t best_i = -1;
    for (int32_t i = 0; i < n; ++i) {
        const double dx = x[i] - wx, dy = y[i] - wy;
        const double d2 = dx * dx + dy * dy;
        if (d2 < best) { best = d2; best_i = i; }
    }
    a.has_pick = best_i >= 0;
    a.pick_slot = best_i;
    a.pick_id = 0;                     // re-latched on the next read
    if (!a.has_pick) a.cell_readout.valid = false;
}

void handle_input(Application& a) {
    const ImGuiIO& io = ImGui::GetIO();
    GLFWwindow* win = a.gl.window;

    static bool dragging = false;
    static bool armed = false;          // a left press began over the chamber, not a panel
    static double last_x = 0.0, last_y = 0.0;
    static double press_x = 0.0, press_y = 0.0;
    static double moved = 0.0;          // cursor travel accumulated while the button is down
    double mx = 0.0, my = 0.0;
    glfwGetCursorPos(win, &mx, &my);

    const bool down = glfwGetMouseButton(win, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
    if (down && !io.WantCaptureMouse) {
        if (!armed) { armed = true; press_x = mx; press_y = my; moved = 0.0; }
        if (dragging) {
            a.camera.pan_pixels(mx - last_x, my - last_y, a.gl.fb_width, a.gl.fb_height);
            moved += std::abs(mx - last_x) + std::abs(my - last_y);
        }
        dragging = true;
    } else {
        // Release. A press that barely moved is a pick; a drag pans the stage (M11f).
        if (armed && moved < 4.0 && !io.WantCaptureMouse) try_pick(a, press_x, press_y);
        dragging = false;
        armed = false;
    }
    last_x = mx; last_y = my;

    if (g_scroll_y != 0.0 && !io.WantCaptureMouse) {
        // Cursor-anchored: the chamber point under the pointer stays put.
        const double factor = (g_scroll_y > 0.0) ? 1.15 : (1.0 / 1.15);
        for (int i = 0; i < static_cast<int>(g_scroll_y > 0 ? g_scroll_y : -g_scroll_y); ++i)
            a.camera.zoom_at(factor, mx, my, a.gl.fb_width, a.gl.fb_height);
    }
    g_scroll_y = 0.0;

    if (glfwGetKey(win, GLFW_KEY_ESCAPE) == GLFW_PRESS) glfwSetWindowShouldClose(win, GLFW_TRUE);
    if (glfwGetKey(win, GLFW_KEY_HOME) == GLFW_PRESS) {
        a.camera.center_x = a.camera.center_y = 0.0;
        a.camera.zoom = 1.0f;
    }

    a.camera.clamp_to_chamber(a.world.chamber.w, a.world.chamber.h,
                              a.gl.fb_width, a.gl.fb_height);
}

} // namespace

Error app_init(Application& a, const Options& o) {
    a.options = o;
    astro::param_set_init(a.params);   // the inspector's overlay, initialised from canon

    // The curated live-tunable set (ADR-035): resolve the ParamSet indices the sim reads and
    // flag them for the parameter panel (which draws a real slider only for these).
    a.param_idx_max_power   = param_index("PETROVA_MAX_POWER");
    a.param_idx_flash_power = param_index("PETROVA_FLASH_POWER");
    a.param_idx_co2_quota   = param_index("CO2_MASS_PER_DIVISION");
    for (int idx : {a.param_idx_max_power, a.param_idx_flash_power, a.param_idx_co2_quota})
        if (idx >= 0) a.param_live[idx] = true;

    // Build the World two ways: from a scenario (loaded + instantiated, which sizes its own
    // capacity, medium, populations, and clock) or a plain uniform population from the flags.
    int32_t capacity = 0;
    if (o.scenario) {
        const std::string id = o.scenario;
        const bool is_path = id.size() > 5 && id.compare(id.size() - 5, 5, ".json") == 0;
        const std::string path = is_path ? id
                                         : (std::string(ASTRO_SCENARIOS_DIR) + "/" + id + ".json");
        if (Error e = sim::scenario_load(path, a.scenario)) {
            std::printf("[app] scenario load failed (%s): %s\n", path.c_str(), status_str(e.status));
            return e;
        }
        if (Error e = sim::scenario_instantiate(a.scenario, a.world)) {
            std::printf("[app] scenario '%s' instantiate failed: %s\n", a.scenario.id,
                        status_str(e.status));
            return e;
        }
        a.has_scenario = true;
        a.obj_needs = sim::metric_needs(a.scenario);   // which aggregates the objective needs
        capacity = a.world.cells.capacity;
    } else {
        const int32_t count = o.cells > 0 ? o.cells : canon::DEFAULT_CELLS;
        if (count > canon::MAX_CELLS) return fail(Status::InvalidArgument, "--cells exceeds MAX_CELLS");
        sim::WorldDesc wd;
        wd.chamber = sim::Chamber{canon::CHAMBER_W, canon::CHAMBER_H, canon::CHAMBER_D};
        wd.capacity = count;
        wd.seed = o.seed;
        ASTRO_TRY(sim::world_create(a.world, wd));
        capacity = count;
    }

    render::GlContextDesc gd;
    gd.width = o.width;
    gd.height = o.height;
    gd.visible = !o.headless;
    gd.debug = o.gl_debug;
    gd.vsync = o.vsync;
    ASTRO_TRY(render::gl_context_create(a.gl, gd));
    glfwSetScrollCallback(a.gl.window, scroll_callback);

    // Registered with CUDA, so it must be created after the GL context.
    ASTRO_TRY(render::cells_pass_create(a.cells_pass, capacity));
    ASTRO_TRY(render::post_pass_create(a.post_pass));

    // A scenario already spawned its populations and set its own clock + scope; a plain run
    // spawns a uniform population and takes the clock/mode from the flags.
    if (a.has_scenario) {
        a.hud.mode = a.scenario.scope.mode;
        a.hud.clock_preset = static_cast<int>(a.scenario.clock);
    } else {
        ASTRO_TRY(spawn_population(a.world, capacity, o.charge, o.seed, o.awake));
        a.hud.mode = o.view_mode;
        // Apply the requested clock (ADR-011/ADR-027) and mirror the resolved rates into the
        // HUD so the panel opens showing the clock the run actually started on.
        sim::world_set_clock(a.world, static_cast<contract::ClockPreset>(o.clock_preset),
                             o.physics_rate, o.biology_rate);
        a.hud.clock_preset = o.clock_preset;
    }
    a.hud.clock_physics = static_cast<float>(a.world.physics_rate);
    a.hud.clock_biology = static_cast<float>(a.world.biology_rate);

    if (o.objective >= 0 && o.objective < canon::OBJECTIVE_COUNT) a.camera.objective = o.objective;
    if (o.zoom > 0.0f) a.camera.zoom = o.zoom;
    a.camera.focal_plane = o.focus_um * 1e-6;

    // Pre-select a cell for the inspector, so a headless screenshot can show the panel
    // (picking is a mouse click a headless run cannot make). ID latches on the first read.
    if (o.inspect_slot >= 0 && o.inspect_slot < a.world.cells.count) {
        a.has_pick = true;
        a.pick_slot = o.inspect_slot;
    }

    a.hud.respawn_count = a.world.cells.count;
    a.hud.respawn_charge = o.charge;
    a.hud.live_charge = o.charge;
    std::printf("[app] %s | chamber %.2f x %.2f mm | %d cells | seed %llu\n",
                a.has_scenario ? a.scenario.id : "(uniform)",
                a.world.chamber.w * 1e3, a.world.chamber.h * 1e3,
                a.world.cells.count, static_cast<unsigned long long>(a.world.seed));
    return ok();
}

void app_shutdown(Application& a) {
    render::post_pass_destroy(a.post_pass);
    render::cells_pass_destroy(a.cells_pass);
    render::gl_context_destroy(a.gl);
    sim::world_destroy(a.world);
}

int app_run(Application& a) {
    double last_time = glfwGetTime();
    double fps_accum = 0.0;
    int    fps_frames = 0;

    while (!render::gl_context_should_close(a.gl)) {
        const double now = glfwGetTime();
        const double dt_real = now - last_time;
        last_time = now;

        render::gl_context_begin_frame(a.gl);
        handle_input(a);

        // Push the inspector's curated overrides into the World before stepping (ADR-035).
        // With no edits these equal canon, so the tick is bit-identical to M11e.
        apply_param_overrides(a);

        // Fixed-tick accumulator (src/app/MODULE.md). Render frame rate floats;
        // DT_PHYSICS never does. Cap the catch-up rather than spiral.
        if (a.hud.paused) {
            a.accumulator = 0.0;
        } else if (a.options.ticks_per_frame > 0) {
            // Wall clock ignored entirely: the same command yields the same
            // simulated time on any machine. Required for golden captures.
            for (int i = 0; i < a.options.ticks_per_frame; ++i) {
                if (a.has_scenario) sim::scenario_apply_drive(a.world, a.scenario);
                sim::world_step(a.world);
            }
        } else {
            // Wall-time accumulator. physics_rate now lives INSIDE world_step (each
            // tick advances DT_PHYSICS * physics_rate of simulated time, ADR-027), so
            // the accumulator is raw wall time and steps once per DT_PHYSICS of it.
            // A fast clock therefore compresses time by taking bigger steps, not by
            // running more ticks -- so the 8-substep cap bounds cost the same at any
            // rate. Scaling here as well would apply physics_rate twice.
            a.accumulator += dt_real;
            int substeps = 0;
            while (a.accumulator >= canon::DT_PHYSICS && substeps < 8) {
                if (a.has_scenario) sim::scenario_apply_drive(a.world, a.scenario);
                sim::world_step(a.world);
                a.accumulator -= canon::DT_PHYSICS;
                ++substeps;
            }
            if (substeps == 8) a.accumulator = 0.0;   // drop time, do not lag
        }

        if (a.hud.set_charge_requested) {
            a.hud.set_charge_requested = false;
            if (Error e = sim::cell_store_set_charge(a.world.cells, a.hud.live_charge)) {
                std::printf("[app] set charge failed: %s\n", status_str(e.status));
                return 1;
            }
        }

        if (a.hud.clock_change_requested) {
            a.hud.clock_change_requested = false;
            sim::world_set_clock(a.world,
                                 static_cast<contract::ClockPreset>(a.hud.clock_preset),
                                 a.hud.clock_physics, a.hud.clock_biology);
            // Reflect any clamping / preset resolution straight back to the sliders.
            a.hud.clock_physics = static_cast<float>(a.world.physics_rate);
            a.hud.clock_biology = static_cast<float>(a.world.biology_rate);
        }

        if (a.hud.respawn_requested) {
            a.hud.respawn_requested = false;
            sim::world_destroy(a.world);
            sim::WorldDesc wd;
            wd.chamber = sim::Chamber{canon::CHAMBER_W, canon::CHAMBER_H, canon::CHAMBER_D};
            wd.capacity = a.cells_pass.capacity;
            wd.seed = a.options.seed;
            if (Error e = sim::world_create(a.world, wd)) {
                std::printf("[app] respawn failed: %s\n", status_str(e.status));
                return 1;
            }
            const int32_t n = a.hud.respawn_count < a.cells_pass.capacity
                            ? a.hud.respawn_count : a.cells_pass.capacity;
            if (Error e = spawn_population(a.world, n, a.hud.respawn_charge, a.options.seed)) {
                std::printf("[app] respawn spawn failed: %s\n", status_str(e.status));
                return 1;
            }
        }

        if (Error e = render::interop_fill_cells(a.cells_pass.interop, a.world.cells.view,
                                                 a.world.cells.count)) {
            std::printf("[app] interop fill failed: %s (%s)\n", status_str(e.status),
                        e.detail ? e.detail : "");
            return 1;
        }

        render::cells_pass_draw(a.cells_pass, a.camera, a.gl.fb_width, a.gl.fb_height,
                                a.world.cells.count, a.hud.mode, a.hud.channel,
                                a.options.morphology);
        // The condenser affects the field as well as the cells, so it goes after
        // them. Applied to the ILLUMINATED modes -- Brightfield and Thermal IR (the
        // film's IR view is a lit circular field) -- but not the emission modes
        // (Darkfield, Petrovascope), whose field is genuinely black.
        if (a.hud.mode == contract::ViewMode::Brightfield ||
            a.hud.mode == contract::ViewMode::ThermalIR)
            render::post_pass_draw(a.post_pass, a.gl.fb_width, a.gl.fb_height, 0.22f, 0.6f,
                                   a.options.aperture);

        // The inspector's lock state is the run's canon status; mirror it into the World
        // so world_stats carries it into Stats, the HUD, and every export (ADR-034).
        a.world.non_canon_run = a.params.non_canon_run;

        if (!a.options.no_ui) {
            // HUD RATE, NOT FRAME RATE. world_stats runs the stage-11 reduction and
            // ends in a synchronous D2H, which stalls the pipeline; calling it every
            // frame cost enough to fail the 200k-cell benchmark outright. This is
            // what ARCHITECTURE.md Sec 3.1 has always specified -- "~30 Hz, not
            // every tick" -- and the HUD cannot show the difference.
            if ((a.frames_done & 3) == 0) {
                a.stats_cache = sim::world_stats(a.world);
                if (a.has_scenario) evaluate_objective(a);
                read_picked_cell(a);   // one cell D2H at HUD rate; no-op with no pick
            }
            const contract::Stats stats = a.stats_cache;
            ui::hud_draw(a.hud, stats, a.camera, a.cells_pass.capacity,
                         a.world.chamber.w, a.world.chamber.h, a.world.chamber.d);
            ui::params_panel_draw(a.params, a.param_live);
            ui::scenario_panel_draw(a.has_scenario ? a.scenario.objective_text : nullptr,
                                    a.obj_checks, a.obj_count, a.has_scenario);
            ui::inspector_panel_draw(a.cell_readout);
            ui::chart_panel_draw(a.charts, stats);
            ui::draw_scale_bar(a.camera, a.gl.fb_width, a.gl.fb_height);
        }

        render::gl_context_render_ui(a.gl);
        // After the UI is rasterised and before the swap, so the capture is the
        // complete frame the user would have seen.
        if (a.options.screenshot && a.options.frames > 0 &&
            a.frames_done == a.options.frames - 1) {
            write_ppm(a.options.screenshot, a.gl.fb_width, a.gl.fb_height);
        }
        render::gl_context_present(a.gl);

        // Frame 0 includes shader compilation and first-touch allocation; it is
        // not representative, so it is excluded from the benchmark.
        if (a.frames_done > 0) {
            const double ms = dt_real * 1e3;
            a.bench_total_ms += ms;
            if (ms > a.bench_worst_ms) a.bench_worst_ms = ms;
            ++a.bench_frames;
        }
        fps_accum += dt_real;
        ++fps_frames;
        if (fps_accum >= 0.25) {
            a.hud.fps = static_cast<float>(fps_frames / fps_accum);
            a.hud.frame_ms = static_cast<float>(fps_accum / fps_frames * 1e3);
            fps_accum = 0.0;
            fps_frames = 0;
        }

        ++a.frames_done;
        if (a.options.frames > 0 && a.frames_done >= a.options.frames) break;
    }

    // A bounded scenario run reports where it ended up, so a headless auto-play can be
    // checked (the gate) and the driving confirmed without eyeballing the HUD.
    if (a.has_scenario && a.options.frames > 0) {
        const contract::Stats s = sim::world_stats(a.world);
        std::printf("[app] %s @ %.2f s: live %d awake %d medium %.2f K mean_charge %.4f "
                    "non_canon %d\n",
                    a.scenario.id, s.sim_time_s, s.n_live, s.n_awake, s.mean_temp_medium_k,
                    s.mean_charge, s.non_canon_run);
    }

    if (a.gl.gl_error_count > 0) {
        std::printf("[app] FAIL: %d GL debug errors (gate M1.3 requires zero)\n",
                    a.gl.gl_error_count);
        return 1;
    }

    if (a.options.benchmark) {
        if (a.bench_frames <= 0) { std::printf("[app] FAIL: no frames measured\n"); return 1; }
        const double mean_ms = a.bench_total_ms / a.bench_frames;
        const double fps = 1000.0 / mean_ms;
        const int tpf = a.options.ticks_per_frame > 0 ? a.options.ticks_per_frame : 1;
        const double ticks_per_s = fps * tpf;
        // How fast the simulation runs against the clock it is modelling. Below
        // 1.0 the Realtime preset is slower than real time -- an honest number
        // that a frame rate alone hides.
        const double realtime_factor = ticks_per_s * canon::DT_PHYSICS;
        std::printf("[bench] %d cells | %d frames | %d tick/frame | mean %.3f ms (%.1f fps)"
                    " | worst %.3f ms | %.0f ticks/s = %.2fx real time\n",
                    a.world.cells.count, a.bench_frames, tpf, mean_ms, fps,
                    a.bench_worst_ms, ticks_per_s, realtime_factor);
        if (fps < canon::TARGET_FPS) {
            std::printf("[bench] FAIL: %.1f fps below target %d\n", fps, canon::TARGET_FPS);
            return 1;
        }
        std::printf("[bench] PASS: target %d fps met\n", canon::TARGET_FPS);
    }
    return 0;
}

} // namespace astro::app
