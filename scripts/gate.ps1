<#
.SYNOPSIS
  Milestone completion gate. Exit 0 means the milestone is DONE.

.DESCRIPTION
  Iron Rule 1: a milestone is done only when this exits 0. Green -> tag m<N>-green.

  Every gate re-runs all earlier gates, so a regression in M2 fails the M7 gate.
  Gates never weaken: if a gate seems wrong, fix it with an ADR in
  docs/DECISIONS.md -- never relax a threshold to pass.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gate.ps1 -Milestone M0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    # Trailing letter accepts split milestones (M5a/M5b, M8b) -- Iron Rule 9.
    [ValidatePattern('^M(1[0-4]|[0-9])[a-z]?$')]
    [string]$Milestone,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$failures = @()

function Gate {
    param([string]$Id, [string]$What, [scriptblock]$Body)
    Write-Host "  [$Id] $What" -NoNewline
    try {
        $r = & $Body
        if ($r -eq $false) { $script:failures += "$Id $What"; Write-Host '  FAIL' -ForegroundColor Red }
        else { Write-Host '  ok' -ForegroundColor Green }
    } catch {
        $script:failures += "$Id $What -- $_"
        Write-Host "  FAIL ($_)" -ForegroundColor Red
    }
}

function Find-Exe([string]$name) {
    $e = Get-ChildItem $build -Filter "$name.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($e) { return $e.FullName }
    return $null
}

