# PHYSICS — the simulation model

**Load only when touching `src/sim/` or `src/fields/`.** Every constant referenced here by `SCREAMING_CASE` name is generated into `src/core/canon_generated.h` from `scripts/canon.py`. Never write a numeric literal for any of them. Every number quoted in prose is verified independently in `docs/VERIFICATION.md`.

Cited as `PHYSICS.md §N` from code comments.

---

## 1. Units, coordinates, chamber

**Strict SI in `core`, `sim`, `fields`.** m, kg, s, K, J, W. Display units exist only in `ui/` and `render/`.

**Precision.** Positions are ~1e-3 m with meaningful structure at ~1e-9 m — 6 decades, at the edge of float32's 7 digits. **Positions, velocities, energy, and biomass are `double`.** Per-cell scratch, field grids, and render instance data are `float`. On sm_89 the fp64 rate is 1/64 fp32, so keep fp64 to the integrator and the energy ledger, where it is required, and use fp32 in the field stencils, where it is not.

**Coordinates.** Right-handed, origin at chamber centre. `x` right, `y` up-screen, `z` toward the objective. `x ∈ [-CHAMBER_W/2, +CHAMBER_W/2]`, likewise `y` with `CHAMBER_H`, `z` with `CHAMBER_D`.

**Gravity acts along −y**, not −z. On a real upright microscope the optical axis is vertical, so sedimentation would run straight through the focal plane and be invisible. We model a side-mounted stage so buoyant drift is in-plane and legible (ADR-006). Switchable via `gravity_axis`.

**Chamber vs. scope.** The chamber is 4 mm × 4 mm × 60 μm; the scope at 40× sees 550 μm of it. You pan the stage to look around. This is both authentic and what gives the GPU something to do — the chamber holds ~200k cells at a few percent packing, where a single field of view physically caps at about 5,000 (ADR-009).

**Boundaries.** `x`, `y`: `reflecting` (default), `periodic`, or `absorbing`, per scenario. `z`: always reflecting (slide and coverslip), with adhesion (§9).

---

## 2. Cell state

Structure-of-Arrays in device memory. Layout is frozen in `contracts/cell_store_v1.h` — that header, not this section, is the authority on field order and types.

| Group | Fields |
|---|---|
| identity | `id` (u64, stable, seeds the RNG stream), `flags` (u32: alive/dead/corpse, awake, stuck, dividing) |
| kinematics | `x, y, z` (f64), `vx, vy, vz` (f64) |
| energetics | `energy` (f64, J, ∈ [0, `CELL_ENERGY_MAX`]), `temp_cell` (f32, K) |
| emission | `emit_power` (f32, W), `dir_x, dir_y, dir_z` (f32, unit) |
| biology | `biomass` (f64, kg), `co2_held` (f64, kg), `age_s` (f32) |
| control | `rng_state` (u64), `taxis_memory` (f32), `run_timer` (f32) |

**Derived, never stored:**

```
mass    = biomass + energy / C_LIGHT^2
density = mass / CELL_VOLUME
charge  = energy / CELL_ENERGY_MAX
```

Storing `mass` as its own accumulating field is a bug: it drifts and silently breaks the energy ledger. Always recompute.

---

## 3. Motion — regime analysis and the integrator

### 3.1 Why the integrator is what it is

| | Empty cell | Full cell |
|---|---|---|
| mass | 2.1e-14 kg | 1.671e-11 kg (**800×**) |
| drag γ = 6πμa | 9.4436e-8 kg/s | same (γ scales with size, not mass) |
| momentum relaxation τ = m/γ | **2.22e-7 s** | **1.77e-4 s** |
| Reynolds at terminal velocity | ≪ 1 | 0.017 |

An empty cell is violently overdamped at `DT_PHYSICS` = 1 ms (dt/τ ≈ 4500). A full cell is only marginally so (dt/τ ≈ 5.6). Therefore:

- **A naive overdamped position-Langevin update is wrong** for charged cells.
- **Velocity-Verlet with linear drag is unstable** for empty cells unless dt < 2τ = 0.44 μs.

