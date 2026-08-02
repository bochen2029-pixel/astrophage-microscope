// contracts/cell_store_v1.h -- CONTRACT v1. Frozen interface; see contracts/README.md.
//
// The authority on the CellStore SoA layout. Consumers (render, ui, tools) read
// THIS FILE, never src/sim/. Changing anything here means bumping to _v2.h,
// updating every consumer, and an ADR -- all in one commit.
//
// Semantics: docs/PHYSICS.md Sec 2.
#pragma once

#include <cstdint>

namespace astro::contract {

inline constexpr int CELL_STORE_CONTRACT_VERSION = 1;

// ---------------------------------------------------------------------------
// Cell flags. Biological state (alive/dead) and thermal state (awake/dormant)
// are ORTHOGONAL -- a dormant cell is alive, and a corpse may have been awake.
// ---------------------------------------------------------------------------
enum CellFlags : uint32_t {
    CELL_FLAG_NONE      = 0u,
    CELL_FLAG_OCCUPIED  = 1u << 0,  // slot is in use (0 = free-list entry)
    CELL_FLAG_ALIVE     = 1u << 1,  // clear + OCCUPIED = corpse, still rendered
    CELL_FLAG_AWAKE     = 1u << 2,  // thermostat engaged; irreversible (ADR-003)
    CELL_FLAG_STUCK     = 1u << 3,  // adhered to a z wall (PHYSICS.md Sec 9)
    CELL_FLAG_DIVIDING  = 1u << 4,  // mid-mitosis
    CELL_FLAG_FLASHING  = 1u << 5,  // forced full discharge (spin-drive face)
};

// Reason a cell died. Recorded for telemetry; does not affect physics.
enum class DeathCause : uint8_t {
    None = 0, Starved = 1, Predated = 2, Overheated = 3, Culled = 4,
};

// ---------------------------------------------------------------------------
// Device-side SoA view. Pointers are DEVICE pointers. This struct is passed by
// value to kernels; keep it POD and small.
//
// Precision policy (PHYSICS.md Sec 1): position/velocity/energy/biomass are f64
// because they span six decades; per-cell scratch and emission are f32.
// ---------------------------------------------------------------------------
struct CellStoreView {
    // identity
    uint64_t* id;            // stable, monotonic; seeds the per-cell RNG stream
    uint32_t* flags;         // CellFlags
    uint8_t*  death_cause;   // DeathCause

    // kinematics [m], [m/s]
    double* x;  double* y;  double* z;
    double* vx; double* vy; double* vz;

    // energetics
    double* energy;          // [J]  in [0, CELL_ENERGY_MAX]
    float*  temp_cell;       // [K]

    // emission
    float* emit_power;       // [W]
    float* dir_x; float* dir_y; float* dir_z;   // unit emission axis

    // biology
    double* biomass;         // [kg]
    double* co2_held;        // [kg] accumulated toward the next division
    float*  age_s;           // [s]

    // control
    uint64_t* rng_state;     // PCG32 state, one stream per cell (INV-1, ADR-014)
    float*    taxis_memory;  // lagged signal for temporal-comparison taxis
    float*    run_timer;     // [s] time in the current run-and-tumble run

    // scratch, refilled every tick by the field_sample stage
    float* t_local;          // [K]      grid sample + analytic near field (ADR-010)
    float* irradiance;       // [W/m^2]
    float* co2_local;        // [kg/m^3]
    float* n2_local;         // [kg/m^3]

    int32_t  count;          // live upper bound; slots [0, count) may be occupied
    int32_t  capacity;
};

// Host-side ownership handle. Opaque to consumers; only sim/ constructs one.
struct CellStore;

} // namespace astro::contract
