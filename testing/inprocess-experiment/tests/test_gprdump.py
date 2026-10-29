#!/usr/bin/env python3
"""Tests for the GprDump probe (all GPRs + the rest of the PSRs).

Used to find the disc's own region: dump with a region A disc, then a
region B disc, and diff. Must stay on the gated public API (the raw
nGetPSR sweep over all 128 PSRs froze the player once).

Run: python3 testing/inprocess-experiment/tests/test_gprdump.py
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(EXP))
SRC = os.path.join(EXP, "GprDump.java")
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
    work = tempfile.mkdtemp(prefix="gprdump_")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                       capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]


def test_gated_api_only_and_guarded():
    src = open(SRC).read()
    assert "nGetPSR" not in src, "raw nGetPSR froze the player; use getPSR"
    assert "RegisterAccess.getPSR" in src, "must read PSRs via the public getter"
    assert "getGPR" in src, "must read GPRs"
    assert "catch (Throwable" in src, "each read must be guarded"
    assert "StringBuilder" not in src, "StringBuilder is absent from this CVM"


def test_covers_gprs_and_upper_psrs():
    src = open(SRC).read()
    assert re.search(r"i\s*<\s*4096", src), "must cover all 4096 GPRs"
    m = re.search(r"int\s+PSR_LO\s*=\s*(\d+)", src)
    assert m and int(m.group(1)) >= 20, "PSR window must start at 20"


def main():
    check("GprDump compiles for this CVM", test_compiles)
    check("GprDump uses the gated API with guards", test_gated_api_only_and_guarded)
    check("GprDump covers GPRs and upper PSRs", test_covers_gprs_and_upper_psrs)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
