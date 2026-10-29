# Blu-ray region: is the config byte a bitmask? (finding, 28 Oct 2026)

Status: **answered (29 Oct 2026).** `3` is not an A+B bitmask: the player
falls back to its own region. With the per-disc helper loaded, `3` does let
the player start a disc of either region, which is what the helper uses. The
sections below are kept in the order they were written; "Measured behaviour"
and "Register set by the helper" hold the results.

## What the firmware does

1. The Blu-ray region is field **5** of the ACFG store (byte 237 of
   `config_file_global.txt`). Its accessors are `a_cfg_get_bdregioncode`
   (bdpprog 0x7bbed8) and `a_cfg_set_bdregioncode` (0x7bbf28). Both call the
   generic ACFG accessors with field id 5 and do **no validation of their own**.
   Any byte is stored and read back — `7` included (the release tool's
   `Config write VERIFIED` at 7 confirms this).

2. The byte that *is* range-checked is the **DVD** region (field 3):
   `acfg_regioncode_validate` (0x7bb470) accepts 0-6 and logs
   `<ACFG> ERROR, acfg_regioncode_validate, invalid value : %d` otherwise.
   This is the DVD field, not Blu-ray.

3. The playback engine's DVD region test (`liblp.so`,
   `CLpDvidMediaManager::vCheckRegion`, 0x17431c) is a **bitmask** test:

   ```
   disc_bit = 1 << (disc_region - 1)
   if ((player_region & disc_bit) == 0) -> region error
   ```

   So for DVD the stored value is a set of regions: 1, 2, 3 = 1+2, etc.

4. The Blu-ray path was not found in `liblp.so` (that library carries the DVD
   manager). The Blu-ray region lives in bdpprog, which is stripped. What is
   known: PSR 20 held `1` while the config byte was `1`, and a written `7`
   behaves like the player's own region (region B on AU/EU).

## What it means

- `7` falling back does **not** prove the config validator rejected it; the
  byte is stored. The fallback happens where the value is turned into the
  player's region, and that code has not been read.
- The build flag `onezone: 1` (in the firmware's build metadata) suggests that
  code accepts one region at a time. If so, `3` (A+B) also falls back.
- The EU unit reported `0`, `2`, `3`, `7` and `255` all playing its own region
  B, which fits the single-zone reading — but a B disc plays under both
  readings, so only an A disc tested at `3` distinguishes them. That was not
  recorded as tested.

## Test (no risk, config write only)

`bd_region.txt` = `3` on the USB, run the tool, power-cycle, then try **both**:

1. a locked region A disc, and
2. The Hurt Locker (locked region B).

- both play -> `3` is A+B; the byte is a bitmask and stock firmware does it;
- only B plays -> single-zone confirmed; `3` falls back like `7`.

## If only B plays

The remaining lever is the single-zone code in bdpprog (the consumer of field
5), which needs a firmware write to change: bdpprog sits on the read-only
rootfs partition (`/dev/mtdblock16`). Not attempted; the firmware metadata
carries `rootfs_check: 1`, `rsa_check: 1` and `antirollback: 1`, and the boot
trust path has not been confirmed.

## Measured behaviour of the region byte (29 Oct 2026)

What the player does with each value, from playback tests on the AU UB450
(Jigsaw = locked A, The Hurt Locker = locked B, Chernobyl = A+B):

- `1` = region A: Jigsaw plays, The Hurt Locker is blocked before its Java starts.
- `2` = region B: The Hurt Locker plays, Jigsaw is refused.
- `4` = region C: never tested (no region C disc).
- `3`, `7` and other values are stored as-is. The player then uses its own
  region: on the tested unit the region register (PSR 20) reads `2`, region B.
- At `3` the player does not block a disc of the other region before BD-J
  starts **while the helper is loaded**: both Jigsaw and The Hurt Locker got
  as far as their own Java with the stick in. That is why the per-disc helper
  uses `3` (see below). Correction, 29 Oct 2026: with the stick **out**, a
  Jigsaw start at `3` stops at the region-error screen before its Java runs,
  so the byte alone does not open the gate. `7` was never tried with the
  helper, so it is not known whether it opens the same gate.
- A locked disc compares PSR 20 with its own region: Jigsaw accepted `1` and
  refused `7`; The Hurt Locker accepted `7`. One value cannot satisfy every
  disc, which is why true A+B needs the register set per disc.

## Register set by the helper (29 Oct 2026, experimental)

**Status: experimental.** The helper sets the register correctly, but it can
make a disc's menu stop taking the remote (see the bullet below), and the byte
`3` it depends on does not open the player's gate when the stick is out. The
supported route is the region switch (Method 2): set byte 237 to `1`, `2` or
`4` and play without the stick.

With the config byte at `3` and the helper setting PSR 20, measured on the
same three discs:

- Jigsaw (locked A) at `1`: plays. `patch_result.txt`: `get20 before=2`,
  `value file=1`, `get20 after=1`.
- **The disc menu can stop taking the remote** (measured 29 Oct 2026, same
  Jigsaw disc, same stick): the top menu appeared, Home worked, but Left,
  Right and Play did nothing — with `patch_result.txt` again showing
  `get20 before=2` / `get20 after=1`, so the region value was applied. Remove
  the stick and set the disc's own region (Method 2) to play such a disc.
  The helper replaces the player's misc interface with its own; what that
  breaks and why keys stop is not yet known, and the same disc had played
  earlier that day with the stick in.
- The Hurt Locker (locked B) at `1`: plays, in the same session, with no new
  helper write. It also plays at `7`.
- Jigsaw at `7`: refused ("mismatch between disc and player region codes").
- `255`: the picture goes blank; values above `7` are not safe.
- **The register persists across disc swaps.** Sequence Chernobyl →
  The Hurt Locker → Jigsaw, no reboot and no file edits: Jigsaw (which
  refuses `2` and accepts only `1`) played last, so the register was still
  `1` from the earlier write. Discs that played in between ran under `1` too.
  This corrects the 28 Oct note that the player rebuilds PSR 20 at disc
  insert — the patch survives until the VM restarts.
- Consequence: `1` is the best single value on the tested player (locked A
  disc and the lax locked B disc both play). A locked B disc that checks
  strictly would still need `2`.

