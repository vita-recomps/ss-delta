# 06 — Compatibility matrix

What works in each part of Soul Sacrifice Delta (PCSA00152, 1.30) in
`ss-delta.exe`, and how it was checked. Phase 9 of the [plan](03-plan.md)
keeps this current.

* **Status:** ✅ works · ⚠️ works with a known issue · ❌ broken ·
  ❔ not checked yet.
* **Checked by:**
  * *scripted*: driven by `tools/v3kdrive.py` (Stage Select sweeps with
    `tools/map-sweep.ps1`, routes through the menus on a save), judged
    from screenshots, frame-rate samples and the log;
  * *user*: played by the user;
  * *compared*: side by side with Vita3K or a real Vita.

**Phase 9 quest pass (2026-10-11):** 36 quests, the first, middle and last of
each of the 12 types in `quest_param.csv` (`build/quests-p9.txt`), started
from Stage Select with `tools/map-sweep.ps1`: screenshots after loading,
with Mind's Eye, after camera turns and a walk. All still running at the
end, 29.5–29.7 fps mean. h0301 stayed on Stage Select once (script) and
started on a rerun.

**RTX 4090 pass (2026-10-13):** the non-map parts repeated on NVIDIA (driver
617.42), all modules native, `full_3d` + scale 2, as copies `--player 2`/`3`
(user 00 not written): book-page episodes, StaffRoll credits, EndingDelta,
new game with the four original-game import prompts declined, a new save
and the opening movie, the 100% save's hub and journal (contents, Mad
Chronicle chapters), Fight Magusar through Librom's sacrifice, Magusar's
introduction, the final battle and "This is not the end...", and Ad Hoc
Play: Create Room, Search for Room, join, both Ready, Start Quest, and both
copies in the quest (25 fps each). All as on AMD, after one fix: opening Ad
Hoc Play after browsing the journal hung at "Connecting .." because
`adhoc_matching.suprx`'s place was taken and its native code could not run
(fork patch 0040, [02-baseline](02-baseline.md#rtx-4090-non-map-pass-2026-10-13)).
Not vendor-specific: the AMD runs opened Ad Hoc Play straight from the hub.

Unless noted: all modules native (NativeCPU, no JIT), Vulkan on the Radeon
760M, `full_3d` on. Scripts can start quests and walk menus, but they
cannot win fights: ✅ from a script means "reached and behaved", not
"played through".

## Settings, display and input

| Area | Status | Checked by | Notes |
|---|---|---|---|
| `ss-delta.ini` settings, warnings for unknown keys | ✅ | scripted | Phase 6 |
| 3D at 960×544 (`full_3d`), `scale` 2 (3D at 1920×1088) | ✅ | scripted, user | all 50 map IDs at 29.3–29.8 fps (Phase 8); depth-of-field haze at 960×544 fixed (patch 0033) |
| Keyboard and gamepad bindings | ✅ | user | Phase 6 playtests |
| Mouse as the touchscreen | ✅ | user | title, name entry |
| Black Rite on a key / trigger (`[touch]`) | ✅ | user | left trigger, in a fight (2026-10-12) |
| F11 / Alt+Enter fullscreen, F12 screenshot | ✅ | scripted | screenshots at render resolution |
| Offline: no network use | ✅ | scripted | Phase 6; the network check dialog ends as cancelled offline (patch 0036) |

## Boot, saves and add-ons

| Area | Status | Checked by | Notes |
|---|---|---|---|
| Boot, title, main menu | ✅ | user, scripted | |
| New game, name entry, intro | ✅ | user, scripted | Phase 6 playtest; save creation and the intro scripted in Phase 9 |
| Save and load | ✅ | user, scripted | load from the title (scripted daily); saving in a quest by the user |
| Import / export of a Vita save | ✅ | scripted | a story-complete save from Apollo's database (Phase 8) |
| Several saves (the game's three slots) | ✅ | scripted | `--import-save ... --slot 2`; the load screen lists both, slot 2 loads the 100% save (patch 0035) |
| Add-ons (raiments, pacts) | ✅ | scripted | recorded in `system.bin` (D14); Healer, Beast, Easterner raiments shown as new. Add-on pacts: see quests |

## Hub and Librom

| Area | Status | Checked by | Notes |
|---|---|---|---|
| Hub (the prison), Librom view | ✅ | scripted, user | |
| Mad Chronicle (story chapter list, pages) | ✅ | scripted | late save: all chapters listed; a late chapter read (Phase 7) |
| Portraiture: appearance, raiments, offerings | ✅ | scripted | Select Offerings (37 pages); Fuse Offerings: a fusion done, the counts change |
| Right Arm: sigils | ✅ | scripted | Carve Sigil: a sigil carved, the arm's boosts change; Rewrite Lv, Essences, Rite of Transmutation open |
| Bazaar Ledger: Carnatux, Cassus (gifts) | ✅ | scripted | a raiment traded at Carnatux ("New raiment acquired", the offering count drops); Cassus's gifts (Phase 8) |
| Lore, Postscript | ✅ | scripted | 100% save: Lore's categories and entries, Postscript pages |
| Blank Page (created pacts) | ✅ | scripted | pact pages render |
| Log & Settings: Save, Options | ✅ | scripted | Color Space set to Wide, saved, kept after a restart (stored in `system.bin` +0x21c); all six option pages open |
| Network: Play Online | ✅ | scripted | offline, Play Online returns to the menu (it waited at "Connecting..." forever before patch 0036) |
| Ad Hoc Play: Create Room, Search for Room, join | ✅ | scripted | two copies on one PC (`--player 2` and `3`, 2026-10-12, NativeCPU): the search lists the host's room, the client joins, both rooms show both sorcerers (plan Phase 10) |
| Ad Hoc Play: a quest together | ✅ | user, scripted | the owner played a quest together and completed it without issues (2026-10-12). Scripted before: Ready, Start Quest and the fight run in step on both copies (same kills, same "targets remaining", same results page). A copy that lets the "Return to lobby" countdown run out leaves the room |
| Ad Hoc Play: LAN between two PCs (`network = lan`) | ✅ | user | 2026-10-12 |
| Ad Hoc Play: a gamepad per copy (`[multiplayer] gamepad`) | ❔ | | needs two gamepads |

## Quests

| Area | Status | Checked by | Notes |
|---|---|---|---|
| Every quest map renders | ✅ | scripted | all 50 map IDs (Phases 7–8); ST17A's only quest does not start from Stage Select (shares ST17B/C's arena) |
| Story quests (`q_e`) | ✅ | scripted | 3 of 98 started and played to the 2.5 s walk (first, middle, last): e0001, e0401, e1504 |
| Avalon pacts (`q_a`) | ✅ | scripted | a0101, a0601, a1014 of 150 |
| Grim pacts (`q_b`) | ✅ | scripted | b0101, b0308, b0514 of 70 (b0514's boss killed the idle player) |
| Sanctuarium pacts (`q_s`) | ✅ | scripted | s0101, s0307, s0514 of 75 |
| Additional pacts, add-ons (`q_l`) | ✅ | scripted, user | l0101, l1103 of 64 scripted; l1206 (ST17A) does not start from Stage Select. A DLC quest played and cleared from the menus (user, 2026-10-12) |
| `q_w` quests (Aquacity) | ✅ | scripted | w0101, w0701, w1204 of 48 |
| Debt Pacts (`q_y`) | ✅ | scripted | y0101, y1001, y1801 of 18 |
| Alice's Hollow (`q_h`) | ✅ | scripted | h0101, h0301, h0401 of 4 |
| Town hunts (`q_o`) | ✅ | scripted | o0001, o0003, o0005 of 5 |
| Other quest types: Phantom (`q_g`), AR (`ar000_00`), test (`testG`), TGS 2013 demo (`tgs2013`) | ✅ | scripted | 2–3 each started |
| Mind's Eye | ✅ | scripted | Phase 7 |
| Fights, Black Rites, sacrifice/save choices, quest clear | ✅ | user | combat, a sacrifice, a DLC quest cleared (2026-10-12) |
| AI allies | ✅ | user | in a co-op DLC quest (2026-10-12) |
| Physics and monster AI timing, native against JIT | ✅ | compared | b0514 idle, 5 runs each: same load time, player down after 24.0 s native and 23.1 s JIT (spread ±5 s in both), same sequence of events ([02-baseline](02-baseline.md#native-against-jit-an-idle-fight-timed-2026-10-12)) |

## Cutscenes, movies and audio

| Area | Status | Checked by | Notes |
|---|---|---|---|
| Book-page episodes | ✅ | scripted | Phase 7 |
| Story scenes up to the final battle | ✅ | scripted | late save: sacrifice scene, Magusar's introduction (Phase 7). 100% save, Fight Magusar: Librom's dialogue, the Save/Sacrifice prompt (hold R), Librom's sacrifice scene, the final battle's opening scene and the fight; losing it gives "This is not the end..." and the save prompt |
| Endings after the final battle | ⚠️ | scripted | not reached: the final battle was not won, by the user or by script (a weakened boss through a loose `chara_param.csv` did not change the fight), and the debug cutscene viewer's `PrisonEnd01` needs the story context (back to the title, as `BookEnding`). Their content checked as far as possible: the ending events (`prison_ending_*`) play movies with subtitles, as the opening does; all 13 movies decode without errors in FFmpeg and share one format (H.264 High 960×544, AAC) with the two openings that play in-game |
| Credits (StaffRoll) | ✅ | scripted | the debug `StaffRoll` with "clear": the full credits to the closing copyright card |
| Movies (FMV) | ✅ | scripted | new game: `ev01_opening.mp4` and `ev03_opening.mp4` play (AvPlayer, recompiled) |
| Audio | ✅ | user | 2026-10-12 |

## Developer content

| Area | Status | Checked by | Notes |
|---|---|---|---|
| Debug menu, Stage Select, test maps | ✅ | scripted | used by the sweeps; `LEVEL_TEST_00GA` renders |
| `BookEnding` sequence | ⚠️ | scripted | black, on upstream Vita3K too (needs context the debug boot lacks) |
