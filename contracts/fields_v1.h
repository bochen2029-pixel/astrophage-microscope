// contracts/fields_v1.h -- CONTRACT v1. Frozen interface; see contracts/README.md.
//
// Field grids, boundary conditions, and the fixed-point deposit scales that make
// GPU determinism possible (INV-2, ADR-013).
//
// Semantics: docs/PHYSICS.md Sec 7.
#pragma once

#include <cstdint>

namespace astro::contract {

inline constexpr int FIELDS_CONTRACT_VERSION = 1;

enum class FieldId : uint8_t {
    Temperature = 0,   // [K]
    CO2         = 1,   // [kg/m^3]
    N2          = 2,   // [kg/m^3]
    Irradiance  = 3,   // [W/m^2], rebuilt each tick -- never deposited into
    Count       = 4,
};

enum class BoundaryCondition : uint8_t {
    Dirichlet = 0,   // held at ambient (a temperature-controlled stage)
    Neumann   = 1,   // insulated, zero flux
    Robin     = 2,   // convective loss to room air, AIR_CONVECTION_H
};

// ---------------------------------------------------------------------------
// Fixed-point deposit scales (ADR-013).
//
// Deposits accumulate into int64 as llround(value * SCALE), then convert back.
// Integer addition is associative, so the result is independent of warp
// scheduling; float atomicAdd is NOT and would break INV-8 on every run.
//
// SAFE RANGE: an int64 holds +/-9.22e18. An overflowing accumulator is a SILENT
// CORRECTNESS BUG, not a crash, so every scale must satisfy
//     DEPOSIT_MAX_CONTRIBUTORS * |value_max| * SCALE < 9.2e18.
//
// The bound is per GRID CELL, not global -- an accumulator only ever sees the
// cells that land in its own grid cell. At the temperature grid one cell fills
// ~14% of a grid cell's volume, so close packing allows about 7 contributors.
// DEPOSIT_MAX_CONTRIBUTORS is set ~500x above that as the audited margin; tests
// assert against it rather than against MAX_CELLS, which would be absurdly
// pessimistic (2e6 cells cannot occupy one 7.8 um grid cell).
// ---------------------------------------------------------------------------
inline constexpr int DEPOSIT_MAX_CONTRIBUTORS = 4096;

// value_max is the largest single-tick contribution from one source.
// Temperature: an isolated awake cell dumps ~190 K into its own grid cell in one
// tick before diffusion redistributes it, so 1e3 K is the audited ceiling.
inline constexpr double DEPOSIT_SCALE_TEMPERATURE = 1.0e9;   // K,      value_max 1e3
inline constexpr double DEPOSIT_SCALE_CO2         = 1.0e15;  // kg/m^3, value_max 1e-2
inline constexpr double DEPOSIT_SCALE_N2          = 1.0e15;  // kg/m^3, value_max 1e-2
inline constexpr double DEPOSIT_SCALE_STATS       = 1.0e6;   // generic reductions

// The irradiance grid reuses its deposit accumulator as an OCCLUSION buffer:
// cells stamp their blocking cross-section (7.854e-11 m^2) into it, and the
// sweep converts that to transmittance. The scale must resolve a single cell, so
// it is far larger than the others. One cell contributes 7.85e7 units; at
// DEPOSIT_MAX_CONTRIBUTORS that is 3.2e11, eleven orders inside int64.
inline constexpr double DEPOSIT_SCALE_IRRADIANCE  = 1.0e18;  // m^2, value_max 1e-9
static_assert(DEPOSIT_MAX_CONTRIBUTORS * 1.0e-9 * DEPOSIT_SCALE_IRRADIANCE < 9.2e18,
              "Irradiance occlusion accumulator can overflow int64; see ADR-013.");

// Irradiance is rebuilt from scratch every tick and never diffused, so its
// diffusivity is a placeholder that only has to satisfy grid_create's stability
// check. It is deliberately not a physical quantity.
inline constexpr double IRRADIANCE_NOMINAL_DIFFUSIVITY = 1.0e-9;

// Compile-time guard: adding a field or changing a scale without redoing this
// arithmetic is a build break, not a runtime surprise.
static_assert(DEPOSIT_MAX_CONTRIBUTORS * 1.0e3  * DEPOSIT_SCALE_TEMPERATURE < 9.2e18,
              "Temperature deposit accumulator can overflow int64; see ADR-013.");
static_assert(DEPOSIT_MAX_CONTRIBUTORS * 1.0e-2 * DEPOSIT_SCALE_CO2 < 9.2e18,
              "CO2 deposit accumulator can overflow int64; see ADR-013.");
static_assert(DEPOSIT_MAX_CONTRIBUTORS * 1.0e-2 * DEPOSIT_SCALE_N2 < 9.2e18,
              "N2 deposit accumulator can overflow int64; see ADR-013.");

// Device-side view of one scalar field.
struct FieldView {
    float*         value;        // n * n, row-major, [x + n*y]
    unsigned long long* deposit; // n * n fixed-point accumulator, zeroed each tick
    int32_t        n;            // grid resolution (n x n)
    float          dx;           // [m] cell size = chamber_w / n
    float          diffusivity;  // [m^2/s]
    int32_t        substeps;     // explicit substeps per tick; see VERIFICATION.md Sec 6
    BoundaryCondition bc;
    float          ambient;      // BC reference value
    double         deposit_scale;
};

// All fields, passed by value to kernels.
struct FieldsView {
    FieldView temperature;
    FieldView co2;
    FieldView n2;
    FieldView irradiance;

    // Chamber extent [m]; fields span x,y and are depth-averaged over z.
    float chamber_w, chamber_h, chamber_d;
};

// A directional light source. Occlusion behind a cell is TOTAL (albedo = 0,
// PHYSICS.md Sec 7.5) -- this is what produces P5.
struct LightSource {
    float dir_x, dir_y;    // unit, in-plane propagation direction
    float irradiance;      // [W/m^2] at the illuminated boundary
    float wavelength;      // [m] -- selects CO2-line vs Petrova-band behaviour
    uint8_t enabled;
};

inline constexpr int MAX_LIGHT_SOURCES = 8;

} // namespace astro::contract
