ss-delta: Soul Sacrifice Delta (PCSA00152, 1.30) on PC.

ss-delta.exe runs the game installed in a Vita file system ([paths] vita_fs in
ss-delta.ini; default: the fs folder next to this file), with the game's code
recompiled to native code (ssd_aot_*.dll, built from your own dump).

Settings are in ss-delta.ini: resolution, window, fullscreen (F11 or
Alt+Enter while playing), filter, frame rate (frame_rate under [display]:
60, or 30 as on the Vita; loading screens stay at 30), volume, keyboard and
gamepad bindings. The mouse is the touchscreen: left button front, right
button rear. The Black Rite icon (touch and hold) is also on F and the
gamepad's left trigger ([touch] in ss-delta.ini). F12 saves a screenshot to
ss-delta\screenshots.

The add-ons (raiments, hoods, additional pacts) are unlocked: their content
is in the game since update 1.30, and ss-delta.exe records them in your save
once ([game] dlc in ss-delta.ini; a copy of the previous file goes to
ss-delta\save-backups).

Saves are in the Vita file system (ux0\user\00\savedata\PCSA00152). To use a
save from a Vita (decrypted, e.g. with VitaShell or Apollo), run
  ss-delta.exe --import-save <folder or .zip> [--slot 2]
The game has three save slots (default 1); the save folder as it was is kept
in ss-delta\save-backups. To copy a slot out:
  ss-delta.exe --export-save <folder> [--slot 2]

Ad Hoc Play (Librom, Network, Ad Hoc Play) works between copies of the game:
start ss-delta.exe for player 1 and run-player2.bat (ss-delta.exe --player 2)
for player 2, up to --player 4. One copy creates a room, the others use Search
for Room. Each player has its own saves (ux0\user\0<N-1>, copied from player
1's on its first start), log and config (ss-delta\player<N>);
ss-delta-player<N>.ini next to ss-delta.ini overrides settings for player N.
[multiplayer] in ss-delta.ini: network = local (copies on this PC) or lan
(PCs in one network: each runs ss-delta.exe; allow it through the firewall),
and gamepad = 1-4 to give each copy its own gamepad.

ss-delta is built from Vita3K (https://github.com/Vita3K/Vita3K) and is under
the GNU GPL version 2. The ssd_aot_*.dll files and the game files are derived
from your own copy of the game: do not share them.
