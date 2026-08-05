# M12f KICKOFF — the render remainder, finished (the hail mary for v1.0)

**Written 2026-08-05 as a planning artifact. The tag is truth; if this disagrees with `git tag --list`, believe the tags.**
Branched off `m14b-green`. This is the last real *feature* work before packaging (now **M12j**) ships `v1.0`.

> **Naming:** these four steps ship as single-letter milestones because `gate.ps1` accepts only a single
> trailing letter — **M12f** = the cross-fade, **M12g** = the render_view_v3 -> scenario_v3 cascade +
> temp_c, **M12h** = the T-field false-colour, **M12i** = bloom. Packaging moved **M12g -> M12j**. The
> `M12f1..f4` labels in the step headings below are the informal names from the original plan; read them
> as f/g/h/i respectively. (Believe `git tag --list` for which have actually landed.)

## The ambition

Finish the renderer. After M12f, **every one of the five view modes is complete and cinematic** —
nothing in `RENDERING.md` still says "deferred". The three payoffs, all physically honest:

1. **You can watch a cell ignite.** Pre-ignition warm-up: a heated-but-dormant cell glows continuously
   in Thermal IR as its local medium climbs toward the 96.415 C setpoint, then latches awake (P3, made
   *visible* for the first time). Today Thermal IR only knows the binary `AWAKE` latch.
2. **The Petrovascope blooms.** The swirling-pink-points-of-light look the novel describes — a real
   bright-pass + downsample/upsample chain over the Petrova emission, intensity tied to `emit_power`.
3. **Modes cross-fade, and Thermal shows the real heat field.** A slider dissolves Brightfield -> Thermal
   -> Petrovascope so you see the correspondence; behind Thermal IR, the actual diffused T-field in
   false-colour instead of a flat warm wash.

Honest by construction, like everything here: no mode invents data. temp_c is the sampled medium T; the
T-field background is the real `RenderFrame.temperature`; bloom is a post filter over real emission.

## Why this splits into four gated steps (Iron Rules 6 + 9)

Full scope is ~530-850 LOC across contracts + render + ui + ~14 include sites, with 3-4 new/changed
goldens spanning three different risk profiles (a GL-layout contract bump, a from-scratch post-process, two
shader features). That is more than one 600-LOC change should carry, and bundling a golden-moving change
with a golden-adding one muddies the "did a measurement golden move?" signal. So: four sub-milestones,
each independently green-able and tagged, sequenced by dependency and risk.

Two facts shrink the work from the NEXT_SESSION framing:
- **Cross-fade needs no contract bump** — `ScopeState::mode_blend` / `mode_blend_to` already exist (v2).
- **The T-field is already reachable** — `RenderFrame.temperature` is a live device pointer and
  `field_pass.cpp` already does grid -> R32F -> LUT. No new plumbing to sim.

The only real contract surgery is one float on `CellInstance`.

---

## M12f1 — The cross-fade slider  (lowest risk, no contract, do FIRST)

Factor the cell fragment appearance and the background into functions of `ViewMode`, evaluate for `mode`
and `mode_blend_to`, `mix()` by `mode_blend`. This refactor is also the scaffold f2/f3 slot into, so it
earns its place first.

- **Files:** `src/render/cells_pass.cpp` (shader: `appearance(mode)` helper, two `u_mode*` uniforms + a
  blend uniform, blend the per-mode `glClearColor` into a background uniform pair), `src/ui/` scope panel
  (a `mode_blend_to` picker + a 0..1 slider driving `ScopeState`).
- **Contract change:** no.
- **Tests/goldens:** new golden `m12f_crossfade_bf_thermal` at `mode_blend=0.5`, asserted to differ from
  both endpoints (imgdiff, like the M12e colourblind check). Existing goldens: at `mode_blend=0` the
  output is byte-identical to today, so no measurement golden moves.
- **Rollback:** the shader helper is additive; revert `cells_pass.cpp` + the panel. `git reset` to
  `m14b-green` if needed.
