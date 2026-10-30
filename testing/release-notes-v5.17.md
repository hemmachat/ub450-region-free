v5.17 fixes the per-disc helper (Method 1). The helper used to replace the
player's misc-interface object and leave it replaced; that object holds none of
the player's data, so a disc's menu stopped taking the remote once it was in
place (Jigsaw, 29 Oct 2026: top menu shown, Home worked, no other key did
anything). The helper now sets PSR 20 and then puts the player's own object
back, so the replacement lasts milliseconds and disc menus keep working.

Verified on a DP-UB450GN (Australia, V127) on 30 Oct 2026: Chernobyl (A+B),
Jigsaw (locked A) and The Hurt Locker (locked B) all played with working menus
in one session, from a single patch. `patch_result.txt` shows the chain:
`get20 before=2`, `target written`, `get20 after=1`, `scan ranges=…`,
`cand=… vt=c99a30 ok`, `passing=1`, `restored=…`, `get20 real=1`.

Why it broke, and how it was proven
- An install-only build (the interface replaced, PSR 20 never written) froze
  the menu exactly the same way. That ruled out the register write and put the
  cause on the lingering replacement object.
- The fix searches writable memory for the object whose first word is the misc
  interface's vtable (`0xc92b20`), accepts a match only when its `+0x10`
  backend is a mapped writable pointer whose own first word is a code pointer,
  and requires exactly one such match. The scan target is stored XORed so the
  helper's own scratch block cannot match itself, which allows the heap to be
  scanned.
- The ARM stubs are emulated under `qemu-system-arm` with a synthetic memory
  image (`testing/inprocess-experiment/experiments/restore/run_emu.sh`).
  During development the restore was gated by `restore_enable.txt` on the
  stick; the shipped helper always restores.

Timing limit (unchanged, now documented)
- A freshly inserted disc checks the region in its first seconds, before the
  helper runs (~10 s after the disc's Java starts). The first disc after a
  boot must therefore be one the player starts and that reaches its menu — an
  A+B disc, or any disc of its own region (locked is fine). Every disc after
  it plays in that session. A fresh locked disc from the other region at byte
  `3` shows the region message even with a 10 s or 90 s patch.

Changed
- **Method 1 is now the recommended method**, and `make-usb.py` defaults to it
  (interactive and `--yes`); the menu freeze was the only reason to prefer
  Method 2. `tests/test_setup_usb.py` was changed first and failed until the
  default moved to Method 1.
- `usb-files/BDJ-region-helper.jar` rebuilt: 1,305,156 bytes, SHA-256
  `264c55126dae11b5dcababea5e92eea040157eaa00cd362634abc78ae4432d14`. Source
  `testing/inprocess-experiment/RegionPatch.java`.
- `test_regionpatch_value.py`: 13 checks (adds the map-permission parser, the
  candidate acceptance rule, the restore path and the masked scan target).
- README, `usb-files/USB-README.txt` and `docs/region-bitmask-finding.md`:
  Method 1 now documented as working, with the first-disc rule; the changelog
  entry is v5.17.
