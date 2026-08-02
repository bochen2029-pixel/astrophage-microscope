// tests/physics/test_fields.cu -- T25 and the diffusion oracle.
//
// The M5 gate text asked the grid to reproduce T(r) = T_inf + dT*a/r. It cannot,
// and should not: that is the THREE-dimensional point-source law, used by
// ADR-010's per-cell near-field correction. This grid is depth-averaged and
// therefore 2D, where a point source relaxes logarithmically (ADR-019).
//
// So the quantitative test here is the exact 2D diffusion solution instead: a
// Gaussian stays Gaussian, with variance sigma^2(t) = sigma0^2 + 2*D*t per axis.
// That pins the diffusivity itself, not just "it spreads out".
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>

#include "core/canon_generated.h"
#include "fields/grid.cuh"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::fields;

namespace {

double total(const std::vector<float>& v) {
    double s = 0.0;
    for (float f : v) s += f;
    return s;
}

// Second moment about the centre, in metres^2, per axis.
double variance_per_axis(const std::vector<float>& v, int n, double dx, double base) {
    double m = 0.0, m2 = 0.0;
    const double half = 0.5 * n * dx;
    for (int j = 0; j < n; ++j) {
        for (int i = 0; i < n; ++i) {
            const double w = v[j * n + i] - base;
            if (w <= 0.0) continue;
            const double x = (i + 0.5) * dx - half;
            const double y = (j + 0.5) * dx - half;
            m += w;
            m2 += w * (x * x + y * y);
        }
    }
    return (m > 0.0) ? m2 / m / 2.0 : 0.0;   // /2 because m2 pools both axes
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_fields: no CUDA device; skipping\n");
        return 0;
    }

    const double W = canon::CHAMBER_W;
    const double D = canon::WATER_THERMAL_DIFFUSIVITY;

    // --- substeps come from the stability criterion --------------------------
    {
        std::printf("  substeps: temperature %d, CO2 %d\n", TEMP_SUBSTEPS, CO2_SUBSTEPS);
        CHECK(TEMP_SUBSTEPS == 10);       // matches VERIFICATION.md Sec 6
        CHECK(CO2_SUBSTEPS == 1);
        const double dt_max = explicit_dt_max(W, canon::FIELD_N_TEMP, D);
        CHECK(canon::DT_PHYSICS / TEMP_SUBSTEPS <= dt_max);
        // The FTCS coefficient must land at or under 1/4.
        const double dx = W / canon::FIELD_N_TEMP;
        const double coeff = D * (canon::DT_PHYSICS / TEMP_SUBSTEPS) / (dx * dx);
        std::printf("  FTCS coefficient = %.4f (stability limit 0.25)\n", coeff);
        CHECK(coeff <= 0.25);
    }

    // --- T25: conservation under an insulated boundary -----------------------
    // Pure diffusion moves heat around; it never creates or destroys it. Under
    // Neumann the grid total must be invariant.
    {
        Grid2D g;
        CHECK(!grid_create(g, 256, W, D, 0.0, 1.0e9,
                           contract::BoundaryCondition::Neumann, canon::DT_PHYSICS));
        const int n = g.n;
        std::vector<float> host(static_cast<size_t>(n) * n, 0.0f);
        // A hot square, deliberately sharp so the solver has something to smooth.
        for (int j = n / 2 - 8; j < n / 2 + 8; ++j)
            for (int i = n / 2 - 8; i < n / 2 + 8; ++i) host[j * n + i] = 100.0f;
        cudaMemcpy(g.value, host.data(), sizeof(float) * host.size(), cudaMemcpyHostToDevice);

        std::vector<float> before(host.size());
        CHECK(!grid_download(g, before.data()));
        const double t0 = total(before);

        for (int s = 0; s < 10000; ++s) CHECK(!grid_diffuse(g, canon::DT_PHYSICS));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<float> after(host.size());
        CHECK(!grid_download(g, after.data()));
        const double t1 = total(after);

        int nan_count = 0;
        float lo = 1e30f, hi = -1e30f;
        for (float f : after) {
            if (!std::isfinite(f)) ++nan_count;
            if (f < lo) lo = f;
            if (f > hi) hi = f;
        }
        std::printf("  insulated 10k ticks: total %.4f -> %.4f (drift %.4f%%), range [%.4f, %.4f]\n",
                    t0, t1, (t1 - t0) / t0 * 100.0, lo, hi);
        CHECK(nan_count == 0);
        CHECK_CLOSE(t1, t0, 1e-3);        // conserved to 0.1 %
        // No oscillation: an explicit step within its stability bound is
        // monotone, so nothing may undershoot below the initial minimum.
        CHECK(lo >= -1e-4f);
        CHECK(hi <= 100.0f + 1e-3f);
        grid_destroy(g);
    }

