# install.ps1 -- set up Phone Mirror Toolkit on a new machine
# usage: powershell -ExecutionPolicy Bypass -File install.ps1
param([string]$Target = "$env:USERPROFILE\Tools\PhoneMirror")
$ErrorActionPreference = 'Stop'
function Say($m,$c='Gray'){ Write-Host $m -ForegroundColor $c }

# $PSScriptRoot is reliable under -File; MyInvocation is the fallback
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

Say ''
Say '  Phone Mirror Toolkit - Installer' Cyan
Say ''
Say ('  Source : ' + $here) DarkGray
Say ('  Target : ' + $Target) DarkGray
Say ''

if (-not (Test-Path (Join-Path $here 'core'))) {
    Say '  ERROR: run this from the extracted toolkit folder.' Red
    Say '         core/ and bin/ must sit next to install.ps1.' Red
    Read-Host 'Enter'; exit 1
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item (Join-Path $here 'core\*') $Target -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $Target 'bin') | Out-Null
Copy-Item (Join-Path $here 'bin\*') (Join-Path $Target 'bin') -Recurse -Force
Say '  files copied' Green

# The scripts resolve their own directory at runtime (PSScriptRoot / __file__),
# so no hard-coded path rewriting is required.
Say '  runtime paths are self-locating' Green

# --- python dependencies -------------------------------------------------
$py = $null
foreach ($cand in @('python','py')) {
    $g = Get-Command $cand -ErrorAction SilentlyContinue
    if ($g) { $py = $g.Source; break }
}
if ($py) {
    Say '  installing python deps (qrcode, cryptography, pillow)...' Yellow
    & $py -m pip install --quiet --disable-pip-version-check qrcode cryptography pillow 2>&1 | Out-Null
    Say '  python deps ok' Green
} else {
    Say '  WARNING: python not found - QR pairing will not work' Yellow
    Say '           install Python 3.x, then rerun this script' Yellow
}

# --- desktop shortcuts ---------------------------------------------------
$desk = [Environment]::GetFolderPath('Desktop')
$nl   = [Environment]::NewLine
$mk   = { param($ps1) '@echo off' + $nl + 'chcp 65001 >nul' + $nl +
          'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $ps1 + '"' + $nl +
          'if errorlevel 1 pause' }

$shorts = @{
    'Phone Mirror.bat'   = (& $mk (Join-Path $Target 'mirror.ps1'))
    'Scan to Mirror.bat' = (& $mk (Join-Path $Target 'scan-mirror.ps1'))
}
foreach ($k in $shorts.Keys) {
    Set-Content (Join-Path $desk $k) $shorts[$k] -Encoding ASCII
    Say ('  desktop shortcut: ' + $k) Green
}

Say ''
Say '  DONE' Green
Say ''
Say '    Phone Mirror.bat   - mirror a USB or already-paired device' White
Say '    Scan to Mirror.bat - show a QR; phone scans it; mirroring starts' White
Say ''