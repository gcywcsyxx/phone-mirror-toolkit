param([switch]$NoLaunch)
$ErrorActionPreference = 'Continue'

$Tools = $PSScriptRoot
if (-not $Tools) { $Tools = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$adb    = Join-Path $Tools 'bin\platform-tools\adb.exe'
$srv    = Join-Path $Tools 'pair_server.py'
$png    = Join-Path $Tools 'pair-qr.png'
$mirror = Join-Path $Tools 'mirror.ps1'
if (-not (Test-Path $adb)) { $adb = 'C:\Users\Jerry\Tools\platform-tools\adb.exe' }
if (-not (Test-Path $srv)) { $srv = 'C:\Users\Jerry\Tools\pair_server.py' }

function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }

$py = $null
foreach ($c in @('python','py')) {
    $g = Get-Command $c -EA SilentlyContinue
    if ($g) { $py = $g.Source; break }
}
if (-not $py -and (Test-Path 'C:\Users\Jerry\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe')) {
    $py = 'C:\Users\Jerry\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe'
}
if (-not $py) { Say 'Python not found. Install it, then rerun.' Red; Read-Host 'Enter'; exit 1 }

$env:ADB = $adb
& $adb start-server 2>&1 | Out-Null

Say ''
Say '============================================================' Cyan
Say '  SCAN TO MIRROR' Cyan
Say '============================================================' Cyan
Say ''
Say '  1. Phone: Settings > More settings > Developer options' White
Say '           > Wireless debugging > Pair device with QR code' White
Say '  2. Point the phone at the QR window on this PC' White
Say ''
Say '  Keep this window open. Waiting up to 180 seconds.' DarkGray
Say ''

$log = Join-Path $Tools 'pair-server.log'
if (Test-Path $log) { Remove-Item $log -Force -EA SilentlyContinue }

$job = Start-Job -ScriptBlock { param($p,$s) & $p $s 2>&1 } -ArgumentList $py,$srv

$ready = $false
for ($i=1; $i -le 50; $i++) {
    Start-Sleep -Milliseconds 400
    $o = Receive-Job $job -Keep 2>&1
    if ($o -match 'READY') { $ready = $true; $o | Set-Content $log -Encoding UTF8; break }
    if ($o -match 'QR_FAIL|CERT_FAIL') { $ready = $false; break }
}
if (-not $ready) {
    Say 'pair server failed:' Red
    Receive-Job $job -Keep 2>&1 | ForEach-Object { '  ' + $_ }
    Stop-Job $job -EA SilentlyContinue; Remove-Job $job -Force -EA SilentlyContinue
    Read-Host 'Enter'; exit 1
}

if (Test-Path $png) {
    $opened = $false
    try {
        Start-Process -FilePath $png -ErrorAction Stop
        $opened = $true
    } catch {
        try {
            & cmd.exe /c start '' $png 2>&1 | Out-Null
            $opened = $true
        } catch { $opened = $false }
    }
    if ($opened) {
        Say '  QR opened. Scan it now.' Green
    } else {
        Say '  Could not open the QR automatically.' Yellow
        Say ('  Open this file yourself, then scan it:  ' + $png) White
    }
} else {
    Say 'QR image missing' Red
    Stop-Job $job -EA SilentlyContinue; Remove-Job $job -Force -EA SilentlyContinue
    Read-Host 'Enter'; exit 1
}

Say ''
Say '  Waiting for the phone ...' Yellow
Write-Host '  ' -NoNewline

$paired = $false
for ($i=1; $i -le 150; $i++) {
    Start-Sleep 1
    if ($i % 5 -eq 0) { Write-Host '.' -NoNewline }
    $o = Receive-Job $job -Keep 2>&1
    if ($o -match 'PAIRED_OK|SENT_RESULT=True') { $paired = $true; $o | Set-Content $log -Encoding UTF8; break }
    if ($o -match 'TIMEOUT') { break }
}
Say ''

$dev = $null
for ($i=1; $i -le 20; $i++) {
    $raw = (& $adb devices 2>&1 | Out-String)
    $hit = ($raw -split "`r?`n") | Where-Object { $_ -match '\tdevice' -and $_ -notmatch 'no serial' } | Select-Object -First 1
    if ($hit) { $dev = ($hit -split '\t')[0].Trim(); break }
    Start-Sleep 2
}

Stop-Job $job -EA SilentlyContinue; Remove-Job $job -Force -EA SilentlyContinue

if (-not $dev) {
    Say 'Pairing did not complete.' Yellow
    if (Test-Path $log) { Get-Content $log | ForEach-Object { '  ' + $_ } }
    Read-Host 'Enter'; exit 2
}

Say ('  Paired: ' + $dev) Green
if ($NoLaunch) { exit 0 }

$raw2 = (& $adb devices 2>&1 | Out-String)
$all = @(($raw2 -split "`r?`n") | Where-Object { $_ -match '\tdevice' -and $_ -notmatch 'no serial' } | ForEach-Object { ($_ -split '\t')[0].Trim() })
if ($all.Count -gt 1) {
    foreach ($d in $all) { if ($d -ne $dev) { & $adb disconnect $d 2>&1 | Out-Null } }
    Start-Sleep 2
}

Say ''
Say '  Starting mirror ...' Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $mirror -Serial $dev