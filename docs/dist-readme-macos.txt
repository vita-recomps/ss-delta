ss-delta: Soul Sacrifice Delta (US PCSA00152 or EU PCSF00532, 1.30) on macOS
(13.3 or newer, Apple Silicon).

"Soul Sacrifice Delta.app" in this folder is the game: double-click it, or
keep it in the Dock. macOS refuses it the first time, as it does anything
downloaded that isn't signed by a registered Apple developer: click Done, open
System Settings > Privacy & Security, scroll down to "Soul Sacrifice Delta was
blocked" and click Open Anyway (once).

The first time, it builds the game from your own dump: a window asks for it (a
folder, .zip or .vpk of the game with its 1.30 update, or the PSN .pkg files
with their licence), downloads the PS Vita firmware from Sony (about 180 MB;
the compiler is in setup/toolchain), installs the game and compiles its code
on this Mac, which takes a few minutes. Play then starts the game, and from then on
the app goes straight to it.

Everything stays in this folder: the game (fs), its code compiled for this Mac
(ssd_aot_*.dylib), settings (ss-delta.ini), saves, logs and the shader cache.
The downloads are deleted once the game is built; delete the folder and the
game is gone (apart from the copy in Applications, if you let the importer
make one). Keep the app and the files next to it together; the folder itself
can move. Graphics go through MoltenVK (Vulkan over Metal, inside the app).

Command line (in Terminal: "Soul Sacrifice Delta.app/Contents/MacOS/ss-delta"
--help lists it all): --install opens the importer again (another dump, an
update); --dump <file> builds without the window; --fullscreen or --windowed;
--set section.key=value sets any setting of ss-delta.ini for one run; --game
<folder> plays the game in another folder.

Android (64-bit ARM with Vulkan; made for Snapdragon handhelds such as the AYN
Thor): once the game is built here, "Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --android
puts it on the device over USB or Wi-Fi debugging: a window asks how the device
is connected, builds the game's code for Android, downloads adb from Google and
copies the app (setup/android/ss-delta.apk), the game's files and its code.
Saves already on the device stay. The APK also builds the game on the device
itself from your dump, with no PC: install it there and start it (Android in
https://github.com/vita-recomps/ss-delta/blob/main/docs/INSTALLING.md).

The US and EU games are the same build: either one runs. When both are
installed, the US one does; --title-id PCSF00532 starts the EU one.

Settings: press F1, or hold Select (the View button) on a gamepad for a
second, to open the settings menu over the paused game (Up/Down choose,
Left/Right or Cross change, L1/R1 or Q/E switch pages, Circle, Esc or F1
close). Its last page, Exit, quits the game: press Cross (X) twice on Exit
the game. Window size, fullscreen, vsync, filter, FPS counter, volume and frame rate change
at once; the rest are marked * and take effect the next time the game starts.
The menu writes ss-delta.ini, which can also be edited by hand (paths are there only). On a Mac keyboard the F keys need fn held, unless
they are set as standard function keys (System Settings, Keyboard).

Settings are in ss-delta.ini: resolution, window, fullscreen (F11 or
Option+Return while playing), filter, frame rate (frame_rate under
[display]: 60, 30 as on the Vita, or 90 / 120 on a high-refresh screen), volume,
keyboard and gamepad bindings. The mouse or trackpad is the touchscreen:
click for the front, right-click (two fingers) for the rear. The Black Rite
icon (touch and hold) is also on F and the gamepad's left trigger ([touch] in
ss-delta.ini). F12 saves a screenshot to ss-delta/screenshots. F5 writes a
mark into ss-delta/vita3k.log: press it when something goes wrong, and
mention the mark in a bug report.

Mouse camera: press Tab or click the middle mouse button to capture the
cursor; moving the mouse then turns the camera. Tab, the middle button or
Esc releases it, and the mouse or trackpad is the touchscreen again.
Sensitivity and Invert vertical are on the menu's Mouse page ([mouse] in
ss-delta.ini). The cursor hides after 3 seconds without mouse motion, or
when you use a key or the gamepad, and comes back when the mouse moves
(Hide idle cursor on the Mouse page; [mouse] hide_cursor).

In fullscreen, started from its app, the game runs in macOS's Game Mode (the
controller icon in the menu bar): background work waits, and Bluetooth
controllers answer faster.

Intro logos: Skip intro logos on the menu's Game page ([game] skip_intro in
ss-delta.ini) skips the health warning and the company logos at start; the
game opens on its title screen.

