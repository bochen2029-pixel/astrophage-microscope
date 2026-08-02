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

    out[i] = inst;
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

Error interop_fill_cells(InteropBuffer& b, const CellStoreView& cells, int32_t count) {
    if (!b.resource) return fail(Status::InvalidArgument, "interop buffer not registered");
    if (count <= 0) return ok();
    if (static_cast<size_t>(count) > b.capacity)
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

    const int block = 256;
    fill_instances<<<(count + block - 1) / block, block>>>(dev, cells, count);
    const cudaError_t launch = cudaGetLastError();

    cudaGraphicsUnmapResources(1, &b.resource, 0);
    if (launch != cudaSuccess) return fail(Status::CudaError, "fill_instances launch");
    return ok();
}

} // namespace astro::render
