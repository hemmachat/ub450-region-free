v5.14 is a helper and documentation release. `run.sh` is unchanged; the
per-disc helper jar is rebuilt.

Measured result (29 Oct 2026, Australian UB450, firmware V127):
- With the helper's value at `1`, the locked region A disc (Jigsaw) and the
  locked region B disc (The Hurt Locker) both play in one session, with no
  edits between discs. Confirmed end-to-end with the built USB stick.
- `7` plays the lax B disc but strict A discs refuse it.
- `255` blanks the picture; values above `7` are unsafe.
- The register set by the helper persists across disc swaps (it is not rebuilt
  at disc insert), so the stick must stay in the player while watching.
- A value change only applies when a disc's Java starts fresh — a different
  disc or a power cycle; reinserting the same disc can resume playback without
  re-running the helper.

Changes:
- Helper default is now `1` (was `7`) when `psr20_value.txt` is missing or
  holds no number. `usb-files/BDJ-region-helper.jar` rebuilt with
  `PROBE_METHOD=go` (1,303,267 bytes, SHA-256
  `3ed5effad1233c9d46f00f4e45b7c6793fea741b1a8e62fb9332acc0aa48dd6e`).
  Building with `run` instead of `go` is wrong: `run` is an instance method,
  so `invokestatic` aborts the class initialiser and blanks the player.
- New `usb-files/psr20_value.txt` (value `1`), so Method 1 needs no manual
  file creation.
- README restructured around the two ways to use it:
  **Method 1 — play both regions (recommended)**: helper jar, no firmware
  build needed, USB stays in the player. **Method 2 — region switcher**: sets
  one region (`1`, `2` or `4`), USB only while the tool runs.
- README/USB-README corrected: the tested value table, the "never above 7"
  warning, the register-persistence note, the fresh-start rule for value
  changes, the correct `bd_region.txt`/`dvd_region.txt` edits for Method 1,
  and the USB media menu during the first run.
- `docs/region-bitmask-finding.md`: new "Register set by the helper" section.
- Tests: `testing/inprocess-experiment/tests/test_regionpatch_value.py` covers
  0-255 parsing, the `1` default, static `go()` injection, and that the
  shipped jar matches a fresh build of the source (6 checks). Probe suite
  10/10; all other suites unchanged and green.

Asset: `ub450-region-switch-v5.14.zip` (1,187,912 bytes), SHA-256
`2b6b4aeaec4e97e8a5cb5221cff856c40c9ff1122844ec67e8c7d19d78ad7f3f`.

Contents: `README.md`, `build/build.py`, `usb-files/` (the USB files, the
helper jar and `psr20_value.txt`; the prebuilt tool `BDJ.jar` is not included —
users build it with `build/build.py`), and the unchanged `us/` and `uk/` test
packets from v5.9.
