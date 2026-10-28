v5.12 is a documentation release. `run.sh` is unchanged from v5.10 and still logs `v5.10`.

Corrected trigger-disc instructions:
- The script runs from a Blu-ray the player can currently play — the same region as its current setting, or a region-free/A+B disc — with BD-J.
- A disc from another region can stop at the region-error screen before its Java starts, so the script never runs. On 28 Oct 2026, The Hurt Locker (B locked) at region A did not trigger; Chernobyl (A+B) did, after which The Hurt Locker played.
- Updated: README, `USB-README.txt`, the `us/` and `uk/` packet instructions, and the repo's AU validation guide.

The playback table now marks The Hurt Locker at `2` as tested.

The `us/` and `uk/` packets keep their v5.9 `run.sh` and skip the DVD change; only their instructions changed.

SHA-256: `311cf3bdea8daeaa4d18d54c91d1c15d6407050b09162d532e2b1e2178d68d01`
