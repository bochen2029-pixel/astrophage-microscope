<#
.SYNOPSIS
  Generate or verify the golden images.

.DESCRIPTION
  Iron Rule 10: goldens are never edited by hand. They change only through
  -Generate, and a regeneration must be accompanied by a docs/DECISIONS.md entry
  in the same commit explaining what changed and why.

  Every capture uses --ticks-per-frame (never the wall clock) and --no-ui, so the
  images depend only on the renderer and are reproducible on any machine.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/goldens.ps1 -Verify
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/goldens.ps1 -Generate
#>
[CmdletBinding()]
param([switch]$Generate, [switch]$Verify, [switch]$KeepCandidates)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$goldens = Join-Path $root 'goldens'
$build = Join-Path $root 'build'

if (-not $Generate -and -not $Verify) { $Verify = $true }

function Find-Exe([string]$name) {
    $e = Get-ChildItem $build -Filter "$name.exe" -Recurse -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if ($e) { return $e.FullName }
    return $null
}

$app = Find-Exe 'astrophage'
$diff = Find-Exe 'imgdiff'
if (-not $app)  { Write-Host '[goldens] astrophage.exe not found (build with -App)' -ForegroundColor Red; exit 1 }
if (-not $diff) { Write-Host '[goldens] imgdiff.exe not found' -ForegroundColor Red; exit 1 }

# M3 cases. Three objectives x three focal depths, plus the two that make the
# optics legible on their own: a sedimented monolayer, and a defocus sweep across
# a single plane of cells.
#
# Seed and tick count are pinned; a golden that depends on wall clock is not a
# golden. 400 ticks is 0.4 s: enough for velocities to settle, far too little for
# sedimentation to move anything measurably, so the layout is stable.
$cases = @(
    @{ name = 'm3_survey_focus0';   args = @('--objective','0','--focus','0')    }
    @{ name = 'm3_working_focus0';  args = @('--objective','1','--focus','0')    }
    @{ name = 'm3_working_focusp8'; args = @('--objective','1','--focus','8')    }
    @{ name = 'm3_working_focusm8'; args = @('--objective','1','--focus','-8')   }
    @{ name = 'm3_working_focusp25';args = @('--objective','1','--focus','25')   }
    @{ name = 'm3_detail_focus0';   args = @('--objective','2','--focus','0')    }
    @{ name = 'm3_detail_focusp2';  args = @('--objective','2','--focus','2')    }
    @{ name = 'm3_detail_focusm2';  args = @('--objective','2','--focus','-2')   }
    # M8b. The only case that leaves the sphere: proves morphology reaches pixels.
    @{ name = 'm8b_working_irregular';
       args = @('--objective','1','--focus','0','--morphology','irregular')      }
    # M7b. The non-brightfield view modes. Captured on an AWAKE, half-charged
    # population (charge so an awake cell does not instantly starve), in darkness so
    # the cells are idle: awake and NOT emitting. That is the exact case that must
    # separate the two IR instruments. Thermal IR is the film's ABSORPTION view --
    # albedo-0 cells are black silhouettes on the warm false-colour medium, with a
    # hot rim on the awake heat-sources -- so the cell is plainly visible. In the
    # Petrovascope the same idle cell is invisible (nothing is emitting). Darkfield
    # shows the cells as bright edge-scatter on black.
    @{ name = 'm7b_thermal_awake';
       args = @('--objective','1','--focus','0','--charge','0.5','--mode','thermal','--awake')     }
    @{ name = 'm7b_petrova_awake';
       args = @('--objective','1','--focus','0','--charge','0.5','--mode','petrovascope','--awake') }
    @{ name = 'm7b_darkfield_awake';
       args = @('--objective','1','--focus','0','--charge','0.5','--mode','darkfield','--awake')    }
)

# EVERY measurement golden pins --morphology sphere and --aperture 0, so the M3
# optics gate keeps measuring exactly what it has measured since M3. Appearance
# work must never be able to move an oracle (ADR-023); the one irregular case
# above overrides this deliberately.
$common = @('--headless','--no-ui','--cells','25000','--seed','20260802',
            '--frames','8','--ticks-per-frame','50','--width','1024','--height','768',
            '--morphology','sphere','--aperture','0','--no-bloom')

New-Item -ItemType Directory -Force $goldens | Out-Null
$candDir = Join-Path $env:TEMP 'astro_goldens'
New-Item -ItemType Directory -Force $candDir | Out-Null

