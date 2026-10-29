> **Status (29 Oct 2026, evening):** Method 1 is now **experimental** (a
> disc's menu can stop taking the remote once the helper runs). `make-usb.py`
> in this release still offers Method 1 as the default; the current script
> defaults to Method 2. See the README.

v5.15 adds a guided USB builder, fixes `diag.sh`, and adds unit tests for
every script that had none. `run.sh` and the helper jar are unchanged.

New: `make-usb.py`
- Asks which method and the few values that matter, writes the stick for
  Method 1 (both regions) or Method 2 (region switcher), and checks every
  copied file against the repository by SHA-256.
- Refuses values above `7` (naming the `255` blank-screen hazard), invalid
  regions, a missing USB path and a missing `BDJ.jar`. Never deletes anything;
  overwrites only after confirmation (`--yes` skips it for scripted use).
- Scripted forms: `python3 make-usb.py --method 1 --usb /Volumes/USB --yes`
  or `--method 2 --bd 2 --dvd skip --yes`.

Fixed: `usb-files/diag.sh`
- It hard-set `USB=/mnt/sda1`, ignoring an override, and wrote its
  `DIAG_DONE.txt` marker outside the chosen folder. Now `USB=${USB:-/mnt/sda1}`;
  behaviour on the player is unchanged.

Tests (each mutation-proved)
- `tests/test_setup_usb.py` - both layouts, custom and refused values, DVD
  skip, missing jar/path, overwrite confirmation, clean no-input message.
- `tests/test_build_py.py` - `set_permission_flag` (04 -> 03), `add_exec`
  (`Runtime.exec` with `run.sh`, custom command), `build_jar` packaging.
- `tests/test_downgrade_class.py` - class 48, StackMapTable attribute removed,
  names preserved, missing file rejected.
- `tests/test_build_inprocess.py` - static `RegionPatch.go` injection (the
  29 Oct blank-screen bug), default `Psr20Probe.run`, class without a static
  initialiser rejected.
- `tests/test_diag_sh.py` - parses in `sh`, completes, writes only under
  `diag_output/`, never into the working directory.

Documentation
- README: new "Make the USB automatically" section with pointers from both
  methods, a "Tests" section listing every suite, and a changelog entry.

Asset: `ub450-region-switch-v5.15.zip` (1,191,641 bytes), SHA-256
`db26b54a16b0f6b5cf25731e831e8d20899dcf9d1955fc33ae2e95beb399e71e`.

Contents: `make-usb.py`, `README.md`, `build/build.py`, `usb-files/` (the USB
files, the helper jar and `psr20_value.txt`; the prebuilt tool `BDJ.jar` is not
included - users build it with `build/build.py`), and the unchanged `us/` and
`uk/` test packets from v5.9.
