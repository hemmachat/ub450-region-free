# Tests

Run from the repo root. The player is not needed: the harnesses build fake
config and USB trees.

- `test_run.sh` — offset detection and read/write helpers (30 assertions).
- `test_pairwise.sh` — 27-case PICT pairwise suite for the fake config writer (154 assertions).
- `test_eeprom_pairwise.sh` — end-to-end tests for the v5.10 EEPROM guard: opt-in
  file, no-op skip, single match, ambiguous matches, invalid/mismatched values,
  IR byte, backup, write and RESTORE (54 assertions). It runs the real `run.sh`
  against fake device files through the `EEPROM_CANDIDATES` hook and needs `zsh`.
- `test_targets_pict.sh` — 66-case PICT pairwise suite plus 24 seeded cases for
  `bd_region.txt` / `dvd_region.txt` parsing, validation, writes and RESTORE
  (651 assertions). It runs the real `run.sh` end-to-end and needs `zsh`
  (macOS dash has no `printf '\x..'`); `sync` is stubbed because the test checks
  bytes and result files, not durability. The PICT model is in the file header.
- `test_us_portability.sh` — simulates the US player's stripped busybox (no
  `strings`, `od` prints nothing, no `timeout`) and checks `run.sh` still finds
  the region keys and writes the Blu-ray byte (5 assertions).
- `test_tmo.sh` — extracts the `tmo` helper from `run.sh` and checks piped
  stdin, kill-on-timeout and exit-code passthrough (4 assertions).
- `test_setup_usb.py` — `make-usb.py`: both stick layouts, the helper jar
  copied byte-for-byte, custom and refused values, the default method (Method 1
  unless `--method` is given), missing target and a clean no-input message
  (7 checks).
- `testing/inprocess-experiment/tests/test_regionpatch_value.py` — the
  per-disc helper: the value file, the skip when the register already matches,
  the map-permission parser, the candidate acceptance rule, the interface
  restore and the masked scan target, and that the shipped jar equals a fresh
  build (13 checks).
- `testing/inprocess-experiment/experiments/restore/run_emu.sh` — the ARM
  stubs from `stubs.s`, run under `qemu-system-arm` against a synthetic memory
  image (12 checks: scan, skip, read-word, setgpr, bounds). Needs qemu; it is
  not part of the default loop.
- `test_build_py.py`, `test_build_inprocess.py`, `test_downgrade_class.py`,
  `test_diag_sh.py` — the build scripts, the probe-call injection, the class
  downgrade and `diag.sh` (5 + 3 + 2 + 2 checks).
- `persistence-test-run.sh`, `watch-region.sh`, `au-validation-run.sh` — one-off
  player-side diagnostics, not part of the local suite. `persistence-test-run.sh`
  also probes `/proc/<bdpprog>/mem`, pagemap and `/dev/mem` read-only.
- `testing/au-hardware-probe/` — USB contents and run sheet for the 27 Oct 2026
  AU probe (hard cut, clean shutdown, memory probes).

Run everything:

```sh
for t in tests/test_*.sh; do sh "$t" || exit 1; done
for t in tests/test_*.py; do python3 -I "$t" || exit 1; done
sh testing/inprocess-experiment/tests/run.sh   # probe suite, 10 checks
```
