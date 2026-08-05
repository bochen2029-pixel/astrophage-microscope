// src/render/bloom.h -- bloom over the Petrova emission, from a SEPARATE emission buffer (M12h, ADR-044).
#pragma once

#include <cstdint>

#include "core/result.h"
#include "render/camera.h"

namespace astro::render {

struct CellsPass;   // fwd: bloom re-draws the Astrophage into its own buffer via the cell program

// Bloom for the Petrovascope emission only (RENDERING.md Sec 5). The Astrophage are re-drawn in
// Petrovascope into a private FBO -- emission magenta on black, with the Taumoeba predators EXCLUDED
// (only instances [0, cell_count) are drawn) -- and that emission-only buffer is blurred and added back
// over the frame. Rendering the emission separately is what makes "bloom the emission, not the predators"
// honest, and it lets even a dim emitter glow: the buffer is black everywhere else, so there is nothing
// else to wash out and the whole emission can bloom without a bright-pass. A non-emitting Petrovascope
// (the m7b_petrova golden) yields a black buffer -> bloom adds zero -> the golden is byte-identical
// (goldens also pin --no-bloom, the ADR-023 appearance precedent).
struct BloomPass {
    unsigned int fbo = 0;
    unsigned int emission_tex = 0;   // RGBA8, mipmapped: the emission-only image + its blur pyramid
    int tex_w = 0, tex_h = 0;
    unsigned int program = 0;        // composite: sum a few emission mips, additive
    unsigned int vao = 0;
    int u_intensity = -1, u_lod = -1;
};

Error bloom_pass_create(BloomPass& b);
void  bloom_pass_destroy(BloomPass& b);

// Re-draws the Astrophage (instances [0, cell_count), Taumoeba excluded) in Petrovascope into the bloom
// FBO, then blurs it via mipmaps and additively composites the glow over the backbuffer. Call AFTER the
// main cells pass, for Petrovascope only. A no-op if cell_count <= 0.
void  bloom_pass_apply(BloomPass& b, const CellsPass& cells, const Camera& cam,
                       int fb_w, int fb_h, int32_t cell_count, float intensity);

} // namespace astro::render
