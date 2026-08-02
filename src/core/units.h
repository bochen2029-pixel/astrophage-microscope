// src/core/units.h -- SI discipline and the host/device compilation bridge.
//
// UNITS POLICY (docs/CLAUDE.md, Code standards): core/, sim/, and fields/ are
// strict SI -- m, kg, s, K, J, W. Display units (um, degC, ng, mW) exist ONLY in
// ui/ and render/. The helpers below are the sanctioned conversion points; if a
// conversion appears anywhere else, it is a bug.
#pragma once

#include <cstdint>

// Lets a header of __host__ __device__ physics be included from a plain .cpp
// compiled by MSVC, so tests exercise the real code path (ARCHITECTURE.md 3.3).
#if defined(__CUDACC__)
    #define ASTRO_HD __host__ __device__
    #define ASTRO_DEV __device__
#else
    #define ASTRO_HD
    #define ASTRO_DEV
#endif

namespace astro {

// --- display conversions (ui/ and render/ only) ----------------------------
ASTRO_HD inline double m_to_um(double m)      { return m * 1.0e6; }
ASTRO_HD inline double um_to_m(double um)     { return um * 1.0e-6; }
ASTRO_HD inline double kg_to_ng(double kg)    { return kg * 1.0e12; }
ASTRO_HD inline double ng_to_kg(double ng)    { return ng * 1.0e-12; }
ASTRO_HD inline double k_to_c(double k)       { return k - 273.15; }
ASTRO_HD inline double c_to_k(double c)       { return c + 273.15; }
ASTRO_HD inline double w_to_mw(double w)      { return w * 1.0e3; }
ASTRO_HD inline double j_to_g_tnt(double j)   { return j / 4184.0; }

// --- small numeric helpers -------------------------------------------------
template <typename T> ASTRO_HD inline T astro_min(T a, T b) { return a < b ? a : b; }
template <typename T> ASTRO_HD inline T astro_max(T a, T b) { return a > b ? a : b; }
template <typename T> ASTRO_HD inline T clamp(T v, T lo, T hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
ASTRO_HD inline double clamp01(double v) { return clamp(v, 0.0, 1.0); }

} // namespace astro
