// src/sim/accept.cpp -- scenario acceptance evaluation. docs/SCENARIOS.md (M11b).
#include "sim/accept.h"

#include <cmath>
#include <cstdint>
#include <vector>

#include "contracts/cell_store_v1.h"   // CELL_FLAG_OCCUPIED / CELL_FLAG_ALIVE
#include "core/canon_generated.h"
#include "sim/cell_store.cuh"
#include "sim/predation.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Pearson correlation of two equal-length series; 0 when undefined (n<2, no spread).
double pearson(const std::vector<double>& a, const std::vector<double>& b) {
    const size_t n = a.size();
    if (n < 2 || b.size() != n) return 0.0;
    double ma = 0.0, mb = 0.0;
    for (size_t i = 0; i < n; ++i) { ma += a[i]; mb += b[i]; }
    ma /= static_cast<double>(n);
    mb /= static_cast<double>(n);
    double sab = 0.0, saa = 0.0, sbb = 0.0;
    for (size_t i = 0; i < n; ++i) {
        const double da = a[i] - ma, db = b[i] - mb;
        sab += da * db; saa += da * da; sbb += db * db;
    }
    if (saa <= 0.0 || sbb <= 0.0) return 0.0;
    return sab / std::sqrt(saa * sbb);
}

// charge vs -y position (P1): high charge sinks, so charge falls as y rises -> negative.
double measure_charge_height_corr(World& w) {
    const int32_t n = w.cells.count;
    if (n < 2) return 0.0;
    std::vector<double> x(n), y(n), z(n), e(n);
    cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
    cell_store_download_energy(w.cells, e.data(), n);
    std::vector<double> charge(n);
    for (int32_t i = 0; i < n; ++i) charge[i] = e[i] / canon::CELL_ENERGY_MAX;
    return pearson(charge, y);
}

// charge vs depth along the light axis (P5): shadowed cells stay uncharged -> negative.
double measure_charge_depth_corr(World& w, const Scenario& s) {
    const int32_t n = w.cells.count;
    if (n < 2) return 0.0;
    std::vector<double> x(n), y(n), z(n), e(n);
    cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
    cell_store_download_energy(w.cells, e.data(), n);
    const double dx = s.lights[0].dir_x, dy = s.lights[0].dir_y;
    std::vector<double> charge(n), depth(n);
    for (int32_t i = 0; i < n; ++i) {
        charge[i] = e[i] / canon::CELL_ENERGY_MAX;
        depth[i]  = x[i] * dx + y[i] * dy;   // distance travelled by the light
    }
    return pearson(charge, depth);
}

// Max N2 tolerance over ALIVE Taumoeba: the Taumoeba-82.5 readout (M10b, ADR-030).
double measure_max_tau_tolerance(World& w) {
    const int32_t n = w.taumoeba.count;
    if (n <= 0) return 0.0;
    std::vector<float>    tol(n);
    std::vector<uint32_t> fl(n);
    taumoeba_download_tolerance(w.taumoeba, tol.data(), n);
    taumoeba_download_flags(w.taumoeba, fl.data(), n);
    double mx = 0.0;
    for (int32_t i = 0; i < n; ++i) {
        const bool alive = (fl[i] & CELL_FLAG_OCCUPIED) && (fl[i] & CELL_FLAG_ALIVE);
        if (alive && static_cast<double>(tol[i]) > mx) mx = static_cast<double>(tol[i]);
    }
    return mx;
}

