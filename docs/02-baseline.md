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
| 7 | OpenGL | `ELDER DEFAULT MAP` | In field: terrain, rocks and character drawn but **heavily overexposed/washed out**, with black quads in the sky. The overexposure did not reproduce in later runs (see the settings test) | 30 / 29 |
| 8 (2026-10-09) | Vulkan + `validation-layer: false` | `ELDER DEFAULT MAP` | **Same crash**, 3.7 s after device creation (write to `0x0`). Upstream defaults `validation-layer: true` and loads the layer here because the Vulkan SDK is installed; Plus defaults it to `false`. This ruled the layer out as the cause | — |
| 9 | Vulkan + `async-pipeline-compilation: false` (Plus's default) | `ELDER DEFAULT MAP` | **Same crash** | — |
| 10 | Vulkan + `memory-mapping: external-host` (Plus's default) | `ELDER DEFAULT MAP` | **Same crash** | — |
| 11 | Vulkan + `high-accuracy: true` + surface sync on (Plus's defaults) | `ELDER DEFAULT MAP` | **Same crash** | — |

#### Where the Vulkan crash happens (2026-10-09)

* **The crash is inside AMD's Vulkan driver.** The Windows Application log
  (event 1000) records every upstream Vulkan crash as faulting module
  `amdvlk64.dll` 32.0.22029.9039, exception `0xc0000005`, fault offset
  `0x2b12324`. That is the same offset in every run, including the copy in
  `dist/`.
* **The shaders are valid SPIR-V.** All 15 `vk13-*.spv` files written before
  the crash pass `spirv-val --target-env vulkan1.1 --scalar-block-layout`.
  Without that flag the only complaints are std140 offsets, which the
  `uniformBufferStandardLayout` feature Vita3K enables allows.
* **No validation-layer errors** were logged before the crash (runs 1 and 4
  had the layer on).
* Runs 8–11 rule out the config defaults that differ between upstream and
  Plus. So the fix is somewhere in Plus's code. None of Plus's commits
  mention AMD.
* **Next:** our build logs the faulting thread's stack (`util/logging.cpp`
  patch), which names the Vita3K call that hands the driver the bad
  input.

#### Our build (2026-10-09): the crash is driver state, not one pipeline

Our build is upstream `b75d5e62` plus a stack-trace patch
([D5](decisions.md), `patches/vita3k/`). It boots to the title on OpenGL at
29–30 fps, like the release.

On Vulkan, the stack shows the render thread in
`PipelineCache::compile_pipeline` (`pipeline_cache.cpp:923`) →
`vkCreateGraphicsPipelines` → validation layer → `amdvlk64.dll+0x2B12324`.
A temporary logging branch (`debug/amd-pipeline-crash` in the fork) named
each pipeline before creation:

| Test | Result |
|---|---|
| Sync or async compilation | always the 7th pipeline: vertex `ab9c7561…` + fragment `61f0d854…` (triangle strip, 4 attributes, framebuffer read through an input attachment) |
| Fragment `main` emptied | crash |
| Vertex `main` emptied | crash |
| Both replaced by trivial GLSL shaders (no resources) | crash |
| Plus the previous good pipeline's layout (fragment textures 3 → 2) | crash. All logged state now matches the previous pipeline, which compiled |
| Plus no `VkPipelineCache` | crash |
| Skip this pipeline | the **next new pipeline** crashes (`f1340375…`/`f5ccb166…`, which Plus compiles fine on this GPU) |

* **Conclusion:** after six pipelines, `vkCreateGraphicsPipelines` on
  amdvlk 32.0.22029.9039 (Adrenalin 25.12.1) crashes whatever the pipeline
  contains. Two explanations remain open:
  * a driver bug triggered by earlier API use;
  * Vita3K corrupting driver-owned memory before that point.
* Plus avoids it on the same driver. It uses fragment-shader interlock
  instead of input attachments, and it never issued this draw. Upstream
  with `high-accuracy: true` also uses interlock (run 11) and still crashed.
  So Plus's escape is something else in its 167 commits.
* **Next:** update the driver to Adrenalin 26.8.1. If the crash goes, it was
  the driver. If not, look for what Vita3K does to the device before the
  7th pipeline.

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

## OpenGL settings test (2026-10-09)

Question: are the OpenGL rendering bugs caused by Vita3K's defaults (surface
sync off, high accuracy off)?

Every run uses OpenGL, a screenshot at about 45 s, and an idle player. Logs
are `logs/gltest-*.log`; screenshots are `gltest-*.png`.

| Map | `disable-surface-sync` | `high-accuracy` | Overexposure | Black blocks | White floor | FPS |
|---|---|---|---|---|---|---|
| ELDER DEFAULT MAP | false (sync on) | false | none | yes | — | 29–30 |
| ELDER DEFAULT MAP | true | true | none | yes | — | 29–30 |
| ELDER DEFAULT MAP | false | true | none | yes | — | 27–30 |
| ELDER DEFAULT MAP | true (default) | false (default) | **none** (control, 2 runs) | yes | — | 29–30 |
| HarpyBattle | true (default) | false (default) | — | yes | **yes** | 29–30 |
| HarpyBattle | false | true | — | yes | **yes** | 29–31 |

Findings:

1. **The overexposure in run 7 did not come back**, even with the same
   default settings.
   * Run 7 was the first time that map ever loaded: it logged 7 shader
     generations, against 0 in the reruns.
   * **Hypothesis:** frames drawn while Vita3K was still generating shaders,
     not a steady-state bug.
2. **The black blocks appear in every OpenGL run, whatever the settings.**
   * They are large screen-space quads, and their shape changes between
     frames.
   * loktar00 saw "blocky fog/particle artifacts" on Vulkan that
     `high-accuracy: true` removed. On OpenGL it does not help.
   * **Hypothesis:** a fog/particle blend or format path that is wrong only
     in the GL backend.
3. **The white floor in Walhalla appears with every setting** and with a
   warm cache.
   * It matches the bug Vita3K-Plus v1.2 fixed for Delta ("floor textures
     rendered white" in the Resplendent Rapunzel and Training Room maps).
   * So it is probably a Vita3K renderer bug, not specific to OpenGL.
4. **Surface sync and high accuracy cost nothing visible here.** The game
   stays at 30 fps at 1× resolution.

**Conclusion:** the settings don't fix OpenGL.

* The remaining OpenGL problems (black blocks, white floors) need renderer
  work, either from Vita3K-Plus or our own.
* Whether Vulkan has the black blocks can only be answered on a machine
  where Vulkan boots: the RTX 4090 PC, or this one once the crash is fixed.

## Vita3K-Plus v1.2 (2026-10-09)

[nckstwrt/Vita3K-Plus](https://github.com/nckstwrt/Vita3K-Plus) v1.2 (build
`2-5b040dc4`, released 2026-09-30) is a fork with fixes for this game. It
lives in `extracted/vita3k-plus/1.2/`, with `pref-path` set to the same
`fs/`. Its defaults differ from upstream:

* `high-accuracy: true`;
* `disable-surface-sync: false` (sync on);
* `memory-mapping: external-host`.

| Map | Backend | Settings | Result | FPS |
|---|---|---|---|---|
| HarpyBattle | Vulkan | Plus defaults | **Boots (no crash) and renders correctly**: textured floor, castle, boss, no black blocks. One artifact: **speckled noise on the player's cloak** | 30 / 29 |
| ELDER DEFAULT MAP | Vulkan | Plus defaults | Correct field, fog and sky text; same cloak speckle | 30 / 29 |
| ELDER DEFAULT MAP | Vulkan | `high-accuracy: false` | same, cloak speckle stays | 30 / 29 |
| ELDER DEFAULT MAP | Vulkan | `memory-mapping: double-buffer` | same, cloak speckle stays | 30 / 29 |
| HarpyBattle | OpenGL | Plus defaults | Same black blocks and white floor as upstream OpenGL; **cloak clean** | 29 |

Conclusions:

* Plus's renderer fixes are on the **Vulkan path**.
* Something in Plus (or in upstream since 4152, which we can't test because
  it crashes) avoids the AMD Vulkan crash. Comparing the two builds shows
  where the crash lives.
* The cloak speckle is **Vulkan-specific**, since OpenGL draws the cloak
  clean. It might be AMD-specific (unknown).
* For rendering comparisons on this machine, **Vita3K-Plus on Vulkan is the
  best reference available** ([D4](decisions.md)).

## RTX 4090 test package

`tools/package4090.ps1 [-Zip]` builds `dist/ss-delta-vita3k-test/`
(3.4 GB, never committed):

* both builds in Vita3K's portable mode;
* the shared `vitafs/` (the installed game, its licence and firmware);
* `run-matrix.bat`: an unattended run of emulator × renderer × map, with
  FPS CSV, screenshots, logs and crash detection, zipped for sending back;
* `play.bat`: interactive play, with the log and F12 screenshots collected
  afterwards;
* a README with instructions.

Scripts are in `tools/pkg4090/` (PowerShell only, so no Python is needed on
the target).

* **Path handling.** In portable mode upstream Vita3K ignores `pref-path`
  and always uses `portable\fs` (`config/src/config.cpp:464`). The scripts
  therefore make each build's `portable\fs` a directory junction to
  `vitafs\`.
* **Local check of the package** (Harpy, 40 s; results in
  `extracted/baseline/package-test/`):
  * upstream Vulkan crashed (exit code 0xC0000005) after 6 s;
  * upstream OpenGL, Plus Vulkan and Plus OpenGL ran at 29–30 fps.

## RTX 4090 results (2026-10-09)

The package was run on the RTX 4090 PC:

* Ryzen 7 7800X3D, RTX 4090 with driver 610.62 (Windows 32.0.16.1062).
  The machine also has the 7800X3D's iGPU and virtual display adapters, but
  every log shows the RTX 4090 in use.
* `run-matrix.bat` defaults: 60 s per run, cold caches.
* Raw results are in `extracted/baseline/rtx4090/`.

**No crashes, and 29–30 fps in all 8 runs.**

| Build | Renderer | ELDER DEFAULT MAP | HarpyBattle (Walhalla) |
|---|---|---|---|
| upstream | Vulkan | **correct**: fog, sky text, clean cloak | **white floor**; castle, boss and cloak correct |
| plus | Vulkan | **correct** | **white floor**; rest correct |
| upstream | OpenGL | **washed out** (almost white) at 30 s and 60 s | washed out, castle barely visible |
| plus | OpenGL | correct | floor textured but desaturated and greenish; no black blocks |

Compared with the Radeon 760M:

| Symptom | Radeon 760M (AMD iGPU) | RTX 4090 (NVIDIA) |
|---|---|---|
| Upstream Vulkan crash at boot | always | **never** |
| Black blocks (OpenGL) | every OpenGL run, both builds | **none** |
| Speckled cloak (Plus, Vulkan) | always | **none** |
| White Walhalla floor | upstream OpenGL; Plus Vulkan has it **textured** | upstream and Plus **Vulkan**; Plus OpenGL textured |
| Overexposure (upstream OpenGL) | first run only | every run (both maps) |

What this means:

1. **No build/backend combination renders this game correctly on both
   GPUs.**
   * The best results are NVIDIA Vulkan (white Walhalla floor only) and AMD
     Plus Vulkan (speckled cloak only).
   * The same Vita3K code gives different wrong pictures on different
     vendors. That points at **undefined behaviour in the translated
     shaders or GPU state**, which drivers resolve differently, rather than
     at missing features.
2. **A concrete lead from the NVIDIA GLSL compiler.** It warns
   `"sa[0]" might be used before being initialized` and
   `"pa[0].zw" might be used before being initialized`:
   * 34–83 times per OpenGL run;
   * none in Plus/Elder, which is the one OpenGL run that looks right.

   `sa`/`pa` are the USSE secondary-attribute (uniform) and
   primary-attribute register files in Vita3K's translated shaders. Reading
   them uninitialized gives driver-dependent values.
   * **Hypothesis:** this causes the overexposure and the white floor, and
     the same translator bug feeds the Vulkan (SPIR-V) path.
   * **Next step:** with `log-active-shaders`, dump the Walhalla floor
     shader and check its `sa`/`pa` reads against the GXP program's
     declared parameters.

   **First check (2026-10-09) weakens this lead.**
   * Over the four OpenGL runs, the warnings are mostly not `sa`/`pa`:

     | Variable | Vertex | Fragment |
     |---|---|---|
     | `r` (temporaries) | 254 | 86 |
     | `pa` | 91 | 219 |
     | `internals` | 120 | 105 |
     | `outs` | 0 | 18 |
     | `sa` | 2 | 6 |

   * 77 shaders can be tied to their warnings because the log names them
     ("Generating … shader <hash>" directly before the compile). All 77 are
     in our local OpenGL shader cache
     (`extracted/vita3k/cache/shaders/PCSA00152/eboot.bin/`, GLSL), and the
     GXP and USSE disassembly are in `extracted/vita3k/shaderlog/`.
   * The two shaders read so far (`da18ddf0….vert`, `4a0ddea9….frag`) warn
     only because the translator copies a whole `vec4` register, sets some
     components and writes it back (`vec4 t = sa[0]; t.x = 1.0; sa[0] = t;`).
     The unset components are never used, so these warnings are benign.
   * NVIDIA reports the declaration line, so the warnings alone can't
     separate benign copies from real reads.
   * **Better test:** make our build zero-initialise every register array
     (`pa`, `sa`, `r`, `internals`, `outs`) in the translator. If the
     NVIDIA white floor or wash-out changes, uninitialised reads matter. If
     not, this lead is dead.
3. **The upstream Vulkan crash is specific to AMD (or the iGPU).** Upstream
   Vulkan runs fine on NVIDIA. Plus avoids the crash on AMD, so the fix is
   in Plus's diff.
4. **Performance is a non-issue** on both machines at 1×: the game's 30 fps
   cap holds everywhere.

## Not measured yet

* Real button input: title → save creation → hub → quest. This needs
  focus-stealing input or a virtual pad.
* Audio. It was muted for the runs.
* Higher resolution multipliers, and `high-accuracy: true`.
* Per-thread CPU time.
* The Mind's Eye overlay bug (D-pad down in a quest).
