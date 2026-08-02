cmake_minimum_required(VERSION 3.27)

# Reference GPU: RTX 4070 Ti SUPER = Ada Lovelace = compute_89.
# 90 (Hopper) and 120 (Blackwell consumer) kept so the build survives a GPU swap.
# Must be set BEFORE project() so CMake's CUDA detection uses it.
if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES 89 90 120 CACHE STRING "")
endif()

project(astrophage
    VERSION 0.1.0
    DESCRIPTION "Astrophage Microscope Simulator"
    # C is required: GLFW and GLAD are C libraries. Omitting it fails at generate
    # time with a misleading "required internal CMake variable not set".
    LANGUAGES C CXX CUDA)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

# Static runtimes so the shipped .exe needs neither cudart64_*.dll nor the VC++
# redistributable. Cascades to FetchContent'd subprojects automatically.
set(CMAKE_CUDA_RUNTIME_LIBRARY Static)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(CUDAToolkit REQUIRED)

option(ASTRO_BUILD_APP "Build the windowed application (needs GLFW/GLAD/ImGui via FetchContent)" OFF)
option(ASTRO_WARNINGS_AS_ERRORS "Treat warnings as errors (Iron Rule: on)" ON)

add_compile_definitions(_CRT_SECURE_NO_WARNINGS NOMINMAX)

# ---------------------------------------------------------------------------
# Generated canon. scripts/canon.py is the single source of truth for every
# physical number; derive.py emits the header, the test goldens, and the docs.
# See docs/ARCHITECTURE.md Sec 5.1 (Anti-drift machinery).
# ---------------------------------------------------------------------------
find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(ASTRO_GENERATED
    ${CMAKE_SOURCE_DIR}/src/core/canon_generated.h
    ${CMAKE_SOURCE_DIR}/tests/golden/expected_values.h
    ${CMAKE_SOURCE_DIR}/docs/VERIFICATION.md)

add_custom_command(
    OUTPUT ${ASTRO_GENERATED}
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/derive.py
    DEPENDS ${CMAKE_SOURCE_DIR}/scripts/canon.py ${CMAKE_SOURCE_DIR}/scripts/derive.py
    COMMENT "Regenerating canon artifacts from scripts/canon.py"
    VERBATIM)
add_custom_target(astro_canon DEPENDS ${ASTRO_GENERATED})

# ---------------------------------------------------------------------------
# astro_core -- header-only. Depends on NOTHING (docs/ARCHITECTURE.md Sec 7).
# ---------------------------------------------------------------------------
add_library(astro_core INTERFACE)
add_dependencies(astro_core astro_canon)
target_include_directories(astro_core INTERFACE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR})           # so "contracts/foo_v1.h" resolves

# Warnings-as-errors, and INV-6: no fast math anywhere in sim/fields.
function(astro_strict target)
    if(MSVC)
        target_compile_options(${target} PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:/W4>
            $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<BOOL:${ASTRO_WARNINGS_AS_ERRORS}>>:/WX>)
    endif()
    target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:--expt-relaxed-constexpr>
        $<$<COMPILE_LANGUAGE:CUDA>:-Xcudafe=--display_error_number>)
    set_target_properties(${target} PROPERTIES
        CUDA_SEPARABLE_COMPILATION ON
        POSITION_INDEPENDENT_CODE ON)
endfunction()

# ---------------------------------------------------------------------------
# astro_fields / astro_sim -- headless by construction (INV-5). No GL, no GLFW,
# no ImGui may ever appear in these targets; scripts/audit.ps1 greps for it.
# Sources are added milestone by milestone; the placeholder keeps the target
# valid until M2/M5 populate it.
# ---------------------------------------------------------------------------
add_library(astro_fields STATIC src/fields/fields_placeholder.cu)
target_link_libraries(astro_fields PUBLIC astro_core)
astro_strict(astro_fields)

add_library(astro_sim STATIC
    src/sim/cell_store.cu
    src/sim/integrator.cu
    src/sim/step.cu)
target_link_libraries(astro_sim PUBLIC astro_core astro_fields)
astro_strict(astro_sim)

# ---------------------------------------------------------------------------
# Tests. Dependency-free: no GL, no gtest. ctest drives plain executables that
# return nonzero on failure (tests/test_util.h).
# ---------------------------------------------------------------------------
enable_testing()

