// src/ui/inspector_panel.h -- the cell inspector (M11f).
//
// Click a cell in the chamber and read its state, with the P1 buoyancy line front and
// centre (ui/MODULE.md: the buoyancy line is what teaches P1, so it is prominent, not a
// footnote). `ui` may not include `sim` (ui/MODULE.md), so the APP does the picking and the
// per-cell download, converts to display units, and hands this plain-data struct in -- the
// same boundary the objective panel uses. No sim type crosses into ui.
#pragma once

#include <cstdint>

namespace astro::ui {

// One picked cell, already in display units and with the buoyancy verdict resolved app-side.
struct CellReadout {
    bool               valid = false;   // a cell is picked and was read this frame
    unsigned long long id = 0;
    int32_t            slot = -1;

    // Kinematics. Gravity is along Y (MotionConfig), so vy IS the vertical drift -- the
    // reading that makes P1 legible (an empty cell rises, a full one sinks).
    double x_um = 0, y_um = 0, z_um = 0;   // position [um]
    double vy_um_s = 0;                    // vertical drift [um/s], + is up
    double speed_um_s = 0;                 // |v| [um/s]

    // State.
    double charge_pct = 0;                 // energy / CELL_ENERGY_MAX * 100
    double energy_j = 0;
    double temp_c = 0;                      // cell temperature [C]
    double biomass_ng = 0;
    double age_s = 0;
    bool   awake = false;
    bool   alive = false;
    bool   corpse = false;                  // occupied, not alive
    const char* death_cause = "";           // "" unless a corpse

    // The P1 buoyancy line (the teaching moment).
    double density = 0;                     // [kg/m^3]
    double density_ratio = 0;               // x water
    bool   sinking = false;                 // charge above neutral buoyancy
    double neutral_pct = 0;                 // the 3% line, for context
};

// Draws the clicked-cell readout. A run with no pick shows how to select one.
void inspector_panel_draw(const CellReadout& r);

} // namespace astro::ui
