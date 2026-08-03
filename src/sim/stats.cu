// src/sim/stats.cu -- tick stage 11. The telemetry reduction.
//
// Unshipped since M6 and asserted by T23. Everything accumulates in 64-bit FIXED
// POINT (INV-2): float atomicAdd is order-dependent, so the same population would
// report a different mean depending on how the blocks happened to retire, and the
// HUD would flicker in the last digits for no physical reason. Integer addition is
// associative, so this is bit-identical across block sizes.
#include <cuda_runtime.h>

#include "core/fixed_atomic.cuh"
#include "fields/grid.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Field sums use 1e9 rather than DEPOSIT_SCALE_STATS (1e6): a CO2 concentration is
// ~1e-5 kg/m^3, which at 1e6 would round to ten units and carry 10 % error per grid
// cell. 1e9 keeps nanogram-per-m^3 resolution and still cannot overflow -- a fully
// saturated 512^2 grid reaches 512*512*1.5*1e9 = 3.9e14, against an int64 ceiling of
// 9.2e18.
constexpr double SCALE_FIELD = 1.0e9;

__global__ void stats_cells_kernel(CellStoreView v, StatsAccum* a) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= v.count) return;
    const uint32_t f = v.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED)) return;

    const bool alive = (f & CELL_FLAG_ALIVE) != 0u;
    const bool awake = (f & CELL_FLAG_AWAKE) != 0u;
    if (alive) atomicAdd(&a->n_alive, 1u); else atomicAdd(&a->n_dead, 1u);
    if (awake) atomicAdd(&a->n_awake, 1u); else atomicAdd(&a->n_dormant, 1u);

    // The energy ledger counts corpses too when the store is retained -- a corpse
    // holding 1.5 MJ is still 358 g of TNT sitting on the slide (ADR-004).
    astro::atomic_deposit(&a->energy, v.energy[i], DEPOSIT_SCALE_STATS);
    if (alive) astro::atomic_deposit(&a->temp_cell, static_cast<double>(v.temp_cell[i]),
                                     DEPOSIT_SCALE_STATS);
}

__global__ void stats_field_kernel(FieldView temp, FieldView co2, FieldView n2,
                                   int32_t n_temp, int32_t n_co2, int32_t n_n2,
                                   StatsAccum* a) {
    const int32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n_temp) {
        const double t = static_cast<double>(temp.value[i]);
        astro::atomic_deposit(&a->temp_medium, t, DEPOSIT_SCALE_STATS);
        // atomicMax on the fixed-point representation. Max is associative and
        // commutative over integers, so this is order-independent too. Temperatures
        // are positive, so the unsigned ordering matches the signed one.
        atomicMax(&a->max_temp, static_cast<unsigned long long>(
                                    astro::to_fixed(t, DEPOSIT_SCALE_STATS)));
    }
    if (i < n_co2) astro::atomic_deposit(&a->co2, static_cast<double>(co2.value[i]), SCALE_FIELD);
    if (i < n_n2)  astro::atomic_deposit(&a->n2,  static_cast<double>(n2.value[i]),  SCALE_FIELD);
}

// M10b. Alive-Taumoeba count and the fixed-point tolerance sum -- the mean-tolerance
// readout that the evolution arc climbs. Tolerance is in [0,1]; at DEPOSIT_SCALE_STATS
// (1e6) a full MAX_TAUMOEBA population sums to 6.6e10, eight orders inside int64.
__global__ void stats_taumoeba_kernel(TaumoebaStore t, StatsAccum* a) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= t.count) return;
    const uint32_t f = t.flags[i];
    if (!(f & CELL_FLAG_OCCUPIED) || !(f & CELL_FLAG_ALIVE)) return;
    atomicAdd(&a->n_taumoeba, 1u);
    astro::atomic_deposit(&a->tau_tolerance, static_cast<double>(t.tolerance[i]),
                          DEPOSIT_SCALE_STATS);
}

__global__ void stats_clear_kernel(StatsAccum* a) { *a = StatsAccum{}; }

} // namespace

