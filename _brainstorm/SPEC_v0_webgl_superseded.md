# Astrophage Microscope Simulator — Technical Specification

**Codename:** `astrophage-scope`
**Version:** 1.0 (spec), 2026-08-02
**Status:** Ready to implement. No code exists yet; this is a greenfield build.
**Source of truth for canon:** `compass_artifact_wf-4fda020d-275f-5a48-95a9-d6a95655e03f_text_markdown.md` (same directory). Cited below as **[REF §x.y]**.

---

## 0. How to use this document

This spec is written so that a fresh session — human or agent — can open it with no other context and start writing code immediately.

- **§1–3** define what is being built and the non-negotiable canon.
- **§4** is the physics model. Every equation is written out. Every constant is verified (§14 shows the verification run).
- **§5–7** are the numerical, software, and rendering architectures.
- **§8–10** are UX, content (scenarios), and data formats.
- **§11** is the acceptance test suite with exact expected values. **If you implement §4 and pass §11, the simulator is correct.**
- **§12–13** are performance budget and milestones. Build in milestone order; each milestone is independently demoable.
- **§15** is the decisions log — read it before you disagree with anything above.

**Convention in this document:** every physical quantity is tagged
`[CANON]` (stated in *Project Hail Mary*), `[DERIVED]` (computed from canon + real physics), `[REAL]` (real-world physical constant or property), or `[INVENTED]` (not in canon; chosen by us and exposed as a tunable parameter). This tagging is **not decoration — it is carried into the source code** (§4.1) and surfaced in the UI (§8.4).

---

## 1. Product definition

### 1.1 One sentence

A deterministic, physically-grounded, real-time simulation of Astrophage viewed **through a microscope** — a quasi-2D slide of water at 40× magnification where you can heat, illuminate, feed, and predate a live culture, and watch canon behavior emerge rather than be scripted.

### 1.2 Scope: what this is

- **Spatial scale:** 20 μm – 2 mm. A field of view of a few hundred micrometres. A single cell is 10 μm and spans ~19 resolution elements — big, round, and clearly resolved.
- **Quasi-2D:** the simulation domain is a thin slab (a slide/coverslip gap), `W × H × D` where `D` (10–120 μm) is much smaller than `W`, `H` (200–2000 μm). Physics is fully 3D in the small; the *view* is a top-down projection through a microscope with a shallow depth of field. The `z` coordinate exists and matters (buoyancy, sedimentation, focus) but the world is effectively a plane.
- **Population:** 100 – 50,000 Astrophage cells, 0 – 500 Taumoeba.
- **Emergence over scripting:** the headline phenomena in §2.2 are *not* special-cased. They fall out of the equations in §4.

### 1.3 Scope: what this is explicitly **not**

Out of scope for v1. Do not build these. They are noted only so a later session knows where the seams are.

- No interstellar / solar-system / Petrova-arc view. No orbital mechanics. No ships.
- No Hail Mary, no Blip-A, no relativistic travel, no time dilation.
- The **spin drive** appears only as **§9.7**, a microscope-scale view of a *single* drive face — because a spin drive is a cell-scale machine, and the microscope is the correct instrument to look at it. It is a slide scenario, not a spacecraft.
- No stellar dimming, no population-of-a-planet, no climate model.

**Seam for later:** the simulation core (§6) is scale-agnostic and unit-clean (SI throughout). A future macro-scale module would reuse `core/constants`, `core/units`, and the provenance system, and share nothing else.

### 1.4 Target platform

**Web. TypeScript + Vite + WebGL2, simulation in a Web Worker.** Rationale: zero-install, trivially shareable, screenshot-verifiable by an agent, and WebGL2 instancing comfortably hits the performance target (§12). No runtime framework dependency beyond a ~4 kB reactive store; UI is plain TS + DOM.

**Swap point:** if a future requirement demands >200k agents or 3D volumetric rendering, replace `render/` and add a WebGPU compute path for `sim/integrator`. Everything in `core/` and `sim/model/` is renderer-agnostic and would survive unchanged.

---

## 2. Design pillars

### 2.1 The four pillars

1. **Canon is data, not code.** Every canon number lives in one table (§3) loaded as data with provenance metadata. Nothing in the physics hardcodes `96.415`. This makes the "what if the setpoint were 80 °C" experiment a slider, not a rebuild.
2. **Honest about the seams.** The novel contains real internal contradictions and unstated quantities. The simulator does not paper over them — it exposes each one as a labelled toggle with the conflicting options both playable (§15).
3. **The invisible is the through-line.** Astrophage is *black in visible light* [CANON, REF §1.2] and *emits at 25.984 μm* [CANON, REF §1.4], which no eye can see. The Petrovascope toggle — switching between what a human sees and what the cell is actually doing — is the core interaction verb, at every scale, in every scenario.
4. **Deterministic and replayable.** Same seed + same scenario + same inputs → bit-identical trajectory. This is what makes §11 testable and makes bug reports reproducible.

### 2.2 The five signature phenomena

These are the reasons this simulator is worth building. Each **emerges** from §4 with no special-case code. Each is verified in §14.

| # | Phenomenon | Emerges from | The moment |
|---|---|---|---|
| **P1** | **The 3% line.** Canon cell mass (0.021 ng) in a 10 μm sphere gives ρ = 40 kg/m³ — 25× *lighter* than water. An empty cell **rises at 52 μm/s**. A fully charged cell (+16.69 ng) is ρ = 31,915 kg/m³, 32× *denser than water*, denser than osmium, and **sinks at 1681 μm/s**. Neutral buoyancy falls at exactly **3.006 % charge**. | §4.5 mass-energy + §4.4 Stokes | Charge state is readable at a glance from which way a cell drifts. Charge the culture and it rains to the coverslip. |
| **P2** | **The perfect thermostat.** 96.415 °C sits just below water's boiling point. A live culture pumps heat into its medium, but output falls as ΔT → 0, so the slide asymptotes to 96.415 °C and **can never boil at 1 atm**. Push it hotter from outside and Astrophage flips to heat *sink* and drags it back down. | §4.6 bidirectional thermostat + conduction | The slide is thermally pinned to a fictional constant. Nothing you do moves it. |
| **P3** | **Ignition.** Below setpoint an unwoken cell is inert powder [CANON, REF §1.7]. Raise the slide past 96.415 °C and the culture *wakes* — and then holds its own temperature even as you cool it back down [CANON, REF §1.4]. | §4.6 dormancy latch | The whole field lights up at once in the Petrovascope. This is the demo. |
| **P4** | **Live cells move.** Canon states motion is the tell that a cell is alive [REF §4]. Reproduced for free: a live cell's 2.9 mW output warms nearby water, viscosity drops 3.4×, Brownian diffusivity rises 4.2×, and the thermal plume convects. Dead cells sit still and go translucent. | §4.4 T-dependent viscosity + §4.6 halo | You can tell live from dead by eye, exactly as Grace does. |
| **P5** | **Absolute shadows.** Astrophage is opaque to *everything* — "super cross-sectionality" [CANON, REF §1.2]. In a directionally lit dense culture, cells shadow each other perfectly, so back rows starve while front rows charge. | §4.8 occluded irradiance field | A charging culture self-organizes into a lit monolayer. |

---

## 3. Canon parameter table

This table is the file `src/core/canon.ts`. It is the **only** place these numbers appear.

### 3.1 Provenance type

```ts
export type Provenance = 'CANON' | 'DERIVED' | 'REAL' | 'INVENTED';

export interface Param<U extends string = string> {
  readonly value: number;
  readonly unit: U;          // SI unit string, e.g. 'm', 'kg', 'J', 'K'
  readonly provenance: Provenance;
  readonly note?: string;    // why this value; what conflicts with it
  readonly ref?: string;     // e.g. 'REF §1.4'
  readonly tunable?: { min: number; max: number; log?: boolean };
}
```

Any `Param` with `tunable` set automatically appears in the parameter inspector (§8.4) with a provenance badge. `CANON` params render with a lock icon that must be explicitly broken to edit; the HUD then shows a persistent **"NON-CANON RUN"** marker, and scenario telemetry exports record every broken lock.

### 3.2 The table

All values SI unless noted. `°C → K` uses `T_K = T_C + 273.15`.

#### Astrophage cell

| Key | Value | Unit | Prov. | Note |
|---|---|---|---|---|
| `cell.diameter` | `1.0e-5` | m | CANON | 10 μm sphere [REF §1.1] |
| `cell.massDry` | `2.1e-14` | kg | CANON | 0.021 ng [REF §1.1] |
| `cell.densityDry` | `40.1` | kg/m³ | DERIVED | = massDry / V. **Conflicts with "mostly water"** — see §15-D1. Drives **P1**. |
| `cell.tempSetpoint` | `369.565` | K | CANON | 96.415 °C [REF §1.4] |
| `cell.energyMax` | `1.5e6` | J | CANON | 1.5 MJ/cell [REF §1.3] |
| `cell.massStoreMax` | `1.669e-11` | kg | DERIVED | = energyMax/c². 16.69 ng; canon says "~17 ng" ✓ |
| `cell.albedo` | `0.0` | — | CANON | opaque at all λ [REF §1.2] |
| `cell.albedoDead` | `0.85` | — | INVENTED | dead cells go translucent [REF §4] |

#### Petrova emission

| Key | Value | Unit | Prov. | Note |
|---|---|---|---|---|
| `petrova.wavelength` | `2.5984e-5` | m | CANON | 25.984 μm [REF §1.4]. **Not 3.11 μm** — see §15-D0 |
| `petrova.frequency` | `1.1538e13` | Hz | DERIVED | 11.538 THz |
| `petrova.photonEnergy` | `7.6449e-21` | J | DERIVED | 0.04772 eV |
| `petrova.photonsPerFullCell` | `1.962e26` | — | DERIVED | HUD flavor |
| `petrova.beamHalfAngle` | `0.35` | rad | INVENTED | ~20°. Directed out one side [REF §1.5]; tightness unstated. Tunable 0.02–π. |
| `petrova.maxPower` | `5.0e-2` | W | INVENTED | 50 mW. Discharge rate is unstated in canon. Chosen so hover ≈ max output (§4.7). Tunable 1e-6–1e2, log. |

