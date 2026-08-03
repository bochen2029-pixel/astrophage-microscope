// contracts/taumoeba_view_v1.h -- CONTRACT v1. Frozen interface; see contracts/README.md.
//
// The predator store's rendering view (M12b). render/ reads THIS, never src/sim/predation.cuh,
// exactly as it reads cell_store_v1.h's CellStoreView for the cells. The interop kernel turns
// each Taumoeba into a render_view_v2 CellInstance appended after the cells (RenderFrame's
// taumoeba_offset), so the predators draw in the same instanced pass. Only the fields the draw
// needs are exposed; the app (which links sim and render) builds this from the TaumoebaStore.
//
// Semantics: docs/PHYSICS.md Sec 11, docs/RENDERING.md.
#pragma once

#include <cstdint>

namespace astro::contract {

inline constexpr int TAUMOEBA_VIEW_CONTRACT_VERSION = 1;

// Device-side SoA view. Pointers are DEVICE pointers; passed by value into a kernel.
struct TaumoebaView {
    const uint64_t* id;        // stable, monotonic -- seeds the per-body silhouette
    const uint32_t* flags;     // CellFlags bits reused (OCCUPIED | ALIVE)
    const double*   x;
    const double*   y;
    const double*   z;         // [m]
    const float*    tolerance; // N2 tolerance in [0,1]; may be null. Carries the evolution state
    int32_t         count;
};

} // namespace astro::contract
