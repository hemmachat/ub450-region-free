v5.9 makes the tool work with the player's actual tools. The player's system has no `timeout`, no `od` and no `strings` — verified in the AU V127, UK V127 and US V113 firmware images, so it was never a US-only problem. Earlier versions silently skipped every EEPROM step because of it, and `diag.sh` reported blank model and region values.

Also in this release:
- `run.sh` and `diag.sh` use a kill-after-N-seconds wrapper when `timeout` is missing, and `hexdump` (which the player ships) when `od` is missing
- The DVD EEPROM step can now actually run; it could not start on any unit before
- Fixed the IR check at 0x205, which read 255 and rejected every matching EEPROM device when `od` was unavailable
- New tests: `test_tmo.sh`, `test_us_portability.sh`
- New `us/` and `uk/` test packages for two reporters (see below)

Upgrading from v5.8: replace `run.sh` and `diag.sh` on the USB. `bd_region.txt` and `dvd_region.txt` work the same way.

Region-free is still not possible on stock firmware: the player enforces one Blu-ray region per boot, `1` = A, `2` = B, `4` = C.

`us/` and `uk/` are test packages for a US and a UK reporter. They write one valid region value (2 on US, 1 on UK) and ask for three runs, to find out whether a valid value survives a power cycle. Earlier "region reverts" reports all used 7, which this player rejects, so they could not answer that question. These folders do not include `BDJ.jar` — the testers use the jar from their earlier runs. They are not needed for normal use.

SHA-256: `375ad40c88762e850a5f9148dbe9c71846add1cd33bd7a171de7bfbacfc9b642`
