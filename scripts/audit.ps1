<#
.SYNOPSIS
  Fast continuous self-audit. Run BEFORE and AFTER every step.

.DESCRIPTION
  Every cheap, non-negotiable oracle in one shot:
    A1  canon artifacts are fresh          (ARCHITECTURE.md 5.1)
    A2  build is clean, warnings as errors (Iron Rule 1)
    A3  ctest is green
    A4  determinism replay hash is stable  (INV-8)
    A5  sim/ and fields/ contain no presentation code (INV-5)
    A6  no bare Math.random-equivalent / host RNG in sim (INV-1)
    A7  no -use_fast_math in sim/fields    (INV-6)
    A8  module inventory matches ARCHITECTURE.md Sec 7 (Iron Rule 7)
    A9  no unexplained physical literals in sim/fields (Iron Rule 3)
    A10 no render size fudge on cells      (RENDERING.md 7)

  gate.ps1 is the milestone gate; this is the check between gates.
  Appends a one-line verdict to docs/CHANGE_AUDIT_LOG.md.
#>
[CmdletBinding()]
param([switch]$SkipBuild, [switch]$Quiet)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$fail = @()
$checks = 0

function Step {
    param([string]$Id, [string]$What, [scriptblock]$Body)
    $script:checks++
    try {
        $r = & $Body
        if ($r -eq $false) { $script:fail += "$Id ($What)"; Write-Host "  FAIL $Id  $What" -ForegroundColor Red }
        elseif (-not $Quiet) { Write-Host "  ok   $Id  $What" -ForegroundColor DarkGray }
    } catch {
        $script:fail += "$Id ($What): $_"
        Write-Host "  FAIL $Id  $What -- $_" -ForegroundColor Red
    }
}

