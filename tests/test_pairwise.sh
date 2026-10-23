#!/bin/sh
# Pairwise tests for run.sh offset detection, write, and restore logic.
# Generated from a PICT model with 7 parameters × 27 test cases.
# Run from the repo root: sh tests/test_pairwise.sh
#
# Parameters:
#   key_order:    DVD_before_BD | BD_before_DVD | adjacent | same_offset
#   file_size:    small_200 | medium_500 | realistic_1219 | large_4096
#   dvd_region:   0-6 (initial DVD region byte)
#   bd_region:    1,2,4,7 (initial BD region byte)
#   key_position: start_of_file | middle | near_end
#   null_padding: all_nulls | random_data | mixed
#   mode:         set_regionfree | restore
#
# Constraints:
#   near_end requires file_size > small_200
#   same_offset only tests set_regionfree (always errors: DVD key missing)
#   adjacent excludes near_end

set -e
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL [$1]: got '$2', expected '$3'"
        FAIL=$((FAIL + 1))
    fi
}

# --- Helpers (from usb-files/run.sh v3) ---

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

# --- Generate all 27 configs ---

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

python3 -I << PYEOF
import os, random

d = "$D"
random.seed(99)

DVD = b"IDX_GB_PTT_REGIONCODE"   # 21 bytes
BD  = b"IDX_GB_PTT_BDREGIONCODE" # 23 bytes
RECORD = 36  # key-name-start to value byte

sizes = {"small_200": 200, "medium_500": 500, "realistic_1219": 1219, "large_4096": 4096}

