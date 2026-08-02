# SESSION LOG

Append-only. One entry per session, under 25 lines. **Read the last two entries at session start; never the whole file.**

Format: milestone · what landed · what is pending · open questions · gotchas.

---

## 2026-08-02 — M3 (Optics) — GREEN

**Landed.** The renderer is a microscope. Per-instance defocus, energy-conserving opacity, the Becke line with its polarity inversion, a condenser vignette, and a depth-of-field gauge in the HUD.

- `render/optics.h` — the model as pure host-testable functions; `test_optics` covers DOF, energy conservation, and polarity.
- `cells_pass.cpp` — shader rewritten around the blurred profile. Signed contrast, so the Becke line can render *brighter* than the field rather than only darker.
- `render/post_pass.{h,cpp}` — condenser vignette, multiply-blended fullscreen triangle, no FBO.
- `tools/imgdiff.cpp` + `scripts/goldens.ps1` — golden capture and comparison. `--no-ui` and `--focus` added so goldens depend on the renderer alone.
- 11 tests green, 8 goldens.

**Rendering is bit-exact** on a fixed driver (mean 0.0000, max 0 immediately after generation), so tolerances are tight enough to catch a **2 μm focus change at 100×**.

**ADR-017 — the golden suite needed a second half.** A golden suite proves the renderer is *stable*, not that it *does anything*: a shader ignoring the focal plane entirely would pass one forever. So `goldens.ps1` also asserts specific pairs must **differ**. The sharpest is focus **+2 vs −2** at 100×: identical `|dz|`, therefore identical blur radius and peak opacity, differing only in sign. If the polarity inversion were dropped they would be byte-identical. That turns a by-eye feature into a headless test (measured: mean 9.8/255 across 21.6 % of pixels).

**Gotchas.**
- **I had written a false claim into `optics.h`** — that sedimentation concentrates cells into a focal plane, so racking onto the settled layer would bring the culture sharp. It does not. Gravity is along −y (ADR-006), so cells pile against a *side wall* while their `z` stays uniformly spread. Only 2.5 % of the chamber is ever in focus at 40×. Comment corrected; the claim would have misled whoever built on it.
- **Two `test_optics` thresholds were invented rather than derived** (`r > 4a`, `peak < 0.06`) and failed at the true values 3.9a and 0.0617. Replaced with assertions on the derived quantities — the blur is `dz·NA/n` and the opacity follows from energy conservation — plus loose qualitative bounds. Guessing a threshold and then discovering the physics disagrees is the wrong order.
- **Energy conservation is what makes blur read as blur.** Without the `(a/R_eff)²` falloff a defocused cell stays jet black and merely grows, which looks like fog.
- Defocus costs fill rate, not shader complexity: 795 → 426 fps at 200k cells. Bloom at M7 lands on top of that; the first lever is vertex-stage culling of near-invisible cells.
- Range-`for` over a braced list needs `<initializer_list>` under MSVC.

---

## 2026-08-02 — M2 (Motion) — GREEN

**Landed.** Cells move, and **P1 is real**: an empty cell (40 kg/m³, 0.04× water) rises and packs against the ceiling; a charged one (6415 kg/m³, 6.4× water) sinks to the floor; at 3.006 % they hang suspended. Drift velocity is linear in charge to **Pearson −1.000000**, zero crossing at **3.00577 %** vs a canon-derived 3.00577 %.

- `sim/integrator.{cuh,cu}` — exact joint OU propagator, buoyant weight, photon thrust, three boundary modes. All pure `__host__ __device__`, so `test_motion` runs the real code on the host.
- `world.motion` config, stages 2/5/6 wired into `world_step`. Live charge slider with a density/buoyancy readout.
- `--ticks-per-frame` decouples capture from the wall clock, which M3's goldens need.
- **Q3 closed**: `tools/headless` now drives the real `World`, so the determinism gate finally covers the integrator instead of a Brownian stand-in. It also now asserts that halving the population changes the hash — catching a hash that silently covers nothing.
- 10 tests green.

**Two corrections, both caught by the oracle before code shipped.**
- **ADR-016.** The integrator my own spec called for — propagate velocity exactly, then `r += v·dt` — gives **47× too much diffusion** for an empty cell, because velocity fully decorrelates within one step at `dt/τ = 4497`. Replaced with the exact joint position–velocity propagator (correlated 2×2 noise). Verified: `σ²_rr → 2D·dt` to four significant figures. This was found by arithmetic against `VERIFICATION.md`, which is exactly what the oracle is for.
- **The oracle and the simulator were using different viscosity models** — tabulated 20 °C vs Vogel–Fulcher — leaving a 2.5e-5 systematic offset that tolerances were absorbing. Unified on VF (the simulator has no choice; it needs the temperature dependence for P4). Tabulated values stay as cross-checks *on* the fit, which is their proper job. Also corrected `WATER_VISCOSITY_96C` (was 2.98e-4, real value ≈ 2.931e-4).

**Gotchas.**
- **T14's statistic was wrong, and fixing it made the gate stricter.** A whole-population position correlation caps near 0.84 for Pearson *and* Spearman. My first guess (wall saturation) was wrong — Spearman barely moved. The real cause: cells within a hair of neutral have near-zero drift and never leave their spawn point, contributing pure noise. That is correct physics. T14 now tests drift *velocity* vs charge, which is the sharp claim and immune to initial conditions.
- `ou_position_shape` needs a series branch below `x ≈ 1e-2`; the direct form cancels its first three orders exactly and returns noise. Both branches pinned.
- "Reflecting" boundaries mean *rest*, not bounce — at Re ≪ 1 there is no inertia to rebound with.

