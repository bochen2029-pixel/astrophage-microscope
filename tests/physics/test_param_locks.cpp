// tests/physics/test_param_locks.cpp -- M11c gate: the runtime-parameter overlay and the
// canon-lock guarantee (src/core/params.h, ADR-034). Pure host logic, no GPU.
//
// The guarantee: every CANON parameter is locked by default, breaking a lock flags the run
// non-canon (stickily), and the overlay starts as an exact copy of the generated canon. A
// run that quietly changed a canon number and still looked canon is the worst failure the
// inspector can have (src/ui/MODULE.md), so this is the test that forbids it.
#include "core/canon_generated.h"
#include "core/params.h"
#include "test_util.h"

using namespace astro;

int main() {
    ParamSet p;
    param_set_init(p);

    // The overlay starts as an exact copy of generated canon, no lock broken.
    CHECK(!p.non_canon_run);
    for (int i = 0; i < canon::PARAM_COUNT; ++i)
        CHECK(p.value[i] == canon::PARAM_TABLE[i].value);

    // CANON parameters are locked by default; every other provenance is unlocked.
    int canon_count = 0;
    for (int i = 0; i < canon::PARAM_COUNT; ++i) {
        const bool is_canon = canon::PARAM_TABLE[i].prov == canon::Provenance::Canon;
        CHECK(p.locked[i] == is_canon);
        if (is_canon) ++canon_count;
    }
    CHECK(canon_count > 0);   // there ARE canon values to protect

    // A locked (CANON) value cannot be written until it is unlocked.
    const int ci = param_index("CELL_TEMP_SETPOINT");
    CHECK(ci >= 0);
    CHECK(canon::PARAM_TABLE[ci].prov == canon::Provenance::Canon);
    CHECK(!param_set(p, ci, 400.0));                          // locked -> rejected
    CHECK(p.value[ci] == canon::PARAM_TABLE[ci].value);
    CHECK(!p.non_canon_run);

    // Breaking a CANON lock flags the run non-canon -- THE guarantee.
    param_unlock(p, ci);
    CHECK(!p.locked[ci]);
    CHECK(p.non_canon_run);
    CHECK(param_set(p, ci, 400.0));                           // now writable
    CHECK(p.value[ci] == 400.0);

    // The flag never clears for the run, even if the value is restored to canon.
    CHECK(param_set(p, ci, canon::PARAM_TABLE[ci].value));
    CHECK(p.non_canon_run);

    // Unlocking a non-canon (INVENTED) parameter is free: it does NOT flag the run.
    ParamSet q;
    param_set_init(q);
    const int ii = param_index("PETROVA_MAX_POWER");
    CHECK(ii >= 0);
    CHECK(canon::PARAM_TABLE[ii].prov == canon::Provenance::Invented);
    CHECK(!q.locked[ii]);                                     // already unlocked
    CHECK(param_set(q, ii, 0.1));                             // freely tunable
    CHECK(!q.non_canon_run);                                  // canon untouched
    param_unlock(q, ii);                                     // unlocking it is still free
    CHECK(!q.non_canon_run);

    // Unknown keys are rejected, not silently matched.
    CHECK(param_index("NOPE_NOT_A_PARAM") == -1);
    CHECK(param_index(nullptr) == -1);

    return astro::test::finish("test_param_locks");
}
