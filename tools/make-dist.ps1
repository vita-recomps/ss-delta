# Lay out a self-contained ss-delta folder: dist\ss-delta-<commit>\ with ss-delta.exe, the DLLs it
# needs, its data, the recompiled modules (built locally from the player's own dump, never shared)
# and a commented ss-delta.ini. Nothing here is committed (dist/ is ignored).
#   .\tools\make-dist.ps1 [-VitaFs C:\path\to\fs] [-Name ss-delta-test] [-RecompiledDir <dir>] [-NoRecompiled]
param(
    [string]$VitaFs = '',
    [string]$Name = '',
    [string]$RecompiledDir = '',
    [switch]$NoRecompiled,
    [switch]$NoJit  # ss-delta.exe from the build without dynarmic (build-vita3k.ps1 -NoJit)
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root $(if ($NoJit) { 'build\vita3k-nojit\bin\RelWithDebInfo' } else { 'build\vita3k\bin\RelWithDebInfo' })
if (-not (Test-Path "$bin\ss-delta.exe")) { throw "build ss-delta.exe first (tools\build-vita3k.ps1)" }
if (-not $Name) { $Name = 'ss-delta-' + (git -C $root rev-parse --short HEAD).Trim() }
$out = Join-Path $root "dist\$Name"
New-Item -ItemType Directory -Force $out | Out-Null

# the executable and the DLLs it loads (Windows and the VC++ runtime are the player's)
Copy-Item "$bin\ss-delta.exe" $out -Force
$dlls = @('discord_game_sdk.dll', 'libssl-4-x64.dll', 'libcrypto-4-x64.dll') +
    (Get-ChildItem $bin -Filter 'av*.dll' | ForEach-Object Name) +
    (Get-ChildItem $bin -Filter 'sw*.dll' | ForEach-Object Name)
foreach ($d in $dlls) { if (Test-Path "$bin\$d") { Copy-Item "$bin\$d" $out -Force } }

# static assets Vita3K reads next to the executable
foreach ($dir in 'data', 'shaders-builtin', 'icons') {
    if (Test-Path "$bin\$dir") { Copy-Item "$bin\$dir" $out -Recurse -Force }
}

# the recompiled modules
if (-not $NoRecompiled) {
    if (-not $RecompiledDir) { $RecompiledDir = Join-Path $root 'build\recomp' }
    $mods = Get-ChildItem $RecompiledDir -Filter 'ssd_aot_*.dll'
    if (-not $mods) { Write-Warning "no ssd_aot_*.dll in ${RecompiledDir}: everything will run on the JIT" }
    $mods | Copy-Item -Destination $out -Force
}

# ss-delta.ini: the default ss-delta.exe writes (from ss-delta/settings.cpp), with vita_fs set
$ini = Join-Path $out 'ss-delta.ini'
if (-not (Test-Path $ini)) {
    $src = Join-Path $root 'third_party\vita3k\vita3k\ss-delta\settings.cpp'
    python -I (Join-Path $PSScriptRoot 'ssdelta_ini.py') $src $ini $VitaFs
    if ($LASTEXITCODE) { throw 'writing ss-delta.ini failed' }
}

@"
ss-delta: Soul Sacrifice Delta (PCSA00152, 1.30) on PC.

ss-delta.exe runs the game installed in a Vita file system ([paths] vita_fs in
ss-delta.ini; default: the fs folder next to this file), with the game's code
recompiled to native code (ssd_aot_*.dll, built from your own dump).

Settings are in ss-delta.ini: resolution, window, fullscreen (F11 or
Alt+Enter while playing), filter, frame rate (frame_rate = 60 under
[display]: 60 fps, loading screens stay at 30), volume, keyboard and
gamepad bindings. The mouse is the touchscreen: left button front, right
button rear. The Black Rite icon (touch and hold) is also on F and the
gamepad's left trigger ([touch] in ss-delta.ini). F12 saves a screenshot to
ss-delta\screenshots.

The add-ons (raiments, hoods, additional pacts) are unlocked: their content
is in the game since update 1.30, and ss-delta.exe records them in your save
once ([game] dlc in ss-delta.ini; a copy of the previous file goes to
ss-delta\save-backups).

Saves are in the Vita file system (ux0\user\00\savedata\PCSA00152). To use a
save from a Vita (decrypted, e.g. with VitaShell or Apollo), run
  ss-delta.exe --import-save <folder or .zip> [--slot 2]
The game has three save slots (default 1); the save folder as it was is kept
in ss-delta\save-backups. To copy a slot out:
  ss-delta.exe --export-save <folder> [--slot 2]

Ad Hoc Play (Librom, Network, Ad Hoc Play) works between copies of the game:
start ss-delta.exe for player 1 and run-player2.bat (ss-delta.exe --player 2)
for player 2, up to --player 4. One copy creates a room, the others use Search
for Room. Each player has its own saves (ux0\user\0<N-1>, copied from player
1's on its first start), log and config (ss-delta\player<N>);
ss-delta-player<N>.ini next to ss-delta.ini overrides settings for player N.
[multiplayer] in ss-delta.ini: network = local (copies on this PC) or lan
(PCs in one network: each runs ss-delta.exe; allow it through the firewall),
and gamepad = 1-4 to give each copy its own gamepad.

ss-delta is built from Vita3K (https://github.com/Vita3K/Vita3K) and is under
the GNU GPL version 2. The ssd_aot_*.dll files and the game files are derived
from your own copy of the game: do not share them.
"@ | Set-Content -Encoding utf8 (Join-Path $out 'README.txt')

# Ad Hoc Play's second player (ss-delta.exe --player 2)
"@start `"`" `"%~dp0ss-delta.exe`" --player 2" | Set-Content -Encoding ascii (Join-Path $out 'run-player2.bat')

$size = (Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
"{0}: {1:N0} MB" -f $out, $size
