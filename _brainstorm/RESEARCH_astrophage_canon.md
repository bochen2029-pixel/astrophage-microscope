# Astrophage Technical Reference for a Physics-Based Visual Simulator
### (Andy Weir, *Project Hail Mary*, 2021 novel + 2026 Amazon MGM film, dir. Phil Lord & Christopher Miller, starring Ryan Gosling)

## TL;DR
- **Astrophage** is a fictional 10-micron, jet-black, spherical single-celled organism that stores stellar heat as mass (neutrinos) at near-E=mc² efficiency, holds up to **1.5 MJ per cell** (gaining ~17 nanograms), maintains a constant internal temperature of **96.415 °C**, and propels itself by emitting infrared light at the **25.984 μm "Petrova wavelength"** (~11.5 THz), reaching **0.92 c**.
- The user's brief contains two canon errors worth flagging up front: **96.415 is a temperature in °C, not a frequency in THz**, and the Petrova emission line is at **25.984 μm (~11.54 THz), not 3.11 μm / 96.415 THz**. The 4.26 μm and 18.31 μm figures are the **CO₂ spectral lines Astrophage homes in on to find breeding planets**, not its emission line.
- For a simulator, most core numbers are hard canon (size, temperature, per-cell energy, Petrova wavelength, 1.5 g, 0.92 c, 1,009 spin drives, 2,000,000 kg fuel); a handful (total wild-population mass, ship length, exact per-scene glow color) are unstated and must be invented — flagged clearly below.

---

## Key Findings

1. **Two terminology corrections drive everything.** The number **96.415** is Astrophage's constant internal **temperature in degrees Celsius** (just below water's boiling point), which Weir derived by a root-mean-square proton-velocity calculation (the temperature at which colliding hydrogen ions carry the kinetic energy needed to produce a neutrino pair). It is *not* a frequency. Astrophage's propulsion/emission line is the **Petrova wavelength = 25.984 μm** (mid-to-far infrared), corresponding to ~**11.54 THz** and a photon energy of **~0.0478 eV**. The CO₂ bands at **4.26 μm and 18.31 μm** are what Astrophage *seeks* to navigate to CO₂-rich planets, not what it *emits*.

2. **Energy storage is the "one lie."** Astrophage converts heat into neutrino mass and back, storing up to **1.5 MJ per cell** at "enrichment," gaining ~**17 ng** of mass — a mass-energy conversion near the theoretical E=mc² maximum (antimatter-class energy density), enabled by the fictional "super cross-sectionality" that traps neutrinos (which Weir treats as Majorana particles that self-annihilate to two photons).

3. **Propulsion is a photon/neutrino rocket.** Directed 25.984 μm light out one side produces thrust (p = E/c). This scales up in the Hail Mary's **1,009 spin-drive** engines.

4. **The film visualizes the invisible IR as glowing pink/magenta**, achieved with practical effects (IR-modified ARRI Alexa 65, chicken-wire LED rigs, water) plus color grading — a direct, defensible aesthetic choice for the simulator.

---

## Details

### 1. CANONICAL PHYSICAL SPECIFICATIONS

