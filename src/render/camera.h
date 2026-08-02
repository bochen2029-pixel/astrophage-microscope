// src/render/camera.h -- the scope: a movable, focusable window onto the chamber.
//
// ADR-009: the chamber is 4 mm across and the 40x objective sees 550 um of it,
// so panning the stage is a primary interaction, not a convenience.
#pragma once

#include "contracts/render_view_v1.h"
#include "core/canon_generated.h"
#include "core/units.h"     // astro::clamp

namespace astro::render {

struct Camera {
    double center_x = 0.0;      // [m] stage position within the chamber
    double center_y = 0.0;
    double focal_plane = 0.0;   // [m] z of the focal plane (used from M3)
    int    objective = canon::OBJECTIVE_DEFAULT;
    float  zoom = 1.0f;         // digital zoom on top of the objective

    // Half-extent of the visible field in metres. The objective sets the field
    // width; height follows from the framebuffer aspect so pixels stay square.
    void half_extent(int fb_w, int fb_h, double& hx, double& hy) const {
        const double field_w = canon::OBJECTIVES[objective].fov_m / static_cast<double>(zoom);
        hx = 0.5 * field_w;
        hy = (fb_w > 0) ? hx * static_cast<double>(fb_h) / static_cast<double>(fb_w) : hx;
    }

    // Metres per pixel -- drives the scale bar and the sub-pixel radius clamp.
    double metres_per_pixel(int fb_w, int fb_h) const {
        double hx, hy;
        half_extent(fb_w, fb_h, hx, hy);
        return (fb_w > 0) ? (2.0 * hx / static_cast<double>(fb_w)) : 0.0;
    }

    void pan_pixels(double dx_px, double dy_px, int fb_w, int fb_h) {
        const double mpp = metres_per_pixel(fb_w, fb_h);
        center_x -= dx_px * mpp;
        center_y += dy_px * mpp;   // screen y grows downward, chamber y upward
    }

    // Cursor-anchored zoom: the chamber point under the cursor stays put.
    void zoom_at(double factor, double cursor_px_x, double cursor_px_y, int fb_w, int fb_h) {
        double wx, wy;
        screen_to_world(cursor_px_x, cursor_px_y, fb_w, fb_h, wx, wy);
        zoom = static_cast<float>(clamp(static_cast<double>(zoom) * factor, 0.05, 200.0));
        double nx, ny;
        screen_to_world(cursor_px_x, cursor_px_y, fb_w, fb_h, nx, ny);
        center_x += wx - nx;
        center_y += wy - ny;
    }

    void screen_to_world(double px, double py, int fb_w, int fb_h,
                         double& wx, double& wy) const {
        double hx, hy;
        half_extent(fb_w, fb_h, hx, hy);
        const double ndc_x = (px / static_cast<double>(fb_w)) * 2.0 - 1.0;
        const double ndc_y = 1.0 - (py / static_cast<double>(fb_h)) * 2.0;
        wx = center_x + ndc_x * hx;
        wy = center_y + ndc_y * hy;
    }

    void clamp_to_chamber(double chamber_w, double chamber_h, int fb_w, int fb_h) {
        double hx, hy;
        half_extent(fb_w, fb_h, hx, hy);
        // Allow the field to overhang by half its width, so chamber edges are
        // reachable, but not so far that the culture leaves the screen entirely.
        const double lx = 0.5 * chamber_w + hx;
        const double ly = 0.5 * chamber_h + hy;
        center_x = clamp(center_x, -lx, lx);
        center_y = clamp(center_y, -ly, ly);
    }
};

} // namespace astro::render
