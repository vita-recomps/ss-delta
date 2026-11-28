# Building ss-delta

For players, the [releases](https://github.com/vita-recomps/ss-delta/releases/latest)
need no building: see [INSTALLING](INSTALLING.md). This guide builds the
game's front end from source, installs a game into a development folder,
and makes a release.

## Contents

* [Requirements](#requirements)
* [Building from a fresh clone](#building-from-a-fresh-clone)
* [Installing your game into a build](#installing-your-game-into-a-build)
* [Playing a build](#playing-a-build)
* [Making a release](#making-a-release)
* [Toolchain](#toolchain)
* [Tools](#tools)

## Requirements

* Your own dump of the game and the firmware update files `PSVUPDAT.PUP`
  and `PSP2UPDAT.PUP` (as for Vita3K; `third_party/recomp/tools/fetch-firmware.py`
  downloads them from Sony), as in [INSTALLING](INSTALLING.md#what-you-need).
* Git, Python 3.12 with `capstone` and `pyyaml` (`pip install capstone
  pyyaml`; `pycryptodome` for SELF decryption in the research tools).
* **Windows:** Visual Studio 2022 or its Build Tools with "Desktop
  development with C++" (MSVC x64, the Windows SDK, CMake and Ninja), the
  Vulkan SDK, and Qt 6.11 for MSVC x64 for Vita3K's own interface (e.g. with
  `aqtinstall` into `C:\Qt`; `--games-only` builds without it).
* **Linux:** GCC 14 or newer, CMake, Ninja. Release builds use the Steam
  Runtime 3 (sniper) SDK, whose glibc 2.31 the game then needs at most
  ([07-linux](07-linux.md)).
* **macOS:** Apple's Command Line Tools (or Xcode), CMake and Ninja
  ([08-macos](08-macos.md)).

## Building from a fresh clone

```
git clone --recurse-submodules https://github.com/vita-recomps/ss-delta.git ss-delta
cd ss-delta
python -I third_party/recomp/tools/build-vita3k.py --target ss-delta
```

On Windows the script finds MSVC (vswhere) and Qt (`Qt6_ROOT`, `--qt <dir>`,
or the newest `C:\Qt\<version>\msvc20*_64`). The first build takes about ten
minutes and puts `ss-delta.exe` in `build/vita3k/bin/RelWithDebInfo/`.
`--games-only` builds the single-game executables without Qt into
`build/vita3k-games/`.

On Linux and macOS the same command builds `ss-delta.x86_64` or
`ss-delta.arm64` (the games only). The release workflow
(`.github/workflows/release.yml`) shows each platform's build exactly.

## Installing your game into a build

```
python -I third_party/recomp/tools/install-game.py --name ss-delta ^
    --firmware PSVUPDAT.PUP PSP2UPDAT.PUP ^
    --install "<your dump: folder, .zip or .vpk>"
```

(For a pkg: `--install "<game>.pkg" --license "<work.bin>" --install
"<1.30 patch>.pkg"`.) The script installs the firmware and the game into a
Vita file system, checks that `eboot.bin` is 1.30, runs the game briefly to
write its modules out, recompiles them and the firmware modules to C++ and
compiles them (this takes a while), then lays out `dist/ss-delta/`: the
front end, the recompiled `ssd_aot_*` modules, a commented `ss-delta.ini`
and the Vita file system in `fs/`. Everything in it is derived from your
copy: don't share it. `--toolchain <dir>` compiles with the downloaded
toolchain instead of MSVC (`toolchain.py fetch`), as a release's importer
does.

## Playing a build

Run `dist/ss-delta/ss-delta.exe` (Linux: `ss-delta.x86_64`; macOS:
`ss-delta.arm64`). `README.txt` in that folder, and
[INSTALLING](INSTALLING.md#playing), explain the settings, saves and Ad
Hoc Play. `--help` lists the command line.

## Making a release

A release is the game's own folder: the front end, its files, and in
`setup/` the importer (Python with Tk, and the recompiler kit), which builds
the game on the player's computer the first time it starts
([D22](decisions.md)). Nothing in it is derived from the game.

```
python -I third_party/recomp/tools/build-vita3k.py --project . --games-only
python -I third_party/recomp/tools/make-setup.py build third_party/recomp/tools/setup-windows.json ^
    --project . --bin build/vita3k-games/bin/RelWithDebInfo --out build/release/ss-delta ^
    --zip --archive build/release/ss-delta-<version>-windows
```

Linux and macOS take `setup-linux.json` and `setup-macos.json` (run there,
with Python 3.12). `--apk <file>` adds the game's Android APK as
`setup/android/ss-delta.apk`, which the release's `--android` step puts on
a device ([09-android](09-android.md)). Pushing a tag `v*` runs
`.github/workflows/release.yml`, which builds the APK (NDK r29 on Ubuntu,
Gradle) and all three archives on GitHub, with their SHA-256 and build
attestations, into a draft release. Each job retries timed downloads
and configure steps with `tools/ci-retry.py`. The kit tries a mirror
when a source is slower than 256 KB/s and retries slow sources without
the speed floor if the mirrors fail. Actions caches the SDK downloads,
Vita3K's configure dependencies and Gradle's dependencies. The
compilers run through sccache. The PC jobs build while the APK is made and wait for it
(`tools/ci-wait-job.py`) only to lay out the setup (#27). Its notes are
`.github/release-notes/<tag>.md` when that file exists (write it before
tagging), else a short default text. Add the release to `CHANGELOG.md`
too, with the issues each change answers.

Each PC job builds, loads and runs a synthetic recompiled module with
the Zig copy in the release folder. The Android job builds that module
with the Android flags and checks the resulting ELF for text
relocations, exports and unsupported C++ symbols. The draft checks
below also cover the APK's on-device compiler.

The APK is signed with the project's release key, from the repository's
secrets `ANDROID_KEYSTORE_BASE64` (the keystore, base64), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`; a tag fails without them.
Every release must use the same key ([D25](decisions.md)): Android
updates an installed app only from an APK with the same signature.

Each archive carries `recomplauncher.json` at its top (`game.json`'s
`release_files`), for [RecompLauncher](https://recomplauncher.com)
([D24](decisions.md)). The workflow stamps the tag into its
`prepare.version` (`tools/stamp-recomplauncher.py`), so the launcher builds
the game again after each update; stamp the new tag into the repository's
copy too when tagging, as the launcher also reads that one. Keep its
`settings` in step with `ss-delta.ini` when a key is added or renamed.

### Before publishing a draft

The tag makes a draft; publish it only after these pass **on the draft's
own downloads**, whenever the kit, the fork or `overrides/` changed since
the last release. On 2026-11-25 three Android faults reached players
through releases checked on Windows alone: the APK lacked
`overrides/eboot.json`, utakata's overrides used a libc++ clock that
Android's modules can't load, and `--android` from Windows lost `-fPIC`.

1. **Windows:** unpack the zip, build from a dump (the game's NoNpDrm zip, or
   its pkgs: `ss-delta.exe --dump <game>
   --dump=<update> --offline <the PUPs> --build-only`), then a quest:
   NativeCPU, 0 native-to-JIT calls, the log's "has the project's fixes".
2. **The APK on the Thor**, installed over the previous release (as a
   player updates): its setup builds again; then a mission, NativeCPU, no
   "cannot load" in `vita3k.log`. For a first setup, pick the dump from
   `Download/` (the file picker path).
3. **`--android` from the Windows folder** onto the Thor, then a mission.
4. A fix after the tag: delete the draft and the tag, tag again, and run
   1-3 on the new draft.

Driving the Thor: tap the main display after the game starts (`adb shell
input -d 0 tap 960 60`), or the gamepad's presses go to the second
screen's launcher.

Checks that run by themselves: `check-overrides.py` (in `make-setup.py` and
`android-build-tools.py`: an override that needs libc++ stops the
release), the read-back of the APK's `buildtools.zip`, the symbol check of
every Android module (`toolchain.py`), and the front end's message when a
module doesn't load under NativeCPU.

## Toolchain

The Vita3K fork and the recompiler are git submodules, repositories of their
own ([D17](decisions.md)):

* `third_party/vita3k`: our Vita3K fork, branch `games` (the single-game
  front end `vita3k/game-frontend/` and one executable per game,
  `vita3k/games/ss-delta/` for `ss-delta.exe`);
* `third_party/recomp`: vita-recomp-kit, the recompiler (`recomp/`), the
  generic tools and the build, install and packaging scripts. `game.json`
  describes this game to those scripts.

## Tools

| Script | What |
|---|---|
| `tools/lspk.py` | list, extract and repack the game's LSPK archives (`.pkh`/`.pk`/`.pfs`) |
| `tools/og-raiments.py` | the original game's raiments mod (D28), a [packaged mod](#packaged-mods) made from the player's dumps of both games; installs it, or writes the `.zip` (`--out`) |
| `tools/button-atlases.py` | write `button_atlases.inc` (texture hashes and symbol boxes for `[game] button_labels`, nothing of the art) from an archive folder |
| `tools/questmaps.py` | the quest map list from `quest_param.csv` |
| `tools/map-sweep.ps1` | screenshot every quest map through Stage Select (`-Frames`: at render resolution) |
| `tools/devshell.ps1` | dot-source to load MSVC x64 and point CMake at Qt 6.11.0 (a fresh configure of the fork, `recomp/run-tests.ps1`) |
| `tools/package4090.ps1` | build `dist/ss-delta-vita3k-test` (both Vita3K builds, the installed game, `run-matrix.bat`/`play.bat` from `tools/pkg4090/`) for testing on another PC |
| `tools/deck-quest.sh` | on a Steam Deck: frame rate and APU power in a quest |
| `tools/stamp-recomplauncher.py` | stamp a release tag into `recomplauncher.json`'s `prepare.version` |
| `tools/ci-retry.py`, `tools/ci-wait-job.py` | release workflow helpers: timed download retries, and waiting on the Android APK job |
| `game.json` | this game for the shared scripts: title, supported eboot, modules to recompile, overrides, the folder's README per platform |
| `overrides/eboot.json` | instruction-level C++ overrides applied when recompiling `eboot` ([D30](decisions.md)) |
| `recomplauncher.json` | [RecompLauncher](https://recomplauncher.com) manifest shipped at the root of each release archive ([D24](decisions.md)) |

### Packaged mods

A mod that adds to one of the game's archives instead of replacing it
(the front end's `game-frontend/packaged_mods.h`; D28 update 1). It is a
`.zip` (or a folder) with:

* `ss-delta-mod.json`, the manifest:

  ```json
  {
   "ss-delta-mod": 1,
   "id": "og-raiments",
   "name": "The original Soul Sacrifice's raiments: ARKS Armor and Dragonslayer",
   "version": "1",
   "titles": ["PCSA00152", "PCSF00532"],
   "archive": "resource/data/pack/mount/retail/archive_patch3",
   "tables_from": ["resource/data/pack/mount/retail/archive"],
   "append": [
    {"member": "resource/boot/costume_table.csv", "lines": "tables/costume_table.csv",
     "conflicts": ["720,", "732,"]}
   ],
   "remove_note": "shown when it is removed"
  }
  ```

* `files/<path in the archive>`: added to the archive, or replacing the
  member of that path;
* the `lines` files: lines (Shift JIS, `\r\n`) appended to that table in
  the archive. A table the archive lacks is read from the first of
  `tables_from` that has it. A line in it starting with one of
  `conflicts` (rows another mod already added) stops the install.

The front end merges it into the archive the game reads: the rePatch
mod's (an undub's) or the game's own, written to `ux0/rePatch/<title>/`.
The package itself is kept in `ux0/rePatch/<title>/ss-delta-mods/<id>/`
(never served to the game). When another mod replaces that archive later,
or it is deleted, the package is merged again (after an install, and when
the game starts). `--remove-mod <id>` takes out its files (the game's own
member put back where it had one) and its lines; when the archive left
is the game's own, rePatch's copy is deleted. A package of the same id
replaces the installed one. It runs only in ss-delta: nothing on a Vita
reads the manifest.

From the shared toolchain (`third_party/recomp/`, each script's docstring
has its options):

| Script | What |
|---|---|
| `tools/build-vita3k.py` | configure and build our Vita3K fork (`third_party/vita3k`) into `build/vita3k` (MSVC found with vswhere, Qt in its default folder; `--games-only`, `--no-jit`) |
| `tools/install-game.py`, `tools/make-dist.py` | a playable folder in `dist/` from the player's dump and firmware, as `game.json` describes it |
| `tools/make-setup.py`, `tools/setup.py` | a release, and its importer |
| `tools/velf.py` | Vita SCE ELF: segments, module_info, NID-named imports/exports, exidx |
| `tools/vitaelf.py` | library: Vita ELF segments, module_info, imports/exports, exidx, EHABI exception scopes |
| `tools/inventory.py` | per-module code inventory into `generated/inventory/<module>/` (see [04-inventory](04-inventory.md)) |
| `tools/imix.py` | Capstone instruction-mix sweep over every exidx function |
| `tools/sfo.py` | print `param.sfo` fields |
| `tools/v3kdrive.py` | drive Vita3K or `ss-delta.exe` without focus: launch, `BootSequence`, buttons, touches, FPS sampling, screenshots |
| `tools/stackdump.py` | every thread's call stack of a running process, with PDB symbols (hangs) |
| `recomp/recompile.py` | recompile a module to C++ in `generated/<module>/` (see [05-recompiler](05-recompiler.md)) |
| `recomp/run-tests.ps1` | regenerate, build and run the dynarmic comparison tests for each module (`-Root .`) |
