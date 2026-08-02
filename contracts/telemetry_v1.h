// contracts/telemetry_v1.h -- CONTRACT v1. Frozen interface; see contracts/README.md.
//
// The per-tick statistics struct (the only routine device->host traffic) and the
// scenario acceptance-metric vocabulary shared by the UI and the headless runner.
//
// Semantics: docs/SCENARIOS.md.
#pragma once

#include <cstdint>

namespace astro::contract {

inline constexpr int TELEMETRY_CONTRACT_VERSION = 1;

// Copied D2H at ~30 Hz, NOT every tick. All reductions are deterministic
// (fixed-point integer accumulation, INV-2) -- never atomicAdd on float.
struct Stats {
    uint64_t tick;
    double   sim_time_s;

    int32_t n_live, n_dead, n_dormant, n_awake, n_taumoeba;

    double mean_charge;          // [0,1]
    double total_energy_j;       // the energy ledger; drives the HUD warning
    double mean_temp_cell_k;
    double mean_temp_medium_k;
    double max_temp_medium_k;    // P2 asserts this never reaches WATER_BOILING_POINT
    double co2_total_kg;
    double n2_total_kg;
    double mean_tau_tolerance;   // the Taumoeba-82.5 evolution readout

    int32_t divisions_this_window;
    int32_t deaths_this_window;
    int32_t boil_events;         // must stay 0 unless externally overheated
    int32_t ignitions_this_window;

    double physics_rate, biology_rate;
    uint8_t non_canon_run;       // set once any CANON parameter lock is broken
};

// Acceptance metrics. Adding one means adding it to BOTH the UI objective panel
// and the headless runner -- they share this enum so a scenario cannot rot.
enum class Metric : uint16_t {
    AwakeFraction = 0,
    MediumTempMean, MediumTempMax,
    BoilEventCount,
    PopulationLive, PopulationDead,
    MeanCharge, TotalEnergyJ,
    MeanTauTolerance, MaxTauTolerance,
    ChargeDepthCorrelation,   // P5: charged fraction vs depth along the light axis
    ChargeHeightCorrelation,  // P1: charge vs -y position
    RiseVelocityEmpty, FallVelocityFull,
    DoublingTimeS,
    ImpulsePerCycle,
    Count
};

enum class CompareOp : uint8_t { Eq, Ne, Lt, Le, Gt, Ge, Approx };

struct AcceptCheck {
    Metric    metric;
    CompareOp op;
    double    value;
    double    tol;        // used by Approx; relative unless tol_absolute
    double    after_s;    // only evaluated once sim_time_s >= after_s
    uint8_t   tol_absolute;
};

} // namespace astro::contract
