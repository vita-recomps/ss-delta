# 02 — Vita3K baseline

How the unmodified game behaves in Vita3K on the dev machine, recorded
2026-10-09. This is the reference the port is measured against. Repeat it
with `third_party/recomp/tools/v3kdrive.py` after any Vita3K update.

Paths: since [D17](decisions.md) (2026-10-13) the generic tools
(`v3kdrive.py`, `stackdump.py`, ...) and `recomp/` are in
`third_party/recomp/`, and the fork's `vita3k/ss-delta/` is split into
`vita3k/game-frontend/` and `vita3k/games/ss-delta/`. Dated entries below
keep the paths of their time.

## Setup

| Item | Value |
|---|---|
| Machine | Minisforum UM760 Slim: Ryzen 5 7640HS, Radeon 760M iGPU, AMD driver 25.12.1 (Vulkan 1.4, GL 4.6), 16 GB RAM |
| Vita3K | v0.2.1 build 4152-38bce160, portable in `extracted/vita3k/` (`pref-path` = `fs/`) |
| Firmware | `PSVUPDAT.PUP` 3.74 (build 571880) and the font package `PSP2UPDAT.PUP` 3.73 (build 571652), both from Sony's update servers; MD5s match the hashes in their download URLs ([hashes](hashes.md)) |
| Game | PCSA00152, merged 1.30 install. Debug-menu header: `Revision : 53172 2014-07-28`, `Build : Jul 29 2014 16:56:14 EF-BUILD-S6-5`, `Version : 01.30 Region : US Lang : us` |
| Config | defaults, except: audio-volume 0, log-level 2 (info), `memory-mapping: double-buffer` (default), resolution ×1, `disable-surface-sync: true` (default), `high-accuracy: false` (default) |

## How runs are driven (no keyboard focus needed)

`third_party/recomp/tools/v3kdrive.py`:

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

**Recheck (2026-10-12, `ss-delta.exe` at 3c67172, no JIT, shader cache
version 15).** The floor is **still white** on the RTX 4090 (owner); the
same package draws it textured on the Radeon 760M.

### The white floor is a NaN in min/max (RTX 4090, 2026-10-12)

Debugged directly on the RTX 4090 (driver 617.42) with our fork (Vita3K.exe,
JIT, Vulkan), by editing the cached SPIR-V of the floor's shaders: decompiled
with SPIRV-Cross, recompiled with glslang (`-e main_fs`/`main_vs
--source-entrypoint main`: Vita3K looks the entry points up by those names).
The post-processing pass changes colours, so values were read out either as
0/1 flags or bit by bit (32 black/white stripes per word).

**Ruled out on the 4090:**
* The denormal lead. Rewriting the floor shader's two denormal packed-half
  constants (`sa[5].y`, `sa[6].x`) as normal floats with the same low halves
  changes nothing, and packing a value into a float register and reading it
  back gives the same bits.
* Textures. Albedo samples correctly (the checkerboard shows when output
  directly); the lightmap and its UVs look plausible.
* Mapped guest memory: `memory-mapping: disabled` is white too.

**Cause.** The floor fragment shader `9a8f3eb3` computes
`lit = … + (1 − t)·sa3` with `sa3 = 1` and `t = v_TexCoord7.x`, then
`pow(lit, 0.556)`. On the 4090 `t` is **0**, which adds a full 1.0 of light.
`t` comes from the vertex shader `9ecd8510`'s height fog,
`t = pow(clamp(sa11.x − y·sa11.y, 0, 1), sa21.z)`, with
`sa11.y = 1/(0 − sa21.y)` and `sa11.x = sa21.x·sa11.y`. The arena's
`sa21 = (≈ −1000, 0, 0.86, 0)`: the fog range is 0, so `sa11.y = +∞`,
`sa11.x = −∞`, and on the floor (y = 0) the fog factor is
`0·(−∞) + (−∞)` = **NaN**. The clamp is two USSE ops, `VMIN` then `VMAX`.
* The translator emitted them as `FMin`/`FMax`, whose result for a NaN
  operand is undefined. NVIDIA returns 0 (it treats the pair as a saturate),
  so `t = 0` and the floor is white.
* AMD Vulkan returns the other operand (IEEE minNum/maxNum): `min(NaN, 1) = 1`,
  `t = 1`, textured floor. **Hypothesis:** the Vita's USSE does the same; it
  is the only reading that matches the textured floor.
* Forcing NaN-ignoring min/max in the vertex shader by hand makes the floor
  textured on the 4090, matching the AMD screenshots.

**Fix: fork patch 0039.** `VMIN`/`VMAX`/`VF16MIN`/`VF16MAX` and the SOP
blend `FMIN`/`FMAX` return the other operand when one is NaN, tested on the
bits (`(bits & 0x7FFFFFFF) > 0x7F800000`). `NMin`/`NMax` was tried first and
is not enough: NVIDIA still returns 0 with them, also with the
`SignedZeroInfNanPreserve 32` execution mode added. Shader cache version
16 (`vk16-*.spv`).
* RTX 4090, Vulkan: arena floor textured (white share of the floor region
  99.8 % → 10.7 %); `ELDER DEFAULT MAP` unchanged and matches the AMD
  screenshot `fix4-vk-elder.png`.
* RTX 4090, OpenGL: the floor is no longer white but flat grey-green; the
  OpenGL backend has its other known problems and isn't our renderer (D4).
* AMD (Radeon 760M, 2026-10-13): no change, as expected. The arena floor
  is textured and `ELDER DEFAULT MAP` matches `fix4-vk-elder.png` (haze,
  solid cloak), both at 30 fps. The full map sweep (`build/maps-0039-amd/`,
  `full_3d`, scale 1, all modules native): every map renders as in the
  Phase 7/8 sweeps, 29.4–29.7 fps mean, all still running at the end.
  ST17A doesn't start from Stage Select, as before. ST17C's dragon killed
  the idle player before the 40 s shot in two runs; with `-Load 25` the
  intro and the arena render.

### RTX 4090 map sweep (2026-10-12)

`tools/map-sweep.ps1 -Frames` over all 50 map IDs (`build/maps-4090/`), in
`ss-delta.exe` with patch 0039, all nine modules native (NativeCPU),
`full_3d` + scale 2 (1920×1088), Vulkan on the RTX 4090 (driver 617.42),
the same steps as the Phase 7/8 sweeps on the Radeon 760M.

* **Frame rate:** 29.3–29.6 fps mean on every map, one-second minimums
  26–29 (the Radeon at the same settings: 23–29). Every run was still
  going at the end.
* **Rendering:** every map that starts renders as on AMD: fog, skies,
  rain and snow, bloom, lava, water, shadows, the HUD and the Mind's Eye
  outlines. No white or black surfaces. The Walhalla arena (ST21A in a
  normal quest) has its textured floor.
* **As on AMD:** ST17A doesn't start from Stage Select; on boss maps
  (ST13B, ST14B, ST17C, ST22C, ST23A) the idle player is killed early, after
  the shots that show the map; `LEVEL_TEST_00GA` has its dark horizon band.
* ST02C's upward shots are a bright golden haze behind the tentacle
  pillars, textured and fogged. **Hypothesis:** intended; compare with the
  AMD sweep shots side by side.

**HDR.** The port has no HDR output: the Vulkan swapchain is 8-bit
`SRGB_NONLINEAR` (`screen_renderer.cpp`), as on the Vita. With Windows HDR
on (here: LG ULTRAGEAR, 10 bpc, SDR content brightness 240 nits), Windows
composites the window as SDR content at that brightness. HDR output
(an HDR10/scRGB swapchain, inverse tone mapping) is not planned (owner,
2026-10-12). The sweep above ran on that HDR desktop. Screenshots capture
the SDR image before Windows converts it, so the owner checked the panel by
eye with the `dist/ss-delta-922f795` package: the picture looks normal,
windowed and fullscreen (2026-10-13).

### RTX 4090 non-map pass (2026-10-13)

The checks of [06-compatibility](06-compatibility.md) that aren't map shots,
repeated on the 4090 (list there). Everything renders and behaves as on
AMD. One bug found, not vendor-specific:

