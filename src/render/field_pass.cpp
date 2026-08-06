// src/render/field_pass.cpp
#include "render/field_pass.h"

#include <cstdio>

#include <glad/gl.h>

namespace astro::render {

namespace {

// Fullscreen triangle from gl_VertexID -- no vertex buffer.
const char* kVert = R"GLSL(
#version 460 core
out vec2 v_uv;
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
)GLSL";

// Map each screen pixel through the camera window into chamber coordinates, then into the field grid, and
// false-colour the sampled temperature. The LUT is the film's IR grade: cold near-black, the medium's
// resting warmth as the old flat pink/red, hot toward white -- so the real temperature STRUCTURE reads
// (a warmed plume brightens) while the overall look stays "warm IR field". The grid spans the chamber
// [-extent/2, +extent/2]; a pixel outside it clamps to the edge (ambient).
const char* kFrag = R"GLSL(
#version 460 core
in vec2 v_uv;
uniform sampler2D u_field;
uniform vec2  u_center;       // camera centre, chamber coords [m]
uniform vec2  u_half_extent;  // camera half-window [m]
uniform float u_extent;       // chamber span [m] (square)
uniform float u_tmin, u_tmax; // temperature normalization [K]
out vec4 frag;

vec3 warm_ir(float t) {
    t = clamp(t, 0.0, 1.0);
    vec3 c0 = vec3(0.03, 0.01, 0.04);    // cold
    vec3 c1 = vec3(0.502, 0.106, 0.180); // resting warm (the old flat clear)
    vec3 c2 = vec3(0.95, 0.42, 0.28);    // hot
    vec3 c3 = vec3(1.00, 0.93, 0.78);    // hottest
    if (t < 0.34) return mix(c0, c1, t / 0.34);
    if (t < 0.67) return mix(c1, c2, (t - 0.34) / 0.33);
    return mix(c2, c3, (t - 0.67) / 0.33);
}

void main() {
    vec2 chamber_xy = u_center + (v_uv * 2.0 - 1.0) * u_half_extent;
    vec2 field_uv = (chamber_xy + 0.5 * u_extent) / u_extent;
    float T = texture(u_field, field_uv).r;
    float t = (T - u_tmin) / max(u_tmax - u_tmin, 1.0);
    frag = vec4(warm_ir(t), 1.0);
}
)GLSL";

unsigned int compile(unsigned int type, const char* src, const char* label) {
    const unsigned int s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    int okFlag = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &okFlag);
    if (!okFlag) {
        char log[1024];
        glGetShaderInfoLog(s, sizeof(log), nullptr, log);
        std::printf("[gl] %s compile failed:\n%s\n", label, log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

} // namespace

Error field_pass_create(FieldPass& f) {
    const unsigned int vs = compile(GL_VERTEX_SHADER, kVert, "field.vert");
    const unsigned int fs = compile(GL_FRAGMENT_SHADER, kFrag, "field.frag");
    if (!vs || !fs) return fail(Status::Unsupported, "field shader compile failed");

    f.program = glCreateProgram();
    glAttachShader(f.program, vs);
    glAttachShader(f.program, fs);
    glLinkProgram(f.program);
    int linked = 0;
    glGetProgramiv(f.program, GL_LINK_STATUS, &linked);
    glDeleteShader(vs);
    glDeleteShader(fs);
    if (!linked) return fail(Status::Unsupported, "field shader link failed");

    f.u_center      = glGetUniformLocation(f.program, "u_center");
    f.u_half_extent = glGetUniformLocation(f.program, "u_half_extent");
    f.u_extent      = glGetUniformLocation(f.program, "u_extent");
    f.u_tmin        = glGetUniformLocation(f.program, "u_tmin");
    f.u_tmax        = glGetUniformLocation(f.program, "u_tmax");
    glGenVertexArrays(1, &f.vao);
    glGenTextures(1, &f.tex);
    return ok();
}

void field_pass_destroy(FieldPass& f) {
    if (f.tex) glDeleteTextures(1, &f.tex);
    if (f.vao) glDeleteVertexArrays(1, &f.vao);
    if (f.program) glDeleteProgram(f.program);
    f = FieldPass{};
}

void field_pass_draw(FieldPass& f, const Camera& cam, int fb_w, int fb_h,
                     const float* host_field, int n, double extent, float tmin, float tmax) {
    if (f.program == 0 || !host_field || n <= 0) return;

    glBindTexture(GL_TEXTURE_2D, f.tex);
    if (f.tex_n != n) {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, n, n, 0, GL_RED, GL_FLOAT, host_field);
        f.tex_n = n;
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, n, n, GL_RED, GL_FLOAT, host_field);
    }

    double hx, hy;
    cam.half_extent(fb_w, fb_h, hx, hy);
    glDisable(GL_BLEND);                      // opaque background
    glUseProgram(f.program);
    glUniform2f(f.u_center, static_cast<float>(cam.center_x), static_cast<float>(cam.center_y));
    glUniform2f(f.u_half_extent, static_cast<float>(hx), static_cast<float>(hy));
    glUniform1f(f.u_extent, static_cast<float>(extent));
    glUniform1f(f.u_tmin, tmin);
    glUniform1f(f.u_tmax, tmax);
    glBindVertexArray(f.vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glUseProgram(0);
    glBindTexture(GL_TEXTURE_2D, 0);
}

} // namespace astro::render
