#!/usr/bin/env python3
"""Tests for the UB450 in-process probe (RegionEngine.java + region_engine.s).

Run: python3 testing/inprocess-experiment/tests/test_probe.py
Exit code 0 = all pass. No third-party packages.

Covered, each of these has already broken once or would silently break:
  1. the jar's RegionEngine.class matches the current source (stale jar)
  2. the hex constant in the class equals the assembled .text, byte for
     byte, in the correct order (a reversed literal killed the player)
  3. every pc-relative literal load in the stubs resolves to a known
     pointer constant at its runtime address
  4. the runtime buffer: object word, 32-slot table, 4 mapped entries,
     no overlap between table / noop / stub code (an overlap blanked the
     player)
  5. which registers the stubs accept, from the PICT model in
     probe_model.pict, checked against the encoded ARM branch logic
  6. the Java API call paths and their register gates (PSR 124/126 are
     rejected in Java before reaching native code)
  7. the registers the probe actually uses
  8. the firmware entry points, UOPs and adapter vtable slots the stubs use
  9. the probe call is injected into BDJCompilerOption.<clinit>
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(EXP))
BDJ_CLASSES = os.path.join(REPO, "analysis", ".bdj-root", "classes")
BDJPROG = os.path.join(REPO, "analysis", "rootfs-part", "usr", "local", "bin", "bdpprog")
JAR = os.environ.get("PROBE_JAR", os.path.join(EXP, "BDJ.jar"))
SRC = os.environ.get("PROBE_SRC", os.path.join(EXP, "RegionEngine.java"))
ASM = os.environ.get("PROBE_ASM", os.path.join(EXP, "region_engine.s"))
CLASS_NAME = "com/mtk/utils/RegionEngine.class"

G_PSR = 0x010FC27C
ENGINE_SET = 0x0021F629
ENGINE_GET = 0x0021FC91
ENGINE_DGET = 0x0021FD09
KNOWN_POINTERS = {G_PSR, ENGINE_SET, ENGINE_GET, ENGINE_DGET}
ADAPTER_VTABLE = 0xC92B20

RESULTS = []


def check(name, fn):
    try:
        detail = fn()
        RESULTS.append((True, name, detail or ""))
    except AssertionError as e:
        RESULTS.append((False, name, str(e)))
    except Exception as e:  # noqa: BLE001 - report, do not crash the suite
        RESULTS.append((False, name, "%s: %s" % (type(e).__name__, e)))


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise AssertionError("%s failed: %s" % (" ".join(cmd), (p.stderr or p.stdout).strip()))
    return p.stdout


def assemble():
    obj = os.path.join(tempfile.mkdtemp(prefix="probe_asm_"), "stubs.o")
    run(["clang", "-target", "armv7-none-eabi", "-c", ASM, "-o", obj])
    return obj


def obj_words(obj):
    """Raw .text bytes of the object file, in file order."""
    out = run(["xcrun", "llvm-objdump", "-s", "--triple=armv7-none-eabi", obj])
    data = bytearray()
    started = False
    for line in out.splitlines():
        m = re.match(r"^\s*([0-9a-f]{4,})\s+((?:[0-9a-f]{8}\s+)+)", line)
        if m and started:
            for w in m.group(2).split():
                data += bytes.fromhex(w)
        elif "Contents of section .text:" in line:
            started = True
        elif started and line.strip():
            break
    return bytes(data)


def class_bytes(path=None):
    with zipfile.ZipFile(JAR) as z:
        return z.read(CLASS_NAME)


def cp_utf8(data):
    n = struct.unpack(">H", data[8:10])[0]
    p, i, out = 10, 1, []
    while i < n:
        tag = data[p]
        p += 1
        if tag == 1:
            ln = struct.unpack(">H", data[p:p + 2])[0]
            out.append(data[p + 2:p + 2 + ln].decode("utf-8", "replace"))
            p += 2 + ln
        elif tag in (7, 8, 16):
            p += 2
        elif tag in (9, 10, 11, 12, 18):
            p += 4
        elif tag in (3, 4):
            p += 4
        elif tag in (5, 6):
            p += 8
            i += 1
        elif tag == 15:
            p += 3
        else:
            raise AssertionError("unknown constant pool tag %d" % tag)
        i += 1
    return out


def embedded_stubs():
    longs = [s for s in cp_utf8(class_bytes()) if re.fullmatch(r"[0-9a-f]+", s) and len(s) > 64]
    if len(longs) != 1:
        raise AssertionError("expected exactly one hex constant in the class, found %d" % len(longs))
    return bytes.fromhex(longs[0])


def vaddr_of(off):
    return off + 0x8000 if off < 0x1053CB8 else off + 0x10000


def file_off(vaddr):
    return vaddr - 0x8000 if vaddr < 0x105BCB8 else vaddr - 0x10000


def firmware_bytes(vaddr, n):
    with open(BDJPROG, "rb") as f:
        f.seek(file_off(vaddr))
        return f.read(n)


def firmware_word(vaddr):
    return struct.unpack("<I", firmware_bytes(vaddr, 4))[0]


def javap(path):
    return run(["javap", "-c", "-p", path])


def method_body(text, signature):
    m = re.search(re.escape(signature) + r".*?Code:(.*?)(?:\n\n|\Z)", text, re.S)
    if not m:
        raise AssertionError("method not found: %s" % signature)
    return m.group(1)


# ---------------------------------------------------------------- ARM helpers
def rotl(v, n):
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF


def arm_imm(imm12):
    imm8 = imm12 & 0xFF
    rot = (imm12 >> 8) & 0xF
    return rotl(imm8, (32 - 2 * rot) % 32)


def is_cmp_r1(w):
    return (w & 0xFFFFF000) == 0xE3510000


def is_mov_r0(w):
    return (w & 0xFFFFF000) == 0xE3A00000


def is_branch(w):
    return (w & 0x0E000000) == 0x0A000000


def is_bx_lr(w):
    return w == 0xE12FFF1E


def is_mem_reg(w):
    # ldr/str, register or immediate offset, but not ldr rX,[pc,#imm]
    if (w & 0x0C000000) != 0x04000000:
        return False
    return (w & 0x0F7F0000) != 0x051F0000


def cond_true(cond, result):
    n = 1 if result < 0 else 0
    z = 1 if result == 0 else 0
    v = 0
    if cond == 0x0:   # eq
        return z == 1
    if cond == 0xA:   # ge
        return n == v
    if cond == 0xB:   # lt
        return n != v
    if cond == 0xC:   # gt
        return z == 0 and n == v
    raise AssertionError("unhandled condition 0x%x" % cond)


def is_push_lr(w):
    """push {... , lr}: 0xE92D4xxx family."""
    return (w >> 16) == 0xE92D and (w & 0x4000) != 0


def classify(words, entry, reg, special):
    """Return Normal / Fail / Special20 for one stub and one register value."""
    pc, cmp_res, ret, steps = 0, None, None, 0
    while steps < 60:
        idx = (entry + pc) // 4
        if idx >= len(words):
            return "Unknown"
        w = words[idx]
        if is_cmp_r1(w):
            imm = arm_imm(w & 0xFFF)
            cmp_res = (reg - imm if reg >= 0 else reg - imm)
            if reg < 0:
                cmp_res = reg - imm
        elif is_branch(w) and cmp_res is not None:
            if cond_true(w >> 28, cmp_res):
                off = w & 0xFFFFFF
                if off & 0x800000:
                    off -= 0x1000000
                target = pc + 8 + off * 4
                if entry + target == special:
                    return "Special20"
                pc = target
                continue
        elif is_bx_lr(w):
            return "Fail" if ret == 1 else "Normal"
        elif is_mov_r0(w):
            ret = arm_imm(w & 0xFFF)
        elif is_mem_reg(w):
            return "Normal"
        pc += 4
        steps += 1
    return "Unknown"


def stub_symbols(obj):
    out = run(["xcrun", "llvm-objdump", "-t", obj])
    syms = {}
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]{8})\s+g\s+\S+\s+[0-9a-f]+\s+(\w+)$", line.strip())
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    for need in ("getgpr", "setgpr", "getpsr", "setpsr"):
        if need not in syms:
            raise AssertionError("symbol %s missing from assembly" % need)
    return syms


def source_layout():
    src = open(SRC).read()
    vals = {}
    for key in ("noop", "stubs"):
        m = re.search(r"int %s = (0x[0-9a-fA-F]+|\d+);" % key, src)
        if not m:
            raise AssertionError("layout constant %s not found in source" % key)
        vals[key] = int(m.group(1), 0)
    return vals


def source_slot_offsets():
    """The four stub offsets the Java puts in the table, read from the source."""
    src = open(SRC).read()
    found = {}
    for m in re.finditer(r"put32\(b, 0x10 \+ (\d) \* 4, buf \+ stubs(?: \+ (0x[0-9a-fA-F]+))?\);", src):
        found[int(m.group(1))] = int(m.group(2), 16) if m.group(2) else 0
    return found


def build_buffer(base=0x5A000000):
    lay = source_layout()
    syms = stub_symbols(assemble())
    stubs = embedded_stubs()
    buf = bytearray(4096)

    def put32(off, val):
        struct.pack_into("<I", buf, off, val & 0xFFFFFFFF)

    put32(0, base + 0x10)
    for i in range(32):
        put32(0x10 + i * 4, base + lay["noop"])
    entries = {"getgpr": 2, "setgpr": 3, "getpsr": 4, "setpsr": 5}
    for name, slot in entries.items():
        put32(0x10 + slot * 4, base + lay["stubs"] + syms[name])
    buf[lay["noop"]:lay["noop"] + 8] = bytes.fromhex("0000a0e31eff2fe1")
    buf[lay["stubs"]:lay["stubs"] + len(stubs)] = stubs
    return buf, base, lay, syms, stubs


# -------------------------------------------------------------------- tests
def test_jar_matches_source():
    work = tempfile.mkdtemp(prefix="probe_src_")
    try:
        run(["javac", "--release", "8", "-cp", BDJ_CLASSES, "-d", work, SRC])
        cls = os.path.join(work, "com", "mtk", "utils", "RegionEngine.class")
        run(["python3", os.path.join(EXP, "downgrade_class.py"), cls])
        fresh = open(cls, "rb").read()
        shipped = class_bytes()
        assert fresh == shipped, "jar class differs from a fresh build of %s - rebuild the jar" % os.path.basename(SRC)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def test_blob_matches_assembly():
    obj = assemble()
    stubs = embedded_stubs()
    text = obj_words(obj)
    assert stubs == text, ("class hex constant is not the assembled .text "
                           "(len %d vs %d, first diff at %s)" % (
                               len(stubs), len(text),
                               next((i for i, (a, b) in enumerate(zip(stubs, text)) if a != b), "end")))
    return "%d bytes" % len(stubs)


def test_literal_resolution():
    buf, base, lay, syms, stubs = build_buffer()
    words = [struct.unpack_from("<I", buf, lay["stubs"] + i)[0] for i in range(0, len(stubs), 4)]
    found = 0
    for i, w in enumerate(words):
        if (w & 0x0F000000) == 0x05000000 and ((w >> 16) & 0xFF) == 0x9F and ((w >> 20) & 0xF) != 0x5:
            tgt = lay["stubs"] + i * 4 + 8 + (w & 0xFFF)
            assert lay["stubs"] <= tgt < lay["stubs"] + len(stubs), "literal load outside blob at +0x%x" % (i * 4)
            val = struct.unpack_from("<I", buf, tgt)[0]
            assert val in KNOWN_POINTERS, "literal at +0x%x is 0x%08x, not a known pointer" % (i * 4, val)
            found += 1
    assert found >= 9, "expected at least 9 literal loads, found %d" % found
    return "%d literal loads" % found


def test_layout():
    buf, base, lay, syms, stubs = build_buffer()
    def u32(off):
        return struct.unpack_from("<I", buf, off)[0]
    assert u32(0) == base + 0x10, "object word does not point at the table"
    slots = [u32(0x10 + i * 4) for i in range(32)]
    expected = [base + lay["noop"]] * 32
    for name, slot in {"getgpr": 2, "setgpr": 3, "getpsr": 4, "setpsr": 5}.items():
        expected[slot] = base + lay["stubs"] + syms[name]
    assert slots == expected, "table entries differ from the four mapped stubs + noop"
    shipped = source_slot_offsets()
    want = {2: syms["getgpr"], 3: syms["setgpr"], 4: syms["getpsr"], 5: syms["setpsr"]}
    assert shipped == want, ("table offsets in %s do not match the assembled stubs: "
                             "source %s, assembly %s" % (os.path.basename(SRC), shipped, want))
    assert not (set(range(0x10, 0x90)) & set(range(lay["noop"], lay["noop"] + 8))), "noop overlaps the table"
    assert not (set(range(0x10, 0x90)) & set(range(lay["stubs"], lay["stubs"] + len(stubs)))), "stubs overlap the table"
    assert lay["noop"] + 8 <= lay["stubs"], "noop and stubs overlap"
    assert lay["stubs"] + len(stubs) <= 4096, "stubs run past the buffer"
    return "noop=0x%x stubs=0x%x len=%d" % (lay["noop"], lay["stubs"], len(stubs))


def pict_pairs():
    """All (Function, RegClass) pairs from probe_model.pict, with expected path."""
    funcs = ["getgpr", "setgpr", "getpsr", "setpsr"]
    regs = {"negative": -1, "zero": 0, "twenty": 20, "edge127": 0x7F, "edge128": 0x80,
            "mid800": 0x800, "edge0xFFF": 0xFFF, "over0x1000": 0x1000}
    pairs = []
    for f in funcs:
        for name, val in regs.items():
            if f in ("getgpr", "setgpr"):
                expect = "Normal" if 0 <= val < 0x1000 else "Fail"
            else:
                expect = "Normal" if 0 <= val < 0x80 else "Fail"
            if f == "setpsr" and val == 20:
                expect = "Special20"
            pairs.append((f, name, val, expect))
    return pairs


def test_stub_semantics_pict():
    obj = assemble()
    stubs = obj_words(obj)
    syms = stub_symbols(obj)
    words = [struct.unpack_from("<I", stubs, i)[0] for i in range(0, len(stubs), 4)]
    # special path = the push {r4,r5,r6,lr} inside setpsr
    special = None
    for off in range(syms["setpsr"], len(stubs), 4):
        if is_push_lr(struct.unpack_from("<I", stubs, off)[0]):
            special = off
            break
    assert special is not None, "setpsr has no engine path"
    bad = []
    for func, regname, regval, expect in pict_pairs():
        got = classify(words, syms[func], regval, special)
        if got != expect:
            bad.append("%s(%s) expected %s got %s" % (func, regname, expect, got))
    assert not bad, "; ".join(bad[:6])
    return "%d PICT cases" % len(pict_pairs())


def test_special_path_shape():
    """setpsr(20) must sweep all four engine indices and record statuses."""
    obj = assemble()
    stubs = obj_words(obj)
    syms = stub_symbols(obj)
    start = None
    for off in range(syms["setpsr"], len(stubs) - 4, 4):
        if is_push_lr(struct.unpack_from("<I", stubs, off)[0]):
            start = off
            break
    assert start is not None, "setpsr has no engine path (push missing)"
    body = []
    for off in range(start, len(stubs) - 4, 4):
        body.append((off, struct.unpack_from("<I", stubs, off)[0]))
    literals = set()
    for off, w in body:
        if (w & 0x0F7F0000) == 0x051F0000:
            target = off + 8 + (w & 0xFFF)
            literals.add(struct.unpack_from("<I", stubs, target)[0] if target + 4 <= len(stubs) else 0)
    for need in (ENGINE_SET, ENGINE_GET, ENGINE_DGET):
        assert need in literals, "engine pointer 0x%08x not loaded in the special path" % need
    assert any((w & 0xFFFFF000) == 0xE3560000 for _, w in body), "no cmp r6,#imm loop bound in the special path"
    assert any((w & 0xFFFFF000) == 0xE3560000 and (w & 0xFFF) == 4 for _, w in body), "engine sweep does not cover four indices"
    return "sweeps 4 indices, 3 engine pointers"


def test_java_api_gates():
    phil = javap(os.path.join(BDJ_CLASSES, "com", "philips", "bluray", "system", "RegisterAccess.class"))
    org = javap(os.path.join(BDJ_CLASSES, "org", "bluray", "system", "RegisterAccess.class"))
    body = method_body(phil, "public static void setPSR(int, int)")
    assert "nSetPSR" in body and "supportedPSR" not in body, "setPSR path changed: expected a direct nSetPSR call"
    body = method_body(phil, "public int getGPR(int)")
    assert "nGetGPR" in body and "IllegalArgumentException" not in body, \
        "getGPR path changed: expected a direct nGetGPR call with no range check"
    body = method_body(phil, "public static int getPSR(int)")
    assert "org/bluray/system/RegisterAccess.getPSR" in body, \
        "getPSR path changed: expected delegation to org.bluray (which gates registers)"
    body = method_body(org, "public int getPSR(int)")
    assert "supportedPSR" in body, "org.bluray getPSR lost its supportedPSR gate"
    return "setPSR/getGPR direct, getPSR gated"


def test_probe_register_usage():
    tmp = tempfile.mkdtemp(prefix="probe_cls_")
    try:
        path = os.path.join(tmp, "RegionEngine.class")
        open(path, "wb").write(class_bytes())
        text = javap(path)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    psr, gpr = [], []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        is_set = "RegisterAccess.setPSR" in line or "RegisterAccess.setPSR:(II)V" in line
        is_get = "RegisterAccess.getPSR" in line or "RegisterAccess.getPSR:(I)I" in line
        is_gpr = "RegisterAccess.getGPR" in line
        if not (is_set or is_get or is_gpr):
            continue
        # collect the constant pushes just before the call; setPSR's first
        # argument (the register) is the earlier of its two pushes
        consts = []
        for j in range(i - 1, max(i - 6, 0), -1):
            cm = re.search(r"(?:bipush|sipush|iconst_\d|ldc)\s+(?:#\d+\s+//\s+int\s+)?(-?\d+)", lines[j])
            if cm:
                consts.insert(0, int(cm.group(1)))
            elif consts:
                break
        if not consts:
            continue
        if is_gpr:
            gpr.append(consts[-1])
        elif is_set:
            psr.append(consts[0])
        else:
            psr.append(consts[-1])
    assert psr, "no PSR calls found in the probe"
    assert set(psr) <= {20}, "probe uses unsupported PSR registers: %s" % sorted(set(psr) - {20})
    assert gpr, "no GPR calls found in the probe"
    assert all(0 <= g < 0x1000 for g in gpr), "probe uses GPR outside the stub bound: %s" % gpr
    return "PSR %s, GPR %s" % (sorted(set(psr)), sorted(set(gpr)))


def test_firmware_abi():
    for addr in (0x21F628, 0x21FC90, 0x21FD08):
        first = firmware_bytes(addr, 2)
        assert first[1] == 0xB5, "0x%x is not a thumb push entry (found %s)" % (addr, first.hex())
    assert b"\x5a\x21" in firmware_bytes(0x21FC90, 0x80), "region_get does not send UOP 0x5a"
    assert b"\xcb\x21" in firmware_bytes(0x21F628, 0x80), "region_code_set does not send UOP 0xcb"
    assert b"\xcb\x21" in firmware_bytes(0x21FD08, 0x80), "disc_region_get does not send UOP 0xcb"
    assert firmware_word(ADAPTER_VTABLE + 0x10) == 0x003135C9, "adapter vtable +0x10 is not OnGetPsr"
    assert firmware_word(ADAPTER_VTABLE + 0x14) == 0x00313841, "adapter vtable +0x14 is not OnSetPsr"
    return "entries, UOPs and vtable slots match"


def test_jar_injection():
    with zipfile.ZipFile(JAR) as z:
        opt = z.read("com/mtk/utils/BDJCompilerOption.class")
        probe = z.read(CLASS_NAME)
    tmp = tempfile.mkdtemp(prefix="probe_opt_")
    try:
        path = os.path.join(tmp, "BDJCompilerOption.class")
        open(path, "wb").write(opt)
        text = javap(path)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    start = text.find("static {};")
    assert start >= 0, "no static initialiser in BDJCompilerOption"
    body = text[start:]
    calls = re.findall(r"invokestatic\s+#\d+\s+//\s+Method ([\w/\.\$]+)\.go:\(\)V", body)
    assert calls and calls[-1].endswith("RegionEngine"), "probe call not injected (found %s)" % calls
    assert body.find("Runtime.exec") < body.find("RegionEngine.go"), "probe call is not after the run.sh step"
    major = struct.unpack(">H", probe[6:8])[0]
    assert major == 48, "probe class is version %d, expected 48" % major
    assert b"StringBuilder" not in probe, "probe class references java.lang.StringBuilder (missing on this CVM)"
    assert b"java/io/File\x00" not in probe, "probe class references java.io.File"
    return "go() injected after Runtime.exec"


def main():
    tests = [
        ("jar matches source", test_jar_matches_source),
        ("stub hex == assembled .text", test_blob_matches_assembly),
        ("literal loads resolve", test_literal_resolution),
        ("runtime buffer layout", test_layout),
        ("stub semantics (PICT)", test_stub_semantics_pict),
        ("special path shape", test_special_path_shape),
        ("java api gates", test_java_api_gates),
        ("probe register usage", test_probe_register_usage),
        ("firmware abi", test_firmware_abi),
        ("jar injection", test_jar_injection),
    ]
    for name, fn in tests:
        check(name, fn)
    failed = [r for r in RESULTS if not r[0]]
    for ok, name, detail in RESULTS:
        print(("PASS " if ok else "FAIL ") + name + (": " + detail if detail else ""))
    print("\n%d/%d passed" % (len(RESULTS) - len(failed), len(RESULTS)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