void stats_step(World& w) {
    if (!w.d_stats) return;
    const int block = 256;
    stats_clear_kernel<<<1, 1>>>(w.d_stats);

    const int32_t n = w.cells.count;
    if (n > 0) stats_cells_kernel<<<(n + block - 1) / block, block>>>(w.cells.view, w.d_stats);

    const int32_t ntau = w.taumoeba.count;
    if (ntau > 0)
        stats_taumoeba_kernel<<<(ntau + block - 1) / block, block>>>(w.taumoeba, w.d_stats);

    const int32_t nt = w.fields.temperature.n * w.fields.temperature.n;
    const int32_t nc = w.fields.co2.n * w.fields.co2.n;
    const int32_t nn = w.fields.n2.n * w.fields.n2.n;
    const int32_t most = nt > nc ? (nt > nn ? nt : nn) : (nc > nn ? nc : nn);
    stats_field_kernel<<<(most + block - 1) / block, block>>>(
        fields::grid_view(w.fields.temperature), fields::grid_view(w.fields.co2),
        fields::grid_view(w.fields.n2), nt, nc, nn, w.d_stats);

    cudaMemcpy(&w.stats_host, w.d_stats, sizeof(StatsAccum), cudaMemcpyDeviceToHost);
}

contract::Stats world_stats(World& w) {
    stats_step(w);
    const StatsAccum& a = w.stats_host;

    contract::Stats s{};
    s.tick = w.tick;
    s.sim_time_s = world_sim_time(w);
    s.physics_rate = w.physics_rate;
    s.biology_rate = w.biology_rate;

    s.n_live = static_cast<int32_t>(a.n_alive);
    s.n_dead = static_cast<int32_t>(a.n_dead);
    s.n_awake = static_cast<int32_t>(a.n_awake);
    s.n_dormant = static_cast<int32_t>(a.n_dormant);

    // The Taumoeba-82.5 readout: alive predator count and their mean N2 tolerance.
    s.n_taumoeba = static_cast<int32_t>(a.n_taumoeba);
    s.mean_tau_tolerance = a.n_taumoeba > 0u
        ? astro::from_fixed(a.tau_tolerance, DEPOSIT_SCALE_STATS) / a.n_taumoeba : 0.0;

    s.total_energy_j = astro::from_fixed(a.energy, DEPOSIT_SCALE_STATS);
    s.mean_charge = (a.n_alive + a.n_dead) > 0u
        ? s.total_energy_j / ((a.n_alive + a.n_dead) * canon::CELL_ENERGY_MAX) : 0.0;
    s.mean_temp_cell_k = a.n_alive > 0u
        ? astro::from_fixed(a.temp_cell, DEPOSIT_SCALE_STATS) / a.n_alive : 0.0;

    const double grid_cells = static_cast<double>(w.fields.temperature.n) *
                              w.fields.temperature.n;
    s.mean_temp_medium_k = grid_cells > 0.0
        ? astro::from_fixed(a.temp_medium, DEPOSIT_SCALE_STATS) / grid_cells : 0.0;
    s.max_temp_medium_k = astro::from_fixed(a.max_temp, DEPOSIT_SCALE_STATS);

    // Concentration sums become masses through the grid cell volume: dx^2 through
    // the full chamber depth, the same lumped volume uptake and conduction use.
    const double vc = static_cast<double>(w.fields.co2.dx) * w.fields.co2.dx * w.chamber.d;
    const double vn = static_cast<double>(w.fields.n2.dx) * w.fields.n2.dx * w.chamber.d;
    s.co2_total_kg = astro::from_fixed(a.co2, SCALE_FIELD) * vc;
    s.n2_total_kg  = astro::from_fixed(a.n2,  SCALE_FIELD) * vn;

    // Window counters: divisions are tallied by lifecycle on the host; deaths are
    // differenced against a CUMULATIVE total (not the live dead count, which
    // compaction reclaims -- differencing that would go negative, ADR-028).
    s.divisions_this_window = w.divisions_this_window;
    s.deaths_this_window = static_cast<int32_t>(w.deaths_total - w.deaths_reported);
    w.divisions_this_window = 0;
    w.deaths_reported = w.deaths_total;
    // P2 asserts this never happens unaided; it is reported, never suppressed.
    s.boil_events = s.max_temp_medium_k >= canon::WATER_BOILING_POINT ? 1 : 0;
    return s;
}

} // namespace astro::sim
