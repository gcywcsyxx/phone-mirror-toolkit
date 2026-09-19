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
if (-not (Test-Path $adb)) { $adb = 'adb' }
if (-not (Test-Path $scrcpy)) { $scrcpy = 'scrcpy' }

function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }
if (-not (Test-Path $scrcpy)) { Say ('scrcpy missing: ' + $scrcpy) Red; Read-Host 'Enter'; exit 1 }
if (-not (Test-Path $adb))    { Say ('adb missing: ' + $adb) Red;    Read-Host 'Enter'; exit 1 }

$env:ADB = $adb
& $adb start-server 2>&1 | Out-Null

function Get-Dev {
    $raw = (& $adb devices 2>&1 | Out-String)
    $res = New-Object System.Collections.ArrayList
    foreach ($ln in ($raw -split "`r?`n")) {
        if ($ln -match '\tdevice' -and $ln -notmatch 'no serial') {
            $sn = ($ln -split '\t')[0].Trim()
            if ($sn) { [void]$res.Add([string]$sn) }
        }
    }
    return ,$res.ToArray()
}

# drop stale/duplicate transports so scrcpy sees exactly one device
$raw_all = (& $adb devices 2>&1 | Out-String)
foreach ($ln in ($raw_all -split "`r?`n")) {
    if ($ln -match '\toffline') {
        $sn = ($ln -split '\t')[0].Trim()
        if ($sn) { Say ('  dropping offline: ' + $sn) DarkGray; & $adb disconnect $sn 2>&1 | Out-Null }
    }
}

$dev = @(Get-Dev)
if ($dev.Count -gt 1) {
    Say ('Found ' + $dev.Count + ' connections. Keeping one.') Yellow
    $keep = [string]$Serial
    if (-not $keep) {
        $cand = $dev | Where-Object { $_ -like '*_adb-tls-connect._tcp' } | Select-Object -First 1
        if ($cand) { $keep = [string]$cand } else { $keep = [string]$dev[0] }
    }
    foreach ($d in $dev) { if ($d -ne $keep) { Say ('  disconnect ' + $d) DarkGray; & $adb disconnect $d 2>&1 | Out-Null } }
    Start-Sleep 2
    $dev = @(Get-Dev)
}

if ($dev.Count -eq 0) {
    Say 'No authorized phone.' Yellow
    Say 'Run the Scan-to-Mirror helper first.' Cyan
    & $adb devices -l
    Read-Host 'Enter'
    exit 2
}

$target = [string]$Serial
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