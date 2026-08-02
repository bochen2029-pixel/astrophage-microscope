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
    [ValidatePattern('^M(1[0-2]|[0-9])[a-z]?$')]
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

# ------------------------------------------------------------ M10: predation
if ($n -ge 10) { Gate 'M10.1' 'predation + nitrogen selection' { return (Run-Test 'test_predation') } }

# -------------------------------------------------------------- M11: content
if ($n -ge 11) {
    Gate 'M11.1' 'every scenario passes its accept block (T24)' {
        $exe = Find-Exe 'headless'
        foreach ($s in Get-ChildItem (Join-Path $root 'scenarios') -Filter '*.json') {
            & $exe --scenario $s.BaseName --assert *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Host "        scenario failed: $($s.BaseName)"; return $false }
        }
        return $true
    }
    Gate 'M11.2' 'canon locks default-on' { return (Run-Test 'test_param_locks') }
}

# ----------------------------------------------------------------- M12: ship
if ($n -ge 12) {
    Gate 'M12.1' 'snapshot round trip (T21, T23)' { return (Run-Test 'test_snapshot') }
    Gate 'M12.2' 'performance budget (T27-T29)'   { return (Run-Test 'test_perf') }
    Gate 'M12.3' 'clean-environment package'      {
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
