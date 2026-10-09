# Shared helpers for the Vita3K test package (dot-source this file).
# Layout, relative to the package root:
#   vita3k\        upstream Vita3K build   (portable\ holds its config, logs, caches)
#   vita3k-plus\   Vita3K-Plus build       (same)
#   vitafs\        the shared Vita file system: installed game, licence, firmware
#   results\       everything the scripts record

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$VitaFs = Join-Path $Root 'vitafs'
$Results = Join-Path $Root 'results'
$TitleId = 'PCSA00152'
$GameIni = Join-Path $VitaFs "ux0\app\$TitleId\resource\config.ini"

$Emulators = @{
    'upstream' = Join-Path $Root 'vita3k'
    'plus'     = Join-Path $Root 'vita3k-plus'
}

$BootTargets = [ordered]@{
    'Title'     = 'Title'
    'DebugMenu' = 'DebugMenu'
    'Elder'     = 'ELDER DEFAULT MAP'
    'Harpy'     = '[G] HarpyBattle Walhalla'
}

if (-not ('Win32Cap' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32Cap {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    // Visible top-level windows of a process whose title contains the marker.
    public static IntPtr FindWindow(int pid, string marker, out string title) {
        IntPtr found = IntPtr.Zero; string t = null;
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
                if (sb.ToString().Contains(marker)) { found = h; t = sb.ToString(); return false; }
            }
            return true;
        }, IntPtr.Zero);
        title = t; return found;
    }

    // PrintWindow(PW_CLIENTONLY | PW_RENDERFULLCONTENT): works while the window is in the background.
    public static void Capture(IntPtr h, string path) {
        RECT r; GetClientRect(h, out r);
        int w = Math.Max(1, r.R - r.L), ht = Math.Max(1, r.B - r.T);
        using (var bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            PrintWindow(h, hdc, 3);
            g.ReleaseHdc(hdc);
            bmp.Save(path, ImageFormat.Png);
        }
    }
}
'@
}
[void][Win32Cap]::SetProcessDPIAware()

function Set-YamlValue([string]$Path, [string]$Key, [string]$Value) {
    $text = [IO.File]::ReadAllText($Path)
    $pattern = '(?m)^' + [regex]::Escape($Key) + ':.*$'
    if ($text -notmatch $pattern) { throw "$Key not found in $Path" }
    $text = [regex]::Replace($text, $pattern, "${Key}: $Value")
    [IO.File]::WriteAllText($Path, $text)
}

# In portable mode upstream Vita3K always uses portable\fs (config.cpp ignores pref-path),
# so portable\fs is made a directory junction to the shared vitafs. Junctions need no admin
# rights. They store an absolute target, so the link is recreated if the package moved.
function Set-FsLink([string]$Emu) {
    $link = Join-Path $Emulators[$Emu] 'portable\fs'
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.LinkType -eq 'Junction') {
            if ((@($item.Target)[0]).TrimEnd('\') -eq $VitaFs.TrimEnd('\')) { return }
            [IO.Directory]::Delete($link)   # removes the link only, never the target
        }
        else {
            if (Get-ChildItem -LiteralPath $link -Recurse -File -Force) {
                throw "$link holds files; move them into $VitaFs or delete them, then retry"
            }
            [IO.Directory]::Delete($link, $true)   # empty placeholder directories only
        }
    }
    New-Item -ItemType Junction -Path $link -Target $VitaFs | Out-Null
}

# Point an emulator at the shared vitafs and set renderer and volume.
function Set-EmulatorConfig([string]$Emu, [string]$Renderer, [int]$Volume) {
    Set-FsLink $Emu
    $cfg = Join-Path $Emulators[$Emu] 'portable\config.yml'
    Set-YamlValue $cfg 'pref-path' '""'
    Set-YamlValue $cfg 'backend-renderer' $Renderer
    Set-YamlValue $cfg 'audio-volume' $Volume
}

# Set the game's BootSequence (retail block of resource\config.ini). Keeps config.ini.orig.
function Set-BootSequence([string]$Name) {
    $orig = "$GameIni.orig"
    if (-not (Test-Path $orig)) { Copy-Item $GameIni $orig }
    $lines = [IO.File]::ReadAllText($orig) -split "`r`n"
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith("BootSequence`t")) { $idx = $i } }
    $lines[$idx] = "BootSequence`t$Name"
    [IO.File]::WriteAllText($GameIni, ($lines -join "`r`n"))
}

function Restore-BootSequence {
    if (Test-Path "$GameIni.orig") { Copy-Item "$GameIni.orig" $GameIni -Force }
}

function Start-Emulator([string]$Emu, [string]$Renderer) {
    $dir = $Emulators[$Emu]
    $log = Join-Path $dir 'portable\vita3k.log'
    if (Test-Path $log) { Remove-Item $log -Force }
    Start-Process -FilePath (Join-Path $dir 'Vita3K.exe') -ArgumentList @('-B', $Renderer, '-r', $TitleId) `
        -WorkingDirectory $dir -PassThru
}

# "... | Vulkan | 30 FPS (34 ms) | 960x544 | ..." -> fps, ms, width, height
function Parse-Title([string]$Title) {
    if ($Title -match '\| (\d+) FPS \((\d+) ms\) \| (\d+)x(\d+)') {
        return [pscustomobject]@{ Fps = [int]$Matches[1]; Ms = [int]$Matches[2]; W = [int]$Matches[3]; H = [int]$Matches[4] }
    }
    return $null
}
