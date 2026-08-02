// src/core/vec.cuh -- minimal double-precision 3-vector.
//
// Positions span six decades (mm chamber, nm structure), so kinematics are f64
// throughout (PHYSICS.md Sec 1). On sm_89 the fp64 rate is 1/64 fp32, so this
// type belongs in the integrator and the energy ledger and NOWHERE ELSE --
// field stencils and render instance data are f32.
#pragma once

#include <cmath>

#include "core/units.h"

namespace astro {

struct Vec3 {
    double x, y, z;
};

ASTRO_HD inline Vec3 make_vec3(double x, double y, double z) { return Vec3{x, y, z}; }
ASTRO_HD inline Vec3 operator+(Vec3 a, Vec3 b) { return Vec3{a.x + b.x, a.y + b.y, a.z + b.z}; }
ASTRO_HD inline Vec3 operator-(Vec3 a, Vec3 b) { return Vec3{a.x - b.x, a.y - b.y, a.z - b.z}; }
ASTRO_HD inline Vec3 operator*(Vec3 a, double s) { return Vec3{a.x * s, a.y * s, a.z * s}; }
ASTRO_HD inline Vec3 operator*(double s, Vec3 a) { return a * s; }
ASTRO_HD inline Vec3 operator-(Vec3 a) { return Vec3{-a.x, -a.y, -a.z}; }
ASTRO_HD inline Vec3& operator+=(Vec3& a, Vec3 b) { a.x += b.x; a.y += b.y; a.z += b.z; return a; }
ASTRO_HD inline Vec3& operator-=(Vec3& a, Vec3 b) { a.x -= b.x; a.y -= b.y; a.z -= b.z; return a; }

ASTRO_HD inline double dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
ASTRO_HD inline double length_sq(Vec3 a) { return dot(a, a); }
ASTRO_HD inline double length(Vec3 a) { return sqrt(dot(a, a)); }

ASTRO_HD inline Vec3 normalize(Vec3 a) {
    const double l = length(a);
    return l > 0.0 ? a * (1.0 / l) : Vec3{0.0, 0.0, 1.0};
}

ASTRO_HD inline Vec3 cross(Vec3 a, Vec3 b) {
    return Vec3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}

} // namespace astro