// Doubling time from the (t, N) series: slope of ln(N) vs t over the exponential phase
// (below 60% of the peak, so CO2 exhaustion's plateau does not flatten the fit). The
// series is in sim_time_s; culture (biological) time is sim_time * biology_rate
// (dt_bio = dt*biology_rate, lifecycle.cu), so scale to report the culture doubling the
// accept names (LIFE_DOUBLING_TIME, 6.912e5 s = 8 days).
double measure_doubling_time(const RunAggregates& agg, double biology_rate) {
    const size_t n = agg.n_series.size();
    if (n < 2) return 0.0;
    double npeak = 0.0;
    for (size_t i = 0; i < n; ++i) if (agg.n_series[i] > npeak) npeak = agg.n_series[i];
    if (npeak <= 0.0) return 0.0;
    const double cap = 0.6 * npeak;
    std::vector<double> t, ln;
    for (size_t i = 0; i < n; ++i) {
        const double N = agg.n_series[i];
        if (N > 0.0 && N <= cap) { t.push_back(agg.t_series[i]); ln.push_back(std::log(N)); }
    }
    if (t.size() < 2) return 0.0;
    double mt = 0.0, ml = 0.0;
    for (size_t i = 0; i < t.size(); ++i) { mt += t[i]; ml += ln[i]; }
    mt /= static_cast<double>(t.size());
    ml /= static_cast<double>(t.size());
    double stl = 0.0, stt = 0.0;
    for (size_t i = 0; i < t.size(); ++i) {
        const double d = t[i] - mt;
        stl += d * (ln[i] - ml); stt += d * d;
    }
    if (stt <= 0.0) return 0.0;
    const double slope = stl / stt;
    if (slope <= 0.0) return 0.0;
    return (std::log(2.0) / slope) * biology_rate;   // sim-time doubling -> culture time
}

}  // namespace

MetricNeeds metric_needs(const Scenario& s) {
    MetricNeeds n;
    for (int i = 0; i < s.accept_count; ++i) {
        switch (s.accept[i].metric) {
            case Metric::RiseVelocityEmpty:
            case Metric::FallVelocityFull:  n.velocity = true; break;
            case Metric::DoublingTimeS:     n.population = true; break;
            default: break;
        }
    }
    return n;
}

void aggregates_sample(RunAggregates& agg, const Stats& st, World& w,
                       const MetricNeeds& needs, double settle_s, double interval_s) {
    agg.boil_events_total += st.boil_events;
    if (st.max_temp_medium_k > agg.max_medium_k) agg.max_medium_k = st.max_temp_medium_k;

    if (needs.population) {
        agg.t_series.push_back(st.sim_time_s);
        agg.n_series.push_back(static_cast<double>(st.n_live));
    }

    if (needs.velocity) {
        const int32_t n = w.cells.count;
        if (agg.vel_stage == 0 && st.sim_time_s >= settle_s && n > 0) {
            // Snapshot A: y and charge of every free cell, before any wall-piling.
            std::vector<double> x(n), y(n), z(n), e(n);
            cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
            cell_store_download_energy(w.cells, e.data(), n);
            agg.vel_y_a.assign(y.begin(), y.end());
            agg.vel_charge_a.resize(n);
            for (int32_t i = 0; i < n; ++i) agg.vel_charge_a[i] = e[i] / canon::CELL_ENERGY_MAX;
            agg.vel_ta = st.sim_time_s;
            agg.vel_stage = 1;
        } else if (agg.vel_stage == 1 && st.sim_time_s >= agg.vel_ta + interval_s && n > 0) {
            // Snapshot B: fit v_settle = a + b*charge from the displacement drift; the
            // endpoints a and a+b are the empty (charge 0) and full (charge 1) velocities.
            std::vector<double> x(n), y(n), z(n);
            cell_store_download_positions(w.cells, x.data(), y.data(), z.data(), n);
            const double half_h = 0.5 * w.chamber.h;
            const double margin = 3.0 * canon::CELL_DIAMETER;   // drop wall-piled cells
            const double dt = st.sim_time_s - agg.vel_ta;
            const int32_t m = n < static_cast<int32_t>(agg.vel_y_a.size())
                              ? n : static_cast<int32_t>(agg.vel_y_a.size());
            std::vector<double> vset, chg;
            vset.reserve(m); chg.reserve(m);
            for (int32_t i = 0; i < m; ++i) {
                if (std::fabs(y[i]) > half_h - margin) continue;   // piled at a y-wall
                vset.push_back(-(y[i] - agg.vel_y_a[i]) / dt);     // downward positive
                chg.push_back(agg.vel_charge_a[i]);
            }
            const size_t k = vset.size();
            if (k >= 2 && dt > 0.0) {
                double mc = 0.0, mv = 0.0;
                for (size_t i = 0; i < k; ++i) { mc += chg[i]; mv += vset[i]; }
                mc /= static_cast<double>(k); mv /= static_cast<double>(k);
                double scv = 0.0, scc = 0.0;
                for (size_t i = 0; i < k; ++i) {
                    const double dc = chg[i] - mc;
                    scv += dc * (vset[i] - mv); scc += dc * dc;
                }
                const double b = scc > 0.0 ? scv / scc : 0.0;
                const double a = mv - b * mc;
                agg.rise_velocity_empty = a;        // charge 0
                agg.fall_velocity_full  = a + b;    // charge 1
            }
            agg.vel_stage = 2;
        }
    }
}