function(astro_test name)
    add_executable(${name} ${ARGN})
    target_link_libraries(${name} PRIVATE astro_core astro_sim astro_fields CUDA::cudart_static)
    target_include_directories(${name} PRIVATE ${CMAKE_SOURCE_DIR}/tests)
    astro_strict(${name})
    add_test(NAME ${name} COMMAND ${name})
endfunction()

astro_test(test_canon        tests/physics/test_canon.cpp)
astro_test(test_rng          tests/physics/test_rng.cpp)
astro_test(test_contracts    tests/physics/test_contracts.cpp)
astro_test(test_fixed_atomic tests/physics/test_fixed_atomic.cu)
astro_test(test_octahedral   tests/physics/test_octahedral.cpp)
astro_test(test_cell_store   tests/physics/test_cell_store.cu)
# Scope geometry is pure arithmetic, so the M1 "scale bar is correct at all three
# objectives" and "no size fudge" conditions are checked headless, not by eye.
astro_test(test_scope        tests/physics/test_scope.cpp)
astro_test(test_motion       tests/physics/test_motion.cpp)
astro_test(test_buoyancy     tests/physics/test_buoyancy.cu)

# ---------------------------------------------------------------------------
# tools -- headless runner. The determinism oracle (INV-8) and the scenario
# acceptance runner both live here. Never links GL.
# ---------------------------------------------------------------------------
add_executable(headless tools/headless.cpp)
target_link_libraries(headless PRIVATE astro_core astro_sim astro_fields CUDA::cudart_static)
astro_strict(headless)

add_test(NAME determinism_replay
         COMMAND headless --ticks 10000 --seed 20260802 --assert-deterministic)

# ---------------------------------------------------------------------------
# The windowed application. OFF until M1 -- keeping it off means the M0 gate
# runs with no network access and no external dependencies.
# ---------------------------------------------------------------------------
if(ASTRO_BUILD_APP)
    include(FetchContent)
    set(FETCHCONTENT_QUIET FALSE)

    FetchContent_Declare(glfw
        GIT_REPOSITORY https://github.com/glfw/glfw.git
        GIT_TAG 3.4 GIT_SHALLOW TRUE)
    set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(glfw)

    FetchContent_Declare(glad
        GIT_REPOSITORY https://github.com/Dav1dde/glad.git
        GIT_TAG v2.0.6 GIT_SHALLOW TRUE SOURCE_SUBDIR cmake)
    FetchContent_MakeAvailable(glad)
    glad_add_library(glad_gl_core_46 REPRODUCIBLE API gl:core=4.6)

    FetchContent_Declare(imgui
        GIT_REPOSITORY https://github.com/ocornut/imgui.git
        GIT_TAG v1.91.5 GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(imgui)
    add_library(imgui STATIC
        ${imgui_SOURCE_DIR}/imgui.cpp
        ${imgui_SOURCE_DIR}/imgui_draw.cpp
        ${imgui_SOURCE_DIR}/imgui_tables.cpp
        ${imgui_SOURCE_DIR}/imgui_widgets.cpp
        ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
        ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp)
    target_include_directories(imgui PUBLIC
        ${imgui_SOURCE_DIR} ${imgui_SOURCE_DIR}/backends)
    target_link_libraries(imgui PUBLIC glfw)

    file(GLOB ASTRO_RENDER_SRC CONFIGURE_DEPENDS src/render/*.cpp src/render/*.cu)
    file(GLOB ASTRO_UI_SRC     CONFIGURE_DEPENDS src/ui/*.cpp)
    file(GLOB ASTRO_APP_SRC    CONFIGURE_DEPENDS src/app/*.cpp)

    add_executable(astrophage ${ASTRO_RENDER_SRC} ${ASTRO_UI_SRC} ${ASTRO_APP_SRC})
    target_link_libraries(astrophage PRIVATE
        astro_core astro_sim astro_fields
        glfw glad_gl_core_46 imgui CUDA::cudart_static)
    astro_strict(astrophage)
    # Note: the executable stays in the build tree. Packaging into dist/ is M12;
    # redirecting it early would put it where scripts/gate.ps1 does not look.
endif()

message(STATUS "astrophage ${PROJECT_VERSION}")
message(STATUS "  CUDA        ${CMAKE_CUDA_COMPILER_VERSION}  arch ${CMAKE_CUDA_ARCHITECTURES}")
message(STATUS "  build type  ${CMAKE_BUILD_TYPE}")
message(STATUS "  app target  ${ASTRO_BUILD_APP}  (M1 turns this ON)")
