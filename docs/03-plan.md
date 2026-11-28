# 03 — Plan

Every phase has an **exit criterion**. A phase is done when that criterion is
met, not when the tasks are ticked off. Sizes are relative effort, not time:
S = a session or two, M = several sessions, L = many sessions, XL = the bulk of
the project.

Status key: ☐ not started · ◐ in progress · ☑ done

Paths in the finished phases are those of their time. Since
[D17](decisions.md) (2026-10-13) `recomp/` and the generic tools
(`tools/velf.py`, `imix.py`, `inventory.py`, `v3kdrive.py`, ...) are in
`third_party/recomp/`, the PowerShell build, install and packaging scripts
are Python scripts there (`build-vita3k.py`, `install-game.py`,
`make-dist.py`), and the fork's `vita3k/ss-delta/` is split into
`vita3k/game-frontend/` and `vita3k/games/ss-delta/`.

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
    0002–0004 as PRs; since 2026-10-12 also patch 0039 (NaN-ignoring
    min/max, the white floor on NVIDIA in upstream and Plus too).
    **Deferred** by the owner until later (2026-10-09).
* ☑ The remaining misaligned vertex attribute (`R16G16_UINT` at an odd
  offset) was the cloak speckle. Patch 0004 repacks any stream Vulkan
  can't fetch in place. The cloak is now correct on AMD, which Plus doesn't
  manage, and the validation layer reports no misalignment.
* ☑ Retest our fork on the RTX 4090. Patch 0003 doesn't fix the white
  Walhalla floor there; patch 0039 does (2026-10-12, below).