**Use the exact-propagator Ornstein–Uhlenbeck velocity update** (the "O" step of BAOAB). It is the analytic solution of the linear-drag + white-noise problem, unconditionally stable at any dt, and degrades automatically to the overdamped limit as dt/τ → ∞. One code path covers the whole 800× range.

### 3.2 The update — exact position **and** velocity propagator

**Propagating velocity exactly and then writing `r += v·dt` is wrong, and wrong by a lot.** When `dt ≫ τ` the velocity fully decorrelates *within* a single step, so the final velocity is not representative of the displacement over that step. Carrying it across the whole `dt` overshoots: for an empty cell at `DT_PHYSICS` it produces **47× too much diffusion** (variance ratio `dt·γ/2m` = 2248). See ADR-016.

Use the exact Ornstein–Uhlenbeck propagator for the **joint** position–velocity distribution (Chandrasekhar 1943; Ermak & Buckholz 1980). With `β = γ/mass`, `x = β·dt`, `E = exp(−x)`, and terminal velocity `v_T = F/γ`:

```
deterministic part
    v ← v·E + v_T·(1 − E)
    r ← r + v_T·dt + (v − v_T)·(1 − E)/β        (v here is the pre-step velocity)

stochastic part, per axis, with kT = K_BOLTZ · T_local
    σ²_vv = (kT/mass)      · (1 − E²)
    σ²_rr = (kT/(mass·β²)) · (2x − 3 + 4E − E²)
    σ_rv  = (kT/(mass·β))  · (1 − E)²

    Δr = σ_rr · z1
    Δv = (σ_rv/σ_rr)·z1 + sqrt(σ²_vv − σ_rv²/σ²_rr)·z2       z1, z2 ~ N(0,1)
```

Position and velocity noise are **correlated** — that 2×2 Cholesky is not optional, and dropping it breaks the fluctuation–dissipation balance.

This reduces correctly at both ends of the 800× mass range: as `x → ∞`, `σ²_rr → 2·D·dt` (Einstein diffusion, verified to 4 significant figures for an empty cell); as `x → 0` it becomes ballistic. That is exactly the property §3.1 demands.

**Numerical care.**
- Use `expm1` for `(1 − E)` and `(1 − E²)`.
- `2x − 3 + 4E − E²` suffers catastrophic cancellation for small `x`: the first three orders cancel exactly and the leading term is `(2/3)x³`. Below `x ≈ 1e-2` use the series `(2/3)x³ − (1/2)x⁴ + (7/30)x⁵`, or an empty cell at a small `dt` silently gets zero diffusion.
- Six gaussian variates per cell per tick (two per axis). `gaussian_pair` returns both variates of a Box–Muller call for exactly this reason.

### 3.3 Viscosity

Temperature-dependent viscosity is not optional — it is what produces **P4**.

```
μ(T) = VF_A * exp(VF_B / (T - VF_C))            Vogel–Fulcher
```

Verified: μ(293.15 K) = 1.002e-3 Pa·s, μ(369.565 K) = 2.98e-4 Pa·s — a 3.36× drop, giving a 4.24× rise in diffusivity `D = kT/γ`. Live cells visibly jitter more than dead ones, which is exactly the tell used in the novel.

### 3.4 Forces

```
F = F_buoyant + F_thrust + F_contact
```

- **Buoyant weight** (Archimedes): `F_buoyant = -(mass - WATER_DENSITY * CELL_VOLUME) * G_ACCEL * ŷ`.
  `CELL_VOLUME` is constant — an enriched cell gains **mass, not volume**; the neutrino store has no volume. This term alone produces **P1**.
- **Photon thrust**: `F_thrust = -(emit_power / C_LIGHT) * d̂`. Recoil is opposite emission.
- **Contact**: §9.
- **Thermophoresis** is implemented but **off by default**: `F = -D_T · mass · ∇T`. Real, but the coefficient for a fictional organism is a free parameter.

---

## 4. Mass–energy coupling

```
mass = biomass + energy / C_LIGHT^2
```

The most consequential line in the codebase. `energy ∈ [0, 1.5 MJ]` maps to a stored mass of 0 → 16.69 ng against a biomass of 0.021 ng — an 800× range.

