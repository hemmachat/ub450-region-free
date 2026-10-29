> **Status (29 Oct 2026, evening):** the per-disc helper introduced here is
> **experimental** — a disc's menu can stop taking the remote once the helper
> has run. Method 2 (region switcher) is the recommended method. See the
> README.

v5.13 is a tool and documentation release. `run.sh` changes:
- `bd_region.txt` accepts `3`, `5` and `6` as well as `1`, `2` and `4`. The
  player stores them but uses its own region for values it does not recognise;
  `3` is what the per-disc helper needs.
- The error message lists `1`/`2`/`4` (and `3` for the helper) only.
- Fixed the MTD size parsing: a `case` pattern inside `$( )` is rejected by
  bash 3.2, so `bash -n` failed. It is rewritten without `case`, and
  `tests/test_us_portability.sh` now runs `bash -n`.

Documentation:
- README restructured into a single step-by-step flow. Blu-ray and DVD values
  have separate tables in Step 3. The measured behaviour of each value is in
  `docs/region-bitmask-finding.md`.
- `USB-README.txt` gains the per-disc section, the value table and the DVD
  steps.
- New reference section "Something not working? Send us these files": every
  file the tool writes to the USB, what each contains, and which to send for
  each symptom (stopped early, region reverted, wrong values, DVD/EEPROM,
  per-disc helper, general), plus the hidden dot-file names. The US/UK test
  protocol now saves `.config_dump.bin` per run (`dump-1.bin` …), because it
  is overwritten every run. `patch_result.txt` is documented for the helper.

Per-disc Blu-ray helper (shipped as `usb-files/BDJ-region-helper.jar`):
- With the region set to `3`, a BD-J jar sets the region register from
  `psr20_value.txt` about 10 seconds after a disc starts. Tested 29 Oct 2026:
  Jigsaw (locked A) with `1`, The Hurt Locker (locked B) with `7`, Chernobyl
  (A+B) with any value. No restart is needed to switch.
- Source: `testing/inprocess-experiment/RegionPatch.java`. The jar ships in
  `usb-files/` as `BDJ-region-helper.jar`; copy it to the USB as `BDJ.jar`,
  replacing the tool's `BDJ.jar` (only one can be on the stick at a time).
  It was built from the Australian V127 firmware.
- A 2-second install blanks the BD-J VM; 10 seconds is stable.

Tests: target selection 651 checks, pairwise 154, EEPROM guards 54,
offset/write 30, US portability 6, TMO 4, agent scripts 8.

Asset: `ub450-region-switch-v5.13.zip` (1,187,072 bytes), SHA-256
`3424dc8e7a16014f63d14cf938ceb85b2fb5dfc91142f18653c66515d1b754a8`.

Contents: `README.md`, `build/build.py`, `usb-files/` (the USB files plus
`BDJ-region-helper.jar`; the prebuilt tool `BDJ.jar` is not included, users
build it with `build/build.py`), and the unchanged `us/` and `uk/` test
packets from v5.9.
