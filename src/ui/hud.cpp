// src/ui/hud.cpp
#include "ui/hud.h"

#include <cstdio>

#include "imgui.h"

#include "core/canon_generated.h"
#include "core/units.h"
#include "ui/scale_bar.h"

namespace astro::ui {

using contract::AnalysisChannel;
using contract::Stats;
using contract::ViewMode;

namespace {

const char* kModeNames[] = {"Brightfield", "Darkfield", "Petrovascope", "Thermal IR", "Analysis"};
const char* kChannelNames[] = {"Charge", "Temperature", "Age", "Mass", "Awake", "Velocity"};

// Simulated time must always read in real units, never as a bare tick count
// (docs/RENDERING.md Sec 6). At Generational rates a run spans months.
void format_sim_time(double s, char* out, size_t n) {
    if (s < 1.0)          std::snprintf(out, n, "%.1f ms", s * 1e3);
    else if (s < 120.0)   std::snprintf(out, n, "%.2f s", s);
    else if (s < 7200.0)  std::snprintf(out, n, "%.2f min", s / 60.0);
    else if (s < 172800.0)std::snprintf(out, n, "%.2f h", s / 3600.0);
    else                  std::snprintf(out, n, "%.2f days", s / 86400.0);
}

} // namespace

// A depth-of-field gauge, because the numbers alone do not convey how thin the
// sharp layer is. At 40x it is 1.53 um inside a 60 um chamber -- the in-focus
// band is under a fortieth of the bar, and seeing that is the point.
void draw_focus_gauge(const render::Camera& cam, double chamber_d) {
    const auto& obj = canon::OBJECTIVES[cam.objective];
    const float w = ImGui::GetContentRegionAvail().x;
    const float h = 26.0f;
    const ImVec2 p0 = ImGui::GetCursorScreenPos();
    const ImVec2 p1 = ImVec2(p0.x + w, p0.y + h);
    ImDrawList* dl = ImGui::GetWindowDrawList();

    dl->AddRectFilled(p0, p1, IM_COL32(24, 26, 32, 255), 3.0f);
    dl->AddRect(p0, p1, IM_COL32(80, 88, 104, 255), 3.0f);

    // Chamber depth maps across the bar; the coverslip and slide are the ends.
    auto z_to_x = [&](double z_m) {
        const double t = (z_m + 0.5 * chamber_d) / chamber_d;
        return p0.x + static_cast<float>(astro::clamp(t, 0.0, 1.0)) * w;
    };

    const float x_focus = z_to_x(cam.focal_plane);
    const float x_lo = z_to_x(cam.focal_plane - 0.5 * obj.depth_of_field_m);
    const float x_hi = z_to_x(cam.focal_plane + 0.5 * obj.depth_of_field_m);

    // The sharp band. Enforce a minimum drawn width of 2 px, or at 40x it is
    // literally invisible -- which would understate the point rather than make it.
    const float band_lo = x_lo;
    const float band_hi = (x_hi - x_lo < 2.0f) ? x_lo + 2.0f : x_hi;
    dl->AddRectFilled(ImVec2(band_lo, p0.y + 2), ImVec2(band_hi, p1.y - 2),
                      IM_COL32(120, 220, 160, 200));
    dl->AddLine(ImVec2(x_focus, p0.y), ImVec2(x_focus, p1.y), IM_COL32(255, 255, 255, 220), 1.5f);

    char label[96];
    std::snprintf(label, sizeof(label), "DOF %.2f um of %.0f um  (%.1f%% sharp)",
                  obj.depth_of_field_m * 1e6, chamber_d * 1e6,
                  100.0 * obj.depth_of_field_m / chamber_d);
    const ImVec2 ts = ImGui::CalcTextSize(label);
    dl->AddText(ImVec2(p0.x + (w - ts.x) * 0.5f, p0.y + (h - ts.y) * 0.5f),
                IM_COL32(210, 215, 225, 255), label);
    ImGui::Dummy(ImVec2(w, h + 2.0f));
}

void hud_draw(HudState& hud, const Stats& stats, render::Camera& cam,
              int32_t capacity, double chamber_w, double chamber_h, double chamber_d) {
    ImGui::SetNextWindowPos(ImVec2(12, 12), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(360, 0), ImGuiCond_FirstUseEver);
    ImGui::Begin("Scope");

    char timebuf[64];
    format_sim_time(stats.sim_time_s, timebuf, sizeof(timebuf));
    ImGui::Text("t = %s   (tick %llu)", timebuf, static_cast<unsigned long long>(stats.tick));
    ImGui::Text("%.1f fps   %.2f ms/frame", hud.fps, hud.frame_ms);
    ImGui::Text("cells: %d live / %d dead / %d capacity", stats.n_live, stats.n_dead, capacity);
    // Both clock multipliers, always visible: the user must never lose track of
    // which clock they are on (ADR-011).
    ImGui::Text("clock: physics %.3gx   biology %.0fx", stats.physics_rate, stats.biology_rate);
    // The energy ledger is a permanent, honest readout -- the default population
    // fully charged is kiloton-scale energy inside a droplet (RENDERING.md Sec 6).
    {
        const double gj = stats.total_energy_j / 1.0e9;
        const double kt_tnt = stats.total_energy_j / canon::TNT_JOULE / 1.0e9;   // g -> kt
        const bool hot = stats.total_energy_j > 1.0e9;
        ImGui::TextColored(hot ? ImVec4(1.0f, 0.6f, 0.3f, 1.0f) : ImVec4(0.70f, 0.75f, 0.82f, 1.0f),
                           "energy: %.3g GJ  (%.3g kt TNT)%s", gj, kt_tnt, hot ? "  [!]" : "");
    }
    // The worst failure this UI can have is a run that quietly changed a canon number and
    // still looks canon (src/ui/MODULE.md). Once a lock is broken it says so, permanently.
    if (stats.non_canon_run)
        ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.30f, 1.0f), "NON-CANON RUN  [!]");

    ImGui::SeparatorText("Objective");
    const auto& obj = canon::OBJECTIVES[cam.objective];
    for (int i = 0; i < canon::OBJECTIVE_COUNT; ++i) {
        if (i) ImGui::SameLine();
        char label[32];
        std::snprintf(label, sizeof(label), "%.0fx", canon::OBJECTIVES[i].magnification);
        if (ImGui::RadioButton(label, cam.objective == i)) cam.objective = i;
    }
    ImGui::Text("NA %.2f   field %.0f um   DOF %.2f um",
                obj.na, obj.fov_m * 1e6, obj.depth_of_field_m * 1e6);
    ImGui::Text("resolution %.0f nm   cell spans %.0f resel",
                obj.resolution_m * 1e9, canon::CELL_DIAMETER / obj.resolution_m);

    ImGui::SliderFloat("zoom", &cam.zoom, 0.05f, 200.0f, "%.2fx", ImGuiSliderFlags_Logarithmic);
    float focal_um = static_cast<float>(cam.focal_plane * 1e6);
    const float half_d_um = static_cast<float>(chamber_d * 0.5e6);
    if (ImGui::SliderFloat("focal plane", &focal_um, -half_d_um, half_d_um, "%.2f um"))
        cam.focal_plane = focal_um * 1e-6;
    draw_focus_gauge(cam, chamber_d);

    ImGui::SeparatorText("View");
    int mode = static_cast<int>(hud.mode);
    if (ImGui::Combo("mode", &mode, kModeNames, IM_ARRAYSIZE(kModeNames)))
        hud.mode = static_cast<ViewMode>(mode);
    // Astrophage is black in visible light and emits where no eye can see, so the
    // IR modes are dark until something makes a cell glow -- say so, or an empty
    // Petrovascope reads as a broken screen rather than as "nothing is emitting".
    if (hud.mode == ViewMode::Petrovascope)
        ImGui::TextDisabled("(only emitting cells glow; ignite and seek light to see it)");
    else if (hud.mode == ViewMode::ThermalIR)
        ImGui::TextDisabled("(awake cells glow warm; dormant cells sit at ambient and stay dark)");
    if (hud.mode == ViewMode::Analysis) {
        int ch = static_cast<int>(hud.channel);
        if (ImGui::Combo("channel", &ch, kChannelNames, IM_ARRAYSIZE(kChannelNames)))
            hud.channel = static_cast<AnalysisChannel>(ch);
        if (hud.channel != AnalysisChannel::Charge)
            ImGui::TextDisabled("(only Charge is populated at M1)");
    }

    ImGui::SeparatorText("Clock  (ADR-011: two independent rates)");
    static const char* kClockNames[] = {"Realtime", "Motion", "Metabolic", "Generational", "Custom"};
    if (ImGui::Combo("preset##clock", &hud.clock_preset, kClockNames, IM_ARRAYSIZE(kClockNames)))
        hud.clock_change_requested = true;
    constexpr int kCustomPreset = 4;
    if (hud.clock_preset == kCustomPreset) {
        if (ImGui::SliderFloat("physics##clock", &hud.clock_physics,
                               static_cast<float>(canon::CLOCK_PHYSICS_MIN),
                               static_cast<float>(canon::CLOCK_PHYSICS_MAX),
                               "%.2fx", ImGuiSliderFlags_Logarithmic))
            hud.clock_change_requested = true;
        if (ImGui::SliderFloat("biology##clock", &hud.clock_biology,
                               static_cast<float>(canon::CLOCK_BIOLOGY_MIN),
                               static_cast<float>(canon::CLOCK_BIOLOGY_MAX),
                               "%.0fx", ImGuiSliderFlags_Logarithmic))
            hud.clock_change_requested = true;
    }
    // Q19 (ADR-027): biology_rate scales growth but NOT CO2 diffusion, so at a fast
    // biology clock the medium cannot resupply and dense growth goes transport-
    // limited. Stated, not hidden -- the honest lever to relieve it is physics_rate.
    if (stats.biology_rate > 1.0)
        ImGui::TextColored(ImVec4(0.72f, 0.70f, 0.48f, 1.0f),
                           "biology outpaces CO2 transport: dense growth is diffusion-limited");

    ImGui::SeparatorText("Chamber");
    ImGui::Text("%.2f x %.2f mm, %.0f um deep", chamber_w * 1e3, chamber_h * 1e3, chamber_d * 1e6);
    ImGui::Text("stage at %.0f, %.0f um", cam.center_x * 1e6, cam.center_y * 1e6);
    if (ImGui::Button("centre stage")) { cam.center_x = 0.0; cam.center_y = 0.0; }

    ImGui::SeparatorText("Charge  (P1: the 3% line)");
    // The neutral-buoyancy figure is the most useful number on this panel:
    // below it cells rise, above it they sink, and the transition is sharp.
    const float neutral = static_cast<float>(canon::CHARGE_NEUTRAL_BUOYANCY);
    if (ImGui::SliderFloat("charge##live", &hud.live_charge, 0.0f, 0.10f, "%.5f"))
        hud.set_charge_requested = true;
    const bool sinking = hud.live_charge > neutral;
    ImGui::TextColored(sinking ? ImVec4(1.0f, 0.55f, 0.35f, 1.0f)
                               : ImVec4(0.45f, 0.75f, 1.0f, 1.0f),
                       "%s   neutral at %.4f%%", sinking ? "SINKING" : "RISING",
                       neutral * 100.0);
    // Density is the readout that makes the mechanism legible, not just the
    // outcome: an empty cell is 25x lighter than water, a full one 32x denser.
    {
        const double mass = canon::CELL_MASS_DRY +
                            hud.live_charge * canon::CELL_ENERGY_MAX /
                            (canon::C_LIGHT * canon::C_LIGHT);
        const double density = mass / canon::CELL_VOLUME;
        ImGui::Text("%.0f kg/m3  (%.2fx water)   mass %.3f ng",
                    density, density / canon::WATER_DENSITY, mass * 1e12);
    }
    ImGui::SameLine();
    if (ImGui::SmallButton("neutral")) {
        hud.live_charge = neutral;
        hud.set_charge_requested = true;
    }

    ImGui::SeparatorText("Population");
    ImGui::Checkbox("paused", &hud.paused);
    ImGui::SliderInt("count", &hud.respawn_count, 1000, capacity);
    ImGui::SliderFloat("spawn charge", &hud.respawn_charge, 0.0f, 1.0f, "%.4f");
    if (ImGui::Button("respawn")) hud.respawn_requested = true;

    ImGui::End();
}

