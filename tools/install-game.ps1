# From the player's own dump to a playable ss-delta folder (Phase 6 install flow, D11):
#   1. install the firmware update(s) and the game dump into a fresh Vita file system,
#   2. check that the game is the 1.30 build ss-delta is made for,
#   3. run the game briefly to write every module's ELF as loaded (decrypted, relocated),
#   4. recompile the game's and the firmware's modules and build them,
#   5. lay out the folder (tools\make-dist.ps1).
# Everything it writes is derived from the player's dump and firmware: it stays local (D2).
#   . .\tools\devshell.ps1
#   .\tools\install-game.ps1 -Dump <NoNpDrm zip|vpk|folder> -Firmware <PSVUPDAT.PUP>[,<PSP2UPDAT.PUP>] [-Name ss-delta]
# Needs: tools\build-vita3k.ps1 run first (ss-delta.exe with the JIT), Python with capstone, MSVC.
param(
    [Parameter(Mandatory)][string]$Dump,
    [Parameter(Mandatory)][string[]]$Firmware,
    [string]$Name = 'ss-delta',
    [int]$DumpSeconds = 45
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'build\vita3k\bin\RelWithDebInfo'
$exe = Join-Path $bin 'ss-delta.exe'
if (-not (Test-Path $exe)) { throw 'build ss-delta.exe first (tools\build-vita3k.ps1)' }
if (-not $env:VCToolsVersion) { throw 'run . .\tools\devshell.ps1 first' }
$out = Join-Path $root "dist\$Name"
$fs = Join-Path $out 'fs'
$work = Join-Path $root "build\install-$Name"
New-Item -ItemType Directory -Force $fs, $work | Out-Null

function Invoke-SsDelta([string[]]$Arguments, [hashtable]$Environment = @{}) {
    foreach ($k in $Environment.Keys) { Set-Item "Env:$k" $Environment[$k] }
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $Arguments -WorkingDirectory $bin -Wait -PassThru
    } finally {
        foreach ($k in $Environment.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    }
    return $p.ExitCode
}

# 1. firmware and game
foreach ($pup in $Firmware) {
    "installing firmware $pup"
    if ((Invoke-SsDelta @('--vita-fs', "`"$fs`"", '--install-firmware', "`"$((Resolve-Path -LiteralPath $pup).Path)`"")) -ne 0) { throw "firmware install failed: $pup" }
}
"installing $Dump"
if ((Invoke-SsDelta @('--vita-fs', "`"$fs`"", '--install', "`"$((Resolve-Path -LiteralPath $Dump).Path)`"")) -ne 0) { throw "game install failed: $Dump" }

# 2. the 1.30 build (docs/hashes.md)
$eboot = Join-Path $fs 'ux0\app\PCSA00152\eboot.bin'
if (-not (Test-Path $eboot)) { throw "no PCSA00152 in $fs after installing" }
$hash = (Get-FileHash $eboot -Algorithm SHA256).Hash.ToLower()
if ($hash -ne 'a13a1bfed7f58aa743fc8c0e2db166438ac3af0f2d92b107c2e3f84b92e64fed') {
    throw "eboot.bin is not the 1.30 build ss-delta supports (SHA-256 $hash): install the 1.30 patch with the game"
}
'eboot.bin: 1.30'

# 3. the modules' ELFs, written as the game loads them (on the JIT: nothing is recompiled yet)
$dumps = Join-Path $bin 'ss-delta\elfdumps\PCSA00152'
if (Test-Path $dumps) { Get-ChildItem $dumps -Filter '*.elf' | Remove-Item }
"running the game for $DumpSeconds s to write the modules"
Invoke-SsDelta @('--vita-fs', "`"$fs`"", '--dump-elfs', $DumpSeconds) @{ SSD_AOT = 'none'; SSD_AOT_NATIVE = '0' } | Out-Null
$modules = [ordered]@{
    eboot = 'eboot'; libc = 'libc'; libfios2 = 'libfios2'; libult = 'libult'
    sysmodule = 'fw_sysmodule'; libSceFt2 = 'fw_libSceFt2'; libpvf = 'fw_libpvf'
    libscemp4 = 'fw_libscemp4'; libsceavplayer = 'fw_libsceavplayer'
}
$elf = Join-Path $work 'elf'
New-Item -ItemType Directory -Force $elf | Out-Null
foreach ($m in $modules.Keys) {
    $src = Get-ChildItem $dumps -Filter "*_$m.elf" | Select-Object -First 1
    if (-not $src) { throw "the game did not load $m within $DumpSeconds s: try a longer -DumpSeconds" }
    Copy-Item $src.FullName (Join-Path $elf "$m.elf") -Force
}

# 4. recompile and build
$gen = Join-Path $work 'generated'
foreach ($m in $modules.Keys) {
    "recompiling $m"
    python -I (Join-Path $root 'recomp\recompile.py') (Join-Path $elf "$m.elf") (Join-Path $gen $modules[$m]) | Select-String 'recompiled|code hash'
    if ($LASTEXITCODE) { throw "recompiling $m failed" }
}
$build = Join-Path $work 'build'
$list = ($modules.Values -join ';')
$ErrorActionPreference = 'Continue'
cmake -S (Join-Path $root 'recomp') -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release "-DGENERATED_DIR=$gen" "-DRECOMP_MODULES=$list" -DRECOMP_TESTS=OFF | Out-Null
'compiling (this takes a while)'
cmake --build $build | Select-String ' error |FAILED|Linking CXX shared'
if ($LASTEXITCODE) { throw 'compiling the recompiled modules failed' }
$ErrorActionPreference = 'Stop'

# 5. the folder
# the Vita file system is the folder's own fs\, ss-delta.ini's default
& (Join-Path $PSScriptRoot 'make-dist.ps1') -Name $Name -RecompiledDir $build
