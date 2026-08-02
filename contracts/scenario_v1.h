// contracts/scenario_v1.h -- CONTRACT v1. Frozen interface; see contracts/README.md.
//
// Parsed form of scenarios/*.json. Semantics and the JSON shape: docs/SCENARIOS.md.
#pragma once

#include <cstdint>

#include "fields_v1.h"
#include "render_view_v1.h"
#include "snapshot_v1.h"    // ParamOverride
#include "telemetry_v1.h"

namespace astro::contract {

inline constexpr int SCENARIO_CONTRACT_VERSION = 1;

enum class Placement : uint8_t { Uniform = 0, Gaussian = 1, Grid = 2, Disc = 3 };
enum class Distribution : uint8_t { Constant = 0, Uniform = 1, Normal = 2 };
enum class OrganismKind : uint8_t { Astrophage = 0, Taumoeba = 1 };

// ADR-002: the unresolvable canon density contradiction ships as a playable option.
enum class DensityModel : uint8_t { CanonMass = 0, WaterDensity = 1 };

// ADR-004: where a dead cell's store goes; canon is silent.
enum class StoreDisposition : uint8_t { Void = 0, Flash = 1, Retain = 2 };

enum class ClockPreset : uint8_t { Realtime = 0, Motion = 1, Metabolic = 2, Generational = 3, Custom = 4 };

enum class ToolBit : uint32_t {
    Heat = 1u << 0, Chill = 1u << 1, Illuminate = 1u << 2,
    InjectCO2 = 1u << 3, InjectN2 = 1u << 4,
    SeedCells = 1u << 5, SeedTaumoeba = 1u << 6,
    Kill = 1u << 7, ChargeBeam = 1u << 8,
};

struct PopulationSpec {
    OrganismKind kind;
    int32_t      count;
    Placement    placement;
    double       place_x, place_y, place_radius;   // for Gaussian/Disc
    Distribution charge_dist;
    double       charge_a, charge_b;               // constant: a; uniform/normal: (a,b)
    uint8_t      awake;
};

inline constexpr int MAX_POPULATIONS   = 8;
inline constexpr int MAX_ACCEPT_CHECKS = 16;
inline constexpr int MAX_OVERRIDES     = 32;

struct Scenario {
    int32_t schema;
    char    id[64];
    char    title[128];
    char    blurb[256];
    uint64_t seed;

    double chamber_w, chamber_h, chamber_d;
    uint8_t boundary_x, boundary_y;      // 0 reflecting, 1 periodic, 2 absorbing

    double            temp_init, co2_init, n2_init, ambient_temp;
    BoundaryCondition thermal_bc;
    DensityModel      density_model;
    StoreDisposition  store_disposition;
    uint8_t           gravity_axis;      // 0 = y (default, ADR-006), 1 = z

    LightSource lights[MAX_LIGHT_SOURCES];
    float       ambient_irradiance;

    PopulationSpec populations[MAX_POPULATIONS];
    int32_t        population_count;

    ClockPreset clock;
    double      physics_rate, biology_rate;   // used when clock == Custom

    ScopeState scope;
    uint32_t   tools;                          // ToolBit mask

    ParamOverride param_overrides[MAX_OVERRIDES];   // from snapshot_v1.h
    int32_t       override_count;

    char        objective_text[256];
    AcceptCheck accept[MAX_ACCEPT_CHECKS];
    int32_t     accept_count;
};

} // namespace astro::contract
