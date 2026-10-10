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
