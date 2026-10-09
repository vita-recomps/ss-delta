# ss-delta

A personal research project: a native PC port of **Soul Sacrifice Delta**
(PS Vita, PCSA00152, v1.30) by static recompilation, built from the owner's
own dump. It is a sibling of `<psp-project>` (Dissidia 012, PSP).

> **Private and non-distributed.** This repository contains *no* game data,
> *no* firmware and *no* code derived from the game. Everything is
> regenerated locally from the user's own dump. See [D2](docs/decisions.md).

## Status

Phase 0 (workspace, decryption, baseline) is done. Phase 1 is in progress:
our Vita3K fork builds, and with two patches it runs the game on Vulkan on
this machine's AMD GPU at 30 fps (upstream crashes there). Scripted input is
next. See the [plan](docs/03-plan.md).

## Documentation

| Doc | Contents |
|---|---|
| [01-research](docs/01-research.md) | prior work, the dump's structure, measurements of the 1.30 eboot, Vita3K as donor, approach options |
| [02-baseline](docs/02-baseline.md) | how the game behaves in Vita3K today, and how to re-run the baseline |
| [03-plan](docs/03-plan.md) | phases, exit criteria, risks |
| [decisions](docs/decisions.md) | decision log |
| [hashes](docs/hashes.md) | input hashes |

## Tools

| Script | What |
|---|---|
| `tools/velf.py` | Vita SCE ELF: segments, module_info, NID-named imports/exports, exidx |
| `tools/imix.py` | Capstone instruction-mix sweep over every exidx function |
| `tools/sfo.py` | print `param.sfo` fields |
| `tools/v3kdrive.py` | drive the portable Vita3K for baseline runs: launch, `BootSequence`, FPS sampling, background screenshots |
| `tools/devshell.ps1` | dot-source to load MSVC x64 and point CMake at Qt 6.11.0 |
| `tools/build-vita3k.ps1` | configure and build our Vita3K fork (`third_party/vita3k`) into `build/vita3k` |
| `tools/package4090.ps1` | build `dist/ss-delta-vita3k-test` (both Vita3K builds, the installed game, `run-matrix.bat`/`play.bat` from `tools/pkg4090/`) for testing on another PC |

Python dependencies: `pyyaml`, `capstone`, `pycryptodome` (for SELF
decryption).
