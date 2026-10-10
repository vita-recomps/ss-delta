# CLAUDE.md

A static-recompilation PC port of Soul Sacrifice Delta (PS Vita, PCSA00152,
1.30). Start with `README.md` and `docs/03-plan.md` to find the current phase.
Sibling project: `<psp-project>` (Dissidia 012, PSP), which has the same
conventions.

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
  `python -I tools/v3kdrive.py extracted/vita3k bootseq PCSA00152 <name>`.
- Our Vita3K fork: `third_party/vita3k`, a nested git clone on branch
  `ss-delta` ([D5](docs/decisions.md)), with Plus as remote `plus`. Build it
  with `. .\tools\devshell.ps1; .\tools\build-vita3k.ps1` (MSVC + Ninja,
  Qt 6.11.0 in `C:\Qt`) into `build/vita3k`. Export our commits to
  `patches/vita3k/` with `git format-patch` before committing here.
- Our build's `config.yml` must keep `disable-surface-sync: false` and
  `high-accuracy: true` (D4 update 4: fog, haze and smoke) and
  `memory-mapping: double-buffer` (`external-host` hides objects).
- The shader cache in `build/vita3k/bin/RelWithDebInfo/cache/shaders/` is
  keyed by guest shader, not by translator version. Runs of a build with
  changed shader translation (debug branches, `SSD_DENORM`, ...) leave
  shaders there that break later runs: move the title's folder aside after
  such runs.
- Recompiled code: build `ssd_aot_<module>.dll` (eboot, libc, libfios2,
  libult) with `recomp/` and set `SSD_AOT` to the `;`-separated DLL paths
  before launching the fork. The libraries are generated at their load
  addresses (docs/05-recompiler.md, which also lists the other `SSD_AOT_*`
  switches). A regenerated module that changes `aot_abi.h` needs a fork
  rebuild.
- `ss-delta.exe` (Phase 6, [D10](docs/decisions.md)) is built next to
  `Vita3K.exe` in `build/vita3k/bin/RelWithDebInfo/`. It reads
  `ss-delta.ini` there (set `vita_fs` and `recompiled` for this machine)
  and logs to `ss-delta/vita3k.log`. Drive it with
  `python -I tools/v3kdrive.py <bin dir> start`, then `run`/`close` as for
  Vita3K. `tools/make-dist.ps1 [-VitaFs <fs>]` lays out a self-contained
  folder in `dist/` (ignored; it holds the game-derived `ssd_aot_*.dll`).
- `recomp/run-tests.ps1` runs the test binaries under a memory and time
  ceiling (`recomp/tests/guarded-run.ps1`). Keep new heavy steps guarded
  too: a runaway test once hung the machine (14 GB RAM).
- NID names: vitasdk `vita-headers` db in `third_party/vita-headers/db/360`
  (pinned commit in `PINNED_COMMIT`, not committed). The code inventory is
  regenerated with `tools/inventory.py` into `generated/inventory/`.
- In Bash heredocs, backslash escapes inside Python strings get mangled. Use
  the Edit tool, or build backslashes with `chr(92)`, for strings containing
  `\`.
- GitHub connections from this machine stall intermittently. Use
  `timeout` plus `-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30` and
  retry; codeload.github.com tarballs are reliable.
- `tools/v3kdrive.py` never takes keyboard focus. Don't add focus-stealing
  input without asking.

## Keep docs current

- When a phase task completes, tick it in `docs/03-plan.md`.
- Record irreversible choices in `docs/decisions.md`.
- Put new binary facts in `docs/01-research.md` (or a new rom-analysis doc
  once it grows), and baseline changes in `docs/02-baseline.md`.
