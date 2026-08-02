"""
canon.py -- THE SINGLE SOURCE OF TRUTH for every number in the Astrophage simulator.

Nothing in src/, tests/, or docs/ may contain a physical literal. Every constant
originates here and is emitted by derive.py into:

    src/core/canon_generated.h      constexpr values + provenance table for the UI
    tests/golden/expected_values.h  expected values for the physics oracle tests
    docs/VERIFICATION.md            the human-readable derivation report

Provenance tags (carried all the way into the UI, see docs/ARCHITECTURE.md Sec 6):
    CANON    stated in Project Hail Mary (Weir, 2021)
    DERIVED  computed from CANON + real physics; formula recorded
    REAL     real-world physical constant or material property
    INVENTED not in canon; our choice; exposed as a tunable parameter

Canon references cite _brainstorm/RESEARCH_astrophage_canon.md by section.
"""

CANON, DERIVED, REAL, INVENTED = "CANON", "DERIVED", "REAL", "INVENTED"

# ---------------------------------------------------------------------------
# Universal constants (CODATA 2018 exact values where applicable)
# ---------------------------------------------------------------------------
U = {
    "C_LIGHT":   (2.99792458e8,    "m/s",       REAL, "exact by definition"),
    "K_BOLTZ":   (1.380649e-23,    "J/K",       REAL, "exact by definition"),
    "H_PLANCK":  (6.62607015e-34,  "J*s",       REAL, "exact by definition"),
    "G_ACCEL":   (9.80665,         "m/s^2",     REAL, "standard gravity"),
    "SIGMA_SB":  (5.670374419e-8,  "W/m^2/K^4", REAL, "Stefan-Boltzmann"),
    "EV_JOULE":  (1.602176634e-19, "J/eV",      REAL, "exact by definition"),
    "WIEN_B":    (2.897771955e-3,  "m*K",       REAL, "Wien displacement"),
    "TNT_JOULE": (4184.0,          "J/g",       REAL, "1 g TNT equivalent"),
}

