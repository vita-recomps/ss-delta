# CLAUDE.md

A static-recompilation PC port of Soul Sacrifice Delta (PS Vita, PCSA00152,
1.30). Start with `README.md` and `docs/03-plan.md` to find the current phase.
Sibling projects: `<psp-project>` (Dissidia 012, PSP), which has the same
conventions, and `<utakata>` (Shinobido 2, PS Vita), which shares this
project's Vita3K fork and recompiler ([D17](docs/decisions.md)).

## Hard rules

- Never commit anything derived from the dump or the firmware: extracted or
  decrypted files, ELFs, generated C++, Ghidra databases, screenshots, logs,
  licences (`.rif`/`work.bin`), PUPs. Check `git status` before every commit.
  Hashes, addresses and notes are fine.
- Treat `rom/` as read-only. Write to `extracted/`, `generated/` or `build/`.
- Mark unverified claims in docs as **hypothesis**. Promote them only after
  checking against the binary or Vita3K.
- Vita3K is the reference. When behaviour differs, compare against it before
  guessing.
- Downloaded third-party code (e.g. loktar00's tools) is read before it is
  run. Run Python that reads game data with `python -I` and pass paths as
  arguments.

## Environment

- Windows 11. Use the PowerShell tool for Windows-native commands; Bash (Git
  Bash) is also available.
- Portable Vita3K: `extracted/vita3k/` (`pref-path` = `fs/`). The installed
  game is in `fs/ux0/app/PCSA00152`. Firmware 3.74 is installed.
- Vulkan is the renderer ([D4](docs/decisions.md) update 3). Our fork runs it
  on this machine's Radeon 760M; the upstream release in `extracted/vita3k`
  still crashes there (AMD compiler bug, see `docs/02-baseline.md`), and so
  does Vita3K-Plus 1.2 since AMD driver 26.8.1 (use `OpenGL` for those two).
- Our build keeps its own config, shader cache and log next to its exe
  (`build/vita3k/bin/RelWithDebInfo/`); only `pref-path` points at the
  shared `extracted/vita3k/fs/`. Edits to cached `.spv` files must go there.
  `BootSequence` is set through the shared install:
  `python -I third_party/recomp/tools/v3kdrive.py extracted/vita3k bootseq PCSA00152 <name>`.
  It rewrites the installed `resource/config.ini` (backup `config.ini.orig`):
  set it back to `Title` afterwards.
- Shared toolchain ([D17](docs/decisions.md)): two git submodules, shared
  with `<utakata>`, whose hubs are bare repositories in `<git>\` until
  they are published (`git -c protocol.file.allow=always submodule update
  --init`). Commit and push changes inside a submodule to its hub first,
  then commit the new submodule commit here.
  * `third_party/vita3k`: our Vita3K fork ([D5](docs/decisions.md)), branch
    `games` (hub `<git>/vita3k.git`, remote `hub`; `origin` is upstream
    Vita3K, `plus` is Vita3K-Plus). `games` is the old `ss-delta` branch
    (patch 0042) plus the shared single-game frontend
    (`vita3k/game-frontend/`) and one executable per game
    (`vita3k/games/ss-delta/`, `vita3k/games/shinobido2/`). The patch
    series in `patches/vita3k/` stops at 0042 (historical); the submodule
    commit is the reference now. Its `external/cubeb` shows local changes
    in two rust submodules: leave them.
  * `third_party/recomp`: `vita-recomp` (hub `<git>/vita-recomp.git`,
    branch `main`): the recompiler (`recomp/`), the generic tools
    (`velf.py`, `vitaelf.py`, `inventory.py`, `imix.py`, `v3kdrive.py`,
    `sfo.py`, `stackdump.py`, ...) and the Python build, install and
    packaging scripts, which read `game.json`.
- Build the fork with
  `python -I third_party/recomp/tools/build-vita3k.py --project . [--target ss-delta]`
  (MSVC found with vswhere, Ninja Multi-Config, RelWithDebInfo) into
  `build/vita3k`. A fresh configure (`--reconfigure`, a new build dir) also
  needs Qt 6.11.0 in `C:\Qt`: dot-source `tools/devshell.ps1` first, which
  sets `Qt6_ROOT`.
- Our build's `config.yml` must keep `disable-surface-sync: false` and
  `high-accuracy: true` (D4 update 4: fog, haze and smoke) and
  `memory-mapping: double-buffer` (`external-host` hides objects).
- The shader cache in `build/vita3k/bin/RelWithDebInfo/cache/shaders/` is
  keyed by guest shader, not by translator version. Runs of a build with
  changed shader translation (debug branches, `SSD_DENORM`, ...) leave
  shaders there that break later runs: move the title's folder aside after
  such runs.
- Recompiled code: build `ssd_aot_<module>.dll` (eboot, libc, libfios2,
  libult) with `third_party/recomp/recomp/` (`cmake -S third_party/recomp/recomp
  -B build/recomp -G Ninja -DCMAKE_BUILD_TYPE=Release -DGENERATED_DIR=<abs>/generated
  -DVITA3K_SRC=<abs>/third_party/vita3k -DVITA3K_BUILD=<abs>/build/vita3k`, in an
  MSVC shell; a `build/recomp` configured from the old `recomp/` must be
  deleted and configured again) and set `SSD_AOT` to the `;`-separated DLL paths
  before launching the fork. The libraries are generated at their load
  addresses (docs/05-recompiler.md, which also lists the other `SSD_AOT_*`
  switches). A regenerated module that changes `aot_abi.h` needs a fork
  rebuild.
- `ss-delta.exe` (Phase 6, [D10](docs/decisions.md)) is built next to
  `Vita3K.exe` in `build/vita3k/bin/RelWithDebInfo/`. It reads
  `ss-delta.ini` there (set `vita_fs` and `recompiled` for this machine)
  and logs to `ss-delta/vita3k.log`. Drive it with
  `python -I third_party/recomp/tools/v3kdrive.py <bin dir> start`, then
  `run`/`close` as for Vita3K.
  `python -I third_party/recomp/tools/make-dist.py --project . [--vita-fs <fs>] [--name x]`
  lays out a self-contained folder in `dist/` (ignored; it holds the
  game-derived `ssd_aot_*.dll`; the ini comes from `ss-delta.exe
  --write-ini`, the README from `docs/dist-readme.txt`, `run-player2.bat`
  from `game.json`).
- `python -I third_party/recomp/tools/install-game.py --project . --firmware <PUPs>
  --install <zip> [--name x]` does the whole thing from a dump into
  `dist/<name>/` (work files in `build/install-<name>/`), as `game.json`
  says (supported eboot, modules, load bases). `make-dist.py --no-jit`
  takes the exe built without dynarmic (`build-vita3k.py --no-jit` →
  `build/vita3k-nojit`). Never point a test install at the owner's `dist/`
  folders: use `--name scratch-...`.
- Firmware modules by hand (D11): run `ss-delta.exe` once with `SSD_DUMP_ELFS=1`, copy
  `ss-delta/elfdumps/PCSA00152/*_{sysmodule,libSceFt2,libpvf,libscemp4,libsceavplayer}.elf`
  to `extracted/elf/firmware/<name>.elf`, then
  `python -I third_party/recomp/recomp/recompile.py extracted/elf/firmware/<name>.elf generated/fw_<name>`
  (no `--load-base`: the dumps are relocated) and add `fw_<name>` to
  `RECOMP_MODULES` in `build/recomp`. `ss-delta.exe` runs on NativeCPU (no
  JIT) by default. `adhoc_matching` loads only in Ad Hoc Play (`--dump-elfs`
  loads it at the end): generate it with `--load-base 80757000` (D15).
- Ad Hoc Play tests: `ss-delta.exe --player N` (2-4) is another copy with
  Vita user N-1 (a copy of user 00's saves), `ss-delta/player<N>/` and the
  address 127.0.0.N; `v3kdrive.py ... --player N` drives it. Test as players
  3 and 4: the owner plays players 1 and 2 (users 00 and 01, their own co-op
  progress since 2026-10-12) from the shared `extracted/vita3k/fs`.
- Game archives: `python -I tools/lspk.py list|extract <.../retail/archive> ...`
  (`archive_patch3` overrides `archive`). `tools/questmaps.py` turns
  `quest_param.csv` into the map list `tools/map-sweep.ps1` sweeps through
  Stage Select (screenshots under `build/`, never committed).
- `ss-delta.exe` hands the game a copy of `boot_config.ini` with
  `ResoDown 0` (`full_3d`, D13) plus any `[boot_config]` keys from the ini;
  the installed file stays untouched. Don't set `SSD_AOT` by hand for
  `ss-delta.exe` runs: it then loads only those DLLs, not the firmware
  modules, and the game stops in SceSysmodule.
- `v3kdrive.py` steps for `ss-delta.exe` only: `frame:<path>` (a PNG at
  render resolution, read back on the render thread), `touch:x:y:ms`,
  `tdown:x:y`/`tup` (960×544 points). Test data patches go in
  `build/vita3k/bin/RelWithDebInfo/patch/PCSA00152.txt` (Vita3K's patch
  format, `[eboot.bin]` then `seg:offset hexbytes`, little-endian values).
  Remove the file after use. A code patch disables native code for the
  eboot.
- `record:<n>:<dir>` (v3kdrive, `ss-delta.exe`) saves the next n rendered
  frames as PNGs: use it for glitches that last a few frames (the ST03A
  water patch is 5 frames). `close` now posts WM_CLOSE and waits up to 8 s
  before killing, so the async log is complete.
- Our fork's shader cache version is 16 (patch 0039), so the files are
  `vk16-*.spv`; leftover `vk15-*` and older files are unused and can be deleted.
- A crash in `amdvlk64.dll` (`c0000409`) at quest load on every run means a
  stale shader in `cache/shaders/PCSA00152` (e.g. from a run with another
  `memory-mapping`). Move the folder aside rather than hunting further.
- Saves: the game has three slots, `datag000N.bin` + `SlotParam_N.bin`, and
  one shared `system.bin` (the add-on record). `ss-delta.exe --import-save
  <folder|zip> [--slot N] [--quiet]` / `--export-save <dir> [--slot N]`
  (backups in `ss-delta/save-backups/`). The owner's install has their own
  save in slot 1 and the story-complete Apollo save in slot 2 (owner's
  request, 2026-10-11); load slot 2 for late-game tests instead of swapping
  files. Older copies: `build/save-backup-*`.
- `third_party/recomp/recomp/run-tests.ps1 -Root .` runs the test binaries
  under a memory and time ceiling (`recomp/tests/guarded-run.ps1` there).
  Keep new heavy steps guarded too: a runaway test once hung the machine
  (14 GB RAM).
- Test runs that must not touch the owner's saves or install: a folder with
  `ss-delta.exe`, its DLLs, the `ssd_aot_*.dll` and an `ss-delta.ini` whose
  `vita_fs` is a junction file system (junctions to the shared `fs/`, but
  `ux0/user` copied, and `ux0/app/PCSA00152/resource` a real folder with
  copies of its `.ini` files, so `bootseq` on that folder writes the copy).
- NID names: vitasdk `vita-headers` db in `third_party/vita-headers/db/360`
  (pinned commit in `PINNED_COMMIT`, not committed). The code inventory is
  regenerated with `third_party/recomp/tools/inventory.py` into
  `generated/inventory/`.
- In Bash heredocs, backslash escapes inside Python strings get mangled. Use
  the Edit tool, or build backslashes with `chr(92)`, for strings containing
  `\`.
- GitHub connections from this machine stall intermittently. Use
  `timeout` plus `-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30` and
  retry; codeload.github.com tarballs are reliable.
- `v3kdrive.py` never takes keyboard focus. Don't add focus-stealing
  input without asking.

## Keep docs current

- When a phase task completes, tick it in `docs/03-plan.md`.
- Record irreversible choices in `docs/decisions.md`.
- Put new binary facts in `docs/01-research.md` (or a new rom-analysis doc
  once it grows), and baseline changes in `docs/02-baseline.md`.
