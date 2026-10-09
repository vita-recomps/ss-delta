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
- Vulkan is the renderer to build on ([D4](docs/decisions.md) update 2).
  Upstream Vulkan crashes at boot on this machine's Radeon 760M (inside
  `amdvlk64.dll`); Vita3K-Plus v1.2 (`extracted/vita3k-plus/1.2/`) runs on
  Vulkan here.
- Our Vita3K fork: `third_party/vita3k`, a nested git clone on branch
  `ss-delta` ([D5](docs/decisions.md)), with Plus as remote `plus`. Build it
  with `. .\tools\devshell.ps1; .\tools\build-vita3k.ps1` (MSVC + Ninja,
  Qt 6.11.0 in `C:\Qt`) into `build/vita3k`. Export our commits to
  `patches/vita3k/` with `git format-patch` before committing here.
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
