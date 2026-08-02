// src/fields/fields_placeholder.cu -- M0 scaffold.
//
// Keeps astro_fields a valid target until M5 populates it. It also carries the
// substep arithmetic that ADR-008 rests on, as a compile-time check: if anyone
// raises a grid resolution without re-deriving the cost, this fails to compile
// rather than silently quadrupling the per-tick field work.
//
// DELETE THIS FILE when grid.cuh and diffuse.cu land in M5.
#include "contracts/fields_v1.h"
#include "core/canon_generated.h"
#include "core/units.h"

#if defined(GLFW_VERSION_MAJOR) || defined(IMGUI_VERSION) || defined(__gl_h_)
    #error "INV-5 violated: fields/ must not include presentation headers."
#endif

namespace astro::fields {

using namespace astro::canon;

// Explicit FTCS stability: dt < dx^2 / (4 * alpha).
constexpr double explicit_dt_max(double chamber_w, int n, double diffusivity) {
    const double dx = chamber_w / static_cast<double>(n);
    return dx * dx / (4.0 * diffusivity);
}

constexpr int substeps_for(double chamber_w, int n, double diffusivity, double dt) {
    return static_cast<int>(dt / explicit_dt_max(chamber_w, n, diffusivity)) + 1;
}

inline constexpr int TEMP_SUBSTEPS =
    substeps_for(CHAMBER_W, FIELD_N_TEMP, WATER_THERMAL_DIFFUSIVITY, DT_PHYSICS);
inline constexpr int CO2_SUBSTEPS =
    substeps_for(CHAMBER_W, FIELD_N_CO2, CO2_DIFFUSIVITY_WATER, DT_PHYSICS);

// ADR-008: explicit was chosen over implicit ADI because the substep count at
// 512^2 is small. If a grid resolution doubles, substeps quadruple and the
// tradeoff flips -- so make that a build break, not a performance surprise.
static_assert(TEMP_SUBSTEPS <= 16,
              "Temperature substeps exceed the ADR-008 budget. Re-derive before "
              "raising FIELD_N_TEMP: at 1024^2 this becomes ~38 and memory traffic "
              "dominates. Either keep the resolution or add the cuSPARSE ADI path.");
static_assert(CO2_SUBSTEPS <= 4, "CO2 substeps exceed budget; see ADR-008.");

__global__ void noop_diffuse(float* f, int n) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n * n) f[i] = f[i];
}

} // namespace astro::fields
