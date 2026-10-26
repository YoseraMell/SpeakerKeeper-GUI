@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\startup.ps1" -Mode remove
pause
