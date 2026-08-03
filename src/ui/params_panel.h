// src/ui/params_panel.h -- the parameter inspector (M11d). docs/ARCHITECTURE.md Sec 6.
#pragma once

#include "core/params.h"

namespace astro::ui {

// The provenance inspector over the runtime ParamSet: every parameter with its provenance
// badge and value, and the canon locks -- unlocking a CANON parameter flags the run
// NON-CANON (ADR-034), the honest bookkeeping of the source research turned into a feature.
void params_panel_draw(astro::ParamSet& ps);

} // namespace astro::ui
