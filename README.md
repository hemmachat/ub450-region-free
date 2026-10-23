# DP-UB450 / UB150 — Blu-ray Region-Free

Play **Blu-rays from any region** on your DP-UB450, DP-UB150, or similar MediaTek-based player. No soldering, no permanent changes. Fully reversible.

Tested on a DP-UB450GN (Australia) with firmware V127 - Sep 10, 2026. See "Does this work on other models?" below for UB150, UB154, UB159, UB820, and UB9000.

> **Disclaimer:**
> - This tool is intended for use on your own player with discs you legally own. It does not bypass copy protection — AACS, BD+, and Cinavia remain fully intact.
> - Region coding controls where a disc can be played, not whether it can be copied. In Australia, circumventing geographic market restrictions on non-game media is permitted under the Copyright Act 1968 (s 10(1)). Laws differ by country — check your local rules.
> - This software is provided as-is, without warranty. Use at your own risk. Modifying your player's configuration may void your warranty. Always back up your original settings (the script does this automatically).

## What you need

> Warning: you must be comfortable to run the command line on your machine e.g. using Windows prompt. If not, these steps might not be for you. So, please ask someone else to do it for you instead.

**Update your player's firmware first** (Setup → System → Firmware Update). The region change might not survive a future update, so get that out of the way before you start.

