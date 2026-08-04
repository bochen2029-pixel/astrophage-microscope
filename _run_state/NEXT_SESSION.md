# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**Two open arcs, both branched from `m12e-green`.** Believe `git tag --list`.

- **The interaction arc (M13). Last green: `m13a-green`.** Direct mouse manipulation: a Tools palette,
  **right-drag pans / left drives the active tool**, and the Heat/Chill/CO₂/N₂ brushes — heat the slide
  and it ignites (emergent, honest). **Next: M13b** (the light-leash + optical tweezers).
- **The ship line (M12). Last green: `m12e-green`.** Snapshot/replay + scrubber + Taumoeba render +
  tolerance colour + perf all done. **Remaining: M12f** (the render remainder — the
  `render_view_v3`→`scenario_v3` cascade, bloom, cross-fade, T-field) and **M12g** (package → `v1.0`).

Pick either arc. 32 tests, 12 goldens, 40 ADRs. (M13's gate re-runs M0..M12e but not the unbuilt
M12f/g, ADR-040.)

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M13a
```

Then `CONTINUATION_PROMPT.md`, the **M13b** (or **M12f**) section of `docs/MILESTONES.md`. For M13b:
`src/app/application.cpp` (`handle_input`, `apply_poke`, the picking + forces plumbing),
`contracts/render_view_v2.h` (`LightSource`), `src/sim/world.cuh` (the `d_fx/fy/fz` force scratch,
stage 5), and ADR-040 (the interaction model to extend).

## What M13b is

1. **The light-leash.** A Light tool that drags `World::light` to the cursor's chamber point each tick
   (the irradiance stage already rebuilds the field from it, M7). Awake cells phototax toward it and
   **follow the cursor like a laser pointer** — emergent herding (P4 + taxis). Mostly wiring; add a
   `--auto-light` headless stand-in and verify the culture's centroid tracks the light.
2. **Optical tweezers.** Grab the picked cell and drag it: a **spring force toward the cursor**, a new
   `World` trap field `{trapped_slot, target_x, target_y, stiffness}` the forces kernel (stage 5,
   `integrator.cu`) reads and adds to `d_fx/d_fy`. Release resumes physics. Honest (a real optical
   trap). Consider focal-plane coupling: only grab in-focus cells. Add a headless scripted grab
   (`--auto-grab slot x_um y_um`) and verify the cell reaches the target.

**Gate.** M13a gate + `--auto-light` herds + `--auto-grab` moves a cell, both headless + a screenshot.

## Loose ends (non-blocking)

- Heat rate is tuned by feel (~2.5 K/tick × strength, 180 µm); a user slider adjusts it. The brush is
  local — read `max_temp`, not the mean. `--auto-poke` pokes the chamber centre only.
- The M12 ship-line loose ends still stand (render_view_v3→scenario_v3 cascade for M12f; snapshot
  has no next_taumoeba_id/motion, ADR-036; `param_overrides` unapplied, ADR-035).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; gitignored-adjacent).
