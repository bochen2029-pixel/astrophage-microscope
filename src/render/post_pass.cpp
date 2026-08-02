// src/render/post_pass.cpp
#include "render/post_pass.h"

#include <cstdio>

#include <glad/gl.h>

namespace astro::render {

namespace {

// Fullscreen triangle from gl_VertexID -- no vertex buffer, no index buffer.
const char* kVert = R"GLSL(
#version 460 core
out vec2 v_uv;
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
)GLSL";

const char* kFrag = R"GLSL(
#version 460 core
in vec2 v_uv;
uniform float u_strength;
uniform float u_warmth;
uniform float u_aspect;
out vec4 frag;

void main() {
    // Circular in SCREEN space, not UV space: a condenser aperture is round, so
    // the falloff must not stretch with the window.
    vec2 d = (v_uv - 0.5) * vec2(u_aspect, 1.0);
    float r = length(d) / length(vec2(0.5 * u_aspect, 0.5));

    // Gentle cos^4-ish falloff, which is roughly what real illumination does.
    float v = 1.0 - u_strength * pow(clamp(r, 0.0, 1.0), 2.5);

    // The lamp is warm, so the falloff cools: blue drops fastest.
    vec3 tint = vec3(1.0, 1.0 - 0.25 * u_warmth * (1.0 - v),
                          1.0 - 0.60 * u_warmth * (1.0 - v));
    frag = vec4(vec3(v) * tint, 1.0);
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

Error post_pass_create(PostPass& p) {
    const unsigned int vs = compile(GL_VERTEX_SHADER, kVert, "post.vert");
    const unsigned int fs = compile(GL_FRAGMENT_SHADER, kFrag, "post.frag");
    if (!vs || !fs) return fail(Status::Unsupported, "post shader compile failed");

    p.program = glCreateProgram();
    glAttachShader(p.program, vs);
    glAttachShader(p.program, fs);
    glLinkProgram(p.program);
    int linked = 0;
    glGetProgramiv(p.program, GL_LINK_STATUS, &linked);
    glDeleteShader(vs);
    glDeleteShader(fs);
    if (!linked) return fail(Status::Unsupported, "post shader link failed");

    p.u_strength = glGetUniformLocation(p.program, "u_strength");
    p.u_warmth   = glGetUniformLocation(p.program, "u_warmth");
    p.u_aspect   = glGetUniformLocation(p.program, "u_aspect");
    glGenVertexArrays(1, &p.vao);
    return ok();
}

void post_pass_destroy(PostPass& p) {
    if (p.vao) glDeleteVertexArrays(1, &p.vao);
    if (p.program) glDeleteProgram(p.program);
    p = PostPass{};
}

void post_pass_draw(const PostPass& p, int fb_w, int fb_h, float strength, float warmth) {
    if (strength <= 0.0f || p.program == 0) return;
    glEnable(GL_BLEND);
    glBlendFunc(GL_ZERO, GL_SRC_COLOR);        // multiply
    glUseProgram(p.program);
    glUniform1f(p.u_strength, strength);
    glUniform1f(p.u_warmth, warmth);
    glUniform1f(p.u_aspect, fb_h > 0 ? static_cast<float>(fb_w) / fb_h : 1.0f);
    glBindVertexArray(p.vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glUseProgram(0);
    glDisable(GL_BLEND);
}

} // namespace astro::render
