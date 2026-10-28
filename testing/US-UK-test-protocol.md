# US / UK / EU players — does the region survive a normal power-off?

This is a test protocol, not a user step. It answers one question: on some
US, UK and EU units the Blu-ray region is written but comes back after a
clean power-off. Does a normal value (1, 2 or 4) survive, or does it revert?

Some US, UK and EU players show the old region again after a reboot: at a clean power-off the player writes its own copy of the settings back over the file. Every earlier report also used `7`, which does nothing useful on this player, so we still do not know whether a normal value (1, 2 or 4) survives a power cycle. If you have a US DP-UB450P, or a UK/EU unit, and a disc from another region, this test answers it.

The latest [release](https://github.com/hemmachat/ub450-region-switch/releases/latest) includes two ready-made packages:

- `us/` writes `2` (Region B). Use it on a US player, which is Region A.
- `uk/` writes `1` (Region A). Use it on a UK/EU player, which is Region B.

Copy the contents of the matching folder to the root of your USB stick, next to the `BDJ.jar` you built with `build/build.py`. Both packages skip the DVD change, so nothing else is touched. The folder's `TEST-INSTRUCTIONS.txt` has the same steps in plain language.

1. **Run 1 — write the value.** Unplug the player's power cord, insert the USB, plug the player back in and turn it on. Insert a BD-J disc the player can play (its own region, or region-free/A+B) and wait about 30 seconds. Rename `region_log.txt` on the USB to `log-1.txt`.
2. **Run 2 — normal power-off.** Press the power button on the remote and wait until the player is off. Turn it on, insert the disc again, wait about 30 seconds. Open `region_log.txt` and find the line starting with `Before:`. Rename the file to `log-2.txt`.
3. **Run 3 — only if Run 2 shows the old value.** Insert the disc and wait about 40 seconds, then unplug the power cord instead of using the remote. Plug it back in, insert the disc, wait about 30 seconds, and read the `Before:` line again. Rename the file to `log-3.txt`.

If the log's `Started:` time looks late (well past the boot), the script ran more than once in that session. The first run after the boot is the one whose `Before:` line answers the question — repeat the run from a cold boot if you are unsure.

What the result means:

- `BD=0x02` after Run 2 on a US player, or `BD=0x01` on a UK player: the value survived a normal power cycle. Try a disc from the other region.
- Only Run 3 keeps it: the player's normal shutdown is rewriting the file.
- Neither keeps it: the player rewrites the value at startup. The logs still tell us how, so please send them.

Send back: `log-1.txt`, `log-2.txt`, `log-3.txt` if you did Run 3, `REGION_FREE_OK.txt` or `REGION_FREE_FAILED.txt` (the OK file can be missing even when the write worked — the `Config write VERIFIED` line is what counts), your model and firmware version, and what the other-region disc did (a photo of any message helps). Open a [GitHub issue](https://github.com/hemmachat/ub450-region-switch/issues) and attach them, or paste the `Before:` lines.

Optional diagnostics: rename `run.sh` to `run-region.sh`, rename `diag.sh` to `run.sh`, and do one more run. The USB gets a `diag_output` folder — send that too. It only reads.

