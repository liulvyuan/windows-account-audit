@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0account-audit.ps1"
if exist "%~dp0out\account-audit-report.html" start "" "%~dp0out\account-audit-report.html"
pause
