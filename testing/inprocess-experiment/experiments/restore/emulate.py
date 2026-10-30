#!/usr/bin/env python3
"""Emulate the restore stubs against a synthetic memory image.

Assembles stubs.s with gen_stubs (same bytes that go into the jar), loads the
blob at 0x10000, and runs the A32 subset the stubs use. Verifies the scan
(candidate, skip, member readback), the read-word mode and the normal setgpr
path, including the bounds check.

Run: python3 emulate.py
"""
import struct
import sys

import gen_stubs


class Memory(object):
    def __init__(self):
        self.regions = []

    def map(self, base, size):
        self.regions.append((base, bytearray(size)))

    def _find(self, addr, n=4):
        for base, buf in self.regions:
            if base <= addr and addr + n <= base + len(buf):
                return base, buf
        raise RuntimeError("unmapped read/write at 0x%x" % addr)

    def read32(self, addr):
        base, buf = self._find(addr)
        return struct.unpack("<I", bytes(buf[addr - base:addr - base + 4]))[0]

    def write32(self, addr, v):
        base, buf = self._find(addr)
        buf[addr - base:addr - base + 4] = struct.pack("<I", v & 0xFFFFFFFF)

    def write(self, addr, data):
        base, buf = self._find(addr, len(data))
        buf[addr - base:addr - base + len(data)] = data


