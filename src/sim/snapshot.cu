// src/sim/snapshot.cu -- full-state serialisation (M12a). See snapshot.h, contracts/snapshot_v1.h.
//
// A .cu (not .cpp) because it issues cudaMemcpy over every SoA array directly: the .cpp files in
// astro_sim reach the device only through the _download_* helpers, and adding one per array
// (25 cells + 20 predators) would dwarf this. The SoA lives in device memory, so save is a batch
// of D2H copies into one byte buffer and load is the H2D reverse. The array LIST is written once
// per store (collect_*_spans) and reused for both directions, so save and load can never disagree.
#include "sim/snapshot.h"

#include <cstdio>
#include <cstring>
#include <vector>

#include <cuda_runtime.h>

#include "contracts/snapshot_v1.h"
#include "core/canon_generated.h"
#include "fields/grid.cuh"
#include "sim/cell_store.cuh"
#include "sim/predation.cuh"
#include "sim/world.cuh"

namespace astro::sim {

using contract::ParamOverride;
using contract::SnapshotHeader;

namespace {

Error cu_check(cudaError_t e, const char* what) {
    return e == cudaSuccess ? ok() : fail(Status::CudaError, what);
}

// A device array as a raw (pointer, byte-count) pair -- the element type only matters for the
// byte count, so once sized, save and load treat every array identically.
struct Span { void* ptr; size_t bytes; };

template <class T>
void add_span(std::vector<Span>& s, T* p, int32_t n) {
    if (n > 0) s.push_back(Span{static_cast<void*>(p), sizeof(T) * static_cast<size_t>(n)});
}

// CellStore SoA, in contracts/cell_store_v1.h declaration order (the contract's file layout).
// The per-tick scratch (t_local..n2_local) is included: it is refilled next tick, but the
// contract lists it and restoring it makes the round trip bit-identical, hash and all.
void collect_cell_spans(const contract::CellStoreView& v, int32_t n, std::vector<Span>& s) {
    add_span(s, v.id, n);          add_span(s, v.flags, n);       add_span(s, v.death_cause, n);
    add_span(s, v.x, n);           add_span(s, v.y, n);           add_span(s, v.z, n);
    add_span(s, v.vx, n);          add_span(s, v.vy, n);          add_span(s, v.vz, n);
    add_span(s, v.energy, n);      add_span(s, v.temp_cell, n);
    add_span(s, v.emit_power, n);  add_span(s, v.dir_x, n);       add_span(s, v.dir_y, n);
    add_span(s, v.dir_z, n);
    add_span(s, v.biomass, n);     add_span(s, v.co2_held, n);    add_span(s, v.age_s, n);
    add_span(s, v.rng_state, n);   add_span(s, v.taxis_memory, n);add_span(s, v.run_timer, n);
    add_span(s, v.t_local, n);     add_span(s, v.irradiance, n);  add_span(s, v.co2_local, n);
    add_span(s, v.n2_local, n);
}

void collect_tau_spans(const TaumoebaStore& t, int32_t n, std::vector<Span>& s) {
    add_span(s, t.id, n);          add_span(s, t.flags, n);
    add_span(s, t.x, n);           add_span(s, t.y, n);           add_span(s, t.z, n);
    add_span(s, t.vx, n);          add_span(s, t.vy, n);          add_span(s, t.vz, n);
    add_span(s, t.dir_x, n);       add_span(s, t.dir_y, n);       add_span(s, t.dir_z, n);
    add_span(s, t.biomass, n);     add_span(s, t.prey_biomass, n);add_span(s, t.digest_timer, n);
    add_span(s, t.tolerance, n);   add_span(s, t.generation, n);  add_span(s, t.rng_state, n);
    add_span(s, t.density_ema, n); add_span(s, t.run_timer, n);   add_span(s, t.target, n);
}

// The slow fields. Irradiance is rebuilt from scratch each tick and never stored (the contract).
void collect_field_spans(const Fields& f, std::vector<Span>& s) {
    add_span(s, f.temperature.value, f.temperature.n * f.temperature.n);
    add_span(s, f.co2.value,         f.co2.n * f.co2.n);
    add_span(s, f.n2.value,          f.n2.n * f.n2.n);
}

// The curated ADR-035 overrides, keyed for the ParamOverride array. Save emits an entry only
// when a field differs from canon (so a canon run has override_count 0); load applies by key.
struct OverrideField { const char* key; double World::* field; double canon_value; };
const OverrideField OVERRIDE_FIELDS[] = {
    {"PETROVA_MAX_POWER",     &World::petrova_max_power,     canon::PETROVA_MAX_POWER},
    {"PETROVA_FLASH_POWER",   &World::petrova_flash_power,   canon::PETROVA_FLASH_POWER},
    {"CO2_MASS_PER_DIVISION", &World::co2_mass_per_division, canon::CO2_MASS_PER_DIVISION},
};

std::vector<ParamOverride> collect_overrides(const World& w) {
    std::vector<ParamOverride> out;
    for (const OverrideField& f : OVERRIDE_FIELDS) {
        if (w.*f.field != f.canon_value) {
            ParamOverride ov{};                                    // zero-init: the char[48]
            std::strncpy(ov.key, f.key, sizeof(ov.key) - 1);       // padding is hashed, so it
            ov.value = w.*f.field;                                 // must be deterministic
            out.push_back(ov);
        }
    }
    return out;
}

// Everything AFTER the header, in file-layout order: [overrides][cells][tau][fields]. One
// batch of D2H copies. Both snapshot_save and snapshot_state_hash build the body this way.
Error serialize_body(const World& w, std::vector<char>& body, int32_t& override_count) {
    body.clear();
    const std::vector<ParamOverride> ov = collect_overrides(w);
    override_count = static_cast<int32_t>(ov.size());
    if (!ov.empty()) {
        const char* p = reinterpret_cast<const char*>(ov.data());
        body.insert(body.end(), p, p + ov.size() * sizeof(ParamOverride));
    }
    std::vector<Span> spans;
    collect_cell_spans(w.cells.view, w.cells.count, spans);
    collect_tau_spans(w.taumoeba, w.taumoeba.count, spans);
    collect_field_spans(w.fields, spans);
    for (const Span& sp : spans) {
        const size_t off = body.size();
        body.resize(off + sp.bytes);
        ASTRO_TRY(cu_check(cudaMemcpy(body.data() + off, sp.ptr, sp.bytes, cudaMemcpyDeviceToHost),
                           "snapshot serialize"));
    }
    return ok();
}

} // namespace

Error snapshot_state_hash(const World& w, uint64_t& hash_out) {
    std::vector<char> body;
    int32_t oc = 0;
    ASTRO_TRY(serialize_body(w, body, oc));
    hash_out = contract::fnv1a64(body.data(), body.size());
    return ok();
}

Error snapshot_to_bytes(const World& w, const char* scenario_id, std::vector<char>& out) {
    std::vector<char> body;
    int32_t oc = 0;
    ASTRO_TRY(serialize_body(w, body, oc));

    SnapshotHeader h{};
    h.magic         = contract::SNAPSHOT_MAGIC;
    h.version       = contract::SNAPSHOT_CONTRACT_VERSION;
    h.seed          = w.seed;
    h.tick          = w.tick;
    h.sim_time_s    = w.sim_time_s;
    h.cell_count    = w.cells.count;      h.cell_capacity     = w.cells.capacity;
    h.taumoeba_count= w.taumoeba.count;   h.taumoeba_capacity = w.taumoeba.capacity;
    h.n_temp        = w.fields.temperature.n;
    h.n_co2         = w.fields.co2.n;
    h.n_n2          = w.fields.n2.n;
    h.chamber_w     = w.chamber.w;        h.chamber_h = w.chamber.h;   h.chamber_d = w.chamber.d;
    h.physics_rate  = w.physics_rate;     h.biology_rate = w.biology_rate;
    h.next_cell_id  = w.cells.next_id;
    h.override_count= oc;
    h.non_canon_run = w.non_canon_run ? 1u : 0u;
    if (scenario_id) std::strncpy(h.scenario_id, scenario_id, sizeof(h.scenario_id) - 1);
    std::strncpy(h.build_describe, "dev", sizeof(h.build_describe) - 1);   // M12e injects the real one
    h.state_hash    = contract::fnv1a64(body.data(), body.size());

    out.resize(sizeof(h) + body.size());
    std::memcpy(out.data(), &h, sizeof(h));
    if (!body.empty()) std::memcpy(out.data() + sizeof(h), body.data(), body.size());
    return ok();
}

Error snapshot_save(const World& w, const char* path, const char* scenario_id) {
    std::vector<char> bytes;
    ASTRO_TRY(snapshot_to_bytes(w, scenario_id, bytes));
    std::FILE* f = std::fopen(path, "wb");
    if (!f) return fail(Status::FileIoError, "snapshot: cannot open file for write");
    const bool wrote = std::fwrite(bytes.data(), 1, bytes.size(), f) == bytes.size();
    std::fclose(f);
    return wrote ? ok() : fail(Status::FileIoError, "snapshot: write failed");
}

Error snapshot_from_bytes(const char* data, size_t n, World& w) {
    if (n < sizeof(SnapshotHeader)) return fail(Status::FileIoError, "snapshot: too small");
    SnapshotHeader h{};
    std::memcpy(&h, data, sizeof(h));
    if (h.magic != contract::SNAPSHOT_MAGIC)
        return fail(Status::InvalidArgument, "snapshot: bad magic");
    if (h.version != contract::SNAPSHOT_CONTRACT_VERSION)
        return fail(Status::ContractVersionMismatch, "snapshot: version mismatch");

    const char* body_data = data + sizeof(h);
    const size_t body_len = n - sizeof(h);
    // Integrity: the body must reproduce the header's state_hash, or the buffer is corrupt.
    if (contract::fnv1a64(body_data, body_len) != h.state_hash)
        return fail(Status::InvalidArgument, "snapshot: state_hash mismatch (corrupt)");

    // Create the world sized to the header. Motion config is NOT serialised (snapshot_v1) -- it
    // is the caller's to restore, as the scenario/app set it originally; and the field values
    // below overwrite whatever ambient/co2_init world_create seeded, so those do not matter.
    WorldDesc d;
    d.chamber      = Chamber{h.chamber_w, h.chamber_h, h.chamber_d};
    d.capacity     = h.cell_capacity;
    d.tau_capacity = h.taumoeba_capacity;
    d.seed         = h.seed;
    ASTRO_TRY(world_create(w, d));

    auto bail = [&](Status s, const char* msg) -> Error { world_destroy(w); return fail(s, msg); };

    if (h.n_temp != w.fields.temperature.n || h.n_co2 != w.fields.co2.n || h.n_n2 != w.fields.n2.n)
        return bail(Status::InvalidArgument, "snapshot: field resolution mismatch");

    const char* cur = body_data;
    const char* end = body_data + body_len;

    // Overrides come first in the body. Apply each to its World field (ADR-035); the header's
    // non_canon_run is restored below so a tuned run can never look canon after a round trip.
    for (int i = 0; i < h.override_count; ++i) {
        if (cur + sizeof(ParamOverride) > end) return bail(Status::InvalidArgument, "snapshot: truncated overrides");
        ParamOverride ov{};
        std::memcpy(&ov, cur, sizeof(ov));
        cur += sizeof(ov);
        for (const OverrideField& of : OVERRIDE_FIELDS)
            if (std::strncmp(ov.key, of.key, sizeof(ov.key)) == 0) w.*of.field = ov.value;
    }

    // Counts must be set before collecting spans, since a span's size is count-derived; they
    // then match the sizes save wrote byte-for-byte.
    w.cells.count = h.cell_count;  w.cells.view.count = h.cell_count;  w.cells.next_id = h.next_cell_id;
    w.taumoeba.count = h.taumoeba_count;

    std::vector<Span> spans;
    collect_cell_spans(w.cells.view, w.cells.count, spans);
    collect_tau_spans(w.taumoeba, w.taumoeba.count, spans);
    collect_field_spans(w.fields, spans);
    for (const Span& sp : spans) {
        if (cur + sp.bytes > end) return bail(Status::InvalidArgument, "snapshot: truncated body");
        if (Error e = cu_check(cudaMemcpy(sp.ptr, cur, sp.bytes, cudaMemcpyHostToDevice),
                               "snapshot upload")) { world_destroy(w); return e; }
        cur += sp.bytes;
    }

    w.seed          = h.seed;
    w.tick          = h.tick;
    w.sim_time_s    = h.sim_time_s;
    w.physics_rate  = h.physics_rate;
    w.biology_rate  = h.biology_rate;
    w.non_canon_run = h.non_canon_run != 0;

    // The Taumoeba next_id has no header slot (snapshot_v1). IDs are monotonic and never reused,
    // so max(id)+1 recovers it -- exact unless the highest-id predator was already culled, which
    // a snapshot_v2 field would fix (see ADR-036). Cells use the authoritative header value.
    w.taumoeba.next_id = 1;
    if (w.taumoeba.count > 0) {
        std::vector<uint64_t> ids(w.taumoeba.count);
        if (Error e = cu_check(cudaMemcpy(ids.data(), w.taumoeba.id,
                                          sizeof(uint64_t) * ids.size(), cudaMemcpyDeviceToHost),
                               "snapshot tau ids")) { world_destroy(w); return e; }
        uint64_t mx = 0;
        for (uint64_t v : ids) if (v > mx) mx = v;
        w.taumoeba.next_id = mx + 1;
    }
    return ok();
}

Error snapshot_load(const char* path, World& w) {
    std::FILE* f = std::fopen(path, "rb");
    if (!f) return fail(Status::FileIoError, "snapshot: cannot open file for read");
    std::vector<char> all;
    char buf[65536];
    size_t r = 0;
    while ((r = std::fread(buf, 1, sizeof(buf), f)) > 0) all.insert(all.end(), buf, buf + r);
    std::fclose(f);
    return snapshot_from_bytes(all.data(), all.size(), w);
}

} // namespace astro::sim
