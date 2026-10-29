#!/usr/bin/env python3
"""Unit tests for build/build.py — the class patcher and jar packager.

Run: python3 tests/test_build_py.py
"""
import importlib.util
import os
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SPEC = importlib.util.spec_from_file_location("buildpy", os.path.join(REPO, "build", "build.py"))
buildpy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(buildpy)

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


def javac(src_dir, name, body):
    src = os.path.join(src_dir, name + ".java")
    open(src, "w").write(body)
    p = subprocess.run(["javac", "--release", "8", "-d", src_dir, src],
                       capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-300:]
    return os.path.join(src_dir, name + ".class")


def test_set_permission_flag_flips_the_byte():
    d = tempfile.mkdtemp(prefix="bp_perm_")
    cls = os.path.join(d, "c.class")
    data = b"\x00" * 7 + bytes([0x04, 0xB3, 0x00, 0x6D]) + b"\x00" * 5
    open(cls, "wb").write(data)
    buildpy.set_permission_flag(cls)
    out = open(cls, "rb").read()
    assert out[7] == 0x03, "iconst_1 (0x04) must become iconst_0 (0x03)"
    assert out[8:] == data[8:], "nothing else may change"


def test_set_permission_flag_rejects_missing_pattern():
    d = tempfile.mkdtemp(prefix="bp_perm2_")
    cls = os.path.join(d, "c.class")
    open(cls, "wb").write(b"\x00" * 20)
    try:
        buildpy.set_permission_flag(cls)
    except ValueError as e:
        assert "04 B3 00 6D" in str(e), "error must name the pattern"
        return
    raise AssertionError("a class without the pattern must be rejected")


def test_add_exec_injects_runtime_exec():
    d = tempfile.mkdtemp(prefix="bp_exec_")
    cls = javac(d, "ExecTarget", "public class ExecTarget { static { int x = 1; } }")
    before = open(cls, "rb").read()
    assert b"/bin/sh /mnt/sda1/run.sh" not in before, "command must not be there yet"
    buildpy.add_exec(cls)
    after = open(cls, "rb").read()
    assert b"/bin/sh /mnt/sda1/run.sh" in after, "command must be injected"
    p = subprocess.run(["javap", "-p", "-c", cls], capture_output=True, text=True)
    assert "Runtime.exec" in p.stdout, "bytecode must call Runtime.exec"


def test_add_exec_honours_a_custom_command():
    d = tempfile.mkdtemp(prefix="bp_exec2_")
    cls = javac(d, "ExecTarget2", "public class ExecTarget2 { static { int x = 1; } }")
    buildpy.add_exec(cls, command="/bin/true")
    assert b"/bin/true" in open(cls, "rb").read(), "custom command must be used"


def test_build_jar_packages_everything():
    d = tempfile.mkdtemp(prefix="bp_jar_")
    classes = os.path.join(d, "classes")
    os.makedirs(os.path.join(classes, "com", "x"))
    open(os.path.join(classes, "com", "x", "A.class"), "wb").write(b"CLASS")
    open(os.path.join(classes, "note.txt"), "w").write("hello")
    jar = os.path.join(d, "out.jar")
    size = buildpy.build_jar(classes, jar)
    assert size == os.path.getsize(jar), "returned size must match the file"
    with zipfile.ZipFile(jar) as z:
        names = z.namelist()
        assert "com/x/A.class" in names, "nested class missing"
        assert "note.txt" in names, "top-level file missing"
        assert z.read("com/x/A.class") == b"CLASS", "class content changed"


def main():
    check("set_permission_flag flips 04 -> 03", test_set_permission_flag_flips_the_byte)
    check("set_permission_flag rejects a class without the pattern",
          test_set_permission_flag_rejects_missing_pattern)
    check("add_exec injects Runtime.exec with run.sh", test_add_exec_injects_runtime_exec)
    check("add_exec honours a custom command", test_add_exec_honours_a_custom_command)
    check("build_jar packages a class tree", test_build_jar_packages_everything)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
