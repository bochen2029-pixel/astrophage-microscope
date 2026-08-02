# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

---

## Where the build stands

**Last green: `m0-green`. Next milestone: M1 — Cell store & first pixels.**

M0 delivered the harness. The build configures with Ninja, compiles clean under `/W4 /WX` with CUDA 13.1 targeting sm_89, and all five tests pass:

```
test_canon ......... generated constants are internally consistent
test_rng ........... PCG32 vs reference vectors, stream independence, moments
test_contracts ..... POD/layout/version guards, FNV-1a, deposit headroom
test_fixed_atomic .. identical sums across 4 block sizes (INV-2, INV-4)
determinism_replay . 10k ticks, same hash twice, seed-sensitive (INV-8)
```

`scripts/audit.ps1 -SkipBuild` passes all 7 invariant checks.

## Start here

```bash
git -C C:\Astrophage tag --list
```

Then read, in order:

1. `CLAUDE.md` — the operating contract. Session ritual, iron rules, authority.
2. `docs/ARCHITECTURE.md` — module map, invariants INV-1..INV-8, glossary, anti-drift machinery.
3. `docs/MILESTONES.md` — **the M1 section only**.
4. `src/sim/MODULE.md` and `src/render/MODULE.md` — the two modules M1 touches.
5. `contracts/cell_store_v1.h` and `contracts/render_view_v1.h`.

Do **not** read `docs/PHYSICS.md` for M1 — there is no physics in M1. Do not read the whole repo.

Then verify the baseline before changing anything:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M0
```

## What M1 is

Per `docs/MILESTONES.md` §M1:

- `CellStore` device SoA at `MAX_CELLS` capacity, free list, layout per `contracts/cell_store_v1.h`
- spawn kernels (uniform / gaussian / grid) using per-cell PCG32 streams
- GLFW window + GL 4.6 + ImGui bootstrap — flip `ASTRO_BUILD_APP` to `ON` (first configure fetches GLFW/GLAD/ImGui, so **this session needs network**)
- `cudaGraphicsGLRegisterBuffer` interop: a kernel writes `CellInstance` straight into a GL VBO
- one instanced draw, disc as an SDF in the fragment shader
- camera: pan, zoom, the three objective presets from `canon::OBJECTIVES`
- scale bar snapping to 10/20/50/100/200/500 μm
- HUD stub: tick, cell count, FPS

**Gate:** M0 gate + window opens + 200,000 static cells at ≥144 fps + scale bar correct at all three objectives + zero GL debug errors.

**Not in M1:** no motion, no fields, no optics beyond a flat disc. Those are M2 and M3.

## Housekeeping M1 should do

- Delete `src/sim/sim_placeholder.cu` when `cell_store.cu` lands, and remove it from `CMakeLists.txt` in the same commit.
- Leave `src/fields/fields_placeholder.cu` alone — it is not touched until M5, and it carries the ADR-008 substep `static_assert`s.
- Add `test_cell_store` to `CMakeLists.txt` via the `astro_test()` helper.
- `gate.ps1` already contains the M1 checks and expects `astrophage.exe` to support `--benchmark`, `--headless`, `--gl-debug`, and `--frames`. Build those flags or the gate cannot pass.

## Traps worth knowing before you start

- **Empty dirs do not survive git.** `src/render`, `src/ui`, and `src/app` currently exist only because of their `MODULE.md` files.
- **MSVC reports an unknown type in a member declaration as "unknown override specifier."** If a contract header suddenly fails to parse, look for a missing include, not a keyword collision. This cost time in M0.
- **`ASTRO_BUILD_APP=ON` needs network** on the first configure only. `scripts/build.ps1 -App` sets it.
- **Ninja needs the MSVC environment.** `build.ps1` imports `vcvars64.bat` automatically when not already in a developer shell; if that ever fails it falls back to the Visual Studio generator rather than erroring.
- **No physical literals in `src/sim` or `src/fields`.** `audit.ps1` A9 greps for them. Add anything new to `scripts/canon.py` with a provenance tag and re-run `derive.py`.

## Open questions carried forward

- **Q1** — Should `--headless` on the app share a code path with `tools/headless.cpp`, or stay separate? M1 will have to pick. Leaning separate: `tools/headless` must never link GL, and merging them risks dragging GL into the determinism oracle.
- **Q2** — Octahedral encoding for `CellInstance::dir_packed` is specified but not written. M1 needs it only as a stub (emission arrives at M7); write the encode/decode pair in `core/` with a round-trip test rather than inlining it in the interop kernel.
