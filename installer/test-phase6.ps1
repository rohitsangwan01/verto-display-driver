# Virtual Display Driver - Phase 6 Functional Verification Test Suite
# Tests end-to-end functionality of ARM64 / x64 Virtual Display Driver
[CmdletBinding()]
param(
    [switch]$SkipMultiMonitor,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    if ($PSScriptRoot) {
        $OutputDir = $PSScriptRoot
    } else {
        $OutputDir = (Get-Location).Path
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Virtual Display Driver - Phase 6 Test Suite            " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$Passed = 0
$Failed = 0
$Skipped = 0

function Report-Result {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Details = ""
    )
    if ($Success) {
        $script:Passed++
        Write-Host " [PASS] $TestName" -ForegroundColor Green
        if ($Details) { Write-Host "        $Details" -ForegroundColor Gray }
    } else {
        $script:Failed++
        Write-Host " [FAIL] $TestName" -ForegroundColor Red
        if ($Details) { Write-Host "        $Details" -ForegroundColor Yellow }
    }
}

function Report-Skip {
    param(
        [string]$TestName,
        [string]$Reason = ""
    )
    $script:Skipped++
    Write-Host " [SKIP] $TestName" -ForegroundColor DarkYellow
    if ($Reason) { Write-Host "        Reason: $Reason" -ForegroundColor Gray }
}

# Locate CLI and Service binaries
$cliPath = Join-Path $OutputDir "virtual-display-driver-cli.exe"
if (-not (Test-Path $cliPath)) {
    $cliPath = Join-Path $OutputDir "..\rust\target\output\virtual-display-driver-cli.exe"
}
if (-not (Test-Path $cliPath)) {
    $cliPath = Join-Path $OutputDir "..\target\output\virtual-display-driver-cli.exe"
}
if (-not (Test-Path $cliPath)) {
    $cmd = Get-Command virtual-display-driver-cli.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $cliPath = $cmd.Source
    }
}

$servicePath = Join-Path $OutputDir "vdd-user-session-service.exe"
if (-not (Test-Path $servicePath)) {
    $servicePath = Join-Path $OutputDir "..\rust\target\output\vdd-user-session-service.exe"
}
if (-not (Test-Path $servicePath)) {
    $servicePath = Join-Path $OutputDir "..\target\output\vdd-user-session-service.exe"
}

$controlPath = Join-Path $OutputDir "VirtualDisplayDriverControl.exe"
if (-not (Test-Path $controlPath)) {
    $controlPath = Join-Path $OutputDir "..\rust\target\output\VirtualDisplayDriverControl.exe"
}
if (-not (Test-Path $controlPath)) {
    $controlPath = Join-Path $OutputDir "..\target\output\VirtualDisplayDriverControl.exe"
}

# --- Test 1: System and Test-Signing Status ---
Write-Host "--- Test Group 1: Environment & Driver Presence ---" -ForegroundColor Yellow
$arch = $env:PROCESSOR_ARCHITECTURE
Report-Result -TestName "Host CPU Architecture is ARM64" -Success ($arch -ieq "ARM64") -Details "Detected: $arch"

$startOpts = (Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SystemStartOptions" -ErrorAction SilentlyContinue)
$testSigningBoot = ($startOpts -match "TESTSIGNING")
Report-Result -TestName "Windows Boot Test-Signing Active" -Success ($testSigningBoot) -Details "SystemStartOptions: $startOpts"

# Check Device Node in PnP
$device = Get-PnpDevice -FriendlyName "*Virtual Display*" -ErrorAction SilentlyContinue | Where-Object { $_.Class -eq "Display" }
if (-not $device) {
    # Check by Hardware ID
    $device = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "*VirtualDisplayDriver*" }
}

$deviceFound = ($device -ne $null)
$deviceStarted = ($deviceFound -and ($device.Status -eq "OK"))
Report-Result -TestName "Virtual Display Driver Device Node Present" -Success $deviceFound -Details $(if ($deviceFound) { "InstanceId: $($device.InstanceId)" } else { "Device not found in PnP tree" })
Report-Result -TestName "Virtual Display Driver Device Status OK" -Success $deviceStarted -Details $(if ($deviceFound) { "Status: $($device.Status), ProblemCode: $($device.Problem)" } else { "Device not present" })

