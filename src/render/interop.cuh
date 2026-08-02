// src/render/interop.cuh -- CUDA writes the instance buffer GL draws from.
//
// The whole point: cell positions never touch host memory. A kernel writes
// CellInstance straight into a GL buffer registered with CUDA
// (ARCHITECTURE.md Sec 3.1).
#pragma once

#include <cstdint>

#include "contracts/cell_store_v1.h"
#include "contracts/render_view_v1.h"
#include "core/result.h"

struct cudaGraphicsResource;

namespace astro::render {

struct InteropBuffer {
    unsigned int          gl_buffer = 0;      // GLuint, kept opaque so sim-side
    cudaGraphicsResource* resource  = nullptr;// callers need no GL header
    size_t                capacity  = 0;      // in CellInstance units
};

// Registers an existing GL buffer for CUDA write access.
Error interop_register(InteropBuffer& b, unsigned int gl_buffer, size_t instance_capacity);
void  interop_unregister(InteropBuffer& b);

// Maps the buffer, fills [0, count) from the cell store, unmaps. One kernel.
Error interop_fill_cells(InteropBuffer& b, const contract::CellStoreView& cells, int32_t count);

} // namespace astro::render
