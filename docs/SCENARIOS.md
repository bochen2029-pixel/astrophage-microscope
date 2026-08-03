# SCENARIOS — the content spec

**Load when working M11, or when adding a scenario.** Scenarios are data (`scenarios/*.json`, schema in `contracts/scenario_v1.h`).

Each scenario's `accept` block has **two consumers**: the objective checkmarks in the UI, and the headless integration runner (`tools/headless --scenario X --assert`). One definition, two consumers — so scenarios cannot silently rot.

---

## The eight

### 1. `first-light` — Ignition · *the tutorial and the demo* · teaches **P3**, **P2**
Room-temperature chamber, 800 dormant cells at 0 % charge, no light.
**Beat.** In Brightfield the field is black dots doing nothing. Petrovascope: nothing. Apply the heat brush past 96.415 °C — the culture **wakes**, and the Petrovascope fills with magenta. Now chill the chamber: the cells hold 96.415 °C anyway.
**Accept.** All cells awake within 5 s of crossing the setpoint; medium equilibrates to 369.565 ± 0.5 K and stays; `boil_event_count == 0`.
**Headless note.** The cells carry a small store (charge 0.02): a literally-0-store cell that wakes is an unstable heat sink — it overcools its own neighbourhood below the setpoint, flips to *spending* a store it doesn't have, and starves. The boundary is `neumann`: under `robin`, waking the edge cells needs the interior above the setpoint (a gradient), so "all awake" and "mean at the setpoint" cannot both hold; insulated, a uniform heat pulse wakes every cell at once and the cells absorb the excess down to the setpoint. That the mean is 369.2 K and not the heated 371 K is the thermostat doing the work — a null with no cells stays at 371.

### 2. `three-percent-line` — Buoyancy · teaches **P1**
**Dormant** cells, charge uniform on [0, 10 %], gravity along −y, no light. Dormant, not
awake, on purpose: the canonical −52.1 / +1681 μm/s are drift at **293 K** water viscosity
(`γ = 6πμa` with `μ(293.15 K)`). Awake cells warm the medium toward the 369.565 K setpoint
(P2), drop `μ` 3.36× and inflate every drift velocity by the same factor — measured, the
whole velocity-vs-charge fit scales 3.25× and misses the tolerance. Buoyancy (P1) is a
mass effect, identical whether awake or dormant, so dormancy costs the scenario nothing.
**Beat.** The field **sorts itself vertically**. Below 3.006 % charge cells rise; above, they sink; a sharp band forms at the neutral line. Then illuminate: charging cells cross the line one by one and rain downward.
**Accept.** After 60 s, mean charge of the top third < 3.006 % < mean charge of the bottom third; the below-neutral and above-neutral groups separate by > 1 mm; measured empty-cell rise −52.1 ± 3 μm/s; full-cell fall +1681 ± 60 μm/s.

**Do not accept on a position correlation.** It saturates around 0.84 for Pearson *and* Spearman alike, because cells within a hair of 3.006 % have near-zero drift velocity — a cell at 3.1 % moves 20 μm in a minute — and so stay wherever they spawned, contributing pure noise. That is correct physics, not a defect. The sharp form of the claim is on **velocity**: drift velocity is linear in charge (measured Pearson −1.000000) with its zero crossing at `CHARGE_NEUTRAL_BUOYANCY`.

### 3. `komorov` — The 1 kW laser · *the canonical experiment*
A single cell on a microbalance. Charge beam at 1 kW for 25 minutes.
**Beat.** Watch the microbalance climb from 0.021 ng to 16.71 ng. This is Dimitri's experiment, reproduced.
**Accept.** After 1500 s of fully absorbed 1 kW: `energy = 1.5 MJ ± 0.1 %`, `Δmass = 16.69 ng ± 0.1 %`.
**Note — an honest detail the novel skips.** With a geometric cross-section of 7.854e-11 m², a 1 kW beam must be focused to a ~10 μm spot (1.27e13 W/m²) for the cell to absorb all of it. The scenario sets that up explicitly (irradiance = 1 kW / `CELL_CROSS_SECTION`, so 1500 s delivers exactly 1.5 MJ) and the beam-spot readout makes the geometry visible.
**Headless note.** A single dormant cell in a uniform medium has no motion or thermal field worth resolving, so the scenario runs `thermal_active: false` at `physics_rate 100` — 15,600 ticks, not 1.56 M — and charging (`energy += P·dt`) is exact at any dt.