**Neutral buoyancy** (emergent, asserted by test T3):

```
ENERGY_NEUTRAL_BUOYANCY  = (WATER_DENSITY * CELL_VOLUME - CELL_MASS_DRY) * C_LIGHT^2  = 45,087 J
CHARGE_NEUTRAL_BUOYANCY  = 3.006 %
```

Below 3.006 % charge a cell rises; above it, it sinks. This is **P1** and it is the most legible mechanic in the simulator.

---

## 5. Thermal model — dormancy, thermostat, conduction

Resolves the central canon contradiction (ADR-003) and produces **P2**, **P3**, and (via §3.3) **P4**.

### 5.1 The ignition latch

```
if (!awake && T_local >= CELL_TEMP_SETPOINT)   awake = true;     // irreversible
temp_cell = awake ? CELL_TEMP_SETPOINT : T_local;
```

The novel says both "constant internal temperature regardless of environment" and "inert unless heated above 96.415 °C". The latch satisfies both: dormant cells track ambient and do nothing; crossing the setpoint wakes them permanently; awake cells clamp forever. This is **P3**.

### 5.2 Conduction

A sphere in a quiescent medium (Nusselt number = 2, exact in the Stokes limit):

```
Q = CONDUCTION_COEFF * (temp_cell - T_local)      CONDUCTION_COEFF = 4 π k_water a = 3.7573e-5 W/K
```

Q = 2.871 mW into 20 °C water; 0.241 mW into 90 °C water; **→ 0 as the medium reaches the setpoint**.

### 5.3 Bidirectional coupling

```
if (awake) {
    energy -= Q * dt;                              // Q > 0: spend store to hold setpoint
                                                   // Q < 0: absorb excess heat as neutrino mass
    energy = clamp(energy, 0, CELL_ENERGY_MAX);
    deposit_temperature(+Q * dt / (rho cp V_gridcell));   // equal and opposite, into the field
    if (energy == 0) die(STARVED);                 // can no longer hold setpoint
}
```

**Why P2 emerges.** Q → 0 as `T_local` → setpoint, so the medium asymptotes to 96.415 °C and stops. Since the setpoint is 3.585 K *below* water's boiling point, a live culture **cannot boil its medium at 1 atm**, ever. Drive the medium hotter externally and Q flips sign: the cells absorb and drag it back down. The slide is pinned to a fictional constant.

This is emergent from a number Weir chose for an unrelated reason. **Do not shortcut it with a special case.** If you find yourself writing `if (temp > boiling)`, stop.

**Endurance:** 1.5 MJ at 2.871 mW = 16.6 years of holding setpoint in room-temperature water.

---

## 6. Petrova emission and thrust

The Petrova line is a **discrete quantum annihilation line, not thermal blackbody emission**. Do not compute it from Planck's law. For contrast, the cell's thermal peak is Wien at 7.841 μm — a completely different band. That distinction is real, and it is why the renderer has both a Thermal-IR mode and a Petrovascope mode (`RENDERING.md` §4).

```
F_thrust    = emit_power / C_LIGHT
dE/dt       = -emit_power
photons/s   = emit_power / PETROVA_PHOTON_ENERGY
```

Emission is a cone of half-angle `PETROVA_BEAM_HALF_ANGLE` about `d̂`; `d̂` slews toward the taxis-commanded direction at `PETROVA_SLEW_RATE` (cells cannot instantly reverse).

| Emission power | Thrust | Terminal velocity | Crosses a 550 μm field in |
|---|---|---|---|
| 1 mW | 3.336e-12 N | 35.3 μm/s | 15.6 s |
| 10 mW | 3.336e-11 N | 353 μm/s | 1.6 s |
| **47.59 mW** | 1.588e-10 N | 1681 μm/s | 0.33 s |

**47.59 mW is exactly what a fully charged cell needs to hover** against its own 32,000 kg/m³ weight — which is why `PETROVA_MAX_POWER` defaults to 50 mW (ADR-005), putting "can just barely hold itself up when full" at the top of the dial.

