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

## Phase 1 — Vita3K from source (M) ☐

We will patch Vita3K heavily, so we need our own build and a debugger on it
first.

* ☐ Clone Vita3K with submodules into `third_party/vita3k` (our fork; vendor
  vs. submodule as in decimation D6). Pin the commit in
  [decisions](decisions.md).
* ☐ Build with VS 2022 / clang-cl + Ninja.
  * loktar00's `port/build/vita3k-msvc1441.patch` notes MSVC 14.41 issues.
  * Check them against our MSVC 14.44.
* ☐ Debug build, plus RelWithDebInfo with PDBs. Our build boots the game to
  the title on OpenGL.
* ☐ **Root-cause the Vulkan crash** on the Radeon 760M: break on the access
  violation and get the call stack.
  * Fix it, or record a workaround, and report it upstream if it is
    Vita3K's bug.
* ◐ Vita3K-Plus.
  * ☑ The v1.2 binary boots on Vulkan here and fixes the black blocks and
    white floors ([02-baseline](02-baseline.md#vita3k-plus-v12-2026-10-09)).
  * ☐ Decide whether our fork starts from Vita3K-Plus instead of upstream.
    Its source is GPL-2.0 too. Diff it against upstream to see how far it has
    diverged.
  * ☐ Find which Plus change avoids the AMD Vulkan crash.
  * ☐ The Vulkan cloak speckle.
* ☐ Collect the RTX 4090 test results (`dist/ss-delta-vita3k-test.zip`,
  `run-matrix.bat`) and record them in [02-baseline](02-baseline.md).
* ☐ Real input for automated runs.
  * Options: a test-only key-injection hook in our fork (preferred: no focus
    stealing), or an SDL virtual joystick.

**Exit:** our own Vita3K build reaches gameplay on Vulkan on this machine, and
input can be scripted.

## Phase 2 — Static analysis and inventory (M) ☐

* ☐ `tools/inventory.py` writes `generated/inventory/*.csv` for the eboot and
  the three modules worth recompiling (libc, libfios2, libult):
  * **`functions.csv`:** every exidx start, its mode (Thumb/ARM), end
    address, NEON/VFP count and call/return counts.
  * **`jumptables.csv`:** every `tbb`/`tbh` with its decoded case targets.
  * **`indirect.csv`:** every `blx reg` / `bx reg` / `pop {pc}` site, split
    into `movw/movt` far calls and true indirect calls.
  * **`imports.csv`:** the stub address → library/NID/name map.
* ☐ Ghidra 12.1.3 + VitaLoaderRedux project built headless from
  `extracted/elf/` (`tools/ghidra_analyze.ps1`), with names from the vitasdk
  NID db.
  * Use it to cross-check function boundaries (exidx vs. Ghidra) and for
    hand analysis.
* ☐ Answer the open research questions that affect the recompiler:
  * `pop {pc}` used as dispatch;
  * tail calls across exidx boundaries;
  * ARM/Thumb switches through pointers;
  * the 703 exidx entries with the Thumb bit clear (ARM code vs.
    CANTUNWIND/data).
* ☐ Find the frame-step logic behind `FPS 30` (for later 60 fps work) and the
  GXM call sites that set render-target sizes (for resolution scaling).

**Exit:** a complete function list. 100% of exidx entries are classified, and
every indirect-flow site is resolved or explicitly listed as dynamic.

## Phase 3 — Recompiler v0: integer + VFP scalar (L) ☐

The tool lives in `third_party/` or `recomp/` (our code). It never ships game
data; it reads `extracted/elf/` and writes `generated/`.

* ☐ **Decoder.** Capstone for Thumb-2/ARM is fine offline, since speed is
  irrelevant. Keep a thin layer of our own, so that operand semantics
  (shifts, writeback, `IT` state) are explicit.
* ☐ **Guest context.**
  * `r0–r15`;
  * NZCV/Q/GE flags;
  * `d0–d31` as a union with `s`/`q` views;
  * FPSCR;
  * TPIDRURO (TLS);
  * exclusive monitor state.
* ☐ **Emitter.** One C++ function per guest function, with one statement
  group per instruction.
  * Write flags only where a later instruction reads them, using a per-block
    liveness pass. Otherwise expect huge sources.
  * Memory is accessed as `base + (uint32_t)addr`, matching Vita3K's
    4 GiB reservation.
* ☐ **Control flow:**
  * `bl`/`blx #imm` become direct calls;
  * a call to an import stub becomes the HLE thunk;
  * `tbb`/`tbh` become `switch`;
  * `IT` becomes `if`;
  * `blx reg` / non-matching `pop {pc}` go through `LOOKUP_FUNC(addr)`;
  * `ldrex`/`strex` become host CAS.
* ☐ Functions containing NEON or ARM-mode code are marked "dynarmic" in v0.
* ☐ **Per-instruction test suite.** Random inputs, our generated code
  vs. dynarmic executing the same instruction (dynarmic is 0BSD and
  embeddable standalone).
* ☐ Measure the generated size and the compile time / memory per job for the
  whole eboot. Split into buckets of about 64 KB of guest code each, as in
  decimation.

**Exit:** C++ for every non-NEON function compiles; the instruction suite
passes; size and compile time are recorded.

## Phase 4 — Hybrid runtime in the Vita3K fork (L) ☐

* ☐ **AOT dispatch.**
  * Before dynarmic runs a block at a function entry, look the address up in
    the AOT table and call native code if present.
  * Native code calling a missing guest address runs dynarmic with LR set
    to a sentinel, then returns.
* ☐ **HLE from native code.** Call Vita3K's `export_*` bridges with a
  `CPUState` view of our guest context. Either keep one register layout or
  copy at the boundary.
* ☐ **Threads.** Each Vita3K guest thread (host thread) owns a guest context
  that native code and dynarmic both see.
  * Callbacks (`run_callback`, the GXM display queue) enter native code when
    the target is recompiled.
* ☐ **Differential mode.**
  * Per call: snapshot the context, run native, re-run on dynarmic against a
    shadow, and compare registers plus written memory. Log mismatches.
  * It is switchable per function and sampled, because it is slow.
* ☐ Counters for the share of guest instructions run natively vs. on
  dynarmic, per function.

**Exit:**

* boot to the title with the AOT build loaded;
* at least 80% of executed guest instructions native at the title;
* zero differential mismatches over 1,000 frames of `ELDER DEFAULT MAP` idle.

## Phase 5 — NEON, ARM mode and the bundled modules (L) ☐

* ☐ **NEON layer** on SIMDe or hand-written SSE4.1/AVX2.
  * Must match ARM semantics: flush-to-zero and default NaN where FPSCR says
    so, saturation, and `vrecpe`/`vrsqrte` estimate tables bit-exact.
  * Unit tests against dynarmic, per op.
* ☐ The 27–29 ARM-mode functions.
* ☐ Recompile `libc`, `libfios2` and `libult` with the same tool. They are
  separate corpora at their own load addresses; record the load addresses
  Vita3K picks, or fix them.
* ☐ Differential runs through quests via the debug Stage Select (561 quests,
  all reachable through `BootSequence Quest Select`).

**Exit:** a full quest with **zero dynarmic entries** in `efg`, libc, fios2
and ult, and a clean differential log.

## Phase 6 — Standalone runtime (L) ☐

* ☐ A single-game executable: SDL3 window, no Qt GUI, no app list, fixed
  config, and its own `ss-delta.ini` (like `decimation.ini`).
* ☐ **libult** on host fibers behind its 13 imports (or keep the recompiled
  libult on top of a native `SceFiber`).
* ☐ **Stubs.** All NP/Net/Http/Ssl/Adhoc/Sns/Smart/Camera/Near imports
  return clean "offline" results. No `sceNpAuthInit` dialogs.
* ☐ **Firmware LLE modules.**
  * Decide per module whether to HLE it natively or keep it as recompiled
    guest code: fonts (pvf/ft2), AvPlayer/Mp4 (FMV is H.264/AAC MP4, so FFmpeg
    can replace it), fiber.
  * Firmware code is Sony's. Any recompiled firmware module is generated
    locally from the user's PUP, like the game.
* ☐ **Install flow.**
  1. Take the user's NoNpDrm zip/folder.
  2. Decrypt PFS + SELF.
  3. Verify hashes ([hashes](hashes.md)).
  4. Generate and compile.
  5. Lay out `app0:` on disk.
* ☐ dynarmic stays as an optional build flag for debugging only.

**Exit:** `ss-delta.exe` boots from the user's own dump to a quest, with no
Vita3K GUI and no dynarmic.

## Phase 7 — Rendering correctness (L) ☐

* ☐ Fix the overexposure and black blocks seen in the baseline on both
  backends. Start with surface sync and `high-accuracy`, then fog/particle
  blending.
* ☐ Mind's Eye overlay (monster HP, soul shards).
* ☐ Every quest map renders correctly (spot check through Stage Select).
* ☐ Async pipeline/shader compilation at install time: translate every GXP
  the game ships ahead of time, so there is no in-game stutter.

**Exit:** a visual sweep of all maps and cutscenes with no known rendering
bugs.

## Phase 8 — PC features (M) ☐

* ☐ **Internal resolution.**
  * Raise the 720×408 render target (the VitaGrafix sites
    `0x818282A6`/`0x818282AC` and the UV-scale floats) to a multiple of the
    output, and combine with Vita3K's resolution multiplier.
  * Widescreen/aspect handling.
* ☐ Remappable keyboard/controller input (SDL), plus touch/rear-touch
  substitutes for the features that need them. Mouse camera is optional.
* ☐ 60 fps study. Find the frame-locked logic first; ship only if it is safe.
* ☐ Saves:
  * stored on the PC;
  * import of real Vita saves;
  * DLC entitlement flag (the DLC data ships in 1.30).

**Exit:** a full playthrough is possible on keyboard/controller at
≥ 2× internal resolution.

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
