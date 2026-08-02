# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **Starting a brand-new session?** Paste [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> instead. It is the self-contained version: same status, plus the eleven accumulated
> meta-lessons, the process rules, and every open question with its reasoning. This
> file is the terse form for a session already oriented.

---

## Where the build stands

**Last green: `m9b-green`. Next milestone: M9c — Life: clock, compaction, charts.**

**All five phenomena live. Cells behave, look like organisms, divide reproducibly, die, and report telemetry.** 20 tests green, 9 goldens, 10 audit checks, 26 ADRs.

| | measured |
|---|---|
| **P1** | drift velocity linear in charge, zero crossing at 3.00577 % |
| **P2** | 2000 awake cells pin the medium at max 369.56 K vs a 369.565 setpoint; never boils |
| **P3** | ignition latch survives cooling to 20 °C |
| **P4** | motility ratio 4.357, matching the oracle |
| **P5** | adjacent collinear pair: rear cell at bitwise `0.0`; 8000 cells: charge-vs-depth r = −0.879 |
| **M8** | migration **26.0σ**; darkness **bit-identical** to the taxis-off null |
| **M8b** | silhouettes area-preserving to **1.6e-14**; all 8 measurement goldens unchanged at mean **0.0000** |
| **M9a** | doubling **1.996**; a 2,000 → **50,508** cell run is bit-reproducible (T22) |
| **M9b** | 8 reductions of one state → **identical bit pattern**; `void` corpses 40.1 kg/m³ vs `retain` 25,500 |
| **perf** | 200k cells at **185.5 fps** with the HUD live, against a 144 target |

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M9b
```

Read: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M9c section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§12** → `src/sim/MODULE.md` → **ADR-011, ADR-018, ADR-025, ADR-026**.

## What M9c is

The multi-rate clock with its four presets (ADR-011), **the Q19 decision**, slot reuse and compaction, and the population/energy/temperature charts.

**Gate:** M9b gate + each preset advances biology and physics at its stated ratio; a run with compaction enabled is still bit-reproducible (T22 re-run).

**Three things it must confront:**

1. **Q19 — `biology_rate` does not scale diffusion, and M9c owns the clock.** ADR-011 assumed biology clocks are local and non-stiff; CO₂ uptake is an exchange with a field on *physics* time. At 2e7 a cell eats 2×10⁴ s of CO₂ per tick while the medium diffuses 10⁻³ s worth, so growth goes locally diffusion-limited at 25 % consumption and even a saturating control slows once dense. Decide whether fast presets scale CO₂ diffusion alongside, or whether the HUD simply says so. **Not a growth bug — it is the clock.** Needs an ADR either way.
2. **Compaction was deferred twice.** Reordering the SoA reorders contact-force summation (ADR-018's hazard). Own determinism argument, own T22 re-run.
3. **Q20 — `scan_kernel` is still single-threaded** when divisions occur. CUB `DeviceScan` is the answer, CUB is already allowed, and compaction needs the same primitive. Do them together.

## The four lessons this build keeps re-learning

- **When a claim is about individual bodies, the grid is the wrong instrument** (ADR-019/020/021). M8 met it a fourth time and **decided the other way on purpose** — BREED is region-scale, so the grid is right there (ADR-022 §1).
- **A gate that PASSES while the thing is broken is worse than one that fails.** M9a's CO₂ test asserted the *total* field stayed positive; negative pockets hid behind positive ones and the field sat at −0.128 kg/m³ with the suite green. Ask what your assertion cannot see.
- **A measured symptom is not a diagnosis.** M8's tumble-rate number was real; the causal story was backwards, and only re-measuring after the change exposed it. Predict, change, **re-measure**.
- **Correctness tests cannot see performance.** M9b went red on the 200k benchmark with all 13 correctness checks green. Fixing it took 145 → **185 fps** with **T22's hash unchanged** — which is what proves an optimisation behaviour-preserving.

## Other hard-won rules

- **Do not guess a numeric threshold — derive it**, and sometimes invent nothing at all (CO₂ availability is just `co2 > 0`).
- **Match the sample AND the units to the source.** M9a booked kilograms against a concentration-calibrated `deposit_scale`; it rounded to zero in fixed point and the rationing silently never fired.
- **Use `DRAG_COEFF_SETPOINT`, not `DRAG_COEFF_20C`, for any timescale about live cells** — P4 applies to thrust as much as to Brownian motion. `TAXIS_SWIM_SPEED` is derived and carried so nobody repeats that 3.46× error.
- **A9 has no waiver in use.** If it flags a literal, remove the need for it.
- **Look at the output.** Every test was green while the renderer drew snowflakes.
- **Regenerating goldens needs a `DECISIONS.md` entry in the same commit.** After `-Generate`, 1-LSB raster noise makes `git` show all goldens modified while `imgdiff` reports mean 0.0000 — revert those, keep only genuinely new ones.

## Deferred, with reasons

- **Bloom and the Petrovascope / Thermal-IR view modes** — still not done from M7. The constraint that matters: they must read *differently* (7.841 μm blackbody vs a 25.984 μm quantum line — a live idle cell glows in one and is **dark** in the other). The simulator's best teaching moment, still missing. `RENDERING.md` §4–§5.
- **Q9** — the neighbour walk visits **27 buckets when 8 would do**. Used by contact *and* occlusion. The best remaining perf lever.
- **Q18** — the tumble rule has no refractory period, so only 3.6 % of cells are on a real run. Fix is a rate-based Poisson tumble, **not** a hard minimum run (a 1.19 s floor commits a cell to 7.3 mm in a 4 mm chamber). Entangled with Q15.
- **Q15** — re-aiming is instantaneous; needs a commanded-heading field (`cell_store_v2.h`). Error direction known: 26.0σ is an upper bound.
- **Q14** — dormant cells charge; light-driven ignition is the canon-consistent alternative. Own ADR.
- **Q7 / ADR-017** — **five** formulas now mirrored across the GLSL boundary with no compiler check. Q7's trigger is met: generate the GLSL from the header rather than adding a sixth copy.
- **Q10** — contact cannot hold a fully charged cell at `dt` = 1 ms; needs substepping if a scenario makes dense charged cultures.
- **Q11, Q12, Q13** — SoA not bucket-reordered; `shell_conductance` deliberately unused (read ADR-020 first); light axis-aligned only.
- **`RENDERING.md` §8 remainder** — chromatic aberration and medium texture, both with honesty caveats; and faceting, since silhouettes are lobed pebbles rather than angular grains.
- **Test suite cost** — `ctest` ~4 min, `test_taxis` 41.5 s of it. Kept deliberately; trimming is an ADR, not a quiet edit.