**Discharge triggers:** thrust-to-move (from taxis); the spin-drive flash (external high-intensity pulse at `PETROVA_WAVELENGTH` forces full-rate discharge); optional death rupture (default off, ADR-004). Note that the thermostat is *not* an emission trigger — that energy leaves as heat, not photons.

---

## 7. Fields

Four grids over the `xy` plane, depth-averaged. Authority on layout: `contracts/fields_v1.h`.

| Field | Grid | Diffusivity | Solver | Substeps per tick |
|---|---|---|---|---|
| Temperature | `FIELD_N_TEMP` = 512² | 1.4325e-7 m²/s | explicit FTCS, ping-pong, fp32 | 10 |
| CO₂ | `FIELD_N_CO2` = 256² | 1.92e-9 m²/s | explicit | 1 |
| N₂ | `FIELD_N_N2` = 128² | 2.0e-9 m²/s | explicit | 1 |
| Irradiance | `FIELD_N_IRRAD` = 512² | — | occlusion sweep, rebuilt each tick | — |

Exact substep counts are computed in `VERIFICATION.md` §6 and must be read from there, not assumed.

**Ping-pong, not red-black** (ADR-019). Red-black is a Gauss-Seidel *ordering* — an implicit smoother that reads partially-updated neighbours deliberately. An explicit step must read the old value everywhere, so it needs a second buffer, not an ordering.

**The grid is 2D.** It is depth-averaged over the slab, so a point source in it relaxes **logarithmically**, not as 1/r. The 1/r law in §7.2 is the *three-dimensional* near field and is applied per cell at sample time — do not expect the grid itself to produce it.

### 7.1 Why explicit, and why 512²

Explicit FTCS stability is `dt < dx²/(4α)`. At 512² over a 4 mm chamber, `dx` = 7.8 μm and `dt_max` = 1.06e-4 s — **10 substeps per 1 ms tick**, which on sm_89 costs well under 0.1 ms. An implicit ADI solve would need batched tridiagonal solves (cuSPARSE) for no practical gain at this resolution. Explicit is simpler, deterministic, and fast enough (ADR-008).

At 1024² the substep count quadruples to 38 and the memory traffic makes it the dominant cost. Do not raise the resolution without re-reading this section.

### 7.2 The analytic near-field correction

`dx` = 7.8 μm is comparable to the cell diameter, so the grid cannot resolve the thermal halo close to a cell — where the steady-state profile is analytic:

```
T(r) = T_inf + (temp_cell - T_inf) * CELL_RADIUS / r
```

(+38.2 K at r = 2a, +15.3 K at 5a, +7.6 K at 10a for a cell in 20 °C water.)

**Solution: grid for the far field, analytic for the near field** (ADR-010). At sample time (tick stage 2), a cell's `T_local` is the bilinear grid sample **plus** the analytic contribution of its hash-neighbours within 4a, with the grid's already-smeared contribution of those neighbours subtracted to avoid double counting. This removes all resolution pressure from the grid and is standard practice for point-source problems.

### 7.3 Deposits

Cells deposit with bilinear scatter into **64-bit fixed-point accumulators** (INV-2), converted to float after the deposit kernel. Scale factors per field live in `contracts/fields_v1.h`. Float `atomicAdd` is forbidden here: it makes the result depend on warp scheduling and destroys INV-8.

### 7.4 Boundary conditions

Per scenario: `dirichlet` (heated stage held at a bath temperature), `neumann` (insulated), `robin` (convective loss to room air, `AIR_CONVECTION_H`). Defaults: `robin` on T, `neumann` on CO₂ and N₂.

### 7.5 Irradiance and P5

Albedo is exactly 0 at all wavelengths ("super cross-sectionality"), so occlusion is total — no transmission, no scattering.

1. Rasterize each cell's opaque disc into an occlusion buffer along the light direction.
2. March the irradiance grid along that direction; behind any occluder, irradiance is **exactly zero**.
3. Add an `ambient` term that is not occluded (multiply-scattered room light).

Dead cells attenuate by `1 − CELL_ALBEDO_DEAD` instead of fully, so a field of corpses is translucent and a field of live cells is jet black. A 1D running-occlusion sweep along the light axis is O(grid) and sufficient. This is **P5**.

