# 04 — Code inventory (Phase 2)

What the recompiler has to cover, measured on the 1.30 eboot and the three
bundled modules worth recompiling. Produced by `tools/inventory.py`
(recursive descent over every exidx function, using `tools/vitaelf.py`).

```
python -I tools/inventory.py extracted/elf/<module>.elf third_party/vita-headers/db/360 generated/inventory/<module>
```

Output goes to `generated/inventory/<module>/`, which is never committed
([D2](decisions.md)). It holds `summary.txt` plus these CSVs:

* `functions.csv`: one row per exidx entry;
* `jumptables.csv`: every jump table with its case targets;
* `indirect.csv`: every indirect branch;
* `calls.csv`: calls that leave the normal pattern;
* `importcalls.csv`: every call site of an import;
* `imports.csv`;
* `addrtaken.csv`: functions whose address appears in data or constants;
* `entrypoints.csv`: entries into the middle of functions;
* `unreached.csv`: every unreached byte, classified.

The NID names come from vitasdk `vita-headers` `e66ebe90`, downloaded to
`third_party/vita-headers/` (MIT, not committed).

## Totals

| | eboot (`efg`) | libc | libfios2 | libult |
|---|---|---|---|---|
| exidx entries | 34,636 | 1,592 | 634 | 184 |
| code functions | 33,961 (33,933 Thumb, 28 ARM) | 1,535 Thumb | 567 Thumb | 157 Thumb |
| import stubs | 674 | 56 | 66 | 26 |
| instructions decoded | 3,730,927 | 82,028 | 47,681 | 21,303 |
| unexplained bytes | **0** | 8 (2 functions) | 0 | 0 |
| jump tables | 1,336 | 19 | 17 | 0 |
| indirect calls (resolved / dynamic) | 15,279 / 26,235 | 288 / 293 | 16 / 36 | 3 / 22 |
| indirect jumps | 1 (`bx r0` at `0x81375cd4`) | 0 | 0 | 0 |
| direct calls to imports | 24,657 | 545 | 450 | 739 |
| address-taken functions | 21,131 | 1,275 | 287 | 103 |
| exception landing pads | **0** | 152 | 0 | 0 |
| orphan code blocks | 1 | 9 | 0 | 2 |

Every exidx entry is classified as code, an import stub or the end marker.
Every byte inside a code function is one of:

* decoded instruction;
* jump table;
* literal;
* dead epilogue, filler or self-loop (see below).

**Exit criterion for "complete function list": met** for the eboot,
libfios2 and libult. libc has 8 unexplained bytes.

## Answers to the open research questions

1. **Exidx entries with the Thumb bit clear (703 in the eboot).**
   * 674 are **import stubs**. Each is a 16-byte ARM placeholder
     (`mvn r0, #0; bx lr`, i.e. return -1) that the loader patches.
   * 28 are hand-written **ARM/NEON routines** at `0x81a1afb4`–`0x81b2…`.
     They push `{r4–r11, ip, lr}` and `d8–d15`, and keep constant tables
     after their code (π/2 and friends, `vtbl` index bytes). Only 38
     direct `blx` sites reach them. No pointer to an ARM function exists,
     and no indirect call resolves to one.
   * 1 is the **end marker**, a can't-unwind entry on the module_info
     block that closes the code.
   * The exidx mode bit is not always right: libc's `memcpy`
     (`0x81013d70`) is Thumb code with an ARM-mode entry. All 200 callers
     use Thumb `bl`. The inventory overrides the mode when every direct
     caller agrees.
2. **`pop {pc}` as dispatch:** not used. Every `pop`/`ldm` into `pc` is a
   return in a function that pushed `lr`. None are flagged.
3. **Tail calls across exidx boundaries:** the eboot has **none**, so SNC
   never emits `b` to another function. libc has 1. No branch or jump-table
   case leaves its function.
4. **ARM/Thumb switches through pointers:** none. Mode switches are the
   import calls (Thumb `blx` to the ARM stubs) and the 38 direct calls into
   the ARM routines.

## Patterns the decoder has to know

* **Literal pools** sit inside functions. Bytes read by `ldr`, `ldrd`,
  `ldrh`, `vldr` (pc-relative) are marked as data.
* **Jump tables (`tbb`/`tbh`).**
  * A table ends where its first case begins, so the decoder reads entries
    up to the lowest target.
  * The bounds check is a cross-check: 1,271 of 1,336 agree.
  * The other 65 have no usable `cmp`. Bounds can be compared against a
    register loaded by `movw` and rebased by `subw` (e.g. `0x81722d0a`, 31
    cases).
  * `tbb` tables with an odd count end in a padding byte.
* **No-return calls.** A call followed only by padding up to the next
  function never returns.
  * In the eboot that is 8 calls, including `module_start` →
    `0x81802984`.
  * In the modules it is mostly `__stack_chk_fail`: libc/fios2/ult are
    built with the stack protector.
