# SESSION LOG

Append-only. One entry per session, under 25 lines. **Read the last two entries at session start; never the whole file.**

Format: milestone · what landed · what is pending · open questions · gotchas.

---

## 2026-08-04 — M13b (Interaction: the light-leash + optical tweezers) — GREEN · **herd the culture, tow a cell**

**Landed.** The M13 arc's second half (ADR-041). Two honest, emergent interactions, both applied at a tick
boundary, both default-off so an un-poked run is bit-identical (M0.4). (1) The **light-leash**: a Light tool drags a
*positional spotlight* -- a radial `(1-t^2)^2` irradiance disc (a new default-off path in `emission_step`) whose peak
awake sub-0.95-charge cells climb via the existing Feed run-and-tumble, following the cursor like a laser pointer
-- emergent herding (P4 + taxis), nothing scripted. (2) The **optical tweezers**: a Grab tool tows the picked cell
with a real harmonic trap (`trap_force`, forces kernel stage 5), stiffness scaled off the stability-limited
CONTACT_STIFFNESS; z stays under buoyancy, so it holds a cell against gravity. Both are World fields, not a
`LightSource` contract bump -- the render boundary is untouched (like `ambient_irradiance`).

**Why a spot.** The canon `LightSource` is a directional plane wave (flat, for P5) with no peak to herd toward; a
focused disc gives the gradient and cells do the rest. The directional light + its P5 shadows are untouched (the
spot is a separate additive path).

**Verified.** `--auto-light` herds an awake culture's centroid +326 um toward an off-frame +x spot (medium stays
healthy at 369.5 K; brightfield shows the pile at the +x wall); `--auto-grab 0 1000 500` tows slot 0 to within 0.3 um
of the target (inspector reads 1000.1, 500.3 um). `test_motion` gains a `trap_force` assertion. Gate M0..M12e +
M13a + M13b.1/.2 green; M0.4 determinism + M3.2 goldens unmoved.

**Gotcha (backlog).** Over-herding a big culture (~2000+ cells) into a tight pile drives the explicit thermal solver
negative -- extreme local density overruns its substep budget (ADR-008-class, pre-existing, NOT the light code;
awake+no-light is stable). Gate uses 1000 cells, below that. Worth a substep-vs-density guard someday.

