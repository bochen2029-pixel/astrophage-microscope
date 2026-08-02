# MODULE: render

**Depends on: `core`, `contracts`.** Reads `contracts/render_view_v1.h` — **never `src/sim/`**.

## Purpose

Everything that produces pixels: GL context, CUDA-GL interop, the single instanced cell draw, the microscope optics model, field overlays, LUTs, bloom.

## Files

| File | Owns | Milestone |
|---|---|---|
| `gl_context.cpp` | ✅ GL 4.6 core context, debug output, ImGui bootstrap | M1 |
| `interop.cu` | ✅ `cudaGraphicsGLRegisterBuffer`; the kernel that writes `CellInstance` | M1 |
| `cells_pass.cpp` | ✅ instanced disc draw, SDF fragment shader | M1 |
| `camera.h` | ✅ scope pan/zoom/focal plane, objective presets (header-only, so it is host-testable) | M1 |
| `optics.h` | ✅ circle of confusion, energy-conserving opacity, Becke amplitude, DOF — header-only, host-testable | M3 |
| `post_pass.cpp` | ✅ condenser vignette (multiply-blended fullscreen triangle, no FBO) | M3 |
| `field_pass.cpp` | grid → R32F texture, LUT mapping, overlays | M5 |
| `luts.cpp` | the five colour tables | M5 |
| `bloom.cpp` | 4-level downsample/upsample chain on Petrova emission | M7 |

## Contracts

Consumes `render_view_v1.h`, `fields_v1.h`, `telemetry_v1.h`. Produces none.

## Things that will bite you

- **`CellInstance` is a GL vertex-attribute contract**, `static_assert`ed at 32 bytes. Changing it means changing the attribute bindings in `cells_pass.cpp` in the same commit.
- **It is the one place outside `ui/` that uses micrometres.** fp32 metres would lose the sub-micron structure the optics depend on.
- **Defocus is per-instance, not screen-space.** Cells overlap in projection and a screen-space depth-of-field pass gets overlapping depths wrong. Expand the quad by `r_coc` and convolve the SDF analytically.
- **No size fudge, ever.** Cells render at true relative size — a 10 μm cell in a 550 μm field is the entire point. `audit.ps1` A10 greps for `radius * 2`, `VISUAL_SCALE`, and similar. Sub-pixel cells clamp to 0.75 px radius with alpha modulated by area ratio so density stays honest.
- **Thermal IR and Petrovascope must look different.** The Petrova line is a discrete quantum line at 25.984 μm; the thermal peak is 7.841 μm. A live idle cell glows thermally and is *dark* in Petrovascope. If the two modes ever agree, a real physical distinction has been lost.
- Zero GL debug-output errors is a gate, always. Never disable the debug layer to pass.

## Status

**M3 complete.** 200,000 cells in one instanced draw with full defocus at ~426 fps on
the reference GPU (target 144), zero GL debug errors. Petrovascope and Thermal IR are
M6/M7; `u_mode` is already plumbed so the shader grows rather than gets rewritten.

### The one hazard specific to this module

**`src/render/optics.h` and the GLSL in `cells_pass.cpp` duplicate the same four
formulas** — circle of confusion, blurred radius, peak opacity, ring amplitude — and
nothing across the GLSL boundary is compiler-checked. `test_optics` guards the C++
side; the golden images guard the shader. **Change one, change both.** Accepted risk,
recorded in ADR-017.

### Things that will bite you

- **Energy conservation is what makes blur read as blur.** Peak opacity falls as
  `(a/R_eff)²` so a defocused cell absorbs exactly as much light as a focused one,
  just spread wider. Drop that term and defocused cells stay jet black and merely
  grow, which reads as fog.
- **Defocus is a fill-rate cost.** A cell 30 μm out of focus covers 64× the area, and
  every fragment is shaded and blended. That is the 795 → 426 fps drop, and bloom at
  M7 lands on top of it. The first lever is culling cells below the discard threshold
  in the vertex stage (`RENDERING.md` §7).
- **Sedimentation does NOT produce a sharp monolayer.** Gravity is along −y (ADR-006),
  so cells pile against a side wall while `z` stays uniformly spread. Only 2.5 % of the
  chamber is in focus at 40×, always.
- **Goldens are captured with `--no-ui`**, so a HUD change never invalidates them.

### Earlier traps still worth knowing

- **`<glad/gl.h>` must be included before `<cuda_gl_interop.h>`.** The CUDA header
  uses `GLuint`/`GLenum` without declaring them, and standalone inclusion fails with
  15 errors that all say "variable GLuint is not a type name".
- **`project()` must enable `C`.** GLFW and GLAD are C libraries; omitting the language
  fails at *generate* time with "required internal CMake variable not set:
  CMAKE_C_COMPILE_OBJECT", which names nothing useful.
