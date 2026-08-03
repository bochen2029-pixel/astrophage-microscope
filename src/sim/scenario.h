// src/sim/scenario.h -- load scenarios/*.json into a World. docs/SCENARIOS.md (M11a).
//
// A scenario is data (contracts/scenario_v2.h, frozen). The loader parses the JSON
// (src/sim/json.h, hand-rolled) into the Scenario struct and instantiates a World from
// it. It lives in sim because it builds a World, and both the headless runner and the
// app link sim (snapshot.cpp is here for the same reason). Host-only; no GL.
//
// M11a scope: load + instantiate + run. The accept blocks are PARSED but evaluated at
// M11b; `scope` (render-only) and `param_overrides` (need a runtime-param system, M11c)
// are parsed but not applied.
#pragma once

#include <string>

#include "contracts/scenario_v2.h"
#include "core/result.h"
#include "sim/world.cuh"

namespace astro::sim {

// Parse a scenario from an in-memory JSON string. Zero-fills `out` first, so a partial
// scenario leaves sane defaults. Returns InvalidArgument on malformed JSON or an unknown
// accept metric (the one place the loader is strict).
Error scenario_parse(const std::string& text, contract::Scenario& out);

// As scenario_parse, reading the JSON from a file.
Error scenario_load(const std::string& path, contract::Scenario& out);

// Build a World from a parsed scenario: WorldDesc (chamber, boundaries, seed, capacity,
// clock inputs) + medium field fills + population spawns + the primary light source.
// Does NOT apply `scope` (render-only) or `param_overrides` (M11c). The World must be
// freshly default-constructed; on error the World is left destroyed.
Error scenario_instantiate(const contract::Scenario& s, World& w);

// Apply the scenario's driving script (v2, ADR-032) to `w` for the current tick. Call
// once per tick BEFORE world_step, from headless --assert and (later) the app. Reads
// w.sim_time_s and issues brushes / sets the light / arms the flash for every Stimulus
// whose window is active. Adds no device work beyond the brushes it already issues.
void scenario_apply_drive(World& w, const contract::Scenario& s);

} // namespace astro::sim