$fail = 0
foreach ($c in $cases) {
    $target = if ($Generate) { Join-Path $goldens "$($c.name).ppm" }
              else           { Join-Path $candDir "$($c.name).ppm" }

    & $app @common @($c.args) --screenshot $target *>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $target)) {
        Write-Host "[goldens] capture FAILED: $($c.name)" -ForegroundColor Red
        $fail++
        continue
    }

    if ($Generate) {
        Write-Host "[goldens] wrote $($c.name).ppm" -ForegroundColor DarkGray
    } else {
        $golden = Join-Path $goldens "$($c.name).ppm"
        if (-not (Test-Path $golden)) {
            Write-Host "[goldens] MISSING golden: $($c.name) -- run with -Generate" -ForegroundColor Red
            $fail++
            continue
        }
        $diffOut = Join-Path $candDir "$($c.name)_diff.ppm"
        & $diff $golden $target --out $diffOut
        if ($LASTEXITCODE -ne 0) { $fail++ }
    }
}

# Pairs that must NOT match.
#
# A golden suite only proves the renderer is stable; it cannot prove the renderer
# does anything. These pairs prove it does.
#
# The focus +2 / -2 pair is the sharpest of them: identical |dz|, so identical
# blur radius, identical peak opacity, identical everything except the SIGN. If
# the defocus polarity inversion were dropped, those two images would be
# byte-identical. This is therefore a headless test of the Becke-line inversion,
# which is otherwise only checkable by eye.
$mustDiffer = @(
    @{ a = 'm3_detail_focusp2';  b = 'm3_detail_focusm2';  why = 'defocus polarity inverts across focus' }
    @{ a = 'm3_working_focus0';  b = 'm3_working_focusp8'; why = 'racking focus changes the image' }
    @{ a = 'm3_working_focusp8'; b = 'm3_working_focusp25';why = 'defocus keeps increasing with distance' }
    # Same scene, same seed, same optics -- only the silhouette differs. If these
    # ever match, morphology has stopped reaching pixels and the shader mirror of
    # morphology.h has silently died (ADR-017 has no compiler check across GLSL).
    @{ a = 'm3_working_focus0';  b = 'm8b_working_irregular';
       why = 'irregular morphology changes the silhouette' }
    # The teaching moment (RENDERING.md Sec 4): the Petrova line is a quantum
    # annihilation line, not thermal emission, so the two IR modes MUST diverge. A
    # live idle cell is bright in Thermal and dark in the Petrovascope. If these
    # ever match, a real physical distinction has been lost.
    @{ a = 'm7b_thermal_awake';  b = 'm7b_petrova_awake';
       why = 'a live idle cell is a visible absorber on the warm IR field and is invisible in the Petrovascope' }
    @{ a = 'm7b_darkfield_awake'; b = 'm7b_petrova_awake';
       why = 'darkfield edge-scatter is not the Petrova glow' }
)
foreach ($pair in $mustDiffer) {
    $pa = Join-Path $goldens "$($pair.a).ppm"
    $pb = Join-Path $goldens "$($pair.b).ppm"
    if (-not (Test-Path $pa) -or -not (Test-Path $pb)) { continue }
    & $diff $pa $pb *>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[goldens] FAIL: $($pair.a) and $($pair.b) are identical -- $($pair.why)" -ForegroundColor Red
        $fail++
    } else {
        Write-Host "[goldens] ok (differ): $($pair.why)" -ForegroundColor DarkGray
    }
}

if (-not $KeepCandidates -and $Verify -and $fail -eq 0) {
    Remove-Item -Recurse -Force $candDir -ErrorAction SilentlyContinue
}

if ($Generate) {
    Write-Host "[goldens] generated $($cases.Count) images." -ForegroundColor Green
    Write-Host '           Iron Rule 10: commit a DECISIONS.md entry alongside any regeneration.' -ForegroundColor DarkYellow
    exit 0
}

if ($fail -eq 0) {
    Write-Host "[goldens] PASS -- $($cases.Count) images match" -ForegroundColor Green
    exit 0
}
Write-Host "[goldens] FAIL -- $fail of $($cases.Count) images differ" -ForegroundColor Red
Write-Host "           diffs written to $candDir" -ForegroundColor DarkYellow
exit 1
