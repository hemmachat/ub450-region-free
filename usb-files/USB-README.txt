USB contents — region switch v5.17
=================================

Factory limitation: the player stores one Blu-ray region code at a time
(1 = A, 2 = B, 4 = C). A locked disc compares the player's region register
with its own region. Discs differ in how strictly they check.

TWO WAYS TO USE THIS STICK

  Region switch (simple): set bd_region.txt to 1, 2 or 4, run this stick
  once, then unplug the player at the wall and remove the stick. The player
  keeps that region and needs no stick while watching.

  Per-disc regions (both A and B, stick stays in): see below. Works since
  30 Oct 2026; the stick stays in the player while you watch.

PER-DISC REGION (both regions, stick stays in)
----------------------------------------------
With the config byte at 3 the player starts a disc of either region, and
BDJ.jar sets the region register about 10 seconds after the disc starts to
the first line of psr20_value.txt. It then puts the player's own interface
back, so disc menus keep working.

THE ONE RULE: the first disc after a power-on must be one the player starts
anyway — a region-free / A+B disc, or any disc from the player's own region
(locked discs are fine — Chernobyl, A+B, is what we use). A disc checks the region in its first
seconds, before the helper runs. After that first disc, every disc of either
region plays in that session, with working menus.

Values:
  1 = region A; also plays the tested lax region B disc
  2 = region B (strict B discs; the tested B disc also plays at 1)
  4 = region C (not tested)
  7 = plays lax B discs only; a strict A disc refuses it
Never use a value above 7: 255 turned the picture off on the tested player.

The first run must leave the config byte at 3 (bd_region.txt = 3), and
bd_region.txt must stay on the stick: the helper also runs run.sh when a disc
starts, and without that file the run falls back to writing 1.

Steps:
1. Eject the disc.
2. Pull the USB out of the player.
3. On a computer, set the first line of psr20_value.txt. Save.
4. Eject the USB from the computer, put it back in the player.
5. Unplug the player at the wall, then power on with the stick in.
6. Wait for the home screen, then wait about 15 seconds more.
7. Insert a disc the player starts anyway (A+B, or a disc of the player's own
   region — locked is fine). It sets the region register about 10 seconds
   after its Java starts.
8. Without powering off, eject it and insert the disc you want to watch. Any
   region works in that session, and disc menus keep working.
Keep the USB in the player while watching.

Started 30 Oct 2026: a disc menu that had stopped responding to the remote
was caused by the helper leaving its replacement interface in place. The
helper now restores the player's own interface immediately; verified with
Chernobyl (A+B), Jigsaw (locked A) and The Hurt Locker (locked B) in one
session. patch_result.txt records it: "restored=" and "get20 real=1".

patch_result.txt is written on every disc start: the region it read before
and after ("get20 before=", "get20 after="), the interface search
("cand=" lines, "passing=") and the restore ("restored="). If a disc is
refused, send that file together with psr20_value.txt.

This applies to Blu-ray only. DVDs switch differently:
1. Set dvd_region.txt (0=free, 1=US, 2=Europe, 3=SE Asia, 4=Australia,
   5=Russia/India, 6=China) and put this USB in the player.
2. Insert a Blu-ray with BD-J that the player can play (a DVD cannot run
   run.sh). Wait ~30 s for "Config write VERIFIED".
3. Unplug the player at the wall, power on, insert the DVD.

BDJ-region-helper.jar
                    Advanced per-disc helper. Copy it to the stick as
                    BDJ.jar, replacing the tool's BDJ.jar (only one of the
                    two can be there at a time). See PER-DISC REGION above.
run.sh              Release script. Writes bd_region.txt to the Blu-ray byte and
                    dvd_region.txt to the DVD byte, verifies, then logs.
bd_region.txt       First line: 1 = Region A, 2 = Region B, 4 = Region C.
                    3 is written as-is; the player then treats it as its own
                    region, which is what the per-disc hook above needs.
psr20_value.txt     Per-disc region for the hook above (1, 2, 4 or 7; ships
                    with 1).
                    Read when a disc starts; no restart needed.
dvd_region.txt      First line: 0 = region-free, 1 = US, 2 = Europe, 3 = SE Asia,
                    4 = Australia, 5 = Russia/India, 6 = China.
                    Default: 1 (US). Make the file empty to skip the DVD
                    change and leave the DVD byte alone.
DVD_EEPROM          Optional, advanced. An empty file that enables the hardware
                    EEPROM DVD write. Leave it out: the config file write is the
                    tested path, and the EEPROM write is unverified. The script
                    writes the EEPROM only when this file is present, the config
                    value differs from the target, and exactly one device matches.
diag.sh             Read-only diagnostics. Copy over run.sh to run it.
run.validation.sh   Old read/write tester used for the Oct 2026 tests; its logs
                    are validation_log_*.txt and config_run*.bin.
run.v5.7.sh         Previous release. It writes BD=7, which does nothing on a
                    region B player (7 falls back to the player's own region).
VALIDATION-old.txt  The Oct 2026 test protocol (historical).

How to run the region switch
----------------------------
1. Unplug the player's power cord (or switch the socket off). Do not use the remote.
2. Plug the USB into the player, plug the player back in and turn it on.
3. Wait for the home screen, then wait about 15 seconds more, then insert a
   Blu-ray with BD-J that the player can currently play — its current region,
   or a region-free/A+B disc. Let the disc menu load — if only the player's
   home screen appears, press Top Menu. A disc from another region may show a
   region message and never start its Java, so the script does not run from
   that screen.
4. Wait about 30 seconds.
5. Unplug the player's power cord (or switch the socket off). Do not use the remote.
6. Remove the USB, plug the player back in, turn it on, and test a US disc.

Files the tool writes here
--------------------------
region_log.txt              Full log of the last run. Replaced every run.
REGION_FREE_OK.txt          The script reached the end. Can be missing on success.
REGION_FREE_FAILED.txt      Why it stopped (config file not found, BD region
                            key not found, value offset out of range,
                            invalid BD region, ...).
.config_dump.bin            Copy of the player's config file from that run.
.config_backup.txt          Config file before the first write. First run only.
.bd_backup.bin .dvd_backup.bin .bd_offset.txt .dvd_offset.txt
                            Original bytes and offsets. First run only.
.eeprom_dvd_backup.bin .eeprom_device.txt
                            EEPROM copy and device path, only when DVD_EEPROM
                            is used.
diag_output/                From diag.sh: diag_log.txt, config file copies,
                            device dumps (*.bin), strace_bdpprog.txt.
patch_result.txt            From the per-disc helper on each disc start.

Files starting with a dot are hidden in Finder on a Mac: press Cmd+Shift+.
To ask for help, send region_log.txt and .config_dump.bin, plus the file that
matches the problem, and your model and firmware version. Full table:
https://github.com/hemmachat/ub450-region-switch#something-not-working-send-us-these-files

Check the disc has BD-J on a computer
-------------------------------------
Open the disc and look for BDMV/JAR/ containing one or more .jar files. If the
JAR folder is missing or empty, the disc cannot trigger the script. MakeMKV or
any Blu-ray disc tool shows the same folders if you have no drive.

To go back to Region B later: set the first line of bd_region.txt to 2 and run once more.
The first line of each file is what the next run writes; change it on the computer
before running.
