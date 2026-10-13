# Decisions

Irreversible or expensive choices, newest last.

## D1 — Hybrid: AOT-recompiled code inside a Vita3K fork, dynarmic fallback (accepted, 2026-10-10)

**Context:** [01-research](01-research.md#approach-options).

* No mature Vita recompiler exists, but Vita3K already runs the game.
* GXM and the USSE shader translator are the hardest parts of Vita emulation,
  and Vita3K has both.
* The first frame is reachable only through indirect calls, so there is no
  "recompile a small static subset" milestone.

**Decision:**

* Write our own Thumb-2/ARM → C++ recompiler.
* Run its output inside a Vita3K fork that dispatches to native code by guest
  address.
* Use dynarmic as the fallback and as the differential oracle.
* Shrink to a standalone runtime once coverage is complete
  ([plan](03-plan.md) Phases 3–6).

**Consequences:**

* The runtime is GPL-2.0-or-later (Vita3K).
* Thread, callback and HLE integration follow Vita3K's model until Phase 6.

**Status:** accepted by the owner on 2026-10-10, after Phase 2. The
inventory ([04-inventory](04-inventory.md)) supports the choice: the
function list is complete, game code has no exception landing pads, and the
dynamic indirect calls (26 k) and the few unexplained data pointers are
exactly what the dynarmic fallback is for.

## D2 — Nothing derived from the dump or firmware is committed (accepted, 2026-10-09)

**Decision:** none of the following go into git:

* extracted or decrypted files;
* ELFs;
* generated C++;
* Ghidra databases;
* screenshots or logs of the game;
* licences (RIF/work.bin);
* firmware.

Hashes, addresses, names and notes are fine. This is the same rule as
decimation D3.

**Consequences:**

* Every build regenerates from the user's own dump and firmware.
* The project stays private and non-distributed, which also keeps the GPL
  question moot.

## D3 — Target the merged US 1.30 build (accepted, 2026-10-09)

**Decision:** all analysis and the port target PCSA00152 at 1.30: the base
app plus the merged patch, eboot module NID `0xD66AEBF4`.

**Why:**

* It is the final version.
* It contains the post-launch content (Odin, Bahamut, collaboration
  costumes), and reportedly the DLC data.
* The VitaGrafix and XLink Kai patches exist for it.
* loktar00's numbers are for 1.10, so their addresses don't apply.

## D4 — OpenGL is the Vita3K reference backend on the dev machine for now (accepted, 2026-10-09)

**Context:** [02-baseline](02-baseline.md). Vulkan crashed at boot on the
Radeon 760M in all three runs; OpenGL reaches gameplay at 30 fps, with
rendering bugs.

**Decision:** baseline runs and early behavioural comparisons use OpenGL.
Rendering comparisons wait until Phase 1 fixes Vulkan, or until they can be
run on the RTX 4090 PC.

**Revisit:** when the Vulkan crash is understood.

**Update (2026-10-09):** Vita3K-Plus v1.2 boots on Vulkan on this machine and
renders the maps correctly, apart from a speckled player cloak. It becomes
the **rendering reference**. Upstream OpenGL stays the reference for
behaviour and timing until our own build exists. The RTX 4090 results
(`dist/ss-delta-vita3k-test`) will show which artifacts are AMD-specific.

**Update 2 (2026-10-09, RTX 4090 results):** every artifact depends on the
GPU vendor. No combination is correct on both GPUs.

* **Vulkan is the renderer to build on.** It is the only backend without
  gross errors on both vendors.
* Comparisons use two references:
  * Plus Vulkan on the mini PC;
  * upstream or Plus Vulkan on the RTX 4090.
* A difference between the two references is itself a bug signal, and
  points at undefined behaviour in shader translation (see
  [02-baseline](02-baseline.md#rtx-4090-results-2026-10-09)).
* OpenGL is no longer used for rendering judgements.

**Update 3 (2026-10-09):** our fork (patches 0002 and 0003) runs Vulkan on
the Radeon 760M. It renders the field correctly and the Walhalla floor
textured. **Our fork on Vulkan is now the reference on this machine.** Plus
stays as a cross-check. The NVIDIA reference needs a retest with our fork.

**Update 4 (2026-10-10):** the reference settings for our fork are now
`disable-surface-sync: false` (surface sync on) and `high-accuracy: true`,
with `memory-mapping: double-buffer` and `async-pipeline-compilation: true`
kept. Compared with a Vita hardware screenshot of the title:

* surface sync brings back the haze and smoke that the game renders
  offscreen and reads back from memory;
* high accuracy removes the flicker and blocks in the green smoke;
* Plus's `external-host` mapping hides the skulls, butterfly and candle in
  our fork, so it stays off.

The cost is small: 29.5 fps in the field, and 29.2 fps at the title with
one 46 ms frame. See [02-baseline](02-baseline.md#fog-and-smoke-differ-from-hardware-2026-10-10).
The config lives in `build/` and isn't committed, so these values are
recorded here and in `CLAUDE.md`.

## D5 — Fork upstream Vita3K, not Vita3K-Plus; cherry-pick from Plus (accepted, 2026-10-09)

**Context:** Phase 1 needs a Vita3K source tree we build and patch. Plus v1.2
(tag `v1.2` = branch `all-enhancements`, `e2331f80`) is the build that runs
on Vulkan on the Radeon 760M. Measured against upstream:

* Merge base `5b040dc4` (2026-06-12, "app: Implement linux portable").
  This is also the hash in the Plus binary's build string `2-5b040dc4`.
* Plus adds 167 commits: 250 files, +17,964/−2,417 lines. Most target other
  games (Killzone, Uncharted, Resistance, Gundam, MGS3 …), Android/Mali/
  Turnip drivers, a thread-scheduling rework ("emulate the 3 cores"), and
  deadlock/hang watchdogs.
* Two commits name this game:
  * `98a65bff` "Fixes for depth in SSDelta": whole-mip-chain texture hashing,
    tiled depth-surface row rounding, full-width colour-surface reads,
    depth-bias slope × resolution multiplier;
  * `d248beee` "Refix Sacrifice Soul Delta outlines": MSAA depth surfaces
    read back as textures at the right samples-per-texel.
* Upstream has 98 commits since the merge base, which Plus lacks.

**Decision:**

* Our fork starts from upstream `master`. It lives in `third_party/vita3k` as
  a nested git clone (it is ~1 GB with submodules, too big to vendor as in
  decimation D6), on branch `ss-delta`.
* Plus is a second remote (`plus`) in that clone. Its fixes come over as
  cherry-picks, one at a time, each tested against this game.
* Our patch series is exported with `git format-patch` into
  `patches/vita3k/`, and that directory is committed here. The pinned
  upstream commit is recorded below.

**Why not Plus:**

* Its game-specific hacks and global scheduling/watchdog changes would be
  noise in the Phase 4 differential work.
* Fixes made on upstream can be sent upstream.
* Plus is behind upstream by 98 commits, and rebasing it is not our job.

**Consequences:** the AMD Vulkan crash has to be found by debugging upstream
directly, with the Plus diff as a hint rather than a ready-made fix.

**Pinned:** upstream `b75d5e62` (2026-10-09, "appimage: Correctly copy data
folder (#4216)").

## D6 — The recompiler is a Python generator; runtime and tests are C++ (accepted, 2026-10-10)

**Context:** Phase 3. Decimation used a C++ framework (Yakumo's psprecomp)
because one existed for the PSP. Nothing comparable exists for ARMv7.
`tools/inventory.py` already decodes every function in Python (Capstone,
recursive descent, jump tables, IT blocks).

**Decision:**

* `recomp/` holds our recompiler:
  * `recomp/armrecomp/` is a Python package that turns the inventory's
    per-function decode into C++ in `generated/<module>/`;
  * `recomp/runtime/` holds the C++ headers the generated code includes
    (guest context, memory access, flag helpers, dispatch hooks);
  * `recomp/tests/` holds a C++ harness that runs each instruction, and a
    sample of whole leaf functions, through the generated code and through
    dynarmic (from the fork's `external/dynarmic`) and compares the results.
* The interface of the generated code is `void f_<addr>(GuestContext *)`
  plus four hooks (`call_indirect`, `call_import`, `escape`,
  `unsupported`).
  * A function returns by setting `r15` to its return address.
  * Every call site checks `r15` and escapes to the fallback CPU when the
    callee returned somewhere else.
  * See [05-recompiler](05-recompiler.md).
* Speed of the generator doesn't matter. It runs once per build and reads
  only `extracted/elf/`.

**Consequences:**

* The generator and inventory share one decoder. A decode fix applies to
  both.
* Generated code depends only on `recomp/runtime/`. Phase 4 plugs it into
  Vita3K through that interface.

## D7 — Native code runs at JIT block boundaries, from a DLL the fork loads (accepted, 2026-10-10)

**Context:** Phase 4. Generated code needs a host CPU loop to run in,
access to Vita3K's HLE imports, and a way back to dynarmic for code that
isn't recompiled (NEON, ARM mode, the LLE libraries, indirect jumps).

**Decision:**

* Each recompiled module is built as a DLL (`ssd_aot_<module>.dll`). It is
  built from `generated/` and never committed. The fork loads every DLL
  named in the `SSD_AOT` environment variable (`;`-separated). The ABI is
  `recomp/runtime/aot_abi.h`, which the fork copies as
  `cpu/include/cpu/aot_abi.h`: the guest context, the host hooks, and the
  module's function table and code hash.
* Before a module's code runs natively, the fork checks its code hash
  against guest memory. A mismatch, for example from a different game
  version or a code patch, leaves the module on the JIT.
  * The hash skips the instruction words the loader patches for variable
    imports. Generated code reads their immediates at run time.
* **JIT → native:** dynarmic's `PreCodeReadHook` ends every block that
  reaches a recompiled function's entry, and halts the JIT there with
  `UserDefined7`. `DynarmicCPU::run` then copies the registers into the
  guest context, calls the function, copies them back and continues the
  JIT at the returned `r15`.
* **Native → JIT** (`call_indirect` without a native target, LLE import
  stubs): the call runs a nested JIT loop with `lr` set to a sentinel
  block. The hook stops the loop there. The nested loop handles SVCs and
  native entries itself.
* **Native → HLE:** `call_import` reads the patched stub. For
  `svc #0; mov pc, lr; .word nid`, it calls the kernel's import handler
  directly. Anything else, such as a stub bound to an LLE module, runs on
  the JIT.
* **Escapes** throw a C++ exception. It is caught at the innermost
  boundary, and the JIT continues from the escape address with the native
  frames above that boundary abandoned. A thread that exits while native
  code is on its stack unwinds the same way (`CPUState::aot_unwind`).
* Guest threads get 64 MiB host stacks while AOT is enabled, because guest
  calls become host calls.
* `strex` is a host compare-and-swap against the value `ldrex` read, as
  Vita3K's dynarmic does it, so native and JIT threads share one exclusive
  protocol.

**Consequences:**

* Without `SSD_AOT` the fork behaves as before.
* Verification tools ship with the runtime:
  * `SSD_AOT_DIFF`, a differential mode against a shadow JIT;
  * `SSD_AOT_COUNT`/`SSD_AOT_STATS` counters;
  * `SSD_AOT_RANGE`, plus `RECOMP_BISECT` DLLs, for bisecting.
  * See [05-recompiler](05-recompiler.md#runtime-in-the-fork-phase-4).
* Every transition copies about 350 bytes of registers. A hot native
  caller of a JIT-only function (most often NEON) pays a nested `Run()`
  per call. Phase 5 removes most of these calls.
* Generated code is never linked into Vita3K. The fork stays free of
  game-derived code (D2), and a regenerated DLL needs no Vita3K rebuild
  unless the ABI version changes.

## D8 — Relocatable modules are generated for Vita3K's load addresses (accepted, 2026-10-10)

**Context:** libc, libfios2 and libult are relocatable. Vita3K loads their
code at addresses other than the ELF's (libc at `0x8031e000`). Generated
code bakes code addresses in: return addresses, branch and escape targets,
and PC-relative loads.

**Decision:**

* Generate each module for the address Vita3K loads it at
  (`recompile.py --load-base`), decoding its code at runtime addresses.
* Data references the loader relocates (Thumb `movw`/`movt`) are decoded
  from guest memory at run time.
* The code hash, with every relocated word skipped, guards the choice: a
  module loaded elsewhere fails verification and runs on the JIT.

**Consequences:**

* The addresses are a property of the boot sequence, not of the modules.
  They were the same in every run so far (title and field boots).
* If the order Vita3K loads modules in ever changes, the libraries quietly
  fall back to the JIT. The log says so ("does not match").
* A position-independent alternative (adding a module base at run time) is
  still possible if the addresses turn out to vary.


## D9 — Fiber switches stay context swaps; native code re-enters at resume points (accepted, 2026-10-10)

**Context:** libult (the game's user-level threads) switches fibers through
SceFiber. Native code reaches a switch as a host call. Swapping the CPU
context under it abandons the native frames, and the rest of each frame
ran on the JIT. Worker loops never return, so they stayed there.

**Decision:**

* With `SSD_AOT` the fork uses its SceFiber HLE and does not load
  libfiber. A switch is a context swap in an import. `call_import` sees a
  different pc, sp or lr and escapes to where the other fiber was
  suspended.
* Generated functions have **resume points**: every call's return address
  is also an entry (`GuestContext::resume`, ABI v2). When the JIT reaches
  one, because a frame whose callee escaped returns to it, the function
  continues natively from there. A switched-back fiber therefore runs
  natively again after one boundary per frame.
* Branches to another recompiled function's entry are tail calls, not
  escapes.

**Rejected:** a host fiber per guest fiber (native frames survive the
switch). ULT moves fibers between worker threads, and a host fiber's
frames point at the CPU of the thread that created it. The experiment is
kept on the fork branch `host-fibers-experiment`.

**Consequences:**

* All four modules run natively with no JIT instructions inside them in
  title, field, arena and quest runs. The JIT is left with firmware LLE
  code ([05-recompiler](05-recompiler.md#coverage-130)).
* Each fiber switch costs an escape (a C++ exception) and one boundary
  per resumed frame, about 12,000 a minute in the field at 29.6 fps.
* libult's load address depends on libfiber not being loaded
  (`80451000`, [D8](#d8--relocatable-modules-are-generated-for-vita3ks-load-addresses-accepted-2026-10-10)).
* Phase 6 does not need host fibers for libult. A standalone runtime can
  keep the same scheme without dynarmic only if every escape target is a
  resume point or a function entry.

## D10 — `ss-delta.exe` is a target in the Vita3K fork (accepted, 2026-10-10)

**Context:** Phase 6 needs a single-game executable without Vita3K's Qt
interface. Upstream's SDL front end (`--frontend sdl -r`) already runs the
game in a plain window, natively at 99.9%.

**Decision** (the user's choice): build `ss-delta.exe` as a second
executable in the fork, `vita3k/ss-delta/`, beside `Vita3K.exe`, reusing
its libraries and leaving out `gui-qt`.

* Settings the game needs are fixed in code: Vulkan, `high-accuracy`,
  surface sync on, `memory-mapping: double-buffer` (D4 update 4).
* The player's choices are in `ss-delta.ini` next to the exe, like
  `decimation.ini`. It is written with comments on first start.
* Recompiled modules (`ssd_aot_*.dll`) are loaded from a configured folder
  unless `SSD_AOT` is set. The DLLs are generated locally and never
  shipped (D2).
* Config and log go in `ss-delta/` next to the exe. The shader cache is
  shared with `Vita3K.exe`.

**Rejected:** a separate runtime that copies only the pieces it needs. It
would fork the HLE, renderer and loader away from the code the
differential checks and Vita3K comparisons run against.

**Consequences:**

* `ss-delta.exe` is built from Vita3K's code, so it is under Vita3K's
  GPLv2.
* It stays in step with the fork: every fix applies to both executables.
* Vita3K's other subsystems (app list, users, config types) come along.
  The exe hides them instead of removing them.

## D11 — Threads run on native code alone (NativeCPU); firmware modules are recompiled too (accepted, 2026-10-11)

**Context:** Phase 6's exit is no dynarmic. After Phase 5 the JIT ran only
firmware modules (the module loader, the video player) and Vita3K's halt
instruction. Its main job was driving threads into native code.

**Decision:**

* The firmware modules the game loads as guest code are recompiled like
  libc. The input is ELFs that `ss-delta.exe` writes as it loads them
  (`SSD_DUMP_ELFS=1`), decrypted and already relocated to their load
  addresses. They are generated locally from the player's firmware and
  never committed (D2). The modules are `sysmodule.skprx`, `libSceFt2`,
  `libpvf`, `libscemp4` and `libsceavplayer`.
* `NativeCPU`, a second CPU backend in the fork:
  * registers in the native context;
  * `run()` calls the native function at pc until the guest returns to
    the halt instruction;
  * escapes continue at resume points (D9), imports go straight to the
    HLE function or the native export;
  * guest code without native code is a logged error.
* The AOT hooks dispatch through an interface (`AotOwner`) both backends
  implement.
* `ss-delta.exe` uses `NativeCPU` by default. `[recompiled] jit = true` in
  `ss-delta.ini` brings the JIT back as a fallback.

**Consequences:**

* Title, dialogs, hub, book menu, field and a quest run with **zero JIT
  instructions** at the same frame rate.
* Native code can't be preempted. A suspend request takes effect only when
  the guest returns to the run loop. Single-stepping isn't available.
* Seventeen font functions (`libSceFt2`, `libpvf`) still use NEON forms
  the translator lacks. None of them has run in any session so far. If one
  ever does, `NativeCPU` names the address in the log.
* `VITA3K_DYNARMIC=OFF` builds without dynarmic (fork patch 0026). The
  normal build keeps it as the `jit = true` fallback and for the
  differential checks.
* The ELF dumps also replace an external SELF decryptor. The install flow
  (`tools/install-game.ps1`) gets every module from them.

## D12 — Shaders and pipelines compile in the background on first use; nothing is translated at install time (accepted, 2026-10-11)

**Context:** Phase 7 planned to translate every GXP the game ships at
install time, so that no shader compiles in game. The game's shaders are in
487 `resource/data/shader/psp2/*.csp` containers (`KPKy`, several GXPs
each).

**Findings:**

* Vita3K's SPIR-V translation depends on draw-time hints as well as the
  GXP: the texture formats bound to each sampler (component type and
  count), the colour surface format and the vertex attribute formats
  (`shader::Hints`). Translating a GXP without them can give a different,
  wrong shader. The cache key is the GXP hash alone, so a wrong
  install-time translation would stick.
* The expensive part on Vulkan is the pipeline, keyed by the GXP pair plus
  the render state (blending, attribute layout, primitive type, render
  pass). Those combinations exist only at draw time.
* With `async-pipeline-compilation` (on), a pipeline seen for the first
  time compiles on worker threads and its draws are skipped meanwhile. The
  SPIR-V files and the driver pipeline cache persist next to the exe.
* Measured with an empty cache (debug build, title → Stage Select →
  ST08A, 2026-10-11): 29.5 fps mean, minimum 28 in one-second samples.
  Mind's Eye, opened for the first time, compiled 6 pipelines and showed
  its outlines within the second.

**Decision:** keep Vita3K's runtime translation with background pipeline
compilation and the persistent caches. `ss-delta.exe` fixes
`async-pipeline-compilation` on and hides the "N pipelines compiled"
notice (fork patch 0028).

**Rejected:**

* Install-time translation of every GXP: wrong without draw-time hints.
* Shipping a prebuilt cache: derived from the game (D2).

**Consequences:**

* On a fresh install, an object can be missing for a frame or two the
  first time its pipeline is needed. There are no frame-time stalls.
* A cache built by one translator version stays valid only for that
  version (`CLAUDE.md`, stale shader cache).

## D13 — Higher resolution comes from the game's own 960×544 mode times Vita3K's multiplier; settings reach the game through a copy of boot_config.ini (accepted, 2026-10-11)

**Context:**

* The game draws its 3D at 720×408 and stretches it into the 960×544
  framebuffer. The plan was to patch the VitaGrafix sites.
* The render-target setup takes a mode from `boot_config.ini`'s
  `ResoDown`: 0 gives 960×544, 1 (the retail value) 720×408.
* Patching only the mode-1 immediates breaks rendering in Vita3K, since
  other code reads the mode. Code patches would also have to go through
  the recompiler, because native code checks the eboot's code against
  guest memory.
* Vita3K's resolution multiplier scales every surface consistently,
  including the depth buffer that Mind's Eye reads.

**Decision:**

* `full_3d` (default on) selects `ResoDown 0`. `scale` multiplies it.
* At scale 2 the 3D is 1920×1088, verified on all 50 map IDs at 30 fps on
  the Radeon 760M.
* `ss-delta.exe` gives the game a changed copy of `boot_config.ini`
  through an IO read override (fork patch 0029). The installed game is
  never modified. `[boot_config]` in `ss-delta.ini` passes other engine
  keys the same way, for experiments.

**Rejected:**

* Patching the immediates (VitaGrafix style): breaks rendering here, and
  needs recompiler support.
* Editing the installed `boot_config.ini`: it changes the player's game
  files, and a reinstall would lose the setting.
* Rendering the 3D above the framebuffer (supersampling into 960×544):
  Vita3K's multiplier already raises the framebuffer.

**Consequences:**

* `full_3d` changes the game's look slightly compared with a Vita, so it
  can be turned off.
* Engine keys (`FPS`, `ForceDLC`, ...) can be tried without patches, but
  `FPS` turned out not to set the frame rate (02-baseline, 60 fps study).

## D14 — The add-ons are unlocked by recording them in the save's system.bin (accepted, 2026-10-11)

**Context:**

* The add-ons' content (raiments, hoods, the additional and otherworldly
  pacts) is in the game's data since update 1.30. PSN, where they were
  sold, no longer exists. The owner asked for them to be unlocked when the
  installed game has them.
* `ForceDLC` in `boot_config.ini` is parsed but never read.
* Answering the game's PSN entitlement queries locally works (the game
  lists all 18), but it hands add-ons out only after an online download
  step on Cassus's Claim Gift page, which does not complete offline
  (tried in fork patch 0030, reverted in 0031).
* Vita owners unlock them by swapping in a `system.bin` from a save that
  had them. The file is four id lists plus a CRC-32/BZIP2 check, decoded
  in 01-research.

**Decision:** `ss-delta.exe` (`[game] dlc`, default on) adds the released
add-ons' ids to those lists in the player's own `system.bin`/`.bak` at
start, keeping anything already there, after checking that the installed
game has the add-on pacts and raiments. The previous files are copied to
`ss-delta/save-backups/` first. The ids are numbers in the fork's source;
no third-party save is shipped or needed.

**Rejected:**

* Shipping or asking for a third-party `system.bin`: it would replace the
  player's own, and the four lists are enough.
* The PSN path: needs a fake online session the game never completes.

**Consequences:**

* The change is in the save, so it carries over to a Vita (same format).
* Turning `dlc` off later does not remove them; restoring the backup does.

## D15 — Ad hoc play uses Vita3K's ad hoc support; copies on one PC take 127.0.0.N (accepted, 2026-10-12)

**Context:**

* The owner asked for multiplayer (plan Phase 10). The game's Ad Hoc Play
  runs on SceNetCtl's ad hoc mode and the firmware's matching module,
  which Vita3K supports since late 2025: the module runs as LLE over P2P
  sockets, which Vita3K maps to UDP port 3658 + virtual port, and peers
  are found by a broadcast every second.
* Decimation (D11 there) had to write its ad hoc layer and server; here
  nothing of the kind is missing.
* Two copies on one PC collide: both bind the same ports, and loopback has
  no broadcast. They also share a save, a config and the shader cache.

**Decision:**

* Keep Vita3K's ad hoc support (LLE matching module, P2P over UDP).
* `ss-delta.exe --player N` is copy N (2-4): Vita user N-1, saves copied
  from player 1's once, its own config and log, the shader cache read
  only.
* `[multiplayer] network = local` (default) gives copy N the address
  127.0.0.N: P2P sockets bound to any address bind it, and a broadcast
  goes to each 127.0.0.1-4 but its own. `lan` is Vita3K's way, for PCs in
  one network.
* The matching module, loaded only when Ad Hoc Play opens, is recompiled
  for a fixed base (`0x80757000`, where Vita3K's allocator puts it), and
  the loader places a module with native code at its base when free (D8's
  guard, the code hash, still applies).

**Rejected:**

* An ad hoc server (PPSSPP's protocol, as in decimation): the Vita's ad
  hoc needs none, and Vita3K builds on IP addresses directly.
* A full copy of the Vita file system per player: gigabytes, and the users
  already separate the saves.

**Consequences:**

* Play with real Vitas (XLink Kai) is not covered; it needs Vita3K's
  traffic bridged to a Vita's ad hoc frames.
* Players on one PC are four at most, the game's room size.
* If the allocator ever puts the matching module elsewhere, the log says
  the base "is taken" and the build without the JIT stops at its first
  call; the JIT build runs it as guest code.

## D16 — 60 fps is an option that keeps loading screens at 30 (accepted, 2026-10-13)

**Context:**

* The owner asked for 60 fps, or to mark it unplanned if it needs a game
  rewrite. The game paces its main loop with a frame timer created for 30
  fps and flips every 2nd vblank; both are data in guest memory.
* Game logic steps by the measured frame time, so movement and fights keep
  their speed at 60 (02-baseline, 60 fps sections).
* The quest-start loading screen never ends at 60: something in the loader
  checks the frame time and fails below about 1/45 s. It was narrowed to
  the time step of the game update and to the `NowLoadingTask`'s
  `roading_loop` animation, which is never told to stop; the check itself
  was not found.

**Decision:**

* `[display] frame_rate = 60` sets the timer and the flip threshold every
  frame to 60, and to 30 while the `NowLoadingTask` is in state 2, 3 or 5
  (fork patch 0041). No game code is patched, so native code stays on.
* The default stays 30 until the owner has played at 60.

**Rejected:**

* A fixed 1/30 s step at 60 fps: the loader works, but the game runs at
  double speed.
* Finding and patching the loader's check: not found after following it
  through the update, the loading task and its animation player; a code
  patch would also take the eboot off native code unless the recompiled
  module carried it.

**Consequences:**

* Loading screens look as on the Vita (30 fps); everything else runs at
  60, as far as the GPU allows (54–57 fps on the Radeon 760M).
* If another screen depends on the frame time the same way, it hangs at 60
  in a way the scripted checks didn't reach; switching back to 30 is the
  workaround.
