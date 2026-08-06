<#
.SYNOPSIS
  Package astrophage into a self-contained .zip, and verify it runs on a scrubbed-PATH clean environment.

.DESCRIPTION
  M12j / v1.0. The app links a STATIC CUDA runtime and a STATIC MSVC CRT (CMakeLists.txt:
  CMAKE_CUDA_RUNTIME_LIBRARY Static, CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded) and resolves its
  scenarios next to the executable (application.cpp scenarios_dir), so the shipped bundle is just
  astrophage.exe + scenarios/ + docs and depends on nothing but the OS. -Verify extracts the zip to a
  temp dir, scrubs PATH down to the bare Windows system directories, runs the app headless from a
  NEUTRAL working directory, and confirms it launches, finds its scenarios, and logs zero GL errors --
  if any hidden DLL or PATH dependency existed, that run would fail.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package.ps1 -Verify
#>
[CmdletBinding()]
param([switch]$Verify, [switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$dist  = Join-Path $root 'dist'

$version = (& git -C $root describe --tags --always 2>$null)
if (-not $version) { $version = 'v1.0' }

# 1. Build the app (Release, static) unless the caller already did (the gate builds at M0.2).
if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\build.ps1') -App *>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host '[package] build failed' -ForegroundColor Red; exit 1 }
}
$exe = Get-ChildItem $build -Filter 'astrophage.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Write-Host '[package] astrophage.exe not found (build with -App)' -ForegroundColor Red; exit 1 }

# 2. Stage the self-contained bundle: exe + scenarios + docs.
$stage = Join-Path $env:TEMP "astro_pkg"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item $exe.FullName (Join-Path $stage 'astrophage.exe')
Copy-Item (Join-Path $root 'scenarios') (Join-Path $stage 'scenarios') -Recurse
foreach ($doc in @('docs\USER_GUIDE.md', 'README.md', 'LICENSE', 'NOTICE.md')) {
    $src = Join-Path $root $doc
    if (Test-Path $src) { Copy-Item $src $stage }
}
Set-Content -Path (Join-Path $stage 'VERSION.txt') -Value $version

# 3. Zip the bundle contents (so it extracts to astrophage.exe + scenarios/ at the root).
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "astrophage-$version.zip"
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Write-Host "[package] wrote $zip" -ForegroundColor Green

if (-not $Verify) { exit 0 }

# 4. Verify on a scrubbed-PATH clean environment. Extract fresh, scrub PATH to the bare system dirs, and
#    run headless from a NEUTRAL cwd -- so scenarios must resolve relative to the exe, not the cwd or the
#    source tree, and any missing DLL/PATH dependency surfaces as a failed launch.
$test = Join-Path $env:TEMP "astro_verify"
Remove-Item -Recurse -Force $test -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $test | Out-Null
Expand-Archive -Path $zip -DestinationPath $test
$pkgExe = Join-Path $test 'astrophage.exe'

$prevPath = $env:PATH
$prevCwd  = (Get-Location).Path
$ok = $true
try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"   # no CUDA toolkit, no build tools
    Set-Location $env:TEMP                                    # neutral cwd: force exe-relative scenarios
    & $pkgExe --headless --gl-debug --frames 3 --ticks-per-frame 10 *>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $ok = $false }
    $out = & $pkgExe --scenario first-light --headless --gl-debug --frames 5 --ticks-per-frame 20 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0)          { $ok = $false }
    if ($out -match 'GL debug errors') { $ok = $false }
    if ($out -notmatch 'first-light')  { $ok = $false }      # the scenario actually loaded exe-relative
} finally {
    $env:PATH = $prevPath
    Set-Location $prevCwd
}

if ($ok) {
    Write-Host '[package] VERIFY PASS -- the bundle runs on a scrubbed PATH and finds its scenarios' -ForegroundColor Green
    exit 0
}
Write-Host '[package] VERIFY FAIL -- the packaged bundle did not run clean; a dependency is missing' -ForegroundColor Red
exit 1
