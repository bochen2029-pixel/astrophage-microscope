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
const char* kVertBody = R"GLSL(
layout(location = 0) in vec4  a_pos_radius;   // x, y, z, radius   [um]
layout(location = 1) in vec2  a_state;        // charge, emit_power_norm
layout(location = 2) in uvec2 a_flags;        // flags_packed, dir_packed
layout(location = 3) in uint  a_shape_seed;   // stable per-cell silhouette seed

uniform vec2  u_center_um;
uniform vec2  u_half_extent_um;
uniform float u_px_per_um;
uniform float u_focal_plane_um;
uniform float u_na;
uniform float u_immersion;
uniform int   u_morphology;   // contract::Morphology

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
out float v_shape_w;      // how much silhouette survives the blur, [0,1]
flat out uint v_flags;
flat out uint v_seed;

void main() {
    float a  = a_pos_radius.w;                                   // true radius
    float dz = a_pos_radius.z - u_focal_plane_um;
    float r_coc = abs(dz) * u_na / u_immersion;                  // optics.h
    float r_eff = sqrt(a * a + r_coc * r_coc);
    float peak  = (a * a) / (r_eff * r_eff);                     // energy conserving

    float px_um = 1.0 / u_px_per_um;
    float edge  = max(r_coc, px_um);          // in focus, soften by one pixel only

    // Q8: cull cells whose peak opacity can never clear the fragment discard
    // threshold. A cell 40 um out of focus contributes under 2 % opacity while
    // covering ~64x the in-focus area, so this is the cheapest attack on the
    // dominant fill-rate cost (RENDERING.md Sec 7). Degenerate the quad rather
    // than branch: no fragments, no work.
    if (peak <= 0.002) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        return;
    }

    // Silhouette survives only as far as geometry dominates blur (morphology.h).
    // In focus w = 1 and the full shape shows; heavily defocused w -> 0 and the
    // cell images as a featureless disc, which is what blur actually does.
    v_seed    = (u_morphology == 0) ? 0u : a_shape_seed;
    v_shape_w = (u_morphology == 0) ? 0.0 : a / r_eff;

    // Where the profile has essentially reached zero. The quad must bound the
    // widest the silhouette can reach, or a cell gets clipped by its own quad and
    // renders with a razor-straight cut edge.
    float extent_um = r_eff * shape_radius_max(v_seed, v_shape_w) + edge;

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

// MIRRORS src/render/morphology.h shape_radius(). Change one, change both --
// this is the fifth formula duplicated across the GLSL boundary with no compiler
// check (ADR-017, Q7). test_morphology guards the C++ side; the irregular golden
// guards this side.
const char* kShapeGLSL = R"GLSL(
uint morph_hash(uint x) {
    x ^= x >> 16; x *= 0x7FEB352Du;
    x ^= x >> 15; x *= 0x846CA68Bu;
    x ^= x >> 16;
    return x;
}

float morph_phase(uint seed, uint k) {
    return 6.283185307179586 * float(morph_hash(seed + k * 0x9E3779B9u)) * (1.0 / 4294967296.0);
}

float shape_radius(float theta, uint seed, float w) {
    if (seed == 0u || w <= 0.0) return 1.0;
    w = min(w, 1.0);
    float sum = 0.0;
    float sq  = 0.0;
    for (uint k = 3u; k <= 8u; ++k) {
        float A = 0.28 / float(k);
        sum += A * cos(float(k) * theta + morph_phase(seed, k));
        sq  += A * A;
    }
    float r = (1.0 + w * sum) * inversesqrt(1.0 + 0.5 * w * w * sq);
    return max(r, 0.05);
}

// The bound the vertex stage sizes its quad from. Same constants as above, so it
// lives beside them rather than being spelled out a third time in the vertex body.
float shape_radius_max(uint seed, float w) {
    if (seed == 0u || w <= 0.0) return 1.0;
    w = min(w, 1.0);
    float sum = 0.0;
    float sq  = 0.0;
    for (uint k = 3u; k <= 8u; ++k) {
        float A = 0.28 / float(k);
        sum += A;
        sq  += A * A;
    }
    return (1.0 + w * sum) * inversesqrt(1.0 + 0.5 * w * w * sq);
}
)GLSL";

const char* kVersion = "#version 460 core\n";

const char* kFragBody = R"GLSL(
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
in float v_shape_w;
flat in uint v_flags;
flat in uint v_seed;

