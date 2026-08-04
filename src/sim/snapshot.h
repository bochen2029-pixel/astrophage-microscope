// src/sim/snapshot.h -- full-state serialisation (M12a). docs/ARCHITECTURE.md Sec 5.4.
//
// The ASPH dump defined by contracts/snapshot_v1.h: the whole simulation state, restorable
// bit-identically within a build. This is the determinism oracle (INV-8) at full resolution --
// the file's state_hash is FNV-1a over every SoA array and field, not the position/velocity/
// energy subset tools/headless.cpp hashes for the fast replay gate.
#pragma once

#include <cstdint>
#include <vector>

#include "core/result.h"
#include "sim/world.cuh"

namespace astro::sim {

// The in-memory form of the ASPH dump: the same bytes snapshot_save writes to a file, held in a
// buffer. The time scrubber (M12d) records a rolling ring of these so it can rewind without file
// I/O per frame; snapshot_save/load are thin wrappers over them.
Error snapshot_to_bytes(const World& w, const char* scenario_id, std::vector<char>& out);
Error snapshot_from_bytes(const char* data, size_t n, World& w);

// Write the full world state to `path` (ASPH). `scenario_id` may be null (a plain run). The
// ADR-035 overrides that differ from canon are recorded on the ParamOverride array, and the
// sticky non_canon_run flag in the header, so a snapshot can never silently look canon.
Error snapshot_save(const World& w, const char* path, const char* scenario_id = nullptr);

// Restore a world from `path`. `w` MUST be a fresh (default-constructed) World; this
// world_creates it sized to the header, then uploads the state. A bad magic, version, or a
// truncated file is rejected. After this returns, world_step continues the run bit-identically
// to the saved run. The caller owns `w` and must world_destroy it.
Error snapshot_load(const char* path, World& w);

// FNV-1a over the full serialisable state (everything after the header, in file-layout order).
// Same seed + scenario + tick => same hash; a save/restore round trip must reproduce it. This
// is what test_snapshot (T21) checks the original against the restored world with.
Error snapshot_state_hash(const World& w, uint64_t& hash_out);

} // namespace astro::sim