cases = [
    {"n":1,  "key_order":"DVD_before_BD",  "file_size":"small_200",     "dvd_region":2, "bd_region":2, "key_position":"start_of_file", "null_padding":"all_nulls",   "mode":"set_regionfree"},
    {"n":2,  "key_order":"adjacent",        "file_size":"realistic_1219","dvd_region":0, "bd_region":1, "key_position":"middle",        "null_padding":"mixed",        "mode":"restore"},
    {"n":3,  "key_order":"DVD_before_BD",  "file_size":"medium_500",    "dvd_region":4, "bd_region":7, "key_position":"near_end",      "null_padding":"random_data",  "mode":"restore"},
    {"n":4,  "key_order":"BD_before_DVD",  "file_size":"large_4096",    "dvd_region":6, "bd_region":4, "key_position":"middle",        "null_padding":"random_data",  "mode":"set_regionfree"},
    {"n":5,  "key_order":"same_offset",    "file_size":"large_4096",    "dvd_region":1, "bd_region":7, "key_position":"start_of_file", "null_padding":"mixed",        "mode":"set_regionfree"},
    {"n":6,  "key_order":"BD_before_DVD",  "file_size":"medium_500",    "dvd_region":1, "bd_region":1, "key_position":"near_end",      "null_padding":"all_nulls",    "mode":"set_regionfree"},
    {"n":7,  "key_order":"adjacent",        "file_size":"small_200",     "dvd_region":4, "bd_region":4, "key_position":"start_of_file", "null_padding":"all_nulls",    "mode":"restore"},
    {"n":8,  "key_order":"same_offset",    "file_size":"realistic_1219","dvd_region":0, "bd_region":2, "key_position":"near_end",      "null_padding":"random_data",  "mode":"set_regionfree"},
    {"n":9,  "key_order":"BD_before_DVD",  "file_size":"medium_500",    "dvd_region":2, "bd_region":2, "key_position":"middle",        "null_padding":"mixed",        "mode":"restore"},
    {"n":10, "key_order":"BD_before_DVD",  "file_size":"realistic_1219","dvd_region":6, "bd_region":7, "key_position":"start_of_file", "null_padding":"all_nulls",    "mode":"restore"},
    {"n":11, "key_order":"DVD_before_BD",  "file_size":"large_4096",    "dvd_region":0, "bd_region":4, "key_position":"near_end",      "null_padding":"mixed",        "mode":"set_regionfree"},
    {"n":12, "key_order":"same_offset",    "file_size":"large_4096",    "dvd_region":4, "bd_region":1, "key_position":"middle",        "null_padding":"all_nulls",    "mode":"set_regionfree"},
    {"n":13, "key_order":"adjacent",        "file_size":"large_4096",    "dvd_region":1, "bd_region":2, "key_position":"middle",        "null_padding":"random_data",  "mode":"restore"},
    {"n":14, "key_order":"same_offset",    "file_size":"small_200",     "dvd_region":6, "bd_region":1, "key_position":"middle",        "null_padding":"random_data",  "mode":"set_regionfree"},
    {"n":15, "key_order":"adjacent",        "file_size":"small_200",     "dvd_region":2, "bd_region":7, "key_position":"middle",        "null_padding":"random_data",  "mode":"set_regionfree"},
    {"n":16, "key_order":"BD_before_DVD",  "file_size":"medium_500",    "dvd_region":0, "bd_region":4, "key_position":"start_of_file", "null_padding":"all_nulls",    "mode":"restore"},
    {"n":17, "key_order":"DVD_before_BD",  "file_size":"realistic_1219","dvd_region":1, "bd_region":4, "key_position":"start_of_file", "null_padding":"mixed",        "mode":"set_regionfree"},
    {"n":18, "key_order":"same_offset",    "file_size":"medium_500",    "dvd_region":2, "bd_region":4, "key_position":"near_end",      "null_padding":"all_nulls",    "mode":"set_regionfree"},
    {"n":19, "key_order":"DVD_before_BD",  "file_size":"large_4096",    "dvd_region":2, "bd_region":1, "key_position":"start_of_file", "null_padding":"random_data",  "mode":"set_regionfree"},
    {"n":20, "key_order":"BD_before_DVD",  "file_size":"small_200",     "dvd_region":4, "bd_region":2, "key_position":"middle",        "null_padding":"mixed",        "mode":"restore"},
    {"n":21, "key_order":"adjacent",        "file_size":"medium_500",    "dvd_region":6, "bd_region":4, "key_position":"middle",        "null_padding":"mixed",        "mode":"restore"},
    {"n":22, "key_order":"DVD_before_BD",  "file_size":"large_4096",    "dvd_region":6, "bd_region":2, "key_position":"middle",        "null_padding":"all_nulls",    "mode":"set_regionfree"},
    {"n":23, "key_order":"adjacent",        "file_size":"small_200",     "dvd_region":0, "bd_region":7, "key_position":"middle",        "null_padding":"all_nulls",    "mode":"restore"},
    {"n":24, "key_order":"DVD_before_BD",  "file_size":"realistic_1219","dvd_region":4, "bd_region":1, "key_position":"start_of_file", "null_padding":"all_nulls",    "mode":"set_regionfree"},
    {"n":25, "key_order":"DVD_before_BD",  "file_size":"realistic_1219","dvd_region":2, "bd_region":1, "key_position":"near_end",      "null_padding":"mixed",        "mode":"set_regionfree"},
    {"n":26, "key_order":"same_offset",    "file_size":"medium_500",    "dvd_region":6, "bd_region":4, "key_position":"near_end",      "null_padding":"mixed",        "mode":"set_regionfree"},
    {"n":27, "key_order":"same_offset",    "file_size":"small_200",     "dvd_region":1, "bd_region":4, "key_position":"start_of_file", "null_padding":"mixed",        "mode":"set_regionfree"},
]

