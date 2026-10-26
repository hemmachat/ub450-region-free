# DP-UB450 / UB150 — Blu-ray Region Switch

Switch your **Blu-ray and DVD region** on a DP-UB450, DP-UB150, or similar MediaTek-based player. No soldering, no permanent changes. Fully reversible.

The tool sets the player to **one Blu-ray region** (1 = A, 2 = B, 4 = C). Stock firmware has no "all regions" value: other values, including `7`, fall back to the player's own region. Region A and region B are separate settings — set `1` to play A discs, `2` to switch back to region B. Whether a B disc also plays while the player is set to `1` is not confirmed; on the EU player tested, it did not.

> **Factory limitation — the player cannot be made region-free.** As manufactured, the firmware enforces **one Blu-ray region at a time**. This tool changes which one; there is no value that enables A+B+C, and `7` is not an "all regions" code (the player falls back to its own region). True region-free playback requires modified player firmware, which this project does not provide.

Tested on a DP-UB450GN (Australia) with firmware V127 - 26 Oct 2026. See "Does this work on other models?" below for UB150, UB154, UB159, UB820, and UB9000.

> **Known limitation:** on some UK, US and EU units the Blu-ray region is written successfully but the player shows the original value again after a reboot (confirmed with v5.7 on a UK player, 26 Oct 2026). v5.7 and later log `Config write VERIFIED`; if the next run's `Before:` line shows the old value, the player reset it. The steps below unplug the player instead of using the remote, because a normal power-off lets some units rewrite the old value. An EU user confirmed that unplugging keeps the change; the UK is still under investigation.

> **Disclaimer:**
> - This tool is intended for use on your own player with discs you legally own. It does not bypass copy protection — AACS, BD+, and Cinavia remain fully intact.
> - Region coding controls where a disc can be played, not whether it can be copied. In Australia, circumventing geographic market restrictions on non-game media is permitted under the Copyright Act 1968 (s 10(1)). Laws differ by country — check your local rules.
> - This software is provided as-is, without warranty. Use at your own risk. Modifying your player's configuration may void your warranty. Always back up your original settings (the script does this automatically).

## What you need

> Warning: you must be comfortable to run the command line on your machine e.g. using Windows prompt. If not, these steps might not be for you. So, please ask someone else to do it for you instead.

**Update your player's firmware first** (Setup → System → Firmware Update). The region change might not survive a future update, so get that out of the way before you start.

- **DP-UB450 or DP-UB150** (tested on UB450GN, Australia). May also work on UB154, UB159. See "Does this work on other models?" below
- **A USB drive** (any size, formatted as **FAT32** — most USB drives already are)
- **A computer** (Mac, Windows with WSL, or Linux)
- **A Blu-ray disc with BD-J** (to trigger the process) — most major-studio discs. To check on a computer, open the disc and look for a `BDMV/JAR/` folder containing one or more `.jar` files (see "How do I check the disc has BD-J?" below). If the script does not start, try a disc from a different region than the player's current one.
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

Replace `/path/to/PANA_DVD.FRM` with the actual path to your downloaded firmware file.

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
- `BDJ.jar` (about 1.2 MB — the file you built in step 2)
- `run.sh` (the region-change script)
- `bd_region.txt` (optional — 1 = A, 2 = B, 4 = C; defaults to 1 = A if missing)
- `dvd_region.txt` (optional — edit the number on line 1 to choose your DVD region; defaults to 1 = US if missing)
- `diag.sh` (collects diagnostic data — always include this file)
- `USB-README.txt` (optional — this guide, for reference on the stick)

The USB drive should look like this:

```
USB drive (root)
├── BDJ_DEBUG
├── BDJ.jar
├── run.sh
├── bd_region.txt   (optional — 1=A, 2=B, 4=C)
├── dvd_region.txt  (optional — edit to change DVD region)
├── diag.sh
└── USB-README.txt  (optional — this guide)
```

### 4. Run it

1. **Unplug the player's power cord** (or switch the socket off at the wall). Do not use the remote or standby.
2. **Plug the USB drive** into the player's USB port (front or rear — use whichever your model has)
3. **Plug the player back in, turn it on**, and wait for the home screen (no disc yet)
4. **Insert a Blu-ray with BD-J** — for example the disc from the other region you want to play. It must be a Blu-ray, not a DVD. The script starts when the disc's Java application (its menu) starts, so **let the disc menu load**; if only the player's home screen appears, press **Top Menu** (or **Menu**) on the remote. Most major-studio discs have BD-J (Disney, Warner, Universal, etc); some boutique labels (Arrow, Criterion, etc) do not. If the player shows a region message instead of the menu, that is normal for a disc from another region — the script can still run from that screen.
5. **Wait about 30 seconds** after the disc menu (or the region message) appears — the region change happens in the background.
6. **If no `region_log.txt` appears on the USB afterwards, the script did not run** — try another disc (a disc from a different region works most reliably).
7. **Unplug the player's power cord** (or switch the socket off at the wall). Do not use the remote. Leave it off for a few seconds.
8. **Remove the USB drive**
9. **Plug it back in and turn it on**

