# Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$RunTests,
    [switch]$NoRebootPrompt
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Virtual Display Driver - Installation Script" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Ensure Admin, auto-elevate if run in interactive shell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Administrator privileges are required. Requesting elevation..." -ForegroundColor Yellow
    try {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($RunTests) { $argList += " -RunTests" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit 0
    } catch {
        Write-Error "Failed to elevate. Please run PowerShell as Administrator."
        exit 1
    }
}

# 1. Test-signing check & configuration
Write-Host "[1/5] Checking Windows Test-Signing status..." -ForegroundColor Yellow
$bcdOutput = bcdedit /enum "{current}" 2>&1 | Out-String
$testSigningOn = $bcdOutput -match "testsigning\s+Yes"
$rebootNeeded = $false

if (-not $testSigningOn) {
    Write-Host "      Enabling test signing: bcdedit /set testsigning on" -ForegroundColor Yellow
    $bcdResult = bcdedit /set testsigning on 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      Test signing successfully enabled." -ForegroundColor Green
        $rebootNeeded = $true
    } else {
        Write-Warning "      Could not enable test signing automatically. Error: $bcdResult"
        Write-Warning "      If Secure Boot is enabled, test signing cannot be turned on until Secure Boot is disabled in UEFI."
    }
} else {
    Write-Host "      Test signing is already enabled." -ForegroundColor Green
}

# 2. Install Certificate if present
$certPath = Join-Path $ScriptDir "DriverCertificate.cer"
if (-not (Test-Path $certPath)) { $certPath = Join-Path $ScriptDir "..\DriverCertificate.cer" }
if (-not (Test-Path $certPath)) { $certPath = Join-Path $ScriptDir "..\target\output\DriverCertificate.cer" }

if (Test-Path $certPath) {
    Write-Host "[2/5] Installing driver certificate: $certPath..." -ForegroundColor Yellow
    certutil -addstore -f root $certPath | Out-Null
    certutil -addstore -f TrustedPublisher $certPath | Out-Null
    Write-Host "      DriverCertificate.cer imported to Root and TrustedPublisher." -ForegroundColor Green
} else {
    Write-Host "[2/5] DriverCertificate.cer not found (skipping)." -ForegroundColor Gray
}

# 3. Import registry defaults
$regPath = Join-Path $ScriptDir "install.reg"
if (-not (Test-Path $regPath)) { $regPath = Join-Path $ScriptDir "files\install.reg" }
if (-not (Test-Path $regPath)) { $regPath = Join-Path $ScriptDir "..\target\output\install.reg" }

if (Test-Path $regPath) {
    Write-Host "[3/5] Importing registry settings: $regPath..." -ForegroundColor Yellow
    reg import $regPath | Out-Null
    Write-Host "      Registry settings imported." -ForegroundColor Green
} else {
    Write-Host "[3/5] install.reg not found (skipping)." -ForegroundColor Gray
}

# 4. Locate nefconc.exe
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
    elseif (Test-Path (Join-Path $ScriptDir "..\target\output\nefconc.exe")) { $nefcon = Join-Path $ScriptDir "..\target\output\nefconc.exe" }
}

$infPath = Join-Path $ScriptDir "VirtualDisplayDriver.inf"
if (-not (Test-Path $infPath)) { $infPath = (Resolve-Path (Join-Path $ScriptDir "..\target\output\VirtualDisplayDriver.inf") -ErrorAction SilentlyContinue).Path }

if (-not (Test-Path $infPath)) {
    Write-Error "VirtualDisplayDriver.inf not found in $ScriptDir or target output directory"
    exit 1
}

Write-Host "      Using driver package: $infPath" -ForegroundColor Gray

# 5. Create device node & install driver package
if ($nefcon) {
    Write-Host "[4/5] Creating device node using $nefcon..." -ForegroundColor Yellow
    & $nefcon --remove-device-node --hardware-id "Root\VirtualDisplayDriver" --class-guid "4d36e968-e325-11ce-bfc1-08002be10318" 2>&1 | Out-Null
    & $nefcon --create-device-node --hardware-id "Root\VirtualDisplayDriver" --class-name "Display" --class-guid "4d36e968-e325-11ce-bfc1-08002be10318"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create device node."
        exit $LASTEXITCODE
    }

    Write-Host "[5/5] Installing driver package..." -ForegroundColor Yellow
    & $nefcon --install-driver --inf-path $infPath
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "nefcon install reported an issue, falling back to pnputil..."
        pnputil /add-driver $infPath /install
    }
} else {
    Write-Host "[4/5] nefconc.exe not found. Falling back to pnputil..." -ForegroundColor Yellow
    Write-Host "[5/5] Installing driver package..." -ForegroundColor Yellow
    pnputil /add-driver $infPath /install
}

Start-Sleep -Seconds 2

# Verify device status in Device Manager
Write-Host ""
Write-Host "Verifying Virtual Display Driver in Device Manager..." -ForegroundColor Cyan
$device = Get-PnpDevice -FriendlyName "*Virtual Display*" -ErrorAction SilentlyContinue | Where-Object { $_.Class -eq "Display" }
if (-not $device) {
    $device = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "*VirtualDisplayDriver*" }
}

if ($device) {
    Write-Host "Device detected: $($device.FriendlyName) [$($device.InstanceId)]" -ForegroundColor Green
    Write-Host "Status:          $($device.Status)" -ForegroundColor $(if ($device.Status -eq "OK") { "Green" } else { "Yellow" })
} else {
    Write-Warning "Device node not yet visible under Display adapters."
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Driver installation finished!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Cyan

if ($rebootNeeded) {
    Write-Host ""
    Write-Host "[IMPORTANT] Windows Test Signing was enabled for the first time." -ForegroundColor Magenta
    Write-Host "A system reboot is required before Windows will load the driver." -ForegroundColor Magenta
}

# Run functional test suite if requested
$testScript = Join-Path $ScriptDir "test-phase6.ps1"
if ($RunTests -and (Test-Path $testScript)) {
    Write-Host ""
    Write-Host "Launching Phase 6 Verification Test Suite..." -ForegroundColor Cyan
    & $testScript -OutputDir $ScriptDir
}
