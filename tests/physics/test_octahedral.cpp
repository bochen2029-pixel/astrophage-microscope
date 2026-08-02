// tests/physics/test_octahedral.cpp -- direction packing round trip.
//
// The emission axis survives a 32-bit round trip well enough that a rendered
// lobe never visibly wobbles. Failing this quietly would show up much later as
// flickering emission cones, so it is pinned here.
#include <cmath>

#include "core/octahedral.cuh"
#include "core/rng.cuh"
#include "test_util.h"

using namespace astro;

int main() {
    // Axis directions must survive exactly enough to stay axis-aligned.
    const Vec3 axes[6] = {{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}};
    for (const Vec3& a : axes) {
        const Vec3 r = oct_decode(oct_encode(a));
        CHECK(dot(a, r) > 0.9999);
    }

    // Random directions on the sphere: check the worst-case angular error.
    Pcg32 rng = pcg32_seed(4242u, 1u);
    double worst_deg = 0.0;
    for (int i = 0; i < 200000; ++i) {
        // Marsaglia: uniform on the sphere, not on the cube.
        const double z = uniform_range(rng, -1.0, 1.0);
        const double phi = uniform_range(rng, 0.0, 6.283185307179586);
        const double s = std::sqrt(1.0 - z * z);
        const Vec3 n{s * std::cos(phi), s * std::sin(phi), z};

        const Vec3 d = oct_decode(oct_encode(n));
        CHECK_CLOSE(length(d), 1.0, 1e-5);          // decode must renormalise
        double c = dot(n, d);
        if (c > 1.0) c = 1.0;
        const double deg = std::acos(c) * 180.0 / 3.14159265358979323846;
        if (deg > worst_deg) worst_deg = deg;
    }
    std::printf("  worst angular error over 200k directions: %.5f deg\n", worst_deg);
    CHECK(worst_deg < 0.05);

    // The packing must actually use both 16-bit halves; a bug that drops one
    // half still round-trips vectors in the z>0 hemisphere, so check explicitly.
    CHECK(oct_encode(Vec3{1, 0, 0}) != oct_encode(Vec3{0, 1, 0}));
    CHECK(oct_encode(Vec3{0, 0, 1}) != oct_encode(Vec3{0, 0, -1}));

    return astro::test::finish("test_octahedral");
}