class ARM(object):
    def __init__(self, mem):
        self.mem = mem
        self.r = [0] * 16
        self.n = False
        self.z = False
        self.c = False
        self.v = False

    def _flags_add(self, a, b, res):
        self.z = (res & 0xFFFFFFFF) == 0
        self.n = (res & 0x80000000) != 0
        self.c = res > 0xFFFFFFFF
        self.v = (a & 0x80000000) == (b & 0x80000000) and (res & 0x80000000) != (a & 0x80000000)

    def _flags_sub(self, a, b, res):
        self.z = (res & 0xFFFFFFFF) == 0
        self.n = (res & 0x80000000) != 0
        self.c = a >= b
        self.v = (a & 0x80000000) != (b & 0x80000000) and (res & 0x80000000) != (a & 0x80000000)

    def cond_ok(self, cond):
        if cond == 0xE:
            return True
        if cond == 0x0:
            return self.z
        if cond == 0x1:
            return not self.z
        if cond == 0x2:
            return self.c
        if cond == 0x3:
            return not self.c
        if cond == 0x4:
            return self.n
        if cond == 0x5:
            return not self.n
        if cond == 0x8:
            return self.c and not self.z
        if cond == 0x9:
            return (not self.c) or self.z
        if cond == 0xA:
            return self.n == self.v
        if cond == 0xB:
            return self.n != self.v
        raise RuntimeError("unhandled condition 0x%x" % cond)

    def step(self):
        pc = self.r[15]
        w = self.mem.read32(pc)
        cond = w >> 28
        self.r[15] = (pc + 4) & 0xFFFFFFFF
        if not self.cond_ok(cond):
            return
        if (w & 0x0E000000) == 0x0A000000:                      # B
            imm = w & 0xFFFFFF
            if imm & 0x800000:
                imm -= 0x1000000
            self.r[15] = (pc + 8 + (imm << 2)) & 0xFFFFFFFF
            return
        if (w & 0x0FFFFFF0) == 0x012FFF10:                      # BX
            self.r[15] = self.r[w & 0xF] & ~1
            return
        if (w & 0x0FFFFFF0) == 0x012FFF30:                      # BLX
            self.r[14] = self.r[15]
            self.r[15] = self.r[w & 0xF] & ~1
            return
        if (w & 0x0FF00000) == 0x03000000:                      # MOVW
            v = (((w >> 16) & 0xF) << 12) | (w & 0xFFF)
            self.r[(w >> 12) & 0xF] = v
            return
        if (w & 0x0FFF0000) == 0x092D0000:                      # PUSH
            regs = [i for i in range(16) if (w >> i) & 1]
            sp = self.r[13] - 4 * len(regs)
            for i, reg in enumerate(regs):
                self.mem.write32(sp + 4 * i, self.r[reg])
            self.r[13] = sp
            return
        if (w & 0x0FFF0000) == 0x08BD0000:                      # POP
            regs = [i for i in range(16) if (w >> i) & 1]
            sp = self.r[13]
            for i, reg in enumerate(regs):
                self.r[reg] = self.mem.read32(sp + 4 * i)
            self.r[13] = sp + 4 * len(regs)
            return
        if (w & 0x0C000000) == 0x04000000:                      # LDR/STR
            p = (w >> 24) & 1
            u = (w >> 23) & 1
            b = (w >> 22) & 1
            wb = (w >> 21) & 1
            l = (w >> 20) & 1
            rn = (w >> 16) & 0xF
            rd = (w >> 12) & 0xF
            base = self.r[rn] + 4 if rn == 15 else self.r[rn]   # PC reads as insn+8
            if (w >> 25) & 1:                                   # register offset
                rm = w & 0xF
                sh = (w >> 7) & 0x1F
                off = self.r[rm] << sh if sh else self.r[rm]
            else:
                off = w & 0xFFF
            if not u:
                off = -off
            addr = (base + off) & 0xFFFFFFFF if p else base
            if l:
                self.r[rd] = self.mem.read32(addr)
            else:
                self.mem.write32(addr, self.r[rd])
            if wb or not p:
                self.r[rn] = (base + off) & 0xFFFFFFFF
            return
        if (w & 0x0C000000) == 0x00000000:                      # data processing
            op = (w >> 21) & 0xF
            s = (w >> 20) & 1
            rn = (w >> 16) & 0xF
            rd = (w >> 12) & 0xF
            if (w >> 25) & 1:
                rm = w & 0xF
                sh = (w >> 7) & 0x1F
                b = self.r[rm] << sh if sh else self.r[rm]
            else:
                imm12 = w & 0xFFF
                rot = ((imm12 >> 8) & 0xF) * 2
                v = imm12 & 0xFF
                b = ((v >> rot) | (v << (32 - rot))) & 0xFFFFFFFF if rot else v
            a = self.r[rn]
            if op == 0xD:                                       # MOV
                res = b
            elif op == 0x4:                                     # ADD
                res = a + b
            elif op == 0x2:                                     # SUB
                res = a - b
            elif op == 0xA:                                     # CMP
                self._flags_sub(a, b, (a - b) & 0xFFFFFFFF)
                return
            else:
                raise RuntimeError("unhandled dp op 0x%x at 0x%x" % (op, pc))
            if s:
                self._flags_add(a, b, res)
            self.r[rd] = res & 0xFFFFFFFF
            return
        raise RuntimeError("unhandled instruction 0x%08x at 0x%x" % (w, pc))


CODE = 0x10000
SCRATCH = 0x20000
GPR = 0x30000
HEAP = 0x40000
GLOBAL = 0x010FC27C


def setup():
    mem = Memory()
    mem.map(CODE, 0x2000)
    mem.map(SCRATCH, 0x1000)
    mem.map(GPR, 0x4000)
    mem.map(HEAP, 0x40000)
    mem.map(GLOBAL & ~0xFFF, 0x1000)
    mem.write32(GLOBAL, GPR)
    return mem


def load_stub(mem):
    mem.write(CODE, BLOB)


BLOB = None


