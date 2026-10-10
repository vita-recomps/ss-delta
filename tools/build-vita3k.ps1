# Configures and builds our Vita3K fork (third_party/vita3k) with MSVC + Ninja
# Multi-Config into build/vita3k. See docs/decisions.md D5.
#   . .\tools\devshell.ps1; .\tools\build-vita3k.ps1 [-Config Debug|RelWithDebInfo|Release] [-Jobs N] [-Reconfigure] [-NoJit]
# The executable lands in build\vita3k\bin\<Config>\Vita3K.exe. -NoJit builds without dynarmic
# (VITA3K_DYNARMIC=OFF: recompiled code only, docs/decisions.md D11) into build\vita3k-nojit.
param(
  [ValidateSet('Debug', 'RelWithDebInfo', 'Release')][string]$Config = 'RelWithDebInfo',
  [int]$Jobs = 0,
  [switch]$Reconfigure,
  [switch]$NoJit
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'third_party\vita3k'
$build = Join-Path $root $(if ($NoJit) { 'build\vita3k-nojit' } else { 'build\vita3k' })
if (-not $env:VCToolsVersion) { throw 'run . .\tools\devshell.ps1 first' }
if (-not (Test-Path "$src\external\dynarmic\CMakeLists.txt")) { throw "submodules missing under $src" }

# Native tools write warnings to stderr; under 'Stop', Windows PowerShell 5.1
# turns those into terminating errors when output is redirected. Exit codes are
# checked explicitly instead.
$ErrorActionPreference = 'Continue'
# Vita3K's presets set this for older external CMakeLists.
$env:CMAKE_POLICY_VERSION_MINIMUM = '3.5'
$cache = Join-Path $build 'CMakeCache.txt'
if ($Reconfigure -or -not (Test-Path $cache) -or -not (Test-Path (Join-Path $build 'build.ninja'))) {
  # The first configure bootstraps Boost's b2, whose build.bat runs
  # 'call guess_toolset.bat' from its own folder. That fails when
  # NoDefaultCurrentDirectoryInExePath is set, so clear it for this step only.
  $savedNoCwd = $env:NoDefaultCurrentDirectoryInExePath
  $env:NoDefaultCurrentDirectoryInExePath = $null
  try {
    $jitArg = if ($NoJit) { '-DVITA3K_DYNARMIC=OFF' } else { '-DVITA3K_DYNARMIC=ON' }
    cmake -S $src -B $build -G 'Ninja Multi-Config' `
      -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl $jitArg
  } finally {
    $env:NoDefaultCurrentDirectoryInExePath = $savedNoCwd
  }
  if ($LASTEXITCODE) { throw 'cmake configure failed' }
}
$jobArgs = if ($Jobs -gt 0) { @('-j', $Jobs) } else { @() }
$sw = [Diagnostics.Stopwatch]::StartNew()
cmake --build $build --config $Config @jobArgs
if ($LASTEXITCODE) { throw 'build failed' }
Write-Host ("build ($Config) finished in {0:n1} min" -f $sw.Elapsed.TotalMinutes)
