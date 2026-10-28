v5.11 is a documentation release. `run.sh` is unchanged from v5.10 and still logs `v5.10`; nothing on the USB needs replacing unless you want the corrected README.

Corrected:
- Blu-ray is one region at a time. A locked region B disc refuses at `1`: The Hurt Locker (Roadshow AU) on the AU UB450, plus 7–8 B discs on the EU UB150. The Chernobyl disc that played at `1` is region-free/A+B, not evidence of A+B support. The "not confirmed" hedge is gone.
- DVD region 0 is not verified on these players. Setting `dvd_region.txt` to `0` writes only the config file; the firmware reads the DVD region from the hardware EEPROM at boot, and that copy is only written with the advanced `DVD_EEPROM` file. v3.2 recorded region 0 failing, and no DVD playback test exists for any value.

Also added:
- A "What plays at which setting" table to the README: a rule table plus tested discs (The Hurt Locker, Chernobyl, Spiral/Jigsaw, a locked region A disc) and expected rows marked.

The `us/` and `uk/` test packages are unchanged from v5.9 (they skip the DVD change, so the guard does not affect them). They are not needed for normal use.

SHA-256: `1eecddeff2adde7cc59c918ae4a1779237cff731d7b1f403cad6c3be1066a7d0`
