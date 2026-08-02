// src/core/rng.cuh -- PCG32 with per-cell streams. INV-1, ADR-014.
//
// WHY PER-CELL STREAMS: with a single global generator, adding or removing one
// cell shifts every subsequent cell's draws, so any run in which a division or
// death occurs is irreproducible -- which is every interesting run. curand's
// default sequences are worse: they key off thread index, so a change in launch
// configuration reshuffles everything (violating INV-4 as well).
//
// Only 64 bits of state are stored per cell (contracts/cell_store_v1.h). The
// stream selector `inc` is derived on the fly from the cell's stable id, which
// is already stored -- so a cell's random sequence depends on nothing but
// (seed_global, cell_id, draw_index).
#pragma once

#include <cmath>
#include <cstdint>

#include "core/units.h"

namespace astro {

// SplitMix64 -- used only to decorrelate seeds, never as a simulation RNG.
ASTRO_HD inline uint64_t splitmix64(uint64_t x) {
    x += 0x9E3779B97F4A7C15ull;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
    return x ^ (x >> 31);
}

struct Pcg32 {
    uint64_t state;
    uint64_t inc;      // must be odd; selects the stream
};

ASTRO_HD inline uint32_t pcg32_next(Pcg32& r) {
    const uint64_t old = r.state;
    r.state = old * 6364136223846793005ull + r.inc;
    const uint32_t xorshifted = static_cast<uint32_t>(((old >> 18) ^ old) >> 27);
    const uint32_t rot = static_cast<uint32_t>(old >> 59);
    return (xorshifted >> rot) | (xorshifted << ((0u - rot) & 31u));
}

// Reference PCG seeding (pcg32_srandom_r), so the known test vectors apply.
ASTRO_HD inline Pcg32 pcg32_seed(uint64_t initstate, uint64_t initseq) {
    Pcg32 r{0ull, (initseq << 1u) | 1u};
    pcg32_next(r);
    r.state += initstate;
    pcg32_next(r);
    return r;
}

// The stream a cell owns. `inc` is reconstructed from the id, so only `state`
// needs storing.
ASTRO_HD inline uint64_t cell_stream_inc(uint64_t cell_id) {
    return (splitmix64(cell_id ^ 0xA5A5A5A5DEADBEEFull) << 1u) | 1u;
}

ASTRO_HD inline Pcg32 cell_rng(uint64_t stored_state, uint64_t cell_id) {
    return Pcg32{stored_state, cell_stream_inc(cell_id)};
}

ASTRO_HD inline uint64_t cell_rng_init(uint64_t seed_global, uint64_t cell_id) {
    Pcg32 r = pcg32_seed(seed_global ^ splitmix64(cell_id), splitmix64(cell_id + 1));
    return r.state;
}

// A daughter must not share her mother's sequence. Deterministic in
// (parent_state, daughter_id) alone -- never in birth order or thread index.
ASTRO_HD inline uint64_t pcg_split(uint64_t parent_state, uint64_t daughter_id) {
    return splitmix64(parent_state ^ splitmix64(daughter_id * 0x2545F4914F6CDD1Dull));
}

// --- distributions ---------------------------------------------------------

// Uniform in [0,1). 24-bit mantissa fill: exact, never returns 1.0.
ASTRO_HD inline float uniform01(Pcg32& r) {
    return static_cast<float>(pcg32_next(r) >> 8) * (1.0f / 16777216.0f);
}

ASTRO_HD inline double uniform01d(Pcg32& r) {
    const uint64_t hi = static_cast<uint64_t>(pcg32_next(r)) << 21;
    const uint64_t lo = static_cast<uint64_t>(pcg32_next(r)) >> 11;
    return static_cast<double>((hi ^ lo) & ((1ull << 53) - 1)) * (1.0 / 9007199254740992.0);
}

ASTRO_HD inline double uniform_range(Pcg32& r, double lo, double hi) {
    return lo + (hi - lo) * uniform01d(r);
}

// Box-Muller. Returns both variates because the OU update (PHYSICS.md 3.2)
// needs three per cell per tick and wasting one per call is measurable.
ASTRO_HD inline void gaussian_pair(Pcg32& r, double& z0, double& z1) {
    // Guard against exactly 0, which would make log() infinite.
    double u1 = uniform01d(r);
    if (u1 < 1.0e-300) u1 = 1.0e-300;
    const double u2 = uniform01d(r);
    const double mag = sqrt(-2.0 * log(u1));
    const double ang = 6.283185307179586476925286766559 * u2;
    z0 = mag * cos(ang);
    z1 = mag * sin(ang);
}

ASTRO_HD inline double gaussian(Pcg32& r) {
    double z0, z1;
    gaussian_pair(r, z0, z1);
    (void)z1;
    return z0;
}

// Three variates for a 3D thermal kick. Two Box-Muller calls, one discarded.
ASTRO_HD inline void gaussian3(Pcg32& r, double& x, double& y, double& z) {
    double a, b, c, d;
    gaussian_pair(r, a, b);
    gaussian_pair(r, c, d);
    (void)d;
    x = a; y = b; z = c;
}

} // namespace astro
