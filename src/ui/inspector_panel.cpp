// src/ui/inspector_panel.cpp -- the cell inspector (M11f). See inspector_panel.h.
#include "ui/inspector_panel.h"

#include <cstdio>

#include "imgui.h"

namespace astro::ui {

void inspector_panel_draw(const CellReadout& r) {
    ImGui::SetNextWindowPos(ImVec2(840, 12), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(320, 0), ImGuiCond_FirstUseEver);
    ImGui::Begin("Cell inspector");

    if (!r.valid) {
        ImGui::TextWrapped("Click a cell in the chamber to inspect it.");
        ImGui::TextDisabled("(or launch with --inspect N to pre-select slot N)");
        ImGui::End();
        return;
    }

    ImGui::Text("cell #%llu   slot %d", r.id, r.slot);

    // State line: awake/dormant and alive/dead are orthogonal (the glossary), so show both.
    const ImVec4 warm(1.00f, 0.60f, 0.30f, 1.0f), cool(0.55f, 0.70f, 0.85f, 1.0f);
    ImGui::TextColored(r.awake ? warm : cool, "%s", r.awake ? "AWAKE" : "dormant");
    ImGui::SameLine();
    if (r.corpse) ImGui::TextColored(ImVec4(0.75f, 0.45f, 0.45f, 1.0f), " -- CORPSE (%s)", r.death_cause);
    else          ImGui::TextColored(ImVec4(0.55f, 0.85f, 0.55f, 1.0f), " -- alive");

    ImGui::SeparatorText("Charge  (P1: the 3% line)");
    ImGui::Text("charge %.4f %%   (%.3g J)", r.charge_pct, r.energy_j);
    // The buoyancy line -- the whole point of the inspector. Density + ratio + verdict,
    // coloured the same way the HUD colours its charge readout.
    ImGui::TextColored(r.sinking ? warm : cool,
                       "%s -- %.0f kg/m3, %.2fx water",
                       r.sinking ? "SINKING" : "RISING", r.density, r.density_ratio);
    ImGui::TextDisabled("neutral buoyancy at %.4f %%", r.neutral_pct);

    ImGui::SeparatorText("Motion");
    // Vertical drift is the measured tell: it should track the buoyancy verdict above.
    ImGui::Text("vertical drift %+.1f um/s  (%s)", r.vy_um_s, r.vy_um_s >= 0.0 ? "up" : "down");
    ImGui::Text("speed %.1f um/s", r.speed_um_s);
    ImGui::Text("position (%.1f, %.1f, %.1f) um", r.x_um, r.y_um, r.z_um);

    ImGui::SeparatorText("Biology");
    ImGui::Text("temperature %.2f C", r.temp_c);
    ImGui::Text("biomass %.4f ng", r.biomass_ng);
    ImGui::Text("age %.3g s", r.age_s);

    ImGui::End();
}

} // namespace astro::ui
