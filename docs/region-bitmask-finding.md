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

## Register set by the helper (30 Oct 2026)

**Status: works.** The helper sets the register and then puts the player's own
misc interface back, so disc menus keep working. Verified on the player on
30 Oct 2026: Chernobyl (A+B), Jigsaw (locked A) and The Hurt Locker (locked B)
all played with working menus in one session. The byte `3` still does not open
the player's gate when the stick is out, and the first disc after a boot must
be one the player starts anyway (see the timing note below).

With the config byte at `3` and the helper setting PSR 20, measured on the
same three discs:

- Jigsaw (locked A) at `1`: plays. `patch_result.txt`: `get20 before=2`,
  `value file=1`, `get20 after=1`.
- **The menu freeze and its fix (29-30 Oct 2026).** On 29 Oct a disc's top
  menu appeared, Home worked, but Left, Right and Play did nothing, with
  `patch_result.txt` showing `get20 before=2` / `get20 after=1`. On 30 Oct an
  install-only build settled the cause: the same freeze happened with the
  interface object installed and the register **never written**. The helper
  replaces the player's `JbiMiscAdapter` object at `0x010fec00`, and that
  object holds the player's data; leaving the replacement in place leaves the
  disc's input handling dead. The fix is to put the player's own object back:
  after setting PSR 20 the helper scans writable memory (heap included; the
  scan target is stored XORed so the helper's own scratch block cannot match
  itself) for a word equal to the adapter vtable `0xc92b20`, accepts a match
  only when its `+0x10` backend is a mapped writable pointer whose own first
  word is a code pointer, requires exactly one such match, and writes that
  address back to `0x010fec00`. `patch_result.txt` logs `scan ranges=`,
  `cand=… vt=c99a30 ok`, `passing=1`, `restored=…`, `get20 real=1`.
- **Region timing.** A freshly inserted disc checks the region in its first
  seconds, before the helper runs (~10 s after the disc's Java starts). A
  fresh Jigsaw start at byte `3` therefore shows the region message even with
  a 10 s or 90 s patch; a disc the player starts anyway (A+B, or any disc of its own region —
  locked is fine) is needed first, and later discs in the session see the register already set.
  The helper still reads PSR 20 first and skips everything when it matches
  `psr20_value.txt` (`already set, patch skipped`).
- The PSR write lands in the real array: the `PlayerRegisters` initialiser at
  `0x1d6928` sets the global `0x010fc27c` to `object + 0x400c`
  (`add.w r2, r4, #0x4000; adds r2, #0xc; str r2, [r3]`).
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