* **Ad Hoc Play stuck at "Connecting .."** when opened after browsing the
  journal. `adhoc_matching.suprx` loads only then, and its native code
  expects it at `0x80757000`. That place was taken by then ("0x80757000 is
  taken; the module's native code will not match"), the module went to
  `0x80759000`, and NativeCPU stopped the calling thread ("no native code
  for the guest code at 0x80759000"). The AMD runs opened Ad Hoc Play
  straight from the hub, when the place was still free.
* **Fix: fork patch 0040.** `aot_init` allocates each recompiled module's
  place (its code, and the segment's tail up to the next module, at most
  256 KB) at boot; the loader frees it right before it places that module.
  The first version held only the code pages, and libult's data tail then
  pushed it out of place; holding up to the next module fixed that. After
  the fix every module, `adhoc_matching` included, logs "code placed ...
  where its native code expects it" and "matches guest memory".
* With the fix, the same route (journal first, then Ad Hoc Play) reaches
  Create Room / Search for Room, and two copies join a room, ready up and
  start a quest together.
* The ad hoc module needs `ssd_aot_fw_adhoc_matching.dll`: the first
  package built on the 4090 (`dist/ss-delta-922f795`) lacked it, because
  `build/recomp` was configured without `fw_adhoc_matching`.

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


## Fog and smoke differ from hardware (2026-10-10)

The owner compared title screens from Vita hardware, Plus 1.2 on Vulkan
(old AMD driver restored) and our fork on Vulkan:

* **Haze.** Hardware and Plus draw a bright grey-green haze over the whole
  title scene, and green smoke spreading from the logo. Ours is dark and
  high-contrast, with the haze almost gone and the smoke reduced to a glow
  around the logo.
* **In motion** (observed by the owner): our fog, dust and smoke flicker,
  and rectangles clip through them.
  * This shows on the title, in `ELDER DEFAULT MAP` (dust clouds) and in
    HarpyBattle (background fog).
* **Butterfly.** Its wings are patterned on hardware and on ours, but plain
  on Plus.

The JIT-only fork looks the same as the native build, so this is a renderer
issue, not a recompiler one. Our OpenGL path draws no background scene at
all, so it can't serve as a comparison.

**Cause: settings, not code.** These effects depend on two renderer
settings our config had off. Upstream defaults both to off for speed; Plus
defaults them on.

| Our fork with | Haze | Green smoke | Skulls, butterfly, candle |
|---|---|---|---|
| our old settings (sync off, `high-accuracy: false`) | missing | faint glow | yes |
| all four of Plus's settings | yes | yes | **missing** (owner, live) |
| surface sync only | yes | flickers, pops in and out | yes |
| surface sync + synchronous pipeline compilation | yes | hard-edged rectangles through it | yes |
| surface sync + `memory-mapping: external-host` | yes | yes | **ghost outlines only** |
| **surface sync + `high-accuracy: true`** | **yes** | **soft, steady in all 8 burst frames** | **yes, butterfly wings patterned** |

* **Surface sync** copies GPU-rendered surfaces back to guest memory. The
  game renders the haze offscreen and later reads it as an ordinary
  texture.
* **High accuracy** makes shader framebuffer reads exact, which the smoke
  particles' blending relies on.
* The burst runs took 8 screenshots 150 ms apart on the title, compared as
  smoke-region crops.
* With the final settings the field runs at 29.5 fps (min 29), and the
  title at 29.2 fps with one 46 ms frame. That is D4 update 4.
* Plus's plain butterfly wings may come from its `external-host` mapping
  (**hypothesis**, not tested on Plus).
* The two Plus depth commits (`98a65bff`, `d248beee`) were not needed. They
  don't apply cleanly to upstream anyway, because they build on earlier
  Plus refactors.

## Ground shimmer in motion, ST17C (2026-10-10)

Seen by the user during the Phase 5 quest sweep, in our build with all
four modules native (`SSD_AOT`). Stage Select index 330 (`testg010`, map
ST17C "Deciding Grounds", boss Dionaea) is a dragon arena. Its ground
looked glitchy and shimmered with grain while the camera moved, and looked
fine while it was still. The boss killed the idle player within the 75 s
run, so the run's screenshot shows the menu.

* **Hardware: the same.** On a real Vita the arena ground shimmers during
  camera movement too (the user, 2026-10-11). Not a bug of ours.
* Not recompilation: the differential check in that run found no mismatch
  in 3,143 calls.
* **Sampler trace (2026-10-11).** A temporary trace logged the sampler
  state of every texture the arena binds:
  * 111 swizzled textures. 73 of them, 128 px or larger and mostly
    UBC1/UBC3 with repeat wrapping, have a single mip level.
  * Textures with a chain are sampled with all of it. The sky (1024×512,
    2048×512) has 11 and 12 levels, as in the stage's `.mxt` files.
  * The game's own data has the same split. Over all 9,540 textures in
    the `archive` `.gxt`/`.mxt` files, 5,625 of the 128 px or larger
    swizzled ones ship **without** mips, against 3,135 with full chains.
  * Sampler settings are passed through as the game sets them: linear
    min/mag filters, trilinear on some, LOD bias 0 (31) or negative (23,
    15), no LOD minimum.
* So the grain is the game's own aliasing: a repeating texture without
  mips aliases while the camera moves on any GPU. That the mipless
  textures cause it is still a **hypothesis** (likely, not isolated).
* Phase 8 option: build mip chains for mipless repeating textures at
  upload, as a PC enhancement that changes the look.
* ST17B shares the ground and looks the same.

## Ghost book in the main menu (2026-10-10, fixed)

Seen by the user in the playtest (`ss-delta.exe`, all four modules native).
The main menu is a 3D scene with Librom, the book. A second, translucent
and red-tinted copy of the book trails behind it with a delay, most visible
while it moves. Other 3D objects such as bones are doubled the same way.
The background behind the book also looks lower resolution than the
foreground (`menu.png` in the repository root, not committed).

* **Not recompilation:** the ghost is the same with `[recompiled]
  enabled = false`, everything on the JIT (the user, 2026-10-10).
* **Hardware:** no ghost. There is a bloom glow around objects there, and
  it stays exactly on them while they move (the user, 2026-10-10).
* So the ghost is the game's bloom, drawn a frame or more late. The
  butterfly on the title screen shows it too (the user).
* **Cause (fixed, fork patch 0019):** the game builds its depth of field
  and bloom as chains of tiles in two atlas render targets (`618e80e0`
  512×384 and `618680c0` 256×512 in the menu). Each draw reads the tile
  the previous draw wrote. The draws use a full-target scissor, so Vita3K
  gives each its own render pass and, because this GPU path runs without
  texture viewports, its own recording. A tile read from the surface being
  rendered is copied in the recording's prerender commands, which run
  before the draws already recorded. The split came at the draw, after
  the draw's textures were synced, so the copy landed in the previous
  draw's recording and held the tile as it was a frame earlier. The lag
  added up along the chain: the last tile, blended over the scene, was
  five frames old. The split now happens at the first texture sync after
  a draw.
* **Found with:**
  * a temporary per-pass dump (the colour attachment copied after every
    render pass of chosen frames, saved as PNGs);
  * normalised correlation of each tile against its source tile in the
    current and the previous frame. Before: t10 matched the previous
    frame's t00 (0.95 against 0.85). After: the current one (0.94 against
    0.73).
* Ruled out on the way: surface sync, depth stores, and the render pass
  dependencies. Forcing a depth load broke rendering, because the game
  relies on depth starting cleared.
* Patch 0018 (a texture tile in the right part of a surface failed the
  surface cache's range check and was read from memory) was a real bug
  on the same path, but not the cause of the ghost. The user still saw it
  after 0018.
* Verified on the Librom transition in the menu (scripted route): before,
  a large blurred copy of the book trails it; after, none. The field is
  unchanged (29.5 fps).
* Confirmed by the user in `ss-delta.exe`: no ghost on the book or the
  title butterfly (2026-10-10).

## Not measured yet

* Real button input through the whole game: title → save creation → hub
  → quest. The fork's input pipe (patch 0005) drives menus without focus;
  Stage Select starts any quest (`BootSequence Quest Select`).
* Audio. It was muted for the runs.
* Higher resolution multipliers, and `high-accuracy: true`.
* Per-thread CPU time.

## Phase 7 map sweep (2026-10-11)

Every quest map through Stage Select in `ss-delta.exe`, all nine modules
native (NativeCPU, no JIT), Vulkan on the Radeon 760M.
`tools/map-sweep.ps1` repeats it.

* **Map list:** `quest_param.csv` from `archive_patch3`, read with
  `tools/lspk.py` and `tools/questmaps.py`. It has 581 quests on 50 map
  IDs, plus 3 quests without one. The Stage Select index is the quest's
  row.
* **Per map:** the map's first quest, screenshots 40 s after starting,
  with Mind's Eye on, after three camera turns and after a 2.5 s walk.
  About 2.5 minutes a map, 2 hours in all.
* **Frame rate:** 29.3–29.7 fps mean on every map, counted from 20 s
  after boot, so the quest's loading screen is included. One-second
  minimums were 14–29. Where in the run the dips fell was not checked.

Results:

| Result | Maps |
|---|---|
| renders correctly | 48: ST00A–C, ST01A–C, ST02A–C, ST03A–B, ST04A–B, ST05A–B, ST06A–B, ST07A–B, ST08A–B, ST09A–B, ST10A–B, ST12A–B, ST13A–B, ST14A–B, ST15A–B, ST16A–B, ST17B–C, ST20A–B, ST21A–B, ST22A–C, ST23A–B, SE01A, STAR, LEVEL_TEST_00GA |
| not reached | ST17A: its one quest (index 580, `q_l1206`) doesn't start from Stage Select. It shares the arena with ST17B/C |
| no map ID | 3 quests from index 572 |

* On boss maps (ST13B, ST22C, ST23A) the boss killed the idle player
  early. The screenshots taken before that show the map correctly.
* `LEVEL_TEST_00GA` is a developer test map: flat ground, sky, and a dark
  band at the horizon where no geometry is.
* No overexposure and no black blocks on any map. Those were OpenGL
  symptoms (above); the fork runs Vulkan.
* ST17B/ST17C ground grain: see "Ground shimmer in motion".

**Mind's Eye works.** Vita3K issue #3852 and Vita3K-Plus issue #34 report
it broken: only the weak-spot circles appear, without the outlines.

* In our build, monsters show as health-coloured (green) silhouettes or
  outlines, with pink weak spots. Hidden spots and items glow white or
  green. Seen on ST01B, ST05B, ST08A, ST08B, ST00C, ST10B and ST22A.
* The outlines read the main depth buffer as a texture. The temporary
  trace shows how the fork serves that read:
  * The game samples the 4× MSAA depth (`60dc0080`, 1440×816 samples) as a
    1472×832 X8U24 texture, tiled-rounded (patch 0006).
  * The fork copies the 720×408 pixel-rate depth image into a 736×416
    view, the same mapping halved.
  * The 1024² shadow map is read directly.
* Plus's fix for the same thing (`d248beee`) is not needed on our fork.

**Story scenes:**

* The book-page episodes render correctly (`BootSequence BookEpisode`,
  Sortiara's chronicle).
* The debug `CutEvent Select` menu lists only tutorial and prison event
  scripts, and they need a quest context to start.
* The story scenes in the user's playtest (intro and first story quest,
  2026-10-10) had no glitches besides the ghost book (fixed).

**Story scenes with a late save (2026-10-11).** The user supplied a
third-party save with the story complete (Apollo's PSV save database,
`00000002.zip`, kept out of the repository). It is plaintext, in the same
layout as Vita3K's `ux0/user/00/savedata/PCSA00152/` (`datag0001.bin/.bak`,
`system.bin/.bak`; its `sce_sys/` isn't needed). The run copied those four
files over the user's save and put the user's save back afterwards
(`build/save-backup-20261011/`). Nothing was saved in between.
Scripted through `ss-delta.exe`, all modules native, 27–30 fps:

* **Librom's Mad Chronicle:** every Magusar chapter and Sortiara's are
  listed. One entry in "The Memories Remain" is an animated ink smudge with
  text showing at its edge. That is the story's "clouded memory": Librom
  says so ("I feel that I'm missing some vital memory").
* **A late chapter (The Memories Remain Ch. 1):** title page, text and
  illustration pages, the red-ink highlight lines, the bright page
  transition, the monster card, the transport effect, the in-engine boss
  fly-by, and the quest at level 99. All correct.
* **The final choice (Fight Magusar):** Librom's dialogue, Yes/No, the
  Save/Sacrifice hands. Holding R (12 s; 4 s wasn't enough for the script)
  plays the sacrifice scene: the journal burns, then a golden memory
  vortex, then Librom's soul as a glowing figure, the cage, a red loading
  screen and Magusar's in-engine introduction and transformation. Then
  the battle starts. All correct.
  * Holding L (save Librom) makes him refuse, and the game returns to the
    hub. It isn't a separate branch.
  * The idle character loses the battle: "This is not the end…", then a
    save prompt. The run declined it.
* **Debug sequences** (`BootSequence`):
  * `EndingDelta` starts the final battle (the red wasteland). Correct.
  * `StaffRoll` opens a debug menu ("no clear" / "clear"; circle
    confirms). "No clear" plays the credits: clouds, particles,
    scattering letters. Correct.
  * `BookEnding` stays pure black at 30 fps, with or without input. Upstream
    Vita3K on OpenGL does the same. It probably needs context the debug
    boot doesn't set (**hypothesis**). It is not a difference from the
    reference.
* **Not seen:** the endings after defeating Magusar. They need a won final
  battle, which a script can't play. (Seen later, 2026-11-21: the owner
  won it with the cheats on; see "Owner playtest: the voice pack and the
  ending".)

## Phase 8 (2026-10-11)

All runs in `ss-delta.exe`, all modules native (NativeCPU), Vulkan on the
Radeon 760M.

**Resolution.** The 3D target follows `boot_config.ini`'s `ResoDown`
(see 01-research). Vita3K's `scale` multiplies everything.

| Setting | 3D target | Framebuffer | Result |
|---|---|---|---|
| `full_3d = false`, scale 1 (the Vita) | 720×408 | 960×544 | the Phase 7 sweep |
| `full_3d = false`, scale 2 | 1440×816 | 1920×1088 | ST01B, ST03A: correct, 29.6 fps; the 3D stays soft (stretched 4:3) |
| `full_3d = true`, scale 1 | 960×544 | 960×544 | ST01B: correct, 29.6 fps; visibly sharper |
| `full_3d = true`, scale 2 | 1920×1088 | 1920×1088 | **all 50 map IDs** (sweep below) |

* **Sweep at `full_3d` + scale 2** (`tools/map-sweep.ps1`, the same steps
  as Phase 7; `build/maps-full2/`): 29.5–29.7 fps mean on every map,
  one-second minimums 23–29. The screenshots match the Phase 7 sweep: fog,
  bloom, shadows, HUD and the Mind's Eye outlines are all correct. As
  before, ST17A doesn't start from Stage Select, and on boss maps the idle
  player is killed early.
* Mind's Eye at scale 2 (a burst of render-resolution frames on ST01B):
  the harpy's outline is drawn correctly. The depth read follows the
  multiplier.
* Patching only the 720×408 immediates (as VitaGrafix does) is not
  equivalent: rendering breaks and the game aborts (01-research).

**Screenshots at render resolution:** F12, or `frame:<path>` in
`v3kdrive.py`. The first version read the frame back from the frontend
thread, and a run at 60 fps aborted in `vk::Queue::submit` on the render
thread. The read-back now runs on the render thread (fork patch 0029).

**Touch.** Injected touches reach the game: a tap at (480, 300) advances
"PRESS ANY BUTTON" to the main menu. Touching Librom during his dialogue
did nothing, and the Black Rite icon didn't appear in a 60-second idle
stretch of a story quest. So the Black Rite binding is untested.

**Save import.** `--import-save` with the Apollo zip:
* It loads through the title screen into the hub, listed by the generated
  slot record ("Save data 1", "Imported").
* The save it replaced was copied to `ss-delta/save-backups/<time>/`.
* `--export-save` gives back the imported files byte for byte.
* A source without the two files at their sizes is refused (exit 1).

### 60 fps study

ST03A from Stage Select. 5 s idle, then a 3 s walk forward. Frames at
render resolution before and after the walk.

| Change | fps | Walk |
|---|---|---|
| none | 29.7–29.8 | reference |
| `[boot_config] FPS = 60` | 29.2–29.8 | same distance |
| flip threshold 1 (data patch, segment 1 `+0x2794`) | 29.4–29.8 | — |
| both | 29.6–29.8 | — |
| `[debug] frame_rate = 60` (timer period and flip threshold) | 57–58 | the quest never finishes loading |
| the same from 62 s (after the quest has loaded) | 57 | **same distance as at 30 fps** |

* The `FPS` key doesn't set the frame rate. A temporary log in
  `sceKernelDelayThread` showed what does: the main thread (8) sleeps
  21–33 ms a frame through `0x81804128`.
* That sleep is called from the main loop `0x812ac026`, which asks the
  frame timer `*(*0x81c957cc)` how long is left (`0x81804c88`). The timer
  is created with 30 (`0x812ab888: movs r0, #0x1e`). Its period, 33,333 µs,
  is the timer object's first u64.
* The display flips every 2nd vblank: threshold 2, static data at
  `0x81c95794`, copied to `0x81d3a630` at init.
* Frame time: `0x812ac73c` returns the measured interval (`+0x28` of the
  timer). It returns a fixed 1/30 s when a byte at `*0x81c9a488 + 5` is
  set. Player movement at 60 fps covered the same distance as at 30, so
  the gameplay code uses the measured interval for that, at least.
* **Blocker:** with 60 fps from the start, the quest-start transition never
  ends (still running after 80 s; it ends within 40 s at 30 fps).
  **Hypothesis:** the game streams the quest in during the main loop's
  spare frame time, and at 16.7 ms frames on this GPU (57 fps) there is
  none.
* Not checked: animation timing, Havok physics, AI, UI timers, audio sync.
* Next steps if 60 fps is pursued: find the loader's budget (or run
  loading at 30 and gameplay at 60), then compare gameplay timings against
  30 fps.

### 60 fps: the loading screen, and loading at 30 (2026-10-13)

Followed up on the owner's request (Phase 8 item, plan). Quest start of
ST03A from Stage Select, `ss-delta.exe`, all modules native unless noted.

**Not a frame budget.** At 60 fps the quest-start screen (the white swirl)
never ends, but a stack dump at that point (`tools/stackdump.py`, native
frames mapped to guest functions through the module's function table) shows
the main thread sleeping in the main loop (`0x812ac142`), the file threads
idle and two job threads polling (`0x812d4e68`). Nothing is blocked; a
condition just never comes true.

| Run at the quest start | Result |
|---|---|
| `frame_rate` 50 (48.9 fps) | stuck |
| `frame_rate` 40 (39.1 fps) | loads, plays |
| 60, the game's fixed 1/30 s step on (`*0x81c9a488 + 5`) | loads (gameplay then runs double speed) |
| 60 on the JIT, the main loop's update call (`0x812ac0bc`) sent to the fixed-step path `0x812ac74c` (patch) | loads |
| the same with the patch rewriting that call to its own target (control) | stuck |

So the stall comes from the frame time handed to the game update (stored
in `0x81d0a150`, read by the per-frame job loops `0x812d4d88`/`0x812d4dc8`),
somewhere in a check that fails when a frame is shorter than about 1/45 s.

**The loading screen.** `NowLoadingTask` (singleton `*0x81c9603c`, vtable
`0x81c5ef6c`, update `0x812b58ec`) runs a state machine at `+0xa4`:

* 2: plays the opening animation, then starts `roading_loop` (sic, a looping
  UI animation, frames 90–169) → 3;
* 3: when that animation reports finished (`0x81844266`: frame ≥ end)
  starts `roading_end` → 5;
* 5: when that finishes → 0 (idle). The only other writer of 0 is the reset
  `0x812b4d80`, called from several places.
* 6 / 4: after a quest the loop plays backwards (6) and the task rests in 4
  until reset.

The animation player (`0x81843d18`) advances `frame += dt × 30 × speed`. At
30 fps the loop flag (`+0x294` bit 2) is cleared about half a second into
state 3, the animation runs to its end and the task moves on. At 60 fps the
flag is never cleared: the loop runs forever (probed for 3 loops). What
clears it was not found (not the animation's own code, nor its keyframe
events, which are sound cues). **Hypothesis:** the loader's "done" signal
is the frame-time-dependent check above.

**Update (2026-11-23): found and fixed in the game's code.** The loader can
finish while the screen's opening still plays, before the loop starts, and
the one call that ends the loop is then lost (01-research, "The loading
screen at 60 fps"). Recompiler overrides fix that (D30); with an eboot
that has them, loading screens run at the set rate, and the 30 fps switch
below is only kept for an eboot without them.

**The fix (fork patch 0041).** `[display] frame_rate = 60` sets the frame
timer and flip threshold every frame: 60, but 30 while the loading task is
in state 2, 3 or 5. The first version used "state ≠ 0" and stayed at 30
after leaving a quest (state 4); states 6 and 4 now stay at 60.

**Checks at 60 (Radeon 760M, `full_3d`, scale 1):**

* Gameplay timing: the Phase 9 idle fight (b0514, ST23B) 5× at 30 and 5×
  at 60, alternating. Loading 18.7 s in all ten (the loading screen runs at
  30). Player down 24.7 s after play at 30 (19.9–33.0) and 26.0 s at 60
  (17.6–34.2), the same spread as in the native/JIT comparison. Fights at
  56.3–56.9 fps.
* All 50 map IDs from Stage Select (`build/maps-60/`): every quest that
  starts at 30 starts at 60 and renders the same; all still running. ST17A
  doesn't start from Stage Select, ST17C's dragon kills the idle player
  before the shots, as at 30. Gameplay 54–57 fps on this GPU; one ST22A shot
  caught a white boss flash that a rerun didn't repeat.
* Player 3 on the 100% save: title, load, hub (57 fps), Librom's dialogue,
  the journal (56 fps), Mad Chronicle, a story chapter's book pages, its
  quest started from the journal ("Now Loading" at 30, tips, Press Any
  Button), the quest (54–57 fps), Exit Quest, results, the save prompt (No),
  back through the journal to the hub (58 fps).
* Not checked: audio against cutscenes, Havok physics in detail, every
  animation; the owner's playtest decides. The option stays off (30) by
  default.

## ST03A water: a dark patch during the opening fly-through (2026-10-11, fixed)

Seen by the user: early in ST03A's opening camera fly-through, a dark,
straight-edged shape cuts through the water near the bottom of the screen.
It is gone once the character spawns. The user saw something similar on
another water map (not identified). **Not on a real Vita** (the user,
2026-10-11).

* **Reproduced.** Every rendered frame of the intro was recorded (the new
  `record:` step). Stage Select ST03A, frames from 7 s after the quest
  starts: the patch shows for 5–7 frames (~200 ms, frames ~135–141), on
  the shot that skims the water. Screenshots taken every second miss it.
* **Narrowing down.**
  * The whole water surface is one draw (vertex shader `dbd8accb`,
    fragment `34b195c9`, 7,566 indices, 1,617 vertices). Its indices and
    vertex streams never change (all 544 draws of the quest dumped); only
    the vertex uniforms (camera, time) do.
  * Showing the environment-map lookup alone: whole water *triangles*
    take one smooth, dark, detail-free value during those frames. Their
    edges are the mesh's big triangles near the camera.
  * Ruled out on the way: memory mapping, the recompiled code (also on
    the JIT), the other shaders, the vertex ring buffer (wraps are not
    tied to it), a stale cached maximum index, and float edge cases
    (RCP/LOG/RSQ made finite).
* **Cause.** Vita3K's translated vertex shaders write depth as
  `max(z/w · scale + offset, 0) · w`, clamping depth below 0 per vertex.
  The camera skims the water, so big water triangles cross the near
  plane. For the vertices the clamp touches, `z` no longer varies linearly
  with `w`, so the GPU's clipper cuts those triangles in the wrong place
  and interpolates their attributes (reflection vector, colours) from the
  wrong points. Removing the clamp removes the patch.
* **Fix (fork patch 0032).** Depth below 0 is clamped per fragment by the
  pipeline (Vulkan `depthClamp`, enabled when the GPU has it) and the
  shader no longer clamps per vertex. Shader cache version 14 → 15, so
  every install retranslates its shaders once. ST03A's intro: no patch,
  the rest unchanged.
* Depth clamp also turns off clipping at the far plane: geometry beyond
  it is drawn at the far depth instead of being cut. A full sweep of all
  50 map IDs after the fix (`build/maps-dclamp`) matches the Phase 8
  sweep shot for shot (skies, fog, distance, Mind's Eye), at 28.6–29.7 fps
  mean. Its lower one-second minimums (7–12 on three maps) were first-use
  shader compiles: version 15 starts from an empty cache. Four deep
  Stage Select entries were mis-navigated in that cold run; rerun warm,
  they match too.
* Side finding: a run with `memory-mapping` disabled leaves shaders in the
  cache translated for that mode (keyed by the GXP alone). With the normal
  mode they crash the AMD driver (`amdvlk64.dll`, `c0000409`) at quest
  load, on every later run, until the cache is cleared. Players can't hit
  this: `ss-delta.exe` fixes the mode.

## Haze over near objects at 960×544 (2026-10-11, fixed)

Seen by the user in the hub (the Librom view): a bluish, blurred band over
the bones in the upper right. It came with `full_3d` (Phase 8), not with
the depth clamp: with `full_3d = false` the bones are sharp.

* Per-pass dumps of one frame in both modes: the scene pass is the same;
  the depth-of-field composite (fragment `67d7b18a`, vertex `113bf15f`)
  is where the bones turn into the blurred copy. Its uniforms are the
  same in both modes (dumped).
* The composite reads depth at `v_TexCoord1`, and the vertex shader
  computes that as the screen UV × (0.978261, 0.980769), 720/736 and
  408/416, from its literal table. Right for the 720×408 mode, whose depth
  texture is padded to whole 32-pixel tiles (1472×832 samples for
  1440×816); at 960×544 the texture (1920×1088) has no padding, so depth
  was read up to 2% short of the right and bottom edges. Near objects got
  the background's depth, hence its blur and haze.
* Four vertex shaders seen carry the pair (`113bf15f`, `3951bb3a`,
  `93f3cfcd`, `bdf52db5`), stored as consecutive literal-table entries
  (`{u32 register, f32 value}`). The eboot's data constants at
  `0x81CC6C50`/`58` (VitaGrafix's sites) are not what these shaders use.
* **Fix (fork patch 0033):** `ss-delta.exe` with `full_3d` sets both
  values to 1.0 in each shader as the game registers it (a GXM hook,
  `on_program_registered`). The hub's bones look as at 720×408, sharper.
* Ruled out on the way: the depth-as-texture path (sampling in place vs
  copying), the eboot's UV-scale constants, the composite's uniforms.
* Full map sweep after the fix (`build/maps-uvfix`): all 50 map IDs
  consistent with the previous sweep, 29.3–29.8 fps mean.

## Native against JIT: an idle fight, timed (2026-10-12)

Phase 9 asks whether the recompiled code changes timing-sensitive behaviour
(Havok physics, monster AI). The same `ss-delta.exe` ran the same quest
start ten times, alternating `[recompiled] enabled = true` (all modules
native, NativeCPU) and `false` (everything on dynarmic), so the CPU backend
was the only difference. Quest `b0514` (ST23B, Stage Select index 317): the
player stands still while two bosses arrive and kill them. A frame every
~1.1 s from the start button; times from the frames' file times. *Play*: the
first frame with the quest HUD. *Down*: the last HUD frame before the
"A sorcerer is dying" screen. *Menu*: back on Stage Select.

| | play (s after start) | down (s after play) | menu (s after play) |
|---|---|---|---|
| native ×5 | 18.7 (all) | 24.0 (20.9–32.0) | 28.1 (25.3–36.3) |
| JIT ×5 | 18.6–18.7 | 23.1 (16.5–28.6) | 27.3 (20.9–33.0) |

* The loading time is the same to the frame.
* How long the idle player lasts varies by about ±5 s between runs in
  **both** modes; the 0.9 s difference of the means is well inside that
  (standard deviations 4.7 s native and 4.9 s JIT; Welch t ≈ 0.3).
* Frames aligned on the start of play show the same sequence in all ten
  runs: a small monster walks up, the winged boss lands from the left at
  +3–6 s, the charges and the second boss's attacks at +9–15 s. Which run is
  early or late does not follow the mode (the slowest of each mode is the
  first run).
* Run-to-run variation is expected: the game runs threads at host speed and
  Vita3K is not deterministic, so frame-exact positions cannot be compared
  between runs. The per-call differential mode (`SSD_AOT_DIFF`, Phase 5:
  0 mismatches in 83,656 calls, and in 116,609 calls in the field) remains
  the exact check; this one shows the outcome of a fight does not shift.

**Result:** no difference between native and JIT in a fight's timing or
outcome, within the run-to-run spread of the emulator itself.


## 60 fps on a discrete GPU, and the 57-58 cap (2026-10-15, fixed)

The owner ran the setup's build (GitHub Actions) on the RTX 4090 PC
(Ryzen 7 7800X3D): 47-50 fps at scale 1, a little less at scale 2, where
the Radeon 760M runs 56-57.

* **Surface sync is the cost.** With `[debug] surface_sync = off` the 4090
  runs 57-58, but ST03A (snow) is blown out: brightness 221 against 184 in
  a screenshot at the same moment.
* **What is synced.** One surface: a 480×272 RGBA8 image at `0x606c0020`,
  which the game's own CPU code reads every frame (`SSD_SYNC_TRACE=1`).
  It is probably the auto-exposure meter (**hypothesis**: the read site
  wasn't looked at). No texture lookup misses the surface cache.
* **Not the waiting.** Signalling notifications early for scenes the CPU
  doesn't read back (`targeted`), or for all of them (`latent`), didn't
  help on the 4090. Both still render ST03A correctly.
* **The cause: reading video memory.** The double-buffer mapping's mirror of
  guest memory is allocated for sequential writes. On a discrete GPU with
  Resizable BAR that is device-local, host-visible memory, which the CPU
  reads very slowly. The sync's `memcpy` back to guest memory runs on the
  request thread, which also releases finished frames. The fix (fork
  `e8d0417e`): the image is also copied into a buffer of its own in cached
  system memory, and the CPU copies from there. **Owner: `exact` now holds
  57-58 at scale 1 and 2 on the 4090, and the snow looks right.**
* **57-58 on every GPU.** With host vsync off it stays 57, so it isn't
  presentation. The game waits out its frame timer (16666 µs at 60), then
  flips on the next vblank. Host waits overshoot by up to about a
  millisecond, so a few frames a second missed their vblank and took two.
  With the timer at 16000 µs (fork `7f8a001c`), the ST03A quest runs at
  59-60 (median 60) on the Radeon 760M. The flip still waits for each
  vblank, so it can't exceed 60.

## 120 fps study (2026-11-24; implemented & verified 2026-11-28)

The owner asked whether 120 fps is possible. A local, uncommitted experiment
on the fork (`SSD_VBLANK_HZ` for the emulated vblank rate, a `frame_rate =
120` choice with an 8000 µs frame timer, `SSD_PRESENT_IMMEDIATE` for Vulkan's
immediate present mode). Junction test folder, Radeon 760M, Stage Select's
first quest (rain, two enemies), native code, vsync off. Run-to-run noise on
that map is about ±3 fps.

| Vblank | Timer | Present | Menu | Quest |
|---|---|---|---|---|
| 60 Hz | 60 (16000 µs) | FIFO-relaxed | 60 | 54–56 |
| 60 Hz | 120 (8000 µs) | FIFO-relaxed | 60 | 55–56 |
| 60 Hz | 120 | immediate, scale 1, 720×408 | 60 | 55–60 |
| 120 Hz | 120 | immediate, scale 1 / scale 2 | 116–118 | 54–56 |
| 480 Hz | 1000 µs (unthrottled) | immediate, scale 1 / 2, surface sync exact / off | 460–470 | 53–57 |

What limits the frame rate:

* **The emulated vblank, through the pad.** The game reads the pad with the
  blocking `sceCtrlReadBufferPositive2` (and `sceTouchRead`), which the fork
  wakes once per vblank (`ctrl.cpp` `ctrl_get`). Vblank is a fixed 60 Hz
  (`display.cpp`, `TARGET_FPS`), so any timer gives exactly 60. The flip
  threshold doesn't pace anything here: the display callback only picks
  `NEXTFRAME` or `IMMEDIATE`, and the fork ignores both. The comment "the flip
  still waits for each vblank" in `update_frame_rate` is really this pad wait.
* **Presentation.** The Vulkan renderer never reads the `vsync` setting (only
  OpenGL applies `pending_vsync`). It takes mailbox, else FIFO-relaxed, else
  FIFO. The 760M has no mailbox, so a 60 Hz monitor caps at 60 whatever
  `vsync` says.
* **The game's own CPU work, in quests.** Unthrottled, the quest stays at about
  55 fps at both resolutions and with surface sync off, so the GPU's fill rate
  isn't the limit. One guest thread runs at 77–80% of a core (~14 ms a frame at
  54 fps), and all six stack samples were in `ssd_aot_eboot` (recompiled game
  code), not in the renderer or HLE. **Hypothesis:** the heavy NEON functions
  of 05-recompiler "Results" are part of it; the hot guest functions weren't
  mapped.
* With a 120 Hz vblank, a frame that misses 8.3 ms waits for the next vblank
  (16.7 ms). A machine that can't hold 120 then gets 60 or less, not 90.

To do it: make the vblank rate follow `frame_rate`, or stop the pad and touch
reads blocking per vblank; honour `vsync = false` on Vulkan (immediate or
mailbox) and use FIFO on a high-refresh or VRR display otherwise; set the
timer to about 8000 µs. Not checked: per-frame game logic like the Blitz bug
(D30; its override scales correctly at k = 0.25, but others would be twice as
far off as at 60), audio, Ad Hoc Play between players at different rates, and
how fast the owner's Ryzen 7 7800X3D runs that game thread.

### AYN Thor (120 Hz) check (2026-11-28)

Checked on the AYN Thor (Adreno 740, NativeCPU, 0 JIT calls, `Present mode: Mailbox (vsync on)`):

| Screen / scene | Driver & scale | Display mode | Target | Measured fps (frame time) |
|---|---|---|---|---|
| Title screen | Qualcomm system, 1× | 120 Hz | 120 | **120** (8 ms) |
| Title screen (live `120 → 90 → 60 → 30`) | Qualcomm system, 1× | 120 Hz | 90 / 30 | **90** (11 ms) / **30** (34 ms) |
| ST03A (`q_e0101`, arena intro) | Turnip T23, 1× | 120 Hz | 120 | **98–121** (avg 108) |
| ST03A (`q_e0101`, combat) | Turnip T23, 1× | 120 Hz | 120 | **96–103** (avg 102, 10 ms) |
| ST03A (`q_e0101`, live `120 → 90`) | Turnip T23, 1× | 120 Hz | 90 | **85–90** (11–12 ms) |
| ST03A (`q_e0101`, intro/arena) | Turnip T23, 2× | Adaptive 60–120 Hz (promoted to 120.00 Hz) | 120 | **72** (14 ms, avg 73) |
| ST03A (`q_e0101`, combat) | Turnip T23, 2× | Locked 60.00 Hz | 120 | **59** (17 ms, avg 64) |

* The loading screen completed cleanly at 120 fps (`loading screens at the set rate`), and live Settings menu toggles (`vsync` and `120 → 90 → 60 → 30`) switched without warnings.
* Under `Mailbox` on Turnip, missing 8.3 ms at 120 Hz did not snap down to 60 fps (96–103 fps at 1×, 72 fps at 2×), and adaptive `60–120 Hz` promoted SurfaceFlinger to `120.00 Hz` automatically.
* **Timed 30 / 60 / 90 / 120 fps comparison (ST03A `q_e0101`, `scale = 1`, Turnip T23, 2026-11-28):** with fixed 16 s post-launch load wait and a 15 s wall-clock interval, all four rates reached the same arena-intro and post-intro combat state at the same wall-clock times (`30` → 30 fps / 34 ms; `60` → 60 fps / 17 ms; `90` → 89 → 85 fps / 11–12 ms; `120` → 99 fps, avg 107 / 10 ms). Boot with `skip_intro = false` at `120` also reached the title screen cleanly (**121 fps**, 8 ms, avg 119).
### Windows high-refresh PC & cross-rate Ad Hoc check (2026-11-28)

Checked on Windows 11 (Ryzen 7 7800X3D, RTX 4090, 2560×1440 @ 143 Hz, NativeCPU):

* **VSync & live toggles:** `vsync = false` selected `Present mode: Immediate (vsync off)` and `vsync = true` selected `Mailbox (vsync on)`. Live menu toggles (`Mailbox → Immediate → Mailbox` and `120 → 90 → 60 → 30 → 120`) switched cleanly with zero Vulkan/swapchain errors. Adding a Windows high-resolution `VblankPacer` (`timeBeginPeriod(1)` + `CREATE_WAITABLE_TIMER_HIGH_RESOLUTION` + 400 µs spin margin in `display.cpp`) and widening 90/120 fps timer headroom to `9800`/`6800 µs` (`frame_pacing.h`) eliminated Windows 1 ms CV overshoot.
* **Timed Blitz (`Firebird Pinion+`, `SE01A` `q_g0001`, `vsync = false`):** Open backward Blitz casts (`end_dist` `13.54–13.85`, `max_dy` `2.21–2.42`, `dur_3b` `0.507–0.636 s`) and forward lock-on rush casts (`18.37–19.41`, `0.629–0.682 s`) stayed consistent across `30`, `60`, `90`, and `120` fps with no high-rate overshoot.
* **MSVC `/O1` developer build bottleneck (fixed in `third_party/recomp`):** Profiling `MainThread` on local MSVC developer builds (`build/recomp/`, `/O1` without `/Oi`) showed >65% of CPU time spent in out-of-line NEON/VFP helpers (`nf_in`/`nf_out`) making 4-byte `VCRUNTIME140.dll!memcpy` calls (release Zig/Clang `-O1` builds were unaffected). Adding `/Oi` to `recomp/CMakeLists.txt` and using `std::bit_cast` + `__forceinline` in `armrecomp.h`/`neon.h` raised `120 fps` (`vsync = false`, `scale = 2` `1920×1088`, `surface_sync = exact`) from `~95–102 fps` on Title and `~68–71 fps` (`1×`, `latent`) in `ST03A` (`q_e0101`) to **locked `120.0 fps` (`8.33 ms` avg, `8.31–8.36 ms` median)** on both.
* **Journal, FMV & Ad Hoc cross-rate:** Journal Ch. 1 narration and opening `.mp4` FMV playback ran at normal 1× speed at 90 and 120 fps. Cross-rate Ad Hoc Play between the AYN Thor at **120 fps** and Windows at **60 fps** worked cleanly with no desync or errors.

## Blue haze in ST02A: colour outputs clamped (2026-10-18, fixed)

The owner compared quest 2 (ST02A, Stage Select index 3) with a Vita
screenshot: ours had a blue-violet haze over the distance (the cave in the
upper left) and a bluer sky. Measured in matching regions, red and green
agreed with the Vita and blue was far higher (far ground 92,100,156 against
103,110,128). The Phase 7 sweep already shows it.

* **Ruled out:** the recompiler (all on the JIT: the same), `full_3d`
  (720x408: the same), EXP/LOG in base 2 (no change), the god-ray pass
  (skipping `d336bf85`: no change), surface sync (off: brighter, still blue).
* **Where.** A RenderDoc capture (`VITA3K_RENDERDOC_FRAME=file`): the pixel
  history put the blue in the scene's own draws (the cave's last draw wrote
  0.35,0.39,0.62), not in post-processing. The shader debugger showed its
  colour input at (0.70, 1.02, 3.01).
* **Why.** The fogged geometry's vertex shaders (`8fce4976`, `9ecd8510`, ...)
  compute the fog colour as ambient light (spherical harmonics, `cAr` ..
  `cC`) times `iFogCol0` (0.5, 0.75, 1.0) and pass it out through COLOR0/1.
  The map's constants are authored that way (four-decimal values in guest
  memory, next to a colour matrix and the fog colour): `cAb` points another
  way than `cAr`/`cAg`, so blue reaches about 3 toward the cave.
* **Fix (fork `a32f1c4c`):** COLOR0 and COLOR1 vertex outputs are clamped
  to [0, 1] (`clamp_color_varyings`, set by `ss-delta.exe` and
  `shinobido2.exe`; `VITA3K_CLAMP_COLOR_VARYINGS=0/1` overrides it). Far
  ground 101,112,132 against the Vita's 103,110,128. **Hypothesis:** the
  Vita's colour iterators saturate; utakata's first mission matches its
  hardware screenshot only with the clamp too. Shader cache version 23.
* Six quest maps (ST16A, ST03A, ST02A, ST01A, ST06A, ST09A) with and without
  it: 60 fps in both; screenshots differ only by what moved, apart from
  ST02A. **Owner: the fix looks right.**

## EU version (PCSF00532 1.30): installed and played (2026-11-17)

The owner's EU dump, through `install-game.py --name scratch-eu` with
`game.json`'s EU hash (D19); Radeon 760M, Vulkan, native code (all ten
modules), `frame_rate = 60`.

* Install: `eboot.bin (PCSF00532): 1.30 (EU)`; every module recompiled
  with nothing left to the fallback CPU; the eboot's code hash
  `f6f20671281686e3`, as for US (01-research, "EU version").
* Title menu: 60 fps, English. A US save (a copy of slot 2, story
  complete) imported with `--import-save` went to `savedata/PCSF00532`.
  The game listed it, loaded it and reached the Librom at 59–61 fps.
* Stage Select (`bootseq PCSF00532 'Quest Select'`, first quest): 30 fps on
  the loading screen (loading state 2), then 60 fps again. In the field,
  52–56 fps in the rain.
* US regression: the same `ss-delta.exe` on the junction test folder
  picks `PCSA00152`, and the US build's recompiled modules pass the
  guest-memory check. Title menu at 60 fps.
* Not checked: the other EU languages (the test used Vita3K's English
  system language), and Ad Hoc Play between an EU and a US copy. The EU
  game's add-on data passed `addon_data_present`, but the unlock itself
  did not run: the imported US `system.bin` already recorded the add-ons
  ("already recorded in the save"). **Hypothesis:** an EU `system.bin`
  has the same layout, so the unlock works the same way.

## Language setting (2026-11-17, GitHub issue #3)

`[game] language` in `ss-delta.ini` (Language on the settings menu's Game
page) sets Vita3K's system language, which the game reads at boot
(01-research, "Text language"). Fork commit "ss-delta: a language setting".
Radeon 760M, native code, the junction test folder (US) and
`dist/scratch-eu` (EU):

* US, `french`: title screen "APPUYER SUR UNE TOUCHE"; `portuguese`:
  "PRESSIONE QUALQUER BOTÃO".
* EU, `german`: "BELIEBIGE TASTE DRÜCKEN".
* Settings menu: the row shows the label ("Portuguese (US game)"), and a
  change is written to the ini (`[game] language = english`), used at the
  next start.
* Not checked: Spanish and Italian, text past the title menu (the same
  language index drives every text folder), and Ad Hoc Play between copies
  set to different languages.

## Japanese Voice-over Pack: installed and heard from (2026-11-20)

The owner's US dump of the add-on (a NoNpDrm zip laid out as ux0:
`addcont/PCSA00152/SSS000CVN0000001/` and
`license/addcont/PCSA00152/SSS000CVN0000001/*.rif`); research in
01-research ("Japanese Voice-over Pack").

* **Install, before:** `ss-delta.exe --install-content <zip>` reported
  success but left the pack PFS-encrypted, with the licence copied into
  the pack as `0000001/<name>.rif`. Vita3K decrypts a NoNpDrm dump only
  from `sce_sys/package/work.bin`, and it picked a content's zip entries
  with `contains(<content path>)`, which `license/addcont/<same path>`
  also matches.
* **Install, after** (fork commit "installer: NoNpDrm dumps laid out as
  ux0"): entries are picked by prefix, and an add-on (or game) without a
  `work.bin` takes the `.rif` the dump keeps in `license/addcont/...`
  (`license/app/...`), from a zip or a folder. The zip and the unpacked
  folder both install decrypted (`voice_jp.pk` starts with `SXDF`; the
  licence goes to `ux0/license/PCSA00152/`). Without a licence the
  install still succeeds, with a warning that the files look encrypted.
  `install-game.py` with the EU game and this zip installs both;
  `dumpinfo.py` shows the add-on's "licence inside".
* **US game** (test folder, native code): the pack is listed and
  `voice_jp.pk` opened at boot; Options → Lang/Sub Settings → Voice
  Language switches English → Japanese.
* **EU game** (`install-game.py --name scratch-eu-jpvoice --no-recompile`,
  JIT): no decrypted EU pack exists here, so the US pack's decrypted files
  were linked into `addcont/PCSF00532/SSS000CVN0000001/` with the EU pkg's
  own `param.sfo`. A US save imported into slot 1; Voice Language offers
  Japanese beside English (UK). With file reads logged (a temporary build),
  each of three Librom lines after the switch opened and read `voice_jp.pk`
  from the EU folder; `voice_ue.pk` was not read.
* **End to end, PC** (a scratch Windows release from `make-setup.py`,
  the setup download cache): the first setup with the game and the pack
  (`setup.py --install <game> --install <pack>`, as RecompLauncher's
  `--dump {input:game} --dump={input:voice}` reaches it) built everything
  in 593 s, the pack decrypted, and wrote the build stamp
  (`ss-delta/build.json`). Then, through `ss-delta.exe` with its output
  piped as a launcher has it:
  * the pack deleted, `--dump <game> --dump=<pack> --build-only --progress`:
    "The game is built here already: installing the add-on only", **5 s**,
    the pack back and decrypted;
  * `--dump=<pack>` alone: 6 s, the same;
  * the EU pack's `.pkg` with the US `.rif` beside it as `work.bin`: the
    licence found beside it, the note that a PCSF00532 add-on isn't used
    by the PCSA00152 game, then the install failed (exit 1: the wrong
    licence), leaving only an empty folder.
  * The stamp's checks: a changed executable's SHA-256 (a new release)
    means a full build; the game's own dump alone, or another game (the EU
    dump), means a full build too.
* **End to end, Android** (the Thor, the `ssdeltatools` test package with
  the game built on the device; a debug APK of these changes, without the
  build tools): the "Add an add-on" shortcut's intent opened the setup
  screen and the file picker; the US zip picked from `Download` installed
  in about 4 s through the front end's step (licence from
  `license/addcont/...`, `voice_jp.pk` starts with `SXDF`); the screen
  then said "Installed: jap-voice-US.zip. The game is built." with Play.
  In the game (Turnip, native code), Voice Language offered Japanese, and
  after the switch each of two Librom lines opened `voice_jp.pk`
  (`log_level = trace`).
* **Heard** (the owner, 2026-11-21): see "Owner playtest: the voice pack
  and the ending" below.
* Not checked: a real decrypted EU pack, the EU pkg
  through `--zrif` (upstream's `install_pkg`, which handles add-ons), the
  setup window's add-on-only path (the same `setup.py` run), and the
  shortcut from a launcher's long-press menu (published with
  `ShortcutManager`; started here by its intent).

## Undub patch: a rePatch mod (2026-11-21, GitHub issue #8)

The patch from archive.org (MD5 as in 01-research, "Undub patch"),
unpacked, and as a zip of its `rePatch` folder. Fork: `game-frontend/repatch.cpp`;
kit: `dumpinfo.py` reports kind `mod`, and `setup.py` installs mods like add-ons.

* **Install, PC setup** (the scratch Windows release from the voice-pack
  tests, the new `ss-delta.exe` and kit scripts copied in, its build stamp
  set to that executable as a release would have it):
  `setup.py --install <unpacked folder>`: "The game is built here
  already: installing only the add-ons and mods", about 1 s. The nine
  files are in `fs/ux0/rePatch/PCSA00152/`; `ux0/app` is unchanged.
* **US game** (that folder, native code): the log says "rePatch: 9 files
  ... read in place of the game's own". At boot the game opens
  `voice_ue`, `voice_patchv_ue` and `archive_patch3` (`.pkh`, `.pk`) from
  `ux0/rePatch`. Title screen as usual. New Game, then the save dialogs,
  then the prologue: the opening movies, then voiced lines streamed from
  the undub's `voice_ue.pk` (`OP_NA_0501_ue`, `OP_PR_0001_ue`, by the
  offsets read; `VITA3K_TRACE_READS=1`).
