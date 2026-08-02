// src/sim/emission.cu -- tick stages 9 (irradiance) and the feeding half of 3.
#include <cuda_runtime.h>

#include "fields/grid.cuh"
#include "sim/emission.cuh"
#include "sim/hash.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Cells stamp their blocking cross-section into the irradiance grid's deposit
// accumulator. Nearest-cell: a cell either occupies a column or it does not.
__global__ void occlusion_stamp_kernel(CellStoreView v, FieldView irr, double per_cell_area) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED)) return;
    // A corpse is translucent, not opaque (PHYSICS.md Sec 7.5).
    const double area = (f & CELL_FLAG_ALIVE) ? per_cell_area
                                              : per_cell_area * (1.0 - canon::CELL_ALBEDO_DEAD);
    astro::fields::grid_deposit_nearest(irr, static_cast<float>(v.x[i]),
                                        static_cast<float>(v.y[i]), area);
}

// Axis-aligned transmittance sweep. One thread per line, so each thread owns its
// whole output line and no two threads touch the same cell -- deterministic by
// construction, no atomics.
//
// Axis-aligned only, deliberately (ADR-021). A sheared sweep for arbitrary
// directions collides threads on shared cells and would need either atomics or a
// rotated buffer; four directions demonstrate P5 completely and the physics is
// identical.
__global__ void sweep_kernel(const unsigned long long* blocked, float* out, int32_t n,
                             double deposit_scale, double face_area,
                             float source, float ambient, int axis, int sign) {
    const int32_t line = blockIdx.x * blockDim.x + threadIdx.x;
    if (line >= n) return;

    double t = 1.0;
    for (int32_t s = 0; s < n; ++s) {
        const int32_t step = (sign > 0) ? s : (n - 1 - s);
        const int32_t idx = (axis == 0) ? (line * n + step) : (step * n + line);
        // The cell sees the light that reached its near face, before its own
        // extinction is applied -- otherwise a cell would shadow itself.
        out[idx] = static_cast<float>(source * t) + ambient;
        const double area = astro::from_fixed(blocked[idx], deposit_scale);
        t *= column_transmittance(area, face_area);
    }
}

__global__ void clear_kernel(unsigned long long* v, int32_t count) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < count) v[i] = 0ull;
}

// Feeding, plus the exact near-field shadow that makes P5 literal.
__global__ void feed_kernel(CellStoreView v, HashView hash, FieldView irr,
                            Vec3 light_dir, float ambient, double dt,
                            unsigned char occlusion_exact) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;

    const Vec3 pos{v.x[i], v.y[i], v.z[i]};
    double directional = static_cast<double>(
        astro::fields::grid_sample(irr, static_cast<float>(pos.x),
                                        static_cast<float>(pos.y))) - ambient;
    if (directional < 0.0) directional = 0.0;

    // The grid gives the FAR field, which can only be fractional -- one cell
    // blocks 16.8 % of a grid column's face. The exact statement of P5 is a 3D
    // fact about two discs, so it is resolved per cell against hash neighbours.
    // A directly-aligned neighbour returns exactly 1, leaving exactly 0 (ADR-021).
    if (occlusion_exact && hash.vals_sorted != nullptr) {
        double open = 1.0;
        ASTRO_FOR_EACH_NEIGHBOUR(hash, pos.x, pos.y, pos.z, j, {
            if (j != i && (v.flags[j] & CELL_FLAG_OCCUPIED) && (v.flags[j] & CELL_FLAG_ALIVE)) {
                open *= (1.0 - shadow_fraction(pos, Vec3{v.x[j], v.y[j], v.z[j]}, light_dir));
            }
        });
        directional *= open;
    }

    v.irradiance[i] = static_cast<float>(directional);

    const double gained = absorbed_power(directional, static_cast<double>(ambient)) * dt;
    double e = v.energy[i] + gained;
    if (e > canon::CELL_ENERGY_MAX) e = canon::CELL_ENERGY_MAX;
    v.energy[i] = e;
}

} // namespace

void emission_step(World& w, double dt) {
    auto& irr = w.fields.irradiance;
    const int32_t cells = irr.n * irr.n;
    const int block = 256;

    const LightSource& L = w.light;
    const float source = L.enabled ? L.irradiance : 0.0f;

    // Dark chamber: nothing to sweep, nothing to absorb, and no reason to pay
    // for a 27-bucket occlusion walk per cell. The irradiance field is already
    // zero and stays that way, which is also what canon says -- Astrophage does
    // not move in darkness (PHYSICS.md Sec 8).
    if (source <= 0.0f && w.ambient_irradiance <= 0.0f) return;

    const Vec3 dir = normalize(Vec3{L.dir_x, L.dir_y, 0.0});

    clear_kernel<<<(cells + block - 1) / block, block>>>(irr.deposit, cells);
    if (w.cells.count > 0 && source > 0.0f) {
        const int g = (w.cells.count + block - 1) / block;
        occlusion_stamp_kernel<<<g, block>>>(w.cells.view, astro::fields::grid_view(irr),
                                             canon::CELL_CROSS_SECTION);
    }

    // Which axis the sweep runs along, and in which direction.
    const int axis = (fabs(dir.x) >= fabs(dir.y)) ? 0 : 1;
    const int sign = (axis == 0) ? (dir.x >= 0.0 ? 1 : -1) : (dir.y >= 0.0 ? 1 : -1);
    const double face_area = irr.dx * w.chamber.d;

    sweep_kernel<<<(irr.n + block - 1) / block, block>>>(
        irr.deposit, irr.value, irr.n, irr.deposit_scale, face_area,
        source, w.ambient_irradiance, axis, sign);

    if (w.cells.count > 0) {
        const int g = (w.cells.count + block - 1) / block;
        feed_kernel<<<g, block>>>(w.cells.view, hash_view(w.hash),
                                  astro::fields::grid_view(irr), dir,
                                  w.ambient_irradiance, dt,
                                  w.motion.occlusion_exact ? 1 : 0);
    }
}

} // namespace astro::sim
