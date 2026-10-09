@echo off
rem Unattended test matrix (about 10 minutes). Results go to results\matrix-<time>\ and a .zip next to it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\matrix.ps1" %*
pause