# --- Test 2: CLI Connectivity ---
Write-Host ""
Write-Host "--- Test Group 2: CLI & Named Pipe IPC ---" -ForegroundColor Yellow
if (-not (Test-Path $cliPath)) {
    Report-Result -TestName "Locate virtual-display-driver-cli.exe" -Success $false -Details "Binary not found at $cliPath"
    Write-Host "Cannot proceed without CLI binary. Aborting remaining tests." -ForegroundColor Red
    exit 1
} else {
    Report-Result -TestName "Locate virtual-display-driver-cli.exe" -Success $true -Details "$cliPath"
}

# Test CLI connectivity via list
$listRaw = & $cliPath --json list 2>&1
$listExit = $LASTEXITCODE
if ($listExit -eq 0) {
    Report-Result -TestName "CLI Named Pipe IPC Connection (\\.\pipe\virtualdisplaydriver)" -Success $true -Details "Successfully communicated with driver"
} else {
    Report-Result -TestName "CLI Named Pipe IPC Connection (\\.\pipe\virtualdisplaydriver)" -Success $false -Details "Error: $($listRaw | Out-String)"
    Write-Host ""
    Write-Host "Driver is not communicating on named pipe. Ensure driver is installed, test signing is enabled, and system rebooted if needed." -ForegroundColor Yellow
    exit 1
}

# Clean any existing monitors before functional tests
& $cliPath remove-all 2>&1 | Out-Null
Start-Sleep -Milliseconds 500

# --- Test 3: Add Monitor & Mode Configuration ---
Write-Host ""
Write-Host "--- Test Group 3: Virtual Monitor Lifecycle ---" -ForegroundColor Yellow
$addOutput = & $cliPath add 1920x1080@60 2560x1440@60 --name "ARM64_Test_1" 2>&1
$addExit = $LASTEXITCODE
Report-Result -TestName "Add Virtual Monitor (1920x1080@60, 2560x1440@60)" -Success ($addExit -eq 0) -Details ($addOutput | Out-String).Trim()

Start-Sleep -Milliseconds 1000
$monitorsJson = & $cliPath --json list 2>&1 | Out-String
$monitors = $null
try {
    $monitors = $monitorsJson | ConvertFrom-Json
} catch {
    $monitors = @()
}

$monitorAdded = ($monitors -and $monitors.Count -ge 1)
$firstId = if ($monitorAdded) { $monitors[0].id } else { $null }
Report-Result -TestName "Verify Virtual Monitor in List" -Success ($monitorAdded) -Details "Detected $($monitors.Count) active monitor(s); Assigned ID: $firstId"

if ($firstId -ne $null) {
    # --- Test 4: Dynamic Resolution Mode Management ---
    Write-Host ""
    Write-Host "--- Test Group 4: Dynamic Resolution & Refresh Rate ---" -ForegroundColor Yellow
    $addModeOutput = & $cliPath add-mode --id $firstId 3840x2160@60 2>&1
    Report-Result -TestName "Add New Resolution Mode (3840x2160@60) to Monitor $firstId" -Success ($LASTEXITCODE -eq 0) -Details ($addModeOutput | Out-String).Trim()

    Start-Sleep -Milliseconds 500
    $removeModeOutput = & $cliPath remove-mode --id $firstId 3840x2160@60 2>&1
    Report-Result -TestName "Remove Resolution Mode (3840x2160@60) from Monitor $firstId" -Success ($LASTEXITCODE -eq 0) -Details ($removeModeOutput | Out-String).Trim()

    # --- Test 5: Enable / Disable State Toggle ---
    Write-Host ""
    Write-Host "--- Test Group 5: Enable / Disable State ---" -ForegroundColor Yellow
    $disableOutput = & $cliPath disable --id $firstId 2>&1
    Report-Result -TestName "Disable Virtual Monitor $firstId" -Success ($LASTEXITCODE -eq 0) -Details ($disableOutput | Out-String).Trim()

    Start-Sleep -Milliseconds 500
    $enableOutput = & $cliPath enable --id $firstId 2>&1
    Report-Result -TestName "Re-enable Virtual Monitor $firstId" -Success ($LASTEXITCODE -eq 0) -Details ($enableOutput | Out-String).Trim()

    # --- Test 6: Remove Specific Monitor ---
    Write-Host ""
    Write-Host "--- Test Group 6: Remove Virtual Monitor ---" -ForegroundColor Yellow
    $removeOutput = & $cliPath remove --id $firstId 2>&1
    Report-Result -TestName "Remove Virtual Monitor $firstId" -Success ($LASTEXITCODE -eq 0) -Details ($removeOutput | Out-String).Trim()

    Start-Sleep -Milliseconds 500
    $postList = & $cliPath --json list 2>&1 | ConvertFrom-Json
    $postCount = if ($postList) { $postList.Count } else { 0 }
    Report-Result -TestName "Verify Monitor Removed from Active List" -Success ($postCount -eq 0) -Details "Remaining monitors: $postCount"
}

