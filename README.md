# DP-UB450 / UB150 — Blu-ray Region Switch

Play Blu-ray and DVD discs from other regions on a DP-UB450, DP-UB150 or
similar MediaTek-based player. No soldering, no permanent changes, fully
reversible.

> **Factory limitation — one Blu-ray region at a time.** There is no value
> that plays every region at once, and `7` is not "all regions". The per-disc
> helper plays locked A and B discs without restarting the player, but still
> one at a time. True simultaneous A+B needs modified player firmware, which
> this project does not provide.

To jump straight to it: values are in [Step 3](#3-prepare-the-usb-drive), the run steps in [Steps](#steps), and changing region later in [Switch region later](#switch-region-later).

## What you need

> Warning: you must be comfortable to run the command line on your machine e.g. using Windows prompt. If not, these steps might not be for you. So, please ask someone else to do it for you instead.

**Update your player's firmware first** (Setup → System → Firmware Update). The region change might not survive a future update, so get that out of the way before you start.

- **DP-UB450 or DP-UB150** (tested on UB450GN, Australia). May also work on UB154, UB159. See "Does this work on other models?" below
- **A USB drive** (any size, formatted as **FAT32** — most USB drives already are)
- **A computer** (Mac, Windows with WSL, or Linux)
- **A Blu-ray disc with BD-J that the player can currently play** — same region as its current setting, or a region-free/A+B disc. Most major-studio discs have BD-J; to check on a computer, open the disc and look for a `BDMV/JAR/` folder containing one or more `.jar` files (see "How do I check the disc has BD-J?" below). Do not rely on the disc from the other region you want to play: it can stop at the region-error screen before its Java starts, so the script never runs. If the script does not start, try another playable disc with BD-J.
- **The firmware update file** (`PANA_DVD.FRM`) — download it from the manufacturer's support site for the UB450 or UB150. You need the file, not to install the update
- **Python 3** (pre-installed on Mac and most Linux; [python.org](https://www.python.org/downloads/) for Windows)
- **unsquashfs** — to extract a file from the firmware:
  - macOS: `brew install squashfs`
  - Linux: `sudo apt install squashfs-tools` (often pre-installed)
  - Windows: use WSL (Windows Subsystem for Linux), then follow the Linux instructions

## Steps

### 1. Download

Clone or download the repository:

```sh
git clone https://github.com/hemmachat/ub450-region-switch.git
```

Or click **Code → Download ZIP** on the [repository page](https://github.com/hemmachat/ub450-region-switch) and unzip it.

### 2. Build BDJ.jar

Open a terminal (command prompt on Windows), go to the `build/` folder and run:

```sh
python3 build.py /path/to/PANA_DVD.FRM
```

Replace `/path/to/PANA_DVD.FRM` with the actual path to your downloaded firmware file. The script writes `usb-files/BDJ.jar` — that is the file you copy in Step 3.

The script will:
1. Extract the player's boot classes from the firmware
2. Set the debug flag (one byte change)
3. Add the region-change trigger
4. Output `BDJ.jar` into the `usb-files/` folder

You should see output ending with `Done.` and a SHA-256 hash.

### 3. Prepare the USB drive

Format your USB drive as **FAT32** (most USB drives already are).

Copy these files from the `usb-files/` folder to the **root** of the USB drive:

- `BDJ_DEBUG` (an empty file — don't open or edit it)
- `BDJ.jar` (about 1.3 MB — the file you built in step 2)
- `run.sh` (the region-change script)
- `bd_region.txt` — **edit line 1** to the value for the disc you want to play (table below): `1` = A, `2` = B, `4` = C. `3` is only for the per-disc helper; delete the file to use the default (1 = A).
- `dvd_region.txt` — ships with `1` (US), so the tool also sets the DVD region to US. **Make the file empty to leave the DVD region unchanged**, or put another number on line 1: 0 = free, 2 = Europe/Japan, 3 = SE Asia, 4 = Australia, 5 = Russia/India, 6 = China.
- `DVD_EEPROM` (optional, advanced — **create an empty file with this name** on the USB to enable the unverified hardware EEPROM write; it is not in `usb-files/`. See [What about DVDs?](#what-about-dvds))
- `diag.sh` (collects diagnostic data — always include this file)
- `USB-README.txt` (optional — this guide, for reference on the stick)

(Advanced: `BDJ-region-helper.jar` is the per-disc helper — it replaces
`BDJ.jar` on the stick; see [Play both regions without restarting the player](#play-both-regions-without-restarting-the-player-advanced).)

The USB drive should look like this:

```
USB drive (root)
├── BDJ_DEBUG
├── BDJ.jar
├── run.sh
├── bd_region.txt   (optional — 1=A, 2=B, 4=C; 3 for the per-disc helper)
├── dvd_region.txt  (default 1 = US; empty = no DVD change)
├── DVD_EEPROM      (optional — create an empty file; leave out normally)
├── diag.sh
└── USB-README.txt  (optional — this guide)
```

**Blu-ray (BD) discs** — the value goes in `bd_region.txt` (the advanced per-disc mode uses `psr20_value.txt` instead):

| Disc you want to play | Region | Value |
|---|---|---|
| US, Japan, Korea, South-East Asia | A | `1` |
| Australia, Europe, Africa, Oceania | B | `2` |
| Central/South Asia, Russia, China | C | `4` (not tested) |

A locked Blu-ray disc from another region shows its region message. `7` is not
"all regions": the player falls back to its own region, so on a region A
player it does not play region B discs. (In the per-disc helper below the
value is used as given, and `7` worked for The Hurt Locker.)

**DVD discs** — the value goes in `dvd_region.txt` (**main tool only**; there is
no per-disc mode for DVDs):

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

### 4. Run it

1. **Unplug the player's power cord** (or switch the socket off at the wall). Do not use the remote or standby.
2. **Plug the USB drive** into the player's USB port (front or rear — use whichever your model has)
3. **Plug the player back in, turn it on**, and wait for the home screen (no disc yet)
4. **Insert a Blu-ray with BD-J that the player can currently play** — the same region as its current setting, or a region-free/A+B disc (Chernobyl, A+B, was used in the 28 Oct 2026 test). It must be a Blu-ray, not a DVD. The script starts when the disc's Java application (its menu) starts, so **let the disc menu load**; if only the player's home screen appears, press **Top Menu** (or **Menu**) on the remote. Most major-studio discs have BD-J (Disney, Warner, Universal, etc); some boutique labels (Arrow, Criterion, etc) do not. A disc from another region may show a region message and never start its Java — the script did not run from that screen with The Hurt Locker on 28 Oct 2026.
5. **Wait about 30 seconds** after the disc menu appears — the region change happens in the background.
6. **If no `region_log.txt` appears on the USB afterwards, the script did not run** — try another disc the player can play (same region or region-free/A+B) that has BD-J.
7. **Unplug the player's power cord** (or switch the socket off at the wall). Do not use the remote. Leave it off for a few seconds.
8. **Remove the USB drive**
9. **Plug it back in and turn it on**

On the tested Australian player, the Blu-ray region is now the value in `bd_region.txt` (1 = A by default). DVD is set to US (region 1) because the shipped `dvd_region.txt` contains `1`; make the file empty if you do not want the DVD region changed. Check `region_log.txt` on the USB — the `Config write VERIFIED` line tells you the new values are in place. If you run the process again later, its `Before:` line shows whether they stuck.


> **Known limitation:** on some UK, US and EU units the Blu-ray region is written successfully but the player shows the original value again after a clean power-off (confirmed with v5.7 on a UK player, 26 Oct 2026). v5.7 and later log `Config write VERIFIED`; if the next run's `Before:` line shows the old value, the player replaced it. The steps for this tool unplug the player instead of using the remote, because a clean power-off lets those units write their old value back; an EU user confirmed that unplugging keeps the change, and the Australian player did not rewrite the value in the 27 Oct 2026 probe, so unplugging is harmless there. US and UK testers are confirming the one-time unplug flow (see [Help test US, UK and EU players](#help-test-us-uk-and-eu-players)).

### 5. Check it worked

Plug the USB drive back into your computer. The main file is **`region_log.txt`** (replaced on every run — if the script ran more than once, only the last run is in it; the `Started:` time tells you which one you are reading). It shows the original values, whether the write was verified, and how far the script got.

- **`Config write VERIFIED`** — the new values are in the config file. This is the important line for Blu-ray.
- **`REGION_FREE_OK.txt`** — the script reached the end. It contains the result line. This file can be missing if the player stopped the script early; that alone does not mean the region change failed.
- **`REGION_FREE_FAILED.txt`** — something went wrong. Check `region_log.txt` and the `diag_output/` folder on the USB for details — attach them to an issue if you need help.

The file `region_log.txt` has a full log of what happened, including your original region values (backed up automatically). The script also saves `.config_dump.bin` (a copy of the player's config file) on every run. It is overwritten each time, so copy it off the USB after each run if you are helping with diagnostics. The full list of files the tool writes, and which ones to send if something goes wrong, is in [Something not working? Send us these files](#something-not-working-send-us-these-files).

### 6. Test

Insert a disc from the region you set: with `bd_region.txt` = `1`, a region A disc; with `2`, a region B disc. A disc from any other region will show the region error (that is expected).

## Switch region later

**To change the Blu-ray region:** edit `bd_region.txt` on the USB drive — line 1: `1` (A), `2` (B) or `4` (C). Any other value is stored but the player uses its own region. `3` is written only by the per-disc helper, which needs it so the player does not block a disc of the other region. Delete the file to keep the default (1 = A).

**To change the DVD region:** edit `dvd_region.txt` on the USB drive — change the number on the first line to your desired region: 0 (region-free), 1 (US), 2 (Europe/Japan), 3 (SE Asia), 4 (Australia), 5 (Russia/India), or 6 (China). Delete the file to use the default (1 = US); make the file empty instead if you want to leave the DVD region unchanged. The new value is written to the config file; the second copy in the hardware EEPROM is **not** written unless you add a `DVD_EEPROM` file to the USB (see [What about DVDs?](#what-about-dvds)).

Both take effect the same way: run the tool again ([Step 4](#4-run-it)) and unplug the player.

**Blu-ray without a restart (advanced):** keep the USB in the player, put the value in `psr20_value.txt` and insert the disc — see [Play both regions without restarting the player](#play-both-regions-without-restarting-the-player-advanced).

Tested on a DP-UB450GN (Australia, firmware V127), 26-29 Oct 2026: Jigsaw
(locked A) plays with `1`; The Hurt Locker (locked B) plays with `2` or `7`;
Chernobyl (A+B) plays with any value. Other models: see
[Does this work on other models?](#does-this-work-on-other-models).

## Play both regions without restarting the player (advanced)

The steps above change which region the player is set to, and the player has
to restart before the change applies. This second way works per disc instead,
so switching is just a file edit:

- the player is set to `3` once (run the normal tool with `bd_region.txt` = `3`),
- a small `BDJ.jar` helper on the USB tells the player, about 10 seconds after
  a disc starts, which region to report to the disc. The value comes from
  `psr20_value.txt`.

The helper is shipped as `usb-files/BDJ-region-helper.jar` — copy it to the USB
as `BDJ.jar`, **replacing** the tool's `BDJ.jar`; only one of the two can be on
the stick at a time. It was built from the Australian V127 firmware; on another
model, rebuild it from your own firmware with `testing/inprocess-experiment/build_inprocess.py`.
Source: `testing/inprocess-experiment/RegionPatch.java`. Why this works, and
what `3` means, is in `docs/region-bitmask-finding.md`.

| Blu-ray disc | `psr20_value.txt` |
|---|---|
| Locked region A (US) | `1` |
| Region B (local) | `2`, or `7` (tested with The Hurt Locker) |
| Region C | `4` (not tested) |

Files on the stick for this mode: `BDJ_DEBUG`, the helper as `BDJ.jar`, and
`psr20_value.txt` — create a plain text file with the value on its first line.
Keep the normal tool files too if you still want to run it.

Tested on the Australian UB450: Jigsaw (locked A) plays with `1`, The Hurt
Locker (locked B) plays with `7`, Chernobyl (A+B) plays with any value. A
locked A disc needs exactly `1`; `7` is refused by that disc.

The helper writes **`patch_result.txt`** on the stick each time a disc starts,
with the region it read before and after the change (`get20 before=`,
`value file=`, `get20 after=`). If a disc is refused or the screen stays blank,
that file plus your `psr20_value.txt` is what to send (see
[Something not working?](#something-not-working-send-us-these-files)).

### Steps to switch region

1. Eject the disc.
2. Pull the USB out of the player.
3. On a computer, open `psr20_value.txt` and set the first line to the value
   from the table above. Save the file.
4. Eject the USB from the computer and put it back in the player.
5. Insert the disc. The film starts about 10 seconds later.

No power cycle is needed. The value is read when the disc starts, so a change
applies to the next disc you insert.

### Blu-ray and DVD switch differently

**Blu-ray (per disc, no restart):** follow [Steps to switch region](#steps-to-switch-region)
above — change `psr20_value.txt`, reinsert the stick and the disc.

**DVD (config write, needs the unplug):**

1. Put the USB in the player with `dvd_region.txt` set to the wanted region
   (0 = free, 1 = US, 2 = Europe, 3 = SE Asia, 4 = Australia, 5 = Russia/India,
   6 = China).
2. Insert a Blu-ray with BD-J that the player can play — that is what runs
   `run.sh`; a DVD cannot trigger it.
3. Wait about 30 seconds. `region_log.txt` on the USB should say
   `Config write VERIFIED: … DVD=…`.
4. Unplug the player at the wall (not the remote), then power it on.
5. Insert the DVD.

If the DVD region still shows the old value after that, the player is taking
it from the hardware EEPROM — that is the opt-in `DVD_EEPROM` write, which is
not verified yet.

### Limits

- The USB must stay in the player. Without it the player uses its own region.
- The helper only runs for Blu-ray discs that have BD-J. DVDs are not affected:
  their region still comes from the normal tool run (plus, on some units,
  the EEPROM copy) and needs the unplug.
- It sets one region at a time: the player still cannot play an A disc and a
  B disc at the same time without changing the value.
- The player must be set to `3` first (run the region tool once with
  `bd_region.txt` = `3`).

## How to undo it

If you ever want to go back to your original region:

1. Create an empty file called **`RESTORE`** on the USB drive (next to the other files)
2. Repeat step 4 above: unplug the player, plug in the USB, insert the disc, wait, unplug it again, remove the USB, then plug it back in and turn it on

For the per-disc region helper, undoing is simpler: pull the USB out — with no stick the player uses its own region again.

The player will restore your original region from the backup that was saved during step 4 (including the EEPROM DVD region, if it was changed). The backup is created on the first run of the tool — if you ran it before, the backup holds the values from that first run, not necessarily the factory values.

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
| The per-disc helper refuses a disc | `patch_result.txt` (written on the stick each time a disc starts), plus the current `bd_region.txt` and `psr20_value.txt`. |
| Nothing above explains it | The `diag_output/` folder — see below. |

**`diag_output/`** comes from a deeper read-only check. Rename `run.sh` to
`run-region.sh`, rename `diag.sh` to `run.sh`, and do one more run. The folder
contains `diag_log.txt`, copies of the player's config files, small dumps of the
storage devices (`*.bin`) and `strace_bdpprog.txt`. It only reads; nothing is
written.

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

### How do I check the disc has BD-J?

1. Put the disc in a computer with a Blu-ray drive.
2. Open the disc and go into the `BDMV` folder.
3. Look for a `JAR` folder containing one or more `.jar` files.
4. If `BDMV/JAR` is missing or empty, the disc has no BD-J and cannot start the script — use a different disc.

No Blu-ray drive? If you have a disc image or backup folder, MakeMKV or any Blu-ray tool shows the same `BDMV/JAR` structure. The disc menu must also actually start on the player: if only the player's home screen appears, press **Top Menu** on the remote.

### Can I leave the USB in during normal use?

It depends which mode you are using:

- **Normal region change:** remove the USB afterwards. The script only has to
  run once, and `BDJ_DEBUG` changes how the player loads disc software.
- **Per-disc region helper** (see above): the USB must **stay in the player**,
  because the helper runs every time a disc starts.

If a disc ever shows a blank screen, remove the USB and power-cycle the player;
with no stick the player behaves normally.

### Will this survive a firmware update?

Unknown. If a firmware update resets the region, repeat the process.

### The region went back to the old value after a reboot

v5.7 and later log `Config write VERIFIED` when the new value is in the config file. If the next run's `Before:` line shows the old value, the player wrote its own copy of the settings back over the file. This can happen at a clean power-off on some UK, US and EU units (confirmed on a UK player, 26 Oct 2026); the Australian unit has not shown it, but the unplug step is safe there too. **Unplug the player instead of using the remote after the run** — an EU user confirmed that keeps the change, and the tool's closing log says the same. Send `region_log.txt` and `.config_dump.bin` from both runs, plus your model and firmware version — the full list is in [Something not working?](#something-not-working-send-us-these-files). US and UK testers are also checking whether a normal value survives — see [Help test US, UK and EU players](#help-test-us-uk-and-eu-players).

### An older version wrote `7` — why did a disc play then?

`7` is not an "all regions" value on stock firmware; the player falls back to its own region. If a disc played, region A was actually loaded: either the value had been set to `1` by an earlier test or manual run, or the player was still using the region it loaded at startup — a written value only takes effect after the next power cycle. The current version writes `1` explicitly; the `Before:` line in `region_log.txt` shows the value that was in the file.

### Can this make my player region-free?

This tool switches the player's Blu-ray region; it does not unlock all regions.
For playing locked A and B discs without restarting the player, see
[Can the player be made region-free (play A and B at the same time)?](#can-the-player-be-made-region-free-play-a-and-b-at-the-same-time).
True simultaneous A+B playback needs modified player firmware, which this
project does not provide.

### Does this work on other models?

It was built and tested on a DP-UB450GN (Australia, firmware V127). The script finds the region settings dynamically, so it adapts to different firmware layouts.

**UB150, UB154, UB159** — likely to work. Same firmware family (unencrypted `PANA_DVD.FRM`), same MediaTek MT8581 platform. Download your model's firmware update and run `build.py` with it. One UB150EF unit reported that at `1` only region A discs play; set `2` to return to region B.

**UB420, UB820, UB9000** — unknown. These models use encrypted firmware (`PANAEUSB.FRM`), so `build.py` cannot extract the boot classes from it. You would need to build BDJ.jar using a UB450 or UB150 firmware file instead, and it is unconfirmed whether the result works on these players. If you own one of these models and want to try, open an issue first so we can coordinate.

If you try it on a different model, please report back by opening an issue.

### Is this safe? Can it brick my player?

The process changes the region settings in the player's configuration and, only when you add a `DVD_EEPROM` file, the DVD region in the hardware memory. It does not modify the firmware. The original values are backed up to the USB drive, and you can restore them at any time (see "How to undo it"). In the worst case, a factory reset (Setup → System → Default Settings) may restore the original region (not tested on this player).

The steps switch the player off at the wall on purpose: it stops the player saving its old settings over the new region. That is safe outside a firmware update — just don't do it while the player is installing firmware.

### The build script says "wrong firmware layout"

The script checks that the config file on your player matches the expected format before writing anything. If your player has a different firmware version with a different layout, it will stop safely. Open an issue with your model and firmware version.

### What about DVDs?

DVD regions are supported as of v5. The player keeps the DVD region in the config file and in a second copy in the hardware EEPROM, and it reads the EEPROM copy at every boot. The script always writes the config file; it writes the EEPROM **only when a `DVD_EEPROM` file (empty) is on the USB**, because the EEPROM step is the only write outside the config file and it has not been verified on real hardware yet. By default the tool sets DVD to region 1 (US); put a `dvd_region.txt` file on the USB to choose 0–6.

The EEPROM step also requires that the value in the config file differs from the one you are setting, that exactly one device matches, and that `/proc/mtd` gives a size for every MTD partition it considers. If more than one device matches, it refuses to write and logs `EEPROM write REFUSED`. The matching device is backed up to `.eeprom_dvd_backup.bin` before any write. If you enable `DVD_EEPROM`, check `region_log.txt`: `EEPROM write SUCCEEDED` means it verified, `REFUSED` means it stopped safely. If the DVD region still doesn't stick, send the `diag_output/` folder — with a verified EEPROM write we still need to confirm the correct device on more models. The files to send are listed in [Something not working?](#something-not-working-send-us-these-files).

DVD uses one region number (0–6); `0` is the region-free value. This is **not verified** on these players: the firmware reads the DVD region from the hardware EEPROM at boot, and the EEPROM copy is only written when the advanced `DVD_EEPROM` file is on the USB. Setting `dvd_region.txt` to `0` changes only the config file, which the player may override at boot. A few older RCE DVDs also refuse a region-0 player.

### Can the player be made region-free (play A and B at the same time)?

Not at the same time on stock firmware. A locked disc insists on its own
region, so one setting cannot play an A disc and a B disc at once.

What does work, without restarting the player: the helper described in
[Play both regions without restarting the player](#play-both-regions-without-restarting-the-player-advanced)
lets each disc see its own region — Jigsaw (locked A) plays with `1`, The Hurt
Locker (locked B) plays with `7`. Still one at a time, but no restart. True
A+B at the same time needs modified player firmware, which this project does
not provide. The technical reason is in `docs/region-bitmask-finding.md`.

## How it works

The player has a BD-Java debug mode that loads boot classes from a USB drive. The build script extracts the boot classes from your firmware file, makes a small change to allow running a shell script, and packages the result as `BDJ.jar`. When you insert a disc with the USB plugged in, the script runs and does two things:

1. **Config file write** — writes both DVD and BD regions to the config file. This works on the tested Australian player; on some UK, US and EU units the value does not survive a reboot (under investigation). DVD also needs the EEPROM write below to survive a reboot.
2. **EEPROM direct write** — writes the DVD region to the hardware EEPROM at offset 0x200, where the firmware reads it at every boot. Off unless a `DVD_EEPROM` file is on the USB; see [What about DVDs?](#what-about-dvds).

The Blu-ray region is set to the value in `bd_region.txt` (1 = A by default), not to "all regions": the player stores any byte, but for values it does not recognise as a region it uses its own region instead. The per-disc helper described above exploits that: with the byte at `3` the player starts a disc of either region, and the helper sets the region the disc's Java sees. The DVD region defaults to 1 (US) unless overridden by a `dvd_region.txt` file on the USB. The original values are backed up to the USB first. No firmware is modified. No network connection is needed.

## Building from source

The `build/build.py` script does everything:

1. Extracts the boot classes from the firmware update file
2. Applies the modifications needed to run the region-change script
3. Packages everything into a standard JAR

It requires Python 3 and `unsquashfs`. If you already have `BDJ.czf` extracted, you can pass it directly instead of the firmware file.

No proprietary code is included in this repository. The build script operates on files you obtain from your own player's firmware.

## Credits

Region codes: the player accepts `1` (A), `2` (B) and `4` (C) as single region codes. The values were checked against the [Blu-ray specification (PSR 20)](https://videolan.videolan.me/libbluray/player__settings_8h.html) via libbluray, but playback tests on a UB450GN (26 Oct 2026) show stock firmware does **not** treat the byte as a PSR 20 bitmask: `7` falls back to the player's own region. DVD values follow the [DVD region code standard](https://en.wikipedia.org/wiki/DVD_region_code). The BD-Java debug mode is a standard feature of the CVM runtime used in MediaTek-based Blu-ray players.

## Changelog

**v5.13 (29 Oct 2026)** — Blu-ray values and documentation.

- `bd_region.txt` now accepts `3`, `5` and `6` as well as `1`, `2` and `4`. The player stores any of them but uses its own region for values it does not recognise; `3` is the value the per-disc helper needs. The error message lists `1`/`2`/`4` (and `3` for the helper) only.
- Fixed a shell portability bug: the MTD size parsing used a `case` pattern inside `$( )`, which bash 3.2 rejects, so `bash -n` failed on the script. Rewritten without `case`; `tests/test_us_portability.sh` now checks `bash -n`.
- Documented the per-disc Blu-ray helper (README, `USB-README.txt`): with the region set to `3`, a BD-J jar sets the region register from `psr20_value.txt` about 10 seconds after a disc starts. Tested 29 Oct 2026: Jigsaw (locked A) with `1`, The Hurt Locker (locked B) with `7`, Chernobyl (A+B) with any value; no restart needed. The helper jar ships as `usb-files/BDJ-region-helper.jar` (copy it as `BDJ.jar` instead of the tool's).
- README restructured into one step-by-step flow, with separate Blu-ray and DVD value tables. The measured behaviour of each value is in `docs/region-bitmask-finding.md`.
- Added the reference section "Something not working? Send us these files": every file the tool writes to the USB, what each contains, and which to send for each symptom (stopped early, region reverted after a power-off, wrong values, DVD/EEPROM, per-disc helper, general). The US/UK protocol now saves `.config_dump.bin` per run (`dump-1.bin` …), because it is overwritten every run; `patch_result.txt` is documented for the helper; `USB-README.txt` lists the written files.
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
