# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Starting a brand-new session?** Paste [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> instead. It is the self-contained version: same status, plus the accumulated
> meta-lessons, the process rules, the deferred work, and all the open questions.
> This file is the terse form for a session already oriented.

---

## Where the build stands

**Last green: `m8b-green`. Next milestone: M9 — Life.**

**All five signature phenomena are live, cells behave, and they look like organisms.** 18 tests green, 9 goldens, 10 audit checks.

| | measured |
|---|---|
| **P1** | drift velocity linear in charge, zero crossing at 3.00577 % |
| **P2** | 2000 awake cells pin the medium at max 369.56 K vs a 369.565 setpoint; never boils |
| **P3** | ignition latch survives cooling to 20 °C |
| **P4** | motility ratio 4.357, matching the oracle |
| **P5** | adjacent collinear pair: rear cell at bitwise `0.0`; 8000 cells: charge-vs-depth r = −0.879 |
| **M8** | migration −262.6 μm = **20.3σ**; darkness **bit-identical** to the taxis-off null |
| **M8b** | silhouette area-preserving to **1.6e-14**; all 8 measurement goldens unchanged at mean **0.0000** |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M8b
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M9 section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§10 and §12 only** → `src/sim/MODULE.md` → **ADR-022, ADR-011, ADR-004, ADR-014**.

## What M9 is

Biomass, CO₂ uptake, mitosis with energy halving and RNG splitting, death paths, corpse rendering, the store-disposition toggle (ADR-004), the multi-rate clock (ADR-011), charts.

**Gate:** M8 gate + T18 (doubling matches `LIFE_DOUBLING_TIME` within 2 % under non-limiting CO₂); growth halts within one doubling of CO₂ exhaustion; **T22 — a run in which cells divide is bit-reproducible**, which is the real test of ADR-014.

**Three things M9 inherits, all in ADR-022:**

1. **CO₂ uptake is the depletion halo M8 guarded against.** Two protections exist and must survive: taxis samples at stage 3 *before* the cell's own deposit at stage 7, and temporal comparison is blind to a roughly-constant self-offset. `TAXIS_RUN_MAX` is the backstop for a cell that outruns its own halo — **it is not decoration, do not remove it for looking arbitrary.**
2. **Stage 2 (`field_sample`) is fused into `motion_step`**, so taxis reads a `co2_local` one tick old. Negligible at M8; re-examine when uptake lands. Unfusing a stage is a correctness change in *both* directions (ADR-018).
3. **Stage 11 (`stats`) has never shipped.** `world_stats` returns only tick, time and counts. M9's charts are its first real consumer. It needs a deterministic device reduction — tree or fixed-point, **never `atomicAdd` on float** (INV-2).

Also confirm `spawn_kernel` clears `vx/vy/vz` when M9 adds slot reuse (Q5). It does today, but only incidentally.

## Q16 — the taxis controller is mistuned, and the fix is a 20-minute job

**This is the most valuable thing M8 found and it is deliberately not fixed.** The gate passes at 20σ, but a run-age diagnostic in `test_taxis` shows **54.2 % of cells tumbling within the last 2 ticks** and a mean run age of 0.185 s against an 8 s cap — Δ ≤ 0 ends essentially every run and the cap almost never fires.

The cause is a clean timescale mismatch:

| | |
|---|---|
| swim speed of an **awake** cell | 6105 μm/s (`PETROVA_MAX_POWER`/c ÷ `DRAG_COEFF_SETPOINT`) |
| time to cross the 4 mm chamber | **0.66 s** |
| gradient e-folding traversal | 0.315 s |
| `TAXIS_MEMORY_TIME` | **2 s — 3.1× a full chamber crossing** |

A cell compares against a baseline older than the entire gradient. Bias efficiency is 0.4 % of path length, so there is a lot of headroom.

**The criterion, so this is a decision and not a guess: τ ≲ the e-folding traversal time**, `L_efold · γ · c / P` ≈ 0.3 s here. `TAXIS_MEMORY_TIME`'s canon range is already (0.05, 60.0), so no range change is needed. Expect the migration figure to improve and the tumble rate to fall to something that looks like an organism rather than jitter.

Not done at M8 because it is a constants decision touching **ADR-005** (why 50 mW) and **ADR-007**, and starting one from green at session end is how a session ends red. It needs its own ADR.

## Q15 — re-aiming is instantaneous

