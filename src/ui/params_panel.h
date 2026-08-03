// src/ui/params_panel.h -- the parameter inspector (M11d). docs/ARCHITECTURE.md Sec 6.
#pragma once

#include "core/params.h"

namespace astro::ui {

// The provenance inspector over the runtime ParamSet: every parameter with its provenance
// badge and value, and the canon locks -- unlocking a CANON parameter flags the run
// NON-CANON (ADR-034), the honest bookkeeping of the source research turned into a feature.
//
// `live` (length canon::PARAM_COUNT, supplied by the app) marks the curated set the SIM
// actually reads an override for (ADR-035). A live, unlocked parameter gets a real editable
// slider that moves physics; everything else stays read-only -- a control that silently does
// nothing is worse than one labelled as such (ui/MODULE.md). Pass nullptr for pure read-only.
void params_panel_draw(astro::ParamSet& ps, const bool* live);

} // namespace astro::ui
