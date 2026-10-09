@echo off
rem Arena floor diagnostics for our Vita3K build (debug/floor): three 45 s runs on Vulkan.
rem none = the build as is, SSD_SOFT_BCN = BC textures decoded on the CPU,
rem SSD_MAXLOD0 = samplers clamped to the base mip level.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\matrix.ps1" -Emu ours -Renderer Vulkan -Boot Harpy -Seconds 45 -Variants none,SSD_SOFT_BCN,SSD_MAXLOD0 %*
pause
