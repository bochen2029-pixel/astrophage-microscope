# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Starting a brand-new session?** Paste [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> instead. It is the self-contained version: same status, plus the accumulated
> meta-lessons, the process rules, and every open question with its reasoning. This
> file is the terse form for a session already oriented.

---

## Where the build stands

**Last green: `m7b-green`. Next milestone: M10 — Predation.**

**All five phenomena live. Cells behave, look like organisms, divide reproducibly, die, report telemetry, run on a multi-rate clock, and all five view modes draw distinctly.** 21 tests green, 12 goldens, 10 audit checks, 29 ADRs.

| | measured |
|---|---|
| **P1** | drift velocity linear in charge, zero crossing at 3.00577 % |
| **P2** | 2000 awake cells pin the medium at max 369.56 K; never boils |
| **P3** | ignition latch survives cooling to 20 °C |
| **P4** | motility ratio 4.357, matching the oracle |
| **P5** | adjacent collinear pair: rear cell at bitwise `0.0`; 8000 cells: charge-vs-depth r = −0.879 |
| **M8** | migration **26.0σ**; darkness bit-identical to the taxis-off null |
| **M9a/b** | doubling **1.996**; 2,000 → 50,508 bit-reproducible (T22); void corpses 40.1 kg/m³ |
| **M9c clock** | preset ratios exact — physics **10.0000**, biology **2.00000**, compounding **1.00000**; T22 unchanged at 50508 / `130793f3` (bit-identical to M9b at rate 1) |
| **M9c compaction** | T22b: 50378 cells, **914 deaths reclaimed**, identical hash `42d459c3` through division + death + contact |
| **M7b modes** | Thermal vs Petrovascope mean **34.1**, max **252** — a live idle cell glows in one, dark in the other |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M9c
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M10 section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§11** → `src/sim/MODULE.md` → **ADR-014, ADR-018, ADR-022, ADR-025**.

## What M10 is

Predation. `TaumoebaStore` (its own SoA, same patterns as `CellStore`), amoeboid crawl biased up the cell-density gradient, engulfment on overlap with a live cell, digestion, the **N₂ field and its lethality**, and **heritable N₂ tolerance with mutation**.

**Gate.** M9c gate + a predator introduction crashes the population; under a slowly rising N₂ ramp the mean tolerance rises monotonically on a 5-generation moving average, and a strain with tolerance ≥ 0.825 (**Taumoeba-82.5**) appears within 40 generations at default `TAU_MUTATION_SIGMA` — by genuine directional selection, **not by script** (`SCENARIOS.md` §6).

**Three things it will confront:**

1. **A second organism store.** `predation.cu` is in the module map but empty. It gets its own OU integrator (own γ from `TAU_DIAMETER`), its own PCG32 streams keyed on a Taumoeba id, and its own compaction — reuse the M9c primitive (`cell_store_compact` is the template; the Taumoeba store needs the same buffers). Evolution means Taumoeba divide and die, so this is the first store since the cell store to exercise reproducible birth/death — T22's argument all over again for a new store.
2. **N₂ is the fourth field** and it already exists (`FIELD_N_N2` = 128², a brush source at M5). M10 gives it a cell/Taumoeba coupling: a lethality hazard `max(0, N − N_lethal·(1 + tol·k))` and a Poisson death. Heritable `tolerance ∈ [0,1]` on the daughter is `parent + N(0, TAU_MUTATION_SIGMA)`, clamped — a real draw from the Taumoeba's stream, so determinism must survive it.
3. **The 82.5 arc must EMERGE.** The gate forbids scripting it. It is directional selection under a rising ramp; if you find yourself special-casing 0.825, stop — the model is wrong (this is the P1–P5 rule for the evolution feature).

## The clock and compaction, now that they exist (M9c)

- **`physics_rate` scales the physics dt; `biology_rate` the growth dt, compounding.** At rate 1 everything is bit-identical to M9b. The M10 Taumoeba clocks: crawl/engulf are physics, digestion/division are biology (ADR-011). Wire them the same way `lifecycle_step` uses `dt_bio`.
- **Compaction is opt-in (`MotionConfig::compaction_enabled`) and off by default.** It reclaims corpses via a stable prefix-sum out-of-place gather (ADR-028). The Taumoeba store wants the same. **Q19 stands:** `biology_rate` does not scale field diffusion — that includes the N₂ field, so a fast-biology predation run is transport-limited the same way growth is. Say so, do not fake it.

## The four lessons this build keeps re-learning

- **When a claim is about individual bodies, the grid is the wrong instrument** (ADR-019/020/021), except when it is genuinely region-scale (ADR-022 §1). Engulfment is a *contact* event (per-cell, via the hash), not a field one.
- **A gate that PASSES while the thing is broken is worse than one that fails.** Assert the minimum, not the total (ADR-025). Ask what your assertion cannot see.
- **A measured symptom is not a diagnosis.** Predict, change, **re-measure** (ADR-024).
- **Correctness tests cannot see performance.** The 200k benchmark (M1.5) is the only thing that catches a per-tick regression; a second organism store doubling the D2H traffic is exactly its kind of bug.

## Deferred, with reasons

- **M7b remainder — bloom over Petrova, the cross-fade mode slider, the Thermal field-halo term.** The modes read differently now (that was the teaching moment); bloom is the *look* (swirling points of pink light) and is pure render polish. The one piece that needs a contract change: **pre-ignition warm-up** of a heated-but-still-dormant cell needs real `temp_cell` in the instance → `render_view_v3`. The awake flag is exact for awake-vs-dormant but binary.
- **Q20 remainder** — the birth prefix is CUB `DeviceScan` now, but the neighbour walk still visits **27 buckets when 8 would do** (Q9). Best remaining perf lever; used by contact, occlusion, and now Taumoeba density-sensing.
- **Q18** — the tumble rule has no refractory period; 3.6 % of cells are on a real run. Fix is a rate-based Poisson tumble, not a hard minimum run. Taumoeba use the same run-and-tumble, so this matters for M10's crawl too.
- **Q15** — re-aiming is instantaneous; needs a commanded-heading field (`cell_store_v2.h`). 26.0σ is an upper bound.
- **Q14** — dormant cells charge; light-driven ignition is the canon-consistent alternative. Own ADR.
- **Q7 / ADR-017** — **six** formulas now mirrored across the GLSL boundary (added `petrova`). Q7's trigger is well past met: generate the GLSL from the header.
- **Q10** — contact cannot hold a fully charged cell at `dt` = 1 ms; needs substepping if a scenario makes dense charged cultures. Compaction at high `physics_rate` already softens contact (`k ∝ 1/physics_rate`, ADR-027), so a dense charged culture on the Motion preset overlaps more — bounded, not a bug.
- **Test suite cost** — `ctest` ~4–6 min now (T22b added a growth run). Kept deliberately.