#### CO₂ navigation

| Key | Value | Unit | Prov. | Note |
|---|---|---|---|---|
| `co2.lineA` | `4.26e-6` | m | CANON | ν₃ asymmetric stretch [REF §1.5, §3.2] |
| `co2.lineB` | `1.831e-5` | m | CANON | book value; real ν₂ band is ~15 μm [REF §3.2] |
| `co2.massPerDivision` | `2.1e-14` | kg | INVENTED | = 1× dry mass. Stoichiometric placeholder. Tunable 0.1×–10×. |
| `co2.diffusivityWater` | `1.92e-9` | m²/s | REAL | 25 °C |
| `co2.satConc1atm` | `1.5` | kg/m³ | REAL | CO₂-saturated water |

#### Life cycle

| Key | Value | Unit | Prov. | Note |
|---|---|---|---|---|
| `life.doublingTime` | `6.912e5` | s | CANON | ~8 days [REF §1.6] |
| `life.growthRate` | `1.003e-6` | 1/s | DERIVED | ln2 / doublingTime |
| `life.divisionEnergyCost` | `0.0` | J | INVENTED | canon silent; default free. Tunable 0–1e5. |
| `life.mitosisDuration` | `900` | s | INVENTED | 15 min visual event. Tunable. |

#### Taumoeba

| Key | Value | Unit | Prov. | Note |
|---|---|---|---|---|
| `tau.diameter` | `4.0e-5` | m | INVENTED | 40 μm — must exceed Astrophage to engulf [REF §1.8] |
| `tau.crawlSpeed` | `5.0e-6` | m/s | INVENTED | amoeboid, real range 1–10 μm/s |
| `tau.digestTime` | `120` | s | INVENTED | per engulfed cell |
| `tau.n2LethalConc` | `1.0e-2` | kg/m³ | INVENTED | nitrogen kills [REF §1.8] |
| `tau.n2ToleranceInit` | `0.0` | — | INVENTED | trait ∈ [0,1]; 0.825 ⇒ "Taumoeba-82.5" |
| `tau.mutationSigma` | `0.02` | — | INVENTED | per-division drift; drives §9.6 breeding |

#### Medium & environment

| Key | Value | Unit | Prov. | Note |
|---|---|---|---|---|
| `water.viscosity20C` | `1.002e-3` | Pa·s | REAL | |
| `water.viscosity96C` | `2.98e-4` | Pa·s | REAL | 3.4× lower — drives **P4** |
| `water.density` | `998.2` | kg/m³ | REAL | |
| `water.conductivity` | `0.598` | W/(m·K) | REAL | |
| `water.specificHeat` | `4182` | J/(kg·K) | REAL | |
| `water.diffusivity` | `1.4325e-7` | m²/s | DERIVED | k/(ρ·cₚ) |
| `water.boilingPoint` | `373.15` | K | REAL | 3.585 K above setpoint — drives **P2** |

#### Universal

`c = 2.99792458e8 m/s`, `kB = 1.380649e-23 J/K`, `h = 6.62607015e-34 J·s`, `g = 9.80665 m/s²`, `σ_SB = 5.670374e-8 W/(m²·K⁴)` — all [REAL].

---

## 4. The physical model

### 4.1 World, coordinates, units

- **Units: strict SI internally.** Metres, kilograms, seconds, kelvin, joules, watts. No exceptions in `core/` or `sim/`. Display conversion (μm, °C, ng, mW) happens only in `ui/` and `render/`.
- **Numeric type:** `Float64Array` for all CPU physics state. Positions are ~1e-4 m with meaningful structure at ~1e-9 m — float32 (7 digits) is marginal, float64 is safe. Convert to `Float32Array` in **micrometres** at GPU upload time.
- **Coordinates:** right-handed, origin at slab centre. `x` right, `y` up-screen, `z` toward the objective (positive = closer to the lens). Domain `x ∈ [-W/2, W/2]`, `y ∈ [-H/2, H/2]`, `z ∈ [-D/2, D/2]`.
- **Gravity** acts along **−y** (screen-down), not −z. This is the deliberate choice that makes **P1** visible: a real upright microscope has gravity along the optical axis, so sedimentation would be invisible (cells would just drift out of focus). We model an *inverted / side-mounted* stage so buoyant drift is in-plane and legible. `[INVENTED]`, documented in-UI, and switchable to `gravityAxis: 'z'` for the physically-conventional-but-boring case.
- **Boundaries:** `x`, `y` are configurable `periodic | reflecting | absorbing` (default `reflecting` — it's a sealed chamber). `z` is always reflecting (glass slide and coverslip). Cells that touch a `z` wall may **adhere** with probability `wall.stickiness` `[INVENTED]`, which reproduces the real microscopy artifact of cells settling and sticking to glass.

### 4.2 Cell state

Structure-of-Arrays. One `CellStore` object holding parallel typed arrays, capacity-doubling on growth, with a free-list for dead slots.

```ts
interface CellStore {
  capacity: number; count: number;
  // identity
  id:        Float64Array;   // stable, monotonic; also seeds the per-cell RNG stream
  alive:     Uint8Array;     // 0 = free slot, 1 = alive, 2 = dead-corpse (still rendered)
  // kinematics (SI)
  x, y, z:   Float64Array;   // m
  vx, vy, vz:Float64Array;   // m/s
  // thermodynamic / energetic
  energy:    Float64Array;   // J, ∈ [0, cell.energyMax]
  tempCell:  Float64Array;   // K, internal
  awake:     Uint8Array;     // 0 = dormant powder, 1 = thermostat engaged  (see §4.6)
  // emission
  emitPower: Float64Array;   // W, current Petrova output
  emitDirX, emitDirY, emitDirZ: Float64Array; // unit vector, emission axis
  // biology
  biomass:   Float64Array;   // kg, ∈ [massDry/2, massDry]; ≥ massDry ⇒ can divide
  co2Held:   Float64Array;   // kg absorbed toward next division
  ageS:      Float64Array;   // s since birth
  // bookkeeping
  rngState:  BigUint64Array; // PCG32 state, one stream per cell
}
```

**Derived, never stored:** `mass = biomass + energy/c²`, `radius = cell.diameter/2`, `density = mass / V`, `charge = energy / energyMax`.

### 4.3 Regime analysis (why the integrator looks the way it does)

Verified in §14:

| Quantity | Empty cell | Full cell | Consequence |
|---|---|---|---|
| mass | 2.1e-14 kg | 1.671e-11 kg | **800× spread** |
| drag coeff γ = 6πμa | 9.4436e-8 kg/s | same (γ ∝ size, not mass) | |
| momentum relaxation τ = m/γ | **2.22e-7 s** | **1.77e-4 s** | 800× spread |
| Reynolds number at terminal | ≪1 | 0.017 | Stokes valid throughout |

An empty cell is *violently* overdamped (τ = 0.2 μs); a full cell at a 1 ms timestep is only marginally so. **Do not write a naive overdamped position-Langevin integrator** — it will be wrong for charged cells. **Do not write plain velocity-Verlet + drag** — it is unstable for empty cells unless `dt < 2τ = 0.44 μs`.

**Use the exact-propagator Ornstein–Uhlenbeck (OU) velocity update** (the "O" step of BAOAB). It is unconditionally stable, exact for the linear-drag + white-noise problem at *any* dt, and degrades gracefully to the overdamped limit as `dt/τ → ∞`. This single choice covers the entire 800× mass range with one code path.

### 4.4 Motion integrator

Per cell, per physics step `dt`:

**1. Deterministic force** `F = F_grav + F_thrust + F_contact + F_thermophoresis`

- **Buoyant weight** (Archimedes): `F_grav = −(m − ρ_medium·V) · g · ŷ`
  where `V = (4/3)πa³` is fixed (an enriched cell gains *mass*, not volume — the neutrino store has no volume). This term alone produces **P1**.
- **Photon thrust** [REAL, REF §2.2]: `F_thrust = −(P_emit / c) · d̂` where `d̂` is the emission direction. Recoil is opposite emission. `P_emit` from §4.7.
- **Contact** (§4.9): soft-sphere repulsion, only within `2a`.
- **Thermophoresis** `[INVENTED, off by default]`: `F_th = −D_T · m · ∇T`. Real and directionally interesting near hot cells, but the coefficient for a fictional organism is a free parameter. Ship it off; expose the toggle.

**2. OU velocity update** (exact propagator). Let `γ = 6π·μ(T_local)·a`, `τ = m/γ`, `c₁ = exp(−dt/τ)`, `c₂ = sqrt((1 − c₁²)·kB·T_local/m)`:

```
v ← c₁·v + (F/γ)·(1 − c₁) + c₂·ξ        with ξ ~ N(0, I₃)
```

The `(F/γ)(1−c₁)` term relaxes toward the terminal velocity `F/γ`, and `c₂·ξ` injects thermal noise at exactly the fluctuation–dissipation-correct amplitude. As `dt ≫ τ` this becomes `v = F/γ + sqrt(kB·T/m)·ξ` — the overdamped limit, automatically.

**3. Position update:** `r ← r + v·dt`, then boundary handling.

**Temperature-dependent viscosity** — this is what produces **P4**, so it is not optional:

```
μ(T) = A · exp(B / (T − C))     Vogel–Fulcher for water
A = 2.414e-5 Pa·s, B = 570.58 K, C = 140.0 K       [REAL]
```
Check: μ(293.15 K) = 1.002e-3 ✓, μ(369.565 K) = 2.98e-4 ✓. `T_local` is sampled from the temperature field (§4.10) at the cell's position, bilinearly.

**Diffusivity sanity** (emerges, do not hardcode): `D = kB·T/γ` = 0.0429 μm²/s at 20 °C, 0.182 μm²/s at 96.4 °C. RMS in-plane displacement in 1 s: 0.414 μm cold, 0.852 μm hot.

### 4.5 Mass–energy coupling

```
mass(cell) = biomass + energy / c²
```

That is the whole model, and it is the most consequential line in the codebase. `energy ∈ [0, 1.5e6] J` maps to a stored mass of `0 → 16.69 ng` against a biomass of `0.021 ng`. Everything in **P1** follows.

**Numerical hazard:** `energy/c²` for small `energy` is ~1e-17 kg against a biomass of 2.1e-14 kg — three orders down but well inside float64. Do **not** store `mass` as a separate accumulating field; always recompute from `energy`. An accumulating mass field drifts and silently breaks the energy ledger (§11-T5).

**Neutral-buoyancy charge** (emerges, verify in tests):
```
E_neutral = (ρ_water·V − m_dry)·c² = 4.509e4 J = 3.006 % of energyMax
```

### 4.6 Thermal model: dormancy, thermostat, conduction

This resolves the central canon contradiction (§15-D2) and produces **P2** and **P3**.

**State machine.** A cell is `awake ∈ {0,1}`:

```
if (!awake && T_local >= tempSetpoint)  awake = 1      // ignition latch — irreversible
if (awake)                              tempCell = tempSetpoint   // perfect clamp
else                                    tempCell = T_local        // inert; tracks medium
```

Reconciliation: [REF §1.7] "inert unless heated above 96.415 °C" describes a **dormant** cell. [REF §1.4] "constant internal temperature regardless of environment" describes an **awake** cell. The latch satisfies both and gives us **P3** as a dramatic, canon-faithful moment.

**Heat exchange with the medium.** A sphere at `T_cell` in a quiescent medium at `T_∞` conducts (Nu = 2 for a sphere in still fluid, exact in the Stokes limit):

```
Q = 4π · k_water · a · (T_cell − T_∞)          [W, positive = cell loses heat]
  = 3.7573e-5 · ΔT   W/K
```

Reference values: at `T_∞` = 20 °C, `Q = 2.871 mW`; at 37 °C, 2.232 mW; at 90 °C, 0.241 mW.

**Bidirectional coupling to the energy store** [CANON, REF §1.4]:

```
if (awake) {
  if (Q > 0)  energy −= Q·dt          // cell is hotter than medium: SPEND stored energy to hold setpoint
  else        energy += (−Q)·dt       // medium is hotter: ABSORB excess heat as neutrino mass (perfect sink)
  energy = clamp(energy, 0, energyMax)
  if (energy == 0) → cell dies (§4.11)         // starved; can no longer hold setpoint
}
// The equal and opposite +Q·dt / −Q·dt is deposited into the temperature field at the cell's cell (§4.10).
```

**Why P2 emerges:** `Q → 0` as `T_∞ → 96.415 °C`. The medium asymptotes to the setpoint and stops there. Since 96.415 °C < 100 °C, a live culture **cannot boil water at 1 atm**, ever. And if you externally drive the medium above the setpoint, `Q` flips sign, cells absorb the excess, and the medium is dragged back to 96.415 °C. The slide is pinned. This is an *emergent* consequence of a canon number that Weir chose for an unrelated reason (a proton-collision neutrino-pair calculation, [REF §1]) — do not shortcut it with a special case.

**Endurance** (emerges): 1.5 MJ at 2.871 mW = **16.6 years** of holding setpoint in 20 °C water. Astrophage in a cold slide is in no hurry.

**Thermal halo** (emerges from the field solve, verify in tests): steady-state around an isolated cell is `T(r) = T_∞ + ΔT·a/r`, giving +38.2 K at r=2a, +15.3 K at 5a, +7.6 K at 10a — a ~50 μm visible halo in the thermal view.

### 4.7 Petrova emission and the drive cycle

**Emission is a discrete quantum line, not thermal blackbody** [CANON, REF §1.4]. Do not compute it from Planck's law. (For contrast, the cell's *thermal* blackbody peak at 369.565 K is Wien λ_max = **7.84 μm** — a completely different band. This distinction is why the sim needs *two* IR view modes, §7.4.)

