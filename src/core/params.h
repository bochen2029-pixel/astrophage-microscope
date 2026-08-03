// src/core/params.h -- the runtime-parameter overlay (M11c, ADR-034).
//
// A runtime OVERLAY of the generated canon (canon_generated.h's PARAM_TABLE), NOT a
// replacement: the sim reads `canon::` by default; the inspector edits this, and from M11d
// the sim reads overridden values from it for the curated tunable set. Generated canon
// stays the source of truth and the default (Iron Rule 3, the anti-drift machinery).
//
// Every CANON parameter is locked by default; breaking a lock is the one event that flags
// a run non-canon, stickily -- a run that quietly changed a canon number and still looks
// canon is the worst failure the UI can have (src/ui/MODULE.md). Header-only and POD, so
// `test_param_locks` checks the logic with no GL and the struct can pass into a kernel.
#pragma once

#include <cstring>

#include "core/canon_generated.h"

namespace astro {

struct ParamSet {
    double value[canon::PARAM_COUNT];
    bool   locked[canon::PARAM_COUNT];
    bool   non_canon_run;   // sticky: set the moment a CANON lock is broken
};

// Values = canon defaults; CANON params locked, everything else unlocked (freely tunable).
inline void param_set_init(ParamSet& p) {
    for (int i = 0; i < canon::PARAM_COUNT; ++i) {
        p.value[i]  = canon::PARAM_TABLE[i].value;
        p.locked[i] = canon::PARAM_TABLE[i].prov == canon::Provenance::Canon;
    }
    p.non_canon_run = false;
}

// Break a parameter's lock. Only CANON params start locked, so this is the sole path that
// trips the non-canon flag; it is sticky and never cleared for the run. Returns the flag.
inline bool param_unlock(ParamSet& p, int i) {
    if (i < 0 || i >= canon::PARAM_COUNT) return p.non_canon_run;
    if (p.locked[i]) {
        p.locked[i] = false;
        if (canon::PARAM_TABLE[i].prov == canon::Provenance::Canon) p.non_canon_run = true;
    }
    return p.non_canon_run;
}

// Set a parameter's value. A locked parameter is not writable, so a CANON value must be
// unlocked first (which flags the run) before it can move. Returns whether it was applied.
inline bool param_set(ParamSet& p, int i, double v) {
    if (i < 0 || i >= canon::PARAM_COUNT || p.locked[i]) return false;
    p.value[i] = v;
    return true;
}

// Parameter index by key, or -1 if unknown. Linear over 109 entries -- a cold UI/load path.
inline int param_index(const char* key) {
    if (key == nullptr) return -1;
    for (int i = 0; i < canon::PARAM_COUNT; ++i)
        if (std::strcmp(canon::PARAM_TABLE[i].key, key) == 0) return i;
    return -1;
}

} // namespace astro