    // --- the quantitative oracle: 2D Gaussian spreading ----------------------
    {
        Grid2D g;
        CHECK(!grid_create(g, 512, W, D, 0.0, 1.0e9,
                           contract::BoundaryCondition::Neumann, canon::DT_PHYSICS));
        const int n = g.n;
        const double dx = g.dx;
        const double sigma0 = 1.0e-4;     // 100 um, comfortably resolved
        std::vector<float> host(static_cast<size_t>(n) * n, 0.0f);
        const double half = 0.5 * n * dx;
        for (int j = 0; j < n; ++j) {
            for (int i = 0; i < n; ++i) {
                const double x = (i + 0.5) * dx - half;
                const double y = (j + 0.5) * dx - half;
                host[j * n + i] = static_cast<float>(
                    100.0 * std::exp(-(x * x + y * y) / (2.0 * sigma0 * sigma0)));
            }
        }
        cudaMemcpy(g.value, host.data(), sizeof(float) * host.size(), cudaMemcpyHostToDevice);

        const double t_run = 0.5;
        const int ticks = static_cast<int>(t_run / canon::DT_PHYSICS);
        for (int s = 0; s < ticks; ++s) CHECK(!grid_diffuse(g, canon::DT_PHYSICS));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);

        std::vector<float> after(host.size());
        CHECK(!grid_download(g, after.data()));

