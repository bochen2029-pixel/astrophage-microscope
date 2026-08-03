// src/sim/cell_store.cuh -- device-resident Astrophage population.
//
// Layout authority is contracts/cell_store_v1.h; this header owns allocation,
// spawning, and the free list. Simulation state never round-trips to the host
// (ARCHITECTURE.md Sec 3.1) -- only the Stats struct does.
#pragma once

#include <cstdint>

#include "contracts/cell_store_v1.h"
#include "core/result.h"

namespace astro::sim {

enum class Placement : uint8_t { Uniform = 0, Gaussian = 1, Grid = 2, Disc = 3 };
enum class Distribution : uint8_t { Constant = 0, Uniform = 1, Normal = 2 };

struct SpawnParams {
    int32_t      count        = 0;
    Placement    placement    = Placement::Uniform;
    double       place_x      = 0.0;      // Gaussian/Disc centre [m]
    double       place_y      = 0.0;
    double       place_radius = 0.0;      // Gaussian sigma or Disc radius [m]
    Distribution charge_dist  = Distribution::Constant;
    double       charge_a     = 0.0;      // constant: value; uniform/normal: (a, b)
    double       charge_b     = 0.0;
    bool         awake        = false;
};

struct Chamber {
    double w, h, d;                        // [m]
};

// Host-owned handle. One device allocation, sub-divided -- 20-odd separate
// cudaMallocs would fragment and would give no control over field adjacency.
struct CellStore {
    contract::CellStoreView view{};        // device pointers into `blob`
    void*    blob        = nullptr;
    size_t   blob_bytes  = 0;
    int32_t  capacity    = 0;
    int32_t  count       = 0;              // host mirror of view.count
    uint64_t next_id     = 1;              // 0 is reserved as "no cell"
    // Scan buffers, one entry per slot. `d_scan_flags` holds the 0/1 predicate
    // (divides-this-tick, or survives-compaction); an exclusive prefix sum
    // (cub::DeviceScan) writes the destination slots into `d_birth_prefix`. The
    // allocation MUST be order-free -- the snapshot hash is over the SoA in slot
    // order, so an atomicAdd assignment would vary it run to run (ADR-025/ADR-028).
    int32_t* d_scan_flags   = nullptr;
    int32_t* d_birth_prefix = nullptr;
    int32_t* d_birth_count  = nullptr;     // reused as the survivor total by compaction
    int32_t* d_dead_count   = nullptr;     // occupied-but-dead slots, the compaction trigger
    // Compaction scratch (ADR-028). `d_compact_src[k]` is the source slot of output
    // slot k; `d_compact_scratch` is a capacity*8-byte gather buffer reused across
    // every SoA array; `d_cub_temp` backs the exclusive-sum.
    int32_t* d_compact_src     = nullptr;
    void*    d_compact_scratch = nullptr;
    void*    d_cub_temp        = nullptr;
    size_t   cub_temp_bytes    = 0;
};

Error cell_store_create(CellStore& s, int32_t capacity);
void  cell_store_destroy(CellStore& s);

// Reclaim the slots of dead cells: pack OCCUPIED && ALIVE survivors into
// [0, live) preserving relative order, and set count = live. Stable and
// prefix-sum-allocated, so it is a pure function of the population and cannot
// perturb determinism (ADR-028). Opt-in via MotionConfig::compaction_enabled.
Error cell_store_compact(CellStore& s);

// Appends `p.count` cells. Each gets its own PCG32 stream seeded from
// (seed, cell_id), so a cell's trajectory depends on nothing but its id --
// not on how many cells exist or in what order they were created (INV-1).
Error cell_store_spawn(CellStore& s, const SpawnParams& p, const Chamber& c, uint64_t seed);

// Sets every cell's stored energy to `charge` * CELL_ENERGY_MAX. Drives the
// HUD charge slider, which is how P1 is demonstrated interactively: sweep it
// past CHARGE_NEUTRAL_BUOYANCY and the culture stops rising and starts sinking.
Error cell_store_set_charge(CellStore& s, double charge);

// One cell's state, downloaded for the inspector (M11f). SI units, host-side; the UI
// converts to display units and the P1 buoyancy line. `valid` is false for an empty or
// out-of-range slot, so a stale pick reads as "no cell" rather than as garbage.
struct CellSample {
    uint64_t id = 0;
    uint32_t flags = 0;
    uint8_t  death_cause = 0;
    double   x = 0, y = 0, z = 0;        // [m]
    double   vx = 0, vy = 0, vz = 0;     // [m/s]
    double   energy = 0;                 // [J]
    float    temp_cell = 0;              // [K]
    double   biomass = 0;                // [kg]
    float    age_s = 0;                  // [s]
    bool     valid = false;
};

// Debug/telemetry/UI only -- one cell's state for the inspector. A handful of small D2H
// copies; call at HUD rate for ONE picked slot, never per tick over the population.
Error cell_store_sample(const CellStore& s, int32_t slot, CellSample& out);

// Debug/telemetry/test only -- full device-to-host copies. Never call per tick.
Error cell_store_download_positions(const CellStore& s, double* x, double* y, double* z,
                                    int32_t max_count);
Error cell_store_download_velocities(const CellStore& s, double* vx, double* vy, double* vz,
                                     int32_t max_count);
Error cell_store_download_energy(const CellStore& s, double* energy, int32_t max_count);

} // namespace astro::sim
