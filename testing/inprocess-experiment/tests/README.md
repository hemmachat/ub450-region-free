# Probe tests

Guards the in-process probe (`RegionEngine.java` + `region_engine.s`) and
the build/embed pipeline. Run:

    testing/inprocess-experiment/tests/run.sh        # or: python3 test_probe.py

Exit code 0 = all pass. Needs `clang`, `llvm-objdump` (via xcrun), `javac`,
`javap` and Python 3. No third-party packages.

## What is covered

| Test | Catches |
|---|---|
| jar matches source | a jar built from an older `RegionEngine.java` |
| stub hex == assembled .text | the class embedding the wrong bytes, including the byte-order bug that blanked the player |
| literal loads resolve | a stub loading anything other than `g_psr` / the three engine functions |
| runtime buffer layout | a table entry pointing at the wrong stub, or stub/noop code overlapping the table (also blanked the player) |
| stub semantics (PICT) | a bound or special case changing, e.g. PSR 128 or negative registers being accepted |
| java api gates | `com.philips` changing so `setPSR`/`getGPR` gain a gate, or `getPSR` stopping delegating to `org.bluray`'s `supportedPSR` |
| probe register usage | the probe using a PSR the Java layer rejects (this produced `-1` readbacks once) or a GPR outside the stub bound |
| firmware abi | the engine entry points, their UOPs, or the adapter vtable slots moving |
| jar injection | `go()` missing from `BDJCompilerOption.<clinit>`, or the class no longer version 48 |

## PICT model

`probe_model.pict` describes the stub input space: four functions x the
register classes (negative, 0, 20, 127, 128, 0x800, 0xFFF, 0x1000) with the
expected path (Normal / Fail / Special20) as constraints. The suite walks
every pair, decodes the ARM compare/branch instructions of the built stub
and checks the path it would take.

## Rule for new probe code

Write the failing test first:

1. Add the case to `probe_model.pict` (or a new test in `test_probe.py`).
2. Run `run.sh` and watch it fail for the right reason.
3. Make the smallest change in `region_engine.s` / `RegionEngine.java`.
4. Rebuild the class and jar, run `run.sh` green.
5. Copy the jar to the USB only after green.

Regenerate the embedded stub hex only through the raw-byte extraction
(`llvm-objdump -s` output is already file order; do not reverse words).
