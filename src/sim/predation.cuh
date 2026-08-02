// src/sim/predation.cuh -- Taumoeba, the predator. docs/PHYSICS.md Sec 11 (M10a).
//
// Its own SoA store, its own PCG32 streams keyed on a Taumoeba id (INV-1/ADR-014
// for a second organism), and the same OU integrator the cells use. Pure
// __host__ __device__ helpers so tests exercise the real code without a GPU.
#pragma once

#include <cstdint>

#include "core/canon_generated.h"
#include "core/result.h"
#include "core/rng.cuh"
#include "core/units.h"
#include "core/vec.cuh"
#include "sim/cell_store.cuh"      // Chamber
#include "sim/integrator.cuh"      // water_viscosity, integrate_cell, apply_boundary_axis

namespace astro::sim {

// Stokes drag on the predator at temperature t -- the cell's form with the
// Taumoeba radius. The crawl is DRIVEN (a persistent walk at TAU_CRAWL_SPEED), so
// mass only sets the Brownian jitter; TAU_MASS is a water-density blob, hence the
// predator is neutrally buoyant and has no sedimentation term.
ASTRO_HD inline double tau_drag(double t_kelvin) {
    return 6.0 * PI * water_viscosity(t_kelvin) * canon::TAU_RADIUS;
}

// A Taumoeba engulfs a cell when their bodies overlap.
ASTRO_HD inline bool tau_overlaps_cell(Vec3 tau, Vec3 cell) {
    const double r = canon::TAU_RADIUS + canon::CELL_RADIUS;
    return length_sq(tau - cell) < r * r;
}

// Run-and-tumble on the prey-density signal, the temporal comparison of ADR-007:
// keep heading while the local live-cell count is rising, otherwise tumble. Returns
// true to tumble. `ema` is updated in place (a first-order lag, exact discretisation).
ASTRO_HD inline bool tau_should_tumble(float signal, float& ema, float run_timer, double dt) {
    const double alpha = -expm1(-dt / canon::TAXIS_MEMORY_TIME);   // step response weight
    const double delta = static_cast<double>(signal) - static_cast<double>(ema);
    ema = static_cast<float>(ema + alpha * delta);
    return !(delta > 0.0 && run_timer < canon::TAXIS_RUN_MAX);
}

// ---------------------------------------------------------------------------
// Device SoA view + host handle. One carved blob, like the cell store.
// ---------------------------------------------------------------------------
struct TaumoebaStore {
    uint64_t* id = nullptr;
    uint32_t* flags = nullptr;        // OCCUPIED | ALIVE (CellFlags bits reused)
    double*   x = nullptr;  double* y = nullptr;  double* z = nullptr;
    double*   vx = nullptr; double* vy = nullptr; double* vz = nullptr;
    float*    dir_x = nullptr; float* dir_y = nullptr; float* dir_z = nullptr;   // crawl heading
    double*   biomass = nullptr;
    double*   prey_biomass = nullptr;  // banked while digesting, yielded on completion
    float*    digest_timer = nullptr;  // [s] remaining; 0 = hunting
    float*    tolerance = nullptr;      // N2 tolerance -- M10b; carried, unused at M10a
    uint64_t* rng_state = nullptr;
    float*    density_ema = nullptr;    // lagged local prey count (run-and-tumble)
    float*    run_timer = nullptr;
    int32_t*  target = nullptr;         // prey slot claimed this tick, -1 = none

    void*    blob = nullptr;
    size_t   blob_bytes = 0;
    int32_t  count = 0;
    int32_t  capacity = 0;
    uint64_t next_id = 1;
};

Error taumoeba_create(TaumoebaStore& s, int32_t capacity);
void  taumoeba_destroy(TaumoebaStore& s);

// Append `count` predators, uniformly placed, each with a PCG32 stream seeded from
// (seed, taumoeba id) -- disjoint from the cells' seeds so the two populations do
// not correlate.
Error taumoeba_spawn(TaumoebaStore& s, int32_t count, const Chamber& c, uint64_t seed);

// Debug/telemetry/test only -- full D2H copies. Never call per tick.
Error taumoeba_download_positions(const TaumoebaStore& s, double* x, double* y, double* z,
                                  int32_t max_count);
Error taumoeba_download_biomass(const TaumoebaStore& s, double* biomass, int32_t max_count);

} // namespace astro::sim