**Discharge triggers.** A cell sets `emitPower > 0` when any of:

| Trigger | Behavior | Canon |
|---|---|---|
| **Thrust-to-move** | Emits opposite to desired travel; power from the taxis controller (§4.8) | [REF §1.5] "toot to scoot" |
| **Thermostat deficit** | Not an emission — energy leaves as heat, not photons (§4.6) | |
| **Spin-drive flash** | External high-intensity pulse at `petrova.wavelength` forces full-rate discharge along `−d̂` where `d̂` faces the slide | [REF §2.4] |
| **Death rupture** | Optional: dump remaining store as a flash (§4.11), default OFF | invented |

**Physics** [REAL]:
```
F_thrust = P_emit / c                      thrust from radiated power
dE/dt    = −P_emit                         store depletes
photons/s = P_emit / petrova.photonEnergy  (for the photon-count HUD)
```

Reference thrust responses in 20 °C water (terminal velocity `v = F/γ`):

| P_emit | Force | Terminal speed | Crosses a 550 μm FOV in |
|---|---|---|---|
| 1 mW | 3.336e-12 N | 35.3 μm/s | 15.6 s |
| 10 mW | 3.336e-11 N | 353 μm/s | 1.56 s |
| 47.6 mW | 1.618e-10 N | 1681 μm/s | 0.33 s |

**47.6 mW is exactly the power a fully-charged cell needs to hover** against its own 32,000 kg/m³ weight. That coincidence is the reason `petrova.maxPower` defaults to 50 mW — it puts "can just barely hold itself up when full" at the top of the dial, which is both dramatically and pedagogically ideal. `[INVENTED]` — canon never states a discharge rate.

**Directionality.** Emission is a cone of half-angle `petrova.beamHalfAngle` about `d̂`. For rendering, draw the lobe. For the irradiance field (§4.10), deposit into the field only within the cone.

**Emission direction control.** `d̂` slews toward the taxis-commanded direction at `petrova.slewRate` `[INVENTED, 1.0 rad/s]` — cells cannot instantly reverse.

### 4.8 Taxis: light-seeking and CO₂-seeking

Canon [REF §1.5]: Astrophage moves toward light/heat to feed, follows the CO₂ lines at 4.26/18.31 μm to find breeding grounds, and **does not move in darkness**.

A three-state behavior controller, evaluated each biology tick:

```
if (irradiance_local < darkThreshold && co2Grad ≈ 0)   → IDLE      (no emission; drift only)  [CANON: "does not move in darkness"]
else if (charge < seekFeedBelow)                        → FEED      (climb ∇irradiance)
else if (charge > seekBreedAbove && co2 available)      → BREED     (climb ∇co2)
else                                                    → IDLE
```

Defaults: `darkThreshold = 1e-3 W/m²`, `seekFeedBelow = 0.95`, `seekBreedAbove = 0.98` — all `[INVENTED]`, tunable.

**Gradient climbing.** Do **not** use a spatial finite difference across the cell body — a 10 μm cell in a 1.5 μm grid can barely resolve one. Use **temporal-comparison chemotaxis**, which is what real bacteria do and what produces the correct visual (a biased random walk, not a smooth glide):

```
Δ = signal_now − signal_lagged        (lagged by tauMemory = 2 s [INVENTED])
if (Δ > 0)  keep heading, extend run
else        tumble: rotate d̂ by a random angle, reset run timer
emitPower = petrova.maxPower · taxisGain · clamp01(demand)
```

This gives run-and-tumble migration up gradients. It is cheap (no gradient sampling), robust to noise, biologically defensible, and looks unmistakably alive.

**Feeding.** A cell absorbs *all* incident radiation (albedo 0):
```
P_absorbed = irradiance_local · π·a²        (geometric cross-section, 7.854e-11 m²)
energy += P_absorbed · dt                   clamped to energyMax
```
Note `π·a²` not `4π·a²` — a sphere in a collimated beam presents its projected disc. Under isotropic illumination use `4π·a²`; the field (§4.10) tracks both a directional and an ambient component, so use `π·a²·E_directional + 4π·a²·E_ambient`.

### 4.9 Contact, crowding, and adhesion

A soft-sphere pair repulsion; the only cell–cell mechanical interaction.

```
for pairs with d < 2a:
  overlap = 2a − d
  F = k_contact · overlap · r̂        k_contact = 1e-6 N/m  [INVENTED, tuned so overlap < 5% at rest]
```

Damped by the ambient OU drag; no separate contact damping term needed. Neighbor search by uniform spatial hash, cell size `2.2a` (§6.4).

**Adhesion:** on `z`-wall contact, stick with probability `wall.stickiness` `[INVENTED, 0.15]`; a stuck cell has drag multiplied by `wall.stuckDragMult = 20` until its thrust exceeds `wall.releaseForce`. Reproduces the real microscopy look of a settled monolayer.

### 4.10 Fields

Four scalar/vector fields on regular grids over the `xy` plane (depth-averaged — this is the "quasi" in quasi-2D). All four are **read** by cells and **written** by cells, so ordering matters (§5.3).

| Field | Symbol | Grid | Diffusivity | Solver |
|---|---|---|---|---|
| Temperature | `T(x,y)` | 256² | 1.4325e-7 m²/s | **ADI implicit** |
| CO₂ concentration | `C(x,y)` | 128² | 1.92e-9 m²/s | explicit FTCS |
| N₂ concentration | `N(x,y)` | 64² | 2.0e-9 m²/s | explicit FTCS |
| Irradiance | `E(x,y)` | 256² | — (instantaneous) | ray accumulation |

