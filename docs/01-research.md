# 01 — Research: a PC port of Soul Sacrifice Delta (PS Vita)

Research snapshot from 2026-10-09. Third-party projects change quickly; re-check
before relying on anything here. **Hypothesis** marks claims not checked against
the binary or Vita3K.

Sources are marked:

* **[local]**: measured on our own dump in this session (scripts listed in
  [Workspace state](#workspace-state));
* **[loktar]**: from loktar00's preservation repo (v01.10 eboot), see
  [Prior work](#prior-work-on-this-game);
* **[web]**: from issue trackers, wikis and READMEs.

## TL;DR

* **Feasible, and better placed than the PSP project was on day one in two
  respects.**
  * The dump decrypts fully offline. We already have plaintext 1.30 ELFs for
    the eboot and all four bundled modules.
  * Someone else has already measured this exact binary for static
    recompilation and published the results. Our 1.30 numbers match theirs.
* **The binary is a good recomp target:**
  * 99.85% Thumb-2;
  * no C++ exceptions, no `svc`, no self-modifying code;
  * a complete compiler-emitted function list in the EHABI unwind tables
    (34,636 starts);
  * jump tables are inline `tbb`/`tbh`;
  * every indirect call lands on a known function start.
* **It is roughly twice the size of Dissidia 012:** 3.8M instructions, 11.7 MB of
  code and 34.6k functions, against about 22k functions and 5 MB.
* **The hard part is not the CPU code:**
  * **GXM graphics.** These are programmable USSE shaders, not the PSP's
    fixed-function GE. Translating them is the hardest single piece of Vita
    emulation, and Vita3K already does it.
  * **NEON/VFP semantics.** 17.7% of instructions are FP/SIMD, mostly
    Havok 2013 physics and engine math.
* **There is no PSPRecomp equivalent for the Vita.**
  * The only Vita static recompiler is an early one (sp00nznet/vitarecomp).
    It has never run a game past its constructors and has no NEON or GXM
    support.
  * No Vita game has ever been ported to PC by recompilation or by
    decompilation.
  * So we would effectively write the Thumb-2 → C++ emitter ourselves.
  * The upside is that the runtime side (OS HLE, GXM → Vulkan, shader
    translator) exists in Vita3K, and Vita3K plays this game at 30 fps today.
* **Recommended approach** (same as loktar00's design study, which we agree
  with after checking):
  * Build an ahead-of-time Thumb-2 → C++ recompiler.
  * Run its output inside a stripped Vita3K fork used as the runtime.
  * Keep dynarmic as the fallback for anything the recompiler misses, and as
    a differential-testing oracle.
  * This is the Vita version of what Yakumo's interpreter fallback gave us on
    the PSP.
* **Licence consequence:** Vita3K is GPL-2.0-or-later, so the runtime becomes
  GPL. That is irrelevant for a private, non-distributed build like
  decimation. It matters only if we ever publish code.

## What's in the dump [local]

Input: `rom/Soul Sacrifice Delta [PCSA00152] [USA] [1.30] [NoNpDrm].zip`
(3.34 GB, 736 entries, all stored, i.e. no zip compression).

### Layout

| Path | What |
|---|---|
| `app/PCSA00152/` | the base game, `APP_VER 01.00`, `c_date=20140402`, `sdk_ver=02500000` (SDK 2.50), needs firmware 3.01 |
| `patch/PCSA00152/` | the 1.30 update, `APP_VER 01.30`, `c_date=20140729`, `CATEGORY gp` |
| `*/eboot.bin` | the main executable (SELF): 6.87 MB in 1.00, 7.00 MB in 1.30 |
| `*/sce_module/` | `libc`, `libfios2`, `libult`, `libsmart` `.suprx`, which the game ships and loads itself. The patch has its own copies |
| `resource/data/pack/mount/retail/` | `archive` (1.67 GB `.pk`, 50,821 files), `voice_ue` (750 MB), patch archives `archive_patch3` (72 MB) and `voice_patchv_ue` |
| `resource/data/pack/memory/` | 53 `*_motion_set` and `magic_effect*` archive triples (`.pk`/`.pkh`/`.pfs`) |
| `resource/data/video/` | 13 FMVs: **H.264 High, 960×544, 29.97 fps, AAC-LC 48 kHz stereo** in `.mp4`, played through `SceAvPlayer` |
| `resource/{boot_config,config}.ini` | engine flags (`FPS 30`, `ResoDown 1`, `PackFileFirst`, ...) and the boot sequence. `config.ini` holds a dev block with `BootSequence DebugMenu` that a retail block overrides |
| `sce_sys/package/work.bin` | NoNpDrm fake licence (RIF) for `UP9000-PCSA00152_00-SOULSACDELTAUS00` |
| `sce_sys/param.sfo` | can import saves from the original game (PCSA00092 and the other regions) |

### Two layers of encryption

1. **PFS layer.**
   * Every file in the zip except `param.sfo`, `head.bin` and the PFS
     databases is still encrypted. That includes `boot_config.ini`, PNG icons
     and MP4s.
   * This is normal for a NoNpDrm dump: the files are copied from the
     memory card as stored.
   * `sce_pfs/files.db` (`SCENGPFS`) and `unicv.db` (`SCEIRODB`) are the PFS
     metadata.
   * **Decrypted by:** Vita3K's installer (`Vita3K.exe <zip>`), which uses
     psvpfsparser and the key in `work.bin`. It installed both `app` and
     `patch` and **merged the 1.30 patch into `ux0/app/PCSA00152`**. It took
     about 20 s on this PC.
2. **SELF layer.**
   * `eboot.bin` and the `.suprx` files are NPDRM SELFs (`SCE\0` magic).
   * **Decrypted by:** loktar00's Python 3 port of TeamMolecule's sceutils
     (`self2elf.py`), with the 28 retail keys generated from Vita3K's
     `packages/src/sce_utils.cpp` and the RIF as klicensee source.
   * Alternatives: Vita3K's GUI "Decrypt selfs", or its
     `kernel.debugger.dump_elfs` option, which dumps relocated ELFs at load.

Both steps are offline. No firmware is needed for decryption, but Vita3K needs
the official firmware PUPs to *run* the game. `libult` imports `SceFiber` from
the firmware's `libfiber`.

### The 1.30 eboot (`efg`)

| Fact | Value |
|---|---|
| ELF type | `0xFE00` (ET_SCE_EXEC, fixed address, not relocatable), ARM, 32-bit LE |
| Module | name **`efg`** ("Elder Fantasy Game"; *Elder Fantasy* was the working title), version 0x101, **module NID `0xD66AEBF4`**. This matches the VitaGrafix entry for US 1.30 |
| Segment 0 (RX) | `0x81000000`, filesz/memsz `0xC92B9C`/`0xC92BB0` (12.6 MB code + rodata) |
| Segment 1 (RW) | `0x81C93000`, filesz `0x51FD8`, memsz `0x188F0C` (1.6 MB, mostly BSS) |
| TLS | 0x10 bytes |
| `module_start` | `0x81802ABC` |
| exidx | `0x81B2ACD0–0x81B6E730`: **34,636 entries** (33,933 Thumb, 703 ARM-bit-clear incl. the 27–29 ARM functions and `CANTUNWIND`/data) |
| Imports | **51 libraries, 704 functions, 9 variables**; every NID resolves to a name in vitasdk's `vita-headers` db |
| Exports | only the module's own `module_start` / `module_info` |
| Middleware | Havok 2013.2.0-r1, statically linked [loktar]. A few `GFx` strings hint at Scaleform (**hypothesis**) |

**Import surface by library (function counts):**

| Group | Libraries (functions) |
|---|---|
| Graphics | SceGxm (116), SceDisplay (1), SceDisplayUser (1) |
| Kernel / OS | SceLibKernel (34 + 1 var), SceThreadmgr (15), SceThreadmgrCoredumpTime (1), SceSysmem (5), SceIofilemgr (5), SceProcessmgr (1), SceSysmodule (3), SceAppMgrUser (3), SceAppUtil (15), ScePower (1), SceRtc (1), SceRtcUser (9) |
| C runtime, provided by the bundled `libc.suprx` | SceLibc (73 + 5 vars), SceLibm (17), SceLibstdcxx (17 + 3 vars) |
| Bundled modules | SceFios2 (16, file I/O), SceUlt (13, user-level threads), SceSmart (13, SmartAR cards) |
| Audio / video | SceAudio (5), SceAudiodecUser (7), SceAvPlayer (17) |
| Input | SceCtrl (2), SceTouch (3), SceMotion (4), SceCamera (10), SceIme (3) |
| UI | SceCommonDialog (49), SceScreenShot (3) |
| **Online, dead since Dec 2021: stub** | SceNet (30), SceNetCtl (11), SceHttp (19), SceSsl (2), SceLibRudp (19), SceNetAdhocMatching (10), ScePspnetAdhoc (10), SceNearUtil (16), SceNp{Activity 3, Basic 12, Common 8, Manager 10, Matching2 26, Message 3, PartyGameUtil 8, Score 13, SnsFacebook 2, Trophy 7, Tus 22, Utility 10} |

About 270 of the 704 imports are online/NP and can be stubbed. That leaves
about 430 that need real behaviour. **SceGxm's 116 is the bulk of the real
work.**

### The bundled modules

| Module | Code | Exports | Imports | Port plan |
|---|---|---|---|---|
| `libc.suprx` (SceLibc) | 0x4D3BC (316 KB), 1,592 exidx | SceLibc 344, SceLibm 201, SceLibstdcxx 507 functions + 591 variables (vtables/typeinfo) | 56 kernel/io/fios2 | Vita3K runs it as guest code (LLE). Either recompile it with the game, or HLE the ~100 functions the game imports with host libc. Recompiling is safer: the C++ runtime's vtables/typeinfo are imported as *variables* |
| `libfios2.suprx` | 0x2B12C (176 KB) | 150 | 66 (kernel, io) | recompile it, or HLE the 16 the game uses on host files |
| `libult.suprx` | 0x1384C (80 KB) | 62 | 26, incl. **SceFiber** (7) | replace the 13 imports with host fibers ([loktar] recommends this) |
| `libsmart.suprx` | 0x1FE8CC (2 MB) | 40 | libc/libm | stub it (AR cards) |

### Instruction mix of the 1.30 eboot [local]

This is a linear Capstone sweep of every exidx function (start → next start),
skipping import stubs. Script: `scratchpad/imix.py` (see below).

| Metric | 1.30 (ours) | 1.10 ([loktar], Ghidra) |
|---|---|---|
| Instructions | **3,799,876** | 3,592,527 |
| Thumb share | 99.85% (5,745 ARM instructions in 29 ARM functions) | 99.85% (27 ARM functions) |
| Function starts (exidx) | **34,636** | 34,094 (Ghidra alone found only 24,984) |
| FP/SIMD | **671,377 (17.7%)** | 631,656 (17.6%) |
| NEON (Q-reg / vector-only ops, rough classifier) | ~243.6k | 241.2k |
| `vrecpe`/`vrsqrte`/`vrecps`/`vrsqrts` | 11,777 | — |
| `blx reg` | 41,486 | 40,166 (24,764 true indirect, the rest `movw/movt r12` far calls) |
| `tbb`/`tbh` jump tables | 1,336 | 1,312 |
| `ldrex`/`strex` family | 1,578 instructions | 787 pairs |
| `mrc` (TLS read, TPIDRURO) | 74 | 74 |
| `svc` | 0 | 0 |
| `sdiv`/`udiv` | 0 (Cortex-A9, division via helpers) | 0 |
| `bkpt` | 146 (assert traps) | 100 |
| `IT` blocks | ~2.5k | 2,367 |

[loktar] results that our sweep does not re-measure, but which fit the
numbers above:

* no C++ exceptions: 0 LSDA personalities, Dinkumware's no-exception abort
  path;
* no `setjmp`/`longjmp`;
* about 3,300 vtable-like tables;
* the first frame is reachable only through indirect calls (the GXM
  display-queue callback). A "static closure of `module_start`" milestone is
  therefore not possible.

### Assets [local + loktar]

* **Archive format** (the Marvelous "LSPK" family, also used by The Last Story
  and Fate/Extella; all big-endian):
  * **`.pkh`:** `u32 count` + 16-byte records `{hash, offset, size, csize}`.
  * **Hash:** CRC-32/BZIP2 of the lower-cased path. This is the same hash
    family as Dissidia's PACKAGE_INFO.
  * **`.pk`:** headerless; members are zlib streams, or raw when csize is 0.
  * **`.pfs`:** the directory tree and name pool. Layout (verified,
    `tools/lspk.py`):
    * header: `u32 0, 0, dirs, files`;
    * one 24-byte record per directory:
      `{index, parent (0xffffffff for the root), first child, child count,
      first file, file count}`;
    * one `u32` name offset per directory, then per file, into the name
      pool that follows.
    * A member's key is the hash of `dir/.../name`, for example
      `resource/boot/quest_param.csv`.
  * **Verified on our 1.30 data:**
    * `archive`: 50,821/50,821 members decompress and every name hashes to a
      pkh entry;
    * `archive_patch3`: 3,026/3,026.
* **Content formats:** `.mdl` (`KPKy`), `.gxt`/`.mxt` (Vita GXT textures),
  `.mtb` motion, `.eff` effects, `.scene` (Shift-JIS XML), `.msgt`
  (UTF-16 text), `quest_param.csv`. The 1.30 copy in `archive_patch3`
  (`resource/boot/`) has 581 quests on 50 map IDs (column `MAP(ID)`). The
  debug Stage Select counts quests by their row in this table.
  * Shaders: 487 `resource/data/shader/psp2/*.csp`, `KPKy` containers of
    GXPs.
  * The boot sequences the eboot knows include `Title`,
    `Quest Select`, `CutEvent Select`, `DebugMenu`, `BookEpisode`,
    `BookEnding`, `BookMenu`, `EndingDelta`, `StaffRoll` and
    `[G] HarpyBattle Walhalla`.
  * What some of them do [local, 2026-10-11]:
    * `EndingDelta` starts the final battle against Magusar.
    * `StaffRoll` shows a two-line debug menu ("no clear" / "clear") and
      plays the credits.
    * `BookEnding` stays black, on upstream Vita3K too.
    * The debug menus confirm with **circle**, not cross.
    * `StaffRoll` → "clear" also plays the full credits, then stays black
      [local, 2026-10-12].
    * `CutEvent Select` is an event viewer: the tutorials, `QuestLast00/01`
      and the prison events (`PrisonOpen00/01`, `PrisonEnd00` "dummy data",
      `PrisonEnd01` "ED: the sorcerer transforms → escapes the prison").
      R adds the entry to a list, circle starts it. Without a loaded save
      `PrisonEnd01` shows "Now Loading..." and falls back to the title
      [local, 2026-10-12].
* **Characters and the final battle** [local, 2026-10-12]:
  * `boot/chara_param.csv` (Shift-JIS): `No., description, HP, attack,
    defence, ...` for the player (`!pc001`), NPCs and every enemy and boss
    (`eb###`, `ez###`) with rank variants (`_r01` ...).
    `boot/chara_id_table.csv` maps the `ch####_##` ids that
    `quest_param.csv` uses (`BOSS_ID1/2`) to models and these rows.
  * Magusar is `マーリン` (Merlin) in the data: `ch5002` Old Merlin (`eb500`)
    and `ch6002` his dragon form (`eb600`), the bosses of `q_e0251` (ST17B);
    Delta's final battle `q_e0252` (`EndingDelta`) is `ch8402` Super Merlin
    (`eb840`) and `ch8602` the last boss (`eb860`).
  * A loose `resource/boot/chara_param.csv` with `PackFileFirst false`
    (through `[boot_config]`) is opened instead of the archive's, but
    setting those bosses' HP to 1 and attack to 0.01 did not visibly change
    the final battle (the player still lost). Fight values probably come
    from elsewhere as well (rank tables, skill data; **hypothesis**).
* **Saves:** `ux0:user/00/savedata/PCSA00152/` holds `datag0001.bin` (979,168
  bytes) and `system.bin` (1,556 bytes), each with a `.bak` copy. In
  Vita3K they are plaintext; a decrypted save from another console (Apollo's
  PSV database) loads by copying those four files [local].
* **Loose files override archives.** The engine `stat()`s loose files first,
  and `archive_patch1` is an unused patch slot (1.30 ships `archive_patch3`).
  Both are modding hooks [loktar].
* **Debug menu:** the retail build still has Marvelous' dev sequence menu
  (Stage Select for all quests, cutscene viewer, test maps). Enable it in
  `config.ini` with `BootSequence DebugMenu` [loktar]. This is extremely
  useful for testing a port.
* **DLC:** the DLC assets reportedly ship inside the 1.30 data; entitlement is
  a flag in the save (`system.bin`) [web, GBAtemp]. So 1.30 is the right
  target. The engine also has a `ForceDLC` key in `boot_config.ini`
  (commented out in retail) [local].
* **Add-ons** [local, 2026-10-11]:
  * The list is the game's own `resource/database/network/entitlement_table_us.csv`
    (`archive_patch3`): product id (`UP9000-PCSA00152_00-SSCnnn`), box id
    (`COSTUME_01`, `PARTS_01`, `STAMP_01` ...), release version, comment.
    21 rows: 18 released, `DBG001` (developer) and `SSC018`/`SSC020`
    marked 配布予定なし (never released).
  * `ForceDLC` (`boot_config.ini`) is parsed into the config's `+0x14` but
    never read.
  * The game asks PSN with `sceNpAuth`: an entitlement manager at
    `*(*0x81c9a4e0 + 0x44)`, state machine `0x818ca438` (1 start request, 2
    wait for the ticket, 3 fetch the id list into `+0x40` count / `+0x44`
    ids, back to 0). Started by `0x818ca3c0` from the online-pass check
    (`0x812782f4`, `STN001`) and from the download step of Cassus's
    **Claim Gift** page (`0x816ae350`, its state 9).
  * Hand-out: `0x816ae876` turns each listed add-on not yet received
    (byte array `*0x81c9a160 + 0xc2ec8`, indexed by table row, in the
    main save) into a gift on the Claim Gift page. It runs when that
    page's download step ends, which needs a PSN sign-in and the network
    (`sceNetCheckDialog`, then a network task); offline it never ends.
  * **What unlocks them is the save's `system.bin`** [local, verified]. On
    a Vita after the shutdown, players swap in a `system.bin` from a save
    that had the add-ons [web, GBAtemp thread 625005]. That file holds,
    after the 32-byte header `{1, 0x614, 0, 0x22, check}`, four sorted id
    lists ended by a zero:
    * `0x14` (u16): 35 `quest_param.csv` rows, the additional pacts
      (449–451, 455–463, 467–472, 561–571, 575–580);
    * `0x224` (u16): 624, 696, 708, 4348, 4420, 4432 (parts tables);
    * `0x324` (u32): 502, 512, 7812, 8702, 8802;
    * `0x344` (u16): `costume_table.csv` rows 112–119, 130 (Healer, Beast,
      Easterner ...).
    The check (`+0x10`) is CRC-32/BZIP2 of the whole 1,556 bytes with the
    check zeroed. Our `system.bin` has all four lists empty. With the
    lists written, the outfit list shows Healer, Beast and Easterner as new
    (seen in `ss-delta.exe`, 2026-10-11). List capacities are taken as the
    gaps to the next list (**hypothesis**), except that the gap after the
    `0x14` list also holds options: setting Options → Color Space to Wide
    and saving changed only `+0x21c` (0 → 1) and the check [local,
    2026-10-12]. The first list then has room for at most 260 ids (it holds
    35); `unlock_addons` keeps to that (patch 0037).
* **Touch** (the game's English text, `ingame_event_us.msgt`,
  `ingame_tutorial_us.msgt`, `letter_text_01_us.msgt`, `online_text_us.msgt`)
  [local, 2026-10-11]:
  * "Black Rite: touch and hold icon". The icon is in the lower left during
    quests, centred near (56, 494) of 960×544. This is the only touch-only
    action found.
  * "Touch enemies or allies to influence those still alive" (after a
    battle), "you may also directly tap a pact" (Phantom Quests), and
    tapping skips a quest's opening (so does START).
  * Librom reacts to being touched ("Hey, that tickles. No touching!").
  * No rear-touch prompts were found. The eboot imports `sceTouchRead`,
    `sceTouchSetSamplingState` and `sceTouchGetPanelInfo`. Which ports it
    samples is not checked (**hypothesis:** the rear panel is unused).

### Rendering facts

* **Native internal resolution: 720×408**, upscaled to the 960×544
  framebuffer. Verified [local]:
  * `0x818282A6: movs.w r1,#0x2D0` (720) and `0x818282AC: movs.w r1,#0x198`
    (408);
  * UV-scale floats in segment 1 at `0x81CC6C50` / `0x81CC6C58` hold
    720/736 = 0.97826 and 408/416 = 0.98077.
  * These are exactly the VitaGrafix patch sites for US 1.30.
* **The resolution is the game's own setting** [local, 2026-10-11]:
  `boot_config.ini`'s `ResoDown` is a mode that the render-target setup
  `0x81828272` takes in `r1` (through `0x81828b0e`, called from
  `0x812ab2b8` with the parsed config's `+4`):

  | `ResoDown` | 3D target |
  |---|---|
  | 0, or 4 and up | 960×544 |
  | 1 (retail) | 720×408 |
  | 2 | 640×368 |
  | 3 | 480×272 |

  * Every buffer derived from it follows, but four vertex shaders keep
    the 720×408 mode's depth UV scale (720/736, 408/416) in their literal
    tables, so `ResoDown 0` needs them set to 1.0 (02-baseline, "Haze
    over near objects"). With that it renders correctly and is sharper.
  * Patching only the mode-1 immediates (as VitaGrafix does) breaks
    rendering in Vita3K: `sceGxmColorSurfaceInit` and
    `sceGxmTextureInitLinear` reject their arguments, and the game aborts.
    Other code reads the mode itself.
* **`boot_config.ini` keys** (parser `0x817e7c74`; the config object's
  pointer is at `0x81c9a48c`): `FPS` +0, `ResoDown` +4, `PackFileFirst`
  +0xa, `Trophy` +0xb, `PowerMode` +0xc, `ScreenShot` +0xd,
  `ScreenShotOverlay` +0xe, `CaptureMode` +0xf, `ModeTrial` +0x10,
  `ModeTrialEvent` +0x11, `ModeCompetition` +0x12, `ModeOpenTest` +0x13,
  `ForceDLC` +0x14, `DebugRegionType` +0x1c, `DebugLanguageType` +0x20,
  `EffectReload` and `EffectGpuLimitThreshold` near +0x28 (offsets from a
  pattern scan; the last two are less certain).
* **30 fps** (`FPS 30` in `boot_config.ini`). No 60 fps patch exists anywhere.
  Game logic is presumably frame-locked (**hypothesis**).

### Ad hoc play

[local, 2026-10-12; plan Phase 10]

* **Menu.** Librom → Network → Ad Hoc Play ("Relive quests w/local
  players"): Create Room (a difficulty cap, then the room) or Search for
  Room. The host's room has four player slots, Select Quest, Arm yourself,
  chat and Ready.
* **Imports** (eboot):
  * SceNetCtl's ad hoc calls (state, address, callbacks, disconnect);
  * SceNetAdhocMatching (10: Init, Create, Start, SetHelloOpt,
    SelectTarget, CancelTarget, Stop, Delete, Term);
  * ScePspnetAdhoc (10: PDP create/send/recv/delete, socket alert,
    adhocctl init and ether address);
  * SceLibRudp (19: a reliable stream over a P2P socket);
  * SceNet sockets (socket, bind, listen, accept, send, recv).
* **Vita3K's support** (upstream since late 2025):
  * Entering Ad Hoc Play opens the network check dialog in ad hoc mode.
    That starts NetCtl's peer thread: every second it sends a peer record
    to the adapter's broadcast address on UDP 3658, and it keeps the peers
    it hears from (5 s timeout).
  * A P2P socket on virtual port v is a host UDP (or TCP) socket on port
    3658 + v. Peers are known by their IPv4 address.
  * Matching and Rudp are the firmware's own modules (`adhoc_matching.suprx`,
    `librudp.suprx`), run as LLE; ScePspnetAdhoc is an HLE stub.
* **Seen on one copy** (JIT, slot 2):
  * `adhoc_matching.suprx` loads when Ad Hoc Play opens (code at
    `0x80757000`, 0x3e48 bytes).
  * It imports SceNetInternal `0x689B9D7D`, which Vita3K lacked. Its two
    call sites pass a pointer to one word and use the result modulo a range
    as a nonzero value. **Hypothesis:** a random number (fork patch 0038
    gives one).
  * Create Room works without a peer.
* **Seen on two copies** (`--player`, local mode, JIT then NativeCPU):
  * The host's room appears in the other copy's Search for Room as
    "<name> [1/4]"; joining, Ready ("Finish preparations though you still
    bear the price?" for a sorcerer with a Black Rite price) and Start
    Quest work.
  * In the quest both copies show the same enemies, kills and "targets
    remaining", and the same results page; the "Return To Lobby In" count
    runs on both. A copy still on the save prompt or "Save complete" when
    it reaches 0 shows "You left the room" (and the host "Connection with
    <name> lost"). **Hypothesis:** this is the game's design, not a
    network failure; answering at once returned both to the room.
  * Only `adhoc_matching.suprx` loads; `librudp.suprx` and pspnet_adhoc's
    PDP are not used up to and through a quest (**hypothesis:** they serve
    Play Online).
  * The matching module loaded at `0x80757000` in every play session, and at
    `0x80755000` when `--dump-elfs` loads it at the title.

## Prior work on this game

### loktar00/soul-sacrifice-preservation (most relevant)

<https://github.com/loktar00/soul-sacrifice-preservation>: one public commit
(2026-10-04); notes dated 2026-10-02/03. No game files. A Claude-assisted
solo project by the look of it.

* **Working:**
  * the game in Vita3K at 30 fps;
  * the debug menu;
  * loose-file and `archive_patch1` mods;
  * a mod kit (`ssmod.py`, recipe mods, new quests);
  * `pktool.py` (pk unpack/pack/verify, byte-identical round trip; we used
    its `verify`);
  * a SELF→ELF decryptor (we used it);
  * Ghidra 12.1.3 + VitaLoaderRedux scripts;
  * a Vita3K input driver for automated tests.
* **`port/re/recomp/DESIGN.md`: a static-recompilation design study,
  marked "parked":**
  * Full measurements of the v01.10 eboot (our table above).
  * Comparison of three options: full recomp, hybrid, Vita3K as runtime.
  * Milestone plan M1–M4 and a risk list.
  * **Effort estimates (one experienced dev):**

    | Option | Estimate |
    |---|---|
    | Hybrid in a Vita3K fork | 6–12 months |
    | Full static recompilation with a native runtime | 9–18 months |
    | Emulator wrapper | 1–2 months |
* **Gaps:**
  * Its eboot is v01.10, so addresses differ from our 1.30.
  * Nothing is implemented beyond measurement scripts.
  * Licence statements conflict between files.

**How we use it** (same policy as with DissidiaDecompProject):

* We treat it as leads and as a cross-check, and verify everything ourselves.
* Its Python tools are small and readable; we read them before running them.
* Nothing from it that is derived from the game comes into our repo.

### Vita3K compatibility [web]

| Issue | Version tested | Status | Notes |
|---|---|---|---|
| [compat #523](https://github.com/Vita3K/compatibility/issues/523) | US PCSA00152 | Playable, graphics bug | Mind's Eye (monster HP / soul overlay) broken since commit `d49480f` ([Vita3K#3852](https://github.com/Vita3K/Vita3K/issues/3852)). Surface sync on fixes it but costs fps (8–12 fps). Some users see Vulkan crashes before the logos; OpenGL works |
| [#1911](https://github.com/Vita3K/compatibility/issues/1911) | EU PCSF00532 | Playable, graphics bug | — |
| [#1195](https://github.com/Vita3K/compatibility/issues/1195) | Asia PCSD00079 | Ingame+ | 10–15 fps in quests at any resolution |
| [#886](https://github.com/Vita3K/compatibility/issues/886) | JP PCSC00049 | Playable | — |

[Vita3K-Plus](https://github.com/nckstwrt/Vita3K-Plus) v1.2 (2026-09-30) has
fixes specific to Delta: outlines, floor textures and Mind's Eye in v1.0.

**Takeaways:**

* Vita3K's GXM path is good enough to play this game, but surface-sync
  (render-to-texture readback) is where its remaining bugs are.
* The same pattern bit us on the PSP: framebuffer→texture effects, decimation
  R5.

### Other

* **Title IDs.**
  * Delta: US PCSA00152, EU PCSF00532, JP PCSC00049, Asia PCSD00079; all end
    at 1.30.
  * Original: US PCSA00092, EU PCSF00178, JP PCSC00039, Asia PCSD00065.
* **Online.**
  * PSN servers closed 2021-12-24.
  * Ad hoc works on hardware and over XLink Kai with an eboot patch (US/EU
    1.30) that lifts a ~24 ms ping limit.
  * Vita3K has had basic ad hoc since late 2025 (PR #3623, #3687); nobody has
    reported Soul Sacrifice working over it.
  * No fan PSN server emulator for the Vita exists.
* **Modding scene.**
  * Nothing on ZenHax/XeNTaX/ResHax.
  * Models load in Noesis through a Fate/Extella plugin (`KPKy`).
  * There is a 2016 cheat plugin for 1.30.
* **Developer.** Marvelous AQL, with Comcept as concept and direction lead;
  produced and published by SCE Japan Studio. The engine is an in-house
  Marvelous engine, the same lineage as Fate/Extella (**hypothesis**, based on
  the shared archive format).

## Vita3K as the runtime donor [local source read, commit `741b19ac`]

* **Licence:** GPL-2.0-or-later (`COPYING.txt` GPLv2, file headers say
  "or later").
* **Submodules:** dynarmic (fork), SPIRV-Cross, glslang, capstone,
  psvpfstools, LibAtrac9, ffmpeg-core, SDL3, VMA, cubeb and others; no unicorn.

| Component | Where | Size | Reuse for a recomp runtime |
|---|---|---|---|
| Memory | `vita3k/mem` | ~1.8k lines | Flat 4 GiB host reservation, guest ptr = `base + addr`. This is exactly what generated code wants (decimation uses the same model). Fault handler does write-tracking for the texture cache |
| CPU | `vita3k/cpu` | ~1.3k lines | dynarmic only, a JIT per guest thread. Behind an interface (`cpu/impl/interface.h`) that we can extend with an AOT dispatch table |
| Kernel | `vita3k/kernel` | ~6k lines | **One host thread per guest thread** (SDL threads), host mutex/condvar sync objects. Callbacks into guest code go through `run_callback`/`run_guest_function` (GXM display queue, threads, AvPlayer), which must call recompiled functions instead |
| Loader | `kernel/src/load_self.cpp`, `relocation.cpp` | 863 + 704 lines | SCE ELF loading, imports patched to `svc #0; bx lr; .word NID` (HLE) or to LLE exports. A dump option writes relocated ELFs |
| HLE modules | `vita3k/modules` | ~55k lines, 152 libraries | 7,380 exports, of which 6,175 are `UNIMPLEMENTED` and 125 `STUBBED`, so about **1,100 real implementations**. SceGxm 292 exports (226 real). The bridge reads arguments from `CPUState` registers, so a recomp runtime either keeps a compatible register context (simplest) or calls the `export_*` functions directly |
| LLE modules | `module/src/load_module.cpp:142`, `interface.cpp:519` | — | libc, libfios2 and libult from `app0:sce_module` (and libfiber from firmware) run as **guest ARM code**. So in Vita3K, Soul Sacrifice's C runtime is emulated, not HLE'd (SceLibc HLE is 1,049/1,071 unimplemented) |
| GXM | `modules/SceGxm` + `vita3k/gxm` | 5.9k + 2.7k lines | the GXM state machine and display queue |
| Renderer | `vita3k/renderer` | 25.7k lines (Vulkan 10.2k, GL 5.3k) | surface cache, texture cache (PVRTC/ASTC/YUV), texture replacement, resolution multiplier |
| Shader translator | `vita3k/shader` | 14.4k lines | USSE/GXP → SPIR-V/GLSL; depends only on gxm/util/glslang/spirv-cross. **Liftable as a library**. CLI `--recompile-shader` already exists |
| Patches | `vita3k/patch` | ~500 lines | per-title byte patches by segment + offset |
| AOT / static recomp | — | none | the only cache is the shader cache |

## Recompilation landscape [web]

No Vita game has been publicly ported to PC by recompilation or by
decompilation. Every other "Vita recomp" project goes the other way, porting
*to* the Vita: repentogxm, xita, halo-ce-vita, the so-loader ports. Persona 4
Golden (2020) and Freedom Wars Remastered (2025) reached PC as official
releases; nothing public says how they were built.

| Project | What | Relevance |
|---|---|---|
| [sp00nznet/vitarecomp](https://github.com/sp00nznet/vitarecomp) | Vita SELF → C (MIT, 2026-07/08, 0★; same author as a psprecomp and ps3recomp. Repo exists, HEAD `6ed4a5c`; status figures are from its README, not re-checked) | **The only Vita static recompiler.** It has an ARMv7 + Thumb-2 decoder and a C emitter. On Uncharted: Fight for Fortune it translates 98.95% of instructions, runs `module_start` and 551 constructors, then stops at the first NEON instruction. No GXM, no shaders, no keys (it handles unencrypted modules only). Worth reading its decoder; it is not a framework to fork the way we forked PSPRecomp |
| [MaryNCRT/…UMK3-iOS-Recomp](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp) | iOS armv7 → C (`tools/armrecomp/recomp.py`), Windows/Linux port | The closest ISA match (ARMv7 Thumb-2). Licence unclear; NEON coverage unknown |
| [fearkov/3dsrecomp](https://github.com/fearkov/3dsrecomp) | 3DS ARMv6K ARM/Thumb/VFP → C, interpreter fallback, verify mode | Good fallback and verify architecture. No Thumb-2, no NEON |
| [mstan/gbarecomp](https://github.com/mstan/gbarecomp) | ARMv4T → C with interpreter fallback | interworking patterns only |
| [xerpi/vita2hos](https://github.com/xerpi/vita2hos) | runs Vita ARM code natively on the Switch (AArch32), imports → Horizon OS, Vita3K's shader translator → deko3d | proof that Vita3K's shader translator lifts out. Homebrew/samples only |
| dynarmic (0BSD) | the JIT inside Vita3K | its A32/Thumb decoder and IR could serve as the lifter front-end. It is also the fallback/oracle in option B |
| remill / mcsema / RetDec / rev.ng | general lifters | nothing usable for Thumb-2 + NEON |

Native execution on ARM hardware (vita2hos-style) is not an option on PC.
Windows on ARM64 has no AArch32 mode, and recent Snapdragon cores lack it in
hardware.

**RE tooling:**

* [VitaLoaderRedux](https://github.com/CreepNT/VitaLoaderRedux) for Ghidra
  (needs ELF-PRX; NID db via `VLR_DATABASE_PATH`);
* a Binary Ninja Vita loader;
* vitasdk `vita-headers` db (MIT), which we used;
* TeamFAPS PSVita-RE-tools (FAGDec on hardware, vita-unmake-fself);
* psvpfstools (upstream needs an online F00D service; Vita3K's fork does
  not);
* motoharu-gosuto/psvgxp and the Henkaku wiki for USSE encoding;
* Vita3K's `usse_disasm` is the only maintained GXP disassembler.

## How the Vita differs from the PSP project

| | Dissidia 012 (PSP) | Soul Sacrifice Delta (Vita) |
|---|---|---|
| CPU | MIPS Allegrex + VFPU; fixed 32-bit instructions, delay slots | ARMv7-A Cortex-A9 Thumb-2 + NEON/VFPv3; mixed 16/32-bit, `IT` blocks, NZCV flags on most ALU ops |
| Code | ~5 MB, ~22k functions, EBOOT + 3 overlays | 11.7 MB, 34.6k functions, **no overlays**, plus 3 modules worth recompiling (libc, fios2, ult) |
| Function discovery | heuristics + Ghidra | **exact**, from exidx |
| Recompiler | PSPRecomp/Yakumo existed; we forked | only the early vitarecomp (no NEON, no runtime); in practice we write the decoder and emitter ourselves |
| Graphics | GE display lists, fixed function; we wrote GE→Vulkan | GXM: programmable USSE shaders, tile-based, memory-mapped surfaces. Vita3K's translator plus renderer are the only working implementation |
| OS HLE | ~320 imports; PPSSPP as reference | 704 imports (~430 real); Vita3K as reference **and** donor |
| SIMD | VFPU (we deferred bit-exactness, D12) | NEON + VFP, 17.7% of code; Havok physics. Same choice is available: non-bit-exact first, differential test later |
| Threads | cooperative scheduler | Vita3K: preemptive host threads, real atomics (`ldrex`/`strex` → host CAS) |
| Decryption | PPSSPP dumps the EBOOT | PFS (Vita3K install) + SELF (sceutils), done |
| FMV / audio | PSMF/Atrac3+ | H.264/AAC MP4 (FFmpeg); audio through SceAudio/SceAudiodec (**hypothesis**: AT9 via LibAtrac9) and the game's own `sndx` mixer |
| Reference oracle | PPSSPP, excellent | Vita3K: plays the game, with known graphics bugs |
| Speed headroom | high | Vita3K holds 30 fps on fast PCs; some users report 10–15 fps in quests |

## Approach options

| Option | What | Effort (loktar's estimates, 1 dev) | Verdict |
|---|---|---|---|
| A. Emulator wrapper | Ship Vita3K with fixed settings and patches (resolution via VitaGrafix-style patch, input) | 1–2 months | Works today. Not a port, but a useful baseline and oracle |
| **B. Hybrid AOT in a Vita3K fork** | Recompile Thumb-2 → C++ ahead of time. Vita3K's CPU layer dispatches to native code by address and falls back to dynarmic on a miss. Keep Vita3K's HLE, GXM and renderer | 6–12 months to full coverage, useful at every step | **Recommended.** Same shape as decimation (recompiled code + fallback + reused HLE) |
| C. Full static recomp, own runtime | Generated C++ only; port only the needed parts of Vita3K (GXM/renderer/shader) into our own runtime | 9–18 months | Where B should end up. Get there by deleting dynarmic once coverage is 100% |
| D. Decompilation | — | years | Out of scope; B/C lets us replace functions one at a time later |

Why B first:

* The first frame needs indirect calls, so there is no "small static subset"
  milestone.
* A fallback lets the game run from day one while coverage grows.
* Differential testing against dynarmic is the only practical way to get
  631k NEON/VFP instructions right.

## Risks

1. **NEON/VFP correctness.** This means flush-to-zero, default NaN, the
   `vrecpe`/`vrsqrte` estimate tables and saturating ops, with Havok physics
   on top.
   * **Mitigation:** SIMDe or hand-written SSE/AVX with a per-op test suite,
     plus differential runs against dynarmic.
2. **Thumb-2 flag semantics.** About 3.8M instructions, most of which set
   NZCV.
   * The generated C++ must compute flags lazily, or let the compiler drop
     dead flag stores.
   * Expect large generated sources: a compile-time and memory risk.
   * PSPRecomp output at 5 MB was already about 15 min and 4 GiB per job on
     the mini PC.
3. **Hidden control flow.** Watch for `pop {pc}` used as dispatch, tail calls
   across exidx boundaries, and Thumb/ARM switches through pointers. The
   dynarmic fallback absorbs them.
4. **GXM renderer bugs inherited from Vita3K.** Surface sync, the Mind's Eye
   overlay and particle/fog artifacts.
   * Vita3K-Plus has fixes worth porting.
   * Fixing these is upstream-quality GPU work.
5. **Threads and ULT.** Native code needs a per-thread guest context that
   Vita3K's kernel and HLE can see. `libult` context switching needs host
   fibers.
6. **Frame-locked logic.** Getting 60 fps is unexplored.
7. **Licence.** The runtime is GPL if it takes Vita3K code. That is fine
   privately, but it rules out ever shipping under MIT.
8. **No mature Vita recomp.** We pay the cost of every first-of-a-kind problem.

## Open questions

1. How much guest time goes into the bundled `libc` (memcpy/malloc/strings)?
   Should we HLE those few hot functions natively even in the hybrid?
2. Is the `sndx` audio engine a software mixer in game code, and which codec
   do the voice files use (AT9 or other)? Check `voice_ue` members.
3. How many threads exist at run time, and do any spin on shared memory and
   depend on timing?
4. What does `boot_config.ini`'s `FPS 30` actually gate? Is the simulation
   step fixed per frame?
5. Is Scaleform present (`GFx` strings)?
6. How large is the generated C++ for 3.8M instructions, and how long does it
   take to compile? (Measure this in the first recompiler milestone.)

## Suggested first steps (superseded by [03-plan](03-plan.md); step 1 is done, see [02-baseline](02-baseline.md))

1. **Boot it in our portable Vita3K.** Install the firmware PUPs from Sony,
   enable the debug menu and record a baseline: fps, known bugs, per-thread
   CPU time.
2. **Function inventory.** Write exidx starts + modes and import stubs to a
   CSV, cross-checked in Ghidra 12.1.3 + VitaLoaderRedux.
3. **Prototype emitter** for the integer + VFP-scalar subset. Functions with
   NEON stay on dynarmic.
4. **Build a Vita3K fork with an AOT dispatch hook and differential mode.**
   * Gate: boot to the AQL splash with native code in the loop, and report
     the share of instructions executed natively.

## Workspace state

All of this is outside git. Treat it like decimation's `extracted/`: never
commit anything derived from the game.

| Path | What |
|---|---|
| `rom/…[NoNpDrm].zip` | input, read-only. SHA-256 `18e19949296150776f2190aa15a3b79110a01fa86546bc381497ae7a7654569f` |
| `extracted/nonpdrm/` | raw unzip of the dump (still PFS-encrypted; can be deleted) |
| `extracted/vita3k/` | portable Vita3K v0.2.1 build 4152-38bce160 (`windows-latest.zip` SHA-256 `664dc3c2…4b98`). `config.yml` sets `pref-path` to `fs/`, wizard, Discord and update checks off, audio muted, screenshot key F12. Firmware 3.74 + font package installed (PUPs in `extracted/firmware/`) |
| `extracted/vita3k/fs/ux0/app/PCSA00152/` | PFS-decrypted game, 1.30 merged. `eboot.bin` (SELF) SHA-256 `a13a1bfe…4fed` |
| `extracted/vita3k/fs/ux0/license/PCSA00152/*.rif` | the licence copied from `work.bin` |
| `extracted/elf/eboot.elf` | decrypted 1.30 eboot, SHA-256 `3d6ff43fde5f383d2ba36011eeff98264b37ab447feda9a1143b3a6e9ba8e30b` |
| `extracted/elf/{libc,libfios2,libult,libsmart}.elf` | decrypted modules (`0cffb6b4…`, `b935f9af…`, `20e0b741…`, `1298110d…`) |

Analysis scripts are in `tools/`:

* `velf.py <elf> <vita-headers/db>`: segments, module_info, NID-resolved
  imports/exports, exidx starts;
* `imix.py <elf> <json from velf>`: the Capstone instruction sweep;
* `sfo.py <param.sfo>`: prints the SFO fields.

They need `pyyaml` and `capstone` (pip). NID names come from the vitasdk
`vita-headers` db (`db/360`); download it, as it is not vendored.

SELF decryption used loktar00's `port/tools/re/sceutils3` (needs
`pycryptodome`), with `make_keys.py` run over Vita3K's
`vita3k/packages/src/sce_utils.cpp`.
