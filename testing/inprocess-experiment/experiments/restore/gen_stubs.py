#!/usr/bin/env python3
"""Assemble stubs.s with clang, apply the branch relocation clang leaves for
the forward jump, and print the hex blob plus the offsets the Java side needs
(setgpr entry, scan literals)."""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def parse(d):
    e_shoff = struct.unpack("<I", d[32:36])[0]
    e_shentsize = struct.unpack("<H", d[46:48])[0]
    e_shnum = struct.unpack("<H", d[48:50])[0]
    e_shstrndx = struct.unpack("<H", d[50:52])[0]
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        name, stype, flags, addr, offset, size, link, info, align, entsize = \
            struct.unpack("<IIIIIIIIII", d[off:off + 40])
        secs.append(dict(name=name, type=stype, offset=offset, size=size,
                         link=link, info=info, entsize=entsize))
    names = d[secs[e_shstrndx]["offset"]:secs[e_shstrndx]["offset"] + secs[e_shstrndx]["size"]]

    def nm(n):
        s = names[n:]
        return s[:s.index(b"\0")].decode()
    for s in secs:
        s["sname"] = nm(s["name"])
    return secs


def symtab(d, secs):
    st = next(s for s in secs if s["type"] == 2)
    strtab = secs[st["link"]]
    names = d[strtab["offset"]:strtab["offset"] + strtab["size"]]
    out = []
    for i in range(st["size"] // st["entsize"]):
        off = st["offset"] + i * st["entsize"]
        name, value, size, info, other, shndx = struct.unpack("<IIIBBH", d[off:off + 16])
        s = names[name:]
        out.append((s[:s.index(b"\0")].decode(), value, size))
    return out


def apply_relocs(code, d, secs, syms):
    """Resolve R_ARM_CALL/JUMP24 (28/29) against symbol addresses."""
    for s in secs:
        if s["type"] != 9 or secs[s["info"]]["sname"] != ".text":
            continue
        for i in range(s["size"] // 8):
            off, info = struct.unpack("<II", d[s["offset"] + i * 8:s["offset"] + i * 8 + 8])
            rtype = info & 0xff
            sym = info >> 8
            if rtype not in (28, 29):
                raise SystemExit("unhandled relocation type %d at 0x%x" % (rtype, off))
            word = struct.unpack("<I", code[off:off + 4])[0]
            imm = word & 0xffffff
            if imm & 0x800000:
                imm -= 0x1000000
            addend = imm << 2
            target = syms[sym][1]
            new = (target + addend - off) >> 2
            word = (word & 0xff000000) | (new & 0xffffff)
            code[off:off + 4] = struct.pack("<I", word)
    return code


def main():
    src = os.path.join(HERE, "stubs.s")
    obj = os.path.join(HERE, "stubs.o")
    subprocess.run(["clang", "-target", "armv7-none-eabi", "-c", src, "-o", obj],
                   check=True)
    d = open(obj, "rb").read()
    secs = parse(d)
    text = next(s for s in secs if s["sname"] == ".text")
    code = bytearray(d[text["offset"]:text["offset"] + text["size"]])
    syms = symtab(d, secs)
    code = apply_relocs(code, d, secs, syms)
    print("blob_len=%d" % len(code))
    print("hex=" + bytes(code).hex())
    for name, value, size in syms:
        if name in ("setgpr_scan", "scan"):
            print("%s offset=0x%x" % (name, value))
    for i in range(0, len(code), 4):
        w = struct.unpack("<I", bytes(code[i:i + 4]))[0]
        if w == 0x11111111:
            print("scratch_literal=0x%x" % i)
        elif w == 0x010fc27c:
            print("g_psr_literal=0x%x" % i)
    return 0


if __name__ == "__main__":
    sys.exit(main())
