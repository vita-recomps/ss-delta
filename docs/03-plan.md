# 03 — Plan

Every phase has an **exit criterion**. A phase is done when that criterion is
met, not when the tasks are ticked off. Sizes are relative effort, not time:
S = a session or two, M = several sessions, L = many sessions, XL = the bulk of
the project.

Status key: ☐ not started · ◐ in progress · ☑ done

The approach is the hybrid from [research](01-research.md#approach-options)
and [D1](decisions.md):

* recompile the game's Thumb-2 code to C++ ahead of time;
* run it inside a fork of Vita3K, which supplies the OS HLE, GXM, the renderer
  and the shader translator;
* fall back to dynarmic for anything the recompiler misses, and use it as a
  differential oracle;
* then shrink Vita3K down to a single-game runtime.

---

## Phase 0 — Workspace, decryption, baseline (S) ☑

* ☑ Research snapshot ([01-research](01-research.md)).
* ☑ Repository with a `.gitignore` excluding every dump-derived artifact
  ([D2](decisions.md)).
* ☑ PFS layer decrypted by Vita3K's installer; the 1.30 patch merged.
* ☑ SELF layer decrypted to ELFs (eboot + libc/libfios2/libult/libsmart).
  The module NID `0xD66AEBF4` matches VitaGrafix's US 1.30 entry.
* ☑ First measurements on 1.30: imports, exidx, instruction mix
  (`tools/velf.py`, `tools/imix.py`).
* ☑ Firmware 3.74 + font package installed into the portable Vita3K.
* ☑ Baseline ([02-baseline](02-baseline.md)):
  * OpenGL runs at 30 fps with broken world rendering.
  * Vulkan crashes at boot on the Radeon 760M.
  * `tools/v3kdrive.py` drives runs without keyboard focus.

**Exit:** met. The game boots in our Vita3K, its behaviour is recorded, and
decrypted ELFs and hashes exist.

## Phase 1 — Vita3K from source (M) ☑

We will patch Vita3K heavily, so we need our own build and a debugger on it
first.

* ☑ Clone Vita3K with submodules into `third_party/vita3k`: a nested clone
  on branch `ss-delta`, pinned at `b75d5e62`, with the patch series in
  `patches/vita3k/` ([D5](decisions.md)).
* ☑ Build with MSVC 14.44 + Ninja Multi-Config, Qt 6.11.0
  (`tools/devshell.ps1`, `tools/build-vita3k.ps1`). No MSVC fixes were
  needed. A clean RelWithDebInfo build takes 8.7 min.
* ☑ RelWithDebInfo with PDBs boots to the title on OpenGL at 29–30 fps.
  ☑ The Debug build (`build/vita3k/bin/Debug`) boots on Vulkan with no
  crash but runs at about 0.2 fps (4.7 s per frame). Use it only for
  stepping through code; runs use RelWithDebInfo.
* ☑ **Root-cause the Vulkan crash** on the Radeon 760M
  ([02-baseline](02-baseline.md#our-build-2026-10-09-the-amd-vulkan-crash-is-found-and-fixed)).
  * It is an AMD shader-compiler crash in `vkCreateGraphicsPipelines`, on
    a texture sample packed with `packHalf2x16` whose low half is read back.
    Present in drivers 2.0.373 and 2.0.395.
  * Fixed by patch 0002 (Plus's f16 saturation).
  * Patch 0003 (repack odd vertex strides) fixes the exploded geometry
    that followed.
  * ☐ Report upstream: the AMD trigger to Vita3K (and AMD), and patches
    0002–0004 as PRs. **Deferred** by the owner until later (2026-10-09).
* ☑ The remaining misaligned vertex attribute (`R16G16_UINT` at an odd
  offset) was the cloak speckle. Patch 0004 repacks any stream Vulkan
  can't fetch in place. The cloak is now correct on AMD, which Plus doesn't
  manage, and the validation layer reports no misalignment.
* ☐ Retest our fork on the RTX 4090. Does patch 0003 also fix the white
  Walhalla floor there?
* ◐ Vita3K-Plus.
  * ☑ The v1.2 binary boots on Vulkan here and fixes the black blocks and
    white floors ([02-baseline](02-baseline.md#vita3k-plus-v12-2026-10-09)).
  * ☑ Base our fork on upstream, not Plus ([D5](decisions.md)). Plus is
    upstream plus 167 commits (+18k lines), mostly other games' fixes.
  * ☐ Port its two fixes for this game (`98a65bff` depth, `d248beee` MSAA
    outlines). Neither applies cleanly on upstream; both build on earlier
    Plus surface-cache changes.
  * ☑ Find which Plus change avoids the AMD Vulkan crash: `105331d9`
    (f16 saturation, patch 0002), plus `35cbde8d`'s stride repacking
    (patch 0003) for correct geometry.
* ☑ Collect the RTX 4090 test results and record them in
  [02-baseline](02-baseline.md#rtx-4090-results-2026-10-09).
  * No crashes, 30 fps.
  * Every rendering artifact depends on the GPU vendor.
  * Upstream Vulkan works on NVIDIA.
* ◐ Investigate the uninitialized register reads in translated shaders
  (NVIDIA GLSL warnings), starting with the Walhalla floor shader.
  * This is the leading hypothesis for the vendor-dependent artifacts.
  * ☑ Tie the warnings to shader hashes. The two read so far are benign
    partial-`vec4` copies ([02-baseline](02-baseline.md#rtx-4090-results-2026-10-09)).
  * ☐ Zero-initialise every register array in our build's translator, and
    compare the Walhalla floor on the RTX 4090.
  * A fix here would be upstreamable, and every Vita3K user of this game
    would benefit.
* ☑ Real input for automated runs.
  * Patch 0005 adds a test-only named pipe (`VITA3K_INPUT_PIPE`) that holds
    buttons and sticks. `tools/v3kdrive.py` uses it automatically.
  * Verified without focus: the title goes to the main menu and New Game
    opens the save dialog; `ls_up` walks the player on the field map.

**Exit:** met 2026-10-09. Our build reaches gameplay on Vulkan on this
machine (field and arena at 30 fps, rendered correctly), and input is
scripted without focus.

Carried over (not blocking Phase 2):
* ☑ RTX 4090 round 2 (2026-10-10): 12/12 ok, 30 fps. The arena floor is
  still white on NVIDIA in every build.
* ☑ White floor root-caused on the mini PC
  ([02-baseline](02-baseline.md#why-the-arena-floor-is-white-2026-10-10)).
  The MSAA depth texture missed the surface cache because of 32-row tile
  rounding. Fixed by patch 0006.
  * ☑ RTX 4090 round 3: the depth texture now comes from the cache, but
    the floor is still white. The cause is narrowed to the floor's albedo
    texture (swizzled UBC1, 10 mips).
  * ☑ 4090 diag rounds 1–3: not BC decoding, mips, overlays or high
    accuracy. The floor shader itself computes white on NVIDIA.
    * Lead: fp32 denormals. The translator packs f16 pairs into floats;
      NVIDIA can't preserve fp32 denormals, AMD does.
  * ⏸ **On hold** until direct NVIDIA access. Then: confirm with RenderDoc
    or shader edits on the 4090, and try keeping packed f16 pairs in
    `uint` registers. Debug toggles are on fork branch `debug/floor`.
* ☑ Zero-init experiment: done on AMD, with no effect. The cause was
  elsewhere.
* porting Plus's two fixes for this game (`98a65bff`, `d248beee`). They
  concern depth and MSAA reads at higher resolutions, so they move to
  Phase 7/8 unless the 4090 retest shows a need.

## Phase 2 — Static analysis and inventory (M) ◐

Results: [04-inventory](04-inventory.md).

* ☑ `tools/inventory.py` (on `tools/vitaelf.py`) writes
  `generated/inventory/<module>/*.csv` for the eboot, libc, libfios2 and
  libult:
  * functions, jump tables, indirect branches, calls, import calls,
    imports;
  * address-taken functions, mid-function entry points;
  * unreached bytes, classified.

  Recursive descent with IT blocks, literal pools, `tbb`/`tbh` tables,
  constants propagated for `movw/movt` far calls, no-return calls, and
  EHABI landing pads.
* ◐ Ghidra 12.1.3 + VitaLoaderRedux project built headless.
  * A VitaLoaderRedux 1.09 release for 12.1.3 exists.
  * Not installed yet: it is a compiled plugin, so it has to be read and
    built from source first, or the owner has to OK the release binary.
  * No longer needed for the function list, which the inventory gives
    completely. Kept for hand analysis.
* ☑ Open research questions answered
  ([04-inventory](04-inventory.md#answers-to-the-open-research-questions)):
  * no `pop {pc}` dispatch;
  * no tail calls in the eboot;
  * no mode switches through pointers;
  * the 703 ARM-mode exidx entries are 674 import stubs, 28 NEON routines
    and the end marker.
* ◐ Frame-step logic and render-target sites:
  * ☑ located: the display callback `0x81828708`, the `FPS` parser
    `0x817e7c74`, the main render target `0x81828272` plus 9 more
    render-target creators;
  * ☐ following the `FPS` value into the main loop is left for the
    Phase 8 60 fps study.

**Exit:** met for the eboot, libfios2 and libult (2026-10-10). 100% of
exidx entries are classified; every indirect branch is resolved or listed as
dynamic in `indirect.csv`. libc has 8 unexplained bytes in 2 functions.

New for the recompiler:
* The eboot has no C++ exception scopes. libc has 152 landing pads that
  need entry support.
* The exidx mode bit can be wrong (libc `memcpy`).

## Phase 3 — Recompiler v0: integer + VFP scalar (L) ☑

The tool is ours, in `recomp/` ([D6](decisions.md)). It never ships game
data; it reads `extracted/elf/` and writes `generated/`. Details and
numbers: [05-recompiler](05-recompiler.md).

* ☑ **Decoder.** Capstone with details, on top of the inventory's recursive
  descent. `recomp/armrecomp/semantics.py` makes operand semantics
  (shifter carry, writeback, `IT` state, S from the mnemonic) explicit.
* ☑ **Guest context** (`recomp/runtime/armrecomp.h`).
  * `r0–r15`;
  * NZCV/Q/GE flags;
  * `d0–d31` as a union with `s` and float/double views. The `q` view waits
    for NEON (Phase 5);
  * FPSCR;
  * TPIDRURO (TLS);
  * exclusive monitor state.
* ☑ **Emitter.** One C++ function per guest function, with one statement
  group per instruction.
  * A liveness pass over the whole function drops flag writes nobody reads
    (1.7 M in the eboot).
  * Memory is accessed as `base + (uint32_t)addr`, matching Vita3K's
    4 GiB reservation.
* ◐ **Control flow:**
  * ☑ `bl`/`blx #imm` become direct calls, checked against the return
    protocol;
  * ☑ a call to an import stub becomes `call_import` (the HLE thunk);
  * ☑ `tbb`/`tbh` become `switch`;
  * ☑ `IT` becomes `if`;
  * ☑ `blx reg` goes through `call_indirect`, and a return to an unexpected
    address goes through `escape`. Phase 4 implements both hooks;
  * ☐ `ldrex`/`strex` become host CAS. They have single-thread semantics in
    v0; the CAS moves to Phase 4, with the threads.
* ☑ Functions containing NEON or ARM-mode code are left to dynarmic in v0:
  5,577 NEON and 28 ARM-mode functions in the eboot.
* ☑ **Per-instruction test suite** (`recomp/run-tests.ps1`). Random inputs,
  our generated code vs. dynarmic executing the same instruction.
  * Up to 20 encodings of every form, 256 states each: 11,366 tests over
    the four modules, **0 failing**.
  * Plus 468 whole leaf functions with control flow, 64 states each:
    **0 failing**.
* ☑ Size and compile time measured for the whole eboot.
  * 91 buckets of about 64 KB of guest code each, 312 MB of C++.
  * A clean build of the four modules takes 4.8 min with 4 jobs; the worst
    bucket peaks at 435 MB.
  * `gen_eboot.lib` is 82 MB.

**Exit:** met (2026-10-10). C++ for every non-NEON function compiles,
there are 0 unsupported instructions in all four modules, and both test
suites pass. Size and compile time are in
[05-recompiler](05-recompiler.md#build-130-eboot).

## Phase 4 — Hybrid runtime in the Vita3K fork (L) ☑

Design: [D7](decisions.md). Details and numbers:
[05-recompiler](05-recompiler.md#runtime-in-the-fork-phase-4). Fork patches
0007 (runtime) and 0008 (import trace).

* ☑ **AOT dispatch.**
  * The recompiled eboot is a DLL (`ssd_aot_eboot.dll`) that the fork loads
    from `SSD_AOT` after checking its code hash against guest memory.
  * Dynarmic's `PreCodeReadHook` ends every block at a recompiled entry, and
    `DynarmicCPU::run` calls the native function.
  * Native code calling a missing guest address runs a nested JIT loop with
    `lr` set to a sentinel block, then returns.
* ☑ **HLE from native code.** `call_import` calls the kernel's import handler
  directly, with the registers copied into the JIT at the boundary. LLE
  stubs (libc and the other bundled modules) run on the JIT.
* ☑ **Threads.** Each `DynarmicCPU` owns its native guest context.
  * `ldrex`/`strex` in native code are a host compare-and-swap against the
    value `ldrex` read, the same protocol as Vita3K's dynarmic.
  * Callbacks (`run_callback`) enter native code through the same hook.
  * HLE calls made inside a run keep the caller's halted state (a guest
    callback ends on WFI).
  * A thread exiting with native frames on its stack unwinds them.
  * Guest threads get 64 MiB host stacks while AOT is on.
* ☑ **Differential mode** (`SSD_AOT_DIFF=N`).
  * Every Nth native call per thread runs first on a shadow JIT, with
    journaled writes that are undone afterwards. Then the native call runs,
    and registers, VFP and the shadow's writes are compared.
  * Calls that make HLE calls or exclusive stores are skipped.
* ☑ Counters (`SSD_AOT_COUNT=1`, `SSD_AOT_STATS=<file>`):
  * native and JIT instructions;
  * transitions;
  * escapes;
  * JIT instructions by entry.
* ☑ Debugging tools:
  * `SSD_AOT_RANGE`, plus a `RECOMP_BISECT` DLL that routes direct calls
    through the host, to bisect down to one native function;
  * `SSD_AOT_TRACE`;
  * `SSD_TRACE_IMPORTS`;
  * `tools/stackdump.py`.

**Exit (2026-10-10):**

* ☑ Boot to the title with the AOT build loaded. Title and field render the
  same as the JIT build, at 30 fps.
* ☑ **At least 80% of executed guest instructions native at the title.**
  **80.3% at the title, 91.7% in the field** (29.5 fps) with eboot, libc
  and libfios2 native; libult stays on the JIT (fibers). See
  [05-recompiler](05-recompiler.md#coverage-130).
  With Phase 5's NEON layer (done early, 2026-10-10): **54% at the title,
  71% in the field.** What remains is libc and the other LLE libraries, plus
  the eboot's 28 ARM-mode functions.
  Before NEON:
  Measured: **26% at the title, 36% in the field.** Nearly all the
  remaining JIT time is in eboot functions that contain NEON, such as
  `8188c41e` (28 KB, 1,275 NEON instructions) and the integer-NEON
  functions at `81a0a130`–`81a0e1f4`, plus libc through its LLE stubs.
* ☑ Zero differential mismatches over 1,000 frames of `ELDER DEFAULT MAP`
  idle. Measured: 11,181 frames and 116,609 checked calls, 0 mismatches.
  22,387 calls were skipped (HLE calls 20,372; atomics 2,015).

## Phase 5 — NEON, ARM mode and the bundled modules (L) ☑

* ☑ **NEON layer**: portable C++ templates (`recomp/runtime/neon.h`), not
  SIMDe or intrinsics. All 97 eboot forms and the 6 libc forms; 0 failing in
  11,576 dynarmic tests. See [05-recompiler](05-recompiler.md#neon).
  * Start with `vmov.i q, #imm` and `vdup q, d`. They are the only NEON
    forms in 2,039 of the eboot's 5,577 NEON functions
    ([05-recompiler](05-recompiler.md#neon-input-to-phase-5)).
  * Must match ARM semantics: flush-to-zero and default NaN where FPSCR says
    so, saturation, and `vrecpe`/`vrsqrte` estimate tables bit-exact.
  * Unit tests against dynarmic, per op.
* ☑ The eboot's 28 ARM-mode functions. All ARM leaf functions are in the
  tests.
* ☑ Recompile `libc`, `libfios2` and `libult` with the same tool. They are
  generated at the load addresses Vita3K picks ([D8](decisions.md)) and all
  run natively. libult's fiber switches escape and resume natively at
  resume points ([D9](decisions.md)).
* ☑ Differential runs through quests via the debug Stage Select (581
  entries, `BootSequence Quest Select`, buttons through the fork's input
  pipe). A sweep of 20 quests (every 30th entry, 75 s each, `SSD_AOT_DIFF=64`)
  found **0 mismatches** in 83,656 checked calls and **0 JIT instructions
  inside the four modules**, at 29.5 fps. A call-level check (every direct
  call sampled, `RECOMP_BISECT` DLLs) then covered 219,000 calls in title,
  field and 5 quests. It found missing FPSCR.DZC in native code (fixed) and
  one race ([05-recompiler](05-recompiler.md#coverage-130)).
* ☑ A full quest played to the end (the user, 2026-10-10, `ss-delta.exe`).
  The run covered a new game, the intro, the first story quest and the
  main menu: 157 G guest instructions native, 0 JIT instructions inside
  the four modules, 416,000 fiber switches resumed natively. There were no
  crashes. One rendering issue: a ghost book in the main menu
  ([02-baseline](02-baseline.md)).

**Exit:** a full quest with **zero dynarmic entries** in `efg`, libc, fios2
and ult, and a clean differential log. **Met** (2026-10-10).

## Phase 6 — Standalone runtime (L) ☑

* ☑ A single-game executable: SDL3 window, no Qt GUI, no app list, fixed
  config, and its own `ss-delta.ini` (like `decimation.ini`).
  * ☑ `ss-delta.exe`, a target in the fork ([D10](decisions.md)), on
    upstream's SDL front end. It boots PCSA00152 directly with the fixed
    settings and `ss-delta.ini` (paths, scale, window, fullscreen with
    F11/Alt+Enter, vsync, filter, volume, recompiled modules, logging). The
    field runs at 29–30 fps, 99.9% native, and `v3kdrive start` drives it
    (fps title, input pipe, screenshots).
  * ☑ Keyboard and gamepad bindings in `ss-delta.ini` (`[keyboard]`: up to
    two keys per Vita button and stick direction; `[gamepad]`: one SDL
    gamepad button per Vita button). The SDL front end had no keyboard
    input at all (only Qt mapped keys); `ss-delta.exe` now maps them
    itself. The mouse is the touchscreen, and typed text reaches the
    game's keyboard dialogs.
  * ☑ Its own icon and version resource (`ss-delta.rc`: a plain delta, no
    game artwork). The window shows the game's `icon0.png` from the
    player's installed copy.
  * ☑ A self-contained folder, `tools/make-dist.ps1` → `dist/ss-delta-<commit>/`
    (187 MB). It holds the exe, 8 DLLs (OpenSSL, FFmpeg, Discord's SDK,
    which Vita3K's libraries link), `data/`, `shaders-builtin/`, `icons/`,
    the locally built `ssd_aot_*.dll`, `ss-delta.ini` and a README. No Qt.
    The field runs at 30 fps from it.
* ☑ **libult**: the recompiled libult runs on the SceFiber HLE, with
  escapes and resume points at fiber switches ([D9](decisions.md)). Host
  fibers were tried and dropped.
* ◐ **Stubs.** All NP/Net/Http/Ssl/Adhoc/Sns/Smart/Camera/Near imports
  return clean "offline" results. No `sceNpAuthInit` dialogs.
  * ☑ Offline mode (fork patch 0023, on in `ss-delta.exe`): NetCtl reports
    disconnected, HTTP/HTTPS/SSL use the HLE modules with no network, and
    requests fail with `SCE_HTTP_ERROR_NETWORK`. `libhttp` and `libssl` no
    longer run on the JIT. No dialogs at boot. The title's DOWNLOAD entry
    shows an empty screen and waits, exactly as in Vita3K without offline
    mode.
  * ☐ NP (PSN), ad hoc, Near, Smart and Camera are Vita3K's HLE stubs.
    Their offline answers are not checked yet; the game hasn't been seen
    using them outside the online menus.
* ◐ **Firmware LLE modules** ([D11](decisions.md)).
  * ☑ Recompiled from ELFs `ss-delta.exe` dumps as it loads them
    (`SSD_DUMP_ELFS=1`, already relocated): `sysmodule.skprx` (19
    functions), `libSceFt2` (758), `libpvf` (98), `libscemp4` (274) and
    `libsceavplayer` (305). The translator gained 4-instruction `IT`
    blocks, `mcr` to TPIDRURO and the fixed-point `vcvt` forms. 0 failing
    in 7,593 dynarmic tests over these modules.
  * ☐ 17 font functions (14 `libSceFt2`, 3 `libpvf`) use NEON forms the
    translator lacks: `vld2`/`vld4`/`vst2`/`vst4`, 64-bit `vld1`/`vst1`,
    `vshll` by the element size, `vmov.16` and `vbic.i32` immediate. None
    has run in any session.
  * Firmware code is Sony's. Any recompiled firmware module is generated
    locally from the user's PUP, like the game.
* ☑ **NativeCPU** (fork patch 0024): threads run on native code alone. It
  is the default in `ss-delta.exe`; `[recompiled] jit = true` brings the
  JIT back. Title, dialogs, hub, book menu, field and a quest: **0 JIT
  instructions**, 29.6 fps.
* ☑ **Install flow**: `tools/install-game.ps1 -Dump <zip|folder> -Firmware <PUPs>`.
  It needs MSVC and Python with capstone, because the code is generated
  locally (D2).
  1. Takes the user's NoNpDrm zip or folder, plus the firmware PUPs.
  2. Decrypts with Vita3K's own installers (`ss-delta.exe --install`,
     `--install-firmware`) and its SELF loader. The game runs for 45 s with
     `--dump-elfs`, and the modules come out as decrypted, relocated ELFs,
     so no external decryptor is needed.
  3. Verifies `eboot.bin` against the 1.30 hash ([hashes](hashes.md)).
  4. Generates the nine modules and compiles them. The code hashes are the
     same as the ones from the hand-made ELFs.
  5. Lays out `dist/<name>/` with the game in its own `fs/`.
  From the user's zip, the run took about 25 minutes, most of it compiling.
* ☑ dynarmic stays as an optional build flag for debugging only:
  `VITA3K_DYNARMIC=OFF` (`build-vita3k.ps1 -NoJit`, fork patch 0026) builds
  without it; every thread then runs on NativeCPU.

**Exit:** `ss-delta.exe` boots from the user's own dump to a quest, with no
Vita3K GUI and no dynarmic. **Met** (2026-10-11): a fresh
`install-game.ps1` folder from the user's zip, with the exe built without
dynarmic (`make-dist.ps1 -NoJit`), boots through Stage Select into the
first quest. 0 JIT instructions, 30 fps. Open items: the remaining offline
stubs (NP, ad hoc and others are Vita3K's HLE stubs) and 17 font functions
that use NEON forms not translated yet.

## Phase 7 — Rendering correctness (L) ☑

Results: [02-baseline](02-baseline.md#phase-7-map-sweep-2026-10-11).

* ☑ Overexposure and black blocks: none on any map in our Vulkan fork.
  They were OpenGL symptoms of the baseline. Fog, haze and smoke were
  fixed by the settings in D4 update 4.
* ☑ Mind's Eye overlay works: health-coloured monster silhouettes, weak
  spots and hidden spots. Its depth read is served correctly; Plus's
  `d248beee` isn't needed.
* ◐ Every quest map renders correctly (`tools/map-sweep.ps1`, 2026-10-11):
  * 48 of 50 map IDs swept, all correct at 29.3–29.7 fps.
  * ST17A's only quest doesn't start from Stage Select. It shares its
    arena with ST17B/C.
  * The ST17B/C ground grain in motion is the game's own look: a real Vita
    shimmers the same (the user, 2026-10-11).
* ☑ Shader stutter: decided against install-time translation (D12). Shader
  translation depends on draw-time hints, so pipelines compile in the
  background on first use and are cached. `ss-delta.exe` hides the
  compile notice (patch 0028).
* ☑ Story scenes:
  * the book-page episodes render correctly;
  * the intro and first story quest were playtested (2026-10-10);
  * with a story-complete save (2026-10-11): the late chapters' pages,
    the boss intros, the sacrifice scene, Magusar's introduction and the
    credits all render correctly;
  * not seen: the endings after defeating Magusar, which need a won final
    battle (a playtest).
* ☑ Bloom drawn frames late (ghost book, title butterfly): fixed by fork
  patch 0019, confirmed by the user.

**Exit:** a visual sweep of all maps and cutscenes with no known rendering
bugs. **Met** (2026-10-11): 48 of 50 map IDs (ST17A is unreachable from
Stage Select but uses the ST17B/C arena), and the story scenes up to the
final battle. No known rendering bugs remain. The ST17 ground shimmer is
also there on a real Vita. Left for a playtest: the endings after
defeating Magusar.

## Phase 8 — PC features (M) ◐

Results: [02-baseline](02-baseline.md#phase-8-2026-10-11), decision
[D13](decisions.md).

* ☑ **Internal resolution** (D13).
  * The 720×408 target is the game's own `ResoDown 1`; `ResoDown 0`
    renders the 3D at 960×544, the framebuffer's size. `ss-delta.ini`
    `full_3d` (default on) serves it through a `boot_config.ini` copy
    (fork patch 0029). The installed file is unchanged.
  * Vita3K's `scale` multiplies that: at 2 the 3D is 1920×1088. All 50
    map IDs swept at `full_3d` + scale 2: correct, 29.5–29.7 fps on the
    Radeon 760M.
  * Widescreen: the Vita's 960×544 is already 16:9 (to within 0.7%), so
    fullscreen on a 16:9 display has no bars to fill. Ultrawide would need
    the game's projection changed; not planned.
* ◐ **Input.** Keyboard/gamepad remapping was done in Phase 6. Touch:
  * The game's text names one touch-only action, the Black Rite ("touch
    and hold the Black Rite icon"). `[touch]` bindings hold a finger at a
    point while a key or gamepad button is held. The default puts the
    icon (56, 494) on F and the left trigger.
  * Injected touches reach the game (a tap advances the title screen).
    The Black Rite binding itself is untested: the icon didn't appear in
    the scripted runs. It needs a playtest.
  * The rest takes buttons or the mouse: the post-battle "touch enemies
    or allies" choice, pacts in Phantom Quests, the quest-intro skip
    (START also skips it).
* ◐ **60 fps study** (not shipped; [02-baseline](02-baseline.md#60-fps-study)).
  * The cap is the main loop's frame timer, created for 30 fps
    (`0x812ab888`), plus the display flip threshold of 2 vblanks.
  * `[debug] frame_rate = 60` sets both in memory: 57 fps on this
    machine, and player movement keeps its speed.
  * Blocker: a quest started at 60 fps never finishes loading.
* ◐ **Saves.**
  * ☑ Stored on the PC, in the Vita file system folder.
  * ☑ Import of Vita saves: `ss-delta.exe --import-save <folder|zip>`
    (decrypted saves, e.g. from VitaShell or Apollo), with
    `--export-save`. Tested with a story-complete Apollo save.
  * ☐ DLC entitlement: the game has a `ForceDLC` engine flag. Some of the
    DLC was sold, so turning it on is the owner's call. Not done.

**Exit:** a full playthrough is possible on keyboard/controller at
≥ 2× internal resolution. Status (2026-10-11): ≥ 2× is met on every map
(3D at 1920×1088, 30 fps). Still needed: a playtest of the Black Rite
binding and of a longer stretch on keyboard and controller.

## Phase 9 — Compatibility pass (M) ☐

* ☐ A compatibility matrix like decimation's: story, all quest types, Avalon
  hub, sigils, Book (Librom) menus, FMV, audio, saves.
* ☐ Comparisons against Vita3K for timing-sensitive systems (Havok physics,
  AI).

**Exit:** the matrix has no blocking entries.

## Later (deferred)

* Ad hoc multiplayer between two copies of the port. It is the same shape as
  decimation's Phase 9: `SceNetAdhocMatching` / PDP over UDP. XLink Kai
  compatibility would allow play with real Vitas.
* Modding hooks: C++ function overrides, plus loose files (the engine
  already prefers loose files when `PackFileFirst false`).
* Other platforms (Linux, Steam Deck).

---

## Risk register

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | NEON/VFP semantics wrong (Havok physics, 17.7% of code) | desyncs, broken physics | differential testing vs. dynarmic per op and per function; bit-exact estimate tables |
| R2 | Generated code too large to compile (3.8M instructions; flags) | slow builds, out of memory | flag liveness, 64 KB buckets, ccache, 3 jobs on 16 GB (decimation's figure) |
| R3 | Hidden control flow (`pop {pc}` dispatch, tail calls, mode switches) | crashes in native code | the dynarmic fallback catches misses; Phase 2 inventory |
| R4 | Vita3K renderer bugs (Vulkan crash on AMD, overexposure, Mind's Eye) | unplayable or ugly | Phase 1 root cause; Vita3K-Plus fixes; Phase 7 |
| R5 | Threads/ULT/callback integration with Vita3K's kernel | deadlocks, crashes | keep Vita3K's thread model in the hybrid; fibers only in Phase 6 |
| R6 | Firmware modules (fonts, AvPlayer) are Sony code run as LLE | can't drop the PUP dependency | FFmpeg for FMV; pvf/ft2 recompiled locally or replaced |
| R7 | Frame-locked game logic | no 60 fps | treat 60 fps as optional (Phase 8 study) |
| R8 | GPL (Vita3K) | the runtime can't be relicensed | private, non-distributed project ([D2](decisions.md)); keep the recompiler tool separate |
| R9 | First Vita recomp: no prior art to copy | slower progress | borrow patterns from decimation (Yakumo fallback), N64Recomp/XenonRecomp (lookup tables), 3dsrecomp (verify mode) |
