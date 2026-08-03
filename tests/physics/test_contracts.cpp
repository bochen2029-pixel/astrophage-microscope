// tests/physics/test_contracts.cpp -- the contracts must stay POD and stable.
//
// contracts/*.h are how a session works one module without reading another's
// source (ARCHITECTURE.md Sec 5.2). That only holds if they stay trivially
// copyable, kernel-safe, and layout-stable. This test is the enforcement.
#include <type_traits>

#include "contracts/cell_store_v1.h"
#include "contracts/fields_v1.h"
#include "contracts/render_view_v2.h"
#include "contracts/scenario_v2.h"
#include "contracts/snapshot_v1.h"
#include "contracts/telemetry_v1.h"
#include "core/canon_generated.h"
#include "test_util.h"

using namespace astro::contract;

// Anything passed by value into a kernel must be trivially copyable.
static_assert(std::is_trivially_copyable_v<CellStoreView>);
static_assert(std::is_trivially_copyable_v<FieldView>);
static_assert(std::is_trivially_copyable_v<FieldsView>);
static_assert(std::is_trivially_copyable_v<LightSource>);
static_assert(std::is_trivially_copyable_v<CellInstance>);
static_assert(std::is_trivially_copyable_v<ScopeState>);
static_assert(std::is_trivially_copyable_v<RenderFrame>);
static_assert(std::is_trivially_copyable_v<Stats>);
static_assert(std::is_trivially_copyable_v<AcceptCheck>);
static_assert(std::is_trivially_copyable_v<SnapshotHeader>);
static_assert(std::is_trivially_copyable_v<Scenario>);
static_assert(std::is_trivially_copyable_v<Stimulus>);   // v2 driving script (ADR-032)

// The GL vertex-attribute contract. Changing this means changing the bindings in
// render/cells_pass.cpp in the same commit.
static_assert(sizeof(CellInstance) == 36);
static_assert(std::is_standard_layout_v<CellInstance>);

// Snapshots are written to disk; the header must be layout-stable.
static_assert(std::is_standard_layout_v<SnapshotHeader>);

int main() {
    CHECK(CELL_STORE_CONTRACT_VERSION == 1);
    CHECK(FIELDS_CONTRACT_VERSION == 1);
    CHECK(RENDER_VIEW_CONTRACT_VERSION == 2);
    CHECK(TELEMETRY_CONTRACT_VERSION == 1);
    CHECK(SNAPSHOT_CONTRACT_VERSION == 1);
    CHECK(SCENARIO_CONTRACT_VERSION == 2);

    // 'ASPH' little-endian, so a snapshot is identifiable in a hex dump.
    CHECK(SNAPSHOT_MAGIC == 0x48505341u);

    // FNV-1a is the determinism oracle (INV-8) and is defined once, in the
    // contract, so tools/, tests/, and sim/ cannot disagree about it.
    const char* s = "astrophage";
    const uint64_t h1 = fnv1a64(s, 10);
    const uint64_t h2 = fnv1a64(s, 10);
    CHECK_EQ_U64(h1, h2);
    CHECK(h1 != 0);
    CHECK(fnv1a64("a", 1) != fnv1a64("b", 1));
    // Chaining must equal hashing the concatenation, or incremental snapshot
    // hashing would not match a whole-buffer hash.
    CHECK_EQ_U64(fnv1a64("phage", 5, fnv1a64("astro", 5)), fnv1a64("astrophage", 10));

    // ADR-013 overflow headroom. The bound is per grid cell (see fields_v1.h),
    // and the header carries static_asserts; these re-check at runtime and also
    // verify the margin is real rather than marginal.
    CHECK(DEPOSIT_SCALE_TEMPERATURE > 0.0);
    CHECK(DEPOSIT_SCALE_CO2 > 0.0);
    CHECK(DEPOSIT_MAX_CONTRIBUTORS * 1.0e3 * DEPOSIT_SCALE_TEMPERATURE < 9.2e18);
    CHECK(DEPOSIT_MAX_CONTRIBUTORS * 1.0e-2 * DEPOSIT_SCALE_CO2 < 9.2e18);
    // At least 100x margin beyond the audited ceiling, so a modest ceiling
    // revision does not silently start truncating.
    CHECK(DEPOSIT_MAX_CONTRIBUTORS * 1.0e3 * DEPOSIT_SCALE_TEMPERATURE * 100.0 < 9.2e18);
    // The physical packing limit must sit far below the audited contributor bound.
    const double grid_cell_volume =
        (astro::canon::CHAMBER_W / astro::canon::FIELD_N_TEMP) *
        (astro::canon::CHAMBER_H / astro::canon::FIELD_N_TEMP) * astro::canon::CHAMBER_D;
    const double packing_limit = grid_cell_volume / astro::canon::CELL_VOLUME;
    CHECK(packing_limit < DEPOSIT_MAX_CONTRIBUTORS / 100.0);

    // Capacity sanity.
    CHECK(astro::canon::DEFAULT_CELLS <= astro::canon::MAX_CELLS);
    CHECK(MAX_LIGHT_SOURCES >= 1);
    CHECK(MAX_POPULATIONS >= 2);

    // Flags must be distinct bits: alive and awake are ORTHOGONAL states, and
    // conflating them would silently break the ignition latch (ADR-003).
    CHECK((CELL_FLAG_ALIVE & CELL_FLAG_AWAKE) == 0u);
    CHECK((CELL_FLAG_OCCUPIED & CELL_FLAG_ALIVE) == 0u);
    CHECK((CELL_FLAG_STUCK & CELL_FLAG_DIVIDING) == 0u);

    return astro::test::finish("test_contracts");
}
