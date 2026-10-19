@echo off
setlocal EnableDelayedExpansion

echo ===================================================
echo   Virtual Display Driver - Installation Script
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

:: 1. Check and enable test signing
echo [1/5] Checking Windows Test-Signing status...
set "REBOOT_REQUIRED=0"
bcdedit /enum {current} | findstr /i "testsigning" | findstr /i "Yes" >nul 2>&1
if %errorLevel% equ 0 (
    echo       Test signing is already enabled.
) else (
    echo       Enabling test signing: bcdedit /set testsigning on
    bcdedit /set testsigning on
    if !errorLevel! equ 0 (
        echo       Test signing successfully enabled.
        set "REBOOT_REQUIRED=1"
    ) else (
        echo       [WARNING] Could not enable test signing automatically.
    )
)

:: 2. Install Certificate if present
set "CERT_FILE="
if exist "%~dp0DriverCertificate.cer" set "CERT_FILE=%~dp0DriverCertificate.cer"
if not defined CERT_FILE if exist "%~dp0..\DriverCertificate.cer" set "CERT_FILE=%~dp0..\DriverCertificate.cer"
if not defined CERT_FILE if exist "%~dp0..\target\output\DriverCertificate.cer" set "CERT_FILE=%~dp0..\target\output\DriverCertificate.cer"

if defined CERT_FILE (
    echo [2/5] Installing driver certificate: !CERT_FILE!...
    certutil -addstore -f root "!CERT_FILE!" >nul 2>&1
    certutil -addstore -f TrustedPublisher "!CERT_FILE!" >nul 2>&1
    if !errorLevel! equ 0 (
        echo       Driver certificate installed into Root and TrustedPublisher.
    ) else (
        echo       [WARNING] Could not install certificate automatically.
    )
) else (
    echo [2/5] DriverCertificate.cer not found (skipping certificate install).
)

:: 3. Import registry defaults if present
set "REG_FILE="
if exist "%~dp0install.reg" set "REG_FILE=%~dp0install.reg"
if not defined REG_FILE if exist "%~dp0files\install.reg" set "REG_FILE=%~dp0files\install.reg"
if not defined REG_FILE if exist "%~dp0..\target\output\install.reg" set "REG_FILE=%~dp0..\target\output\install.reg"

if defined REG_FILE (
    echo [3/5] Importing registry settings: !REG_FILE!...
    reg import "!REG_FILE!" >nul 2>&1
    if !errorLevel! equ 0 (
        echo       Registry settings imported successfully.
    ) else (
        echo       [WARNING] Failed to import registry settings.
    )
) else (
    echo [3/5] install.reg not found (skipping registry import).
)

:: 4. Determine architecture and find nefconc.exe
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

:: 5. Locate driver INF and install device node and driver package
set "INF_PATH="
if exist "%~dp0VirtualDisplayDriver.inf" set "INF_PATH=%~dp0VirtualDisplayDriver.inf"
if not defined INF_PATH if exist "%~dp0..\target\output\VirtualDisplayDriver.inf" (
    for %%i in ("%~dp0..\target\output\VirtualDisplayDriver.inf") do set "INF_PATH=%%~fi"
)

if not defined INF_PATH (
    echo [ERROR] VirtualDisplayDriver.inf not found in "%~dp0" or target output directory!
    pause
    exit /b 1
)

echo       Using driver package: !INF_PATH!

if defined NEFCON_EXE (
    echo [4/5] Creating virtual display device node using !NEFCON_EXE!...
    "!NEFCON_EXE!" --remove-device-node --hardware-id Root\VirtualDisplayDriver --class-guid 4d36e968-e325-11ce-bfc1-08002be10318 >nul 2>&1
    "!NEFCON_EXE!" --create-device-node --hardware-id Root\VirtualDisplayDriver --class-name Display --class-guid 4d36e968-e325-11ce-bfc1-08002be10318
    if !errorLevel! neq 0 (
        echo [ERROR] Failed to create device node with nefcon.
        pause
        exit /b 1
    )

    echo [5/5] Installing driver package using !NEFCON_EXE!...
    "!NEFCON_EXE!" --install-driver --inf-path "!INF_PATH!"
    if !errorLevel! neq 0 (
        echo [WARNING] nefcon driver install reported error, falling back to pnputil...
        pnputil /add-driver "!INF_PATH!" /install
    )
) else (
    echo [4/5] nefconc.exe not found. Falling back to Windows pnputil...
    echo [5/5] Installing driver package...
    pnputil /add-driver "!INF_PATH!" /install
)

echo.
echo ===================================================
echo   Driver installation finished!
echo ===================================================

if "%REBOOT_REQUIRED%"=="1" (
    echo.
    echo [IMPORTANT] Windows Test Signing was enabled for the first time.
    echo A system reboot is required before Windows will load the driver.
)

:: Check if user wants to run tests
set "TEST_BAT="
if exist "%~dp0test-phase6.bat" set "TEST_BAT=%~dp0test-phase6.bat"
if not defined TEST_BAT if exist "%~dp0..\target\output\test-phase6.bat" set "TEST_BAT=%~dp0..\target\output\test-phase6.bat"

if defined TEST_BAT (
    echo.
    echo To verify the driver, you can now run:
    echo   !TEST_BAT!
)

echo.
pause
