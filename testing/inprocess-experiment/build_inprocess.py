#!/usr/bin/env python3
"""Build a BDJ.jar that runs run.sh, then com.mtk.utils.Psr20Probe.run()."""
import hashlib
import os
import shutil
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "build"))
import build  # noqa: E402

TARGET = "com/mtk/utils/BDJCompilerOption.class"
PROBE_NAME = os.environ.get("PROBE_NAME", "com/mtk/utils/Psr20Probe")
PROBE_METHOD = os.environ.get("PROBE_METHOD", "run")
PROBE_FILE = os.environ.get(
    "PROBE_FILE", os.path.join(HERE, "out", "com", "mtk", "utils", "Psr20Probe.class"))


def add_probe_call(class_path, probe="com/mtk/utils/Psr20Probe", method="run", desc="()V"):
    d = bytearray(open(class_path, "rb").read())
    cp_count = struct.unpack(">H", d[8:10])[0]
    pos = 10
    cp_offsets = [0] * cp_count
    i = 1
    while i < cp_count:
        cp_offsets[i] = pos
        tag = d[pos]
        if tag == 1:
            ln = struct.unpack(">H", d[pos + 1:pos + 3])[0]
            pos += 3 + ln
        elif tag in (7, 8, 16):
            pos += 3
        elif tag in (9, 10, 11, 12, 18):
            pos += 5
        elif tag in (3, 4):
            pos += 5
        elif tag in (5, 6):
            pos += 9
            i += 1
        elif tag == 15:
            pos += 4
        else:
            raise ValueError(f"unknown cp tag {tag}")
        i += 1
    cp_end = pos

    new_entries = bytearray()
    base = cp_count

    def utf8(s):
        nonlocal new_entries, base
        b = s.encode()
        new_entries += bytes([1]) + struct.pack(">H", len(b)) + b
        r = base
        base += 1
        return r

    def cls(n):
        nonlocal new_entries, base
        new_entries += bytes([7]) + struct.pack(">H", n)
        r = base
        base += 1
        return r

    def nat(n, t):
        nonlocal new_entries, base
        new_entries += bytes([12]) + struct.pack(">HH", n, t)
        r = base
        base += 1
        return r

    def mref(c, n):
        nonlocal new_entries, base
        new_entries += bytes([10]) + struct.pack(">HH", c, n)
        r = base
        base += 1
        return r

    c = cls(utf8(probe))
    mr = mref(c, nat(utf8(method), utf8(desc)))

    d[8:10] = struct.pack(">H", base)
    d = d[:cp_end] + new_entries + d[cp_end:]

    clinit_ui = code_ui = None
    for ci in range(1, cp_count):
        if d[cp_offsets[ci]] == 1:
            ln = struct.unpack(">H", d[cp_offsets[ci] + 1:cp_offsets[ci] + 3])[0]
            v = d[cp_offsets[ci] + 3:cp_offsets[ci] + 3 + ln]
            if v == b"<clinit>":
                clinit_ui = ci
            if v == b"Code":
                code_ui = ci

    p = cp_end + len(new_entries) + 6
    iface_count = struct.unpack(">H", d[p:p + 2])[0]
    p += 2 + 2 * iface_count
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

    method_count = struct.unpack(">H", d[p:p + 2])[0]
    p += 2
    clinit_pos = None
    for _ in range(method_count):
        mn = struct.unpack(">H", d[p + 2:p + 4])[0]
        p += 6
        is_clinit = (mn == clinit_ui)
        mac = struct.unpack(">H", d[p:p + 2])[0]
        p += 2
        for _ in range(mac):
            an = struct.unpack(">H", d[p:p + 2])[0]
            p += 2
            al = struct.unpack(">I", d[p:p + 4])[0]
            p += 4
            if is_clinit and an == code_ui:
                clinit_pos = p
            p += al

    if clinit_pos is None:
        raise ValueError("clinit Code not found")
    code_len = struct.unpack(">I", d[clinit_pos + 4:clinit_pos + 8])[0]
    code_start = clinit_pos + 8
    if d[code_start + code_len - 1] != 0xB1:
        raise ValueError("last opcode is not return")

    inject = bytes([0xB8]) + struct.pack(">H", mr) + bytes([0xB1])
    new_code = d[code_start:code_start + code_len - 1] + inject
    d = d[:code_start] + new_code + d[code_start + code_len:]
    new_len = len(new_code)
    d[clinit_pos + 4:clinit_pos + 8] = struct.pack(">I", new_len)
    attr_len_pos = clinit_pos - 4
    old_attr = struct.unpack(">I", d[attr_len_pos:attr_len_pos + 4])[0]
    d[attr_len_pos:attr_len_pos + 4] = struct.pack(">I", old_attr + (new_len - code_len))
    open(class_path, "wb").write(d)
    return len(inject)


def main():
    firmware = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(REPO), "firmware", "AU_UPDATE_UB150_450_V127", "PANA_DVD.FRM")
    out_jar = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "BDJ.jar")
    if not os.path.exists(PROBE_FILE):
        print(f"Error: probe class missing: {PROBE_FILE}")
        sys.exit(1)

    work = tempfile.mkdtemp(prefix="inproc_")
    try:
        czf = os.path.join(work, "BDJ.czf")
        build.extract_czf_from_firmware(firmware, czf)
        classes = os.path.join(work, "classes")
        count = build.extract_czf(czf, classes)
        print(f"Extracted {count} classes")

        target = os.path.join(classes, TARGET)
        build.set_permission_flag(target)
        build.add_exec(target)
        n = add_probe_call(target, PROBE_NAME, PROBE_METHOD)
        print(f"Probe call injected ({n} bytes)")

        dst = os.path.join(classes, *PROBE_NAME.split("/")) + ".class"
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(PROBE_FILE, dst)
        print(f"Probe class: {os.path.getsize(PROBE_FILE)} bytes")

        size = build.build_jar(classes, out_jar)
        sha = hashlib.sha256(open(out_jar, "rb").read()).hexdigest()
        print(f"Built: {out_jar} ({size} bytes)")
        print(f"SHA-256: {sha}")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