Cheats: the menu's Cheats page ([cheats] in ss-delta.ini), all off by
default and switched while the game runs: Infinite health, Unlimited
offerings (casts never run out), Lasting offerings (arms and buffs stay for
the whole quest) and One-hit kills in quests (bosses take five hits),
Invincible (enemies' attacks neither hurt you nor knock you down), Max Lacrima
and Max levels (Life and Magic 99, once the story has opened your Right Arm's
levels). Lacrima and levels are kept when the game saves; export a save first
to go back. In Ad Hoc Play they change only your own sorcerer.

Language: the game has no language option of its own; it uses the console's
language, which the game sets from Language on the menu's Game page
([game] language in ss-delta.ini; takes effect at the next start). The US
game has English, French, Spanish and Portuguese (Brazil), the EU game
English, French, Spanish, German and Italian; a language the installed game
lacks gives English.

Button prompts: Xbox, Nintendo or keyboard labels in place of the PlayStation
symbols, from Button prompts on the menu's Game page ([game] button_labels =
xbox, nintendo, keyboard, or auto to follow the device you used last; switches
at once). Each symbol shows the gamepad button bound to it in [gamepad] (A, B,
X, Y, LB, RB, and Xbox's Menu and View for START and SELECT; for nintendo a
Switch Pro Controller's: A on the right, B at the bottom, L, R, + and -), or
the key bound to it in
[keyboard] in a keycap (X, C, Z, V, Q, E, ENT, SHF ...), also in the tutorial
pictures and the text.

Controls: the menu's Controls page lists each Vita button with its key, a
second key, its gamepad button and a second gamepad button, and the Black
Rite. Pick one, press Cross, then the new key, mouse button or gamepad button
(Esc cancels); Square clears it, Triangle restores its default, Reset all
controls (Cross twice) restores them all. A key or button already in use
changes places with the old one. The gamepad's triggers (LT, RT) can be bound
to any Vita button too, e.g. RT as a second D-pad up ([gamepad] up = dpup,
righttrigger); they still work as L2 and R2 as well, which the game reads only
with PS TV controls on. The mouse's
side buttons can be bound; its left and right buttons too, which then act only
while the mouse camera has the cursor.

The add-ons (raiments, hoods, additional pacts) are unlocked: their content
is in the game since update 1.30, and the game records them in your
save once ([game] dlc in ss-delta.ini; a copy of the previous file goes to
ss-delta/save-backups). The ones PSN gave as gifts at Cassus (Soulbinder and
other raiments, hoods, the Fox Sigil) appear in the loaded save, marked NEW,
and so do the raiments only Japan had (Sylvan, Benkei; [game] japan_raiments).
So do the original Soul Sacrifice's 20 pre-order offerings (Spirits' Flamepike
and the rest; [game] spirits_offerings), which Delta keeps switched off: ss-delta
switches them on in a copy of the game's patch archive in fs/ux0/rePatch.
The original Soul Sacrifice's ARKS Armor and Dragonslayer can be added as a mod
made from your own copy of that game (INSTALLING on the project's page).
Sortiara, who fights beside you in the early story, can join your allies:
[game] sortiara_ally = true (off by default). The game keeps her once it saves.

The Japanese Voice-over Pack is a separate add-on (the one for your
version, US or EU). If you have it (a decrypted folder or .zip, or its .pkg
with its work.bin or .rif beside it), add it without building again:
  "Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --dump "<the pack>"
or with --install, the add-on alone in the importer. In the game: Options,
Lang/Sub Settings, Voice Language, Japanese.

Mods made for rePatch, such as the Undub patch (Japanese voices from the
start), are added the same way: unpack its .7z and give the folder that
holds rePatch (or a .zip of it), for the US or the EU game alike. The mod
is kept in fs/ux0/rePatch, the game's files stay as they are; Mods
(rePatch) on the menu's Game page ([game] repatch) turns it off. A
packaged mod (a .zip with an ss-delta-mod.json in it, such as the original
game's raiments) is added the same way, as it is, without unpacking it:
it is merged with the Undub instead of replacing it, in either order.
"Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --remove-mod <id> takes
one out again.

Saves are in the Vita file system (ux0/user/00/savedata/PCSA00152, or
PCSF00532 for the EU game). To use a save from a Vita (decrypted, e.g. with
VitaShell or Apollo), or from the Windows or Linux port, run in Terminal, in
this folder:
  "Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --import-save <folder or .zip> [--slot 2]
The game has three save slots (default 1); the save folder as it was is kept
in ss-delta/save-backups. To copy a slot out:
  "Soul Sacrifice Delta.app/Contents/MacOS/ss-delta" --export-save <folder> [--slot 2]

Ad Hoc Play (Librom, Network, Ad Hoc Play): ss-delta.ini has network = lan
([multiplayer]): computers and devices in one network, Windows, Linux, macOS
or Android, each running the game. macOS asks whether the game may "find and
connect to devices on your local network": allow it, or no room can be
joined (System Settings, Privacy & Security, Local Network changes it
later). Over the internet through a VPN such as Tailscale or ZeroTier, the
other players enter the host's VPN address in Peers on the settings menu's
Multiplayer page (docs/ONLINE-PLAY.md in the source repository). Several copies on one Mac (network = local, --player 2) don't work yet: macOS only has the address 127.0.0.1 for them.

ss-delta is built from Vita3K (https://github.com/Vita3K/Vita3K) and is under
the GNU GPL version 2. The ssd_aot_*.dylib files and the game files are
derived from your own copy of the game: do not share them.
