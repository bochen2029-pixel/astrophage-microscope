// src/render/cells_pass.h -- one instanced draw for the whole population.
#pragma once

#include <cstdint>

#include "contracts/render_view_v2.h"
#include "core/result.h"
#include "render/camera.h"
#include "render/interop.cuh"

namespace astro::render {

struct CellsPass {
    unsigned int program = 0;
    unsigned int vao = 0;
    unsigned int instance_vbo = 0;
    InteropBuffer interop;
    int32_t capacity = 0;

    // Uniform locations, resolved once at build time.
    int u_center_um = -1, u_half_extent_um = -1, u_px_per_um = -1;
    int u_mode = -1, u_channel = -1, u_focal_plane_um = -1;
    int u_na = -1, u_immersion = -1, u_morphology = -1, u_colorblind = -1;
    int u_mode_blend_to = -1, u_blend = -1;   // cross-fade target + amount (M12f)
};

// The instance buffer holds cells AND the Taumoeba appended after them (M12b), so it is sized
// cell_capacity + tau_capacity. `p.capacity` reports the CELL capacity (what the app shows and
// clamps respawns to); the larger interop buffer is an internal detail.
Error cells_pass_create(CellsPass& p, int32_t cell_capacity, int32_t tau_capacity);
void  cells_pass_destroy(CellsPass& p);

// Clears to the mode's background and draws `count` instances. mode_blend in (0,1]
// cross-fades the cells and the background toward mode_blend_to (M12f); at 0 the draw
// is bit-identical to rendering `mode` alone, so every measurement golden is unmoved.
void cells_pass_draw(const CellsPass& p, const Camera& cam, int fb_w, int fb_h,
                     int32_t count, contract::ViewMode mode,
                     contract::AnalysisChannel channel,
                     contract::Morphology morphology = contract::Morphology::Irregular,
                     bool colorblind = false,
                     contract::ViewMode mode_blend_to = contract::ViewMode::Brightfield,
                     float mode_blend = 0.0f);

} // namespace astro::render
