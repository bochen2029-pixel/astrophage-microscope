# SESSION LOG

Append-only. One entry per session, under 25 lines. **Read the last two entries at session start; never the whole file.**

Format: milestone · what landed · what is pending · open questions · gotchas.

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
