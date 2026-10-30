#!/bin/sh
# Build blob.h from stubs.s, compile the harness and run it under QEMU.
set -e
cd "$(dirname "$0")"
python3 - <<'PY' > blob.h
import subprocess, sys
out = subprocess.run([sys.executable, "gen_stubs.py"], capture_output=True, text=True, check=True).stdout
hexs = [l[4:] for l in out.splitlines() if l.startswith("hex=")][0]
b = bytes.fromhex(hexs)
print("static const unsigned char stub_blob[] = {")
for i in range(0, len(b), 12):
    print("    " + ", ".join("0x%02x" % x for x in b[i:i+12]) + ",")
print("};")
PY
clang --target=armv7-none-eabi -nostdlib -ffreestanding -O1 -c harness.c -o harness.o
/opt/homebrew/bin/ld.lld -T link_emu.ld harness.o -o harness.elf
rm -f harness.out
/opt/homebrew/bin/qemu-system-arm -M virt -cpu cortex-a15 -m 128M -nographic \
    -kernel harness.elf > harness.out 2> qemu.err &
pid=$!
sleep 4
kill $pid 2>/dev/null || true
wait $pid 2>/dev/null || true
cat harness.out
grep -q "RESULT PASS" harness.out
