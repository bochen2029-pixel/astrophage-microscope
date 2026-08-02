# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m7-green`. Next milestone: M8 — Taxis.**

**All five signature phenomena are live.** The physics core is complete; everything remaining adds behaviour and content on top of it. 16 tests green, 8 goldens, 7 audit checks.

| | measured |
|---|---|
| **P1** | drift velocity linear in charge, zero crossing at 3.00577 % |
| **P2** | 2000 awake cells pin the medium at max 369.56 K vs a 369.565 setpoint; never boils; driven to 400 K it relaxes back while cell energy rises |
| **P3** | ignition latch survives cooling to 20 °C |
| **P4** | motility ratio 4.357, matching the oracle |
| **P5** | adjacent collinear pair: rear cell at bitwise `0.0`. 8000 cells: charge-vs-depth r = −0.879, 8× lit/far ratio |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M7
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M8 section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§8 only** → `src/sim/MODULE.md`.

## What M8 is

`PHYSICS.md` §8. Run-and-tumble taxis, and it is mostly plumbing on top of parts that already exist.

- **Temporal-comparison gradient climbing** (ADR-007), not spatial finite differences: a 10 μm cell cannot meaningfully difference a 7.8 μm grid across its own body, and a smooth glide reads as a video game. `taxis_memory` and `run_timer` are already in the cell store and unused.
- **FEED / BREED / IDLE** state machine keyed on charge and the darkness rule. `TAXIS_DARK_THRESHOLD` and both seek thresholds are already in canon.
- **CO₂ chemotaxis** — the CO₂ field, its brush, and per-cell sampling all exist from M5/M6; only the controller is missing.
- Emission direction already slews (`slew_toward`, tested). Thrust already works (T6). **The taxis controller just needs to set `emit_power` and the commanded heading.**

**Gate:** M7 gate + a population in a light gradient migrates measurably up-gradient (mean position shift > 3σ of the null over 10⁴ ticks); cells in darkness show zero emission and pure Brownian statistics.

## The pattern that has caught three bugs — check for it first

**ADR-019, ADR-020, ADR-021 are the same lesson.** A grid field is depth-averaged, 2D, and far-field. Whenever a claim is about *individual bodies* — a 1/r profile, a cell's own conduction, an exact shadow — the grid is the wrong instrument and the answer is per-cell via the spatial hash.

M8 will meet it again: **a cell's own CO₂ uptake will contaminate the grid cell it samples**, exactly as its own heat did in M6. Decide up front whether the taxis signal is far-field (grid) or near-field (per-cell), and do not let a cell chase its own depletion halo.

## Other hard-won rules

- **Do not guess a numeric threshold — derive it.** Every invented cutoff this build has been wrong. Size a test from the physics.
- **When a gate fails, first ask whether it asks the right question.** Four times now the failing threshold was the *test's* fault and the corrected test came out stricter.
- **Fusing across a documented tick-stage boundary is a correctness change** (ADR-018), not an optimisation.
- **Match the sample to the source.** Lumped exchanges need `grid_sample_nearest`/`grid_deposit_nearest`; bilinear reads back only `Σw²` of what it writes.
- **Regenerating goldens needs a `DECISIONS.md` entry in the same commit** (Iron Rule 10).

## Deferred, with reasons

- **Bloom and the Petrovascope/Thermal-IR view modes** were in M7's scope and are **not done** — the physics gate took the milestone. The enum values and `u_mode` uniform are plumbed; `cells_pass.cpp` currently renders modes 1–4 through the Analysis branch. `RENDERING.md` §4 has the spec, and the key constraint is that Thermal IR and Petrovascope must read *differently* (7.841 μm blackbody vs a 25.984 μm quantum line — a live idle cell glows in one and is dark in the other). Do this at M11 with the rest of the UI, or as a standalone M7b.
- **Q9** — the neighbour walk visits **27 buckets when 8 would do** (`cell_size` 22 μm ≥ 2 × 10 μm range). Now used by *both* contact and occlusion, so the win has doubled. This is the single best performance lever available.
- **Q8** — defocus overdraw: cull cells below the fragment discard threshold in the vertex stage.
- **Q10** — contact cannot hold a fully charged cell at `dt` = 1 ms (ADR-018 §3); needs substepping if M9 makes dense charged cultures.
- **Q12** — `shell_conductance` is kept but deliberately unused; read ADR-020 before reaching for it.
- **Q13 (new)** — light is axis-aligned only (ADR-021). A sheared sweep needs atomics or a rotated buffer. Fine for P5; revisit only if a scenario needs oblique illumination.
