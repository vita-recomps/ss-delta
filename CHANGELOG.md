# Changelog

The changes in each release of ss-delta. The downloads and each release's
full notes are on the [releases page](https://github.com/vita-recomps/ss-delta/releases);
[INSTALLING](docs/INSTALLING.md#updating) explains how to update.

## Unreleased

### New

* **Android: view and share diagnostic reports**
  ([#29](https://github.com/vita-recomps/ss-delta/issues/29),
  [Vita3K#2](https://github.com/vita-recomps/Vita3K/pull/2), contributed by
  ELLINDON): the setup screen has **View diagnostic report** and **Share
  diagnostic report**, and the settings menu's Debug page has **Share
  diagnostic report**. Each report writes an immutable snapshot of device
  details and bounded tails of the setup and game logs (omitting matching
  licence-key lines) and shares it through a non-exported read-only content
  provider, so Android issues can be reported without USB/adb.

### Fixed

* **Audio during an Ad Hoc Play pause**: opening the settings menu (or
  pausing) during Ad Hoc Play now mutes the audio ports while keeping the
  audio device draining at its normal rate, instead of suspending the
  device while guest threads keep running. Offline pauses still suspend
  the device.
* **Controls page fixes**:
  * Binding `leftstick`, `rightstick` or `guide` to a Vita button or a
    touch binding (such as Black Rite) no longer triggers L3, R3 or PS as
    well.
  * `[mouse] capture_key` now accepts mouse buttons too, and a game
    binding on the same key takes priority over cursor capture
    (middle-click still captures the cursor).
  * Touch- and pen-generated clicks on a touchscreen PC or Steam Deck are
    ignored while waiting for a new key binding, instead of binding
    `MouseLeft`.
  * Enter always confirms in the desktop settings menu, so clearing both
    Cross and Start can no longer leave a keyboard-only player stuck.
  * Live gamepad binding edits now share a mutex with guest controller
    reads while the game runs behind the menu during Ad Hoc Play.
* **A dump carrying a rePatch mod with a standalone title folder**
  (`PCSA00152/`, with no `app/` folder, including wrapped dumps and mods
  carrying a `param.sfo`) now installs both the game and the mod instead
  of only the mod.
* **A rare shutdown hang** when the display queue was full:
  `Queue::abort()` now holds the queue's mutex while updating its abort
  flag so blocked `push()` and `wait_space()` callers cannot miss the
  wakeup.
* **Stale setup error messages**: `step-error.txt` is now cleared before
  each install step on PC and Android so a later crash cannot report an
  earlier run's licence error.
* **Compiler downloads on slow lines**: a source dropped for being slower
  than 256 KB/s is retried without the speed floor if all mirrors fail,
  and the Windows `curl.exe` speed-limited attempt no longer retries
  three times before moving on.
* **Android: firmware size text**: the setup screen now says about
  180 MB, matching the PC readmes and release notes.

### Changed

* **`--android` setup and `adb`**: reuses an `adb` already installed on
  `PATH` or in the Android SDK (skipping Google's SDK licence prompt and
  leaving its server running). When setup must download `adb` while an
  existing server is running, it warns about a possible version conflict
  instead of stopping that server.
* **Recompiler and macOS modules**: ARM jump-table decoding verifies that
  the preceding `cmp` matches the index register with a valid bound;
  macOS recompiled `.dylib` modules narrow their Mach-O export trie to
  the two AOT entry points (`armrecomp_aot_init`,
  `armrecomp_aot_features`) and renew their ad-hoc signature.
* **Tests and release workflow**: the pause, audio-pause and queue unit
  tests are wired into CMake/CTest and run on every PC release job; all
  four release jobs build and check a synthetic AOT module with the
  shipped Zig toolchain; configure dependencies and Gradle are cached and
  bounded with retries, `ci-wait-job.py` fails fast on permanent GitHub
  API errors, and `sccache-action` is pinned by commit SHA.

## 0.6.0 (2026-11-26)

### New

* **Key bindings in the settings menu**
  ([#24](https://github.com/vita-recomps/ss-delta/issues/24)): a Controls
  page lists each Vita button's key, second key, gamepad button and second
  gamepad button, and the Black Rite. Pick one and press the new key or
  button (one already in use changes places), or reset all controls. On
  Android the page shows the gamepad's buttons only.
* **Two gamepad inputs per Vita button, the triggers among them**
  ([#26](https://github.com/vita-recomps/ss-delta/issues/26)): `[gamepad]`
  takes up to two inputs for each Vita button (`up = dpup, righttrigger`),
  and LT and RT can be bound like any button, on the Controls page too
  (#26 asked for RT as a second D-pad up, for the support spells in
  combat, with the D-pad kept for the menus). A trigger bound this way still works as L2
  or R2 as well, which the game reads only with PS TV controls on. The
  button prompts show LT/RT (ZL/ZR, L2/R2) for a Vita button whose first
  input is a trigger.
* **Mouse buttons as bindings**: the side buttons (MouseX1, MouseX2) bind
  like keys, and MouseLeft and MouseRight while the mouse camera has the
  cursor.
* **Keyboard button prompts**: `[game] button_labels = keyboard` draws the
  bound key in a keycap over each button symbol in the game; `auto`
  follows what you used last, keyboard or gamepad (touches, the on-screen
  controls and Android's keys don't count). On macOS the Command keys read
  CMD.
* **Nintendo button prompts**: `[game] button_labels = nintendo` shows a
  Switch Pro Controller's buttons: A on the right, B at the bottom, X at
  the top, Y on the left, L, R, + and −. `auto` picks it for a Nintendo
  pad.
* **Android: handheld button prompts**: `[game] button_labels = handheld`
  (Android handheld) for the built-in controls of the Retroid Pocket, AYN
  and other Android handhelds, which letter their face buttons the
  Nintendo way, name their shoulders L1 and R1, and keep Xbox's View and
  Menu buttons. Pick it by hand: these devices report themselves as Xbox
  pads.
* **FPS counter**: FPS counter on the settings menu's Display page
  (`[display] fps_counter`) shows the frame rate in the top left corner,
  with the frame time, the last minute's lowest, average and highest, and
  a graph as you choose.
* **Android: the setup takes your own firmware files.** If you have the PS
  Vita firmware 3.74's `PSVUPDAT.PUP` and `PSP2UPDAT.PUP`, **Add firmware
  files** on the setup screen takes them (one or both, whatever their
  names; they are checked against the right ones), and they aren't
  downloaded from Sony.
* **Invincible cheat** (`[cheats] invincible`): enemies' attacks neither
  hurt you nor knock you down, so you keep control in a fight; attacks
  that cost health cost none either. It switches on the game's own debug
  switch for this (NoDamage). A boss's shockwave or wing gust still makes
  you brace for a moment.
* **F5 marks the moment in the log**: when something goes wrong, press F5
  and `vita3k.log` gets a line `User mark N at frame F`, so a bug report
  shows where to look. A binding on F5 still works.
* **Slow frames in the log**: a game frame that takes longer than 100 ms
  gets a `Hitch` line in `vita3k.log`, with the number of shaders built
  meanwhile, which helps with a stutter report. The settings menu's Debug
  page sets the limit (`[debug] hitch_log_ms`, 0 turns it off).

### Fixed

* **The settings menu pauses the game**
  ([#29](https://github.com/vita-recomps/ss-delta/issues/29), contributed
  by ELLINDON): until now, opening it stopped the sound while the game
  kept running behind it, on every system. During Ad Hoc Play the game
  keeps running behind the menu, so the other players don't drop you.
* **Android: the game pauses while the app is in the background.** It
  went on behind the home screen, using more of the CPU than in front
  (on the AYN Thor, about 11% now instead of 240%). During Ad Hoc Play it
  keeps running there too.
* **A crash when a journal chapter was opened again after a quest**
  (Seeing Red, chapter 3, from the journal): with full-resolution 3D the
  game ran out of graphics memory in the chapter's scene. Its Graphics
  pool is 64 MB now instead of 56.
* **A dump that also carries a rePatch mod** (a fan patch packed with the
  game) installed only the mod; it now installs the game, then the mod.
* **A recompiled module that can't be loaded** left the game stopped at
  its title, with one line in the log. A message now names it and asks
  you to build the game again.
* **Android: the Turnip offer comes before the setup's first run of the
  game** ([#25](https://github.com/vita-recomps/ss-delta/issues/25)), not
  only at Play. On an Adreno 735, Qualcomm's driver crashed in that run,
  so the game was never built.
* **A `.pkg` with a licence for other content**
  ([#25](https://github.com/vita-recomps/ss-delta/issues/25)): a
  `work.bin` or `.rif` picked for the wrong game or add-on (the US voice
  pack's for the EU one, say) unpacked the whole package and then failed
  with only "exit 1". The install now stops at once and says, on the
  setup screen (PC and Android), which content the licence is for and
  which one to pick. For an update, the licence already installed with the
  game is used instead. Any add-on that fails to install is named on the
  screen too, instead of "see the log".
* **Android: the setup no longer waits behind the notification
  permission dialog.** The app asks when the setup screen opens, not when
  you tap Build.

### Changed

* **The firmware download** has one more fallback: when Sony's servers
  and the Wayback Machine's copies both fail, the setup takes the
  firmware from RetroBIOS's copy on GitHub. Every copy is held to the
  firmware's known size and SHA-256 while it downloads, so a wrong or
  damaged file is refused at once rather than after the whole download.
* **The compiler's download** (zig, which the release already carries; it
  is downloaded only when building from the repository) has community
  mirrors, and a mirror slower than 256 KB/s is left for the next.
* **From Vita3K**: the display queue follows the firmware's limits
  (queue length, waiting for a free slot), and additions to it are
  serialized and refused after the game shuts its graphics down.
* **Renderer**: a surface read right after it was drawn now reaches the
  game's memory in the `double-buffer` mapping too (it broke another game
  on the same tools; no change seen in Soul Sacrifice Delta).
* **Recompiler**: more ARM code is handled (jump tables through
  `ldr pc`, NEON `vuzp` and fixed-point `vcvt`, calls through linker
  veneers, ARM-mode `movw`/`movt` relocations), for other games built
  with the same tools.

## 0.5.3 (2026-11-25)

### Fixed

* **Android: building the game on the device stopped at "Recompiling
  eboot"** since 0.5.0 (`FileNotFoundError: ... overrides/eboot.json`):
  the APK didn't carry the game's code fixes (the 60 fps fixes of
  [#14](https://github.com/vita-recomps/ss-delta/issues/14) and the
  loading screens), which the build needs. Building from a PC
  (`--android`) wasn't affected.

## 0.5.2 (2026-11-25)

### Fixed

* **Android: the game's files wouldn't install on some phones**
  ([#23](https://github.com/vita-recomps/ss-delta/issues/23)), such as a
  Galaxy S25: the setup stopped at "Failed to load archive file". The app
  now reads the files you pick through the access Android's file picker
  gives it, instead of opening them again by name, which those phones
  refuse to an app without storage permission.
* **Building the Android app's game from Windows** (`--android`) stopped
  with `relocation R_AARCH64_ABS64 cannot be used against symbol ...;
  recompile with -fPIC` since 0.5.0
  ([#23](https://github.com/vita-recomps/ss-delta/issues/23)).
* **Square blocks in smoke, fire and fog on some graphics cards**
  ([#17](https://github.com/vita-recomps/ss-delta/issues/17)): cards whose
  driver has neither shader interlock nor raster-order attachment access
  (older AMD Radeon, such as the R5 in an A10-9600P laptop; Qualcomm's own
  Adreno driver on Android). The log's `Framebuffer reads:` line says
  "no, no" on those. The smoke, fire and fog shaders there now leave their
  blending to the graphics card's own blender instead of reading the
  picture, which looks as on other cards; the few shaders that can't
  still read a copy of the picture. `[debug] shader_blend` and
  `[debug] framebuffer_reads` on the settings menu's Debug page change
  this if something looks wrong on your card.

### New

* **Ad Hoc Play over the internet**, through a VPN (Tailscale, ZeroTier,
  Radmin VPN or another) or between subnets, where broadcasts don't arrive:
  the other players type the host's VPN address into **Peers (host
  address)** on the settings menu's Multiplayer page. Step by step:
  [Playing together over the internet](docs/ONLINE-PLAY.md).
* **Typing in the settings menu**: Peers takes a keyboard (Android's
  on-screen one too) or a gamepad (Up/Down change the character under the
  cursor).
* **Network adapter `auto`** (the new default) takes the adapter that
  reaches the first peer, or the one of the internet connection, not a
  virtual adapter that Windows lists first (Hyper-V, WSL).
* **The log lists every graphics card** Vulkan offers the game, and
  `[debug] gpu` picks one by its number there (for a laptop that starts on
  the wrong one).
* **Ad Hoc Play over LAN: the log names the network adapter** the game uses,
  with its address, and lists the others
  ([#21](https://github.com/vita-recomps/ss-delta/issues/21)). If it is a
  virtual one (vEthernet, Hyper-V, VPN), pick your home network's on the
  settings menu's Multiplayer page. `[debug] net_trace` logs every Ad Hoc
  packet, for a connection that doesn't work.

## 0.5.1 (2026-11-24)

### New

* **Building without internet**: `--download-only <folder>` saves
  everything the first build downloads (the firmware and the compiler),
  and a build then takes them from that folder (`--offline <folder>`, the
  importer's "Downloaded files" row, or a folder named `offline` in the
  game's folder) instead of the internet. Firmware PUPs you already have
  work too, whatever their names. See
  [INSTALLING](docs/INSTALLING.md#without-internet).
* **The cursor hides by itself**
  ([#16](https://github.com/vita-recomps/ss-delta/issues/16)) when the
  mouse has been still for 3 seconds, and at once when you use a key or a
  gamepad; moving the mouse shows it again. Hide idle cursor on the
  settings menu's Mouse page turns it off.

### Changed

* **The compiler comes with the release; no Microsoft licence.** The
  game's code is now compiled with zig on Windows too, as on Linux and
  macOS, and each release carries it: the first build downloads only the
  PS Vita firmware (about 180 MB; Windows downloaded 650 MB before), and
  there is no Microsoft licence to accept. `--accept-microsoft-license`
  is still accepted and does nothing. The release download is about
  90 MB larger.
* **Fallback downloads**: when Sony's server (or ziglang.org) doesn't
  answer, the setup takes the same files from the Wayback Machine's
  copies, checked by SHA-256.
* **RecompLauncher: no second build for nothing.** When the launcher runs
  the setup again with the same release and the same dump, it now ends at
  once ("Already built") instead of building the game again; a new
  release or another dump still builds. `--rebuild` builds anyway. The
  launcher's setup text no longer mentions a compiler download.

### Fixed

* **Spirits' Wolf fang and Spirits' Dragon fang: the thrust no longer
  crashes the game** ([#18](https://github.com/vita-recomps/ss-delta/issues/18))
  or misses. Their punch still named a skill Delta removed; it now does
  the arm's damage, as Delta's own fang arms do. The Spirits' offerings
  are rebuilt once when the game starts.
* **Spirits' Flame Arrow and Spirits' Stone Arrow fire their arrows**
  ([#19](https://github.com/vita-recomps/ss-delta/issues/19)); they had
  drawn none and done no damage. ss-delta had left out part of the
  Spirits' effect data, so other Spirits' offerings (the swords, giant
  arms, eggs, roots, Frostfluff, Falconfeather) now also have all their
  effects, as the original game's did.

## 0.5.0 (2026-11-23)

### New

* **The original game's Spirits' offerings**
  ([#11](https://github.com/vita-recomps/ss-delta/issues/11)): the 20
  pre-order offerings of the first *Soul Sacrifice* (Spirits' Flamepike
  ... Spirits' Gravelshield). Delta still has them, switched off; ss-delta
  switches them on and gives each once per save, with Add-ons (DLC) on
  (`[game] spirits_offerings`, on by default). They look and play like
  Delta's own offerings of the same kind. No copy of the original is
  needed. See [INSTALLING](docs/INSTALLING.md).

* **PS TV controls** ([#12](https://github.com/vita-recomps/ss-delta/issues/12)):
  `[game] pstv_mode` (the settings menu's Game page) runs the game as a
  PlayStation TV, which has no touchscreen. The one touch the story
  needs, pulling Librom out of the bones at the start of a new game, then
  takes L2 or R2 (the gamepad's triggers, U and O on the keyboard). AR
  mode and "near" are unavailable then.

* **All eight Blank Page slots**
  ([#15](https://github.com/vita-recomps/ss-delta/issues/15)): Librom's
  Blank Page has eight slots for created pact pages, and only three are
  open. The other five were unlocked with Memory Clods, bought on the
  PlayStation Store. With Add-ons (DLC) on, ss-delta now unlocks them in
  the loaded save, and the game keeps them when it saves. "Sacrifice
  memory", which made a page with a Memory Clod instead of an Offering
  (with rewards you don't own yet), works too.

* **Sortiara as an ally**: Sortiara, who fights beside you in the early
  story, can join your allies (`[game] sortiara_ally`, off by default; the
  settings menu's Game page). The game has everything she needs as an ally
  (her offerings, voice and portrait) but never adds her. She is added once
  per save, listed NEW in Portraiture > Allies, and the game keeps her when
  it saves.

### Fixed

* **"Failed to load save data." with Add-ons (DLC) on** (since 0.4.2): a
  save that was never saved with the add-on gifts in it (an imported Vita
  save, for example) could fail to load. The gifts were written into the
  save while the game's "Loading complete" dialog was up, and the game's
  own check of the file then failed. They are now given without breaking
  that check.
* **Blitz offerings at 60 fps**
  ([#14](https://github.com/vita-recomps/ss-delta/issues/14)): after a hit,
  a Blitz offering's push-back moved the caster a fixed step every frame,
  so at 60 fps it threw you almost twice as far as on the Vita and the
  next cast of a chain fell short. The steps now follow the frame time, so
  60 fps plays like 30.
* **Loading screens run at 60 fps.** The quest-start loading screen could
  hang at 60 fps, so loading screens were kept at 30 (`frame_rate`). The
  hang was a race in the game: the loader can finish before the screen's
  opening animation ends, and its looping animation then never stops. This
  is fixed in the recompiled code, so loading screens now run at the set
  rate. A game built before this update still loads at 30 until it is
  built again.
* **Games copied straight off a Vita**
  ([#13](https://github.com/vita-recomps/ss-delta/issues/13)): their
  folders carry the PSN account's own licence, usable only on that Vita,
  and the setup stopped with "header signature is invalid". It now says
  what is wrong before its downloads, takes the NoNpDrm licence in the
  dump's `license/` folder in place of that licence, and uses a licence
  given with a folder or `.zip` (it used to be ignored). See
  [INSTALLING](docs/INSTALLING.md#what-you-need), "From your own Vita".
* **Linux and the Steam Deck: the update in the same folder as the game
  could be left out** (#13). The game and its update were installed in the
  order the file system lists them, and on Linux the update could come
  first and fail; the setup then stopped with "eboot.bin is not a build
  this port supports" (the game's 1.00). The game is now always installed
  first, and the setup says when the update is missing.
* A folder whose game failed to install while something else in it
  installed counted as installed; the setup then stopped with "no
  PCSA00152 or PCSF00532 ... after installing" instead of the reason.
* Removing a packaged mod that had added a table the game's patch archive
  lacks left a copy of the archive in `fs/ux0/rePatch/`; it is deleted now.

## 0.4.3 (2026-11-22)

### Fixed

* **The setup refused dumps decrypted by an older Vita3K**
  ([#9](https://github.com/vita-recomps/ss-delta/issues/9)): "eboot.bin is
  not a build this port supports". Vita3K versions before December 2024
  decrypted the game's files when they installed it, and folders copied out
  of such an install (often named "[vita3k]") hold those decrypted files.
  They are the same 1.30 game, US or EU, and are now accepted.

## 0.4.2 (2026-11-22)

### New

* **The add-ons PSN gave as gifts are unlocked too**
  ([#11](https://github.com/vita-recomps/ss-delta/issues/11)): the
  Soulbinder, Fox (the gift "Necky"), Slave, Great Seer ("Archsorcerer"),
  Mad Witch, Easterner, Disciple ("Saint"), Beast and White Cat raiments,
  eight hoods (Fox Hood, Demon's Horns, Golden Mask, Mind's Eyewear,
  Wizard's Hat, Magic Helm, Polytan Hood, Possessed Mask) and the Fox
  Sigil. On the Vita they came from the Claim Gift page at Cassus, which
  needs PSN; now they appear in your save, marked NEW, with `[game] dlc`
  on (the default). See them all in the [gallery](docs/GALLERY.md).
* **The raiments only Japan had**: Sylvan and Benkei, both in the game's
  data (`[game] japan_raiments`, on by default; Japan-only raiments in the
  settings menu).
* **The original game's raiments**, ARKS Armor and Dragonslayer, as a mod
  you make from your own copy of the first *Soul Sacrifice* (1.30):
  `tools/og-raiments.py` in the repository makes it, a 1.4 MB `.zip`, and
  installs it ([INSTALLING](docs/INSTALLING.md#what-you-need)).
* **Packaged mods**: a `.zip` with an `ss-delta-mod.json` is added like
  any mod (the importer, `--dump`, Android's Add an add-on), but merged
  into the game's archive instead of replacing it, so it works with the
  Undub installed before or after it. `--remove-mod <id>` takes it out
  again.
* **The logs of the last five runs are kept**: `ss-delta/vita3k.log` is
  the latest, `vita3k.1.log` to `vita3k.4.log` the runs before it. A
  report sent after the game was started again (RecompLauncher sends the
  whole log folder) still carries the run that crashed.

## 0.4.1 (2026-11-21)

### Fixed

* **Windows: the setup stopped with "msiexec failed (1639)"** when the
  temp folder's path has a space, as under a Windows user name with a
  space. Windows Installer refused the folder the setup unpacks the Windows
  SDK into. One cause of
  [#9](https://github.com/vita-recomps/ss-delta/issues/9), possibly not the
  only one. Linux, macOS and Android are the same as 0.4.0.

## 0.4.0 (2026-11-21)

### New

* **Android:** an APK for Android 9 or newer on 64-bit ARM with Vulkan, made
  for Snapdragon handhelds (tested on an AYN Thor). Its setup screen builds
  the game on the device from your dump, with no PC: it downloads the
  firmware from Sony and compiles the native code with its own compiler, in
  about 15 minutes on a Snapdragon 8 Gen 2. After an app update it builds
  again by itself, without asking for the dump. On Adreno GPUs it offers to
  download Turnip. It has on-screen controls for phones without a gamepad,
  with a LOCK toggle for the lock-on. `ss-delta.exe --android` puts a game
  built on a PC on a device. The APK is signed with the project's release
  key, so later versions install over it.
* **Cheats** ([#7](https://github.com/vita-recomps/ss-delta/issues/7)) on
  every platform, on the settings menu's Cheats page: Infinite health,
  Unlimited offerings, Lasting offerings, One-hit kills, Max Lacrima and Max
  levels.
* **The Japanese Voice-over Pack**
  ([#8](https://github.com/vita-recomps/ss-delta/issues/8)), the game's
  separate PSN add-on, installs as an add-on. Once the game is built, an
  add-on goes in on its own without building again: `--dump`, the
  importer, **Add an add-on** on Android, or RecompLauncher's Add-ons step.
* **rePatch mods, such as the Undub patch**
  ([#8](https://github.com/vita-recomps/ss-delta/issues/8)), for Japanese
  voices from the start. They are kept beside the game, and **Mods
  (rePatch)** on the settings menu turns them off.
* **Xbox button labels** in the game's prompts, tutorial pictures and text
  (Button prompts), following your gamepad bindings.
* **Mouse camera** on Windows, Linux and macOS: Tab or a middle click
  captures the cursor and the mouse turns the camera (the Mouse page:
  Sensitivity, Invert vertical).
* **Skip intro logos**
  ([#6](https://github.com/vita-recomps/ss-delta/issues/6)), off by
  default: the game opens on its title screen after about 6 seconds instead
  of 20.

### Fixed

* A dump that holds only the 1.30 update
  ([#5](https://github.com/vita-recomps/ss-delta/issues/5)): the setup
  now stops before the downloads and says what to give it, instead of
  failing at the end with "Install app before patch".
* The settings menu's page names ran into each other in its tab bar.
* The settings menu froze when opened over one of the system's dialogs
  (the save list, "Do you want to load this saved data?").

## 0.3.1 (2026-11-19)

### New

* **RecompLauncher:** every release carries a `recomplauncher.json`, so
  [RecompLauncher](https://recomplauncher.com) can install the game, build
  it from your dump, show its main settings, back up the saves and rebuild
  after an update.
* **Exit from a gamepad:** the settings menu's last page, Exit.
* **`--progress`:** progress lines while building, for a launcher's
  progress bar.

### Fixed

* Laptops with an AMD and an NVIDIA GPU
  ([#4](https://github.com/vita-recomps/ss-delta/issues/4)): the build
  could stop near the end with "LoadLibrary failed with error 87". The
  game asks for the dedicated GPU again.

## 0.3.0 (2026-11-18)

### New

* **Linux and the Steam Deck:** a native `ss-delta.x86_64`, built in the
  Steam Runtime SDK; the importer can add the game to Steam. Quests run at
  60 fps on the Deck.
* **macOS on Apple Silicon:** a native app on Metal (MoltenVK), at 60 fps
  on all 50 quest maps; Game Mode in fullscreen.
* **Ad Hoc Play across platforms:** Windows, Linux and macOS copies play
  together over a LAN, with any of them as host.
* **One program, one folder:** the download is the game's folder. It
  builds itself from your dump the first time it starts, and keeps
  everything inside its folder (the separate setup of 0.1 and 0.2 is gone).
* **A command line for everything:** `--dump`, `--install`, `--build-only`,
  `--game`, `--add-to-steam`, `--fullscreen`/`--windowed`, `--set`.
* The importer reads your dump and doesn't ask again for what it already
  holds (the 1.30 update, the licence).

### Fixed

* Keyboard diagonals ran about 1.4 times as fast as straight movement.
* A room hosted over Wi-Fi (a Steam Deck or a Mac) couldn't be joined.
* Linux and macOS: "A network error has occurred" after leaving a room,
  and menus that stopped responding on macOS.
* Windows: downloads failed on PCs where Python couldn't check a server's
  certificate.

## 0.2.1 (2026-11-17)

### New

* **Language setting**
  ([#3](https://github.com/vita-recomps/ss-delta/issues/3)) on the
  settings menu's Game page: English, French, Spanish and Portuguese
  (Brazil) in the US game; English, French, Spanish, German and Italian in
  the EU game.

## 0.2.0 (2026-11-17)

### New

* **The EU version**
  ([#2](https://github.com/vita-recomps/ss-delta/issues/2)), PCSF00532
  at update 1.30. It is the same build as the US game, so the same
  recompiled code serves both.

## 0.1.0 (2026-11-16)

The first release
([#1](https://github.com/vita-recomps/ss-delta/issues/1)), for Windows: a
setup (`setup.bat`) that builds a playable folder from your own dump of
the US game (PCSA00152, update 1.30).

* The game's code, and the firmware modules it loads, recompiled ahead of
  time to C++ and run natively, without a JIT.
* 60 fps with the game's speed kept, and the 3D at full resolution
  (960×544 times the resolution multiplier).
* Rendering fixes, among them the white floors on NVIDIA GPUs.
* Ad Hoc Play for up to four copies, on one PC or across a LAN.
* The add-ons' content unlocked.
* An in-game settings menu, a commented `ss-delta.ini`, and Vita saves
  imported and exported.
