# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Three open arcs, all branched off `m12e-green`.** Believe `git tag --list`.

- **The presentation arc (M14). Last green: `m14a-green`.** `--demo` is the living-screensaver: it cycles a
  playlist of the self-driving scenarios (ignition → the 3% line → bloom → predation/selection → shadows)
  with camera + view-mode choreography, looping. Honest — each act IS a scenario that drives itself; the demo
  only cycles which plays and eases the scope zoom. ADR-042. **Next: M14b** (view cross-fades via
  `render_view_v2` `mode_blend`, a caption overlay, an idle-input trigger for a *true* screensaver, and
  interaction-actor acts — e.g. the M13b light-leash herding on a loop).
- **The interaction arc (M13). Last green: `m13b-green`.** Right-drag pans, left drives the tool. M13a =
  Heat/Chill/CO₂/N₂ brushes (poke to ignite). M13b = the light-leash (drag a spotlight, cells herd) + optical
  tweezers (grab + tow a cell). ADR-040, ADR-041. **Next: M13c** (record interactions to the snapshot ring) —
  *optional*.
- **The ship line (M12). Last green: `m12e-green`.** Snapshot/replay + scrubber + Taumoeba render + tolerance
  colour + perf all done. **Remaining: M12f** (the render remainder — the `render_view_v3`→`scenario_v3`
  cascade, bloom, cross-fade, T-field) and **M12g** (package → `v1.0`).

Pick any. 32 tests, 12 goldens, 42 ADRs. (M13/M14 gates re-run M0..M13b but not the unbuilt M12f/g.)

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M14a
```

Then `CONTINUATION_PROMPT.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M14b (finish the screensaver)** — the natural continuation, user-loved. `src/app/application.cpp`
  (`DEMO_PLAYLIST`, `load_act`, `demo_update` — the act engine to extend), `contracts/render_view_v2.h`
  (`ScopeState.mode_blend` / `mode_blend_to` already exist — drive them for cross-fades), `src/ui/hud.cpp`
  (a caption overlay like `draw_scale_bar`). An interaction-actor act reuses `apply_light`/`apply_grab` to
  herd/tow on a loop (mind the M13b thermal-density note — keep the herded pile modest).
- **M12f (render remainder)** — plan the multi-contract change FIRST: the `render_view_v3` bump (per-cell
  `temp_c` for pre-ignition Thermal-IR) cascades into `scenario_v3` because `scenario_v2.h` includes
  `render_view_v2.h` and no TU may include two contract versions. High goldens risk.
- **M13c (record interactions)** — small; record poke/light/grab events alongside the M12d ring.

## Loose ends (non-blocking)

- **M13a + M13b + M14a are unpushed** (`git push origin main` + `--tags` when ready — remote is
  `bochen2029-pixel/astrophage-microscope`).
- **Thermal-density gotcha (M13b):** herding a LARGE culture (~2000+ cells) into a tight pile drives the
  explicit thermal solver negative — extreme local density overruns its fixed substep budget (an ADR-008-class
  limit, pre-existing, NOT the light code; awake+no-light is stable). A substep-vs-density guard would fix it;
  until then any interaction-actor act (M14b) must keep the herded pile modest.
- **Demo caveats (ADR-042):** the interop is sized at init to the playlist max, so runtime enable from a
  non-demo start stays out (a normal run's buffer may be too small for taumoeba). `cells_pass.capacity` shows
  the max during a demo (cosmetic). The scrubber ring is off under `--demo`.
- The light spot / optical trap are NOT serialised (transient interaction state; ADR-036/041).
- The M12 ship loose ends still stand (render_view_v3→scenario_v3 cascade; snapshot has no
  next_taumoeba_id/motion, ADR-036; scenario `param_overrides` unapplied, ADR-035).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
