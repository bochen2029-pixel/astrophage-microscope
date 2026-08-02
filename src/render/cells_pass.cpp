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
//
// The optics below MIRROR src/render/optics.h. Change one, change both -- the
// golden images are the only thing that catches a divergence across the GLSL
// boundary.
const char* kVert = R"GLSL(
#version 460 core
layout(location = 0) in vec4  a_pos_radius;   // x, y, z, radius   [um]
layout(location = 1) in vec2  a_state;        // charge, emit_power_norm
layout(location = 2) in uvec2 a_flags;        // flags_packed, dir_packed

uniform vec2  u_center_um;
uniform vec2  u_half_extent_um;
uniform float u_px_per_um;
uniform float u_focal_plane_um;
uniform float u_na;
uniform float u_immersion;

out vec2  v_local;        // [-1,1] across the quad
out float v_draw_um;      // half-extent of the quad, um
out float v_radius_um;    // true cell radius, um
out float v_r_eff;        // blurred profile radius, um
out float v_edge_um;      // profile softness, um
out float v_peak;         // peak opacity (energy-conserving)
out float v_ring;         // Becke-line amplitude, 0 when defocused
out float v_polarity;     // +1 above focus, -1 below -- inverts the ring
out float v_alpha_scale;  // sub-pixel compensation
out float v_charge;
out float v_emit;
flat out uint v_flags;

void main() {
    float a  = a_pos_radius.w;                                   // true radius
    float dz = a_pos_radius.z - u_focal_plane_um;
    float r_coc = abs(dz) * u_na / u_immersion;                  // optics.h
    float r_eff = sqrt(a * a + r_coc * r_coc);
    float peak  = (a * a) / (r_eff * r_eff);                     // energy conserving

    float px_um = 1.0 / u_px_per_um;
    float edge  = max(r_coc, px_um);          // in focus, soften by one pixel only

    // Where the profile has essentially reached zero.
    float extent_um = r_eff + edge;

    // Sub-pixel objects must still register. Clamp the DRAWN extent to 0.75 px
    // and pay for it in alpha by area ratio, so density stays honest instead of
    // aliasing away (docs/RENDERING.md Sec 7). Not a size fudge: above the clamp
    // the cell is drawn at true scale, and the clamp only ever shrinks alpha.
    float extent_px = extent_um * u_px_per_um;
    float draw_px   = max(extent_px, 0.75);
    v_alpha_scale = (extent_px < 0.75) ? (extent_px * extent_px) / (0.75 * 0.75) : 1.0;
    float draw_um = draw_px / u_px_per_um;

    vec2 corner = vec2((gl_VertexID & 1) == 0 ? -1.0 : 1.0,
                       (gl_VertexID & 2) == 0 ? -1.0 : 1.0);
    v_local = corner;

    vec2 world = a_pos_radius.xy + corner * draw_um;
    gl_Position = vec4((world - u_center_um) / u_half_extent_um, 0.0, 1.0);

    v_draw_um   = draw_um;
    v_radius_um = a;
    v_r_eff     = r_eff;
    v_edge_um   = edge;
    v_peak      = peak;
    v_ring      = max(0.0, 1.0 - r_coc / a);
    v_polarity  = dz >= 0.0 ? 1.0 : -1.0;
    v_charge    = a_state.x;
    v_emit      = a_state.y;
    v_flags     = a_flags.x;
}
)GLSL";

const char* kFrag = R"GLSL(
#version 460 core
in vec2  v_local;
in float v_draw_um;
in float v_radius_um;
in float v_r_eff;
in float v_edge_um;
in float v_peak;
in float v_ring;
in float v_polarity;
in float v_alpha_scale;
in float v_charge;
in float v_emit;
flat in uint v_flags;

uniform int u_mode;      // contract::ViewMode
uniform int u_channel;   // contract::AnalysisChannel

out vec4 frag;

const uint FLAG_ALIVE = 2u;

// Provisional ramp. The real perceptually-uniform LUTs arrive as 1D textures in
// M5 (docs/RENDERING.md Sec 5); this keeps the pass free of texture plumbing.
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
    float d = length(v_local) * v_draw_um;      // distance from centre, um

    // The blurred disc: a uniform disc convolved with the defocus kernel,
    // approximated as a soft-edged profile of radius r_eff and softness edge.
    float cov = 1.0 - smoothstep(v_r_eff - v_edge_um, v_r_eff + v_edge_um, d);

    // Becke line. A real diffraction artefact at the edge of an opaque object in
    // brightfield: a narrow band just outside the geometric edge that is BRIGHT
    // on one side of focus and DARK on the other. That inversion is how a viewer
    // knows which way to rack the focus.
    float band = 0.0;
    if (v_ring > 0.0) {
        float t = (d - v_radius_um * 1.06) / (v_radius_um * 0.16);
        band = exp(-t * t) * v_ring;
    }

    // Signed contrast against the background: positive darkens (absorption),
    // negative brightens (the halo).
    float contrast = v_peak * cov - v_polarity * band * 0.5;

    bool alive = (v_flags & FLAG_ALIVE) != 0u;

    vec3 color;
    float alpha;
    if (u_mode == 0) {
        // Brightfield. Live Astrophage is opaque black at every wavelength;
        // dead cells go translucent (docs/PHYSICS.md Sec 10).
        if (contrast >= 0.0) {
            color = alive ? vec3(0.02) : vec3(0.55);
            alpha = contrast * (alive ? 1.0 : 0.35);
        } else {
            color = vec3(1.0);            // lighter than the field: the halo
            alpha = -contrast;
        }
    } else {
        float t = (u_channel == 0) ? v_charge : v_emit;
        color = alive ? ramp(t) : vec3(0.25);
        alpha = max(contrast, 0.0) * (alive ? 1.0 : 0.5);
    }

    alpha *= v_alpha_scale;
    if (alpha <= 0.002) discard;          // a heavily defocused cell is a whisper
    frag = vec4(color, clamp(alpha, 0.0, 1.0));
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
    p.u_focal_plane_um = glGetUniformLocation(p.program, "u_focal_plane_um");
    p.u_na             = glGetUniformLocation(p.program, "u_na");
    p.u_immersion      = glGetUniformLocation(p.program, "u_immersion");

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
    glUniform1f(p.u_focal_plane_um, static_cast<float>(cam.focal_plane * 1.0e6));
    const auto& obj = canon::OBJECTIVES[cam.objective];
    glUniform1f(p.u_na, static_cast<float>(obj.na));
    glUniform1f(p.u_immersion, static_cast<float>(obj.immersion));

    glBindVertexArray(p.vao);
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, count);
    glBindVertexArray(0);
    glUseProgram(0);
    glDisable(GL_BLEND);
}

} // namespace astro::render