for c in cases:
    sz = sizes[c["file_size"]]

    # Fill base data
    pad = c["null_padding"]
    if pad == "all_nulls":
        data = bytearray(sz)
    elif pad == "random_data":
        data = bytearray(random.randbytes(sz))
    else:  # mixed
        data = bytearray(sz // 2) + bytearray(random.randbytes(sz - sz // 2))

    # Compute base offset from key_position
    pos = c["key_position"]
    if pos == "start_of_file":
        base = 2
    elif pos == "middle":
        base = sz // 3
    else:  # near_end
        base = sz - 120

    dvd_val = c["dvd_region"]
    bd_val = c["bd_region"]
    order = c["key_order"]

    dvd_off = bd_off = -1

    if order == "DVD_before_BD":
        dvd_off = base
        bd_off = base + 60
    elif order == "BD_before_DVD":
        bd_off = base
        dvd_off = base + 60
    elif order == "adjacent":
        dvd_off = base
        bd_off = base + 37  # DVD key(21) + padding(15) + value(1) = 37
    else:  # same_offset — only BD key placed; DVD key absent → error
        bd_off = base
        dvd_off = -1

    # Clear key areas and place keys
    if dvd_off >= 0:
        data[dvd_off:dvd_off+RECORD+1] = b'\x00' * (RECORD + 1)
        data[dvd_off:dvd_off+len(DVD)] = DVD
        data[dvd_off+RECORD] = dvd_val

    data[bd_off:bd_off+RECORD+1] = b'\x00' * (RECORD + 1)
    data[bd_off:bd_off+len(BD)] = BD
    data[bd_off+RECORD] = bd_val

    fname = os.path.join(d, f"case_{c['n']:02d}.bin")
    open(fname, "wb").write(data)

    # Write metadata for the shell test
    meta = os.path.join(d, f"case_{c['n']:02d}.meta")
    with open(meta, "w") as f:
        f.write(f"ORDER={order}\n")
        f.write(f"MODE={c['mode']}\n")
        f.write(f"DVD_OFF={dvd_off}\n")
        f.write(f"BD_OFF={bd_off}\n")
        f.write(f"DVD_VAL={dvd_val}\n")
        f.write(f"BD_VAL={bd_val}\n")
        f.write(f"FILE_SIZE={sz}\n")
        f.write(f"DESC='{order} {c['file_size']} dvd={dvd_val} bd={bd_val} {pos} {pad} {c['mode']}'\n")

print(f"Generated {len(cases)} config files in {d}")
PYEOF

# --- Run tests ---

for meta in "$D"/case_*.meta; do
    . "$meta"   # loads ORDER, MODE, DVD_OFF, BD_OFF, DVD_VAL, BD_VAL, FILE_SIZE, DESC
    CASE=$(basename "$meta" .meta)
    BIN="$D/${CASE}.bin"
    W="$D/${CASE}_work"
    mkdir -p "$W"

    echo "$CASE: $DESC"

    # --- same_offset: DVD key missing → expect error ---
    if [ "$ORDER" = "same_offset" ]; then
        GOT_DVD=$(find_offset "$BIN" "IDX_GB_PTT_REGIONCODE") || true
        check "$CASE dvd not found" "${GOT_DVD:-(empty)}" "(empty)"
        GOT_BD=$(find_offset "$BIN" "IDX_GB_PTT_BDREGIONCODE")
        check "$CASE bd found" "$GOT_BD" "$BD_OFF"
        continue
    fi

    # --- Normal: find both keys ---
    GOT_DVD=$(find_offset "$BIN" "IDX_GB_PTT_REGIONCODE")
    GOT_BD=$(find_offset "$BIN" "IDX_GB_PTT_BDREGIONCODE")
    check "$CASE dvd offset" "$GOT_DVD" "$DVD_OFF"
    check "$CASE bd offset"  "$GOT_BD"  "$BD_OFF"

    DVD_VAL_OFF=$((GOT_DVD + 36))
    BD_VAL_OFF=$((GOT_BD + 36))

    # Verify initial values
    check "$CASE dvd initial" "$(read_byte "$BIN" $DVD_VAL_OFF)" "$(printf '%02x' $DVD_VAL)"
    check "$CASE bd initial"  "$(read_byte "$BIN" $BD_VAL_OFF)"  "$(printf '%02x' $BD_VAL)"

    # --- set_regionfree mode ---
    cp "$BIN" "$W/conf.bin"
    printf '\x00' | dd of="$W/conf.bin" bs=1 seek=$DVD_VAL_OFF conv=notrunc 2>/dev/null
    printf '\x07' | dd of="$W/conf.bin" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null
    check "$CASE dvd→00" "$(read_byte "$W/conf.bin" $DVD_VAL_OFF)" "00"
    check "$CASE bd→07"  "$(read_byte "$W/conf.bin" $BD_VAL_OFF)"  "07"

    # --- restore mode ---
    if [ "$MODE" = "restore" ]; then
        # Save backups (as run.sh does)
        dd if="$BIN" bs=1 skip=$DVD_VAL_OFF count=1 of="$W/.dvd_backup.bin" 2>/dev/null
        dd if="$BIN" bs=1 skip=$BD_VAL_OFF count=1 of="$W/.bd_backup.bin" 2>/dev/null

        # Restore from backup
        dd if="$W/.dvd_backup.bin" of="$W/conf.bin" bs=1 seek=$DVD_VAL_OFF conv=notrunc 2>/dev/null
        dd if="$W/.bd_backup.bin"  of="$W/conf.bin" bs=1 seek=$BD_VAL_OFF  conv=notrunc 2>/dev/null

        check "$CASE restore dvd" "$(read_byte "$W/conf.bin" $DVD_VAL_OFF)" "$(printf '%02x' $DVD_VAL)"
        check "$CASE restore bd"  "$(read_byte "$W/conf.bin" $BD_VAL_OFF)"  "$(printf '%02x' $BD_VAL)"
    fi
done

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL $PASS PAIRWISE TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
