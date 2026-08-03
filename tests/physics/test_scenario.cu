// tests/physics/test_scenario.cu -- M11a gate. docs/SCENARIOS.md.
//
// The scenario spine: every scenario JSON loads, instantiates into a World, and runs
// deterministically (INV-8 for scenario-built worlds). Plus the hand-rolled JSON parser
// and scenario_parse. Accept-block *evaluation* and scenario driving are M11b -- this
// milestone proves the content loads and runs, not that it passes its objectives.
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/scenario_v1.h"
#include "contracts/snapshot_v1.h"
#include "sim/json.h"
#include "sim/scenario.h"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

#ifndef ASTRO_SCENARIOS_DIR
#define ASTRO_SCENARIOS_DIR "scenarios"
#endif

namespace {

const char* SCENARIO_IDS[] = {
    "first-light", "three-percent-line", "komorov", "shadow-garden",
    "bloom", "taumoeba", "spin-drive-face", "sandbox",
};

std::string scenario_path(const char* id) {
    return std::string(ASTRO_SCENARIOS_DIR) + "/" + id + ".json";
}

uint64_t hash_world(World& w) {
    const int32_t nc = w.cells.count, nt = w.taumoeba.count;
    std::vector<double> cx(nc), cy(nc), cz(nc), tx(nt), ty(nt), tz(nt);
    cell_store_download_positions(w.cells, cx.data(), cy.data(), cz.data(), nc);
    taumoeba_download_positions(w.taumoeba, tx.data(), ty.data(), tz.data(), nt);
    uint64_t h = contract::fnv1a64(&nc, sizeof(nc));
    h = contract::fnv1a64(&nt, sizeof(nt), h);
    if (nc) {
        h = contract::fnv1a64(cx.data(), sizeof(double) * nc, h);
        h = contract::fnv1a64(cy.data(), sizeof(double) * nc, h);
        h = contract::fnv1a64(cz.data(), sizeof(double) * nc, h);
    }
    if (nt) {
        h = contract::fnv1a64(tx.data(), sizeof(double) * nt, h);
        h = contract::fnv1a64(ty.data(), sizeof(double) * nt, h);
        h = contract::fnv1a64(tz.data(), sizeof(double) * nt, h);
    }
    return h;
}

}  // namespace

int main() {
    // --- T-SCN.1 (pure): the JSON parser ------------------------------------
    {
        std::string err;
        json::Value v = json::parse(
            "{ \"a\": 1, \"b\": [true, null, \"x\"], // trailing comment\n \"c\": 2.5e-3 }", err);
        CHECK(v.is_object());
        CHECK(v.num("a", -1.0) == 1.0);
        const json::Value* b = v.find("b");
        CHECK(b && b->is_array() && b->size() == 3);
        CHECK(b->arr[0].bool_or(false) == true);
        CHECK(b->arr[1].is_null());
        CHECK(b->arr[2].str_or("") == "x");
        CHECK(std::fabs(v.num("c", 0.0) - 2.5e-3) < 1e-12);
        json::Value bad = json::parse("{ oops }", err);
        CHECK(bad.is_null());
    }

    // --- T-SCN.2 (pure): scenario_parse from a string -----------------------
    {
        contract::Scenario s;
        const char* js =
            "{ \"id\":\"t\", \"seed\": 7, "
            "  \"populations\":[{\"kind\":\"astrophage\",\"count\":5,\"awake\":true}], "
            "  \"clock\":{\"preset\":\"motion\"} }";
        CHECK(!scenario_parse(js, s));
        CHECK(std::string(s.id) == "t");
        CHECK(s.seed == 7);
        CHECK(s.population_count == 1);
        CHECK(s.populations[0].count == 5);
        CHECK(s.populations[0].awake == 1);
        CHECK(s.clock == contract::ClockPreset::Motion);
        // An unknown accept metric is the one thing the loader rejects.
        contract::Scenario bad;
        CHECK(static_cast<bool>(
            scenario_parse("{\"objective\":{\"accept\":[{\"metric\":\"nope\"}]}}", bad)));
    }

    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_scenario: no CUDA device; ran the pure checks only\n");
        return astro::test::finish("test_scenario");
    }

    // --- T-SCN.3 (GATE): every scenario loads, instantiates, runs, and is
    // bit-reproducible; the spawned population matches the spec ---------------
    const int ticks = 50;
    for (const char* id : SCENARIO_IDS) {
        contract::Scenario s;
        if (scenario_load(scenario_path(id), s)) {
            std::printf("  FAIL: could not load %s\n", id);
            CHECK(false);
            continue;
        }
        int32_t exp_cells = 0, exp_tau = 0;
        for (int i = 0; i < s.population_count; ++i) {
            if (s.populations[i].kind == contract::OrganismKind::Taumoeba)
                exp_tau += s.populations[i].count;
            else
                exp_cells += s.populations[i].count;
        }

        uint64_t h[2] = {0, 0};
        int32_t nc = 0, nt = 0;
        for (int pass = 0; pass < 2; ++pass) {
            World w{};
            CHECK(!scenario_instantiate(s, w));
            if (pass == 0) { nc = w.cells.count; nt = w.taumoeba.count; }
            for (int t = 0; t < ticks; ++t) world_step(w);
            cudaDeviceSynchronize();
            h[pass] = hash_world(w);
            world_destroy(w);
        }
        std::printf("  %-18s cells %6d (exp %6d)  tau %4d (exp %4d)  hash %016llx  %s\n",
                    id, nc, exp_cells, nt, exp_tau,
                    static_cast<unsigned long long>(h[0]), h[0] == h[1] ? "det" : "NONDET");
        CHECK(nc == exp_cells);
        CHECK(nt == exp_tau);
        CHECK(h[0] == h[1]);
    }

    // A different scenario produces a different trajectory -- the loader is not a
    // no-op that maps everything to one default world.
    {
        contract::Scenario a, b;
        CHECK(!scenario_load(scenario_path("first-light"), a));
        CHECK(!scenario_load(scenario_path("sandbox"), b));
        World wa{}, wb{};
        CHECK(!scenario_instantiate(a, wa));
        CHECK(!scenario_instantiate(b, wb));
        for (int t = 0; t < 20; ++t) { world_step(wa); world_step(wb); }
        cudaDeviceSynchronize();
        CHECK(hash_world(wa) != hash_world(wb));
        world_destroy(wa);
        world_destroy(wb);
    }

    return astro::test::finish("test_scenario");
}
