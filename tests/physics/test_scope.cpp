// tests/physics/test_scope.cpp -- camera and scale bar, headless.
//
// M1 gate conditions: "the scale bar reads correctly at all three objectives"
// and "cells are drawn at true relative size". Both are checkable without a GL
// context because the geometry is pure arithmetic -- so they are checked here
// rather than by eye (CLAUDE.md Iron Rule 5).
#include <cmath>
#include <cstdio>

#include "core/canon_generated.h"
#include "render/camera.h"
#include "test_util.h"
#include "ui/scale_bar.h"

using namespace astro;
using astro::render::Camera;
using astro::ui::choose_scale_bar;

int main() {
    constexpr int FB_W = 1600, FB_H = 1000;

    // --- the field of view matches the objective -----------------------------
    for (int i = 0; i < canon::OBJECTIVE_COUNT; ++i) {
        Camera cam;
        cam.objective = i;
        cam.zoom = 1.0f;
        double hx, hy;
        cam.half_extent(FB_W, FB_H, hx, hy);
        CHECK_CLOSE(2.0 * hx, canon::OBJECTIVES[i].fov_m, 1e-12);
        // Pixels must stay square, or every measurement made through the scope
        // would be anisotropic.
        CHECK_CLOSE(hy / hx, static_cast<double>(FB_H) / FB_W, 1e-12);
    }

    // --- the scale bar is right at every objective ---------------------------
    // Verified against hand arithmetic: field width / 1600 px gives m/px, and
    // the bar takes the largest 1-2-5 snap point fitting in a quarter width.
    struct Expect { int objective; double length_um; };
    const Expect expected[] = {
        {0, 500.0},   // 10x:  2200 um field -> 1.375   um/px -> 500 um = 364 px
        {1, 100.0},   // 40x:   550 um field -> 0.34375 um/px -> 100 um = 291 px
        {2,  50.0},   // 100x:  220 um field -> 0.1375  um/px ->  50 um = 364 px
    };
    for (const Expect& e : expected) {
        Camera cam;
        cam.objective = e.objective;
        const double mpp = cam.metres_per_pixel(FB_W, FB_H);
        const auto c = choose_scale_bar(mpp, FB_W * 0.25);
        std::printf("  objective %.0fx: %.4f um/px -> bar %.0f um (%.0f px)\n",
                    canon::OBJECTIVES[e.objective].magnification, mpp * 1e6,
                    c.length_um, c.length_px);
        CHECK_CLOSE(c.length_um, e.length_um, 1e-9);
        CHECK(c.length_px <= FB_W * 0.25);
        CHECK(c.length_px > FB_W * 0.05);      // a bar that small is unreadable
    }

    // The bar must stay inside its budget across the WHOLE zoom range, at every
    // objective -- including 200x digital zoom on the 100x objective, where the
    // field is narrower than one cell. That corner is what forces the snap table
    // down to 0.1 um; without those entries the fallback fires and the bar
    // overflows.
    for (int i = 0; i < canon::OBJECTIVE_COUNT; ++i) {
        for (double z = 0.05; z <= 200.0; z *= 1.7) {
            Camera cam;
            cam.objective = i;
            cam.zoom = static_cast<float>(z);
            const double mpp = cam.metres_per_pixel(FB_W, FB_H);
            const auto c = choose_scale_bar(mpp, FB_W * 0.25);
            CHECK(c.length_um > 0.0);
            CHECK(c.length_px <= FB_W * 0.25);
            // The label must describe the bar it is drawn under: length_px is
            // exactly length_um at the current scale.
            CHECK_CLOSE(c.length_px * mpp * 1e6, c.length_um, 1e-9);
        }
    }

    // --- cells are drawn at true relative size (no fudge) --------------------
    // A cell is 10 um. At each objective the on-screen diameter must be exactly
    // 10 um worth of pixels. audit.ps1 A10 greps for a fudge factor; this proves
    // the geometry independently.
    for (int i = 0; i < canon::OBJECTIVE_COUNT; ++i) {
        Camera cam;
        cam.objective = i;
        const double mpp = cam.metres_per_pixel(FB_W, FB_H);
        const double diameter_px = canon::CELL_DIAMETER / mpp;
        const double field_fraction = canon::CELL_DIAMETER / canon::OBJECTIVES[i].fov_m;
        CHECK_CLOSE(diameter_px / FB_W, field_fraction, 1e-12);
    }
    // At 40x a cell should be a few tens of pixels across -- resolvable, which
    // is the entire premise of looking at this through a microscope.
    {
        Camera cam;
        cam.objective = canon::OBJECTIVE_DEFAULT;
        const double d_px = canon::CELL_DIAMETER / cam.metres_per_pixel(FB_W, FB_H);
        std::printf("  cell diameter at 40x: %.1f px\n", d_px);
        CHECK(d_px > 10.0 && d_px < 60.0);
    }

    // --- cursor-anchored zoom keeps the point under the cursor fixed ---------
    {
        Camera cam;
        const double px = 1200.0, py = 300.0;
        double before_x, before_y;
        cam.screen_to_world(px, py, FB_W, FB_H, before_x, before_y);
        cam.zoom_at(2.5, px, py, FB_W, FB_H);
        double after_x, after_y;
        cam.screen_to_world(px, py, FB_W, FB_H, after_x, after_y);
        CHECK(std::fabs(after_x - before_x) < 1e-12);
        CHECK(std::fabs(after_y - before_y) < 1e-12);
    }

    // --- panning moves the stage the distance the cursor moved ---------------
    {
        Camera cam;
        const double mpp = cam.metres_per_pixel(FB_W, FB_H);
        cam.pan_pixels(100.0, 0.0, FB_W, FB_H);
        CHECK_CLOSE(cam.center_x, -100.0 * mpp, 1e-12);
        // Screen y grows downward, chamber y upward: dragging down must raise
        // the stage centre, not lower it.
        cam.pan_pixels(0.0, 50.0, FB_W, FB_H);
        CHECK_CLOSE(cam.center_y, 50.0 * mpp, 1e-12);
    }

    // --- zoom is clamped, and the stage cannot wander off the chamber --------
    {
        Camera cam;
        for (int i = 0; i < 200; ++i) cam.zoom_at(2.0, 800, 500, FB_W, FB_H);
        CHECK(cam.zoom <= 200.0f);
        for (int i = 0; i < 400; ++i) cam.zoom_at(0.5, 800, 500, FB_W, FB_H);
        CHECK(cam.zoom >= 0.05f);

        cam.center_x = 1.0;   // a metre away from a 4 mm chamber
        cam.clamp_to_chamber(canon::CHAMBER_W, canon::CHAMBER_H, FB_W, FB_H);
        // The documented bound is half the chamber plus the field half-width --
        // deliberate overhang, so at wide zoom the whole chamber is reachable.
        // Checking against CHAMBER_W alone would be wrong at low zoom, where the
        // field is wider than the chamber itself.
        double hx, hy;
        cam.half_extent(FB_W, FB_H, hx, hy);
        CHECK(std::fabs(cam.center_x) <= 0.5 * canon::CHAMBER_W + hx + 1e-12);

        // At default zoom the overhang is modest: the culture stays on screen.
        Camera c2;
        c2.center_x = 1.0;
        c2.clamp_to_chamber(canon::CHAMBER_W, canon::CHAMBER_H, FB_W, FB_H);
        CHECK(std::fabs(c2.center_x) < canon::CHAMBER_W);
    }

    return astro::test::finish("test_scope");
}
