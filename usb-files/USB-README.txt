USB contents — region switch v5.10
=================================

Factory limitation: the player cannot be made region-free. It enforces one
Blu-ray region at a time (1 = A, 2 = B, 4 = C); 7 does not unlock all regions
and falls back to the player's own region.

run.sh              Release script. Writes bd_region.txt to the Blu-ray byte and
                    dvd_region.txt to the DVD byte, verifies, then logs.
bd_region.txt       First line: 1 = Region A, 2 = Region B, 4 = Region C.
                    Current value: 1 (Region A).
dvd_region.txt      First line: 0 = region-free, 1 = US, 2 = Europe, 3 = SE Asia,
                    4 = Australia, 5 = Russia/India, 6 = China.
                    Current value: 1 (US). Make the file empty to skip the
                    DVD change and leave the DVD byte alone.
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

How to run it
-------------
1. Unplug the player's power cord (or switch the socket off). Do not use the remote.
2. Plug the USB into the player, plug the player back in and turn it on.
3. Wait for the home screen, then insert a Blu-ray with BD-J. Let the disc menu
   load — if only the player's home screen appears, press Top Menu. A region
   message instead of the disc menu is normal on a disc from another region;
   the script can still run from that screen.
4. Wait about 30 seconds.
5. Unplug the player's power cord (or switch the socket off). Do not use the remote.
6. Remove the USB, plug the player back in, turn it on, and test a US disc.

Check the disc has BD-J on a computer
-------------------------------------
Open the disc and look for BDMV/JAR/ containing one or more .jar files. If the
JAR folder is missing or empty, the disc cannot trigger the script. MakeMKV or
any Blu-ray disc tool shows the same folders if you have no drive.

To go back to Region B later: set the first line of bd_region.txt to 2 and run once more.
The first line of each file is what the next run writes; change it on the computer
before running.
