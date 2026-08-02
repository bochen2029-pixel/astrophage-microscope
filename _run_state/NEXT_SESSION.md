# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m4-green`. Next milestone: M5 — Fields.**

13 tests green, 8 goldens, 7 audit checks clean. Hash rebuild 0.110 ms at 200k cells; determinism holds through contact (0/3000 positions differing).

## Start here

```bash
git -C C:\Astrophage tag --list
```

Read, in order: `CLAUDE.md` → `docs/ARCHITECTURE.md` → **the M5 section only** of `docs/MILESTONES.md` → `docs/PHYSICS.md` **§7 only** → `src/fields/MODULE.md` → `contracts/fields_v1.h`.

Verify the baseline before touching anything:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M4
```

## What M5 is

`docs/MILESTONES.md` §M5 and `docs/PHYSICS.md` §7.

- `Grid2D<float>` in device memory, bilinear sample and scatter.
- Explicit red-black diffusion, substep counts read from `VERIFICATION.md` §6 — **not assumed**. `src/fields/fields_placeholder.cu` carries `static_assert`s that turn a resolution change into a build break; **keep them alive when you delete that file.**
- **Fixed-point i64 deposit accumulators** (INV-2, ADR-013). Float `atomicAdd` is order-dependent and would break INV-8 on every run. `contracts/fields_v1.h` has the scales and the overflow arithmetic; `DEPOSIT_MAX_CONTRIBUTORS` is a per-grid-cell bound, not a global one.
- Boundary conditions: dirichlet / neumann / robin.
- Field overlay render pass with LUTs; heat and chill brushes.

**Gate:** M4 gate + T25 (no NaN, no oscillation, energy conserved to 0.1 % under insulated BC) + the analytic point-source profile `T(r) = T∞ + ΔT·a/r` matching in the far field within 2 %.

**Do not** couple cells to the fields yet — sources are brush-only at M5. Cell↔field coupling is M6.

**Tool brushes must enqueue commands consumed at a defined point in the tick**, not write into device memory from the input handler. The latter breaks INV-8 (`src/app/MODULE.md`).

## Traps worth knowing

- **Fusing across a documented tick-stage boundary is a correctness change, not an optimisation.** M4 learned this the hard way: contact fused into the integrate kernel read positions other threads were writing, and 2709 of 3000 positions differed between identical runs. If a field stage reads what another writes, they are separate kernels.
- **Braces do not protect commas in macro arguments** — only parentheses do. `ASTRO_FOR_EACH_NEIGHBOUR` is variadic for this reason.
- **`build.ps1 -App`** whenever the executable matters.
- **No physical literals in `src/sim` or `src/fields`** — `audit.ps1` A9 greps three patterns. Maths constants go in `core/units.h`.
- **The oracle is authoritative** and has now caught four real errors. If it disagrees with the simulator, the simulator is wrong.
- **Do not guess a numeric threshold** — derive it. Every invented cutoff so far has been wrong.
- **Regenerating goldens needs a `DECISIONS.md` entry in the same commit** (Iron Rule 10).

## Performance state

200k cells run at **281 ticks/s = 0.28× real time**. Contact dominates. Two named levers, both untouched:

- **Q8** — defocus overdraw: cull cells whose peak opacity is below the fragment discard threshold, in the vertex stage. Bloom at M7 lands on top of this.
- **Q9 (new, and the bigger one)** — the neighbour walk visits **27 buckets when 8 would do**. The hash cell is 22 μm and the contact range is 10 μm, so a 2×2×2 walk is correct whenever `cell_size ≥ 2 × range`, which holds. ~3.4× on the dominant cost. Take this if M5 makes the tick budget tight.

## Open questions carried forward

- **Q1** — App `--headless` and `tools/headless` stay separate deliberately.
- **Q5** — When M9 adds slot reuse, confirm `spawn_kernel` clears `vx/vy/vz`.
- **Q6** — `MotionConfig::thermal_noise`, `contact_enabled`, `adhesion_enabled` are test-only; a scenario wanting them needs fields in `scenario_v1.h`.
- **Q7** — `optics.h` and the GLSL in `cells_pass.cpp` duplicate four formulas with no compiler check (ADR-017).
- **Q10 (new)** — Contact cannot hold a fully charged cell at `dt` = 1 ms (ADR-018 §3): stability caps stiffness 3.36× below what rigidity needs. Bounded and tested, but if M9 produces dense charged cultures this needs contact substepping or a smaller `dt`.
- **Q11 (new)** — The SoA is not reordered by bucket, contrary to M4's stated scope. Deliberate; revisit only with profiling evidence.