**1.1 Size, shape, mass, density (CANON)**
- Diameter: **10 microns (10 μm)**, spherical. Comparable to a large eukaryotic/human cell (~size of a red blood cell).
- Single-cell rest mass: **~0.021 nanograms** (fan-wiki precise value 0.02105 ng). *(Flag: one blog estimates ~0.5 ng; use 0.021 ng as the wiki/canonical value.)*
- Density: not explicitly stated. Astrophage is described as mostly water, so **~1,000 kg/m³** is a reasonable modeling assumption. A 10 μm sphere has volume ≈ 5.24×10⁻¹⁶ m³; at water density that is ~0.52 ng — the same order of magnitude as the canon mass, so water density is a self-consistent choice (SPECULATIVE/derived).
- Structure: carbon-based, water-based, DNA, mitochondria-like organelles, ATP — deliberately Earth-like (panspermia premise; Weir explicitly invoked a panspermia event so he wouldn't have to invent life from the ground up).

**1.2 Blackness / albedo (CANON)**
- Live Astrophage is **completely black and opaque across the entire electromagnetic spectrum** — visible, UV, even gamma and (impossibly) wavelengths larger than the cell, plus neutrinos. This is the "super cross-sectionality" property: nothing can quantum-tunnel through it.
- Near-zero albedo → behaves like an idealized black-body absorber. Dead Astrophage loses the property and becomes translucent, revealing the interior.
- It dims stars like "mold growing across a window," blocking progressively more light as it multiplies.

**1.3 Energy storage as mass (CANON + derived)**
- Mechanism: absorbs heat, converts proton-collision kinetic energy into **neutrino pairs**, stores neutrinos as mass; reverses the process (neutrino–neutrino annihilation) to emit **two 25.984 μm photons**.
- Maximum stored energy: **1.5 MJ per cell** (canonical figure; a "1,500 J" figure on one blog is an error). Mass gained at full enrichment: **~17 ng**.
- Verification math (DERIVED): 1.5×10⁶ J ÷ c² = 1.5×10⁶ / 8.988×10¹⁶ = **1.67×10⁻¹¹ kg ≈ 16.7 ng** ✓ — matches the canon 17 ng.
- Dimitri Komorov's experiment (CANON): a **1 kW laser for 25 minutes** = 1,000 W × 1,500 s = **1.5 MJ**, producing the 17 ng mass gain. Internally consistent.
- Energy density: because ~17 ng of stored mass dwarfs the 0.021 ng biomass, bulk energy density approaches antimatter. For comparison (real values): gasoline ~46 MJ/kg; U-235 fission ~1.44×10⁸ MJ/kg (only ~0.1% of mass converted); D-T fusion ~5.76×10⁸ MJ/kg (~0.7%); antimatter ~8.99×10¹⁰ MJ/kg (100%). Astrophage sits near the antimatter limit.

**1.4 Temperature behavior (CANON)**
- Constant internal temperature **96.415 °C** regardless of environment, even in a stellar photosphere. Above 96.415 °C it dumps excess heat into neutrino mass storage (perfect heat sink); below it, it spends mass-energy to warm itself (heat source). This bidirectional thermostat is used by Rocky for inventions (e.g., a heat-sink "environment ball").
- The Petrova emission line is **25.984 μm** (11.54 THz); this is a discrete quantum line, not thermal black-body emission.

**1.5 Propulsion / navigation / travel (CANON)**
- Emits directed 25.984 μm light for thrust; "toot to scoot."
- Navigation: follows light/heat gradients (moves toward stars for feeding) and follows the **CO₂ spectral signature (4.26 μm and 18.31 μm)** to find breeding planets. Does not move in darkness.
- Uses the star's **magnetic field** to distance itself once "enriched" before departing.
- Max velocity: **0.92 c** (≈2.76×10⁸ m/s). Spore form can travel up to **8 light-years**.
- Deceleration at destination: **aerobraking** — hits the planet's atmosphere at relativistic speed; the collision heat is absorbed as neutrino mass (so it doesn't burn up), stopping at ~0.02 atm.

**1.6 Reproduction (CANON)**
- Requires CO₂. Full cycle: feed at the Sun → become enriched → travel to a CO₂-rich planet (Venus in our system; "Adrian" at Tau Ceti; "Threeworld" at 40 Eridani) → aerobrake → absorb CO₂ to build biomass → divide by **mitosis** → both parent and daughter return to the star. Doubling roughly every ~8 days.
- The migratory light trail is the **Petrova line**.

**1.7 Storage / handling / resilience (CANON)**
- Inert unless heated above 96.415 °C; below that it's a stable, storable powder-like substance. Extremely radiation-hardy (used as a radiation shield around the Hail Mary crew compartment). Survives vacuum and extreme temperature/pressure.

**1.8 Taumoeba — the predator (CANON)**
- Native to the planet Adrian's upper atmosphere (~91.2 km altitude) in the Tau Ceti system; the only known natural predator of Astrophage; keeps Tau Ceti's population in check.
- Kills Astrophage by engulfing it (phagocytosis, amoeba-like), producing methane and solid waste.
- **Nitrogen is lethal to Taumoeba** — so it cannot survive in Venus's or Threeworld's nitrogen-bearing atmospheres without a bred nitrogen-resistant strain ("Taumoeba-82.5").
- Plot twist: the nitrogen-resistant strain also evolved to permeate **xenonite** (the Eridian building material), threatening the ships' fuel tanks.

