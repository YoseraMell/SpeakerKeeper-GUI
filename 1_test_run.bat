@echo off
rem Run SpeakerKeeper in a visible window for testing. Close the window to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SpeakerKeeper.ps1"
pause
