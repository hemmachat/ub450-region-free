# Tests

Run from the repo root. The player is not needed: the harnesses build fake
config and USB trees.

- `test_run.sh` — offset detection and read/write helpers (30 assertions).
- `test_pairwise.sh` — 27-case PICT pairwise suite for the fake config writer (154 assertions).
- `test_eeprom_pairwise.sh` — 27-case PICT pairwise suite for EEPROM detection, write and restore (96 assertions).
- `test_targets_pict.sh` — 66-case PICT pairwise suite plus 24 seeded cases for
  `bd_region.txt` / `dvd_region.txt` parsing, validation, writes and RESTORE
  (630 assertions). It runs the real `run.sh` end-to-end and needs `zsh`
  (macOS dash has no `printf '\x..'`); `sync` is stubbed because the test checks
  bytes and result files, not durability. The PICT model is in the file header.
- `test_us_portability.sh` — simulates the US player's stripped busybox (no
  `strings`, `od` prints nothing, no `timeout`) and checks `run.sh` still finds
  the region keys and writes the Blu-ray byte (5 assertions).
- `test_tmo.sh` — extracts the `tmo` helper from `run.sh` and checks piped
  stdin, kill-on-timeout and exit-code passthrough (4 assertions).
- `persistence-test-run.sh`, `watch-region.sh`, `au-validation-run.sh` — one-off
  player-side diagnostics, not part of the local suite.

Run everything:

```sh
for t in tests/test_*.sh; do sh "$t" || exit 1; done
```
