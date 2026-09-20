param(
    [string]$Serial = '',
    [int]$MaxSize = 1280,
    [int]$MaxFps = 60,
    [switch]$NoAudio,
    [switch]$Fullscreen,
    [switch]$List
)
$ErrorActionPreference = 'Continue'

# locate adb + scrcpy: prefer the toolkit layout, fall back to the dev layout
$Tools = $PSScriptRoot
if (-not $Tools) { $Tools = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$adb    = Join-Path $Tools 'bin\platform-tools\adb.exe'
$scrcpy = Join-Path $Tools 'bin\scrcpy\scrcpy.exe'
if (-not (Test-Path $adb))    { $adb    = 'C:\Users\Jerry\Tools\platform-tools\adb.exe' }
if (-not (Test-Path $scrcpy)) { $scrcpy = 'C:\Users\Jerry\Tools\scrcpy\scrcpy-win64-v4.1\scrcpy.exe' }

function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }
if (-not (Test-Path $scrcpy)) { Say ('scrcpy missing: ' + $scrcpy) Red; Read-Host 'Enter'; exit 1 }
if (-not (Test-Path $adb))    { Say ('adb missing: ' + $adb) Red;    Read-Host 'Enter'; exit 1 }

$env:ADB = $adb
& $adb start-server 2>&1 | Out-Null

function Get-Dev {
    # returns a STRING array of device serials (never collapses to one string)
    $raw = (& $adb devices 2>&1 | Out-String)
    $res = New-Object System.Collections.ArrayList
    foreach ($ln in ($raw -split "`r?`n")) {
        if ($ln -match '\tdevice' -and $ln -notmatch 'no serial') {
            $sn = ($ln -split '\t')[0].Trim()
            if ($sn) { [void]$res.Add([string]$sn) }
        }
    }
    $arr = New-Object string[] $res.Count
    for ($i = 0; $i -lt $res.Count; $i++) { $arr[$i] = [string]$res[$i] }
    return $arr
}

# drop stale wireless transports (USB devices cannot be disconnected this way)
$raw_all = (& $adb devices 2>&1 | Out-String)
foreach ($ln in ($raw_all -split "`r?`n")) {
    if ($ln -match '\toffline') {
        $sn = ($ln -split '\t')[0].Trim()
        if ($sn -and $sn -match ':') { Say ('  dropping offline: ' + $sn) DarkGray; & $adb disconnect $sn 2>&1 | Out-Null }
    }
}

$dev = Get-Dev
if ($dev.Count -eq 0) {
    Say 'No authorized phone.' Yellow
    Say 'Run the Scan-to-Mirror helper first.' Cyan
    & $adb devices -l
    Read-Host 'Enter'
    exit 2
}

$target = [string]$Serial

if (-not $target -and $dev.Count -gt 1) {
    # several devices: let the user choose instead of guessing
    Say ''
    Say ('  ' + $dev.Count + ' devices connected. Pick one:') Yellow
    Say ''
    $models = @()
    for ($i = 0; $i -lt $dev.Count; $i++) {
        $m = (& $adb -s $dev[$i] shell getprop ro.product.model 2>&1 | Out-String).Trim()
        $models += $m
        Say ('    [' + ($i+1) + ']  ' + $dev[$i]) White
        Say ('         ' + $m) DarkGray
    }
    Say ''
    $pick = Read-Host '  Enter number (default 1)'
    $idx = 0
    if ($pick -match '^\d+$') { $idx = [int]$pick - 1 }
    if ($idx -lt 0 -or $idx -ge $dev.Count) { $idx = 0 }
    $target = [string]$dev[$idx]
}

if (-not $target) { $target = [string]$dev[0] }

if ($List) { Say ('Target: ' + $target) Cyan; & $adb devices -l; Read-Host 'Enter'; exit 0 }
Say ('Connected: ' + $target) Green

$a = @('--serial', $target, '--stay-awake', '--max-size', [string]$MaxSize, '--max-fps', [string]$MaxFps, '--window-title', 'Phone Mirror')
if ($NoAudio)    { $a += '--no-audio' }
if ($Fullscreen) { $a += '--fullscreen' }

Say 'Starting mirror. Close the window to stop.' Cyan
Say 'Left click = tap | Wheel = scroll | Keyboard = type | Drag file = install' DarkGray
Say ''
& $scrcpy @a
if ($LASTEXITCODE -ne 0) { Say ('scrcpy exit: ' + $LASTEXITCODE) Yellow; Read-Host 'Enter' }