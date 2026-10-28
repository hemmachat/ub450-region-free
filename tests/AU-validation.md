# AU validation run order

USB: `run.sh` = validation script, mode from the first line of `bd_region.txt`.
The release tool on the validation USB is `run.v5.7.sh` (it writes BD=7 and DVD; the
current release is v5.8, default BD=1). Do not use it during this test.

Each script run creates `validation_log_<N>.txt`, `config_run<N>_before.bin` /
`config_run<N>_after.bin`, and copies of the 121 KB `/acfg/config_file.txt`
before and after (`config_run<N>_config_file_*.txt`). `N` goes up by one every
run; the log's `Mode:` line says what that run did.

## Before anything

- The player must be unplugged (power cord out — not the remote or standby) before
  you plug in or remove the USB. Never hot-plug the stick.
- Edit `bd_region.txt` on the computer, save, eject the stick, then take it to the player.
- A "run" only happens if a Blu-ray with BD-J starts. Use a disc the player can
  play at its current value (same region or region-free/A+B). A mismatched disc
  may show the region error and never start its Java — The Hurt Locker did not
  trigger at BD=1 on 28 Oct 2026, while Chernobyl (A+B) did.

## Step 1 — read the current value (no write)

1. On the computer, `bd_region.txt` first line is `read` (already set).
2. Eject the USB.
3. Player unplugged → plug in the USB → plug the player back in and turn it on.
4. Wait for the home screen (~20–30 s). Do not insert a disc yet.
5. Insert the trigger disc: a disc the player can play at its current value
   (same region or region-free/A+B) with BD-J. Wait about 1 minute. A region
   error means the script may not run — use a playable disc instead.
6. Power the player off. Remove the USB. Plug it into the computer.
7. Check the newest `validation_log_<N>.txt`: it should say `Mode: read` and
   `Before: DVD=0x.., BD=0x..`. That is the player's current value.

## Step 2 — playback test at the current value (nothing changed)

8. Take the USB out of the player (it is already out) and leave it out for this step.
9. Boot the player with no USB. Insert the locked **region A** disc.
   Record: plays / doesn't play (a region error counts as doesn't play).
10. Eject it, insert the locked **region B** disc. Record: plays / doesn't play.
11. Switch the player off at the wall, or unplug it. Do not use the remote.

This answers the open question: if BD is `02` and the A disc plays, the EU
mapping does not apply to your player.

## Step 3 — repeat for each value: 1, then 2, then 7 (optional: 0, 4, 255)

For each value:

12. On the computer, set the first line of `bd_region.txt` to the value (e.g. `1`).
    Save and eject.
13. Player unplugged → plug in the USB → plug it back in and turn it on → wait for the home screen.
14. Insert the trigger disc: a disc the player can play at its current value
    (the last value written, or the factory value for the first run; region-free/A+B
    also works) with BD-J. If a run does not start, try another playable disc.
    Wait ~1 minute.
15. Power the player off. Remove the USB from the player, but keep it out.
16. Power the player on and off once so the new value is loaded at startup
    (PSR 20 is read at boot; a write does nothing until the next boot).
17. With no USB inserted, test the locked region A disc and the locked region B
    disc. Record both results.
18. Plug the USB into the computer and check the newest log: `Mode: <value>`,
    `Write: BD=0x.. rc=0`, `read back BD=0x..`.

## Results to bring back

A small table is enough; the logs have the rest:

| Value | A disc | B disc | Log run # |
|---|---|---|---|
| current (read) | | | |
| 1 | | | |
| 2 | | | |
| 7 | | | |
| optional 0 / 4 / 255 | | | |

Then plug the stick into the Mac again and leave it in — the logs and the
before/after config dumps are read from there.

## Pitfalls

- A write only takes effect after unplugging and powering back on; testing
  playback straight after the run tests the old value.
- Keep the USB out during playback tests, otherwise inserting a BD-J test disc
  starts the script again (harmless in `read` mode, but it adds a log entry and
  in write mode it rewrites the same value).
- `bd_region.txt` must have the value alone on the first line; spaces and tabs are
  stripped, anything else is rejected.
- The player's current BD value before the first write is what matters for step 2.
  Do not run the release tool (`run.v5.7.sh`) or the fix before that.
