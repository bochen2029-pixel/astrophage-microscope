// src/sim/thermal.cuh -- the thermostat. docs/PHYSICS.md Sec 5.
//
// Produces P2 (the medium pins to 96.415 C and can never boil), P3 (irreversible
// ignition), and P4 (live cells are visibly more mobile than dead ones). None of
// the three is special-cased anywhere -- if you find yourself writing
// `if (temp > boiling)`, stop and re-read PHYSICS.md Sec 5.3.
#pragma once

#include <cmath>

#include "core/canon_generated.h"
#include "core/units.h"

namespace astro::sim {

// Free-space conduction from a sphere into a quiescent medium, Nu = 2.
ASTRO_HD inline double conduction_power(double t_cell, double t_far) {
    return canon::CONDUCTION_COEFF * (t_cell - t_far);
}

// Conductance from the cell surface out to radius R.
//
// CORRECT MATHEMATICS, AND DELIBERATELY NOT USED. Kept because the reasoning is
// worth preserving: substituting the analytic profile T(R) = T_inf + dT*a/R into
// this returns exactly 4*pi*k*a*dT, so it looks like the right way to conduct
// against a grid cell that sits at the near-field temperature rather than at
// infinity.
//
// It is wrong here because that premise fails. A grid cell's thermal time
// constant is dx^2/(4*alpha) = 1.06e-4 s, which equals the diffusion substep --
// so diffusion drains the cell as fast as a source fills it and it never holds
// the near-field temperature. Conducting against it at 2.78x the free-space rate
// then pumps without feedback: measured 1.76e6 K instead of 369.6 K.
//
// The grid represents the FAR field. Conduct against it with the free-space
// coefficient, and leave the sub-grid 1/r structure unresolved. See ADR-020.
ASTRO_HD inline double shell_conductance(double r_outer) {
    const double a = canon::CELL_RADIUS;
    if (r_outer <= a) return 0.0;
    return 4.0 * PI * canon::WATER_CONDUCTIVITY / (1.0 / a - 1.0 / r_outer);
}

// The analytic steady-state profile around a cell, T(r) = T_inf + dT*a/r.
ASTRO_HD inline double near_field_temperature(double t_cell, double t_far, double r) {
    const double a = canon::CELL_RADIUS;
    if (r <= a) return t_cell;
    return t_far + (t_cell - t_far) * a / r;
}

// ADR-003. The latch is ONE-WAY: crossing the setpoint wakes a cell for good.
ASTRO_HD inline bool should_ignite(bool awake, double t_local) {
    return !awake && t_local >= canon::CELL_TEMP_SETPOINT;
}

// A dormant cell tracks ambient; an awake one clamps to the setpoint forever.
ASTRO_HD inline double cell_temperature(bool awake, double t_local) {
    return awake ? canon::CELL_TEMP_SETPOINT : t_local;
}

// The temperature that sets a cell's drag, and therefore its Brownian mobility.
//
// For an awake cell this is its SURFACE temperature, not the far field and not
// the film mean. Stokes drag is set by the fluid in the boundary layer at the
// sphere surface, and an awake cell holds that surface at the setpoint however
// cold the bulk is. The three candidates give motility ratios of 2.87 (far
// field), 2.38 (film), and 4.36 (surface); only the last reproduces the
// independently-derived T12_MOTILITY_RATIO. See ADR-020.
ASTRO_HD inline double viscosity_temperature(bool awake, double t_local) {
    return awake ? canon::CELL_TEMP_SETPOINT : t_local;
}

// Exact lumped exchange over dt between a cell and one grid cell of heat
// capacity C. Returns the ENERGY the cell gives up (negative = absorbs).
//
// Exponential rather than explicit, and that is not a refinement: an explicit
// step deposits 188 K into a single grid cell in one tick and sails past
// boiling. The exponential form is the exact solution of the two-body lumped
// ODE, so the medium approaches the cell temperature and CANNOT overshoot it --
// which is the second law, not a clamp.
ASTRO_HD inline double lumped_exchange_energy(double t_cell, double t_grid,
                                              double conductance, double capacity,
                                              double dt) {
    if (capacity <= 0.0 || conductance <= 0.0) return 0.0;
    const double relax = -expm1(-conductance * dt / capacity);   // 1 - exp(-Gdt/C)
    return capacity * (t_cell - t_grid) * relax;
}

} // namespace astro::sim