- **Diff budget:** ~180 LOC.
- **Gate M12f1:** M14b gate + the cross-fade golden differs from both endpoints + all measurement goldens
  unmoved.

## M12f2 — The `render_view_v3` -> `scenario_v3` cascade + pre-ignition warm-up  (highest structural risk)

Add `float temp_c` to `CellInstance` (36 -> 40 bytes) and light the continuous Thermal-IR warm-up.

- **The cascade (mechanical but wide):** create `contracts/render_view_v3.h` (copy v2, add `temp_c`, bump
  `RENDER_VIEW_CONTRACT_VERSION=3`, `static_assert(sizeof(CellInstance)==40)`) and
  `contracts/scenario_v3.h` (copy v2, swap its `#include "render_view_v2.h"` -> `v3`, bump
  `SCENARIO_CONTRACT_VERSION=3`). Then swap every consumer's include v2 -> v3 (~14 files; a missed one is
  a *compile* error from the two-version ODR clash, not a silent bug). Freeze v2 like v1.
- **temp_c source (keeps the cascade to just these two contracts):** the **interop kernel samples the T
  grid** at the cell position and writes `temp_c` — a render-side derivation, no `sim/` or `cell_store`
  change. (If field_sample's per-cell T already persists in `CellStore`, read that instead — a 5-minute
  check at implementation; prefer it only if it's already exposed, else sample.)
- **The warm-up:** in the Thermal-IR branch, dormant cells glow by
  `clamp((temp_c - ambient)/(SETPOINT_C - ambient), 0, 1)`; awake cells keep the existing hot rim. So a
  heated dormant cell visibly warms, then latches.
- **Files:** 2 new contract headers; `src/render/interop.cu(h)` (sample + write temp_c); `cells_pass.cpp`
  (attrib location 4 float@36, stride 40, static_assert, Thermal branch uses temp_c); ~14 one-line include
  swaps; `src/render/MODULE.md` + `docs/ARCHITECTURE.md` module inventory (v2 -> v3) + `RENDERING.md` §4.
- **Contract change:** YES — `render_view_v3` + `scenario_v3`. **ADR-043** in the same commit (Rule 7):
  why temp_c, the render-side sample, the 36->40 layout, why measurement goldens are unmoved.
- **Tests/goldens:** `test_contracts` updates to v3 sizes. New golden `m12f_thermal_warmup` (a half-heated
  dormant patch shows a gradient). Measurement goldens are Brightfield/Sphere and never read temp_c ->
  unmoved (the gate's core assertion). Verify `m7b_thermal_awake` doesn't move (its dormant cells sit at
  ambient -> warm factor ~0).
- **Rollback:** the cascade is atomic in one commit; if goldens move unexpectedly, `git reset` to
  `m12f1-green` and re-approach the Thermal branch (the layout half is separable from the shader half).
- **Diff budget:** ~300 LOC (mostly the mechanical swaps + two headers).
- **Gate M12f2:** M12f1 gate + `test_contracts` green at v3 + determinism (M0.4) unmoved (temp_c is render
  only) + measurement goldens unmoved + the warm-up golden renders the gradient.

## M12f3 — Real T-field false-colour behind Thermal IR  (moves the Thermal golden, by design)

Replace the flat `ThermalIR` clear colour with the diffused T-field sampled through the magma/film-warm
LUT — reusing the M12f1 background-function seam and the existing `field_pass` grid->texture->LUT path.

- **Files:** `src/render/field_pass.cpp` (a Thermal-IR background pass from `RenderFrame.temperature`),
  `cells_pass.cpp`/compose wiring so ThermalIR's background is the T texture (blended under cross-fade),
  `src/render/luts.cpp` if a dedicated warm ramp is wanted, `RENDERING.md` §4.
- **Contract change:** no (temperature already in `RenderFrame`).
- **Tests/goldens:** the `m7b_thermal_*` goldens **change** (flat wash -> spatial field) — regenerate via
  `tools/goldgen` + a `DECISIONS.md` line (Rule 10; fold into ADR-043 or a sibling ADR-044). New golden
  showing a hot plume reading as a bright region.
- **Rollback:** background source is a single wire; revert to the clear colour. `git reset` to
  `m12f2-green`.
- **Diff budget:** ~150 LOC.
- **Gate M12f3:** M12f2 gate + regenerated thermal goldens (with ADR) + a plume renders hot.

## M12f4 — Bloom over the Petrova emission  (independent; perf-sensitive; do LAST)

Build bloom from scratch (the file does **not** exist today, despite MODULE.md). Bright-pass threshold
0.6 on the emission target, 4-level down/up chain, additive composite — Petrovascope only, intensity tied
to `emit_power` (`RENDERING.md` §5).

- **Files:** new `src/render/bloom.cpp` (+ `.h`), compose wiring (§2 order: compose -> bloom -> optics),
  `render/MODULE.md` (correct the stale bloom row), `RENDERING.md` §5.
- **Contract change:** no.
- **Tests/goldens:** new golden `m12f_petrova_bloom` (a lit emitter blooms; must differ from the
  no-bloom Petrovascope). **Perf:** re-run `test_perf` / the M1.5 fps check — bloom lands on top of the
  defocus fill-rate (§7); confirm 200k cells still clear 144 fps, else apply the §7 vertex-cull lever.
- **Rollback:** bloom is a self-contained pass behind a toggle; disable it. `git reset` to `m12f3-green`.
- **Diff budget:** ~250 LOC.
- **Gate M12f4:** M12f3 gate + the bloom golden differs from no-bloom + fps target still met + zero GL
  debug errors. **This closes the render remainder** -> M12g packages v1.0.

---

## Goldens & ADR ledger

- **ADR-043 (M12f2):** the `render_view_v3` -> `scenario_v3` cascade + render-side `temp_c` + pre-ignition
  warm-up. States why measurement goldens are unmoved.
- **ADR-044 (M12f3), or a clause in 043:** the Thermal-IR goldens change from flat wash to real T-field.
- New goldens (crossfade, warmup, plume, petrova-bloom) are *additions*; existing measurement goldens
  (Brightfield/Sphere optics oracles) must never move across all of M12f. That invariant is the spine of
  every gate here.

## Risks & notes

- **The doc drift:** `render/MODULE.md` and `RENDERING.md` claim bloom exists at M7. It does not. M12f4
  builds it and reconciles the docs (Rule 7).
- **ADR-017 / Q7 (optional stretch, NOT core):** M12f1+f2 both touch the cell fragment shader, exactly
  where the flagged GLSL/`optics.h` formula duplication bites. If drift bites during f1/f2, the ambitious
  fix is generating the GLSL constants from the header (Q7). Recommend deferring unless it actually bites
  — it is a large orthogonal refactor the project already deferred with reason.
- **Perf ordering:** bloom is deliberately last because it stacks on the defocus fill-rate crisis (§7);
  measuring it in isolation keeps the fps regression attributable.
- **Sequencing rationale:** f1 builds the blend seam f2/f3 reuse; f2 isolates the one risky contract/layout
  change; f3 reuses f1's background seam and owns the only deliberate golden move; f4 is independent and
  perf-gated, so it goes last and its gate is the render-complete line.

## First move for the executing session

1. Read `contracts/render_view_v2.h`, `docs/RENDERING.md` §4-5, `src/render/cells_pass.cpp` (shader +
   the attrib bindings at ll. 30-33 / 399-415).
2. Split M12f -> M12f1..M12f4 in `docs/MILESTONES.md` (Rule 9, before starting) and add the M12f1..f4 gate
   cases to `scripts/gate.ps1`.
3. Build M12f1 (cross-fade) first. It is self-contained, ships a visible affordance, and lays the shader
   seam the Thermal work slots into.
