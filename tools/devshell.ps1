# Loads the MSVC x64 build environment (cl, link, Windows SDK) into the current
# PowerShell session, refreshes PATH from the registry, and points CMake at Qt.
# Usage:  . .\tools\devshell.ps1      (dot-source it)
$ErrorActionPreference = 'Stop'
$vs = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools'
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found under $vs" }

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

cmd /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
}
if (-not $env:VULKAN_SDK) { $env:VULKAN_SDK = [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'Machine') }
# Qt 6.11.0 (MSVC 2022 x64 + qtmultimedia), installed with aqtinstall, matching
# Vita3K's CI (.github/workflows/c-cpp.yml, QT_VERSION).
$env:Qt6_ROOT = 'C:\Qt\6.11.0\msvc2022_64'
if (-not (Test-Path "$env:Qt6_ROOT\lib\cmake\Qt6")) { Write-Warning "Qt not found at $env:Qt6_ROOT" }

Write-Host "devshell: MSVC $env:VCToolsVersion, VULKAN_SDK=$env:VULKAN_SDK, Qt6_ROOT=$env:Qt6_ROOT"
