// src/render/cells_pass.cpp
//
// M1 draws flat discs. Defocus, the diffraction ring, and the focal-plane
// response arrive at M3 (docs/RENDERING.md Sec 3); Petrovascope and Thermal IR
// arrive at M6/M7. The uniforms those need are already plumbed so the shader
// grows rather than gets rewritten.
#include "render/cells_pass.h"

#include <cstdio>

#include <glad/gl.h>

#include "core/canon_generated.h"

namespace astro::render {

using contract::AnalysisChannel;
using contract::CellInstance;
using contract::ViewMode;

namespace {

// No vertex buffer: the quad corner comes from gl_VertexID. One less binding to
// get wrong, and the geometry is two triangles either way.
const char* kVert = R"GLSL(
#version 460 core
layout(location = 0) in vec4  a_pos_radius;   // x, y, z, radius   [um]
layout(location = 1) in vec2  a_state;        // charge, emit_power_norm
layout(location = 2) in uvec2 a_flags;        // flags_packed, dir_packed

uniform vec2  u_center_um;
uniform vec2  u_half_extent_um;
uniform float u_px_per_um;

out vec2  v_local;      // [-1,1] across the quad
out float v_alpha;
out float v_charge;
out float v_emit;
flat out uint v_flags;

void main() {
    // Sub-pixel cells must still register. Clamp the drawn radius to 0.75 px and
    // pay for it in alpha by area ratio, so density stays honest instead of
    // aliasing away (docs/RENDERING.md Sec 7). This is NOT a size fudge: at any
    // radius above the clamp the cell is drawn at true scale.
    float radius_px = a_pos_radius.w * u_px_per_um;
    float draw_px   = max(radius_px, 0.75);
    v_alpha = (radius_px < 0.75) ? (radius_px * radius_px) / (0.75 * 0.75) : 1.0;

    float draw_um = draw_px / u_px_per_um;

    vec2 corner = vec2((gl_VertexID & 1) == 0 ? -1.0 : 1.0,
                       (gl_VertexID & 2) == 0 ? -1.0 : 1.0);
    v_local = corner;

    vec2 world = a_pos_radius.xy + corner * draw_um;
    gl_Position = vec4((world - u_center_um) / u_half_extent_um, 0.0, 1.0);

    v_charge = a_state.x;
    v_emit   = a_state.y;
    v_flags  = a_flags.x;
}
)GLSL";

const char* kFrag = R"GLSL(
#version 460 core
in vec2  v_local;
in float v_alpha;
in float v_charge;
in float v_emit;
flat in uint v_flags;

uniform int u_mode;      // contract::ViewMode
uniform int u_channel;   // contract::AnalysisChannel

out vec4 frag;

const uint FLAG_ALIVE = 2u;

// Provisional ramp. The real perceptually-uniform LUTs arrive as 1D textures in
// M5 (docs/RENDERING.md Sec 5); this keeps M1 free of texture plumbing.
vec3 ramp(float t) {
    t = clamp(t, 0.0, 1.0);
    vec3 c0 = vec3(0.001, 0.000, 0.014);
    vec3 c1 = vec3(0.316, 0.072, 0.485);
    vec3 c2 = vec3(0.716, 0.215, 0.475);
    vec3 c3 = vec3(0.988, 0.553, 0.353);
    vec3 c4 = vec3(0.987, 0.991, 0.750);
    if (t < 0.25) return mix(c0, c1, t / 0.25);
    if (t < 0.50) return mix(c1, c2, (t - 0.25) / 0.25);
    if (t < 0.75) return mix(c2, c3, (t - 0.50) / 0.25);
    return mix(c3, c4, (t - 0.75) / 0.25);
}

void main() {
    // Analytic antialiasing on the disc SDF: one pixel of the local coordinate.
    float d  = length(v_local);
    float fw = max(fwidth(d), 1e-5);
    float coverage = 1.0 - smoothstep(1.0 - fw, 1.0, d);
    if (coverage <= 0.0) discard;

    bool alive = (v_flags & FLAG_ALIVE) != 0u;
    vec3 color;
    float alpha = coverage * v_alpha;

    if (u_mode == 0) {
        // Brightfield. Live Astrophage is opaque black at every wavelength;
        // dead cells go translucent (docs/PHYSICS.md Sec 10).
        color = vec3(0.02);
        if (!alive) { color = vec3(0.55); alpha *= 0.35; }
    } else {
        float t = (u_channel == 0) ? v_charge : v_emit;
        color = ramp(t);
        if (!alive) { color = vec3(0.25); alpha *= 0.5; }
    }
    frag = vec4(color, alpha);
}
)GLSL";