        const double var_got = variance_per_axis(after, n, dx, 0.0);
        const double var_want = sigma0 * sigma0 + 2.0 * D * t_run;
        std::printf("  Gaussian spreading over %.2f s: sigma %.1f -> %.1f um "
                    "(analytic %.1f um, error %.2f%%)\n",
                    t_run, sigma0 * 1e6, std::sqrt(var_got) * 1e6,
                    std::sqrt(var_want) * 1e6,
                    (std::sqrt(var_got) - std::sqrt(var_want)) / std::sqrt(var_want) * 100.0);
        CHECK_CLOSE(var_got, var_want, 2e-2);
        grid_destroy(g);
    }

    // --- boundary conditions each do what they claim -------------------------
    {
        const double amb = 300.0;
        struct Case { contract::BoundaryCondition bc; const char* name; };
        const Case cases[] = {
            {contract::BoundaryCondition::Neumann,   "neumann"},
            {contract::BoundaryCondition::Dirichlet, "dirichlet"},
            {contract::BoundaryCondition::Robin,     "robin"},
        };
        double finals[3];
        for (int c = 0; c < 3; ++c) {
            Grid2D g;
            CHECK(!grid_create(g, 128, W, D, amb, 1.0e9, cases[c].bc, canon::DT_PHYSICS));
            CHECK(!grid_fill(g, static_cast<float>(amb + 50.0)));   // uniformly hot
            for (int s = 0; s < 20000; ++s) CHECK(!grid_diffuse(g, canon::DT_PHYSICS));
            CHECK(cudaDeviceSynchronize() == cudaSuccess);
            std::vector<float> v(static_cast<size_t>(g.n) * g.n);
            CHECK(!grid_download(g, v.data()));
            finals[c] = total(v) / v.size();
            std::printf("  %-10s after 20 s: mean %.3f (started %.1f, ambient %.1f)\n",
                        cases[c].name, finals[c], amb + 50.0, amb);
            grid_destroy(g);
        }
        // Insulated: nothing escapes, so the uniform field is untouched.
        CHECK_CLOSE(finals[0], amb + 50.0, 1e-4);
        // Dirichlet: the edge is pinned to ambient, so heat drains out.
        CHECK(finals[1] < amb + 50.0);
        // Robin: also drains, but far more slowly -- at dx = 31 um the coupling
        // dx*h/k is ~5e-4, so a chamber edge is nearly insulating in practice.
        CHECK(finals[2] < amb + 50.0);
        CHECK(finals[2] > finals[1]);
    }

    // --- fixed-point deposits (INV-2) ----------------------------------------
    {
        Grid2D g;
        CHECK(!grid_create(g, 64, W, D, 0.0, contract::DEPOSIT_SCALE_TEMPERATURE,
                           contract::BoundaryCondition::Neumann, canon::DT_PHYSICS));
        std::vector<float> v(static_cast<size_t>(g.n) * g.n);
        CHECK(!grid_download(g, v.data()));
        CHECK_CLOSE(total(v), 0.0, 1e-6);

        // Deposits accumulate in int64 and only reach `value` on flush.
        unsigned long long raw = static_cast<unsigned long long>(
            astro::to_fixed(12.5, contract::DEPOSIT_SCALE_TEMPERATURE));
        cudaMemcpy(g.deposit, &raw, sizeof(raw), cudaMemcpyHostToDevice);
        CHECK(!grid_download(g, v.data()));
        CHECK_CLOSE(v[0], 0.0, 1e-6);                 // not visible yet

        CHECK(!grid_flush_deposits(g));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!grid_download(g, v.data()));
        CHECK_CLOSE(v[0], 12.5, 1e-5);                // now it is
        CHECK_CLOSE(total(v), 12.5, 1e-5);            // and nowhere else

        // Flushing twice must not double-count: the accumulator is zeroed.
        CHECK(!grid_flush_deposits(g));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!grid_download(g, v.data()));
        CHECK_CLOSE(v[0], 12.5, 1e-5);
        grid_destroy(g);
    }

    // --- brushes, through the world, at a tick boundary ----------------------
    {
        sim::World w;
        sim::WorldDesc d;
        d.capacity = 100;
        CHECK(!sim::world_create(w, d));

        std::vector<float> v(static_cast<size_t>(w.fields.temperature.n) *
                             w.fields.temperature.n);
        CHECK(!grid_download(w.fields.temperature, v.data()));
        const double before = total(v);

        CHECK(!sim::world_apply_brush(w, sim::BrushKind::Heat, 0.0, 0.0, 2.0e-4, 40.0));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!grid_download(w.fields.temperature, v.data()));
        const double after = total(v);
        float peak = -1e30f;
        for (float f : v) if (f > peak) peak = f;
        std::printf("  heat brush: mean %.3f -> %.3f K, peak %.2f K\n",
                    before / v.size(), after / v.size(), peak);
        CHECK(after > before);
        CHECK(peak > canon::AMBIENT_TEMP_DEFAULT + 30.0);

        // Chill removes what heat added.
        CHECK(!sim::world_apply_brush(w, sim::BrushKind::Chill, 0.0, 0.0, 2.0e-4, 40.0));
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!grid_download(w.fields.temperature, v.data()));
        CHECK_CLOSE(total(v), before, 1e-5);

        // And a world tick leaves the field finite.
        for (int s = 0; s < 100; ++s) sim::world_step(w);
        CHECK(cudaDeviceSynchronize() == cudaSuccess);
        CHECK(!grid_download(w.fields.temperature, v.data()));
        int bad = 0;
        for (float f : v) if (!std::isfinite(f)) ++bad;
        CHECK(bad == 0);
        sim::world_destroy(w);
    }

    return astro::test::finish("test_fields");
}
