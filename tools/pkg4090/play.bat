@echo off
rem Play interactively. Examples:
rem   play.bat                                       (Vita3K-Plus, Vulkan, title screen)
rem   play.bat -Emu upstream -Renderer Vulkan -Boot Elder
rem   play.bat -Boot DebugMenu                       (developer menu; Circle = confirm)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\play.ps1" %*
pause
