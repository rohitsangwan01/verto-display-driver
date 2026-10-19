@echo off
set "CERT_FILE=%~dp0DriverCertificate.cer"
if not exist "%CERT_FILE%" if exist "%~dp0..\cert\DriverCertificate.cer" set "CERT_FILE=%~dp0..\cert\DriverCertificate.cer"
if not exist "%CERT_FILE%" if exist "%~dp0..\DriverCertificate.cer" set "CERT_FILE=%~dp0..\DriverCertificate.cer"
if not exist "%CERT_FILE%" if exist "%~dp0..\target\output\DriverCertificate.cer" set "CERT_FILE=%~dp0..\target\output\DriverCertificate.cer"

if not exist "%CERT_FILE%" (
    echo [ERROR] DriverCertificate.cer not found!
    exit /b 1
)

certutil -addstore -f root "%CERT_FILE%"
certutil -addstore -f TrustedPublisher "%CERT_FILE%"

