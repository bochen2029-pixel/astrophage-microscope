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
    int32_t* d_free_list = nullptr;        // unused until M9 (lifecycle)
    int32_t* d_free_count = nullptr;
};

Error cell_store_create(CellStore& s, int32_t capacity);
void  cell_store_destroy(CellStore& s);

// Appends `p.count` cells. Each gets its own PCG32 stream seeded from
// (seed, cell_id), so a cell's trajectory depends on nothing but its id --
// not on how many cells exist or in what order they were created (INV-1).
Error cell_store_spawn(CellStore& s, const SpawnParams& p, const Chamber& c, uint64_t seed);

// Sets every cell's stored energy to `charge` * CELL_ENERGY_MAX. Drives the
// HUD charge slider, which is how P1 is demonstrated interactively: sweep it
// past CHARGE_NEUTRAL_BUOYANCY and the culture stops rising and starts sinking.
Error cell_store_set_charge(CellStore& s, double charge);

// Debug/telemetry/test only -- full device-to-host copies. Never call per tick.
Error cell_store_download_positions(const CellStore& s, double* x, double* y, double* z,
                                    int32_t max_count);
Error cell_store_download_velocities(const CellStore& s, double* vx, double* vy, double* vz,
                                     int32_t max_count);
Error cell_store_download_energy(const CellStore& s, double* energy, int32_t max_count);

} // namespace astro::sim
