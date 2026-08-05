// src/render/bloom.cpp
#include "render/bloom.h"

#include <cstdio>

#include <glad/gl.h>

#include "contracts/render_view_v3.h"
#include "render/cells_pass.h"

namespace astro::render {

namespace {

// Fullscreen triangle from gl_VertexID -- no vertex buffer, like post_pass/bloom composite.
const char* kVert = R"GLSL(
#version 460 core
out vec2 v_uv;
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
)GLSL";

// The source is an EMISSION-ONLY buffer -- magenta on black, no silhouettes, no Taumoeba -- so there is
// no bright-pass: bloom all of it, and a dim emitter still gets a proportional halo while black stays
// black (so the frame's non-emitting regions, and the non-emitting m7b_petrova golden, are unchanged).
// Sum a few mip levels (glGenerateMipmap did the downsampling) for a tight core plus a soft, wide glow.
const char* kFrag = R"GLSL(
#version 460 core
in vec2 v_uv;
uniform sampler2D u_tex;
uniform float u_intensity;
uniform float u_lod;
out vec4 frag;
void main() {
    vec3 sum = textureLod(u_tex, v_uv, max(u_lod - 2.0, 0.0)).rgb * 0.5
             + textureLod(u_tex, v_uv, max(u_lod - 1.0, 0.0)).rgb * 0.8
             + textureLod(u_tex, v_uv, u_lod).rgb * 1.0;
    frag = vec4(sum * u_intensity, 0.0);   // additive; alpha 0 leaves the backbuffer alpha untouched
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

// (Re)allocate the emission texture to the framebuffer size and attach it to the FBO. RGBA8 with a mip
// chain (the blur pyramid); no depth attachment -- the cell pass blends in 2D and needs none.
void ensure_size(BloomPass& b, int w, int h) {
    if (b.tex_w == w && b.tex_h == h) return;
    glBindTexture(GL_TEXTURE_2D, b.emission_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindFramebuffer(GL_FRAMEBUFFER, b.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, b.emission_tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        std::printf("[gl] bloom FBO incomplete at %dx%d\n", w, h);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    b.tex_w = w; b.tex_h = h;
}

} // namespace

Error bloom_pass_create(BloomPass& b) {
    const unsigned int vs = compile(GL_VERTEX_SHADER, kVert, "bloom.vert");
    const unsigned int fs = compile(GL_FRAGMENT_SHADER, kFrag, "bloom.frag");
    if (!vs || !fs) return fail(Status::Unsupported, "bloom shader compile failed");

    b.program = glCreateProgram();
    glAttachShader(b.program, vs);
    glAttachShader(b.program, fs);
    glLinkProgram(b.program);
    int linked = 0;
    glGetProgramiv(b.program, GL_LINK_STATUS, &linked);
    glDeleteShader(vs);
    glDeleteShader(fs);
    if (!linked) return fail(Status::Unsupported, "bloom shader link failed");

    b.u_intensity = glGetUniformLocation(b.program, "u_intensity");
    b.u_lod       = glGetUniformLocation(b.program, "u_lod");
    glGenVertexArrays(1, &b.vao);
    glGenFramebuffers(1, &b.fbo);
    glGenTextures(1, &b.emission_tex);
    return ok();
}

void bloom_pass_destroy(BloomPass& b) {
    if (b.emission_tex) glDeleteTextures(1, &b.emission_tex);
    if (b.fbo) glDeleteFramebuffers(1, &b.fbo);
    if (b.vao) glDeleteVertexArrays(1, &b.vao);
    if (b.program) glDeleteProgram(b.program);
    b = BloomPass{};
}

void bloom_pass_apply(BloomPass& b, const CellsPass& cells, const Camera& cam,
                      int fb_w, int fb_h, int32_t cell_count, float intensity) {
    if (b.program == 0 || fb_w <= 0 || fb_h <= 0 || cell_count <= 0) return;
    ensure_size(b, fb_w, fb_h);

    // 1) Emission-only pass. cells_pass_draw clears to the Petrovascope background (black) and draws the
    //    instance range [0, cell_count) -- the Astrophage, NOT the Taumoeba appended after them -- so the
    //    FBO holds the emission magenta on black with no predators. Sphere morphology: the blur hides the
    //    silhouette, and the measurement goldens (which pin sphere) are captured with --no-bloom anyway.
    glBindFramebuffer(GL_FRAMEBUFFER, b.fbo);
    cells_pass_draw(cells, cam, fb_w, fb_h, cell_count, contract::ViewMode::Petrovascope,
                    contract::AnalysisChannel::Charge, contract::Morphology::Sphere, false);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    // 2) Blur pyramid over the emission-only buffer.
    glBindTexture(GL_TEXTURE_2D, b.emission_tex);
    glGenerateMipmap(GL_TEXTURE_2D);
    float max_lod = 0.0f;
    for (int m = (fb_w < fb_h ? fb_w : fb_h); m > 1; m >>= 1) max_lod += 1.0f;
    const float lod = max_lod > 3.0f ? max_lod - 3.0f : max_lod;

    // 3) Additive composite of the blurred emission over the backbuffer.
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE);
    glUseProgram(b.program);
    glUniform1f(b.u_intensity, intensity);
    glUniform1f(b.u_lod, lod);
    glBindVertexArray(b.vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glUseProgram(0);
    glDisable(GL_BLEND);
    glBindTexture(GL_TEXTURE_2D, 0);
}

} // namespace astro::render
