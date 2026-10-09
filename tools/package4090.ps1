# Build dist\ss-delta-vita3k-test: our Vita3K fork, upstream and Vita3K-Plus in portable mode, the shared
# Vita file system (installed game + licence + firmware) and the test scripts.
# The output contains the owner's decrypted dump: it is for the owner's own PCs only.
param(
    [string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\ss-delta-vita3k-test'),
    [switch]$Zip
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$ext = Join-Path $repo 'extracted'
$src = @{
    'vita3k'      = Join-Path $ext 'vita3k'
    'vita3k-plus' = Join-Path $ext 'vita3k-plus\1.2'
    # our fork (third_party/vita3k), built by tools/build-vita3k.ps1; the PDB is kept so a
    # crash on the other PC logs a symbolised stack
    'vita3k-ours' = Join-Path $repo 'build\vita3k\bin\RelWithDebInfo'
}

function Invoke-Robocopy([string]$From, [string]$To, [string[]]$ExtraArgs) {
    & robocopy $From $To /E /NFL /NDL /NJH /NJS /NP @ExtraArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy $From -> $To failed ($LASTEXITCODE)" }
}

if (Get-Process Vita3K -ErrorAction SilentlyContinue) { throw 'Close Vita3K first.' }
if (Test-Path $Out) {
    # Test runs turn portable\fs into junctions to vitafs: unlink them first so the
    # recursive delete never walks into the shared game files through a link.
    foreach ($name in $src.Keys) {
        $link = Join-Path $Out "$name\portable\fs"
        if ((Test-Path -LiteralPath $link) -and (Get-Item -LiteralPath $link -Force).LinkType -eq 'Junction') {
            [IO.Directory]::Delete($link)
        }
    }
    Remove-Item -LiteralPath $Out -Recurse -Force
}
New-Item -ItemType Directory -Force $Out | Out-Null

foreach ($name in $src.Keys) {
    $from = $src[$name]
    $to = Join-Path $Out $name
    Write-Host "emulator: $name"
    # Program files only: no VitaFS, caches, logs, GUI state or our run outputs.
    Invoke-Robocopy $from $to @('/XD', 'fs', 'cache', 'shaderlog', 'texturelog', 'gui-configs', 'patch', 'portable', 'screenshots',
        '/XF', 'config.yml', 'config.yml.*', '*.log', '*.out', '*.ilk')
    $portable = Join-Path $to 'portable'
    New-Item -ItemType Directory -Force $portable | Out-Null
    Copy-Item (Join-Path $from 'config.yml') (Join-Path $portable 'config.yml') -Force
    # pref-path is rewritten by the scripts at every launch; start from a neutral value.
    $cfg = Join-Path $portable 'config.yml'
    $text = [IO.File]::ReadAllText($cfg)
    $text = [regex]::Replace($text, '(?m)^pref-path:.*$', 'pref-path: ""')
    $text = [regex]::Replace($text, '(?m)^keyboard-take-screenshot:.*$', 'keyboard-take-screenshot: F12')
    $text = [regex]::Replace($text, '(?m)^discord-rich-presence:.*$', 'discord-rich-presence: false')
    # only loaded where the Vulkan SDK is installed; keep runs comparable across PCs
    $text = [regex]::Replace($text, '(?m)^validation-layer:.*$', 'validation-layer: false')
    [IO.File]::WriteAllText($cfg, $text)
}

Write-Host 'vitafs (about 3.4 GB)'
$fsFrom = Join-Path $src['vita3k'] 'fs'
Invoke-Robocopy $fsFrom (Join-Path $Out 'vitafs') @('/XD', 'savedata', 'PUP_DEC')
$ini = Join-Path $Out 'vitafs\ux0\app\PCSA00152\resource\config.ini'
if (Test-Path "$ini.orig") { Copy-Item "$ini.orig" $ini -Force }

Write-Host 'scripts'
$pkg = Join-Path $PSScriptRoot 'pkg4090'
New-Item -ItemType Directory -Force (Join-Path $Out 'scripts') | Out-Null
Copy-Item (Join-Path $pkg '*.ps1') (Join-Path $Out 'scripts') -Force
Copy-Item (Join-Path $pkg '*.bat'), (Join-Path $pkg 'README.txt') $Out -Force
New-Item -ItemType Directory -Force (Join-Path $Out 'results') | Out-Null

$size = (Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("package: {0} ({1:N2} GB)" -f $Out, ($size / 1GB))

if ($Zip) {
    $7z = 'C:\Program Files\7-Zip\7z.exe'
    $zipPath = "$Out.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath }
    # Store only: the game archives are already compressed.
    & $7z a -tzip -mx0 $zipPath "$Out\*" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7-Zip failed ($LASTEXITCODE)" }
    Write-Host ("zip: {0} ({1:N2} GB)" -f $zipPath, ((Get-Item $zipPath).Length / 1GB))
}
