#!/usr/bin/env python3
"""Tests for the region value file read by RegionPatch.

The probe must take the PSR 20 value from /mnt/sda1/psr20_value.txt (first
digit), defaulting to 1 when the file is missing or unreadable, so the value
can be changed on the stick or over the LAN without rebuilding the jar. It
must read PSR 20 through the player's own interface before replacing it, and
skip the patch when the value is already set (that keeps disc menus working
after the disc's Java restarts).

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


def run_already(now, want):
    """Compile RegionPatch + harness and return alreadySet(now, want)."""
    work = tempfile.mkdtemp(prefix="rpalr_run_")
    h = os.path.join(HERE, "ValueHarness.java")
    p = subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work,
                        SRC, h], capture_output=True, text=True)
    assert p.returncode == 0, "javac failed: " + p.stderr[-400:]
    q = subprocess.run(["java", "-cp", work + os.pathsep + CLASSES, "ValueHarness",
                        "already", str(now), str(want)], capture_output=True, text=True)
    assert q.returncode == 0, "harness failed: " + q.stderr[-400:]
    return int(q.stdout.strip())


def test_skips_when_the_register_already_holds_the_value():
    # The helper only has to set the register once per session. Keeping the
    # player's own interface in place afterwards is what keeps disc menus
    # working, so an already-correct value must skip the patch.
    assert run_already(1, 1) == 1, "1 already set -> skip"
    assert run_already(2, 2) == 1, "same value -> skip"
    assert run_already(2, 1) == 0, "2 -> 1 needs the patch"
    assert run_already(-1, 1) == 0, "unknown value -> patch as before"
    assert run_already(7, 1) == 0, "7 -> 1 needs the patch"


def compiled_run_body():
    """javap -c output for RegionPatch.run()."""
    work = tempfile.mkdtemp(prefix="rpord_")
    subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                   check=True, capture_output=True)
    cls = os.path.join(work, "com", "mtk", "utils", "RegionPatch.class")
    out = subprocess.run(["javap", "-p", "-c", cls], capture_output=True, text=True,
                         check=True).stdout
    assert "public void run();" in out, "run() not found in the class"
    body = out.split("public void run();", 1)[1]
    return body.split("\n\n", 1)[0]


def test_reads_the_register_before_replacing_the_interface():
    body = compiled_run_body()
    get = body.find("RegisterAccess.getPSR")
    alloc = body.find("NativeCopier.allocate")
    assert get >= 0, "run() never reads PSR 20 through the player's own interface"
    assert alloc >= 0, "run() no longer installs the stubs"
    assert get < alloc, "PSR 20 is read after the interface is replaced - the skip cannot work"


def test_skip_is_visible_in_the_log():
    # patch_result.txt is the only way to tell from the stick that the helper
    # stayed out of the way, so the message must be in the shipped class.
    work = tempfile.mkdtemp(prefix="rplog_")
    subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC],
                   check=True, capture_output=True)
    cls = os.path.join(work, "com", "mtk", "utils", "RegionPatch.class")
    out = subprocess.run(["javap", "-v", cls], capture_output=True, text=True,
                         check=True).stdout
    assert "already set, patch skipped" in out, "a skipped patch must be visible in patch_result.txt"


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



def run_inregion(maps, addr, flag):
    work = tempfile.mkdtemp(prefix="rpin_")
    h = os.path.join(HERE, "ValueHarness.java")
    subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC, h],
                   check=True, capture_output=True)
    q = subprocess.run(["java", "-cp", work + os.pathsep + CLASSES, "ValueHarness",
                        "inregion", maps, addr, flag], capture_output=True, text=True)
    assert q.returncode == 0, "harness failed: " + q.stderr[-300:]
    return int(q.stdout.strip())


def test_inregion_reads_permissions():
    maps = ("00010000-00020000 r-xp 00000000 1f:10 1 /bin/bdpprog\n"
            "00020000-00040000 rw-p 00000000 00:00 0\n")
    assert run_inregion(maps, "00025000", "w") == 1, "writable region not found"
    assert run_inregion(maps, "00025000", "x") == 0, "w region wrongly executable"
    assert run_inregion(maps, "00015000", "x") == 1, "executable region not found"
    assert run_inregion(maps, "00050000", "w") == 0, "unmapped address accepted"


def test_restores_the_player_interface():
    src = open(SRC).read()
    assert "findAdapter" in src, "no adapter lookup"
    assert "restored=" in src, "restore is not visible in patch_result.txt"
    assert "0x010fec00L" in src, "restore does not write the adapter pointer"


def test_scan_target_is_masked():
    src = open(SRC).read()
    assert "SCAN_MASK" in src, "scan target is not masked; the heap cannot be scanned"
    assert "0xC92B20L ^ SCAN_MASK" in src, "scan target is not stored XORed"



MAPS = ("00010000-00020000 r-xp 00000000 1f:10 1 /bin/bdpprog\n"
        "00020000-00040000 rw-p 00000000 00:00 0\n")


def run_candok(obj, m2, vptr):
    work = tempfile.mkdtemp(prefix="rpcand_")
    h = os.path.join(HERE, "ValueHarness.java")
    subprocess.run(["javac", "--release", "8", "-cp", CLASSES, "-d", work, SRC, h],
                   check=True, capture_output=True)
    q = subprocess.run(["java", "-cp", work + os.pathsep + CLASSES, "ValueHarness",
                        "candok", MAPS, "%x" % obj, "%x" % m2, "%x" % vptr],
                       capture_output=True, text=True)
    assert q.returncode == 0, "harness failed: " + q.stderr[-300:]
    return int(q.stdout.strip())


def test_candidate_rules():
    assert run_candok(0x25000, 0x30000, 0x15000) == 1, "valid candidate rejected"
    assert run_candok(0x25002, 0x30000, 0x15000) == 0, "unaligned object accepted"
    assert run_candok(0x25000, 0, 0x15000) == 0, "null backend accepted"
    assert run_candok(0x25000, 0x15000, 0x15000) == 0, "read-only backend accepted"
    assert run_candok(0x25000, 0x30000, 0) == 0, "null vtable accepted"
    assert run_candok(0x25000, 0x30000, 0x15001) == 0, "odd vtable accepted"
    assert run_candok(0x25000, 0x30000, 0x30000) == 0, "non-executable vtable accepted"


def main():
    check("RegionPatch compiles for this CVM", test_compiles)
    check("RegionPatch reads the value file, defaulting safely",
          test_reads_value_file_with_default)
    check("RegionPatch parses 0-255 from the value file", test_parses_up_to_three_digits)
    check("RegionPatch falls back to value 1", test_default_value_is_1)
    check("RegionPatch skips the patch when the value is already set",
          test_skips_when_the_register_already_holds_the_value)
    check("RegionPatch reads PSR 20 before replacing the interface",
          test_reads_the_register_before_replacing_the_interface)
    check("a skipped patch is visible in patch_result.txt", test_skip_is_visible_in_the_log)
    check("inRegion reads the map permissions", test_inregion_reads_permissions)
    check("the helper restores the player's interface", test_restores_the_player_interface)
    check("the scan target is masked", test_scan_target_is_masked)
    check("the candidate rule accepts only the real adapter", test_candidate_rules)
    check("shipped jar matches a fresh build of the source", test_shipped_jar_matches_source)
    check("shipped helper calls static RegionPatch.go", test_shipped_helper_calls_static_go)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
