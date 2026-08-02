# MODULE: render

**Depends on: `core`, `contracts`.** Reads `contracts/render_view_v1.h` — **never `src/sim/`**.

## Purpose

Everything that produces pixels: GL context, CUDA-GL interop, the single instanced cell draw, the microscope optics model, field overlays, LUTs, bloom.

## Files

| File | Owns | Milestone |
|---|---|---|
| `gl_context.cpp` | GL 4.6 core context, debug output, extension checks | M1 |
| `interop.cu` | `cudaGraphicsGLRegisterBuffer`; the kernel that writes `CellInstance` | M1 |
| `cells_pass.cpp` | instanced disc draw, SDF fragment shader | M1 |
| `optics.cpp` | defocus, circle of confusion, diffraction ring, condenser | M3 |
| `camera.cpp` | scope pan/zoom/focal plane, objective presets | M1 |
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

Not started. Begins at M1 (`ASTRO_BUILD_APP=ON`).