* **Off:** with `[game] repatch = false` the log says "mods off", and no
  file is read from `ux0/rePatch`.
* **EU game** (the EU scratch folder): `ss-delta.exe --install-content
  <zip>` installed the zip (the mod made for PCSA00152) into
  `ux0/rePatch/PCSF00532/` ("installed for PCSF00532, the game installed
  here"), `voice_ue.pk` intact (same MD5). The EU game booted to its title
  screen with the nine files served from there.
* `dumpinfo.py` finds the mod from the unpacked folder, its `rePatch`
  folder, `rePatch/PCSA00152` itself and the zip; the game's dump still
  reads as game and update.
* **Android** (the Thor, the `ssdeltatools` test package with the game
  built on the device; a debug APK of fork `dda265d9`, without the build
  tools): the "Add an add-on" shortcut's intent opened the file picker,
  and the zip picked from `Download` installed through the front end's
  step ("Installed: undub-test.zip. The game is built.", the button now
  "Add an add-on or mod…"). The nine files are in
  `fs/ux0/rePatch/PCSA00152/`, `voice_ue.pk` with the same MD5 as the
  original. Play: "rePatch: 9 files ... read in place of the game's own",
  the three archives opened from there, the title screen, then Continue
  into the hub (native code, Turnip). No new errors in the log. (That
  save has Voice Language set to Japanese from the voice-pack test, so
  its lines come from the pack's `voice_jp.pk`, not the undub.)
* **Heard** (the owner, 2026-11-21): a test folder from that day's build
  (`make-dist.py`, `vita_fs` the scratch release's file system with the
  undub and the voice pack, volume 100). The log: "rePatch: 9 files ...
  read in place of the game's own", the three archives from
  `ux0/rePatch`. New Game: the prologue's lines are in Japanese.
* Not checked: the prologue to its end and the Final Fantasy bosses in the EU game with the US-made
  `archive_patch3`, a full build with the mod among the parts (the same
  `--install-content` step), the setup window, and RecompLauncher.

## Owner playtest: the voice pack and the ending (2026-11-21)

A test folder from that day's build (`make-dist.py`, `vita_fs` the scratch
release's file system with the pack installed, `[game] repatch = false`,
volume 100), US game, native code, the Radeon 760M. The story-complete
Apollo save imported into slot 2 (`--import-save ... --slot 2`).

* **Voice pack:** with Voice Language set to Japanese, the owner heard
  the lines in Japanese. The log: "rePatch: mods off", `voice_jp.pk`
  opened from `addcont0:`.
* **The ending:** Fight Magusar, then `ev00_ending.mp4`; in the battle
  the owner turned on one-hit kills, unlimited offerings and infinite
  health on the Cheats page and killed Magusar. `ev01_ending.mp4` played,
  the trophy "The Wheel of Fate" ("... fought Magusar, and saw ending")
  unlocked, and the game went back to Librom's menu. The ending played
  correctly (the owner). No errors in the log. Whether the game has
  other endings, and the movies they would play, is not checked.

## Cheats (2026-11-21, GitHub issue #7)

`[cheats]` in `ss-delta.ini`, the settings menu's Cheats page (fork:
`games/ss-delta/main.cpp`, `apply_cheats`; addresses in 01-research,
"Cheats"). Test folder with a junction file system, US game, native code,
the Radeon 760M.

