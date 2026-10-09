# 02 — Vita3K baseline

How the unmodified game behaves in Vita3K on the dev machine, recorded
2026-10-09. This is the reference the port is measured against. Repeat it
with `tools/v3kdrive.py` after any Vita3K update.

## Setup

| Item | Value |
|---|---|
| Machine | Minisforum UM760 Slim: Ryzen 5 7640HS, Radeon 760M iGPU, AMD driver 25.12.1 (Vulkan 1.4, GL 4.6), 16 GB RAM |
| Vita3K | v0.2.1 build 4152-38bce160, portable in `extracted/vita3k/` (`pref-path` = `fs/`) |
| Firmware | `PSVUPDAT.PUP` 3.74 (build 571880) and the font package `PSP2UPDAT.PUP` 3.73 (build 571652), both from Sony's update servers; MD5s match the hashes in their download URLs ([hashes](hashes.md)) |
| Game | PCSA00152, merged 1.30 install. Debug-menu header: `Revision : 53172 2014-07-28`, `Build : Jul 29 2014 16:56:14 EF-BUILD-S6-5`, `Version : 01.30 Region : US Lang : us` |
| Config | defaults, except: audio-volume 0, log-level 2 (info), `memory-mapping: double-buffer` (default), resolution ×1, `disable-surface-sync: true` (default), `high-accuracy: false` (default) |

## How runs are driven (no keyboard focus needed)

`tools/v3kdrive.py`:

* **`launch <TITLEID> [Vulkan|OpenGL]`**
  * Writes the backend into `config.yml`. A later `-B Vulkan` on the command
    line was ignored once the config held `OpenGL`.
  * Boots the game in the Qt frontend.
* **`bootseq <TITLEID> <name>`**
  * Sets the **retail block's `BootSequence`** in the installed
    `resource/config.ini` and keeps a backup as `config.ini.orig`.
  * The game accepts the names from its own sequence table, so it boots
    **straight into gameplay with no input**:
    * `Title`, `DebugMenu`
    * `[G] HarpyBattle Walhalla` (a boss arena)
    * `ELDER DEFAULT MAP` (an open field)
    * `Quest Select`, `CutEvent Select`, `Prison`, ...
* **`run "<steps>" fps.csv`**
  * Samples the FPS and frame time every 500 ms from the game window's title
    (`… | 30 FPS (34 ms) | 960x544 | …`).
  * Takes screenshots with `PrintWindow(PW_RENDERFULLCONTENT)`, which works
    while the window is in the background.

**Input** isn't automated yet. Qt drops key messages posted to a window that
doesn't have focus, so button presses would need real focus and `SendInput`.
That means stealing the desktop. The `BootSequence` route makes input
unnecessary for boot and idle-gameplay baselines.

Artifacts are in `extracted/baseline/` (never committed): `fps.csv`,
`run*.png`, `logs/run*.log` and `hle-gaps.txt`.

## Results

| Run | Backend | Boot target | Outcome | FPS (median / min after load) |
|---|---|---|---|---|
| 1 | Vulkan | Title | **Crash** about 4 s after boot: host `EXCEPTION_ACCESS_VIOLATION`, write to `0x0`. No frames reached the title | — |
| 2 | OpenGL | Title | Logos, then "PRESS ANY BUTTON" title, renders correctly | 29 / 29 |
| 3 | OpenGL | `[G] HarpyBattle Walhalla` | In battle: player model and HUD correct, **environment broken** (white ground, black sky and blocks) | 30 / 29 (one dip to 12 during the first load) |
| 4 | Vulkan | HarpyBattle | **Same crash** about 3.4 s after device creation, right after opening the `magic_effect_*` archives. Six title samples at 16 fps before it died | — |
| 5 | Vulkan + `memory-mapping: disabled` | HarpyBattle | **Hard crash**; the log stops mid-line during module loading | — |
| 6 | OpenGL | `DebugMenu` | Dev "SELECT SEQUENCE MODULE" menu, 17 entries, renders correctly | 30 |
| 7 | OpenGL | `ELDER DEFAULT MAP` | In field: terrain, rocks and character drawn but **heavily overexposed/washed out**, with black quads in the sky | 30 / 29 |

### Takeaways

1. **Vulkan is unusable on this AMD iGPU.** It crashed at boot in all three
   attempts.
   * The same symptom appears in Vita3K compatibility reports ("crash before
     the logos on Vulkan" on Windows 11 and on the Steam Deck, which is also
     AMD).
   * loktar00 reports Vulkan working at 30 fps on an RTX 4090.
   * **Next:** check on the RTX 4090 PC, and debug with a source build
     (plan Phase 1).
2. **OpenGL runs at the game's 30 fps cap**, in menus and in gameplay, with
   no CPU bottleneck visible at 1× resolution. So this game's CPU load is fine
   under dynarmic on a Zen 4 laptop chip.
3. **Gameplay rendering is wrong under OpenGL.** It is overexposed, with
   black blocks.
   * This matches the "oversaturated first scene" and "OpenGL glitches badly"
     reports.
   * The cause is unknown. Candidates are render-to-texture/surface sync (we
     run with `disable-surface-sync: true`, the default) or a GL-only blend
     or format path.
   * **Hypothesis:** the black blocks are fog/particle quads. loktar00 saw
     "blocky fog/particle artifacts" on Vulkan and fixed them with
     `high-accuracy: true`.
4. **Little of the HLE layer is exercised by boot + idle gameplay.** Only 28
   distinct unimplemented/stubbed imports were hit (`hle-gaps.txt`):
   * NP/online init (`sceNpAuthInit`, `sceNpTusInit`, ...);
   * three GXM stubs (`sceGxmMapVertex/FragmentUsseMemory`,
     `sceGxmGetRenderTargetMemSize`);
   * `_sceDisplaySetFrameBuf` (`SETBUF_IMMEDIATE`);
   * ULT object-manager registration;
   * `sceKernelChangeThreadVfpException`;
   * `sceAppUtilInit`, `sceCommonDialogUpdate`.
   * Everything else the game called is implemented in Vita3K. The only
     errors logged are `stat` misses on optional loose `gimmick/*_ext.csv`
     files.
5. **Modules running as guest code (LLE) during gameplay:**
   * From the game's `sce_module/`: `SceLibc`, `SceLibFios2`, `SceUlt`.
   * From the firmware: `SceLibft2`, `SceLibPvf` (fonts), `SceFiber`,
     `SceMp4`, `SceAvPlayer` (FMV), `SceLibHttp`, `SceLibSsl`.
   * Plus the kernel stubs `bootimage`/`sysmodule`.
   * A native port has to replace or recompile all of these, not just the
     game's own four modules. **Font rendering (pvf/ft2) and AvPlayer are
     firmware code.**

## Not measured yet

* Real button input: title → save creation → hub → quest. This needs
  focus-stealing input or a virtual pad.
* Audio. It was muted for the runs.
* Higher resolution multipliers, and `high-accuracy: true`.
* Per-thread CPU time.
* Vulkan on an NVIDIA GPU.
* The Mind's Eye overlay bug (D-pad down in a quest).