# ---------------------------------------------------------------------------
# Base parameters. (key, value, unit, provenance, note, ref, tunable)
# tunable = None | (min, max, log)
# ---------------------------------------------------------------------------
BASE = [
    # --- Astrophage cell -----------------------------------------------------
    ("CELL_DIAMETER", 1.0e-5, "m", CANON,
     "10 micron sphere.", "REF 1.1", None),
    ("CELL_MASS_DRY", 2.1e-14, "kg", CANON,
     "0.021 ng. Conflicts with 'mostly water' -- see ADR-002.", "REF 1.1", None),
    ("CELL_TEMP_SETPOINT", 369.565, "K", CANON,
     "96.415 C. NOT a frequency -- see ADR-001.", "REF 1.4", (273.15, 573.15, False)),
    ("CELL_ENERGY_MAX", 1.5e6, "J", CANON,
     "1.5 MJ per cell at full enrichment.", "REF 1.3", (1.0e3, 1.5e7, True)),
    ("CELL_ALBEDO", 0.0, "-", CANON,
     "Opaque at ALL wavelengths (super cross-sectionality).", "REF 1.2", None),
    ("CELL_ALBEDO_DEAD", 0.85, "-", INVENTED,
     "Dead cells go translucent; degree unstated.", "REF 4", (0.0, 1.0, False)),
    ("CELL_LETHAL_TEMP", 573.15, "K", INVENTED,
     "300 C. Torch-the-slide escape hatch; canon silent.", None, (373.15, 1273.15, False)),

    # --- Petrova emission ----------------------------------------------------
    ("PETROVA_WAVELENGTH", 2.5984e-5, "m", CANON,
     "25.984 micron. NOT 3.11 um -- see ADR-001.", "REF 1.4", None),
    ("PETROVA_BEAM_HALF_ANGLE", 0.35, "rad", INVENTED,
     "~20 deg. Directed out one side; tightness unstated.", "REF 1.5", (0.02, 3.14159, False)),
    ("PETROVA_MAX_POWER", 5.0e-2, "W", INVENTED,
     "50 mW. Chosen so max output ~= the power a full cell needs to hover. "
     "Canon gives capacity but never a discharge rate. See ADR-005.", None, (1e-6, 1e2, True)),
    ("PETROVA_SLEW_RATE", 1.0, "rad/s", INVENTED,
     "How fast a cell can re-aim its emission axis.", None, (0.01, 100.0, True)),

    # --- CO2 navigation and reproduction ------------------------------------
    ("CO2_LINE_A", 4.26e-6, "m", CANON,
     "nu3 asymmetric stretch; strongest IR-active CO2 band.", "REF 1.5", None),
    ("CO2_LINE_B", 1.831e-5, "m", CANON,
     "Book value. Real nu2 bending band is ~15 um; treat as artistic offset.", "REF 3.2", None),
    ("CO2_MASS_PER_DIVISION", 2.1e-14, "kg", INVENTED,
     "= 1x dry mass. Stoichiometric placeholder.", None, (2.1e-15, 2.1e-13, True)),
    ("CO2_DIFFUSIVITY_WATER", 1.92e-9, "m^2/s", REAL, "in water at 25 C", None, None),
    ("CO2_SAT_CONC_1ATM", 1.5, "kg/m^3", REAL, "CO2-saturated water at 1 atm", None, None),

    # --- Life cycle ----------------------------------------------------------
    ("LIFE_DOUBLING_TIME", 6.912e5, "s", CANON,
     "~8 days.", "REF 1.6", (3.6e3, 6.912e6, True)),
    ("LIFE_DIVISION_ENERGY_COST", 0.0, "J", INVENTED,
     "Canon silent; default free.", None, (0.0, 1.0e5, False)),
    ("LIFE_MITOSIS_DURATION", 900.0, "s", INVENTED,
     "15 min visual division event.", None, (1.0, 1.0e4, True)),

    # --- Taumoeba ------------------------------------------------------------
    ("TAU_DIAMETER", 4.0e-5, "m", INVENTED,
     "40 um. Must exceed Astrophage to engulf; size unstated.", "REF 1.8", (1.5e-5, 2.0e-4, True)),
    ("TAU_CRAWL_SPEED", 5.0e-6, "m/s", INVENTED,
     "Amoeboid crawl; real range 1-10 um/s.", None, (1e-7, 1e-4, True)),
    ("TAU_DIGEST_TIME", 120.0, "s", INVENTED, "Per engulfed cell.", None, (1.0, 1e4, True)),
    ("TAU_N2_LETHAL_CONC", 1.0e-2, "kg/m^3", INVENTED,
     "Nitrogen is lethal to Taumoeba.", "REF 1.8", (1e-4, 1.0, True)),
    ("TAU_N2_TOLERANCE_INIT", 0.0, "-", INVENTED,
     "Heritable trait in [0,1]. 0.825 => the 'Taumoeba-82.5' strain.", "REF 1.8", (0.0, 1.0, False)),
    ("TAU_MUTATION_SIGMA", 0.02, "-", INVENTED,
     "Per-division trait drift; drives the breeding scenario.", None, (0.0, 0.5, False)),
    ("TAU_BIOMASS_YIELD", 0.6, "-", INVENTED,
     "Fraction of prey biomass converted.", None, (0.0, 1.0, False)),

    # --- Medium (water) ------------------------------------------------------
    ("WATER_VISCOSITY_20C", 1.002e-3, "Pa*s", REAL, None, None, None),
    ("WATER_DENSITY", 998.2, "kg/m^3", REAL, "at 20 C", None, (500.0, 2000.0, False)),
    ("WATER_CONDUCTIVITY", 0.598, "W/m/K", REAL, None, None, None),
    ("WATER_SPECIFIC_HEAT", 4182.0, "J/kg/K", REAL, None, None, None),
    ("WATER_BOILING_POINT", 373.15, "K", REAL,
     "3.585 K above the Astrophage setpoint. This gap is why a culture can never boil.",
     None, None),
    # Vogel-Fulcher fit for water viscosity: mu(T) = A*exp(B/(T-C))
    ("VF_A", 2.414e-5, "Pa*s", REAL, "Vogel-Fulcher coefficient A", None, None),
    ("VF_B", 570.58, "K", REAL, "Vogel-Fulcher coefficient B", None, None),
    ("VF_C", 140.0, "K", REAL, "Vogel-Fulcher coefficient C", None, None),
    ("AIR_CONVECTION_H", 10.0, "W/m^2/K", REAL, "free convection to room air (Robin BC)", None, None),

    # --- Mechanics / numerics -----------------------------------------------
    ("CONTACT_STIFFNESS", 1.0e-6, "N/m", INVENTED,
     "Soft-sphere repulsion; tuned so rest overlap < 5%.", None, (1e-9, 1e-3, True)),
    ("WALL_STICKINESS", 0.15, "-", INVENTED,
     "Adhesion probability on coverslip contact.", None, (0.0, 1.0, False)),
    ("WALL_STUCK_DRAG_MULT", 20.0, "-", INVENTED, "Drag multiplier while adhered.", None, (1.0, 1e3, True)),
    ("DT_PHYSICS", 1.0e-3, "s", INVENTED,
     "Fixed physics timestep. Never varies with frame rate.", None, (1e-5, 1e-2, True)),
    ("TAXIS_MEMORY_TIME", 2.0, "s", INVENTED,
     "Run-and-tumble temporal comparison window. See ADR-007.", None, (0.05, 60.0, True)),
    ("TAXIS_DARK_THRESHOLD", 1.0e-3, "W/m^2", INVENTED,
     "Below this irradiance a cell does not move (canon: 'does not move in darkness').",
     "REF 1.5", (0.0, 1e3, True)),
    ("TAXIS_SEEK_FEED_BELOW", 0.95, "-", INVENTED, "Charge fraction below which a cell seeks light.", None, (0.0, 1.0, False)),
    ("TAXIS_SEEK_BREED_ABOVE", 0.98, "-", INVENTED, "Charge fraction above which a cell seeks CO2.", None, (0.0, 1.0, False)),

    # --- Chamber defaults ----------------------------------------------------
    ("CHAMBER_W", 4.0e-3, "m", INVENTED, "Default culture chamber width. See ADR-009.", None, (1e-4, 2e-2, True)),
    ("CHAMBER_H", 4.0e-3, "m", INVENTED, "Default culture chamber height.", None, (1e-4, 2e-2, True)),
    ("CHAMBER_D", 6.0e-5, "m", INVENTED, "Default slide/coverslip gap (slab depth).", None, (1e-5, 1e-3, True)),

    # --- Optics presets ------------------------------------------------------
    ("OPTICS_LAMBDA_VIS", 5.5e-7, "m", REAL, "550 nm reference for resolution/DOF.", None, None),
    ("OPTICS_SENSOR_PIXEL", 6.0e-6, "m", REAL, "Detector pixel pitch for the Berek DOF term.", None, None),
]

