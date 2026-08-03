// src/sim/lifecycle.cuh -- growth, mitosis, and division. docs/PHYSICS.md Sec 10,
// ADR-014, ADR-025.
//
// Pure __host__ __device__ functions so tests exercise the real code path without a
// GPU (ARCHITECTURE.md Sec 3.3). The kernels in lifecycle.cu are thin loops over
// these.
#pragma once

#include <cmath>
#include <cstdint>

#include "contracts/cell_store_v1.h"
#include "contracts/scenario_v2.h"
#include "core/canon_generated.h"
#include "core/rng.cuh"
#include "core/units.h"

namespace astro::sim {

// Michaelis-Menten uptake. Saturates at LIFE_CO2_UPTAKE_MAX where CO2 is plentiful,
// and falls smoothly to zero as the medium is stripped -- which is what makes
// "growth halts within one doubling of CO2 exhaustion" emerge rather than be
// scripted. A hard cutoff would halt growth as a cliff instead of a slowdown.
ASTRO_HD inline double co2_uptake_rate(double co2_local) {
    if (co2_local <= 0.0) return 0.0;
    return canon::LIFE_CO2_UPTAKE_MAX * co2_local /
           (co2_local + canon::LIFE_CO2_HALF_SATURATION);
}

// A cell that has banked a division's worth of CO2 enters mitosis. `quota` defaults to
// canon so existing callers are unchanged and bit-identical; lifecycle.cu passes the World
// override (ADR-035), which equals canon unless the inspector tuned it.
ASTRO_HD inline bool ready_to_divide(double co2_held,
                                     double quota = canon::CO2_MASS_PER_DIVISION) {
    return co2_held >= quota;
}

// NOTE: M9a splits the instant the quota is banked. The TIMED mitosis event
// (LIFE_MITOSIS_DURATION, and the CELL_FLAG_DIVIDING visual that goes with it)
// needs somewhere to keep a per-cell elapsed time, and cell_store_v1.h has no
// spare field -- so it lands with M9b's corpse and render work, which is where
// the visual belongs anyway. Getting clever with an existing field to fake a
// timer inside the determinism-critical path is not worth 0.13 % of a cycle.

// Energy is SPLIT, not duplicated. Getting this wrong manufactures 1.5 MJ per
// division out of nothing, and the energy ledger is the one number in this
// simulator that must never be quietly wrong (PHYSICS.md Sec 10).
ASTRO_HD inline double daughter_energy(double parent_energy) {
    const double half = 0.5 * (parent_energy - canon::LIFE_DIVISION_ENERGY_COST);
    return half > 0.0 ? half : 0.0;
}

// Death by heat. Starvation already lands via the M6 thermal path; this is the
// other end, and it is what makes the torch-the-slide escape hatch real.
ASTRO_HD inline bool lethal_temperature(double t_local) {
    return t_local > canon::CELL_LETHAL_TEMP;
}

// Where a dead cell's store goes -- canon is silent, so all three readings ship and
// `void` is the default (ADR-004). Returns the energy the CORPSE retains.
//
// `flash` is the physically conserving one and it is not a detail: one full cell is
// 358.5 g of TNT equivalent, so a mass death event is a containment failure rather
// than something a slide shrugs off. M9b discharges it as emission over one tick;
// the scripted end state belongs with the scenario system at M11.
ASTRO_HD inline double corpse_energy(contract::StoreDisposition d, double energy) {
    switch (d) {
        case contract::StoreDisposition::Retain: return energy;   // inert ballast
        case contract::StoreDisposition::Flash:  return 0.0;      // radiated away
        case contract::StoreDisposition::Void:
        default:                                 return 0.0;      // vanishes
    }
}

// The daughter's stream must depend on nothing but (parent state, daughter id) --
// never on birth order, slot index, or how many cells divided this tick. That is
// the whole of INV-1 and it is what T22 tests (ADR-014).
ASTRO_HD inline uint64_t daughter_rng_state(uint64_t parent_state, uint64_t daughter_id) {
    return pcg_split(parent_state, daughter_id);
}

// Daughters are placed one radius either side of the parent along a direction
// derived from the daughter's own id, so placement is reproducible without
// consuming a draw from either cell's stream. Consuming one would make the
// parent's subsequent trajectory depend on whether it happened to divide, which
// is precisely the coupling ADR-014 exists to prevent.
ASTRO_HD inline void division_axis(uint64_t daughter_id, double& ax, double& ay, double& az) {
    // Double-mixed rather than salted with a magic constant: splitmix64 already
    // carries the golden-ratio increment internally, and a bare 64-bit literal here
    // would trip A9's physical-literal grep for no benefit.
    const uint64_t h = splitmix64(splitmix64(daughter_id));
    // Two uniforms from disjoint halves of one hash: a z in [-1,1] and an azimuth.
    const double u = static_cast<double>(h >> 33) * (1.0 / 2147483648.0) - 1.0;
    const double phi = static_cast<double>(h & 0xFFFFFFFFull) * (TWO_PI / 4294967296.0);
    const double s = sqrt(u * u < 1.0 ? 1.0 - u * u : 0.0);
    ax = s * cos(phi);
    ay = s * sin(phi);
    az = u;
}

} // namespace astro::sim
