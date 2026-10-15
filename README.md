# ss-delta

A native PC port of **Soul Sacrifice Delta** (PS Vita, US PCSA00152, v1.30)
by static recompilation, built from the player's own dump. The game's code,
and the firmware modules it loads, are recompiled ahead of time to C++ and
run natively inside a fork of Vita3K, which supplies the rest of the
console.

> This repository contains *no* game data, *no* firmware and *no* code
> derived from the game. You bring your own dump; everything game-derived is
> generated locally from it. See [D2](docs/decisions.md).

## Status

The whole game plays on native code, without a JIT: every quest map and the
story up to the final battle render correctly on AMD and NVIDIA GPUs, the
add-ons are unlocked, and Ad Hoc Play works between copies on one PC and
across a LAN ([compatibility](docs/06-compatibility.md)). The endings after
the final battle have not been reached in testing yet. Windows only for
now; Linux and macOS builds are planned.

## Features

Compared with running the game in Vita3K:

* **Native code.** The game's code, and the firmware modules it loads, are
  recompiled ahead of time to C++ and run natively; the build ships without
  the JIT. Each module is checked against the game in memory before its
  native code runs.
* **60 fps.** The game runs at 60 fps by default and keeps its speed:
  ss-delta changes its frame pacing (data in memory, no code patch) and
  drops to 30 fps only on loading screens, which never finish at 60
  ([D16](docs/decisions.md)). `frame_rate = 30` gives the Vita's rate.
* **Full-resolution 3D.** On a Vita the game draws its 3D at 720×408 and
  stretches it. ss-delta uses the game's own 960×544 mode, times the
  resolution multiplier: 1920×1088 at scale 2 ([D13](docs/decisions.md)).
* **Rendering fixes** for bugs the game shows in Vita3K, among them the
  white floors on NVIDIA GPUs (in upstream Vita3K and Vita3K-Plus too) and
  a "ghost" of the bloom trailing moving objects.
* **Ad Hoc Play on one PC.** Up to four copies of the game play together on
  one PC, each with its own saves and gamepad, or across a LAN
  ([D15](docs/decisions.md)).
* **The add-ons unlocked.** Their content is in the game since update
  1.30, and PSN, which recorded the purchases, is closed
  ([D14](docs/decisions.md)).
* **An in-game settings menu** (F1, or Select held on a gamepad) over the
  paused game, and a commented `ss-delta.ini`.
* **Touch on keys and buttons:** the Black Rite icon on F and the left
  trigger; the mouse is the touchscreens.
* **Vita saves** imported and exported (`--import-save`, `--export-save`).
* **One executable**, `ss-delta.exe`, without Vita3K's interface and
  offline, installed from your own dump with one command.

## The setup (no building)

Each release on GitHub has a setup, `ss-delta-setup-<version>.zip`, for
players who don't want to build anything. Unzip it, run `setup.bat`, and
in its window:

1. choose your dump (the parts described below);
2. choose the folder to play from;
3. accept Microsoft's licence.

The setup downloads the PS Vita firmware from Sony and a compiler (about
650 MB in all, kept in `%LOCALAPPDATA%\vita-recomps`). It then installs
the game, translates its code and compiles it on your PC, which takes a
few minutes. Play from the folder it made (by default `ss-delta`, next to
the setup's folder) or from the desktop shortcut it offers; the setup's
own folder can be deleted afterwards. Nothing of the game is in the setup
or leaves your PC. The setup is not signed yet, so Windows may warn about
it ("More info", "Run anyway"). Its SHA-256 and build attestation are on
the release page.

## What you need

* Windows 10 or 11, x64, a GPU with Vulkan.
* Your own copy of the game, US version (PCSA00152) at **update 1.30**: a
  decrypted dump (folder, `.zip` or `.vpk`, with the 1.30 patch merged),
  or the PSN `.pkg` with its licence `work.bin` plus the 1.30 patch pkg.
  The add-ons' content is part of 1.30.
* The PS Vita firmware update files `PSVUPDAT.PUP` and `PSP2UPDAT.PUP` (as
  for Vita3K; Sony publishes them, and the setup downloads them).
* To build (not needed with the setup): Git, Python 3.12 (`pip install capstone pyyaml`), Visual Studio
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

The Vita3K fork and the recompiler are git submodules, repositories of their
own ([D17](docs/decisions.md)):

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