On the tested Australian player, the Blu-ray region is now the value in `bd_region.txt` (1 = A by default). DVD is set to US (region 1) by default. Check `region_log.txt` on the USB — the `Config write VERIFIED` line tells you the new values are in place. If you run the process again later, its `Before:` line shows whether they stuck. To play your own-region discs again, set `bd_region.txt` to `2` and run the tool once more.

**To change the Blu-ray region**, edit `bd_region.txt` on the USB drive — line 1: `1` (A), `2` (B) or `4` (C). Other values, including `7`, are rejected or fall back to the player's own region. Delete the file to keep the default (1 = A).

**To change the DVD region**, edit `dvd_region.txt` on the USB drive — change the number on the first line to your desired region: 0 (region-free), 1 (US), 2 (Europe/Japan), 3 (SE Asia), 4 (Australia), 5 (Russia/India), or 6 (China). Delete the file to keep the default (1 = US).

### 5. Check it worked

Plug the USB drive back into your computer. The main file is **`region_log.txt`** (replaced on every run). It shows the original values, whether the write was verified, and how far the script got.

- **`Config write VERIFIED`** — the new values are in the config file. This is the important line for Blu-ray.
- **`REGION_FREE_OK.txt`** — the script reached the end. It contains the result line. This file can be missing if the player stopped the script early; that alone does not mean the region change failed.
- **`REGION_FREE_FAILED.txt`** — something went wrong. Check `region_log.txt` and the `diag_output/` folder on the USB for details — attach them to an issue if you need help.

