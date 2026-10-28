# Blu-ray region: is the config byte a bitmask? (finding, 28 Oct 2026)

Status: **open question, one live test decides it.** It has to run on an
Australian UB450 (see "Test").

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
  starts: both Jigsaw and The Hurt Locker got as far as their own Java. That
  is why the per-disc helper uses `3` (see below). `7` was never tried with
  the helper, so it is not known whether it opens the same gate.
- A locked disc compares PSR 20 with its own region: Jigsaw accepted `1` and
  refused `7`; The Hurt Locker accepted `7`. One value cannot satisfy both at
  once, which is why true A+B needs the register set per disc.
