// contracts/scenario_v3.h -- CONTRACT v3. Frozen interface; see contracts/README.md.
//
// SUPERSEDES scenario_v2.h. Scenario itself is unchanged; v3 exists only to carry the
// render_view_v3 CellInstance (ADR-043) -- scenario_v2.h includes render_view_v2.h, and no
// translation unit may include two contract versions, so the include bump cascades to here.
//
// Parsed form of scenarios/*.json. Semantics and the JSON shape: docs/SCENARIOS.md.
//
// v2 adds the DRIVING SCRIPT (`drive`): a list of scripted stimuli the headless
// acceptance runner (and, later, the app) applies at tick boundaries so a scenario
// can play out its objective unattended -- first-light's heat, taumoeba's nitrogen
// ramp, the spin-drive flash. v1 had `tools` (which tools are AVAILABLE) but no way
// to say WHEN a stimulus fires. Everything else is byte-for-byte v1. See ADR-032.
#pragma once

#include <cstdint>

#include "fields_v1.h"
#include "render_view_v3.h"
#include "snapshot_v1.h"    // ParamOverride
#include "telemetry_v1.h"

namespace astro::contract {

inline constexpr int SCENARIO_CONTRACT_VERSION = 3;

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

// A scripted stimulus (ADR-032). Active while t0_s <= sim_time_s < t1_s; the driver
// (sim/scenario.cpp) applies it every tick in that window. `value` is a RATE lerped
// v0 -> v1 across the window and multiplied by the tick's dt, so the total effect is
// invariant to physics_rate:
//   Heat/Chill        -- world_apply_brush on temperature, [K/s]
//   InjectCO2/InjectN2-- world_apply_brush on that field,  [kg/m^3/s]
//   SetLight          -- set the primary light source's irradiance to `value` [W/m^2]
//                        (an absolute level, NOT rate*dt); dir/wavelength stay as the
//                        scenario's light[0]
//   SetN2             -- fill the whole N2 field to `value` [kg/m^3] (absolute, NOT a
//                        rate). This is the taumoeba nitrogen ramp: an absolute uniform
//                        level, exactly as test_evolution's set_n2 (ADR-030), not an
//                        additive brush, so the frontier tol* = N/N_lethal-1 is exact
//   SeedCells         -- maintain the astrophage population at `value` cells, spawning the
//                        deficit each tick with the first astrophage population's charge.
//                        The predator's food supply for the breeding arc (test_evolution's
//                        top_up_prey); needs `compaction` on so count == live
//   Flash             -- arm the spin-drive flash (PHYSICS.md Sec 6) for the window;
//                        `value` unused, canon PETROVA_FLASH_* set the discharge
// radius <= 0 means a chamber-global brush.
enum class StimulusKind : uint8_t {
    Heat = 0, Chill = 1, InjectCO2 = 2, InjectN2 = 3,
    SetLight = 4, SetN2 = 5, SeedCells = 6, Flash = 7,
};

struct Stimulus {
    double       t0_s, t1_s;         // active window in simulated seconds
    double       x, y, radius;       // brush centre + radius [m]; radius<=0 = global
    double       v0, v1;             // strength, lerped v0 -> v1 across the window
    StimulusKind kind;
    uint8_t      _pad[7];            // explicit: keep the struct's layout obvious
};

inline constexpr int MAX_POPULATIONS   = 8;
inline constexpr int MAX_ACCEPT_CHECKS = 16;
inline constexpr int MAX_OVERRIDES     = 32;
inline constexpr int MAX_STIMULI       = 16;

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
    // 1 (default) runs the temperature field; 0 skips thermal_step entirely, for a
    // scenario with no thermal dynamics whose medium stays uniform (komorov: a dormant
    // cell absorbing a beam as store, not heat) -- so the gate is not paying for 512^2
    // diffusion of a flat field over a long run. v2 (M11b).
    uint8_t           thermal_active;
    // Reclaim dead cell / Taumoeba slots by stable compaction (ADR-028). Default 0 (off),
    // matching a plain run; on, a population can turn over at a bounded capacity, which is
    // what the taumoeba breeding arc needs (test_evolution). v2 (M11b).
    uint8_t           compaction;
    uint8_t           tau_compaction;

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

    // The driving script (v2, ADR-032). Applied by sim/scenario.cpp's driver.
    Stimulus drive[MAX_STIMULI];
    int32_t  drive_count;

    char        objective_text[256];
    AcceptCheck accept[MAX_ACCEPT_CHECKS];
    int32_t     accept_count;

    // The headless --assert run horizon [s] (v2). 0 = derive it from the latest accept
    // after_s or drive window. Scenarios whose objective is time-open (bloom's growth,
    // taumoeba's breeding arc) set it explicitly. docs/SCENARIOS.md.
    double      run_duration_s;
};

} // namespace astro::contract