---

## 2026-08-02 — M1 (Cell store & first pixels) — GREEN

**Landed.** The simulator draws. 200,000 cells in one instanced draw at ~795 fps on the RTX 4070 Ti SUPER (target 144), zero GL debug errors.

- **`sim`**: `cell_store.{cuh,cu}` — one carved device blob rather than 25 allocations; spawn kernels (uniform/gaussian/grid/disc) with per-cell PCG32 streams; capacity enforcement. `world.cuh` + `step.cu` carry the tick sequence as an ordered comment list so each milestone inserts at its documented position.
- **`render`**: GL 4.6 + ImGui bootstrap, CUDA-GL interop writing `CellInstance` straight into a GL VBO (positions never touch host memory), instanced SDF disc pass, header-only `Camera` with cursor-anchored zoom.
- **`ui`**: scope panel, population controls, scale bar. Pending controls are *labelled* pending rather than silently inert.
- **`app`**: fixed-tick accumulator, pan/zoom, PPM screenshot, and the `--benchmark` path the gate drives.
- **+3 tests** (`test_cell_store`, `test_scope`, `test_octahedral`), 8 total, all green.

**Pending.** M2 (motion). `world_stats` returns only tick/time/counts; the means and the energy ledger need the M6 device reduction.

**Gotchas.**
- **`project()` must enable `C`.** GLFW and GLAD are C libraries; without it CMake fails at *generate* time with "required internal CMake variable not set: CMAKE_C_COMPILE_OBJECT", which points at nothing useful.
- **`<glad/gl.h>` must precede `<cuda_gl_interop.h>`** — the CUDA header uses `GLuint`/`GLenum` without declaring them and produces 15 errors about "variable GLuint is not a type name".
- **The gate had a real bug**: `M0.2` does a clean build, and without `-App` that reconfigure sets `ASTRO_BUILD_APP=OFF` and deletes the executable `M1.1` then looks for. Gates that build must know which targets later checks need.
- **200k cells was the wrong default** and the render was right. It is ~11 % of the chamber by volume but ~98 % *projected*, because the scope looks through the whole 60 μm slab — a solid black field. `DEFAULT_CELLS` is now 25,000, `BENCH_CELLS` stays 200,000. ADR-015.
- **The audit caught a 2π literal in `cell_store.cu`** (Iron Rule 3 working as intended), and while fixing it I found `293.15` had slipped past the regex. Added `AMBIENT_TEMP_DEFAULT` to canon, `PI`/`TWO_PI` to `core/units.h` (maths constants are not canon), and taught A9 a third pattern.
- Two `test_scope` assertions failed on first run and **both were my test's fault, not the code's** — but one exposed a genuine gap: at high zoom the field is narrower than a cell and the scale-bar snap table bottomed out at 1 μm. Extended down to 0.1 μm, which the 100× objective's 268 nm resolution makes meaningful anyway.

---

## 2026-08-02 — M0 (Harness) — GREEN

**Landed.** Whole repo from scratch. Stack chosen: C++20 + CUDA 13.1 + CMake/Ninja, sm_89, static runtimes (ADR-012, superseding an earlier TypeScript/WebGL draft now archived in `_brainstorm/`).

- **Generated canon.** `scripts/canon.py` is the single source of every physical number; `scripts/derive.py` emits `src/core/canon_generated.h`, `tests/golden/expected_values.h`, and `docs/VERIFICATION.md`. Idempotent, `--check` mode wired into the audit.
- **Docs system** sized for context-bounded sessions: `CLAUDE.md` + `ARCHITECTURE` + `PHYSICS` + `RENDERING` + `MILESTONES` (M0–M12) + `DECISIONS` (14 ADRs) + `SCENARIOS` + generated `VERIFICATION`.
- **Six frozen contracts** in `contracts/`, so a session can work one module without reading another's source.
- **`core`**: `units.h` (ASTRO_HD host/device bridge), `rng.cuh` (PCG32 per-cell streams), `vec.cuh`, `fixed_atomic.cuh`, `result.h`.
- **Harness**: `build.ps1` (finds VS-bundled Ninja, imports vcvars, falls back to the VS generator), `audit.ps1` (10 checks), `gate.ps1` (M0–M12, each re-running all earlier gates).
- **5 tests green**, plus 7 audit invariant checks.

**Pending.** Everything from M1 on. `src/render`, `src/ui`, `src/app` are `MODULE.md` only.

**Open questions.** Q1 app `--headless` vs `tools/headless` code path; Q2 octahedral direction encoding still a stub. Both in `_run_state/NEXT_SESSION.md`.

**Gotchas.**
- Two tests failed on first run and both were the oracle doing its job, not bad tests. (a) The CO₂ deposit scale genuinely overflowed int64 — the exact silent bug ADR-013 exists to prevent. Fixed by bounding contributors **per grid cell** rather than by `MAX_CELLS` (2e6 cells cannot occupy one 7.8 μm grid cell), now backed by `static_assert` in `fields_v1.h`. (b) A canon-count assertion was simply wrong; replaced with a stronger check that the *specific* parameters Weir wrote carry the lock, and that invented ones do not masquerade as canon.
- MSVC reports an unknown type in a member declaration as `C3646: unknown override specifier`. The real cause was a missing include of `snapshot_v1.h`. Worth remembering — the error names the wrong thing entirely.
- `ninja` is not on PATH but VS 2022 bundles it; `build.ps1` locates it and imports the MSVC environment itself.
