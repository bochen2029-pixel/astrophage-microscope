// src/sim/scenario.cpp -- scenario JSON -> Scenario -> World. docs/SCENARIOS.md (M11a).
#include "sim/scenario.h"

#include <cstdint>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>

#include "core/canon_generated.h"
#include "fields/grid.cuh"
#include "sim/json.h"

namespace astro::sim {

using namespace astro::contract;

namespace {

// Copy a std::string into a fixed char buffer, always null-terminated (truncates).
void set_str(char* dst, size_t cap, const std::string& src) {
    const size_t n = src.size() < cap - 1 ? src.size() : cap - 1;
    if (n) std::memcpy(dst, src.data(), n);
    dst[n] = '\0';
}

// --- string -> enum maps. Unknown values fall back to the documented default -------
uint8_t boundary_of(const std::string& s) {   // 0 reflecting, 1 periodic, 2 absorbing
    if (s == "periodic") return 1;
    if (s == "absorbing") return 2;
    return 0;
}
BoundaryCondition thermal_bc_of(const std::string& s) {
    if (s == "dirichlet") return BoundaryCondition::Dirichlet;
    if (s == "neumann")   return BoundaryCondition::Neumann;
    return BoundaryCondition::Robin;
}
DensityModel density_of(const std::string& s) {
    return s == "water-density" ? DensityModel::WaterDensity : DensityModel::CanonMass;
}
StoreDisposition disposition_of(const std::string& s) {
    if (s == "flash")  return StoreDisposition::Flash;
    if (s == "retain") return StoreDisposition::Retain;
    return StoreDisposition::Void;
}
ClockPreset clock_of(const std::string& s) {
    if (s == "motion")       return ClockPreset::Motion;
    if (s == "metabolic")    return ClockPreset::Metabolic;
    if (s == "generational") return ClockPreset::Generational;
    if (s == "custom")       return ClockPreset::Custom;
    return ClockPreset::Realtime;
}
// Placement and Distribution exist in BOTH astro::sim and astro::contract; the
// Scenario struct uses the contract ones, so these are explicitly contract-qualified.
contract::Placement placement_of(const std::string& s) {
    if (s == "gaussian") return contract::Placement::Gaussian;
    if (s == "grid")     return contract::Placement::Grid;
    if (s == "disc")     return contract::Placement::Disc;
    return contract::Placement::Uniform;
}
contract::Distribution dist_of(const std::string& s) {
    if (s == "uniform") return contract::Distribution::Uniform;
    if (s == "normal")  return contract::Distribution::Normal;
    return contract::Distribution::Constant;
}
OrganismKind kind_of(const std::string& s) {
    return s == "taumoeba" ? OrganismKind::Taumoeba : OrganismKind::Astrophage;
}
ViewMode viewmode_of(const std::string& s) {
    if (s == "darkfield")    return ViewMode::Darkfield;
    if (s == "petrovascope") return ViewMode::Petrovascope;
    if (s == "thermal")      return ViewMode::ThermalIR;
    if (s == "analysis")     return ViewMode::Analysis;
    return ViewMode::Brightfield;
}
int32_t objective_of(const std::string& s) {
    if (s == "SURVEY") return 0;
    if (s == "DETAIL") return 2;
    return 1;   // WORKING
}
uint32_t tool_bit_of(const std::string& s) {
    if (s == "heat")          return static_cast<uint32_t>(ToolBit::Heat);
    if (s == "chill")         return static_cast<uint32_t>(ToolBit::Chill);
    if (s == "illuminate")    return static_cast<uint32_t>(ToolBit::Illuminate);
    if (s == "inject_co2")    return static_cast<uint32_t>(ToolBit::InjectCO2);
    if (s == "inject_n2")     return static_cast<uint32_t>(ToolBit::InjectN2);
    if (s == "seed_cells")    return static_cast<uint32_t>(ToolBit::SeedCells);
    if (s == "seed_taumoeba") return static_cast<uint32_t>(ToolBit::SeedTaumoeba);
    if (s == "kill")          return static_cast<uint32_t>(ToolBit::Kill);
    if (s == "charge_beam")   return static_cast<uint32_t>(ToolBit::ChargeBeam);
    return 0;
}
CompareOp op_of(const std::string& s) {
    if (s == "!=") return CompareOp::Ne;
    if (s == "<")  return CompareOp::Lt;
    if (s == "<=") return CompareOp::Le;
    if (s == ">")  return CompareOp::Gt;
    if (s == ">=") return CompareOp::Ge;
    if (s == "~=") return CompareOp::Approx;
    return CompareOp::Eq;
}
Metric metric_of(const std::string& s, bool& ok) {
    ok = true;
    if (s == "awake_fraction")            return Metric::AwakeFraction;
    if (s == "medium_temp_mean")          return Metric::MediumTempMean;
    if (s == "medium_temp_max")           return Metric::MediumTempMax;
    if (s == "boil_event_count")          return Metric::BoilEventCount;
    if (s == "population_live")           return Metric::PopulationLive;
    if (s == "population_dead")           return Metric::PopulationDead;
    if (s == "mean_charge")               return Metric::MeanCharge;
    if (s == "total_energy_j")            return Metric::TotalEnergyJ;
    if (s == "mean_tau_tolerance")        return Metric::MeanTauTolerance;
    if (s == "max_tau_tolerance")         return Metric::MaxTauTolerance;
    if (s == "charge_depth_correlation")  return Metric::ChargeDepthCorrelation;
    if (s == "charge_height_correlation") return Metric::ChargeHeightCorrelation;
    if (s == "rise_velocity_empty")       return Metric::RiseVelocityEmpty;
    if (s == "fall_velocity_full")        return Metric::FallVelocityFull;
    if (s == "doubling_time_s")           return Metric::DoublingTimeS;
    if (s == "impulse_per_cycle")         return Metric::ImpulsePerCycle;
    ok = false;
    return Metric::Count;
}

}  // namespace

Error scenario_parse(const std::string& text, Scenario& out) {
    out = Scenario{};
    std::string err;
    const json::Value root = json::parse(text, err);
    if (!root.is_object()) return fail(Status::InvalidArgument, "scenario: not a JSON object");

    out.schema = static_cast<int32_t>(root.num("schema", 1));
    set_str(out.id, sizeof(out.id), root.text("id", ""));
    set_str(out.title, sizeof(out.title), root.text("title", ""));
    set_str(out.blurb, sizeof(out.blurb), root.text("blurb", ""));
    out.seed = static_cast<uint64_t>(root.num("seed", 20260802.0));

    out.chamber_w = canon::CHAMBER_W;
    out.chamber_h = canon::CHAMBER_H;
    out.chamber_d = canon::CHAMBER_D;
    if (const json::Value* ch = root.find("chamber")) {
        out.chamber_w = ch->num("w", canon::CHAMBER_W);
        out.chamber_h = ch->num("h", canon::CHAMBER_H);
        out.chamber_d = ch->num("d", canon::CHAMBER_D);
        out.boundary_x = boundary_of(ch->text("boundary_x", "reflecting"));
        out.boundary_y = boundary_of(ch->text("boundary_y", "reflecting"));
    }

    out.temp_init = canon::AMBIENT_TEMP_DEFAULT;
    out.ambient_temp = canon::AMBIENT_TEMP_DEFAULT;
    out.thermal_bc = BoundaryCondition::Robin;
    out.density_model = DensityModel::CanonMass;
    out.store_disposition = StoreDisposition::Void;
    if (const json::Value* md = root.find("medium")) {
        out.temp_init = md->num("temp_init", canon::AMBIENT_TEMP_DEFAULT);
        out.co2_init = md->num("co2_init", 0.0);
        out.n2_init = md->num("n2_init", 0.0);
        out.ambient_temp = md->num("ambient_temp", canon::AMBIENT_TEMP_DEFAULT);
        out.thermal_bc = thermal_bc_of(md->text("thermal_bc", "robin"));
        out.density_model = density_of(md->text("density_model", "canon-mass"));
        out.store_disposition = disposition_of(md->text("store_disposition", "void"));
        out.gravity_axis = md->text("gravity_axis", "y") == "z" ? 1 : 0;
    }

    if (const json::Value* lt = root.find("light")) {
        out.ambient_irradiance = static_cast<float>(lt->num("ambient", 0.0));
        if (const json::Value* srcs = lt->find("sources")) {
            int n = 0;
            for (const auto& src : srcs->arr) {
                if (n >= MAX_LIGHT_SOURCES) break;
                out.lights[n].dir_x = static_cast<float>(src.num("dir_x", 1.0));
                out.lights[n].dir_y = static_cast<float>(src.num("dir_y", 0.0));
                out.lights[n].irradiance = static_cast<float>(src.num("irradiance", 0.0));
                out.lights[n].wavelength = static_cast<float>(src.num("wavelength", 0.0));
                out.lights[n].enabled = 1;
                ++n;
            }
        }
    }

    if (const json::Value* pops = root.find("populations")) {
        int n = 0;
        for (const auto& p : pops->arr) {
            if (n >= MAX_POPULATIONS) break;
            PopulationSpec& ps = out.populations[n];
            ps.kind = kind_of(p.text("kind", "astrophage"));
            ps.count = static_cast<int32_t>(p.num("count", 0));
            ps.placement = placement_of(p.text("placement", "uniform"));
            ps.place_x = p.num("place_x", 0.0);
            ps.place_y = p.num("place_y", 0.0);
            ps.place_radius = p.num("place_radius", 0.0);
            ps.charge_dist = contract::Distribution::Constant;
            ps.charge_a = 0.0;
            ps.charge_b = 0.0;
            if (const json::Value* cg = p.find("charge")) {
                ps.charge_dist = dist_of(cg->text("dist", "constant"));
                ps.charge_a = cg->num("value", cg->num("a", 0.0));
                ps.charge_b = cg->num("b", 0.0);
            }
            ps.awake = p.flag("awake", false) ? 1 : 0;
            ++n;
        }
        out.population_count = n;
    }

    out.clock = ClockPreset::Realtime;
    out.physics_rate = 1.0;
    out.biology_rate = 1.0;
    if (const json::Value* ck = root.find("clock")) {
        out.clock = clock_of(ck->text("preset", "realtime"));
        out.physics_rate = ck->num("physics_rate", 1.0);
        out.biology_rate = ck->num("biology_rate", 1.0);
    }

    // Scope is render-only; parsed so the app can consume it, ignored by headless.
    out.scope.objective = 1;
    out.scope.zoom = 1.0f;
    out.scope.mode = ViewMode::Brightfield;
    out.scope.overlays = OVERLAY_SCALE_BAR;
    if (const json::Value* sc = root.find("scope")) {
        out.scope.mode = viewmode_of(sc->text("mode", "brightfield"));
        out.scope.objective = objective_of(sc->text("objective", "WORKING"));
        out.scope.focal_plane = sc->num("focal_plane", 0.0);
        out.scope.zoom = static_cast<float>(sc->num("zoom", 1.0));
        if (const json::Value* c = sc->find("center")) {
            if (c->arr.size() >= 2) {
                out.scope.center_x = c->arr[0].num_or(0.0);
                out.scope.center_y = c->arr[1].num_or(0.0);
            }
        }
    }

    if (const json::Value* tl = root.find("tools")) {
        for (const auto& t : tl->arr)
            if (t.is_string()) out.tools |= tool_bit_of(t.str);
    }

    // Overrides parsed, not applied (a runtime-param system is M11c).
    if (const json::Value* po = root.find("param_overrides")) {
        int n = 0;
        for (const auto& kv : po->obj) {
            if (n >= MAX_OVERRIDES) break;
            set_str(out.param_overrides[n].key, sizeof(out.param_overrides[n].key), kv.first);
            out.param_overrides[n].value = kv.second.num_or(0.0);
            ++n;
        }
        out.override_count = n;
    }

    if (const json::Value* ob = root.find("objective")) {
        set_str(out.objective_text, sizeof(out.objective_text), ob->text("text", ""));
        if (const json::Value* ac = ob->find("accept")) {
            int n = 0;
            for (const auto& c : ac->arr) {
                if (n >= MAX_ACCEPT_CHECKS) break;
                bool ok = false;
                const Metric m = metric_of(c.text("metric", ""), ok);
                if (!ok) return fail(Status::InvalidArgument, "scenario: unknown accept metric");
                AcceptCheck& chk = out.accept[n];
                chk.metric = m;
                chk.op = op_of(c.text("op", "=="));
                chk.value = c.num("value", 0.0);
                chk.tol = c.num("tol", 0.0);
                chk.after_s = c.num("after_s", 0.0);
                chk.tol_absolute = c.flag("tol_absolute", false) ? 1 : 0;
                ++n;
            }
            out.accept_count = n;
        }
    }

    return ok();
}

Error scenario_load(const std::string& path, Scenario& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return fail(Status::InvalidArgument, "scenario: cannot open file");
    const std::string text((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    return scenario_parse(text, out);
}

Error scenario_instantiate(const Scenario& s, World& w) {
    int64_t total_cells = 0, total_tau = 0;
    for (int i = 0; i < s.population_count; ++i) {
        if (s.populations[i].kind == OrganismKind::Taumoeba) total_tau += s.populations[i].count;
        else total_cells += s.populations[i].count;
    }

    WorldDesc d;
    d.chamber = Chamber{s.chamber_w, s.chamber_h, s.chamber_d};
    // Headroom for growth (bloom divides), clamped to the store's hard cap.
    int64_t cap = total_cells * 2 + 4096;
    if (cap < canon::DEFAULT_CELLS) cap = canon::DEFAULT_CELLS;
    if (cap > canon::MAX_CELLS) cap = canon::MAX_CELLS;
    d.capacity = static_cast<int32_t>(cap);
    int64_t tcap = total_tau * 4 + canon::DEFAULT_TAUMOEBA;
    if (tcap > canon::MAX_TAUMOEBA) tcap = canon::MAX_TAUMOEBA;
    d.tau_capacity = static_cast<int32_t>(tcap);
    d.seed = s.seed;
    d.co2_init = s.co2_init;
    d.motion.boundary_x = static_cast<Boundary>(s.boundary_x);
    d.motion.boundary_y = static_cast<Boundary>(s.boundary_y);
    d.motion.gravity_axis = static_cast<GravityAxis>(s.gravity_axis);
    d.motion.ambient_temp = s.ambient_temp;
    d.motion.store_disposition = s.store_disposition;
    ASTRO_TRY(world_create(w, d));

    // Everything past world_create; destroy the World on any failure so the caller
    // never holds a half-built one (the header's contract). The temperature grid is
    // created at ambient_temp and N2 at zero, so only fill them when they differ.
    Error e = ok();
    if (!e && s.temp_init != s.ambient_temp)
        e = fields::grid_fill(w.fields.temperature, static_cast<float>(s.temp_init));
    if (!e && s.n2_init != 0.0)
        e = fields::grid_fill(w.fields.n2, static_cast<float>(s.n2_init));

    // One distinct seed per population so two identical specs do not spawn on top of
    // each other; the base seed still drives the first population, matching a plain run.
    uint64_t spawn_seed = s.seed;
    for (int i = 0; !e && i < s.population_count; ++i) {
        const PopulationSpec& p = s.populations[i];
        if (p.count <= 0) continue;
        if (p.kind == OrganismKind::Taumoeba) {
            e = taumoeba_spawn(w.taumoeba, p.count, w.chamber, spawn_seed);
        } else {
            SpawnParams sp;
            sp.count = p.count;
            sp.placement = static_cast<Placement>(static_cast<uint8_t>(p.placement));
            sp.place_x = p.place_x;
            sp.place_y = p.place_y;
            sp.place_radius = p.place_radius;
            sp.charge_dist = static_cast<Distribution>(static_cast<uint8_t>(p.charge_dist));
            sp.charge_a = p.charge_a;
            sp.charge_b = p.charge_b;
            sp.awake = p.awake != 0;
            e = cell_store_spawn(w.cells, sp, w.chamber, spawn_seed);
        }
        ++spawn_seed;
    }
    if (e) { world_destroy(w); return e; }

    w.ambient_irradiance = s.ambient_irradiance;
    if (s.lights[0].enabled) w.light = s.lights[0];   // one source at M11a (MAX is 8)
    world_set_clock(w, s.clock, s.physics_rate, s.biology_rate);
    return ok();
}

} // namespace astro::sim
