# ss-delta

A personal research project: a native PC port of **Soul Sacrifice Delta**
(PS Vita, PCSA00152, v1.30) by static recompilation, built from the owner's
own dump. It is a sibling of `<psp-project>` (Dissidia 012, PSP).

> **Private and non-distributed.** This repository contains *no* game data,
> *no* firmware and *no* code derived from the game. Everything is
> regenerated locally from the user's own dump. See [D2](docs/decisions.md).

## Status

Phases 0 to 6 are done. `ss-delta.exe` is a single-game executable built
from our Vita3K fork. It has no Qt interface; its settings, keyboard and
gamepad bindings are in `ss-delta.ini`, and it runs offline. It runs the game
on native code alone: the game's modules and the firmware modules it loads
are recompiled to C++, and a build without the dynarmic JIT plays at 30 fps.
`tools/install-game.ps1` turns the player's own dump and firmware into a
playable folder, generating and compiling everything locally.

Phase 7 (rendering correctness) is done. Every quest map and the story
scenes up to the final battle render correctly, and Mind's Eye works.

Phase 8 (PC features) is mostly done:
* the 3D renders at the full 960×544 (the game's own mode), times
  Vita3K's multiplier: 1920×1088 at 30 fps on every map at scale 2;
* the Black Rite touch has key/gamepad bindings;
* Vita saves can be imported and exported;
* the add-ons (DLC) are unlocked;
* F12 saves a screenshot.

The game runs at 60 fps (`[display] frame_rate`, 30 for the Vita's rate):
it keeps its speed, and loading screens stay at 30 fps ([D16](docs/decisions.md)).

Phase 9 (the compatibility pass, [06-compatibility](docs/06-compatibility.md))
and Phase 10 (Ad Hoc Play) are done. Copies of `ss-delta.exe` play together
in Ad Hoc Play, on one PC (`--player 2`) or between PCs in a LAN.

## Documentation

| Doc | Contents |
|---|---|
| [01-research](docs/01-research.md) | prior work, the dump's structure, measurements of the 1.30 eboot, Vita3K as donor, approach options |
| [02-baseline](docs/02-baseline.md) | how the game behaves in Vita3K today, and how to re-run the baseline |
| [03-plan](docs/03-plan.md) | phases, exit criteria, risks |
| [04-inventory](docs/04-inventory.md) | the code inventory: functions, jump tables, indirect branches, exceptions, frame pacing and render-target sites |
| [05-recompiler](docs/05-recompiler.md) | the recompiler and its runtime in the fork: generated code, coverage, tests, build, `SSD_AOT` and differential mode |
| [06-compatibility](docs/06-compatibility.md) | what works in each part of the game, and how it was checked |
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
| `tools/v3kdrive.py` | drive Vita3K or `ss-delta.exe` without focus: launch, `BootSequence`, buttons, touches, FPS sampling, screenshots |
| `tools/lspk.py` | list and extract the game's LSPK archives (`.pkh`/`.pk`/`.pfs`) |
| `tools/questmaps.py` | the quest map list from `quest_param.csv` |
| `tools/map-sweep.ps1` | screenshot every quest map through Stage Select (`-Frames`: at render resolution) |
| `tools/install-game.ps1`, `tools/make-dist.ps1` | a playable folder from the player's dump and firmware |
| `recomp/recompile.py` | recompile a module to C++ in `generated/<module>/` (see docs/05-recompiler) |
| `recomp/run-tests.ps1` | regenerate, build and run the dynarmic comparison tests for each module |
| `tools/stackdump.py` | every thread's call stack of a running process, with PDB symbols (hangs) |
| `tools/devshell.ps1` | dot-source to load MSVC x64 and point CMake at Qt 6.11.0 |
| `tools/build-vita3k.ps1` | configure and build our Vita3K fork (`third_party/vita3k`) into `build/vita3k` |
| `tools/package4090.ps1` | build `dist/ss-delta-vita3k-test` (both Vita3K builds, the installed game, `run-matrix.bat`/`play.bat` from `tools/pkg4090/`) for testing on another PC |

Python dependencies: `pyyaml`, `capstone`, `pycryptodome` (for SELF
decryption).
