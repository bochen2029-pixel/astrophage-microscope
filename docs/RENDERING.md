# RENDERING — the scope

**Load only when touching `src/render/` or `src/ui/`.** Interfaces are frozen in `contracts/render_view_v2.h`; that header, not this document, is the authority on struct layout.

---

## 1. The look, in one sentence

This must read as **microscopy**, not as a particle toy, and the entire difference is the optics model in §3: a real 40×/0.65 objective has a **1.53 μm depth of field** inside a **60 μm** chamber slab, so most cells are visibly out of focus at any moment and racking focus is a primary interaction. Get that right and everything else follows.

---

## 2. Pipeline

```
[cell occlusion raster] ──▶ [irradiance grid] ─┐   (sim-side, PHYSICS.md §7.5)
                                               │
[field grids → R32F textures] ──▶ [field pass, LUT-mapped]  ─┐
[CellStore → instance VBO via CUDA interop] ──▶ [cells pass] ─┼─▶ [compose] ─▶ [bloom] ─▶ [optics FX] ─▶ screen
[petrova emission lobes, additive] ──────────────────────────┘
```

**One instanced draw for all cells.** A CUDA kernel writes per-instance attributes directly into a GL buffer registered with `cudaGraphicsGLRegisterBuffer` — positions never touch host memory. Instance payload is 36 bytes in **micrometres, fp32**: `(x, y, z, radius)`, `(charge, emit_power_norm)`, `(flags_packed, dir_packed)`, and a `shape_seed` (ADR-023).

The silhouette is an **SDF in the fragment shader**, so it stays crisp at any zoom and costs nothing extra when small. Under `Morphology::Sphere` it is a circle; under `Irregular` it is the area-preserving harmonic outline of §8 (ADR-023).

---

## 3. Microscope optics

Objective presets come from `canon::OBJECTIVES` (generated). Verified values in `VERIFICATION.md` §7:

| Preset | M | NA | Resolution | DOF | FOV | Cell spans |
|---|---|---|---|---|---|---|
| SURVEY | 10× | 0.25 | 1342 nm | 11.20 μm | 2200 μm | 7 resel |
| **WORKING** (default) | 40× | 0.65 | 516 nm | **1.53 μm** | 550 μm | 19 resel |
| DETAIL | 100× oil | 1.25 | 268 nm | 0.61 μm | 220 μm | 37 resel |

**Defocus.** Circle-of-confusion radius `r_coc = |z - z_focus| * NA / n`. At Δz = 10 μm with NA 0.65 that is a 6.5 μm blur radius — larger than the cell itself, and correct.

Implement as **per-instance quad expansion**: grow the quad by `r_coc` and convolve the disc SDF with a Gaussian of that radius analytically (`smoothstep` over the SDF with width `r_coc` is a good approximation). This is far cheaper than a screen-space depth-of-field pass and, critically, it is *correct per object* — cells overlap in projection, and a screen-space pass gets overlapping depths wrong.

**Diffraction ring.** In focus, an opaque disc shows a bright Becke line just outside its edge and a dark ring just inside. Two `smoothstep` bands on the SDF, amplitude scaled by `(1 - r_coc/a)`. Cheap, and it does more for the microscopy read than anything else in this document.

**Defocus polarity.** Above and below focus the ring pattern inverts. Flip the band polarity by `sign(z - z_focus)`. Nearly free, and it is the cue that tells a viewer which way to rack the focus.

**Condenser.** Subtle radial vignette plus a slight warm chromatic shift at the field edge.

---

## 4. View modes

Five modes, **cross-faded with a slider rather than hard-cut**, so the user can see the correspondence between them. Mode switching is the core verb of the whole product: Astrophage is black in visible light and emits where no eye can see, so the gap between "what a human sees" and "what the cell is doing" *is* the subject.

