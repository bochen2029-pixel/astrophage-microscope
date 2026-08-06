# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep, self-contained
> immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps): read it to arrive
> *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md) for the bootstrap
> ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**`v1.0` is SHIPPED. The ship line is complete.** Believe `git tag --list`.

- **The ship line (M12) -> `v1.0`. DONE.** Latest tag: **`v1.0`** (== `m12j-green`). Snapshot/scrubber,
  perf, render legibility, the whole render remainder (M12f cross-fade / M12g pre-ignition warm-up / M12h
  bloom / M12i T-field), and M12j packaging. `scripts/package.ps1` builds a self-contained
  `dist/astrophage-<ver>.zip` (static exe + scenarios + docs) that runs on a scrubbed-PATH clean machine.
- **The presentation arc (M14). Last green: `m14b-green`.** The `--demo` living screensaver. **Next: M14c**
  (view cross-fades + a cold-start trigger) -- fully unblocked; M12f's `mode_blend` is the cross-fade.
- **The interaction arc (M13). Last green: `m13b-green`.** Brushes + light-leash + tweezers. **Next: M13c**
  (record interactions to the snapshot ring) -- *optional*.

**Everything green: 32 tests, 12 goldens, 45 ADRs, M0..M12j + M13a/b + M14a/b all tagged and pushed.**

## What's left (all POST-1.0, all optional)

The project met its goal at `v1.0`. Remaining work is polish, not completion:

- **M14c** -- view cross-fades on a loop + a true cold-start screensaver trigger (the crowd-pleaser).
- **M13c** -- record poke/light/grab interactions into the M12d snapshot ring.
- **Small polish:** a HUD toggle + intensity slider for bloom (`application.cpp` hardcodes 2.0) and the
  T-field range (hardcodes 0-100 C); the CSV `git_describe` header field is still a placeholder for the
  build to inject; a scenario-adaptive T-field normalization range.

## Start here

```bash
git -C C:\Astrophage tag --list          # v1.0 is the top of the M12 line
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12j
```

Package a fresh build: `powershell -File scripts/package.ps1` -> `dist/astrophage-<ver>.zip`.

## Loose ends (non-blocking)

- **Everything is pushed through `v1.0`** (remote `origin` = github.com/bochen2029-pixel/astrophage-microscope).
  Ask Bo before pushing future work.
- **Scenario resolution:** `application.cpp` uses `scenarios_beside_exe()` (`src/app/exe_path.cpp`, kept
  clear of CUDA headers so `<windows.h>` doesn't trip /WX): `<exe_dir>/scenarios` if present (packaged),
  else the compile-time `ASTRO_SCENARIOS_DIR` (dev tree). Do NOT redefine NOMINMAX (it is on the command
  line project-wide; C4005 is fatal under /WX).
- **Render toggles:** `--no-bloom` (M12h) and `--no-field` (M12i) fall back to the pre-feature look;
  goldens pin `--no-bloom` and capture the T-field. `--gl-debug` + `--screenshot` together emit one benign
  glReadPixels warning; gates never combine them.
- **Golden tolerance:** a full `goldens.ps1 -Generate` rewrites the m3_* oracles by a sub-tolerance ULP
  (M12f `pm/apre` round-trip; within M3.2 tolerance). For a real golden change, revert the spurious m3_*
  and commit only the intended one (as M12i did for m7b_thermal_awake).
- **Thermal-density gotcha (M13b):** herding a LARGE awake culture (~2000+) into a pile blows up the
  explicit thermal solver; 1000 cells is stable (gates use 1000).
- The M12 ship loose ends stand (snapshot has no next_taumoeba_id/motion, ADR-036; scenario
  `param_overrides` unapplied, ADR-035). Demo caveats: interop sized at init (ADR-042).