### 4. `shadow-garden` — Absolute shadows · teaches **P5**
Dense culture, 12,000 cells in one scope field, single collimated source, aimable.
**Beat.** A lit monolayer forms at the light-facing surface; everything behind is in perfect darkness and never charges. Rotate the light and the population re-sorts. Self-shading is total because albedo is exactly 0.
**Accept.** Cells with irradiance < `TAXIS_DARK_THRESHOLD` show `dCharge/dt == 0` exactly; charged fraction vs. depth along the light axis correlates at r < −0.8.
**Headless note.** At a realistic irradiance a cell charges over hours (why komorov needs a focused 1 kW beam), so the source is a bright collimated 1e15 W/m² and the cells are **dormant** — they still absorb (feeding gates on alive, not awake), with no thermostat drain to blur the read. The gradient is read early (3 s, front layer ~15 % charged) while it is steep; as the front saturates the profile broadens and the correlation weakens (−0.88 at 3 s → −0.81 by 10 s).

### 5. `bloom` — Population dynamics
CO₂-saturated medium, warm, well lit, 10 starting cells, Generational clock.
**Beat.** Exponential growth; the log-axis chart goes straight. CO₂ depletes, growth stalls, add more and it resumes. The chamber goes black.
**Accept.** Population fits `N(t) = N₀·2^(t/8d)` within 5 % while CO₂ is non-limiting; growth halts within one doubling of CO₂ exhaustion.
**Headless note.** `doubling_time_s` is reported in **culture** time: the fit is over `sim_time_s`, scaled by `biology_rate` (`dt_bio = dt·biology_rate`), so at the generational clock a doubling of 0.69 s of sim time is the canon 6.912e5 s (8 days). Measured 706k s, within 5 %.

### 6. `taumoeba` — Predation and the 82.5 problem
Established culture; introduce 20 Taumoeba; then apply a nitrogen gradient.
**Beat.** The predator crashes the population. Introduce nitrogen and the Taumoeba die where N₂ is high, letting Astrophage recover there. Then raise nitrogen slowly across generations and watch mean tolerance climb under selection until a resistant strain emerges. **That is Taumoeba-82.5, arrived at by actual directional selection rather than by script.**
**Accept.** Mean tolerance rises monotonically on a 5-generation moving average under a slow N₂ ramp; a strain with tolerance ≥ 0.825 appears within 40 generations at default `TAU_MUTATION_SIGMA`.
**Headless note.** The self-contained run reproduces `test_evolution`'s proven dynamics (ADR-030): a dense 1 mm chamber, 24,000 prey held by a `seed_cells` top-up (the predator's food), 1024 predators, `biology_rate 5e5`, both compaction flags on, and a `set_n2` ramp from `TAU_N2_LETHAL_CONC` to 1.87× over 2.175 s — a linear survival frontier `tol* = N/N_lethal − 1 = 0.4·t` that clears 0.825 near 2.06 s, then holds at the cap. Measured: max tolerance 0.99, mean 0.88.

### 7. `spin-drive-face` — One drive face, under the microscope
The one place the ship intrudes, and it belongs here: a spin drive is a **cell-scale machine**, so the microscope is the correct instrument to look at it. The view is a single triangular face of one of the 1,009 drives. The cycle loops:
1. **Attract** — low-intensity IR at the CO₂ lines at the face; cells migrate to it by taxis.
2. **Rotate** — the face turns to vacuum.
3. **Flash** — a high-intensity 25.984 μm pulse forces full discharge against the slide; the Petrovascope whites out.
4. **Scrape** — spent cells are cleared; repeat.

