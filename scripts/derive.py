#!/usr/bin/env python3
"""
derive.py -- compute every DERIVED quantity from canon.py and emit three artifacts.

    python scripts/derive.py            regenerate all three
    python scripts/derive.py --check    exit 1 if any artifact is stale (used by audit.ps1)

Emits:
    src/core/canon_generated.h      constexpr values + provenance table
    tests/golden/expected_values.h  physics-oracle expectations
    docs/VERIFICATION.md            human-readable derivation report

Why this exists: across dozens of sessions, a hand-copied constant WILL drift between
the doc, the header, and the test. Generating all three from one file makes that
impossible. See docs/ARCHITECTURE.md Sec 5 (Anti-drift machinery).
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import canon as K  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = {k: v[0] for k, v in ((p[0], p[1:]) for p in K.BASE)}
for name, (val, *_rest) in K.U.items():
    B[name] = val

c, kB, h, g = B["C_LIGHT"], B["K_BOLTZ"], B["H_PLANCK"], B["G_ACCEL"]


def mu_water(T):
    """Vogel-Fulcher viscosity of water [Pa*s]."""
    return B["VF_A"] * math.exp(B["VF_B"] / (T - B["VF_C"]))


# ---------------------------------------------------------------------------
# Derived quantities. (KEY, value, unit, formula)
# ---------------------------------------------------------------------------
a = B["CELL_DIAMETER"] / 2.0
V = 4.0 / 3.0 * math.pi * a ** 3
m_dry = B["CELL_MASS_DRY"]
m_store_max = B["CELL_ENERGY_MAX"] / c ** 2
m_full = m_dry + m_store_max
rho_w = B["WATER_DENSITY"]
mu20 = B["WATER_VISCOSITY_20C"]
mu96 = mu_water(B["CELL_TEMP_SETPOINT"])
gamma20 = 6.0 * math.pi * mu20 * a
gamma96 = 6.0 * math.pi * mu96 * a
E_neutral = (rho_w * V - m_dry) * c ** 2
lam = B["PETROVA_WAVELENGTH"]
E_photon = h * c / lam
cond = 4.0 * math.pi * B["WATER_CONDUCTIVITY"] * a          # W/K
alpha_w = B["WATER_CONDUCTIVITY"] / (rho_w * B["WATER_SPECIFIC_HEAT"])
T_room = B["AMBIENT_TEMP_DEFAULT"]


def stokes_v(rho_p, mu=mu20):
    """Terminal velocity, +down. Negative means the cell rises."""
    return 2.0 / 9.0 * (rho_p - rho_w) * g * a ** 2 / mu


DERIVED = [
    ("CELL_RADIUS", a, "m", "CELL_DIAMETER / 2"),
    ("CELL_VOLUME", V, "m^3", "(4/3) pi r^3"),
    ("CELL_CROSS_SECTION", math.pi * a ** 2, "m^2", "pi r^2 (projected disc, collimated beam)"),
    ("CELL_SURFACE_AREA", 4.0 * math.pi * a ** 2, "m^2", "4 pi r^2 (isotropic illumination)"),
    ("CELL_DENSITY_DRY", m_dry / V, "kg/m^3", "CELL_MASS_DRY / CELL_VOLUME"),
    ("CELL_MASS_STORE_MAX", m_store_max, "kg", "CELL_ENERGY_MAX / c^2"),
    ("CELL_MASS_FULL", m_full, "kg", "CELL_MASS_DRY + CELL_MASS_STORE_MAX"),
    ("CELL_DENSITY_FULL", m_full / V, "kg/m^3", "CELL_MASS_FULL / CELL_VOLUME"),
    ("ENERGY_NEUTRAL_BUOYANCY", E_neutral, "J", "(rho_water * V - m_dry) c^2"),
    ("CHARGE_NEUTRAL_BUOYANCY", E_neutral / B["CELL_ENERGY_MAX"], "-", "E_neutral / CELL_ENERGY_MAX"),
    ("PETROVA_FREQUENCY", c / lam, "Hz", "c / lambda"),
    ("PETROVA_PHOTON_ENERGY", E_photon, "J", "h c / lambda"),
    ("PETROVA_PHOTON_ENERGY_EV", E_photon / B["EV_JOULE"], "eV", "h c / (lambda * e)"),
    ("PETROVA_PHOTONS_PER_FULL_CELL", B["CELL_ENERGY_MAX"] / E_photon, "-", "E_max / E_photon"),
    ("WATER_VISCOSITY_SETPOINT", mu96, "Pa*s", "Vogel-Fulcher at CELL_TEMP_SETPOINT"),
    ("WATER_THERMAL_DIFFUSIVITY", alpha_w, "m^2/s", "k / (rho cp)"),
    ("DRAG_COEFF_20C", gamma20, "kg/s", "6 pi mu(20C) a"),
    ("DRAG_COEFF_SETPOINT", gamma96, "kg/s", "6 pi mu(96.415C) a"),
    ("DIFFUSIVITY_20C", kB * T_room / gamma20, "m^2/s", "Einstein-Stokes kT/gamma at 20 C"),
    ("DIFFUSIVITY_SETPOINT", kB * B["CELL_TEMP_SETPOINT"] / gamma96, "m^2/s",
     "Einstein-Stokes at the setpoint; 4.24x the 20 C value -- drives P4"),
    ("CONDUCTION_COEFF", cond, "W/K", "4 pi k_water a  (Nu = 2, sphere in still fluid)"),
    ("LIFE_GROWTH_RATE", math.log(2.0) / B["LIFE_DOUBLING_TIME"], "1/s", "ln2 / doubling time"),
    ("TNT_GRAMS_PER_FULL_CELL", B["CELL_ENERGY_MAX"] / B["TNT_JOULE"], "g", "E_max / 4184 J/g"),
    ("WIEN_LAMBDA_AT_SETPOINT", B["WIEN_B"] / B["CELL_TEMP_SETPOINT"], "m",
     "Wien b / T -- the THERMAL peak, distinct from the Petrova line"),
]

# ---------------------------------------------------------------------------
# Physics-oracle expectations (docs/VERIFICATION.md + tests/golden/expected_values.h)
# ---------------------------------------------------------------------------
v_full = stokes_v(m_full / V)
v_empty = stokes_v(m_dry / V)
D20 = kB * T_room / gamma20
D96 = kB * B["CELL_TEMP_SETPOINT"] / gamma96
Q20 = cond * (B["CELL_TEMP_SETPOINT"] - T_room)
F_1mW = 1.0e-3 / c
P_hover = gamma20 * v_full * c

EXPECT = [
    ("T1_V_SETTLE_FULL", v_full, "m/s", 5e-3, "Stokes terminal velocity, fully charged cell (down)"),
    ("T2_V_RISE_EMPTY", v_empty, "m/s", 5e-3, "Stokes terminal velocity, empty cell (negative = rises)"),
    ("T3_CHARGE_NEUTRAL", E_neutral / B["CELL_ENERGY_MAX"], "-", 1e-3, "Charge fraction at neutral buoyancy"),
    ("T4_DIFFUSIVITY_20C", D20, "m^2/s", 3e-2, "Einstein-Stokes D = kT/gamma at 20 C"),
    ("T4_RMS_DISP_1S_20C", math.sqrt(4.0 * D20 * 1.0), "m", 3e-2, "2D RMS displacement in 1 s, MSD = 4Dt"),
    ("T5_DELTA_MASS_FULL", m_store_max, "kg", 1e-9, "Mass gained charging 0 -> 1.5 MJ"),
    ("T6_THRUST_1MW", F_1mW, "N", 5e-3, "Photon thrust F = P/c at P = 1 mW"),
    ("T6_VTERM_1MW", F_1mW / gamma20, "m/s", 5e-3, "Terminal velocity under 1 mW thrust"),
    ("T7_CONDUCTION_20C", Q20, "W", 5e-3, "Heat loss of an awake cell into 20 C water"),
    ("T7_ENDURANCE_20C", B["CELL_ENERGY_MAX"] / Q20, "s", 5e-3, "Time to drain 1.5 MJ at that rate"),
    ("T8_REYNOLDS_FULL", rho_w * abs(v_full) * B["CELL_DIAMETER"] / mu20, "-", 5e-3,
     "Reynolds number at max terminal velocity; must stay << 1"),
    ("T12_DIFFUSIVITY_SETPOINT", D96, "m^2/s", 3e-2, "D at the setpoint temperature (drives P4)"),
    ("T12_MOTILITY_RATIO", D96 / D20, "-", 3e-2, "Live/dead Brownian mobility ratio"),
    ("T15_KOMOROV_ENERGY", 1.0e3 * 1500.0, "J", 1e-3, "Dimitri's laser: 1 kW x 25 min"),
    ("T15_KOMOROV_MASS", 1.0e3 * 1500.0 / c ** 2, "kg", 1e-3, "Mass gained in the Komorov experiment"),
    ("T16_PHOTON_ENERGY", E_photon, "J", 1e-4, "Petrova photon energy"),
    ("T17_PETROVA_FREQ", c / lam, "Hz", 1e-4, "Petrova frequency"),
    ("T20_WIEN_SETPOINT", B["WIEN_B"] / B["CELL_TEMP_SETPOINT"], "m", 1e-4,
     "Thermal blackbody peak; must differ from the Petrova line"),
    ("HOVER_POWER_FULL", P_hover, "W", 5e-3, "Emission power a full cell needs to hover"),
    ("TAU_MOMENTUM_EMPTY", m_dry / gamma20, "s", 1e-6, "Momentum relaxation time, empty cell"),
    ("TAU_MOMENTUM_FULL", m_full / gamma20, "s", 1e-6, "Momentum relaxation time, full cell"),
]

# Numerical-stability facts that drive solver choices (docs/PHYSICS.md Sec 7).
STAB = []
for key, n, *_ in K.FIELDS:
    dx = B["CHAMBER_W"] / n
    diff = alpha_w if "TEMP" in key else (B["CO2_DIFFUSIVITY_WATER"] if "CO2" in key else 2.0e-9)
    if "IRRAD" in key:
        continue
    dt_max = dx * dx / (4.0 * diff)
    STAB.append((key, n, dx, diff, dt_max, math.ceil(B["DT_PHYSICS"] / dt_max)))

OPTICS = []
for name, M, NA, n_im in K.OBJECTIVES:
    lam_v = B["OPTICS_LAMBDA_VIS"]
    res = 0.61 * lam_v / NA
    dof = (lam_v * n_im) / (NA * NA) + (n_im * B["OPTICS_SENSOR_PIXEL"]) / (M * NA)
    fov = 22.0e-3 / M
    OPTICS.append((name, M, NA, n_im, res, dof, fov, B["CELL_DIAMETER"] / res))


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------
def d(x):
    return f"{x:.17g}"


BANNER = ("// GENERATED BY scripts/derive.py FROM scripts/canon.py -- DO NOT EDIT BY HAND.\n"
          "// Edit scripts/canon.py and re-run:  python scripts/derive.py\n"
          "// Rationale: docs/ARCHITECTURE.md Sec 5 (Anti-drift machinery).\n")


def emit_header():
    o = [BANNER, "#pragma once", "", "namespace astro::canon {", ""]
    o.append("enum class Provenance : unsigned char { Canon = 0, Derived = 1, Real = 2, Invented = 3 };")
    o.append("")
    o.append("// ---- Universal constants -------------------------------------------------")
    for name, (val, unit, prov, note) in K.U.items():
        o.append(f"inline constexpr double {name} = {d(val)}; // [{unit}] {note}")
    o.append("")
    o.append("// ---- Base parameters (see scripts/canon.py for provenance) ---------------")
    for key, val, unit, prov, note, ref, tun in K.BASE:
        cm = f"// [{unit}] {prov}" + (f" -- {note}" if note else "")
        o.append(f"inline constexpr double {key} = {d(val)}; {cm}")
    o.append("")
    o.append("// ---- Derived quantities --------------------------------------------------")
    for key, val, unit, formula in DERIVED:
        o.append(f"inline constexpr double {key} = {d(val)}; // [{unit}] DERIVED = {formula}")
    o.append("")
    o.append("// ---- Field grid resolutions ----------------------------------------------")
    for key, n, unit, prov, note in K.FIELDS:
        o.append(f"inline constexpr int {key} = {n}; // {prov} -- {note}")
    o.append("")
    o.append("// ---- Capacity and performance targets ------------------------------------")
    for key, n, unit, prov, note in K.LIMITS:
        o.append(f"inline constexpr int {key} = {n}; // {prov} -- {note}")
    o.append("")
    o.append("// ---- Objective presets ----------------------------------------------------")
    o.append("struct Objective { const char* name; double magnification; double na; double immersion;")
    o.append("                   double resolution_m; double depth_of_field_m; double fov_m; };")
    o.append("inline constexpr Objective OBJECTIVES[] = {")
    for name, M, NA, n_im, res, dof, fov, _sp in OPTICS:
        o.append(f'    {{ "{name}", {d(M)}, {d(NA)}, {d(n_im)}, {d(res)}, {d(dof)}, {d(fov)} }},')
    o.append("};")
    o.append(f"inline constexpr int OBJECTIVE_COUNT = {len(OPTICS)};")
    o.append("inline constexpr int OBJECTIVE_DEFAULT = 1; // WORKING 40x/0.65")
    o.append("")
    o.append("// ---- Provenance table (drives the UI parameter inspector) ----------------")
    o.append("struct ParamMeta { const char* key; double value; const char* unit; Provenance prov;")
    o.append("                   const char* note; bool tunable; double tmin; double tmax; bool tlog; };")
    o.append("inline constexpr ParamMeta PARAM_TABLE[] = {")
    pmap = {"CANON": "Canon", "DERIVED": "Derived", "REAL": "Real", "INVENTED": "Invented"}
    for key, val, unit, prov, note, ref, tun in K.BASE:
        nt = (note or "").replace('"', "'")
        if ref:
            nt = f"[{ref}] {nt}"
        if tun:
            o.append(f'    {{ "{key}", {d(val)}, "{unit}", Provenance::{pmap[prov]}, "{nt}", '
                     f'true, {d(tun[0])}, {d(tun[1])}, {"true" if tun[2] else "false"} }},')
        else:
            o.append(f'    {{ "{key}", {d(val)}, "{unit}", Provenance::{pmap[prov]}, "{nt}", '
                     f'false, 0.0, 0.0, false }},')
    for key, val, unit, formula in DERIVED:
        o.append(f'    {{ "{key}", {d(val)}, "{unit}", Provenance::Derived, "= {formula}", '
                 f'false, 0.0, 0.0, false }},')
    o.append("};")
    o.append(f"inline constexpr int PARAM_COUNT = {len(K.BASE) + len(DERIVED)};")
    o.append("")
    o.append("} // namespace astro::canon")
    return "\n".join(o) + "\n"


def emit_expected():
    o = [BANNER, "#pragma once", "",
         "// Physics-oracle expectations. Every value is computed by scripts/derive.py from",
         "// first principles -- the tests assert that the SIMULATION reproduces them.",
         "// See docs/VERIFICATION.md for the full derivation report.", "",
         "namespace astro::expected {", ""]
    for key, val, unit, tol, note in EXPECT:
        o.append(f"inline constexpr double {key} = {d(val)}; // [{unit}] {note}")
        o.append(f"inline constexpr double {key}_TOL = {d(tol)}; // relative tolerance")
    o.append("")
    o.append("} // namespace astro::expected")
    return "\n".join(o) + "\n"


def emit_doc():
    o = ["# VERIFICATION -- the physics oracle",
         "",
         "<!-- GENERATED BY scripts/derive.py FROM scripts/canon.py -- DO NOT EDIT BY HAND. -->",
         "",
         "This file is the **oracle**. Every number here is computed from first principles by",
         "`scripts/derive.py`, independently of the simulator. The tests in `tests/physics/`",
         "assert that the simulation reproduces them. **If these pass, the physics is right.**",
         "",
         "Regenerate with `python scripts/derive.py`. `scripts/audit.ps1` fails if this file is stale.",
         "",
         "---",
         "",
         "## 1. Cell geometry, mass, and the buoyancy consequence",
         "",
         "| Quantity | Value | Unit | Origin |",
         "|---|---|---|---|"]
    rows = [("Cell volume", V, "m^3", "(4/3)pi r^3"),
            ("Dry density (canon mass)", m_dry / V, "kg/m^3", "**25x LIGHTER than water** -- see ADR-002"),
            ("Mass if water-density", rho_w * V, "kg", "0.523 ng vs canon 0.021 ng"),
            ("Stored mass at 1.5 MJ", m_store_max, "kg", "E/c^2; canon says '~17 ng'"),
            ("Full-cell density", m_full / V, "kg/m^3", f"**{m_full / V / rho_w:.1f}x water**, denser than osmium"),
            ("Energy at neutral buoyancy", E_neutral, "J", "(rho_w V - m_dry) c^2"),
            ("**Charge at neutral buoyancy**", E_neutral / B["CELL_ENERGY_MAX"] * 100.0, "%",
             "**P1: below this a cell rises, above it sinks**")]
    for n_, v_, u_, s_ in rows:
        o.append(f"| {n_} | `{v_:.6g}` | {u_} | {s_} |")

    o += ["", "## 2. Drag, diffusion, and dynamic regime", "",
          "| Quantity | Value | Unit | Note |", "|---|---|---|---|",
          f"| Drag coefficient gamma(20 C) | `{gamma20:.6g}` | kg/s | 6 pi mu a |",
          f"| Diffusivity D(20 C) | `{D20:.6g}` | m^2/s | = `{D20 * 1e12:.4f}` um^2/s |",
          f"| RMS 2D displacement in 1 s (20 C) | `{math.sqrt(4 * D20) * 1e6:.4f}` | um | MSD = 4Dt |",
          f"| Diffusivity D(96.415 C) | `{D96:.6g}` | m^2/s | = `{D96 * 1e12:.4f}` um^2/s |",
          f"| RMS 2D displacement in 1 s (96.415 C) | `{math.sqrt(4 * D96) * 1e6:.4f}` | um | **{D96 / D20:.2f}x -- drives P4** |",
          f"| Momentum relaxation tau, empty | `{m_dry / gamma20:.6g}` | s | |",
          f"| Momentum relaxation tau, full | `{m_full / gamma20:.6g}` | s | **{m_full / m_dry:.0f}x spread -> OU integrator** |",
          "",
          "The 800x mass spread between an empty and a full cell is why the integrator must be the",
          "exact-propagator Ornstein-Uhlenbeck update and not a naive overdamped or Verlet scheme.",
          "See `docs/PHYSICS.md` Sec 3.",
          "",
          "## 3. Sedimentation (P1)", "",
          "| Quantity | Value | Unit | Note |", "|---|---|---|---|",
          f"| Empty cell terminal velocity | `{v_empty * 1e6:+.1f}` | um/s | negative = **rises** |",
          f"| Full cell terminal velocity | `{v_full * 1e6:+.1f}` | um/s | **sinks** |",
          f"| Reynolds number at max speed | `{rho_w * abs(v_full) * B['CELL_DIAMETER'] / mu20:.4f}` | - | Stokes valid (<< 1) |",
          "",
          "## 4. Petrova emission and photon thrust", "",
          "| Quantity | Value | Unit |", "|---|---|---|",
          f"| Wavelength | `{lam * 1e6:.3f}` | um |",
          f"| Frequency | `{c / lam / 1e12:.3f}` | THz |",
          f"| Photon energy | `{E_photon:.6g}` J = `{E_photon / B['EV_JOULE']:.5f}` | eV |",
          f"| Photons in a full cell | `{B['CELL_ENERGY_MAX'] / E_photon:.4g}` | - |",
          "",
          "| Emission power | Thrust F = P/c | Terminal velocity |", "|---|---|---|"]
    for P in (1e-3, 1e-2, P_hover):
        o.append(f"| `{P * 1e3:.2f}` mW | `{P / c:.4g}` N | `{P / c / gamma20 * 1e6:.2f}` um/s |")
    o += ["",
          f"**`{P_hover * 1e3:.2f}` mW is exactly the power a fully charged cell needs to hover** against its own",
          "weight. That is why `PETROVA_MAX_POWER` defaults to 50 mW (ADR-005).",
          "",
          "## 5. Thermal behaviour (P2, P3)", "",
          f"Conduction coefficient `4 pi k a` = `{cond:.6g}` W/K.", "",
          "| Medium temperature | Heat loss Q | 1.5 MJ endurance |", "|---|---|---|"]
    for Tc in (20.0, 37.0, 90.0, 96.0):
        Q = cond * (B["CELL_TEMP_SETPOINT"] - (Tc + 273.15))
        o.append(f"| `{Tc:.1f}` C | `{Q * 1e3:.3f}` mW | `{B['CELL_ENERGY_MAX'] / Q / 86400 / 365.25:.1f}` yr |")
    o += ["",
          "**Q -> 0 as the medium approaches the setpoint.** The medium asymptotes to 96.415 C and stops.",
          f"Since the setpoint is `{B['WATER_BOILING_POINT'] - B['CELL_TEMP_SETPOINT']:.3f}` K below water's boiling point, "
          "**a live culture can never boil its medium at 1 atm**. That is P2, and it is emergent -- do not special-case it.",
          "",
          "Analytic near-field halo around an isolated cell, `T(r) = T_inf + dT a/r`:", "",
          "| r | Excess temperature |", "|---|---|"]
    for mult in (2, 5, 10, 20):
        o.append(f"| {mult}a | `+{(B['CELL_TEMP_SETPOINT'] - T_room) / mult:.1f}` K |")
    o += ["",
          "## 6. Field solver stability", "",
          f"Water thermal diffusivity alpha = `{alpha_w:.6g}` m^2/s.",
          f"Diffusion time across the default {B['CHAMBER_W'] * 1e3:.1f} mm chamber = "
          f"`{B['CHAMBER_W'] ** 2 / alpha_w:.4g}` s -- fast, but not instantaneous, so a quasi-steady solve is wrong.",
          "",
          "| Field | N | dx | Diffusivity | Explicit dt_max | Substeps per 1 ms |", "|---|---|---|---|---|---|"]
    for key, n, dx, diff, dt_max, sub in STAB:
        o.append(f"| `{key}` | {n} | `{dx * 1e6:.2f}` um | `{diff:.4g}` m^2/s | `{dt_max:.4g}` s | **{sub}** |")
    o += ["",
          "These substep counts are why the grids are sized as they are (ADR-008) and why the",
          "sub-grid thermal halo is added analytically rather than resolved (ADR-010).",
          "",
          "## 7. Microscope optics", "",
          "| Objective | M | NA | Resolution | Depth of field | Field of view | Cell spans |",
          "|---|---|---|---|---|---|---|"]
    for name, M, NA, n_im, res, dof, fov, span in OPTICS:
        o.append(f"| {name} | {M:.0f}x | {NA:.2f} | `{res * 1e9:.0f}` nm | `{dof * 1e6:.2f}` um | "
                 f"`{fov * 1e6:.0f}` um | `{span:.0f}` resel |")
    o += ["",
          f"At the default WORKING objective the depth of field is `{OPTICS[1][5] * 1e6:.2f}` um inside a "
          f"`{B['CHAMBER_D'] * 1e6:.0f}` um slab,",
          "so most cells are visibly out of focus at any moment. Racking focus is a primary interaction, not a garnish.",
          "",
          "## 8. Scale and the energy ledger", "",
          "| Quantity | Value |", "|---|---|",
          f"| One full cell | `{B['CELL_ENERGY_MAX'] / B['TNT_JOULE']:.1f}` g TNT equivalent |",
          f"| 5,000 full cells | `{5000 * B['CELL_ENERGY_MAX'] / 1e9:.2f}` GJ = `{5000 * B['CELL_ENERGY_MAX'] / B['TNT_JOULE'] / 1e6:.3f}` t TNT |",
          f"| Default population ({B_int('DEFAULT_CELLS')} cells), fully charged | "
          f"`{lim('DEFAULT_CELLS') * B['CELL_ENERGY_MAX'] / 1e12:.1f}` TJ = "
          f"`{lim('DEFAULT_CELLS') * B['CELL_ENERGY_MAX'] / B['TNT_JOULE'] / 1e6:.1f}` kt TNT |",
          f"| Thermal blackbody peak at setpoint (Wien) | `{B['WIEN_B'] / B['CELL_TEMP_SETPOINT'] * 1e6:.3f}` um -- **distinct from the 25.984 um Petrova line** |",
          f"| Growth rate at 8 d doubling | `{math.log(2) / B['LIFE_DOUBLING_TIME']:.4g}` /s |",
          "",
          "The energy ledger is not a curiosity: the default population holds kiloton-scale energy inside a",
          "droplet. The HUD carries this readout permanently (docs/RENDERING.md Sec 6).",
          "",
          "## 9. Test expectations", "",
          "Emitted verbatim into `tests/golden/expected_values.h`.", "",
          "| Symbol | Value | Unit | Rel. tol | Meaning |", "|---|---|---|---|---|"]
    for key, val, unit, tol, note in EXPECT:
        o.append(f"| `{key}` | `{val:.6g}` | {unit} | {tol:g} | {note} |")
    o.append("")
    return "\n".join(o) + "\n"


def lim(key):
    return {k: v for k, v, *_ in K.LIMITS}[key]


def B_int(key):
    return f"{lim(key):,}"


def write(path, content, check):
    full = os.path.join(ROOT, path)
    old = None
    if os.path.exists(full):
        with open(full, "r", encoding="utf-8", newline="") as f:
            old = f.read()
    if check:
        # Compare line-ending-normalised. Git may check these files out with CRLF
        # depending on core.autocrlf, and a fresh clone must not report STALE
        # (which would fail audit A1 for a session that has changed nothing).
        if old is None or old.replace("\r\n", "\n") != content.replace("\r\n", "\n"):
            print(f"STALE: {path}  (run: python scripts/derive.py)")
            return False
        print(f"  ok   {path}")
        return True
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="") as f:
        f.write(content)
    print(f"  wrote {path}")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 if any artifact is stale")
    args = ap.parse_args()
    ok = True
    ok &= write("src/core/canon_generated.h", emit_header(), args.check)
    ok &= write("tests/golden/expected_values.h", emit_expected(), args.check)
    ok &= write("docs/VERIFICATION.md", emit_doc(), args.check)
    if not ok:
        sys.exit(1)
    print("derive.py: OK")


if __name__ == "__main__":
    main()