**Why T needs an implicit solver — the single most important numerical fact in this spec.** At the default 256² grid over a 400 μm domain, `dx = 1.5625 μm`, and explicit FTCS stability requires

```
dt < dx²/(4α) = 4.247e-6 s
```

That is a **4.2 μs** timestep — 240× smaller than the 1 ms physics step. An explicit heat solve is a non-starter. Two facts make it tractable:
- Heat crosses the whole 400 μm FOV in `L²/α` = **1.12 s** — fast, but *not* instantaneous relative to cell motion, so a quasi-steady Poisson solve is also wrong.
- Therefore: **Peaceman–Rachford ADI**, unconditionally stable, two tridiagonal (Thomas-algorithm) sweeps per step, O(N) per sweep. ~1.5 ms for 256² in JS. This is the right and only answer.

CO₂ is 75× less diffusive: explicit stability limit is `3.17e-4 s`, so a plain FTCS with 4 substeps per 1 ms step is fine. Do not over-engineer it.

**Source terms.** Each cell deposits into the grid cell containing it, with bilinear scatter:
- into `T`: `+Q/(ρ·cₚ·V_gridcell)` K/s from §4.6 (positive when the cell is shedding heat, negative when absorbing)
- into `C`: `−(co2 uptake rate)`
- Taumoeba deposit `+methane` (cosmetic) and consume nothing thermally.

**Boundary conditions.** Configurable per scenario: `dirichlet` (held at a bath temperature — a heated stage), `neumann` (insulated), or `robin` (convective loss to room air, `h = 10 W/(m²·K)` `[REAL]`). Default: `robin` on T, `neumann` on C and N.

**Irradiance field and P5.** This is what makes absolute shadows work. For each of `nLightSources` directional sources:
1. Rasterize each cell's opaque disc into an *occlusion* buffer along the light direction.
2. March the irradiance grid along the light direction, attenuating to **exactly zero** behind any occluder (albedo = 0 — no transmission, no scattering, per canon "super cross-sectionality" [REF §1.2]).
3. Add an `ambient` term that is not occluded (models multiply-scattered room light).

A 1D running-occlusion sweep along the light axis is O(grid) and sufficient. Dead cells attenuate by `1 − albedoDead` instead of fully — so a field of corpses is translucent and a field of live cells is jet black. That contrast *is* the microscopy.

### 4.11 Death, corpses, and the energy question

**Death conditions:**
1. `energy == 0` while `awake` — starvation. Cannot hold setpoint.
2. Engulfed by Taumoeba (§4.12).
3. `tempCell > cell.lethalTemp` `[INVENTED, 573 K]` — a "torch the slide" escape hatch.

**On death:** `alive = 2`, `albedo → albedoDead` (translucent, per [REF §4]), emission stops, all taxis stops, thermostat disengages, `tempCell` relaxes to `T_local`. The corpse persists and is rendered — a field of dead Astrophage is visually distinct and diagnostically important.

**Where does the stored energy go?** Canon does not say. This is §15-D3, and it is exposed as a three-way scenario toggle:

| Mode | Behavior | Consequence |
|---|---|---|
| `void` **(default)** | `energy → 0` silently | Canon-lite. Nothing explodes. |
| `flash` | Discharge as Petrova photons over `1 ms` | Physically conserving and spectacular. A full cell = 358.5 g TNT. See the warning below. |
| `retain` | Store persists as inert ballast in the corpse | Corpses stay 32,000 kg/m³ and rain to the coverslip |

**Energy-scale warning (put this in the UI).** 1.5 MJ per cell is not a metaphor. A single fully-charged cell holds **358.5 g TNT equivalent**. A modest 5,000-cell field holds **7.50 GJ = 1.79 tonnes of TNT** — inside a droplet. The HUD carries a permanent `TOTAL STORED ENERGY` readout in J / kg-TNT / equivalent-mass. In `flash` mode, a mass death event triggers a scripted **CONTAINMENT FAILURE** end-state rather than pretending a microscope slide survives it. Being honest about this is more interesting than ignoring it, and it is the single best intuition-pump for why the Hail Mary's 2,000,000 kg of fuel is terrifying.

### 4.12 Taumoeba

An agent with its own small store (`TaumoebaStore`, same SoA pattern).

- **Motion:** persistent random walk at `crawlSpeed`, biased up the Astrophage-density gradient (same run-and-tumble as §4.8, sensing local cell count). Larger and heavier than Astrophage; same OU integrator, its own `γ` from its radius.
- **Predation:** on overlap with a live Astrophage, engulf. Cell → dead (§4.11). Taumoeba enters `digesting` for `digestTime`, gains `biomass += astrophage.biomass·yield`, emits methane into a cosmetic field. Per [REF §5], it consumes **only the chemical/biomass energy** — the neutrino store is handled by the §4.11 toggle, and `void` is the canon-consistent default.
- **Nitrogen sensitivity** [CANON, REF §1.8]: each tick, `hazard = max(0, N_local − n2LethalConc·(1 + tolerance·k))`; die with probability `1 − exp(−hazard·rate·dt)`. `tolerance ∈ [0,1]` is the heritable trait.
- **Reproduction & evolution:** divide when `biomass ≥ 2×` initial. Daughter inherits `tolerance + N(0, mutationSigma)`, clamped to [0,1]. Under a nitrogen gradient this reproduces the **Taumoeba-82.5 breeding arc** [REF §1.8] as genuine directional selection — the scenario in §9.6.

---

## 5. Numerical architecture

### 5.1 Fixed timestep with accumulator

```
dtPhysics   = 1e-3 s        // fixed, never varies with frame rate
maxSubsteps = 8             // spiral-of-death guard; drop time rather than lag
```

Render interpolates positions between the last two physics states (`alpha` blend) so motion is smooth at any frame rate.

### 5.2 Multi-rate clock — the hardest UX problem in this simulator

The processes span **nine orders of magnitude**:

| Process | Characteristic time |
|---|---|
| Momentum relaxation (empty cell) | 2.2e-7 s |
| Full-cell sedimentation across FOV | 0.33 s |
| Brownian excursion of one diameter | ~60 s |
| Thermal equilibration across FOV | 1.12 s |
| Mitosis cycle | 6.9e5 s (8 days) |
| Culture 1 → 10,000 cells | 9.2e6 s (106 days) |

You cannot show Brownian motion and cell division on the same clock. **Do not solve this with a single global time-scale slider** — at 10⁶× the integrator explodes; at 1× nothing ever divides.

**Solution: decoupled process rates.** Two independent multipliers, both exposed:

```
physicsRate  ∈ [0.1, 100]      // scales dtPhysics; motion, heat, thrust
biologyRate  ∈ [1, 1e6]        // scales ONLY division/growth/digestion clocks (log slider)
```

Biology is a slow, non-stiff, purely-local process — scaling its rate is numerically free and physically meaningful (it is exactly "imagine this culture were 10⁶× faster"). Physics is stiff and must stay near 1×.

**Named presets** drive both at once and are the primary UI control:

| Preset | physicsRate | biologyRate | What you watch |
|---|---|---|---|
| **Realtime** | 1 | 1 | Brownian jitter, thrust, honest microscopy |
| **Motion** | 10 | 1 | Sedimentation, taxis, migration |
| **Metabolic** | 1 | 1e4 | Charging, thermal equilibrium, feeding |
| **Generational** | 0.5 | 1e6 | Division, population curves, evolution |

The HUD **always** shows both multipliers and the elapsed simulated time in real units ("14.2 days of culture time"). Never let the user lose track of what clock they're on.

### 5.3 Step ordering

Order matters — fields are read and written in the same step. Fixed sequence, do not reorder:

```
1. FIELDS.readback      sample T, C, N, E at every agent position (bilinear)
2. AGENTS.think         taxis state machine; set emitPower, d̂, demand      (biologyRate-scaled)
3. AGENTS.thermal       compute Q; move energy; accumulate field sources
4. AGENTS.forces        gravity/buoyancy, thrust, contact
5. AGENTS.integrate     OU velocity update, position update, boundaries
6. FIELDS.scatter       deposit accumulated sources into grids
7. FIELDS.diffuse       ADI for T; substepped FTCS for C, N
8. FIELDS.irradiance    occlusion sweep + ray accumulation (rebuild from scratch)
9. AGENTS.lifecycle     division, death, predation, spawn/free  (biologyRate-scaled)
10. EVENTS.emit         push events to the ring buffer for the UI
```

Steps 1–5 are trivially parallel over agents. Step 7 is the ADI sweep. Step 9 mutates the store and must be last.

### 5.4 Determinism

Non-negotiable — §11 depends on it.

- **PCG32, one stream per cell**, seeded `seed_global ⊕ hash(cell.id)`. This is why `rngState` is per-cell rather than a single global generator: with a global RNG, adding or removing one cell shifts every subsequent cell's random draws and destroys reproducibility across any run where a division happens. Per-cell streams make the trajectory invariant to population changes.
- **Daughter seeding on division:** `daughter.rngState = pcg_split(parent.rngState, daughter.id)`.
- **No `Math.random()` anywhere** in `sim/` or `core/`. Lint rule enforces it.
- **No wall-clock reads** in the sim. Time is `stepIndex × dtPhysics`.
- **Stable iteration order:** always iterate the SoA by index. Never iterate a `Set`/`Map` in the hot path.
- **Float determinism:** JS `Math.exp`/`Math.sqrt` are not bit-identical across engines. Accept cross-engine drift; guarantee determinism *within* one engine. Tests use tolerances (§11), not bit equality.

---

## 6. Software architecture