### 2. THE MATH AND EQUATIONS

**2.1 Mass–energy (CANON + derived)**
- E = mc². Per cell: 1.5 MJ ↔ 16.7 ng (verified above).

**2.2 Photon-rocket thrust (REAL PHYSICS)**
- Photon momentum: p = E/c. Thrust from emitted power P: **F = P/c**.
- Example: to produce the Hail Mary's 1.5 g on ~100,000 kg (dry) requires F = ma ≈ 100,000 × 14.7 ≈ 1.47×10⁶ N. A pure photon drive would need P = F·c ≈ 4.4×10¹⁴ W — enormous, explaining the "nuclear-bomb levels of light" critique.
- Thrust-to-power ratio of a photon rocket: **1/c ≈ 3.34×10⁻⁹ N/W** (very poor per watt, but the energy is essentially free/onboard).

**2.3 Energy-density comparison (REAL)**
| Fuel | Specific energy (MJ/kg) | Mass fraction converted |
|---|---|---|
| Gasoline | ~46 | chemical |
| U-235 fission | ~1.44×10⁸ | ~0.1% |
| D-T fusion | ~5.76×10⁸ | ~0.7% |
| Antimatter | ~8.99×10¹⁰ | 100% |
| Astrophage | near antimatter | near 100% |

Context figure often quoted from fan analysis: the Hail Mary's ~2,000,000 kg of Astrophage represents on the order of **~1.8×10²³ J** — roughly 20× the energy of all global oil reserves.

**2.4 Spin drive (CANON)**
- **1,009** individual engines (Dimitri built many small ones for redundancy: "one thousand and nine, actually"). Each is a transparent triangular ("revolver") mechanism cycling: (1) attract Astrophage to a face with low-intensity IR at the CO₂ lines (4.26/18.31 μm); (2) rotate the face to space and pulse high-intensity light so the cells discharge their 25.984 μm energy against the slide, imparting momentum; (3) rotate back, scrape off dead cells, repeat.
- A single spin drive can melt a metric ton of metal in a fraction of a second.

