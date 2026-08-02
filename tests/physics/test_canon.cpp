// tests/physics/test_canon.cpp -- the generated canon must be internally consistent.
//
// This is the guard on the anti-drift machinery (ARCHITECTURE.md Sec 5.1). It
// recomputes the DERIVED quantities here, in C++, from the CANON base values,
// and asserts they match what scripts/derive.py emitted in Python. If the two
// ever disagree, one of them has a bug -- and silently trusting either would
// poison every physics test downstream.
#include <cmath>

#include "core/canon_generated.h"
#include "golden/expected_values.h"
#include "test_util.h"

using namespace astro::canon;

int main() {
    // --- geometry and mass ---------------------------------------------------
    const double a = CELL_DIAMETER / 2.0;
    const double V = 4.0 / 3.0 * 3.14159265358979323846 * a * a * a;
    CHECK_CLOSE(CELL_VOLUME, V, 1e-12);
    CHECK_CLOSE(CELL_RADIUS, a, 1e-15);
    CHECK_CLOSE(CELL_DENSITY_DRY, CELL_MASS_DRY / V, 1e-12);
    CHECK_CLOSE(CELL_MASS_STORE_MAX, CELL_ENERGY_MAX / (C_LIGHT * C_LIGHT), 1e-12);
    CHECK_CLOSE(CELL_MASS_FULL, CELL_MASS_DRY + CELL_MASS_STORE_MAX, 1e-12);

    // ADR-002: canon mass in a 10 um sphere is 25x LIGHTER than water. If this
    // ever stops holding, P1 is gone and the density model has silently changed.
    CHECK(CELL_DENSITY_DRY < WATER_DENSITY / 10.0);
    CHECK(CELL_DENSITY_FULL > WATER_DENSITY * 30.0);

    // Canon says "~17 ng" gained at full enrichment; E/c^2 gives 16.69 ng.
    CHECK_CLOSE(CELL_MASS_STORE_MAX * 1e12, 16.69, 1e-3);

    // --- the 3% line (P1) ----------------------------------------------------
    const double e_neutral = (WATER_DENSITY * V - CELL_MASS_DRY) * C_LIGHT * C_LIGHT;
    CHECK_CLOSE(ENERGY_NEUTRAL_BUOYANCY, e_neutral, 1e-12);
    CHECK_CLOSE(CHARGE_NEUTRAL_BUOYANCY, e_neutral / CELL_ENERGY_MAX, 1e-12);
    CHECK_CLOSE(CHARGE_NEUTRAL_BUOYANCY, 0.030058, 1e-4);

    // --- Petrova -------------------------------------------------------------
    CHECK_CLOSE(PETROVA_FREQUENCY, C_LIGHT / PETROVA_WAVELENGTH, 1e-12);
    CHECK_CLOSE(PETROVA_PHOTON_ENERGY, H_PLANCK * C_LIGHT / PETROVA_WAVELENGTH, 1e-12);
    CHECK_CLOSE(PETROVA_PHOTON_ENERGY_EV, 0.04772, 1e-3);
    CHECK_CLOSE(PETROVA_FREQUENCY / 1e12, 11.538, 1e-4);

    // ADR-001: the emission line is 25.984 um, NOT 3.11 um; the setpoint is a
    // temperature in Celsius, NOT 96.415 THz. Guard both against regression.
    CHECK_CLOSE(PETROVA_WAVELENGTH * 1e6, 25.984, 1e-9);
    CHECK_CLOSE(CELL_TEMP_SETPOINT - 273.15, 96.415, 1e-9);

    // --- P2 depends entirely on this 3.585 K gap ------------------------------
    CHECK(CELL_TEMP_SETPOINT < WATER_BOILING_POINT);
    CHECK_CLOSE(WATER_BOILING_POINT - CELL_TEMP_SETPOINT, 3.585, 1e-3);

    // The thermal blackbody peak must NOT coincide with the Petrova line, or the
    // Thermal-IR and Petrovascope view modes would be showing the same thing.
    CHECK_CLOSE(WIEN_LAMBDA_AT_SETPOINT * 1e6, 7.841, 1e-3);
    CHECK(std::fabs(WIEN_LAMBDA_AT_SETPOINT - PETROVA_WAVELENGTH) > 1e-5);

    // --- transport -----------------------------------------------------------
    // Vogel-Fulcher is the ONE viscosity model, used by the simulator and by the
    // oracle alike. Deriving gamma from the tabulated 20 C measurement instead
    // would leave a 2.5e-5 systematic offset between oracle and simulation that
    // every transport test would then have to absorb in its tolerance.
    const double mu_vf_room = VF_A * std::exp(VF_B / (AMBIENT_TEMP_DEFAULT - VF_C));
    const double gamma = 6.0 * 3.14159265358979323846 * mu_vf_room * a;
    CHECK_CLOSE(DRAG_COEFF_20C, gamma, 1e-12);

    // The tabulated measurement is the cross-check ON the fit, and that is its
    // whole job. If the fit ever drifts from reality by more than 0.5 %, the
    // problem is the fit, not the tolerance.
    CHECK_CLOSE(mu_vf_room, WATER_VISCOSITY_20C, 5e-3);
    CHECK_CLOSE(CONDUCTION_COEFF, 4.0 * 3.14159265358979323846 * WATER_CONDUCTIVITY * a, 1e-12);
    CHECK_CLOSE(WATER_THERMAL_DIFFUSIVITY,
                WATER_CONDUCTIVITY / (WATER_DENSITY * WATER_SPECIFIC_HEAT), 1e-12);

    CHECK_CLOSE(WATER_VISCOSITY_SETPOINT, VF_A * std::exp(VF_B / (CELL_TEMP_SETPOINT - VF_C)), 1e-12);
    // The fit must also hold at the far end of the range it is used over, or
    // P4's magnitude is guesswork. It is less accurate up there (~1%), which is
    // exactly why the tabulated value is kept alongside it.
    CHECK_CLOSE(WATER_VISCOSITY_SETPOINT, WATER_VISCOSITY_96C, 2e-2);

    // P4 rests on this: viscosity drops ~3.5x between room temperature and the
    // Astrophage setpoint, so a live cell jitters visibly more than a dead one.
    // The exact ratio depends on the fit, so assert the magnitude, not a digit.
    CHECK(mu_vf_room / WATER_VISCOSITY_SETPOINT > 3.0);
    const double motility = DIFFUSIVITY_SETPOINT / DIFFUSIVITY_20C;
    CHECK(motility > 4.0 && motility < 4.6);

    // --- cross-check against the emitted oracle -------------------------------
    using namespace astro::expected;
    CHECK_CLOSE(T3_CHARGE_NEUTRAL, CHARGE_NEUTRAL_BUOYANCY, 1e-12);
    CHECK_CLOSE(T5_DELTA_MASS_FULL, CELL_MASS_STORE_MAX, 1e-12);
    CHECK_CLOSE(T16_PHOTON_ENERGY, PETROVA_PHOTON_ENERGY, 1e-12);
    CHECK_CLOSE(T17_PETROVA_FREQ, PETROVA_FREQUENCY, 1e-12);
    CHECK_CLOSE(T8_REYNOLDS_FULL, 0.0167, 5e-2);
    CHECK(T8_REYNOLDS_FULL < 0.1);                 // Stokes must stay valid
    CHECK(T2_V_RISE_EMPTY < 0.0);                  // empty cells RISE
    CHECK(T1_V_SETTLE_FULL > 0.0);                 // full cells SINK
    CHECK(T12_MOTILITY_RATIO > 3.5);               // P4 is detectable

    // Komorov: 1 kW for 25 minutes is exactly the 1.5 MJ capacity.
    CHECK_CLOSE(T15_KOMOROV_ENERGY, CELL_ENERGY_MAX, 1e-12);
    CHECK_CLOSE(T15_KOMOROV_MASS, CELL_MASS_STORE_MAX, 1e-12);

    // --- provenance table integrity -------------------------------------------
    CHECK(PARAM_COUNT > 40);
    for (int i = 0; i < PARAM_COUNT; ++i) {
        CHECK(PARAM_TABLE[i].key != nullptr && PARAM_TABLE[i].key[0] != '\0');
        CHECK(PARAM_TABLE[i].unit != nullptr);
        if (PARAM_TABLE[i].tunable) CHECK(PARAM_TABLE[i].tmin < PARAM_TABLE[i].tmax);
        if (PARAM_TABLE[i].prov == Provenance::Derived) CHECK(!PARAM_TABLE[i].tunable);
    }

    // Checking a COUNT of canon entries would be a weak test -- it passes if the
    // wrong parameters are tagged. Check that the specific numbers Weir wrote are
    // the ones carrying the gold lock, since the UI's canon guarantee rests on it.
    auto provenance_of = [](const char* key) -> Provenance {
        for (int i = 0; i < PARAM_COUNT; ++i) {
            const char* k = PARAM_TABLE[i].key;
            int j = 0;
            while (k[j] && key[j] && k[j] == key[j]) ++j;
            if (k[j] == '\0' && key[j] == '\0') return PARAM_TABLE[i].prov;
        }
        return Provenance::Invented;   // not found
    };
    const char* must_be_canon[] = {
        "CELL_DIAMETER", "CELL_MASS_DRY", "CELL_TEMP_SETPOINT", "CELL_ENERGY_MAX",
        "CELL_ALBEDO", "PETROVA_WAVELENGTH", "CO2_LINE_A", "CO2_LINE_B",
        "LIFE_DOUBLING_TIME",
    };
    for (const char* k : must_be_canon) CHECK(provenance_of(k) == Provenance::Canon);

    // And the numbers we invented must NOT masquerade as canon.
    const char* must_be_invented[] = {
        "PETROVA_MAX_POWER", "TAU_DIAMETER", "CHAMBER_W", "CO2_MASS_PER_DIVISION",
        "CELL_ALBEDO_DEAD",
    };
    for (const char* k : must_be_invented) CHECK(provenance_of(k) == Provenance::Invented);

    // Objective presets must be ordered by magnification and have sane optics.
    CHECK(OBJECTIVE_COUNT == 3);
    CHECK(OBJECTIVE_DEFAULT >= 0 && OBJECTIVE_DEFAULT < OBJECTIVE_COUNT);
    for (int i = 1; i < OBJECTIVE_COUNT; ++i) {
        CHECK(OBJECTIVES[i].magnification > OBJECTIVES[i - 1].magnification);
        CHECK(OBJECTIVES[i].resolution_m < OBJECTIVES[i - 1].resolution_m);
        CHECK(OBJECTIVES[i].depth_of_field_m < OBJECTIVES[i - 1].depth_of_field_m);
    }
    // The whole optics premise: DOF is far shallower than the chamber slab.
    CHECK(OBJECTIVES[OBJECTIVE_DEFAULT].depth_of_field_m < CHAMBER_D / 10.0);
    // ADR-009: a single field of view cannot hold the population; the chamber must be bigger.
    CHECK(OBJECTIVES[OBJECTIVE_DEFAULT].fov_m < CHAMBER_W / 4.0);

    return astro::test::finish("test_canon");
}
