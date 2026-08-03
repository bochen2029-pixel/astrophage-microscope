// tests/physics/test_snapshot.cu -- T21. Full-state snapshot round trip and replay across the
// save/restore boundary (M12a, contracts/snapshot_v1.h, ADR-036).
#include <cstdio>
#include <cstdint>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "sim/snapshot.h"
#include "sim/world.cuh"
#include "test_util.h"

using namespace astro;
using namespace astro::sim;

namespace {

const char* kPath = "test_snapshot.asph";

// A growth world like test_lifecycle's: saturating CO2 + a compressed biology clock so cells
// divide within tens of ticks, giving a non-trivial SoA. Absorbing walls let a few sink into
// the -y wall and become corpses (compaction stays off, so those dead slots persist in [0,count)
// and are exercised by the serialisation). Charge 0.5 so they sink.
Error make_growth_world(World& w, int32_t n, double biology_rate, bool absorbing,
                        uint64_t seed = 20260802ull) {
    WorldDesc d;
    d.capacity = 1 << 20;
    d.seed = seed;
    d.co2_init = canon::CO2_SAT_CONC_1ATM;
    d.motion.emission_enabled = false;
    d.motion.taxis_enabled = false;
    if (absorbing) {
        d.motion.boundary_x = Boundary::Absorbing;
        d.motion.boundary_y = Boundary::Absorbing;
    }
    ASTRO_TRY(world_create(w, d));
    w.biology_rate = biology_rate;
    SpawnParams p;
    p.count = n;
    p.placement = Placement::Uniform;
    p.charge_dist = Distribution::Constant;
    p.charge_a = 0.5;
    p.awake = false;
    return cell_store_spawn(w.cells, p, w.chamber, seed);
}

uint64_t hashw(const World& w) {
    uint64_t h = 0;
    CHECK(!snapshot_state_hash(w, h));
    return h;
}

} // namespace

int main() {
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess || devices == 0) {
        std::printf("test_snapshot: no CUDA device; skipping\n");
        return 0;
    }

    // --- T21.1 (GATE): round-trip fidelity with a rich world ------------------
    // Cells that have divided (and some sunk into the wall as corpses), predators present, a
    // tuned override, and a broken canon lock. Save -> load -> the full-state hash and every
    // header scalar must survive.
    {
        World w{};
        CHECK(!make_growth_world(w, 3000, 2.0e7, /*absorbing=*/true));
        CHECK(!taumoeba_spawn(w.taumoeba, 40, w.chamber, 4242ull));
        for (int t = 0; t < 50; ++t) world_step(w);
        cudaDeviceSynchronize();
        // A tuned override (rides the ParamOverride array) and a broken lock (the header flag),
        // so a round trip can never quietly look canon.
        w.co2_mass_per_division = 0.5 * canon::CO2_MASS_PER_DIVISION;
        w.non_canon_run = true;

        const uint64_t h0 = hashw(w);
        const int32_t cells0 = w.cells.count, tau0 = w.taumoeba.count;
        const uint64_t tick0 = w.tick, nextid0 = w.cells.next_id;
        CHECK(cells0 > 3000);                       // divisions happened: a non-trivial SoA
        CHECK(!snapshot_save(w, kPath, "unit-test"));
        world_destroy(w);

        World w2{};
        CHECK(!snapshot_load(kPath, w2));
        std::printf("  T21.1: restored cells %d tau %d tick %llu hash %016llx\n",
                    w2.cells.count, w2.taumoeba.count,
                    static_cast<unsigned long long>(w2.tick),
                    static_cast<unsigned long long>(hashw(w2)));
        CHECK(w2.cells.count == cells0);
        CHECK(w2.taumoeba.count == tau0);
        CHECK(w2.tick == tick0);
        CHECK(w2.cells.next_id == nextid0);         // or daughters collide after restore
        CHECK(w2.non_canon_run == true);            // the flag survived
        CHECK(w2.co2_mass_per_division == 0.5 * canon::CO2_MASS_PER_DIVISION);  // override restored
        CHECK(hashw(w2) == h0);                      // full-state fidelity
        world_destroy(w2);
    }

    // --- T21.2 (GATE): replay across the save/restore boundary ----------------
    // The hard claim: a restored world is a valid CONTINUATION point. Step the original and the
    // restored world the same number of ticks past the boundary and require identical full
    // state -- so next_cell_id and every per-cell RNG stream came back exactly. Motion config is
    // the caller's to restore (snapshot_v1), so mirror it.
    {
        World a{};
        CHECK(!make_growth_world(a, 2000, 2.0e7, /*absorbing=*/false));
        for (int t = 0; t < 40; ++t) world_step(a);
        cudaDeviceSynchronize();
        const MotionConfig motion = a.motion;
        const double bio = a.biology_rate;

        CHECK(!snapshot_save(a, kPath));

        World b{};
        CHECK(!snapshot_load(kPath, b));
        b.motion = motion;          // configuration is not serialised (snapshot_v1)
        b.biology_rate = bio;       // nor the clock rates beyond the header's physics/biology
        CHECK(hashw(b) == hashw(a));                 // same starting point

        for (int t = 0; t < 30; ++t) { world_step(a); world_step(b); }
        cudaDeviceSynchronize();
        std::printf("  T21.2: +30 past boundary -> a cells %d hash %016llx | b cells %d hash %016llx\n",
                    a.cells.count, static_cast<unsigned long long>(hashw(a)),
                    b.cells.count, static_cast<unsigned long long>(hashw(b)));
        CHECK(a.cells.count > 2000);                 // divisions occurred in the window
        CHECK(a.cells.count == b.cells.count);
        CHECK(hashw(a) == hashw(b));                 // bit-identical continuation
        world_destroy(a);
        world_destroy(b);
    }

    // --- T21.3 (GATE): a corrupt file is rejected -----------------------------
    // A snapshot that does not begin with the ASPH magic must not load as a valid world.
    {
        World w{};
        CHECK(!make_growth_world(w, 500, 1.0, /*absorbing=*/false));
        CHECK(!snapshot_save(w, kPath));
        world_destroy(w);

        std::FILE* f = std::fopen(kPath, "r+b");
        CHECK(f != nullptr);
        const uint32_t bad = 0xDEADBEEFu;
        std::fwrite(&bad, sizeof(bad), 1, f);        // clobber the magic
        std::fclose(f);

        World w2{};
        const Error e = snapshot_load(kPath, w2);
        std::printf("  T21.3: corrupt load -> %s\n", status_str(e.status));
        CHECK(static_cast<bool>(e));                 // must fail (no world to destroy)
    }

    std::remove(kPath);
    return astro::test::finish("test_snapshot");
}