void draw_scale_bar(const render::Camera& cam, int fb_w, int fb_h) {
    const double mpp = cam.metres_per_pixel(fb_w, fb_h);
    if (mpp <= 0.0) return;

    const ScaleBarChoice choice = choose_scale_bar(mpp, fb_w * 0.25);
    const double chosen_um = choice.length_um;

    // ImGui coordinates are in logical points; the framebuffer may be scaled.
    const ImGuiIO& io = ImGui::GetIO();
    const float sx = (fb_w > 0) ? io.DisplaySize.x / static_cast<float>(fb_w) : 1.0f;
    const float bar_px = static_cast<float>(choice.length_px) * sx;

    const float pad = 24.0f;
    const float x1 = io.DisplaySize.x - pad;
    const float x0 = x1 - bar_px;
    const float y  = io.DisplaySize.y - pad;

    ImDrawList* dl = ImGui::GetForegroundDrawList();
    const ImU32 shadow = IM_COL32(0, 0, 0, 160);
    const ImU32 ink    = IM_COL32(255, 255, 255, 230);
    for (int pass = 0; pass < 2; ++pass) {
        const float o = pass == 0 ? 1.5f : 0.0f;      // drop shadow, so the bar
        const ImU32 col = pass == 0 ? shadow : ink;   // reads on any background
        dl->AddLine(ImVec2(x0 + o, y + o), ImVec2(x1 + o, y + o), col, 3.0f);
        dl->AddLine(ImVec2(x0 + o, y - 6 + o), ImVec2(x0 + o, y + 6 + o), col, 3.0f);
        dl->AddLine(ImVec2(x1 + o, y - 6 + o), ImVec2(x1 + o, y + 6 + o), col, 3.0f);
    }

    char label[32];
    if (chosen_um >= 1000.0)     std::snprintf(label, sizeof(label), "%.0f mm", chosen_um / 1000.0);
    else if (chosen_um >= 1.0)   std::snprintf(label, sizeof(label), "%.0f um", chosen_um);
    else                         std::snprintf(label, sizeof(label), "%.0f nm", chosen_um * 1000.0);
    const ImVec2 ts = ImGui::CalcTextSize(label);
    const ImVec2 tp(x0 + (bar_px - ts.x) * 0.5f, y - 8 - ts.y);
    dl->AddText(ImVec2(tp.x + 1.5f, tp.y + 1.5f), shadow, label);
    dl->AddText(tp, ink, label);
}

} // namespace astro::ui
