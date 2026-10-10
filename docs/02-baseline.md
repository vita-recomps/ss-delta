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

#### Our build (2026-10-09): the AMD Vulkan crash is found and fixed

Our build is upstream `b75d5e62` plus our patches ([D5](decisions.md),
`patches/vita3k/`). It boots to the title on OpenGL at 29–30 fps, like the
release.

**Where it crashed.** The stack shows the render thread in
`PipelineCache::compile_pipeline` → `vkCreateGraphicsPipelines` →
validation layer → `amdvlk64.dll`. A temporary logging branch
(`debug/amd-pipeline-crash` in the fork) named each pipeline before
creation. The crashing pipeline depends on the boot target:

* title: vertex `ab9c7561…` + fragment `61f0d854…`;
* Elder map: vertex `f1340375…` + fragment `f5ccb166…`.

**Driver update.** On 2026-10-09 the driver went from 32.0.22029.9039
(Vulkan 2.0.373, Dec 2025) to 32.0.31041.1004 (Vulkan 2.0.395,
2026-08-17). The crash is the same, so the newer AMD driver has the same
bug.

**Bisection.** Our build keeps its own shader cache next to its exe
(`build/vita3k/bin/RelWithDebInfo/cache/`), and Vita3K loads `.spv` files
from it by hash. So edited SPIR-V can be tested without rebuilding.