| Mode | Background | Cells | Shows |
|---|---|---|---|
| **Brightfield** | bright warm white | pure black discs with diffraction ring; corpses translucent grey | what a human sees. Charge state invisible. |
| **Darkfield** | black | bright edge-scattering rings | classic contrast; live/dead legible |
| **Petrovascope** | pure black | magenta emission lobes only; non-emitting cells **invisible** | the 25.984 μm band. The canon instrument. |
| **Thermal IR** | deep blue/black | glow by `temp_cell`, plus the field halo | the 7.841 μm blackbody band |
| **Analysis** | dark grey | flat discs coloured by a selectable channel (charge / temp / age / mass / awake) | the honest scientific view |

**Thermal IR and Petrovascope must read differently.** The Petrova line is a discrete quantum annihilation line, not thermal emission (`PHYSICS.md` §6), so a live idle cell glows in Thermal and is *dark* in Petrovascope, while a discharging cell blazes in Petrovascope. This is scientifically real and it is the simulator's best teaching moment — do not let the two modes collapse into one another.

**Overlays**, independently toggleable on any mode: T field, CO₂ field, N₂ field, irradiance field, velocity vectors, hash grid, trajectory trails, scale bar.

---

## 5. Colour

| LUT | Use | Values |
|---|---|---|
| `petrova-film` (default) | Petrovascope | `#FF2D95` → `#C4187A` → `#3D0620`. Matches the 2026 film's pink/magenta grade. |
| `petrova-false-ir` | Petrovascope, alt | `#C4000A` → `#2A0000`. Conventional false-colour IR. |
| `magma` | Thermal IR, analysis | perceptually uniform, colourblind-safe |
| `viridis` | field overlays | perceptually uniform |
| `brightfield` | brightfield | `#F5F0E6` background, `#050505` cells |

All LUTs are 256-entry tables in `luts.cpp` uploaded as 1D textures. A global colourblind-safe toggle swaps `petrova-film` for `magma`.

**Bloom applies to Petrova emission only** — a 4-level downsample/upsample chain, threshold 0.6, intensity tied to `emit_power`. This is what sells the swirling-pink-points-of-light look.

---

## 6. HUD and UI

Layout: viewport centre; instruments and inspector right; transport and tool brushes bottom; parameter table and charts right-lower.

**The HUD is always honest.** Permanently visible: simulated time **in real units** (never a bare tick count), live/dead/Taumoeba counts, mean charge, medium temperature, both clock multipliers, and the **total stored energy ledger** in J and TNT-equivalent with a warning icon past 1 GJ. Plus a `NON-CANON RUN` badge whenever any `CANON` parameter has been unlocked.

**Parameter inspector.** Every entry of `canon::PARAM_TABLE` as a row: name · value · unit · provenance badge · lock. Gold/locked for `CANON` (unlocking prompts once and sets the non-canon flag), blue/read-only with formula for `DERIVED`, grey/unlocked for `REAL`, orange/tunable for `INVENTED` with a hover explaining what canon does and does not say.

**Cell inspector.** Click to follow. Live readout of id, age, charge (J and %), stored mass (ng), total mass, **density and buoyancy state** — `"SINKING — 31,915 kg/m³, 32× water"` — temperature, awake/dormant, emission power and direction, biomass, CO₂ held, time to division, plus a 60 s charge sparkline. The buoyancy line is what teaches P1; make it prominent.

