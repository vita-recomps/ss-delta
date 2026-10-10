# 05 — The recompiler (Phases 3 and 4)

`recomp/` turns a module's Thumb-2 code into C++ ahead of time
([D1](decisions.md), [D6](decisions.md)). Its input is `extracted/elf/` and
its output goes to `generated/`; neither is ever committed ([D2](decisions.md)).

```
python -I recomp/recompile.py extracted/elf/<module>.elf generated/<module>
. .\tools\devshell.ps1
cmake -S recomp -B build/recomp -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/recomp                  # gen_<module>.lib and ssd_aot_<module>.dll
.\recomp\run-tests.ps1                      # dynarmic comparison, all modules
$env:SSD_AOT = "$PWD\build\recomp\ssd_aot_eboot.dll"   # then launch the fork as usual
```

## Layout

| Path | What |
|---|---|
| `recomp/armrecomp/frontend.py` | runs `tools/inventory.py` and re-decodes each function's instructions with Capstone details |
| `recomp/armrecomp/semantics.py` | one instruction → C++ statements, its control-flow kind and the flags it reads and writes |
| `recomp/armrecomp/emit.py` | one guest function → one C++ function: flag liveness, labels, `IT` as `if`, calls, returns, jump tables |
| `recomp/recompile.py` | a whole module → `funcs.h`, `bucket_NNN.cpp` (about 64 KiB of guest code each), `table.cpp`, `report.txt` |
| `recomp/runtime/armrecomp.h` | memory accessors, helpers, and the hooks the embedder provides |
| `recomp/runtime/aot_abi.h` | the guest context and the DLL interface (D7); the fork keeps a copy in `cpu/include/cpu/aot_abi.h` |
| `recomp/runtime/aot_dll.cpp` | the DLL entry point `armrecomp_aot_init`: host hooks in, function table out |
| `recomp/make_tests.py` | the comparison tests: `tests.cpp` (per instruction) and `functions.cpp` (whole leaf functions) |
| `recomp/tests/harness.cpp` | runs every test natively and on dynarmic and compares the results |
| `recomp/run-tests.ps1` | regenerate, build and run the tests for each module |
| `recomp/forms.py` | instruction-form key (`vmla s,s,s`) used to group tests |

## Generated code

Every guest function becomes `void f_<address>(GuestContext *ctx)`.

* **Context:** `r0–r15`; N, Z, C, V, Q and GE as separate words; `d0–d31`
  as a union with `s` and `f`/`fd` views; FPSCR; TPIDRURO; the exclusive
  monitor.
* **Memory:** `g_guest_base + (uint32_t)addr`, matching Vita3K's 4 GiB
  reservation. The test harness replaces the accessors
  (`RECOMP_CUSTOM_MEMORY`).
  * Accesses are `volatile`. Other guest threads change memory at the same
    time, so the C++ compiler must not cache a load (a spin-wait would
    never end) or merge stores. On x64 these are plain `mov`s.
  * `dmb`/`dsb` become `std::atomic_thread_fence(seq_cst)`.
* **Loader-patched instructions:** Vita3K rewrites the `movw`/`movt` pairs
  that load a variable import's address. The eboot has 52 pairs, taken
  from the ELF's variable-import reference tables (`vitaelf.var_import_sites`).
  Generated code decodes their immediates from guest memory at run time
  (`thumb_mov_imm16`), and the code hash skips them.
* **Flags:** a backward liveness pass over the instruction graph drops
  flag writes that no path reads. Calls kill the flags (AAPCS); escapes to
  the fallback CPU keep all of them live. In the eboot this drops 1,703,841
  of the flag writes.
* **Control flow:**
  * branches inside the function become `goto`;
  * `tbb`/`tbh` become `switch`;
  * `IT` blocks become one `if` per instruction. A 16-bit instruction inside
    an `IT` block doesn't set flags;
  * `bl`/`blx #imm` to a recompiled function becomes a direct call
    (`RECOMP_CALL`). A `RECOMP_BISECT` build routes these calls through
    `call_indirect` instead, so the runtime chooses per function;
  * a call to a function that isn't recompiled (NEON, ARM mode) or through a
    register goes to `call_indirect`;
  * a call to an import stub goes to `call_import`.
* **Return protocol:** a function sets `ctx->r[15]` to the address it
  returns to and returns. Each call site checks that `r15` is its own return
  address; if it isn't, it calls `escape`, which continues on the fallback
  CPU and never comes back.