# Files that are allowed to contain physical constants and RNG plumbing.
$simFiles = Get-ChildItem -Path (Join-Path $root 'src\sim'), (Join-Path $root 'src\fields') `
            -Include *.cu, *.cuh, *.cpp, *.h -Recurse -ErrorAction SilentlyContinue

Write-Host "[audit] astrophage self-audit"

Step 'A1' 'canon artifacts fresh' {
    & python (Join-Path $root 'scripts\derive.py') --check *>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

if (-not $SkipBuild) {
    Step 'A2' 'clean build (warnings as errors)' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\build.ps1') *>&1 |
            Tee-Object -Variable buildOut | Out-Null
        return ($LASTEXITCODE -eq 0)
    }

    Step 'A3' 'ctest green' {
        Push-Location $root
        & ctest --test-dir (Join-Path $root 'build') --output-on-failure *>&1 | Out-Null
        $code = $LASTEXITCODE
        Pop-Location
        return ($code -eq 0)
    }

    Step 'A4' 'determinism replay (INV-8)' {
        $exe = Get-ChildItem (Join-Path $root 'build') -Filter 'headless.exe' -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if (-not $exe) { return $false }
        & $exe.FullName --ticks 2000 --assert-deterministic *>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
} else {
    Write-Host '  skip A2-A4 (build skipped)' -ForegroundColor DarkYellow
}

Step 'A5' 'sim/fields have no presentation code (INV-5)' {
    $hits = $simFiles | Select-String -Pattern '#include\s*[<"](GLFW/|glad/|imgui|GL/|windows\.h)' -ErrorAction SilentlyContinue
    if ($hits) { $hits | ForEach-Object { Write-Host "      $($_.Path):$($_.LineNumber)" } ; return $false }
    return $true
}

Step 'A6' 'no host RNG in sim/fields (INV-1)' {
    $hits = $simFiles | Select-String -Pattern '\b(rand\s*\(|srand\s*\(|std::mt19937|curand|random_device)' -ErrorAction SilentlyContinue
    if ($hits) { $hits | ForEach-Object { Write-Host "      $($_.Path):$($_.LineNumber)  $($_.Line.Trim())" } ; return $false }
    return $true
}

Step 'A7' 'no fast-math in sim/fields (INV-6)' {
    $cm = Get-Content (Join-Path $root 'CMakeLists.txt') -Raw
    if ($cm -match 'use_fast_math|--ftz=true|--prec-div=false') { return $false }
    return $true
}

Step 'A8' 'module inventory matches ARCHITECTURE.md (Iron Rule 7)' {
    $arch = Get-Content (Join-Path $root 'docs\ARCHITECTURE.md') -Raw
    $missing = @()
    foreach ($m in 'core', 'fields', 'sim', 'render', 'ui', 'app') {
        if (-not (Test-Path (Join-Path $root "src\$m"))) { $missing += "src\$m" }
        if ($arch -notmatch [regex]::Escape("src/$m")) { $missing += "ARCHITECTURE:src/$m" }
    }
    foreach ($c in Get-ChildItem (Join-Path $root 'contracts') -Filter '*_v*.h' -ErrorAction SilentlyContinue) {
        if ($arch -notmatch [regex]::Escape($c.Name)) { $missing += "ARCHITECTURE:$($c.Name)" }
    }
    if ($missing) { $missing | ForEach-Object { Write-Host "      missing: $_" } ; return $false }
    return $true
}

Step 'A9' 'no unexplained physical literals in sim/fields (Iron Rule 3)' {
    # Physical constants must come from canon_generated.h. Flags scientific
    # notation and long decimals; allows small integers, 0.5, 2.0, array indices,
    # and anything on a line that cites canon or carries an explicit waiver.
    $hits = @()
    foreach ($f in $simFiles) {
        $n = 0
        foreach ($line in Get-Content $f.FullName) {
            $n++
            if ($line -match '^\s*(//|\*|/\*)') { continue }
            if ($line -match 'canon::|ASTRO_LITERAL_OK') { continue }
            # Three shapes of "that looks like a physical constant":
            #   long mantissa   6.283185307179586
            #   scientific      1.5e6, 2.1e-14
            #   two-and-two     293.15, 96.415   (missed by the first pattern,
            #                                     which is how room temperature
            #                                     slipped into cell_store.cu)
            # Small literals (0.5, 1.0, 2.0, 0.25) are deliberately allowed.
            if ($line -match '[0-9]\.[0-9]{4,}|[0-9]e[-+]?[0-9]{2,}|[0-9]{2,}\.[0-9]{2,}') {
                $hits += "$($f.Name):$n  $($line.Trim())"
            }
        }
    }
    if ($hits) { $hits | ForEach-Object { Write-Host "      $_" } ; return $false }
    return $true
}

Step 'A10' 'no cell size fudge in render (RENDERING.md 7)' {
    $rf = Get-ChildItem (Join-Path $root 'src\render') -Include *.cpp, *.cu, *.h -Recurse -ErrorAction SilentlyContinue
    if (-not $rf) { return $true }
    $hits = $rf | Select-String -Pattern 'radius\s*\*\s*[2-9]|VISUAL_SCALE|size_boost|radius_fudge' -ErrorAction SilentlyContinue
    if ($hits) { $hits | ForEach-Object { Write-Host "      $($_.Path):$($_.LineNumber)" } ; return $false }
    return $true
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$describe = (& git -C $root describe --always --dirty 2>$null)
if (-not $describe) { $describe = 'no-git' }

if ($fail.Count -eq 0) {
    $verdict = "$stamp  $describe  AUDIT PASS  ($checks checks)"
    Write-Host "[audit] PASS -- $checks checks" -ForegroundColor Green
} else {
    $verdict = "$stamp  $describe  AUDIT FAIL  $($fail -join '; ')"
    Write-Host "[audit] FAIL -- $($fail -join '; ')" -ForegroundColor Red
}

$logPath = Join-Path $root 'docs\CHANGE_AUDIT_LOG.md'
if (-not (Test-Path $logPath)) {
    Set-Content $logPath "# CHANGE AUDIT LOG`n`nOne line per ``scripts/audit.ps1`` run. Append-only.`n"
}
Add-Content $logPath $verdict

exit ($(if ($fail.Count -eq 0) { 0 } else { 1 }))
