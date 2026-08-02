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
    [ValidatePattern('^M(1[0-2]|[0-9])$')]
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

$n = [int]$Milestone.Substring(1)
Write-Host "[gate] $Milestone (re-running gates M0..$Milestone)" -ForegroundColor Cyan

# ---------------------------------------------------------------- M0: harness
Gate 'M0.1' 'canon artifacts fresh' {
    & python (Join-Path $root 'scripts\derive.py') --check *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}
if (-not $SkipBuild) {
    Gate 'M0.2' 'clean build, warnings as errors' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\build.ps1') -Clean *>&1 | Out-Null
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
    Gate 'M1.2' 'render 200k cells at target fps (headless timing)' {
        $exe = Find-Exe 'astrophage'
        if (-not $exe) { return $false }
        & $exe --benchmark --cells 200000 --frames 600 *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    Gate 'M1.3' 'zero GL debug errors' {
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
if ($n -ge 3) { Gate 'M3.1' 'optics goldens' { return (Run-Test 'test_optics_golden') } }

# -------------------------------------------------------- M4: neighbourhood
if ($n -ge 4) {
    Gate 'M4.1' 'contact + containment'                      { return (Run-Test 'test_contact') }
    Gate 'M4.2' 'hash determinism across block sizes (INV-4)' { return (Run-Test 'test_hash') }
}

# --------------------------------------------------------------- M5: fields
if ($n -ge 5) {
    Gate 'M5.1' 'diffusion stability + conservation (T25)' { return (Run-Test 'test_fields') }
    Gate 'M5.2' 'point-source analytic profile'            { return (Run-Test 'test_field_analytic') }
}

# -------------------------------------------------------------- M6: thermal
if ($n -ge 6) {
    Gate 'M6.1' 'thermal oracle (T5, T7, T12)'          { return (Run-Test 'test_thermal') }
    Gate 'M6.2' 'P2 thermostat, never boils (T9, T10, T19)' { return (Run-Test 'test_thermostat') }
    Gate 'M6.3' 'P3 ignition latch (T11)'               { return (Run-Test 'test_ignition') }
}

# ---------------------------------------------------------------- M7: light
if ($n -ge 7) {
    Gate 'M7.1' 'emission + thrust (T15, T16, T17, T20)' { return (Run-Test 'test_emission') }
    Gate 'M7.2' 'P5 total occlusion (T13)'               { return (Run-Test 'test_occlusion') }
}

# ---------------------------------------------------------------- M8: taxis
if ($n -ge 8) { Gate 'M8.1' 'gradient migration + darkness rule' { return (Run-Test 'test_taxis') } }

# ----------------------------------------------------------------- M9: life
if ($n -ge 9) {
    Gate 'M9.1' 'doubling time (T18)'                        { return (Run-Test 'test_lifecycle') }
    Gate 'M9.2' 'determinism through division (T22)' {
        $exe = Find-Exe 'headless'
        & $exe --scenario bloom --ticks 200000 --assert-deterministic *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
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
