// src/render/interop.cuh -- CUDA writes the instance buffer GL draws from.
//
// The whole point: cell positions never touch host memory. A kernel writes
// CellInstance straight into a GL buffer registered with CUDA
// (ARCHITECTURE.md Sec 3.1).
#pragma once

#include <cstdint>

#include "contracts/cell_store_v1.h"
#include "contracts/render_view_v3.h"
#include "contracts/taumoeba_view_v1.h"
#include "core/result.h"

struct cudaGraphicsResource;

namespace astro::render {

// A render-only bit set in CellInstance::flags_packed to mark a Taumoeba instance (M12b). It
// lives in bits 6-15 of the CellFlags region, which sim never sets, so a cell always reads 0
// here and the fragment shader's predator branch is a no-op for cells (goldens untouched). The
// shader hardcodes 0x8000 -- change one, change both (the flags cross the GLSL boundary
// uncompiler-checked, ADR-017's class of hazard).
inline constexpr uint32_t RENDER_FLAG_TAUMOEBA = 1u << 15;

struct InteropBuffer {
    unsigned int          gl_buffer = 0;      // GLuint, kept opaque so sim-side
    cudaGraphicsResource* resource  = nullptr;// callers need no GL header
    size_t                capacity  = 0;      // in CellInstance units
};

// Registers an existing GL buffer for CUDA write access.
Error interop_register(InteropBuffer& b, unsigned int gl_buffer, size_t instance_capacity);
void  interop_unregister(InteropBuffer& b);

// Maps the buffer ONCE, fills cells into [0, cell_count) and Taumoeba into
// [cell_count, cell_count + tau_count), and unmaps. A single map is mandatory: the buffer is
// registered WriteDiscard, so a second map would discard the cells written by the first.
// `total_out` receives the instance count to draw; pass tau.count 0 (or a null store) for a
// cells-only frame. The Taumoeba region begins at cell_count (RenderFrame::taumoeba_offset).
Error interop_fill_frame(InteropBuffer& b, const contract::CellStoreView& cells, int32_t cell_count,
                         const contract::TaumoebaView& tau, int32_t tau_count, int32_t& total_out);

} // namespace astro::render
