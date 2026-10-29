#!/usr/bin/env python3
"""Tests for the PsrScan probe (narrow, guarded register scan).

The earlier 128-register dump bypassed the Java gate and froze the player.
This probe must:
  - read only a small window of registers (20..40),
  - use the public getPSR (the gated, disc-safe path) and never the raw
    nGetPSR reflection,
  - guard every read so one bad index cannot abort the scan,
  - write one file to the stick.

Run: python3 testing/inprocess-experiment/tests/test_psrscan.py
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(EXP))
SRC = os.path.join(EXP, "PsrScan.java")
CLASSES = os.path.join(REPO, "analysis", ".bdj-root", "classes")

PASS = 0
FAIL = 0


def check(name, fn):
    global PASS, FAIL
    try:
        fn()
        PASS += 1
        print("PASS " + name)
    except AssertionError as e:
        FAIL += 1
        print("FAIL " + name + ": " + str(e))


def test_compiles():
    work = tempfile.mkdtemp(prefix="psrscan_")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                       capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]


def test_uses_gated_public_getter_only():
    src = open(SRC).read()
    assert "nGetPSR" not in src, "raw nGetPSR froze the player; use getPSR"
    assert "RegisterAccess.getPSR" in src, "must read through the public getPSR"
    assert "try" in src and "catch (Throwable" in src, "each read must be guarded"
    assert "StringBuilder" not in src, "StringBuilder is absent from this CVM"
    assert not re.search(r"java\.io\.File\b", src), "java.io.File is absent"


def test_window_is_small():
    src = open(SRC).read()
    m = re.search(r"int\s+LO\s*=\s*(\d+)", src)
    n = re.search(r"int\s+HI\s*=\s*(\d+)", src)
    assert m and n, "expected LO/HI constants bounding the scan"
    lo, hi = int(m.group(1)), int(n.group(1))
    assert lo == 20, "scan must start at PSR 20 (region), got %d" % lo
    assert 20 < hi <= 64, "scan window too wide: %d..%d" % (lo, hi)


def main():
    check("PsrScan compiles for this CVM", test_compiles)
    check("PsrScan uses only the gated getter", test_uses_gated_public_getter_only)
    check("PsrScan window is narrow", test_window_is_small)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