* ☑ Vita3K-Plus.
  * ☑ The v1.2 binary boots on Vulkan here and fixes the black blocks and
    white floors ([02-baseline](02-baseline.md#vita3k-plus-v12-2026-10-09)).
  * ☑ Base our fork on upstream, not Plus ([D5](decisions.md)). Plus is
    upstream plus 167 commits (+18k lines), mostly other games' fixes.
  * ☑ Its two fixes for this game (`98a65bff` depth, `d248beee` MSAA
    outlines): not ported, nothing left for them to fix. Neither applies
    cleanly on upstream (both build on earlier Plus surface-cache changes);
    our own patches serve the depth reads (0006 MSAA depth, 0032 depth
    clamp, 0033 depth UV scale), Mind's Eye is correct without `d248beee`
    (Phase 7) and all 50 map IDs render at 960×544 and 1920×1088 (Phase 8)
    (2026-10-12).
  * ☑ Find which Plus change avoids the AMD Vulkan crash: `105331d9`
    (f16 saturation, patch 0002), plus `35cbde8d`'s stride repacking
    (patch 0003) for correct geometry.
* ☑ Collect the RTX 4090 test results and record them in
  [02-baseline](02-baseline.md#rtx-4090-results-2026-10-09).
  * No crashes, 30 fps.
  * Every rendering artifact depends on the GPU vendor.
  * Upstream Vulkan works on NVIDIA.
* ☑ Investigate the uninitialized register reads in translated shaders
  (NVIDIA GLSL warnings), starting with the Walhalla floor shader.
  * Closed 2026-10-13: they were not the cause. The last vendor-dependent
    artifact, the NVIDIA floor, was a NaN in min/max (patch 0039, below),
    and the warnings read were benign.
  * ☑ Tie the warnings to shader hashes. The two read so far are benign
    partial-`vec4` copies ([02-baseline](02-baseline.md#rtx-4090-results-2026-10-09)).
  * ☑ Zero-initialise every register array in our build's translator: done
    on AMD with no effect (below). The RTX 4090 comparison waits with the
    NVIDIA floor (on hold).
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
* ☑ White floor root-caused on the Radeon 760M test PC
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
  * ☑ Debugged on the RTX 4090 (2026-10-12): not denormals. A NaN in the
    vertex shader's height-fog clamp (`VMIN`/`VMAX`): NVIDIA returns 0, AMD
    the other operand. Fixed by patch 0039 (NaN-ignoring min/max, shader
    cache version 16); the floor is textured on the 4090
    ([02-baseline](02-baseline.md#the-white-floor-is-a-nan-in-minmax-rtx-4090-2026-10-12)).
  * ☑ Recheck the arena and the field on the Radeon 760M with patch 0039
    (2026-10-13): unchanged, and a full map sweep renders as before.
  * ☑ Full map sweep on the RTX 4090 with patch 0039 (`full_3d` + scale 2):
    all 50 map IDs as on AMD, 29.3–29.6 fps
    ([02-baseline](02-baseline.md#rtx-4090-map-sweep-2026-10-12)).
  * ☑ Non-map checks on the RTX 4090 (story scenes, credits, new game,
    final battle, Ad Hoc Play), 2026-10-13: as on AMD after fork patch 0040
    (Ad Hoc Play hung when opened after the journal; not NVIDIA-specific)
    ([02-baseline](02-baseline.md#rtx-4090-non-map-pass-2026-10-13)).
  * ☑ HDR: no HDR output (SDR swapchain, owner chose no HDR mode). On the
    HDR desktop it looks normal, windowed and fullscreen (owner, 2026-10-13).
* ☑ Zero-init experiment: done on AMD, with no effect. The cause was
  elsewhere.
* porting Plus's two fixes for this game (`98a65bff`, `d248beee`). They
  concern depth and MSAA reads at higher resolutions, so they move to
  Phase 7/8 unless the 4090 retest shows a need.

## Phase 2 — Static analysis and inventory (M) ☑

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
* ☑ Ghidra 12.1.3 + VitaLoaderRedux project built headless: dropped
  (2026-10-12), not needed.
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
* ☑ Frame-step logic and render-target sites:
  * ☑ located: the display callback `0x81828708`, the `FPS` parser
    `0x817e7c74`, the main render target `0x81828272` plus 9 more
    render-target creators;
  * following the `FPS` value into the main loop moves with the 60 fps
    study (deferred, Phase 8).

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
* ☑ **Control flow:**
  * ☑ `bl`/`blx #imm` become direct calls, checked against the return
    protocol;
  * ☑ a call to an import stub becomes `call_import` (the HLE thunk);
  * ☑ `tbb`/`tbh` become `switch`;
  * ☑ `IT` becomes `if`;
  * ☑ `blx reg` goes through `call_indirect`, and a return to an unexpected
    address goes through `escape`. Phase 4 implements both hooks;
  * ☑ `ldrex`/`strex` become host CAS: done in Phase 4, with the threads
    (single-thread semantics in v0).
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
    ([05-recompiler](05-recompiler.md#neon)).
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
  config, and its own `ss-delta.ini`.
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
* ☑ **Stubs.** All NP/Net/Http/Ssl/Adhoc/Sns/Smart/Camera/Near imports
  return clean "offline" results. No `sceNpAuthInit` dialogs.
  * ☑ Offline mode (fork patch 0023, on in `ss-delta.exe`): NetCtl reports
    disconnected, HTTP/HTTPS/SSL use the HLE modules with no network, and
    requests fail with `SCE_HTTP_ERROR_NETWORK`. `libhttp` and `libssl` no
    longer run on the JIT. No dialogs at boot. The title's DOWNLOAD entry
    shows an empty screen and waits, exactly as in Vita3K without offline
    mode.
  * ☑ NP (PSN), ad hoc, Near, Smart and Camera are Vita3K's HLE stubs.
    Checked offline (2026-10-12): Play Online ends as cancelled and returns
    to the menu (fork patch 0036; it hung at "Connecting..." before); the
    AR quests start; nothing else uses them outside the online menus. Ad
    hoc play is the multiplayer phase.
* ☑ **Firmware LLE modules** ([D11](decisions.md)).
  * ☑ Recompiled from ELFs `ss-delta.exe` dumps as it loads them
    (`SSD_DUMP_ELFS=1`, already relocated): `sysmodule.skprx` (19
    functions), `libSceFt2` (758), `libpvf` (98), `libscemp4` (274) and
    `libsceavplayer` (305). The translator gained 4-instruction `IT`
    blocks, `mcr` to TPIDRURO and the fixed-point `vcvt` forms. 0 failing
    in 7,593 dynarmic tests over these modules.
  * ☑ 17 font functions (14 `libSceFt2`, 3 `libpvf`) used NEON forms the
    translator lacked: `vld2`/`vld4`/`vst2`/`vst4`, `vld1`/`vst1` with an
    alignment hint, `vshll`, `vmov.8/16` into a lane and `vbic`/`vorr`
    immediates, plus a `mov pc, rN` jump (2026-10-12). All 772 + 101
    functions are now native, so the build without the JIT has no font
    path left to stop on. 0 failing in 3,537 + 1,468 dynarmic tests (the
    new forms included), and in the game modules' full suite. None of these
    functions has run in a session yet (the modules verify on first call).
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
* ☑ Every quest map renders correctly (`tools/map-sweep.ps1`, 2026-10-11;
  all 50 map IDs in Phase 8):
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
  * the ending after defeating Magusar: playtested by the owner
    (2026-11-21, the final battle won with the cheats on): it plays
    correctly and returns to Librom's menu.
* ☑ Bloom drawn frames late (ghost book, title butterfly): fixed by fork
  patch 0019, confirmed by the user.
* ☑ ST03A water: a dark patch over the water during the opening
  fly-through (seen by the user, not on a Vita). Per-vertex depth clamp
  in translated shaders broke near-plane clipping; fixed by fork patch
  0032 (depth clamp in the pipeline), checked with a full map sweep.

**Exit:** a visual sweep of all maps and cutscenes with no known rendering
bugs. **Met** (2026-10-11): 48 of 50 map IDs (ST17A is unreachable from
Stage Select but uses the ST17B/C arena), and the story scenes up to the
final battle. No known rendering bugs remain. The ST17 ground shimmer is
also there on a real Vita. The ending after defeating Magusar was
playtested later (2026-11-21).

## Phase 8 — PC features (M) ☑

Results: [02-baseline](02-baseline.md#phase-8-2026-10-11), decision
[D13](decisions.md).

* ☑ **Internal resolution** (D13).
  * The 720×408 target is the game's own `ResoDown 1`; `ResoDown 0`
    renders the 3D at 960×544, the framebuffer's size. `ss-delta.ini`
    `full_3d` (default on) serves it through a `boot_config.ini` copy
    (fork patch 0029). The installed file is unchanged.
  * The game's 960×544 mode is not fully consistent: its depth-of-field
    shaders keep the 720×408 mode's depth UV scale. Fixed in the shaders
    as the game registers them (fork patch 0033); found by the user as
    haze over the hub's bones.
  * Vita3K's `scale` multiplies that: at 2 the 3D is 1920×1088. All 50
    map IDs swept at `full_3d` + scale 2: correct, 29.5–29.7 fps on the
    Radeon 760M.
  * Widescreen: the Vita's 960×544 is already 16:9 (to within 0.7%), so
    fullscreen on a 16:9 display has no bars to fill. Wider screens
    (phones, ultrawide) need the game's projection and 2D layer changed:
    under "Later" since #28.
* ☑ **Input.** Keyboard/gamepad remapping was done in Phase 6. Touch:
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
* ☑ **60 fps** as an option (fork patch 0041, 2026-10-13;
  [02-baseline](02-baseline.md#60-fps-the-loading-screen-and-loading-at-30-2026-10-13)).
  * The cap is the main loop's frame timer, created for 30 fps
    (`0x812ab888`), plus the display flip threshold of 2 vblanks.
  * `[display] frame_rate = 60` sets both in memory: 57 fps on this
    machine. Game logic steps by the measured frame time: movement and an
    idle boss fight keep their speed.
  * The quest-start loading screen never ends at 60 (a frame-time check in
    the loader; its loop animation is never told to stop), so loading
    screens run at 30 (the `NowLoadingTask` in state 2, 3 or 5).
  * Checked: all 50 maps, the fight timing, title → hub → journal → story
    quest → results → hub.
  * ☑ The owner played at 60, alone and in Ad Hoc Play, without issues
    (2026-10-13): 60 is the default since patch 0042, written explicitly
    in the default `ss-delta.ini` (`frame_rate = 30` for the Vita's rate).
  * ☑ The 30-versus-60 fps follow-up on the constant scan measured a
    Blitz wall cast, journal playback, a projectile offering and Red
    Hood's intercept chains. The Blitz cast used the D30 overrides.
    See [01-research](01-research.md#130-s-and-960544-constants-in-the-eboot-local-2026-11-26).
* ☑ **Saves.**
  * ☑ Stored on the PC, in the Vita file system folder.
  * ☑ Import of Vita saves: `ss-delta.exe --import-save <folder|zip>`
    (decrypted saves, e.g. from VitaShell or Apollo), with
    `--export-save`, into any of the game's three slots (`--slot`).
    Tested with a story-complete Apollo save in slot 2 next to the
    owner's own.
  * ☑ Add-ons (DLC), D14: `ss-delta.exe` records the released add-ons in
    the save's `system.bin` at start (`[game] dlc`, on), once the
    installed game's data has them (1.30's pacts and raiments). Same bytes
    as the file Vita owners swap in; the new outfits appear.
  * ☑ The add-ons PSN gave as gifts at Cassus (GitHub issue #11, D14
    update 1): Soulbinder, Fox (Necky), Slave, Archsorcerer, Mad Witch,
    Easterner, Saint, Beast, White Cat, eight hoods, the Fox Sigil, given
    in the loaded save as taking the gifts would. Seen NEW in the raiment
    list, kept through a save and reload (test folder, slots 1 and 2).
  * ☑ The Japan-only raiments (issue #11, part 2): `[game]
    japan_raiments` (on, with `dlc`) gives Sylvan (Japan's boxes
    COSTUME_09 and COSTUME_11: all twelve rows) and Benkei (in no box:
    colour A, as Necky). Both listed and drawn in Raiments: Top (test
    folder, 2026-11-21).
  * ☑ The original game's raiments (issue #11, part 3, D28):
    `tools/og-raiments.py` builds a rePatch mod from the player's dump of
    the original Soul Sacrifice 1.30 and their Delta: ARKS Armor and
    Dragonslayer as raiments 720-743, worn as top and bottom. Built from
    the owner's EU dump (NoNpDrm, and installed), given by `ss-delta.exe`,
    drawn in Raiments, Portraiture and the hub, kept through a save and
    reload; built over another rePatch mod, rebuilt and removed again (the
    mod beneath restored exactly). US Delta, test folder.
  * ☑ The original's pre-order Spirits' offerings (20 items, D29):
    Delta keeps their rows commented out; `[game] spirits_offerings`
    (on, with `dlc`) switches them on with a packaged mod `ss-delta.exe`
    makes from the installed game, and gives each once per save. Listed
    NEW in Select Offerings with their names; Spirits' Flamepike, Wolf
    fang and Heart cast in a try-out (weapon, beast arm, golem); kept
    through a save and reload without being given again; the save loads
    without them with every other offering unchanged; the setting off
    deletes rePatch's copy. US game, test folder, 2026-11-22.
  * ☑ Sortiara as an ally (D31): `[game] sortiara_ally` (off by default)
    adds her to the roster once a save. Listed NEW in Select Allies with her
    portrait, details and six offerings; she fought in a Phantom Quest;
    the game saved her and she was still an ally after a reload with the
    setting off (test folder, story-complete save, 2026-11-23). Still to
    check: her falling and Undo Death, affinity growth, a story quest she is
    already in.
  * ☑ A save that never stored the gifts failed to load with `dlc`
    ("Failed to load save data."): the grant wrote into the image before the
    game's checksum check. It now keeps the checksum right (01-research,
    "Failed to load save data." with the add-on gifts). The story-complete
    test save loads with `dlc` on, gifts and all (2026-11-23).

* ☑ **Xbox button labels** (2026-11-20; research in
  [01-research](01-research.md#button-prompts-local-2026-11-20)).
  * ☑ `[game] button_labels` (`playstation`, `xbox`, `auto`), live in the settings
    menu as Button prompts. The fork's texture cache takes a
    `TextureOverride` from the front end (`game-frontend/button_labels.*`):
    the game's `com_001_*` atlases are decoded as they are uploaded, each
    □ ○ × △ / L / R painted over in its ink blot with the letters of the
    gamepad button `[gamepad]` binds to it, drawn at the internal
    resolution, and uploaded like an imported texture. Switching re-uploads
    every texture.
  * ☑ The textures are found by an FNV-1a hash of their data: 59 in all
    languages, table from `tools/button-atlases.py` (the symbols sit at the
    same place in every copy of an atlas; only the words move; a tutorial
    picture's copies are matched by their strokes).
  * ☑ START and SELECT (`com_001_002`, `005`): Xbox's Menu (≡) and View
    symbols. Kept: the D-pad and the sticks (an Xbox pad's are the same,
    and the icons are generic) and TOUCH (the touchscreen; only the Black
    Rite is also on LT).
  * ☑ The tutorial pictures with buttons drawn in: `game_027_000c`,
    `002c`–`005c` (letters narrowed where the picture is drawn squeezed),
    `menu_eu_tutorial_002`, `003`, `005`, `006`. Left as they are: the
    journal screenshots `menu_034_002/003` (tiny inventory markers, and a
    multiplication ×) and the photo of a Vita.
  * ☑ The text's ○ △ □ (`elder_number_font`, the U8 font page they come
    from): circled letters in the glyphs' cells. They are buttons in every
    supported language's text. Not the × (U+00D7) of the Latin font, which
    the UI also uses as a multiplication sign ("Ether × 0"): if "Press the
    %lc button" (`ingame_tutorial` 3111) gets ×, it stays.
  * ☑ `auto`: the first connected gamepad's own face-button labels (SDL):
    lettered → Xbox labels with its letters (a Nintendo-style pad's A is
    east), PlayStation symbols or no gamepad → the game's icons.
  * ☑ `ss-delta.exe --button-labels-test <in> <out>` draws the labels on
    extracted `.gxt` files, for review (all 17 US and French samples
    matched their table entries and looked right, 2026-11-20).
  * ☑ Playtest (the owner, 2026-11-20): the icons and `auto` work, in play
    and in the journal, its tutorial entries (Lore > Tactical advice, where
    the tutorial pictures are) included. Not seen yet: the △ text (a
    tutorial message when Offerings renewal or boosting unlocks).
* ☑ **Skip the intro logos** (GitHub issue #6, 2026-11-20; research in
  [01-research](01-research.md#boot-logos-local-2026-11-20-github-issue-6)).
  * ☑ `[game] skip_intro` (Skip intro logos, default off, as on the Vita):
    the health warning and the four company logos are skipped and the game
    opens on its title screen, about 6 s after start instead of 20.
    Data only, like `frame_rate`: the front end zeroes each logo's
    timeline in guest memory, so native code stays on.
  * ☑ Checked: no logo drawn on any recorded frame; title → Continue →
    a save loaded into the hub.
  * ☑ Playtest by the owner (2026-11-20): the skip works. It stays off by
    default (owner).
* ☑ **Japanese Voice-over Pack** (a PSN add-on, 2026-11-20; research in
  [01-research](01-research.md), "Japanese Voice-over Pack"; tests in
  [02-baseline](02-baseline.md#japanese-voice-over-pack-installed-and-heard-from-2026-11-20)).
  * ☑ The installer takes NoNpDrm dumps laid out as ux0 (the licence in
    `license/addcont/<title>/<dir>/`, no `work.bin`), from a zip or a
    folder, and warns when a content stays encrypted (fork); `dumpinfo.py`
    sees that licence (kit).
  * ☑ Both regions: each game looks in its own `addcont/<title>/`, and the
    US and EU packs hold the same files. US game with the US pack, and EU
    game with the pack in its folder: Voice Language offers Japanese, and
    Librom's lines are read from `voice_jp.pk`.
  * ☑ End to end: the front end takes `--dump=<file>`; `setup.py` takes a
    pkg's licence from beside it, and with the game built by this release
    (`ss-delta/build.json`, the executable's SHA-256) installs add-ons
    alone in seconds (also from the setup window, the game's rows left
    empty); RecompLauncher's setup asks for the pack as an optional `dlc`
    input (`--dump={input:voice}`); Android installs one from the setup
    screen, which the launcher's "Add an add-on" shortcut opens once the
    game is built. Tested on the PC and the Thor.
  * ☑ Playtest by the owner (2026-11-21): the lines heard in Japanese
    (story-complete save, Voice Language → Japanese, US game, PC).
  * Not supported: a pack for the other region's title (an EU game with
    the US pack). It installs into the other title's folder, which the
    game never reads; the setup says so.
* ☑ **Undub patch** (GitHub issue #8, 2026-11-21; research in
  [01-research](01-research.md), "Undub patch"; tests in
  [02-baseline](02-baseline.md#undub-patch-a-repatch-mod-2026-11-21-github-issue-8)).
  * ☑ rePatch mods (fork): `--install-content` takes a folder or zip with
    `rePatch/<title>/` and installs it into `ux0/rePatch/<title>/`, for the
    installed region when the mod names the other one. When the game
    starts, those files are read in place of the game's own (IOState's
    read overrides), while `[game] repatch` is on (default, in the settings
    menu as "Mods (rePatch)"). A mod's `boot_config.ini` is the base of
    the copy ss-delta serves.
  * ☑ Setup (kit): `dumpinfo.py` reports a mod, and `setup.py` installs
    mods alone when the game is built, like add-ons. The setup window's
    "Add an add-on (DLC) or mod...", RecompLauncher's optional `mod` input
    (`--dump={input:mod}`) and its Mods setting, and Android's add-on
    picker (a zip) all reach the same step.
  * ☑ Tested on the PC: the US game streams the prologue's lines from the
    undub; the EU game boots with it. On the Thor: installed through the
    "Add an add-on" shortcut from a zip, served at boot, the hub reached.
  * ☑ Playtest by the owner (2026-11-21): the prologue's lines heard in
    Japanese (New Game, US game, PC).
  * Note: a `.7z` isn't read; players unpack it (on Android, zip the
    `rePatch` folder).
* ◐ **Cheats** (GitHub issue #7, 2026-11-21; research in
  [01-research](01-research.md), "Cheats"; tests in
  [02-baseline](02-baseline.md#cheats-2026-11-21-github-issue-7)).
  * ☑ `[cheats]`, the settings menu's Cheats page (every platform, all off,
    switched while the game runs): Infinite health and Unlimited offerings
    (quests), Max Lacrima (9,999,999) and Max levels (Life and Magic 99).
    Data only, like `skip_intro`: the front end sets the values in guest
    memory each frame, through the game's own pointers (from the VitaCheat
    codes for 1.30), after checking vtables and plausible values.
  * ☑ Checked on the PC: health and offering uses refilled in a quest, the
    Lacrima and levels shown on Portraiture, kept through a save and reload.
  * ☑ One-hit kills: ordinary enemies in one hit; bosses take five (the
    game limits a hit on a boss to a fifth of its health).
  * ☑ Checked in real fights, the EU game, Android (the Thor) and Ad Hoc
    Play (each copy changes only its own player; enemies stay in step).
  * ☑ Offerings: Unlimited offerings gives each cast back and brings a
    lost offering back; Lasting offerings (new) keeps an arm, armour or
    buff for the whole quest instead of its 30-180 s. Tested with Giant's
    Arm.
  * ☑ Lasting offerings on summons, armour, shields, transforms and buffs
    (their durations live in four tables); on the EU game and the Thor.
  * ☑ Ad Hoc Play between the PC and Android (the Thor): room, lobby and a
    quest together, cheats on the Android side.
  * ☑ Invincible (2026-11-26): enemies' hits pass without damage or a
    stagger, through the game's own debug switch (NoDamage, 01-research
    "Cheats"), so scripted playtests stay on course
    (`v3kdrive.py ... start --set cheats.invincible=true`). Checked
    against goblins, the Harpy's minions and the Harpy on the PC.
  * ☑ Invincible in Ad Hoc Play (players 3 and 4, host or guest: only the
    copy's own sorcerer) and on the EU game on Android, in a room with the
    US game on the PC (2026-11-26).
  * ☐ Invincible with allies; a boss's shockwave and gust still make the
    sorcerer brace for a moment (a reaction outside the hit handler).
  * ☐ Max levels early in the story: those saves keep the levels in play
    in another record whose place depends on the save; left alone for now.
  * ☐ Playtest by the owner: the stats at level 99, a whole quest.
  * ☐ Candidates (addresses known, not used yet): 99 of each owned
    offering, slayer points.
* ☑ **Mouse camera** (2026-11-21; research in
  [01-research](01-research.md), "Mouse camera"; tests in
  [02-baseline](02-baseline.md#mouse-camera-2026-11-21)).
  * ☑ `[mouse]` (PC only; the settings menu's Mouse page): Tab or a middle
    click captures the cursor, and mouse motion turns the camera through
    the right stick; the same again or Esc releases it, and the settings
    menu, a text dialog or another window release it while they last.
    Sensitivity (1: a full turn for 7200 counts) and Invert vertical
    switch while the game runs.
  * ☑ Through the game's measured stick table, each axis on its own, so
    the camera turns by as much as the mouse moved (up to its ~550°/s);
    byte-exact pushes, added after Vita3K's unit-circle clamp.
  * ☑ Checked through the input pipe: steady 5-200°/s and whole motions
    within about 10%, diagonals at full speed.
  * ☑ Played by the owner with a real mouse (2026-11-21): "it works".
  * Note: the pitch's speed is assumed to follow the yaw table
    (**hypothesis**, not measured).

**Exit:** a full playthrough is possible on keyboard/controller at
≥ 2× internal resolution. **Met** (2026-10-12): the owner played on a
controller at scale 2: combat, the Black Rite on the left trigger, a
sacrifice, a DLC quest cleared, audio. 60 fps stays deferred.

## Phase 9 — Compatibility pass (M) ☑

Matrix: [06-compatibility](06-compatibility.md).

* ☑ A compatibility matrix: story, all quest types, Avalon
  hub, sigils, Book (Librom) menus, FMV, audio, saves (2026-10-12). Two
  non-blocking ⚠️: the endings after the final battle (not reached; their
  movies and event mechanism checked; ✅ since the owner's playtest of
  2026-11-21) and the debug-only `BookEnding`.
* ☑ Comparisons against Vita3K for timing-sensitive systems (Havok physics,
  AI): an idle boss fight, five runs native and five on the JIT, ends the
  same within the emulator's own run-to-run spread
  ([02-baseline](02-baseline.md#native-against-jit-an-idle-fight-timed-2026-10-12)).

**Exit:** the matrix has no blocking entries.

## Phase 10 — Ad hoc multiplayer (L) ☑

The owner asked for it on 2026-10-12, after Phase 9. Ad Hoc Play (Librom →
Network → Ad Hoc Play) between copies of the port. Unlike a PSP port,
which needs its own ad hoc layer, Vita3K already speaks ad hoc ([research](01-research.md#ad-hoc-play)):
the firmware's own matching module runs on the emulated Vita, over P2P
sockets that Vita3K maps to UDP.

* ☑ **10a Survey, one copy** (2026-10-12): Create Room reaches the host
  lobby (four slots, quest, Ready) on the JIT. The game loads
  `adhoc_matching.suprx` as LLE when it enters Ad Hoc Play; one import of
  it was missing (SceNetInternal `0x689B9D7D`).
* ☑ **10b Copies on one PC** (fork patch 0038, `ss-delta.exe --player N`,
  [D15](decisions.md)):
  * player N is Vita user N-1 (its saves copied from player 1's on its first
    start), with its config and log in `ss-delta/player<N>/`, and reads the
    shader cache without writing it (checked: 717 files, none touched);
  * `[multiplayer] network = local`: copy N has the address 127.0.0.N, ad hoc
    sockets bind it, and a broadcast goes to each other copy; `lan` is
    Vita3K's way (an adapter and its broadcast);
  * `[multiplayer] gamepad = n`: only the nth gamepad, also in the background
    (not checked: no gamepad on the test machine);
  * `tools/v3kdrive.py --player N` drives copy N.
* ☑ **10c Two copies in one room** (2026-10-12): Search for Room finds the
  host, the client joins, a quest starts, runs in step and ends for both
  ([06-compatibility](06-compatibility.md)). On the JIT first, then on
  NativeCPU. Not played to a win (the test save's Black Rite price kills
  both sorcerers).
* ☑ **10d Native code** for `adhoc_matching.suprx`, the only module ad hoc
  loads (Rudp and ScePspnetAdhoc are not used in Ad Hoc Play): 81 functions,
  0 failing in 454 + 5 dynarmic tests. It loads only when Ad Hoc Play opens,
  so the loader puts it where its code was generated for (`0x80757000`,
  where it lands anyway), and `--dump-elfs` loads it so that
  `install-game.ps1` gets its ELF.
* ☑ **10e Package**: `run-player2.bat` and the README's Ad Hoc Play section
  in `make-dist.ps1`; the owner's folder is updated. The owner's check
  (2026-10-12): a quest played and completed together without issues, and
  LAN play between two PCs works. A gamepad per copy is still unchecked
  (the owner has one gamepad).

**Exit:** two copies play a quest together in Ad Hoc Play, from a package
built without the JIT.

## Shared toolchain with shinobido-2 (S) ☑

[D17](decisions.md), for the sibling port of Shinobido 2 (its D4 and D6).

* ☑ The fork as a submodule, `third_party/vita3k` on branch `games` (the
  `ss-delta` branch, patch 0042, plus the shared single-game frontend).
* ☑ `recomp/` and the generic tools replaced by the `vita-recomp`
  submodule, `third_party/recomp`; SSD's own tools point at it.
* ☑ `game.json` and `docs/dist-readme.txt` for the shared Python scripts;
  `build-vita3k.ps1`, `install-game.ps1`, `make-dist.ps1` and
  `ssdelta_ini.py` deleted.
* ☑ Checked (2026-10-13): the fork built with `build-vita3k.py`; the new
  `ss-delta.exe`, on a junction file system with a copy of the saves,
  starts ST01A from Stage Select on native code (all ten modules), 30 fps
  on the loading screen, then 56–58 fps in the field.

**Exit:** `ss-delta.exe` built from the submodules plays a quest as before.

## EU version (S) ☑

[D19](decisions.md); GitHub issue #2.

* ☑ EU 1.30 against US: the same build, identical code and modules
  (01-research, "EU version").
* ☑ The frontend runs whichever region is installed
  (`Profile::other_title_ids`, `--title-id`); saves, `boot_config.ini` and
  the add-on check use that title.
* ☑ `game.json`: `other_title_ids` and the EU eboot hash; the kit's
  install and setup accept either region.
* ☑ Checked (2026-11-17, 02-baseline): installed from the EU dump; a US
  save loads; a quest at 60 fps, loading at 30; the US game unchanged.

**Exit:** an EU dump installs and plays like a US one.

## Phase 11 — Linux, targeting the Steam Deck (L) ◐

The owner asked for it on 2026-11-17. Research:
[07-linux](07-linux.md). The Deck is the only Linux machine.

* ☑ Survey of what the code needs (2026-11-17, 07-linux).
* ◐ **11a Baselines on the Deck**: upstream Vita3K's Linux AppImage (the
  reference) and our Windows release under Proton, setup included. Frame
  rate at 1× and 2×, rendering on RADV against the 760M.
  * ☑ Upstream AppImage (2026-11-17): hangs the GPU on Vulkan within
    35 s in every configuration; OpenGL doesn't (07-linux).
  * ◐ Our Windows build under Proton 11: runs natively, no GPU hang
    (2026-11-17); its frame rate and the setup under Proton still to do.
* ◐ **11b The fork on Linux, JIT only**: built in the Steam Linux Runtime
  SDK (WSL2 or CI), run on the Deck on dynarmic. Our renderer patches on
  RADV; `v3kdrive.py`'s Linux backend (FIFO input, `SIGTERM`).
  * ☑ Built in WSL 2 with the sniper SDK (g++ 14), runs in the sniper
    runtime on the Deck: a quest from Stage Select at 60 fps, rendered
    correctly, no GPU hang (2026-11-17, 07-linux).
  * ☑ The input pipe as a FIFO; driven from a shell script on the Deck.
  * ☑ The fork and kit changes committed (fork `18bdae40`, kit `c5b23f5`);
    `ss-delta.exe` checked unchanged on Windows.
  * ☑ A 2× run: 59.9 fps in the first quest map.
  * ☐ `v3kdrive.py` and `build-vita3k.py` on Linux; which patch avoids
    upstream's hang.
* ◐ **11c Native code on Linux**: the `dlopen` loader, the recompiler's
  CMake for clang, `ssd_aot_*.so`, NativeCPU; the dynarmic tests
  (`run-tests`) on Linux.
  * ☑ The loader, the CMake (g++ 14 for now) and the ten modules as
    `.so`; a quest on NativeCPU on the Deck at 60 fps, 0 JIT calls
    (2026-11-17, 07-linux).
  * ☐ The dynarmic tests on Linux; a longer play session natively.
* ☑ **11d A setup for Linux** (kit): a pinned portable LLVM and sysroot,
  the compile on the Deck (time, memory), a release job. Record the choice
  in decisions.md.
  * ☑ The compiler is zig, not LLVM plus a sysroot ([D20](decisions.md));
    the exe needs only glibc, zlib and Vulkan (curl linked in).
  * ☑ The kit's setup on Linux (`setup-linux.json`, `toolchain-linux.json`,
    `setup.sh`, the window, a desktop entry) and `build-vita3k.py` on Linux.
  * ☑ On the Deck (2026-11-17): from the dump to a playable folder in
    20 min (14 compiling, 6 jobs); the folder plays a quest natively at
    60 fps (07-linux).
  * ☑ The release workflow's `linux` job, run by hand on GitHub
    (2026-11-17, run 44080546990): 25 min, an 87 MB artifact; its
    `ss-delta.x86_64` plays a quest natively on the Deck at 60 fps.
  * ☑ Peak memory on the Deck: 4.6 GB used against 2.0 GB idle, so about
    2.6 GB for the setup with 6 jobs; second run 1165 s, with the menu
    entry and icon, and zig's cache removed (466 MB left).
* ◐ **11e Deck polish**: Game Mode, controls and touch, 16:10 screen,
  suspend/resume, 30/40/60 fps and battery.
  * ☑ Measured over SSH (2026-11-17, 07-linux, `tools/deck-quest.sh`):
    four maps at 60 fps, 4.3–4.8 W APU (30 fps: 3.9 W; 2×: 6.9 W);
    nested gamescope; SIGTERM quits cleanly in 0.2 s; audio on PipeWire.
  * ☑ The setup adds the game to Steam (`--steam`, kit 706ea10); checked:
    the shortcut, and a launch through Steam on native code.
  * ☐ On the Deck in hand (07-linux's list): Game Mode from Steam, the
    touchscreen, suspend/resume, 40 Hz, battery unplugged.

**Exit:** with a Deck and their own dump, a player gets from a release to
a quest in Game Mode, on native code.

## Phase 12 — macOS on Apple Silicon (L) ◐

The owner asked for it on 2026-11-17. Research:
[08-macos](08-macos.md). The test machine is a MacBook Air (M5). arm64
only: no Rosetta, no Intel Macs.

* ☑ Survey of what the code needs (2026-11-17, 08-macos).
* ☑ **12a Access and baseline** (2026-11-17): SSH to the Mac, its
  configuration; upstream Vita3K's macOS arm64 build on the M5 with the
  test file system runs title to quest at 26–29 fps, too bright, with
  ST03A's water patch (08-macos).
* ☑ **12b Memory mapping**: `double-buffer` works on MoltenVK without
  upstream's `__APPLE__` override and is needed (`disabled` blows out the
  snow, as in upstream) (2026-11-17, 08-macos).
  * ☑ The override dropped (2026-11-17).
  * ☑ Write tracking with 16 KiB host pages: tracked regions cover
    whole host pages, and the merge loop's end fixed; 0 unhandled faults
    on the M5, Windows unchanged (2026-11-17).
  * ☑ The map sweep on the Mac: all 50 maps natively at 60 fps, 0
    native-to-JIT calls, 0 unhandled faults, pictures as on Windows;
    ST16A's fault race and the input pipe race fixed (fork `9b380165`,
    `60cf6936`) (2026-11-17, 08-macos).
* ◐ **12c The fork on macOS, JIT only**: the single-game executable on
  APPLE (`<id>.arm64`, `.dylib` module scan), built on the Mac or in CI;
  our renderer patches on MoltenVK; `v3kdrive.py`'s POSIX backend.
  * ☑ Built on the Mac (configure 82 s, build 100 s); ST03A from Stage
    Select at 59.4 fps on the JIT, rendered as on Windows, water patch
    fixed (2026-11-17, 08-macos).
  * ☑ The fork changes committed; `ss-delta.exe` on Windows checked
    (ST03A natively, 60 fps, pictures as before).
  * ☐ `v3kdrive.py`'s POSIX backend (a shell driver stands in for now).
* ◐ **12d Native code on arm64**: the recompiler's CMake for Apple clang
  (`-ffp-contract=off`, `.dylib`, exported symbols); the dynarmic tests on
  an arm64 host; a quest on NativeCPU.
  * ☑ The ten modules as `.dylib` in 95 s; ST03A natively, 0 native-to-JIT
    calls, rendered as on Windows; 23,280 + 684 dynarmic tests, 0 failing
    (2026-11-17, 08-macos).
  * ☑ Frame pacing: macOS wakes timed waits 25–50% late; real-time
    threads (fork `09587ca1`) give 60.0 fps natively, p99 17 ms
    (2026-11-17, 08-macos).
  * ☐ A longer play session natively (audio included).
* ☑ **12e A setup for macOS** (kit): zig or the Command Line Tools,
  measured on the M5; packaging (folder or `.app`), signing and
  quarantine; a release job. Record the choice in decisions.md.
  * ☑ zig chosen (D21): ten modules in 2.8 min, signed ad hoc by its
    linker, ST03A natively at 60 fps (2026-11-17, 08-macos).
  * ☑ The kit's macOS branch (`setup-macos.json`, `toolchain-macos.json`,
    `setup.command`, the app in the playable folder); the setup built on
    the M5 and run end to end from a quarantined download: 5.6 min from
    the dump to the title on native code (2026-11-17, 08-macos).
  * ☑ The Dock icon looked at on the Mac's screen (the owner, 2026-11-18):
    the game's icon, but square and larger than other apps'; the setup
    now draws it in Apple's shape (kit `49a3a5b`) and the game no longer
    replaces it (fork `e0a324a8`, 08-macos).
  * ☑ The setup run by the owner from a quarantined download, window and
    all (2026-11-18, 08-macos); it no longer asks for an update or licence
    the dump holds (kit `2b39018`).
  * ☑ The release workflow's `macos` job run on GitHub (shipped in v0.3.0,
    2026-11-18).
* ☐ **12f Mac polish**: Retina and fullscreen, trackpad touch, Ad Hoc
  Play's `local` mode (only 127.0.0.1 exists on `lo0`), thermals and
  battery.
  * ☑ Game Mode in fullscreen: the app runs the game's binary from
    inside its bundle (kit `60b1bf2`, fork `bc449f9a`, 2026-11-18,
    08-macos).

**Exit:** with an Apple Silicon Mac and their own dump, a player gets
from a release to a quest on native code.

## Phase 13 — Launcher standards: one program, a portable folder (M) ◐

An open letter from RecompLauncher's lead asks recomp ports for one
executable, everything in its folder, a tarball, and a flag for
everything ([D22](decisions.md)). 0.3.0 waits for it (its first draft,
2026-11-18, was held back).

* ☑ The front end: every path from the game's folder (no
  `init_paths`, no `SDL_GetPrefPath`); the importer in `setup/` started
  when the game isn't built, waited for, then the game boots; macOS
  translocation handled; `--game`, `--install`, `--dump`,
  `--add-to-steam`, `--set`, `--fullscreen`/`--windowed`, `--help`
  (with every setting), the importer's options passed on.
* ☑ The kit: `setup.py` builds in its own folder and deletes its
  downloads and work files; the window's Play hands back to the game;
  `make-setup.py` lays out the release as the game's folder (Windows: the
  VC++ runtime beside the exe; macOS: the app bundle); `curl.exe` when
  Python can't check a certificate on Windows.
* ☑ Unattended runs from a release folder (2026-11-18), the US dump, the
  downloads inside the folder:
  * Windows: `ss-delta.exe --dump <zip> --accept-microsoft-license`
    built the game and booted it in the same process, natively at 59 fps;
    a second start went straight to it; `--set` with a bad key and an
    out-of-range value were reported and ignored;
  * the Deck: `--dump --build-only` (exit 0, 3.7 GB);
  * the M5: `--dump --build-only` (exit 0, 3.5 GB).

  On all three, `setup/` kept only `kit` and `python` afterwards, and
  nothing was written outside the folder: `%APPDATA%\Vita3K`,
  `~/.cache/Vita3K`, `~/.local/share/Vita3K`, `~/Library/Application
  Support/Vita3K` and the old shared download caches were not touched.
  Found on the way: Windows' Python couldn't check llvm-mingw's
  certificate (now `curl.exe`), and Vita3K's patch folder must exist.
* ☑ The window flow on the Mac (the owner, 2026-11-18): the test release
  as a quarantined download, the app through Open Anyway, the importer's
  window, Build, Play; later starts go straight to the game; Game Mode in
  fullscreen.
* ☐ The window flow on Windows and the Deck in Game Mode (optional:
  both run the same code as the tested paths).
* ☑ The release workflow's three jobs; 0.3.0 tagged again (shipped
  2026-11-18).

**Exit:** each platform's archive, unpacked, is the game: started once
with the player's dump it builds itself, and nothing lands outside its
folder.

## Phase 14 — Android, targeting the AYN Thor (L) ◐

The owner asked for it on 2026-11-19. Research:
[09-android](09-android.md). The test device is an AYN Thor Max
(Snapdragon 8 Gen 2, Adreno 740, 16 GB, Android 13). The owner's choice:
a PC builds the native modules first; an on-device build may come later.
Update (2026-11-20): the on-device build (14g, D27) is the 0.4.0
milestone, and nothing is released before it.

* ☑ Survey of what the code needs (2026-11-19, 09-android). The Android
  SDK, NDK r29 and adb installed on the test PC.
* ◐ **14a Access and baseline**: wireless adb to the Thor; the device read
  (`getprop`, CPU, page size, both Vulkan drivers' extensions);
  upstream Vita3K's release APK with the test file system, title to quest:
  frame rate at 1× and 2×, rendering on Qualcomm's driver and on Turnip.
  * ☑ Wireless adb; the device read (2026-11-19, 09-android): QCS8550,
    4 KiB pages, 15.6 GB, Qualcomm's Vulkan driver of 2023-12 without
    shader interlock or raster-order access (the subpass input path).
  * ☑ Upstream's APK on Qualcomm's driver, 1×: title 29.5 fps, ST03A
    from Stage Select at 29.9 fps on the JIT, no crash; brighter, hazier
    snow than Windows, as upstream on the Mac. Driven entirely over
    adb (gamepad events written to the built-in controls' device).
  * ☐ Turnip (Mr. Purple T23, T30) in upstream's app; 2×.
* ◐ **14b The single-game APK, JIT only**: `add_game` as a shared library
  on `ANDROID`, an `SDLActivity` for the game, the frontend's paths in the
  app's folders, no importer; built on the test PC with Gradle and the
  NDK; `v3kdrive.py`'s adb backend (FIFO, `am start`, `frame:`).
  * ☑ The library in WSL with the NDK, without vcpkg (Boost, OpenSSL,
    curl from source, the NDK's zlib); the APK with Gradle on Windows
    (`game-frontend/android/`); the frontend's Android glue (2026-11-19,
    09-android).
  * ☑ On the Thor, Qualcomm's driver, on the JIT: the title at 45–49
    fps, ST03A from Stage Select at 58.5–59 fps, rendered as on Windows;
    the built-in controls work as a gamepad.
  * ☑ Turnip in the APK: `[debug] gpu_driver`, libadrenotools' hook
    libraries packed beside the game's; T23 and T30 load and have
    raster-order access (Qualcomm's driver: neither that nor interlock).
    ST03A at about 57 fps on all three, rendered alike.
  * ☑ The fork changes committed (fork `89d9b84b`); `ss-delta.exe` on
    Windows checked (ST03A natively, 59–60 fps, interlock as before).
  * ☐ The swapchain following a resized surface; `v3kdrive.py`'s adb
    backend (the session's shell helpers stand in).
* ☑ **14c Our renderer on the Adreno**: `double-buffer` mapping, depth
  clamp, programmable blending without shader interlock; then the 50-map
  sweep against Windows' pictures.
  * ☑ The sweep over adb on Turnip T23 (2026-11-20, 09-android): every
    Stage Select screenshot checked against Windows' (all 50 right the
    first time); 48 maps at 60 fps and rendered as on Windows; ST06A and
    ST20A hung in libult (`Queue.h:797 packet != NULL`).
  * ☑ The hang: `strex` as a value-only compare-and-swap let libult's
    queue lose a packet (ABA) when a host thread stalled; the kit's
    exclusive monitor now breaks other reservations as dynarmic's does.
    The sweep twice over with it: 100 quest loads, no hang.
* ☑ **14d Native code on Android**: the modules built with the NDK's clang
  for `aarch64-linux-android`, loaded from internal storage; a quest on
  NativeCPU with 0 JIT calls; the dynarmic tests on the Thor under adb.
  * ☑ The ten modules with the NDK on the test PC (6.8 min, 106 MB
    stripped); the frontend copies them into internal storage
    (2026-11-19, 09-android).
  * ☑ ST03A on NativeCPU, 0 native-to-JIT calls: 60.0 fps at 1× and 2× on
    Qualcomm's driver, 60.0 / 58.1 fps on Turnip T23.
  * ☑ The dynarmic tests on the Thor: 23,280 + 684 over the ten modules,
    0 failing (built in WSL with the NDK, run under adb with a time limit
    and an RSS watchdog).
  * ☑ A longer play session natively (audio included). The owner
    (2026-11-19): the first story quest on Qualcomm's driver showed
    black rectangles in the fog (non-coherent framebuffer reads within
    a draw, 09-android); on Turnip T23, two quests without issues,
    audio fine. Found on the way and fixed: a false critical log line
    on a write-tracking race (`mem.cpp`), and the log's end lost when
    the app is swiped away (flushed on pause).
* ◐ **14e A PC setup for Android** (kit): the modules for Android built by
  the existing setup on Windows, Linux or macOS (zig against a stub libc,
  or the NDK), the folder laid out and pushed or copied. Record the
  choice in decisions.md.
  * ☑ zig, not the NDK ([D25](decisions.md)): musl headers, no C library
    linked, stubs for bionic's; `aot_android.cpp`; the ten in 5.1 min,
    89 MB; ST03A natively at 60 fps (2026-11-19, 09-android).
  * ☑ `build-recomp.py --android`, `install-game.py --android`,
    `android.py push` (APK, fs, modules, driver; saves kept); the
    frontend unpacks driver packages from `drivers/`.
  * ☑ End to end from the owner's dump to a separate test app: 19 min on
    the PC, 4.6 min of copying, ST03A natively on T23 at 60 fps.
  * ☑ From a release folder (2026-11-20): `setup.py --android` and its
    window, `ss-delta.exe --android`, adb pinned from Google (its licence
    accepted), the APK in `setup/android/`. End to end on the Thor:
    built from the dump, copied, the app from its icon, Turnip
    downloaded, ST03A natively at 60 fps (09-android).
  * ☑ The APK in the release workflow: the `android` job (NDK r29,
    Gradle, signed with the release key from the secrets) feeds every PC
    archive. A manual run on GitHub (2026-11-20, 33 min): the APK signed
    with the release key, the same APK in all three archives.
* ◐ **14f Thor polish**: the gamepad and the analog triggers, the
  touchscreen, the second screen (rear touch?), 120 Hz pacing, AYN's
  performance modes and battery, pausing in the background.
  * ☑ Turnip as the driver on Adreno: Qualcomm's draws the fog wrong
    (09-android). The APK's first screen offers Mr. Purple's T23 on
    Adreno 7xx (pinned size and SHA-256); `[debug] gpu_driver = auto`
    takes it (2026-11-20, checked in a test package).
  * ☑ Home and back to the game (same process, 60 fps); Back doesn't
    quit; holding Select opens the settings menu.
  * ☑ The settings menu without PC leftovers (the owner, 2026-11-20;
    09-android): no window, fullscreen, F-key, validation-layer or
    several-copies settings on Android, and the GPU driver as a choice.
    The tabs fit their names on every platform.
  * ◐ Touch: the touchscreen reaches the game; the `[touch]` bindings
    (Black Rite on the left trigger) didn't on Android and are fixed in
    `touch.cpp` (**hypothesis** until seen in play: no Black Rite icon
    showed in the quests tried, so neither a finger nor the trigger could
    be checked there).
  * ◐ 60 Hz: the surface asks for it; unmeasured, the test Thor's
    setting caps the screen at 60 Hz already.
  * ☑ The second screen: dropped (the owner, 2026-11-20: most players
    have one screen, so the game stays on the main one).
  * ◐ On-screen controls for phones without a gamepad (the owner,
    2026-11-21; 09-android, "On-screen controls"): on by default, off on
    the settings menu's Controls page; a finger elsewhere is the Vita's
    touchscreen, the Black Rite spot stays clear; hidden while a gamepad
    is used; LOCK holds L for the lock-on until tapped again. Checked on
    the Thor, also with a phone-shaped display. Left: a real phone, the
    Black Rite spot's size and the lock-on seen in play.
  * ☑ The settings menu froze over a system dialog (save list, load
    prompt): Vita3K's overlay input queue (09-android, "On-screen
    controls"). Fixed; checked on Windows and the Thor.
  * ☑ AYN's performance modes and battery: they raise only the GPU's
    lowest clock and the CPU clocks in use. ST03A runs at 60 fps at 1×
    in Standard (4.1 W from USB, about 5½ h on the battery, an estimate);
    High Performance costs 0.7 W more for nothing. At 2× it drops a few
    frames in either mode (5.3–6.5 W).
* ☑ **14g The setup on the device: the 0.4.0 milestone**
  ([D27](decisions.md); the owner, 2026-11-20: no release before it).
  The APK builds the game itself, with Python, capstone and zig packed
  in it as native libraries. Survey: 09-android, "The setup on the
  device".
  * ☑ Probe on the Thor over adb (2026-11-20, 09-android). The kit ran
    unchanged under python.org's Python 3.14 with zig 0.17.1: recompiling
    took 4.2 min and compiling 24.4 min (8 jobs), peaks of 1.8 GB and
    95.9 °C, 4.4 GB of space. The output is the PC's, byte for byte.
  * ☑ The tools in the APK (2026-11-20, 09-android): kit
    `android-build-tools.py`, the APK's `buildToolsDir`, `BuildTools.java`,
    and the release workflow packs them. Started by the app, the full
    build takes 14.6 min on the Thor (4.3 to recompile, 10.3 to compile)
    and the modules match. The APK grows to about 105 MB.
  * ☑ The front end's own steps called from Java (2026-11-20, 09-android):
    `FrontendStepActivity` runs each in its own process. Firmware took
    4.4 s, the dump's zip 16 s, `--dump-elfs` 45.5 s. The fix for libfiber
    in dumps (`SSD_AOT=none` set by the front end) made the dumps match
    the PC's. With the build on top, all ten modules are byte-identical
    to the owner's app's.
  * ☑ The setup screen and a foreground service (2026-11-20,
    09-android): `BuildActivity`, `BuildService`, kit `android-setup.py`.
    On the Thor, from the launcher with a fresh app: the dump picked in
    Android's file picker, then firmware from Sony, install, version
    check, dump and build (15.3 min), then Play, the Turnip offer, and the
    title on native code. All ten modules byte-identical to the PC's. By
    gamepad or touch; a stopped step can be tried again. No cancel button
    yet.
  * ☑ Rebuild when the modules no longer match the app: an update (a new
    `versionCode` or new tools) opens the setup again, which builds from
    the installed game and its dumps without the dump (15.3 min on the
    Thor). The saves stay.
  * ☑ The workflow's APK with the tools: a manual run on GitHub
    (2026-11-20, `0d676e5`, 25 min). The APK is 99.4 MB, release-signed,
    with the tools and `game.json`; it updated the owner's app in place
    (saves intact, straight to the game). Shipped as v0.4.0 (2026-11-21).

**Exit (v0.4.0):** with a Thor and their own dump, and no PC, a player
gets from the release's APK to a quest on native code. With a PC, D25's
route still works.

## Phase 15 — iOS and iPadOS, targeting an M4 iPad Pro (L) ☐

The owner asked on 2026-11-19: an IPA for sideloading, no App Store.
Research: [10-ios](10-ios.md). The test device is an M4 iPad Pro. The
owner's choice: as much as possible on the Mac (Xcode, the Simulator,
`devicectl`), so development needs no sideloader. Possible because the
port needs no JIT (D11, `VITA3K_DYNARMIC=OFF`).

* ☑ Survey of what the code needs (2026-11-19, 10-ios).
* ☑ How other recomps ship for iOS (2026-11-19, 10-ios): the release is
  the desktop setup with an iOS output, not an IPA ([D26](decisions.md)).
* ☐ **15a Before the iPad**: the game's resident memory measured on the
  Mac; a module for `aarch64-ios` against a stub `libSystem.tbd`. Choose
  the linker (zig's, rust-lld or LLVM's `ld64.lld`) and where the headers
  come from (zig's Darwin headers or Apple's open-source ones: check the
  licence first).
* ☐ **15b Xcode and the address space**: Xcode and a free team on the
  Mac; a test app that reserves 4 GiB as `mem.cpp` does, on the iPad,
  with and without `increased-memory-limit`. Decides whether a free
  Apple ID is enough.
* ☐ **15c The fork on the Simulator**: the CMake `iOS` branch, SDL3's
  UIKit entry point, dependencies, MoltenVK, no dynarmic; title, then a
  quest on native code.
* ☐ **15d On the iPad**: ST03A on native code; the map sweep against
  Windows' pictures; memory and frame rate.
* ☐ **15e The IPA for players** (kit, D26): the unsigned base app built
  on GitHub's macOS runners as a release asset, its executable ad hoc
  signed with its entitlements; the setup's iOS output (Windows, Linux,
  macOS) downloads it pinned, builds the modules, writes an unsigned IPA;
  release checks (reproducible zip, no personal strings, no game-derived
  files in anything published); AltStore Classic, SideStore and
  Sideloadly checked with a free Apple ID; the game data through Finder,
  Apple Devices or Files.
* ☐ **15f iPad polish**: touch and on-screen controls, gamepads, the
  lifecycle (no GPU in the background), 120 Hz pacing, thermals.

**Exit:** with an iPad or iPhone, a PC or Mac and their own dump, a
player sideloads their own IPA and gets to a quest on native code.

## Installer future-proofing: offline installs (M) ☑

The owner asked on 2026-11-23: the setup must keep working when a
download link dies, and work without a network. Before this work a
player's setup downloaded (kit `setup.py`):

| What | From | Size | Redistributable? |
|---|---|---|---|
| Firmware 3.74, `PSVUPDAT.PUP` + `PSP2UPDAT.PUP` (`fetch-firmware.py`) | Sony's `dus01.*.update.playstation.net` | 182 MB | no (Sony's, D2/D18) |
| Windows compiler (`toolchain-windows.json`): Microsoft's C++ runtime and Windows SDK, 37 payloads | `download.visualstudio.microsoft.com` | 447 MB with llvm-mingw | no (Build Tools licence) |
| … llvm-mingw | a GitHub release | (above) | yes |
| Linux and macOS compiler: zig (`toolchain-{linux,macos}.json`) | ziglang.org | 52 MB | yes (MIT) |
| Android modules from Windows: zig (`toolchain-android-windows.json`) | ziglang.org | 95 MB | yes |
| Android: adb (`android-tools.json`) | dl.google.com | ~7 MB | no (Android SDK licence) |

Python, Tk and the wheels are inside the release (`make-setup.py`); their
URLs matter only when a release is built. Every file above is pinned by
size and SHA-256, and a file already in the downloads folder with the
right hash is never fetched again. `--cache DIR` keeps the folder, so a
second install from it is offline already, but nothing fills it on
purpose, the window and launchers can't point at it, and a dead URL has
no fallback.

* ☑ **A. Bring your own files** (2026-11-23). `setup.py --offline PATH`
  (repeatable; a folder, searched four levels deep, or a single file):
  before any download, a file of the right size and SHA-256 is taken from
  there, whatever its name (kit `offline.py`; a hard link when the volume
  allows, else a copy). The game's folder's `offline/` is searched
  without being asked. The window has a "Downloaded files" folder row;
  the front end passes `--offline` on (fork). Without network and without
  a match, the error names the file, its size, SHA-256 and URL.
  `offline.py <folder>` alone lists which pinned downloads a folder holds.
* ☑ **B. An offline bundle** (2026-11-23). `setup.py --download-only DIR
  [--for windows,linux,macos,android|all]` (the front end's
  `--download-only` passes it on): everything the setup would download,
  for this platform or the ones named, into DIR in the downloads folder's
  layout with `offline.json` (file, size, SHA-256, URL), then exits; run
  again, it fetches only what is missing. The licences are accepted as for
  a build, so the player downloads Sony's, Microsoft's and Google's files
  themselves and nothing is redistributed.
  * Found on the way: Microsoft's manifest gives the four CRT VSIX
    payloads sizes that aren't their files' (CRT.Headers 14.44.17.14:
    2,128,977 listed, 2,116,223 served, SHA-256 as listed). Every check
    compares the size first, so they were downloaded again on every run,
    `--cache` too, and offline they would have failed. The lock file has
    the files' sizes now, and `toolchain.py resolve` takes them from the
    files.
  * Checked on Windows: a Windows + Android bundle (42 files, 732 MB);
    with the network blocked (a dead proxy), a fresh release folder built
    the US dump from it through `ss-delta.exe --dump ... --offline
    <bundle> --build-only` (10 min, exit 0, every file from the bundle),
    booted to the title at 60 fps on native code; `ss-delta.exe
    --download-only` filled a second bundle from the first, offline.
    Linux and macOS not run yet (the same code paths, zig's lock).
  * Checked on the Steam Deck and the M5 (2026-11-24) with the release
    workflow's archives of `c1842f3` (run 45362983839), each unpacked
    fresh, the US dump through the game's own `--dump ... --build-only`:
    * online: only the firmware downloaded (182 MB), zig from
      `setup/toolchain`; Deck 1219 s (peak 6.2 GB), Mac 333 s; the
      downloads and work files removed; booted to the title on native
      code (0 native-to-JIT calls);
    * `--download-only`: 2 files (182 MB) and `offline.json`, the
      compiler left out as the release's own. On the Mac with only
      `web.archive.org` reachable (a dead proxy, `no_proxy`) and `--for
      macos,linux`: both PUPs and Linux's zig came from the Wayback copies
      (C), checked by SHA-256;
    * offline, no network at all (Deck `unshare -rn`, the bundle as the
      game folder's `offline/`, not named; Mac `sandbox-exec` denying
      outbound IP, `--offline <bundle>`): Deck 1207 s, Mac 329 s, every
      file from the bundle, which is left intact; booted on native code;
    * no network and no file: `fetch-firmware.py` exits 1 naming the
      file, its size, SHA-256 and the three URLs tried;
    * the setup window (no arguments) starts without errors on both; its
      "Downloaded files" row was not looked at (no screen over SSH).
    * Found: the Linux and macOS release READMEs still said the first start
      downloads "a compiler (zig, about 240 MB in all)"; now the firmware
      alone (about 180 MB), as Windows' README says.
    * RecompLauncher's step replayed on the Mac (`recomplauncher.json`'s
      args: `--dump <copy> --build-only --progress`, plus the old
      `--accept-microsoft-license` a launcher may still pass): built, exit
      0, progress lines 0.02 → 1.00. Against the launcher's current
      developer guide: a run again with the same copy built everything a
      second time (329 s); now "Already built" (D24 update). The launcher
      app itself not run (it installs published releases).
* ☑ **C. Fallback URLs** (2026-11-23). Lock entries take `mirrors`
  (kit `toolchain.obtain`), the firmware `MIRRORS` (`fetch-firmware.py`),
  tried in order after the URL; a copy whose SHA-256 is wrong goes on to
  the next, and the error lists every URL. The mirrors are the Wayback
  Machine's raw copies (`https://web.archive.org/web/<timestamp>id_/<url>`)
  at snapshots whose SHA-1 (Wayback's CDX index) is the pinned file's:
  every PSVUPDAT snapshot with HTTP 200 is the file; PSP2UPDAT's
  2022-07-07 and 2025-07-15 are, but its newest (2026-02-27) is another
  file, so a mirror names a checked timestamp, never the newest. Two a
  file for the PUPs and the three zigs; PSP2UPDAT's 2025-07-15 copy and
  the Linux and macOS zigs were downloaded and their SHA-256 checked.
  With Sony's host made unreachable, `fetch-firmware.py` took PSP2UPDAT
  from Wayback. adb has no copy there (left: an archived copy, or a
  mirror of our own; Google's licence forbids redistributing it).
  * ☑ A last firmware mirror (2026-11-26, the owner's request):
    RetroBIOS's re-upload in a GitHub release
    (`Abdess/retrobios`, release `large-files`: `PSVUPDAT.PUP` and
    `PSP2UPDAT.PUP.3ae832c9`; its plain `PSP2UPDAT.PUP` is another
    revision), tried after Sony and both Wayback copies. A private
    person's copy in a release that isn't immutable, so treated as
    untrusted: `download()` now holds every URL to the pinned file. A
    different `Content-Length` is refused before reading, reading stops at
    the first byte past the pinned size, the SHA-256 is taken while
    reading, and a refused or broken download leaves no file (the Windows
    curl.exe path: `--max-filesize`, then size and hash). Checked against
    a local server (the right file, one of the same size with other
    bytes, a larger one announced or unannounced, a short one, both
    download paths), and for real with Sony's and Wayback's URLs dead:
    both files from the mirror in 28 s, hashes as pinned.
* ☑ **D. The compiler in the release** (2026-11-23). `make-setup.py`
  puts the platform's pinned zig into `setup/toolchain` (as `toolchain.py
  fetch` unpacks it, its MIT licence beside it); `setup.py` uses it when
  its version is the lock file's, else downloads as before. A player's
  setup then downloads only the firmware (and adb for Android);
  `--download-only` leaves out a compiler the release carries. The
  release archives grow by 93 MB (Windows' zip) and 85 MB (the Linux and
  macOS `.tar.gz`; the release workflow's run of 6ce7313 against 0690f8b's:
  Windows 125 → 218 MB, Linux 176 → 260, macOS 135 → 220, each with the
  92 MB APK). Not trimmed: the headers of unused targets are 34 MB of
  399 MB unpacked (zig.exe alone is 181 MB).
* ☑ **E. No Microsoft download on Windows** (2026-11-23, D32). The
  modules are built by zig for `x86_64-windows-gnu`: no Microsoft headers
  or libraries, nothing for the player to accept. The kit's clang-cl path,
  `toolchain-android-windows.json` and the Microsoft lock file are gone;
  `toolchain-windows.json` is zig, which builds Android's modules too.
  * Built: all ten modules in 10 min (as with clang-cl); each exports only
    its two entry points and imports only Windows' UCRT and kernel32.
  * Run: `ss-delta.exe` loads them, they match guest memory; the title
    menu, then quest 2 (ST03A) walked and fought through, as with the
    MSVC-built modules: 59.3 against 59.5 fps, 33,032 escapes (the fork's
    C++ `throw` through generated frames, unwound on the modules' SEH
    tables).
  * Maths: zig's software `fmaf` against UCRT's, 60 million cases (edge
    values, random bits, near-cancellation): equal but for 16 `inf × 0 +
    NaN` cases that differ in the NaN's sign, which `neon.h`'s callers
    return before reaching. `sqrt` is `sqrtss` (UCRT's is correctly
    rounded too), its result through `process_nans`.
* ☑ **F. A weekly link check** (2026-11-23). `offline.py --check-urls`
  sends a HEAD request to every pinned URL and mirror (`offline.pinned()`)
  and fails when one stops answering 200 at the pinned size;
  `.github/workflows/links.yml` runs it every Monday (and by hand), checks
  a failure again 10 minutes later, then opens an issue or comments on the
  open one. By hand 2026-11-23: 14 of 14 answer.

**Exit:** with an offline bundle made once (B) and no network, a fresh
release folder on a fresh computer builds the game from the player's
dump; and a dead primary URL is found by F before players report it.
Met on Windows 2026-11-23 (a fresh release with zig inside and the
firmware from a bundle, network blocked); Linux and macOS not run yet.

## Next release (0.6.1): from the 0.6.0 review (2026-11-26)

The review of everything since 0.5.3 (this repository, the fork
`b70141dd..f73546eb`, the kit `7a72d445..9b2a987`) found nothing to hold
0.6.0. Fixed before the tag (fork `3c2ae20c`, checked in the test folder):

* ☑ A touch kept only its changed line on an ini without `[touch]` (the
  Controls page wrote `black_rite_key` alone), and the next start dropped
  the Black Rite: a default touch now starts from its default binding.
* ☑ The settings menu and Vita3K's dialogs (`poll_overlay_input`) ignored
  second gamepad inputs, and a trigger bound to a Vita button also turned
  the menu's page as R2.

0.6.1 checklist:

* ☑ **Audio during an Ad Hoc pause**: settings mute the ports while the
  guest and audio device keep running. Full pauses still suspend the
  device. The audio test covers gain changes and new ports during mute.
  Two Windows copies stayed in a room through a 36-second settings
  pause with the host still submitting audio to SDL's dummy device.
* ☑ **`Queue::abort()` without the mutex** (fork
  `threads/include/threads/queue.h`): `wait_space()` and `push()` can miss
  its notify and block for good; at shutdown, with the display queue full,
  `process_exit`'s join would wait forever (a window of a few
  instructions). `abort()` now holds `mutex_` while changing the
  predicate. The Windows queue test exercised racing producers,
  consumers and `wait_space()` callers.
* ☑ **The pause's unit tests** (`util/tests/cooperative_pause_tests.cpp`)
  aren't built by any CMake project or CI, and cover the primitive only
  (not `pause_threads`, `run_loop`, the import handler, `process_exit`).
  CMake and the PC release jobs now run the primitive and kernel tests.
  Both passed on Windows, with a synthetic guest thread and no dump.
* ☑ **Controls page**:
  * Binding `leftstick`, `rightstick` or `guide` to a Vita button still
    presses L3/R3/PS as well (`controller_binds` keeps Vita3K's identity
    entries for them; the swap logic doesn't know them).
  * The mouse camera's `capture_key` (Tab) isn't checked for conflicts: a
    Vita button bound to Tab only captures the cursor while the mouse
    camera is on; `capture_key = MouseX1` parses but never matches
    (compared with `key_from_scancode`).
  * `bind_mouse` (`settings_menu.cpp`) takes the mouse events SDL makes
    from touches: a tap on a touchscreen PC or the Deck's desktop while a
    key cell waits binds MouseLeft.
  * Clearing both the Cross and Start keys leaves a keyboard-only player
    without a confirm in the menu (an ini edit recovers it): a fixed
    menu-only confirm key.
  * `cfg.controller_binds` is written on the main thread while guest
    threads read it during Ad Hoc Play (the game runs behind the menu):
    short writes, harmless in practice.
  * Remapped buttons now suppress their implicit action. Cursor capture
    accepts physical mouse buttons and uses middle-click when its key is
    already bound. Touch-generated clicks are ignored during capture,
    Enter confirms in the desktop menu, and controller bindings share a
    mutex with guest reads.
* ☑ **Kit `tools/toolchain.py` `obtain()`**: a source slower than 256 KB/s
  is dropped for good; if the last source (no floor) then fails, the
  download fails on a slow line that ziglang.org alone would have served.
  Retry the sources dropped for speed without the floor. Players aren't
  hit (the release carries zig, D32). Also: the curl.exe branch keeps
  `--retry 3` with `--speed-limit`, so a slow source is dropped after
  about 2 min instead of 30 s. A simulated slow primary and failed
  mirror verified the fallback. The curl speed-limited attempt runs
  without curl's retry flag.
* ☑ **Kit `install-game.py` / `setup.py`**: a stale `step-error.txt` (the
  front end removes it only when the install step finishes) can blame a
  run that crashed earlier on the previous run's licence error. PC and
  Android clear the file before invoking the front end. A Windows
  installer fixture verified the file across success and failure.
* ☑ **Kit recompiler**: `decode_arm_table` (`tools/inventory.py`) takes the case
  count from the last `cmp` without checking it was on the index register
  (the Thumb `word_table_parts` does); a stale compare sends a valid index
  to `default: unsupported`. No unit tests for `vuzp`, fixed-point `vcvt`
  or `arm_mov_imm16`. Not reachable for ss-delta (its modules generate
  the same code with and without these changes). The decoder checks the
  index register, and the synthetic tests pass on Windows and Linux.
* ☑ **Release workflow**:
  * Configure-time downloads (FFmpeg prebuilts, curl through
    FetchContent, MoltenVK and OpenSSL on macOS) run without a timeout,
    outside `ci-retry.py` and the cache: a GitHub stall can hold a job to
    its 120 min limit.
  * Gradle's plugin and dependency downloads (the `android` job's "Pack
    and sign the APK") have no retry and no cache: run 52 (2026-11-26)
    failed there, "Plugin [id: 'com.android.application', version:
    '9.2.1'] was not found" (Google's Maven, which served it again
    minutes later), and the PC jobs, which wait for the APK, with it.
    Cache `~/.gradle` and retry the step, or resolve the plugins in the
    download phase.
  * `mozilla-actions/sccache-action` is pinned by tag, in jobs with
    `contents: write`, `id-token: write` and (Android) the signing
    secrets: pin it by SHA.
  * `tools/ci-wait-job.py` treats a 401/403 as a passing error and polls
    for 85 min before failing.
  * The workflow now caches the configure dependencies and Gradle,
    bounds and retries downloads and builds, and pins sccache by commit.
    The job waiter fails early on a permanent GitHub API error. The
    workflow files were checked locally. The next draft will exercise
    the changes on the hosted runners.
* ☑ **rePatch**: a zip with a rePatch folder whose game sits at the root as
  `PCSA00152/` (no `app/`) still gets only the mod installed. A scratch
  Windows install verified both the base game and mod installed into
  their own directories, even with a `param.sfo` inside the mod.
* ☑ **A toolchain smoke test in the release workflow**: CI never compiled
  anything with the toolchain it ships (the game's code can't be in CI),
  so a broken zig, a lost flag or a missing file passes CI and is found
  by the symbol check or the front end's load message on a player's
  machine, or by the manual draft checks (BUILDING, "Before publishing a
  draft"). A tiny synthetic ARM module from the kit's own test code,
  recompiled and built by each job with the release's own zig and flags
  (Windows, Linux, macOS, Android): position-independent with no text
  relocations, only the two entry points exported, Android's symbol
  check passed, and on the PC targets loaded and run for a known result.
  The APK's on-device build tools (aarch64 Android binaries) can't run on
  an x86 runner, so the Thor check stays for that path.
  The workflow includes the test on all four targets. It ran on Windows,
  Linux and Apple Silicon macOS. The Android ELF cross-build passed its
  symbol and relocation checks. The native macOS run used the pinned
  release Python and Zig and passed strict signature verification, the
  two-export and relocation checks, and the load and execution checks.
* ☑ **Quest frame rate on this PC, unfocused**: in the 0.6.0 draft check
  ST16A ran at 32-33 fps on Windows (the 760M, window not focused, as
  v3kdrive leaves it), the release build and the dev build alike (both
  native code, 0 native-to-JIT calls), where ST03A had shown 59.3 (D32).
  Find out whether ST16A's rain costs that on the 760M or an unfocused
  window is throttled (focused run, GPU clocks), and record it in
  02-baseline. The foreground RDP run held at 31–33 fps. On the physical
  console, ST16A measured 56 fps median with and without focus, with
  WDDM engine clock medians of 948 and 967 MHz. Foreground ST03A measured
  59.5 fps median at 1,017 MHz.
* ☑ **`--android` and a running adb server**: setup uses installed SDK
  adb when available. If it needs the bundled version and detects a
  server, it warns about a possible version conflict. Windows
  `--android --push-only` installed a scratch APK and copied its ten
  modules with the SDK's 37.0.1 daemon and wireless Thor transport intact.
* ☑ **The firmware's size**: the Android setup screen now says about
  180 MB, matching the PC readmes and release notes.
* ☑ **#26 on Android**: the Thor's built-in pad bound RT as the second
  D-pad Up input through Controls. Both physical inputs opened the
  Support Spell overlay in ST03A with Giant's Arm active, using
  `sendevent` with the app focused on display 0.
* ☑ **Ad Hoc WAN latency and loss spike** (16a.0 in [11-online](11-online.md)):
  measure the existing `lan` + VPN path with clumsy / `tc netem` at
  50/100/200 ms RTT and 1–5 % loss through a full quest; look for the
  ~24 ms XLink Kai ping patch's eboot change (`overrides/eboot.json` fix in
  0.6.1 if a limit shows up and passes a quest); record Ad Hoc socket types
  and whether `adhoc_matching` payloads carry IP addresses (`net_trace`).
  Both Deck copies cleared a regular quest at 50 ms RTT / 1% loss
  and 100 ms / 3%. Both cleared the *Founder in Forest* Blank Page at
  100 ms / 3%, with matching 1:59 results. At 200 ms / 5%, all four
  cleared a quest after one guest rejoined the room. On an earlier run
  the fourth guest stayed in combat after the others cleared. Matching
  used P2P datagrams with peer IPv4 addresses in the payload. Measurements
  are in [11-online](11-online.md).
* ☑ **30-vs-60 fps constant-scan check** (Phase 8 above,
  [01-research](01-research.md)). With the D30 overrides loaded, the
  Firebird Pinion+ cast moved about ten units at both rates. The same
  journal page advanced at real time, the Fire Dragon Egg had similar
  active times and Red Hood's chains lasted a median 1.605 and 1.596
  seconds in the moving state. No new timing bug was confirmed in
  these runs.

## Phase 16 — Online multiplayer without a VPN (overlay first, Play Online later) ☐

Design and breakdown: [11-online](11-online.md). Inspired by
[Project Nativ](https://github.com/TheLostPantheon/nativ)'s GPL-2.0-or-later
networking stack (fork only, never into MIT-licensed `third_party/recomp`).
Staged in two decoupled halves: Part 1 needs no extra firmware modules,
and its single-WAN-port vport mux, session-wide virtual IPs, loopback bridge
and guest-agnostic `vita3k/net/online/` library are what Part 2 builds on.

**Prerequisites:** the 0.6.1 Ad Hoc pause audio and `Queue::abort()` items
are closed (same code paths); 16a.0 (scheduled in 0.6.1 above) passes.

### Part 1 — P2P overlay under Ad Hoc Play (L, ~12–20 sessions) ☐

* ☑ **16a.0 Latency and loss spike (go/no-go, before overlay code)**:
  on hardware, Ad Hoc needed an eboot patch for a ~24 ms XLink Kai ping
  limit. Measure the existing `lan` + VPN path with clumsy / `tc netem` at
  50/100/200 ms RTT and 1–5 % loss through a full quest; look for the
  XLink Kai patch's eboot change; record Ad Hoc socket types (datagram vs.
  `SOCK_STREAM_P2P`) and whether `adhoc_matching` payloads carry IP
  addresses (`net_trace`). The regular and Blank Page clears passed
  the 100 ms playability gate with the existing LLE hook.
* ☐ **16a.1 Transport library** (`third_party/vita3k/vita3k/net/online/`):
  port/adapt the encrypted P2P overlay (session-wide `198.18.0.0/15`
  virtual IPs derived from public keys, single-WAN-port vport framing,
  hole punching, relay client; reliable streams required if 16a.0 finds
  `SOCK_STREAM_P2P`), Monocypher X25519 + XChaCha20-Poly1305 crypto, LAN
  multicast discovery, Mainline DHT rendezvous (topics namespaced by
  protocol version, game ID, compatibility version and `adhoc`/`m2`), STUN
  and UPnP; build across Windows, Linux, macOS and Android NDK, with
  standalone unit/fuzz tests.
* ☐ **16a.2 Relay (decide before 16a.1)**: hosted community relay,
  self-hostable daemon via `[multiplayer] relay`, or both (cost, abuse,
  rate limits); required for symmetric and carrier-grade NAT. Configurable
  DHT bootstrap nodes, with the relay as a rendezvous fallback.
* ☐ **16a.3 Vita3K socket & Ad Hoc NetCtl integration**: in `network =
  online`, guest P2P sockets keep real host UDP sockets on `127.0.0.1` and
  a loopback bridge forwards them to the overlay; `P2PSocket`
  (`p2psocket.cpp`) only translates virtual IP + vport ↔ loopback port, so
  `Epoll`, receive timeouts and `sceNetSocketAbort` stay unchanged.
  `SceNetCtl`'s Ad Hoc peer thread uses the session virtual IP and a
  virtual broadcast address. `local`, `lan` and VPN `peers` modes (and
  utakata) stay intact.
* ☐ **16a.4 Frontend settings, consent & Android permissions**: opt-in
  `network = online`, `room_code` (generated high-entropy codes by
  default, KDF into the DHT topic and handshake PSK; no public lobby in
  Part 1), `relay`, opt-in `upnp`, a status line on the Multiplayer page,
  and a first-use notice that peers, the DHT and the relay see the
  player's IP; Android network/multicast permissions and lifecycle;
  update [ONLINE-PLAY](ONLINE-PLAY.md) with a privacy note.
* ☐ **16a.5 WAN & cross-platform verification**: `--player 3`/`4`
  loopback, LAN multicast, cross-NAT hole punch, forced relay at the
  latency and loss 16a.0 passed, across Windows, Steam Deck, macOS and
  Android (Wi-Fi and mobile hotspot), US ↔ EU.
* ☐ **16a.6 Security review**: bounds, amplification and peer-table audit
  of all untrusted-packet handlers before release; the bridge forwards
  only authenticated peers of the current room.

**Exit (Part 1):** two players on separate home networks with no VPN
installed set `network = online` with a shared `room_code`, find each
other in **Ad Hoc Play** and complete a quest, both direct hole-punched
and via relay.

### Part 2 — Later transition to full Play Online via NP Matching2 (L–XL) ☐

Triggered if in-game room passwords/filters, lobby text chat, kick, host
handover, a working **Play Online** button or `SceLibRudp` WAN transport
are needed (or if 16a.0 finds a latency limit with no patch). Reuses Part
1's overlay, virtual IPs and vport mux; room search across the internet is
new work (Nativ's Matching2 service is local per host).

* ☐ **16b.1 Gatekeeper spike (JIT)**: flip `cfg.offline` off in a test
  run, LLE `np_matching2` / `np_common` / `libssl` / `librudp`, trace
  **Play Online** with `SSD_TRACE_IMPORTS=1`, and check `STN001`
  online-pass entitlement, `SceNpUtility` (`WordFilter`), `SceNpBasic`,
  `SceNpTus`, `SceNpScore`, US ↔ EU `comm_id`, and firmware 3.74
  dependencies (`np_signaling`, `libhttp`).
* ☐ **16b.2 LLE & static recompilation**: implement missing internal
  imports, dump and pin `load_bases` for the 4+ firmware modules (~455 KB+
  vs. 14 KB for `adhoc_matching`), fix any new recompiler forms with
  dynarmic tests, and add incremental module compilation in `setup.py` so
  upgrades don't rebuild `eboot`.
* ☐ **16b.3 Fork NP / HTTP / SSL / NetCtl runtime**: split `cfg.offline`
  to intercept Sony hosts locally, serve the local HTTPS matching-server
  list with `libssl` cert trust, implement PSN tickets + `STN001`
  entitlement (`SceNpCommon`), `SceNpManager` signed-in state/region,
  `sceNetCheckDialog` PSN mode, `sceNetCtlGetNatInfo` (NAT type 1), and
  clean stubs for `WordFilter`/Basic/Tus/Score.
* ☐ **16b.4 Matching2 server, room directory & room proxy**: port
  `m2_wire`, `m2_server`, `m2_rooms`, `m2_proxy` and `basic_msg` onto
  Part 1's overlay (`m2` service tag), design a distributed room directory
  for `SearchRoom` / `GetWorldInfoList`, and cover Soul Sacrifice Delta's
  26 `SceNpMatching2` imports (world list, room external/internal data,
  chat, kick, owner handover).
* ☐ **16b.5 Frontend UX, pause & security**: `[multiplayer] online_id`,
  keep the game unpaused during Play Online in fork
  `app/src/session_controller.cpp`, and restrict guest-bound packet
  forwarding to authenticated room peers.
* ☐ **16b.6 End-to-end verification**: public & passworded rooms, search
  filters, lobby chat, kick, host handover, full quest, US ↔ EU, across
  Windows, Steam Deck, macOS and Android (direct + relay), with Ad Hoc Play
  still working alongside.

**Exit (Part 2):** two players on separate networks (no VPN, native code
without dynarmic) use **Librom → Network → Play Online** to create/find a
room, chat, complete a quest and survive host handover across all four
platforms.

## Later (deferred)

* Modding hooks: C++ function overrides, plus loose files (the engine
  already prefers loose files when `PackFileFirst false`).
* Key bindings in the settings menu
  ([#24](https://github.com/vita-recomps/ss-delta/issues/24); asked for by
  a RecompLauncher user, 2026-11-25). Until then `[keyboard]`, `[gamepad]`
  and `[touch]` could only be changed by editing `ss-delta.ini`
  (INSTALLING, "Controls"). Done 2026-11-25 in the shared front end
  (`game-frontend/settings_menu.*`, `input.*`, `button_labels.*`), so
  every game on it has them.
  * ☑ A Controls page (after Audio; on Android after the on-screen
    controls on the same page): each Vita button with its key, second key
    and gamepad button, then the `[touch]` bindings (Black Rite), then
    Reset all controls (Cross twice). Left/Right pick the column, Cross
    waits for the new key or button (raw SDL input from the front end; Esc
    cancels, 6 s timeout), Square clears, Triangle restores that row's
    defaults. A key or button another control has changes places with it.
    Changes are applied at once (`apply_bindings`, `Touches::configure`)
    and written to the ini; an empty `[gamepad]` value now unbinds, as an
    empty `[keyboard]` one already did. The defaults are one table
    (`button_bindings()`), which also writes the default file's lines. The
    sticks and LT/RT (L2/R2) are shown, not editable (since #26 LT/RT can
    be any Vita button's input as well, below). The menu's
    own hints name the keys bound now. Checked on Windows 2026-11-25 with
    posted keys in a test folder: rebinding, the swap and its note, a new
    key working in the menu at once, Esc, a mouse side button on the Black
    Rite, Reset all, the ini after each. Checked on the Thor the same day
    (a test package, its built-in pad through `sendevent`): the page
    shows the gamepad column only, without the stick and L2/R2 rows; a
    real pad's button rebinds, swaps and restores; Back cancels a wait.
    It found a button that, still held as its own binding changed,
    pressed another Vita button (a cleared binding): the menu now ignores
    its buttons for 350 ms after a change (fork `d470d46a`). Not checked:
    a trigger into a touch's gamepad cell.
  * ☑ Mouse buttons as bindings: `MouseX1`, `MouseX2` (side buttons)
    always; `MouseLeft`, `MouseRight` only while the mouse camera has the
    cursor (the touchscreen otherwise; let go when the cursor is
    released). Middle stays the capture. Key codes of their own on HID's
    Button page (0x09xxxx) beside the keyboard's, so `[keyboard]` and
    `[touch]` take them like keys.
  * ☑ Keyboard button prompts: `[game] button_labels = keyboard`, each
    symbol a keycap (rounded outline) with the first key `[keyboard]`
    binds, in the ink blot; START/SELECT's keycap half again as tall as
    the word; the font page's ○ △ □ in a keycap instead of a ring. The
    stroke font grew A-Z, 0-9, punctuation and arrows; long names have
    three-letter forms (SPC, ENT, SHF, TAB, CTL, ALT, BS, ESC, F12, M4).
    `auto` follows the device used last (a key or mouse click: keyboard; a
    gamepad: its letters or PlayStation's), before any input the connected
    gamepad's, keyboard without one (Android: PlayStation's). The prompts
    follow a Controls page change at once (the labels read `[keyboard]`
    each tick). Checked: every atlas, tutorial picture and the font page
    with `--button-labels-test` (`--set game.button_labels=keyboard`), all
    glyphs at 3x; `auto` switching from Xbox to keyboard on a key press in
    the log; the keycaps in play in the journal and a quest (the owner's
    and the test runs). A click SDL makes from a touch or pen doesn't
    count as the mouse, and on Android no key does (Back and a device's
    extra buttons arrive as keys): on the Thor `auto` stayed Xbox through
    Back presses (fork `5974c744`).
  * ☑ Nintendo and Android handheld button prompts (2026-11-26):
    `[game] button_labels = nintendo` (a Switch Pro Controller's: face
    buttons by position, south B, east A, west Y, north X, in white; L, R,
    and + / − for START and SELECT, glyphs as big as Xbox's Menu and View)
    and, on Android only, `handheld` (the same letters, L1 and R1, and
    Xbox's Menu and View: the Retroid Pocket's, AYN's and other handhelds'
    built-in controls). `auto` takes `nintendo` for a pad whose SDL labels
    are Nintendo's; never `handheld`, as those built-in pads report Xbox
    labels (the Thor's is an "Xbox Wireless Controller"). A desktop ini
    with `handheld` is ignored with a warning. Checked: every atlas,
    tutorial picture and the font page with `--button-labels-test`
    (`--set game.button_labels=nintendo`) at 3x; on the Thor (test
    package, NDK build plus Gradle), `handheld` in the hub, the journal
    (Lore, Tactical Advice's picture, Portraiture) and Select Offerings
    (B, A, Y, X, R1, Menu, View; the font page redrawn per the log, its
    letters not seen on screen), the
    settings menu listing Android handheld, and a live switch to
    `nintendo` there (+, −, R). Fork `12d08f73`.
  * ☑ Two gamepad inputs per Vita button, and the triggers as bindings
    ([#26](https://github.com/vita-recomps/ss-delta/issues/26), 2026-11-25:
    RT as a second D-pad up, for the support spells in combat, with the
    D-pad kept for the menus). Done 2026-11-26 in the shared front end:
    `[gamepad]` takes up to two inputs per Vita button, triggers included
    (`up = dpup, righttrigger`), and so does a touch's `_gamepad`. The first
    button stays in upstream's `controller_binds` (one slot per button);
    the rest go into `CtrlState::extra_gamepad_binds` (the Vita button's
    basic and extended bits), which `ctrl.cpp` `apply_controller` reads
    beside its L2/R2 check, so the game's pad read sees them with no frame
    of delay. The triggers still press L2/R2 too: harmless outside PS TV
    mode (the game reads L2/R2 only in its PS TV branches, 01-research),
    both with `pstv_mode`; the Controls page says so when a trigger is
    bound. The Controls page has a fourth column, Second button (Android:
    the two gamepad columns); a trigger is captured like a button on any
    row, and a swap moves inputs between cells as for keys. Button prompts
    got LT/RT (ZL/ZR, L2/R2) labels for a Vita button whose first input is
    a trigger. Checked on Windows 2026-11-26 in the test folder with a
    virtual SDL gamepad (new: v3kdrive `gpad:`, the input pipe's
    `gamepad`): in a quest RT as a second D-pad down toggled Mind's Eye on
    and off as the pad's D-pad down did; on the Controls page LT captured
    into D-pad up's second cell (swapped with the Black Rite's, note
    shown), LT moved to D-pad down live (RT then no longer toggled Mind's
    Eye, LT did), Square, Triangle, Reset all, the ini after each. Not
    checked: Android (built-in pad, `sendevent`), and the support spells
    themselves (the first quest has no use for D-pad up).
* ☐ **Wider screens** (phones at 19.5:9–21:9, ultrawide monitors)
  ([#28](https://github.com/vita-recomps/ss-delta/issues/28), 2026-11-25:
  a player got the 3D proportions right on a phone with Codex, but the
  menu page animations broke; asked for their changes, device and
  screenshots). Today the 960×544 image (16:9) is pillarboxed. Needed:
  * ☐ A wider image: the game's display buffers, render targets,
    viewports and scissors are 960×544 (about 1216×544 for 20:9).
    **Hypothesis**: the `ResoDown` switch between 720×408 and 960×544
    (D13) is the place for another, wider mode. #29 found four modes
    there (640×368 and 480×272 too; 01-research, "The 3D resolution
    modes", not checked yet).
  * ☐ Hor+ 3D: the projection's horizontal field of view widened, the
    vertical kept; culling checked on every map (**hypothesis**: it
    follows the projection).
  * ☐ The 2D layer is laid out in 960×544, and menu pages slide in from
    just past its edges, which a wider screen shows (very likely #28's
    animation bug). Clip it to the centre 960 columns, or anchor the HUD
    to the new edges; full-screen 2D (loading screens, fades, movies,
    backgrounds) pillarboxed or stretched.
  * ☐ Post-processing with fixed UV scales (as the depth of field in fork
    patch 0033).
  * ☐ Touch mapped back to the game's 960×544; the Android on-screen
    controls, which sit mostly in the bars now, then cover the picture.
  * ☐ An option, off until the map sweep and the menus pass at 16:9,
    19.5:9, 20:9 and 21:9; on Android the screen's shape by default.
    Fixes through `overrides/eboot.json` (D30) and the fork.
* **The game pauses behind the settings menu**
  ([#29](https://github.com/vita-recomps/ss-delta/issues/29), 2026-11-25:
  a player's Android build; 02-baseline, "The settings menu's pause"):
  * ☑ The menu (2026-11-26): ELLINDON's cooperative pause, PR
    vita-recomps/Vita3K#1, merged with our fixes as fork `5e241028`.
    Checked on Windows (native code, both JIT modes, quest, loading
    screen, movie, closing while paused) and on the Thor.
  * ☑ Ad Hoc Play keeps the game running behind a pause: a copy paused
    for 20–30 s was dropped from the room.
  * ☑ Android: the game pauses while the app is in the background
    (2026-11-26, fork `41475130`): it went on there at more CPU than in
    front; on the Thor 240% → 11%.
* **Offered in #29** (ELLINDON's Android build), welcome as separate PRs:
  * ☐ A diagnostics export on Android (the setup's and the game's logs,
    the device, shared through a content provider).
  * ☑ An FPS counter (2026-11-26, fork `fbb38768`): `[display]
    fps_counter`, Vita3K's performance overlay at its four detail levels,
    live from the menu, on every game's Display page.
  * ☐ A layout editor for the on-screen controls (09-android, "Not yet"),
    floating sticks, combos, buttons that touch a screen point.
  * ☐ Driver import from a zip, and back to the system driver after a
    launch with a custom one crashed.
  * ☑ Android's setup from PUP files the player has (2026-11-26, fork
    `0f6a57eb`; PC: `--offline`, "Installer future-proofing"): Add firmware
    files, checked against fetch-firmware.py's sizes and hashes, put where
    the firmware step keeps them; the one not given is downloaded.
  * Not taken: 24/40/45 fps targets (uneven on a 60 Hz vblank, the game's
    speed unproven), an APK with game modules in it (D2).

## Unplanned

* XLink Kai compatibility, ad hoc play against real Vitas over the
  internet (owner, 2026-10-13). Ad Hoc Play between copies of the port, on
  one PC or in a LAN, is Phase 10.

---

## Risk register

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | NEON/VFP semantics wrong (Havok physics, 17.7% of code) | desyncs, broken physics | differential testing vs. dynarmic per op and per function; bit-exact estimate tables |
| R2 | Generated code too large to compile (3.8M instructions; flags) | slow builds, out of memory | flag liveness, 64 KB buckets, ccache, 3 jobs on 16 GB |
| R3 | Hidden control flow (`pop {pc}` dispatch, tail calls, mode switches) | crashes in native code | the dynarmic fallback catches misses; Phase 2 inventory |
| R4 | Vita3K renderer bugs (Vulkan crash on AMD, overexposure, Mind's Eye) | unplayable or ugly | Phase 1 root cause; Vita3K-Plus fixes; Phase 7 |
| R5 | Threads/ULT/callback integration with Vita3K's kernel | deadlocks, crashes | keep Vita3K's thread model in the hybrid; fibers only in Phase 6 |
| R6 | Firmware modules (fonts, AvPlayer) are Sony code run as LLE | can't drop the PUP dependency | FFmpeg for FMV; pvf/ft2 recompiled locally or replaced |
| R7 | Frame-locked game logic | no 60 fps | treat 60 fps as optional; logic steps by frame time, loading screens kept at 30 ([D16](decisions.md)) |
| R8 | GPL (Vita3K) | the runtime can't be relicensed | keep this repo and `third_party/recomp` MIT-licensed, `third_party/vita3k` GPL-2.0-or-later, and ship no game-derived code ([D2](decisions.md), [D17](decisions.md), [D18](decisions.md)) |
| R9 | First Vita recomp: no prior art to copy | slower progress | borrow patterns from PSP recompilers (Yakumo's psprecomp fallback), N64Recomp/XenonRecomp (lookup tables), 3dsrecomp (verify mode) |
| R10 | A download the setup needs disappears (Sony's update servers, ziglang.org, Google's adb) | new players can't build the game | offline files matched by hash, offline bundles, fallback URLs, a link check ("Installer future-proofing") |
