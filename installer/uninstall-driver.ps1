[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Virtual Display Driver - Uninstallation Script" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Administrator privileges are required. Requesting elevation..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit 0
    } catch {
        Write-Error "Administrator privileges are required. Please run PowerShell as administrator."
        exit 1
    }
}

$arch = $env:PROCESSOR_ARCHITECTURE
$nefcon = $null
if ($arch -ieq "ARM64") {
    if (Test-Path (Join-Path $ScriptDir "arm64\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "arm64\nefconc.exe" }
    elseif (Test-Path (Join-Path $ScriptDir "files\arm64\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "files\arm64\nefconc.exe" }
} elseif ($arch -ieq "AMD64") {
    if (Test-Path (Join-Path $ScriptDir "x64\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "x64\nefconc.exe" }
    elseif (Test-Path (Join-Path $ScriptDir "files\x64\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "files\x64\nefconc.exe" }
}

if (-not $nefcon) {
    if (Test-Path (Join-Path $ScriptDir "nefconc.exe")) { $nefcon = Join-Path $ScriptDir "nefconc.exe" }
    elseif (Test-Path (Join-Path $ScriptDir "files\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "files\nefconc.exe" }
    elseif (Test-Path (Join-Path $ScriptDir "..\rust\target\output\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "..\rust\target\output\nefconc.exe" }
}

# 1. Remove device node
if ($nefcon) {
    Write-Host "[1/3] Removing virtual display device node using $nefcon..." -ForegroundColor Yellow
    & $nefcon --remove-device-node --hardware-id "Root\VirtualDisplayDriver" --class-guid "4d36e968-e325-11ce-bfc1-08002be10318" 2>&1 | Out-Null
    Write-Host "[2/3] Removing driver package from driver store..." -ForegroundColor Yellow
    & $nefcon --remove-driver-store-package --inf-name "VirtualDisplayDriver.inf" 2>&1 | Out-Null
} else {
    Write-Host "[1/3] Attempting device removal via pnputil..." -ForegroundColor Yellow
    pnputil /remove-device /deviceid "Root\VirtualDisplayDriver" 2>&1 | Out-Null
}

# Clean any matching OEM inf from driver store via pnputil
$oemPackages = (pnputil /enum-drivers | Select-String -Pattern "VirtualDisplayDriver\.inf" -Context 3,0 | Select-String "oem\d+\.inf").Matches.Value
foreach ($pkg in $oemPackages) {
    Write-Host "      Purging published driver package $pkg from driver store..." -ForegroundColor Yellow
    pnputil /delete-driver $pkg /uninstall /force 2>&1 | Out-Null
}

# 3. Registry cleanup
$regPath = Join-Path $ScriptDir "uninstall.reg"
if (-not (Test-Path $regPath)) { $regPath = Join-Path $ScriptDir "files\uninstall.reg" }
if (-not (Test-Path $regPath)) { $regPath = Join-Path $ScriptDir "..\rust\target\output\uninstall.reg" }

if (Test-Path $regPath) {
    Write-Host "[3/3] Cleaning up registry entries: $regPath..." -ForegroundColor Yellow
    reg import $regPath | Out-Null
} else {
    Write-Host "[3/3] uninstall.reg not found (skipping)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Uninstallation completed successfully!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Cyan
