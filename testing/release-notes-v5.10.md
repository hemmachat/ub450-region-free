v5.10 makes the DVD EEPROM write opt-in. It is the only step that writes outside the config file, it identifies the device by guessing (byte at 0x200 plus the IR byte at 0x205), and it has never run on real hardware — every v5.9 log we have stops before the scan. A wrong match could write into a firmware partition, so it is now a deliberate test step instead of something every run does.

Also in this release:
- The EEPROM step runs only when an empty `DVD_EEPROM` file is on the USB
- It is skipped when the config already holds the target value
- It refuses to write when more than one device matches (`EEPROM write REFUSED`)
- MTD partitions whose size `/proc/mtd` does not report are skipped
- The Blu-ray and DVD config-file writes are unchanged; RESTORE is unchanged
- New end-to-end tests run the real `run.sh` against fake devices (54 assertions; full suite 877)

Upgrading from v5.9: replace `run.sh` and `USB-README.txt` on the USB. `bd_region.txt` and `dvd_region.txt` work the same way. If you do not create `DVD_EEPROM`, the DVD region is still written to the config file, but the hardware EEPROM copy is not touched.

Region-free is still not possible on stock firmware: the player enforces one Blu-ray region per boot, `1` = A, `2` = B, `4` = C.

The `us/` and `uk/` test packages are unchanged from v5.9 (both skip the DVD change, so the new guard does not affect them). They are not needed for normal use.

SHA-256: `e38ec43231c3fcdd48f96540eab1713a16c443f074b8211c8bef6465ad1521b2`
