// contracts/render_view_v2.h -- CONTRACT v2. Frozen interface; see contracts/README.md.
//
// The sim/render boundary. render/ and ui/ read THIS FILE, never src/sim/.
// Semantics: docs/RENDERING.md.
//
// SUPERSEDES render_view_v1.h. The only change is CellInstance, which gains a
// `shape_seed` and grows 32 -> 36 bytes. Rationale in ADR-023: cell silhouettes
// are irregular and each one must be stable for the life of the cell, so the
// shader needs a per-cell value that does not change as the cell moves, charges,
// divides, or is compacted into a different slot. Nothing already in the struct
// qualifies -- position, charge, flags and the emission axis all vary.
#pragma once

#include <cstdint>

namespace astro::contract {

inline constexpr int RENDER_VIEW_CONTRACT_VERSION = 2;

enum class ViewMode : uint8_t {
    Brightfield = 0,   // what a human sees: black cells on warm white
    Darkfield   = 1,
    Petrovascope= 2,   // 25.984 um band; non-emitting cells are INVISIBLE
    ThermalIR   = 3,   // 7.841 um blackbody band; distinct from Petrovascope
    Analysis    = 4,   // flat cells coloured by AnalysisChannel
    Count       = 5,
};

enum class AnalysisChannel : uint8_t {
    Charge = 0, Temperature = 1, Age = 2, Mass = 3, Awake = 4, Velocity = 5,
};

// How a cell is DRAWN. Appearance only: the physics body is always a sphere of
// CELL_RADIUS, and sim/ neither knows nor can know which of these is selected
// (ADR-023). The novel describes spheres; reference photography shows irregular
// grains -- both readings ship, as with ADR-002 and ADR-003.
enum class Morphology : uint8_t {
    Sphere    = 0,   // novel-faithful, and what every measurement golden is pinned to
    Irregular = 1,   // reference-faithful; the application default
};

enum OverlayBits : uint32_t {
    OVERLAY_NONE        = 0u,
    OVERLAY_TEMPERATURE = 1u << 0,
    OVERLAY_CO2         = 1u << 1,
    OVERLAY_N2          = 1u << 2,
    OVERLAY_IRRADIANCE  = 1u << 3,
    OVERLAY_VELOCITY    = 1u << 4,
    OVERLAY_HASH_GRID   = 1u << 5,
    OVERLAY_TRAILS      = 1u << 6,
    OVERLAY_SCALE_BAR   = 1u << 7,   // on by default; this is a microscope
};

// ---------------------------------------------------------------------------
// Per-instance attributes written by a CUDA kernel directly into a GL VBO via
// cudaGraphicsGLRegisterBuffer. Positions never touch host memory.
//
// UNITS: micrometres, fp32. This is the ONE place outside ui/ where a display
// unit is used -- fp32 metres would lose the sub-micron structure that the
// optics model depends on.
//
// Layout must match the vertex attribute bindings in render/cells_pass.cpp.
// 36 bytes per instance; 200k cells = 7.2 MB.
// ---------------------------------------------------------------------------
struct CellInstance {
    float x_um, y_um, z_um;   // position [um]
    float radius_um;          // true radius; NEVER inflated for visibility

    float charge;             // [0,1]
    float emit_power_norm;    // emit_power / PETROVA_MAX_POWER, [0,1]
    uint32_t flags_packed;    // CellFlags in bits 0-15, DeathCause in bits 16-23
    uint32_t dir_packed;      // emission axis, octahedral-encoded into 32 bits

    // Stable for the life of the cell: hashed from the cell's monotonic id, never
    // from its slot index. A slot-derived seed would make every silhouette change
    // the moment M9's compaction moves a cell, which is the same class of mistake
    // INV-1 forbids for the RNG.
    uint32_t shape_seed;
};
static_assert(sizeof(CellInstance) == 36, "CellInstance layout is a GL contract");

// ---------------------------------------------------------------------------
// The scope: a movable, focusable window onto the chamber (ADR-009).
// ---------------------------------------------------------------------------
struct ScopeState {
    double center_x, center_y;  // [m] stage position within the chamber
    double focal_plane;         // [m] z of the focal plane
    int32_t objective;          // index into canon::OBJECTIVES
    float   zoom;               // additional digital zoom on top of the objective

    ViewMode mode;
    ViewMode mode_blend_to;     // cross-fade target
    float    mode_blend;        // 0 = mode, 1 = mode_blend_to
    AnalysisChannel channel;
    uint32_t overlays;          // OverlayBits

    uint8_t colorblind_safe;    // swaps petrova-film for magma
};

// Everything render/ needs from a completed tick. No sim headers required.
struct RenderFrame {
    const CellInstance* instances;   // device pointer into the mapped GL buffer
    int32_t instance_count;
    int32_t taumoeba_offset;         // instances [taumoeba_offset, count) are Taumoeba

    const float* temperature;        // device pointers to field values, or null
    const float* co2;
    const float* n2;
    const float* irradiance;
    int32_t n_temp, n_co2, n_n2, n_irrad;

    double sim_time_s;
    uint64_t tick;
    float alpha;                     // interpolation factor between the last two ticks
};

} // namespace astro::contract