### 6.1 Repository layout

```
astrophage-scope/
  spec.md                        ← this document
  compass_artifact_*.md          ← canon research source
  package.json  tsconfig.json  vite.config.ts  vitest.config.ts
  index.html
  src/
    core/
      canon.ts                   § 3 parameter table, with provenance
      constants.ts               universal physical constants
      units.ts                   branded unit types + display conversion
      params.ts                  Param<> type, override/lock machinery
      rng.ts                     PCG32, splitting, gaussian (Box–Muller, cached pair)
      math.ts                    vec3, clamp, bilinear sample, Thomas solver
    sim/
      world.ts                   World: owns stores + fields + clock
      cellStore.ts               SoA + free list + capacity growth
      taumoebaStore.ts
      integrator.ts              § 4.4 OU update
      thermal.ts                 § 4.6
      emission.ts                § 4.7
      taxis.ts                   § 4.8
      contact.ts                 § 4.9 + spatial hash
      lifecycle.ts               § 4.11 division / death
      predation.ts               § 4.12
      fields/
        grid.ts                  Grid2D<Float64Array>, bilinear sample/scatter
        heat.ts                  ADI (Peaceman–Rachford)
        diffusion.ts             explicit FTCS, substepped
        irradiance.ts            § 4.10 occlusion sweep
      step.ts                    § 5.3 ordering
      events.ts                  ring buffer of SimEvent
      snapshot.ts                serialize / restore
    worker/
      sim.worker.ts              owns World; runs the loop
      protocol.ts                § 6.3 message types
    render/
      gl.ts                      WebGL2 context, extension checks
      passes/
        cells.pass.ts            instanced SDF discs
        taumoeba.pass.ts         instanced blobs
        field.pass.ts            grid → texture, LUT
        petrova.pass.ts          additive emission lobes
        bloom.pass.ts            downsample/upsample bloom chain
        optics.pass.ts           defocus, diffraction ring, vignette, condenser
        compose.pass.ts          view-mode mix
      viewModes.ts               § 7.4
      luts.ts                    § 7.5 color lookup tables
      camera.ts                  pan/zoom/focal-plane
    ui/
      store.ts                   tiny reactive store (~4 kB, no framework)
      layout.ts
      panels/
        instrument.panel.ts      Petrovascope / spectrometer / thermometer / microbalance
        inspector.panel.ts       clicked-cell readout
        params.panel.ts          § 8.4 with provenance badges
        scenario.panel.ts
        chart.panel.ts           population, energy, temperature time series
      hud.ts                     clock, counts, energy ledger
    scenarios/
      *.scenario.json            § 9
      loader.ts  schema.ts
    main.ts
  test/
    physics/*.test.ts            § 11
    fixtures/
```

### 6.2 Threading

- **Main thread:** UI, WebGL rendering, input. Never runs physics.
- **Worker:** owns the `World`. Runs the fixed-step loop.
- **Transfer:** `SharedArrayBuffer` for the agent SoA and field grids when cross-origin isolation is available (requires COOP/COEP headers — set them in `vite.config.ts`), with a **transferable double-buffer fallback** when it is not. Do not assume SAB; the fallback path must exist from M0 or it will never be added.
- **Rendering reads the shared buffers directly** and uploads to GPU. No per-frame serialization.
- **Event ring buffer** (`Int32Array` header + payload) carries discrete events (division, death, ignition, engulfment) to the UI without allocation.

### 6.3 Worker protocol

```ts
// main → worker
type Command =
  | { t: 'load';    scenario: Scenario; seed: number }
  | { t: 'play' } | { t: 'pause' } | { t: 'stepOnce' }
  | { t: 'rates';   physics: number; biology: number }
  | { t: 'param';   path: string; value: number }         // live canon override
  | { t: 'poke';    kind: PokeKind; x: number; y: number; r: number; strength: number }
  | { t: 'snapshot' } | { t: 'restore'; blob: ArrayBuffer };

// PokeKind — the direct-manipulation verbs (§8.3)
type PokeKind = 'heat' | 'chill' | 'illuminate' | 'injectCO2' | 'injectN2'
              | 'seedCells' | 'seedTaumoeba' | 'kill' | 'chargeBeam';

// worker → main
type Report =
  | { t: 'ready';  layout: BufferLayout }
  | { t: 'tick';   step: number; simTime: number; stats: Stats }  // ~30 Hz, not per step
  | { t: 'events'; count: number }
  | { t: 'snapshot'; blob: ArrayBuffer };
```

### 6.4 Spatial hash

Uniform grid, cell size `2.2 × cell.diameter` (22 μm). Rebuilt every step (cheap: one counting-sort pass, O(n), no allocation after warm-up). Used by contact (§4.9), predation (§4.12), and the taxis density sense.

### 6.5 Testability rule

Every module in `sim/` exports **pure functions over explicit state**. `World` is a plain data object. No module holds hidden mutable state, no singletons, no `this`-bound closures over simulation data. This is what makes §11 possible — every test constructs a two-cell world and calls one function.

---

## 7. Rendering architecture

### 7.1 The look

This must read as **microscopy**, not as a particle toy. The difference is entirely in the optics model (§7.3): a real 40×/0.65 objective has a **1.53 μm depth of field** inside a **20–120 μm slab**, so at any moment most cells are visibly out of focus, and racking focus is a primary interaction. Get that right and the rest follows.

### 7.2 Pipeline

```
[cells → occlusion buffer]  →  [irradiance texture]
[fields → R32F textures]    →  [field pass, LUT-mapped]        ┐
[cells → instanced quads, SDF disc, per-instance defocus]      ├→ [compose] → [bloom] → [optics FX] → screen
[petrova lobes, additive]                                      ┘
```

All cell geometry is a **single instanced draw**: one unit quad, per-instance `(x, y, z, radius, charge, awake, alive, emitPower, dirX, dirY)` packed into two `vec4` attribute streams from a `Float32Array` in micrometres. 50,000 cells = 1 draw call.

The disc is an **SDF in the fragment shader**, so cells are perfect circles at any zoom and cost nothing extra when small.

### 7.3 Microscope optics model

Per-instance in the vertex/fragment shader:

**Objective presets** (verified in §14):

| Preset | M | NA | Resolution (λ=550 nm) | DOF | FOV | Cell spans |
|---|---|---|---|---|---|---|
| Survey | 10× | 0.25 | 1342 nm | 11.20 μm | 2200 μm | 7 resel |
| **Working (default)** | 40× | 0.65 | 516 nm | **1.53 μm** | 550 μm | 19 resel |
| Detail | 100× oil | 1.25 | 268 nm | 0.61 μm | 220 μm | 37 resel |

**Defocus.** Circle-of-confusion radius from the cell's distance to the focal plane:
```
r_coc = |z − z_focus| · NA / n          (geometric; adequate and cheap)
```
At Δz = 10 μm with NA 0.65 that is a 6.5 μm blur radius — larger than the cell. Correct and important: it is exactly what a real slide looks like.

Implement as a **per-instance quad expansion** (grow the quad by `r_coc`, and in the fragment shader convolve the disc SDF with a Gaussian of that radius analytically — `smoothstep` over the SDF with width `r_coc` is a good approximation). This is far cheaper than a screen-space depth-of-field pass and is correct per-object, which matters because cells overlap in projection.

**Diffraction ring.** In focus, an opaque disc shows a bright Becke line just outside its edge and a dark ring just inside. Approximate with two `smoothstep` bands on the SDF, amplitude scaled by `(1 − r_coc/a)`. Cheap; enormously increases the "this is a microscope" read.

**Defocus asymmetry.** Above and below focus, the ring pattern inverts (bright halo vs dark halo). Use `sign(z − z_focus)` to flip the band polarity. Almost free, and it's the cue that lets a viewer tell which way to rack the focus.

**Condenser / illumination:** subtle radial vignette + slight chromatic warm-shift at the field edge.

### 7.4 View modes

Five modes, cross-fadeable with a slider (not a hard cut) so the user can see correspondence. **Mode switching is the core verb (pillar 3).**

| Mode | Background | Cells | Shows |
|---|---|---|---|
| **Brightfield** | bright warm white | pure black discs, diffraction ring; corpses translucent grey | what a human sees. Charge state invisible. |
| **Darkfield** | black | bright edge-scattering rings | classic microscopy; live/dead contrast |
| **Petrovascope** | pure black | magenta emission lobes only; non-emitting cells **invisible** | 25.984 μm band. The canon instrument. |
| **Thermal IR** | deep blue/black | glow by `tempCell`, plus the halo from the T field | 7.84 μm blackbody band. **Different from Petrovascope** — a live idle cell glows in thermal but is dark in Petrova. |
| **Analysis** | dark grey | flat discs colored by a selectable channel (charge / temp / age / mass / awake) | the honest scientific view |

**Overlays** (independently toggleable on any mode): T field, CO₂ field, N₂ field, irradiance field, velocity vectors, spatial-hash grid, per-cell trajectory trails, scale bar.

The Thermal-vs-Petrovascope distinction is scientifically real and is the sim's best teaching moment: it makes visible that the Petrova line is a **discrete quantum annihilation line, not thermal emission** [REF §3.3] — a cell can be blazing hot and Petrova-dark, or cool-store-depleting and Petrova-bright.

### 7.5 Color

| LUT | Use | Values |
|---|---|---|
| `petrova-film` **(default)** | Petrovascope | core `#FF2D95` → mid `#C4187A` → falloff `#3D0620`. Matches the 2026 film's pink/magenta grade [REF §4]. |
| `petrova-false-ir` | Petrovascope, alt | deep red `#C4000A` → `#2A0000`. The conventional false-color-IR convention. |
| `magma` | Thermal IR, analysis | perceptually uniform, colorblind-safe |
| `viridis` | field overlays | perceptually uniform |
| `brightfield` | brightfield | `#F5F0E6` background, `#050505` cells |