### 7.6 Feeding

A cell absorbs all incident radiation:

```
P_absorbed = E_directional * CELL_CROSS_SECTION + E_ambient * CELL_SURFACE_AREA
energy    += P_absorbed * dt      (clamped to CELL_ENERGY_MAX)
```

Projected disc `π a²` for the collimated component, full sphere `4π a²` for the isotropic one.

---

## 8. Taxis

Canon: cells move toward light/heat to feed, follow the CO₂ lines to find breeding grounds, and **do not move in darkness**.

```
if      (dark && no CO2)                                   → IDLE   // no emission, drift only
else if (!dark && charge < TAXIS_SEEK_FEED_BELOW)          → FEED   // climb irradiance
else if (charge > TAXIS_SEEK_BREED_ABOVE && CO2 available) → BREED  // climb CO2
else                                                       → IDLE
```

where `dark` is `irradiance < TAXIS_DARK_THRESHOLD` and "CO₂ available" is simply `co2 > 0` — the field is zero until something adds to it, and no availability constant is invented (ADR-022 §3). **FEED requires light**, a deliberate deviation from the earlier form of this pseudocode: a dim cell climbing an irradiance gradient that does not exist would burn store for nothing and would contradict "does not move in darkness" (ADR-022 §2).

**Gradient climbing is temporal, not spatial** (ADR-007). A 10 μm cell cannot meaningfully finite-difference a 7.8 μm grid across its own body, and a smooth gradient-glide looks like a video game rather than an organism.

The lagged signal is a **first-order lag, not a delay line**: `taxis_memory` is a single float, and real chemotactic response kernels are approximated by exactly this. The update uses the exact discretisation, so a step input reaches 1 − 1/e at exactly `TAXIS_MEMORY_TIME` whatever `dt` is.

```
ema  ← ema + (1 - exp(-dt/TAXIS_MEMORY_TIME)) * (signal_now - ema)
Δ    = signal_now - ema
if (Δ > 0 && run_timer < TAXIS_RUN_MAX)  keep heading, extend the run
else  tumble: rotate ĥ by an angle drawn exponential with mean TAXIS_TUMBLE_ANGLE_MEAN,
      clamped to pi, about a uniform azimuth, from the cell's PCG32 stream; reset run_timer
emit_dir   = -ĥ                                  // recoil is opposite the axis
emit_power = PETROVA_MAX_POWER while seeking, clamped to what the store can supply
energy    -= emit_power * dt                     // Sec 6; nothing debited this before M8
```

**The comparison window must be short compared to a chamber crossing.** An awake cell swims at 6105 um/s and crosses the 4 mm chamber in 0.655 s; no gradient can be larger than the chamber, so a longer memory compares against a baseline older than any structure the cell could be climbing. `TAXIS_MEMORY_CHAMBER_RATIO` is derived and asserted below 0.5 (ADR-024).

**The run cap is load-bearing.** A cell that outruns its own depletion halo sees a rising signal in every direction and would otherwise never tumble (ADR-022 §1). `TAXIS_RUN_MAX` is derived as 4 × `TAXIS_MEMORY_TIME` so it cannot drift away from the comparison window.

Only **awake** cells taxis — dormant cells are inert powder. The IDLE path draws no random numbers, which makes a dark chamber bit-identical to a run with the controller disabled rather than merely similar to it.

Run-and-tumble is cheap (no gradient sampling), robust to noise, biologically real, and looks unmistakably alive.

---

## 9. Contact and adhesion

Soft-sphere pair repulsion, the only cell–cell mechanical interaction. Neighbours come from the spatial hash (chamber grid, cell size 2.2 × `CELL_DIAMETER`, built by counting sort — order-stable, INV-7).

```
for pairs with d < 2a:
    F += CONTACT_STIFFNESS * (2a - d) * r̂
```

Damped by the ambient OU drag; no separate contact damping term.

**Adhesion:** on `z`-wall contact, stick with probability `WALL_STICKINESS`; a stuck cell's drag is multiplied by `WALL_STUCK_DRAG_MULT` until its thrust exceeds the release force. This reproduces the real microscopy look of a settled monolayer.

