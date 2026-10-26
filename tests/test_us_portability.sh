#!/bin/sh
# Simulates the US player's stripped busybox, as reported on 26 Oct 2026:
# no `strings`, an `od` that prints nothing for -An/-tx1, and no `timeout`.
# Checks that run.sh still finds the region keys and writes bd_region.txt=2.
# Run from the repo root: sh tests/test_us_portability.sh

PASS=0; FAIL=0
check() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL [$1]: got '$2', expected '$3'"
        FAIL=$((FAIL + 1))
    fi
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN="$ROOT/usb-files/run.sh"
command -v zsh >/dev/null 2>&1 || { echo "SKIP: zsh not found"; exit 0; }
T=$(mktemp -d "$ROOT/tests/.us.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

# Player-side tools that are broken/absent on the US unit. od prints nothing
# and still exits 0 — that is what made the failures silent there.
mkdir -p "$T/bin" "$T/usb"
for c in sync strings od; do
    printf '#!/bin/sh\nexit 0\n' > "$T/bin/$c"
    chmod +x "$T/bin/$c"
done

CONF="$T/config_file_global.txt"
dd if=/dev/zero of="$CONF" bs=1219 count=1 2>/dev/null
printf 'IDX_GB_PTT_REGIONCODE'     | dd of="$CONF" bs=1 seek=127 conv=notrunc 2>/dev/null
printf 'IDX_GB_PTT_BDREGIONCODE'   | dd of="$CONF" bs=1 seek=201 conv=notrunc 2>/dev/null
printf '\x01' | dd of="$CONF" bs=1 seek=163 conv=notrunc 2>/dev/null
printf '\x01' | dd of="$CONF" bs=1 seek=237 conv=notrunc 2>/dev/null

printf '2\n' > "$T/usb/bd_region.txt"
: > "$T/usb/dvd_region.txt"   # empty = skip DVD, so no EEPROM scan on a Mac

USB="$T/usb" CONF="$CONF" PATH="$T/bin:$PATH" zsh --emulate sh "$RUN" >/dev/null 2>&1
RC=$?

rd() { dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"'; }
check "exit code" "$RC" "0"
check "BD byte written" "$(rd "$CONF" 237)" "02"
check "DVD byte untouched" "$(rd "$CONF" 163)" "01"
check "result file" "$([ -f "$T/usb/REGION_FREE_OK.txt" ] && echo y)" "y"
check "no failure file" "$([ -f "$T/usb/REGION_FREE_FAILED.txt" ] && echo y || echo n)" "n"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
