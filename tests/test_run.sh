#!/bin/sh
# Tests for run.sh offset detection and region write logic.
# Run from the repo root: sh tests/test_run.sh

set -e
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $1 — got '$2', expected '$3'"
        FAIL=$((FAIL + 1))
    fi
}

# --- Helpers (copied from usb-files/run.sh v3) ---

find_offset() {
    _fo_file="$1"; _fo_key="$2"; _fo_off=""
    _fo_off=$(strings -a -t d "$_fo_file" 2>/dev/null | grep "${_fo_key}$" | head -1 | awk '{print $1}')
    if [ -n "$_fo_off" ] && expr "$_fo_off" + 0 >/dev/null 2>&1; then
        _fo_check=$(dd if="$_fo_file" bs=1 skip="$_fo_off" count=${#_fo_key} 2>/dev/null)
        if [ "$_fo_check" = "$_fo_key" ]; then
            echo "$_fo_off"; return
        fi
    fi
    _fo_fhex=$(od -v -An -tx1 < "$_fo_file" 2>/dev/null | tr -cd '0-9a-f')
    _fo_khex=$(printf '%s' "$_fo_key" | od -v -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ -n "$_fo_fhex" ] && [ -n "$_fo_khex" ]; then
        _fo_before="${_fo_fhex%%${_fo_khex}*}"
        if [ "$_fo_before" != "$_fo_fhex" ]; then
            echo $(( ${#_fo_before} / 2 )); return
        fi
    fi
    _fo_max=$(($(wc -c < "$_fo_file" | tr -d ' ') - ${#_fo_key}))
    _fo_i=0
    while [ $_fo_i -le $_fo_max ]; do
        _fo_check=$(dd if="$_fo_file" bs=1 skip=$_fo_i count=${#_fo_key} 2>/dev/null)
        if [ "$_fo_check" = "$_fo_key" ]; then
            echo $_fo_i; return
        fi
        _fo_i=$((_fo_i + 1))
    done
    return 1
}

read_byte() {
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_raw=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)
    printf '%02x' "'$_rb_raw"
}

# --- Generate test configs ---

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

python3 -I << PYEOF
import os
d = "$D"

def write(name, size, placements):
    data = bytearray(size)
    for off, key, val in placements:
        data[off:off+len(key)] = key
        data[off+36] = val
    open(os.path.join(d, name), "wb").write(data)

DVD = b"IDX_GB_PTT_REGIONCODE"
BD  = b"IDX_GB_PTT_BDREGIONCODE"
IR  = b"IDX_GB_PTT_IR_REGIONCODE"

# 1. UB450 layout: DVD before BD
write("ub450.bin", 500, [(127, DVD, 4), (201, BD, 2), (300, IR, 0)])

# 2. UB150 layout: BD before DVD, 1219 bytes
write("ub150.bin", 1219, [(80, BD, 2), (200, DVD, 4), (350, IR, 0)])

# 3. Key at offset 0
write("edge_zero.bin", 200, [(0, DVD, 1), (100, BD, 2)])

# 4. Keys near end of file
write("edge_end.bin", 300, [(220, DVD, 3), (260, BD, 5)])

# 5. Adjacent keys (no gap)
write("adjacent.bin", 200, [(50, DVD, 6), (87, BD, 1)])

# 6. No region keys
data = bytearray(b"THIS_IS_NOT_A_VALID_CONFIG" * 10)
open(os.path.join(d, "no_keys.bin"), "wb").write(data)

# 7. DVD only, no BD key
write("dvd_only.bin", 200, [(50, DVD, 4)])

# 8. Realistic: all nulls around keys (like actual ACFG)
data = bytearray(1219)
data[127:127+21] = DVD; data[163] = 4
data[201:201+23] = BD;  data[237] = 2
data[300:300+24] = IR;  data[336] = 0
open(os.path.join(d, "realistic.bin"), "wb").write(data)
PYEOF

# --- Tests ---

echo "1. UB450 layout (DVD before BD)"
DVD_OFF=$(find_offset "$D/ub450.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/ub450.bin" "IDX_GB_PTT_BDREGIONCODE")
check "DVD key offset" "$DVD_OFF" "127"
check "BD key offset"  "$BD_OFF"  "201"
check "DVD value" "$(read_byte "$D/ub450.bin" $((DVD_OFF + 36)))" "04"
check "BD value"  "$(read_byte "$D/ub450.bin" $((BD_OFF  + 36)))" "02"

echo "2. UB150 layout (BD before DVD, 1219 bytes)"
DVD_OFF=$(find_offset "$D/ub150.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/ub150.bin" "IDX_GB_PTT_BDREGIONCODE")
check "DVD key offset" "$DVD_OFF" "200"
check "BD key offset"  "$BD_OFF"  "80"
check "DVD value" "$(read_byte "$D/ub150.bin" $((DVD_OFF + 36)))" "04"
check "BD value"  "$(read_byte "$D/ub150.bin" $((BD_OFF  + 36)))" "02"

echo "3. Key at offset 0"
DVD_OFF=$(find_offset "$D/edge_zero.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/edge_zero.bin" "IDX_GB_PTT_BDREGIONCODE")
check "DVD key at 0" "$DVD_OFF" "0"
check "BD key at 100" "$BD_OFF" "100"
check "DVD value" "$(read_byte "$D/edge_zero.bin" $((DVD_OFF + 36)))" "01"

echo "4. Keys near end of file"
DVD_OFF=$(find_offset "$D/edge_end.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/edge_end.bin" "IDX_GB_PTT_BDREGIONCODE")
check "DVD key offset" "$DVD_OFF" "220"
check "BD key offset"  "$BD_OFF"  "260"
check "DVD value" "$(read_byte "$D/edge_end.bin" $((DVD_OFF + 36)))" "03"
check "BD value"  "$(read_byte "$D/edge_end.bin" $((BD_OFF  + 36)))" "05"

echo "5. Adjacent keys (no gap)"
DVD_OFF=$(find_offset "$D/adjacent.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/adjacent.bin" "IDX_GB_PTT_BDREGIONCODE")
check "DVD key offset" "$DVD_OFF" "50"
check "BD key offset"  "$BD_OFF"  "87"
check "DVD value" "$(read_byte "$D/adjacent.bin" $((DVD_OFF + 36)))" "06"
check "BD value"  "$(read_byte "$D/adjacent.bin" $((BD_OFF  + 36)))" "01"

echo "6. No keys (graceful failure)"
DVD_OFF=$(find_offset "$D/no_keys.bin" "IDX_GB_PTT_REGIONCODE") || true
BD_OFF=$(find_offset  "$D/no_keys.bin" "IDX_GB_PTT_BDREGIONCODE") || true
check "DVD not found" "${DVD_OFF:-(empty)}" "(empty)"
check "BD not found"  "${BD_OFF:-(empty)}"  "(empty)"

echo "7. DVD only, no BD key"
DVD_OFF=$(find_offset "$D/dvd_only.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/dvd_only.bin" "IDX_GB_PTT_BDREGIONCODE") || true
check "DVD found" "$DVD_OFF" "50"
check "BD not found" "${BD_OFF:-(empty)}" "(empty)"

echo "8. Realistic (nulls around keys)"
DVD_OFF=$(find_offset "$D/realistic.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/realistic.bin" "IDX_GB_PTT_BDREGIONCODE")
check "DVD key offset" "$DVD_OFF" "127"
check "BD key offset"  "$BD_OFF"  "201"
check "DVD value" "$(read_byte "$D/realistic.bin" 163)" "04"
check "BD value"  "$(read_byte "$D/realistic.bin" 237)" "02"

echo "9. Write + verify round trip"
cp "$D/realistic.bin" "$D/writable.bin"
DVD_OFF=$(find_offset "$D/writable.bin" "IDX_GB_PTT_REGIONCODE")
BD_OFF=$(find_offset  "$D/writable.bin" "IDX_GB_PTT_BDREGIONCODE")
printf '\x00' | dd of="$D/writable.bin" bs=1 seek=$((DVD_OFF + 36)) conv=notrunc 2>/dev/null
printf '\x07' | dd of="$D/writable.bin" bs=1 seek=$((BD_OFF  + 36)) conv=notrunc 2>/dev/null
check "DVD after write" "$(read_byte "$D/writable.bin" $((DVD_OFF + 36)))" "00"
check "BD after write"  "$(read_byte "$D/writable.bin" $((BD_OFF  + 36)))" "07"

echo "10. No false positives (REGIONCODE vs BDREGIONCODE)"
DVD_OFF=$(find_offset "$D/ub150.bin" "IDX_GB_PTT_REGIONCODE")
check "DVD at 200 not 80" "$DVD_OFF" "200"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
