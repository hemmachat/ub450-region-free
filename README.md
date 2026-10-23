# DP-UB450 / UB150 — Region-Free (No Jailbreak)

Play Blu-rays and DVDs from **any region** on your DP-UB450, DP-UB150, or similar MediaTek-based player. No jailbreak firmware, no soldering, no permanent changes. Fully reversible.

Tested on a DP-UB450GN (Australia) with firmware V127 - Sep 10, 2026. See "Does this work on other models?" below for UB150, UB154, UB159, UB820, and UB9000.

> **Disclaimer:**
> - This tool is intended for use on your own player with discs you legally own. It does not bypass copy protection — AACS, BD+, and Cinavia remain fully intact.
> - Region coding controls where a disc can be played, not whether it can be copied. In Australia, circumventing geographic market restrictions on non-game media is permitted under the Copyright Act 1968 (s 10(1)). Laws differ by country — check your local rules.
> - This software is provided as-is, without warranty. Use at your own risk. Modifying your player's configuration may void your warranty. Always back up your original settings (the script does this automatically).

## What you need

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

### 1. Build BDJ.jar

Open a terminal, go to this repo's `build/` folder, and run:

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

### 2. Prepare the USB drive

Format your USB drive as **FAT32** (most USB drives already are).

Copy these three files from the `usb-files/` folder to the **root** of the USB drive:

- `BDJ_DEBUG` (an empty file — don't open or edit it)
- `BDJ.jar` (about 1.2 MB — the file you just built)
- `run.sh` (a small text file)

The USB drive should look like this:

```
USB drive (root)
├── BDJ_DEBUG
├── BDJ.jar
└── run.sh
```

### 3. Run it

1. **Turn on** the player (no disc yet)
2. **Plug the USB drive** into the player's USB port
3. **Insert any Blu-ray disc** and wait for it to load (about 30 seconds). The screen may go blank for a moment — that's normal
4. Once the disc starts playing (or shows its menu), wait another **10 seconds**
5. **Power off** the player with the remote
6. **Remove the USB drive**
7. **Power on** the player

Your player is now region-free.

### 4. Check it worked

Plug the USB drive into your computer. You should see a new file:

- **`REGION_FREE_OK.txt`** — it worked. You can now play discs from any region.
- **`REGION_FREE_FAILED.txt`** — something went wrong. Check `region_log.txt` on the USB for details.

The file `region_log.txt` has a full log of what happened, including your original region values (backed up automatically).

### 5. Test

Insert a disc from a different region. It should play without any region error.

## How to undo it

If you ever want to go back to your original region:

1. Create an empty file called **`RESTORE`** on the USB drive (next to the other files)
2. Repeat step 3 above (plug USB, insert disc, wait, power off, remove USB, power on)

The player will restore your original region from the backup that was saved during step 3.

## FAQ

### Which USB port should I use?

Use the **rear** USB port. If that doesn't work, try the front one.

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

The process changes two bytes in a configuration file on the player's internal storage. It does not modify the firmware. The original values are backed up to the USB drive, and you can restore them at any time. In the worst case, a factory reset (Setup → System → Default Settings) should restore the original region.

### The build script says "wrong firmware layout"

The script checks that the config file on your player matches the expected format before writing anything. If your player has a different firmware version with a different layout, it will stop safely. Open an issue with your model and firmware version.

### A few old DVDs don't play

Some early 2000s DVDs with "RCE" (Regional Coding Enhancement) refuse to play on region-free players. This is rare. If it happens, it's the disc, not the player.

## How it works

The player has a BD-Java debug mode that loads boot classes from a USB drive. The build script extracts the boot classes from your firmware file, makes a small change to allow running a shell script, and packages the result as `BDJ.jar`. When you insert a disc with the USB plugged in, the script runs and changes two bytes in the player's region configuration file. The original values are backed up to the USB first. No firmware is modified — only a config file on the player's internal storage. No network connection is needed.

## Building from source

The `build/build.py` script does everything:

1. Extracts the boot classes from the firmware update file
2. Applies the modifications needed to run the region-change script
3. Packages everything into a standard JAR

It requires Python 3 and `unsquashfs`. If you already have `BDJ.czf` extracted, you can pass it directly instead of the firmware file.

No proprietary code is included in this repository. The build script operates on files you obtain from your own player's firmware.

## Credits

Region code values confirmed against the [Blu-ray specification (PSR 20)](https://videolan.videolan.me/libbluray/player__settings_8h.html) via libbluray and the [DVD region code standard](https://en.wikipedia.org/wiki/DVD_region_code). The BD-Java debug mode is a standard feature of the CVM runtime used in MediaTek-based Blu-ray players.

## License

MIT
