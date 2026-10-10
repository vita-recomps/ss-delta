# ss-delta

A personal research project: a native PC port of **Soul Sacrifice Delta**
(PS Vita, PCSA00152, v1.30) by static recompilation, built from the owner's
own dump. It is a sibling of `<psp-project>` (Dissidia 012, PSP).

> **Private and non-distributed.** This repository contains *no* game data,
> *no* firmware and *no* code derived from the game. Everything is
> regenerated locally from the user's own dump. See [D2](docs/decisions.md).

## Status

Phases 0 to 4 are done, and Phase 5 is nearly done. Our Vita3K fork runs
the game on Vulkan on this machine's AMD GPU, which upstream can't, and
renders it correctly at 30 fps. The recompiler (`recomp/`) turns every
function of the eboot and of the bundled libc, libfios2 and libult into
C++, NEON and ARM mode included. The fork loads them as DLLs (`SSD_AOT`).
In title, field, arena and quest runs, 99.9% of the guest instructions run
natively and none run on the JIT inside those modules. The JIT is left
with firmware code. See the [plan](docs/03-plan.md).

## Documentation

| Doc | Contents |
|---|---|
| [01-research](docs/01-research.md) | prior work, the dump's structure, measurements of the 1.30 eboot, Vita3K as donor, approach options |
| [02-baseline](docs/02-baseline.md) | how the game behaves in Vita3K today, and how to re-run the baseline |
| [03-plan](docs/03-plan.md) | phases, exit criteria, risks |
| [04-inventory](docs/04-inventory.md) | the code inventory: functions, jump tables, indirect branches, exceptions, frame pacing and render-target sites |
| [05-recompiler](docs/05-recompiler.md) | the recompiler and its runtime in the fork: generated code, coverage, tests, build, `SSD_AOT` and differential mode |
| [decisions](docs/decisions.md) | decision log |
| [hashes](docs/hashes.md) | input hashes |

## Tools

| Script | What |
|---|---|
| `tools/velf.py` | Vita SCE ELF: segments, module_info, NID-named imports/exports, exidx |
| `tools/vitaelf.py` | library: Vita ELF segments, module_info, imports/exports, exidx, EHABI exception scopes |
| `tools/inventory.py` | per-module code inventory into `generated/inventory/<module>/` (see docs/04-inventory) |
| `tools/imix.py` | Capstone instruction-mix sweep over every exidx function |
| `tools/sfo.py` | print `param.sfo` fields |
| `tools/v3kdrive.py` | drive the portable Vita3K for baseline runs: launch, `BootSequence`, FPS sampling, background screenshots |
| `recomp/recompile.py` | recompile a module to C++ in `generated/<module>/` (see docs/05-recompiler) |
| `recomp/run-tests.ps1` | regenerate, build and run the dynarmic comparison tests for each module |
| `tools/stackdump.py` | every thread's call stack of a running process, with PDB symbols (hangs) |
| `tools/devshell.ps1` | dot-source to load MSVC x64 and point CMake at Qt 6.11.0 |
| `tools/build-vita3k.ps1` | configure and build our Vita3K fork (`third_party/vita3k`) into `build/vita3k` |
| `tools/package4090.ps1` | build `dist/ss-delta-vita3k-test` (both Vita3K builds, the installed game, `run-matrix.bat`/`play.bat` from `tools/pkg4090/`) for testing on another PC |

Python dependencies: `pyyaml`, `capstone`, `pycryptodome` (for SELF
decryption).
