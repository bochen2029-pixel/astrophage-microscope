// src/render/gl_context.h -- window, GL 4.6 core context, debug output, ImGui.
#pragma once

#include "core/result.h"

struct GLFWwindow;

namespace astro::render {

struct GlContextDesc {
    int         width   = 1600;
    int         height  = 1000;
    const char* title   = "Astrophage Microscope";
    bool        visible = true;    // false = hidden window for --headless
    bool        debug   = false;   // GL_DEBUG_OUTPUT with a fatal callback
    bool        vsync   = false;   // off by default so --benchmark measures the GPU
};

struct GlContext {
    GLFWwindow* window = nullptr;
    int  fb_width = 0, fb_height = 0;
    bool imgui_ready = false;
    // Every GL_DEBUG_SEVERITY_HIGH message increments this. Zero is a gate
    // condition (docs/MILESTONES.md M1.3) -- never disable the layer to pass.
    int  gl_error_count = 0;
};

Error gl_context_create(GlContext& c, const GlContextDesc& d);
void  gl_context_destroy(GlContext& c);

bool  gl_context_should_close(const GlContext& c);
void  gl_context_begin_frame(GlContext& c);   // poll, resize, ImGui NewFrame

// Split so a screenshot can be taken between them: after this the back buffer
// holds the complete frame including ImGui, and it has not been swapped away.
void  gl_context_render_ui(GlContext& c);
void  gl_context_present(GlContext& c);

} // namespace astro::render
