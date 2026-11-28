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
  GPL. That is irrelevant for a private, non-distributed build. It
  matters only if we ever publish code (we do now: the fork is published as
  GPL, D17).

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

### EU version (PCSF00532 1.30): the same build [local, 2026-11-17]

Compared from the owner's EU dump (NoNpDrm zip, app + 1.30 patch), with the
modules as `ss-delta.exe --dump-elfs` writes them (decrypted, at their load
addresses), against the US ones:

* Installed `eboot.bin` (1.30): SHA-256 `a1055b12…d27197` (US `a13a1bfe…e64fed`),
  in `game.json`.
* `libc`, `libfios2`, `libult` and every firmware module the game loads
  (sysmodule, libSceFt2, libpvf, libscemp4, libsceavplayer, adhoc_matching):
  **byte-identical** to the US dumps, at the same addresses.
* `eboot.elf`: same size and segments; **1,215 bytes differ**, none of
  them code. In segment 0, two read-only words: the build time string
  (`Jul 29 2014 16:55:43`, US `16:56:14`, at `0x81b98ab8`) and a 4-byte
  build stamp at `0x81b285c0`. In segment 1, about 300 words of initialised
  data (`0x81c9a860`–`0x81ce25e4`) that differ by a near-constant amount,
  values derived from the build time. The EU eboot is the US build,
  linked 31 s earlier.
* `recompile.py` gives the same code hash (`f6f20671281686e3`) and
  byte-identical C++ for both eboots. So the recompiled modules are
  interchangeable, and every guest address `ss-delta.exe` uses (frame
  timer, loading task) holds for EU.
* `param.sfo`: same `c_date` 20140729 and SDK, same `NP_COMMUNICATION_ID`
  and imports from the original game's four regions. Languages: EU has
  English, French, Spanish, German, Italian and English (UK) entries; US has
  English, French, Spanish and Portuguese. Saves go to
  `savedata/PCSF00532`. How the game picks its language: see "Text
  language" below.
* The EU game boots in `ss-delta.exe` on the JIT and on native code (see
  02-baseline).

### Dumps decrypted by an older Vita3K [local, 2026-11-22; GitHub issue #9]

Until upstream commit `57202418` (Dec 2024, "packages: Implement decrypt
fself in a fly"), Vita3K's pkg install decrypted every SELF in place:
`self2elf` (decrypt and decompress the segments into an ELF), then
`make_fself` (the vita-make-fself layout: a 0x1000-byte header with
plaintext, uncompressed segment entries, then the whole ELF; the original
authid is kept). Folders copied out of such an install (shared as
"[vita3k]" dumps) hold that FSELF as `eboot.bin`, so its file hash is
neither of the NoNpDrm ones, though the code is the same.

* Rebuilt from our own decrypted 1.30 ELFs: US
  `b194d16907ce9ff0…4b841a078189` (13,543,649 bytes), the exact hash in the
  #9 reporter's setup.log; EU `1730d04bf05e36d0…f42c4248a28` (derived the
  same way, not yet seen in a real dump). Both are in `game.json`.
* A Python port of the old `self2elf` on the installed US files gives
  `eboot.elf`, `libc`, `libfios2`, `libult` and `libsmart` with exactly the
  hashes in `hashes.md`: the decrypted ELFs are the ones we recompile.
  `sce_sys/about/right.suprx` (system-signed, key revision 1) is left
  encrypted; the game never loads it.
* Vita3K loads an unencrypted FSELF without a licence (`decrypt_fself`
  returns it unchanged), so such a folder needs no `work.bin` or `.rif`.

### Folders copied straight off a Vita [local, 2026-11-22; GitHub issue #13]

A licence (`.rif`, `work.bin`, 0x200 bytes) has its account ID at 0x08.
NoNpDrm's fake licences carry `0x0123456789ABCDEF`, stored little-endian
(`ef cd ab 89 67 45 23 01`: checked in our own dump's `work.bin` and the
installed `ux0/license/PCSA00152/*.rif`), with the content's key in the
clear at 0x50. A work.bin made from a zRIF is one of those.

* **Hypothesis** (from dump guides, no real Vita checked): a game
  installed on a Vita keeps the PSN account's own licence in its
  `sce_sys/package/work.bin`, with the account's ID and a key only that
  console can decrypt. psvpfstools takes the key as it is, so the files.db
  check fails: "header signature is invalid", the #13 reporter's error
  with the encrypted folders. The fix on the Vita is NoNpDrm: started
  once with the plugin, the game gets a fake licence in
  `ux0:nonpdrm/license/app/<title>/6488b73b912a753a492e2714e9b38bc7.rif`.
* Simulated here (our dump's work.bin with another account ID and a
  scrambled key): the install fails at that check, as reported. With the
  fake licence in `license/app/PCSA00152/` beside `app/` and `patch/`, or
  given with `--license`, the fork (game-frontend, `interface.cpp`
  `license_kind`) replaces the account's work.bin and installs the US 1.30
  eboot (`a13a1bfe…`). `dumpinfo.py` tells the two kinds apart the same
  way, so the setup stops before its downloads.
