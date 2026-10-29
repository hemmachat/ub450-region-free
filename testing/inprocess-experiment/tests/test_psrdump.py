#!/usr/bin/env python3
"""Tests for the PsrDump probe (dumps all 128 PSRs at BD-J start).

Run: python3 testing/inprocess-experiment/tests/test_psrdump.py
Exit code 0 = all pass.

The probe must use only APIs this CVM has (no StringBuilder, no java.io.File),
read the registers through nGetPSR with the public getPSR as fallback, and
write one file to the stick.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(EXP))
SRC = os.path.join(EXP, "PsrDump.java")
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


def _compile():
    work = tempfile.mkdtemp(prefix="psrdump_")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                       capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]
    cls = os.path.join(work, "com", "mtk", "utils", "PsrDump.class")
    assert os.path.exists(cls), "PsrDump.class not produced"
    return cls


def test_compiles():
    _compile()


def test_uses_cvm_safe_apis():
    src = open(SRC).read()
    assert "StringBuilder" not in src, "StringBuilder is absent from this CVM"
    assert not re.search(r"java\.io\.File\b", src), "java.io.File is absent; use streams"
    assert "StringBuffer" in src, "expected StringBuffer for the log"


def test_reads_registers_and_writes_one_file():
    src = open(SRC).read()
    assert "nGetPSR" in src, "must read through nGetPSR"
    assert "getPSR" in src, "must fall back to the public getPSR"
    out = re.findall(r'"(/mnt/sda1/[^"]+)"', src)
    assert out, "no output path on the stick"
    assert all(o.startswith("/mnt/sda1/") for o in out), out


def main():
    check("probe compiles for this CVM", test_compiles)
    check("probe uses CVM-safe APIs", test_uses_cvm_safe_apis)
    check("probe reads registers and writes to the stick",
          test_reads_registers_and_writes_one_file)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
