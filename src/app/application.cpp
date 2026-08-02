// src/app/application.cpp
#include "app/application.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

#include <glad/gl.h>
#include <GLFW/glfw3.h>

#include "imgui.h"

#include "core/canon_generated.h"

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

void handle_input(Application& a) {
    const ImGuiIO& io = ImGui::GetIO();
    GLFWwindow* win = a.gl.window;

    static bool dragging = false;
    static double last_x = 0.0, last_y = 0.0;
    double mx = 0.0, my = 0.0;
    glfwGetCursorPos(win, &mx, &my);

    const bool down = glfwGetMouseButton(win, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
    if (down && !io.WantCaptureMouse) {
        if (dragging) a.camera.pan_pixels(mx - last_x, my - last_y, a.gl.fb_width, a.gl.fb_height);
        dragging = true;
    } else {
        dragging = false;
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

    const int32_t count = o.cells > 0 ? o.cells : canon::DEFAULT_CELLS;
    if (count > canon::MAX_CELLS) return fail(Status::InvalidArgument, "--cells exceeds MAX_CELLS");

    sim::WorldDesc wd;
    wd.chamber = sim::Chamber{canon::CHAMBER_W, canon::CHAMBER_H, canon::CHAMBER_D};
    wd.capacity = count;
    wd.seed = o.seed;
    ASTRO_TRY(sim::world_create(a.world, wd));

    render::GlContextDesc gd;
    gd.width = o.width;
    gd.height = o.height;
    gd.visible = !o.headless;
    gd.debug = o.gl_debug;
    gd.vsync = o.vsync;
    ASTRO_TRY(render::gl_context_create(a.gl, gd));
    glfwSetScrollCallback(a.gl.window, scroll_callback);

    // Registered with CUDA, so it must be created after the GL context.
    ASTRO_TRY(render::cells_pass_create(a.cells_pass, count));
    ASTRO_TRY(render::post_pass_create(a.post_pass));
    ASTRO_TRY(spawn_population(a.world, count, o.charge, o.seed, o.awake));
    a.hud.mode = o.view_mode;

    // Apply the requested clock (ADR-011/ADR-027) and mirror the resolved rates
    // into the HUD so the panel opens showing the clock the run actually started on.
    sim::world_set_clock(a.world, static_cast<contract::ClockPreset>(o.clock_preset),
                         o.physics_rate, o.biology_rate);
    a.hud.clock_preset = o.clock_preset;
    a.hud.clock_physics = static_cast<float>(a.world.physics_rate);
    a.hud.clock_biology = static_cast<float>(a.world.biology_rate);

    if (o.objective >= 0 && o.objective < canon::OBJECTIVE_COUNT) a.camera.objective = o.objective;
    if (o.zoom > 0.0f) a.camera.zoom = o.zoom;
    a.camera.focal_plane = o.focus_um * 1e-6;

    a.hud.respawn_count = count;
    a.hud.respawn_charge = o.charge;
    a.hud.live_charge = o.charge;
    std::printf("[app] chamber %.2f x %.2f mm, %.0f um deep | %d cells | seed %llu\n",
                a.world.chamber.w * 1e3, a.world.chamber.h * 1e3, a.world.chamber.d * 1e6,
                a.world.cells.count, static_cast<unsigned long long>(o.seed));
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

        // Fixed-tick accumulator (src/app/MODULE.md). Render frame rate floats;
        // DT_PHYSICS never does. Cap the catch-up rather than spiral.
        if (a.hud.paused) {
            a.accumulator = 0.0;
        } else if (a.options.ticks_per_frame > 0) {
            // Wall clock ignored entirely: the same command yields the same
            // simulated time on any machine. Required for golden captures.
            for (int i = 0; i < a.options.ticks_per_frame; ++i) sim::world_step(a.world);
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

        if (!a.options.no_ui) {
            // HUD RATE, NOT FRAME RATE. world_stats runs the stage-11 reduction and
            // ends in a synchronous D2H, which stalls the pipeline; calling it every
            // frame cost enough to fail the 200k-cell benchmark outright. This is
            // what ARCHITECTURE.md Sec 3.1 has always specified -- "~30 Hz, not
            // every tick" -- and the HUD cannot show the difference.
            if ((a.frames_done & 3) == 0) a.stats_cache = sim::world_stats(a.world);
            const contract::Stats stats = a.stats_cache;
            ui::hud_draw(a.hud, stats, a.camera, a.cells_pass.capacity,
                         a.world.chamber.w, a.world.chamber.h, a.world.chamber.d);
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