uniform int u_mode;       // contract::ViewMode
uniform int u_channel;    // contract::AnalysisChannel
uniform int u_colorblind; // ScopeState::colorblind_safe -- swaps the petrova-film LUT for magma
uniform int u_mode_blend_to; // cross-fade target mode (M12f)
uniform float u_blend;       // 0 = u_mode, 1 = u_mode_blend_to

out vec4 frag;

const uint FLAG_ALIVE = 2u;
const uint FLAG_AWAKE = 4u;   // thermostat engaged: surface held at the setpoint

// Provisional magma-like ramp (perceptually-uniform-ish). The real 1D-texture
// LUTs are RENDERING.md Sec 5; this keeps the pass free of texture plumbing. Used
// for the Analysis channels and, at its warm end, for the Thermal-IR glow.
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

// The Petrova-film LUT: dark plum -> magenta -> hot pink (RENDERING.md Sec 5,
// #3D0620 -> #C4187A -> #FF2D95). Deliberately a different colour family from the
// thermal ramp so the two IR modes never read alike.
vec3 petrova(float t) {
    t = clamp(t, 0.0, 1.0);
    vec3 c0 = vec3(0.239, 0.024, 0.125);
    vec3 c1 = vec3(0.769, 0.094, 0.478);
    vec3 c2 = vec3(1.000, 0.176, 0.584);
    if (t < 0.5) return mix(c0, c1, t / 0.5);
    return mix(c1, c2, (t - 0.5) / 0.5);
}

// M12f: one mode's cell appearance as a function of the shared optics terms. This is
// the per-mode if/else that used to live inline in main -- factored out UNCHANGED so
// the cross-fade can evaluate two modes and dissolve between them, and so u_blend == 0
// reproduces the old output bit-for-bit. RENDERING.md Sec 4; docs/PHYSICS.md Sec 10.
vec4 appearance(int mode, float contrast, float cov_a, float band, bool alive, bool awake) {
    vec3 color;
    float alpha;
    if (mode == 0) {
        // Brightfield: live Astrophage opaque black, dead cells translucent; the
        // negative-contrast case is the bright halo just outside the edge.
        if (contrast >= 0.0) {
            color = alive ? vec3(0.02) : vec3(0.55);
            alpha = contrast * (alive ? 1.0 : 0.35);
        } else {
            color = vec3(1.0);
            alpha = -contrast;
        }
    } else if (mode == 1) {
        // Darkfield: a bright edge shell on black, reinforced by the Becke band.
        float shell = cov_a * (1.0 - cov_a) * 4.0;
        float rim = max(shell, band);
        color = alive ? vec3(0.75, 0.86, 1.0) : vec3(0.50, 0.55, 0.60);
        alpha = rim * (alive ? 1.0 : 0.6);
    } else if (mode == 2) {
        // Petrovascope: the 25.984 um line only; a non-emitting cell is invisible.
        float e = alive ? v_emit : 0.0;
        color = (u_colorblind != 0) ? ramp(0.35 + 0.65 * e) : petrova(0.35 + 0.65 * e);
        alpha = cov_a * e;
    } else if (mode == 3) {
        // Thermal IR (film grade): albedo-0 cells are black absorbers; an AWAKE cell
        // is a heat source and takes a hot rim (the latch, ADR-003). The T-field
        // false-colour behind it and per-cell pre-ignition warmth are M12h/M12g.
        float hot = (alive && awake) ? 1.0 : 0.0;
        if (contrast >= 0.0) {
            color = mix(vec3(0.02), vec3(1.0, 0.80, 0.45), clamp(band * hot * 2.0, 0.0, 1.0));
            alpha = max(cov_a, band * hot);
        } else {
            color = vec3(1.0, 0.85, 0.60);
            alpha = -contrast;
        }
    } else {
        // Analysis: flat discs coloured by the selected channel.
        float t = (u_channel == 0) ? v_charge : v_emit;
        color = alive ? ramp(t) : vec3(0.25);
        alpha = cov_a * (alive ? 1.0 : 0.5);
    }
    return vec4(color, alpha);
}