> **Correction.** The first round of shader edits went into the
> *release's* cache (`extracted/vita3k/cache`), which our build never
> reads. Those results ("fragment emptied / vertex emptied / trivial
> shaders → still crashes") were invalid, and the conclusion drawn from
> them ("driver state, not the pipeline") was wrong. These earlier tests
> did not touch shaders and stand:
> * the layout swap (crash);
> * no `VkPipelineCache` (crash);
> * skipping the pipeline (the next pipeline with the same pattern
>   crashes).

The redone bisection, on the Elder map with fragment `f5ccb166`:

| Fragment shader variant | Result |
|---|---|
| original, or round-tripped through `spirv-cross`/glslang | crash |
| trivial shader | compiles (the crash moves to the next pipeline with the pattern: `fd8e9c7b` + `49d92568`) |
| trivial *vertex* shader, original fragment | crash |
| `primary_program` or `frag_output_finalize` call removed | compiles |
| `pack4xU8`/`unpack4xU8` as shifts, no `round`, `mediump` removed | crash |
| texture 1 not sampled, or the alpha factor a constant | compiles |
| factor taken from the **green** half instead of the red one | compiles |
| Vita3K-Plus's `pack2xF16` (clamp to ±65504, keep NaN), or just the clamp | **compiles** |

* **Trigger (AMD compiler bug).** A fragment shader that takes a texture
  sample, packs it with `packHalf2x16`, reads the *low* half back with
  `unpackHalf2x16(...).x`, and uses it in the output. All three crashing
  shaders do this: `vec4(1, 1, 1, a) * colour` with `a` from a texture's
  red channel.
* **Fix.** Vita3K-Plus `105331d9`, made for MotoGP 14, clamps the value
  before `packHalf2x16`. That breaks the pattern. It is ported as fork
  patch 0002, with the shader cache version bumped to 14.

**After the crash: exploded geometry.** With patch 0002 the game runs at 30
fps on Vulkan with no crashes. The world geometry was still exploded into
huge flat triangles in every `memory-mapping` mode, while the HUD and
OpenGL were correct.
* The validation layer reported `misaligned attribAddress`: the game uses
  vertex strides that aren't a multiple of 4.
* NVIDIA tolerates this; AMD fetches garbage.
* Patch 0003 repacks such streams on all platforms. This is the same idea
  as Plus `35cbde8d`, and upstream only did it on Apple.

**Result (runs 20–21, 2026-10-09).** Upstream plus patches 0002 and 0003,
Vulkan, Radeon 760M, default config:
* the field (`ELDER DEFAULT MAP`) renders like Plus;
* the Walhalla arena floor is **textured**;
* title, field and arena run at 30 fps with no crashes.

**Cloak (run 22).** The last misaligned attribute, an `R16G16_UINT` at an
odd offset within an aligned stride, was the cloak. Patch 0004 gives every
stream that Vulkan can't fetch in place a repacked layout, with each
attribute 4-aligned.
* The cloak is now solid on AMD; Plus still speckles it.
* The validation layer reports no misalignment.
* One validation message remains in the arena: a depth image is in
  `ATTACHMENT_OPTIMAL` where `READ_ONLY_OPTIMAL` is expected. This is an
  upstream sync issue with no visible effect so far.

**Input (2026-10-09).** Patch 0005 plus `tools/v3kdrive.py` drive the game
without focus:
* title → main menu → New Game → save-data dialog;
* `hold:ls_up:3000` walks the player.

### Takeaways

1. **Vulkan was unusable on this AMD iGPU** (crashed at boot in all three
   attempts). Fixed in our fork since; see "Our build" above.
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

## RTX 4090 test package, round 2 (2026-10-09)

`tools/package4090.ps1 -Zip` now also packs our fork as `vita3k-ours`
(RelWithDebInfo, with its PDB for symbolised crash stacks; no `.ilk`). It
sets `validation-layer: false` in every packed config, so PCs with and
without the Vulkan SDK behave the same.
* `run-matrix.bat` defaults to ours, upstream and Plus × Vulkan/OpenGL ×
  Elder/Harpy: 12 runs.
* `play.bat` defaults to ours.
* Local smoke test (ours, Vulkan, Harpy, 40 s): ok, 30 fps median, textured
  floor.
* The question for round 2: does our fork also fix the white Walhalla floor
  on NVIDIA?

### Round 2 results (2026-10-10, `matrix-20261010-005119.zip`)

All 12 runs passed: no crashes, 29–30 fps median, RTX 4090 (driver 610.62)
in every run.
* **Field (Elder):** our fork on Vulkan renders it correctly, solid cloak
  included.
* **Walhalla arena:** the floor is white in **every** combination, Plus
  OpenGL included (in round 1 Plus OpenGL showed it desaturated). Patches
  0002–0005 don't affect it.

Floor whiteness (share of white pixels in the floor region, 60 s shot):

| Build | Vulkan | OpenGL |
|---|---|---|
| ours | 82 % | 92 % |
| upstream | 82 % | 89 % |
| Plus | 82 % | 85 % |

### Why the arena floor is white (2026-10-10)

Across both rounds, only AMD Vulkan draws the floor textured. AMD OpenGL,
NVIDIA Vulkan and NVIDIA OpenGL all draw it white. Investigated on the mini
PC with a debug branch in the fork (`debug/amd-pipeline-crash`: toggles
`SSD_SKIP_FRAGS`, `SSD_ZERO_REGS`, and logging).

**Ruled out:**

| Suspect | Test on AMD Vulkan | Result |
|---|---|---|
| Rasterization-order attachment access (AMD has it, NVIDIA doesn't) | turned off | floor still textured |
| 3-component vertex formats (AMD-only rgba fallback) | logged | AMD supports all of them; path unused |
| Reads of unset shader registers | every register bank zero-initialised | floor still textured |

Zero-initialising through an `OpVariable` initializer crashes AMD's
compiler; explicit stores work.

**Found:**
* Bisecting draws by fragment shader (skip lists, screenshots compared by
  region) gives the floor shader: fragment **`9a8f3eb3`** (14 textures)
  with vertex `9ecd8510`.
  * It samples `Albedo0`, `ILLMINATION_RGBI0`, `Multi0` and
    `LightWeight0/1`.
  * It `textureGather`s `ShadowMap0` and compares the samples with the
    fragment's projected depth.
* `ShadowMap0` is the main **4× MSAA depth buffer**: a tiled X8U24 texture,
  1472×832, at `0x60DC0080`.
  * The cached depth surface there is 1440×816 samples. The texture covers
    816 rows rounded up to the 32-row tile.
  * Upstream's containment check (`retrieve_depth_stencil_as_texture`)
    rejects it. Vita3K then reads the texture from guest memory, which
    doesn't hold the GPU's depth.
  * Each path converts those bytes differently: AMD Vulkan to F32, NVIDIA
    Vulkan as native X8D24, OpenGL with a conversion its own code marks
    "TODO: this is wrong". The OpenGL backend never looks depth textures up
    in its surface cache at all.
* **Fix: fork patch 0006.** Tiled depth/stencil surfaces count as whole
  32-row tiles, the tiled-row part of Plus `98a65bff`.
  * On AMD the lookup now hits the surface cache; no X8U24 upload from
    memory remains.
  * The floor is unchanged (region difference 0.3).
  * **Hypothesis:** this fixes the NVIDIA white floor. To verify on the
    RTX 4090 with `dist/ss-delta-ours-update.zip`.
* Plus has this check but still draws white on NVIDIA. **Hypothesis:**
  another Plus change leads elsewhere. Not investigated.

**RTX 4090 round 3 (2026-10-10, `matrix-20261010-015047.zip`, our build with
patch 0006).** The floor is **still white** on NVIDIA Vulkan, though the
depth texture now comes from the surface cache: round 2 logged the
X8U24-from-memory upload on NVIDIA and round 3 doesn't. So patch 0006 fixes
a real bug, but not the white floor.

**Narrowed further on AMD** by editing the floor shader's cached SPIR-V
(spirv-cross → GLSL → glslang):

| Change to fragment `9a8f3eb3` | Floor |
|---|---|
| shadow gather forced to 0 / 1 | darker / unchanged. The shadow term doesn't make it white |
| `ILLMINATION_RGBI0`, `Multi0` or `LightWeight1` forced to white | 1–25 % white |
| `LightWeight0` forced to white | 76 % white |
| `Albedo0` forced to white | **86 % white, the look of the 4090** (82 %) |

Forcing albedo white also whitens the boss's tentacles, which use the same
shader with other textures. On the 4090 those look normal. So NVIDIA gets
**the floor's albedo texture** wrong, not the shader.

The textures (logged on AMD via the debug branch):

| Unit | Address | Size | Format | Mips |
|---|---|---|---|---|
| 0 (`Albedo0`) | `0x6304C050` | 512×512 | swizzled UBC1 (DXT1) | 10 |
| 1 (`ILLMINATION_RGBI0`) | | 1024×1024 | UBC3 | 11 |
| 2 | | 512×512 | UBC1 | 10 |
| 6 | | 512×512 | UBC1 | 10 |

All are uploaded from memory, not from cached render targets.

**Next:** a diagnostic run on the 4090. `diag.bat` in
`dist/ss-delta-ours-update.zip` runs the `debug/floor` build three times:
* as is;
* with `SSD_SOFT_BCN` (BC textures decoded on the CPU, Vita3K's path for
  GPUs without BC support);
* with `SSD_MAXLOD0` (base mip level only).

A textured floor in one of them points at NVIDIA's BC1 decoding or at the
mip chain.

**4090 diag 1 (2026-10-10, `matrix-20261010-021120.zip`).** As is, with
CPU BC decoding (`SSD_SOFT_BCN`), and with base-mip-only sampling
(`SSD_MAXLOD0`): all three have **exactly 81.7 %** white floor. So neither
BC decoding nor the mip chain is involved, and probably not the albedo
sample at all. **Hypothesis:** something drawn over the floor saturates it
on NVIDIA.
* Candidate `5b16f882` reads the framebuffer and adds
  `texture × vertex colour × alpha` to it (an additive layer). On AMD,
  skipping it changes nothing.

**4090 diag 2 (prepared).** `diag2.bat` runs the `debug/floor` build 8
times:
* as is;
* `SSD_HIGH_ACC` (forces the shader-interlock path for framebuffer reads);
* `SSD_SKIP_FRAGS=9a8f3eb3` (control: no floor);
* five groups of the arena's other 35 fragment shaders skipped.

AMD reference (white share / mean brightness of the floor region):

| Variant | White | Mean |
|---|---|---|
| as is, `SSD_HIGH_ACC`, groups 1, 2, 4, 5 | ≈ 21.7 % | 186 |
| group 3 skipped (`95c836aa a39e7dd7 a3cc810d a9941409 ad07babc af0c9ab6`) | 1.3 % | 158 |
| floor shader skipped | 0.6 % | 25 |

On AMD, group 3 supplies the floor's bright highlights.

**4090 diag 2 (2026-10-10, `matrix-20261010-022712.zip`).** Only skipping
the floor shader itself removes the white (81.5 % → 22.9 %).
`SSD_HIGH_ACC` and skipping any of the five groups change nothing. So on
NVIDIA the floor shader `9a8f3eb3` **itself computes white**. Its
textures, BC decoding, mips and overlays are all ruled out.

**Denormals.** The translator keeps pairs of halves packed in 32-bit float
registers (`uintBitsToFloat(packHalf2x16(...))`). A pair whose upper half
is zero or tiny is a 32-bit denormal, and the floor shader has such
constants: `sa[5].y = 1.70e-41`, `sa[6].x = 2.15e-41`. Vita3K requests no
float-controls behaviour, so each driver uses its default.

Tests on AMD (the Radeon 760M reports denormal preserve and flush-to-zero
supported for f16/f32/f64, independence "32BitOnly"):

| Change | Result on AMD |
|---|---|
| those constants zeroed by hand | floor black |
| `SSD_DENORM=preserve` (`DenormPreserve 32` in every shader) | identical to default (0.1–0.2) |
| `SSD_DENORM=ftz` (`DenormFlushToZero 32`) | geometry explodes (the vertex shaders break), floor still textured |

One earlier `preserve` run looked washed out at 40 s. That was a fade-in
caught while every shader was being retranslated; at 75 s it matches.

**Hypothesis:** AMD preserves 32-bit denormals by default, which this
translation needs. NVIDIA flushes some of them, and the floor shader is
where it shows. Forcing `DenormPreserve 32` on NVIDIA should fix the
floor. `diag3.bat` (in `dist/ss-delta-ours-update.zip`) runs as is,
`SSD_DENORM=preserve` and `SSD_DENORM=ftz` for 75 s each, and the log
prints NVIDIA's float-controls properties.

**4090 diag 3 (2026-10-10, `matrix-20261010-024932.zip`).**
* NVIDIA (driver 610.62) reports float controls: denorm preserve f16 1,
  **f32 0**, f64 0; flush-to-zero f16 0, **f32 0**; independence "All".
  So it can neither guarantee preserving nor be told to flush 32-bit
  denormals.
* As is 81.5 % white, `preserve` 84.2 %, `ftz` 83.4 %: the execution modes
  are effectively ignored.
* This is consistent with the hypothesis: AMD guarantees fp32 denormals and
  renders correctly; NVIDIA flushes some, and the floor shader breaks.
  **Not proven.**
* **Likely fix:** a translator change. Keep packed f16 pairs in integer
  (`uint`) registers instead of `uintBitsToFloat` floats, so no packed
  value ever passes through a float operation as a denormal. It is a
  sizeable change to Vita3K's shader translator.

**On hold (owner, 2026-10-10)** until direct NVIDIA access is available for
straightforward debugging.

**Intermittent guest fault (2026-10-10).** One arena run of the patched
build stopped after a guest invalid read at PC `0x8180cc02` (a load
through `r1 = 0x90c12bc8`). It didn't reproduce in the next 3 runs, and no
earlier log has one. To watch for in Phase 4's differential runs.

## Stale shader cache after the floor diagnostics (2026-10-10)

During Phase 4 the player in `ELDER DEFAULT MAP` showed up with the cloak
stretched across the screen and the body bare. The JIT-only build did the
same, so the recompiled code wasn't the cause. The cause was the shader cache
next to our exe (`cache/shaders/PCSA00152`). It still held shaders that a
diagnostic build (the `SSD_DENORM` variants) had translated. The cache is
keyed by the guest shader, so later builds reused those shaders and the
vertex shaders broke, as in the `SSD_DENORM=ftz` row above.

With the folder moved aside (`PCSA00152.stale-floor-diag`), the JIT build
and the native build (`SSD_AOT`) both render the field as in
`fix4-vk-elder.png`: solid cloak, correct body. After any run of a build
whose shader translation differs, move the title's cache folder aside.


## Vita3K-Plus on Vulkan crashes with AMD driver 26.8.1 (2026-10-10)

Plus 1.2's Vulkan runs above (2026-10-09 19:17–19:20) predate the driver
update. `setupapi.dev.log` dates the Adrenalin 26.8.1 install (Windows
driver 32.0.31041.1004) to 2026-10-09 22:42. Since then, every Plus Vulkan
boot crashes 2–3 s after loading `libssl`, both to the title and to
`ELDER DEFAULT MAP`:

* faulting module `amdvlk64.dll` 32.0.31041.1004;
* exception `0xc0000005`;
* offset `0x2d5a411`.

None of these were the cause:

* the shader cache: Plus's own cache is unchanged since 2026-10-09 19:20;
* a second Vita3K instance running;
* the config.

**Hypothesis:** the same kind of AMD shader-compiler fault as upstream's
(see patch 0002), which the newer driver now also hits with Plus's shaders.
Not confirmed: Plus doesn't log the faulting stack.

Plus on OpenGL still boots to the title. Our fork on Vulkan is unaffected.
For Vulkan rendering comparisons on this machine, our fork is now the
reference. Plus on Vulkan needs the old driver or another GPU (the RTX 4090
runs).

## Not measured yet

* Real button input: title → save creation → hub → quest. This needs
  focus-stealing input or a virtual pad.
* Audio. It was muted for the runs.
* Higher resolution multipliers, and `high-accuracy: true`.
* Per-thread CPU time.
* The Mind's Eye overlay bug (D-pad down in a quest).
