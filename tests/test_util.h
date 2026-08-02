// tests/test_util.h -- dependency-free test harness.
//
// ctest drives plain executables that return nonzero on failure. No gtest: a
// test framework would be a dependency, and Iron Rule 8 makes every dependency
// an ADR. This is enough.
#pragma once

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace astro::test {

inline int g_failures = 0;
inline int g_checks   = 0;

inline void report(bool pass, const char* expr, const char* file, int line, const char* extra) {
    ++g_checks;
    if (!pass) {
        ++g_failures;
        std::printf("  FAIL %s:%d  %s%s%s\n", file, line, expr,
                    extra ? "  -- " : "", extra ? extra : "");
    }
}

inline bool close_rel(double got, double want, double rel_tol) {
    if (want == 0.0) return std::fabs(got) <= rel_tol;
    return std::fabs(got - want) / std::fabs(want) <= rel_tol;
}

inline int finish(const char* suite) {
    std::printf("%s: %d checks, %d failures\n", suite, g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}

} // namespace astro::test

#define CHECK(cond) \
    ::astro::test::report((cond), #cond, __FILE__, __LINE__, nullptr)

#define CHECK_CLOSE(got, want, rel_tol)                                              \
    do {                                                                             \
        const double _g = (got), _w = (want), _t = (rel_tol);                        \
        char _buf[192];                                                              \
        std::snprintf(_buf, sizeof(_buf), "got %.12g want %.12g rel_tol %.3g", _g, _w, _t); \
        ::astro::test::report(::astro::test::close_rel(_g, _w, _t),                  \
                              #got " ~= " #want, __FILE__, __LINE__, _buf);          \
    } while (0)

#define CHECK_EQ_U64(got, want)                                                      \
    do {                                                                             \
        const unsigned long long _g = (unsigned long long)(got);                     \
        const unsigned long long _w = (unsigned long long)(want);                    \
        char _buf[128];                                                              \
        std::snprintf(_buf, sizeof(_buf), "got 0x%llx want 0x%llx", _g, _w);         \
        ::astro::test::report(_g == _w, #got " == " #want, __FILE__, __LINE__, _buf);\
    } while (0)