# Objective presets: (name, magnification, NA, immersion index)
OBJECTIVES = [
    ("SURVEY",  10.0,  0.25, 1.000),
    ("WORKING", 40.0,  0.65, 1.000),
    ("DETAIL", 100.0,  1.25, 1.515),
]

# Field grid resolutions. See ADR-008 (why 512 and not 1024).
FIELDS = [
    ("FIELD_N_TEMP", 512, "-", INVENTED, "Temperature grid resolution (NxN)."),
    ("FIELD_N_CO2",  256, "-", INVENTED, "CO2 grid resolution."),
    ("FIELD_N_N2",   128, "-", INVENTED, "N2 grid resolution."),
    ("FIELD_N_IRRAD", 512, "-", INVENTED, "Irradiance grid resolution."),
]

# Capacity / performance targets for the sm_89 reference GPU (RTX 4070 Ti SUPER).
LIMITS = [
    ("MAX_CELLS",     2000000, "-", INVENTED, "Hard capacity of the cell store."),
    ("MAX_TAUMOEBA",    65536, "-", INVENTED, "Hard capacity of the taumoeba store."),
    ("DEFAULT_CELLS",  200000, "-", INVENTED, "Default starting population."),
    ("TARGET_FPS",        144, "-", INVENTED, "Frame budget target on the reference GPU."),
]