* **VFP:** host IEEE arithmetic. Vita3K threads run with FPSCR = 0
  (round to nearest, no flush-to-zero, no default-NaN mode), so FPSCR's mode
  bits are stored but don't change the generated code. ARM's NaN rules are
  applied explicitly (`fp_add`/`fp_mul`/…, `process_nans`):
  * a signalling NaN operand wins over a quiet one;
  * an invalid operation gives the default NaN `0x7fc00000`, not x86's
    `0xffc00000`;
  * `vmla` and its relatives are an `FPMul` followed by an `FPAdd`, with
    `FPNeg` as a sign-bit flip, as in ARM's pseudocode.
* **`vmsr fpscr`** keeps only the bits ARMv7 VFP implements
  (`0xfff7009f`, as dynarmic does).
* **Exclusives:** `strex` is a host compare-and-swap. It succeeds when the
  monitor is armed for its address and memory still holds the value `ldrex`
  read. This is the same value-based protocol Vita3K's dynarmic uses, so
  native and JIT threads interoperate.
* **Counting:** every basic block starts with `RECOMP_COUNT(n)`. Builds
  with `RECOMP_COUNT_INSNS` (the default) add `n` to `ctx->insns` for the
  fork's counters.

## Coverage (1.30)

Native code covers every Thumb function that has no NEON instruction.
The others go to the fallback CPU through `call_indirect`.

| | eboot | libc | libfios2 | libult |
|---|---|---|---|---|
| functions recompiled | 28,356 | 1,530 | 567 | 157 |
| left to dynarmic: NEON | 5,577 | 5 | 0 | 0 |
| left to dynarmic: ARM mode | 28 | 0 | 0 | 0 |
| instructions recompiled | 2,046,448 | 79,333 | 47,681 | 21,303 |
| unsupported instructions | 0 | 0 | 0 | 0 |
| flag writes dropped | 1,703,841 | 64,559 | 37,832 | 14,111 |
| buckets | 91 | 4 | 3 | 1 |

The libraries' code is generated at their ELF addresses. The addresses
Vita3K loads them at are still open (Phase 5).

### NEON (input to Phase 5)

None of the 5,577 eboot functions that use NEON translates completely yet.
Most are blocked by a few common forms:

* `vmov.i q, #imm` (zeroing a quad register) is the **only** blocker in
  1,901 functions;
* `vdup q, d` is the only blocker in 138 more.

Supporting those two forms would make about 37% of the NEON functions
native.

## Tests

The comparison runs each test on dynarmic as Vita3K builds it (the fork's
`external/dynarmic`, RelWithDebInfo) and on the generated code. Both sides
start from the same random state:

* integer registers mixing special values and random words;
* random doubles and floats, including NaNs and infinities;
* FPSCR = 0.

Both sides read the same deterministic sparse memory. The harness compares
`r0–r14`, all 64 single-precision registers, FPSCR above the cumulative
exception bits, and every memory write.

* **Per instruction:** for every instruction form in the module, up to 20
  distinct encodings, 256 random states each. The tests cover every
  translated sequential instruction except `ldrex`/`strex`/`clrex` and the
  TLS `mrc`. NZCV, Q and GE are compared too. An instruction inside an `IT`
  block is preceded by a one-slot `IT`.
* **Per function:** 300 leaf functions with control flow (branches, `IT`,
  jump tables, loops), spread evenly over the module. Each is emitted
  exactly as `recompile.py` emits it and runs from its entry until it
  returns to a sentinel `lr`. Each gets 64 random states. A state is
  skipped when dynarmic doesn't reach the sentinel within 200,000 ticks,
  since random inputs can make a loop run for ever. Flags are not compared,
  because dead flag writes are dropped.

### Results (2026-10-10, rerun after the Phase 4 changes)

| | eboot | libc | libfios2 | libult |
|---|---|---|---|---|
| instruction tests (forms) | 5,364 (554) | 2,960 (380) | 2,176 (332) | 869 (152) |
| failing | **0** | **0** | **0** | **0** |
| function tests (leaf functions with control flow) | 300 of 2,587 | 118 of 118 | 47 of 47 | 3 of 3 |
| failing | **0** | **0** | **0** | **0** |
| functions never returning in the budget | 22 | 1 | 2 | 0 |
| runs skipped | 2,334 of 19,200 | 840 of 7,552 | 425 of 3,008 | 0 of 192 |

Bugs the suite found while it was brought up:

* Capstone's `update_flags` is set for `adc.w` without S. S now comes from
  the mnemonic.
* x86 NaN results differ from ARM's in three ways:
  * x86 returns the negative indefinite NaN where ARM returns the default
    NaN;
  * x86 picks the first operand's NaN where ARM prefers a signalling NaN;
  * MSVC folds `a + -b` into `a - b`, which loses `FPNeg`'s sign flip on a
    NaN.
* `vmov.f32 d, #imm` (NEON) writes both lanes.
* `vmsr fpscr` must drop the bits VFP doesn't implement.

## Build (1.30 eboot)

