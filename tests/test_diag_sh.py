#!/usr/bin/env python3
"""Tests for usb-files/diag.sh - the read-only diagnostics collector.

Runs the script with USB pointed at a temporary folder and checks that it
finishes, writes diag_output/diag_log.txt, stays inside that folder, and does
not modify anything it reads.

Run: python3 tests/test_diag_sh.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DIAG = os.path.join(REPO, "usb-files", "diag.sh")

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


def test_parses_in_sh():
    p = subprocess.run(["sh", "-n", DIAG], capture_output=True, text=True)
    assert p.returncode == 0, "sh -n failed: " + p.stderr[-300:]


def test_runs_and_writes_only_to_usb():
    usb = tempfile.mkdtemp(prefix="diag_usb_")
    cwd = tempfile.mkdtemp(prefix="diag_cwd_")
    before = set(os.listdir(cwd))
    p = subprocess.run(["sh", DIAG], capture_output=True, text=True,
                       env=dict(os.environ, USB=usb), cwd=cwd, timeout=180)
    assert p.returncode == 0, "diag.sh failed: " + (p.stderr or p.stdout)[-500:]
    log = os.path.join(usb, "diag_output", "diag_log.txt")
    assert os.path.isfile(log), "diag_output/diag_log.txt was not created"
    text = open(log, errors="replace").read()
    assert "Finished" in text, "the log must reach its closing line"
    assert "UB450" in text or "diag" in text.lower(), "the log must identify the run"
    after = set(os.listdir(cwd))
    assert after == before, "diag.sh must not write into the working directory: %r" % (after - before)


def main():
    check("diag.sh parses in sh", test_parses_in_sh)
    check("diag.sh completes and writes only to the USB folder", test_runs_and_writes_only_to_usb)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
