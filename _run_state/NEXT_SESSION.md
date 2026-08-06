# NEXT SESSION — cold start

**Rewritten at the end of every session.** If this file disagrees with `git tag --list`, believe the tags.

> **New session? Read [`ONBOARDING.md`](ONBOARDING.md) FIRST — in full.** It is the deep,
> self-contained immersion brief (the gist, the intent, the hard-won wisdom, the state, the traps):
> read it to arrive *warm* before touching anything. Then [`CONTINUATION_PROMPT.md`](CONTINUATION_PROMPT.md)
> for the bootstrap ritual + full meta-lessons. This file is the one-screen "you are here".

## Where the build stands

**The render remainder is COMPLETE. One milestone from `v1.0`.** Believe `git tag --list`.

- **The ship line (M12) -> v1.0. Last green: `m12i-green`. The render remainder is DONE** (M12f/g/h/i):
  **M12f** view cross-fade; **M12g** `render_view_v3` + pre-ignition warm-up (ADR-043); **M12h** bloom over
  the Petrova emission from a separate emission buffer (ADR-044); **M12i** the real T-field false-colour
  behind Thermal IR (ADR-045). **Remaining: M12j** -- package to a clean-machine `.zip`, the user guide,
  `README` finalisation, CSV `git_describe` injection, then tag **`v1.0`**.
- **The presentation arc (M14). Last green: `m14b-green`.** The living-screensaver demo. **Next: M14c**
  (view cross-fades + a cold-start trigger) -- now fully unblocked: M12f's `mode_blend` shader path is the
  cross-fade, and the render is complete.
- **The interaction arc (M13). Last green: `m13b-green`.** Brushes + light-leash + tweezers. **Next: M13c**
  (record interactions to the snapshot ring) -- *optional*.

Pick any. 32 tests, 12 goldens, **45 ADRs**. (M13/M14 gates re-run M0..M14b but NOT M12f+, which is scoped
to the M12 ship line only.)

**Recommended next: M12j -- ship `v1.0`.** The render is done; only packaging stands between here and the
first release.

## Start here

```bash
git -C C:\Astrophage tag --list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M12i
```

Then `CONTINUATION_PROMPT.md`, `M12F_PLAN.md`, and the chosen milestone's section of `docs/MILESTONES.md`.

- **M12j (package -> v1.0, RECOMMENDED)** -- `scripts/package.ps1` (does NOT exist; build it): a
  static-runtime `.zip` that runs on a scrubbed-PATH clean machine, the user guide, `README` finalisation,
  and the CSV `git_describe` header injection (currently a placeholder). The M12j gate is scoped to the M12
  ship line only (`$n -eq 12 -and $suffix -ge 'j'`) and already exists in `gate.ps1`, calling
  `package.ps1 -Verify`. Tag `v1.0` on green.
- **M14c** -- the crowd-pleaser; the render is complete so nothing blocks it now.
- **M13c** -- small; record poke/light/grab events alongside the M12d ring.

## Render pipeline note (post-M12i)

The renderer now has **two texture paths**, both reusable for future overlays (the CO2/N2/irradiance field
overlays in RENDERING.md Sec 4 would copy the field idiom):
- **`bloom.cpp`** (M12h): an FBO the Astrophage are re-drawn into (`cells_pass_draw` with `count =
  cell_count`, Taumoeba excluded), mip-blurred, additively composited. The first FBO.
- **`field_pass.cpp`** (M12i): the app `grid_download`s a field to a host buffer and hands render a raw
  `float*`; the pass uploads an R32F texture and samples it camera-mapped through a LUT. `cells_pass_draw`
  takes `clear=false` so a background pass can own the clear.

## Contracts state

Live contracts are **`render_view_v3.h`** + **`scenario_v3.h`** (v1/v2 frozen). `CellInstance` is 40 bytes.

## Loose ends (non-blocking)

- **Everything is pushed through `m12i-green`** (remote `origin` =
  github.com/bochen2029-pixel/astrophage-microscope). Ask Bo before pushing future work.
- **Golden tolerance:** a full `goldens.ps1 -Generate` rewrites the m3_* Brightfield oracles by a
  sub-tolerance ULP (the M12f cross-fade `pm/apre` round-trip; within M3.2 tolerance, so every gate
  passes). When regenerating for a REAL golden change, revert the spurious m3_* and commit only the
  intended golden -- as M12i did for m7b_thermal_awake.
- **Render toggles:** `--no-bloom` (M12h) and `--no-field` (M12i) fall back to the pre-feature look;
  goldens pin `--no-bloom` but capture the T-field (M12i's golden moved). Bloom intensity (2.0) and the
  T-field range (0-100 C) are hardcoded in `application.cpp`; HUD toggles/sliders are a nice future tweak.
- **`--gl-debug` + `--screenshot` together emit one benign glReadPixels warning** (pre-existing). Gates
  never combine them.
- **Thermal-density gotcha (M13b):** herding a LARGE awake culture (~2000+ cells) into a tight pile blows
  up the explicit thermal solver; 1000 cells is stable (the M12h gate uses 1000). Keep piles modest.
- Other M12 loose ends stand (snapshot has no next_taumoeba_id/motion, ADR-036; scenario `param_overrides`
  unapplied, ADR-035). Demo caveats: interop sized at init (ADR-042).
- A stray `carlquist_MASTER_v2.pdf` sits untracked in the repo root (not ours; leave it).