**2.5 Hail Mary trajectory (CANON + derived)**
- Distance to Tau Ceti: **11.9 light-years** (also cited 11.92 ly).
- Acceleration: **1.5 g** (accelerate to midpoint, flip 180°, decelerate).
- Max speed: **0.92 c**.
- Fuel: **~2,000,000 kg** Astrophage; dry/payload mass **~100,000 kg** (mass ratio ~21); fuel held in 3 cylindrical tanks × 3 sections = **9 sections**.
- Travel time: **~13 years Earth-frame; ~3.9–4 years ship-frame** (time dilation; Grace's proper time). One character notes 13 years each way (needing ~26–27 years total for a round-trip data return). Return trip is shorter in proper time (~4–5 yr) because the refueled ship carries less mass.
- Console velocity on waking: **11,872 km/s**; local-maneuver cruise after a 3-hour burn: **162 km/s** (that maneuver consumes 130 kg fuel). The small "Beetle" probes are a separate case: 500 g to 0.93 c.
- Relativistic rocket relations (REAL): ship-frame time per half-leg τ = (c/a)·cosh⁻¹(1 + a·d/c²); Tsiolkovsky Δv = v_e·ln(m₀/m_f) with exhaust velocity v_e = c for a photon drive.

**2.6 Stellar-dimming math (CANON)**
- Onset: Sun **0.01%** dimmer than expected. Projection: **1% drop over 9 years; 5% at 20 years; up to 10% total**, over a ~30-year horizon. Result: **10–15 °C** global temperature drop → ice age. One in-book projection: **3.5 billion dead in 19 years**. The dimming curve is exponential (matches ~8-day Astrophage doubling).
- Real-world context: per NASA's TSIS-1 mission, total solar irradiance "fluctuates by about 0.1 percent over the course of the Sun's 11-year cycle," and luminosity rises ~10% per billion years — so the book's rate is dramatically accelerated for fiction.

**2.7 Blip-A (CANON + derived)**
- Eridian ship; length **139 m** (~3× the Hail Mary); constructed of **xenonite**; set out with **31,000,000 kg** Astrophage (over-fueled because the Eridians didn't know relativity and used Newtonian math); interior ~29 atm ammonia at ~210 °C; 23 crew, one survivor (Rocky). Acceleration ~**2.2 g** is a physicist's *inference* (≈ Erid surface gravity), not stated text.

### 3. REAL PHYSICS FOR AN ACCURATE SIMULATOR

**3.1 The 25.984 μm Petrova light**
- Wavelength: 25.984 μm = 25,984 nm.
- Frequency: f = c/λ = 2.998×10⁸ / 25.984×10⁻⁶ = **1.154×10¹³ Hz ≈ 11.54 THz**.
- Photon energy: E = hf = 6.626×10⁻³⁴ × 1.154×10¹³ = **7.65×10⁻²¹ J = 0.0478 eV**.
- Spectral location: **mid/far-infrared** (thermal IR), completely invisible to the human eye. Weir's likely rationale: 25.984 μm is the Compton wavelength (λ = h/mc) of a ~0.0478 eV / ~8.5×10⁻³⁸ kg particle — a plausible neutrino mass scale.
- Visualization: since it's invisible, any color mapping is a choice. The film maps it to **glowing pink/magenta**; a physically-motivated alternative is a deep-red "false-color IR" palette.

**3.2 CO₂ vibrational modes (REAL)**
- Asymmetric stretch (ν₃): **4.26 μm (2,349 cm⁻¹)** — the strongest IR-active CO₂ band (one of the strongest absorption bands of any small molecule, per FTIR literature).
- Bending mode (ν₂): **~15 μm (667 cm⁻¹)** — the real dominant terrestrial band (per GeoExpro's climate-research review, "IR radiation at 667 cm⁻¹ (15 μm) excites these vibrations"). *(Note: the book uses 18.31 μm as Astrophage's second CO₂ target line; the canonical real bending band is ~15 μm — treat 18.31 μm as an artistic offset. Weaker/hot bands at 2.7 and 2.0 μm also exist.)*
- Symmetric stretch (ν₁): IR-inactive (no dipole-moment change).
- The Petrova line (25.984 μm) does **not** correspond to a CO₂ band; it is Astrophage's own emission. The 4.26/18.31 μm lines are only the *navigation* cue.

**3.3 Black-body radiation (REAL)**
- Planck's law: B(λ,T) = (2hc²/λ⁵) · 1/(e^{hc/λkT} − 1).
- Wien: λ_max = 2.898×10⁻³/T. At 96.415 °C = 369.6 K, λ_max ≈ **7.84 μm** — importantly *different* from the 25.984 μm emission, underscoring that the Petrova line is a discrete quantum-annihilation line, not thermal emission.
- Stefan–Boltzmann: j = σT⁴, σ = 5.67×10⁻⁸ W/m²·K⁴.

**3.4 Matter-to-energy efficiency (REAL)** — fission ~0.1%, fusion ~0.7%, antimatter 100%; Astrophage ~100% (near antimatter).

**3.5 Orbital mechanics (REAL vs book)** — A real Venus–Sun transfer would be a Hohmann ellipse (months of coasting); the book uses continuous high-thrust "brachistochrone"-style arcs, which is why the Petrova line appears as a continuous glowing arc from the star's pole to the planet rather than a coasting ellipse.

**3.6 Cell-scale physics (REAL)** — At 10 μm in a fluid, motion is low-Reynolds-number (Re ≪ 1, viscous-dominated) with significant Brownian motion; in vacuum near a star it is ballistic plus radiation-pressure/photon-thrust driven. Surface tension dominates any liquid interface at this scale.

### 4. VISUAL / AESTHETIC REFERENCE

- **Astrophage appearance:** individually, tiny black dots; in bulk, a matte "blacker-than-black" powder that absorbs all light. Under a microscope, live cells are opaque black and visibly *move* (the tell that they're alive); dead cells go translucent.
- **Petrova line from space:** a faint glowing infrared arc extending from the star's (north) pole to engulf the breeding planet (Sun→Venus). Invisible to the eye; visible only in the 25.984 μm band via a "Petrovascope."
- **Film (2026):** cinematographer Greig Fraser used two ARRI Alexa 65 cameras on a crane and modified one by **removing its internal infrared-cut filter** (confirmed by No Film School, 27 Mar 2026; the close-up Astrophage was practical while wide shots were digital from ILM, per Christopher Miller). Director Christopher Miller described taking the IR-blocking filter out to "[make] this beautiful pinkish, reddish color" and surrounding Ryan Gosling "with a bunch of chicken wire filled with infrared lights that were sparkling"; Phil Lord added that Fraser "built an aquarium, sort of like a double-glass window with a hose that was dripping water through it." Colorist **David Cole** then "isolate[d] and manipulate[d] those specific invisible light spectrums in the grade" (Filmmakers Academy) to produce the glowing pink/magenta Petrova radiation. The production reportedly used **zero green/blue screens**. The EVA-in-the-Petrova-line scene shows Astrophage as swirling pink points of light.
- **Ships:** the Hail Mary runs 1,009 spin drives (glow driven by making 25.984 μm IR visible); the **Blip-A** is a xenonite Eridian ship, 139 m, ~3× the Hail Mary, redesigned for the film to look distinctly alien.

### 5. FAN / COMMUNITY TECHNICAL ANALYSIS

- **Weir's own admissions (interviews):** the single deliberate physics break is Astrophage's quantum "super cross-sectionality" (neutrino trapping) — he wants internal consistency above all. He even worked out the Eridians' "wrong" Newtonian math to justify why Rocky has leftover fuel to give Grace.
- **Known issues a simulator builder should note:**
  - *Second Law of Thermodynamics:* Astrophage extracts work from pure heat with no cold reservoir. Weir's patch: the neutrino store acts as a near-zero-temperature heat sink. Multiple physicist reviewers call this the story's one true physics violation.
  - *Conservation of energy w/ Taumoeba:* eating a cell full of ~1.5 MJ but leaving only sludge — resolved by Weir's claim that the predator only consumes the chemical/biomass energy, not the neutrino store.
  - *Radiation at 0.92 c:* interstellar-medium impacts are handled via the super-cross-sectional Astrophage radiation shield.
  - *Energy mismatch:* the Sun emits ~10²⁶ W; critics (e.g., astrophysicist Jacqueline McCleary) note that a microbe storing enough to matter is many orders of magnitude beyond real biology.
  - *Return-trip solar-wind asymmetry, magnetic-field navigation inconsistencies, and neutrino detection* are acknowledged hand-waves.
- **Existing fan artifacts:** CG spin-drive animations (e.g., a Japanese creator's recreation widely shared on X), 3D-printable Blip-A models (MakerWorld), "Powered by Astrophage" merch/prints; no full physics simulator was identified — a genuine gap this project would fill.

---

## Recommendations (staged build plan)

**Stage 1 — Single-cell model (canon-locked).** Model a 10 μm black sphere, mass 0.021 ng, internal temperature clamped to 96.415 °C, with an energy reservoir 0–1.5 MJ and dynamic mass = 0.021 ng + (E/c²). Render it as pure black (albedo ≈ 0) in visible light; add a "Petrovascope mode" that maps its 25.984 μm emission to pink/magenta (film-accurate) or false-color red. *Benchmark to change approach:* if scientific IR realism matters more than cinematic feel, switch the color map to a calibrated thermal-IR LUT.

**Stage 2 — Behavior/physics layer.** Implement the heat-sink/heat-source thermostat; navigation toward light and toward CO₂ 4.26/18.31 μm sources; thrust via F = P/c with exhaust modeled at 25.984 μm; low-Reynolds Brownian motion in fluids, ballistic + radiation-pressure motion in vacuum; aerobraking stop at 0.02 atm. Add Taumoeba as a nitrogen-sensitive predator agent.

**Stage 3 — System scale.** Render the Petrova line as a continuous brachistochrone arc (not a Hohmann ellipse) from the star's pole to the CO₂ planet, visible only in Petrova-band mode. Model exponential population growth (~8-day doubling) driving stellar dimming (0.01% → 1%/9 yr → 5%/20 yr → 10%/30 yr) and the resulting 10–15 °C cooling.

**Stage 4 — Ship / mission scale.** Hail Mary: 100,000 kg dry, 2,000,000 kg fuel, 1,009 spin drives, 1.5 g, 0.92 c, 11.9 ly, relativistic time dilation (~13 yr Earth / ~4 yr ship). Include the Blip-A (139 m, 31,000,000 kg) as a contrast object.

**Scale/visualization strategy:** use logarithmic zoom levels spanning 10⁻⁵ m (cell) → 10¹¹ m (Venus–Sun Petrova arc) → 10¹⁷ m (~12 ly journey); provide a "Petrovascope toggle" as the unifying visual motif across all scales, so the invisible-IR signature is the through-line that ties micro to macro.

### Suggested parameter table (units flagged canon / derived / invented)

| Quantity | Value | Unit | Status |
|---|---|---|---|
| Cell diameter | 10 | μm | CANON |
| Cell rest mass | 0.021 | ng | CANON (wiki) |
| Cell density | ~1,000 | kg/m³ | DERIVED |
| Internal temperature | 96.415 | °C (369.6 K) | CANON |
| Max stored energy | 1.5 | MJ/cell | CANON |
| Mass gain when full | 17 | ng | CANON |
| Petrova wavelength | 25.984 | μm | CANON |
| Petrova frequency | 11.54 | THz | DERIVED |
| Petrova photon energy | 0.0478 | eV (7.65×10⁻²¹ J) | DERIVED |
| CO₂ navigation lines | 4.26 / 18.31 | μm | CANON |
| Max velocity | 0.92 | c | CANON |
| Spore travel range | 8 | ly | CANON |
| Reproduction doubling | ~8 | days | CANON |
| Aerobrake stop pressure | 0.02 | atm | CANON |
| Hail Mary dry mass | ~100,000 | kg | CANON |
| Hail Mary fuel | ~2,000,000 | kg | CANON |
| Spin drives | 1,009 | — | CANON |
| Ship acceleration | 1.5 | g | CANON |
| Distance to Tau Ceti | 11.9 | ly | CANON |
| Earth-frame trip time | ~13 | yr | CANON |
| Ship-frame trip time | ~4 | yr | CANON |
| Blip-A length | 139 | m | CANON |
| Blip-A fuel | 31,000,000 | kg | CANON |
| Hail Mary length | ~46 | m | INFERRED (not stated) |
| Total wild Astrophage mass | — | — | UNSTATED/invent |

## Caveats

- **Canon vs. invented, clearly flagged:** Hard canon — 10 μm, 0.021 ng, 96.415 °C, 1.5 MJ/17 ng, 25.984 μm, 0.92 c, 8 ly spore range, 1.5 g, 11.9 ly, 1,009 spin drives, 2,000,000 kg fuel, 100,000 kg dry, Blip-A 139 m / 31,000,000 kg, CO₂ lines 4.26/18.31 μm, dimming 1%/9 yr–5%/20 yr–10%/30 yr, Taumoeba nitrogen sensitivity. **Derived** — density ~1,000 kg/m³, Petrova frequency/photon energy, photon-drive power, black-body λ_max, Compton-wavelength rationale for 25.984 μm. **Unstated/invented** — total wild-population Astrophage mass, exact Hail Mary length (~46 m inferred from "Blip-A is 3× longer"), per-scene glow color (film uses pink/magenta).
- **Two prompt errors corrected:** 96.415 is °C, not THz; the Petrova line is 25.984 μm (~11.5 THz), not 3.11 μm / 96.415 THz.
- **Source-conflict resolutions:** per-cell energy is **1.5 MJ** (a "1,500 J" blog figure is an error, contradicted by the book's explicit 1 kW × 25 min = 1.5 MJ and the 17 ng mass gain); cell mass is **0.021 ng** (not a ~0.5 ng blog estimate); Blip-A's 2.2 g and the Hail Mary's ~46 m length are inferences, not stated text; the specific "3 fuel bays jettisoned" detail is plausible but not independently confirmed (9 sections across 3 tanks is confirmed).
- **Source quality:** hard numbers come from the novel via fan wikis and Goodreads book-quote highlights, cross-checked against physics blogs (Science Meets Fiction, timandersen, thescienceof.org), Physics Forums, and author interviews (Planetary Society, Astronomy.com, Space.com, Scientific American). Film-production details (pink/magenta grade by colorist David Cole, IR-filter-removed Alexa 65 per No Film School, chicken-wire/water rigs per Lord & Miller, no green screen) come from press coverage of the March 2026 release and reflect creative choices, not physics.