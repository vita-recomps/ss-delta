@echo off
rem Arena floor diagnostics round 3 (debug/floor build): 3 runs of 75 s on Vulkan, about 4 minutes.
rem Variants: as is; 32-bit denormals preserved; 32-bit denormals flushed to zero.
rem The denormal runs retranslate every shader, so loading takes longer.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\matrix.ps1" -Emu ours -Renderer Vulkan -Boot Harpy -Seconds 75 -Variants "none;SSD_DENORM=preserve;SSD_DENORM=ftz" %*
pause
