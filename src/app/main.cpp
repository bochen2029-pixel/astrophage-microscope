// src/app/main.cpp -- entry point.
#include <cstdio>

#include <cuda_runtime.h>

#include "app/application.h"
#include "app/cli.h"
#include "core/canon_generated.h"

int main(int argc, char** argv) {
    astro::app::Options o = astro::app::parse_args(argc, argv);
    if (o.help) { astro::app::print_usage(); return 0; }
    if (o.bad)  { astro::app::print_usage(); return 2; }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("no CUDA device found; this simulator requires one\n");
        return 3;
    }
    cudaDeviceProp prop{};
    cudaGetDeviceProperties(&prop, 0);
    std::printf("[cuda] %s | sm_%d%d | %.1f GB\n", prop.name, prop.major, prop.minor,
                static_cast<double>(prop.totalGlobalMem) / (1024.0 * 1024.0 * 1024.0));

    astro::app::Application app;
    if (astro::Error e = astro::app::app_init(app, o)) {
        std::printf("init failed: %s (%s)\n", astro::status_str(e.status),
                    e.detail ? e.detail : "");
        astro::app::app_shutdown(app);
        return 1;
    }

    const int code = astro::app::app_run(app);
    astro::app::app_shutdown(app);
    return code;
}
