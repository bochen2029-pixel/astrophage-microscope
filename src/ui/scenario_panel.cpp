// src/ui/scenario_panel.cpp -- the objective/acceptance panel (M11e). docs/SCENARIOS.md.
#include "ui/scenario_panel.h"

#include "imgui.h"

namespace astro::ui {

void scenario_panel_draw(const char* objective, const ObjectiveCheck* checks, int count,
                         bool has_scenario) {
    ImGui::SetNextWindowPos(ImVec2(384, 584), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(440, 0), ImGuiCond_FirstUseEver);
    ImGui::Begin("Objective");

    if (!has_scenario) {
        ImGui::TextDisabled("No scenario. Load one with --scenario ID.");
        ImGui::End();
        return;
    }

    if (objective && objective[0]) ImGui::TextWrapped("%s", objective);
    ImGui::Separator();

    if (count == 0) ImGui::TextDisabled("no acceptance checks (sandbox)");

    int passed = 0, live = 0;
    for (int i = 0; i < count; ++i) {
        const ObjectiveCheck& c = checks[i];
        if (!c.live) {
            ImGui::TextColored(ImVec4(0.60f, 0.62f, 0.68f, 1.0f),
                               "[ ] %-24s (measured at run end)", c.metric);
            continue;
        }
        ++live;
        if (c.pass) ++passed;
        const ImVec4 col = c.pass ? ImVec4(0.45f, 0.85f, 0.55f, 1.0f)
                                  : ImVec4(1.00f, 0.55f, 0.40f, 1.0f);
        ImGui::TextColored(col, "[%s] %-24s %10.4g %s %.4g",
                           c.pass ? "x" : " ", c.metric, c.measured, c.op, c.target);
    }
    if (live > 0) {
        ImGui::Separator();
        ImGui::Text("%d / %d live checks passing", passed, live);
    }
    ImGui::End();
}

} // namespace astro::ui