- **DP-UB450 or DP-UB150** (tested on UB450GN, Australia). May also work on UB154, UB159. See "Does this work on other models?" below
- **A USB drive** (any size, formatted as FAT32 — most USB drives already are)
- **A computer** (Mac, Windows with WSL, or Linux)
- **Any Blu-ray disc** (to trigger the process — the region doesn't matter, use one you already own)
- **The firmware update file** (`PANA_DVD.FRM`) — download it from the manufacturer's support site for the UB450 or UB150. You need the file, not to install the update
- **Python 3** (pre-installed on Mac and most Linux; [python.org](https://www.python.org/downloads/) for Windows)
- **unsquashfs** — to extract a file from the firmware:
  - macOS: `brew install squashfs`
  - Linux: `sudo apt install squashfs-tools` (often pre-installed)
  - Windows: use WSL (Windows Subsystem for Linux), then follow the Linux instructions

## Steps

### 1. Download

Download the latest release zip from the [Releases page](https://github.com/hemmachat/ub450-region-free/releases) and unzip it.

### 2. Build BDJ.jar

Open a terminal (command prompt on Windows), go to the `build/` folder inside the unzipped folder from step 1, and run:

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

Copy these three files from the `usb-files/` folder (inside the folder you unzipped in step 1) to the **root** of the USB drive:

- `BDJ_DEBUG` (an empty file — don't open or edit it)
- `BDJ.jar` (about 1.2 MB — the file you built in step 2)
- `run.sh` (a small text file)

The USB drive should look like this:

```
USB drive (root)
├── BDJ_DEBUG
├── BDJ.jar
└── run.sh
```

### 4. Run it

1. **Turn off** the player completely (not standby — press and hold power until it shuts down)
2. **Plug the USB drive** into the player's USB port (front or rear — use whichever your model has)
3. **Turn on** the player and wait for the home screen (no disc yet)
4. **Insert a Blu-ray disc** — it must be a Blu-ray, not a DVD. Most commercial Blu-rays work. The disc triggers the BD-Java runtime, which loads the region-change script from the USB
5. **(Very important) Wait for the screen to go blank for a moment** — this means the player is loading the script from USB. If the disc menu appears without a blank screen, the script didn't trigger — try a different disc. **You need the disc menu to load to run the script. If the disc menu did not load, you need to open it manually e.g. press "Top Menu" button on the remote.**
6. **Wait for the disc menu to fully load**, then wait another **10 seconds**. The region change happens in the background while the disc loads. 
7. **Power off** the player with the remote
8. **Remove the USB drive**
9. **Power on** the player

Your Blu-ray region is now unlocked (all regions). Check `region_log.txt` on the USB for details.

### 5. Check it worked

Plug the USB drive back into your computer. You should see a new file on the USB:

- **`REGION_FREE_OK.txt`** — it worked. You can now play Blu-rays from any region.
- **`REGION_FREE_FAILED.txt`** — something went wrong. Check `region_log.txt` on the USB for details.

The file `region_log.txt` has a full log of what happened, including your original region values (backed up automatically).

### 6. Test

Insert a Blu-ray from a different region. It should play without any region error.

## How to undo it

If you ever want to go back to your original region:

1. Create an empty file called **`RESTORE`** on the USB drive (next to the other files)
2. Repeat step 4 above (plug USB, insert disc, wait, power off, remove USB, power on)

The player will restore your original region from the backup that was saved during step 4.

## FAQ

### Which USB port should I use?

Use whichever USB port your player has. The UB450 has one on the front; other models may have front and rear ports. Either works.

### The screen goes blank and stays blank

The disc's menu software is loading from the USB. Wait 30–60 seconds. If it stays blank for more than 2 minutes, remove the USB and power cycle the player.

### Can I leave the USB in during normal use?

**No.** Remove the USB after the process is done. The `BDJ_DEBUG` file changes how the player loads disc software, which can cause blank screens.

### Will this survive a firmware update?

Unknown. If a firmware update resets the region, repeat the process.

### Does this work on other models?

It was built and tested on a DP-UB450GN (Australia, firmware V127). The script finds the region settings dynamically, so it adapts to different firmware layouts.

**UB150, UB154, UB159** — likely to work. Same firmware family (unencrypted `PANA_DVD.FRM`), same MediaTek MT8581 platform. Download your model's firmware update and run `build.py` with it.

**UB420, UB820, UB9000** — unknown. These models use encrypted firmware (`PANAEUSB.FRM`), so `build.py` cannot extract the boot classes from it. You would need to build BDJ.jar using a UB450 or UB150 firmware file instead, and it is unconfirmed whether the result works on these players. If you own one of these models and want to try, open an issue first so we can coordinate.

If you try it on a different model, please report back by opening an issue.

### Is this safe? Can it brick my player?

The process changes one byte in a configuration file on the player's internal storage. It does not modify the firmware. The original values are backed up to the USB drive, and you can restore them at any time. In the worst case, a factory reset (Setup → System → Default Settings) should restore the original region.

### The build script says "wrong firmware layout"

The script checks that the config file on your player matches the expected format before writing anything. If your player has a different firmware version with a different layout, it will stop safely. Open an issue with your model and firmware version.

### What about DVDs?

This tool only unlocks **Blu-ray** regions. DVD region changes don't work with this method — the player stores the DVD region in a way that the config file alone can't change.

## How it works

The player has a BD-Java debug mode that loads boot classes from a USB drive. The build script extracts the boot classes from your firmware file, makes a small change to allow running a shell script, and packages the result as `BDJ.jar`. When you insert a disc with the USB plugged in, the script runs and changes the Blu-ray region byte in the player's configuration file to allow all regions (A+B+C). The original values are backed up to the USB first. No firmware is modified — only a config file on the player's internal storage. No network connection is needed.

## Building from source

The `build/build.py` script does everything:

1. Extracts the boot classes from the firmware update file
2. Applies the modifications needed to run the region-change script
3. Packages everything into a standard JAR

It requires Python 3 and `unsquashfs`. If you already have `BDJ.czf` extracted, you can pass it directly instead of the firmware file.

No proprietary code is included in this repository. The build script operates on files you obtain from your own player's firmware.

## Credits

Region code values confirmed against the [Blu-ray specification (PSR 20)](https://videolan.videolan.me/libbluray/player__settings_8h.html) via libbluray and the [DVD region code standard](https://en.wikipedia.org/wiki/DVD_region_code). The BD-Java debug mode is a standard feature of the CVM runtime used in MediaTek-based Blu-ray players.

## Changelog

**v4** — Removed DVD region support. Writing the DVD region to the config file doesn't actually change DVD playback — the player reads the DVD region from somewhere else. This tool now only unlocks Blu-ray (all regions A+B+C), which is confirmed working.

**v3.4** — Fixed DVD_REGION.txt parsing: comments on later lines were being picked up as the region number. Now only the first line is read.

**v3.3** — Added DVD_REGION.txt template with region table and instructions. Both `DVD_REGION` and `DVD_REGION.txt` filenames work.

**v3.2** — DVD region 0 ("region-free") doesn't work on these players — US DVDs and others were rejected. DVD now requires a `DVD_REGION` file on the USB with the region number (1-6) you want. If no file is present, the DVD region is left unchanged and only Blu-ray is unlocked. Blu-ray still gets all regions (A+B+C) as before.

**v3.1** — Fixed a bug where the backup was overwritten before checking for RESTORE, so restoring would lose your original region values. Now the restore runs first, and re-running the script won't overwrite an existing backup if the player is already region-free.

**v3** — Fixed `run.sh` failing on UB450 and UB150 when the player's busybox `od` doesn't support `-v -An -tx1` (produces no output, so both keys show "not found"). The primary offset detection now uses `strings -t d`, which is confirmed working on the player's busybox. Falls back to `od` hex search (macOS/GNU), then a `dd` byte-scan as last resort. `read_byte` also has multiple fallbacks (`od` → `hexdump` → `printf`). Tested on a real UB450GN config dump: `strings -t d` returns the correct byte offsets for both region keys.

**v2** — Fixed `run.sh` failing on both UB450 and UB150 with `unexpected key order (BD before DVD)`. The player's busybox `grep -b` reports the byte offset of the line start (always 0 for a binary file), not the match position, so both keys appeared at offset 0. Replaced `grep -boa` with an `od`-based hex search that works on any busybox. Also removed the assumption that the BD key comes after the DVD key in the config file, and added a config file dump to USB (`.config_dump.bin`) for easier debugging on untested models.

## License

MIT