`PETROVA_SLEW_RATE` is unused by the controller. Rate-limiting the re-aim needs the *commanded* heading stored separately from the current axis, and `cell_store_v1.h` has no such field — `dir_*` is the current axis and the heading is its negation, so slewing toward a target reconstructed from that axis is circular. A `cell_store_v2.h` change. **Direction of the error is known: instantaneous re-aim makes taxis strictly more effective, so 20.3σ is an upper bound.** `TAXIS_TUMBLE_SLEW_TIME` (1.19 s) is derived and carried so the cost stays visible. Entangled with Q16 — resolve them together.

## Q14 — dormant cells charge, and probably should not

`feed_kernel` checks `OCCUPIED|ALIVE` only, so a dormant cell accumulates neutrino store while running none of its machinery. Absorption itself is not optional (albedo is 0), but the physically consistent alternative is that absorbed light *warms* a dormant cell and ignites it on crossing 96.415 °C — **light-driven ignition**, which is canon-consistent and would be a lovely emergent path. New behaviour; needs its own ADR. Do not smuggle it into another milestone.

## The pattern that has caught three bugs

**ADR-019, ADR-020, ADR-021 are the same lesson.** A grid field is depth-averaged, 2D, and far-field. Whenever a claim is about *individual bodies* — a 1/r profile, a cell's own conduction, an exact shadow — the grid is the wrong instrument and the answer is per-cell via the spatial hash. M8 met it a fourth time and **decided the other way on purpose**: BREED is a region-scale claim, so the grid is correct there (ADR-022 §1).

## Other hard-won rules

- **Do not guess a numeric threshold — derive it.** M8 added two constants: the clamped tumble mean is derived in `derive.py` and asserted directly rather than hidden behind a wide tolerance, and `TAXIS_RUN_MAX` is derived from `TAXIS_MEMORY_TIME` so it cannot drift away from it. No CO₂-availability constant was invented at all — `co2 > 0` is the whole test.
- **Use `DRAG_COEFF_SETPOINT`, not `DRAG_COEFF_20C`, for any timescale argument about live cells.** M8 estimated a swim speed 3.46× too low by forgetting that P4 applies to thrust as much as to Brownian motion.
- **When a gate fails, first ask whether it asks the right question.** Still 4-for-4.
- **Regenerating goldens needs a `DECISIONS.md` entry in the same commit** (Iron Rule 10).
- **A9 has no waiver in use.** If it flags a literal, prefer removing the need for it — M8's `log(0)` guard vanished by sampling `1 − u` instead of `u`.

## Deferred, with reasons

- **Bloom and the Petrovascope/Thermal-IR view modes** were in M7's scope and are **not done**. The enum values and `u_mode` are plumbed; `cells_pass.cpp` renders modes 1–4 through the Analysis branch. `RENDERING.md` §4 has the spec. The constraint that matters: Thermal IR and Petrovascope must read *differently* (7.841 μm blackbody vs a 25.984 μm quantum line — a live idle cell glows in one and is dark in the other). Do it at M11 or as a standalone M7b.
- **DONE at M8b: Q8 and Q17.** Vertex-stage defocus culling and irregular morphology both shipped (ADR-023). What is left of `RENDERING.md` §8: lateral chromatic aberration and procedural medium texture (both carry honesty caveats — aberration displaces pixels and must never reach a measurement golden; a debris speck miscounted as a cell is a bug in a simulator built to count cells), and faceting, since the outlines are lobed rather than angular.
- **Q9** — the neighbour walk visits **27 buckets when 8 would do** (`cell_size` 22 μm ≥ 2 × 10 μm range). Used by contact *and* occlusion, so the win has doubled. Still the single best performance lever.
- **Q10** — contact cannot hold a fully charged cell at `dt` = 1 ms (ADR-018 §3); needs substepping if M9 makes dense charged cultures.
- **Q11** — the SoA is not reordered by bucket, contrary to M4's stated scope. Revisit only with profiling evidence.
- **Q12** — `shell_conductance` is kept but deliberately unused; read ADR-020 before reaching for it.
- **Q13** — light is axis-aligned only (ADR-021). A sheared sweep needs atomics or a rotated buffer.
- **Test suite cost.** `ctest` is now 3m43s; `test_taxis` alone is 41.5 s (two 10⁴-tick 8000-cell runs). Kept deliberately — it is the specified gate and it passes at 20σ. If the suite becomes a problem, that is an ADR, not a quiet trim.
