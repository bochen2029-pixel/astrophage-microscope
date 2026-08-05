// src/render/interop.cu
#include "render/interop.cuh"

// glad must come first: cuda_gl_interop.h uses GLuint/GLenum without declaring
// them, so including it standalone fails with 15 confusing errors about
// "variable GLuint is not a type name".
#include <glad/gl.h>

#include <cuda_gl_interop.h>
#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "core/octahedral.cuh"
#include "core/rng.cuh"
#include "core/units.h"

namespace astro::render {

using namespace astro::contract;

namespace {

__global__ void fill_instances(CellInstance* out, CellStoreView v, int32_t count) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;

    CellInstance inst;
    // Micrometres, fp32: the one sanctioned display-unit conversion outside ui/.
    // fp32 metres would lose the sub-micron structure the optics model needs.
    inst.x_um = static_cast<float>(v.x[i] * 1.0e6);
    inst.y_um = static_cast<float>(v.y[i] * 1.0e6);
    inst.z_um = static_cast<float>(v.z[i] * 1.0e6);
    inst.radius_um = static_cast<float>(canon::CELL_RADIUS * 1.0e6);   // true size, never inflated

    inst.charge = static_cast<float>(v.energy[i] / canon::CELL_ENERGY_MAX);
    inst.emit_power_norm = static_cast<float>(v.emit_power[i] / canon::PETROVA_MAX_POWER);

    const uint32_t flags = v.flags[i];
    inst.flags_packed = (flags & 0xFFFFu) | (static_cast<uint32_t>(v.death_cause[i]) << 16);
    inst.dir_packed = oct_encode(Vec3{v.dir_x[i], v.dir_y[i], v.dir_z[i]});

    // Silhouette seed from the cell's MONOTONIC ID, never from `i`. A slot-derived
    // seed would reshape every cell the moment M9's compaction moves it -- the same
    // class of mistake INV-1 forbids for the RNG (ADR-023). Never zero: zero is the
    // sentinel the shader reads as "perfectly circular".
    const uint32_t seed = static_cast<uint32_t>(splitmix64(v.id[i]) >> 32);
    inst.shape_seed = seed | 1u;

    // v3 (ADR-043): temperature for the Thermal-IR pre-ignition warm-up, in Celsius (the
    // instance's display unit). temp_cell is refreshed each tick by the thermal stage.
    inst.temp_c = static_cast<float>(v.temp_cell[i] - 273.15);

    out[i] = inst;
}

// A Taumoeba becomes a CellInstance at its true size (TAU_RADIUS, 4x a cell), marked with
// the render-only predator bit so the fragment shader draws it distinctly. Written at
// `offset` so the predators occupy [offset, offset + count) after the cells (M12b).
__global__ void fill_taumoeba(CellInstance* out, TaumoebaView t, int32_t count, int32_t offset) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= count) return;

    CellInstance inst;
    inst.x_um = static_cast<float>(t.x[i] * 1.0e6);
    inst.y_um = static_cast<float>(t.y[i] * 1.0e6);
    inst.z_um = static_cast<float>(t.z[i] * 1.0e6);
    inst.radius_um = static_cast<float>(canon::TAU_RADIUS * 1.0e6);   // true size, never inflated

    // Reuse `charge` to carry N2 tolerance, so a future Analysis channel can colour the
    // evolution; emission is meaningless for a predator.
    inst.charge = t.tolerance ? t.tolerance[i] : 0.0f;
    inst.emit_power_norm = 0.0f;

    const uint32_t flags = t.flags[i];
    inst.flags_packed = (flags & 0xFFFFu) | RENDER_FLAG_TAUMOEBA;
    inst.dir_packed = 0u;

    const uint32_t seed = static_cast<uint32_t>(splitmix64(t.id[i]) >> 32);
    inst.shape_seed = seed | 1u;                                     // an irregular blob
    inst.temp_c = 0.0f;                                             // unused: the predator branch ignores it

    out[offset + i] = inst;
}

} // namespace

Error interop_register(InteropBuffer& b, unsigned int gl_buffer, size_t instance_capacity) {
    // WriteDiscard: CUDA overwrites every instance each frame, so the driver may
    // skip preserving the previous contents.
    const cudaError_t e = cudaGraphicsGLRegisterBuffer(
        &b.resource, gl_buffer, cudaGraphicsRegisterFlagsWriteDiscard);
    if (e != cudaSuccess) return fail(Status::CudaError, "cudaGraphicsGLRegisterBuffer");
    b.gl_buffer = gl_buffer;
    b.capacity = instance_capacity;
    return ok();
}

void interop_unregister(InteropBuffer& b) {
    if (b.resource) cudaGraphicsUnregisterResource(b.resource);
    b = InteropBuffer{};
}

Error interop_fill_frame(InteropBuffer& b, const CellStoreView& cells, int32_t cell_count,
                         const TaumoebaView& tau, int32_t tau_count, int32_t& total_out) {
    if (cell_count < 0) cell_count = 0;
    if (tau_count < 0) tau_count = 0;
    total_out = cell_count + tau_count;
    if (!b.resource) return fail(Status::InvalidArgument, "interop buffer not registered");
    if (total_out <= 0) return ok();
    if (static_cast<size_t>(total_out) > b.capacity)
        return fail(Status::CapacityExceeded, "instance count exceeds buffer capacity");

    if (cudaGraphicsMapResources(1, &b.resource, 0) != cudaSuccess)
        return fail(Status::CudaError, "cudaGraphicsMapResources");

    CellInstance* dev = nullptr;
    size_t bytes = 0;
    if (cudaGraphicsResourceGetMappedPointer(reinterpret_cast<void**>(&dev), &bytes, b.resource)
        != cudaSuccess) {
        cudaGraphicsUnmapResources(1, &b.resource, 0);
        return fail(Status::CudaError, "cudaGraphicsResourceGetMappedPointer");
    }

    // Cells into [0, cell_count), Taumoeba into [cell_count, total). ONE map -- the buffer is
    // WriteDiscard, so a second map would throw away the cells the first kernel just wrote.
    const int block = 256;
    if (cell_count > 0)
        fill_instances<<<(cell_count + block - 1) / block, block>>>(dev, cells, cell_count);
    if (tau_count > 0)
        fill_taumoeba<<<(tau_count + block - 1) / block, block>>>(dev, tau, tau_count, cell_count);
    const cudaError_t launch = cudaGetLastError();

    cudaGraphicsUnmapResources(1, &b.resource, 0);
    if (launch != cudaSuccess) return fail(Status::CudaError, "interop fill launch");
    return ok();
}

} // namespace astro::render