# --- Test 7: Multi-Monitor Scalability (up to 10 monitors) ---
Write-Host ""
Write-Host "--- Test Group 7: Multi-Monitor Scalability ---" -ForegroundColor Yellow
if ($SkipMultiMonitor) {
    Report-Skip -TestName "Multi-Monitor Scalability (up to 10 monitors)" -Reason "Skipped via -SkipMultiMonitor flag"
} else {
    $targetCount = 10
    $batchSuccess = $true
    Write-Host "      Adding $targetCount virtual monitors sequentially..." -ForegroundColor Gray
    for ($i = 0; $i -lt $targetCount; $i++) {
        $res = & $cliPath add 1920x1080@60 --name "MultiMon_$i" 2>&1
        if ($LASTEXITCODE -ne 0) {
            $batchSuccess = $false
            Write-Host "      Failed at monitor $($i): $res" -ForegroundColor Yellow
            break
        }
    }

    Start-Sleep -Milliseconds 1500
    $multiList = & $cliPath --json list 2>&1 | ConvertFrom-Json
    $multiCount = if ($multiList) { $multiList.Count } else { 0 }
    Report-Result -TestName "Multi-Monitor Scalability ($targetCount monitors)" -Success ($multiCount -eq $targetCount) -Details "Created: $multiCount / $targetCount monitors"

    # Cleanup all monitors
    $cleanRes = & $cliPath remove-all 2>&1
    Report-Result -TestName "Remove All Monitors (remove-all)" -Success ($LASTEXITCODE -eq 0) -Details ($cleanRes | Out-String).Trim()
}

# --- Test 8: Persistence across user sessions ---
Write-Host ""
Write-Host "--- Test Group 8: Persistence & Session Service ---" -ForegroundColor Yellow
# Add a monitor and persist
& $cliPath add 1920x1080@60 --name "Persist_Test_Mon" 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
$persistOutput = & $cliPath persist 2>&1
Report-Result -TestName "CLI Persist Configuration Command" -Success ($LASTEXITCODE -eq 0) -Details ($persistOutput | Out-String).Trim()

# Verify registry persistence
$regKey = "HKCU:\Software\VirtualDisplayDriver"
$regExists = Test-Path $regKey
Report-Result -TestName "Verify Registry Persistence Key ($regKey)" -Success $regExists -Details $(if ($regExists) { "Key present in CurrentUser" } else { "Registry key not found" })

# Cleanup persistent test monitor
& $cliPath remove-all 2>&1 | Out-Null

# Verify session service binary
if (Test-Path $servicePath) {
    $svcHelp = & $servicePath --help 2>&1
    Report-Result -TestName "Verify vdd-user-session-service binary execution" -Success ($LASTEXITCODE -eq 0) -Details "$servicePath"
} else {
    Report-Result -TestName "Verify vdd-user-session-service binary execution" -Success $false -Details "Binary not found at $servicePath"
}

# --- Test 9: Control App (GUI) Check ---
Write-Host ""
Write-Host "--- Test Group 9: Virtual Display Driver Control GUI ---" -ForegroundColor Yellow
if (Test-Path $controlPath) {
    Report-Result -TestName "VirtualDisplayDriverControl.exe Present" -Success $true -Details "$controlPath"
} else {
    Report-Skip -TestName "VirtualDisplayDriverControl.exe Present" -Reason "GUI app not compiled on this machine (Phase 5 pending dotnet SDK)"
}

# --- Test Summary ---
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Phase 6 Test Results Summary" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Total Tests: $($Passed + $Failed + $Skipped)"
Write-Host "  Passed:      $Passed" -ForegroundColor Green
Write-Host "  Failed:      $Failed" -ForegroundColor $(if ($Failed -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped:     $Skipped" -ForegroundColor DarkYellow
Write-Host "==========================================================" -ForegroundColor Cyan

if ($Failed -gt 0) {
    exit 1
} else {
    exit 0
}
