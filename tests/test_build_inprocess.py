#!/usr/bin/env python3
"""Unit tests for build_inprocess.add_probe_call (the static go() injection).

The shipped helper must call a STATIC entry point (RegionPatch.go). Injecting
an instance method (RegionPatch.run) aborts the class initialiser on the
player and blanks the screen - that happened on 29 Oct 2026.

Run: python3 tests/test_build_inprocess.py
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
EXP = os.path.join(REPO, "testing", "inprocess-experiment")
SPEC = importlib.util.spec_from_file_location("binproc", os.path.join(EXP, "build_inprocess.py"))
binproc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(binproc)

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


def compile_target(d, name="Target"):
    src = os.path.join(d, name + ".java")
    open(src, "w").write("public class %s { static { int x = 1; } }" % name)
    p = subprocess.run(["javac", "--release", "8", "-d", d, src],
                       capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-300:]
    return os.path.join(d, name + ".class")


def javap(path):
    p = subprocess.run(["javap", "-p", "-c", path], capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-200:]
    return p.stdout


def test_injects_static_go():
    d = tempfile.mkdtemp(prefix="bi_go_")
    cls = compile_target(d)
    added = binproc.add_probe_call(cls, probe="com/mtk/utils/RegionPatch", method="go")
    assert added == 4, "the injected call must be 4 bytes, got %r" % added
    out = javap(cls)
    assert "RegionPatch.go:()V" in out, "must invoke the static go entry point"
    assert "RegionPatch.run" not in out, "must not invoke the instance run method"


def test_default_probe_is_psr20probe_run():
    d = tempfile.mkdtemp(prefix="bi_def_")
    cls = compile_target(d, "Target2")
    binproc.add_probe_call(cls)
    out = javap(cls)
    assert "Psr20Probe.run:()V" in out, "default probe must be Psr20Probe.run"


def test_rejects_class_without_clinit():
    d = tempfile.mkdtemp(prefix="bi_bad_")
    src = os.path.join(d, "NoStatic.java")
    open(src, "w").write("public class NoStatic { public int v = 1; }")
    p = subprocess.run(["javac", "--release", "8", "-d", d, src], capture_output=True, text=True)
    assert p.returncode == 0, p.stderr[-200:]
    cls = os.path.join(d, "NoStatic.class")
    try:
        binproc.add_probe_call(cls)
    except Exception:
        return
    raise AssertionError("a class without a static initialiser must be rejected")


def main():
    check("injects the static RegionPatch.go call", test_injects_static_go)
    check("defaults to Psr20Probe.run", test_default_probe_is_psr20probe_run)
    check("rejects a class with no static initialiser", test_rejects_class_without_clinit)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
