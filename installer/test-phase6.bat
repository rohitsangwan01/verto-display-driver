@echo off
setlocal

cd /d "%~dp0"
echo Starting Virtual Display Driver Phase 6 Verification Test Suite...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-phase6.ps1" %*
set TEST_EXIT=%ERRORLEVEL%

echo.
echo Test run finished with exit code %TEST_EXIT%.
pause
exit /b %TEST_EXIT%