Every LUT is generated from a 256-entry table in `luts.ts`, uploaded as a 1D texture. Provide a global colorblind-safe toggle that swaps `petrova-film` for `magma`.

**Bloom** on Petrova emission only — a 4-level downsample/upsample chain, threshold at 0.6, intensity tied to `emitPower`. This is what sells the "swirling pink points of light" [REF §4].

### 7.6 Non-negotiable rendering details

- **A scale bar, always.** Bottom-right, snapping to 10/20/50/100/200/500 μm. This is a microscope.
- **Cells are drawn at true relative size.** No "make them bigger so you can see them" fudge. The 10 μm cell against the 550 μm field is the point.
- **Sub-pixel cells still render.** At the Survey objective a cell is ~2 px; clamp minimum rendered radius to 0.75 px and modulate alpha by the area ratio so density stays honest instead of aliasing away.

---

## 8. UI / UX specification

### 8.1 Layout

```
┌──────────────────────────────────────────────┬────────────────┐
│                                              │  INSTRUMENTS   │
│                                              │  ├ view mode   │
│              VIEWPORT                        │  ├ objective   │
│         (microscope field)                   │  ├ focal plane │
│                                              │  └ overlays    │
│                                              ├────────────────┤
│                                              │  INSPECTOR     │
│  [scale bar]              [focus indicator]  │  (clicked cell)│
├──────────────────────────────────────────────┤                │
│ HUD: t=14.2 d │ 4,812 cells │ 61% chg │ 96.4°C │ 2.1 GJ ⚠   ├────────────────┤
├──────────────────────────────────────────────┤  PARAMETERS    │
│ ▶ ⏸ ⏭  [Realtime|Motion|Metabolic|Generational]│  (provenance) │
│ TOOLS: 🔥 ❄ 💡 CO₂ N₂ ✚cell ✚tau ☠ ⚡          ├────────────────┤
└──────────────────────────────────────────────┤  CHARTS        │
                                               └────────────────┘
```

### 8.2 The HUD is always honest

Permanently visible: simulated time **in real units** (never just "t=14200"), live/dead counts, mean charge, medium temperature, and the **total stored energy ledger** in J and TNT-equivalent with a warning icon past 1 GJ. Plus a `NON-CANON RUN` badge whenever any `CANON` param has been unlocked.

### 8.3 Direct manipulation

Every tool is a brush: click-drag paints into a field or spawns agents. Radius and strength on the scroll wheel.

| Tool | Effect |
|---|---|
| 🔥 Heat | add W/m³ to `T`. **This is how you trigger ignition (P3).** |
| ❄ Chill | remove heat; watch the thermostat fight back (P2) |
| 💡 Illuminate | move/aim the directional light source; watch shadows (P5) |
| CO₂ / N₂ | inject concentration |
| ✚ cell / ✚ tau | seed agents with a charge distribution |
| ☠ Kill | mark cells dead in radius |
| ⚡ Charge beam | Dimitri's 1 kW laser [REF §1.3] — a collimated beam; §9.3 |

### 8.4 Parameter inspector with provenance

Every `Param` from §3 rendered as a row: **name · value · unit · provenance badge · lock**.