function Run-Test([string]$testName) {
    & ctest --test-dir $build -R "^$testName$" --output-on-failure *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Milestones may be split (M5a/M5b, M8b). The trailing letter selects the extra
# checks; the number selects which earlier gates re-run.
if ($Milestone -notmatch '^[Mm](\d+)([a-z]?)$') {
    Write-Host "[gate] unrecognised milestone '$Milestone' (expected e.g. M7 or M8b)" -ForegroundColor Red
    exit 2
}
$n = [int]$Matches[1]
$suffix = $Matches[2]
Write-Host "[gate] $Milestone (re-running gates M0..$Milestone)" -ForegroundColor Cyan

# ---------------------------------------------------------------- M0: harness
Gate 'M0.1' 'canon artifacts fresh' {
    & python (Join-Path $root 'scripts\derive.py') --check *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}
if (-not $SkipBuild) {
    Gate 'M0.2' 'clean build, warnings as errors' {
        # The app target exists from M1 on. Without -App the clean reconfigure
        # sets ASTRO_BUILD_APP=OFF and deletes the very executable the M1 checks
        # below are about to look for.
        $buildArgs = @('-Clean')
        if ($n -ge 1) { $buildArgs += '-App' }
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $root 'scripts\build.ps1') @buildArgs *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}
Gate 'M0.3' 'ctest all green' {
    & ctest --test-dir $build --output-on-failure *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}
Gate 'M0.4' 'determinism replay + seed sensitivity (INV-8)' {
    $exe = Find-Exe 'headless'
    if (-not $exe) { return $false }
    & $exe --ticks 10000 --seed 20260802 --assert-deterministic *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}
Gate 'M0.5' 'invariants + inventory (audit A5-A10)' {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\audit.ps1') -SkipBuild -Quiet *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ------------------------------------------------------- M1: store and pixels
if ($n -ge 1) {
    Gate 'M1.1' 'app target builds' { return [bool](Find-Exe 'astrophage') }
    Gate 'M1.2' 'cell store: spawn, INV-1 streams, capacity' { return (Run-Test 'test_cell_store') }
    Gate 'M1.3' 'scope: scale bar at 3 objectives, true cell size' { return (Run-Test 'test_scope') }
    Gate 'M1.4' 'direction packing round trip' { return (Run-Test 'test_octahedral') }
    Gate 'M1.5' 'render BENCH_CELLS at target fps' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        & $exe --benchmark --cells 200000 --frames 600 --headless *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    Gate 'M1.6' 'zero GL debug errors' {
        $exe = Find-Exe 'astrophage'
        & $exe --gl-debug --frames 60 --headless *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# --------------------------------------------------------------- M2: motion
if ($n -ge 2) {
    Gate 'M2.1' 'analytic physics oracle (T1-T4, T6, T8)' { return (Run-Test 'test_motion') }
    Gate 'M2.2' 'P1 charge/height sorting (T14)'          { return (Run-Test 'test_buoyancy') }
}

# --------------------------------------------------------------- M3: optics
if ($n -ge 3) {
    Gate 'M3.1' 'optics model (DOF, energy conservation, polarity)' { return (Run-Test 'test_optics') }
    Gate 'M3.2' 'golden images match, and prove the optics do something' {
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $root 'scripts\goldens.ps1') -Verify *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# -------------------------------------------------------- M4: neighbourhood
if ($n -ge 4) {
    Gate 'M4.1' 'contact + containment'                      { return (Run-Test 'test_contact') }
    Gate 'M4.2' 'hash determinism across block sizes (INV-4)' { return (Run-Test 'test_hash') }
}

# --------------------------------------------------------------- M5: fields
if ($n -ge 5) {
    # One test covers all of it: stability, T25 conservation, the analytic 2D
    # Gaussian oracle, boundary conditions, and fixed-point deposits. The M5 text
    # named a second "point-source analytic profile" check; that asked a 2D
    # depth-averaged grid to reproduce a 3D 1/r law, which it cannot (ADR-019).
    Gate 'M5.1' 'diffusion: stability, conservation, 2D Gaussian oracle, BCs' {
        return (Run-Test 'test_fields')
    }
}

# -------------------------------------------------------------- M6: thermal
if ($n -ge 6) {
    # One test covers the oracle (T5, T7, T12), the P2 thermostat and its
    # never-boils bound (T9, T10, T19), the P3 latch (T11), starvation, and
    # determinism through the thermal stage.
    Gate 'M6.1' 'thermal: P2 thermostat, P3 latch, P4 motility, T5/T7/T9/T10/T12/T19' {
        return (Run-Test 'test_thermal')
    }
}

# ---------------------------------------------------------------- M7: light
if ($n -ge 7) {
    # One test: emission, photon thrust, Komorov (T15), the band separation
    # (T16/T17/T20), and P5 both exactly (T13, adjacent pair) and statistically
    # (population-scale depth gradient). See ADR-021 for why it is both.
    Gate 'M7.1' 'emission, thrust, Komorov, P5 near-exact + far-statistical' {
        return (Run-Test 'test_emission')
    }
}

# ---------------------------------------------------------------- M8: taxis
if ($n -ge 8) { Gate 'M8.1' 'gradient migration + darkness rule' { return (Run-Test 'test_taxis') } }

# ------------------------------------------------- M8b: cell morphology (T27)
# The goldens step above already proves the measurement oracles are untouched:
# every m3_* capture pins --morphology sphere, and the one irregular capture is a
# must-differ pair against m3_working_focus0. Appearance can never move an oracle.
if (($n -gt 8) -or ($n -eq 8 -and $suffix -ge 'b')) {
    Gate 'M8b.1' 'morphology: area-preserving, bounded, distinct (T27)' {
        return (Run-Test 'test_morphology')
    }
}

# ----------------------------------------------------------------- M9: life
if ($n -ge 9) {
    Gate 'M9a.1' 'growth: T18 doubling, CO2 exhaustion, T22 determinism through division' {
        return (Run-Test 'test_lifecycle')
    }
    # Containment is an invariant and a full rising culture is its hardest case:
    # 25k empty cells cream against the +y wall for 70 s and must all stay inside.
    Gate 'M9a.2' 'containment under a fully creamed culture' {
        $exe = Find-Exe 'headless'
        & $exe --cells 25000 --charge 0.0 --ticks 70000 --extent *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# --------------------------------- M9b: death, disposition, stats (T23)
if (($n -gt 9) -or ($n -eq 9 -and $suffix -ge 'b')) {
    Gate 'M9b.1' 'stats reduction bit-identical, death paths, store disposition (T23)' {
        return (Run-Test 'test_stats')
    }
}

# ------------------------------- M9c: clock, compaction, charts
if (($n -gt 9) -or ($n -eq 9 -and $suffix -ge 'c')) {
    Gate 'M9c.1' 'multi-rate clock: preset ratios and compounding (ADR-027)' {
        return (Run-Test 'test_clock')
    }
    # Compaction reorders the SoA, which is ADR-018's determinism hazard, so it gets
    # its own re-run of the T22 argument: a growing-and-dying culture with slots
    # reclaimed must still be bit-reproducible. Absorbing walls guarantee the deaths.
    Gate 'M9c.2' 'compaction is bit-reproducible (T22 re-run, ADR-028)' {
        $exe = Find-Exe 'headless'
        if (-not $exe) { return $false }
        & $exe --cells 20000 --charge 0.0 --ticks 4000 --compaction --absorbing --assert-deterministic *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# ------------------------------- M10a: predation (store, crawl, engulfment)
if (($n -gt 10) -or ($n -eq 10 -and $suffix -ge 'a')) {
    Gate 'M10a.1' 'predation: T30 determinism, population reduction, containment' {
        return (Run-Test 'test_predation')
    }
}

# ---------------------------------- M10b: evolution (N2 lethality, selection)
if (($n -gt 10) -or ($n -eq 10 -and $suffix -ge 'b')) {
    Gate 'M10b.1' 'nitrogen lethality + Taumoeba-82.5 selection' { return (Run-Test 'test_evolution') }
}

# -------------------------------------------- M11a: content, the scenario spine
if (($n -gt 11) -or ($n -eq 11 -and $suffix -ge 'a')) {
    Gate 'M11a.1' 'scenarios load + instantiate + run deterministically' { return (Run-Test 'test_scenario') }
}

# ----------------------------- M11b: derived metrics + every scenario (T24)
if (($n -gt 11) -or ($n -eq 11 -and $suffix -ge 'b')) {
    Gate 'M11b.1' 'every scenario passes its accept block (T24)' {
        $exe = Find-Exe 'headless'
        foreach ($s in Get-ChildItem (Join-Path $root 'scenarios') -Filter '*.json') {
            & $exe --scenario $s.BaseName --assert *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Host "        scenario failed: $($s.BaseName)"; return $false }
        }
        return $true
    }
}

# ---------------------- M11c: runtime-param overlay, canon locks, telemetry
if (($n -gt 11) -or ($n -eq 11 -and $suffix -ge 'c')) {
    Gate 'M11c.1' 'canon locks default-on, non-canon flag' { return (Run-Test 'test_param_locks') }
}

# ---- M11d/M11e: app auto-play, the parameter inspector, and the objective panel
# M11d.1 also covers M11e: the app auto-play draws the objective panel, whose checks are
# evaluated app-side with the same metric_measure/accept_eval as headless --assert.
if (($n -gt 11) -or ($n -eq 11 -and $suffix -ge 'd')) {
    Gate 'M11d.1' 'app auto-plays every scenario headless (no GL errors, contained)' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        foreach ($s in Get-ChildItem (Join-Path $root 'scenarios') -Filter '*.json') {
            & $exe --scenario $s.BaseName --headless --gl-debug --frames 20 --ticks-per-frame 20 *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Host "        scenario failed in app: $($s.BaseName)"; return $false }
        }
        return $true
    }
}

# ---------------------------- M11f: the cell inspector and live param overrides
if (($n -gt 11) -or ($n -eq 11 -and $suffix -ge 'f')) {
    # The sim reads the curated live-tunable overrides so a tuned parameter changes the
    # physics -- AND an untouched override is bit-identical to canon, so no earlier gate
    # moved (ADR-035). The determinism half is the honest guard: this could not pass while
    # secretly perturbing M9a/M11b.
    Gate 'M11f.1' 'sim reads curated overrides; default bit-identical to canon (ADR-035)' {
        return (Run-Test 'test_param_override')
    }
    # Picking is a mouse click a headless run cannot make, so --inspect pre-selects a slot;
    # this exercises the inspector's per-cell download and panel draw. Zero GL errors, and
    # the run stays contained (the app prints its end-state, checked by exit code).
    Gate 'M11f.2' 'cell inspector renders a picked cell headless (no GL errors)' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        & $exe --scenario three-percent-line --inspect 0 --headless --gl-debug `
               --frames 20 --ticks-per-frame 20 *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# ---------------------------- M12a: snapshot save/load and replay determinism
if (($n -gt 12) -or ($n -eq 12 -and $suffix -ge 'a')) {
    # A world stepped -> saved -> restored reproduces the full-state hash, and stepping the
    # original and the restored world past the boundary stays bit-identical (T21). A corrupt
    # file is rejected. This is the INV-8 oracle at full resolution (ADR-036).
    Gate 'M12a.1' 'snapshot round trip + replay across the boundary (T21)' {
        return (Run-Test 'test_snapshot')
    }
}

# ---------------------------- M12b: Taumoeba rendering
if (($n -gt 12) -or ($n -eq 12 -and $suffix -ge 'b')) {
    # The predators (invisible until now) render as marked CellInstances appended after the
    # cells in the same instanced draw (ADR-037). The taumoeba scenario breeds thousands, so
    # this exercises the second fill kernel at scale; zero GL errors, and the goldens (M3.2,
    # re-run above) still match because the predator branch is a no-op for cells.
    Gate 'M12b.1' 'app renders Taumoeba (taumoeba scenario headless, no GL errors)' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        & $exe --scenario taumoeba --headless --gl-debug --frames 20 --ticks-per-frame 20 *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# ---------------------------- M12c: the performance pass
if (($n -gt 12) -or ($n -eq 12 -and $suffix -ge 'c')) {
    # T29: zero device allocation in the steady-state tick loop (all scratch preallocated at
    # world_create) -- free memory stays flat across a dividing+compacting run. T28: sim tick
    # throughput at the 200k reference. The render frame budget (T27) is M1.5's --benchmark.
    Gate 'M12c.1' 'no steady-state allocation + sim throughput (T28/T29)' { return (Run-Test 'test_perf') }
}

# ---------------------------- M12d: the time scrubber
if (($n -gt 12) -or ($n -eq 12 -and $suffix -ge 'd')) {
    # The app records a rolling ring of full-state snapshots and rewinds into it (ADR-038).
    # --scrub-to N is the headless stand-in for the mouse-drag Timeline slider: run, then rewind
    # to recorded frame 0. Zero GL errors, and the ring's fidelity is test_snapshot's T21.4.
    Gate 'M12d.1' 'app records + rewinds the timeline headless (no GL errors)' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        & $exe --scenario bloom --headless --gl-debug --frames 20 --ticks-per-frame 30 `
               --scrub-to 0 *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

# ---------------------------- M12e: render legibility (evolution arc + colourblind LUT)
if (($n -gt 12) -or ($n -eq 12 -and $suffix -ge 'e')) {
    # The Taumoeba tolerance colour is a no-op for the cell path (M3.2 goldens, re-run above,
    # still match) so this just confirms the predators still render cleanly with it.
    Gate 'M12e.1' 'Taumoeba tolerance colouring renders headless (no GL errors)' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        & $exe --scenario taumoeba --headless --gl-debug --frames 15 --ticks-per-frame 25 *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    # The colourblind LUT must actually change Petrovascope: render a lit scene with and without
    # --colorblind and require the images to DIFFER (imgdiff exits nonzero). A must-differ check,
    # the same idea as the morphology golden pair -- it proves the swap does something.
    Gate 'M12e.2' 'colourblind LUT changes Petrovascope (must differ)' {
        $exe = Find-Exe 'astrophage'; $diff = Find-Exe 'imgdiff'
        if (-not $exe -or -not $diff) { return $false }
        $a = Join-Path $build 'm12e_petro_norm.ppm'; $b = Join-Path $build 'm12e_petro_cb.ppm'
        & $exe --scenario shadow-garden --mode petrovascope --headless --frames 12 --ticks-per-frame 20 --screenshot $a *>&1 | Out-Null
        & $exe --scenario shadow-garden --mode petrovascope --colorblind --headless --frames 12 --ticks-per-frame 20 --screenshot $b *>&1 | Out-Null
        & $diff $a $b *>&1 | Out-Null
        return ($LASTEXITCODE -ne 0)   # nonzero = the images differ = the LUT swap did something
    }
}

# ---------------------------- M13a: the field-brush toolset (poke the culture)
if (($n -gt 13) -or ($n -eq 13 -and $suffix -ge 'a')) {
    # An un-poked run is bit-identical (INV-8, M0.4 re-run above); a held Heat brush ignites a
    # dormant culture (awake rises). The marquee interaction, verified via --auto-poke -- the
    # headless stand-in for a mouse drag, like --inspect.
    Gate 'M13a.1' 'the Heat tool ignites a dormant culture headless' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        $out = & $exe --cells 4000 --charge 0.05 --headless --frames 40 --ticks-per-frame 20 --auto-poke heat 2>&1 | Out-String
        if ($out -match 'awake (\d+)') { return ([int]$Matches[1] -gt 0) }
        return $false
    }
}

# ---------------------------- M13b: the light-leash and optical tweezers
if (($n -gt 13) -or ($n -eq 13 -and $suffix -ge 'b')) {
    # The light-leash: an awake culture climbs the irradiance gradient of a spot parked off-centre
    # (--auto-light, the headless stand-in for dragging the Light tool), so its centroid tracks +x
    # toward the spot. Emergent herding (P4 + the Feed state), nothing scripted; --gl-debug asserts a
    # clean render. 1000 cells keep the herded pile below the explicit thermal solver's density limit.
    Gate 'M13b.1' 'the light-leash herds an awake culture toward the spot headless' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        $out = & $exe --auto-light --awake --charge 0.5 --cells 1000 --headless --gl-debug `
                      --frames 30 --ticks-per-frame 50 2>&1 | Out-String
        if ($out -match 'GL debug errors') { return $false }
        if ($out -match 'mean_x ([\-\d\.]+) um') { return ([double]$Matches[1] -gt 100.0) }
        return $false
    }
    # The optical tweezers: a harmonic trap tows the grabbed cell to a target point (--auto-grab, the
    # headless stand-in), reaching within a few um of it against buoyancy.
    Gate 'M13b.2' 'the optical tweezers tow a cell to a target headless' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        $out = & $exe --auto-grab 0 1000 500 --cells 2000 --headless --gl-debug `
                      --frames 30 --ticks-per-frame 50 2>&1 | Out-String
        if ($out -match 'GL debug errors') { return $false }
        if ($out -match 'dist ([\d\.]+) um') { return ([double]$Matches[1] -lt 20.0) }
        return $false
    }
}

# ---------------------------- M14a: the living-screensaver demo
# Scoped to the M14 arc off m13b-green (like M13, not the ship line). --demo cycles a playlist of the
# self-driving scenarios with a moving scope; the gate confirms it advances through the WHOLE playlist
# headless with zero GL errors. Default-off, so determinism (M0.4) + goldens (M3.2) above are unmoved.
if (($n -gt 14) -or ($n -eq 14 -and $suffix -ge 'a')) {
    Gate 'M14a.1' 'the demo cycles the full scenario playlist headless' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        # 60 frames x 500 ticks = 30000 ticks, more than one full loop of the ~25500-tick playlist.
        $out = & $exe --demo --headless --gl-debug --frames 60 --ticks-per-frame 500 2>&1 | Out-String
        if ($out -match 'GL debug errors') { return $false }
        foreach ($act in @('first-light', 'three-percent-line', 'bloom', 'taumoeba', 'shadow-garden')) {
            if ($out -notmatch "\[demo\] act.*$act") { return $false }
        }
        return $true
    }
}

# ---------------------------- M14b: the demo comes alive (herd act, caption, idle-yield, drift)
# Adds a sixth act -- the light-leash herding cells on a loop (demo-herd.json) -- plus a caption
# overlay, camera drift, and idle-aware auto-advance. The gate confirms the full six-act cycle headless
# (the always-idle path); the caption and the herd are eyeballed by screenshot, input-pause is a HUD
# toggle. Default-off still, so determinism (M0.4) + goldens (M3.2) above are unmoved.
if (($n -gt 14) -or ($n -eq 14 -and $suffix -ge 'b')) {
    Gate 'M14b.1' 'the demo cycles all six acts incl. the herd act headless' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        # 70 frames x 500 ticks = 35000 ticks, more than one full loop of the ~30500-tick playlist.
        $out = & $exe --demo --headless --gl-debug --frames 70 --ticks-per-frame 500 2>&1 | Out-String
        if ($out -match 'GL debug errors') { return $false }
        foreach ($act in @('first-light', 'three-percent-line', 'bloom', 'taumoeba', 'shadow-garden', 'demo-herd')) {
            if ($out -notmatch "\[demo\] act.*$act") { return $false }
        }
        return $true
    }
}

# ---------------------------- M12f: the view cross-fade
# Scoped to the M12 ship line only (not $n -gt 12): M13/M14 branched from m12e-green before the render
# remainder, so their gates must not require it. The cross-fade dissolves between two view modes; a
# blended frame must differ from BOTH endpoints (the M12e.2 must-differ idiom). Default blend 0 renders
# the primary mode bit-for-bit, so the M3.2 measurement goldens above are unmoved.
if ($n -eq 12 -and $suffix -ge 'f') {
    Gate 'M12f.1' 'the cross-fade blends between two modes (differs from both endpoints)' {
        $exe = Find-Exe 'astrophage'; $diff = Find-Exe 'imgdiff'
        if (-not $exe -or -not $diff) { return $false }
        $a = Join-Path $build 'm12f_petro.ppm'
        $b = Join-Path $build 'm12f_blend.ppm'
        $c = Join-Path $build 'm12f_bright.ppm'
        $common = @('--scenario', 'shadow-garden', '--headless', '--frames', '12', '--ticks-per-frame', '20')
        & $exe @common --mode petrovascope --screenshot $a *>&1 | Out-Null
        & $exe @common --mode petrovascope --mode-blend-to brightfield --mode-blend 0.5 --screenshot $b *>&1 | Out-Null
        & $exe @common --mode brightfield --screenshot $c *>&1 | Out-Null
        & $diff $a $b *>&1 | Out-Null; $ab = ($LASTEXITCODE -ne 0)
        & $diff $c $b *>&1 | Out-Null; $cb = ($LASTEXITCODE -ne 0)
        return ($ab -and $cb)   # the blend must differ from both endpoints
    }
}

# ---------------------------- M12g: render_view_v3 + the pre-ignition Thermal-IR warm-up
# The render_view_v3 -> scenario_v3 cascade adds per-cell temp_c (ADR-043). A heated but still
# DORMANT culture now glows continuously in Thermal IR, where before it stayed black until ignition.
# The gate heats a dormant culture, confirms it is still dormant (awake 0), and requires the Thermal
# render to differ from the cold baseline -- the warm-up. temp_c is render-only, so determinism (M0.4)
# and the Brightfield measurement goldens (M3.2) above are unmoved, and test_contracts (M0.3) pins the
# 40-byte layout + the v3 versions.
if ($n -eq 12 -and $suffix -ge 'g') {
    Gate 'M12g.1' 'pre-ignition warm-up: a heated dormant culture glows in Thermal IR' {
        $exe = Find-Exe 'astrophage'; $diff = Find-Exe 'imgdiff'
        if (-not $exe -or -not $diff) { return $false }
        $cold = Join-Path $build 'm12g_cold.ppm'
        $warm = Join-Path $build 'm12g_warm.ppm'
        $common = @('--cells', '3000', '--charge', '0.05', '--mode', 'thermal', '--headless', '--no-ui', '--frames', '4', '--ticks-per-frame', '15')
        & $exe @common --screenshot $cold *>&1 | Out-Null
        $out = & $exe @common --auto-poke heat --screenshot $warm 2>&1 | Out-String
        if ($out -match 'awake (\d+)') { if ([int]$Matches[1] -ne 0) { return $false } } else { return $false }
        & $diff $cold $warm *>&1 | Out-Null
        return ($LASTEXITCODE -ne 0)   # nonzero = the warm-up changed the Thermal render
    }
}

# ---------------------------- M12j: package and v1.0
# Scoped to the M12 ship line only (not $n -gt 12): M13 is a parallel arc branched from
# m12e-green before packaging is built, so an M13 gate must not require the unbuilt package.ps1.
if ($n -eq 12 -and $suffix -ge 'j') {
    Gate 'M12j.1' 'clean-environment package' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\package.ps1') -Verify *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host "[gate] $Milestone GREEN" -ForegroundColor Green
    Write-Host "       next: git tag $($Milestone.ToLower())-green" -ForegroundColor DarkGray
    exit 0
}
Write-Host "[gate] $Milestone RED" -ForegroundColor Red
$failures | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
exit 1
