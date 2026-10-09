# Interactive run: boot the game in one emulator/renderer, play, then close the window.
# The log and any screenshots (F12) are copied to results\ afterwards.
param(
    [ValidateSet('ours', 'upstream', 'plus')][string]$Emu = 'ours',
    [ValidateSet('Vulkan', 'OpenGL')][string]$Renderer = 'Vulkan',
    [ValidateSet('Title', 'DebugMenu', 'Elder', 'Harpy')][string]$Boot = 'Title',
    [int]$Volume = 100
)
. (Join-Path $PSScriptRoot 'common.ps1')

Set-EmulatorConfig $Emu $Renderer $Volume
Set-BootSequence $BootTargets[$Boot]
$shotDir = Join-Path $Emulators[$Emu] 'portable\screenshots'
$before = @()
if (Test-Path $shotDir) { $before = @(Get-ChildItem $shotDir -Recurse -File | ForEach-Object FullName) }

Write-Host "Starting $Emu / $Renderer / $Boot. Close the game window when done." -ForegroundColor Cyan
$p = Start-Emulator $Emu $Renderer
$p.WaitForExit()
Restore-BootSequence

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $Results "play-$stamp-$Emu-$Renderer-$Boot"
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $Emulators[$Emu] 'portable\vita3k.log'
if (Test-Path $log) { Copy-Item $log (Join-Path $out 'vita3k.log') }
if (Test-Path $shotDir) {
    Get-ChildItem $shotDir -Recurse -File | Where-Object { $before -notcontains $_.FullName } |
        Copy-Item -Destination $out
}
"exit code $($p.ExitCode)" | Out-File (Join-Path $out 'exit.txt') -Encoding ascii
Write-Host "Saved log and screenshots to $out" -ForegroundColor Green
