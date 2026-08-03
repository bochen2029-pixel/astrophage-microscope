// src/sim/accept.h -- scenario acceptance evaluation. docs/SCENARIOS.md (M11b).
//
// The accept block of a scenario (contracts/telemetry_v1.h: Metric/AcceptCheck) has two
// consumers -- the UI objective panel and the headless runner -- so it lives here in sim
// where both can reach it, exactly as the scenario loader does (ADR-031).
//
// Most metrics are read straight from a HUD-rate `Stats`. The DERIVED ones (velocities,
// correlations, doubling time, the flash impulse audit) cannot be: they are functions of
// the full per-cell state over TIME, so a `RunAggregates` accumulates them as the run
// proceeds and a couple are captured from a full-state download at measurement. See the
// per-metric notes in accept.cpp. Host-only; no GL.
#pragma once

#include <vector>

#include "contracts/scenario_v2.h"
#include "contracts/telemetry_v1.h"
#include "core/result.h"
#include "sim/world.cuh"

namespace astro::sim {

// Which expensive full-state samples a scenario needs, derived from its accept metrics,
// so a run only pays for the downloads its objectives actually read.
struct MetricNeeds {
    bool velocity   = false;   // rise_velocity_empty / fall_velocity_full
    bool population = false;   // doubling_time_s
};

// Accumulated across a run, sampled at HUD rate by the runner.
struct RunAggregates {
    // boil_event_count: summed over samples; the run "boiled" if this is nonzero.
    int64_t boil_events_total = 0;
    double  max_medium_k = 0.0;                 // medium_temp_max (running peak)

    // doubling_time_s: (sim_time, n_live) series, regressed as ln(N) vs t.
    std::vector<double> t_series, n_series;

    // rise/fall velocity: displacement-based drift, captured from two free-cell
    // position snapshots (thermal noise on instantaneous velocity is 8x the drift;
    // drift over seconds swamps Brownian diffusion, so displacement is the clean read).
    int     vel_stage = 0;                      // 0 none, 1 have snapshot A, 2 captured
    double  vel_ta = 0.0;
    std::vector<double> vel_y_a, vel_charge_a;
    double  rise_velocity_empty = 0.0;          // v_settle at charge 0 (downward +)
    double  fall_velocity_full  = 0.0;          // v_settle at charge 1

    // impulse_per_cycle (spin-drive flash, ADR-033) reads w.d_flash_accum directly at
    // measure time via world_flash_audit -- no per-sample aggregation needed.
};

// Derive the sampling needs from a scenario's accept block.
MetricNeeds metric_needs(const contract::Scenario& s);

// One HUD-rate update. `settle_s` and `interval_s` gate the two velocity snapshots.
void aggregates_sample(RunAggregates& agg, const contract::Stats& st, World& w,
                       const MetricNeeds& needs, double settle_s, double interval_s);

// Measure one metric at run end from final stats + aggregates + (for correlations and
// max tolerance) a fresh full-state download.
double metric_measure(contract::Metric m, const contract::Stats& fin,
                      RunAggregates& agg, World& w, const contract::Scenario& s);

// Evaluate one check against a measured value. Approx uses relative tol unless
// tol_absolute; every other op is exact.
bool accept_eval(const contract::AcceptCheck& c, double measured);

// A metric's docs/SCENARIOS.md JSON name, for the runner's per-check report.
const char* metric_name(contract::Metric m);

} // namespace astro::sim
