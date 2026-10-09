Soul Sacrifice Delta - Vita3K test package (for the RTX 4090 PC)
=================================================================

Contains the owner's own dump only. Do not share this folder.

The package holds:

* two emulator builds:
  * vita3k\       upstream Vita3K v0.2.1 build 4152 (2026-10-09)
  * vita3k-plus\  Vita3K-Plus v1.2 (a fork with fixes for this game)
* vitafs\         the installed game (US 1.30, decrypted), its licence and
                  firmware 3.74, shared by both builds
* scripts\        PowerShell scripts behind the .bat files

Nothing is installed and nothing is written outside this folder. Each
emulator runs in portable mode: its config, logs, shader cache and
screenshots stay in its own portable\ folder.

Requirements: Windows 10/11 x64 and a current GPU driver. Unzip or copy the
whole folder to any path, for example D:\ss-delta-test. Avoid paths with
unusual characters. It needs about 3.5 GB.

The first time a script runs, it links each build's portable\fs folder to
vitafs\ with a directory junction. A junction is a folder shortcut; creating
it needs no admin rights.

* Once you have run anything, don't copy the folder elsewhere with
  Explorer: Explorer would copy the game data twice. Moving it on the same drive or
  deleting it is fine.
* If you do move it, the scripts repair the links on the next run.


1. What we want to know
-----------------------

On the dev mini PC (Radeon 760M), these were the results:

| Build    | Vulkan                               | OpenGL                                          |
|----------|--------------------------------------|-------------------------------------------------|
| upstream | crashes about 4 s into boot, every time | runs at 30 fps; black blocks in the sky, white arena floor |
| plus     | runs at 30 fps and looks right, except speckled noise on the player's cloak | runs at 30 fps; same black blocks and white floor as upstream, clean cloak |

On the 4090 PC we want to know:

* Does upstream Vulkan boot?
* Does each build render correctly: no black blocks, textured floors, a
  clean cloak?
* What frame rate does each manage?


2. The automatic test: please run this first (about 10 minutes)
---------------------------------------------------------------

Double-click run-matrix.bat.

It boots each build x renderer x map combination (8 runs of about 70 s).
Each run goes straight into a map, using the game's developer
"BootSequence" setting, so no input is needed.

* The maps are ELDER DEFAULT MAP (an open field) and
  [G] HarpyBattle Walhalla (a boss arena). The character just stands still.
* Each run records the FPS from the window title every 0.5 s, takes
  screenshots at 30 s and 60 s, and keeps the log. Crashes are recorded.
* Sound is muted. Game windows will pop up and close; that is expected.
  You can use the PC meanwhile, but don't close the windows yourself.

When it finishes, it prints a summary table and the path of a zip:

    results\matrix-<date>-<time>.zip

Send that zip back. It is small: screenshots, logs and CSVs.

Run only part of the matrix:

    run-matrix.bat -Emu upstream -Renderer Vulkan
    run-matrix.bat -Boot Harpy -Seconds 90


3. Playing interactively (optional)
-----------------------------------

    play.bat                                    Vita3K-Plus, Vulkan, title screen
    play.bat -Emu upstream                      upstream build instead
    play.bat -Renderer OpenGL
    play.bat -Boot DebugMenu                    developer menu
    play.bat -Boot Elder                        straight into the open field
    play.bat -Boot Harpy                        straight into the boss arena

Keyboard (Vita3K defaults):

    Left stick          W A S D
    Right stick         I J K L
    D-pad               arrow keys
    Cross               X
    Circle              C
    Square              Z
    Triangle            V
    L / R               Q / E
    Start / Select      Enter / Right Shift
    Screenshot          F12
    Fullscreen          F11

* In the developer menu, Circle confirms (the Japanese convention).
* "01 Quest Select" opens a stage select covering all 561 quests.
* Worth checking in a quest: the Mind's Eye view (D-pad down) should show
  monster HP and soul shards.

Close the game window when done. The log and your F12 screenshots are then
copied to results\play-<time>-<build>-<renderer>-<map>\. Please send those
folders too, with a sentence about what you saw.

The scripts always put the game's boot setting back to the normal title
screen when they finish.


4. If something goes wrong
--------------------------

* "running scripts is disabled": the .bat files already bypass the policy
  for this one script. Run them from the .bat, not the .ps1.
* A build crashes immediately on every run: that is a result too. Keep the
  zip.
* To reset an emulator's settings, delete its portable\cache folder (the
  shader cache). Don't delete portable\config.yml.
