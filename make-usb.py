#!/usr/bin/env python3
"""Guided USB builder for the DP-UB450/UB150 region tool.

Asks which method you want and the few values that matter, writes the stick
and verifies every file against the repository by SHA-256.

  Method 2 (recommended): region switcher. One region at a time, USB only
  while it runs.
  Method 1 (both regions): play both regions. USB stays in the player; the
  first disc after a boot must be one the player starts anyway.

Run:  python3 make-usb.py
Flags (for scripted use): --method 1|2 --usb DIR [--psr20 N] [--bd 1|2|4]
                          [--dvd 0-6|skip] [--jar PATH] [--yes]
"""
import argparse
import hashlib
import os
import shutil
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
USB_SRC = os.path.join(REPO, "usb-files")


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def ask(prompt, default=None):
    suffix = " [%s]" % default if default is not None else ""
    try:
        v = input(prompt + suffix + ": ").strip()
    except EOFError:
        raise SystemExit("ERROR: no input available. Run interactively, or pass "
                         "--method and --usb (and the values) on the command line.")
    return v or default


def fail(msg):
    print("ERROR: " + msg, file=sys.stderr)
    return 1


def set_first_line(path, value):
    with open(path) as f:
        lines = f.read().split("\n")
    lines[0] = str(value)
    with open(path, "w") as f:
        f.write("\n".join(lines))


def copy_checked(src, dst):
    shutil.copyfile(src, dst)
    if sha(src) != sha(dst):
        raise RuntimeError("copy of %s does not match the source" % os.path.basename(src))


def write_method1(dst, psr20):
    for name, src in [
        ("BDJ_DEBUG", os.path.join(USB_SRC, "BDJ_DEBUG")),
        ("BDJ.jar", os.path.join(USB_SRC, "BDJ-region-helper.jar")),
        ("run.sh", os.path.join(USB_SRC, "run.sh")),
        ("bd_region.txt", os.path.join(USB_SRC, "bd_region.txt")),
    ]:
        copy_checked(src, os.path.join(dst, name))
    set_first_line(os.path.join(dst, "bd_region.txt"), "3")
    with open(os.path.join(dst, "psr20_value.txt"), "w") as f:
        f.write("%d\n" % psr20)
    open(os.path.join(dst, "dvd_region.txt"), "w").close()


def write_method2(dst, jar, bd, dvd):
    for name, src in [
        ("BDJ_DEBUG", os.path.join(USB_SRC, "BDJ_DEBUG")),
        ("run.sh", os.path.join(USB_SRC, "run.sh")),
        ("diag.sh", os.path.join(USB_SRC, "diag.sh")),
        ("USB-README.txt", os.path.join(USB_SRC, "USB-README.txt")),
        ("bd_region.txt", os.path.join(USB_SRC, "bd_region.txt")),
    ]:
        copy_checked(src, os.path.join(dst, name))
    copy_checked(jar, os.path.join(dst, "BDJ.jar"))
    set_first_line(os.path.join(dst, "bd_region.txt"), str(bd))
    dvd_path = os.path.join(dst, "dvd_region.txt")
    if dvd == "skip":
        open(dvd_path, "w").close()
    else:
        copy_checked(os.path.join(USB_SRC, "dvd_region.txt"), dvd_path)
        set_first_line(dvd_path, str(dvd))