| | |
|---|---|
| generator time | 102 s (decode and inventory included) |
| generated C++ | 312 MB in 91 buckets, plus `funcs.h` and `table.cpp` |
| clean build of the four modules | **4.8 min**, MSVC 14.44 `/O1`, 4 jobs (`RECOMP_JOBS`) on 12 threads |
| sum of per-object compile times | 18 min for the eboot |
| slowest bucket alone | `bucket_010`: 23 s, 435 MB peak working set |
| `gen_eboot.lib` | 81.6 MB (libc 3.4, libfios2 1.8, libult 0.6) |
| `ssd_aot_eboot.dll` | 50 MB; the eboot alone builds in 4–5 min |

Compile time doesn't follow source size: the largest source file,
`bucket_008` (4.2 MB), compiles in 3 s. **Hypothesis:** the slow buckets
hold very large functions with many labels, which the optimiser handles
badly. Memory is not the limit: `RECOMP_JOBS` can go up to the core count.

## Runtime in the fork (Phase 4)

Design: [D7](decisions.md). Code: the fork's `cpu/src/aot.cpp` (loading,
verification, counters) and `cpu/src/dynarmic_cpu.cpp` (boundary, hooks,
differential mode). These are patches 0007 and 0008.

### Environment variables

| Variable | Effect |
|---|---|
| `SSD_AOT=<dll>[;<dll>...]` | load recompiled modules; without it the fork behaves like upstream |
| `SSD_AOT_COUNT=1` | count guest instructions on both sides (dynarmic cycle counting) and profile JIT instructions by entry |
| `SSD_AOT_STATS=<file>` | rewrite the counters to a file every 5 s, with the native share of the last interval |
| `SSD_AOT_DIFF=<N>` | differential mode: check every Nth native call per thread |
| `SSD_AOT_RANGE=<lo>-<hi>[,...]` | only these functions run natively (with a `RECOMP_BISECT` DLL, also for direct calls) |
| `SSD_AOT_TRACE=<N>` | log the first N native calls with their registers |
| `SSD_AOT_DUMP=<file>` | write the module's code as guest memory holds it at verification |
| `SSD_TRACE_IMPORTS=<file>` | every HLE call with arguments and result, flushed per line |

The log is asynchronous and loses its tail when the process is killed. Use
`SSD_AOT_STATS` and `SSD_TRACE_IMPORTS` for anything that has to survive.
`tools/stackdump.py <pid|image>` prints every thread's stack with PDB
symbols, for hangs.

### Results (1.30, Radeon 760M, 2026-10-10)

| | Title | `ELDER DEFAULT MAP` |
|---|---|---|
| renders like the JIT build | yes | yes |
| fps | 30 | 29–30 |
| guest instructions native (5 s interval) | **26%** | **36%** |
| escapes | 0 | 0 |
| differential check (`SSD_AOT_DIFF=100`, 150 s) | — | 11,181 frames, 116,609 calls checked, **0 mismatches**, 22,387 skipped (HLE calls 20,372, atomics 2,015) |

During loading the share is about 80%. In gameplay, most JIT
instructions run in eboot functions that contain NEON, called from native
code. The heaviest are:

* `8188c41e`: 28 KB, 1,275 NEON instructions; float vectors (`vmla`/`vmul`
  `q`, `vrsqrte`, `vbsl`);
* `81a0c708`, `81a0a130`, `81a0e1f4`: integer NEON (`vmull`, `vshrn`,
  `vqadd`, `vqshrn`);
* `8186d012`, `8188bf80`, `81a1a104`, `81a166cc`;
* libc through its LLE stubs.

There are about 18 M native→JIT calls in a 60 s field run, from boot onward.

### Bugs found on the way

* **Variable imports** (above): the loader patches 104 instruction words
  in the eboot. The first code-hash check caught them.
* **HLE calls inside a run** must keep the caller's `halted` flag. Guest
  callbacks that an HLE function runs (here, from
  `sceGxmShaderPatcherCreate`) end on the thread's WFI halt instruction.
  Before the fix, the main thread took that for its own exit and the boot
  hung with every thread waiting.
  * Found by bisecting native functions with `SSD_AOT_RANGE` down to the
    entry `81277330`, then with a `RECOMP_BISECT` DLL to that function
    alone, then by diffing `SSD_TRACE_IMPORTS` traces of a JIT run and the
    failing run.
* **Differential-mode harness bugs:**
  * the shadow JIT needs its own exclusive monitor, because dynarmic asserts
    without one;
  * a halt left over from an aborted shadow run returns once;
  * nested checks need separate results;
  * stack slots holding the sentinel return address differ by design and
    are ignored.
  * A spinlock-protected allocator (`818953d6`) gave false mismatches when
    another thread allocated between the shadow run and the native run, so
    calls that store exclusively are skipped.