The file `region_log.txt` has a full log of what happened, including your original region values (backed up automatically). The script also saves `.config_dump.bin` (a copy of the player's config file) on every run. It is overwritten each time, so copy it off the USB after each run if you are helping with diagnostics.

### 6. Test

Insert a disc from the region you set: with `bd_region.txt` = `1`, a region A disc; with `2`, a region B disc. A disc from any other region will show the region error (that is expected).

## How to undo it

If you ever want to go back to your original region:

1. Create an empty file called **`RESTORE`** on the USB drive (next to the other files)
2. Repeat step 4 above: unplug the player, plug in the USB, insert the disc, wait, unplug it again, remove the USB, then plug it back in and turn it on

The player will restore your original region from the backup that was saved during step 4 (including the EEPROM DVD region, if it was changed). The backup is created on the first run of the tool — if you ran it before, the backup holds the values from that first run, not necessarily the factory values.

## FAQ

### Which USB port should I use?

Use whichever USB port your player has. The UB450 has one on the front; other models may have front and rear ports. Either works.

### The screen goes blank and stays blank

The disc's menu software is loading from the USB. Wait 30–60 seconds. If it stays blank for more than 2 minutes, remove the USB, unplug the player, plug it back in and turn it on.

### How do I check the disc has BD-J?

1. Put the disc in a computer with a Blu-ray drive.
2. Open the disc and go into the `BDMV` folder.
3. Look for a `JAR` folder containing one or more `.jar` files.
4. If `BDMV/JAR` is missing or empty, the disc has no BD-J and cannot start the script — use a different disc.

No Blu-ray drive? If you have a disc image or backup folder, MakeMKV or any Blu-ray tool shows the same `BDMV/JAR` structure. The disc menu must also actually start on the player: if only the player's home screen appears, press **Top Menu** on the remote.

### Can I leave the USB in during normal use?

**No.** Remove the USB after the process is done. The `BDJ_DEBUG` file changes how the player loads disc software, which can cause blank screens.

### Will this survive a firmware update?

Unknown. If a firmware update resets the region, repeat the process.

### The region went back to the old value after a reboot

v5.7 and later log `Config write VERIFIED` when the new value is in the config file. If the next run's `Before:` line shows the old value, the player changed it after the write. This happens on some UK, US and EU units (confirmed on a UK player, 26 Oct 2026) and is under investigation. Send `region_log.txt` and `.config_dump.bin` from both runs, plus your model and firmware version. Also copy `diag.sh` over `run.sh` on the USB and run once more — it only reads — and send the `diag_output` folder it creates.

### An older version wrote `7` — why did a disc play then?

`7` is not an "all regions" value on stock firmware; the player falls back to its own region. If a disc played, region A was actually loaded: either the value had been set to `1` by an earlier test or manual run, or the player was still using the region it loaded at startup — a written value only takes effect after the next power cycle. The current version writes `1` explicitly; the `Before:` line in `region_log.txt` shows the value that was in the file.

### Can this make my player region-free?

No. The factory firmware accepts **one Blu-ray region at a time**. This tool switches that region (1 = A, 2 = B, 4 = C) — it does not unlock all regions, and `7` falls back to the player's own region. Set the region of the discs you want to watch, run the tool, and switch back to your own region when you are done (2 on a B player, 1 on an A player). True region-free playback needs modified player firmware, which this project does not provide or install.

DVD is different: DVD region 0 (region-free) works for most DVDs — set `dvd_region.txt` to `0`. A few older RCE DVDs may still refuse a region-0 player.

### Does this work on other models?

It was built and tested on a DP-UB450GN (Australia, firmware V127). The script finds the region settings dynamically, so it adapts to different firmware layouts.

**UB150, UB154, UB159** — likely to work. Same firmware family (unencrypted `PANA_DVD.FRM`), same MediaTek MT8581 platform. Download your model's firmware update and run `build.py` with it. One UB150EF unit reported that at `1` only region A discs play; set `2` to return to region B.

**UB420, UB820, UB9000** — unknown. These models use encrypted firmware (`PANAEUSB.FRM`), so `build.py` cannot extract the boot classes from it. You would need to build BDJ.jar using a UB450 or UB150 firmware file instead, and it is unconfirmed whether the result works on these players. If you own one of these models and want to try, open an issue first so we can coordinate.

If you try it on a different model, please report back by opening an issue.

### Is this safe? Can it brick my player?

The process changes region bytes in the player's configuration file and EEPROM. It does not modify the firmware. The original values are backed up to the USB drive, and you can restore them at any time (see "How to undo it"). In the worst case, a factory reset (Setup → System → Default Settings) should restore the original region.

The steps switch the player off at the wall on purpose: it stops the player saving its old settings over the new region. That is safe outside a firmware update — just don't do it while the player is installing firmware.

### The build script says "wrong firmware layout"

The script checks that the config file on your player matches the expected format before writing anything. If your player has a different firmware version with a different layout, it will stop safely. Open an issue with your model and firmware version.

### What about DVDs?

DVD regions are now supported as of v5. The player stores the DVD region in EEPROM as well as the config file, so the script writes to both. By default it sets DVD to region 1 (US). To choose a different region, put a `dvd_region.txt` file on the USB with the region number (0–6).

If the DVD region didn't change after running the script, your player's EEPROM device might be different. Check the `diag_output/` folder on the USB and open an issue with it — this will help identify the right device.

## How it works

The player has a BD-Java debug mode that loads boot classes from a USB drive. The build script extracts the boot classes from your firmware file, makes a small change to allow running a shell script, and packages the result as `BDJ.jar`. When you insert a disc with the USB plugged in, the script runs and does two things:

1. **Config file write** — writes both DVD and BD regions to the config file. This works on the tested Australian player; on some UK, US and EU units the value does not survive a reboot (under investigation). DVD also needs the EEPROM write below to survive a reboot.
2. **EEPROM direct write** — writes the DVD region to the hardware EEPROM at offset 0x200, where the firmware reads it at every boot

The Blu-ray region is set to the value in `bd_region.txt` (1 = A by default), not to "all regions": stock firmware treats the byte as a single region code and other values, including `7`, fall back to the player's own region. The DVD region defaults to 1 (US) unless overridden by a `dvd_region.txt` file on the USB. The original values are backed up to the USB first. No firmware is modified. No network connection is needed.

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

**v5.8** — Blu-ray is now a region selector, not "region-free". The default is `BD_TARGET=1` (region A), and an optional `bd_region.txt` on the USB sets 1 (A), 2 (B) or 4 (C). Playback tests on a UB450GN (26 Oct 2026) showed the player treats the byte as a single region code: `1` plays region A, `2` plays region B, and `7` falls back to the player's own region (it did nothing).

- `bd_region.txt` and `dvd_region.txt` are read from the first line; leading zeros and Windows line endings are accepted. BD values other than 1/2/4 are rejected before anything is written. DVD values are validated 0–6, and an empty file skips the DVD change — previously 7–9 were written unchecked.
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

## License

MIT
