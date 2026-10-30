# DP-UB450 / UB150 — Blu-ray Region Switch

Play Blu-ray and DVD discs from other regions on a DP-UB450, DP-UB150 or
similar MediaTek-based player. No soldering, no permanent changes, fully
reversible.

> **Use Method 2.** It sets the player to one region at a time, and needs no
> USB while watching.
>
> **Method 1 (the per-disc helper) works since 30 Oct 2026.** It sets the
> region register, then puts the player's own interface back, so disc menus
> keep working. Verified on the player: Chernobyl (A+B), Jigsaw (locked A)
> and The Hurt Locker (locked B) all played with working menus in one
> session. One rule: **the first disc after a boot must be one the player
> starts anyway** (A+B or its own region) — a fresh locked disc is refused
> before the helper can run. The byte `3` it relies on does not open the
> player's gate when the stick is out. Discs differ in how strictly they
> check; `7` is not "all regions". True all-region firmware is not provided
> by this project.

There are two ways to use it:

| Method | What it does | USB while watching |
|---|---|---|
| **[Method 1 — play both regions](#method-1--play-both-regions)** | one value (`1`) plays the tested locked A and B discs; put a playable disc in first | stays in the player |
| **[Method 2 — region switcher](#method-2--region-switcher-no-stick-while-watching)** (recommended) | sets the player to one region (`1`, `2` or `4`) at a time | only while the tool runs |

Both start by [downloading the repository](#common-setup); building `BDJ.jar` is only needed for Method 2.

## What you need

> Warning: you must be comfortable to run the command line on your machine e.g. using Windows prompt. If not, these steps might not be for you. So, please ask someone else to do it for you instead.

**Update your player's firmware first** (Setup → System → Firmware Update). The region change might not survive a future update, so get that out of the way before you start.

- **DP-UB450 or DP-UB150** (tested on UB450GN, Australia). May also work on UB154, UB159. See "Does this work on other models?" below
- **A USB drive** (any size, formatted as **FAT32** — most already are; FAT16 also worked on the tested player)
- **A computer** (Mac, Windows with WSL, or Linux)
- **A Blu-ray disc with BD-J that the player can currently play** — same region as its current setting, or a region-free/A+B disc. Most major-studio discs have BD-J; to check on a computer, open the disc and look for a `BDMV/JAR/` folder containing one or more `.jar` files (see "How do I check the disc has BD-J?" below). Do not rely on the disc from the other region you want to play: with the region switcher it can stop at the region-error screen before its Java starts, so the script never runs. (With the Method 1 helper loaded, a mismatched disc's Java does start — measured 29 Oct 2026.) If the script does not start, try another playable disc with BD-J.
Everything above is needed for both methods. **Method 2 only** also needs:

- **The firmware update file** (`PANA_DVD.FRM`) — download it from the manufacturer's support site for the UB450 or UB150. You need the file, not to install the update
- **Python 3** (pre-installed on Mac and most Linux; [python.org](https://www.python.org/downloads/) for Windows)
- **unsquashfs** — to extract a file from the firmware:
  - macOS: `brew install squashfs`
  - Linux: `sudo apt install squashfs-tools` (often pre-installed)
  - Windows: use WSL (Windows Subsystem for Linux), then follow the Linux instructions

## Common setup

**Step 1 (download) is needed for both methods. Step 2 (build) is only needed
for Method 2** — Method 1 uses the helper jar that ships in the repository, so
it needs no firmware file, no Python and no `unsquashfs`.

### 1. Download

Clone or download the repository:

```sh
git clone https://github.com/hemmachat/ub450-region-switch.git
```

Or click **Code → Download ZIP** on the [repository page](https://github.com/hemmachat/ub450-region-switch) and unzip it.

### 2. Build BDJ.jar (Method 2 only)

Open a terminal (command prompt on Windows), go to the `build/` folder and run:

```sh
python3 build.py /path/to/PANA_DVD.FRM
```

Replace `/path/to/PANA_DVD.FRM` with the actual path to your downloaded firmware file. The script writes `usb-files/BDJ.jar`. Use it in [Method 2](#method-2--region-switcher-no-stick-while-watching); Method 1 uses the helper jar that ships in the repo instead.

The script will:
1. Extract the player's boot classes from the firmware
2. Set the debug flag (one byte change)
3. Add the region-change trigger
4. Output `BDJ.jar` into the `usb-files/` folder

You should see output ending with `Done.` and a SHA-256 hash.

## Make the USB automatically (optional)

`make-usb.py` asks a couple of questions and writes the stick for either
method, checking every copied file against the repository by SHA-256:

```sh
python3 make-usb.py
```

- **Method 2 (recommended, the default):** press Return; it asks for the
  Blu-ray region and the DVD region (or `skip`) and copies `usb-files/BDJ.jar`
  — build it first (common step 2), or pass `--jar /path/to/BDJ.jar`.
- **Method 1:** choose `1`; it asks for the USB path and the
  region value (default `1`). Read [its limits](#method-1--play-both-regions)
  first.

It never deletes anything, and it only overwrites existing files after you
confirm — `--yes` skips that prompt for scripted use, and picks Method 2
unless you pass `--method`:
`python3 make-usb.py --method 1 --usb /Volumes/USB --yes` (Method 1) or
`--method 2 --bd 2 --dvd skip --yes` (Method 2).

This needs Python 3, which Method 1 does not otherwise require — the manual
copy in its setup section does the same thing.

## Method 1 — play both regions

> **Works since 30 Oct 2026.** The helper sets the region register and then
> puts the player's own interface back, so disc menus keep working (see
> "The menu freeze, fixed" below). Verified on the player: Chernobyl (A+B),
> Jigsaw (locked A) and The Hurt Locker (locked B) all played in one session.

One value, `1`, plays the tested locked region A disc **and** the tested locked
region B disc in the same session. The USB stays in the player while you
watch. **Insert a disc the player starts anyway first** (A+B or its own
region): it sets the register, and every disc after it plays in that session.

### Set up the USB (once)

This method does not need the `BDJ.jar` you would build: it uses the helper jar that ships in the repository. (Or let [make-usb.py](#make-the-usb-automatically-optional) copy the files for you.)

| File on the stick | Value |
|---|---|
| `BDJ_DEBUG` | empty file (from `usb-files/`) |
| `BDJ.jar` | the helper: `usb-files/BDJ-region-helper.jar` |
| `run.sh` | from `usb-files/` |
| `bd_region.txt` | **edit line 1** from the shipped `1` to `3` |
| `psr20_value.txt` | ships with `1` (from `usb-files/`); leave it |
| `dvd_region.txt` | **empty the shipped file** (the shipped one contains `1`, which would set the DVD region to US) |

Do not remove `bd_region.txt`: the helper also runs `run.sh`, and without that
file the run falls back to writing `1`, which closes the `3` gate after the
next power cycle.

The helper jar was built from the Australian V127 firmware. Copy the files
from `usb-files/` to the **root** of the stick. On another model,
rebuild it from your own firmware with
`testing/inprocess-experiment/build_inprocess.py` (source:
`testing/inprocess-experiment/RegionPatch.java`). Why this works, and what `3`
means, is in `docs/region-bitmask-finding.md`.

### First run (once)

The player must store the `3` once. With the stick in the player:

1. Unplug the player at the wall, insert the stick, power on. If the player
   shows its USB media menu ("please select a function"), press **Return** to
   leave it.
2. Insert any Blu-ray with BD-J that the player can play and wait ~30 s.
3. Unplug the player, power on once more — that applies the `3`.

To see what the run did, plug the stick into a computer afterwards:
`region_log.txt` should say `Config write VERIFIED: … BD=0x03`.

If you already ran the tool before, the byte is probably `3` already. A
locked region A disc still shows its region message if you start it **without**
the stick: the byte is not enough on its own, the disc's Java only starts
when the helper is loaded (measured 29 Oct 2026).

### Play

Keep the stick in the player and insert any disc. The helper applies the
value about 10 seconds after the disc's Java starts.

Tested on the Australian UB450: Chernobyl (A+B), Jigsaw (locked A) and
The Hurt Locker (locked B) all played in one session with working menus
(30 Oct 2026).

**The menu freeze, fixed (30 Oct 2026).** Until 30 Oct the helper replaced
the player's interface object and left it replaced; that object has none of
the player's data, so the disc's Java lost its key handling — the top menu
appeared, Home worked, and no other key did anything. An experiment that
installed the object and never wrote the register froze the menu the same
way, which proved the cause was the replacement, not the region value. The
helper now sets the register and then **puts the player's own object back**:
it scans the writable memory for the object whose vtable is the player's misc
interface, accepts it only when its backend member points at real code, and
restores the pointer. The replacement now lasts milliseconds. `patch_result.txt`
shows the whole chain: `get20 before=2`, `target written`, `get20 after=1`,
`cand=… vt=c99a30 ok`, `passing=1`, `restored=…`, `get20 real=1`.

**Region timing.** A newly inserted disc checks the region in its first
seconds, before the helper runs (about 10 seconds after the disc's Java
starts). That is why the first disc after a boot must be one the player starts
anyway; after that the register stays `1` for the session.

### The value to use

| Blu-ray disc | `psr20_value.txt` |
|---|---|
| Locked region A (US) | `1` |
| Locked region B, strict check | `2` |
| Locked region B, lax check (tested: The Hurt Locker) | `1`, `2` or `7` |
| Region C | `4` (not tested) |

Discs do not all check the region the same way. Jigsaw (locked A) accepts only
`1` and refuses `7`. The Hurt Locker (locked B) accepted `7`, and it also
played with the player set to `1`. So `1` is the value to try first: it played
the locked A disc and The Hurt Locker in one session, with no edit between
discs. A locked B disc that checks strictly would need `2` — and then region
A discs stop playing. Remember the warning above: this worked on 29 Oct 2026
and failed on the same disc that evening. **Never use a value above `7`** —
`255` turned the picture off on the tested player. If `psr20_value.txt` is
missing or holds no number, the helper uses `1`.

### Change the value

1. Eject the disc.
2. Pull the USB out of the player.
3. On a computer, set the first line of `psr20_value.txt` to the value you
   need. Save the file.
4. Eject the USB from the computer and put it back in the player.
5. Insert a disc whose Java has not just started — a different disc, or any
   disc after a power cycle. The helper reads the value about 10 seconds
   after the disc's Java starts. If the disc's menu is still on screen when
   that happens, it may stop responding — use Method 2 for that disc.

The value is read when a disc's Java starts. Reinserting the **same** disc can
resume the previous playback instead; the helper then does not run again and
the new value is not applied — use another disc or power-cycle the player.
For the tested discs, `1` needs no change at all.

### Limits

- The USB must stay in the player while watching. Without it the player uses
  its own region (B on the Australian unit) and locked A discs are blocked.
- The helper only runs for Blu-ray discs that have BD-J. DVDs are not affected
  — their region comes from the tool run in Method 2 (plus, on some units, the
  EEPROM copy).
- A locked B disc that checks strictly needs `2`, which then locks out region
  A discs.
- The player must have the byte at `3` (the first run above).
- The **first disc after a boot** must be one the player starts anyway (A+B
  or its own region). A freshly inserted locked disc checks the region in its
  first seconds, before the helper runs; after the register is set, every disc
  in that session plays.

The helper writes **`patch_result.txt`** on the stick each time a disc's Java starts,
with the region it read before and after the change (`get20 before=`,
`value file=`, `get20 after=`), the interface scan (`cand=`, `passing=`) and
the restore (`restored=`, `get20 real=`). If a disc is refused or the screen stays blank,
that file plus your `psr20_value.txt` is what to send (see
[Something not working?](#something-not-working-send-us-these-files)).

## Method 2 — region switcher (no stick while watching)

This sets the player's own Blu-ray region to one value and keeps it. The stick
is only needed while the tool runs; remove it for playback. One region at a
time: to play the other region, run it again.

### Set up the USB

Format the USB drive as **FAT32**. Copy these files from `usb-files/` to the
**root** of the stick (or let [make-usb.py](#make-the-usb-automatically-optional)
do it, after building `BDJ.jar`):

- `BDJ_DEBUG` (an empty file — do not open or edit it)
- `BDJ.jar` (the file you built in common step 2)
- `run.sh` (the region-change script)
- `bd_region.txt` — **edit line 1**: `1` = A, `2` = B, `4` = C (table below)
- `dvd_region.txt` — ships with `1` (US). **Make the file empty to leave the
  DVD region unchanged**, or put another number on line 1 (table below)
- `DVD_EEPROM` (optional, advanced — **create an empty file with this name**
  to enable the unverified hardware EEPROM write; see
  [What about DVDs?](#what-about-dvds))
- `diag.sh` (collects diagnostic data — always include it)
- `USB-README.txt` (optional — the same guide, for reference on the stick)

The stick should look like this:

```
USB drive (root)
├── BDJ_DEBUG
├── BDJ.jar
├── run.sh
├── bd_region.txt   (1=A, 2=B, 4=C)
├── dvd_region.txt  (default 1 = US; empty = no DVD change)
├── DVD_EEPROM      (optional — create an empty file; leave out normally)
├── diag.sh
└── USB-README.txt  (optional — this guide)
```

**Blu-ray values** (`bd_region.txt`, line 1):

| Disc you want to play | Region | Value |
|---|---|---|
| US, Japan, Korea, South-East Asia | A | `1` |
| Australia, Europe, Africa, Oceania | B | `2` |
| Central/South Asia, Russia, China | C | `4` (not tested) |

A locked Blu-ray disc from another region shows its region message. `7` is not
"all regions": the player falls back to its own region, so on a region A
player it does not play region B discs.

**DVD values** (`dvd_region.txt`, line 1):

| Disc you want to play | Value |
|---|---|
| US, Canada | `1` |
| Europe, Japan | `2` |
| South-East Asia, Korea, Taiwan | `3` |
| Australia, Oceania, Latin America | `4` |
| Russia, India, Africa | `5` |
| China | `6` |
| Region-free (some discs refuse it) | `0` (not verified) |

On some players the DVD value comes back after a restart unless the EEPROM
copy is written too (that EEPROM write is not verified yet) — see
[What about DVDs?](#what-about-dvds).

### Run it

1. **Unplug the power cord** (or switch the socket off). Do not use the remote.
2. **Plug the USB drive** into the player.
3. **Plug the player back in, turn it on**, and wait for the home screen (no
   disc yet).
4. **Insert a Blu-ray with BD-J that the player can currently play** — the
   same region as its current setting, or a region-free/A+B disc. The script
   starts when the disc menu loads; if only the home screen appears, press
   **Top Menu**. A disc from another region may show a region message and never
   start its Java, so the script does not run from that screen.
5. **Wait about 30 seconds** after the disc menu appears.
6. **If no `region_log.txt` appears on the USB, the script did not run** — try
   another playable disc with BD-J.
7. **Unplug the player** (not the remote), leave it off for a few seconds.
8. **Remove the USB drive**.
9. **Plug it back in and turn it on**.

### Check it worked

Plug the USB into your computer. The main file is **`region_log.txt`**
(replaced on every run). It shows the original values, whether the write was
verified, and how far the script got.

- **`Config write VERIFIED`** — the new values are in the config file.
- **`REGION_FREE_OK.txt`** — the script reached the end. It can be missing when
  the player stopped the script early; that alone does not mean it failed.
- **`REGION_FREE_FAILED.txt`** — something went wrong. Check `region_log.txt`
  and `diag_output/` (if present) and attach them to an issue.

The full list of files the tool writes is in
[Something not working?](#something-not-working-send-us-these-files).

### Change region later

- **Blu-ray:** edit `bd_region.txt` (line 1: `1`, `2` or `4`).
- **DVD:** edit `dvd_region.txt` (line 1: `0`–`6`), or make the file empty to
  leave the DVD region alone.

Then repeat [Run it](#run-it) and unplug the player at the end.

Tested on a DP-UB450GN (Australia, firmware V127), 26-29 Oct 2026: Jigsaw
(locked A) plays with `1`; The Hurt Locker (locked B) plays with `2` (and with
`7`, which the player treats as its own region); Chernobyl (A+B) plays with any
value. Playing both regions without switching is the idea behind the
[Method 1](#method-1--play-both-regions).

## How to undo it

If you ever want to go back to your original region:

1. Create an empty file called **`RESTORE`** on the USB drive (next to the other files)
2. Repeat [Run it](#run-it) in Method 2: unplug the player, plug in the USB, insert a playable Blu-ray with BD-J, wait, unplug it again, remove the USB, then plug it back in and turn it on

For the per-disc region helper, undoing is simpler: pull the USB out — with no stick the player uses its own region again.

The player will restore your original region from the backup that was saved during the first run (including the EEPROM DVD region, if it was changed). The backup is created on the first run of the tool — if you ran it before, the backup holds the values from that first run, not necessarily the factory values.

## Something not working? Send us these files

Everything below is written onto the USB stick by the tool. Copy the files off
the stick after **each** run — most of them are overwritten on the next run.

These two always help:

| File | What it tells us |
|---|---|
| `region_log.txt` | The whole run: the `Started:` time, the `Before: DVD=0x…, BD=0x…` values, `Config write VERIFIED` or `MISMATCH`, and the last checkpoint reached if the player stopped the script early. |
| `.config_dump.bin` | A copy of the player's config file from that run — shows whether the region bytes really are at the expected offsets on your model. |

Then add the one that matches what happened:

| What happened | Also send |
|---|---|
| The script stopped early (`REGION_FREE_FAILED.txt` appears) | That file — its text names the reason (`config file not found`, `BD region key not found`, `value offset out of range`, `invalid BD region`, …). `REGION_FREE_OK.txt` can be missing even when the write worked; the `Config write VERIFIED` line is what counts. |
| The region went back to the old value after a power-off | The files from the run **before** and the run **after** the power-off, renamed `log-1.txt`, `log-2.txt`, … so they do not overwrite each other. The second run's `Before:` line is the answer. |
| The values look wrong from the start | `.config_backup.txt`, `.bd_backup.bin`, `.dvd_backup.bin`, `.bd_offset.txt`, `.dvd_offset.txt` — saved on the **first** run only, so they hold the values from before the tool wrote anything. |
| A DVD region does not stick, or you used `DVD_EEPROM` | `.eeprom_dvd_backup.bin`, `.eeprom_device.txt` (if present) and the `diag_output/` folder. |
| The per-disc helper refuses a disc | `patch_result.txt` (written on the stick each time a disc's Java starts), plus the current `bd_region.txt` and `psr20_value.txt`. |
| The disc menu shows but the remote does nothing (per-disc helper) | `patch_result.txt`, `psr20_value.txt` and `bd_region.txt`. The fixed helper logs `restored=` and `get20 real=`; if the file has no `restored=` line, the helper did not find the player's interface object — send the file. A first disc that is region-locked is refused before the helper runs: insert a playable disc first. |
| Nothing above explains it | The `diag_output/` folder — see below. |

**`diag_output/`** is a deeper read-only check. `run.sh` runs `diag.sh`
automatically at the end, so the folder is already on the stick after a run
that reached the end. If the script stopped early and there is no folder,
rename `run.sh` to `run-region.sh`, rename `diag.sh` to `run.sh`, and do one
more run. It contains `diag_log.txt`, copies of the player's config files,
small dumps of the storage devices (`*.bin`) and `strace_bdpprog.txt`. It only
reads; nothing is written.

**Hidden files:** `.config_dump.bin`, `.config_backup.txt`, `.bd_backup.bin`,
`.dvd_backup.bin`, `.bd_offset.txt`, `.dvd_offset.txt`, `.eeprom_dvd_backup.bin`
and `.eeprom_device.txt` start with a dot, so Finder hides them. Press
<kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>.</kbd> on a Mac (or use `ls -a` in a terminal)
to see them.

Also write down: your **model number** (back label, e.g. `DP-UB450`), the
**firmware version** (shown in the player's setup menu), which **disc** you used
and what region it is, and the exact text of any message on screen. A photo of
the screen helps.

## Help test US, UK and EU players

On some US, UK and EU units the player writes the region but shows the old
value again after a clean power-off. If you have one of those players and a
disc from another region, your logs answer the open question. Use the `us/`
packet (writes `2`) on a US player, or the `uk/` packet (writes `1`) on a UK/EU
player, from the [latest release](https://github.com/hemmachat/ub450-region-switch/releases/latest).

1. **Run 1 — write the value:** unplug the player, insert the USB, plug the
   player back in and turn it on. Insert a BD-J disc the player can play and
   wait about 30 seconds. Rename `region_log.txt` on the USB to `log-1.txt`,
   and copy `.config_dump.bin` to `dump-1.bin`.
2. **Run 2 — normal power-off:** press the power button on the remote, turn
   the player on, insert the disc again, wait about 30 seconds. Copy
   `region_log.txt` to `log-2.txt` and `.config_dump.bin` to `dump-2.bin`. The
   line starting with `Before:` answers the question.
3. **Run 3 — only if Run 2 shows the old value:** insert the disc, wait about
   40 seconds, pull the power cord, plug it back in, insert the disc again,
   wait about 30 seconds. Copy `region_log.txt` to `log-3.txt` and
   `.config_dump.bin` to `dump-3.bin`.

Send `log-1.txt`, `log-2.txt`, `log-3.txt`, `dump-1.bin`, `dump-2.bin` (and
`dump-3.bin` if you did Run 3), `.config_backup.txt` if it is on the stick, plus
your model and firmware version, in a [GitHub issue](https://github.com/hemmachat/ub450-region-switch/issues).
The dot-files are hidden in Finder — press <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>.</kbd>.
Full details, including why each run matters: [testing/US-UK-test-protocol.md](testing/US-UK-test-protocol.md).

## FAQ

### Which USB port should I use?

Use whichever USB port your player has. The UB450 has one on the front; other models may have front and rear ports. Either works.

### The screen goes blank and stays blank

The disc's menu software is loading from the USB. Wait 30–60 seconds. If it stays blank for more than 2 minutes, remove the USB, unplug the player, plug it back in and turn it on.

With the per-disc helper (advanced) a blank screen right after a disc starts means the helper upset the player: remove the USB, power-cycle, and insert the disc again without the stick. The film should play in the player's own region.

### The disc menu appears but the remote does nothing

With the per-disc helper (Method 1) this was measured on Jigsaw, 29 Oct 2026: the top menu showed and Home worked, but Left, Right and Play did nothing. The helper still set the region correctly, so this is a limit of the helper, not the disc. Play that disc with [Method 2](#method-2--region-switcher-no-stick-while-watching) — set its own region, no stick while watching. See [the limit](#limits) in Method 1.

### How do I check the disc has BD-J?

1. Put the disc in a computer with a Blu-ray drive.
2. Open the disc and go into the `BDMV` folder.
3. Look for a `JAR` folder containing one or more `.jar` files.
4. If `BDMV/JAR` is missing or empty, the disc has no BD-J and cannot start the script — use a different disc.

No Blu-ray drive? If you have a disc image or backup folder, MakeMKV or any Blu-ray tool shows the same `BDMV/JAR` structure. The disc menu must also actually start on the player: if only the player's home screen appears, press **Top Menu** on the remote.

### Can I leave the USB in during normal use?

It depends which method you use:

- **Method 2 (region switcher, recommended):** remove the stick after the run.
  The script only has to run once per region change, and `BDJ_DEBUG` changes
  how the player loads disc software.
- **Method 1:** yes, the stick must **stay in the player**, because the
  helper runs when each disc starts. A disc's menu keeps working: the helper
  restores the player's own interface right after setting the region (see
  [Method 1](#method-1--play-both-regions)).

If a disc ever shows a blank screen, remove the USB and power-cycle the player;
with no stick the player behaves normally.

### Will this survive a firmware update?

Unknown. If a firmware update resets the region, repeat the process.

### The region went back to the old value after a reboot

v5.7 and later log `Config write VERIFIED` when the new value is in the config file. If the next run's `Before:` line shows the old value, the player wrote its own copy of the settings back over the file. This can happen at a clean power-off on some UK, US and EU units (confirmed on a UK player, 26 Oct 2026); the Australian unit has not shown it, but the unplug step is safe there too. **Unplug the player instead of using the remote after the run** — an EU user confirmed that keeps the change, and the tool's closing log says the same. Send `region_log.txt` and `.config_dump.bin` from both runs, plus your model and firmware version — the full list is in [Something not working?](#something-not-working-send-us-these-files). US and UK testers are also checking whether a normal value survives — see [Help test US, UK and EU players](#help-test-us-uk-and-eu-players).

### An older version wrote `7` — why did a disc play then?

`7` is not an "all regions" value on stock firmware; the player falls back to its own region. If a disc played, region A was actually loaded: either the value had been set to `1` by an earlier test or manual run, or the player was still using the region it loaded at startup — a written value only takes effect after the next power cycle. The current version writes `1` explicitly; the `Before:` line in `region_log.txt` shows the value that was in the file.

### Can this make my player region-free?

On the tested player, the per-disc helper at value `1` plays the tested
locked A disc and the tested locked B disc in the same session — see
[Can the player be made region-free (play A and B at the same time)?](#can-the-player-be-made-region-free-play-a-and-b-at-the-same-time).
It is not a universal unlock: a disc that checks strictly for its own region
can still refuse, and true all-region firmware is not provided by this
project.

### Does this work on other models?

It was built and tested on a DP-UB450GN (Australia, firmware V127). The script finds the region settings dynamically, so it adapts to different firmware layouts.

**UB150, UB154, UB159** — likely to work. Same firmware family (unencrypted `PANA_DVD.FRM`), same MediaTek MT8581 platform. Download your model's firmware update and run `build.py` with it. One UB150EF unit reported that at `1` only region A discs play; set `2` to return to region B.

**UB420, UB820, UB9000** — unknown. These models use encrypted firmware (`PANAEUSB.FRM`), so `build.py` cannot extract the boot classes from it. You would need to build BDJ.jar using a UB450 or UB150 firmware file instead, and it is unconfirmed whether the result works on these players. If you own one of these models and want to try, open an issue first so we can coordinate.

If you try it on a different model, please report back by opening an issue.

### Is this safe? Can it brick my player?

The process changes the region settings in the player's configuration and, only when you add a `DVD_EEPROM` file, the DVD region in the hardware memory. It does not modify the firmware. The original values are backed up to the USB drive, and you can restore them at any time (see "How to undo it"). In the worst case, a factory reset (Setup → System → Default Settings) may restore the original region (not tested on this player).

The steps switch the player off at the wall on purpose: it stops the player saving its old settings over the new region. That is safe outside a firmware update — just don't do it while the player is installing firmware.

### The build script fails on my firmware file

It stops with an error instead of guessing:

- **`Error: no SquashFS filesystem found in firmware file.`** — the file is encrypted (UB820/UB9000 images are). Use the `PANA_DVD.FRM` update file for a UB450 or UB150; the BD-Java classes are the same across the platform.
- **`Error: unsquashfs not found.`** — install it first (see [What you need](#what-you-need)).
- **A `ValueError` such as `Pattern 04 B3 00 6D not found in class file` or `Last bytecode is … expected return`** — your firmware's classes differ from the tested one (AU V127). Nothing has been changed on the player; open an issue with your model and firmware version.

The player side also stops safely: if the region keys are not where the tool expects them, it writes `REGION_FREE_FAILED.txt` with the reason (see [Something not working?](#something-not-working-send-us-these-files)).

### What about DVDs?

DVD regions are supported as of v5. The player keeps the DVD region in the config file and in a second copy in the hardware EEPROM, and it reads the EEPROM copy at every boot. The script always writes the config file; it writes the EEPROM **only when a `DVD_EEPROM` file (empty) is on the USB**, because the EEPROM step is the only write outside the config file and it has not been verified on real hardware yet. By default the tool sets DVD to region 1 (US); put a `dvd_region.txt` file on the USB to choose 0–6.

The EEPROM step also requires that the value in the config file differs from the one you are setting, that exactly one device matches, and that `/proc/mtd` gives a size for every MTD partition it considers. If more than one device matches, it refuses to write and logs `EEPROM write REFUSED`. The matching device is backed up to `.eeprom_dvd_backup.bin` before any write. If you enable `DVD_EEPROM`, check `region_log.txt`: `EEPROM write SUCCEEDED` means it verified, `REFUSED` means it stopped safely. If the DVD region still doesn't stick, send the `diag_output/` folder — with a verified EEPROM write we still need to confirm the correct device on more models. The files to send are listed in [Something not working?](#something-not-working-send-us-these-files).

DVD uses one region number (0–6); `0` is the region-free value. This is **not verified** on these players: the firmware reads the DVD region from the hardware EEPROM at boot, and the EEPROM copy is only written when the advanced `DVD_EEPROM` file is on the USB. Setting `dvd_region.txt` to `0` changes only the config file, which the player may override at boot. A few older RCE DVDs also refuse a region-0 player.

### Can the player be made region-free (play A and B at the same time)?

**Yes, with [Method 1](#method-1--play-both-regions), since 30 Oct 2026.**
With the helper set to `1`, the tested locked A disc, the tested locked B disc
and an A+B disc all played with working menus in one session. The first disc
after a boot must be one the player starts anyway (A+B or its own region);
every disc after it plays. The helper sets the region register and then puts
the player's own interface back — leaving that replacement in place is what
used to leave disc menus dead (Jigsaw, 29 Oct 2026). Method 2 (set the
player's own region, no stick) is still the simpler route for one region.

That is not a universal guarantee either. Discs check the region differently:
the locked A disc accepts only `1` (it refused `7`), the locked B disc is lax
(it plays at `1`, `2` and `7`). A locked region B disc that checks strictly
would need `2`, and then region A discs stop playing. Values above `7` are
unsafe — `255` blanked the picture. The technical reason is in
`docs/region-bitmask-finding.md`.

True region-free firmware for every disc is not provided by this project.

## How it works

The player has a BD-Java debug mode that loads boot classes from a USB drive. The build script extracts the boot classes from your firmware file, makes a small change to allow running a shell script, and packages the result as `BDJ.jar`. When you insert a disc with the USB plugged in, the script runs and does two things:

1. **Config file write** — writes both DVD and BD regions to the config file. This works on the tested Australian player; on some UK, US and EU units the value does not survive a reboot (under investigation). DVD also needs the EEPROM write below to survive a reboot.
2. **EEPROM direct write** — writes the DVD region to the hardware EEPROM at offset 0x200, where the firmware reads it at every boot. Off unless a `DVD_EEPROM` file is on the USB; see [What about DVDs?](#what-about-dvds).

The Blu-ray region is set to the value in `bd_region.txt` (1 = A by default), not to "all regions": the player stores any byte, but for values it does not recognise as a region it uses its own region instead. The per-disc helper described above exploits that: with the byte at `3` **and the helper loaded**, the player starts a disc of either region, and the helper sets the region the disc's Java sees. With the stick out, a locked disc is refused before its Java starts (29 Oct 2026). Measured 29 Oct 2026: at `1` both the locked A disc and the locked B disc tested play natively, because they check the register differently — see `docs/region-bitmask-finding.md`. The DVD region defaults to 1 (US) unless overridden by a `dvd_region.txt` file on the USB. The original values are backed up to the USB first. No firmware is modified. No network connection is needed.

## Building from source

The `build/build.py` script does everything:

1. Extracts the boot classes from the firmware update file
2. Applies the modifications needed to run the region-change script
3. Packages everything into a standard JAR

It requires Python 3 and `unsquashfs`. If you already have `BDJ.czf` extracted, you can pass it directly instead of the firmware file.

No proprietary code is included in this repository. The build script operates on files you obtain from your own player's firmware.

## Tests

Run every suite from the repository root:

```sh
sh tests/test_run.sh                     # offsets and region write logic
sh tests/test_pairwise.sh                # pairwise target selection
sh tests/test_targets_pict.sh            # 651-check PICT suite (slow)
sh tests/test_eeprom_pairwise.sh         # DVD EEPROM guards
sh tests/test_us_portability.sh          # bash -n portability
sh tests/test_tmo.sh                     # timeout wrapper fallback

python3 tests/test_setup_usb.py          # make-usb.py: both layouts, default method, refusals
python3 tests/test_build_py.py           # build/build.py: patch, exec, jar
python3 tests/test_downgrade_class.py    # downgrade_class.py: class 48
python3 tests/test_build_inprocess.py    # probe injection: static go()
python3 tests/test_diag_sh.py            # diag.sh: writes only to the USB
python3 testing/inprocess-experiment/tests/test_regionpatch_value.py
testing/inprocess-experiment/tests/run.sh  # probe suite
python3 testing/usb-agent/test_agent.py    # agent scripts
```

The tests need `python3`, `javac`/`javap` for the class-file suites, and a
shell. They do not need a player or a firmware file.

## Credits

Region codes: the player accepts `1` (A), `2` (B) and `4` (C) as single region codes. The values were checked against the [Blu-ray specification (PSR 20)](https://videolan.videolan.me/libbluray/player__settings_8h.html) via libbluray, but playback tests on a UB450GN (26 Oct 2026) show stock firmware does **not** treat the byte as a PSR 20 bitmask: `7` falls back to the player's own region. DVD values follow the [DVD region code standard](https://en.wikipedia.org/wiki/DVD_region_code). The BD-Java debug mode is a standard feature of the CVM runtime used in MediaTek-based Blu-ray players.

## Changelog

**v5.17 (30 Oct 2026)** — the per-disc helper restores the player's own interface; disc menus keep working.

- **The menu freeze is fixed.** The helper used to replace the player's misc-interface object at `0x010fec00` and leave it there; that object holds none of the player's data, so the disc's Java lost its key handling (Jigsaw, 29 Oct 2026). An experiment that installed the object without writing the register froze the menu the same way, which proved the replacement was the cause, not the region value. The helper now sets PSR 20, scans writable memory for the player's real object (first word = the misc-interface vtable `0xc92b20`), accepts it only when its `+0x10` backend points at real code, and writes it back; the replacement lasts milliseconds. `patch_result.txt` shows `scan ranges=`, one `cand=` line per match, `passing=`, `restored=` and `get20 real=`. Verified on the player: Chernobyl (A+B), Jigsaw (locked A) and The Hurt Locker (locked B) all played with working menus in one session (30 Oct 2026).
- **First disc after a boot must be playable** (A+B or the player's own region): a disc checks the region in its first seconds, before the helper runs (~10 s after the disc's Java starts). Later discs in the session see the register already set. It still reads PSR 20 first and skips everything when it already matches `psr20_value.txt`.
- `usb-files/BDJ-region-helper.jar` rebuilt (1,305,084 bytes, SHA-256 `7d69c5d540800fd5093868840a952bafa21ed63dc6e3c4559278195a2fc0c09b`). `test_regionpatch_value.py` now has 12 checks (the map-permission parser, the restore path and the masked scan target); the ARM stubs are emulated under QEMU (12 checks, `testing/inprocess-experiment/experiments/restore/run_emu.sh`). During development the restore was gated by a `restore_enable.txt` file on the stick; the shipped helper restores always.

**v5.16 (29 Oct 2026)** — per-disc helper demoted to experimental. Documentation and builder only; `run.sh` and the helper jar are byte-identical to v5.15, so nothing that runs on the player changed.

- **Method 1 is now experimental; Method 2 is the recommended method.** The README intro, method table, Method 1 heading (anchor is now `#method-1--play-both-regions`), limits, FAQ, `usb-files/USB-README.txt` and `docs/region-bitmask-finding.md` say so and point to Method 2. `make-usb.py` labels Method 1 experimental, offers Method 2 as the default answer, and `--yes` without `--method` now writes a Method 2 stick; its next-steps text warns about the menu limit. Test: `tests/test_setup_usb.py` — "No --method picks the recommended method" (written failing first; the default built the Method 1 stick before the change).
- With the helper loaded and the region set correctly, Jigsaw's top menu appeared but Left, Right and Play did nothing (Home still worked). `patch_result.txt` showed `get20 before=2`, `value file=1`, `get20 after=1`, so the value was applied — this is the helper, not the disc. The same stick and value played the same disc earlier that day, so the break may depend on pressing keys after the value is applied (~10 s after the disc's Java starts); not confirmed. Method 1 (Play, Limits, FAQ) now says to use Method 2 for a disc that needs its menu; `docs/region-bitmask-finding.md` records the run.
- Corrected an earlier claim: the byte `3` alone does not open the native gate. With the stick **out**, a Jigsaw start at `3` stops at the region-error screen before its Java runs (29 Oct 2026). The gate only opens while the helper is loaded.
- Every current-facing doc re-checked against the code, the firmware and the 29 Oct runs: `usb-files/USB-README.txt` (region switch first, timing and gate corrections), `docs/region-bitmask-finding.md` (status "answered", helper section experimental), status headers on the v5.13–v5.15 release notes, `tests/README.md` (Python suites listed; PICT count corrected 630 → 651), and the `RegionPatch.java` header comment. All README anchors verified.

**v5.15 (29 Oct 2026)** — guided USB builder, a `diag.sh` fix and unit tests.

- New `make-usb.py`: asks which method and the values, writes the stick for Method 1 or Method 2, and checks every copied file against the repository by SHA-256. Refuses values above `7`, invalid regions, a missing USB path and a missing `BDJ.jar`. See [Make the USB automatically](#make-the-usb-automatically-optional).
- `usb-files/diag.sh` now honours a `USB` override (`USB=${USB:-/mnt/sda1}`); it used to hard-set the player path and write its marker outside the chosen folder. Same behaviour on the player.
- Unit tests for every script that had none: `build/build.py` (permission flip, `Runtime.exec` injection, jar packaging), `downgrade_class.py` (class 48, StackMapTable removed), `build_inprocess.add_probe_call` (static `go()` entry point, the 29 Oct blank-screen bug), `diag.sh` (completes, writes only to the USB folder) and `make-usb.py` (both layouts, refusals, no overwrite without confirmation). Each was mutation-proved. See [Tests](#tests).

**v5.14 (29 Oct 2026)** — per-disc helper default and the measured single-value result.

- The helper's fallback value (used when `psr20_value.txt` is missing or unreadable) is now `1` instead of `7`. Measured 29 Oct 2026: `1` plays the locked region A disc **and** the locked region B disc tested (The Hurt Locker) in one session; `7` makes strict A discs refuse. `usb-files/BDJ-region-helper.jar` rebuilt with `PROBE_METHOD=go` (1,303,267 bytes, SHA-256 `3ed5effad1233c9d46f00f4e45b7c6793fea741b1a8e62fb9332acc0aa48dd6e`). Never use a value above `7` — `255` blanks the picture.
- Documented that the register set by the helper persists across disc swaps (it is not rebuilt at disc insert, correcting the 28 Oct note), so the stick must stay in the player while watching. A value change only applies when a disc's Java starts fresh — a different disc or a power cycle; reinserting the same disc can resume playback without re-running the helper.
- Confirmed end-to-end on the player, 29 Oct 2026: with the built stick (helper default `1`), Jigsaw and The Hurt Locker both played.
- New `usb-files/psr20_value.txt` (value `1`), so the recommended method needs no manual file creation.
- README restructured around the two ways to use it: **Method 1 (both regions, recommended)** first — no build needed, helper jar ships in the repo — then **Method 2 (region switcher)**. Shared setup and values tables stay in one place.
- Tests: `test_regionpatch_value.py` now covers 0–255 parsing, the `1` default, static `go()` injection and that the shipped jar matches a fresh build of the source (6 checks).

**v5.13 (29 Oct 2026)** — Blu-ray values and documentation.

- `bd_region.txt` now accepts `3`, `5` and `6` as well as `1`, `2` and `4`. The player stores any of them but uses its own region for values it does not recognise; `3` is the value the per-disc helper needs. The error message lists `1`/`2`/`4` (and `3` for the helper) only.
- Fixed a shell portability bug: the MTD size parsing used a `case` pattern inside `$( )`, which bash 3.2 rejects, so `bash -n` failed on the script. Rewritten without `case`; `tests/test_us_portability.sh` now checks `bash -n`.
- Documented the per-disc Blu-ray helper (README, `USB-README.txt`): with the region set to `3`, a BD-J jar sets the region register from `psr20_value.txt` about 10 seconds after a disc starts. Tested 29 Oct 2026: Jigsaw (locked A) with `1`, The Hurt Locker (locked B) with `7`, Chernobyl (A+B) with any value; no restart needed. The helper jar ships as `usb-files/BDJ-region-helper.jar` (copy it as `BDJ.jar` instead of the tool's).
- README restructured into one step-by-step flow, with separate Blu-ray and DVD value tables. The measured behaviour of each value is in `docs/region-bitmask-finding.md`.
- Added the reference section "Something not working? Send us these files": every file the tool writes to the USB, what each contains, and which to send for each symptom (stopped early, region reverted after a power-off, wrong values, DVD/EEPROM, per-disc helper, general). The US/UK protocol now saves `.config_dump.bin` per run (`dump-1.bin` …), because it is overwritten every run; `patch_result.txt` is documented for the helper; `USB-README.txt` lists the written files. Also corrected the helper's stick requirements (keep `run.sh` and `bd_region.txt` = `3`, because the helper jar also runs `run.sh` on each disc start) and replaced the build-error FAQ with the messages `build.py` actually prints.
- Tests: target selection 651 checks, pairwise 154, EEPROM 54, offset/write 30, US portability 6, TMO 4, agent scripts 8.

**v5.12 (documentation)** — Corrected the trigger-disc instructions. The script runs from a Blu-ray the player can currently play (same region as its setting, or region-free/A+B) that has BD-J. A disc from another region can stop at the region-error screen before its Java starts: on 28 Oct 2026, The Hurt Locker (B locked) at region A did not run the script; Chernobyl (A+B) did, after which The Hurt Locker played. The playback table now marks The Hurt Locker at `2` as tested.

**v5.11 (documentation)** — Corrected the DVD region 0 claim. Setting `dvd_region.txt` to `0` writes only the config file, and the firmware reads the DVD region from the hardware EEPROM at boot; a region-0 setting has not been verified to play discs from other regions on these players. v3.2 recorded region 0 failing, the EEPROM copy has never been written on any logged unit, and no DVD playback test exists for any value. The script is unchanged from v5.10; `DVD_EEPROM` is still the only way to write the EEPROM copy, and that path remains unverified. The Blu-ray ambiguity from 26 Oct is also closed: a locked region B disc (The Hurt Locker, Roadshow) refuses at `1` on the AU UB450, so the player has no own-region allowance; the Chernobyl disc that played at `1` must be region-free/A+B. `1` = A only and `2` = B only on both the AU UB450 and the EU UB150. The README now includes a playback examples table for the tested player.

**v5.10** — The DVD EEPROM write is now off by default. It is the only path that writes outside the config file, the device is identified by guessing, and it has never run on real hardware (every v5.9 log stops before it). It now requires an empty `DVD_EEPROM` file on the USB, is skipped when the config already holds the target, refuses to write when more than one device matches, and skips MTD partitions whose size `/proc/mtd` does not report. The config file write and RESTORE are unchanged.

**v5.9** — Works with the player's actual toolset. The rootfs has no `timeout`, no `od` and no `strings` (checked in the AU V127, UK V127 and US V113 firmware images), so earlier versions silently skipped every EEPROM step — the DVD hardware write never happened on any unit — and `diag.sh` reported blank model and region values. Both scripts now use a kill-after-N-seconds wrapper and `hexdump` (which the player does ship). Reported by a US DP-UB450P user (26 Oct 2026); the US region still reverts at boot, which is a separate, open issue.

**v5.8** — Blu-ray is now a region selector, not "region-free". The default is `BD_TARGET=1` (region A), and an optional `bd_region.txt` on the USB sets 1 (A), 2 (B) or 4 (C). Playback tests on a UB450GN (26 Oct 2026) showed the player treats the byte as a single region code: `1` plays region A, `2` plays region B, and `7` falls back to the player's own region (it did nothing).

- `bd_region.txt` and `dvd_region.txt` are read from the first line; leading zeros and Windows line endings are accepted. BD values outside 1-6 are rejected before anything is written (0, 7 and above). DVD values are validated 0–6, and an empty file skips the DVD change — previously 7–9 were written unchecked.
- RESTORE now works even when `bd_region.txt` or `dvd_region.txt` is invalid or left over from an older version.
- A run that skips the DVD change now logs `Config write VERIFIED: DVD skipped` instead of a false `MISMATCH`.
- Added the local target-selection tests (`tests/test_targets_pict.sh`, 66 PICT pairwise cases plus 24 seeded cases) and `CONF`/`USB` environment overrides for the test harness.

**v5.7** — Verifies the config write. After writing and syncing, the script reads both region bytes back and logs `Config write VERIFIED` (with the `dd` return code) or `Config write MISMATCH`. This separates a failed write from a value that changes later, which is what happens on some UK and US players.

**v5.6** — Added diagnostic checkpoints. Every key step now syncs a checkpoint to the log on the USB, so if the player kills the script early, the log shows exactly which step it reached. This helps debug players where the region change doesn't take effect. Also clarified that the trigger disc must use BD-Java (most major studio Blu-rays do; some boutique labels do not).

**v5.5** — Optimised for speed. Removed the web CLI probe (port 8383 is never available during disc playback — it was wasting 1–2 seconds on every run). Removed the secondary config file write. The config write now finishes in under a second, so the Blu-ray write is done before the player can kill the script.

**v5.4** — Fixed the script being killed before writing region values. The player's BD-Java runtime can kill the subprocess at any time, so the config file write now happens immediately after backup — before the web CLI probe and EEPROM scan. This means the Blu-ray write lands even if the script is killed early. Also reduced curl timeout from 2s to 1s.

**v5.3** — Fixed script hanging on some players during EEPROM/MTD device scanning. All `dd` reads and writes to hardware devices now have a 3-second timeout, so a non-responsive device is skipped instead of blocking forever. Also dumps `/proc/mtd` and device listing to the log before scanning, so diagnostic data is captured even if a device hangs. `diag.sh` device reads also have timeouts (5 seconds).

**v5.2** — Improved diagnostics: `diag.sh` now runs automatically every time (not just on failure), collects model name, firmware version, kernel info, country code, and current DVD/BD/IR region values from both the config file and the player's live settings. The log header now shows the script version and kernel. Verified that AU, UK, CAD, and US firmware all use identical BD-Java classes — `build.py` works with any of them.

**v5.1** — Fixed EEPROM detection on players that expose EEPROM through MTD devices (`/dev/mtd*`) instead of `/dev/eeprom_*`. v5 only searched for `/dev/eeprom_0` and `/dev/eeprom_3`, which don't exist on most UB450 units. The script now scans all MTD partitions (filtered by size < 256KB), cross-references the value at offset 0x200 against the config file's DVD region, and checks the IR region at 0x205 for extra safety. Also dumps `/dev/` listing and `/proc/mtd` to the log when no EEPROM is found, for easier debugging.

**v5** — DVD region support is back. Analysis of the player's firmware revealed why v3's config-file-only approach failed: the player reads the DVD region from EEPROM at every boot, overwriting the config file value. Blu-ray has no EEPROM copy, which is why it always worked. The script now writes the DVD region directly to EEPROM, and also tries the player's internal command interface first. Added `diag.sh` for collecting EEPROM and config diagnostics on untested models.

**v4** — Removed DVD region support. Writing the DVD region to the config file doesn't actually change DVD playback — the player reads the DVD region from somewhere else. This tool now only unlocks Blu-ray (all regions A+B+C), which is confirmed working. *(Later found not to work as described: `7` falls back to the player's own region — corrected in v5.8.)*

**v3.4** — Fixed DVD_REGION.txt parsing: comments on later lines were being picked up as the region number. Now only the first line is read.

**v3.3** — Added DVD_REGION.txt template with region table and instructions. Both `DVD_REGION` and `DVD_REGION.txt` filenames work.

**v3.2** — DVD region 0 ("region-free") doesn't work on these players — US DVDs and others were rejected. DVD now requires a `DVD_REGION` file on the USB with the region number (1-6) you want. If no file is present, the DVD region is left unchanged and only Blu-ray is unlocked. Blu-ray still gets all regions (A+B+C) as before. *(The A+B+C part was later disproved — see v5.8.)*

**v3.1** — Fixed a bug where the backup was overwritten before checking for RESTORE, so restoring would lose your original region values. Now the restore runs first, and re-running the script won't overwrite an existing backup if the player is already at the target values.

**v3** — Fixed `run.sh` failing on UB450 and UB150 when the player's busybox `od` doesn't support `-v -An -tx1` (produces no output, so both keys show "not found"). The primary offset detection now uses `strings -t d`, which is confirmed working on the player's busybox. Falls back to `od` hex search (macOS/GNU), then a `dd` byte-scan as last resort. `read_byte` also has multiple fallbacks (`od` → `hexdump` → `printf`). Tested on a real UB450GN config dump: `strings -t d` returns the correct byte offsets for both region keys.

**v2** — Fixed `run.sh` failing on both UB450 and UB150 with `unexpected key order (BD before DVD)`. The player's busybox `grep -b` reports the byte offset of the line start (always 0 for a binary file), not the match position, so both keys appeared at offset 0. Replaced `grep -boa` with an `od`-based hex search that works on any busybox. Also removed the assumption that the BD key comes after the DVD key in the config file, and added a config file dump to USB (`.config_dump.bin`) for easier debugging on untested models.

> **Disclaimer:**
> - This tool is intended for use on your own player with discs you legally own. It does not bypass copy protection — AACS, BD+, and Cinavia remain fully intact.
> - Region coding controls where a disc can be played, not whether it can be copied. In Australia, circumventing geographic market restrictions on non-game media is permitted under the Copyright Act 1968 (s 10(1)). Laws differ by country — check your local rules.
> - This software is provided as-is, without warranty. Use at your own risk. Modifying your player's configuration may void your warranty. Always back up your original settings (the script does this automatically).

## License

MIT
