v5.16 demotes the per-disc helper (Method 1) to experimental and corrects
every doc that still presented it as the recommended method. Documentation and
builder only: `run.sh` and `usb-files/BDJ-region-helper.jar` are byte-identical
to v5.15, so nothing that runs on the player changed and no hardware re-test
was needed.

Why: on 29 Oct 2026, with the helper loaded and PSR 20 set correctly
(`patch_result.txt`: `get20 before=2`, `value file=1`, `get20 after=1`),
Jigsaw's top menu appeared but Left, Right and Play did nothing — Home still
worked. The same stick and value had played that disc earlier the same day.
Also corrected: the byte `3` alone does not open the player's gate — with the
stick out, a locked disc stops at the region-error screen before its Java runs.
Method 2 (set the player's own region, no stick while watching) is the method
that works.

Changed
- README: Method 2 is the recommended method; Method 1 marked experimental in
  the intro, the method table, the Method 1 heading (the anchor is now
  `#method-1--play-both-regions-experimental`), its limits and FAQ, the symptom
  table and "How it works". "Wait ~20 s" removed — the helper applies the value
  about 10 seconds after the disc's Java starts. New FAQ entry for a disc menu
  that takes no input.
- `make-usb.py`: Method 1 labelled experimental; the default answer, and
  `--yes` without `--method`, now pick Method 2; the next-steps text warns
  about the menu limit. New test in `tests/test_setup_usb.py`, "No --method
  picks the recommended method", written failing first (the default used to
  build the Method 1 stick). Suites green: shell 30/154/54/651/4/6, python
  7/5/3/2/2, probe 10/10.
- `usb-files/USB-README.txt`: the region switch comes first; the per-disc
  helper is marked experimental; the gate and timing statements corrected.
- `docs/region-bitmask-finding.md`: status changed to "answered"; the helper
  section is marked experimental and records the 29 Oct menu result.
- Release notes v5.13-v5.15: status headers. `tests/README.md`: the Python
  suites and the probe command listed; PICT assertion count corrected from 630
  to 651. `RegionPatch.java` header comment corrected on one line, so the
  shipped jar still matches a fresh build of the source.
  `autoresearch/user-dryrun/README.md` marked as an out-of-date snapshot.
- Root `CLAUDE.md` section 11: the 29 Oct menu result, the demotion, and a note
  that the `docs/...` files it cites for older evidence are not in the
  repository.

Asset: `ub450-region-switch-v5.16.zip` (1,192,360 bytes), SHA-256
`5795e1c1f5d84174c027f2b5b318c2295fdde43194456f6e3305e17984a1bb12`.

Contents: `make-usb.py`, `README.md`, `build/build.py`, `usb-files/` (the USB
files, the helper jar and `psr20_value.txt`; the prebuilt tool `BDJ.jar` is not
included - users build it with `build/build.py`), and the unchanged `us/` and
`uk/` test packets from v5.9.
