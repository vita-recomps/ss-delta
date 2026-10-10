# 05 — The recompiler (Phase 3)

`recomp/` turns a module's Thumb-2 code into C++ ahead of time
([D1](decisions.md), [D6](decisions.md)). Its input is `extracted/elf/` and
its output goes to `generated/`; neither is ever committed ([D2](decisions.md)).

```
python -I recomp/recompile.py extracted/elf/<module>.elf generated/<module>
. .\tools\devshell.ps1
cmake -S recomp -B build/recomp -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/recomp                  # gen_<module>.lib for each module
.\recomp\run-tests.ps1                      # dynarmic comparison, all modules
```

## Layout

| Path | What |
|---|---|
| `recomp/armrecomp/frontend.py` | runs `tools/inventory.py` and re-decodes each function's instructions with Capstone details |
| `recomp/armrecomp/semantics.py` | one instruction → C++ statements, its control-flow kind and the flags it reads and writes |
| `recomp/armrecomp/emit.py` | one guest function → one C++ function: flag liveness, labels, `IT` as `if`, calls, returns, jump tables |
| `recomp/recompile.py` | a whole module → `funcs.h`, `bucket_NNN.cpp` (about 64 KiB of guest code each), `table.cpp`, `report.txt` |
| `recomp/runtime/armrecomp.h` | guest context, memory accessors, helpers, and the hooks the embedder provides |
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
* **Flags:** a backward liveness pass over the instruction graph drops
  flag writes that no path reads. Calls kill the flags (AAPCS); escapes to
  the fallback CPU keep all of them live. In the eboot this drops 1,703,841
  of the flag writes.
* **Control flow:**
  * branches inside the function become `goto`;
  * `tbb`/`tbh` become `switch`;
  * `IT` blocks become one `if` per instruction. A 16-bit instruction inside
    an `IT` block doesn't set flags;
  * `bl`/`blx #imm` to a recompiled function becomes a direct call;
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
* **Exclusives:** single-thread semantics in v0. `strex` succeeds when the
  monitor is armed for its address. **Phase 4** turns this into a host
  compare-and-swap.

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

### Results (2026-10-10)

| | eboot | libc | libfios2 | libult |
|---|---|---|---|---|
| instruction tests (forms) | 5,363 (554) | 2,960 (380) | 2,175 (332) | 868 (152) |
| failing | **0** | **0** | **0** | **0** |
| function tests (leaf functions with control flow) | 300 of 2,587 | 118 of 118 | 47 of 47 | 3 of 3 |
| failing | **0** | **0** | **0** | **0** |
| functions never returning in the budget | 21 | 1 | 3 | 0 |
| runs skipped | 2,331 of 19,200 | 840 of 7,552 | 426 of 3,008 | 0 of 192 |

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

Compile time doesn't follow source size: the largest source file,
`bucket_008` (4.2 MB), compiles in 3 s. **Hypothesis:** the slow buckets
hold very large functions with many labels, which the optimiser handles
badly. Memory is not the limit: `RECOMP_JOBS` can go up to the core count.
