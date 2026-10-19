@echo off
setlocal EnableDelayedExpansion

echo ===================================================
echo   Virtual Display Driver - Uninstallation Script
echo ===================================================
echo.

:: Check for administrative permissions; prompt for elevation if non-admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges are required. Requesting elevation...
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Ensure current working directory is the script directory
cd /d "%~dp0"

:: Determine architecture and find nefconc.exe
set "NEFCON_EXE="
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    if exist "%~dp0arm64\nefconc.exe" set "NEFCON_EXE=%~dp0arm64\nefconc.exe"
    if not defined NEFCON_EXE if exist "%~dp0files\arm64\nefconc.exe" set "NEFCON_EXE=%~dp0files\arm64\nefconc.exe"
)
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    if exist "%~dp0x64\nefconc.exe" set "NEFCON_EXE=%~dp0x64\nefconc.exe"
    if not defined NEFCON_EXE if exist "%~dp0files\x64\nefconc.exe" set "NEFCON_EXE=%~dp0files\x64\nefconc.exe"
)
if not defined NEFCON_EXE (
    if exist "%~dp0nefconc.exe" set "NEFCON_EXE=%~dp0nefconc.exe"
    if not defined NEFCON_EXE if exist "%~dp0files\nefconc.exe" set "NEFCON_EXE=%~dp0files\nefconc.exe"
    if not defined NEFCON_EXE if exist "%~dp0..\target\output\nefconc.exe" set "NEFCON_EXE=%~dp0..\target\output\nefconc.exe"
)

:: 1. Remove device node
if defined NEFCON_EXE (
    echo [1/3] Removing virtual display device node using !NEFCON_EXE!...
    "!NEFCON_EXE!" --remove-device-node --hardware-id Root\VirtualDisplayDriver --class-guid 4d36e968-e325-11ce-bfc1-08002be10318 >nul 2>&1
    echo [2/3] Removing driver package from driver store...
    "!NEFCON_EXE!" --remove-driver-store-package --inf-name VirtualDisplayDriver.inf >nul 2>&1
) else (
    echo [1/3] nefconc.exe not found. Attempting device removal via pnputil...
    pnputil /remove-device /deviceid "Root\VirtualDisplayDriver" >nul 2>&1
)

:: Also query and delete matching OEM inf via pnputil if nefcon was not present or left anything
for /f "tokens=*" %%a in ('powershell -Command "(pnputil /enum-drivers | Select-String -Pattern 'VirtualDisplayDriver\.inf' -Context 3,0 | Select-String 'oem\d+\.inf').Matches.Value"') do (
    if not "%%a"=="" (
        echo Deleting driver store package %%a...
        pnputil /delete-driver %%a /uninstall /force >nul 2>&1
    )
)

:: 3. Clean up registry if uninstall.reg present
set "UNREG_FILE="
if exist "%~dp0uninstall.reg" set "UNREG_FILE=%~dp0uninstall.reg"
if not defined UNREG_FILE if exist "%~dp0files\uninstall.reg" set "UNREG_FILE=%~dp0files\uninstall.reg"
if not defined UNREG_FILE if exist "%~dp0..\target\output\uninstall.reg" set "UNREG_FILE=%~dp0..\target\output\uninstall.reg"

if defined UNREG_FILE (
    echo [3/3] Cleaning up registry entries: !UNREG_FILE!...
    reg import "!UNREG_FILE!" >nul 2>&1
) else (
    echo [3/3] No uninstall.reg found (skipping registry cleanup).
)

echo.
echo ===================================================
echo   Uninstallation completed!
echo ===================================================
echo.
pause
