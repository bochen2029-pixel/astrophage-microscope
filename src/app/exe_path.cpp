// src/app/exe_path.cpp -- Win32 executable-relative resource lookup, kept clear of the CUDA headers.
#include "app/exe_path.h"

#ifdef _WIN32
// NOMINMAX and friends are already set on the compile command line project-wide -- do not redefine them
// (C4005 is fatal under /WX); just pull the header for GetModuleFileNameA.
#  include <windows.h>
#endif

#include <filesystem>

namespace astro::app {

std::string scenarios_beside_exe() {
#ifdef _WIN32
    char buf[MAX_PATH] = {};
    const unsigned long len = GetModuleFileNameA(nullptr, buf, MAX_PATH);
    if (len > 0 && len < MAX_PATH) {
        std::filesystem::path d = std::filesystem::path(buf).parent_path() / "scenarios";
        std::error_code ec;
        if (std::filesystem::exists(d, ec)) return d.string();
    }
#endif
    return std::string();
}

} // namespace astro::app