**User request logged:** a **demo/screensaver mode** (new M14a/b in MILESTONES) -- a looping attract mode framing the
real emergent behaviours (Conway's Life as the feeling; honest physics as the mechanism).

**Next.** M13c (record interactions), the M12 ship line (M12f/g -> v1.0), or M14 (demo mode). M13a+b unpushed.

---

## 2026-08-03 — M13a (Interaction: the field-brush toolset) — GREEN · **poke the culture to ignite it**

**Landed.** The M13 arc opens (direct mouse manipulation). A Tools palette (Inspect + Heat/Chill/CO2/N2), the input model changed so **right-drag pans** and **left drives the active tool** (a left click still picks a cell under Inspect), brushes painted at the cursor via `world_apply_brush` at a tick boundary, a brush size/strength control, and a cursor ring at true µm size coloured by tool. Heat is the marquee: hold over dormant powder and it ignites -- the local medium crosses 96.415 °C, cells wake and warm their neighbours (P2), the front spreads, all emergent. New ADR-040. A **parallel arc off m12e-green** (before the M12f/g ship line); its gate re-runs M0..M12e but not the unbuilt M12f/g.

**Honest + safe.** Every poke is a field deposit (nothing fakes advection; M13b's tweezers will be a real optical-trap force). Applied from the tick loop, never the input handler (mid-tick device writes break INV-8). Live pokes are non-deterministic by design; an un-poked run is bit-identical (M0.4 confirms). Heat rate tuned (~2.5 K/tick, 180 µm) to cross the setpoint without overshooting 573 K lethal. Verified: `--auto-poke heat` (headless stand-in for a drag) ignites a dormant culture (awake 60, max medium 140 °C, cells alive); Thermal-IR screenshot shows the ignited cells' gold rims + the palette.

**Gotcha.** The brush is LOCAL; the mean medium temp barely moves while the local hotspot hits the setpoint -- read `max_temp`, not the mean (the end-state printf now reports both, for uniform runs too). `three-percent-line` cells sink off-centre, so a centre poke misses them; verify ignition on a spread population.

**Pending / next.** M13b: the light-leash (drag the light source, cells herd) + optical tweezers (grab a cell). The M12 ship line (M12f render remainder, M12g package → v1.0) is still open in parallel.

---

## 2026-08-03 — M12e (Ship: render legibility) — GREEN · **the evolution arc, visible**

**Landed.** Two low-risk render features (chosen over the render remainder, whose render_view_v3 bump cascades into scenario_v3). (1) The **Taumoeba are coloured by their N2 tolerance** (carried in the instance since M12b): pale teal for the intolerant, vivid gold-green for the evolved Taumoeba-82.5 -- the selection arc is visible, the swarm warming toward gold as the N2 ramp breeds tolerance. A no-op for cells (gated on the ADR-037 predator bit), so every golden is byte-identical. (2) The **colourblind-safe LUT** (a HUD toggle + --colorblind) swaps the petrova-film LUT for magma in Petrovascope, default-off so the m7b golden is unmoved. (3) **--mode now overrides a scenario's scope.mode** (like --objective). New ADR-039.

**Verified.** Screenshot: at mean tolerance 0.46 the swarm has warmed from teal (tol 0) toward yellow-gold. The colourblind LUT by a **must-differ** (imgdiff of Petrovascope with/without --colorblind: max channel delta 241 on the glow) -- the opposite of a golden, proving the swap does something. Gate green M0..M12e; M3.2 goldens unmoved, M1.5 fps intact.

**Pending / next.** M12f: the render remainder (the render_view_v3->scenario_v3 cascade for pre-ignition temp_c, bloom over Petrova, cross-fade, T-field false-colour). Then M12g: package + v1.0.

---

## 2026-08-03 — M12d (Ship: the time scrubber) — GREEN · **rewind through the run**

**Landed.** The scrubber rewinds a live run through a rolling ring of full-state snapshots. `snapshot_to_bytes`/`from_bytes` (M12a's ASPH, in memory) so recording a frame costs no disk; `snapshot_save`/`load` are now thin wrappers over them (test_snapshot T21.4 exercises the in-memory round trip -- same INV-8 fidelity). The app records a frame every 30 ticks during live play, bounded to 256 MB (oldest evicted), and **off under --benchmark** so M1.5's fps is unperturbed; the HUD **Timeline** slider rewinds into the ring. New ADR-038. M12 re-split M12d/e/f: scrubber, then the render remainder, then package.

**Seeking re-applies the motion config** (snapshot_v1 doesn't carry it, ADR-036), refreshes the HUD stats so the clock shows the rewound frame at once (not a stale HUD-rate cache), and clears the cell pick. Verified: `--scrub-to N` (headless stand-in for the slider drag) rewinds bloom/taumoeba to frame 0 -- the HUD reads the rewound tick 50, the render is the past state, exit 0. Gate green M0..M12d, incl. M1.5 (fps) + M3.2 (goldens) untouched.

**The render_view_v3 finding (for M12e).** The render remainder's `render_view_v3` bump (per-cell `temp_c` → pre-ignition Thermal-IR warm-up) **cascades into `scenario_v3`**: `scenario_v2.h` includes `render_view_v2.h`, and nothing may include two versions. That multi-contract change is exactly why the render remainder wants a fresh, focused session.

**Pending / next.** M12e: the render remainder (the `render_view_v3`→`scenario_v3` cascade, bloom over Petrova, cross-fade, T-field false-colour, colourblind LUT). Then M12f: package + `v1.0`.

---

## 2026-08-03 — M12c (Ship: the performance pass) — GREEN · **the tick loop allocates nothing, and it is at budget**

**Landed.** `test_perf` (T28/T29), split out so the perf pass stands alone (M12 re-split M12c/d/e, Iron Rule 9). **T29** is load-bearing: zero device allocation in the steady-state tick loop. A world that divides AND compacts (the scan/gather paths most likely to sneak a per-tick `cudaMalloc`) is warmed up, then stepped 500 ticks; `cudaMemGetInfo` free comes back **delta 0 KB** even as the population churns 39664 -> 76185, so all scratch really is carved once at `world_create`. **T28**: 200k cells at **2.598 ms/tick**, right at the 2.7 ms budget (the ceiling is generous -- M1.5's fps target polices the real budget with the renderer in the loop). T27 (render frame budget) stays M1.5's `--benchmark`.

**Gotcha.** `cudaMemGetInfo` catches a leak-shaped regression (a per-tick malloc-without-free), the common one; malloc-then-free churn would show delta 0 -- documented, and the design forbids both. Timing (T28) is generous on purpose: a hard ms/tick assert is machine-flaky.

**Pending / next.** M12d: the M7b render remainder (bloom over Petrova, cross-fade, T-field false-colour; the **`render_view_v3`** bump for pre-ignition `temp_cell`), the colourblind LUT, the time scrubber over M12a's snapshots. Then M12e: `package.ps1` + `v1.0`.

---

## 2026-08-03 — M12b (Ship: Taumoeba rendering) — GREEN · **the predators are no longer invisible**

**Landed.** The Taumoeba ran but never drew (the app filled the instance buffer from the cell store only). Now they render as `CellInstance`s appended after the cells in the same instanced draw (`RenderFrame::taumoeba_offset`, designed for this since render_view_v2). New contract `contracts/taumoeba_view_v1.h` (`TaumoebaView`) so render reads the predator store without including `sim/`; `interop_fill_frame` maps the GL buffer ONCE (WriteDiscard forbids two) and fills cells `[0,cell_count)` + Taumoeba `[cell_count,total)`; the fragment shader branches on a render-only marker bit (0x8000) into a translucent teal membrane. New ADR-037; new additive contract, no bump.

**Byte-identical for cells.** The predator branch reads bit 15 of `flags_packed`, which sim never sets, so a cell always skips it and every measurement golden is unchanged (M3.2 re-verified green; imgdiff is tolerant anyway). The instance buffer is sized `cell_cap + tau_cap`; `CellsPass::capacity` still reports the cell capacity so the HUD and respawn clamp are unaffected.

**Verified by screenshot** (meta-lesson 11): the taumoeba scenario breeds the 20 predators into thousands, and they render as green irregular membrane blobs consuming the black Astrophage -- distinct, visible, reading as organisms (they reuse the cell morphology's `shape_seed`). Gate green: the app renders the scenario headless with zero GL errors, all goldens match.

**Pending / next.** M12c: the perf pass (T27-T29, `test_perf`), the M7b render remainder (bloom over Petrova, cross-fade, T-field false-colour; `render_view_v3` for pre-ignition `temp_cell`), the colourblind LUT, the time scrubber over M12a's snapshots. Then M12d: package + `v1.0`. Deferred: a distinct amoeba silhouette, a tolerance-coloured Analysis channel (the view already carries `tolerance`).

---

## 2026-08-03 — M12a (Ship: snapshot save/load + replay determinism) — GREEN · **a run saves and resumes bit-identically**

**Landed.** `src/sim/snapshot.cu` — the ASPH full-state dump (`contracts/snapshot_v1.h`): header, the ADR-035 overrides on the `ParamOverride` array, the CellStore + TaumoebaStore SoA in declaration order, and the T/CO2/N2 fields (irradiance is rebuilt, never stored). `snapshot_save` / `snapshot_load` / `snapshot_state_hash`. The array list is written once per store (`collect_*_spans`) and reused for both directions, so save and load can't disagree about layout. New ADR-036; no contract change. M12 was split M12a/b/c first (Iron Rule 9).

**A `.cu`, not the inventory's `.cpp`.** The `.cpp` files in `astro_sim` reach the device only through `_download_*` helpers (no `cuda_runtime.h`); snapshot copies *every* array, so it `cudaMemcpy`s them directly as a `.cu`. Inventory + `sim/MODULE.md` reconciled in the commit.

**The full-state hash is the INV-8 oracle at full resolution** (headless hashes only pos/vel/energy). `test_snapshot` (T21): round-trip fidelity on a rich world (3000 -> 5933 cells via division, 40 predators, a tuned override + broken lock -- hash and every scalar survive); replay across the boundary (step original + restored 30 ticks past save -> identical hash `54ef714f...`); a corrupt magic rejected.

**Two snapshot_v1 gaps, handled + flagged (ADR-036).** Motion config is NOT serialised -- it's *how a run was set up*, not its state, so the caller restores it (the test mirrors it). Taumoeba `next_id` has no header slot -> reconstructed `max(id)+1` (exact unless the top-id predator was culled), so T21's replay arm is cells-only; a `snapshot_v2` field closes it.

**Pending / next.** M12b: the perf pass (T27-T29, `test_perf`), **Taumoeba rendering** (still invisible), the M7b render remainder (`render_view_v3` for pre-ignition `temp_cell`), the colourblind LUT, the time scrubber over these snapshots. Then M12c: `package.ps1` + `v1.0`.

---

## 2026-08-03 — M11f (Content: cell inspector + live param overrides) — GREEN · **the inspector's sliders finally move physics**

**Landed.** Two features that close M11's UI. (1) The **cell inspector** (`inspector_panel.cpp`): click a cell -> its state with the P1 buoyancy line prominent (SINKING/RISING, density, x water). Picking is app-side -- cursor -> chamber via the camera, nearest cell from a positions download, the slot latched with its id so a recycled slot drops the pick -- and one cell is read at HUD rate through a new `cell_store_sample`, converted to display units, handed to the panel as plain data (`ui` may not include `sim`). `--inspect N` pre-selects a slot for headless screenshots. (2) The **curated live overrides** (ADR-035): `PETROVA_MAX_POWER` / `PETROVA_FLASH_POWER` / `CO2_MASS_PER_DIVISION` each get a `World` field the app fills from the `ParamSet` every frame; the kernels read it (threaded via **defaulted** args, so every other caller is unchanged). The params panel now draws a real LIVE slider for exactly these three, read-only otherwise. New ADR-035; no contract change.

**Verified.** `test_param_override` (M11f.1): halving the division quota grows faster (7942 > canon 4000 > double-quota 2000), 2x flash power discharges 2x the store (ratio 2.0000), and **the default reproduces canon exactly (4000 == 4000)** -- the determinism half is the honest guard (a gate that only checks "override changes something" could pass while perturbing M9a). Screenshot (three-percent-line --inspect 0): the inspector reads "SINKING -- 1155 kg/m3, 1.16x water" for a 3.499% cell; exactly the 3 curated params carry a LIVE slider. M11f.2: the app renders a picked cell headless, zero GL errors. Full gate M0..M11f green; determinism replay hash unchanged.

**Gotchas.** Defaults MUST be the `canon::` value bit-for-bit (World default member initializers) or a hash moves. The `--screenshot` + `--gl-debug` combo trips one pixel-transfer perf warning (glReadPixels) -- the gate uses them separately, as M11d does. `pick_id == 0` is a safe "unlatched" sentinel: cell ids start at 1 (0 = no cell).

**Pending / next.** M12 Ship: snapshot/replay + time scrubber, perf pass, colourblind LUT, **Taumoeba rendering** (still invisible), the M7b render remainder (`render_view_v3` for pre-ignition `temp_cell`), packaging, then v1.0. Deferred together: scenario `param_overrides` application (parsed, unapplied -- no scenario needs one) and the full `constexpr`->runtime refactor.

---

## 2026-08-03 — M11e (Content: the objective/acceptance panel) — GREEN · **the scenario grades itself on screen**

**Landed.** `scenario_panel.cpp`: the loaded scenario's objective text + a live checkmark per accept check. The catch — `ui` may not include `sim`, and `accept_eval`/`metric_measure` live in `sim` — so the **app** evaluates the checks (it links both: samples a `RunAggregates` at HUD rate, calls `sim::metric_measure` + `sim::accept_eval`) and hands a plain-data `ObjectiveCheck[]` to the panel. Verified by screenshot: first-light shows **3/3 live checks passing** (awake 1>=1, medium 369.5~=369.6, boil 0==0), green. Split from the original M11e (Iron Rule 9): the cell inspector + live overrides are M11f. No new ADR.

**Honest about the derived metrics.** Velocity fit, doubling, and flash impulse need the whole run, so they show "measured at run end" rather than a misleading live cross; direct metrics + correlations are live. The panel agrees with `headless --assert` by construction (same functions). Gate: `M11d.1`'s headless auto-play now draws the panel every frame, so it exercises the app-side eval for all eight scenarios (exit 0).

**Pending / next.** M11f: the cell inspector (click → state + the P1 line via picking; the HUD Charge section already teaches P1) and the sim reading overridden params for a curated set (so the inspector sliders bite). Then M12 Ship.

---

## 2026-08-03 — M11d (Content: app auto-play + the parameter inspector) — GREEN · **the scenarios can be watched**

**Landed.** The app plays scenarios. `--scenario ID` loads + instantiates one (its own clock + scope + capacity) and `scenario_apply_drive` runs before every `world_step`, so first-light ignites, the spin-drive flash empties the store, etc. New `params_panel.cpp`: every `PARAM_TABLE` entry with a provenance badge (CANON gold, INVENTED orange, DERIVED blue, REAL grey) over the `core/params.h` `ParamSet`, with the canon lock toggles; unlocking a CANON param flips the **NON-CANON RUN** badge (HUD + panel, from `Stats.non_canon_run`). Split from the original M11d (Iron Rule 9): the cell inspector + objective panel are M11e. No new ADR (uses ADR-034 + the M11b driver).

**Verified without a display.** `--headless` is a hidden window with a real GL context, so `--screenshot` captures the full frame (ImGui included). Converted PPM→PNG and looked: first-light's medium chart plateaus at 96.35 °C (ignition + thermostat), the params panel shows the gold CANON locks, the field renders the cells. The gate (`M11d.1`) loops every scenario through `astrophage --scenario <id> --headless --gl-debug` and requires exit 0 — auto-play works for all eight, default path intact.

**The honesty call (ui/MODULE.md).** The inspector shows values read-only + working lock toggles; live *value* editing is labelled pending, not a slider that does nothing — a control that silently does nothing is worse than one labelled pending. The objective panel is deferred because `accept_eval` lives in `sim` and `ui` may not include it, so the app must compute the checks and hand them to the panel (M11e).

**Pending / next.** M11e: the objective/acceptance panel (checkmarks, results computed app-side against a live `RunAggregates`), the cell inspector (click → state + the P1 buoyancy line), and the sim reading overridden param values for a curated set (so the inspector's sliders affect physics). Then M12 Ship.

---

## 2026-08-03 — M11c (Content: runtime-param overlay, canon locks, telemetry) — GREEN · **a run cannot quietly go non-canon**

**Landed.** The provenance/telemetry backbone of the inspector, split from the original M11c (Iron Rule 9 — the ImGui panels are now M11d). `src/core/params.h`: a `ParamSet` runtime OVERLAY of `PARAM_TABLE`'s 109 params (ADR-034) — values from canon, every CANON param locked by default, and a **sticky `non_canon_run`** flag set the moment a canon lock is broken. `World.non_canon_run` → `world_stats` → `Stats.non_canon_run`. CSV telemetry export (`headless --csv`): the SCENARIOS.md columns, header recording seed / scenario / non-canon status. **`test_param_locks` green** (the M11c gate). New ADR-034; no contract change (`Stats.non_canon_run` pre-declared).

**The design call (ADR-034):** the overlay does NOT replace `constexpr` canon — canon stays the source of truth and the default (Iron Rule 3). The sim reads `canon::` by default; the overlay is what the inspector edits and (from M11d) the sim reads overridden values from for the curated tunable set. The flag trips on **unlocking** (not changing), stickily: a run that looks canon but broke a lock is the worst failure the UI can have (ui/MODULE.md), so the guard is conservative and irreversible.

**Why the split.** The M11 UI panels did not exist (`src/ui` had only hud/chart/scale_bar). Building three ImGui panels + the runtime-param system in one session — panels that need a display to verify — is two milestones. M11c is the headless-verifiable backend (`test_param_locks` + a written CSV); M11d is the panels + app auto-play of scenarios.

**Pending / next.** M11d: params_panel (badges + lock toggles → `ParamSet`), inspector_panel (click-cell + the P1 buoyancy line), scenario_panel (objective checkmarks over `accept.cpp`), the HUD non-canon badge, and wiring the app to auto-play a scenario's drive script (so the eight scenarios can be watched, not just asserted). Then M12 Ship.

---

## 2026-08-03 — M11b (Content: acceptance, driving, the flash) — GREEN · **all 8 scenarios pass their objectives**

**Landed.** The acceptance layer on M11a's spine. `scenario_v2` adds a scripted `drive[]` (ADR-032): `scenario_apply_drive` (sim) applies heat / N₂-ramp / flash / top-up stimuli each tick, shared by headless and (later) the app. `sim/accept.{h,cpp}` measures every objective from `Stats` + a `RunAggregates`; `headless --scenario ID --assert` runs to the horizon and exits nonzero on a missed check. The **spin-drive flash** (`flash.cu`, ADR-033, new canon `PETROVA_FLASH_POWER`) is the one new physics. **T24 green: all 8 ACCEPT.** New ADR-032/033. Contract bump v1→v2 (drive, `thermal_active`, compaction flags, `duration_s`).

**Derived metrics** (from full state, not just `Stats`): displacement-based velocity fit (three-percent-line −52.1/+1681 μm/s — instantaneous velocity is 8× thermal noise, so fit drift over seconds), charge/depth & charge/height correlations, `biology_rate`-scaled doubling (bloom 706k s), max tolerance (taumoeba 0.99), the flash impulse identity (spin-drive 1.0).

**Physics found while tuning (all in SCENARIOS.md):** (1) three-percent-line must be **dormant** — awake cells warm the medium, drop μ 3.36× and inflate drift 3.25×. (2) first-light cells need a small store (0-store wakes → overcools → starves) and a **neumann** boundary (robin's edge gradient makes all-awake + mean-at-setpoint incompatible). (3) komorov `thermal_active:false` + `physics_rate 100`: 44 min → 25 s, exact for a static cell. (4) shadow-garden bright source read early while the gradient is steep. (5) taumoeba mirrors `test_evolution` (24k topped-up prey via `seed_cells`).

**Gotchas.** The global brush needed radius 10× chamber — `grid_brush`'s `(1-t²)²` falloff otherwise wakes centre cells first (665/800). `tol` is relative unless `tol_absolute` (first-light ±0.5 K). The flash recoil is **accounted, not applied** (a 16.7 ng discharge recoils a lone cell at ~c). Determinism preserved: `thermal_enabled`/`flash_active` default to M9b/M11a behaviour, so `world_step` is bit-identical unless a scenario opts in.

**Pending / next.** M11c: the parameter inspector + canon locks (`test_param_locks`), the cell inspector, the objective panel, CSV export, and the runtime-param system that makes `param_overrides` apply. Deferred: Q9, Q18, the M7b render remainder.

---

## 2026-08-02 — M11a (Content: scenario spine) — GREEN · **scenarios load and run**

**Landed.** The scenario system, which was a stub (`headless` printed "arrives in M11"). A hand-rolled dependency-free jsonc reader (`src/sim/json.h`), a loader + world instantiation (`src/sim/scenario.{h,cpp}`), all **eight** `scenarios/*.json`, the `headless --scenario ID` runner, and `test_scenario`. **24 tests green.** No contract change (`Scenario`/`ScopeState`/`ParamOverride`/`AcceptCheck` all pre-existed). New ADR-031. M11 was **split into M11a/M11b/M11c** first (Iron Rule 9) — this is M11a.

**The gate is `test_scenario` (INV-8, again).** Every scenario loads, instantiates into a `World`, spawns exactly its spec'd populations, and runs **bit-reproducibly** (same scenario → same hash; a different scenario diverges). first-light 800 · three-percent-line 2000 · komorov 1 · shadow-garden 12000 · bloom 10 · taumoeba 3000+20 · spin-drive-face 1000 · sandbox 5000 — all `det`. Headless smoke: taumoeba thins 3000→2997 in 100 ticks; first-light sits cold (no driving yet, correct).

**Four decisions, in ADR-031.** (1) JSON hand-rolled, no dependency. (2) Loader in `sim` — it builds a `World` (snapshot.cpp's precedent) and both `headless` and the app link sim; it is the first `.cpp` in `astro_sim`. (3) `scope` (render-only) and `param_overrides` (need a runtime-param system, which is `constexpr` canon's blocker → M11c) are **parsed but not applied**. (4) **Accept-evaluation + scenario driving → M11b**: every accept block needs driving (first-light's heat, taumoeba's N₂ ramp — the schema has no scripted events) or a derived metric.

**Gotchas.** `Placement`/`Distribution` exist in BOTH `astro::sim` and `astro::contract`; inside `namespace astro::sim` the unqualified name is the sim one, so the loader's helpers are explicitly `contract::`-qualified. `Error`'s `operator bool` is explicit — `CHECK(!e)` works, `CHECK(e)` needs a `static_cast<bool>`. Scenarios load by absolute path (`ASTRO_SCENARIOS_DIR` compile define); relocatable paths are M12's.

**Pending / next.** M11b: the accept framework + `--assert` runner, the scenario-driving mechanism (scripted stimulus, likely `scenario_v2`, own ADR), the derived metrics, the spin-drive flash (new physics, own ADR), and all 8 scenarios passing T24.

---

## 2026-08-02 — M10b (Evolution) — GREEN · **Taumoeba-82.5 breeds itself**

**Landed.** The evolution half of predation: N₂ Poisson lethality, heritable N₂ tolerance, Taumoeba division mirroring cell mitosis (prefix-sum slots, daughter stream, mutation from the daughter's draw), a per-Taumoeba `generation` counter, and a stable opt-in `taumoeba_store_compact` (ADR-028). `Stats.n_taumoeba` / `mean_tau_tolerance` filled in the stage-11 reduction; a mean-tolerance chart in the UI. **23 tests green** (added `test_evolution`). No contract change (both telemetry fields were already declared). New ADR-030.

**The arc emerges — it is not scripted (T32).** Under a slow N₂ ramp the mean tolerance climbs monotonically 0.005 → 0.89, and **Taumoeba-82.5 appears at lineage generation 36** (budget 40), by directional selection: high N₂ kills the intolerant, survivors divide and pass on mutated tolerance, the frontier climbs, the population tracks it. The population is decimated by selection (2748 → 119) then **recovers** once the tolerant strain stops dying. A **constant-N₂ control** plateaus at max tolerance 0.17 (T33) — the rise is the *rising* ramp's selection, not drift or the [0,1]-clamp (meta-lesson 4). T31 is T22 a third time: the dividing/dying/compacting store is bit-reproducible.

**Two model calls, both in ADR-030.**
- **Division is on DRY biomass, not the water-blob mass.** M10a set `biomass = TAU_MASS` (a 40 μm water blob); doubling that needs ~2655 prey and no arc could run. Split it as the cell splits `CELL_MASS_DRY` from total mass: `TAU_MASS_DRY` (1e-13 kg) is the growth variable, `TAU_MASS` is drag-only. Division at 2× dry biomass, ~8 prey. Meta-lesson 9 in new clothes.
- **The lethality rate is derived; its time scale is tuned.** `TAU_N2_HAZARD_RATE = 1/(N_lethal·TAU_N2_LETHAL_TIME)`. My first `TAU_N2_LETHAL_TIME` (120 s, "equal to digest time") drove the population **extinct in 6 rounds** — death outran reproduction. Weakening it 17× → 2000 s rescued it. The seductive derivation was wrong; only running the arc showed it (meta-lesson 5).

**Gotchas.** The N₂ death draws **one uniform unconditionally** per alive Taumoeba (ADR-022 — survivor and dier both draw), or determinism breaks. The ramp must **cap** (~1.87·N_lethal): pushing past 2·N_lethal kills even a tol=1 strain, so an uncapped ramp ends every run in extinction. Prey supply self-limits the predator population, so the store cap is not the binding constraint. Fixed pre-existing doc drift: `ARCHITECTURE.md §3.4` and `step.cu` now list predation as tick stage 10 (M10a never recorded it).

**Pending / next.** M11 Content (scenario loader, the 8 scenarios, inspector panels, CSV telemetry). Deferred: Q9 (27→8 bucket neighbour walk, now also Taumoeba prey-sensing), Q18 (Poisson tumble, inherited by the crawl), the M7b render remainder.

---

## 2026-08-02 — M10a (Predation) — GREEN · **the predator arrives**

**Landed.** The `TaumoebaStore` — a second organism SoA with its own PCG32 streams (double-mixed seed, disjoint from the cells), amoeboid crawl (run-and-tumble biased up the prey-density signal, reusing the taxis temporal comparison), deterministic engulfment, and digestion. `predation.{cuh,cu}`, tick stage 10, before lifecycle. 22 tests green. No contract change.

**T30 is the claim, and it is T22 for a second store.** A predation run — 150 predators crawling, engulfing, and digesting through a 6,000-cell culture over 2,000 ticks — reproduces **bit-identically** (hash `5301212a`), and a different seed diverges. ADR-014 holding for the second organism.

**Engulfment is order-free.** Two predators reaching one prey resolve by `atomicMin` of the predator id into a per-cell claim buffer, so the lowest id wins regardless of thread order — the fixed-point-deposit reasoning (INV-2) applied to a *claim* rather than a sum. Exactly one predator engulfs each claimed cell, so the prey death is race-free.

**Predation thins the culture** (T30.3): live **6,000 → 5,898**, 102 engulfed into corpses, every predator contained. The reduction is limited by the 5 μm/s crawl over 4 s of physics — a predator eats what it starts near. The dramatic crash is M10b's, on the biology clock over generations.

**Gotchas.**
- **A distance sentinel `1.0e30` tripped A9** (scientific notation in `sim/`). Switched to the FIRST overlapping prey in hash order — deterministic anyway (the hash is a stable sort, INV-7), which also removed a redundant overlap re-test.
- **The predator is neutrally buoyant** (water-density blob, `TAU_MASS = ρ_w · V_tau`), so there is no sedimentation term — the crawl is a purely driven walk, `TAU_CRAWL_THRUST` giving `TAU_CRAWL_SPEED` as the terminal velocity, exactly as photon thrust does for a cell.
- **Digestion is on the biology clock** (`dt_bio`), so a high `biology_rate` cycles predators fast — which is how the test sees kills at all in 4 s of physics time.

**Pending / next.** M10b: the N₂ field lethality, Taumoeba division, heritable tolerance, and the emergent Taumoeba-82.5 arc. The store's compaction (for N₂ deaths) reuses the M9c primitive.

---

## 2026-08-02 — M7b (View modes) — GREEN · **the black screen was a deferred mode, now lit**

**Landed.** Darkfield, **Petrovascope**, and **Thermal IR** drawn distinctly in the fragment shader (ADR-029), each with its own background, plus `--mode` / `--awake` CLI flags and honest HUD hints. Prompted by a user report: Thermal IR was a black screen. It was not a bug in the sim — the shader only implemented Brightfield and the other four modes fell through to an Analysis-by-charge ramp, near-black on a dark field for an uncharged culture.

**The reference redirected the physics, and that is the lesson.** My first cut made Thermal IR an *emission* thermogram — awake cells glowing warm on black. Then a frame of the 2026 film's actual IR view came in: a warm pink/red false-colour field with cells as **black silhouettes**. That is an *absorption* image, not emission — Astrophage absorbs at every wavelength (albedo 0), so under IR it is dark, and the pink is the medium's false-colour. Reworked to match: black absorbing cells on the warm field, a hot rim on the awake heat-sources (still exact from the `AWAKE` latch, ADR-003), and the circular field diaphragm since it is an illuminated view. **The Petrovascope stays the novel's emission view** (glow by `emit_power`) — so the two IR modes are now the novel-vs-film split shipped both ways, the same house move as ADR-002/003/023.

**No contract bump.** Both signals — `AWAKE` (thermal) and `emit_power` (Petrova) — were already in the instance, so `render_view_v3` buys nothing for the core contrast. `--mode` / `--awake` CLI flags let the modes be captured headless.

**The divergence is a golden.** `m7b_thermal_awake` vs `m7b_petrova_awake`, on an awake, half-charged, idle population (charged so an awake cell does not instantly starve; idle so it is not emitting) — the same cell is a visible dark absorber in Thermal and invisible in the Petrovascope. Every existing measurement golden verifies **unchanged**, because Brightfield (mode 0) was not touched — the guarantee ADR-023 gave morphology.

**Gotchas.**
- **An awake cell at charge 0 starves instantly** (energy 0 while awake ⇒ STARVED that tick), so `--awake` alone renders corpses, not glowing cells. The mode goldens pin `--charge 0.5`, which also keeps them idle-but-alive.
- **The 1-LSB golden-churn trap, again.** `-Generate` rewrote all 12 goldens; the 8 pre-existing ones showed modified at imgdiff **mean 0.0000, max 1**. Reverted them, kept only the 3 new `m7b_*` — committing the churn would make a future real change invisible in the diff (the M8b lesson).

**Pending / next.** Bloom over Petrova, the cross-fade slider, the Thermal field-halo, and pre-ignition warm-up (the one piece that truly needs `render_view_v3`). Then M10 predation.

---

## 2026-08-02 — M9c (Life: clock, compaction, charts) — GREEN · **the life cycle closes**

**Landed.** The multi-rate clock wired for real (physics_rate scales the physics dt; biology_rate the growth dt, compounding), the **Q19 decision** (ADR-027), opt-in stable **compaction** (ADR-028), CUB `DeviceScan` for the birth prefix (Q20), and the population/energy/temperature charts + clock UI + permanent energy ledger. 21 tests green (added `test_clock`), 27 files, ~760 LOC. No contract change.

**The regression guard is exactness at rate 1.** `test_clock` measures the physics ratio at **10.0000**, the biology ratio at **2.00000**, and the compounding at **1.00000** — and T22 is **unchanged at 50508 / hash `130793f3`**, which is the proof the clock is bit-identical to M9b when physics_rate = 1. The two couplings that would have broken it are handled at the source, not clamped: diffusion substeps are derived from the actual dt (`substeps_for_dt`), and contact stiffness scales as `1/physics_rate` so a fast clock never diverges the explicit spring and ejects a cell.

**T22b is the compaction claim.** A growing-and-dying culture with corpses reclaimed **and contact on** (ADR-018's reordering hazard) reproduces bit-identically: count 50378, **914 deaths reclaimed**, hash `42d459c3` on both passes. The map is an exclusive prefix sum (pure function of the flags), the move is out-of-place (an in-place parallel compaction is a read/write race), and it is stable, so within-bucket contact summation order is preserved.

**Q19 decided: biology_rate does NOT scale CO₂ diffusion.** It is real transport-limited growth, not a defect; faking a faster diffusivity would violate the oracle and blow the CO₂ stability budget. `physics_rate` is the honest lever, and the HUD says so.

**Gotchas.**
- **Compaction breaks death-differencing.** `deaths_this_window` was derived by differencing the live dead count, which goes **negative** the instant a corpse is reclaimed. Replaced with a cumulative host counter: new deaths = occupied-dead now minus corpses carried over. Under no-compaction the value is identical to M9b, so T23 is untouched.
- **physics_rate must not be applied twice.** M9c made `world_step` advance `DT*physics_rate` per tick; the app accumulator *also* scaled `dt_real` by physics_rate. Left as-was that squares the rate. Fixed: the accumulator is raw wall time now, since physics_rate lives inside the tick.
- **Thermal IR / Petrovascope still show a black screen** (user-reported). NOT M9c — it is the deferred M7b view modes: the shader only implements Brightfield distinctly and the rest fall through to an Analysis-by-charge ramp, which is near-black for uncharged cells. Fixable **without a contract bump** — the `awake` flag (thermal glow) and `emit_power` (Petrova glow) are already in the instance. Taking it next.

**Pending / next.** M7b (Petrovascope + Thermal IR + Darkfield in the shader), then M10 predation. Deferred list otherwise unchanged (Q9 8-bucket walk, Q18 Poisson tumble, bloom).

---

## 2026-08-02 — M9b (Life: death) — GREEN · **stage 11 finally ships**

**Landed.** Death by overheating, the three-way store disposition (ADR-004), and **tick stage 11 — the telemetry reduction, unshipped for nine milestones** while `contract::Stats` sat fully specified and entirely unfilled. 20 tests green. No contract change.

**T23 is the claim.** Eight reductions of one identical state produce an **identical bit pattern**, and the energy ledger matches a sorted host-side sum to 1e-9. Fixed point is not about accuracy here — a float sum would be *order-dependent*, so the HUD's last digits would flicker with occupancy and no two runs would agree on the ledger.

**ADR-004 is observable rather than nominal.** Under `void` a corpse falls to `CELL_DENSITY_DRY` = 40.1 kg/m³ and *rises*; under `retain` it stays at ~25,500 kg/m³ and rains to the coverslip. Both are just `mass = biomass + energy/c²` with the store gone or kept — no special case.

**Gotchas.**
- **A lethal bath does not sterilise, and that is P2.** 4,000 dormant cells dropped into 623 K — 50 K above lethal — lose only 3,411. Every one ignites (P3), and the survivors drag the medium from 623 K down to **601 K**, because the thermostat is bidirectional and *absorbs* heat above the setpoint. It surfaced as a confound in a disposition test; the right answer was to isolate that test **and assert the contest separately** (T23.5), not to suppress it.
- **The first death counter shared the stats accumulator** it was meant to be independent of. Divisions are already known on the host in `lifecycle_step`, and deaths difference against the previous reduction — so the window counters need no device buffer and no per-tick D2H at all.
- **`AWAKE` is not cleared on death.** The glossary makes alive/dead orthogonal to awake/dormant; a corpse that *was* awake is a fact about its history. Corpses stop emitting and stop taxis for free, since both stages already gate on `ALIVE`.
- **The M1.5 render benchmark caught two performance regressions no correctness test could.** `world_stats` was being called every frame and ends in a synchronous D2H; and `scan_kernel` is `<<<1,1>>>`, a serial loop over the whole population, running unconditionally to build a prefix that is almost always all zeros. Counting first and skipping the scan took 200k cells from **145.2 to 185.5 fps** — margin over target from 0.8 % to 29 % — with **T22's hash unchanged**, which is what proves it behaviour-preserving. Q20: the scan is still serial when divisions do happen; CUB `DeviceScan` belongs with M9c's compaction.
- **README screenshots regenerated** now that cells are grains rather than dots — hero and the 100× focus sweep. `p1-buoyancy` is left alone deliberately: it is a 10× survey montage where a cell is one or two pixels, so morphology cannot show and regenerating would only churn the file.

---

## 2026-08-02 — M9a (Life: division) — GREEN · **cells divide, reproducibly**

**Landed.** CO₂ uptake, mitosis with energy halving and `pcg_split`, and prefix-sum daughter slots. 19 tests green. **No contract change** — `biomass`, `co2_held` and `CELL_FLAG_DIVIDING` were all already in `cell_store_v1.h`.

**T22 is the one that mattered.** Every determinism result before this held a *fixed* population, so nothing had yet exercised the case per-cell streams were introduced to survive. A run growing 2,000 → **50,508** cells reproduces **bit-identically**, and a different seed still diverges. That is ADR-014 finally under load.

The design decision the milestone turns on: **daughter slots come from an exclusive prefix sum, never `atomicAdd`.** The snapshot hash is taken over the SoA in slot order, so order-dependent allocation would make the hash vary run to run. INV-2's reasoning one level up — it is the *allocation* that must be order-free, not just the arithmetic.

**T18 is exact rather than tuned**: `LIFE_CO2_UPTAKE_MAX` is *derived* from the canon doubling time, so the test asserts the implementation reproduces its own definition. Measured 4000 → 7986 in one doubling time = **1.996**.

**Gotchas — two unit bugs in one exchange, the second hiding behind the first.**
- Uptake drove the CO₂ field to **−0.128 kg/m³**. A per-cell clamp is not enough: N cells sharing a grid cell each take its whole contents. Fixed with a two-pass demand/ration.
- It *still* went negative, because the demand was booked in **kilograms** against a `deposit_scale` calibrated for **concentration** — 6e-16 rounds to zero in fixed point, so `asked` came back ~0 and the ration never fired. Match the units to the field, not just the sample to the source.
- **The test passed through both of those.** It asserted the *total* CO₂ stayed positive, which negative pockets clear easily by hiding behind positive ones. It now asserts the **minimum**. A gate that passes while the thing it guards is broken is worse than no gate — this is the inverse of the usual lesson, and it cost two debugging rounds.
- **Q19: `biology_rate` does not scale diffusion.** ADR-011 assumed biology clocks are local; CO₂ uptake is an exchange with a field on *physics* time. At 2e7 a cell eats 2e4 s of CO₂ per tick while the medium diffuses 1e-3 s worth, so growth goes locally diffusion-limited at 25 % consumption and even a saturating control slows once dense. T18.3 therefore compares against a control instead of asserting "grows then halts" — that shape is not constructible at a high biology rate. M9b owns the clock and should decide.
- Answered a question from the app: the "curtain rolling up" when zoomed out is **P1**, not a defect. Empty cells at 40 kg/m³ cream upward at 52 μm/s as a coherent front because the charge slider makes every cell identical. Verified with a new `headless --extent`: x ∈ [−1995, 1995] against walls at ±2000 — every cell contained. That check is now gate step M9a.2.

---

## 2026-08-02 — Q16 retune (ADR-024) — GREEN · **and a diagnosis that was half wrong**

**Landed.** `TAXIS_MEMORY_TIME` 2 s → **0.1 s**. Migration **20.3σ → 26.0σ**, a 28 % larger displacement on the identical scenario and seed.

The 2 s window was indefensible on its own terms: an awake cell crosses the whole 4 mm chamber in **0.655 s**, so the memory was **3.05 chamber crossings** and the cell compared against a baseline older than any gradient that could exist. The criterion is now derived and **asserted**, not advisory — `TAXIS_MEMORY_CHAMBER_RATIO` must stay under 0.5; it is 0.153. `TAXIS_SWIM_SPEED` is carried explicitly because its absence caused M8's 3.46× error.

**The prediction was backwards, and that is the useful part.** I expected the retune to *lower* the tumble rate. It **raised** it, 54 % → 69 %. A shorter memory makes the EMA track the signal more closely, so `Δ = signal − ema` is smaller and crosses zero more often — a longer memory gives a larger, more persistent Δ. The tumble rate is set by the **rule** (`Δ ≤ 0`, every tick, no refractory period), not by the window. I had bundled the two together at M8 and only one was the window's fault.

That migration improved *while* tumbling rose is the tell: frequent reorientation with the right sign is tighter gradient following, not jitter. **The tumble rate was a symptom I misread as the defect.**

**Gotchas.**
- **A measured symptom is not a diagnosis.** The M8 number was real; the causal story attached to it was not. Only re-measuring after the change exposed it. Predict, change, *re-measure*.
- The residual issue is better posed as **Q18**: no refractory period, so only **3.6 %** of cells are on a run outlasting one comparison window. The fix is a rate-based Poisson tumble, *not* a hard minimum run — a floor at `TAXIS_TUMBLE_SLEW_TIME` = 1.19 s commits a cell to 7.3 mm in a 4 mm chamber.
- Adding "% locked on" beside "% searching" is what made the regime legible. A single rate reads as pathology; the split reads as behaviour.

---

## 2026-08-02 — M8b (Presentation) — GREEN · **cells look like organisms**

**Landed.** Irregular cell silhouettes (Q17), the field diaphragm, and Q8's vertex-stage culling that pays for the extra fill. `render_view_v2.h` adds a per-cell `shape_seed`; 18 tests green, 9 goldens.

Prompted by reference photography of Astrophage under a lab scope: the renderer drew perfect circles — `RENDERING.md` §2 said so outright — and circles read as *notation* where irregular grains read as *organisms*.

**The claim that mattered was provable, not promised.** Appearance must never be able to move a measurement. Every M3 golden now pins `--morphology sphere --aperture 0`, and after the change all eight verify against the **pre-existing** goldens at **mean difference 0.0000**. So the contract bump and the Q8 cull are demonstrably neutral to the optics oracle rather than argued to be. A ninth capture on `--morphology irregular` is a must-differ pair, so if the shader mirror of `morphology.h` ever dies silently the suite says so.

**Area preservation is the load-bearing property.** An irregular cell stands for a sphere and must absorb *exactly* as much light, or the renderer stops agreeing with the physics that computed the charge. Dividing by `sqrt(1 + ½w²ΣA_k²)` — carrying the same blur weight `w`, or the area drifts back off as the cell defocuses — gives a worst-case error of **1.6e-14** over 200 seeds × 11 blur weights. Machine precision, not a tolerance.

**Gotchas.**
- **Do not ruffle the rim by modulating edge softness per angle.** It is the obvious route to the reference's frilled skirt and it renders as **starbursts** — a field of snowflakes. A radially-varying *falloff distance* is exactly what makes radial spokes. Crinkle belongs in the outline, not in the fade. Caught by looking at the output; the tests were all green.
- **Plot the pure function before blaming the pipeline.** Rendering `shape_radius` directly in 20 lines of Python showed the silhouette was already correct, which localised the bug to the rim treatment immediately instead of a hunt through the shader.
- **`git status` disagreed with `imgdiff`** after `-Generate`: all 8 goldens showed as modified while imgdiff reported mean 0.0000, max 1. That is 1-LSB raster noise. Reverted them and kept only the new golden — committing churn would make a future real change invisible in the diff.
- **`gate.ps1` rejected `M8b` twice** — first the `[int]"8b"` parse, then a `ValidatePattern` I had not noticed. Split milestones are an Iron Rule 9 affordance the gate never supported; it does now.
- ADR-017 got worse before it gets better: `shape_radius` is the **fifth** formula mirrored across the GLSL boundary. Q7's trigger is met — the next one should generate the GLSL from the header.

---

## 2026-08-02 — M8 (Taxis) — GREEN · **cells behave**

**Landed.** Run-and-tumble taxis on the culture's own self-shadowing gradient, the FEED/BREED/IDLE machine, and the emission discharge that was missing (`dE/dt = −emit_power` — nothing debited the store before M8 because nothing ever set `emit_power` nonzero). 17 tests green. **No contract change:** `taxis_memory`, `run_timer` and `co2_local` were already in `cell_store_v1.h`.

Migration **−262.6 μm = 20.3σ** against a 3σ bar, in the correct −x direction. Darkness is **bit-identical** to the taxis-off null — 0 of 2000 positions differ — because the IDLE path draws no random numbers. That was a deliberate design choice (ADR-022) and it upgrades the darkness half of the gate from a distributional claim to an exact one.

**The migration sign is the assertion, and it is meaningful because the obvious confound pushes the other way.** A mobility gradient (lit cells thrusting, dark ones not) drives net flux toward the *low*-mobility side, i.e. away from the light. Measuring −x cannot be that artifact. It does not even arise here: the far side still sees ~121 W/m², four orders above the dark threshold, so every cell stays in FEED.

**Q16 — the controller is mistuned, and the diagnostic is what found it.** A run-age readout showed **54.2 % of cells tumbling within the last 2 ticks** and a mean run age of 0.185 s against an 8 s cap, so Δ ≤ 0 terminates essentially every run and the cap almost never fires. Working out why produced a clean number: an **awake** cell holds its surface at the setpoint, so viscosity is 3.46× lower and it swims at **6105 μm/s** — it crosses the whole 4 mm chamber in **0.66 s**. `TAXIS_MEMORY_TIME` = 2 s is therefore **3.1× a full chamber crossing** and 6.3× the gradient's e-folding traversal. The cell is comparing against a baseline older than the entire gradient. Bias efficiency is 0.4 % of path length, so the headroom is large. **Criterion for the fix: τ ≲ the e-folding traversal time**, ~0.3 s here, and 0.05 s is already inside the canon range. Not retuned at M8: it is a constants decision touching ADR-005 and ADR-007, and starting one from green at session end is how a session ends red.

**Gotchas.**
- **I first estimated the swim speed with the 20 °C drag and got 1770 μm/s — 3.46× too low.** Awake cells are not at ambient viscosity; that is P4, and it applies to *thrust* as much as to Brownian motion. Any timescale argument about live cells must use `DRAG_COEFF_SETPOINT`.
- **A9 caught a `1.0e-300` guard against `log(0)`.** The fix was not a waiver but sampling from `1 − u` instead of `u`: `uniform01d` returns [0,1), so `1 − u` is (0,1] and the guard is unnecessary. No bare literal, no dead branch.
- **`test_taxis` costs 41.5 s of a 3m43s suite** — the largest single test. Kept at 10⁴ ticks anyway: it is the specified gate, and trimming a test that passes at 20σ for speed is how gates erode.
- The clamped tumble mean (63.18°, 7 % below the unclamped 68°) is **derived** in `derive.py` and asserted directly, rather than asserting 68° with a tolerance wide enough to hide the clamp.

---

## 2026-08-02 — M7 (Light) — GREEN · **all five phenomena live**

**Landed.** Petrova emission, photon thrust, the irradiance field, and occlusion. **P5 completes the set.** Komorov (T15) is exact: 1 kW × 25 min ⇒ 1.5 MJ and 16.6898 ng. Bands separated 3.31× (T20). 16 tests green.

**ADR-021 — the same structural lesson for the third time.** P5 claims *exact* zero behind a cell. The irradiance field is depth-averaged and therefore 2D, where one cell blocks only **16.8 %** of a grid column's face — a depth-averaged grid can never produce an exact zero from one occluder. That is a 3D fact about two discs.

This is precisely ADR-019 (2D grid, 3D 1/r) and ADR-020 (grid is far field, not near field) again. **When a claim is about individual bodies, the grid is the wrong instrument.** Having named the pattern at M6, I looked for it at M7 before writing code rather than after — which is the first time this build has caught one of these in advance.

So: exact per-cell shadowing over the hash neighbourhood (`disc_overlap_fraction` returns bitwise 1.0 at zero offset and bitwise 0.0 beyond 2a), plus Beer–Lambert extinction on the grid for the far field. Measured: an adjacent collinear pair leaves the rear cell at bitwise `0.0`; a pair 200 μm apart gets 0.832 transmittance, the correct single-cell far-field value; 8,000 cells lit along +x give charge-versus-depth **r = −0.879** and an 8× lit-face/far-side ratio.

**Gotchas.**
- **"Exactly zero" survives one tick, not two hundred.** Integration drifts a collinear pair apart by ~1e-13 m — enough to leave 1e-8 of the incident light. That residual is *correct*: they are no longer collinear. The exact assertion belongs on the pure function and an undrifted pair; the drifted case gets a relative bound. I had to back-solve the 1.17e-8 residual to a 0.09 pm offset to see this.
- **A per-cell 27-bucket walk in every tick of every test doubled the suite runtime** before I added the dark-chamber early-out. No source and no ambient ⇒ nothing to compute, which is also what canon says about darkness.
- **`test_hash`'s timing check flaked** when run after a heavy test — leftover GPU work inflated the mean. Switched to the floor over several batches, which is the right statistic for "how fast can this go".
- Axis-aligned light only, deliberately: a sheared sweep collides threads on shared cells and would need atomics. One thread per line owns its whole output line.

---

## 2026-08-02 — M6 (Thermal) — GREEN · **P2, P3, P4 live**

**Landed.** The thermostat. 2,000 awake cells in an insulated chamber pin the medium at a maximum of **369.56 K** against a setpoint of 369.565 — and never approach boiling. Driven externally to 400 K it relaxes back down while cell energy goes *up*. The ignition latch survives cooling to 20 °C. Motility ratio **4.357**, matching the oracle exactly. 15 tests green.

**ADR-020 — the hardest bug of the build.** A refinement that looked compelling and was completely wrong.

A cell conducts `4πka·(T_cell − T_∞)`. But the grid does not sit at `T_∞`, it sits at the near-field value 342 K — so conducting against it with the free-space coefficient *appears* to under-report the flux, and the fix *appears* to be the shell conductance `4πk/(1/a − 1/dx)`. That is exactly self-consistent on paper: substitute the analytic profile and it returns precisely `4πka·ΔT`.

It produced a **1.76 × 10⁶ K** runaway. The premise fails because a grid cell's thermal time constant is `dx²/4α` = 1.06e-4 s — *equal to the diffusion substep* — so diffusion drains it as fast as any source fills it and it never holds the near-field temperature. **The grid is the far field**; the sub-grid 1/r structure is unresolved and must not be double-counted.

The diagnostic that cracked it: the energy rate was 5.3 W against 2000 × 2.871 mW = 5.74 W — the cells were conducting at exactly the free-space rate, as if the medium were permanently cold. That number said *no feedback* rather than *wrong coefficient*, which pointed at the premise instead of the arithmetic.

**A wrong intermediate hypothesis, worth recording.** I first blamed the bilinear scatter: it spreads a deposit over four cells but reads back only `Σw²` of it (0.25 at a node), so a lumped model sees a quarter of its feedback. Switching to nearest-cell made the runaway **4× worse**, disproving it immediately — and that 4× is exactly the `Σw²` factor, so the mechanism was real and the causal claim was not. The nearest-cell pair was kept regardless: it *is* correct for a lumped exchange.

**Supporting decision.** The exchange is the exact lumped exponential `C·ΔT·(1 − exp(−G·dt/C))`, applied per diffusion substep. An explicit step deposits 188 K into one grid cell per tick and sails past boiling unaided; the exponential *approaches* the cell temperature and cannot overshoot it. That is the second law, not a clamp.

**P4's viscosity temperature was a genuine choice, settled by the oracle.** Far field 2.87×, film mean 2.38×, surface 4.36×. Only the surface reproduces `T12_MOTILITY_RATIO` = 4.357 — and it is the physically right one, since Stokes drag is set by the boundary layer at the sphere surface and an awake cell holds that surface at the setpoint.

**Gotchas.**
- **An ordinary chamber cannot starve a culture** — 500 cells warm their own medium to the setpoint within a second and stop spending. That is P2 working, but it meant the starvation test needed a perfect cold bath re-imposed every tick, not just a Dirichlet edge. Two attempts at that test failed for this reason before I understood it.
- A 1e-6 tolerance on the lumped rate failed by 5e-6 — that residual *is* the second-order term of `1 − exp(−x)`, which is the whole reason for using the exponential. Now asserted explicitly.
- Goldens survived unchanged: the golden scenario spawns dormant cells, whose drag M6 does not alter.

---

## 2026-08-02 — M5 (Fields) — GREEN

**Landed.** `Grid2D`, explicit FTCS diffusion, fixed-point deposits, tool brushes. **Gaussian spreading matches the exact 2D analytic solution to −0.00 %** (σ 100 → 391.5 μm over 0.5 s); conservation drift −0.0001 % over 10⁴ ticks; FTCS coefficient 0.2347 against the 0.25 limit.

**Two spec corrections (ADR-019).**
- **"Explicit red-black" is not a scheme.** Red-black is a Gauss-Seidel *ordering* — an implicit smoother that reads partially-updated neighbours deliberately. An explicit step must read the old value everywhere, so it needs a second buffer, not an ordering.
- **The gate asked a 2D grid to reproduce a 3D law.** `T = T∞ + ΔT·a/r` is the three-dimensional point-source profile; a depth-averaged grid is 2D, where a point source relaxes logarithmically. That 1/r law belongs to the per-cell near-field correction. Replaced with the 2D Gaussian oracle, which is stronger because it pins the diffusivity itself.

Boundary conditions measured and distinguishable: Neumann conserves exactly (350.000), Dirichlet drains to 301.03, Robin to 347.57 — Robin sitting near Neumann is right at this resolution, since `dx·h/k` ≈ 5e-4.

`fields_placeholder.cu` deleted, its ADR-008 substep `static_assert`s moved into `grid.cuh` so a resolution change stays a build break.

---

## 2026-08-02 — M4 (Neighbourhood) — GREEN

**Landed.** Spatial hash, soft-sphere contact, wall adhesion. Hash rebuild **0.110 ms** at 200k cells; neighbour query matches an O(n²) brute-force reference **exactly**; packed-cluster overlap **0.55 %**; 13 tests green.

**Three findings, all in ADR-018.**

1. **The hash is a stable radix sort, not the textbook atomicAdd counting scatter.** That scatter randomises order *within* a bucket, which sets the summation order of contact forces, which breaks INV-8 — intermittently, which is the worst way. CUB's `SortPairs` is stable and ships with the toolkit, so it costs no dependency.

2. **Forces and integrate had to be un-fused — and this one was my error.** M2 merged tick stages 5 and 6 for register reuse. Contact reads neighbours' positions from the arrays the same kernel writes, so cell *i* saw some neighbours pre-step and some post-step depending on scheduling. **2709 of 3000 positions differed between two identical runs.** `ARCHITECTURE.md` §3.4 already listed forces and integrate as separate stages, and this is precisely why. Fusing across a documented stage boundary is a correctness change, not an optimisation.

3. **Contact stiffness is stability-limited and cannot hold a fully charged cell.** The old value gave a rest overlap of **1587 % of a diameter** — cells passing straight through. But raising it far enough is impossible: an overdamped explicit spring moves `k·δ·dt/γ` per step, so stability caps `k` at `γ/dt`, while resting a 32×-water cell within 5 % needs **3.36× that**. Set `k = γ/(8·dt)`; empty cells rest at 4.17 % (inside the gate), fully charged at 134 % (outside). Bounded by a test at < 200 % so it cannot silently worsen; the fix is contact substepping or `dt ≤ 0.3 ms`, deferred to when dense charged cultures matter.

**Gotchas.**
- **Braces do not protect commas in a macro argument — only parentheses do.** The neighbour-walk macro is variadic for that reason; without it, a body containing `Vec3{a, b, c}` splits into extra arguments and fails with a wholly misleading error.
- **The benchmark was measuring a feedback equilibrium.** Under the real-time accumulator, slower frames request more substeps, which slows frames further, until it pins at the 8-substep cap. `--benchmark` now implies one tick per frame and reports a real-time factor: 200k cells run at **0.28× real time**, which a frame rate alone was hiding.
- **Goldens legitimately changed** — M4 adds a real force to the 400 ticks they capture, though no shader or optics formula was touched. Regenerated under Iron Rule 10 with ADR-018 §5 as the record.
- **Deliberately skipped the SoA reorder** the milestone called for: a determinism hazard for a speculative gain. Recorded rather than silently dropped.

---

## 2026-08-02 — M3 (Optics) — GREEN

**Landed.** The renderer is a microscope. Per-instance defocus, energy-conserving opacity, the Becke line with its polarity inversion, a condenser vignette, and a depth-of-field gauge in the HUD.

- `render/optics.h` — the model as pure host-testable functions; `test_optics` covers DOF, energy conservation, and polarity.
- `cells_pass.cpp` — shader rewritten around the blurred profile. Signed contrast, so the Becke line can render *brighter* than the field rather than only darker.
- `render/post_pass.{h,cpp}` — condenser vignette, multiply-blended fullscreen triangle, no FBO.
- `tools/imgdiff.cpp` + `scripts/goldens.ps1` — golden capture and comparison. `--no-ui` and `--focus` added so goldens depend on the renderer alone.
- 11 tests green, 8 goldens.

**Rendering is bit-exact** on a fixed driver (mean 0.0000, max 0 immediately after generation), so tolerances are tight enough to catch a **2 μm focus change at 100×**.

**ADR-017 — the golden suite needed a second half.** A golden suite proves the renderer is *stable*, not that it *does anything*: a shader ignoring the focal plane entirely would pass one forever. So `goldens.ps1` also asserts specific pairs must **differ**. The sharpest is focus **+2 vs −2** at 100×: identical `|dz|`, therefore identical blur radius and peak opacity, differing only in sign. If the polarity inversion were dropped they would be byte-identical. That turns a by-eye feature into a headless test (measured: mean 9.8/255 across 21.6 % of pixels).

**Gotchas.**
- **I had written a false claim into `optics.h`** — that sedimentation concentrates cells into a focal plane, so racking onto the settled layer would bring the culture sharp. It does not. Gravity is along −y (ADR-006), so cells pile against a *side wall* while their `z` stays uniformly spread. Only 2.5 % of the chamber is ever in focus at 40×. Comment corrected; the claim would have misled whoever built on it.
- **Two `test_optics` thresholds were invented rather than derived** (`r > 4a`, `peak < 0.06`) and failed at the true values 3.9a and 0.0617. Replaced with assertions on the derived quantities — the blur is `dz·NA/n` and the opacity follows from energy conservation — plus loose qualitative bounds. Guessing a threshold and then discovering the physics disagrees is the wrong order.
- **Energy conservation is what makes blur read as blur.** Without the `(a/R_eff)²` falloff a defocused cell stays jet black and merely grows, which looks like fog.
- Defocus costs fill rate, not shader complexity: 795 → 426 fps at 200k cells. Bloom at M7 lands on top of that; the first lever is vertex-stage culling of near-invisible cells.
- Range-`for` over a braced list needs `<initializer_list>` under MSVC.

---

## 2026-08-02 — M2 (Motion) — GREEN

**Landed.** Cells move, and **P1 is real**: an empty cell (40 kg/m³, 0.04× water) rises and packs against the ceiling; a charged one (6415 kg/m³, 6.4× water) sinks to the floor; at 3.006 % they hang suspended. Drift velocity is linear in charge to **Pearson −1.000000**, zero crossing at **3.00577 %** vs a canon-derived 3.00577 %.

- `sim/integrator.{cuh,cu}` — exact joint OU propagator, buoyant weight, photon thrust, three boundary modes. All pure `__host__ __device__`, so `test_motion` runs the real code on the host.
- `world.motion` config, stages 2/5/6 wired into `world_step`. Live charge slider with a density/buoyancy readout.
- `--ticks-per-frame` decouples capture from the wall clock, which M3's goldens need.
- **Q3 closed**: `tools/headless` now drives the real `World`, so the determinism gate finally covers the integrator instead of a Brownian stand-in. It also now asserts that halving the population changes the hash — catching a hash that silently covers nothing.
- 10 tests green.

**Two corrections, both caught by the oracle before code shipped.**
- **ADR-016.** The integrator my own spec called for — propagate velocity exactly, then `r += v·dt` — gives **47× too much diffusion** for an empty cell, because velocity fully decorrelates within one step at `dt/τ = 4497`. Replaced with the exact joint position–velocity propagator (correlated 2×2 noise). Verified: `σ²_rr → 2D·dt` to four significant figures. This was found by arithmetic against `VERIFICATION.md`, which is exactly what the oracle is for.
- **The oracle and the simulator were using different viscosity models** — tabulated 20 °C vs Vogel–Fulcher — leaving a 2.5e-5 systematic offset that tolerances were absorbing. Unified on VF (the simulator has no choice; it needs the temperature dependence for P4). Tabulated values stay as cross-checks *on* the fit, which is their proper job. Also corrected `WATER_VISCOSITY_96C` (was 2.98e-4, real value ≈ 2.931e-4).

**Gotchas.**
- **T14's statistic was wrong, and fixing it made the gate stricter.** A whole-population position correlation caps near 0.84 for Pearson *and* Spearman. My first guess (wall saturation) was wrong — Spearman barely moved. The real cause: cells within a hair of neutral have near-zero drift and never leave their spawn point, contributing pure noise. That is correct physics. T14 now tests drift *velocity* vs charge, which is the sharp claim and immune to initial conditions.
- `ou_position_shape` needs a series branch below `x ≈ 1e-2`; the direct form cancels its first three orders exactly and returns noise. Both branches pinned.
- "Reflecting" boundaries mean *rest*, not bounce — at Re ≪ 1 there is no inertia to rebound with.

---

## 2026-08-02 — M1 (Cell store & first pixels) — GREEN

**Landed.** The simulator draws. 200,000 cells in one instanced draw at ~795 fps on the RTX 4070 Ti SUPER (target 144), zero GL debug errors.

- **`sim`**: `cell_store.{cuh,cu}` — one carved device blob rather than 25 allocations; spawn kernels (uniform/gaussian/grid/disc) with per-cell PCG32 streams; capacity enforcement. `world.cuh` + `step.cu` carry the tick sequence as an ordered comment list so each milestone inserts at its documented position.
- **`render`**: GL 4.6 + ImGui bootstrap, CUDA-GL interop writing `CellInstance` straight into a GL VBO (positions never touch host memory), instanced SDF disc pass, header-only `Camera` with cursor-anchored zoom.
- **`ui`**: scope panel, population controls, scale bar. Pending controls are *labelled* pending rather than silently inert.
- **`app`**: fixed-tick accumulator, pan/zoom, PPM screenshot, and the `--benchmark` path the gate drives.
- **+3 tests** (`test_cell_store`, `test_scope`, `test_octahedral`), 8 total, all green.

**Pending.** M2 (motion). `world_stats` returns only tick/time/counts; the means and the energy ledger need the M6 device reduction.

**Gotchas.**
- **`project()` must enable `C`.** GLFW and GLAD are C libraries; without it CMake fails at *generate* time with "required internal CMake variable not set: CMAKE_C_COMPILE_OBJECT", which points at nothing useful.
- **`<glad/gl.h>` must precede `<cuda_gl_interop.h>`** — the CUDA header uses `GLuint`/`GLenum` without declaring them and produces 15 errors about "variable GLuint is not a type name".
- **The gate had a real bug**: `M0.2` does a clean build, and without `-App` that reconfigure sets `ASTRO_BUILD_APP=OFF` and deletes the executable `M1.1` then looks for. Gates that build must know which targets later checks need.
- **200k cells was the wrong default** and the render was right. It is ~11 % of the chamber by volume but ~98 % *projected*, because the scope looks through the whole 60 μm slab — a solid black field. `DEFAULT_CELLS` is now 25,000, `BENCH_CELLS` stays 200,000. ADR-015.
- **The audit caught a 2π literal in `cell_store.cu`** (Iron Rule 3 working as intended), and while fixing it I found `293.15` had slipped past the regex. Added `AMBIENT_TEMP_DEFAULT` to canon, `PI`/`TWO_PI` to `core/units.h` (maths constants are not canon), and taught A9 a third pattern.
- Two `test_scope` assertions failed on first run and **both were my test's fault, not the code's** — but one exposed a genuine gap: at high zoom the field is narrower than a cell and the scale-bar snap table bottomed out at 1 μm. Extended down to 0.1 μm, which the 100× objective's 268 nm resolution makes meaningful anyway.

---

## 2026-08-02 — M0 (Harness) — GREEN

**Landed.** Whole repo from scratch. Stack chosen: C++20 + CUDA 13.1 + CMake/Ninja, sm_89, static runtimes (ADR-012, superseding an earlier TypeScript/WebGL draft now archived in `_brainstorm/`).

- **Generated canon.** `scripts/canon.py` is the single source of every physical number; `scripts/derive.py` emits `src/core/canon_generated.h`, `tests/golden/expected_values.h`, and `docs/VERIFICATION.md`. Idempotent, `--check` mode wired into the audit.
- **Docs system** sized for context-bounded sessions: `CLAUDE.md` + `ARCHITECTURE` + `PHYSICS` + `RENDERING` + `MILESTONES` (M0–M12) + `DECISIONS` (14 ADRs) + `SCENARIOS` + generated `VERIFICATION`.
- **Six frozen contracts** in `contracts/`, so a session can work one module without reading another's source.
- **`core`**: `units.h` (ASTRO_HD host/device bridge), `rng.cuh` (PCG32 per-cell streams), `vec.cuh`, `fixed_atomic.cuh`, `result.h`.
- **Harness**: `build.ps1` (finds VS-bundled Ninja, imports vcvars, falls back to the VS generator), `audit.ps1` (10 checks), `gate.ps1` (M0–M12, each re-running all earlier gates).
- **5 tests green**, plus 7 audit invariant checks.

**Pending.** Everything from M1 on. `src/render`, `src/ui`, `src/app` are `MODULE.md` only.

**Open questions.** Q1 app `--headless` vs `tools/headless` code path; Q2 octahedral direction encoding still a stub. Both in `_run_state/NEXT_SESSION.md`.

**Gotchas.**
- Two tests failed on first run and both were the oracle doing its job, not bad tests. (a) The CO₂ deposit scale genuinely overflowed int64 — the exact silent bug ADR-013 exists to prevent. Fixed by bounding contributors **per grid cell** rather than by `MAX_CELLS` (2e6 cells cannot occupy one 7.8 μm grid cell), now backed by `static_assert` in `fields_v1.h`. (b) A canon-count assertion was simply wrong; replaced with a stronger check that the *specific* parameters Weir wrote carry the lock, and that invented ones do not masquerade as canon.
- MSVC reports an unknown type in a member declaration as `C3646: unknown override specifier`. The real cause was a missing include of `snapshot_v1.h`. Worth remembering — the error names the wrong thing entirely.
- `ninja` is not on PATH but VS 2022 bundles it; `build.ps1` locates it and imports the MSVC environment itself.
