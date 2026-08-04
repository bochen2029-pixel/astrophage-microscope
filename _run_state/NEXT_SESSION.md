# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Two open arcs off `m12e-green`, plus a fresh backlog milestone.** Believe `git tag --list`.

- **The interaction arc (M13). Last green: `m13b-green`.** Direct mouse manipulation is complete through
  M13b: right-drag pans, left drives the active tool. M13a = the Heat/Chill/CO₂/N₂ field brushes (poke to
  ignite). M13b = the **light-leash** (drag a Light spotlight; awake sub-0.95-charge cells herd up its
  irradiance gradient, emergent) + **optical tweezers** (Grab a cell; a real harmonic trap tows it against
  buoyancy). ADR-040, ADR-041. **Next: M13c** (record interactions to the snapshot ring so a session
  replays) — *optional*.
- **The ship line (M12). Last green: `m12e-green`.** Snapshot/replay + scrubber + Taumoeba render +
  tolerance colour + perf all done. **Remaining: M12f** (the render remainder — the
  `render_view_v3`→`scenario_v3` cascade, bloom, cross-fade, T-field) and **M12g** (package → `v1.0`).
- **NEW — M14 (demo mode). Not started.** Bo asked (2026-08-03) for a looping **screensaver / attract mode**
  that shows the cells "alive" (Conway's Life as the *feeling*; honest physics as the mechanism). Speced as
  **M14a** (act engine + `--demo` loop, reusing the `--auto-poke`/`--auto-light`/`--auto-grab` stand-ins as
  live actors) + **M14b** (view cross-fades + idle-trigger). See `MILESTONES.md`.

Pick any. 32 tests, 12 goldens, 41 ADRs. (M13's gate re-runs M0..M12e but not the unbuilt M12f/g, ADR-040.)

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M13b
```

Then `CONTINUATION_PROMPT.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M14 (demo mode)** — the freshest, user-requested. `src/app/application.cpp` (the tick loop + the
  `--auto-*` stand-ins are your live actors), `src/ui/hud.h` (`HudState` for a demo toggle),
  `render/camera.h` (keyframe pan/zoom/focus), `render_view_v2.h` (`mode_blend` for cross-fades). Start with
  **M14a**: a playlist of acts (scenario + duration + camera track) and a `--demo` loop; default-off so every
  gate is unmoved. The interaction stand-ins already let the demo poke/herd/tow its own culture honestly.
- **M12f (render remainder)** — plan the multi-contract change FIRST: the `render_view_v3` bump (per-cell
  `temp_c` for pre-ignition Thermal-IR) cascades into `scenario_v3` because `scenario_v2.h` includes
  `render_view_v2.h` and no TU may include two contract versions. High goldens risk.
- **M13c (record interactions)** — small; record poke/light/grab events alongside the M12d ring.

## Loose ends (non-blocking)

- **M13a + M13b are unpushed** (`git push origin main` + `--tags` when ready — remote is
  `bochen2029-pixel/astrophage-microscope`).
- **Thermal-density gotcha (M13b):** herding a LARGE culture (~2000+ cells) into a tight pile drives the
  explicit thermal solver negative — extreme local cell density overruns its fixed substep budget (an
  ADR-008-class limit, pre-existing, NOT the light code; awake+no-light is stable). The `--auto-light` gate
  uses 1000 cells, below the threshold. A substep-vs-density guard would let a user over-herd safely; a good
  M14/M13c-adjacent fix.
- The light spot / optical trap are NOT serialised (transient interaction state, like the M13a poke;
  ADR-036/041), so a mid-grab snapshot restores un-grabbed. Fine — the caller re-applies interaction.
- The M12 ship loose ends still stand (render_view_v3→scenario_v3 cascade for M12f; snapshot has no
  next_taumoeba_id/motion, ADR-036; scenario `param_overrides` unapplied, ADR-035).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
