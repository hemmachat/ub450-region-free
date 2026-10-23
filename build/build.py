#!/usr/bin/env python3
"""
Build BDJ.jar for the DP-UB450/UB150 region-free tool.

Accepts either:
  - The firmware update file (PANA_DVD.FRM) — extracts BDJ.czf automatically
  - A previously extracted BDJ.czf file

Usage:
    python3 build.py PANA_DVD.FRM
    python3 build.py BDJ.czf

Requires: Python 3, and unsquashfs (if using .FRM input).
  macOS:  brew install squashfs
  Linux:  sudo apt install squashfs-tools  (usually pre-installed)

Output: usb-files/BDJ.jar (or BDJ.jar in the current directory).
"""

import struct
import zipfile
import zlib
import os
import sys
import tempfile
import shutil
import subprocess
import hashlib


SQFS_MAGIC = b"hsqs"
CZF_PATH_IN_FIRMWARE = "lib/BDJ.czf"
TARGET_CLASS = "com/mtk/utils/BDJCompilerOption.class"


def find_sqfs_offset(data):
    """Find the SquashFS filesystem offset inside a firmware .FRM file."""
    idx = data.find(SQFS_MAGIC)
    if idx < 0:
        return None
    return idx


def extract_czf_from_firmware(frm_path, out_path):
    """Extract BDJ.czf from a PANA_DVD.FRM firmware file."""
    if shutil.which("unsquashfs") is None:
        print("Error: unsquashfs not found.")
        print("  macOS:  brew install squashfs")
        print("  Linux:  sudo apt install squashfs-tools")
        sys.exit(1)

    data = open(frm_path, "rb").read()
    offset = find_sqfs_offset(data)
    if offset is None:
        print("Error: no SquashFS filesystem found in firmware file.")
        print("The UB820/UB9000 firmware (PANAEUSB.FRM) is encrypted and can't")
        print("be used. Use the UB450 or UB150 firmware (PANA_DVD.FRM) instead —")
        print("the BD-Java classes are the same across the platform.")
        sys.exit(1)

    print(f"       SquashFS found at offset 0x{offset:x}")

    tmp = tempfile.mkdtemp(prefix="ub450_sqfs_")
    sqfs_path = os.path.join(tmp, "rootfs.sqfs")
    try:
        open(sqfs_path, "wb").write(data[offset:])
        result = subprocess.run(
            ["unsquashfs", "-f", "-d", os.path.join(tmp, "root"),
             sqfs_path, CZF_PATH_IN_FIRMWARE],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"Error: unsquashfs failed: {result.stderr.strip()}")
            sys.exit(1)

        extracted = os.path.join(tmp, "root", CZF_PATH_IN_FIRMWARE)
        if not os.path.exists(extracted):
            print(f"Error: {CZF_PATH_IN_FIRMWARE} not found in firmware.")
            sys.exit(1)

        shutil.copy2(extracted, out_path)
        return out_path
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def extract_czf(czf_path, out_dir):
    """Extract BDJ.czf, handling method-24 (raw deflate) entries."""
    data = open(czf_path, "rb").read()
    zf = zipfile.ZipFile(czf_path, "r")
    count = 0
    for info in zf.infolist():
        out_path = os.path.join(out_dir, info.filename)
        if info.is_dir():
            os.makedirs(out_path, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        if info.compress_type == 24:
            off = info.header_offset
            name_len = struct.unpack("<H", data[off + 26:off + 28])[0]
            extra_len = struct.unpack("<H", data[off + 28:off + 30])[0]
            comp_start = off + 30 + name_len + extra_len
            raw = data[comp_start:comp_start + info.compress_size]
            for wbits in [-15, 0, 15, 31]:
                try:
                    decompressed = zlib.decompress(raw, wbits)
                    if len(decompressed) == info.file_size:
                        open(out_path, "wb").write(decompressed)
                        count += 1
                        break
                except Exception:
                    pass
        else:
            open(out_path, "wb").write(zf.read(info.filename))
            count += 1
    return count


def set_permission_flag(class_path):
    """
    Set ENABLE_CHECK_PERMISSION to false.

    Bytecode: 04 B3 00 6D → 03 B3 00 6D (iconst_1 → iconst_0)
    """
    d = bytearray(open(class_path, "rb").read())
    target = bytes([0x04, 0xB3, 0x00, 0x6D])
    idx = d.find(target)
    if idx < 0:
        raise ValueError("Pattern 04 B3 00 6D not found in class file")
    d[idx] = 0x03
    open(class_path, "wb").write(d)
    return idx


def add_exec(class_path, command="/bin/sh /mnt/sda1/run.sh"):
    """
    Add Runtime.exec(command) to the class's static initialiser.

    Adds constant pool entries for Runtime.getRuntime() and Runtime.exec(),
    then appends bytecode before the return instruction in <clinit>.
    """
    d = bytearray(open(class_path, "rb").read())

    # Parse constant pool
    cp_count = struct.unpack(">H", d[8:10])[0]
    pos = 10
    cp_offsets = [0] * cp_count
    i = 1
    while i < cp_count:
        cp_offsets[i] = pos
        tag = d[pos]
        if tag == 1:  # Utf8
            length = struct.unpack(">H", d[pos + 1:pos + 3])[0]
            pos += 3 + length
        elif tag in (7, 8):  # Class, String
            pos += 3
        elif tag in (9, 10, 11, 12):  # Field/Method/InterfaceMethod/NameAndType
            pos += 5
        elif tag in (3, 4):  # Integer, Float
            pos += 5
        elif tag in (5, 6):  # Long, Double
            pos += 9
            i += 1
        elif tag == 15:  # MethodHandle
            pos += 4
        elif tag == 16:  # MethodType
            pos += 3
        elif tag == 18:  # InvokeDynamic
            pos += 5
        else:
            raise ValueError(f"Unknown constant pool tag {tag} at offset {pos}")
        i += 1
    cp_end = pos

    # Helper to add constant pool entries
    new_entries = bytearray()
    base_idx = cp_count

    def add_utf8(s):
        nonlocal new_entries, base_idx
        b = s.encode("utf-8")
        new_entries += bytes([1]) + struct.pack(">H", len(b)) + b
        idx = base_idx
        base_idx += 1
        return idx

    def add_class(name_idx):
        nonlocal new_entries, base_idx
        new_entries += bytes([7]) + struct.pack(">H", name_idx)
        idx = base_idx
        base_idx += 1
        return idx

    def add_nat(name_idx, desc_idx):
        nonlocal new_entries, base_idx
        new_entries += bytes([12]) + struct.pack(">H", name_idx) + struct.pack(">H", desc_idx)
        idx = base_idx
        base_idx += 1
        return idx

    def add_methodref(class_idx, nat_idx):
        nonlocal new_entries, base_idx
        new_entries += bytes([10]) + struct.pack(">H", class_idx) + struct.pack(">H", nat_idx)
        idx = base_idx
        base_idx += 1
        return idx

    def add_string(utf8_idx):
        nonlocal new_entries, base_idx
        new_entries += bytes([8]) + struct.pack(">H", utf8_idx)
        idx = base_idx
        base_idx += 1
        return idx

    # Add Runtime class and methods
    u_rt = add_utf8("java/lang/Runtime")
    c_rt = add_class(u_rt)
    u_gr = add_utf8("getRuntime")
    u_gr_d = add_utf8("()Ljava/lang/Runtime;")
    nat_gr = add_nat(u_gr, u_gr_d)
    mr_gr = add_methodref(c_rt, nat_gr)
    u_ex = add_utf8("exec")
    u_ex_d = add_utf8("(Ljava/lang/String;)Ljava/lang/Process;")
    nat_ex = add_nat(u_ex, u_ex_d)
    mr_ex = add_methodref(c_rt, nat_ex)
    u_cmd = add_utf8(command)
    s_cmd = add_string(u_cmd)

    # Update constant pool count
    d[8:10] = struct.pack(">H", base_idx)
    d = d[:cp_end] + new_entries + d[cp_end:]

    # Build additional bytecode
    inject = bytearray()
    inject += bytes([0xB8])  # invokestatic Runtime.getRuntime()
    inject += struct.pack(">H", mr_gr)
    if s_cmd < 256:
        inject += bytes([0x12, s_cmd])  # ldc
    else:
        inject += bytes([0x13]) + struct.pack(">H", s_cmd)  # ldc_w
    inject += bytes([0xB6])  # invokevirtual Runtime.exec(String)
    inject += struct.pack(">H", mr_ex)
    inject += bytes([0x57])  # pop
    inject += bytes([0xB1])  # return

    # Find <clinit> and "Code" in constant pool
    clinit_ui = code_ui = None
    for ci in range(1, cp_count):
        if d[cp_offsets[ci]] == 1:
            le = struct.unpack(">H", d[cp_offsets[ci] + 1:cp_offsets[ci] + 3])[0]
            val = d[cp_offsets[ci] + 3:cp_offsets[ci] + 3 + le]
            if val == b"<clinit>":
                clinit_ui = ci
            if val == b"Code":
                code_ui = ci

    # Skip to methods section
    p = cp_end + len(new_entries)
    p += 6  # access_flags, this_class, super_class
    iface_count = struct.unpack(">H", d[p:p + 2])[0]
    p += 2 + 2 * iface_count

    # Skip fields
    field_count = struct.unpack(">H", d[p:p + 2])[0]
    p += 2
    for _ in range(field_count):
        p += 6
        ac = struct.unpack(">H", d[p:p + 2])[0]
        p += 2
        for _ in range(ac):
            p += 2
            al = struct.unpack(">I", d[p:p + 4])[0]
            p += 4 + al

    # Find clinit Code attribute
    method_count = struct.unpack(">H", d[p:p + 2])[0]
    p += 2
    clinit_code_pos = None
    for _ in range(method_count):
        m_name = struct.unpack(">H", d[p + 2:p + 4])[0]
        p += 6
        is_clinit = (m_name == clinit_ui)
        mac = struct.unpack(">H", d[p:p + 2])[0]
        p += 2
        for _ in range(mac):
            a_name = struct.unpack(">H", d[p:p + 2])[0]
            p += 2
            a_len = struct.unpack(">I", d[p:p + 4])[0]
            p += 4
            if is_clinit and a_name == code_ui:
                clinit_code_pos = p
            p += a_len

    if clinit_code_pos is None:
        raise ValueError("clinit Code attribute not found")

    # Modify clinit bytecode
    cpos = clinit_code_pos
    code_length = struct.unpack(">I", d[cpos + 4:cpos + 8])[0]
    code_start = cpos + 8

    if d[code_start + code_length - 1] != 0xB1:
        raise ValueError(f"Last bytecode is 0x{d[code_start + code_length - 1]:02x}, expected return")

    new_code = d[code_start:code_start + code_length - 1] + inject
    d = d[:code_start] + new_code + d[code_start + code_length:]

    new_len = len(new_code)
    d[cpos + 4:cpos + 8] = struct.pack(">I", new_len)

    # Update Code attribute length
    attr_len_pos = clinit_code_pos - 4
    old_attr_len = struct.unpack(">I", d[attr_len_pos:attr_len_pos + 4])[0]
    d[attr_len_pos:attr_len_pos + 4] = struct.pack(">I", old_attr_len + (new_len - code_length))

    # Ensure max_stack >= 2
    ms = struct.unpack(">H", d[cpos:cpos + 2])[0]
    if ms < 2:
        d[cpos:cpos + 2] = struct.pack(">H", 2)

    open(class_path, "wb").write(d)
    return len(inject)


def build_jar(class_dir, jar_path):
    """Package all class files into a standard ZIP/JAR."""
    with zipfile.ZipFile(jar_path, "w", zipfile.ZIP_DEFLATED) as zout:
        for root, dirs, files in os.walk(class_dir):
            for fname in files:
                fpath = os.path.join(root, fname)
                arcname = os.path.relpath(fpath, class_dir)
                zout.write(fpath, arcname)
    return os.path.getsize(jar_path)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <PANA_DVD.FRM or BDJ.czf>")
        print()
        print("  PANA_DVD.FRM  — firmware update file (downloads from the manufacturer's site)")
        print("  BDJ.czf       — extracted from the player's firmware at /lib/BDJ.czf")
        sys.exit(1)

    input_path = sys.argv[1]
    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found")
        sys.exit(1)

    work_dir = tempfile.mkdtemp(prefix="ub450_build_")

    # Output path: prefer usb-files/ if it exists alongside build/
    script_dir = os.path.dirname(os.path.abspath(__file__))
    usb_dir = os.path.join(os.path.dirname(script_dir), "usb-files")
    if os.path.isdir(usb_dir):
        jar_path = os.path.join(usb_dir, "BDJ.jar")
    else:
        jar_path = os.path.join(os.getcwd(), "BDJ.jar")

    try:
        # Determine input type
        with open(input_path, "rb") as f:
            header = f.read(4)

        if header[:2] == b"PK":
            czf_path = input_path
            print(f"[1/4] Using BDJ.czf: {czf_path}")
        else:
            print(f"[1/4] Extracting BDJ.czf from firmware...")
            czf_path = os.path.join(work_dir, "BDJ.czf")
            extract_czf_from_firmware(input_path, czf_path)
            print(f"       Extracted BDJ.czf ({os.path.getsize(czf_path)} bytes)")

        print("[2/4] Extracting and modifying classes...")
        class_dir = os.path.join(work_dir, "classes")
        count = extract_czf(czf_path, class_dir)
        print(f"       Extracted {count} files")

        class_file = os.path.join(class_dir, TARGET_CLASS)
        if not os.path.exists(class_file):
            print(f"Error: {TARGET_CLASS} not found in archive")
            sys.exit(1)

        offset = set_permission_flag(class_file)
        print(f"       Permission flag set at offset {offset}")

        print("[3/4] Adding exec call...")
        size = add_exec(class_file)
        print(f"       Added {size} bytes")

        print(f"[4/4] Building {jar_path}...")
        jar_size = build_jar(class_dir, jar_path)
        sha = hashlib.sha256(open(jar_path, "rb").read()).hexdigest()
        print(f"       Built: {jar_path} ({jar_size / 1024 / 1024:.1f} MB)")
        print(f"       SHA-256: {sha}")
        print()
        print("Done. Copy BDJ.jar, BDJ_DEBUG, and run.sh to your USB drive.")

    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
