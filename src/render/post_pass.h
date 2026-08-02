// src/render/post_pass.h -- condenser vignette (docs/RENDERING.md Sec 3).
//
// Multiply-blended fullscreen triangle. No framebuffer object: the effect is
// purely multiplicative, so GL_ZERO/GL_SRC_COLOR does it in one draw with no
// render-target churn.
#pragma once

#include "core/result.h"

namespace astro::render {

struct PostPass {
    unsigned int program = 0;
    unsigned int vao = 0;      // empty VAO; the triangle comes from gl_VertexID
    int u_strength = -1;
    int u_warmth = -1;
    int u_aspect = -1;
};

Error post_pass_create(PostPass& p);
void  post_pass_destroy(PostPass& p);

// strength 0 disables. warmth tints the falloff toward the lamp colour, which is
// what a real condenser does at the field edge.
void  post_pass_draw(const PostPass& p, int fb_w, int fb_h,
                     float strength, float warmth);

} // namespace astro::render
