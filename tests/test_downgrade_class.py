#!/usr/bin/env python3
"""Unit tests for downgrade_class.py (class 48 + StackMapTable strip).

Run: python3 tests/test_downgrade_class.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
TOOL = os.path.join(REPO, "testing", "inprocess-experiment", "downgrade_class.py")

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


def compile_branchy(src_dir, name):
    src = os.path.join(src_dir, name + ".java")
    open(src, "w").write(
        "public class %s { public static int f(int x) { if (x > 0) { return 1; } return 2; } }" % name)
    p = subprocess.run(["javac", "--release", "8", "-d", src_dir, src],
                       capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-300:]
    return os.path.join(src_dir, name + ".class")


def test_downgrades_and_strips_stackmap():
    d = tempfile.mkdtemp(prefix="dg_")
    cls = compile_branchy(d, "Branchy")
    before = open(cls, "rb").read()
    assert int.from_bytes(before[6:8], "big") > 48, "test needs a modern class"
    assert b"StackMapTable" in before, "test needs a class with StackMapTable"
    p = subprocess.run([sys.executable, TOOL, cls], capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-300:]
    after = open(cls, "rb").read()
    assert int.from_bytes(after[6:8], "big") == 48, "class version must be 48"
    # The attribute is removed; its name may remain as an unused constant-pool
    # string, so check the parsed structure via javap, not raw bytes.
    v = subprocess.run(["javap", "-v", cls], capture_output=True, text=True)
    assert v.returncode == 0, v.stderr[-200:]
    assert "StackMapTable:" not in v.stdout, "the StackMapTable attribute must be gone"
    assert len(after) < len(before), "removing the attribute must shrink the class"
    assert b"Branchy" in after and b"f" in after, "class and method names must survive"


def test_rejects_missing_file():
    p = subprocess.run([sys.executable, TOOL, "/nonexistent/Nope.class"],
                       capture_output=True, text=True)
    assert p.returncode != 0, "a missing file must fail"


def main():
    check("downgrade to class 48 and strip StackMapTable", test_downgrades_and_strips_stackmap)
    check("downgrade rejects a missing file", test_rejects_missing_file)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