**Tool brushes.** Every tool is a radius-and-strength brush: heat, chill, illuminate (aim the source), inject CO₂, inject N₂, seed cells, seed Taumoeba, kill, and the charge beam (Dimitri's 1 kW laser).

---

## 7. Performance budget

Reference machine: RTX 4070 Ti SUPER (sm_89, 16 GB), 200,000 cells, `TARGET_FPS` = 144 (6.9 ms/frame).

| Stage | Budget |
|---|---|
| hash build (counting sort) | 0.30 ms |
| field sample + near-field correction | 0.40 ms |
| taxis + thermal + forces + integrate | 0.80 ms |
| field deposit + diffuse (10 substeps) | 0.60 ms |
| irradiance + occlusion | 0.40 ms |
| lifecycle + stats | 0.20 ms |
| **sim subtotal per tick** | **2.7 ms** |
| interop instance write | 0.15 ms |
| cells pass (1 instanced draw) | 1.2 ms flat discs · **2.3 ms with defocus** |
| field pass + compose + bloom + optics | 1.5 ms |
| ImGui | 0.5 ms |

**Defocus is a fill-rate cost, not a shader-complexity cost.** A cell 30 μm out of focus expands its quad to ~40 μm across — 64× the in-focus area — and every one of those fragments is shaded and blended. Measured at M3: 200k cells went from 795 fps (flat discs) to **426 fps at 40×** and **387 fps at 100×**, where the higher NA blurs harder. Both comfortably clear the 144 target, but the headroom is now 3× rather than 5×, and **bloom at M7 lands on top of this**. If a budget crisis comes, it will come here.

**Scaling levers, in the order to reach for them:** drop field grids one power of two; run `lifecycle` every 10th tick (it is `biology_rate`-scaled anyway); **cull cells whose peak opacity falls below the discard threshold** — at the working objective a cell past ~40 μm of defocus contributes under 2 % opacity and could be skipped entirely in the vertex stage, which directly attacks the overdraw above; LOD to a density heatmap beyond 500k; only then persistent kernels or graph capture.

**Hard rules.** Zero device allocation in the steady-state tick loop — all scratch preallocated at scenario load (test T29). Cells are drawn at **true relative size**; there is no "make them bigger so you can see them" fudge, and `audit.ps1` greps for one. Sub-pixel cells still render: clamp the minimum radius to 0.75 px and modulate alpha by the area ratio so density stays honest instead of aliasing away.

---

## 8. Cell morphology — **implemented at M8b** (ADR-023)

§2 says the disc is an SDF, so "cells are perfect circles at any zoom". Reference photography of Astrophage under a lab scope shows something quite different: **irregular, faceted, crumpled silhouettes**, each one unique, with a dense black core and a soft ruffled rim — closer to torn foil or a crushed mineral grain than to a dot. Perfect circles read as *notation*; the irregular shapes read as *organisms*. **§8.1–§8.4 shipped at M8b**; §8.5 and §8.6 are still design, and §8.7 is physics rather than rendering.

### 8.1 The invariant that keeps this honest

**Morphology is appearance only.** The physics body stays a sphere of `CELL_RADIUS` — Stokes drag, `CELL_CROSS_SECTION`, contact radius, `disc_overlap_fraction`, and every occlusion path are untouched. `sim/` must not learn that morphology exists.

That gives a machine-checkable gate, and it is the one that matters here:

> **Same seed + same scenario + any morphology setting ⇒ identical snapshot hash (INV-8).**

If a shape change ever moves the hash, morphology has leaked into the simulation and the change is wrong. This is what stops "make it look better" from quietly becoming "make it behave differently".

Two supporting rules:
- Per-cell shape coefficients derive from `splitmix64(cell_id)` **in the render path only**. Never draw from `rng_state` — that is the cell's simulation stream (INV-1) and consuming from it would desynchronise the sim.
- Radius stays canon-locked. **Do not add size variation.** The apparent size spread in the reference images is mostly defocus, which §3 already models correctly — a cell 10 μm off the focal plane genuinely images larger and softer. Randomising the radius would be a size fudge in disguise and would trip A10 in spirit if not in grep.

### 8.2 Silhouette — the highest-impact change

Replace the circular SDF test with an angular radius function evaluated in the fragment shader:

```
r_eff(theta) = a * (1 + sum_k A_k * cos(k*theta + phi_k))          k = 3..8
```

Three to six harmonics with amplitudes ~0.10–0.25 falling as `1/k` give lobed, crumpled outlines. Coefficients are packed per instance by the interop kernel (two extra `vec4`s), so the fragment shader only evaluates.

The reference images look **faceted**, not merely wavy, so the better base is a **jittered polygon**: 7–12 vertices at radii `a*(1 + jitter)`, `theta` quantised into sectors with linear interpolation between adjacent vertices. Straight edges, sharp corners. Then add the harmonic ripple on top of the polygon — polygon for the angularity, harmonics for the crumple. That combination is what produces the crushed-foil read.

Each cell needs a stable orientation from its `id`. Rotation over time is defensible (rotational Brownian motion is real and fast at this scale) but there is no angular state in the store today, so **start static**; a real per-cell orientation is a `cell_store_v2.h` conversation, not a shader one.

### 8.3 Core and rim

The high-magnification reference shows a **pure black core** with a **semi-transparent ruffled skirt**, not a clean edge plus a ring. Two-zone opacity:

- `alpha = 1` for `r < 0.75 * r_eff(theta)` — albedo is exactly 0, so the core is genuinely black, not dark grey.
- Between `0.75*r_eff` and `r_eff`, fall off with a *noisy* profile — reuse the high-`k` harmonics, phase-shifted — so the rim frills instead of feathering evenly.

This composes with the existing defocus `smoothstep` rather than replacing it: the rim is the shape's own structure, the defocus is the optics on top.

### 8.4 The field of view is doing a lot of the work

Every reference frame shows a **bright circular aperture with a vignette**, black outside it. The current renderer fills the rectangle. Adding a soft-edged circular field mask plus radial falloff in `post_pass.cpp` is a handful of lines and probably buys more "microscope" per line of code than anything in §8.2. It is also physically the field diaphragm, so it is not a cheat. HUD, scale bar, and panels sit outside the aperture.

### 8.5 Lateral chromatic aberration

Cyan/magenta fringing is visible on high-contrast edges in the reference. Sample the cell pass with a per-channel radial offset that scales from 0 on the optical axis to ~1–2 px at the field edge. Real (it is the objective's lateral colour), cheap, and a strong authenticity cue.

**Must be a toggle, off in Analysis mode.** It displaces pixels, so it corrupts any quantitative read of position — and it must never be baked into a golden image used as a measurement oracle.

### 8.6 Medium texture — the one to be careful with

The reference field is not clean: faint debris, scratches, mottling. Procedural, seeded from the scenario, would sell the look.

**The risk is honesty, not implementation.** A speck that could be mistaken for a cell in a simulator whose whole point is counting and measuring cells is a bug, not a flourish. If built: keep it clearly out of focus, low contrast, static, visually distinct from any cell, off by default, and never present in Analysis mode or in a golden used as an oracle.

### 8.7 Clumping is physics, not rendering

Many reference cells sit in irregular clusters of two to four. **Do not fake this in the renderer.** Wall adhesion exists (`WALL_STICKINESS`); cell–cell adhesion does not. If Astrophage stick to each other, that is a `sim/` change with its own ADR and its own gate — and clusters should then *emerge*, like every other signature phenomenon. Drawing cells near each other and calling it clumping would be exactly the special-casing `ARCHITECTURE.md` §1 forbids.

### 8.8 Costs, and what this collides with

- **Overdraw gets worse, not better.** An irregular silhouette needs a slightly larger bounding quad, and §7 already identifies defocus fill rate as the first budget crisis. **Do Q8 (vertex-stage culling of sub-threshold cells) before this, not after.**
- **Fragment cost rises** — harmonics and a polygon test per fragment, on top of the optics.
- **ADR-017 / Q7 bites here.** `optics.h` and the GLSL in `cells_pass.cpp` already duplicate four formulas with no compiler check between them. A morphology function needed by both the shader and any host-side test is the third consumer that Q7 says should trigger **generating the GLSL from the header** rather than adding a fourth hand-kept copy.

### 8.9 The canon question this raises

The novel describes Astrophage as small black spheres. The reference photography shows irregular grains. That is a source contradiction of exactly the kind `DECISIONS.md` exists to adjudicate, and this project's established answer (ADR-002, ADR-003) is to **ship both readings as options** rather than silently pick one: a `cell_morphology` setting of `Sphere` (novel-faithful, today's behaviour) or `Irregular` (reference-faithful).

Whoever implements this writes the ADR and picks the default. Because of §8.1 the choice is guaranteed to be cosmetic — the snapshot hash cannot tell the difference.