void main() {
    vec2  p = v_local * v_draw_um;              // offset from centre, um
    float d = length(p);

    // The silhouette. Sphere morphology and the heavily-defocused limit both give
    // shape == 1 and this collapses to the original circular profile exactly
    // (RENDERING.md Sec 8, ADR-023). The shape is AREA-PRESERVING, so an irregular
    // cell absorbs precisely as much light as the sphere it stands for.
    float theta = atan(p.y, p.x);
    float shape = shape_radius(theta, v_seed, v_shape_w);

    // The rim is ruffled by the SILHOUETTE, never by the falloff width. Modulating
    // the softness per angle looks like an obvious way to frill the edge and is a
    // trap: a radially-varying falloff distance renders as radial spokes, and cells
    // come out as starbursts rather than grains. The crinkle belongs in
    // shape_radius, where it perturbs where the outline is (ADR-023).

    // The blurred disc: a uniform disc convolved with the defocus kernel,
    // approximated as a soft-edged profile of radius r_eff and softness edge.
    float r_edge = v_r_eff * shape;
    float cov = 1.0 - smoothstep(r_edge - v_edge_um, r_edge + v_edge_um, d);

    // Becke line. A real diffraction artefact at the edge of an opaque object in
    // brightfield: a narrow band just outside the geometric edge that is BRIGHT
    // on one side of focus and DARK on the other. That inversion is how a viewer
    // knows which way to rack the focus. It follows the silhouette, not a circle.
    float band = 0.0;
    if (v_ring > 0.0) {
        float t = (d - v_radius_um * shape * 1.06) / (v_radius_um * 0.16);
        band = exp(-t * t) * v_ring;
    }

    // Signed contrast against the background: positive darkens (absorption),
    // negative brightens (the halo).
    float contrast = v_peak * cov - v_polarity * band * 0.5;

    bool alive = (v_flags & FLAG_ALIVE) != 0u;
    bool awake = (v_flags & FLAG_AWAKE) != 0u;
    float cov_a = max(contrast, 0.0);        // positive coverage: the disc fill

    // Predators (Taumoeba) carry a render-only marker bit set in interop.cu (0x8000, see
    // RENDER_FLAG_TAUMOEBA). They are 4x a cell and read the same in every mode: a translucent
    // teal membrane blob, distinct from the opaque black Astrophage. Sim never sets this bit,
    // so a cell always skips this branch and every measurement golden is byte-identical.
    if ((v_flags & 0x8000u) != 0u) {
        // Colour the predator by its N2 tolerance (carried in v_charge by interop.cu, M12b):
        // the intolerant are a pale teal, the evolved Taumoeba-82.5 strain a vivid gold-green,
        // so the evolution arc is visible -- the swarm warms toward gold as selection breeds
        // tolerance (docs/PHYSICS.md Sec 11, the biology's emotional peak, M12e).
        float tol = clamp(v_charge, 0.0, 1.0);
        vec3 tcol = alive ? mix(vec3(0.30, 0.62, 0.70), vec3(0.80, 0.93, 0.30), tol)
                          : vec3(0.45, 0.46, 0.50);
        float talpha = cov_a * (alive ? 0.55 : 0.35) * v_alpha_scale;
        if (talpha <= 0.002) discard;
        frag = vec4(tcol, clamp(talpha, 0.0, 1.0));
        return;
    }

    // M12f: the cross-fade. A mode's cell appearance is a function of the shared optics
    // terms, so it is evaluated for the primary mode AND the blend target and dissolved
    // between them. Blending in PREMULTIPLIED alpha is load-bearing: a cell invisible in
    // one mode (Petrovascope at emit 0) must add no colour to the mix, only its zero
    // coverage. At u_blend == 0, a1 == a0 and this reduces to the primary mode exactly --
    // every measurement golden is captured at blend 0, so none can move.
    vec4 a0 = appearance(u_mode, contrast, cov_a, band, alive, awake);
    vec4 a1 = (u_blend > 0.0) ? appearance(u_mode_blend_to, contrast, cov_a, band, alive, awake) : a0;
    float apre = mix(a0.a, a1.a, u_blend);
    vec3  pm   = mix(a0.rgb * a0.a, a1.rgb * a1.a, u_blend);
    vec3  color = (apre > 0.0) ? pm / apre : vec3(0.0);
    float alpha = apre * v_alpha_scale;
    if (alpha <= 0.002) discard;          // a heavily defocused cell is a whisper
    frag = vec4(color, clamp(alpha, 0.0, 1.0));
}
)GLSL";

