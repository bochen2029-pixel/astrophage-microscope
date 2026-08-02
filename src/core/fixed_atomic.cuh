// src/core/fixed_atomic.cuh -- deterministic accumulation. INV-2, ADR-013.
//
// THE PROBLEM: atomicAdd(float*) produces results that depend on warp
// scheduling, because float addition is not associative. Any field deposit or
// statistic accumulated that way makes the run irreproducible, breaking INV-8
// on every execution. This is the single hardest obstacle to GPU determinism.
//
// THE FIX: accumulate into 64-bit fixed point. Integer addition IS associative
// and commutative, so the sum is independent of execution order. Signed values
// ride through the unsigned atomicAdd as two's complement, which wraps to
// exactly the right answer.
//
// COST: one multiply and one round per deposit.
//
// OVERFLOW IS A SILENT CORRECTNESS BUG, NOT A CRASH. Before choosing a scale,
// verify  N_max * |value_max| * SCALE < 9.2e18. Per-field scales and their
// headroom are documented in contracts/fields_v1.h.
#pragma once

#include <cmath>
#include <cstdint>

#include "core/units.h"

namespace astro {

ASTRO_HD inline int64_t to_fixed(double value, double scale) {
    return static_cast<int64_t>(llround(value * scale));
}

ASTRO_HD inline double from_fixed(uint64_t raw, double scale) {
    return static_cast<double>(static_cast<int64_t>(raw)) / scale;
}

#if defined(__CUDACC__)
// Two's complement: adding the unsigned reinterpretation of a negative int64 is
// exactly a signed add modulo 2^64, which is what we want.
__device__ inline void atomic_deposit(unsigned long long* acc, double value, double scale) {
    atomicAdd(acc, static_cast<unsigned long long>(to_fixed(value, scale)));
}

__device__ inline void atomic_deposit_fixed(unsigned long long* acc, int64_t fixed) {
    atomicAdd(acc, static_cast<unsigned long long>(fixed));
}
#endif

// Host-side equivalent, so the same accumulation logic is testable off-device.
inline void deposit_host(uint64_t* acc, double value, double scale) {
    *acc += static_cast<uint64_t>(to_fixed(value, scale));
}

// Largest magnitude that can be accumulated n times at this scale without
// overflowing int64. Use it in an assert when introducing a new field.
inline double deposit_headroom(int64_t n, double scale) {
    return 9.2233720368547758e18 / (static_cast<double>(n) * scale);
}

} // namespace astro
