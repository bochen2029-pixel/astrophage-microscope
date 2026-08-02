# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m6-green`. Next milestone: M7 — Light.**

**Three of the five signature phenomena are live.** 15 tests green, 8 goldens, 7 audit checks clean.

- **P1** drift velocity linear in charge, zero crossing at 3.00577 %
- **P2** 2000 awake cells pin the medium at max 369.56 K against a 369.565 setpoint; never boils; driven to 400 K it relaxes back while cell energy rises
- **P3** ignition latch survives cooling to 20 °C
- **P4** motility ratio 4.357, matching the oracle exactly
- **P5** is M7 — the last one

## Start here

```bash
git -C C:\Astrophage tag --list
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M7 section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§6 and §7.5–7.6** → `docs/RENDERING.md` **§4–§5** → `src/render/MODULE.md`.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M6
build/astrophage.exe
```

## What M7 is — the milestone that completes the set

- **Petrova emission**: directional lobe, `PETROVA_SLEW_RATE`, photon thrust `F = P/c` (the pure functions already exist and T6 already passes).
- **Irradiance field with TOTAL occlusion** → **P5**. Albedo is exactly 0, so irradiance behind a live cell is exactly **zero**, not "very small". Tests assert exact zero.
- **Feeding**: `P_absorbed = E_directional·πa² + E_ambient·4πa²`.
- **View modes**: Petrovascope (magenta, non-emitting cells *invisible*) and Thermal IR. **They must read differently** — the Petrova line is a discrete 25.984 μm quantum line, the thermal peak is 7.841 μm blackbody. A live idle cell glows in Thermal and is dark in Petrovascope. If the two modes ever agree, a real physical distinction has been lost.
- **Bloom** on Petrova emission only.

**Gate:** M6 gate + T13 (rear cell in a collinear pair: irradiance exactly 0, dCharge/dt exactly 0), T15 (Komorov: 1 kW × 1500 s ⇒ 1.5 MJ and 16.69 ng within 0.1 %), T16, T17, T20.

## Hard-won lessons that apply directly to M7

- **The grid is the far field** (ADR-020). The irradiance field will have the same temptation: do not try to make it resolve sub-grid structure. Occlusion is a ray march, not a diffusion.
- **Match the sample to the source.** A lumped exchange needs `grid_sample_nearest`/`grid_deposit_nearest`; bilinear reads back only `Σw²` of what it writes. Irradiance is read-only per cell, so bilinear is fine there.
- **When a number is wrong, check whether it says "no feedback" or "wrong coefficient".** The 1.76e6 K runaway was diagnosed by noticing the energy rate equalled the free-space rate exactly.
- **Do not guess a threshold — derive it.** Every invented cutoff this build has been wrong. Size a test from the physics (e.g. run length from `store / conduction rate`).
- **Fusing across a documented tick-stage boundary is a correctness change** (ADR-018). Emission reads neighbour occlusion; if it reads what another kernel writes, they are separate stages.
- **Regenerating goldens needs a `DECISIONS.md` entry in the same commit.** M7 changes what cells emit, so the goldens will likely move — the golden scenario currently spawns *dormant* cells, which is why M6 left them untouched.

## Performance state

200k cells at ~281 ticks/s (0.28× real time) before M6; the thermal stage adds 10 kernel launches per tick. **Two named levers, both untouched:**

- **Q9** — the neighbour walk visits **27 buckets when 8 would do** (`cell_size` 22 μm ≥ 2 × 10 μm contact range). ~3.4× on the dominant cost.
- **Q8** — defocus overdraw: cull cells below the fragment discard threshold in the vertex stage. **Bloom lands on top of this in M7**, so take it if the frame budget tightens.

## Open questions

- **Q1** App `--headless` and `tools/headless` stay separate deliberately.
- **Q5** When M9 adds slot reuse, confirm `spawn_kernel` clears `vx/vy/vz`.
- **Q6** `MotionConfig` flags (`thermal_noise`, `contact_enabled`, `adhesion_enabled`, `thermal_enabled`) are test-only; a scenario wanting them needs fields in `scenario_v1.h`.
- **Q7** `optics.h` and the GLSL duplicate four formulas with no compiler check (ADR-017).
- **Q10** Contact cannot hold a fully charged cell at `dt` = 1 ms (ADR-018 §3). Bounded and tested; needs substepping if M9 produces dense charged cultures.
- **Q11** The SoA is not reordered by bucket, contrary to M4's stated scope. Deliberate.
- **Q12 (new)** `shell_conductance` is kept in `thermal.cuh` but deliberately unused, with its reasoning preserved. If someone later needs a resolved near field, that is the right starting point — but re-read ADR-020 first.