* **Dead epilogues.** The compiler often leaves a second `bx lr` or
  `pop {…, pc}` right after the real return: 4,849 in the eboot.
* **Filler halfwords** `0x8xx0` (decoding as `ldrh/strh r0, [rN, #imm]`)
  sit after returns and between functions: 723. There are also 206 dead
  `b .` self-loops.
* **Far calls** are `movw/movt ip, #target; blx ip`. They make up all
  15,279 resolved indirect calls: 11,151 to functions and 4,126 to import
  stubs. Two call address 0 (unlinked weak symbols).
* **The modules are pre-linked** at their program-header addresses (seg0 at
  `0x81000000`): `movw/movt` constants resolve to their own functions. So
  the inventory can treat them like the eboot. At load time Vita3K
  relocates them (SCE relocation formats 0–9, `kernel/src/relocation.cpp`).

## C++ exceptions

Parsed from the EHABI tables (`vitaelf.exception_scopes`):

* **eboot: no exception scopes at all.** All 34,634 unwind entries are
  compact (personality 0/1) with an empty scope list. There are no catch
  blocks, cleanups or landing pads.
  * The game imports `std::_Throw`, `std::exception` and
    `sceKernelChangeThreadVfpException`.
  * **Hypothesis:** a throw from library code reaches `std::terminate`.
    To check later at runtime: does anything ever throw?
  * For the recompiler: no re-entry points from unwinding in game code.
* **libc** has 119 functions with GCC-style LSDAs (`__gxx_personality_v0`)
  and 152 landing pads. They are decoded as extra roots; all land on
  instructions.
* The compact unwind words (`0x81xxxxxx`) look like code pointers. A naive
  scan of extab "finds" hundreds of fake mid-function pointers, so pointer
  scans skip exidx/extab.

## Functions without exidx entries

* The eboot has none in use. No direct call, branch or resolved constant
  targets the middle of a function.
  * 45 data words look like Thumb pointers into code (`entrypoints.csv`,
    `data_word`). They land on arbitrary instructions (`str.w`, `lsrs`,
    …), so they are **probably coincidence**. The hybrid runtime's dynarmic
    fallback covers them if not.
  * 1 orphan block is unreachable epilogue code.
* libc has small hand-written helpers without exidx entries, e.g. the VFP
  register save/restore pairs at `0x81032414`–`0x810324cc`, reached by
  `movw/movt` + `blx`. They are its 9 orphan blocks; the 87 "mid-function"
  calls in `calls.csv` go to them.

## Frame pacing and render targets (pointers for Phases 7–8)

* **Display callback `0x81828708`** (the GXM display-queue callback) calls
  `sceDisplayGetVcount` and then `sceDisplaySetFrameBuf`.
  * It compares the vblanks since the last flip with a threshold. State is
    at `0x81d3a62c`: `+0` force flag, `+4` threshold, `+8`/`+c` vcounts.
  * A late frame is flipped immediately; otherwise it waits for vblank.
  * The game never calls `sceDisplayWaitVblankStart`.
* **`FPS` key.** The engine's config parser `0x817e7c74` compares keys
  against `"FPS"` (string at `0x81be4570`, `strcmp` at `0x817e7d44`). It
  converts the value with `0x81802ac4` and stores it through a pointer
  argument.
  * `config.ini` also has `SyncFps`: `true` in the dev block, `false` in
    the retail block.
  * Next (Phase 8): follow the stored value to the main loop.
* **Render targets.** The main 3D target (720×408, the VitaGrafix sites
  `0x818282a6`/`0x818282ac`) is created in `0x81828272`.
  * That function also calls `sceGxmDepthStencilSurfaceInit`,
    `sceGxmGetRenderTargetMemSize`, `sceGxmTextureInitTiled` and
    `sceKernelAllocMemBlock`.
  * Nine more functions create render targets or colour surfaces:
    `0x818281c4`, `0x8182d102`, `0x8182e5be`, `0x818360b4`, `0x8183aaa4`,
    `0x8183c1dc`, `0x8183d95c`, `0x8183df1a`, `0x8183f24a`. Most are
    probably post-processing and shadow buffers (**hypothesis**).
  * Resolution scaling has to keep them consistent.

## What this means for Phase 3

* The recompiler's unit is the exidx function. Each one has a single entry,
  except libc's landing pads and orphan helpers.
* Dispatch tables:
  * `LOOKUP_FUNC` needs the 21,131 address-taken eboot functions;
  * 26,235 indirect calls are dynamic (virtual calls and function
    pointers);
  * one indirect jump (`0x81375cd4`) is dynamic.
* Jump tables become `switch`es, from `jumptables.csv`.
* ARM-mode work is the 28 NEON routines. NEON/VFP instructions are 672,779
  of the eboot's 3.73 M (18 %).