* **Quests** (Stage Select, `q_e0101` in ST03A): with the cheats off,
  `memwrite` set HP to 300.0 and slot 0's uses to 3; the health bar showed
  30%, and both stayed. On the Cheats page, Infinite health and Unlimited
  offerings switched on (the log: "Settings menu: [cheats] ... = true",
  then "cheats: infinite health" and "cheats: unlimited offering uses"):
  HP back to 1000.0, slot 0 back to 15. Two casts with the cheat on left
  the uses at their start; HP written to 300.0 again was 1000.0 half a
  second later. The 9999 slot (no limit) is left alone.
* **Save** (slot 2 of a copy of the story-complete save): Portraiture
  showed Lacrima 9627 and levels 1 / 99, as in memory. Max Lacrima and Max
  levels switched on in the menu: 9999999 and 99 / 99 on Portraiture.
  Saved in the hub ("Save complete", `SlotParam_2.bin`: "Life Lv99 Magic
  Lv99"), restarted with every cheat off, loaded: both still set. The
  test folder's slot 2 was copied back from the original afterwards.
* `v3kdrive.py` step `memwrite:<addr>:<bytes>` (kit) and the input pipe's
  `memwrite` command (fork, `ctrl.cpp`, written by the front end) are new
  for these tests.
* **Real fights** (Stage Select, `q_e0103` ST01A and `q_e0105` ST06A):
  goblins and the Harpy hit the player, HP stayed 1000.0 in every read
  and the log said "cheats: infinite health". One-hit kills (fork
  `dac57802`), switched on in the menu: goblins 110 → 0 on single punches
  (without it, six punches left one at 3); the Harpy 1700 → 1360 → 1020 →
  680 → 647 → 307 → 0 (340 a strong hit, a fifth of its health), then its
  dying scene as usual.
* **EU game** (the EU scratch folder, its early save): Lacrima 50 → 9999999
  in memory; levels 0 / 0 there. The first build wanted levels 1-99 and
  therefore left the whole save alone (fork `97bd8574` takes 0, and Max
  levels waits). Quest cheats: the same addresses (one build).
* **Max levels on early saves**: the Thor's test save (Life 1, Magic 3)
  imported into the PC test folder as slot 3: its levels are at
  `+0x139fa8`, `+0x17ced8` holds zeros (01-research, "Cheats"). The cheat
  logs once that it leaves them alone. The test folder's saves were put
  back from the import's backup afterwards.
* **Android** (the Thor, the `ssdeltatools` test package, debug APKs of
  `97bd8574` and `dac57802` built in WSL and packed with Gradle): the
  Cheats page's values from the settings file; Portraiture showed Lacrima
  9999999 after loading the save; in `q_e0105` the log said one-hit kills,
  infinite health after a goblin's hit, unlimited offering uses after a
  cast; goblins fell, HP bar full. The test package's settings and
  `BootSequence` were set back afterwards.
* **Ad Hoc Play** (players 3 and 4 in the test folder, `network = local`;
  player 3 hosting with no cheats, player 4 with health, offerings and
  one-hit kills from `ss-delta-player4.ini`): room, ready, "Croaking
  Fiends in the Forest". On each copy `+0x18` is its own player: the
  host's at 524/1000, the guest's held at 1000, and the host's copy of
  the guest at 1000 too. Player 4's log names only its own player. The
  guest's single hits took two goblins 120 → 0, and the same goblins were
  at 0 on the host.
* **Offerings** (fork `2a29069a`, Stage Select `q_e0105`, Giant's Arm in
  slot 1):
  * No cheats: 5 → 4 per cast; the arm left after about 70 s each time;
    at 0 one more cast, "Giant's Arm was lost.", slot -1.
  * Unlimited offerings refills the casts only; the arm still left after
    70 s with it on. With slot 1 lost (-1), switching it on gave the slot
    its 5 uses back; the empty slots stayed -1.
  * Lasting offerings, on from boot: "duration tables: arms at 0x82acf654,
    offerings at 0x8277e950", 126 of 126 arms and 503 of 1015 offering
    records set to 9999 s. Cast in a new quest: the arm still out at 30,
    60 and 90 s. Switched on in the menu during a quest, then cast: still
    out after 85 s.
  * One run stopped with a Vulkan device loss about 40 s after a cast
    (`waitForFences`); the owner had started another program that took
    the GPU. The rerun went through.
* **Lasting offerings, every kind** (fork `3fe4016e`; test folder, slot 2,
  the story-complete save; the created pact "Hell Minion in Splendor"
  with the stone shell, stone charm, shield shard, large falcon feather
  and fire golem heart written into the loadout in memory, not saved):
  * Without the cheat: the golem left before 30 s.
  * The first version (arms and offerings tables only): the golem left
    before 40 s, the stone armour and the rock wall before 70 s. Their
    durations are in other tables (01-research, "Cheats").
  * With all four tables: stone armour still on at 100 s (normally 50),
    rock wall up at 90 s (30), rolling boulder at 45 s (15), golem at 75 s
    (30). The feather (a type-16 buff, its "80" as text) first still got
    80 s; after the text fix its timer started at 9999 (9882 after
    2 minutes).
  * Switched off in the menu: "offering durations back as the game has
    them (943)", and the feather's next cast got 80 s again.
  * A first check of the protector table compared its anchor's duration,
    which the cheat itself changes, so a minute later the log said the
    armour table was missing; fixed before commit.
* **EU game** (`dist/scratch-eu-jpvoice`, Stage Select `q_e0105`): all four
  tables found at other addresses, 37 buffs; Giant's Arm still out at
  90 s.
* **Android** (the Thor, `ssdeltatools`, debug APK of `3fe4016e`): the same
  log lines (tables at the EU-like addresses); Giant's Arm still out at
  90 s in `q_e0105`.
* **Ad Hoc Play, PC and Android** (2026-11-21): the test folder's player 3
  (`network = lan`, `adapter = 1`, the PC's Wi-Fi) and the Thor, both with
  slot 2 (copied to the Thor's test package for the test, removed after;
  its own saves checked by MD5). The PC created the room; the Thor's
  Search for Room listed "Gamora [1/4]" and joined; both showed the same
  lobby (host flag on the PC's sorcerer). Both readied, the host started
  "Croaking Fiends in the Forest", and both entered the quest together,
  each showing the other's sorcerer and name. The beasts brought the
  idle PC host down; the Thor showed "Gamora is dying" and the
  save/sacrifice choice for the ally. On the Thor, the Cheats page (Select
  held) switched on Infinite health and One-hit kills; its sorcerer kept
  full health beside the fallen host. A kill from the Thor wasn't reached
  (steering its melee blind over adb); one-hit kills from a guest were
  checked between two PCs above.
* Not checked: a hit that takes all the health at once (the cheat refills
  once a frame and leaves a player at 0 alone), the battle stats at
  level 99, a quest played to its end in Ad Hoc Play with cheats, and
  cheats on the host. For Lasting offerings: buffs, armour and summons
  (only an arm was tested; the debug Stage Select gives one loadout),
  switching it off (the durations go back for the next cast), and
  Android and the EU game.
* **Invincible** (2026-11-26, for scripted playtests that enemies knocked
  off course; the debug menu's NoDamage, 01-research "Cheats"). Test
  folder, US game, native code, Stage Select, the Radeon 760M; frames
  with `record`, HP read every 1-2 s.
  * `q_e0103` (ST01A), every cheat off, Circle pressed once a second
    near goblins: HP 940 → 511 in 12 s (hits of about 96, and 5 a C
    press); the sorcerer was thrown to the ground. NoDamage written with
    `memwrite`: HP stayed at 319 through 12 s of the same and 15 s
    standing among attacking goblins (their claw trails on him), no
    stagger; cleared again: 319 → 163 in 12 s.
  * `q_e0105` (ST06A), the Harpy's minions on top of him: set, 15 s
    standing, HP 1000, never moved; cleared, knocked down twice in 10 s
    (1000 → 808).
  * The cheat (fork build, `invincible = true` in the test ini): "cheats:
    invincible (0x820161b0)" a moment into the boot; goblins' hits passed
    (HP 1000 through 12 s). Switched off on the Cheats page: the log said
    "Settings menu: [cheats] invincible = false" and "cheats: invincible
    off", the byte was 0 and hits counted again (899 → 571). The Harpy,
    with the cheat on, 30 s standing under its stomps, dives and gusts:
    HP 1000, no knock-down; it braced (crouched, arm over its face) for
    a moment at each shockwave or gust and stood again by itself.
  * `v3kdrive.py <dir> start --set cheats.invincible=true` (kit: start
    passes its arguments on): the flag set from the title screen, the
    ini unchanged.
  * **Ad Hoc Play, PC** (players 3 and 4 in the test folder,
    `network = local`, both with slot 2; `--set` for the cheats, so the
    shared ini stayed as it was): room, ready, "Croaking Fiends in the
    Forest". Player 4 (guest) started with `--set cheats.invincible=true`:
    over 20 s standing among the beasts its HP stayed 1000 on its copy,
    and on player 3's screen its sorcerer stood untouched; player 3 (host,
    no cheat) went 384 → 0 and was "dying" on both screens. Player 4 saved
    it ("F. Cleric III Gained"). Then the other way round, switched on the
    Cheats page of each copy: host on, guest off. The host held 500 and
    never moved, and the guest went 430 → 0. Each copy's NoDamage
    (`memdump`) was what its menu said. So the switch covers only the
    copy's own sorcerer, host or guest.
  * **EU game on Android, with the PC** (the Thor, `ssdelta.t25`: the EU
    game, a debug APK of fork `52a2980d` with t25's own versionCode and
    build tools, so its build stamp held and nothing was rebuilt; the
    test folder's slot 2 imported with `--import-save`, removed after):
    the EU game's Search for Room listed the US PC host's "Gamora [1/4]"
    (player 3, `network = lan`, `adapter = 1`), joined, and both entered
    the quest. On the Thor's Cheats page Invincible was there with its
    text; on, its sorcerer stood through 30 s of the beasts' swipes, no
    stagger and no health ring, while the PC host went down.
    `--set cheats.invincible=true` through GameActivity's `args` turns it
    on for the run there too (Cheats page: On, ini without the key). A
    change on the Cheats page is written to the ini (`invincible = true`
    appeared; taken out after).
  * Not checked: allies, grabs, status ailments.

## Mouse camera (2026-11-21)

`[mouse]` in `ss-delta.ini`, the settings menu's Mouse page (PC only;
fork `game-frontend/input.cpp` `MouseCamera`, `frontend.cpp`; the stick
table in 01-research, "Mouse camera"). Test folder with a junction file
system, US game, native code, Stage Select's first quest, the Radeon 760M.
The motion came through the input pipe's new `mouse <dx> <dy>` command
(`v3kdrive.py` step `mouse:<dx>:<dy>[:ms]`, kit), which the front end
takes as captured mouse motion, in 10 ms pieces; the turn was read from
the compass. At sensitivity 1 a count asks for 0.05°.

* **Steady motion** (counts per second → asked → measured, both
  directions): 100 → 5 → 4.9-5.0°/s; 400 → 20 → 15-20; 1000 → 50 →
  46-53; 2000 → 100 → 91-105; 4000 → 200 → 188-218.
* **Whole motions** (counts over ms → asked → turned): 1000/500 → 50° →
  47-49; 2000/1000 → 100° → 100-105; 200/200 → 10° → 9.4-10.6; 100/2000
  → 5° → 4.3; 40/100 → 2° → 1.0-1.6; 3000/300 → 150° → 117 (faster than
  the game can turn: what waits longer than 0.25 s is dropped).
* **Diagonal** (1000, 1000 over 500 ms): yaw 51-52°, as without the
  vertical part.
* **Before the fixes:** a linear stick (motion speed = push) and a v⁸
  model turned 75-89% of the motion; without the byte rounding, right
  turns came out 15% short of left ones (44° against 49°); inside Vita3K's
  unit circle a diagonal flick turned at 0.71 push, a few degrees a second.
* **Settings menu:** the Mouse page lists Mouse camera, Capture key
  (shown, not editable), Sensitivity and Invert vertical; Sensitivity
  1 → 1.1 → 1 was saved to the ini and logged.
* **Not tested here** (the test driver never takes focus): the real
  cursor capture (SDL's relative mouse mode, Tab and middle click, Esc,
  release for the menu and a text dialog, alt-tab and back) and how it
  feels with a real mouse. The owner played it with a mouse the same day:
  it works.
* **Idle cursor** (2026-11-24, GitHub issue #16, fork `c4ba2112`):
  `[mouse] hide_cursor` (on by default, Hide idle cursor on the Mouse
  page) hides the cursor after 3 s without mouse motion while the window
  has the focus, and at once on a key, gamepad button or stick (past a
  quarter); motion, a click or the wheel show it again. The test folder
  booted to the title screen with no new log errors; the owner checked
  the hiding itself: the cursor goes after 3 seconds.

## Laptops with two GPUs: AMD's "LoadLibrary failed with error 87" (2026-11-19, GitHub issue #4)

Reported on a Ryzen 7 7840HS (Radeon 780M) + RTX 4070 Laptop GPU with
v0.3.0: the importer stopped while it ran the game unseen to dump the
modules (`install-game.py` step 3), with the AMD driver's message box
"LoadLibrary failed with error 87: The parameter is incorrect". The log
ended right after `Present mode: Mailbox`, with Vulkan already on the RTX
4070. The message isn't ours: AMD's OpenGL driver shows it on AMD iGPU +
NVIDIA laptops.

* Cause on our side: `ss-delta.exe` had no exports at all.
  `NvOptimusEnablement` and `AmdPowerXpressRequestHighPerformance`
  (`vita3k/performance.cpp`) were in the `game-frontend` static library,
  and the linker drops an object nothing references (`Vita3K.exe`, which
  compiles the file itself, had both). Fork `8b815f2f` compiles it into
  each game's executable; both names are now in the export tables of
  `ss-delta.exe` and `shinobido2.exe`. Boot on the Radeon 760M unchanged
  (title screen, recompiled modules native).
* Workaround, confirmed by the reporter: Windows Settings → Display →
  Graphics, `ss-delta.exe` set to High performance; setup then finished
  and the game runs.
* Not checked: the fixed build on such a laptop without the setting.
  **Hypothesis:** the export has the same effect as the setting, so builds
  from `8b815f2f` on need no workaround.

## Squares in smoke and fire (2026-11-24, GitHub issue #17, fixed)

Reported on 0.5.0 at 1366×768: square blocks in the hub's fire-pit smoke
"and almost everything that has smoke". Up close they are 8×8-pixel blocks
on a grid inside the smoke, each holding stale image data from elsewhere.
The reporter's GPU and log were asked for; no answer yet.

* **Hypothesis:** a GPU with neither shader interlock nor raster-order
  attachment access. The renderer then reads the framebuffer for the
  smoke's programmable blending through non-coherent subpass input, which
  orders draws but not the overlapping particles within one draw: the
  failure Qualcomm's Android driver showed in ST03A's fog (09-android).
  Every machine tested so far has interlock (Radeon 760M, RTX 4090, the
  Deck's RADV, MoltenVK on the M5). **Hypothesis** (owner): an older
  Intel iGPU, which was never tested.
* `VITA3K_NO_ORDERED_FB_READS=1` (fork) leaves both features unused, to
  run that path on any GPU; the log says so and its `Framebuffer reads:`
  line reads "no, no". Shader translation changes with it: move the
  title's shader cache aside for such a run.
* On the Radeon 760M with it (save 2, the hub, the fire pit, 40 frames
  recorded): the smoke stays smooth, no squares. An immediate-mode GPU
  seems to keep the reads in order in practice, so the path's fault
  doesn't show here; this neither confirms nor rules out the hypothesis.
* **Intel iGPUs have interlock on Windows** (vulkan.gpuinfo.org, the
  `VK_EXT_fragment_shader_interlock` coverage list for Windows, read by
  the owner): every Intel iGPU from Skylake on, from its first driver
  with Vulkan (HD 520/620/630 and UHD 620/630 since 100.71xx in 2019,
  Iris Xe since 2020; Arc). Older ones have no Vulkan on Windows. So an
  older Intel laptop doesn't lack the feature; the list doesn't show
  whether the driver enables `fragmentShaderSampleInterlock`, which the
  fork requires (its shaders use `SampleInterlockOrderedEXT`).
* **`[debug] high_accuracy = false`** (the settings menu's Debug page,
  "Off is faster but can flicker") takes the same non-coherent path on
  any GPU, and texture viewport as well. On the Radeon 760M at the fire
  pit, 40 frames: smooth smoke, no squares.
* Left (**hypotheses**): on the reporter's GPU either that path shows what
  the 760M hides (with `high_accuracy` off, or without sample interlock),
  or the driver's interlock itself doesn't order the reads. Their log
  (`Framebuffer reads:`, "Using shader interlock") and `ss-delta.ini`
  tell which.
* **Confirmed (the reporter's log and ini, 2026-11-24):** `Vulkan device:
  AMD Radeon R5 Graphics`, driver 2.0.179, the integrated GPU of an AMD
  A10-9600P (Bristol Ridge, 2016; the laptop also has a Radeon R7 M340,
  not the one the game used), Adrenalin 21.9; `Framebuffer reads:
  raster-order attachment access no, shader interlock no`, with
  `high_accuracy = true`. So the squares are the non-coherent path on a
  GPU that has neither feature, as on Qualcomm's driver; the Radeon 760M
  (RDNA 3) doesn't show the path's fault, this GCN APU does. Whether the
  R7 M340 on the same driver has interlock is not known.

### The fix: reads from a copy (2026-11-24; fork 763971ac, 6655bc93)

Reproduced on the AYN Thor with Qualcomm's own driver (Adreno 740, 512.676.53:
no interlock, no raster-order access), the title screen's green smoke, a test
package of the APK (`io.github.vitarecomps.ssdelta.kittest`) with a copy of the
game files:

* Five draws on the title read the framebuffer: the smoke particles (fragment
  shader `6ee9a18da1766bc9`, 72 quads in one draw: texture x vertex colour,
  added to the old pixel with its alpha) give the 8x8 blocks; four triangle
  strips (`e1e0003f…`, `c3ca22e8…`, `61f0d854…`, `e89cc4b3…`) give strips of
  stale pixels. Skipping all five (`VITA3K_SKIP_FRAGMENT_SHADERS`) removes
  both, and the smoke.
* Not fixed by: the draw split into parts of 2 or 1 triangles with the
  subpass barrier between them; a new render pass before each reading draw;
  a new render pass between each 2 triangles; storage usage on the colour
  surfaces; the render pass's external dependency extended to input
  attachment reads in the fragment shader; all of these together. So on that
  driver a subpass input of the attachment being drawn reads stale data
  whatever the ordering.
* **Fixed by reading a copy** (`FeatureState::fetch_from_copy`): before each
  draw that reads the framebuffer the render pass ends, the colour surface
  (its scissor) is copied into an image of the attachment view's format, and
  the fragment shader fetches its own pixel from that (set 1 binding 0, a
  sampled image; shader cache version 24). No blocks in any frame; 60.0 fps,
  p95 18 ms on the Thor, as on Turnip.
* What the copy changes: particles that overlap within one draw each blend
  with the picture as it was before the draw, so smoke is thinner than on
  Turnip (raster-order access, the reference) and an overlap can show a
  straight edge. A copy before each particle matches Turnip but costs p95
  131 ms; up to 8 or 16 parts per draw (`VITA3K_FB_FETCH_PARTS`) still leave
  edges, and 16 parts drop to 37 fps.
* On the Radeon 760M with the path forced (`VITA3K_NO_ORDERED_FB_READS`) at
  2x, the title runs at 46-49 fps with copies (60 without): the cost is the
  render-pass restarts, not the copy's size (the whole surface or the
  scissor, the same).
* `[debug] framebuffer_reads` (auto, subpass, subpass_storage, copy): on a GPU
  without either feature, auto is the copy. subpass_storage keeps the subpass
  input but gives the colour surfaces storage usage, which keeps AMD's colour
  compression (DCC) off them. **Hypothesis**: the R5's blocks lie on DCC's
  8x8 grid for 32-bit pixels, so on GCN that alone may fix them, with the
  overlaps right (the 760M's subpass path draws them right). It doesn't help
  on the Adreno. The reporter's test decides `auto` for AMD.
* The log now lists every Vulkan device (`Vulkan devices: N ...`) and
  `[debug] gpu` picks one by that number: the reporter's R7 M340 was never
  offered to the game (only the R5 was chosen, with the high-performance
  exports in the exe).

### The reporter's test of the copy (2026-11-24)

The test build (release workflow, Windows only, `ss-delta-67d51ad`) on the
R5: `framebuffer_reads = copy` (auto) removes the squares, but the smoke
flickers and parts of it are missing below the logo; `subpass_storage` is
slow and flickers. So DCC wasn't the whole story on GCN, and the copy's
thin, edged overlaps show on that card as flicker.

### The fix: the blend by the fixed-function blender (2026-11-24, fork, see below)

Every program that reads the framebuffer on the title and at the hub ends
the same way: `PHAS`, then one `SOP2` that blends the program's colour with
the old pixel (`o0`) into `o0`: `result = op(f1 * src1, f2 * src2)`, factors
zero, a colour, an alpha or their complements, op add or subtract. That is a
Vulkan blend state. The fork now finds such programs and blends them with the
fixed-function blender, without reading the framebuffer:

* `shader::find_shader_blend` translates the program once in a scan mode:
  it counts the SOP2s and the reads and writes of the output bank outside the
  final blend. A program qualifies if it has exactly one SOP2, that SOP2 has
  the blend form (no predicate, no repeat or modifiers, `o0` as destination
  and as one source, the other source not an output register), and the output
  bank isn't touched elsewhere. The old pixel may be either source (one shader
  on the title, `38a75dfe…`, computes `old - colour.a * colour`, i.e. Vulkan's
  reverse subtract).
* Its translation for the pipeline then reads no framebuffer and the SOP2
  just writes the colour; the blend state goes into the fragment program
  (`ShaderBlend` → `VkPipelineColorBlendAttachmentState`). The translation is
  cached under the program's hash with its last byte changed (`^ 0xB1`), so it
  doesn't clash with the reading translation of the same program.
* On by default (`FeatureState::native_shader_blend`) only on a GPU with
  neither interlock nor raster-order access, where reading is the problem.
  `[debug] shader_blend` (auto, on, off; `VITA3K_SHADER_BLEND=1/0`) forces it;
  `VITA3K_SHADER_BLEND_ONLY=<hash prefixes>` limits it to some programs
  (debugging). The log says `Fragment programs that read the framebuffer only
  to blend: blended by the fixed-function blender`, then one line per program,
  and `Framebuffer read from a copy by fragment program …` once for each
  program still read through the copy.
* 96 programs qualify; the game creates all its fragment programs at boot.
  On the title, the menus, the hub and five quest maps (ST03A, ST02A, ST06A,
  ST09A, ST10A, through Stage Select) no program is read through the copy any
  more (the log's per-program line), and the quests' smoke and mist look
  right. A program that used the old pixel for anything else would keep the
  copy.
* Checked against the reference, 60 frames over 10 s of the title (the smoke
  changes a lot between frames, so 40 consecutive frames gave differences of
  5-8 that were only the animation's phase): Radeon 760M at 2x, interlock
  (reference) 64.5/74.6/63.1 mean RGB in the smoke region, the default path
  of a card with neither feature (copy + native blend, forced with
  `VITA3K_NO_ORDERED_FB_READS`) 65.8/75.4/63.6, the copy alone 63.7/71.2/62.9
  (thinner smoke, as above). At 1x the same. The fire pit and the menus look
  like the reference; no squares, no edges.
* AYN Thor, title: Turnip (raster-order access, the reference) 68.7/72.5/61.0,
  with native blend forced 68.7/72.8/60.9; at 2x 75.7/79.9/64.4 and
  75.0/79.1/63.4. Qualcomm's driver (neither feature): copy 67.9/69.5/62.0,
  copy + native blend (the default now) 69.4/73.5/62.1.
* Native blend mixed with interlock (forced on the 760M) darkens the smoke:
  pipelines that blend into the attachment and pipelines that read and write
  it under interlock aren't ordered against each other. That's why it stays
  off on GPUs with interlock. **Hypothesis**: the same reason as storage-image
  writes against attachment writes; not investigated, as nothing needs it.
* **Confirmed on the reporter's laptop (2026-11-24, test build
  `ss-delta-3d9b353`):** "it works perfectly now". Their log: Radeon R5,
  driver 2.0.179, neither feature, the notice line, all 96 programs
  converted and none read through the copy.

## LAN play stuck at "Connecting..." (2026-11-25, GitHub issue #21, open)

Two Windows PCs on 0.5.0 (`network = lan` on both): the guest finds the
host's room and readies up but stays at "Connecting..."; the host never sees
the guest. Both logs reach Ad Hoc Play normally (SceNetAdhocMatching loaded,
its retransmit interval raised, no socket errors before the players leave).
They don't say which adapter or address either copy used.

* What reaches whom: the room is announced by the host's broadcast, which
  the guest received; the guest's answers go to the host's address (unicast)
  and never arrive. **Hypothesis**: something on the host blocks inbound
  traffic to `ss-delta.exe` (Windows Firewall with the network set to Public
  and the app allowed only on Private, or another security program). A wrong
  adapter on the guest wouldn't stop its unicast reaching the host (the
  socket is bound to any address and routed by destination); a wrong one on
  the host would stop its broadcast, which arrived. Asked the reporter to
  check the firewall on both PCs and the adapter (2026-11-25).
* The adapter setting (`[multiplayer] adapter`) defaults to the first of the
  PC's adapters with an address, in `GetAdaptersInfo`'s order. On the owner's
  PC that is Hyper-V's virtual adapter, before the Wi-Fi (the 2026-11-17
  cross-platform test needed `adapter = 1`).
* Diagnostics (fork `cb51b507`): `init_address` logs the mode and, for LAN,
  the adapter's index, address, mask, name and broadcast address, and lists
  every adapter with its index (`Ad Hoc Play: network adapter 0 of 2 ...`),
  once for each change. `[debug] net_trace` sets `VITA3K_NET_TRACE=1`
  (P2PSocket logs each packet sent and received, with the host address and
  port); the log says so at the start. Checked in the test folder: LAN mode
  lists the PC's two adapters (Hyper-V first, the Wi-Fi second), local mode
  logs `copies on this PC (network = local), this one 127.0.0.1`.

## Ad Hoc Play across networks (2026-11-25)

LAN play found the others only by UDP broadcasts on the chosen adapter's
subnet, which Tailscale and other VPNs, and routers between subnets, don't
pass. Every broadcast goes through `P2PSocket::send_packet` (Vita3K's peer
beacon from the ad hoc thread, once a second, and SceNetAdhocMatching's
hellos; `sceNetSendto` turns 255.255.255.255 into the adapter's broadcast
address); `local` mode already sent one datagram to each copy instead, and
rooms, joining and quests work that way.

* `[multiplayer] peers` (fork): addresses or host names (resolved once at
  start, IPv4; Tailscale's MagicDNS names work). In `lan` mode each
  broadcast goes out as before and also as a datagram to each peer.
* **Learned peers**: every address a P2P packet came from (not this
  machine's own) joins the list for this session, up to 16, logged once
  (`Ad Hoc Play: a packet from ..., which now also gets this copy's
  broadcasts`). So one side knowing the other is enough: the others list
  the host, whose own beacons and hellos then reach them.
* The ad hoc thread's peer list (`sceNetCtlAdhocGetPeerList`) keeps the
  address a peer's packets come from, not the one the peer reports for
  itself (that is its chosen adapter's, possibly a wrong or unreachable
  one, #21).
* An adapter whose broadcast address is its own address (a /32, as
  Tailscale's can be) sends no broadcast, only the peers'.
* `VITA3K_ADHOC_NO_BROADCAST=1` (testing) sends only to the peers.
* **Checked, the PC (Windows, Wi-Fi, test folder's player 3, slot 2) and the
  Thor (test package, slot 2), both with `VITA3K_ADHOC_NO_BROADCAST=1`:**
  (1) the PC lists the Thor, the Thor nothing: the PC created a room, the
  Thor's Search for Room listed "Gamora [1/4]", joined, both readied, the
  host started "Croaking Fiends in the Forest", and both were in the quest
  together; the Thor learned the PC from its packets. (2) The PC lists
  nobody, the Thor the PC: the PC learned the Thor from its beacon, the
  Thor listed the room and joined; both lobbies showed both players.
  (3) Plain `lan` with broadcasts and no peers (each beacon then arrives
  twice, as broadcast and to the learned address): lobby, ready, start
  and the quest as before.
* Not tried over a real Tailscale or routed network (none here):
  **hypothesis** that it behaves as (1) and (2) there, with `adapter` set
  to that network's adapter so the address the game reports is reachable.

### Peers from the settings menu, adapter auto (2026-11-25)

* **Text in the settings menu** (fork `game-frontend/settings_menu.cpp`):
  a `Text` setting with `text_entry` (only `[multiplayer] peers` so far) is
  edited in the menu. Cross starts editing; typed text arrives as SDL text
  input (the front end turns it on while a row is edited, and sends the
  keyboard to the menu instead of the game; Android shows its on-screen
  keyboard), and a gamepad edits it too: Up/Down change the character under
  the cursor through the setting's `text_chars`, Left/Right move the cursor,
  Square deletes, Cross/Enter keep it, Circle/Esc drop it. The edited text
  shows with the cursor's character in brackets.
* The front end's per-frame IME check (for the game's own keyboard dialogs)
  had turned SDL's text input off again each frame; it now keeps it on
  while a menu row is edited.
* `peers` is applied at once (`net_utils::set_lan_peers_text`, also used at
  start), and saved to the player's settings file (`ss-delta-player<N>.ini`
  for player N).
* **`[multiplayer] adapter = auto`** (the new default; Vita3K's
  `adhoc_addr` -1): the adapter whose address the routing table sends from
  to reach the first peer (a connected UDP socket's local address; nothing
  is sent), or without peers to `8.8.8.8` (the default route's); picked again
  each time Ad Hoc Play starts. On the PC it takes the Wi-Fi (adapter 1), not
  Hyper-V's adapter 0 (`Ad Hoc Play: network adapter auto (1) of 2`).
* Checked: on the PC (test folder, player 3), Multiplayer page, Peers edited
  with the gamepad to `10.0.0.5`; the log showed the change and `Ad Hoc
  Play: peers 10.0.0.5`, and `ss-delta-player3.ini` got it. Typed text could
  not be checked there: SDL delivers it only to the window with the keyboard
  focus, which v3kdrive doesn't take. On the Thor: Select held for the menu,
  Cross on Peers showed Android's keyboard, `100.64.0.7` typed on it (taps
  on its keys; `adb shell input text` sends key events, not text, and
  arrives as nothing), its Enter key kept it, the keyboard closed and
  `ss-delta.ini` got it.
* Player guide: [ONLINE-PLAY.md](ONLINE-PLAY.md) (Tailscale, ZeroTier, Radmin VPN).

## The settings menu's pause (2026-11-26, GitHub issue #29, fixed)

Reported by ELLINDON from their Android build (Moto g54, Mi Pad 5): opening
the settings menu stopped the sound, but the game went on behind it.

* **Cause.** `KernelState::pause_threads` suspended each running thread
  with `stop()`, and `NativeCPU::stop()` is empty: native code isn't
  preemptible, so recompiled threads never stopped. On the JIT the same
  snapshot missed threads that woke from a wait after the pause. On every
  platform, not only Android.
* **Fix** (fork `7ca38db9`, ELLINDON's PR vita-recomps/Vita3K#1, merged
  as `5e241028` with three commits of ours): a session gate
  (`util/cooperative_pause.h`) that guest threads wait at before and
  after each import, before each LLE call, and before each entry into
  `run()` (both CPUs, and the JIT's nested loop). Exits and deletes
  release it; shutdown resumes it before joining. `be53a38c`: the import
  handler only waits; throwing `AotUnwind` there skipped
  `aot_call_import`'s restore of `halted`, so an exit after a callback
  could take r0 as the thread's exit status. `92aba4ad`: during Ad Hoc
  Play the threads keep running (below).
* **Checked** (test folder, Windows, Radeon 760M; two frames 3 s apart
  with the menu open, `frame:`):
  * Before (fork `1955f5fc`), in a quest: the frames differ, an enemy
    knocked the player down behind the menu. After: frames and a 128 KB
    memdump of the eboot's data identical; closed, the game runs at
    59–60 fps; 20 quick open/close cycles while walking fine; `close`
    with the menu open exits in 1 s.
  * `[recompiled] jit = true` and the JIT alone (`enabled = false`): the
    same.
  * A loading screen ("Now Loading", three more cycles during the load,
    the quest then playable), the opening movie (its text and mid-FMV),
    the menu over a save dialog (it answered afterwards): frozen, then
    continued.
  * The PR's host test (`vita3k/util/tests`) passes with MSVC.
* **Ad Hoc Play.** Players 3 and 4 in one lobby: player 4's menu open for
  30 s, and player 3 (the host) had dropped it between 20 and 30 s; player
  4, resumed, was alone ("You are now the host"). `adhoc_matching` and the
  game's traffic are guest threads. While `netctl.adhocState` isn't
  disconnected, a pause now stops audio, input and the picture only, as
  before. Then the guest's menu, and after it the host's, stayed open
  about 37 s each and the room held.
* **AYN Thor** (test package `kittest`, Qualcomm's driver, Select held for
  the menu, `screencap` 3 s apart): title frozen with the menu open, the
  process's CPU 155% → 42%; 10 quick cycles fine; Home and back, the same
  process, running.
* **Seen meanwhile:** the game didn't pause when the Android app went to
  the background (CPU 155% → 255%); the games' front end never set the
  background pause reason. Next section.

## Android: the pause in the background (2026-11-26, fixed)

* **Cause.** Upstream's Android app sets the session's `Background` pause
  reason from Java (`android/jni/native_session.cpp`); the games' front end
  doesn't build that and never set it. SDL blocks the front end's event
  loop while the app is paused, but the guest threads went on, with no
  surface to draw on.
* **Fix** (fork `41475130`): the SDL event watch that already flushed the
  log (`game-frontend/android.cpp`) sets `Background` on
  `SDL_EVENT_WILL_ENTER_BACKGROUND` and clears it on
  `SDL_EVENT_DID_ENTER_FOREGROUND`, through the session the front end
  hands it for the time `run()` lasts. The Ad Hoc rule of the menu's pause
  applies (`AppSessionController::apply_runtime_state_locked`).
* **Checked** on the Thor (`kittest`, title screen, `top` on the process):
  in front 153%, in the background **11%** (16% after 30 s; 240% before),
  back in front 151% with the same process, the title animating; the log
  says "Android: the app left the screen" and "is back on the screen".
  The menu still freezes the title. With the menu open, Home and back: the
  title stays frozen until the menu closes, then runs.

## FPS counter and Android's firmware from the player's files (2026-11-26)

Two of #29's offers, written here rather than ported from the contributor's
build (their counter was a game-specific setting; their firmware import a
separate offline mode needing both files).

* **FPS counter** (fork `fbb38768`): `[display] fps_counter` = `off`,
  `fps`, `frametime`, `stats`, `graph`, mapped onto Vita3K's performance
  overlay (`cfg.performance_overlay`, its detail level, top left), which
  the renderer already draws from `app.cpp`'s once-a-second figures; live
  through `app::sync_perf_overlay_config`. Checked on Windows (test
  folder): on from the menu (Display page, saved to the ini), `graph` from
  the ini (FPS, ms, min/avg/max, RAM, the graph); the title screen at
  32.4 fps with it off and with `graph`. On the Thor (`kittest`, `stats`):
  60 fps (17 ms), min 56, max 61, readable at the screen's size.
* **Firmware files on Android** (fork `0f6a57eb`): the setup screen's Add
  firmware files (`EXTRA_ALLOW_MULTIPLE`) reads each file through the
  picker's grant, hashing it as it copies it into
  `setup-work/firmware/picked.part`; size and SHA-256 equal to one of
  fetch-firmware.py's pins → renamed to that PUP's name. The firmware step
  (`android-setup.py firmware`, unchanged) keeps a file that is there with
  the right size and hash. Checked on the Thor (a fresh test package):
  `firmware-a.bin` and `fonts-b.bin` (the two PUPs) taken as PSVUPDAT.PUP
  and PSP2UPDAT.PUP, a 56,768,512-byte file of zeros named `fake.PUP`
  refused by its hash; with a dummy game file, Build: the firmware step
  printed the two paths and downloaded nothing, Installing the firmware
  exit 0, the dummy's install failed as it should. Files pushed with adb
  show in the picker only after `content call --method scan_volume`.

## A pkg's licence for other content (2026-11-26, GitHub issue #25)

Fork `52a2980d` (`game-frontend/frontend.cpp` `pkg_zrif`,
`packages` `pkg_content_id`): a licence file is compared with the
package's content ID before anything is unpacked. Checked on the PC with
Shinobido 2's pkgs when it was written (the commit message). On the Thor
(`ssdelta.t25`, the EU game, the debug APK from the Invincible tests):

* The EU Japanese Voice-over Pack (`EP9000-PCSF00532_00-SSS000CVN0000001`,
  919 MB) with the US pack's licence
  (`UP9000-PCSA00152_00-SSS000CVN0000001`), through GameActivity's `args`
  (`--install-content <pkg> --license <rif>`, the step "Add an add-on"
  runs): refused 9 ms after "Installing", nothing unpacked (no
  `ux0/addcont`). The log says the licence "is for UP9000-..., not for
  ... (EP9000-...): it can't decrypt it", then that the pkg "needs the
  licence (work.bin or .rif) for EP9000-PCSF00532_00-SSS000CVN0000001",
  and "Installation failed". An add-on keeps no installed licence, so
  there was nothing to use instead.
* The screens said only "... failed (the game's log: ...)", on Android
  (`BuildActivity`) and in the PC setup. Fixed (fork `b8612172`, kit): the
  install step writes a line per part it couldn't install to
  `<id>/step-error.txt` beside the log (removed when a step succeeds), and
  the add-on screen, `setup.py` and `install-game.py` show it. A picked
  file keeps its name in the app's cache (`picked-N/<name>`), so the line
  names it.
  * PC, a scratch folder (`--game`, `--vita-fs`): the EU pack with the US
    licence, exit 1, "jpvoice-eu.pkg: the licence picked is for
    UP9000-..., not for this package. Pick the work.bin or .rif for
    EP9000-PCSF00532_00-SSS000CVN0000001."; the pack alone, "it needs its
    licence: pick its work.bin or .rif with it."; then the US pack's
    folder installed (exit 0) and the file was gone.
  * The Thor (debug APK of `b8612172`, `t25` labelled `ss-delta-t25` for
    the test): the "Add an add-on" shortcut's intent (`SetupActivity`,
    action `ADD_ADDON`), the system picker, `jpvoice-eu.pkg` then
    `us-addon.rif` from `Download`: "Installing the add-on failed:" with
    that line in red, then "(More in the game's log: ...)". Start over
    went back to "The game is built." with Play. Files removed after.
* Not checked on the device: a right licence through the same path (none
  here for the EU pack), an update's fallback to the game's installed
  licence.

## ST16A and ST03A on the Radeon 760M (2026-11-27)

Windows scratch install, Vulkan at 1920×1088, 60 fps target, sampled from
45 seconds after the unattended Stage Select run began. All three runs
executed on NativeCPU with zero native-to-JIT calls. This fixture used
the older eboot that temporarily returned to 30 fps while loading. The
log showed the switch back to a 60 fps target before the sample window.

| Map | Samples | Median fps | Range |
| --- | ---: | ---: | ---: |
| ST16A, first run | 38 | 49 | 34–53 |
| ST16A, second run | 41 | 54 | 51–56 |
| ST03A | 42 | 32 | 31–33 |

ST03A also stayed around 32 fps at 960×544 with the eboot that includes
the loading-screen fix. With that eboot at 1920×1088, ST16A measured
31–33 fps across 40 samples. The window was foregrounded for the last
21 seconds and the rate held steady through that change. The matching
ST03A run measured 32–33 fps. The AMD interfaces returned no GPU clock
reading. The owner confirmed these runs were through Windows Remote
Desktop, where the 32 fps cap is a known quirk on this PC.

The physical Windows console was tested at the same resolution and in-game
target with the loading-screen fix active. Window focus was recorded per
sample and engine 0 clock was read through Windows' WDDM node telemetry.

| Map and focus | Samples | Median fps | fps range | Median clock |
| --- | ---: | ---: | ---: | ---: |
| ST16A, foreground | 40 | 56 | 54–57 | 948 MHz |
| ST16A, unfocused | 22 | 56 | 53–57 | 967 MHz |
| ST03A, foreground | 28 | 59.5 | 59–60 | 1,017 MHz |

The same ST16A session had a median of 56 fps in both focus states.
The physical session removed the 32 fps cap and ST16A still ran slower
than ST03A in these scenes. The comparison sampled the full scenes, so
the specific cost of rain remains unmeasured.

In later scratch runs on the same console, Windows logged two new
`LiveKernelEvent 141` GPU engine timeouts within seconds of closing
60 fps Vulkan sessions. The valid ST03A performance run had already
finished. The gameplay check at 30 fps produced no new watchdog report.
The timing points to shutdown as a possible trigger. The event records
do not identify the GPU command that stalled.
