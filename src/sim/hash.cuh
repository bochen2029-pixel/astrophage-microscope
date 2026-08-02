// src/sim/hash.cuh -- uniform spatial hash. Tick stage 1.
//
// Everything after M4 depends on this: contact, predation, the taxis density
// sense, and the M6 analytic near-field correction all need neighbours.
//
// DETERMINISM IS THE WHOLE DESIGN CONSTRAINT HERE (ADR-018). The textbook
// counting sort scatters with `slot = atomicAdd(&cursor[key], 1)`, which makes
// the order WITHIN a bucket depend on which thread wins a race. That order then
// decides the summation order of contact forces, and float addition is not
// associative -- so INV-8 would break on every run, invisibly. A stable radix
// sort costs a little more and removes the hazard entirely.
#pragma once

#include <cstdint>

#include "contracts/cell_store_v1.h"
#include "core/result.h"
#include "core/units.h"
#include "core/vec.cuh"
#include "sim/cell_store.cuh"

namespace astro::sim {

// Passed by value into kernels. POD.
struct HashView {
    const uint32_t* vals_sorted;    // cell indices, ordered by bucket
    const int32_t*  bucket_start;   // first entry of each bucket
    const int32_t*  bucket_end;     // one past the last
    int32_t nx, ny, nz;
    int32_t bucket_count;
    float   cell_size;
    float   inv_cell_size;
    float   origin_x, origin_y, origin_z;   // chamber min corner
};

struct SpatialHash {
    uint32_t* d_keys = nullptr;
    uint32_t* d_keys_sorted = nullptr;
    uint32_t* d_vals = nullptr;
    uint32_t* d_vals_sorted = nullptr;
    int32_t*  d_bucket_start = nullptr;
    int32_t*  d_bucket_end = nullptr;
    void*     d_temp = nullptr;
    size_t    temp_bytes = 0;
    int32_t   nx = 0, ny = 0, nz = 0, bucket_count = 0;
    double    cell_size = 0.0;
    int32_t   capacity = 0;
};

Error hash_create(SpatialHash& h, const Chamber& c, int32_t capacity);
void  hash_destroy(SpatialHash& h);
Error hash_build(SpatialHash& h, const contract::CellStoreView& cells, int32_t count);
HashView hash_view(const SpatialHash& h);

// ---------------------------------------------------------------------------
// Device-side lookup
// ---------------------------------------------------------------------------

ASTRO_HD inline int32_t hash_clampi(int32_t v, int32_t lo, int32_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

ASTRO_HD inline void hash_coords(const HashView& h, double x, double y, double z,
                                 int32_t& gx, int32_t& gy, int32_t& gz) {
    gx = hash_clampi(static_cast<int32_t>((x - h.origin_x) * h.inv_cell_size), 0, h.nx - 1);
    gy = hash_clampi(static_cast<int32_t>((y - h.origin_y) * h.inv_cell_size), 0, h.ny - 1);
    gz = hash_clampi(static_cast<int32_t>((z - h.origin_z) * h.inv_cell_size), 0, h.nz - 1);
}

ASTRO_HD inline uint32_t hash_index(const HashView& h, int32_t gx, int32_t gy, int32_t gz) {
    return static_cast<uint32_t>((gz * h.ny + gy) * h.nx + gx);
}

ASTRO_HD inline uint32_t hash_key(const HashView& h, double x, double y, double z) {
    int32_t gx, gy, gz;
    hash_coords(h, x, y, z, gx, gy, gz);
    return hash_index(h, gx, gy, gz);
}

// Iterate the 27-cell neighbourhood in a FIXED order (z, then y, then x, then
// sorted position within the bucket). That fixed order is what makes a
// per-thread force sum reproducible without fixed-point accumulation.
//
// VARIADIC ON PURPOSE. Braces do NOT protect commas in a macro argument -- only
// parentheses do -- so a body containing `Vec3{a, b, c}` or a multi-declarator
// `double x = ..., y = ...;` would be split into extra arguments and fail to
// compile with a wholly misleading error. __VA_ARGS__ swallows them.
#define ASTRO_FOR_EACH_NEIGHBOUR(h, px, py, pz, jvar, ...)                      \
    do {                                                                        \
        int32_t _gx, _gy, _gz;                                                   \
        hash_coords((h), (px), (py), (pz), _gx, _gy, _gz);                       \
        for (int32_t _dz = -1; _dz <= 1; ++_dz) {                                \
            const int32_t _cz = _gz + _dz;                                       \
            if (_cz < 0 || _cz >= (h).nz) continue;                              \
            for (int32_t _dy = -1; _dy <= 1; ++_dy) {                            \
                const int32_t _cy = _gy + _dy;                                   \
                if (_cy < 0 || _cy >= (h).ny) continue;                          \
                for (int32_t _dx = -1; _dx <= 1; ++_dx) {                        \
                    const int32_t _cx = _gx + _dx;                               \
                    if (_cx < 0 || _cx >= (h).nx) continue;                      \
                    const uint32_t _b = hash_index((h), _cx, _cy, _cz);          \
                    const int32_t _s = (h).bucket_start[_b];                     \
                    const int32_t _e = (h).bucket_end[_b];                       \
                    for (int32_t _k = _s; _k < _e; ++_k) {                       \
                        const int32_t jvar = static_cast<int32_t>((h).vals_sorted[_k]); \
                        __VA_ARGS__                                              \
                    }                                                            \
                }                                                                \
            }                                                                    \
        }                                                                        \
    } while (0)

} // namespace astro::sim