def subprocess_blob():
    global BLOB
    import subprocess
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    out = subprocess.run([sys.executable, os.path.join(here, "gen_stubs.py")],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.startswith("hex="):
            BLOB = bytes.fromhex(line[4:])
            return
    raise RuntimeError("no hex in gen_stubs output")


def write_scratch(mem, count, target, skip, ranges):
    mem.write32(SCRATCH, count)
    mem.write32(SCRATCH + 4, target)
    mem.write32(SCRATCH + 8, skip)
    for i, (s, e) in enumerate(ranges):
        mem.write32(SCRATCH + 0x10 + i * 8, s)
        mem.write32(SCRATCH + 0x10 + i * 8 + 4, e)


def gpr(mem, i):
    return mem.read32(GPR + i * 4)


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


def main():
    global BLOB
    subprocess_blob()
    # object at 0x42000, backend at 0x70000
    def t_scan():
        mem = setup()
        load_stub(mem)
        write_scratch(mem, 1, 0xC92B20, 0, [(HEAP, HEAP + 0x40000)])
        mem.write32(0x42000, 0xC92B20)
        mem.write32(0x4200C, 0x60100)
        mem.write32(0x42010, 0x70000)
        mem.write32(0x70000, 0x00008001)      # backend vtable (code, Thumb)
        cpu = ARM(mem)
        cpu.r[1] = 0xF00
        cpu.r[13] = 0x38000
        cpu.r[14] = 0xDEAD0000
        cpu.r[15] = CODE
        while cpu.r[15] != 0xDEAD0000:
            cpu.step()
        assert gpr(mem, 3003) == 0x42000, "obj=0x%x" % gpr(mem, 3003)
        assert gpr(mem, 3004) == 0x60100, "m0c=0x%x" % gpr(mem, 3004)
        assert gpr(mem, 3005) == 0x70000, "m10=0x%x" % gpr(mem, 3005)
        assert cpu.r[0] == 0

    def t_skip():
        mem = setup()
        load_stub(mem)
        write_scratch(mem, 1, 0xC92B20, 0x42000, [(HEAP, HEAP + 0x40000)])
        mem.write32(0x42000, 0xC92B20)
        mem.write32(0x43000, 0xC92B20)
        mem.write32(0x4300C, 0x60100)
        mem.write32(0x43010, 0x70000)
        cpu = ARM(mem)
        cpu.r[1] = 0xF00
        cpu.r[13] = 0x38000
        cpu.r[14] = 0xDEAD0000
        cpu.r[15] = CODE
        while cpu.r[15] != 0xDEAD0000:
            cpu.step()
        assert gpr(mem, 3003) == 0x43000, "skip ignored: 0x%x" % gpr(mem, 3003)

    def t_readword():
        mem = setup()
        load_stub(mem)
        mem.write32(GPR + 3010 * 4, 0x42000)
        mem.write32(0x42000, 0xC92B20)
        cpu = ARM(mem)
        cpu.r[1] = 0xF01
        cpu.r[13] = 0x38000
        cpu.r[14] = 0xDEAD0000
        cpu.r[15] = CODE
        while cpu.r[15] != 0xDEAD0000:
            cpu.step()
        assert gpr(mem, 3011) == 0xC92B20, "read=0x%x" % gpr(mem, 3011)

    def t_setgpr():
        mem = setup()
        load_stub(mem)
        cpu = ARM(mem)
        cpu.r[1], cpu.r[2] = 5, 0x1234
        cpu.r[13] = 0x38000
        cpu.r[14] = 0xDEAD0000
        cpu.r[15] = CODE
        while cpu.r[15] != 0xDEAD0000:
            cpu.step()
        assert gpr(mem, 5) == 0x1234, "gpr5=0x%x" % gpr(mem, 5)

    def t_bounds():
        mem = setup()
        load_stub(mem)
        cpu = ARM(mem)
        cpu.r[1], cpu.r[2] = 0x1000, 7
        cpu.r[13] = 0x38000
        cpu.r[14] = 0xDEAD0000
        cpu.r[15] = CODE
        while cpu.r[15] != 0xDEAD0000:
            cpu.step()
        assert cpu.r[0] == 1, "bounds check did not fail"

    check("scan finds the object and its members", t_scan)
    check("scan honours the skip word", t_skip)
    check("read-word mode returns the word", t_readword)
    check("normal setgpr still writes", t_setgpr)
    check("out-of-range register is rejected", t_bounds)
    print("\n%d/%d passed" % (PASS, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