unsigned int compile(unsigned int type, const char* src, const char* label) {
    const unsigned int s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    int okFlag = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &okFlag);
    if (!okFlag) {
        char log[2048];
        glGetShaderInfoLog(s, sizeof(log), nullptr, log);
        std::printf("[gl] %s shader compile failed:\n%s\n", label, log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

} // namespace

Error cells_pass_create(CellsPass& p, int32_t instance_capacity) {
    const unsigned int vs = compile(GL_VERTEX_SHADER, kVert, "cells.vert");
    const unsigned int fs = compile(GL_FRAGMENT_SHADER, kFrag, "cells.frag");
    if (!vs || !fs) return fail(Status::Unsupported, "cell shader compile failed");

    p.program = glCreateProgram();
    glAttachShader(p.program, vs);
    glAttachShader(p.program, fs);
    glLinkProgram(p.program);
    int linked = 0;
    glGetProgramiv(p.program, GL_LINK_STATUS, &linked);
    glDeleteShader(vs);
    glDeleteShader(fs);
    if (!linked) {
        char log[2048];
        glGetProgramInfoLog(p.program, sizeof(log), nullptr, log);
        std::printf("[gl] cell program link failed:\n%s\n", log);
        return fail(Status::Unsupported, "cell shader link failed");
    }

    p.u_center_um      = glGetUniformLocation(p.program, "u_center_um");
    p.u_half_extent_um = glGetUniformLocation(p.program, "u_half_extent_um");
    p.u_px_per_um      = glGetUniformLocation(p.program, "u_px_per_um");
    p.u_mode           = glGetUniformLocation(p.program, "u_mode");
    p.u_channel        = glGetUniformLocation(p.program, "u_channel");
    p.u_focal_plane_um = glGetUniformLocation(p.program, "u_focal_plane_um");   // -1 until M3

    glGenVertexArrays(1, &p.vao);
    glGenBuffers(1, &p.instance_vbo);
    glBindVertexArray(p.vao);
    glBindBuffer(GL_ARRAY_BUFFER, p.instance_vbo);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(sizeof(CellInstance)) * instance_capacity,
                 nullptr, GL_DYNAMIC_DRAW);

    // Layout must match contracts/render_view_v1.h CellInstance exactly.
    const GLsizei stride = static_cast<GLsizei>(sizeof(CellInstance));
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(0));
    glVertexAttribDivisor(0, 1);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(16));
    glVertexAttribDivisor(1, 1);
    glEnableVertexAttribArray(2);
    glVertexAttribIPointer(2, 2, GL_UNSIGNED_INT, stride, reinterpret_cast<void*>(24));
    glVertexAttribDivisor(2, 1);
    glBindVertexArray(0);

    p.capacity = instance_capacity;
    ASTRO_TRY(interop_register(p.interop, p.instance_vbo,
                               static_cast<size_t>(instance_capacity)));
    return ok();
}

void cells_pass_destroy(CellsPass& p) {
    interop_unregister(p.interop);
    if (p.instance_vbo) glDeleteBuffers(1, &p.instance_vbo);
    if (p.vao) glDeleteVertexArrays(1, &p.vao);
    if (p.program) glDeleteProgram(p.program);
    p = CellsPass{};
}

void cells_pass_draw(const CellsPass& p, const Camera& cam, int fb_w, int fb_h,
                     int32_t count, ViewMode mode, AnalysisChannel channel) {
    if (mode == ViewMode::Brightfield) glClearColor(0.961f, 0.941f, 0.902f, 1.0f);
    else                               glClearColor(0.055f, 0.055f, 0.070f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    if (count <= 0) return;

    double hx, hy;
    cam.half_extent(fb_w, fb_h, hx, hy);
    const double mpp = cam.metres_per_pixel(fb_w, fb_h);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(p.program);
    glUniform2f(p.u_center_um, static_cast<float>(cam.center_x * 1.0e6),
                               static_cast<float>(cam.center_y * 1.0e6));
    glUniform2f(p.u_half_extent_um, static_cast<float>(hx * 1.0e6),
                                    static_cast<float>(hy * 1.0e6));
    glUniform1f(p.u_px_per_um, static_cast<float>(1.0e-6 / (mpp > 0.0 ? mpp : 1.0)));
    glUniform1i(p.u_mode, static_cast<int>(mode));
    glUniform1i(p.u_channel, static_cast<int>(channel));
    if (p.u_focal_plane_um >= 0)
        glUniform1f(p.u_focal_plane_um, static_cast<float>(cam.focal_plane * 1.0e6));

    glBindVertexArray(p.vao);
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, count);
    glBindVertexArray(0);
    glUseProgram(0);
    glDisable(GL_BLEND);
}

} // namespace astro::render
