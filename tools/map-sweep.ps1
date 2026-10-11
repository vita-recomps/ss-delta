# Visual sweep of every quest map (Phase 7): for each map, start its first quest from Stage Select
# in ss-delta.exe and take screenshots after loading, with Mind's Eye on, after three camera turns
# and after a short walk. Screenshots and the per-map fps line go to -OutDir (under build/: they
# show the game, so they are never committed).
#   python -I tools/lspk.py extract <...>/retail/archive_patch3 build/lspk boot/quest_param.csv
#   python -I tools/questmaps.py build/lspk/resource/boot/quest_param.csv > build/maps.txt
#   .\tools\map-sweep.ps1 -List build\maps.txt [-Only ST17C,ST01B] [-OutDir build\maps]
# Needs ss-delta.exe built (tools/build-vita3k.ps1) with ss-delta.ini pointing at the shared install
# and the recompiled modules. About 2.5 minutes per map.
param(
    [Parameter(Mandatory)][string]$List,
    [string]$Only = '',
    [string]$OutDir = 'build\maps',
    [string]$Bin = 'build\vita3k\bin\RelWithDebInfo',
    [int]$Load = 40,
    # also save each shot at render resolution (<map>-<n>-frame.png), to check the internal resolution
    [switch]$Frames
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$drive = Join-Path $PSScriptRoot 'v3kdrive.py'
$install = 'extracted/vita3k'
New-Item -ItemType Directory -Force $OutDir | Out-Null

foreach ($line in Get-Content $List) {
    $map, $index = ($line -split '\s+')[0, 1]
    if (-not $index -or ($Only -and ($Only -split ',') -notcontains $map)) { continue }
    $k = [int]$index
    $o = ($OutDir -replace '\\', '/') + "/$map"

    # Stage Select: six rows down to "Set Quest ID", then R+right steps 10 quests, right steps 1
    $steps = @('wait 15000', 'down*6')
    for ($i = 0; $i -lt [math]::Floor($k / 10); $i++) { $steps += 'hold:r+right:300', 'wait 300' }
    if ($k % 10) { $steps += "right*$($k % 10)" }
    $steps += "shot:$o-0menu.png", 'circle', "wait $($Load * 1000)", "shot:$o-1.png"
    # Mind's Eye (D-pad down toggles it) before a boss can end the quest
    $steps += 'down', 'wait 1000', "shot:$o-1mind.png", 'down', 'wait 500'
    $steps += 'hold:rs_right:900', 'wait 500', "shot:$o-2.png"
    $steps += 'hold:rs_right:900', 'wait 500', "shot:$o-3.png"
    $steps += 'hold:rs_up:500', 'hold:rs_right:900', 'wait 500', "shot:$o-4.png"
    $steps += 'hold:ls_up:2500', 'wait 300', "shot:$o-5.png"

    if ($Frames) { $steps = $steps | ForEach-Object { if ($_ -like 'shot:*') { $_; 'frame:' + ($_.Substring(5) -replace '\.png$', '-frame.png') } else { $_ } } }

    python -I $drive $install bootseq PCSA00152 'Quest Select' | Out-Null
    try {
        python -I $drive $Bin start | Out-Null
        python -I $drive $Bin run ($steps -join ',') "$OutDir/$map-fps.csv" | Out-Null
        python -I $drive $Bin close | Out-Null
    } finally {
        python -I $drive $install bootseq PCSA00152 Title | Out-Null
    }
    $fps = Get-Content "$OutDir/$map-fps.csv" -ErrorAction SilentlyContinue | Select-Object -Skip 1 |
        ForEach-Object { $c = $_ -split ','; [pscustomobject]@{ t = [double]$c[0]; fps = [double]$c[2] } } |
        Where-Object { $_.t -gt 20 }
    '{0} {1} fps mean {2:N1} min {3}' -f $map, $k, ($fps | Measure-Object fps -Average).Average,
        ($fps | Measure-Object fps -Minimum).Minimum | Tee-Object -Append (Join-Path $OutDir 'sweep.txt')
}
