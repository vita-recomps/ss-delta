# ss-delta

A native PC port of **Soul Sacrifice Delta** (PS Vita, US PCSA00152, v1.30)
by static recompilation, built from the player's own dump. The game's code,
and the firmware modules it loads, are recompiled ahead of time to C++ and
run natively inside a fork of Vita3K, which supplies the rest of the
console. Its sibling, utakata, ports Shinobido 2 with the same toolchain.

> This repository contains *no* game data, *no* firmware and *no* code
> derived from the game. You bring your own dump; everything game-derived is
> generated locally from it. See [D2](docs/decisions.md).

## Status

Phases 0 to 6 are done. `ss-delta.exe` is a single-game executable built
from our Vita3K fork. It has no Qt interface; its settings, keyboard and
gamepad bindings are in `ss-delta.ini`, and it runs offline. It runs the game
on native code alone: the game's modules and the firmware modules it loads
are recompiled to C++, and a build without the dynarmic JIT plays at 30 fps.
`third_party/recomp/tools/install-game.py` turns the player's own dump and
firmware into a playable folder, generating and compiling everything
locally.

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

## What you need

* Windows 10 or 11, x64, a GPU with Vulkan.
* Your own copy of the game, US version (PCSA00152) at **update 1.30**: a
  decrypted dump (folder, `.zip` or `.vpk`, with the 1.30 patch merged),
  or the PSN `.pkg` with its licence `work.bin` plus the 1.30 patch pkg.
  The add-ons' content is part of 1.30.
* The PS Vita firmware update files `PSVUPDAT.PUP` and `PSP2UPDAT.PUP` (as
  for Vita3K; Sony publishes them).
* To build: Git, Python 3.12 (`pip install capstone pyyaml`), Visual Studio
  2022 or its Build Tools with "Desktop development with C++" (MSVC x64,
  the Windows SDK, CMake and Ninja), Qt 6.11 for MSVC x64 (Vita3K's own
  interface is built too; e.g. with `aqtinstall` into `C:\Qt`), and the
  Vulkan SDK. These are Vita3K's build requirements.

## Building from a fresh clone

```
git clone --recurse-submodules <this repository's URL> ss-delta
cd ss-delta
python -I third_party/recomp/tools/build-vita3k.py --target ss-delta
```

The script finds MSVC (vswhere) and Qt (`Qt6_ROOT`, `--qt <dir>`, or the
newest `C:\Qt\<version>\msvc20*_64`). The first build takes about ten
minutes and puts `ss-delta.exe` in `build/vita3k/bin/RelWithDebInfo/`.

## Installing your game

```
python -I third_party/recomp/tools/install-game.py --name ss-delta ^
    --firmware PSVUPDAT.PUP PSP2UPDAT.PUP ^
    --install "<your dump: folder, .zip or .vpk>"
```

(For a pkg: `--install "<game>.pkg" --license "<work.bin>" --install
"<1.30 patch>.pkg"`.) The script installs the firmware and the game into a
Vita file system, checks that `eboot.bin` is 1.30, runs the game briefly to
write its modules out, recompiles them and the firmware modules to C++ and
compiles them (this takes a while), then lays out `dist/ss-delta/`:
`ss-delta.exe`, the recompiled `ssd_aot_*.dll`, a commented `ss-delta.ini`
and the Vita file system in `fs/`. Everything in it is derived from your
copy: don't share it.

## Playing

Run `dist/ss-delta/ss-delta.exe`; `README.txt` in that folder explains the
settings (`ss-delta.ini`: resolution, frame rate, window, bindings), the
Black Rite binding, save import and export, and Ad Hoc Play
(`run-player2.bat`).

## Toolchain

The Vita3K fork and the recompiler are git submodules, shared with utakata
([D17](docs/decisions.md)):

* `third_party/vita3k`: our Vita3K fork, branch `games` (the single-game
  frontend `vita3k/game-frontend/` and one executable per game,
  `vita3k/games/ss-delta/` for `ss-delta.exe`);
* `third_party/recomp`: vita-recomp-kit, the recompiler (`recomp/`), the
  generic tools and the build, install and packaging scripts. `game.json`
  describes this game to those scripts.

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
| `tools/lspk.py` | list and extract the game's LSPK archives (`.pkh`/`.pk`/`.pfs`) |
| `tools/questmaps.py` | the quest map list from `quest_param.csv` |
| `tools/map-sweep.ps1` | screenshot every quest map through Stage Select (`-Frames`: at render resolution) |
| `tools/devshell.ps1` | dot-source to load MSVC x64 and point CMake at Qt 6.11.0 (a fresh configure of the fork, `recomp/run-tests.ps1`) |
| `tools/package4090.ps1` | build `dist/ss-delta-vita3k-test` (both Vita3K builds, the installed game, `run-matrix.bat`/`play.bat` from `tools/pkg4090/`) for testing on another PC |
| `game.json` | this game for the shared scripts: title, supported eboot, modules to recompile, packaged README (`docs/dist-readme.txt`) |

From the shared toolchain (`third_party/recomp/`, each script's docstring
has its options):

| Script | What |
|---|---|
| `tools/build-vita3k.py` | configure and build our Vita3K fork (`third_party/vita3k`) into `build/vita3k` (MSVC found with vswhere, Qt in its default folder; `--no-jit`: `build/vita3k-nojit`) |
| `tools/install-game.py`, `tools/make-dist.py` | a playable folder in `dist/` from the player's dump and firmware, as `game.json` describes it |
| `tools/velf.py` | Vita SCE ELF: segments, module_info, NID-named imports/exports, exidx |
| `tools/vitaelf.py` | library: Vita ELF segments, module_info, imports/exports, exidx, EHABI exception scopes |
| `tools/inventory.py` | per-module code inventory into `generated/inventory/<module>/` (see docs/04-inventory) |
| `tools/imix.py` | Capstone instruction-mix sweep over every exidx function |
| `tools/sfo.py` | print `param.sfo` fields |
| `tools/v3kdrive.py` | drive Vita3K or `ss-delta.exe` without focus: launch, `BootSequence`, buttons, touches, FPS sampling, screenshots |
| `tools/stackdump.py` | every thread's call stack of a running process, with PDB symbols (hangs) |
| `recomp/recompile.py` | recompile a module to C++ in `generated/<module>/` (see docs/05-recompiler) |
| `recomp/run-tests.ps1` | regenerate, build and run the dynarmic comparison tests for each module (`-Root .`) |

Python dependencies: `pyyaml`, `capstone`, `pycryptodome` (for SELF
decryption).

## Licence

MIT ([LICENSE](LICENSE)), except `patches/vita3k/`, which are changes to
Vita3K and, like it, under the GNU GPL version 2 or later. The Vita3K fork
(`third_party/vita3k`) is GPL-2.0-or-later.
