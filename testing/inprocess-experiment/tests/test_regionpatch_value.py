#!/usr/bin/env python3
"""Tests for the region value file read by RegionPatch.

The probe must take the PSR 20 value from /mnt/sda1/psr20_value.txt (first
digit), defaulting to 7 when the file is missing or unreadable, so the value
can be changed on the stick or over the LAN without rebuilding the jar.

Run: python3 testing/inprocess-experiment/tests/test_regionpatch_value.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(EXP))
SRC = os.path.join(EXP, "RegionPatch.java")
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
    work = tempfile.mkdtemp(prefix="rpval_")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                       capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]


def test_reads_value_file_with_default():
    src = open(SRC).read()
    assert "/mnt/sda1/psr20_value.txt" in src, "value file path missing"
    assert "FileInputStream" in src, "must read it with a stream (no java.io.File)"
    assert "catch (Throwable" in src, "a missing file must not throw out of run()"
    assert "StringBuilder" not in src, "StringBuilder is absent from this CVM"


def run_parse(c0, c1, c2):
    """Compile RegionPatch + harness and return parseValue(c0,c1,c2)."""
    work = tempfile.mkdtemp(prefix="rpval_run_")
    h = os.path.join(HERE, "ValueHarness.java")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work,
                        SRC, h], capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]
    q = subprocess.run(["java", "-cp", work + os.pathsep + CLASSES, "ValueHarness",
                        str(c0), str(c1), str(c2)],
                       capture_output=True, text=True)
    assert q.returncode == 0, "harness failed: " + q.stderr[-400:]
    return int(q.stdout.strip())


def test_parses_up_to_three_digits():
    # 255 (0xFF) is the region-free value real players use; today only 1-9 work.
    assert run_parse(ord("2"), ord("5"), ord("5")) == 255, "must read three digits"
    assert run_parse(ord("1"), -1, -1) == 1, "one digit then EOF"
    assert run_parse(ord("7"), ord("\n"), -1) == 7, "newline ends the number"
    assert run_parse(ord("0"), ord("\n"), -1) == 0, "zero is a real value"
    assert run_parse(ord("9"), ord("9"), ord("9")) == -1, "999 is out of range"
    assert run_parse(-1, -1, -1) == -1, "empty file is invalid"


def run_default(v):
    """Compile RegionPatch + harness and return valueOrDefault(v)."""
    work = tempfile.mkdtemp(prefix="rpdef_run_")
    h = os.path.join(HERE, "ValueHarness.java")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work,
                        SRC, h], capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]
    q = subprocess.run(["java", "-cp", work + os.pathsep + CLASSES, "ValueHarness",
                        "default", str(v)], capture_output=True, text=True)
    assert q.returncode == 0, "harness failed: " + q.stderr[-400:]
    return int(q.stdout.strip())


def test_default_value_is_1():
    # Value 1 plays locked A discs and the lax locked B disc (29 Oct 2026);
    # 7 makes strict A discs refuse, so 1 is the safer fallback.
    assert run_default(-1) == 1, "a missing/invalid value file must fall back to 1"
    assert run_default(0) == 0, "0 is a real value, not a fallback"
    assert run_default(7) == 7, "an explicit value must be used as given"


def test_shipped_jar_matches_source():
    """The shipped jar's RegionPatch.class must equal a fresh build of the
    source (compile -> downgrade), so a stale jar cannot ship."""
    jar = os.path.join(REPO, "usb-files", "BDJ-region-helper.jar")
    work = tempfile.mkdtemp(prefix="rpjar_")
    subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                   check=True, capture_output=True)
    cls = os.path.join(work, "com", "mtk", "utils", "RegionPatch.class")
    subprocess.run(["python3", os.path.join(EXP, "downgrade_class.py"), cls],
                   check=True, capture_output=True)
    fresh = open(cls, "rb").read()
    shipped = subprocess.run(["unzip", "-p", jar, "com/mtk/utils/RegionPatch.class"],
                             capture_output=True, check=True).stdout
    assert fresh == shipped, "shipped RegionPatch.class differs from a fresh build - rebuild the jar"


def test_shipped_helper_calls_static_go():
    """The shipped jar must invoke RegionPatch.go (static); run is an
    instance method, so invokestatic run aborts the class initialiser and
    blanks the player (seen 29 Oct 2026 with a locally rebuilt jar)."""
    jar = os.path.join(REPO, "usb-files", "BDJ-region-helper.jar")
    work = tempfile.mkdtemp(prefix="rpgo_")
    subprocess.run(["unzip", "-q", "-o", jar, "com/mtk/utils/BDJCompilerOption.class",
                    "-d", work], check=True)
    cls = os.path.join(work, "com", "mtk", "utils", "BDJCompilerOption.class")
    p = subprocess.run(["javap", "-p", "-c", cls], capture_output=True, text=True)
    assert p.returncode == 0, "javap failed: " + p.stderr[-300:]
    assert "RegionPatch.go:()V" in p.stdout, "shipped jar does not call RegionPatch.go"
    assert "RegionPatch.run" not in p.stdout, "shipped jar calls RegionPatch.run (instance method)"


def main():
    check("RegionPatch compiles for this CVM", test_compiles)
    check("RegionPatch reads the value file, defaulting safely",
          test_reads_value_file_with_default)
    check("RegionPatch parses 0-255 from the value file", test_parses_up_to_three_digits)
    check("RegionPatch falls back to value 1", test_default_value_is_1)
    check("shipped jar matches a fresh build of the source", test_shipped_jar_matches_source)
    check("shipped helper calls static RegionPatch.go", test_shipped_helper_calls_static_go)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
