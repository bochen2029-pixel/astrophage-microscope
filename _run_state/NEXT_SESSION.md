# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Three open arcs, all branched off `m12e-green`.** Believe `git tag --list`.

- **The presentation arc (M14). Last green: `m14b-green`.** M14a = the `--demo` living-screensaver:
  it cycles a playlist of self-driving scenarios (ignition -> the 3% line -> bloom -> predation ->
  shadows) with camera + view choreography, looping. M14b made it *read* as finished: a per-act
  **caption** overlay (`draw_demo_caption`), scope **drift** (a slow pan, not just zoom), **idle-aware
  auto-advance** (mouse input holds the current act so you can look or use the tools; 2.5 s of quiet
  resumes -- headless has no input so it always advances, the gate path), and a 6th **"Herding" act**
  (`demo-herd.json`, thermal-off) that runs the M13b light-leash on autopilot (awake cells chase a wide
  spot the demo circles, via the HUD light state so `apply_light` parks it at a tick boundary). ADR-042.
  **Next: M14c** (view cross-fades + a true cold-start screensaver trigger) -- but it **waits on M12f**:
  cross-fades need the `render_view_v2` `mode_blend` wired through the cells shader (M12f render work),
  and the cold-start trigger needs runtime demo enable/disable (the interop is sized at init today).
- **The interaction arc (M13). Last green: `m13b-green`.** Right-drag pans, left drives the tool. M13a =
  Heat/Chill/CO2/N2 brushes (poke to ignite). M13b = the light-leash (drag a spotlight, cells herd) +
  optical tweezers (grab + tow a cell). ADR-040, ADR-041. **Next: M13c** (record interactions to the
  snapshot ring) -- *optional*.
- **The ship line (M12). Last green: `m12e-green`.** Snapshot/replay + scrubber + Taumoeba render +
  tolerance colour + perf all done. **Remaining: M12f** (the render remainder -- the
  `render_view_v3`->`scenario_v3` cascade, bloom, cross-fade, T-field) and **M12g** (package -> `v1.0`).

Pick any. 32 tests, 12 goldens, 42 ADRs. (M14 gates re-run M0..M14b but not the unbuilt M12f/g.)

**Recommended next: M12f.** It advances the ship line toward `v1.0` *and* unblocks M14c's cross-fades,
so it is the highest-leverage move. M14c is the crowd-pleaser but is gated on M12f; do it after.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M14b
```

Then `CONTINUATION_PROMPT.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M12f (render remainder, RECOMMENDED)** -- plan the multi-contract change FIRST: the `render_view_v3`
  bump (per-cell `temp_c` for pre-ignition Thermal-IR) cascades into `scenario_v3` because
  `scenario_v2.h` includes `render_view_v2.h` and no TU may include two contract versions. High goldens
  risk. Unblocks M14c. Load `docs/RENDERING.md` + `contracts/render_view_v2.h` + `src/render/`.
- **M14c (finish the screensaver)** -- do *after* M12f. Cross-fades drive the `render_view_v2`
  `mode_blend` (already exists) through the cells shader (M12f wires it); the cold-start trigger needs
  runtime demo enable/disable. Act engine to extend lives in `src/app/application.cpp`
  (`DEMO_PLAYLIST`, `load_act`, `demo_update`); caption is `draw_demo_caption` in `src/ui/hud.cpp`.
- **M12g (package -> v1.0)** -- after M12f. Clean-machine `.zip`, user guide, tag `v1.0`.
- **M13c (record interactions)** -- small; record poke/light/grab events alongside the M12d ring.

## Loose ends (non-blocking)

- **M13a + M13b + M14a + M14b are all unpushed** (`git push origin main` + `--tags` when ready --
  remote is `origin` = github.com/bochen2029-pixel/astrophage-microscope). Ask Bo before pushing.
- **Thermal-density gotcha (M13b):** herding a LARGE culture (~2000+ cells) into a tight pile drives the
  explicit thermal solver negative -- extreme local density overruns its fixed substep budget (an
  ADR-008-class limit, pre-existing, NOT the light code; awake+no-light is stable). M14b's herd act
  sidesteps it (`demo-herd.json` is thermal-off + moderate count); any future interaction-actor act must
  keep the pile modest or thermal-off. A substep-vs-density guard would fix it properly.
- **Demo caveats (ADR-042):** the interop is sized at init to the playlist max, so runtime enable from a
  non-demo start stays out (this is the M14c cold-start-trigger blocker). `cells_pass.capacity` shows the
  max during a demo (cosmetic). The scrubber ring is off under `--demo`. The light spot / optical trap
  are NOT serialised (transient interaction state; ADR-036/041).
- The M12 ship loose ends still stand (`render_view_v3`->`scenario_v3` cascade; snapshot has no
  next_taumoeba_id/motion, ADR-036; scenario `param_overrides` unapplied, ADR-035).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
