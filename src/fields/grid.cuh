// src/fields/grid.cuh -- a scalar field on a regular grid. docs/PHYSICS.md Sec 7.
//
// TWO CORRECTIONS TO THE MILESTONE TEXT, both recorded in ADR-019:
//
//  1. The solver is explicit FTCS with PING-PONG buffers, not "red-black".
//     Red-black is a Gauss-Seidel ordering -- an implicit smoother that reads
//     partially-updated neighbours on purpose. An explicit step must read the
//     OLD value everywhere, so it needs a second buffer, not an ordering.
//
//  2. The grid is DEPTH-AVERAGED and therefore two-dimensional. A 2D point
//     source relaxes logarithmically, not as 1/r. The 1/r law belongs to
//     ADR-010's per-cell analytic near field (M6) and is not a property this
//     grid can or should reproduce.
#pragma once

#include <cstdint>

#include "contracts/fields_v1.h"
#include "core/canon_generated.h"
#include "core/fixed_atomic.cuh"
#include "core/result.h"
#include "core/units.h"

#if defined(GLFW_VERSION_MAJOR) || defined(IMGUI_VERSION) || defined(__gl_h_)
    #error "INV-5 violated: fields/ must not include presentation headers."
#endif

namespace astro::fields {

using astro::contract::BoundaryCondition;
using astro::contract::FieldView;

// ---------------------------------------------------------------------------
// Explicit stability, and the ADR-008 budget it justifies
// ---------------------------------------------------------------------------
constexpr double explicit_dt_max(double extent, int n, double diffusivity) {
    const double dx = extent / static_cast<double>(n);
    return dx * dx / (4.0 * diffusivity);
}

constexpr int substeps_for(double extent, int n, double diffusivity, double dt) {
    return static_cast<int>(dt / explicit_dt_max(extent, n, diffusivity)) + 1;
}

inline constexpr int TEMP_SUBSTEPS = substeps_for(
    canon::CHAMBER_W, canon::FIELD_N_TEMP, canon::WATER_THERMAL_DIFFUSIVITY, canon::DT_PHYSICS);
inline constexpr int CO2_SUBSTEPS = substeps_for(
    canon::CHAMBER_W, canon::FIELD_N_CO2, canon::CO2_DIFFUSIVITY_WATER, canon::DT_PHYSICS);

// ADR-008: explicit beat implicit ADI because the substep count is small. Raise
// a resolution and substeps scale as N^2 -- so make that a build break rather
// than a performance surprise discovered three milestones later.
static_assert(TEMP_SUBSTEPS <= 16,
              "Temperature substeps exceed the ADR-008 budget. Re-derive before raising "
              "FIELD_N_TEMP: at 1024^2 this becomes ~38 and memory traffic dominates. "
              "Either keep the resolution or add the cuSPARSE ADI path.");
static_assert(CO2_SUBSTEPS <= 4, "CO2 substeps exceed budget; see ADR-008.");

// ---------------------------------------------------------------------------
// Host handle
// ---------------------------------------------------------------------------
struct Grid2D {
    float*              value = nullptr;
    float*              scratch = nullptr;   // ping-pong target; never read externally
    unsigned long long* deposit = nullptr;
    int32_t             n = 0;
    double              extent = 0.0;        // world span [m]
    double              dx = 0.0;
    double              diffusivity = 0.0;
    double              ambient = 0.0;
    double              deposit_scale = 1.0;
    double              robin_coeff = 0.0;   // dx * h / k, dimensionless
    int32_t             substeps = 1;
    BoundaryCondition   bc = BoundaryCondition::Neumann;
};

Error grid_create(Grid2D& g, int32_t n, double extent, double diffusivity,
                  double ambient, double deposit_scale, BoundaryCondition bc,
                  double dt);
void  grid_destroy(Grid2D& g);
Error grid_fill(Grid2D& g, float value);
Error grid_diffuse(Grid2D& g, double dt);
Error grid_flush_deposits(Grid2D& g);        // fold the fixed-point accumulator in
Error grid_download(const Grid2D& g, float* out);
FieldView grid_view(const Grid2D& g);

// Tool brushes. Applied from the host at a defined tick boundary, so they write
// `value` directly rather than going through the deposit accumulator -- there is
// no concurrency to serialise and the ordering is already fixed.
Error grid_brush(Grid2D& g, double x, double y, double radius, double amount);

// ---------------------------------------------------------------------------
// Device access. World coordinates are centred on the origin; the grid indexes
// from its min corner.
// ---------------------------------------------------------------------------
ASTRO_HD inline float grid_sample(const FieldView& f, float x, float y) {
    const float half = 0.5f * f.n * f.dx;
    const float gx = (x + half) / f.dx - 0.5f;
    const float gy = (y + half) / f.dx - 0.5f;
    int32_t x0 = static_cast<int32_t>(floorf(gx));
    int32_t y0 = static_cast<int32_t>(floorf(gy));
    const float tx = gx - static_cast<float>(x0);
    const float ty = gy - static_cast<float>(y0);
    const int32_t x1 = x0 + 1, y1 = y0 + 1;
    auto at = [&](int32_t i, int32_t j) -> float {
        i = i < 0 ? 0 : (i >= f.n ? f.n - 1 : i);
        j = j < 0 ? 0 : (j >= f.n ? f.n - 1 : j);
        return f.value[j * f.n + i];
    };
    return (1.0f - tx) * (1.0f - ty) * at(x0, y0) + tx * (1.0f - ty) * at(x1, y0) +
           (1.0f - tx) * ty * at(x0, y1) + tx * ty * at(x1, y1);
}

#if defined(__CUDACC__)
// Bilinear scatter into the FIXED-POINT accumulator (INV-2, ADR-013). Float
// atomicAdd here would make the field depend on warp scheduling.
__device__ inline void grid_deposit(const FieldView& f, float x, float y, double amount) {
    const float half = 0.5f * f.n * f.dx;
    const float gx = (x + half) / f.dx - 0.5f;
    const float gy = (y + half) / f.dx - 0.5f;
    const int32_t x0 = static_cast<int32_t>(floorf(gx));
    const int32_t y0 = static_cast<int32_t>(floorf(gy));
    const float tx = gx - static_cast<float>(x0);
    const float ty = gy - static_cast<float>(y0);
    const float w[4] = {(1.0f - tx) * (1.0f - ty), tx * (1.0f - ty),
                        (1.0f - tx) * ty,           tx * ty};
    const int32_t ix[4] = {x0, x0 + 1, x0, x0 + 1};
    const int32_t iy[4] = {y0, y0, y0 + 1, y0 + 1};
    for (int k = 0; k < 4; ++k) {
        if (ix[k] < 0 || ix[k] >= f.n || iy[k] < 0 || iy[k] >= f.n) continue;
        astro::atomic_deposit(&f.deposit[iy[k] * f.n + ix[k]],
                              amount * static_cast<double>(w[k]), f.deposit_scale);
    }
}
#endif

} // namespace astro::fields
