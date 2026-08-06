// src/app/exe_path.h -- locate resources relative to the running executable (M12j).
#pragma once

#include <string>

namespace astro::app {

// The `scenarios` directory sitting next to the running executable, or "" if it is not there. Isolated
// in its own translation unit so <windows.h>/<filesystem> never share a TU with the CUDA headers
// application.cpp pulls in (that combination trips the CCCL traditional-preprocessor warning under /WX).
std::string scenarios_beside_exe();

} // namespace astro::app
