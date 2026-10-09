# Decisions

Irreversible or expensive choices, newest last.

## D1 — Hybrid: AOT-recompiled code inside a Vita3K fork, dynarmic fallback (proposed, 2026-10-09)

**Context:** [01-research](01-research.md#approach-options).

* No mature Vita recompiler exists, but Vita3K already runs the game.
* GXM and the USSE shader translator are the hardest parts of Vita emulation,
  and Vita3K has both.
* The first frame is reachable only through indirect calls, so there is no
  "recompile a small static subset" milestone.

**Decision:**

* Write our own Thumb-2/ARM → C++ recompiler.
* Run its output inside a Vita3K fork that dispatches to native code by guest
  address.
* Use dynarmic as the fallback and as the differential oracle.
* Shrink to a standalone runtime once coverage is complete
  ([plan](03-plan.md) Phases 3–6).

**Consequences:**

* The runtime is GPL-2.0-or-later (Vita3K).
* Thread, callback and HLE integration follow Vita3K's model until Phase 6.

**Status:** proposed. Confirm before Phase 3 starts.

## D2 — Nothing derived from the dump or firmware is committed (accepted, 2026-10-09)

**Decision:** none of the following go into git:

* extracted or decrypted files;
* ELFs;
* generated C++;
* Ghidra databases;
* screenshots or logs of the game;
* licences (RIF/work.bin);
* firmware.

Hashes, addresses, names and notes are fine. This is the same rule as
decimation D3.

**Consequences:**

* Every build regenerates from the user's own dump and firmware.
* The project stays private and non-distributed, which also keeps the GPL
  question moot.

## D3 — Target the merged US 1.30 build (accepted, 2026-10-09)

**Decision:** all analysis and the port target PCSA00152 at 1.30: the base
app plus the merged patch, eboot module NID `0xD66AEBF4`.

**Why:**

* It is the final version.
* It contains the post-launch content (Odin, Bahamut, collaboration
  costumes), and reportedly the DLC data.
* The VitaGrafix and XLink Kai patches exist for it.
* loktar00's numbers are for 1.10, so their addresses don't apply.

## D4 — OpenGL is the Vita3K reference backend on the dev machine for now (accepted, 2026-10-09)

**Context:** [02-baseline](02-baseline.md). Vulkan crashed at boot on the
Radeon 760M in all three runs; OpenGL reaches gameplay at 30 fps, with
rendering bugs.

**Decision:** baseline runs and early behavioural comparisons use OpenGL.
Rendering comparisons wait until Phase 1 fixes Vulkan, or until they can be
run on the RTX 4090 PC.

**Revisit:** when the Vulkan crash is understood.

**Update (2026-10-09):** Vita3K-Plus v1.2 boots on Vulkan on this machine and
renders the maps correctly, apart from a speckled player cloak. It becomes
the **rendering reference**. Upstream OpenGL stays the reference for
behaviour and timing until our own build exists. The RTX 4090 results
(`dist/ss-delta-vita3k-test`) will show which artifacts are AMD-specific.

**Update 2 (2026-10-09, RTX 4090 results):** every artifact depends on the
GPU vendor. No combination is correct on both GPUs.

* **Vulkan is the renderer to build on.** It is the only backend without
  gross errors on both vendors.
* Comparisons use two references:
  * Plus Vulkan on the mini PC;
  * upstream or Plus Vulkan on the RTX 4090.
* A difference between the two references is itself a bug signal, and
  points at undefined behaviour in shader translation (see
  [02-baseline](02-baseline.md#rtx-4090-results-2026-10-09)).
* OpenGL is no longer used for rendering judgements.

**Update 3 (2026-10-09):** our fork (patches 0002 and 0003) runs Vulkan on
the Radeon 760M. It renders the field correctly and the Walhalla floor
textured. **Our fork on Vulkan is now the reference on this machine.** Plus
stays as a cross-check. The NVIDIA reference needs a retest with our fork.

## D5 — Fork upstream Vita3K, not Vita3K-Plus; cherry-pick from Plus (accepted, 2026-10-09)

**Context:** Phase 1 needs a Vita3K source tree we build and patch. Plus v1.2
(tag `v1.2` = branch `all-enhancements`, `e2331f80`) is the build that runs
on Vulkan on the Radeon 760M. Measured against upstream:

* Merge base `5b040dc4` (2026-06-12, "app: Implement linux portable").
  This is also the hash in the Plus binary's build string `2-5b040dc4`.
* Plus adds 167 commits: 250 files, +17,964/−2,417 lines. Most target other
  games (Killzone, Uncharted, Resistance, Gundam, MGS3 …), Android/Mali/
  Turnip drivers, a thread-scheduling rework ("emulate the 3 cores"), and
  deadlock/hang watchdogs.
* Two commits name this game:
  * `98a65bff` "Fixes for depth in SSDelta": whole-mip-chain texture hashing,
    tiled depth-surface row rounding, full-width colour-surface reads,
    depth-bias slope × resolution multiplier;
  * `d248beee` "Refix Sacrifice Soul Delta outlines": MSAA depth surfaces
    read back as textures at the right samples-per-texel.
* Upstream has 98 commits since the merge base, which Plus lacks.

**Decision:**

* Our fork starts from upstream `master`. It lives in `third_party/vita3k` as
  a nested git clone (it is ~1 GB with submodules, too big to vendor as in
  decimation D6), on branch `ss-delta`.
* Plus is a second remote (`plus`) in that clone. Its fixes come over as
  cherry-picks, one at a time, each tested against this game.
* Our patch series is exported with `git format-patch` into
  `patches/vita3k/`, and that directory is committed here. The pinned
  upstream commit is recorded below.

**Why not Plus:**

* Its game-specific hacks and global scheduling/watchdog changes would be
  noise in the Phase 4 differential work.
* Fixes made on upstream can be sent upstream.
* Plus is behind upstream by 98 commits, and rebasing it is not our job.

**Consequences:** the AMD Vulkan crash has to be found by debugging upstream
directly, with the Plus diff as a hint rather than a ready-made fix.

**Pinned:** upstream `b75d5e62` (2026-10-09, "appimage: Correctly copy data
folder (#4216)").