def main():
    ap = argparse.ArgumentParser(description="Build the region-switch USB stick.")
    ap.add_argument("--method", choices=["1", "2"])
    ap.add_argument("--usb", help="path to the mounted USB stick")
    ap.add_argument("--psr20", help="Method 1 value (0-7, default 1)")
    ap.add_argument("--bd", help="Method 2 Blu-ray value: 1, 2 or 4")
    ap.add_argument("--dvd", help="Method 2 DVD value: 0-6 or skip")
    ap.add_argument("--jar", help="Method 2: path to a built BDJ.jar")
    ap.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    a = ap.parse_args()

    method = a.method or ("2" if a.yes else ask("Which method? 1 = both regions, 2 = region switcher (recommended)", "2"))
    if method not in ("1", "2"):
        return fail("method must be 1 or 2")
    usb = a.usb or ask("USB stick path (the mounted volume)")
    if not usb or not os.path.isdir(usb):
        return fail("USB path does not exist or is not a folder: %s" % usb)

    if method == "1":
        psr20 = int(a.psr20 if a.psr20 is not None else ("1" if a.yes else ask("Region value for the helper (0-7)", "1")))
        if not 0 <= psr20 <= 7:
            return fail("value %d is not allowed: use 0-7. 255 blanks the player; never go above 7." % psr20)
        if psr20 == 0:
            print("Warning: 0 is untested on the player.")
        plan = ("Method 1 (both regions): helper jar, bd_region=3, "
                "psr20=%d, DVD left alone" % psr20)
    else:
        bd = a.bd or ("1" if a.yes else ask("Blu-ray region: 1 = A, 2 = B, 4 = C", "1"))
        if bd not in ("1", "2", "4"):
            return fail("Blu-ray value must be 1, 2 or 4")
        dvd = a.dvd if a.dvd is not None else ("skip" if a.yes else ask("DVD region 0-6, or 'skip' to leave it alone", "skip"))
        if dvd != "skip" and (not dvd.isdigit() or not 0 <= int(dvd) <= 6):
            return fail("DVD value must be 0-6 or skip")
        jar = a.jar or os.path.join(USB_SRC, "BDJ.jar")
        if a.jar and not os.path.isfile(a.jar):
            return fail("BDJ.jar not found at %s" % a.jar)
        if not os.path.isfile(jar):
            return fail("no BDJ.jar to copy. Build it first:\n"
                        "  cd build && python3 build.py /path/to/PANA_DVD.FRM\n"
                        "or pass --jar /path/to/BDJ.jar")
        plan = "Method 2 (region switcher): bd_region=%s, DVD=%s" % (bd, "unchanged" if dvd == "skip" else dvd)

    existing = [n for n in ("BDJ_DEBUG", "BDJ.jar", "run.sh", "bd_region.txt") if os.path.exists(os.path.join(usb, n))]
    print("\nTarget: " + usb)
    print("Plan:   " + plan)
    if existing and not a.yes:
        ans = ask("The stick already has " + ", ".join(existing) + " - overwrite? (y/n)", "n")
        if ans.lower() != "y":
            return fail("cancelled")

    try:
        if method == "1":
            write_method1(usb, psr20)
        else:
            write_method2(usb, jar, bd, dvd)
    except RuntimeError as e:
        return fail(str(e))

    print("\nWritten and verified:")
    for n in sorted(os.listdir(usb)):
        p = os.path.join(usb, n)
        if os.path.isfile(p) and n in ("BDJ_DEBUG", "BDJ.jar", "run.sh", "bd_region.txt",
                                       "psr20_value.txt", "dvd_region.txt", "diag.sh", "USB-README.txt"):
            print("  %-16s %8d bytes" % (n, os.path.getsize(p)))
    print("\nNext steps:")
    if method == "1":
        print("  1. Unplug the player, insert the stick, power on. If the USB media menu")
        print("     appears, press Return.")
        print("  2. Wait for the home screen plus ~15 s, then insert a playable Blu-ray")
        print("     with BD-J and wait ~30 s (first run only).")
        print("  3. Unplug the player, power on once more.")
        print("  Keep the stick in the player while watching.")
        print("  Insert a disc the player starts anyway (A+B, e.g. Chernobyl, or one")
        print("  of the player's own region) first: it sets the region register,")
        print("  then every disc in that session plays.")
        print("  Disc menus keep working; the helper restores the player interface.")
    else:
        print("  1. Unplug the player, insert the stick, power on.")
        print("  2. Wait for the home screen plus ~15 s, then insert a playable Blu-ray")
        print("     with BD-J and wait ~30 s.")
        print("  3. Unplug the player, remove the stick, power on and play that region.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