// Multi-source so the shared shape function can be spliced between the #version
// line and each stage's body without duplicating it in two raw strings.
unsigned int compile(unsigned int type, const char* const* srcs, int n, const char* label) {
    const unsigned int s = glCreateShader(type);
    glShaderSource(s, n, srcs, nullptr);
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

// The mode's flat background clear colour. Extracted so the cross-fade can lerp between
// two modes' backgrounds (M12f); at blend 0 it is exactly the old per-mode clear, so the
// goldens are unmoved.
void mode_clear_color(ViewMode mode, float rgb[3]) {
    switch (mode) {
        case ViewMode::Brightfield:  rgb[0] = 0.961f; rgb[1] = 0.941f; rgb[2] = 0.902f; break;
        case ViewMode::Darkfield:    rgb[0] = 0.020f; rgb[1] = 0.020f; rgb[2] = 0.030f; break;
        case ViewMode::Petrovascope: rgb[0] = 0.000f; rgb[1] = 0.000f; rgb[2] = 0.000f; break;
        case ViewMode::ThermalIR:    rgb[0] = 0.502f; rgb[1] = 0.106f; rgb[2] = 0.180f; break;
        default:                     rgb[0] = 0.055f; rgb[1] = 0.055f; rgb[2] = 0.070f; break;
    }
}

} // namespace

Error cells_pass_create(CellsPass& p, int32_t cell_capacity, int32_t tau_capacity) {
    // The VBO and the CUDA-registered buffer hold cells then Taumoeba; p.capacity below stays
    // the CELL capacity so the app's HUD and respawn clamp keep meaning what they meant.
    const int32_t instance_capacity = cell_capacity + tau_capacity;
    const char* vsrc[] = {kVersion, kShapeGLSL, kVertBody};
    const char* fsrc[] = {kVersion, kShapeGLSL, kFragBody};
    const unsigned int vs = compile(GL_VERTEX_SHADER, vsrc, 3, "cells.vert");
    const unsigned int fs = compile(GL_FRAGMENT_SHADER, fsrc, 3, "cells.frag");
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
    p.u_morphology     = glGetUniformLocation(p.program, "u_morphology");
    p.u_colorblind     = glGetUniformLocation(p.program, "u_colorblind");
    p.u_mode_blend_to  = glGetUniformLocation(p.program, "u_mode_blend_to");
    p.u_blend          = glGetUniformLocation(p.program, "u_blend");

    glGenVertexArrays(1, &p.vao);
    glGenBuffers(1, &p.instance_vbo);
    glBindVertexArray(p.vao);
    glBindBuffer(GL_ARRAY_BUFFER, p.instance_vbo);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(sizeof(CellInstance)) * instance_capacity,
                 nullptr, GL_DYNAMIC_DRAW);

    // Layout must match contracts/render_view_v2.h CellInstance exactly.
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
    glEnableVertexAttribArray(3);
    glVertexAttribIPointer(3, 1, GL_UNSIGNED_INT, stride, reinterpret_cast<void*>(32));
    glVertexAttribDivisor(3, 1);
    glBindVertexArray(0);

    p.capacity = cell_capacity;   // the app reads this as the cell capacity (see header)
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
                     int32_t count, ViewMode mode, AnalysisChannel channel,
                     contract::Morphology morphology, bool colorblind,
                     ViewMode mode_blend_to, float mode_blend) {
    // The background is part of the mode: brightfield is lamp-white, the IR modes are
    // near-black so a faint glow reads, and Analysis is a neutral dark grey. The
    // cross-fade lerps between the primary and target mode backgrounds (M12f); at
    // mode_blend 0 this is exactly the primary mode's clear colour, so goldens are unmoved.
    float bg0[3], bg1[3];
    mode_clear_color(mode, bg0);
    mode_clear_color(mode_blend_to, bg1);
    const float tb = mode_blend;
    glClearColor(bg0[0] + (bg1[0] - bg0[0]) * tb,
                 bg0[1] + (bg1[1] - bg0[1]) * tb,
                 bg0[2] + (bg1[2] - bg0[2]) * tb, 1.0f);
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
    glUniform1i(p.u_morphology, static_cast<int>(morphology));
    glUniform1i(p.u_colorblind, colorblind ? 1 : 0);
    glUniform1i(p.u_mode_blend_to, static_cast<int>(mode_blend_to));
    glUniform1f(p.u_blend, mode_blend);

    glBindVertexArray(p.vao);
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, count);
    glBindVertexArray(0);
    glUseProgram(0);
    glDisable(GL_BLEND);
}

} // namespace astro::render
