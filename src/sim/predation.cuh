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

// --- M10b evolution: N2 lethality and heritable tolerance (PHYSICS.md Sec 11) ------

// Poisson death hazard [kg/m^3] for a Taumoeba in nitrogen. Its tolerance raises the
// concentration it can withstand: the effective lethal threshold is
// TAU_N2_LETHAL_CONC*(1 + tolerance*k). Below that the hazard is zero (the tolerant
// survive), above it the hazard grows with the excess. This IS a field read -- a
// concentration at the predator's location -- so, unlike engulfment, the grid is the
// right instrument (ADR-030, cf. meta-lesson 1).
ASTRO_HD inline double tau_n2_hazard(double n2_local, double tolerance) {
    const double threshold =
        canon::TAU_N2_LETHAL_CONC * (1.0 + tolerance * canon::TAU_N2_TOLERANCE_K);
    const double h = n2_local - threshold;
    return h > 0.0 ? h : 0.0;
}

// Per-tick death probability from that hazard over a biology-time step. 1 - exp(-x)
// via expm1 so it stays accurate as the hazard approaches zero. Rate is DERIVED from a
// survival time (TAU_N2_HAZARD_RATE), never guessed (meta-lesson 2, ADR-030).
ASTRO_HD inline double tau_n2_death_prob(double hazard, double dt_bio) {
    return -expm1(-hazard * canon::TAU_N2_HAZARD_RATE * dt_bio);
}

// A Taumoeba divides once its DRY biomass reaches 2x its initial value
// (TAU_DIVIDE_BIOMASS), the direct analogue of the cell's CO2-quota mitosis
// (ready_to_divide, ADR-025). The water-blob mass TAU_MASS is for drag only (ADR-030).
ASTRO_HD inline bool tau_ready_to_divide(double biomass) {
    return biomass >= canon::TAU_DIVIDE_BIOMASS;
}

// The daughter's inherited N2 tolerance: parent + a gaussian mutation of scale
// TAU_MUTATION_SIGMA, clamped to [0,1]. The `mutation` variate is drawn from the
// DAUGHTER's own stream (ADR-025), so the parent's trajectory never depends on whether
// it divided. Heritable drift under N2 selection is the whole engine of the arc.
ASTRO_HD inline float tau_daughter_tolerance(float parent_tol, double mutation) {
    return static_cast<float>(clamp(
        static_cast<double>(parent_tol) + canon::TAU_MUTATION_SIGMA * mutation, 0.0, 1.0));
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
    double*   biomass = nullptr;       // DRY biomass; grows by eating, divides at 2x (ADR-030)
    double*   prey_biomass = nullptr;  // banked while digesting, yielded on completion
    float*    digest_timer = nullptr;  // [s] remaining; 0 = hunting
    float*    tolerance = nullptr;      // N2 tolerance in [0,1] -- heritable (M10b)
    uint32_t* generation = nullptr;     // lineage depth; daughter = parent + 1 (M10b)
    uint64_t* rng_state = nullptr;
    float*    density_ema = nullptr;    // lagged local prey count (run-and-tumble)
    float*    run_timer = nullptr;
    int32_t*  target = nullptr;         // prey slot claimed this tick, -1 = none

    void*    blob = nullptr;
    size_t   blob_bytes = 0;
    int32_t  count = 0;
    int32_t  capacity = 0;
    uint64_t next_id = 1;

    // Scan + compaction scratch (M10b), mirroring CellStore (ADR-025/ADR-028). Death
    // and division now churn the store, so daughter slots come from an exclusive
    // prefix sum (never atomicAdd) and dead slots are reclaimed by a stable,
    // out-of-place compaction. Sized once at capacity so the tick loop never allocates.
    int32_t* d_scan_flags   = nullptr;  // 0/1 predicate: divides-this-tick, or survives
    int32_t* d_birth_prefix = nullptr;  // exclusive prefix sum of the predicate
    int32_t* d_birth_count  = nullptr;  // division count; reused as survivor total
    int32_t* d_dead_count   = nullptr;  // occupied-but-dead slots (compaction trigger)
    int32_t* d_compact_src  = nullptr;  // source slot of each output slot
    void*    d_compact_scratch = nullptr;  // capacity*8-byte gather buffer, reused per array
    void*    d_cub_temp     = nullptr;  // backs cub::DeviceScan::ExclusiveSum
    size_t   cub_temp_bytes = 0;
};

Error taumoeba_create(TaumoebaStore& s, int32_t capacity);
void  taumoeba_destroy(TaumoebaStore& s);

// Reclaim the slots of dead Taumoeba: pack OCCUPIED && ALIVE survivors into [0, live)
// preserving relative order, and set count = live. Stable and prefix-sum-allocated, so
// it is a pure function of the flags and cannot perturb determinism (ADR-028). Opt-in
// via MotionConfig::tau_compaction_enabled; default off keeps M10a bit-identical.
Error taumoeba_store_compact(TaumoebaStore& s);

// Append `count` predators, uniformly placed, each with a PCG32 stream seeded from
// (seed, taumoeba id) -- disjoint from the cells' seeds so the two populations do
// not correlate.
Error taumoeba_spawn(TaumoebaStore& s, int32_t count, const Chamber& c, uint64_t seed);

// Debug/telemetry/test only -- full D2H copies. Never call per tick.
Error taumoeba_download_positions(const TaumoebaStore& s, double* x, double* y, double* z,
                                  int32_t max_count);
Error taumoeba_download_biomass(const TaumoebaStore& s, double* biomass, int32_t max_count);
Error taumoeba_download_tolerance(const TaumoebaStore& s, float* tolerance, int32_t max_count);
Error taumoeba_download_generation(const TaumoebaStore& s, uint32_t* generation, int32_t max_count);
Error taumoeba_download_flags(const TaumoebaStore& s, uint32_t* flags, int32_t max_count);

} // namespace astro::sim