double metric_measure(Metric m, const Stats& fin, RunAggregates& agg, World& w,
                      const Scenario& s) {
    switch (m) {
        case Metric::AwakeFraction:
            return fin.n_live > 0 ? static_cast<double>(fin.n_awake) / static_cast<double>(fin.n_live) : 0.0;
        case Metric::MediumTempMean:   return fin.mean_temp_medium_k;
        case Metric::MediumTempMax:    return agg.max_medium_k;
        case Metric::BoilEventCount:   return static_cast<double>(agg.boil_events_total);
        case Metric::PopulationLive:   return static_cast<double>(fin.n_live);
        case Metric::PopulationDead:   return static_cast<double>(fin.n_dead);
        case Metric::MeanCharge:       return fin.mean_charge;
        case Metric::TotalEnergyJ:     return fin.total_energy_j;
        case Metric::MeanTauTolerance: return fin.mean_tau_tolerance;
        case Metric::MaxTauTolerance:  return measure_max_tau_tolerance(w);
        case Metric::ChargeHeightCorrelation: return measure_charge_height_corr(w);
        case Metric::ChargeDepthCorrelation:  return measure_charge_depth_corr(w, s);
        case Metric::RiseVelocityEmpty: return agg.rise_velocity_empty;
        case Metric::FallVelocityFull:  return agg.fall_velocity_full;
        case Metric::DoublingTimeS:     return measure_doubling_time(agg, w.biology_rate);
        case Metric::ImpulsePerCycle: {
            double imp = 0.0, dis = 0.0;
            world_flash_audit(w, imp, dis);
            return dis > 0.0 ? imp * canon::C_LIGHT / dis : 0.0;
        }
        default: return 0.0;
    }
}

bool accept_eval(const AcceptCheck& c, double measured) {
    switch (c.op) {
        case CompareOp::Eq: return measured == c.value;
        case CompareOp::Ne: return measured != c.value;
        case CompareOp::Lt: return measured <  c.value;
        case CompareOp::Le: return measured <= c.value;
        case CompareOp::Gt: return measured >  c.value;
        case CompareOp::Ge: return measured >= c.value;
        case CompareOp::Approx: {
            const double diff = std::fabs(measured - c.value);
            const double tol  = c.tol_absolute ? c.tol : c.tol * std::fabs(c.value);
            return diff <= tol;
        }
    }
    return false;
}

const char* metric_name(Metric m) {
    switch (m) {
        case Metric::AwakeFraction:            return "awake_fraction";
        case Metric::MediumTempMean:           return "medium_temp_mean";
        case Metric::MediumTempMax:            return "medium_temp_max";
        case Metric::BoilEventCount:           return "boil_event_count";
        case Metric::PopulationLive:           return "population_live";
        case Metric::PopulationDead:           return "population_dead";
        case Metric::MeanCharge:               return "mean_charge";
        case Metric::TotalEnergyJ:             return "total_energy_j";
        case Metric::MeanTauTolerance:         return "mean_tau_tolerance";
        case Metric::MaxTauTolerance:          return "max_tau_tolerance";
        case Metric::ChargeDepthCorrelation:   return "charge_depth_correlation";
        case Metric::ChargeHeightCorrelation:  return "charge_height_correlation";
        case Metric::RiseVelocityEmpty:        return "rise_velocity_empty";
        case Metric::FallVelocityFull:         return "fall_velocity_full";
        case Metric::DoublingTimeS:            return "doubling_time_s";
        case Metric::ImpulsePerCycle:          return "impulse_per_cycle";
        default:                               return "?";
    }
}

} // namespace astro::sim
