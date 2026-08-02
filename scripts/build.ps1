<#
.SYNOPSIS
  Configure and build astrophage.

.DESCRIPTION
  Finds a generator (prefers Ninja, including the copy bundled with VS 2022),
  regenerates the canon artifacts, and builds. Exits nonzero on any failure so
  gate.ps1 and audit.ps1 can rely on it.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Clean -App
#>
[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$App,                       # ASTRO_BUILD_APP=ON (needs network on first configure)
    [ValidateSet('Release','Debug','RelWithDebInfo')]
    [string]$Config = 'Release',
    [string]$BuildDir = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $BuildDir) { $BuildDir = Join-Path $root 'build' }

function Find-Tool {
    param([string]$Name, [string[]]$Candidates)
    $onPath = Get-Command $Name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($c in $Candidates) { if (Test-Path $c) { return $c } }
    return $null
}

$vsRoot = 'C:\Program Files\Microsoft Visual Studio\2022'
$cmake = Find-Tool 'cmake' @(
    "$vsRoot\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "$vsRoot\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "$vsRoot\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe")
if (-not $cmake) { Write-Error 'cmake not found.' }

$ninja = Find-Tool 'ninja' @(
    "$vsRoot\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
    "$vsRoot\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
    "$vsRoot\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe")

# Ninja needs the MSVC environment; the VS generator sets it up itself. If we are
# not already inside a developer shell, fall back rather than fail confusingly.
$inDevShell = [bool]$env:VCToolsInstallDir
if ($ninja -and -not $inDevShell) {
    $vcvars = Get-ChildItem "$vsRoot\*\VC\Auxiliary\Build\vcvars64.bat" -ErrorAction SilentlyContinue |
              Select-Object -First 1
    if ($vcvars) {
        # Import the developer environment into this session once.
        cmd /c "`"$($vcvars.FullName)`" >nul 2>&1 && set" | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] }
        }
        $inDevShell = [bool]$env:VCToolsInstallDir
    }
}

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "[build] cleaning $BuildDir"
    Remove-Item -Recurse -Force $BuildDir
}

Write-Host '[build] regenerating canon artifacts'
& python (Join-Path $root 'scripts\derive.py')
if ($LASTEXITCODE -ne 0) { Write-Error 'derive.py failed.' }

$needConfigure = -not (Test-Path (Join-Path $BuildDir 'CMakeCache.txt'))
if ($needConfigure) {
    $genArgs = @()
    if ($ninja -and $inDevShell) {
        $genArgs = @('-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$ninja", "-DCMAKE_BUILD_TYPE=$Config")
        Write-Host "[build] generator: Ninja ($ninja)"
    } else {
        $genArgs = @('-G', 'Visual Studio 17 2022', '-A', 'x64')
        Write-Host '[build] generator: Visual Studio 17 2022'
    }
    $appFlag = if ($App) { 'ON' } else { 'OFF' }
    & $cmake -S $root -B $BuildDir @genArgs "-DASTRO_BUILD_APP=$appFlag"
    if ($LASTEXITCODE -ne 0) { Write-Error 'cmake configure failed.' }
} elseif ($App) {
    & $cmake -S $root -B $BuildDir -DASTRO_BUILD_APP=ON
    if ($LASTEXITCODE -ne 0) { Write-Error 'cmake reconfigure failed.' }
}

& $cmake --build $BuildDir --config $Config --parallel
if ($LASTEXITCODE -ne 0) { Write-Error 'build failed.' }

Write-Host "[build] OK ($Config)"
exit 0
