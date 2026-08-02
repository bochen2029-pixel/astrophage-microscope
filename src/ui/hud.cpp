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

void hud_draw(HudState& hud, const Stats& stats, render::Camera& cam,
              int32_t capacity, double chamber_w, double chamber_h, double chamber_d) {
    ImGui::SetNextWindowPos(ImVec2(12, 12), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(360, 0), ImGuiCond_FirstUseEver);
    ImGui::Begin("Scope");

    char timebuf[64];
    format_sim_time(stats.sim_time_s, timebuf, sizeof(timebuf));
    ImGui::Text("t = %s   (tick %llu)", timebuf, static_cast<unsigned long long>(stats.tick));
    ImGui::Text("%.1f fps   %.2f ms/frame", hud.fps, hud.frame_ms);
    ImGui::Text("cells: %d live / %d capacity", stats.n_live, capacity);

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
    if (ImGui::SliderFloat("focal plane", &focal_um, -half_d_um, half_d_um, "%.1f um"))
        cam.focal_plane = focal_um * 1e-6;
    ImGui::TextDisabled("(focus has no visual effect until M3)");

    ImGui::SeparatorText("View");
    int mode = static_cast<int>(hud.mode);
    if (ImGui::Combo("mode", &mode, kModeNames, IM_ARRAYSIZE(kModeNames)))
        hud.mode = static_cast<ViewMode>(mode);
    if (hud.mode != ViewMode::Brightfield && hud.mode != ViewMode::Analysis)
        ImGui::TextDisabled("(this mode arrives at M6/M7; drawing Analysis)");
    if (hud.mode == ViewMode::Analysis) {
        int ch = static_cast<int>(hud.channel);
        if (ImGui::Combo("channel", &ch, kChannelNames, IM_ARRAYSIZE(kChannelNames)))
            hud.channel = static_cast<AnalysisChannel>(ch);
        if (hud.channel != AnalysisChannel::Charge)
            ImGui::TextDisabled("(only Charge is populated at M1)");
    }

    ImGui::SeparatorText("Chamber");
    ImGui::Text("%.2f x %.2f mm, %.0f um deep", chamber_w * 1e3, chamber_h * 1e3, chamber_d * 1e6);
    ImGui::Text("stage at %.0f, %.0f um", cam.center_x * 1e6, cam.center_y * 1e6);
    if (ImGui::Button("centre stage")) { cam.center_x = 0.0; cam.center_y = 0.0; }

    ImGui::SeparatorText("Population");
    ImGui::SliderInt("count", &hud.respawn_count, 1000, capacity);
    ImGui::SliderFloat("charge", &hud.respawn_charge, 0.0f, 1.0f, "%.4f");
    // P1's neutral-buoyancy point is the most useful number on this panel once
    // motion exists at M2, so surface it now rather than burying it in a doc.
    ImGui::TextDisabled("neutral buoyancy at %.3f%% charge",
                        canon::CHARGE_NEUTRAL_BUOYANCY * 100.0);
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
