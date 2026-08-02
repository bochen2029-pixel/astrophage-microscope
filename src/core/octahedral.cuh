// src/core/octahedral.cuh -- unit vector <-> 32 bits.
//
// contracts/render_view_v1.h packs a cell's emission axis into CellInstance::
// dir_packed so the instance stays at 32 bytes. Octahedral mapping gives ~0.01
// degree accuracy from two 16-bit snorm channels, which is far more than a
// visual emission lobe needs.
//
// Lives in core/ rather than inside the interop kernel so the round trip is
// testable on the host (ARCHITECTURE.md Sec 3.3).
#pragma once

#include <cmath>
#include <cstdint>

#include "core/units.h"
#include "core/vec.cuh"

namespace astro {

ASTRO_HD inline float oct_sign_nonzero(float v) { return v >= 0.0f ? 1.0f : -1.0f; }

ASTRO_HD inline uint32_t oct_encode(Vec3 n) {
    const double inv_l1 = 1.0 / (fabs(n.x) + fabs(n.y) + fabs(n.z) + 1e-300);
    float px = static_cast<float>(n.x * inv_l1);
    float py = static_cast<float>(n.y * inv_l1);
    if (n.z < 0.0) {
        const float ax = px, ay = py;
        px = (1.0f - fabsf(ay)) * oct_sign_nonzero(ax);
        py = (1.0f - fabsf(ax)) * oct_sign_nonzero(ay);
    }
    // snorm16, round-to-nearest, clamped so +1.0 does not wrap to -1.0.
    const float cx = px < -1.0f ? -1.0f : (px > 1.0f ? 1.0f : px);
    const float cy = py < -1.0f ? -1.0f : (py > 1.0f ? 1.0f : py);
    const int32_t qx = static_cast<int32_t>(lroundf(cx * 32767.0f));
    const int32_t qy = static_cast<int32_t>(lroundf(cy * 32767.0f));
    return (static_cast<uint32_t>(qx & 0xFFFF)) | (static_cast<uint32_t>(qy & 0xFFFF) << 16);
}

ASTRO_HD inline Vec3 oct_decode(uint32_t packed) {
    const int16_t sx = static_cast<int16_t>(packed & 0xFFFFu);
    const int16_t sy = static_cast<int16_t>((packed >> 16) & 0xFFFFu);
    float px = static_cast<float>(sx) / 32767.0f;
    float py = static_cast<float>(sy) / 32767.0f;
    float pz = 1.0f - fabsf(px) - fabsf(py);
    if (pz < 0.0f) {
        const float ax = px, ay = py;
        px = (1.0f - fabsf(ay)) * oct_sign_nonzero(ax);
        py = (1.0f - fabsf(ax)) * oct_sign_nonzero(ay);
    }
    return normalize(Vec3{px, py, pz});
}

} // namespace astro