---

## 10. Life cycle

**Division.** Requires CO₂. A cell accumulates `co2_held` from the CO₂ field; at `CO2_MASS_PER_DIVISION` it enters mitosis for `LIFE_MITOSIS_DURATION`, then splits:

- biomass: parent keeps `CELL_MASS_DRY`, daughter is built from the consumed CO₂
- **energy: split in half** — each daughter carries half the store
- daughter RNG: `pcg_split(parent_state, daughter_id)` (INV-1)
- the base rate is tuned so that under non-limiting CO₂ the population doubles in `LIFE_DOUBLING_TIME` (test T18)

**Death.** Starvation (`energy == 0` while awake), predation (§11), or `temp_cell > CELL_LETHAL_TEMP`.

**On death:** state → corpse, albedo → `CELL_ALBEDO_DEAD` (translucent), emission stops, taxis stops, the thermostat disengages, `temp_cell` relaxes to ambient. Corpses persist and are rendered — a field of dead Astrophage is visually and diagnostically distinct.

**Where the store goes** is canon-silent and ships as a three-way scenario toggle (ADR-004): `void` (default, energy vanishes), `flash` (discharged as Petrova photons — physically conserving, and since one full cell is 358.5 g TNT this triggers a scripted containment-failure end state rather than pretending a slide survives it), or `retain` (store persists as inert ballast, so corpses stay 32,000 kg/m³ and rain to the coverslip).

**The energy ledger is not a curiosity.** The default 200,000-cell population fully charged holds 300 TJ ≈ 72 kt TNT inside a droplet. The HUD carries this readout permanently. Being honest about it is more interesting than ignoring it.

---

## 11. Taumoeba

Own SoA store, same patterns.

- **Motion:** persistent random walk at `TAU_CRAWL_SPEED`, biased up the local cell-density gradient (same run-and-tumble as §8, sensing hash-cell occupancy). Same OU integrator with its own γ from `TAU_DIAMETER`.
- **Predation:** on overlap with a live cell, engulf. Cell → dead. The Taumoeba digests for `TAU_DIGEST_TIME`, gaining `biomass * TAU_BIOMASS_YIELD`. Per Weir's own resolution, it consumes only the **chemical** energy — the neutrino store is handled by the §10 toggle, and `void` is the canon-consistent default.
- **Nitrogen lethality:** `hazard = max(0, N_local - TAU_N2_LETHAL_CONC * (1 + tolerance * k))`; die with probability `1 - exp(-hazard * rate * dt)`.
- **Evolution:** divide at 2× initial biomass; the daughter inherits `tolerance + N(0, TAU_MUTATION_SIGMA)` clamped to [0,1]. Under a slowly rising nitrogen ramp this reproduces the **Taumoeba-82.5** breeding arc as genuine directional selection rather than as a script.

---

## 12. Multi-rate time

Processes span nine orders of magnitude: momentum relaxation 2.2e-7 s, full-cell sedimentation across a field 0.33 s, thermal equilibration ~1 s, mitosis 6.9e5 s, a culture reaching 10⁴ cells 9.2e6 s. **A single global time-scale slider cannot work** — at 10⁶× the integrator explodes; at 1× nothing ever divides.

Two independent multipliers (ADR-011):

```
physics_rate ∈ [0.1, 100]     scales DT_PHYSICS: motion, heat, thrust     (stiff; stay near 1)
biology_rate ∈ [1, 1e6]       scales ONLY division/growth/digestion clocks (non-stiff; free)
```

Biology is slow, local, and non-stiff, so scaling its rate is numerically free and physically meaningful. Named presets drive both:

| Preset | physics | biology | What you watch |
|---|---|---|---|
| Realtime | 1 | 1 | Brownian jitter, thrust, honest microscopy |
| Motion | 10 | 1 | sedimentation, taxis, migration |
| Metabolic | 1 | 1e4 | charging, thermal equilibrium, feeding |
| Generational | 0.5 | 1e6 | division, population curves, evolution |

The HUD always shows both multipliers and the elapsed simulated time in real units ("14.2 days of culture time"). Never let the user lose track of which clock they are on.
