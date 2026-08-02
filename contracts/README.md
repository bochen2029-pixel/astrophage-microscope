# contracts/

Versioned, dependency-free headers defining every cross-module interface.

## Why these exist

This project spans dozens of sessions with a bounded context window. A session working on `render` must be able to do its job **without reading `src/sim/`**. These headers are how: they are the complete, authoritative description of what one module exposes to another.

If you ever find yourself opening another module's `.cu`/`.cpp` to learn what a function does or how a struct is laid out, **the contract is wrong** — fix the contract rather than reading the source. That reflex is the single most important habit for keeping this build tractable.

## Rules

1. **Frozen.** A `_v1.h` header never changes meaning. To evolve an interface, add `_v2.h`, update every consumer, and file an ADR in `docs/DECISIONS.md` — all in one commit.
2. **Dependency-free.** Only `<cstdint>`, `<cstddef>`, and other `contracts/` headers. No CUDA headers, no project headers, no standard containers. They must compile standalone under both MSVC and nvcc.
3. **POD only.** Structs crossing the boundary are trivially copyable, explicitly laid out, and safe to pass by value into a kernel. No virtuals, no constructors, no `std::` members.
4. **Semantics live in docs.** Each header points at the document section that explains it. Headers carry layout and units; documents carry meaning.
5. **Units are stated for every field.** SI everywhere, with one deliberate exception: `CellInstance` in `render_view_v2.h` is in micrometres, because fp32 metres would lose the sub-micron structure the optics model depends on.

## Inventory

| Header | Defines | Semantics |
|---|---|---|
| `cell_store_v1.h` | Astrophage SoA layout, cell flags, death causes | `docs/PHYSICS.md` §2 |
| `fields_v1.h` | field grids, boundary conditions, **fixed-point deposit scales**, light sources | `docs/PHYSICS.md` §7 |
| `render_view_v2.h` | view modes, morphology, overlays, `CellInstance` GL layout, scope state | `docs/RENDERING.md` |
| `telemetry_v1.h` | the `Stats` struct, acceptance metrics and comparison ops | `docs/SCENARIOS.md` |
| `snapshot_v1.h` | snapshot file layout, param overrides, the FNV-1a determinism hash | `docs/ARCHITECTURE.md` §5.4 |
| `scenario_v1.h` | parsed scenario, populations, clock presets, canon-contradiction toggles | `docs/SCENARIOS.md` |

## The two that carry the most weight

- **`fields_v1.h` deposit scales.** These are what make GPU determinism possible (ADR-013). Float `atomicAdd` is order-dependent; integer accumulation is not. If you change a scale, redo the overflow arithmetic documented in the header — an overflowing int64 accumulator is a silent correctness bug, not a crash.
- **`render_view_v2.h` `CellInstance`.** Its layout is a GL vertex-attribute contract, asserted at 36 bytes. Changing it means changing `render/cells_pass.cpp` bindings in the same commit. `render_view_v1.h` is retained frozen and unused, per rule 1; nothing may include both, because they declare the same names in the same namespace.
