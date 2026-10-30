#!/usr/bin/env python3
"""Tests for make-usb.py (the guided USB builder).

Runs the builder non-interactively against temporary directories and checks
exactly what lands on the stick for each method, including rejection of unsafe
values. No player and no firmware build is needed: Method 2 is exercised with
a prebuilt jar passed via --jar.

Run: python3 tests/test_setup_usb.py
"""
import hashlib
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
TOOL = os.path.join(REPO, "make-usb.py")
USB = os.path.join(REPO, "usb-files")

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


def run(args):
    return subprocess.run([sys.executable, TOOL] + args, capture_output=True, text=True)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def first_line(path):
    with open(path) as f:
        return f.readline().strip()


def test_method1_writes_helper_layout():
    d = tempfile.mkdtemp(prefix="usb_m1_")
    p = run(["--method", "1", "--usb", d, "--yes"])
    assert p.returncode == 0, "failed: " + p.stderr[-400:]
    assert first_line(os.path.join(d, "bd_region.txt")) == "3", "bd_region must be 3"
    assert first_line(os.path.join(d, "psr20_value.txt")) == "1", "default psr20 must be 1"
    assert os.path.getsize(os.path.join(d, "dvd_region.txt")) == 0, "dvd_region must be empty"
    assert os.path.getsize(os.path.join(d, "BDJ_DEBUG")) == 0, "BDJ_DEBUG must be empty"
    assert sha(os.path.join(d, "BDJ.jar")) == sha(os.path.join(USB, "BDJ-region-helper.jar")), \
        "BDJ.jar must be the helper jar"
    assert sha(os.path.join(d, "run.sh")) == sha(os.path.join(USB, "run.sh")), "run.sh mismatch"


def test_method1_custom_value_and_rejects_unsafe():
    d = tempfile.mkdtemp(prefix="usb_m1b_")
    p = run(["--method", "1", "--usb", d, "--yes", "--psr20", "2"])
    assert p.returncode == 0, p.stderr[-300:]
    assert first_line(os.path.join(d, "psr20_value.txt")) == "2", "psr20 2 not written"
    d2 = tempfile.mkdtemp(prefix="usb_m1c_")
    p = run(["--method", "1", "--usb", d2, "--yes", "--psr20", "255"])
    assert p.returncode != 0, "255 must be refused"
    assert "7" in (p.stdout + p.stderr), "the refusal must mention the 7 limit"


def test_method2_uses_given_jar_and_values():
    d = tempfile.mkdtemp(prefix="usb_m2_")
    jar = os.path.join(d, "built.jar")
    open(jar, "wb").write(b"FAKEJAR")
    p = run(["--method", "2", "--usb", d, "--yes", "--bd", "2", "--dvd", "4", "--jar", jar])
    assert p.returncode == 0, p.stderr[-400:]
    assert first_line(os.path.join(d, "bd_region.txt")) == "2", "bd 2 not written"
    assert first_line(os.path.join(d, "dvd_region.txt")) == "4", "dvd 4 not written"
    assert sha(os.path.join(d, "BDJ.jar")) == sha(jar), "BDJ.jar must be the given jar"
    assert os.path.exists(os.path.join(d, "run.sh")), "run.sh missing"


def test_method2_dvd_skip_and_missing_jar():
    d = tempfile.mkdtemp(prefix="usb_m2b_")
    jar = os.path.join(d, "built.jar")
    open(jar, "wb").write(b"FAKEJAR")
    p = run(["--method", "2", "--usb", d, "--yes", "--bd", "1", "--dvd", "skip", "--jar", jar])
    assert p.returncode == 0, p.stderr[-300:]
    assert os.path.getsize(os.path.join(d, "dvd_region.txt")) == 0, "dvd skip must be an empty file"
    d2 = tempfile.mkdtemp(prefix="usb_m2c_")
    p2 = run(["--method", "2", "--usb", d2, "--yes", "--bd", "1", "--dvd", "skip",
              "--jar", os.path.join(d2, "does-not-exist.jar")])
    assert p2.returncode != 0, "a missing jar must fail"
    assert "BDJ.jar" in (p2.stdout + p2.stderr), "the error must say how to get BDJ.jar"


def test_no_input_gives_a_clean_message():
    # Running without a terminal must not dump a Python traceback.
    p = subprocess.run([sys.executable, TOOL], capture_output=True, text=True, input="")
    assert p.returncode != 0, "a no-input run must fail"
    assert "Traceback" not in p.stderr, "no traceback for the user to see"
    assert "make-usb" in (p.stdout + p.stderr).lower() or "--method" in (p.stdout + p.stderr), \
        "the message must say how to run it non-interactively"


def test_refuses_missing_target_and_bad_region():
    p = run(["--method", "1", "--usb", "/nonexistent/usb/path", "--yes"])
    assert p.returncode != 0, "a missing target must fail"
    d = tempfile.mkdtemp(prefix="usb_bad_")
    p2 = run(["--method", "2", "--usb", d, "--yes", "--bd", "7"])
    assert p2.returncode != 0, "bd 7 must be refused"


def test_no_method_defaults_to_the_recommended_method():
    # Method 1 is the recommended method: since 30 Oct 2026 the helper restores
    # the player interface, so disc menus keep working. A run without --method
    # must build the Method 1 stick: the helper jar plus psr20_value.txt.
    d = tempfile.mkdtemp(prefix="usb_default_")
    run(["--usb", d, "--yes"])
    assert "psr20_value.txt" in os.listdir(d), \
        "the default did not build the recommended Method 1 stick"
    helper = os.path.join(USB, "BDJ-region-helper.jar")
    assert sha(os.path.join(d, "BDJ.jar")) == sha(helper), \
        "the default BDJ.jar is not the shipped helper"


def main():
    check("No --method picks the recommended method", test_no_method_defaults_to_the_recommended_method)
    check("Method 1 writes the helper stick", test_method1_writes_helper_layout)
    check("Method 1 takes a custom value and refuses >7",
          test_method1_custom_value_and_rejects_unsafe)
    check("Method 2 writes the chosen region and jar", test_method2_uses_given_jar_and_values)
    check("Method 2 supports skipping DVD and needs a jar",
          test_method2_dvd_skip_and_missing_jar)
    check("builder refuses a missing target and an invalid region",
          test_refuses_missing_target_and_bad_region)
    check("no-input run fails cleanly", test_no_input_gives_a_clean_message)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
