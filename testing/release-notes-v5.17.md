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
  helper runs (~10 s after the disc's Java starts). The first disc after a boot
  must therefore be one the player starts anyway (A+B or its own region);
  every disc after it plays in that session. A fresh locked disc at byte `3`
  shows the region message even with a 10 s or 90 s patch.

Changed
- `usb-files/BDJ-region-helper.jar` rebuilt: 1,305,084 bytes, SHA-256
  `7d69c5d540800fd5093868840a952bafa21ed63dc6e3c4559278195a2fc0c09b`. Source
  `testing/inprocess-experiment/RegionPatch.java`.
- `test_regionpatch_value.py`: 12 checks (adds the map-permission parser, the
  restore path and the masked scan target).
- README, `usb-files/USB-README.txt` and `docs/region-bitmask-finding.md`:
  Method 1 now documented as working, with the first-disc rule; the changelog
  entry is v5.17.
