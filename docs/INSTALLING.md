# Installing ss-delta

ss-delta runs **Soul Sacrifice Delta** natively on Windows, Linux (and the
Steam Deck), macOS on Apple Silicon, and Android. The downloads contain no
game files and no code derived from the game: the first start builds the
game on your computer or device from **your own dump** of it.

## Contents

* [What you need](#what-you-need)
* [Windows](#windows)
* [Linux and the Steam Deck](#linux-and-the-steam-deck)
* [macOS (Apple Silicon)](#macos-apple-silicon)
* [Android](#android)
* [The first start: building the game](#the-first-start-building-the-game)
  ([without internet](#without-internet))
* [Playing](#playing) ([controls](#controls))
* [Saves](#saves)
* [Ad Hoc Play](#ad-hoc-play)
* [Files and folders](#files-and-folders)
* [Command-line options](#command-line-options)
* [Updating](#updating)
* [Uninstalling](#uninstalling)
* [Reporting a problem](#reporting-a-problem)

## What you need

| | |
|---|---|
| Windows | Windows 10 or 11, x64, a GPU with Vulkan |
| Linux | x64, glibc 2.30 or newer (any current distribution, SteamOS), a GPU with Vulkan |
| macOS | macOS 13.3 or newer on Apple Silicon (M1 and later) |
| Android | Android 9 or newer, 64-bit ARM, Vulkan; about 10 GB free while it builds ([Android](#android)) |
| Disk space | about 4 GB for the game's folder, and up to 2 GB more while it builds |
| Internet | the first start downloads the PS Vita firmware from Sony (the compiler comes with the release), unless you kept it ([offline](#without-internet)) |

**Your own copy of the game, at update 1.30**, either version:

| Version | Title ID |
|---|---|
| US | PCSA00152 |
| EU | PCSF00532 |

Any of these forms works:

* a decrypted dump (a folder, a `.zip` or a `.vpk`) with the 1.30 update,
  merged into the game or beside it as NoNpDrm dumps keep it (`app/` and
  `patch/`). For a NoNpDrm dump, give the `.zip` or the folder that holds
  both `app` and `patch`, not `patch/PCSA00152` alone (that is only the
  update), and don't unpack the update into the game's folder: its files
  replace the game's, and the game can't be installed from what is left;
* the PSN `.pkg` of the game with its licence (`work.bin` or a `.rif`, or a
  zRIF), plus the 1.30 update's `.pkg`.

**From your own Vita** (a modded one, with the game installed on its
memory card or SD2Vita): the folders on the Vita carry your PSN account's
own licence, which works only on that Vita, so they can't be used as they
are (the setup says so; older releases stopped with "header signature is
invalid"). Make a NoNpDrm dump:

1. Install the NoNpDrm plugin and start the game once. It writes a
   licence that works anywhere:
   `ux0:nonpdrm/license/app/PCSA00152/6488b73b912a753a492e2714e9b38bc7.rif`
   (`PCSF00532` for EU).
2. Copy `ux0:app/PCSA00152`, `ux0:patch/PCSA00152` (the 1.30 update) and
   `ux0:nonpdrm/license` into one folder on the PC, as `app/PCSA00152`,
   `patch/PCSA00152` and `license/`. Copy them as they are, not with
   VitaShell's "Open decrypted".
3. Give that folder as the **Game**. Instead of copying `license/`, the
   `.rif` can also be given as its **Licence**.

Add-ons from the Vita need their NoNpDrm licences too
(`ux0:nonpdrm/license/addcont/...`, in the same `license/` folder).

The add-ons' content (raiments, hoods, additional pacts) is part of update
1.30; ss-delta unlocks it.

The **Japanese Voice-over Pack** is a separate add-on. If you have it, add
it as an add-on in the importer: the pack for your version
(`UP9000-PCSA00152_00-SSS000CVN0000001` for US,
`EP9000-PCSF00532_00-SSS000CVN0000001` for EU; the other region's pack
installs for the other version's title and isn't used), as a decrypted
dump (a NoNpDrm folder or `.zip`, with its licence as
`sce_sys/package/work.bin` or in `license/addcont/...`) or as its `.pkg`
with its licence (a `work.bin` or `.rif` beside the `.pkg` is found by
itself). Then choose it in the game: Options → Lang/Sub Settings → Voice
Language → Japanese.

[MODS](MODS.md) is a short step-by-step guide to adding mods.

**Mods made for rePatch**, such as the
[Undub patch](https://archive.org/details/soul_sacrifice_delta_undub_patch)
(Japanese voices from the very start, also without the pack), are added
the same way, as an add-on. Unpack the `.7z` and give its folder (the one
that holds `rePatch`), or a `.zip` of it. ss-delta keeps the mod beside the
game, in `fs/ux0/rePatch/`, so the game's own files stay as they are. A
mod made for one region (the undub's `PCSA00152` folder) also works with
the other region's game, with no renaming. **Mods (rePatch)** on the
settings menu's Game page (`[game] repatch` in `ss-delta.ini`) turns them
off. To remove a mod, delete its folder in `fs/ux0/rePatch/`.

**Packaged mods** are `.zip` files with an `ss-delta-mod.json` inside,
such as the original game's raiments below. Add the `.zip` as it is,
without unpacking it, the same way. Instead of replacing a whole archive,
ss-delta merges a packaged mod into the archive the game reads, so it
works together with rePatch mods like the Undub, installed before or
after it. `ss-delta --remove-mod <id>` takes one out again (the log of the
install names its id); deleting `fs/ux0/rePatch/` removes all mods. On
Android there is no remove yet: Mods (rePatch) turns all mods off.

**The original game's raiments.** The first *Soul Sacrifice* had two
collaboration raiments that Delta never got: ARKS Armor (*Phantasy Star
Online 2*) and Dragonslayer (*Ragnarok Odyssey ACE*). If you have the
original game with update 1.30 (any region; a NoNpDrm dump with its
licences, or an installed copy), you can make a mod that adds them (or download it from
[ModDB](https://www.moddb.com/mods/the-original-raiments-arks-armor-dragonslayer)
and add it as a packaged mod, [MODS](MODS.md)). You
need Python 3 and two scripts from this repository's
[`tools`](https://github.com/vita-recomps/ss-delta/tree/main/tools)
folder, `og-raiments.py` and `lspk.py`, side by side:

```
python og-raiments.py --original "<the original game>" --vita-fs "<ss-delta>/fs" --exe "<ss-delta>/ss-delta.exe"
```

It reads the raiments' models from your copy of the original, makes the
mod, a packaged mod of about 1.5 MB, and installs it. With
`--out <folder>` it writes `ss-delta-og-raiments.zip` there instead, to
add later as above (on Android too). Nothing from either game is in
ss-delta; the mod is made on your computer. The two raiments then appear
in Portraiture → Appearance → Raiments, marked new, with Add-ons (DLC) on.
Wear one as both top and bottom (△ "Match with Above" in the bottom
list); with another bottom, that bottom covers its legs. The
[gallery](GALLERY.md#from-the-original-game-mod) shows both.

* It works with the Undub installed before or after it.
* `ss-delta --remove-mod og-raiments` (or `og-raiments.py --remove`)
  takes it out again. Put on another raiment first: a save that wears one
  of the two shows no body without the mod until you choose another
  raiment.
* A mod made by the first version of `og-raiments.py` (a whole
  `archive_patch3` in `fs/ux0/rePatch/`): remove it with this version's
  `--remove` before adding the new one.

**The original game's Spirits' offerings.** The first *Soul Sacrifice*
had 20 pre-order offerings (Spirits' Flamepike, Spirits' Icebrand ...
Spirits' Gravelshield). Delta still has them, switched off, and ss-delta
switches them on (`[game] spirits_offerings`, on by default, with Add-ons
(DLC) on): each is given once in every save, at the end of Select
Offerings, marked new. They look and play like Delta's own offerings of
the same kind (Imp Pitchfork, Swordsman Icebrand, Firegiant's Arm ...),
with their own numbers. Nothing of the original game is needed.
[ORIGINAL-CONTENT](ORIGINAL-CONTENT.md) compares each with the offering
it copies.

* ss-delta makes a copy of the game's patch archive with them in
  `fs/ux0/rePatch/` at the first start (it keeps the Undub's changes, and
  the Undub installed later keeps them). Mods (rePatch) must be on.
* Turned off, the copy is taken out at the next start. The game then
  doesn't show them, and drops them from the save the next time it saves;
  your other offerings stay as they are.

Once the game is built, an add-on or a mod can be added on its own,
without building the game again (it takes seconds):

* PC: start the game with `--install` and add only the add-on in the
  importer (leave the game's rows empty), or run
  `ss-delta.exe --dump "<the pack>"`;
* Android: long-press the app's icon → **Add an add-on**, and pick it (a
  mod as a `.zip`);
* RecompLauncher: the game's setup has an Add-ons step for it.

Download the archive for your system from the
[latest release](https://github.com/vita-recomps/ss-delta/releases/latest)
(on Android, the `.apk`: see [Android](#android)).
Each archive unpacks to a folder `ss-delta`: that folder **is** the game. Keep it
wherever you like (not inside a folder that needs administrator rights, such
as `C:\Program Files`).

## Windows

1. Download `ss-delta-<version>-windows.zip` and unzip it.
2. Start `ss-delta.exe`. Windows may warn that it doesn't know the program
   (it isn't signed with a publisher's certificate): click "More info", then
   "Run anyway".
3. The importer opens: see [the first start](#the-first-start-building-the-game).

The importer can put a shortcut on the desktop.

**Laptops with two GPUs** (an AMD Radeon built in and an NVIDIA card):
releases up to v0.3.0 can stop near the end of the build with "LoadLibrary
failed with error 87". Open Windows Settings → System → Display →
Graphics, add `ss-delta.exe`, set it to High performance, and build again.
Later releases ask for the NVIDIA GPU themselves.

## Linux and the Steam Deck

1. Download `ss-delta-<version>-linux.tar.gz` and unpack it (on a Steam
   Deck, in desktop mode: Dolphin can unpack it with a right-click).
2. Start `ss-delta.x86_64`: double-click it, or `./ss-delta.x86_64` in a
   terminal.
3. The importer opens: see [the first start](#the-first-start-building-the-game).
   Tick **Add the game to Steam** (Steam must be running) to play it from
   the Steam Deck's Game Mode, and the applications-menu box for a menu
   entry.

It is a Linux program, not a Windows one: no Proton or other compatibility
tool is needed. If the game didn't reach Steam, run
`./ss-delta.x86_64 --add-to-steam` with Steam running, or add
`ss-delta.desktop` from the folder with Steam's "Add a Non-Steam Game". On
the Deck the controls are a gamepad to the game, and the touchscreen is the
Vita's front touchscreen.

## macOS (Apple Silicon)

1. Download `ss-delta-<version>-macos.tar.gz` and open it (Archive Utility
   unpacks it).
2. Double-click **Soul Sacrifice Delta.app** in the folder. macOS refuses it
   the first time, as it does anything downloaded that isn't signed by a
   registered Apple developer: click Done, open System Settings > Privacy &
   Security, scroll down to "Soul Sacrifice Delta was blocked" and click
   **Open Anyway** (once).
3. The importer opens: see [the first start](#the-first-start-building-the-game).
   It can also put the game in Applications (Launchpad and Spotlight list it).

When you join or host Ad Hoc Play, macOS asks whether the game may "find and
connect to devices on your local network": allow it. In fullscreen the game
runs in macOS's Game Mode.

## Android

The game builds itself on the device from your dump: no PC needed. Made
for Snapdragon handhelds (tested on an AYN Thor: Snapdragon 8 Gen 2); the
device needs a 64-bit ARM chip, Vulkan, Android 9 or newer, about 10 GB of
free space (5 GB of it only while building) and preferably 12 GB of memory
or more.

1. Download `ss-delta-<version>-android.apk` from the release onto the
   device and install it (allow installing from your browser or file
   manager when Android asks).
2. Copy your dump to the device (for example into `Download`): the NoNpDrm
   `.zip` or `.vpk` (zip a dumped folder first), or the game's `.pkg` with
   its licence file (`work.bin` or `.rif`) and, if the dump lacks it, the
   1.30 update's `.pkg`.
3. Start **ss-delta**. Its setup screen asks for the files: **Add the
   game's files** (the dump; then the update's `.pkg` if needed) and, for
   a `.pkg`, **Add a licence**. If you have the PS Vita firmware 3.74's
   files (`PSVUPDAT.PUP`, `PSP2UPDAT.PUP`, whatever their names), **Add
   firmware files** takes them, and nothing is downloaded for them. Then
   **Build**.
4. The app downloads the PS Vita firmware from Sony (unless you added it), installs it and the
   game, runs the game for a moment to find its code, and builds the native
   code: about 15 minutes on a Snapdragon 8 Gen 2. Keep the device
   charging; you may leave the app meanwhile (a notification says when it
   is done).
5. **Play**. On a Snapdragon device the game offers Turnip, the
   open-source GPU driver that draws this game's fog correctly, the first
   time: Download.

After an app update the setup screen comes back and builds the native code
again (your dump isn't needed). The game's files live in
`Android/data/io.github.vitarecomps.ssdelta/files/` on the device
(`ss-delta.ini` there holds the settings, `setup.log` the setup's log);
uninstalling the app deletes them, saves included. Holding Select opens
the settings menu, as on PCs.

**On-screen controls.** Without a gamepad (a phone), the game shows the
Vita's buttons, D-pad and both sticks on the touchscreen, a **LOCK** button
beside L (tap it to lock on to enemies, tap again to let go: no need to hold
L), and a menu button at the top that opens the settings menu. A finger anywhere else touches the
game's own touchscreen, as on a Vita; the Black Rite icon (lower left in
quests: touch and hold) is always left clear. They hide while a gamepad is
used, and come back when it is disconnected. Size, opacity and On/Off are on
the settings menu's **Controls** page; switched off, only the menu button
stays.

### From a PC instead

A PC that has built the game (as above) can copy it to the device too, for
a device too small or slow to build:

1. On the device, turn on **Developer options** (Settings > About device:
   tap the build number seven times), then in Developer options either
   **USB debugging** (and connect the cable), or **Wireless debugging**
   (the same Wi-Fi network as the PC).
2. On the PC, start the game with `--android` (Windows: `ss-delta.exe
   --android`, from a command prompt in the game's folder; Linux:
   `./ss-delta.x86_64 --android`; macOS:
   `"Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --android`). A
   window asks how the device is connected. Over Wi-Fi: on the device,
   Wireless debugging > **Pair device with pairing code**, and type the IP
   address, port and code it shows. Accept Google's licence for adb (the
   tool that copies the game) and click **Copy to the device**.
3. The PC builds the game's code for Android (a few minutes), downloads adb
   from Google, installs the app (`setup/android/ss-delta.apk`, also
   attached to each release) and copies the game's files (several GB:
   minutes over Wi-Fi) and code to the device.

Saves already on the device stay when you copy again. Without the window:
`--android --accept-android-sdk-license` and the device as `--serial <adb
serial>` or `--pair <ip:port> --code <code>`; `--push-only` copies again
what was built before.

## The first start: building the game

The importer's window asks for your dump:

1. **Game**: the game's folder, `.zip`, `.vpk` or `.pkg` (File... or
   Folder...). The importer looks inside a folder or archive: when it
   already holds the 1.30 update and the licence, it says so and doesn't ask
   for them.
2. **Update**: the 1.30 update, if the game's dump doesn't hold it.
3. **Licence** (for a `.pkg`, or a folder or `.zip` without a usable
   licence inside): its `work.bin` or `.rif`, found beside a `.pkg` when
   it's there, or a zRIF typed in.
4. Add-ons are optional (their content is part of 1.30).

Then **Build**. The importer:

* downloads the PS Vita firmware from Sony (about 180 MB; the compiler,
  zig, comes with the release);
* installs the game into the folder, starts it once unseen to read its code,
  translates that code to C++ and compiles it on your computer;
* deletes the downloads and its work files.

This takes a few minutes (about 6 on an M5 MacBook Air, 20 on a Steam
Deck). Then **Play** starts the game. From then on, starting the game goes
straight to it.

Without the window (for scripts and launchers):

```
ss-delta.exe --dump "<your dump>"           (Windows)
./ss-delta.x86_64 --dump "<your dump>"      (Linux)
```

`--build-only` builds and quits instead of playing, and `--progress` adds
`progress <0-1> <text>` lines for a launcher's progress bar.

### Without internet

The downloads can be kept, so a later build needs no network (a new PC, a
reinstall, or a time when a download link no longer works). Once, with
internet:

```
ss-delta.exe --download-only "<folder>"           (Windows)
./ss-delta.x86_64 --download-only "<folder>"      (Linux)
```

This saves the firmware in that folder (about 180 MB), with a list
(`offline.json`), and builds nothing. `--for windows,linux,macos,android`
(or `all`) saves what those platforms need too (their compiler, adb for
Android). Then either put the
folder in the game's folder as `offline`, choose it in the importer's
"Downloaded files" row, or pass `--offline "<folder>"` with `--dump`.
Files are recognised by their size and SHA-256, whatever their names, so a
folder holding the firmware PUPs you already have (`PSVUPDAT.PUP`,
`PSP2UPDAT.PUP`) works too; anything not found there is downloaded as
usual. The firmware is under Sony's licence: keep the folder for
yourself.

**RecompLauncher:** each release carries a `recomplauncher.json`, so
[RecompLauncher](https://recomplauncher.com/game/ss-delta) can install the game, build
it from the dump you pick (the same importer, without its window), show
the main settings of `ss-delta.ini` on the game's page, and back up the
saves. After an update it builds the game again from the same dump; when
it runs the setup again with nothing new (the same release and dump), the
setup says "Already built" at once. Its
setup also takes the Japanese Voice-over Pack and a rePatch mod such as
the Undub patch (both optional, on its Add-ons step); adding one later
installs only that.

## Playing

* **Settings:** F1, or Select (Back/View) held for a second on a gamepad,
  opens the settings menu over the paused game. Everything is also in
  `ss-delta.ini`, which can be edited by hand (paths are there only; see
  [Controls](#controls) for bindings).
* **Exit:** the settings menu's last page, Exit: Cross (X on the keyboard)
  twice on Exit the game. Closing the window does the same. Progress since
  the game last saved is lost.
* **Fullscreen:** F11 or Alt+Enter (Option+Return on a Mac). On a Mac
  keyboard the F keys need fn held, unless they are set as standard function
  keys.
* **Touch:** the mouse (or trackpad) is the touchscreen: left button front,
  right button rear. The Black Rite icon (touch and hold) is also on F and on
  the gamepad's left trigger.
* **Without touch (PS TV controls):** PS TV controls on the settings menu's
  Game page (`pstv_mode = true` under `[game]`, read at start) run the game
  as a PlayStation TV, which has no touchscreen. The one touch the story
  needs, pulling Librom out of the bones at the start of a new game, then
  takes L2 or R2: the gamepad's triggers, or U and O on the keyboard
  (`l2`, `r2` under `[keyboard]`). The game's text prompts show ✕ instead
  of touch. The Vita's "near" feature is unavailable then (it no longer
  works anyway), and so is AR mode, which needs the camera.
* **Frame rate:** 60 fps by default; `frame_rate = 30` under `[display]`
  gives the Vita's rate.
* **FPS counter:** FPS counter on the settings menu's Display page
  (`fps_counter` under `[display]`): off, `fps`, `frametime` (and the
  milliseconds a frame), `stats` (and the lowest, average and highest of
  the last minute) or `graph`, in the top left corner.
* **Intro logos:** Skip intro logos on the settings menu's Game page
  (`skip_intro = true` under `[game]`) skips the health warning and the
  company logos at start: the game opens on its title screen.
* **Cheats:** the settings menu's Cheats page (`[cheats]`), all off by
  default and switched while the game runs: Infinite health, Unlimited
  offerings (casts never run out), Lasting offerings (arms and buffs stay
  for the whole quest) and One-hit kills in quests (bosses take five hits),
  Invincible (enemies' attacks neither hurt you nor knock you down), Max
  Lacrima and Max levels (Life and Magic 99, once the story has opened
  your Right Arm's levels). Lacrima and levels are kept when the game
  saves, so export a save first (below) to be able to go back. In Ad Hoc
  Play they change only your own sorcerer.
* **Language:** Language on the settings menu's Game page. The US game has
  English, French, Spanish and Portuguese (Brazil), the EU game English,
  French, Spanish, German and Italian.
* **Screenshots:** F12, into `ss-delta/screenshots`.
* **Both versions installed:** the US one starts; `--title-id PCSF00532`
  starts the EU one.

### Controls

The default bindings:

| Vita | Keyboard | Gamepad (Xbox names) |
|---|---|---|
| Left stick | W, A, S, D | left stick |
| Right stick (camera) | I, J, K, L | right stick |
| ✕ | X | A |
| ○ | C | B |
| □ | Z | X |
| △ | V | Y |
| L, R | Q, E | LB, RB |
| D-pad | arrow keys | D-pad |
| Start | Enter | Menu |
| Select | Right Shift | View |
| L2, R2 (only with PS TV controls) | U, O | LT, RT |
| Black Rite (touch and hold its icon) | F | LT |

Keys that do the same thing whatever the bindings are:

| Key | What it does |
|---|---|
| F1 (or View held for a second) | settings menu |
| F11, Alt+Enter | fullscreen |
| F12 | screenshot |
| F5 | a mark in the log, for a bug report (a binding on F5 still works) |
| Tab, middle click | capture the cursor for the mouse camera, and release it |
| Esc | release the cursor |

**Mouse** (PC only): when the cursor isn't captured, the mouse is the
touchscreen (left button front, right button rear). Once captured (Tab or a
middle click), it hides and moving the mouse turns the camera. The settings
menu's Mouse page (`[mouse]`) holds Mouse camera (off: the mouse is only the
touchscreen), Capture key, Sensitivity, Invert vertical and Hide idle
cursor. Capture key accepts mouse buttons too. If a capture shortcut
also has a game binding, the game binding wins and middle-click still
captures the cursor.

**Changing the bindings:** the settings menu's **Controls** page (F1, or
View held for a second) lists each Vita button with its key, a second key,
its gamepad button and a second gamepad button, and the Black Rite below
them. Up/Down picks a control and Left/Right picks a column. Press Cross
or Enter in the menu, then the new key, mouse button, gamepad button or
trigger (Esc cancels). Square
clears the selected one, Triangle puts that control back to its defaults,
and **Reset all controls** at the bottom (Cross twice) all of them. A key or
button another control already has changes places with it, so nothing is
left with two jobs. The changes work at once and are saved in
`ss-delta.ini`. The gamepad's sticks can't be changed there.

**A second gamepad button:** each Vita button takes two gamepad inputs, and
LT and RT are among them. For example, RT as a second D-pad up puts the
D-pad's up in a quest on a trigger while the D-pad still moves through the
menus: on the Controls page, D-pad up, the **Second button** column, Cross,
then RT (or `up = dpup, righttrigger` in `[gamepad]`). The triggers stay a
PS TV's L2 and R2 as well, which the game reads only with PS TV controls
(the Game page).

**Mouse buttons as bindings:** the side buttons (`MouseX1`, `MouseX2`) work
like keys. The left and right buttons (`MouseLeft`, `MouseRight`) press
their Vita button only while the mouse camera has the cursor; otherwise
they stay the touchscreen. The middle button always captures the cursor.

**Keyboard button prompts:** Button prompts on the settings menu's Game page
(`[game] button_labels`) also has **Keyboard**: each □ ○ ✕ △, L, R, START and
SELECT in the game's prompts, tutorial pictures and text shows the key bound
to it (the first of two) in a keycap: X, C, Z, V, Q, E, and short forms for
long names (ENT, SHF, SPC, TAB, CTL, ALT, BS, ESC, arrows, F1-F12, M4/M5 for
the mouse's side buttons). **As the device used** (`auto`) switches between
keyboard prompts and your gamepad's (Xbox letters, or PlayStation symbols
for a PlayStation pad) by what you pressed last; before any input it takes
the connected gamepad's, or the keyboard's without one. The prompts follow
a binding changed on the Controls page at once.

**Nintendo and handheld button prompts:** **Nintendo (Switch Pro)**
(`nintendo`) letters the face buttons as a Switch Pro Controller does (A on
the right, B at the bottom, X at the top, Y on the left) and shows L, R, +
and − for the shoulders, START and SELECT. **As the device used** picks it
for a Nintendo pad. On Android there is also **Android handheld**
(`handheld`), for the built-in controls of the Retroid Pocket, AYN and
other handhelds: the face buttons lettered the Nintendo way, L1 and R1 for
the shoulders, and Xbox's Menu and View. Choose it yourself: these handhelds tell the game
they are Xbox pads, so **As the device used** shows Xbox letters there.

The bindings can also be changed by hand: close the game and edit
`ss-delta.ini` in a text editor.

* `[keyboard]`: `<vita button> = <key>`, or two keys separated by a comma
  (`cross = X, Space`). The Vita button names are `cross`, `circle`, `square`,
  `triangle`, `l`, `r`, `start`, `select`, `up`, `down`, `left`, `right`,
  `analog_up`, `analog_down`, `analog_left`, `analog_right` (the left stick),
  `right_analog_up` ... `right_analog_right` (the right stick), and `l2`, `r2`.
  The key names are listed in the comment above the section: A-Z, 0-9, the
  arrows, Return, Space, Tab, Left Shift, Right Ctrl, F1-F12, Keypad 0-9, or
  W3C codes such as Comma, Period, Semicolon, BracketLeft, and the mouse
  buttons above. Nothing after the `=` unbinds the button.
* `[gamepad]`: one or two gamepad buttons per Vita button, separated by a
  comma (`up = dpup, righttrigger`): `south`, `east`, `west`, `north` (the
  face buttons: A, B, X, Y on an Xbox pad), `leftshoulder`, `rightshoulder`,
  `start`, `back`, `guide`, `dpup`, `dpdown`, `dpleft`, `dpright`,
  `leftstick`, `rightstick`, and the triggers `lefttrigger`, `righttrigger`;
  nothing after the `=` unbinds it. The sticks can't be swapped.
* `[touch]`: keys and buttons that hold a finger on the screen for as long
  as they are held. `black_rite_key` and `black_rite_gamepad` move the Black
  Rite (up to two of each, as above). More can be added: `<name> = x, y` (a
  point on the 960×544 screen) with `<name>_key` and `<name>_gamepad`.
* `[mouse] capture_key`: the key(s) that capture the cursor, as in
  `[keyboard]`.

## Saves

Saves are in the game's folder, in the Vita file system:
`fs/ux0/user/00/savedata/PCSA00152` (`PCSF00532` for the EU game). The game
has three save slots.

To use a save from a Vita (decrypted, for example with VitaShell or Apollo),
or from another computer:

```
ss-delta.exe --import-save <folder or .zip> [--slot 2]
ss-delta.exe --export-save <folder> [--slot 2]
```

`--slot` picks the game's slot (default 1). An import keeps the previous
save in `ss-delta/save-backups`.

## Ad Hoc Play

Librom → Network → Ad Hoc Play works between copies of the game, as on a
Vita: one creates a room, the others use Search for Room.

* **Across computers and devices** (Windows, Linux, macOS and Android mixed,
  any of them as host): `network = lan` under `[multiplayer]` in
  `ss-delta.ini`, the default on Linux, macOS and Android. On Windows set
  it, and allow `ss-delta.exe` through the firewall when Windows asks (on
  private and public networks, or the host never hears the others). The
  settings menu's Multiplayer page, **Network adapter**, must name the
  adapter of your home network (its 192.168.x.x address, the Ethernet or
  Wi-Fi), not a virtual one (vEthernet, Hyper-V, VirtualBox, VPN), which
  Windows often lists first; since 0.5.2, `auto` (the default) picks it by
  itself. The log names the adapter in use and lists the others
  (`Ad Hoc Play: network adapter ...`); `[debug] net_trace` logs every
  packet, for a connection that doesn't work.
* **Over the internet** (0.5.2 and newer): through a VPN (Tailscale,
  ZeroTier, Radmin VPN or another), step by step in
  [Playing together over the internet](ONLINE-PLAY.md). In short: as across
  computers, the host's **Network adapter** set to the VPN's, and the host's
  VPN address in **Peers (host address)** on the Multiplayer page of every
  other player's copy (`peers` under `[multiplayer]`; several addresses
  separated by commas). The same works between subnets with a router
  between them, where broadcasts don't arrive. **Network adapter** `auto`
  (the default) takes the adapter that reaches the first peer, or without
  peers the one of the internet connection.
* **Several copies on one PC** (Windows and Linux): `network = local`, the
  default on Windows; start `run-player2.bat` (`run-player2.sh`) or
  `--player 2` up to `--player 4`. Each player has its own saves, copied from
  player 1's on its first start, and its own log and settings
  (`ss-delta-player<N>.ini` overrides `ss-delta.ini` for that player).
  `gamepad = 1`–`4` gives each copy a gamepad of its own.

## Files and folders

Everything the game uses is in its folder; nothing is written anywhere else
(apart from the shortcut, menu entry, Steam entry or Applications copy, if you
let the importer make one).

| In the game's folder | What |
|---|---|
| `ss-delta.exe`, `ss-delta.x86_64`, `Soul Sacrifice Delta.app` | the game: the one thing to start |
| `ss-delta.ini` | settings |
| `fs/` | the Vita file system: the installed game, the firmware, your saves |
| `ssd_aot_*.dll` / `.so` / `.dylib` | the game's code, compiled for your computer |
| `ss-delta/` | logs (`vita3k.log`, the four runs before it as `vita3k.1.log`–`vita3k.4.log`, the importer's `setup.log`), save backups, screenshots, per-player data |
| `cache/` | the shader cache |
| `patch/` | Vita3K-style patches, if you add any |
| `setup/` | the importer (its Python and the recompiler kit), kept for `--install` |
| `data/`, `shaders-builtin/`, `icons/` | files from Vita3K the game reads |

Everything in `fs/`, `ssd_aot_*` and `cache/` is derived from your copy of the
game: don't share it.

## Command-line options

`--help` prints these and every setting of `ss-delta.ini`.

| Option | What |
|---|---|
| `--game <folder>` | play the game in that folder (default: the program's own) |
| `--install` | open the importer again (another dump, an update), then play |
| `--dump <file> [--license <work.bin\|.rif> \| --zrif <zRIF>]` | build from this dump without the window (repeat for the update and add-ons; also `--dump=<file>`), then play. A `.pkg` takes the licence beside it. With the game built, add-ons alone are installed without building again; the same dump it was built from (by this release, unchanged): nothing to do |
| `--rebuild` | with `--dump`: build again even from the same dump |
| `--build-only` | build if needed (or with `--install` / `--dump`), then quit |
| `--shortcut`, `--steam` | with `--dump`: a desktop shortcut, menu entry or Applications copy; add the game to Steam (Linux) |
| `--cache <folder>`, `--jobs <n>` | with `--dump`: keep the downloads there for next time; compile with n jobs |
| `--offline <folder\|file>` | take the downloads from there first (any name, matched by size and SHA-256; repeatable). The game folder's `offline` is used unasked ([without internet](#without-internet)) |
| `--download-only <folder> [--for <platforms>]` | save everything the importer downloads into that folder, then quit |
| `--progress` | with `--dump`: also `progress <0-1> <text>` lines, for a launcher (RecompLauncher) |
| `--add-to-steam` | Linux, Steam Deck: add the game to Steam (Steam running), then quit |
| `--android` | put the game, built here, on an Android device (a window asks how it's connected), then quit; with `--dump`, build for both first |
| `--serial <s>`, `--pair <ip:port> --code <code>`, `--connect <ip:port>` | with `--android`: the device, without the window |
| `--accept-android-sdk-license`, `--push-only`, `--apk <file>` | with `--android`: accept Google's licence for adb; copy again without building; another APK |
| `--set <section.key=value>` | a setting of `ss-delta.ini` for this run only |
| `--fullscreen`, `--windowed` | the same as `--set display.fullscreen=true` / `false` |
| `--player <1-4>` | Ad Hoc Play: another player's copy |
| `--title-id <id>` | with both versions installed: that one |
| `--import-save <folder\|zip>`, `--export-save <folder>`, `--slot <1-3>` | saves, then quit |
| `--remove-mod <id>` | take a packaged mod out again, then quit |
| `--write-ini <file>` | write the default settings file there, then quit |

On macOS the program inside the app takes them:
`"Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --help`.

## Updating

To move to a newer release, unpack it over your game's folder (replace the
files), then start the game with `--install` and build again from the same
dump: saves and settings are kept. Coming from a release before 0.3.0 (a
separate setup and playable folder): build the new release, then copy the
old folder's `fs/ux0/user/00/savedata/PCSA00152` (or `PCSF00532`) and
`ss-delta.ini` into the new one.

## Uninstalling

Delete the game's folder. If you let the importer make them, also delete the
desktop shortcut (Windows), the menu entry and the Steam entry (Linux), or the
copy in Applications (macOS).

## Reporting a problem

Open an [issue](https://github.com/vita-recomps/ss-delta/issues) with your
system, the release, what you did and what happened. Attach the log,
`ss-delta/vita3k.log` in the game's folder (if the build from your dump
failed, `ss-delta/setup.log`). `vita3k.log` is the last run's: the four
before it are kept as `vita3k.1.log` (the run before) to `vita3k.4.log`,
so after a crash attach the one whose run crashed, even if you have
started the game since. Never attach game files, saves you don't want public, or
anything from `fs/`.

Press F5 the moment something goes wrong: the log gets a line `User mark N
at frame F`, and the issue can say "after mark 2". Stutters show up on
their own as `Hitch` lines (frames slower than 100 ms, with the shaders
built meanwhile; `[debug] hitch_log_ms` sets the limit).
