# Unattended test matrix: each emulator x renderer x boot target.
# Boots straight into a map through the game's BootSequence, samples FPS from the
# window title every 0.5 s, takes background screenshots, records crashes and logs.
# Nothing needs keyboard focus; you can keep using the PC (it will be busy though).
param(
    [string[]]$Emu = @('ours', 'upstream', 'plus'),
    [string[]]$Renderer = @('Vulkan', 'OpenGL'),
    [string[]]$Boot = @('Elder', 'Harpy'),
    [int]$Seconds = 60
)
. (Join-Path $PSScriptRoot 'common.ps1')

# powershell -File passes "a,b" as one string; accept both forms.
$Emu = @($Emu -split ',' | Where-Object { $_ })
$Renderer = @($Renderer -split ',' | Where-Object { $_ })
$Boot = @($Boot -split ',' | Where-Object { $_ })
foreach ($e in $Emu) { if (-not $Emulators.Contains($e)) { throw "unknown -Emu $e (ours, upstream, plus)" } }
foreach ($b in $Boot) { if (-not $BootTargets.Contains($b)) { throw "unknown -Boot $b ($($BootTargets.Keys -join ', '))" } }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $Results "matrix-$stamp"
New-Item -ItemType Directory -Force $out | Out-Null
$summary = Join-Path $out 'summary.csv'
'emulator,renderer,boot,outcome,seconds_alive,fps_median,fps_min,resolution' | Out-File $summary -Encoding ascii
$fpsCsv = Join-Path $out 'fps.csv'
'emulator,renderer,boot,t,fps,ms' | Out-File $fpsCsv -Encoding ascii

$gpu = (Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) (driver $($_.DriverVersion))" }) -join '; '
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
"GPU: $gpu`r`nCPU: $cpu`r`nOS: $([Environment]::OSVersion.VersionString)`r`nStarted: $stamp" | Out-File (Join-Path $out 'machine.txt') -Encoding utf8

try {
    foreach ($e in $Emu) {
        foreach ($r in $Renderer) {
            foreach ($b in $Boot) {
                $name = "$e-$r-$b"
                Write-Host "=== $name" -ForegroundColor Cyan
                Set-EmulatorConfig $e $r 0
                Set-BootSequence $BootTargets[$b]
                $p = Start-Emulator $e $r
                $t0 = Get-Date
                $samples = @()
                $outcome = 'ok'
                $shots = @{ 30 = $false; $Seconds = $false }
                while ($true) {
                    Start-Sleep -Milliseconds 500
                    $elapsed = ((Get-Date) - $t0).TotalSeconds
                    if ($p.HasExited) { $outcome = "crashed (exit code $($p.ExitCode))"; break }
                    $title = $null
                    $h = [Win32Cap]::FindWindow($p.Id, 'FPS', [ref]$title)
                    if ($h -ne [IntPtr]::Zero) {
                        $m = Parse-Title $title
                        if ($m) {
                            $samples += $m
                            "$e,$r,$b,$([math]::Round($elapsed,1)),$($m.Fps),$($m.Ms)" | Out-File $fpsCsv -Append -Encoding ascii
                        }
                        foreach ($s in @($shots.Keys)) {
                            if (-not $shots[$s] -and $elapsed -ge $s) {
                                [Win32Cap]::Capture($h, (Join-Path $out "$name-$($s)s.png"))
                                $shots[$s] = $true
                            }
                        }
                    }
                    if ($elapsed -ge $Seconds + 1) { break }
                }
                $alive = [math]::Round(((Get-Date) - $t0).TotalSeconds)
                if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Start-Sleep -Seconds 2 }
                $log = Join-Path $Emulators[$e] 'portable\vita3k.log'
                if (Test-Path $log) { Copy-Item $log (Join-Path $out "$name.log") }
                # FPS stats over the second half of the run (after loading)
                $late = @($samples | Select-Object -Last ([math]::Max(1, [int]($samples.Count / 2))) | ForEach-Object { $_.Fps })
                $med = ''; $min = ''; $res = ''
                if ($samples.Count -gt 0) {
                    $sorted = $late | Sort-Object
                    $med = $sorted[[int]($sorted.Count / 2)]; $min = $sorted[0]
                    $res = "$($samples[-1].W)x$($samples[-1].H)"
                }
                if ($outcome -eq 'ok' -and $samples.Count -eq 0) { $outcome = 'no game window / no frames' }
                "$e,$r,$b,$outcome,$alive,$med,$min,$res" | Out-File $summary -Append -Encoding ascii
                Write-Host "    $outcome; median fps $med, min $min"
            }
        }
    }
}
finally {
    Restore-BootSequence
    Get-Process Vita3K -ErrorAction SilentlyContinue | Stop-Process -Force
}

$zip = "$out.zip"
Compress-Archive -Path "$out\*" -DestinationPath $zip -Force
Write-Host ''
Write-Host "Done. Results: $out" -ForegroundColor Green
Write-Host "Send back: $zip"
Get-Content $summary