- `CANON` — gold badge, locked. Unlocking prompts once and sets the non-canon flag.
- `DERIVED` — blue badge, read-only, with the formula shown ("= massDry / V").
- `REAL` — grey badge, unlocked (it's a medium property; changing water viscosity is legitimate).
- `INVENTED` — orange badge, unlocked, freely tunable. Hovering shows *why* it's invented and what canon does/doesn't say.

This turns the honest bookkeeping of the research document into an interactive feature and is a genuine differentiator: the user can always see which numbers Weir wrote and which we made up.

### 8.5 Cell inspector

Click a cell → follow it. Live readout of: id, age, charge (J and %), stored mass (ng), total mass, **density and buoyancy state ("SINKING — 32,000 kg/m³, 31× water")**, temperature, awake/dormant, emission power and direction, biomass, CO₂ held, and time-to-division. Plus a sparkline of charge over the last 60 s.

The density/buoyancy line is the thing that teaches **P1**. Make it prominent.

### 8.6 Charts

Time series, scrubable, CSV-exportable: population (live/dead, log axis), mean & total stored energy, medium temperature, CO₂ concentration, Taumoeba population and mean nitrogen tolerance (the evolution readout for §9.6).

---

## 9. Scenarios

Scenarios are data (§10.1). Each defines initial conditions, boundaries, tools available, an objective, and **acceptance criteria** that double as integration tests.

### 9.1 `first-light` — Ignition *(the tutorial and the demo)*
Room-temperature slide, 400 μm FOV, 800 dormant cells at 0% charge, no light.
**Beat:** In Brightfield the field is dead black dots doing nothing. Switch to Petrovascope: nothing. Apply the heat brush past 96.415 °C — the culture **wakes**, and the Petrovascope fills with magenta. Now chill the slide: the cells hold 96.415 °C anyway (**P3**, **P2**).
**Accept:** all cells `awake` within 5 s of crossing setpoint; medium equilibrates to 369.565 ± 0.5 K and stays; zero boiling events.

### 9.2 `the-three-percent-line` — Buoyancy *(teaches P1)*
Awake cells with charge uniformly distributed 0–10%. Gravity along −y. No light.
**Beat:** The field **sorts itself vertically**. Cells below 3.006% charge rise; above, they sink. A sharp band forms at the neutral line. Then illuminate: charging cells cross the line one by one and rain downward.
**Accept:** after 60 s, mean charge of cells in the top third < 3.006% < mean charge of the bottom third; measured empty-cell rise velocity −52.1 ± 3 μm/s; full-cell fall +1681 ± 60 μm/s.

### 9.3 `komorov` — The 1 kW laser *(the canonical experiment, [REF §1.3])*
A single cell on a microbalance. Charge beam at 1 kW for 25 min.
**Beat:** Watch the microbalance readout climb from 0.021 ng to 16.71 ng. This is Dimitri's experiment, reproduced.
**Accept:** after 1500 s at 1 kW absorbed, `energy = 1.5 MJ ± 0.1%` and `Δmass = 16.69 ng ± 0.1%`. This is a direct canon-consistency check and the single most important scenario in the build.
**Note:** at 1 kW the cell absorbs its 1.5 MJ cap in 1500 s only if it absorbs *all* the beam. With the geometric cross-section π·a² = 7.854e-11 m², a 1 kW beam must be focused to a ~10 μm spot (1.27e13 W/m²) for this to work. The scenario sets that up explicitly and the beam-spot readout makes the geometry visible — an honest detail the novel skips.

### 9.4 `shadow-garden` — Absolute shadows *(teaches P5)*
Dense culture, 12,000 cells, single collimated light source, `Illuminate` tool aimable.
**Beat:** A lit monolayer forms at the light-facing surface; everything behind is in perfect darkness and never charges. Rotate the light and watch the population re-sort. Self-shading is total, because albedo is exactly 0.
**Accept:** cells with `irradiance < 1e-3 W/m²` show `dCharge/dt = 0`; the charged fraction correlates with depth along the light axis at r < −0.8.

### 9.5 `bloom` — Population dynamics
CO₂-saturated medium, warm, well-lit, 10 starting cells, `Generational` clock.
**Beat:** Exponential growth. The chart's log axis goes straight. CO₂ is consumed; growth stalls when it runs out; add more and it resumes. Watch the culture go black.
**Accept:** population fits `N(t) = N₀·2^(t/8d)` within 5% while CO₂ is non-limiting; growth halts within 1 doubling of CO₂ exhaustion.

### 9.6 `taumoeba` — Predation and the 82.5 problem
Established culture; introduce 20 Taumoeba; then apply a nitrogen gradient.
**Beat:** The predator crashes the population. Introduce nitrogen — the Taumoeba die where N₂ is high, and Astrophage recovers in the nitrogen-rich zone. Then raise nitrogen slowly over generations, and watch the mean tolerance trait climb under selection until a nitrogen-resistant strain emerges. **That's Taumoeba-82.5**, arrived at by actual directional selection rather than by script [REF §1.8].
**Accept:** mean `tolerance` increases monotonically (5-generation moving average) under a slowly-rising N₂ ramp; a strain with `tolerance ≥ 0.825` appears within 40 generations at default `mutationSigma`.

### 9.7 `spin-drive-face` — One drive face, under the microscope
The one place the ship intrudes, and it belongs here because a spin drive is a **cell-scale machine** [REF §2.4]. The view is a single triangular face of one of the 1,009 drives, seen through the microscope. The three-phase cycle runs on a loop:
1. **Attract** — low-intensity IR at 4.26/18.31 μm at the face; cells migrate to it via CO₂-line taxis (§4.8)
2. **Rotate** — the face turns to face vacuum
3. **Flash** — a high-intensity 25.984 μm pulse forces full discharge against the slide; momentum transfers; the Petrovascope whites out
4. **Scrape** — spent cells are cleared, and the cycle repeats

**Beat:** you see, at cell scale, the actual mechanism that pushes a 2,100,000 kg starship. The HUD shows accumulated impulse per cycle.
**Accept:** total impulse per cycle = `Σ(E_discharged)/c` within 1%; no cell retains energy after a flash; the cycle is stable over 100 iterations.

### 9.8 `sandbox` — Everything unlocked
All tools, all params, no objective. The scenario people will spend the most time in.

---

## 10. Data formats

### 10.1 Scenario JSON

```jsonc
{
  "$schema": "./schema.json",
  "id": "first-light",
  "title": "First Light",
  "blurb": "A cold slide of inert black powder. Until you heat it.",
  "teaches": ["P3", "P2"],
  "seed": 20260802,

  "domain": { "w": 400e-6, "h": 250e-6, "d": 40e-6,
              "boundary": { "x": "reflecting", "y": "reflecting" } },

  "medium": { "kind": "water", "tempInit": 293.15, "co2Init": 0.0, "n2Init": 0.0,
              "thermalBC": "robin", "ambientTemp": 293.15 },

  "light": { "sources": [], "ambient": 0.0 },

  "populations": [
    { "kind": "astrophage", "count": 800,
      "placement": { "mode": "uniform" },
      "charge": { "dist": "constant", "value": 0.0 },
      "awake": false }
  ],

  "clock": { "preset": "realtime" },

  "view": { "mode": "brightfield", "objective": "40x", "focalPlane": 0.0,
            "overlays": [] },

  "tools": ["heat", "chill", "illuminate", "seedCells"],

  "paramOverrides": {},

  "objective": {
    "text": "Wake the culture. Then try to cool it back down.",
    "accept": [
      { "metric": "awakeFraction",    "op": ">=", "value": 1.0,     "afterS": 5 },
      { "metric": "mediumTempMean",   "op": "~=", "value": 369.565, "tol": 0.5, "afterS": 120 },
      { "metric": "boilEventCount",   "op": "==", "value": 0 }
    ]
  }
}
```

The `accept` block is consumed both by the UI (objective checkmarks) and by the headless integration test runner (§11.4). **One definition, two consumers** — scenarios cannot silently rot.

### 10.2 Snapshot

Binary. Header (`magic 'ASPH'`, version, seed, stepIndex, counts, param-override table) followed by raw SoA buffers and field grids. Restores bit-identically within one engine. Used for save/load, for the time-scrubber, and for pinning regression-test fixtures.

### 10.3 Telemetry export

CSV, one row per sampled step: `t_s, nLive, nDead, nTau, meanCharge, totalEnergy_J, meanTempCell_K, meanTempMedium_K, co2Total_kg, meanTolerance, boilEvents, divisions, deaths`. Header comments record the seed, scenario id, spec version, and every broken canon lock.

---

## 11. Acceptance test suite

**If these pass, the physics is right.** Every expected value below is verified in §14. Vitest, headless, no GPU. Tolerances are stated because JS transcendental functions are not bit-portable.

### 11.1 Analytic single-body tests

| # | Test | Setup | Expected | Tol |
|---|---|---|---|---|
| **T1** | Stokes settling, full cell | 1 cell, charge = 1.0, no noise (`kB=0`), no thrust | terminal `vy = +1681.0 μm/s` | 0.5% |
| **T2** | Stokes rise, empty cell | charge = 0, no noise | terminal `vy = −52.1 μm/s` | 0.5% |
| **T3** | Neutral buoyancy | solve for zero terminal velocity | `charge = 3.006 %` (`E = 4.509e4 J`) | 0.1% |
| **T4** | Einstein diffusion | 1 cell, no forces, T = 293.15 K, 10⁵ steps × 1 ms, 200 realizations | 2D MSD = 4·D·t with `D = 4.2858e-14 m²/s`; RMS at t=1 s = 0.414 μm | 3% (stochastic) |
| **T5** | Mass–energy ledger | charge 0 → max | `Δm = 1.669e-11 kg`; `mass = biomass + E/c²` holds to machine precision every step | 1e-12 rel |
| **T6** | Photon thrust | P = 1 mW, no gravity, no noise | `F = 3.336e-12 N`, terminal `v = 35.32 μm/s` | 0.5% |
| **T7** | Conduction rate | awake cell, T_∞ = 293.15 K | `Q = 2.871 mW`; store drains in 16.6 yr | 0.5% |
| **T8** | Reynolds guard | at max terminal velocity | `Re = 0.0167 < 0.1` (assert Stokes regime is never violated) | — |

### 11.2 Emergent-phenomenon tests

| # | Test | Setup | Expected |
|---|---|---|---|
| **T9** (P2) | Thermostat asymptote | 2000 awake cells, insulated boundary, T₀ = 293.15 K | medium → 369.565 K ± 0.2 and **never exceeds 373.15 K**; `dQ/dt → 0` |
| **T10** (P2) | Sink mode | same, but drive medium to 400 K externally | cells absorb; medium returns to 369.565 ± 0.5 K; total cell energy increases |
| **T11** (P3) | Ignition latch | dormant cells, ramp T past setpoint then back to 293.15 K | 100% awake at crossing; still 100% awake and holding setpoint after cooling |
| **T12** (P4) | Live/dead motility | 500 live + 500 dead, same medium | live-cell MSD / dead-cell MSD > 3.5 over 60 s |
| **T13** (P5) | Total shadowing | 2 cells collinear with the light | rear cell `irradiance == 0` exactly; `dCharge/dt == 0` exactly |
| **T14** (P1) | Charge sorting | uniform charge 0–10%, 60 s | Pearson r between charge and −y position > 0.85 |

### 11.3 Canon-consistency tests

| # | Test | Expected |
|---|---|---|
| **T15** | Komorov (§9.3) | 1 kW × 1500 s absorbed ⇒ E = 1.5 MJ ± 0.1%, Δm = 16.69 ng ± 0.1% |
| **T16** | Photon energy | `hc/λ` at 25.984 μm = 7.6449e-21 J = 0.04772 eV ± 1e-4 |
| **T17** | Petrova frequency | 11.538 THz ± 0.01 |
| **T18** | Doubling | with non-limiting CO₂, population doubles in 6.912e5 s ± 2% |
| **T19** | Never boils | over every scenario in §9, `boilEventCount == 0` unless external heating exceeds 373.15 K |
| **T20** | Thermal ≠ Petrova | Wien λ_max at 369.565 K = 7.841 μm, distinct from 25.984 μm — assert the two view modes read different fields |

### 11.4 Determinism and integration

| # | Test | Expected |
|---|---|---|
| **T21** | Bit-reproducibility | same seed + scenario, 10⁴ steps, run twice ⇒ identical snapshot hash |
| **T22** | Division invariance | a run where cells divide reproduces exactly (validates per-cell RNG streams, §5.4) |
| **T23** | Snapshot round-trip | snapshot → restore → 1000 steps ≡ 1000 steps uninterrupted |
| **T24** | Scenario objectives | headless runner executes every `accept` block in every §9 scenario and asserts it passes |
| **T25** | ADI stability | 256² heat field, 10⁴ steps at dt = 1 ms with strong sources ⇒ no NaN, no oscillation, energy conserved to 0.1% under insulated BC |
| **T26** | No `Math.random` | lint/AST scan of `src/sim/**` and `src/core/**` |

### 11.5 Performance regression

| # | Test | Budget |
|---|---|---|
| **T27** | 20k cells, 1000 steps, headless | < 8 ms mean per step |
| **T28** | ADI 256² | < 2.0 ms per step |
| **T29** | Zero steady-state allocation | heap delta over 1000 steps ≈ 0 (no GC sawtooth) |

---

## 12. Performance budget

**Target: 60 fps with 20,000 Astrophage + 200 Taumoeba on 2020-era integrated graphics.**

| Stage | Budget/frame | Notes |
|---|---|---|
| Agent physics (20k) | 4.0 ms | SoA, no allocation, no virtual dispatch |
| Spatial hash rebuild | 0.5 ms | counting sort |
| Heat ADI (256²) | 1.5 ms | 2 Thomas sweeps |
| CO₂/N₂ FTCS | 0.5 ms | 128²/64², 4 substeps |
| Irradiance + occlusion | 1.0 ms | 1D sweeps |
| **Worker subtotal** | **7.5 ms** | 16.6 ms budget at 60 fps |
| GPU upload | 0.5 ms | 20k × 32 B = 640 kB |
| Render passes | 4.0 ms | 1 instanced draw + bloom chain |
| UI/DOM | 1.0 ms | throttle panels to 15 Hz |

**Scaling levers, in the order to reach for them:**
1. Drop field grids to 128²/64²/32².
2. Run biology lifecycle every 10th step (it's `biologyRate`-scaled anyway).
3. LOD: beyond 50k cells, render a density heatmap for off-focal-plane cells instead of instances.
4. Move the integrator to a WebGPU compute shader (the SoA layout is already GPU-ready — this was designed for).

**Hard rule: zero allocation in the steady-state step loop.** All scratch buffers preallocated at scenario load. T29 enforces it.

---

## 13. Milestones

Each milestone is independently demoable and ends with its tests green. Build strictly in order.

| M | Name | Deliverable | Done when |
|---|---|---|---|
| **M0** | Skeleton | Vite+TS+Vitest, `core/canon.ts` with the full §3 table, PCG32, deterministic empty loop, worker+SAB (and the fallback), brightfield renderer drawing static black discs, scale bar | T21, T26 pass; you can see 800 black dots |
| **M1** | Motion | OU integrator, buoyancy, contact, spatial hash, boundaries, full microscope optics (defocus, diffraction ring, focal-plane control, 3 objectives), cell inspector | **T1–T4, T6, T8, T14 pass. `the-three-percent-line` playable. P1 visible.** |
| **M2** | Thermal | Energy/mass coupling, dormancy latch, thermostat, conduction, heat ADI, T field + overlay, heat/chill brushes, Thermal-IR and Petrovascope view modes | **T5, T7, T9–T12, T19, T20, T25 pass. `first-light` playable. P2, P3, P4 all visible.** |
| **M3** | Light & thrust | Petrova emission + directionality + bloom, photon thrust, irradiance field with total occlusion, phototaxis run-and-tumble, charge beam | **T13, T15–T17 pass. `komorov` and `shadow-garden` playable. P5 visible. All five signature phenomena done.** |
| **M4** | Life | CO₂ field, chemotaxis, biomass, mitosis, death, corpses, multi-rate clock with presets, charts | T18 passes; `bloom` playable |
| **M5** | Predation | Taumoeba store, engulfment, N₂ field, lethality, heritable tolerance, evolution readout | `taumoeba` playable; the 82.5 strain emerges by selection |
| **M6** | Content & polish | Scenario loader + all 8 scenarios, objectives/acceptance UI, parameter inspector with provenance badges, snapshot/scrubber, CSV export, colorblind LUTs, `spin-drive-face` | **T24, T27–T29 pass. Ship.** |

**M3 is the meaningful "v1 feels real" line** — all five signature phenomena are live. M4–M6 add depth and content.

---

## 14. Verification appendix

Every derived number in this spec was computed and checked before writing. Reproduce with `scripts/derive.py`:

```
=== GEOMETRY / MASS ===
V                        = 5.2360e-16 m^3
rho_dry (canon mass)     = 40.1 kg/m3            ← 25x LIGHTER than water
m at water density       = 0.5227 ng             ← vs canon 0.021 ng (25x conflict, §15-D1)
m_store @1.5MJ           = 16.690 ng             ← canon says "~17 ng" ✓
rho_full                 = 31915 kg/m3  (32.0x water, denser than osmium)

=== NEUTRAL BUOYANCY (P1) ===
E_neutral                = 4.509e+04 J = 3.006 % of max

=== DRAG / DIFFUSION ===
gamma(20C)               = 9.4436e-08 kg/s
D(20C)                   = 0.0429 um2/s ; rms 2D disp in 1 s = 0.414 um
D(96.4C)                 = 0.1817 um2/s ; rms 2D disp in 1 s = 0.852 um    ← 4.2x, drives P4
tau_empty                = 2.224e-07 s
tau_full                 = 1.770e-04 s           ← 800x spread ⇒ OU integrator (§4.3)

=== SEDIMENTATION ===
empty (rho=40)           v = -52.1 um/s   (rises)
full  (rho=31915)        v = +1681.0 um/s (sinks)
Re at full-cell settling = 0.0167                ← Stokes valid ✓

=== PHOTON / THRUST ===
nu                       = 11.538 THz
E_photon                 = 7.6449e-21 J = 0.04772 eV
photons in 1.5 MJ        = 1.9621e+26
P=  1.00 mW -> F=3.336e-12 N, v_term =   35.32 um/s
P= 10.00 mW -> F=3.336e-11 N, v_term =  353.22 um/s
P to hover a FULL cell   = 47.59 mW              ← sets petrova.maxPower default

=== THERMAL ===
T_inf=20.0C -> Q=2.871 mW ; 1.5 MJ lasts 16.6 yr
T_inf=37.0C -> Q=2.232 mW ; 21.3 yr
T_inf=90.0C -> Q=0.241 mW ; 197.2 yr             ← Q -> 0 as T -> setpoint. This is P2.
halo: dT = +38.2K at r=2a, +15.3K at 5a, +7.6K at 10a
alpha_water              = 1.4325e-07 m2/s
diffusion time over 400 um = 1.117 s             ← not quasi-steady; needs a real solver
explicit-stable dt @dx=1.5625um (heat) = 4.247e-06 s   ← 240x too small ⇒ ADI (§4.10)
explicit-stable dt @dx=1.5625um (CO2)  = 3.169e-04 s   ← explicit is fine
1 uL, 1000 cells @2.87 mW: initial dT/dt = 687.8 K/s

=== OPTICS ===
10x/0.25       res=1342 nm  DOF=11.20 um  FOV=2200 um  cell spans  7 resel
40x/0.65       res= 516 nm  DOF= 1.53 um  FOV= 550 um  cell spans 19 resel
100x/1.25 oil  res= 268 nm  DOF= 0.61 um  FOV= 220 um  cell spans 37 resel

=== ENERGY LEDGER ===
1.5 MJ                   = 358.5 g TNT
5000 full cells          = 7.50 GJ = 1.793 t TNT
Wien lam_max @369.565K   = 7.841 um              ← distinct from 25.984 um (§7.4)
doubling 8 d: growth rate = 1.003e-06 /s ; 1 -> 1e4 cells takes 106.3 d
```

---

## 15. Decisions log

Read this before overriding anything above. Each entry is a real conflict in the source material, the decision taken, and what to do if you disagree.

**D0 — Two errors in the original brief, already corrected.** `96.415` is a **temperature in °C, not a frequency in THz**. The Petrova line is **25.984 μm (11.54 THz)**, not 3.11 μm / 96.415 THz. The 4.26/18.31 μm lines are the CO₂ bands Astrophage *navigates by*, not what it emits [REF §Key Findings 1]. Do not reintroduce these.

**D1 — Cell density conflict (the big one).** Canon says the cell is 10 μm across [REF §1.1], canon says it masses 0.021 ng [REF §1.1], and canon says it's mostly water [REF §1.1]. These three cannot all be true: 0.021 ng in a 10 μm sphere is **40 kg/m³**, 25× lighter than water. (Water density would require 0.523 ng.)
**Decision:** honor the two hard numbers (diameter, mass) and treat density as derived — so an empty cell is strongly buoyant. This is what generates **P1**, the most legible mechanic in the simulator, directly from canon numbers. The "mostly water" statement is treated as compositional, not densitometric.
**Escape hatch:** `medium.densityModel: 'canon-mass' | 'water-density'` as a scenario switch. Under `water-density`, `cell.massDry = 5.227e-13 kg`, empty cells are neutrally buoyant, and P1 becomes purely a sinking effect. Both are playable; `canon-mass` is default.

**D2 — Dormancy vs. constant temperature.** [REF §1.4] says the internal temperature is always 96.415 °C regardless of environment. [REF §1.7] says it's inert unless heated above 96.415 °C. Contradictory as written.
**Decision:** the **ignition latch** (§4.6). Dormant cells track ambient and do nothing; crossing the setpoint wakes them irreversibly; awake cells clamp to setpoint forever. Satisfies both statements and yields **P3**.

**D3 — Where does a dead cell's 1.5 MJ go?** Canon hand-waves this; Weir's stated resolution is only that Taumoeba consumes the chemical energy, not the neutrino store [REF §5].
**Decision:** three-way toggle (§4.11), default `void`. `flash` is physically conserving but detonates the slide, and is wired to an explicit CONTAINMENT FAILURE end-state rather than being silently absurd.

**D4 — Discharge rate is unstated.** Canon gives the *capacity* (1.5 MJ) but never a maximum emission power.
**Decision:** `petrova.maxPower = 50 mW` `[INVENTED]`, chosen so that maximum output ≈ the 47.6 mW needed for a full cell to hover. Tunable across 8 decades. Every downstream velocity in the sim depends on this number, so it is flagged loudly in the inspector.

**D5 — Gravity along −y, not −z.** Physically a microscope's optical axis is vertical, so sedimentation would go straight through the focal plane and be invisible.
**Decision:** model an inverted/side-mounted stage so buoyancy is in-plane and legible. `[INVENTED]`, disclosed in-UI, switchable to `gravityAxis: 'z'`.

**D6 — Temporal-comparison taxis over spatial gradients.** A 10 μm cell cannot meaningfully finite-difference a 1.5 μm grid across its own body, and a smooth gradient-glide looks like a video game.
**Decision:** run-and-tumble with a 2 s memory (§4.8). Cheap, robust, biologically real, and it *looks alive*.

**D7 — ADI for heat, explicit for CO₂.** Forced by the 75× diffusivity ratio (§4.10). Do not "unify" the solvers; you will either destroy performance or destroy stability.

**D8 — Decoupled physics/biology clocks.** A single time-scale slider cannot span 2.2e-7 s to 6.9e5 s. Two independent rates plus named presets (§5.2). Do not replace this with one slider, however much simpler it looks.

**D9 — Per-cell RNG streams.** Required for determinism across division/death (§5.4). A single global generator makes reproducibility impossible the moment population changes, which is every interesting run.

**D10 — Canon lives in data, not code.** No physics function may reference a canon literal. This is what makes the parameter inspector, the non-canon badge, and the `water-density`/`canon-mass` switch possible at all.

### Open questions (safe to defer past v1)

- **Q1** — Should awake cells *stay* awake if their energy hits zero and they die, or is death reversible by re-heating a corpse? Currently death is terminal. Canon is silent.
- **Q2** — Does Astrophage self-shadow at the CO₂ navigation wavelengths as absolutely as at visible ones? We assume yes (super-cross-sectionality is stated to be total). Affects the §9.7 attract phase in dense packs.
- **Q3** — Taumoeba size is entirely invented. If a canon figure surfaces, it changes predation rates and crawl dynamics.
- **Q4** — Should the medium's viscosity field respond to the local temperature field per-cell (currently yes, sampled bilinearly) or use a single bulk value (cheaper)? Per-cell is what drives P4; keep it unless profiling demands otherwise.

---

## 16. Getting started (for the next session)

```bash
npm create vite@latest . -- --template vanilla-ts
npm i -D vitest @vitest/ui
```

Then, in order:
1. Write `src/core/canon.ts` from **§3** verbatim, with `Param` provenance metadata. This is the foundation; everything reads from it.
2. Write `src/core/rng.ts` (PCG32 + split + gaussian) and `src/core/math.ts` (vec3, Thomas solver).
3. Write `test/physics/analytic.test.ts` from **§11.1** — **write the tests before the integrator.** Every expected value is already in §14; you are implementing against known-correct numbers.
4. Write `src/sim/integrator.ts` from **§4.4**. Make T1–T4, T6, T8 green.
5. Proceed through the M0–M6 table in **§13**.

Set `vite.config.ts` COOP/COEP headers for `SharedArrayBuffer` at M0, and build the non-SAB fallback at the same time.

**The build is on rails from here.** §4 is the model, §11 is the oracle, §13 is the order.