* Before this, a folder install counted as done when any one content in it
  installed (`install_contents(...) > 0`), so a failed game could end as
  "no PCSA00152 or PCSF00532 ... after installing" (#13's third error).
* The reporter's logs bear the hypothesis out. Their Vita's own `work.bin`
  compressed to a 443-byte zRIF (a NoNpDrm licence, mostly zeros,
  compresses to about 64) and failed the files.db check; with the NoNpDrm
  `.rif` in its place the check passed and the game decrypted.
* The second failure (Steam Deck, one folder holding `app/` and `patch/`):
  only the game was decrypted, and its eboot.bin was
  `339fb27bf34794ad…3e3bf8a870`, the US 1.00 one (PFS-decrypted, checked
  against our dump). Vita3K installs a folder's contents in the order
  `recursive_directory_iterator` lists them; Windows lists `app` before
  `patch`, Linux in its file system's order, so the update came first,
  failed with "Install app before patch", and the install still counted as
  done. The fork now installs a folder's or zip's game first, then its
  update, then the rest (`sort_contents`, by param.sfo CATEGORY). Tested
  with the update named so it lists first (`0patch/`, `zapp/`): both
  install and the eboot is 1.30. `game.json` `eboot_sha256_other` names
  the 1.00 hash, so the setup says the update is missing.

### Text language [local, 2026-11-17; GitHub issue #3]

There is no language option in the game: it follows the Vita's system
language, filtered by the region in `boot_config.ini`. Read from the 1.30
eboot (the generated C++'s disassembly comments) and checked in runs: the US
title screen in French and Portuguese, the EU one in German (02-baseline,
"Language setting").

* Globals: the language index at `0x81c9a7c4` (getter `0x81805e1a`,
  setter `0x81805e26`, which accepts 0–15) and the region at `0x81c9a7c8`
  (getter `0x818079f0`, setter `0x818079fc`, which accepts 0–4).
* Boot (`0x812ab1fc`..`0x812ab27c`): `boot_config.ini` is parsed, the
  region is set from `DebugRegionType` (config +0x1c; strings `jp`, `us`,
  `eu`, `as`; both shipped files say `us`), then `0x818cef94` works out
  the language from the region and `sceAppUtilSystemParamGetInt(LANG)`:

  | Region | System language → language index |
  |---|---|
  | 0 (`jp`) | always 0 (Japanese) |
  | 1 (`us`) | French (2) → 5, Spanish (3) → 8, Portuguese-BR (17) → 0xb, anything else → 1 (English) |
  | 2 (`eu`) | French → 5, Spanish → 8, German (4) → 7, Italian (5) → 6, anything else → 4 (English UK) |
  | 4 | Korean (9) → 0xf, Chinese simplified (11) → 0xd, anything else → 0xe |
  | other | the index is left as it was |

* So the US game shows English, French, Spanish or Brazilian Portuguese,
  matching its `param.sfo`. The US `archive` holds text folders `jp`, `us`,
  `fr`, `sp`, `bp` and `it` (`resource/message/<lang>/`,
  `resource/database/boss/message/<lang>/`, `resource/boot/<lang>/`, ...),
  and `resource/data/icon/` has `us`, `fr`, `sp` and `bp` save icons.
  Italian is in the archive but the US region never picks it.
* `DebugLanguageType` (config +0x20) is not used in that path.
* `0x818cf028` (a second `sceAppUtilSystemParamGetInt` caller, also run
  briefly from `0x81275852`) and `0x818ccf34` turn the system language
  into other codes (a bitmask, the `ja`/`en`/`fr`/`pt-br`/... strings of
  `TitleUpdateCheckTask`); they don't choose the text.
* Vita3K hands the game `cfg.sys_lang` (SceAppUtil). `ss-delta.exe` reads
  neither `config.yml` nor the per-title `config/config_<title>.xml` into
  it (the latter only fills `current_config.sys_lang`); up to v0.2.0 the
  game always saw English (US). Since v0.2.1, `[game] language` sets it.

### Button prompts [local, 2026-11-20]

Where the PlayStation button art comes from, read from the 1.30 `archive`
(textures decoded offline; the swizzle is Vita3K's
`resolve_z_order_compressed_image`):

* **Icon atlases.** The HUD and menu prompts are sprites in a few
  128×128 BC3 atlases, `resource/data/texture/com_001_*.gxt`:
  * `com_001_000`: □ ○ × △ in ink blots, L and R, "L HOLD" and "R HOLD";
  * `com_001_002`, `com_001_005`: the same four with HOLD, L/R HOLD, the
    left/right stick and START (`_005` adds SELECT and TOUCH);
  * `com_001_003`: the D-pad directions, each with HOLD, □/○/△ RELEASE;
  * `com_001_001`, `com_001_006`: a small and a large D-pad;
  * `com_001_007`: the word HOLD; `com_001_008`: big "L HOLD"/"R HOLD";
    `com_001_009` (32×64): the right stick with R.

  About 40 sprites in all. The layouts (`resource/data/d2anime/*.d2b`, which
  name their textures by the artists' `D:\project_elder\D2Anime\tga\*.dds`
  paths) use these atlases in 30-odd screens; `com_001_005_jp` alone in
  14 (`com_000_000`, `game_010_000`, `game_039_001`, `menu_009_300`, ...).
* **Regional copies.** The `_jp`, `_us`, `_ue`, `_fr`, `_ge`, `_it`, `_sp`,
  `_bp`, `_cn`, `_kr`, `_tw` copies differ only in the words drawn
  (HOLD, RELEASE, ...): `_jp`, `_us` and `_ue` are byte-identical for
  `000`, `003`, `005`, `007`; `_fr` differs. The layouts name the `_jp`
  file. **Hypothesis:** the game swaps the suffix for the language.
* **Art with buttons drawn in.** Tutorial pictures (shown in the journal,
  Lore > Tactical advice): `game_027_000c` and
  `002c`–`005c` (○ △ □ HOLD R over a scene), `menu_eu_tutorial_002`/`005`/`006`
  (□/○ on hands, □ R), `menu_034_002`/`003` (journal screenshots with small
  button captions; the US copies show "× Back") and
  `menu_eu_tutorial_001c`, a photo of a Vita.
  `menu_006_000` is a Japanese control chart. Found by matching the four
  face symbols over all 3,410 decoded textures (`archive` + `archive_patch3`);
  hits below these were effects and noise.
* **Buttons in text.** The fonts (`resource/font/*.gly` + `.gxt`, U8
  atlases with the `1RRR` swizzle; `.gly` is a big-endian `u16` count and
  a 10-byte header with the cell height at +4, then 14-byte records:
  UTF-16 code, x, y, width, ...; positions in 1/128 pixel) draw △ ○ □
  from `elder_number_font` and × (U+00D7) from `elder_normal_font`.
  `font_config.csv`'s font 1 (the default) looks in `elder_number_font`
  first. The UI also prints × as a multiplication sign ("Ether × 0" in
  the journal). The US text
  uses them rarely: "Press the △ button" (`ingame_tutorial` 3204, 3208;
  `online_text` 1084) and "Press the %lc button" (`ingame_tutorial` 3111),
  where the game puts in the character at run time. Most text names
  buttons in words ("the L button", "the down button").
* `boot/pad_caption_param.csv` (the Offering prompts) names abstract
  keys (0 reset, 1 cast, 2 action, 3/4 left/right stick, +100 HOLD), not
  icons.
* Vita3K's texture replacement keys a texture by
  `(width << 16 | height | gamma << 32 | swizzle << 33) ^ XXH3_64(first mip)`
  (`hash_texture_nostride`). The Xbox labels (03-plan, Phase 8) don't use
  it: they hash the atlas data themselves (FNV-1a 64), which matched the
  archive's bytes in play (2026-11-20: `com_001_000`'s US copy, in the hub
  and in a quest).

### Boot logos [local, 2026-11-20; GitHub issue #6]

What the `Title` boot sequence shows before the title screen, read from
the 1.30 eboot's code and checked in `ss-delta.exe`:

* **`GameLogoControlTask`** (0x60 bytes, vtable `0x81c5edd8`, constructor
  `0x812ad8ce`, created by `0x812ae270`) is a singleton
  (`*0x81c957d0`, set early in the constructor). The constructor fills a
  list of `GameLogoTask`s (+0x50, count +0x48, capacity +0x4c), in order:
  * `VITAwarningscreen_xx` (the health warning, hold 5 s), only when the
    boot config's `+0x1c` (`DebugRegionType`; **hypothesis**: filled with
    the region when the key is unset, US = 1) is 1;
  * `SLS_ESRB_wDESCRIPTORS_resize` (hold 4 s), only when `0x818079f0`
    returns 1 and `*0x81c9a488 + 0x45` is set. The US game doesn't show
    it;
  * `company_logo_scej_00_xx`, `company_logo_scej_01` ("Sony Computer
    Entertainment presents", Japan Studio), `comcept_1024x512`,
    `MAQL_1024x512` (MarvelousAQL).
* It skips them all when the byte at `*0x81c9a488 + 0x54` is set.
  **Hypothesis:** that is the debug parameter `IsModeTGS` (registered at
  `+0x50` of a base 4 bytes into that object, where `SyncFps` at base + 1
  is the known `+5`), a show-floor mode whose title menu has its own
  layout (`m_tgs2013_*`), so not an option for players.
* **Timeline.** Each `GameLogoTask` (0x130 bytes, vtable `0x81c5ee0c`,
  update `0x812ae40e`) counts seconds at +0x48 and plays floats: start
  delay +0x50 (1/6), fade in +0x54 (0.5), hold +0x58, fade out +0x5c
  (0.5), black +0x60 (0.5). Buttons end the hold only after +0x64 seconds,
  which is 999: retail logos can't be skipped. At the end its state
  (+0x44) becomes 3.
* **The control task's update** (`0x812ae354`) starts the next logo when
  the current one is in state 3; past the last (or with an empty list) it
  sets its own state to 2 and the title starts. Its state is 1 from its
  init (`0x812ae322`, once the logos' textures have loaded) to then.
* In the US game the title appeared about 20 s after the window opened
  (2026-11-20, Radeon 760M); the US game shows five logos, no ESRB.
* `[game] skip_intro` (`ss-delta.exe`) sets the five floats of each
  logo to 0 once the control task is in state 1: each logo ends on its
  first frame without being drawn. Recorded frame by frame: black, then
  the game's own "Now Loading..." and the title about 6 s after the
  window opened; loading a save from there works as usual.

### Cheats [local + web, 2026-11-21; GitHub issue #7]

* **Sources.** The VitaCheat database (`r0ah/vitacheat`, `db/PCSA00152.psv`,
  codes by r0ah, AngelofWoe, Yohoki; `db/PCSF00532.psv` by tomberyx) has
  pointer codes for 1.30. There is also a 2016 taiHEN trainer ("Soul
  Sacrifice Delta Trainer", vosman, a Better Amphetamin mod), binary only.
  VitaCheat pointer codes (`$3XNN base off1`, `$3X00 0 offN`, `$3300 0
  value`) read `*base + off1`, then `*(that) + off2` and so on, and write
  the value at the last address. `$7` is the same with a repeat count and
  stride (compression).
* **One root for both regions.** The US codes start at `0x8105D64C`, a
  literal-pool word in the eboot's code that holds `0x81c985e0`; their
  first offsets (`+0x920`, `+0x38`) give `0x81c98f00` and `0x81c98618`.
  The EU codes start at `0x81C98F00` itself. US and EU are one build
  ([EU version](#eu-version-pcsf00532-130-the-same-build-local-2026-11-17)),
  so the same addresses hold for both.
* **The quest's player** (checked with `v3kdrive memdump`/`memwrite` in
  Stage Select quests and from a save):
  * `*0x81c98f00` is a quest object (vtable `0x81c7a40c`) while a quest
    runs, 0 in the hub, menus and Stage Select. Its `+0x18`, `+0x44` and
    `+0x60` all point to the player object (vtable `0x81c61f6c`) in single
    player; the codes use one each. In Ad Hoc Play (two copies, 2026-11-21)
    `+0x18` and `+0x60` are this machine's player on the host and on the
    guest alike; the other sorcerer is a second object of the same class.
  * Every character (player, allies, enemies, bosses) has the same HP
    component at `+0x54` (vtable `0x81c60fbc`, then the HP float at `+0x58`,
    the maximum at `+0xf8`), so scanning the heap for that vtable lists them
    all: goblins 110 or 120, kobolds 90, the Jack-o'-Lantern 2175 (its rank
    0 row says 4350: half, **hypothesis:** single player), the Harpy 1700.
  * Player `+0x58`: HP, a float (1000.0 at level 1). Writing 300.0 made the
    HUD's health bar appear at 30%. `+0x5c` follows it (1000.0 again after
    a refill; **hypothesis:** the bar's displayed value). `+0xf8`: the
    maximum HP, an int (1000).
  * Player `+0xd0`, `+0xd4`: 1 and 1 at level 1 (tomberyx: "Magic-Power",
    "Life-Power"; **hypothesis:** the quest's Magic and Life levels).
  * Player `+0x200 + 4 × slot` (slots 0-5): an offering's uses left; -1 for
    an empty slot, 9999 for an offering without a limit (it still counts
    down from 9999). `+0x218 + 4 × slot`: the uses it started the quest
    with (0 for an empty slot). A cast took slot 1 from 5 to 4, the copy at
    `+0x218` stayed 5.
  * **What a cast spends** (Giant's Arm, 5 casts, in the Harpy quest, no
    cheats): each cast takes one from `+0x204`. At 0 the offering still
    casts once more ("Power of Giant's Arm is almost exhausted." at 1);
    that last cast shows "Giant's Arm was lost." and the slot becomes -1,
    its start at `+0x218` unchanged, so a lost slot (-1, start > 0) and an
    empty one (-1, start 0) differ. Writing the uses back to a lost slot
    brings it back: its icon returns and it casts again.
  * **How long a cast lasts** is separate from the cast limit: an arm
    stays out for its duration (70 s for Giant's Arm), then goes. The
    duration is data, read at each cast, in the game's tables as it holds
    them from boot. Each kind of offering has its own (found 2026-11-21,
    with the story-complete save's created pact and a loadout written into
    the save data's first six words, `+0x0`, `+0xc`, `+0x18` ...: offering
    id, count, 0 for each slot; Portraiture showed the new icons):
    * `boot/arms_param.csv` for arms and weapons on the right arm (126
      rows, 30-180 s): records of 0x128 bytes, the skill id, category,
      control type, then the duration float at `+0xc` and the model name
      at `+0x1c` (`ws170_00` for Giant's Arm, 70.0).
    * `boot/magic_gimmick_param_ply.csv` for summons, transforms, traps,
      healing zones and the like (`生存時間`, lifetime): records of 0x328
      bytes, the skill id, a type, the lifetime float at `+0x8` (the fire
      golem, 1201110: 30 s; the stone shell's boulder, type 4: 15 s). The
      table also holds the game's own short effects (bosses' spells, hit
      effects), so only skills of offerings with a duration count.
    * The self-buffs in that table (type 16: falcon feathers, the
      regeneration offerings; 37 of them) leave the lifetime at 0 and keep
      the duration in their second general parameter (`汎用パラメータ１`,
      "80" for the large falcon feather) as text: from `+0x14` each
      parameter is a string object of 8 bytes (a class word `0x81c5abbc`,
      then a pointer into the table's string pool), so "80" is pointed to
      from `+0x20`. Its timer is in the player object, `+0x254`.
    * `boot/protector_param.csv` for armour and shields (the stone charm's
      armour, 50 s; the shield shard's rock wall, 30 s; 43 rows): records
      of 0x11c bytes found by the skill id, with the duration float just
      before it and the model name (`pa240_00.chr`) just after.
    * `boot/item_param_ply.csv`, the offerings (`効果時間`): records of
      0x6c bytes, the id at `+0x0`, the duration float at `+0x40` (0 none,
      -1 no limit for the cursed swords), the skill at `+0x5c`, the cast
      limit at `+0x64`. This one only says what the game shows: changing
      it had no effect on the arm, the armour or the feather.
    * `boot/skill_param_ply.csv` has a "stock time" (60 for most), not
      the duration.
    * A cast copies the duration into a timer (remaining and total floats,
      in a pooled block with no pointer to it). No pointer leads to the
      tables either, only a tree of the game's tables whose sentinel
      thousands of nodes share, so the cheat finds each by a known record
      pair (arms 1140000/`ws140_00` then 1140100/`ws140_01`; gimmicks
      80100 then 81100; protectors 1240000/`pa240_00.chr` then 1240010;
      offerings 102000 then 102030 with their skills and cast limits).
    * The tables move with the build and the region (US: arms
      `0x82acf654`, gimmicks `0x832c2708`, protectors `0x82ad85c8`,
      offerings `0x8277e950`; EU and the Thor: elsewhere), all found.
  * tomberyx's "One Hit Kill" writes 1.07e20 to player `+0x370`, the first
    of a run of 1.0 floats (**hypothesis:** damage factors). The game sets it
    back to 1.0 from time to time, so it is written every frame. With it,
    goblins (110-120 HP) fell to single hits (six punches without it left one
    at 3), in single player and from an Ad Hoc guest (the host's copy of the
    goblin at 0 too). A boss still took a fifth of its health a hit (the
    Harpy: 1700, 1360, 1020, 680 ... 0, then its dying state as usual): the
    game limits a hit on a boss to 20% (**hypothesis**, from these numbers).
* **The developers' debug menu** [local, 2026-11-26]: the retail eboot
  still builds it. Its values sit in one block, `*0x81c9a488`
  (`0x820161b0` in every US run so far), built at boot and read by the
  game code. `0x817e4f4c` registers the menu: groups through
  `0x81810cfc(parent, name)`, bools through `0x818105a0(group, name,
  &var, ...)`, floats through `0x8181041c`, ints through `0x81810350`, so
  each label (a string in the eboot) gives its field. Offsets from the
  block:
  * Config/Preset at `+0x62`..`+0x65`: InvincibleMode, BG DesignerMode,
    SND DesignerMode, EnemyCheck. Debug at `+0x58`..`+0x61`
    (NoSetSceneEnemy and the like).
  * The Player group from `+0x68` (`0x817e3bfc`): NoDamage `+0x8d`,
    NoDeadEnd `+0x8e`, NoTabooPenalty `+0x8f` (read by the checks of a bit
    mask at `+0xcc`, `0x8135885e` ...; **hypothesis:** the black rites'
    penalties), InfinityMagic
    `+0x90`, Respawn `+0x96`, Limited Death `+0x97`, AI Mode `+0xf1`,
    AutoPilot `+0xf2`, Stop NPC `+0xf8`; PlayerParamRate's AttackRate,
    DamageRate ... RecvDmgRate floats at `+0xd4`..`+0xe8`. Defaults
    seen: TurnLimit[Normal] 360.0 at `+0x70`, MotionSpeed 1.0 at `+0x88`.
  * The Enemy group from `+0x438` (`0x817e3344`): isBossAttackCheck,
    isMobAttackCheck, isMoveStop, isBossNoDamage `+0x43b`, isMobNoDamage
    `+0x43c`, ..., MobKnockBackDecr (float, `+0x468`).
  * `0x817e78fa(block)` is "no damage": NoDamage, InvincibleMode or BG
    DesignerMode. Six callers, all in the player-side character code. The
    hit handler `0x81377452` (a virtual method in 19 vtables, at `+0x190`
    in the player's) returns at once when it is true, or when the
    character's byte `+0x17c3` is set (the game's own short invulnerability,
    set and cleared by event and move code). Otherwise it applies the
    damage (`0x813769ac`) and calls virtual `+0x194`, the hit reaction
    (stagger, knock-down). Four other callers skip `0x8136be14`, the health
    an attack costs (the test loadout's C attack took 5 a press, none with
    NoDamage). Retail code never
    sets NoDamage; `0x817e93c0`, which sets it with NoDeadEnd, is a debug
    preset.
  * Checked in quests (test folder, `memwrite` and then the cheat): with
    NoDamage set, goblins, the Harpy's minions and the Harpy hit the
    sorcerer for 15-30 s at a time and he never staggered, fell or lost
    health; cleared, the same enemies knocked him down twice in 10 s. His
    own attacks still kill. The Harpy's shockwave (landing) and wing gust
    still make him brace for a moment, arm over his face, then stand: a
    reaction outside the hit handler, without damage.
  * Ad Hoc Play (02-baseline): the switch covers only the copy's own
    sorcerer. With it on the guest, the host's sorcerer still took its
    hits and died on both screens, and the reverse; each sorcerer's
    health is its own copy's. The EU game (Android) behaves the same.
  * Not checked: allies, grabs, status ailments, falls.
* **The save data**, `*0x81c98618` (the game's pointer, set from boot; a
  block of more than 1.5 MB, not the file's layout):
  * `+0x8c`: Lacrima (u32). 9627 in memory and on the Portraiture page.
    9,999,999 shows in full there and survives a save and reload. `+0x88`
    held 5,000,000 (unknown).
  * `+0x17ced8`, `+0x17ceda`: the Life and Magic levels (u16), shown as the
    two levels on Portraiture's Right Arm and in `SlotParam_N.bin`'s
    summary ("Life Lv1 Magic Lv99"). Levels end at 99
    (`boot/lowchaos_growth_param.csv`: level, EXP for the next level,
    attack, health ... for levels 1-99). Set to 99 and saved: both still 99
    after a reload, so the game doesn't recompute them from EXP.
  * **Only later in the story.** The late-game save has the level pair in
    eight records of the block (`+0xea2e8`, `+0xeb258`, then five 0x3ec
    apart from `+0x17ba40`, and `+0x17ced8`); in the file they sit 0x8e3f0
    lower. An early save (the journal's first chapters, Life 1 Magic 3 in
    its summary, Portraiture hiding the appearance and the Right Arm) has
    one, at `+0x139fa8`, and zeros at `+0x17ced8`; an early EU save has
    zeros there too. No pointer in the block or the eboot's data points
    near `+0x139fa8`, so the record is found by layout. **Hypothesis:** the
    records are the journal author's and your own sorcerer's, and
    `+0x17ced8` is yours. Max levels acts only when it is set.
  * At boot, before a save loads, the block holds leftovers (levels 63302 /
    30968, refused), then defaults that pass the checks for a moment, so
    the cheats can write there before the save replaces it (logged).
  * **The offering stock** [local, 2026-11-22, corrected; first noted by
    r0ah]: a count at `+0x84` (2196 in Delta 1.30, 2216 with the Spirits'
    offerings switched on), then entries of 0x2c bytes from `+0x88`, one per item
    row of the tables (`5000000` first, then `100010`, `100020` ...): the
    id, four counts (`+0x4`..`+0x10`, copies, one per star rank, at most
    99), four flag words (`+0x14`..`+0x20`: bit 1 obtained, bit 0 new) and
    a word at `+0x28`, 0 to 989 for Delta's rows and 0x7fffffff for the
    Spirits' offerings, which the list shows last (**hypothesis:** a sort
    key). The block builds it from the item tables when the save is
    applied, and matches the save's records by id. Adding one
    (`0x812f3c30`, through `0x812f6ece(block, id, rank, n)` as an offering
    box's gift calls it, `0x816b05ca`) raises the count and sets the
    obtained bit, which stays when the offering is carried (count 0, moved
    to the loadout: the first six 0xc-byte records from `+0x0`, id, rank,
    flags). `0x812f6f8a` counts both.
  * The save file keeps the stock as records of 0x24 bytes (id, counts,
    flags) from image `+0xb4`, written from the block when the game saves:
    a row the tables lack is dropped, one they gain is added.
  * Slayer points (r0ah): Avalon, Sanctuarium, Grim at `+0xe50b0`,
    `+0xe50b4`, `+0xe50b8` (u32; 310, 0, 0 in the test save). Not used yet.

### Mouse camera [local, 2026-11-21]

How the right stick turns the camera in a quest, measured for the mouse
camera (fork `game-frontend/input.cpp`, `MouseCamera`; the table is in
`games/ss-delta/main.cpp`). Stage Select's first quest, US game, native
code, 60 fps setting (55-60 shown). The input pipe's `axes` held the stick;
the yaw is the angle of the compass's red N (top right, centre (1800, 120)
in the 1920×1088 frame) between two screenshots taken during the hold, so
the start of the turn doesn't count.

* **Per axis.** The yaw speed depends on the x value alone: (0.6, ±0.6)
  turns like 0.6, and (0.8, ±0.5) like 0.8. Pushing up or down doesn't
  turn the yaw at all. Stick down (y > 0) looks down; the pitch stops at
  its limits within about 0.3 s at full push.
* **The stick is a byte, 128 at the centre.** Vita3K's `float_to_byte`
  truncates (v + 1) × 127.5, so +0.7 reaches the game as 216 (+88) and
  −0.7 as 38 (−90). The game turned +0.7 at 27°/s and −0.7 at 31°/s,
  which is (90/88) to a high power: the game counts from 128.
* **Speed by push** (degrees per second, steady; push = byte offset /
  127, both directions averaged):

  | push | 0.40 | 0.45 | 0.50 | 0.55 | 0.60 | 0.70 | 0.76 | 0.80 | 0.85 | 0.87 | 0.90 | 0.93 | 0.95 | 1.0 |
  |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
  | °/s | 0 | 0.6 | 2.0 | 4.8 | 9.3 | 28 | 47 | 73 | 119 | 156 | 210 | 355 | ~510 | ~550 |

  Nothing up to 0.40, then about tenfold for each 0.25 (exponential from
  0.6 to 0.9), and almost flat from 0.95. A mouse mapped straight onto
  the stick (motion speed = push) does nothing for slow motions and spins
  for fast ones; the mouse camera asks this table for the push that turns
  at the speed it wants.
* **Short pushes turn less.** Full push held 50 / 100 / 150 / 200 / 300 ms
  turned 7.5 / 27 / 54 / 89 / 138°: about the first 45 ms count for
  nothing, so the camera ramps up. Small mouse flicks (1-2°) arrive at
  65-80%.
* **Hypothesis:** the pitch uses the same table (the compass shows only
  the yaw; the pitch wasn't measured).

### Blitz offerings at 60 fps [local, 2026-11-23; GitHub issue #14]

Reported: at 60 fps a Blitz offering pushes the player farther back on a
hit, so the next cast of the chain doesn't connect; at 30 it works.

* **What they are.** The offerings whose text says "aerial blitz" or
  "low-altitude blitz" (the bird pinions, Traitor's Horn, Flamehag's Red
  Rag, Traitor's Icy Wax, Everyoung Hardwing, and their + forms) have
  magic system 14 in `boot/item_param_ply.csv`. Their skill is a
  `magic_gimmick_param_ply.csv` record of type 9 (`タックル`, tackle) with two
  `magic_explode_param_ply.csv` sub-skills, the hit and the hit chained
  from armour (`鎧連携ヒット`, knockback 2 and 20). The player's motions are
  `PC000_IM_RUSH------_*` (indices 0x157-0x163 of the motion name table
  at `0x81c957e8`); `HT_*` is the bounce after a hit (`衝突落下着地`).
* **The motion steps per frame, not per second** (Firebird Pinion+,
  ST03A, the same cast at 30 and at 60, the position sampled every
  host tick). The player moves by the vector at player `+0x13d8` (x, y, z)
  each game frame: 0.69, then 1.2803 forward and 0.2257 up for 8 frames
  (the rush), then 0.4333 forward with `+0x13fc` falling by 0.0300 every
  frame (gravity). The positions were the same frame for frame at both
  rates, so at 60 the rush took 100 ms instead of 212 ms. Walking, by
  contrast, steps by the frame time. Against a wall, or after a miss, the
  path ends on landing, so the distance is the same at both rates.
* The player's state at `+0x16f4` (previous at `+0x16f8`; set by
  `0x81370d4a`) is 0x2c during the cast, 0x3b during the rush and the
  air phase and 0x3e on landing. State 0x3b is set as an immediate only in
  `0x8153bbc2` and `0x8153f206`, an object whose `+0xc` is the caster: it
  takes the frame time in `s0`, keeps a phase at `+0x4c` (0-8, `tbh` at
  `0x8153f256`; 1 is the rush, and a hit check `0x8153e46a` moves it to 3)
  and counts some of its timers in seconds (`+0x9c` minus the frame time,
  `+0x188` against `+0x18c`). **Hypothesis:** this is the type-9 gimmick's
  controller.
* **The push-back after a hit, measured** (Stage Select quest 318,
  `q_g0001` on `SE01A`: the offering test arena, with one rat-like enemy;
  the enemy held at a fixed spot 7 units ahead of the spawn by writing its
  `+0x650`/`+0x1360` every host tick; lock-on held with L). The rush
  reaches the enemy after 4 frames; the player is then thrown straight
  back at a constant height (1.53) by 0.433 a frame for about a second:
  * 60 fps: 19.7 units in 934 ms; the next cast (rush 11 units plus the
    glide) lands 4 units short of the enemy;
  * 30 fps: 11.6 units in 1024 ms; the next cast passes the enemy's spot.

  So the push lasts a time but moves per frame: about 1.7 times as far at
  60 fps, which is the reported bug.
* **The controller's per-frame steps** (`0x8153f206`, frame time in `s0`):
  phase 1 (the rush) adds 0.7 a frame to a speed at `+0x128` (at most 1.3)
  and the speed to a distance at `+0x124` that ends the rush, then calls
  the mover `0x8136e29e(chara, dir, dt, scale 1.0)`; phases 3, 5, 7 and 8
  (glide, push-back, fall) call `0x8136eeca(chara, chara+0x1370, dt,
  speed, scale 1.0, s3)` at `0x8153f398`, speed being `+0x128` / 3 (phase
  7) or a timer at `+0x148` counted down in seconds (3, 5, 8). Both movers
  step horizontally by speed × scale a frame (the frame time only turns
  the character) and add `s3` × a gravity vector to a velocity at
  `chara+0x13f8` each frame, which they add to the position as it is.
  Phase 8 shrinks a factor at `+0x6c` to a tenth each frame.
* **Fixed (D30):** recompiler overrides (`overrides/eboot.json`) scale those
  steps by k = 30 × the controller's frame time (at most 1). With the fix,
  at 60 fps the rush steps 0.65 a frame and the push 0.217, and the paths
  follow the 30 fps ones in time: the wall cast within 0.5 units; after a
  hit, pushed back 12.4 units (three runs: 12.37, 12.52, 12.37) against
  11.4 at 30 fps (11.41, 11.44, 11.43), from 19.7 before. What is left: at
  60 the finer steps meet the enemy about 0.5 units earlier, and the push
  at 30 runs at 0.416 a frame (1.25 / 3, the speed one 0.05 lower on the
  hit frame), against 0.434 at 60. At 30 fps the steps are as before,
  frame for frame.

### The loading screen at 60 fps [local, 2026-11-23]

Why the quest-start loading screen never ended at 60 fps (02-baseline,
"60 fps: the loading screen"; D16 kept loading screens at 30 for it).

* **The routine that ends it:** `0x812b50ce` (on the NowLoadingTask, `r5`)
  clears the loop bit (bit 2 of `+0x294`) of the animation at `+0x9c` and
  stops five sub-objects (`+0xb0`, 0x30 apart). Callers: `0x812ed4ba`,
  `0x812f00b8` and `0x81711c4e` (the last waits for the task's state 3).
  The quest manager is the singleton `*0x81c985e0` (vtable `0x81c5fa58`,
  update `0x812ef38c`, state at `+0xe364`); the quest loader is
  `*0x81c998b0` (state at `+4`, updated by `0x8165f9ea` with the frame
  time).
* **What goes wrong** (ST03A from Stage Select, the states logged every
  host tick): at 30 fps the screen's opening (state 2) ends at 19.95 s and
  starts `roading_loop` with the loop bit set (state 3, `0x812b5984`:
  `play(anim, "roading_loop", 1.0, loop = 1)`); the loader reaches 7 at
  20.44 s and the loop bit is cleared, so the loop plays to its end
  (state 5 at 22.6 s, idle at 26.1 s). At 60 fps the loader works a step a
  frame and reaches 7 at 19.85 s, while the opening still plays (it lasts
  1.3 s at either rate): the loop bit is cleared before the loop starts,
  the loop starts with it set, and nothing clears it again. A race, not a
  frame-time check; frames shorter than about 1/45 s make the loader win.
* **Fixed (D30):** overrides note a finish that comes in state 2
  (`0x812b50e0`), start the loop without looping then (`0x812b5984`), and
  forget the note on a reset (`0x812b4d80`). At 60 fps without the front
  end's 30 fps switch: ST03A's screen goes 2 → 3 (no loop) → 5 → 0 at the
  same times as at 30 fps (3 at 20.12 s, 5 at 22.75 s, idle at 26.27 s),
  and eight more Stage Select quests (0, 6, 13, 49, 97, 173, 283, 317)
  load the same way. The arena's enemy staggers an idle
  player (states 0x11, 0x12, 0x18) and keeps the cast from starting; the
  dev key `InvincibleMode true` in `config.ini` didn't stop that.
* Getting a Blitz into a Stage Select quest: its loadout is the
  `opevent_reset` set of `boot/magic_setting.csv` (102000, 170000,
  100010), copied into the save data (`*0x81c98618`) and five other copies
  before the quest starts. Writing the offering id into all six copies
  (at `0x83b3e218`, `0x83cbb0b8`, `0x83cbd73c`, `0x83cbddc8`,
  `0x83cbe454`, `0x83cbeae0` in that boot) from the menu works; changing
  the id in the player's slot (`+0x1d0 + 4 × slot`) during a quest doesn't
  change the skill.

### 1/30 s and 960/544 constants in the eboot [local, 2026-11-26]

A static scan of the 1.30 eboot for the float constants a 60 fps or
widescreen fix looks for, after Project Nativ's `dev/hookscan.py`: movw/movt
pairs and pc-relative `ldr`/`vldr` building 1/30 (`0x3d088889`, ±1 ulp),
1/60, 30.0, 60.0, 960/544 (`0x3fe1e1e2`) or 544/960, plus every aligned
word in the image with those values. Nothing was run; the verdicts are from
reading the code.

* **The game counts time in seconds and converts to 30 fps frames
  itself.** `vmov.f32 sN, #30` appears 278 times in 218 functions
  (the usual idiom is frame time × 30 = frames elapsed, e.g. `0x81882c9e`),
  and a global float **30.0 at `0x81c9a484`** (data segment, next to the
  debug config pointer `*0x81c9a488`) is read 65 times in 54 functions; no
  code writes it through its address. 1/30 itself is built in only 14 places, all by
  movw/movt; no literal pool holds it.
* **1/30 sites** (function: what it does):
  * `0x812ac73c`: the frame-time getter's fixed 1/30 when
    `*0x81c9a488 + 5` is set (02-baseline "60 fps study"). Known.
  * `0x812cf524` (`0x812cf55c`), `0x81882c36` (`0x81882c64`), and the
    one-frame character update `0x81672e7c` (`0x81672e82`), called from
    `0x8105f1dc` (the DEBUG MENU's draw), `0x817134bc` and `0x8103ed34`
    behind a flag or button: a **debug pause and frame step**. The flags
    are `*0x81c9a80c + 0x56a` (paused), `+0x568` (stepping) and `+0x569`
    (step now); a step adds exactly 1/30, the normal path the frame time.
    Harmless in play (**hypothesis**: debug only).
  * `0x8167312a` (`0x816732de`), `0x8101b6f0` (`0x8101b828`), `0x816798fe`
    (`0x81679b12`), the last two through `0x81672e90`: one 1/30 update of a
    character right after its motion or position is set, so the new pose
    shows at once. One-off, harmless (**hypothesis**).
  * `0x8151cc34` (`0x8151d31a`), the constructor of the state-0x11 action
    (vtable `0x81c7c614`): duration = motion frames × 1.3 × 1/30, which
    its update `0x8151dc58` counts down by the frame time. Frame count to
    seconds: harmless.
  * `0x81723c9c` (`0x81723e3c`): a timer set to 1/30 minus the frame time
    and counted down in seconds (state 0x327). Harmless.
  * `0x8190f950` (`0x8190facc`) and the rodata struct at `0x81c17780`
    (0.1, 200, 1/30, 0.6, 4, 1, ..., 0.01): world-setup defaults that
    match Havok's `hkpWorldCinfo` (expected minimum step 1/30, then 0.01
    and 20 iterations). `0x81902f82` stores 1/60 and 60 (`0x819040ba`,
    `0x819040c8`) like a default step info. **Hypothesis:** Havok
    defaults, not the step the game uses; how the game steps Havok is not
    answered here.
  * `0x81659334` (`0x816593ec`) and `0x81659112` (`0x8165912e`): the
    journal's episode player (`EpisodePlayer`, `.evep` timelines; the book
    player's update is `0x81694aba`). Its normal update `0x81657bba` takes
    the frame time; `0x81659334` advances the timeline by a fixed 1/30,
    used for catch-up (`+0xf0` whole steps, `+0xf4` the rest,
    `0x81694ea0`), for skipping (`0x81659112`: up to 1,500 × 2 steps) and
    once from `0x81694742` when a page check fails (`0x81694aa6`).
    **Unknown** whether that last path runs every frame in some state.
  * `0x815ed630` (`0x815ed964`), in `MagicBullet`'s code: stores 1/30 at
    object offset `+0x1920` (`+0x920` from the subobject at `+0x1000`).
    The write is gated on bullet parameter flag `0x40`. The shipped
    player, environment and system bullet tables have no entries with
    that flag. The four enemy entries are Red Hood's two intercept
    chains, Sleeping Beauty's intercept projectile and Cinderella's
    throw counter. No direct read of the field was found.
* **960/544** is built 6 times, each stored into a camera-like object
  shortly before `0x81815d22` (**hypothesis:** the projection): `0x8105a55c`
  (`+0x5a4`), `0x812b71b4`, `0x817074aa` (`+0x12c`), `0x817923be`
  (`+0xb4`, a constructor that also sets near 0.5 and far 10000),
  `0x817fb16e` (`+0xac`), `0x817fd598`. These are the sites for the wider
  screens option (03-plan). 544/960 doesn't occur.
* The other 30.0 and 60.0 words are geometry: vector constants loaded
  with `vldr d` (`0x81494854`, `0x81707790`, `0x8171fa38` and its two
  copies) and repeated static records in the data segment (`0x81c9d080`
  onwards, about 0x4d0 apart).
* **What a constant scan can't see:** fixed steps a frame with no
  constant at all (the Blitz controller's 0.7 and 0.433, above) and
  integer frame counters. So this list isn't a list of every 60 fps bug.

Worth checking in play at 30 against 60 fps, most likely first:

1. The reads of `0x81c9a484` that the code doesn't multiply by its own
   frame time (54 of 65 by a simple check:
   the value isn't multiplied by the function's entry `s0`): `vdiv` by 30 (a per-second value made
   per frame, or frames made seconds) in, e.g., `0x81082b54`, `0x810a4902`,
   `0x81113988`, `0x811147ac`, `0x81461c72`, `0x814e3b24`-`0x814e3c4a`,
   `0x81591a36`; and the per-frame movers of the Blitz family
   (`0x8136b022`, `0x8136e7bc`, `0x8136eeca` at `0x8136f35a`,
   `0x8136f54e`), which multiply a step vector by 30.
2. The journal's episode playback (`0x81694742`'s 1/30 tick): text,
   voice and animation timing of a journal page at 60 fps.
3. `MagicBullet` (`0x815ed630`, object offset `+0x1920`): projectile
   offerings and the enemy counterattack branch at 60 fps.

**Physical-console check (2026-11-27).** With the D30 overrides loaded,
Firebird Pinion+ travelled 10.12 units at 29 fps and 10.02 at 60 fps in
the same ST03A wall cast. The rush and air state lasted approximately
0.46 and 0.48 seconds.

**Steam Deck checks.** In *The Sorcerer's Ordeal Ch. 1*, the live episode
cursor advanced 12.199 seconds over 12.194 wall seconds at 30 fps, and
12.116 over 12.112 at 60 fps. Both runs turned to the same narrated page
and showed the same text and animation in the same order. The captured
audio envelope aligned near normal speed, with far weaker matches at
half or double speed. In ST03A, two Fire Dragon Egg shots at each rate
left the active projectile state about 0.68–0.71 seconds after firing.
The state measurements and rendered shots show similar timing at the
two rates. The 1/30 field stayed zero for this offering. Red Hood's
intercept chains on ST02B did set the field to 1/30 at both rates.
For five chains per run, the median measured duration in the moving
state was 1.605 seconds at 30 fps and 1.596 at 60 fps. The homing paths
varied between the two fights. The checked cases did not require a new
eboot override.

### The Graphics pool and the journal crash [local, 2026-11-25]

A RecompLauncher player (0.5.0, EU game) reported a crash when Seeing
Red ch. 3 (Sorcerous Deeds > Grim) was opened again straight from the
journal; their log ended at boot (the asynchronous log wasn't flushed).
The owner reproduced it in the test folder (2026-11-25: save 2, Sorcerer's
Ordeal Ch. 1, a few minutes and several settings-menu visits, then Seeing
Red ch. 3): the game died as the chapter's journal scene began.

* **The crash.** A write to guest address 0 (host `0x400000000`, the
  guest memory base) in libc's `memcpy` (`0x80331d70`), on a job thread
  (`0x812d4e68`) through `0x8189cf88` → `0x8183be28` → `0x8183bbf6`. The
  last loads a texture-like resource: it allocates its size from the
  default heap (`0x8183ba46`); if that fails it tries the memory type
  `0x0c208060` heap (`0x81829606`, the Graphics pool below), and copies
  into the result **without checking it** (`0x8183bde6` → `0x8183bc24`).
  Both heaps full → `memcpy` to NULL. Frames were mapped with the DLL's
  own `g_functions` table (guest address, size, host pointer).
* **The heaps are dlmalloc mspaces** (`0x8180d646` is `mspace_memalign`:
  the magic at `+0x24`, `mflags` at `+0x1bc`, the lock at `+0x1c0`,
  footprint at `+0x1b0`). The default heap's object is `*0x81c9a848`
  (mspace `0x60000008`, 96 MB, CDRAM); the Graphics pool's
  `*0x81c9a808` (mspace `0x89ed49d8`, 56 MB). Each object's `+0xc` is its
  mspace; one segment, starting at mspace − 8, as big as the footprint, so
  a memdump of it walks chunk by chunk.
* **The pools.** At boot `0x812aad70` allocates one 218 MB block
  (`0xda00000`, USER_RW) and `0x812ab13e` carves four pools out of it with
  `0x81804514(size, index, name)`: Default 126.75 MB, Graphics 56 MB
  (`0x812ab1b2`), Sound 25 MB, Collision 10 MB (217.75 MB, 0.25 MB to
  spare). The eboot never calls `sceKernelGetFreeMemorySize`.
* **Measured** (memdumps of the two mspaces through the input pipe, about
  8 a second): in every journal chapter scene the default heap's free top
  drops to 0 at once and stays there for the scene (about a minute), so
  each texture loaded meanwhile goes to the Graphics pool, which then
  shrinks page by page. In one session with `full_3d` (ResoDown 0) the
  Graphics pool's free top went 10.7 → 4.7 → 3.2 → **0.6 MB**; a larger
  texture, or a scene that starts a little lower, is the crash. At the hub
  after loading the same save: Graphics pool 9.7 MB free with ResoDown 0,
  14.3 MB with ResoDown 1 (the retail mode). So `full_3d` (D13) takes about
  **4.6 MB** of the Graphics pool, the Vita's margin in these scenes.
* **Fix** (D30 update): `overrides/eboot.json` makes the block 226 MB
  (`0x812aad88`, `0x812aadb4`) and the Graphics pool 64 MB (`0x812ab1b2`).
  A Graphics pool alone made larger left the Collision pool without memory
  (a null write at `0x9fffdc` at boot). With both: the hub has 17.7 MB free
  in the Graphics pool, and the owner's route (quests, the menu, Seeing
  Red ch. 3 opened again directly) bottomed out at 8.8 MB, without a crash
  [test folder, 2026-11-25]. The default heap still runs empty in those
  scenes, as it does at ResoDown 1. On Android (the Thor, a test package
  with the eboot built for it) the game boots with the 226 MB block and
  loads a save to the hub, no critical log lines; the pool's size there
  wasn't read (memdump is the PC's input pipe).
* Project Nativ (another Vita recompiler) keeps guest surfaces at the
  Vita's size and scales them only on the host GPU, so its higher
  resolutions cost the game no memory; for us that would mean ResoDown 1
  with a larger multiplier (D13), not tried.

### The 3D resolution modes: ResoDown 0-3 [contributor, 2026-11-25, **hypothesis**]

From [#29](https://github.com/vita-recomps/ss-delta/issues/29) (ELLINDON,
read in their own build of the EU eboot, PCSF00532 1.30, the same build as
US, D19); **not checked against our binary yet**:

* Function `0x81828272` takes the mode in r1 and stores it at
  `0x81d3a63c` (`0x81828280`); width and height go to `0x81c9a820` and
  `0x81c9a824`. Mode 0: 960×544 (immediates at `0x81828298`/`0x8182829e`),
  1: 720×408 (`0x818282a6`/`0x818282ac`), **2: 640×368**
  (`0x818282e2`/`0x818282e8`), **3: 480×272** (`0x818282c6`/`0x818282cc`).
  Above 3: 960×544. Compares at `0x8182828a`, `0x818282be`, `0x818282c2`.
* The sizes are then rounded up to 32 (`0x818282fe`-`0x81828308`):
  960×544, 736×416, 640×384, 480×288; their product (`0x8182830c`) sizes
  the buffers.
* Their build sets `ResoDown 3` through `boot_config` for a 0.5× mode on
  weak phones, with the depth-UV literals (as `unscale_depth_uvs` for mode
  0) set to 272/288 in Y. Depth of field, shadows, bloom and Mind's Eye
  weren't checked in every mode.
* For wider screens (03-plan, #28) this is the switch to extend: a wider
  mode would be a fifth case here. A smaller mode also leaves the Graphics
  pool more room (above).

### Sortiara as an ally [local, 2026-11-23]

* **The data is complete.** Sortiara is `ch9000_06` (`ニミュエ`, Nimue):
  * `chara_id_table.csv` (model `np006_bs00_00`, params `!npc001` as Magusar's `ch9000_00`, AI `np006`,
    voice `npc_voice_06`, intro cameras `CAM--_EV_INTORO-NIM_0n`);
  * `npc_param.csv` `np006` (six offerings);
  * `member_list.csv` (portrait `menu_005_120`);
  * `member_variety_list.csv` (variant `ch9004_60`);
  * 22 battle lines in `npc_voice_param.csv`, as many as the other story allies;
  * "Sortiara" in `chara_name_text`.

  `ch9004_60`/`_61` are her story-quest versions (`q_e01xx` lines), `ch9102_*` her boss forms.
* **Missing: a row in `boot/member_add_list.csv`** (`archive` only, 18 rows: chara id, the quest whose
  clear adds the member, a flag, a comment). The loader is `0x817acd54`: table `*0x81c9a39c`, 0x24-byte
  entries {id[16], quest[16], int}, count `*0x81d315f4`. The trial build reads `member_add_list_trial.csv`.
  At a quest clear, `0x812b031e` looks up the quest (`0x817acf84`). If the member isn't in the roster yet
  (`0x812f795a`), `0x812f737e` adds them. A nonzero third column also shows a notice (`0x817429ee`).
  Rows with 0 there (Sympatha, Bowman, Maisie, ...) still join.
* **The roster** is in the play block (`*0x81c98618`): count `+0x5c31c` (495, `member_list.csv`), 0x1c-byte
  entries from `+0x5c320`: {member id, affinity, 0, 0, a value (-1 for unmet), flags, `member_list` record}.
  The member id is `atoi(id+2) × 100 + atoi(id+7)`, so Sortiara is 900006, index 6. Flags bit 1 (2) =
  selectable ally; the add sets bits 0 and 1 (3), clamps affinity to 0..200, zeroes `+0x8`/`+0xc`. The save
  keeps 0x18-byte records from file offset `0x4c360` (Sortiara `0x4c3f0`). Both test saves hold
  affinity (6 early, 12 story-complete) and the value 3 for her, with flags 0.
* **Tested by hand first** (test folder, story-complete save, flags set to 3 in memory with `memwrite`,
  nothing saved):
  * Select Allies lists "Sortiara – Dark Arm III – C", marked NEW.
  * Her details page shows "The Mad Sorceress", Avalon, Affinity C, the six `np006` offerings, Give
    Offering and Undo Death.
  * In a Phantom Quest (Croaking Fiends in the Forest) she spawns with her intro camera, follows and fights.
* **Flags:**
  * Death and sacrifice set bits 2 and 3 over bit 1 (`0x812f74e0` ff.); `0x812f764c` clears them again.
    None of the member accessors (`0x812f7210`–`0x812f7d3e`) clears bit 1.
  * So `[game] sortiara_ally` (D31) adds her only while bits 1–3 are all clear, which makes it once a save.
* **Tested with `sortiara_ally`** (test folder, story-complete save):
  * She joined with the affinity of the save (12).
  * The game wrote her into the file when it saved: record `{900006, 0, 12, 0, 3, 3}`.
  * The file loaded again with the setting off, and she was still an ally.
* **Not checked yet:**
  * affinity growth and her `ch9004_60` variant;
  * her falling, Save/Sacrifice and Undo Death;
  * picking her for a story quest in which she already appears;
  * a new game before her chapter, where her record may still be unmet (-1);
  * Ad Hoc Play with a peer without the setting (the member id is in every copy's tables, so probably
    harmless: **hypothesis**).

### "Failed to load save data." with the add-on gifts [local, 2026-11-23]

* **The save's checksum:** `+0x1c` of the file holds CRC-32/BZIP2 (`0x81803dc2`) of all 0xef0e0 bytes,
  with `+0x1c` taken as 0, whenever `+0x18` is 0x22. `0x8178322a` sets it before the file is written.
* **The check:** a load reads the file into the image (`*0x81c9a160`) and shows "Loading complete". Once
  the player confirms, `0x8178ab88` checks it with `0x81783248`, which zeroes `+0x1c` and doesn't put it
  back (seen: the image's `+0x1c` is 0 in the hub).
* **The cause:** `[game] dlc`'s gift grant (`grant_addon_gifts`, twice a second) gave its gifts in the
  image while that dialog was up. The check then failed: "Failed to load save data.", and back to the
  title. It hits every save that was never written with the gifts in it: here the story-complete save
  (ss-delta 0.5.0, the test folder; it loaded with `dlc = false`). A save that already had them (the
  test folder's slot 1) wrote nothing and loaded.
* **Fixed in the fork:**
  * The grant leaves an image alone while its checksum is set but doesn't match: the game is still
    filling or writing it.
  * Over an image whose checksum matches (a file just read, or just written), it writes and then sets the
    checksum again.
  * Tested: the dialog was left up 12 s, the image's CRC matched after the gifts were given, the save
    loaded, and after an in-game save the file held the gifts with a valid checksum.

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
* **Loose files override archives** [loktar], **not for the boot tables or
  models** [local, 2026-11-22]: with `resource/boot/parts_upper_param.csv`
  and models served as new files under `app0:`, the game never looked for
  them; the only loose path it stats in a whole boot is
  `resource/database/gimmick/gm00_07_000_ext.csv`. Archives are mounted by
  the app version (`0x812abc7c`; paths at `0x81c95700`): `archive`, then
  **one** patch archive, the highest the version allows (version ≥ 0x11e:
  `archive_patch3`, ≥ 0x114: `_patch2`, ≥ 0x10a: `_patch1`, ≥ 0x101:
  `_patch0`). So `archive_patch1` isn't a usable extra slot on 1.30, and a
  mod has to replace `archive_patch3`, as the Undub does.
  * With `PackFileFirst false` (`[boot_config]` in `ss-delta.ini`) a loose
    `resource/boot/magic_setting.csv` *was* read [local, 2026-11-23]: its
    changed `opevent_reset` row showed up in the parsed table in memory.
    So boot tables can load loose with that key (as `chara_param.csv` did,
    Assets above); the 2026-11-22 test ran without it (**hypothesis**).
* **LSPK archives** [local, 2026-11-22]: `.pkh` is a big-endian count, then
  16-byte entries (path hash, offset, size, compressed size or 0 if stored)
  sorted by hash; `.pk` members start at 16-byte offsets, zlib-compressed.
  The `.pfs` name tree isn't read by the game. `tools/lspk.py pack` writes a
  copy with members added or replaced, and the game reads it (served through
  rePatch, test folder).
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
* **Content from the original game, and locked raiments** [local + web,
  2026-11-21, GitHub issue #11]:
  * The entitlement table's box ids are resolved by
    `database/network/itembox_fixed.csv`: `COSTUME_nn` gives
    `costume_table.csv` rows (`COSTUME_01` = row 156 ×13, Soulbinder A–F
    and the faction colours; `_02` 180 Necky; `_03` 360 Slave; `_04` 372
    Archsorcerer; `_05` 528 Mad Witch; `_06` 252 Easterner ×6; `_07` 312
    Saint ×6; `_08` 324 Beast ×6; `_10` 600 White Cat; `_09`/`_11` 612
    Sylvan, never released). `PARTS_01`–`_08` give hoods 104–111 (Fox Hood,
    Demon's Horns, Golden Mask, Mind's Eyewear, Wizard's Hat, Magic Helm,
    Polytan Hood, Possessed Mask) and `STAMP_01` sigil 7101900 (Fox Sigil).
    In the west, Soulbinder, the hoods and the Slave raiment were Delta's
    first-four-weeks PSN bundle [web, PlayStation Blog 2014-05-13]. They are
    handed out only through Cassus's Claim Gift page (above), so offline they
    can't be obtained. Our `system.bin` lists don't include them.
  * **Their names in the game** [local, 2026-11-22, US game]: three gift
    names differ from the raiment's own. Necky (row 180, type 29) is
    **Fox**, Archsorcerer (372, type 41, `大魔導士の法衣`) is **Great Seer**,
    Saint (312, type 21, `仮１の法衣` in the table's comment) is
    **Disciple**. Raiments: Top lists owned raiments in type order (the
    table's third column), which places type 21 between Wanderer (20) and
    Healer (24). Column 4 of `costume_table.csv` is the sex: 0 both, 1
    male only (Great Seer), 2 female only (Mad Witch 528, White Cat 600).
    Screenshots of all of them: [GALLERY](GALLERY.md).
  * **The right arm's look** [local, 2026-11-22]: the sigil carved in the
    arm's **Hand** slot (Carve Sigil, Up from the top sigil; "Affects right
    arm") decides the arm model, from `parts_hand_param.csv` (186 rows:
    neutral `AR00`, the Life and Magic stages `AR01`/`AR02`, allies' and
    monsters' arms). The story-complete save's hand sigil "Arm of the
    Grandmagus" draws Magusar's arm. With no hand sigil, the Life and Magic
    levels choose it: Magic 99 gave Dark Arm VI, Life 1 Magic 1 (set in
    memory, saved and loaded again) a plain arm and "Neutral Arm".
  * The four tables (`entitlement_table.csv` JP, `_us`, `_eu`, `_as`) list
    the same 21 boxes in the same order. The game picks one by the region
    at `*0x81c9a7c8` (0 JP, 1 US, 2 EU, 4 Asia; loader `0x817ec5c0`) and
    maps each product id to its box (index into the name table at
    `0x81c9301c`: TSS 0–19, NEAR 20, CATALYST 21–30, COSTUME 31–45, PARTS
    46–60, STAMP 61–70) and to its data row, counted from 0 after the
    header (the CSV reader `0x81aae178` skips to the next line before each
    read).
  * **What taking a gift does** [local, verified in runs 2026-11-21]
    (`0x816b06e6` ff., the gift's kind 2 raiment, 3 hood, 4 sigil):
    * Received gifts: a byte per table row at `*0x81c9a160 + 0xc2ec8`,
      set to 1 (`0x816b0a7e`). `*0x81c9a160` is the save file's image in
      memory (its header `+0x8` is the file size, 0xef0e0), 0x8e3f0 past
      the play block `*0x81c98618`; offsets into it are file offsets.
    * Raiments: `0x812f8834(block, row)` sets the row's state from 0
      (hidden) or 4 (shown, not owned: a colour still to be traded for) to
      1 (new); the raiment list shows NEW and makes it 3 once seen. The
      block holds 0x2c-byte entries from `+0x6ab28` (row, state at
      `+0x14`; count `+0x6ab24`, 720). The file keeps 8 bytes a row (row,
      state) from image `+0x84 + 0x522dc`, copied into the block when the
      save is applied (`0x812f5c32`) and back when it is written. Granting
      a colour A (costume record: type `+0x4` below 0x1c and not 5,
      colour `+0xc` 0; records of 0x5c bytes at `*0x81c9a28c`,
      `*0x81d301d0` of them) also gives rows +9 to +11, its faction
      colours. A box's count: up to 12 rows from the first; 13: colours
      A–F and the faction colours; 14: G–I and the faction colours; 15: A
      and the faction colours.
    * Hoods: a u16 per attach id below 0x80 at image `+0x84 + 0x568dc + 2 ×
      id` (`+0x579d4` from 0x80), bit n for colour n and bit 15 for new
      (`0x817808c8`, `0x8178095e`).
    * Sigils: a byte at image `+0x84 + 0x564dc +` the stamp's index in the
      stamp table (`*0x81c9a3e4`, records of 0xb4 bytes with the id at
      `+0x4`, `*0x81d329b0` of them), bits 0, 1, 2 set (`0x81780708`,
      `0x8178072a`, `0x81780768`).
    * A load of an old save (US version `0x22` in the image's `+0x4`; 1.30
      writes `0x3a`) checks the first 19 received bytes against owned
      catalysts and raiments 99 and 117 and clears the unmatched ones
      (`0x812f5ff2`), so it doesn't apply to current saves.
    * The game reads into the image several times: the slot list, the
      load, and `datag000N.bak` once the hub is reached (read only; no file
      is written). Before a load it holds defaults, sometimes half-built
      (raiment records not yet numbered).
  * The `system.bin` list at `0x344` (112–119, 130) matches hood ids from
    `attach_param_text` (112 Noble's Mask+ ...) better than costume rows, and
    the one at `0x224` holds costume rows 624, 696, 708 (Mononofu, Sinner,
    God Eater, colour A) (**hypothesis**; `saves.cpp` calls the `0x344` list
    raiments). The story-complete Apollo save already owned Easterner,
    Beast, Healer, Slave and White Cat; an early save (slot 1 of the test
    folder) owned none of them before the gifts.
  * `costume_table.csv` rows whose appearance condition is `q_a9999` are
    the special-unlock raiments: 156 Soulbinder, 168 Benkei (JP collab, in no
    entitlement box), 180 Necky, 252, 312, 324, 336, 360, 600, 612, 624,
    648/660/672 (Wild Arms), 684, 696, 708. Their models (`UP19`, `UP23`,
    `UP29`, ...) are all in `archive`. Every `UP`/`LW`/`CS` model in the
    archives is referenced by the parts tables, so nothing else is hidden.
  * Only in the original game: the Ragnarok Odyssey ACE raiment
    (Dragonslayer, text 3956) and the Japan-only PSO2 ARKS Armor (text 3954)
    have names in `d2a_text` but no costume rows and no models; for the
    original's pre-order Spirits' offerings see "What only the original
    has" below (Delta keeps their names and, commented out, their rows). Black Rite Angelus (an original-game
    DLC) is `TABOO_06` in `taboo_param.csv`, the Sanctuarium faction's rite
    in Delta [web, TV Tropes], so it isn't missing.
  * **The original's collaboration raiments** [local, 2026-11-22; the EU
    original, PCSF00178 1.30, a NoNpDrm dump installed with `ss-delta.exe
    --install-content` into a scratch file system]: its 1.30
    `costume_table.csv` ends with `#コラボ衣装`, three raiments of one colour
    each: row 117 Mononofu (text 3955), 118 ARKS Armor (3954), 119
    Dragonslayer / Ace of Souls (3956). `parts_body_param.csv` gives their
    whole-body models `CS20`, `CS21`, `CS22` (`_M0`, `_F0`). The add-ons that
    unlocked them are "TOUKIDEN Collaboration Costume: Mononofu" and
    "Ragnarok Odyssey Ace Collaboration Costume: Ace of Souls"
    (`SSS000FZN…`, licence-only add-ons). The original 1.00 (a decrypted US
    VPK, PCSA00092) has none of them.
    * Delta remade Mononofu as `UP20`/`LW20`. For `CS21` and `CS22` Delta's
      archives hold only the `.chr` (the same bytes as the original's) and
      `CS21_F0_HKS.hks`: the 4 `.mdl` and 23 `.mxt` (`CS21_F0`, `CS21_F1`,
      `CS21_M0_00`, `CS21_M0_01`, `CS22_F0`, `CS22_M0` textures) exist only in
      the original. Delta's `CS12`–`CS15` `.chr`/`.mxt` are leftovers too.
    * The `.chr` files use Delta's skeleton (`CS00_SKL.skl`) and format, so a
      whole-body model works as a raiment part: with `CS22` as a raiment's
      upper and lower model (`parts_upper_param.csv`, `parts_lower_param.csv`,
      the model and textures packed into `archive_patch3`), Delta draws the
      whole Ace of Souls, horns, armour and wings, in Raiments [test folder,
      2026-11-22]. As the top with one of Delta's bottoms, the bottom covers
      the costume's legs (Intellectual, Knight, Sand Dweller tried; no
      flicker).
  * **The eraser tables** (`parts_upper_eraser_param.csv`: a top's model name,
    then a 1 for each mesh set it hides in the bottom; `_lower_` the other
    way round) hide **switchable sets** only. The model loader (`0x81869080`
    ff.) cuts each mesh name at `-geom-P`, and registers it under its base
    name only when it ends in `_before` (shown) or `_after` (hidden), e.g.
    `Waist_Parts_before` → column `Waist_Parts`. A part's main mesh
    (`SET_model_2-geom-P0` in 59 bottoms, `SET_model_1` in 19, ...) has
    neither, so no eraser hides it. Renaming a bottom's main mesh in place to
    `S_before-geom-P0` didn't make an `S` column hide it either, and one such
    test aborted the game in the preview (`sceKernelCallAbortHandler`). The
    tables' arrays grow (initial 20), so their size isn't the limit.
  * **Raiments added past row 719** [local, 2026-11-22, the mod of D28]:
    with `costume_table.csv` at 744 rows the game's costume count
    (`*0x81d301d0`) is 744 and the play block's raiment table grows with it
    (`+0x6ab24` = 744, rows numbered, state 0). The save image keeps 0x300
    records; those past the table's rows hold `{0xffffffff, 0}` until the
    game writes the save with the longer table, which then stores them as
    `{row, state}` (a save with the mod: `{720, 3}`, `{732, 3}` once seen).
    The text ids, type numbers 51 and 52 (Delta's last is 50) and the
    whole-body models drew in Raiments, Portraiture and the hub; "Match with
    Above" puts the same raiment on as the bottom.
  * **The raiment worn** is two u16 costume rows (top, bottom) in three
    records of the image: `+0x5b770`/`+0x5b774`, `+0x5bf96`/`+0x5bf9a`,
    `+0xeeb86`/`+0xeeb8a` (9 and 117 in the test save before, 732 and 732
    with Dragonslayer worn). The play block holds no copy. A save that wears
    a row the table lacks (the mod removed) loads, but the body isn't drawn
    (head and right arm only) until another raiment is put on; the list
    shows the missing one as the first raiment. Setting the records to 0
    in memory came too late once the hub was loaded, and doing it every
    frame during the load stalled the game at the title (no menu), so it
    is only reported.
  * **What only the original has** [local, 2026-11-22; the EU original
    1.30, its `archive_patch3` over `archive`, against Delta 1.30 (US); the
    tables joined to the English text, by name and then by id]:
    * Raiments: ARKS Costume (Delta's text: ARKS Armor) and Ace of Souls
      (Dragonslayer), the og-raiments mod (D28). Mononofu is in Delta, remade.
      Faces, hair, arms and low-chaos bodies: all of the original's models
      are in Delta's parts tables; of the body models only `CS20` (Mononofu,
      remade), `CS21` and `CS22` aren't.
    * **The 20 Spirits' offerings** (items 600000–601900: Spirits'
      Flamepike, Frostblade, Firearm, Stormfist, Flame Arrow, Stone Arrow,
      Blazestone, Blightstone, Greatroot, Fulgurwood, Dragon fang, Wolf fang,
      Heart, Flamebulb, Frostfluff, Storm Pinion, Storm Ward, Viviblossom,
      Falconfeather, Stoneshield): the original's pre-order offerings, item
      rows with skills 1600000–1601900 (`炎の剣（※特典用）`, "for the bonus").
      Delta keeps their names in `item_param_text` (a few renamed: Icebrand,
      Sparktree, Halebloom, Gravelshield; 601800 is "test"). Correction:
      earlier notes said Delta's item text lacked them.
      * **Delta has their rows, commented out** [local, 2026-11-22]: `;600000`
        … `;601900` in `item_param_ply.csv` (already filled in for Delta's
        new columns `状態異常値`, `威力(属性値のみ)`), and `;`-rows in
        `skill_param_ply` (49 of the original's 51), `magic_eff_pack_param_ply`
        (49), `magic_explode_param_ply` (44), `magic_gimmick_param_ply` (12),
        `magic_bullet_param_ply` (5), `magic_crawl_param_ply` (6),
        `arms_param.csv` (`;ws1600000` …, 6) and `protector_param.csv` (2).
        Missing: only `1601001` and `1601101`, the punch-effect rows of the
        two fang arms (Delta dropped the regular arms' matching rows too).
        Most rows are the original's plus Delta's padding columns; a few
        were moved to Delta's versions of the regular spells: the root and
        lightning crawl charge (gimmick params 1.3/3 → 0.7/2.3), Flamebulb
        (5 → 35), Frostfluff (type 5 → 47, lifetime 6 → 30, Delta's Snowtuft).
      * **They are copies of regular offerings, not new spells** [local,
        2026-11-22; every row of each Spirit tree compared with the closest
        regular row]: each skill row equals a regular Lv.1 skill except the
        effect pack ID (same attack motion, cast time, controls); each
        effect, bullet, crawl and gimmick row equals a regular row except the
        damage and element numbers and the sub-skill IDs; the weapon and
        armour rows use the regular models (`ws161_01`, `ws162_01`,
        `ws171_01`, `ws173_01`, `ws141_01`, `ws142_01`, `pa243_01`,
        `pa2401_01`). No `.efp`, model or sound file differs, except Spirits'
        Stone Arrow's hit sound (`hit_general` instead of `hit_rock`). They
        copy, in Delta's names: Imp/Devil Pitchfork (Flamepike), Swordsman
        Icebrand, Firegiant's Arm, Stormgiant's Arm, Fire Djinn's Arrow (M,
        four shots), Stone Arrow (M), Firedrake Egg, Leafdrake Egg, Great
        Tree Root (Tri), Sparktree Root (Tri), Firedrake Fang (M), Blizzard
        Wolf Fang (M), Stonefiend Entrails, Blaze Bulb, Snowtuft (M),
        Stormbird Pinion (M), Lightning Amulet, Healing Bloom (M), Falcon
        Feather (M), Gravelshield Fragment. Differences in play are numbers
        only: damage between the Lv.1 and Lv.2 items, the fang arms' punch
        knock-back (7 against 0.7), the Stonefiend's gimmick param 0 (500
        against 7000), Healing Bloom's 15 s / radius 5 (13 s / 5.5), Falcon
        Feather's param 1 (15 against 25 in the original, 70 in Delta). The
        regular rows of Falcon Feather, the root crawls, Snowtuft and
        Leafdrake Egg have effect slots Delta added (`EFF_mg209_20x`,
        `EFF_mg303_200`, `EFF_mg300_200`, `EFF_mg311_200`, `EFF_mg323_204`)
        that the Spirit rows leave empty.
      * **Switched on** (D29, `[game] spirits_offerings`): with the rows
        appended without the `;`, all
        20 are in the offering stock (entries 990-1009) and Select
        Offerings, sorted last; given in memory, Spirits' Flamepike (the
        flaming pitchfork), Wolf fang (the ice arm, thrust and breath) and
        Heart (the stone golem) cast in a try-out [test folder]. Delta's
        `itembox_fixed.csv` still has the original's offering boxes
        `CATALYST_01`-`_17` (19 of the 20; Spirits' Heart is in none), but
        no entitlement table names them.
      * **The fang arms' thrust** [local, 2026-11-24; GitHub issue #18]:
        `chara_motion_combo_param.csv` has active rows for the Spirit arms
        (1494-1541, Delta's file line numbers), and the two fang punches
        (`CH_ATD01_01_M`, `CH_ATIW01_01_M`, level 1) name 1601001/1601101,
        which only the original has (its punch-effect skills, no damage).
        Delta's own fang punch rows name the damage skill (`1142103` for
        Blizzard Wolf Fang (M)). A thrust that hit an enemy crashed the
        game (read of guest address 0, the same in a reporter's log on an
        RTX 5080) or did nothing. Fixed in D29's package (version 2).
      * **The arrows drew nothing: continuation rows** [local, 2026-11-24;
        GitHub issue #19]: Spirits' Flame Arrow cast (aim reticle, the Fire
        prompt) but no arrows appeared and nothing was hit; Fire Djinn's
        Arrow (L) in the same try-out worked.
        * `magic_eff_pack_param_ply.csv` has **continuation rows**: lines
          with an empty ID that belong to the row above (3,004 in Delta).
          A throw's pack (`1121010`) is followed by four `投擲準備` (throw
          preparation) rows, one hover position per arrow. Delta commented
          out only the first line of each Spirit pack (`;1600400`), not its
          continuation rows, and D29's package took only the `;` lines: the
          Spirit throws had no arrows.
        * 16 of the 49 Spirit packs have continuation rows (47 lines): the
          swords `1600001`/`1600101` (6 each), the giant arms
          `1600201`/`1600301` (4), both throws (4), the eggs and the
          root/spark crawls with their shots (2 each), Frostfluff
          (`1601400`, 2), Falconfeather (`1601800`, 1). No other Spirit table
          has continuation rows, and none of the tables has a commented one
          (`;,`).
        * Found by swapping: the Spirit skill pointed at Delta's pack
          `1121010` drew arrows. Ruled out on the way (each tried alone in a
          try-out): the gimmick's general parameter 1 (0 in the Spirit and
          all of the original's arrows, 0.45 in Delta's; no change) and
          Delta's "強化" (enhanced) projectile slot (the element's sub-skill,
          5 for fire, 8 for stone; the Spirit projectile there crashed the
          cast, read of guest `0x2beb6b09`).
        * Fixed in D29's package (version 3): each row taken with its
          continuation rows. Spirits' Flame Arrow then draws its four
          arrows, locks on and kills the try-out's goblin; Spirits' Stone
          Arrow draws its rocks.
        * In Delta itself the 47 lines stay active after the commented
          block. **Hypothesis:** the game reads them as further effects of
          the last active row before the block, `1514621` (a boss's
          Gungnir Lv3 projectile, which has 3 of its own).
    * Sanguine Shot (and its Godly and Diabolic forms, items 100000/50/60):
      the original's right-arm shot, replaced in Delta by Sanguine Cannon,
      Angelshot and Demonshot. A mechanic changed, not content removed.
    * Not missing: the other 51 offering names, 57 sigils, 8 souls and 154
      character names that differ are the same ids renamed (Iron Pinwheel →
      Iron Mill, Fire Giant's Arm → Firegiant's Arm, Effulgent Sigil →
      Gleaming Sigil, Iron Maiden → Iron Virgin, Great Sorcerer → Great Seer).
      Black Rites: all 14 in Delta. Quests: every quest and event (DLC) quest
      of the original is in Delta; the 16 ids only the original has are
      unused rows (`q_a0000`–`0009` "@No Data", and `q_d1902`–`q_d2003`,
      empty duplicates of the Impure Blood and Knight of Vengeance chapters
      that Delta has as `q_e05xx`/`q_e09xx`; Delta lists them only in
      `old_quest_list.csv`, for imported saves).
* **Blank Page slots (Memory Clods)** [local, verified in runs 2026-11-23,
  GitHub issue #15]:
  * Blank Page is on Librom's own menu (Read Journal, Talk to Librom, Blank
    Page, Network), not on the hub's. Its screen (`0x810248c8`) has **8
    slots**: three on the left page and five under "Psychic link" on the
    right, which are inked out while locked.
  * Unlocked slots are a bitmask, bit n for slot n: a u32 at `*0x81c9a160 +
    0xc075c` (`0x81789d02`) `+ 0x1da0 + 0xc`, i.e. **file offset `0xc2508`
    of `datag000N.bin`**. Every save seen has `0x7`, including the
    story-complete one. `0x81024158` offers the unlock for a locked slot
    below 8 (text 10062400, "Progress is automatically saved when unlocking
    a new blank page"). On Yes, `0x81024c14` sets the bit and saves.
  * The other five needed **Memory Clods**, a PlayStation Store consumable
    (`system_text` 2004–2012). With the mask set to `0xff` in memory, all 8
    slots read "Blank", a pact page was made in slot 4 (Normal, an
    Offering), and the game's auto-save wrote `0xff` to the `.bin` and the
    `.bak` [test folder, story-complete save]. `[game] dlc` now sets it (D14
    update 2).
  * Erasing a page (□ on the slot list) works on the new slots too: a page
    made in slot 4 and erased read "Blank" again [test folder].
  * **"Sacrifice memory"** (Create page → difficulty → the right-hand
    choice) made a page with one Memory Clod in place of an Offering, with
    its own reward rules (2211–2221: accessories not yet owned, then a voice,
    then Rumor Notes). Every clod spend is a network task: `0x81278238`
    makes it from a request (kind, two system texts, the clods needed),
    `0x812782f4` runs it (vtable `0x81c5d004`, at `*0x81c953d0` while it
    lives). `+0x44` is its state (`tbh` at `0x81278364`, 14 states),
    `+0x48` is 1 once the clods are spent, which only state 11
    (`0x81278412`) writes, `+0x54` 1 for a page and 3 for a slot (the clods
    needed, **hypothesis**: texts 2006 and 2011 show such a count),
    `+0x58`/`+0x5c` the
    texts of its dialogs (2007 "Insufficient Memory Clods" for a page and
    for a slot), `+0x60` 1 for the store page (START, "Add memory", text
    2004). Requests: `0x81021afe` (create screen, kind 1), `0x81024ff2`
    (slot unlock, kind 3), `0x810253c0` (store page). Offline it ends
    without `+0x48`. The create screen waits while the task lives and takes
    `+0x48` = 1 as paid (`0x81021838`), then makes the page and saves.
    `[game] dlc` now writes the 1 while a spend runs (not for the store
    page): a page was made this way, saved, its three pacts listed and
    played [test folder, 2026-11-23]. Where the clod count itself comes
    from (`sceNpAuthGetEntitlementById`, `sceNpTus` variables) is still not
    traced; nothing needs it now.
  * **The bosses a page can roll** are `boot/white_page_boss.csv`
    (`archive_patch3`): one row per boss, with its element, whether it pairs
    in a Gemini pact, its own map (`ST20A` Hansel & Gretel, `ST16A`
    Leviathan, `ST17C` Magusar's forms), unlock columns (after the first
    clear, after the last chapter, after a quest: `q_e0273` for Terrwyn),
    the name text (`whitepage_quest_name_text`, e.g. 30430 "Candy Kids"),
    the maps it fits and its music. Chimera (`ch7512`), the Pied Piper of
    Hamelin (`ch7112`), Terrwyn (`ch7412`) and Hansel & Gretel (`ch7302`),
    which players report as met only through Blank Pages, are rows there.
    Each was forced as the only rollable boss (a loose copy of the table
    with `PackFileFirst false`, test folder only) and played in a page made
    with Sacrifice memory: Terrwyn in Noah's Desert East, the Pied Piper on
    Leviathan's 2nd floor, Hansel & Gretel at the Gingerbread House (two
    bodies sharing 14,500–17,400 HP), Chimera in the Ruins of Tartarus East
    (18,000 HP). Each entered, fought, fell, was sacrificed, and its pact
    was stamped Eliminated [2026-11-23]. A table with only those four rows
    crashed the page's creation (a read at `0x400000000` in libc): the game
    expects the other rows.
  * **Co-op** [test folder, players 3 and 4, 2026-11-23]: Ad Hoc Play's
    Select Quest has a **Blank Page** tab (top right of the Pacts index)
    that lists the host's own pages. A pact above the room's difficulty cap
    shows "Difficulty cap" and can't be picked; this save allowed rooms up
    to 10 (15 needs a later chapter). The host's Normal page ("Giant Bird
    in Ruins", Griffin) was picked: both lobbies showed it, both entered
    the quest together, each showed the other's sorcerer, and both reached
    the results (the Griffin's HP is scaled for the party: 54,400). Online
    co-op (Play Online) needs PSN, which neither the game's servers nor
    Vita3K provide: offline it returns to the menu (patch 0036).
* **Japanese Voice-over Pack** [local, 2026-11-20]: a separate PSN add-on,
  not in 1.30's data and not in the entitlement table above.
  * Content IDs `UP9000-PCSA00152_00-SSS000CVN0000001` (US) and
    `EP9000-PCSF00532_00-SSS000CVN0000001` (EU), both `c_date` 20140516,
    version 01.00. It holds `resource/data/pack/mount/retail/voice_jp.{pk,pkh,pfs}`
    (917,593,536 / 322,196 / 513,517 bytes). The EU pkg's file table (its
    outer layer, read with Vita3K's public pkg keys; the files inside stay
    PFS-encrypted without the zRIF) lists the same files at the same sizes as
    the US dump, so the decrypted packs are taken to be the same
    (**hypothesis**: no decrypted EU pack seen).
  * `voice_jp.pk` holds 20,137 files against `voice_ue.pk`'s 16,417:
    every English file has a Japanese counterpart (`_jp` for `_ue`) except
    20 streams, plus 3,740 streams of its own.
  * The game builds the add-on's folder name as `SSS000CVN0000%03d`
    (`0x81b9c750`) in a loop at boot (`0x812ab018`, called from
    `0x812ab30e`), lists `addcont0:SSS000CVN0000001` and opens `voice_jp.pk`
    beside `voice_ue.pk` [checked in runs]. `addcont0:` is
    `ux0:addcont/<title ID>/` (the title's `param.sfo` has no
    `INSTALL_DIR_ADDCONT`), so the US game looks in `addcont/PCSA00152/` and
    the EU game in `addcont/PCSF00532/`; each region's pack installs into
    its own title's folder. Vita3K checks no licence for add-on folders.
  * Options → Lang/Sub Settings → Voice Language then offers Japanese
    beside English (US game) or English (UK) (EU game); what it offers
    without the pack is not checked. With it chosen, each of Librom's
    lines opens and reads `voice_jp.pk` and nothing reads `voice_ue.pk`
    [EU game, checked in runs with file reads logged]. `online_text` 1042
    "Japanese Voice-over Pack" and 1046 "English Voice Pack" name it and
    its counterpart for the Japanese release.
* **Undub patch** [local, 2026-11-21] (GitHub issue #8): swosho's "Soul
  Sacrifice Delta UNDUB patch" v1.0 (archive.org, 2023-04-15; one `.7z`
  of 747,214,819 bytes, MD5 `92b181b28a7846585708f15c0aa79fd7`). It is a
  rePatch mod: `rePatch/PCSA00152/resource/data/pack/mount/retail/` holds
  nine files that replace the game's `voice_ue`, `voice_patchv_ue` and
  `archive_patch3` (`.pk`, `.pkh` and `.pfs` of each). Its description says
  to rename the folder to `PCSF00532` for the EU game, and that with the
  voice pack the voice language can only be switched after the prologue,
  which the undub covers (the author's claims, not checked here).
  * The three `.pfs` directory trees are 1.30's own, byte for byte.
    `voice_patchv_ue.pk` replaces all 421 members. `voice_ue.pk` replaces
    16,400 of 16,417; its index lacks 16 entries (parts of nine
    streams, e.g. `VO_MA_0055_ue`, `EP_MA02_1_0500_ue`), which are then
    missing: the author's "seven mute voice clips". `archive_patch3`
    differs from 1.30's in one member of 3,026:
    `resource/data/sound/se/prison_voice_ue.sxd` (1,041,120 → 1,979,600
    bytes).
  * US and EU: 1.30's `voice_ue` and `voice_patchv_ue` are the same in
    both regions. `archive_patch3` differs in six members,
    `project/obj/ElderFantasy/{Release,Ship}_PSVita/eb{771_bahamut,781_gigas,850_odin}.o`:
    relocatable objects with debug info, the same sizes but different
    string tables; build leftovers. No ELF of the game names `project/obj`
    or `Release_PSVita` (the eboot names those bosses `boss_eb771` and so
    on), so the game is taken not to read them (**hypothesis**), and the
    US-made `archive_patch3` to be fine for the EU game.
  * At boot the game opens the three archives' `.pkh` and `.pk` (not the
    `.pfs`). Each voiced line of the prologue opens `voice_ue.pk` again
    (AvPlayer's file streaming) and streams one member: the offsets read
    are `OP_NA_0501_ue.sxd2`'s and `OP_PR_0001_ue.sxd2`'s in the undub's
    index, and would be mid-member in 1.30's [checked in runs, file reads
    logged]. The opening movies (`ev01_opening.mp4`, `ev03_opening.mp4`)
    are separate files that the patch doesn't change.
  * ss-delta installs it as a rePatch mod beside the game
    (`ux0/rePatch/<title>/`, the installed region's) and serves its files
    in place of the game's (`[game] repatch`); the game's own files stay.
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
    `sceTouchSetSamplingState` and `sceTouchGetPanelInfo`. It samples both
    panels (`0x8180fb02` reads ports 0 and 1). The rear panel is still
    **hypothesis:** cosmetic only (Librom's `BK_BACK_TOUCH_*` reactions).
* **Touch-only spots and the game's PS TV controls** (#12)
  [local, 2026-11-22, static analysis of 1.30]:
  * Not in the event scripts: the `resource/data/event/*_event_param.csv`
    commands have no touch command. The touch waits are in code.
  * The input chain: `sceTouchRead` goes into a 128-entry queue per panel
    (`0x81d387c0`), then a gesture manager (`*0x81c9a7d4`), then a
    dispatcher task (`*0x81c9881c`, update `0x81329d2a`). The dispatcher
    passes gestures to registered listeners (base constructor
    `0x813274ba`; fields `+0x48` enabled, `+0x4c` panel mask, virtual
    `+0x30`) and answers "tapped inside a rectangle" (`0x8132a4dc`).
  * `0x817e775a` is `sceKernelGetModel() & 0x20000`, i.e. "is a PS TV". It
    is the eboot's only use of the model. Its 16 callers are where the
    game behaves differently without a touchscreen. Seven of them have the
    pattern "a tap in a rectangle, or (on a PS TV) a pad button"
    (`0x812f1284`):
    * PrisonEventOpening (`0x81721a7e`, `0x81722ae4`): the new-game book
      grab, a 350×400 rectangle at the screen centre. The issue's case.
    * PrisonEventAnotherEpisode (`0x81054cda`) and Prison, the hub
      (`0x817374dc`, `0x81738474`).
    * GestureMenuTask (`0x8133412a`, multiplayer gestures) and PlayerTask /
      ControlChargeTabooMagic (`0x812f288e`, `0x8137e2fe`, the Black Rite).
  * The other callers only branch on the model (**hypothesis:** they swap
    the touch prompt for a button prompt): PrisonEventEther (`0x8171eeba`,
    `0x8171f1da`, which, like Opening and AnotherEpisode, shows the finger
    prompt `FingerUI` = `menu_018_004.d2b`), BookBormanShopTask, a Prison
    menu list (`menu_018_014.d2b`), DeadFixUI and BookArEntryTask.
  * So the story's touch waits are hub events (Opening, AnotherEpisode,
    Ether, the hub itself), not cutscenes in quests.
  * The pad buttons these checks take are the game's indices 8 and 9
    (`0x812f05d0`: game bits `0x1000`, `0x2000`), which the pad read
    (`0x8180e73e`, `sceCtrlReadBufferPositive2` port 0) makes from
    `SCE_CTRL_L2` (`0x100`) and `SCE_CTRL_R2` (`0x200`): a DualShock's
    triggers on a PS TV. In the extended functions a Vita's L/R are L1/R1
    (`0x400`/`0x800`, game bits `0x40`/`0x80`), so a Vita never sends them.
  * Vita3K's `pstv-mode` alone did nothing here: its `SceKernelModel` enum
    was 0 and 1 (upstream and Vita3K-Plus too), while the SDK's values are
    `0x10000` and `0x20000`, so `& 0x20000` never matched. Seen in a run
    (the opening sat in state `0x436`, the PS TV check, with R2 reaching
    the pad object); fixed in our fork.
  * With the fix, `[game] pstv_mode` plays the new-game opening without
    touch [checked in a run, 2026-11-22, test folder]: R2 pulls Librom out
    of the bones (three pulls, the `+0x68` counter), ✕ advances the text,
    the camera scene and "Go on, have a peek", and the game goes on into
    the first quest. Seen on the way: on a PS TV the dialogue shows a ✕
    prompt, and the camera scene before the prisoners' movie waits for ✕
    (without PS TV mode it went on alone after about 160 s).
  * The other spots [checked in runs, 2026-11-22, test folder; the events
    started through a test-only patch of the event index the hub passes on
    a load (`0x81735cc4`, `0x8173619a`, `0x8173647e`: `movs r1, #2`,
    PrisonEventContinue, the factory `0x8172892c`'s index; 15
    AnotherEpisode, 6 Ether) on the JIT, since the native eboot ignores a
    code patch, and the PrisonCameraTask mode `+0x44` set to 6, which both
    events wait for]:
    * PrisonEventAnotherEpisode (after `q_e1304`): its wait takes a tap, ✕
      (`pad +0x20 & *0x81de1e80`, `0x200`) on any model, and L2/R2 on a PS
      TV. R2 and, without PS TV mode, ✕ open the book (the Red Hood
      episode).
    * PrisonEventEther (lacrima): a tap near the hand, button index 16
      (`*0x81de1e80`, ✕) on any model, L2/R2 on a PS TV. R2 and, without
      PS TV mode, ✕ give the lacrima.
    * So of the story's finger prompts only the opening's grab is
      touch-only on a Vita.
    * Prison (hub, `0x817374dc`, `0x81738474`): the touch squashes the
      cockroaches (`Cockroach`, `0x8170e2e4`) and turns the view; on a PS
      TV L2/R2 at the screen centre. Cosmetic.
    * Black Rite (`0x812f288e`): a tap in the lower-left 128×128 on any
      model, plus L2 (index 8) on a PS TV, so with PS TV mode LT is the
      Black Rite twice over (the `[touch]` binding and the game's L2), one
      check. Not played (Stage Select's player had no rite to show).
    * Blocked on a PS TV with system text 1225 ("You may not use this
      feature under the present circumstances."): BookArEntryTask (AR, the
      camera), a state of BookBormanShopTask whose Vita branch starts
      `NearTask`, and entry 2 of the Network menu (PrisonMultiMenuTask; its
      three shown entries, Play Online, Ad Hoc Play, Sorcerer Stats, still
      open: **hypothesis** that entry 2 is near).
    * Not played: GestureMenuTask (multiplayer gestures; it takes pad
      buttons on any model) and DeadFixUI (influencing players while dead
      in multiplayer; its PS TV branch draws something else).

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

**XLink Kai retransmit patch (2026-11-27).** Both 1.30 XDelta patches
matched both target-window checksums when applied to their region's
eboot. Each changes two instructions, at `0x818a2e36` and `0x818a3142`,
in the calls to `sceNetAdhocMatchingCreate`. The original instructions
set the eighth argument to 8,000 µs with three retries. The patches
replace those instructions with `movt`, setting the interval's upper
16 bits to `0x80` (US) or `0x10` (EU). In either region the fork's LLE
hook already raises the original interval to at least 250,000 µs.
See [11-online](11-online.md#implementation-steps-phase-16a) for the
port's measured latency and loss results.
[Team XLink patch and installation notes](https://www.teamxlink.co.uk/wiki/Soul_Sacrifice_Delta_(PlayStation_Vita))

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
* The same pattern is known from PSP emulation: framebuffer→texture effects.

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
| Memory | `vita3k/mem` | ~1.8k lines | Flat 4 GiB host reservation, guest ptr = `base + addr`. This is exactly what generated code wants (static recompilers commonly use the same model). Fault handler does write-tracking for the texture cache |
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
| **B. Hybrid AOT in a Vita3K fork** | Recompile Thumb-2 → C++ ahead of time. Vita3K's CPU layer dispatches to native code by address and falls back to dynarmic on a miss. Keep Vita3K's HLE, GXM and renderer | 6–12 months to full coverage, useful at every step | **Recommended.** Recompiled code + fallback + reused HLE |
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
     the Radeon 760M test PC.
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

All of this is outside git: never commit anything derived from the game.

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
