// contracts/snapshot_v1.h -- CONTRACT v1. Frozen interface; see contracts/README.md.
//
// Full-state serialisation. This is the determinism oracle (INV-8): same seed +
// same scenario + same tick count must produce an identical state_hash.
//
// Semantics: docs/ARCHITECTURE.md Sec 5.4.
#pragma once

#include <cstddef>
#include <cstdint>

namespace astro::contract {

inline constexpr int      SNAPSHOT_CONTRACT_VERSION = 1;
inline constexpr uint32_t SNAPSHOT_MAGIC = 0x48505341u; // 'ASPH' little-endian

// File layout:
//   [SnapshotHeader]
//   [ParamOverride  x override_count]
//   [CellStore SoA arrays, in contracts/cell_store_v1.h declaration order]
//   [TaumoebaStore SoA arrays]
//   [field values: temperature, co2, n2  (irradiance is rebuilt, never stored)]
//
// All little-endian. No padding beyond what is declared here.
struct SnapshotHeader {
    uint32_t magic;              // SNAPSHOT_MAGIC
    uint32_t version;            // SNAPSHOT_CONTRACT_VERSION
    uint64_t seed;
    uint64_t tick;
    double   sim_time_s;

    int32_t  cell_count, cell_capacity;
    int32_t  taumoeba_count, taumoeba_capacity;
    int32_t  n_temp, n_co2, n_n2;

    double   chamber_w, chamber_h, chamber_d;
    double   physics_rate, biology_rate;

    uint64_t next_cell_id;       // must be preserved or IDs collide after restore
    int32_t  override_count;
    uint8_t  non_canon_run;
    uint8_t  _pad[3];

    char     scenario_id[64];
    char     build_describe[64]; // git describe --always --dirty at capture time

    uint64_t state_hash;         // FNV-1a over everything after this header
};

// A broken canon lock. Recorded so a snapshot can never silently claim to be a
// canon run when it is not.
struct ParamOverride {
    char   key[48];              // matches canon::PARAM_TABLE[i].key
    double value;
};

// FNV-1a 64. Defined here so tools/, tests/, and sim/ cannot disagree about the
// determinism oracle. Order of bytes hashed is the file layout order above.
inline uint64_t fnv1a64(const void* data, size_t n, uint64_t h = 1469598103934665603ull) {
    const unsigned char* p = static_cast<const unsigned char*>(data);
    for (size_t i = 0; i < n; ++i) { h ^= p[i]; h *= 1099511628211ull; }
    return h;
}

} // namespace astro::contract
