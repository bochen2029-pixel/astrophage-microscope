// src/ui/params_panel.cpp -- the parameter inspector (M11d). docs/ARCHITECTURE.md Sec 6.
//
// A view onto canon's PARAM_TABLE with provenance badges, over the core/params.h ParamSet.
// Every CANON parameter is locked; unlocking one flags the run NON-CANON (ADR-034) -- the
// honest bookkeeping of the source research (which numbers Weir wrote, which we made up)
// turned into a feature. Live value editing lands with the runtime read path (M11e); until
// then this is a read-only inspector plus the lock guard, never an editor that does nothing.
#include "ui/params_panel.h"

#include "imgui.h"

#include "core/canon_generated.h"

namespace astro::ui {

namespace {

ImVec4 prov_color(canon::Provenance p) {
    switch (p) {
        case canon::Provenance::Canon:    return ImVec4(1.00f, 0.84f, 0.20f, 1.0f);  // gold
        case canon::Provenance::Derived:  return ImVec4(0.45f, 0.65f, 1.00f, 1.0f);  // blue
        case canon::Provenance::Real:     return ImVec4(0.62f, 0.66f, 0.72f, 1.0f);  // grey
        case canon::Provenance::Invented: return ImVec4(1.00f, 0.60f, 0.25f, 1.0f);  // orange
    }
    return ImVec4(1, 1, 1, 1);
}

const char* prov_tag(canon::Provenance p) {
    switch (p) {
        case canon::Provenance::Canon:    return "CANON";
        case canon::Provenance::Derived:  return "DERIV";
        case canon::Provenance::Real:     return "REAL ";
        case canon::Provenance::Invented: return "INVNT";
    }
    return "?";
}

void draw_group(ParamSet& ps, canon::Provenance group) {
    for (int i = 0; i < canon::PARAM_COUNT; ++i) {
        const canon::ParamMeta& m = canon::PARAM_TABLE[i];
        if (m.prov != group) continue;

        ImGui::TextColored(prov_color(m.prov), "%s", prov_tag(m.prov));
        ImGui::SameLine();

        // CANON parameters carry a lock; everything else is aligned past that column.
        if (m.prov == canon::Provenance::Canon) {
            bool locked = ps.locked[i];
            ImGui::PushID(i);
            if (ImGui::Checkbox("##lock", &locked)) {
                if (!locked) param_unlock(ps, i);   // unlocking flags the run non-canon
                else ps.locked[i] = true;            // re-lock; the flag stays sticky
            }
            ImGui::PopID();
            ImGui::SameLine();
        } else {
            ImGui::Dummy(ImVec2(24.0f, 0.0f));
            ImGui::SameLine();
        }

        ImGui::Text("%-28s %10.4g %s", m.key, ps.value[i], m.unit);
        if (ImGui::IsItemHovered() && m.note && m.note[0])
            ImGui::SetTooltip("%s", m.note);
    }
}

}  // namespace

void params_panel_draw(ParamSet& ps) {
    ImGui::SetNextWindowPos(ImVec2(384, 12), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(440, 560), ImGuiCond_FirstUseEver);
    ImGui::Begin("Parameters");

    if (ps.non_canon_run)
        ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.30f, 1.0f),
                           "NON-CANON RUN  -- a canon lock was broken");
    else
        ImGui::TextColored(ImVec4(0.45f, 0.85f, 0.55f, 1.0f), "canon: all locks intact");
    ImGui::TextDisabled("Uncheck a CANON lock to mark it for tuning -- that flags the run.");
    ImGui::TextDisabled("(Live value editing arrives with the runtime read path, M11e.)");
    ImGui::Separator();

    ImGui::BeginChild("params_scroll");
    if (ImGui::CollapsingHeader("CANON -- stated in Project Hail Mary", ImGuiTreeNodeFlags_DefaultOpen))
        draw_group(ps, canon::Provenance::Canon);
    if (ImGui::CollapsingHeader("INVENTED -- our choice; canon is silent"))
        draw_group(ps, canon::Provenance::Invented);
    if (ImGui::CollapsingHeader("DERIVED -- computed from canon + real physics"))
        draw_group(ps, canon::Provenance::Derived);
    if (ImGui::CollapsingHeader("REAL -- real-world constant or material property"))
        draw_group(ps, canon::Provenance::Real);
    ImGui::EndChild();

    ImGui::End();
}

} // namespace astro::ui
