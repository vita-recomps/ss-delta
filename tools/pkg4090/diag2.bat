@echo off
rem Arena floor diagnostics round 2 (debug/floor build): 8 runs of 45 s on Vulkan, about 7 minutes.
rem Variants: as is; high accuracy forced; floor shader skipped (control); five groups of other shaders skipped.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\matrix.ps1" -Emu ours -Renderer Vulkan -Boot Harpy -Seconds 45 -Variants "none;SSD_HIGH_ACC;SSD_SKIP_FRAGS=9a8f3eb3;SSD_SKIP_FRAGS=122ecf7d,30960ee1,3d08817c,40e4e728,49d92568,4a0ddea9,4cec1f5d;SSD_SKIP_FRAGS=5615a762,5b16f882,5f74e59a,6a03f740,6bf1c363,6ee9a18d,8ac153e2;SSD_SKIP_FRAGS=95c836aa,a39e7dd7,a3cc810d,a9941409,ad07babc,af0c9ab6;SSD_SKIP_FRAGS=b2dcf911,b78f3c4c,b87cb95f,c3ca22e8,c47d1fdb,c890c0a0,cf51fb55;SSD_SKIP_FRAGS=d336bf85,d5de8cfb,de966e14,e1e0003f,e7284269,e934bd8f,f5ccb166" %*
pause