**Beat.** You see, at cell scale, the actual mechanism that pushes a 2,100,000 kg starship. The HUD shows accumulated impulse per cycle.
**Accept.** Impulse per cycle = `Σ(E_discharged)/c` within 1 %; no cell retains energy after a flash; stable over 100 cycles.
**Headless note.** A `flash` stimulus arms the discharge (ADR-033): at `PETROVA_FLASH_POWER` (3 MW) a full cell empties in ~0.5 s, so a 0.6 s pulse clears all 1000. `impulse_per_cycle` is the photon-momentum identity `|Σ recoil|·c / Σ(E_discharged) = 1`, and `total_energy_j → 0` is the "no cell retains energy" check. The recoil is **accounted, not applied** to the free cell — a 16.7 ng discharge would recoil a lone 10 μm cell at ~c; the cell is on the drive face, so the impulse drives the ship.

### 8. `sandbox` — Everything unlocked
All tools, all parameters, no objective. The scenario people will spend the most time in.

---

## Scenario JSON

```jsonc
{
  "schema": 1,
  "id": "first-light",
  "title": "First Light",
  "blurb": "A cold chamber of inert black powder. Until you heat it.",
  "teaches": ["P3", "P2"],
  "seed": 20260802,

  "chamber": { "w": 4.0e-3, "h": 4.0e-3, "d": 6.0e-5,
               "boundary_x": "reflecting", "boundary_y": "reflecting" },

  "medium": { "kind": "water", "temp_init": 293.15, "co2_init": 0.0, "n2_init": 0.0,
              "thermal_bc": "robin", "ambient_temp": 293.15,
              "density_model": "canon-mass" },

  "light": { "sources": [], "ambient": 0.0 },

  "populations": [
    { "kind": "astrophage", "count": 800,
      "placement": "uniform",
      "charge": { "dist": "constant", "value": 0.0 },
      "awake": false }
  ],

  "clock": { "preset": "realtime" },

  "scope": { "mode": "brightfield", "objective": "WORKING",
             "focal_plane": 0.0, "center": [0.0, 0.0], "overlays": [] },

  "tools": ["heat", "chill", "illuminate", "seed_cells"],

  "param_overrides": {},

  "objective": {
    "text": "Wake the culture. Then try to cool it back down.",
    "accept": [
      { "metric": "awake_fraction",  "op": ">=", "value": 1.0,     "after_s": 5 },
      { "metric": "medium_temp_mean","op": "~=", "value": 369.565, "tol": 0.5, "after_s": 120 },
      { "metric": "boil_event_count","op": "==", "value": 0 }
    ]
  }
}
```

## Driving (schema v2, ADR-032)

A scenario plays itself out unattended through a `drive` list — the headless `--assert`
runner (and, later, the app) applies each stimulus at every tick in its window:

```jsonc
"drive": [
  { "kind": "heat",   "t0_s": 0.0, "t1_s": 5.0, "v0": 15.9, "v1": 15.9 },  // K/s, x dt
  { "kind": "set_n2", "t0_s": 0.0, "t1_s": 2.175, "v0": 0.01, "v1": 0.0187 },// absolute kg/m^3
  { "kind": "seed_cells", "t0_s": 0, "t1_s": 0, "v0": 24000, "v1": 24000 },  // maintain prey
  { "kind": "flash",  "t0_s": 0.0, "t1_s": 0.6 }                             // arm the discharge
]
```

Kinds: `heat` / `chill` / `inject_co2` / `inject_n2` (brush rates, ×dt so a dose is
`physics_rate`-invariant), `set_light` / `set_n2` (absolute levels), `seed_cells` (hold a
prey target), `flash` (the spin-drive discharge). `radius <= 0` is a chamber-global brush;
`t1 <= t0` is an open-ended window. Other v2 fields: `objective.duration_s` (the `--assert`
horizon; 0 = derive it), `medium.thermal_active` (0 skips the temperature field), and
`compaction` / `tau_compaction` (store turnover, for the breeding arc).

## Telemetry export

CSV, one row per sampled tick: `t_s, n_live, n_dead, n_tau, mean_charge, total_energy_J, mean_temp_cell_K, mean_temp_medium_K, co2_total_kg, mean_tolerance, boil_events, divisions, deaths`.

Header comments record the seed, scenario id, git describe, and **every broken canon lock**.
