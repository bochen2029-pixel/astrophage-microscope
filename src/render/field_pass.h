// src/render/field_pass.h -- false-colour a scalar field as a fullscreen background (M12i, ADR-045).
#pragma once

#include <cstdint>

#include "core/result.h"
#include "render/camera.h"

namespace astro::render {

// Draws a scalar field (the medium temperature) as a fullscreen false-coloured background, mapped to the
// camera's chamber window so it aligns with the cells drawn on top. The field arrives as a HOST buffer --
// the app `grid_download`s it, so render/ never touches sim/ -- and this pass uploads it to an R32F
// texture and samples it through a warm IR LUT. It is what sits behind Thermal IR (M12i); before it, a
// flat warm clear colour stood in for the real T-field. The chamber is square (a single `extent`), so the
// grid spans [-extent/2, +extent/2] on both axes.
struct FieldPass {
    unsigned int program = 0;
    unsigned int vao = 0;
    unsigned int tex = 0;        // R32F, the uploaded field
    int tex_n = 0;               // current texture size (n x n), to skip reallocation
    int u_center = -1, u_half_extent = -1, u_extent = -1, u_tmin = -1, u_tmax = -1;
};

Error field_pass_create(FieldPass& f);
void  field_pass_destroy(FieldPass& f);

// Uploads the n x n host field and draws it as the camera-mapped false-colour background. tmin/tmax are
// the temperature normalization range [K]. Fills the whole framebuffer opaquely; draw BEFORE the cells,
// and draw the cells with clear=false so they land on this background.
void  field_pass_draw(FieldPass& f, const Camera& cam, int fb_w, int fb_h,
                      const float* host_field, int n, double extent, float tmin, float tmax);

} // namespace astro::render
