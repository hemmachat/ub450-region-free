#!/bin/sh
# Pairwise tests for DVD_REGION file parsing, backup, write, and restore logic.
# Generated from a PICT model with 6 parameters.
# Run from the repo root: sh tests/test_dvd_region.sh

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

# --- Helpers (from usb-files/run.sh v3.2) ---

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

# --- Generate test configs and run cases ---

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

python3 -I << 'PYEOF'
import os, json

d = os.environ.get("D", "") or "$D"
PYEOF

# Use shell to pass D to python
python3 -I - "$D" << 'PYEOF'
import os, sys

d = sys.argv[1]

DVD = b"IDX_GB_PTT_REGIONCODE"
BD  = b"IDX_GB_PTT_BDREGIONCODE"
RECORD = 36

# PICT model:
#   dvd_file:    absent | DVD_REGION | DVD_REGION.txt
#   dvd_content: 1 | 4 | 6 | 0 | 7 | abc | empty
#   initial_dvd: 1 | 2 | 4
#   initial_bd:  2 | 4 | 7
#   has_backup:  yes | no
#   mode:        set | restore
#
# Constraints:
#   IF dvd_file = absent THEN dvd_content = empty
#   IF mode = restore THEN has_backup = yes

cases = [
    {"n":1,  "dvd_file":"DVD_REGION",     "dvd_content":"1",     "initial_dvd":4, "initial_bd":2, "has_backup":"no",  "mode":"set"},
    {"n":2,  "dvd_file":"DVD_REGION.txt", "dvd_content":"4",     "initial_dvd":2, "initial_bd":4, "has_backup":"yes", "mode":"set"},
    {"n":3,  "dvd_file":"absent",         "dvd_content":"empty", "initial_dvd":1, "initial_bd":7, "has_backup":"no",  "mode":"set"},
    {"n":4,  "dvd_file":"DVD_REGION",     "dvd_content":"6",     "initial_dvd":1, "initial_bd":4, "has_backup":"no",  "mode":"set"},
    {"n":5,  "dvd_file":"DVD_REGION.txt", "dvd_content":"0",     "initial_dvd":4, "initial_bd":7, "has_backup":"yes", "mode":"set"},
    {"n":6,  "dvd_file":"DVD_REGION",     "dvd_content":"7",     "initial_dvd":2, "initial_bd":2, "has_backup":"no",  "mode":"set"},
    {"n":7,  "dvd_file":"DVD_REGION.txt", "dvd_content":"abc",   "initial_dvd":1, "initial_bd":2, "has_backup":"yes", "mode":"set"},
    {"n":8,  "dvd_file":"absent",         "dvd_content":"empty", "initial_dvd":4, "initial_bd":4, "has_backup":"yes", "mode":"restore"},
    {"n":9,  "dvd_file":"DVD_REGION",     "dvd_content":"1",     "initial_dvd":2, "initial_bd":7, "has_backup":"yes", "mode":"restore"},
    {"n":10, "dvd_file":"DVD_REGION.txt", "dvd_content":"6",     "initial_dvd":4, "initial_bd":2, "has_backup":"yes", "mode":"restore"},
    {"n":11, "dvd_file":"DVD_REGION",     "dvd_content":"4",     "initial_dvd":1, "initial_bd":2, "has_backup":"yes", "mode":"set"},
    {"n":12, "dvd_file":"absent",         "dvd_content":"empty", "initial_dvd":2, "initial_bd":2, "has_backup":"yes", "mode":"set"},
    {"n":13, "dvd_file":"DVD_REGION",     "dvd_content":"abc",   "initial_dvd":4, "initial_bd":4, "has_backup":"no",  "mode":"set"},
    {"n":14, "dvd_file":"DVD_REGION.txt", "dvd_content":"1",     "initial_dvd":1, "initial_bd":4, "has_backup":"no",  "mode":"set"},
    {"n":15, "dvd_file":"DVD_REGION",     "dvd_content":"0",     "initial_dvd":2, "initial_bd":4, "has_backup":"yes", "mode":"set"},
    {"n":16, "dvd_file":"DVD_REGION.txt", "dvd_content":"7",     "initial_dvd":4, "initial_bd":7, "has_backup":"no",  "mode":"set"},
    {"n":17, "dvd_file":"DVD_REGION",     "dvd_content":"empty", "initial_dvd":4, "initial_bd":7, "has_backup":"yes", "mode":"restore"},
    {"n":18, "dvd_file":"absent",         "dvd_content":"empty", "initial_dvd":1, "initial_bd":2, "has_backup":"no",  "mode":"set"},
    {"n":19, "dvd_file":"DVD_REGION.txt", "dvd_content":"empty", "initial_dvd":2, "initial_bd":2, "has_backup":"no",  "mode":"set"},
    {"n":20, "dvd_file":"DVD_REGION",     "dvd_content":"1",     "initial_dvd":1, "initial_bd":7, "has_backup":"no",  "mode":"set"},
    {"n":21, "dvd_file":"DVD_REGION.txt", "dvd_content":"4",     "initial_dvd":4, "initial_bd":2, "has_backup":"yes", "mode":"restore"},
    {"n":22, "dvd_file":"DVD_REGION",     "dvd_content":"6",     "initial_dvd":2, "initial_bd":7, "has_backup":"yes", "mode":"set"},
    {"n":23, "dvd_file":"absent",         "dvd_content":"empty", "initial_dvd":4, "initial_bd":4, "has_backup":"no",  "mode":"set"},
    {"n":24, "dvd_file":"DVD_REGION.txt", "dvd_content":"abc",   "initial_dvd":2, "initial_bd":7, "has_backup":"yes", "mode":"restore"},
]

for c in cases:
    sz = 1219
    data = bytearray(sz)
    dvd_off = 127
    bd_off = 201
    data[dvd_off:dvd_off+len(DVD)] = DVD
    data[dvd_off+RECORD] = c["initial_dvd"]
    data[bd_off:bd_off+len(BD)] = BD
    data[bd_off+RECORD] = c["initial_bd"]

    case_dir = os.path.join(d, f"case_{c['n']:02d}")
    os.makedirs(case_dir, exist_ok=True)

    # Write config file
    open(os.path.join(case_dir, "conf.bin"), "wb").write(data)

    # Write DVD_REGION file if needed
    if c["dvd_file"] != "absent":
        content = "" if c["dvd_content"] == "empty" else c["dvd_content"]
        open(os.path.join(case_dir, c["dvd_file"]), "w").write(content + "\n")

    # Write existing backup if needed (original values)
    if c["has_backup"] == "yes":
        open(os.path.join(case_dir, ".dvd_backup.bin"), "wb").write(bytes([c["initial_dvd"]]))
        open(os.path.join(case_dir, ".bd_backup.bin"), "wb").write(bytes([c["initial_bd"]]))
        open(os.path.join(case_dir, ".dvd_offset.txt"), "w").write(str(dvd_off + RECORD) + "\n")
        open(os.path.join(case_dir, ".bd_offset.txt"), "w").write(str(bd_off + RECORD) + "\n")

    # Write RESTORE flag if restore mode
    if c["mode"] == "restore":
        open(os.path.join(case_dir, "RESTORE"), "w").write("")

    # Determine expected DVD target
    dvd_target = ""
    if c["dvd_file"] != "absent" and c["dvd_content"] not in ("empty", "abc", "0", "7"):
        dvd_target = c["dvd_content"]

    # Determine expected values after run
    if c["mode"] == "restore":
        exp_dvd = c["initial_dvd"]  # restored to original
        exp_bd = c["initial_bd"]
    else:
        exp_bd = 7  # always set
        if dvd_target:
            exp_dvd = int(dvd_target)
        else:
            exp_dvd = c["initial_dvd"]  # unchanged

    meta = os.path.join(case_dir, "meta")
    with open(meta, "w") as f:
        f.write(f"DVD_FILE='{c['dvd_file']}'\n")
        f.write(f"DVD_CONTENT='{c['dvd_content']}'\n")
        f.write(f"INITIAL_DVD={c['initial_dvd']}\n")
        f.write(f"INITIAL_BD={c['initial_bd']}\n")
        f.write(f"HAS_BACKUP='{c['has_backup']}'\n")
        f.write(f"MODE='{c['mode']}'\n")
        f.write(f"DVD_TARGET='{dvd_target}'\n")
        f.write(f"EXP_DVD={exp_dvd}\n")
        f.write(f"EXP_BD={exp_bd}\n")
        f.write(f"DESC='{c['dvd_file']} content={c['dvd_content']} dvd={c['initial_dvd']} bd={c['initial_bd']} backup={c['has_backup']} {c['mode']}'\n")

print(f"Generated {len(cases)} test cases")
PYEOF

# --- Run tests ---

for case_dir in "$D"/case_*; do
    [ -d "$case_dir" ] || continue
    . "$case_dir/meta"
    CASE=$(basename "$case_dir")
    CONF="$case_dir/conf.bin"
    USB="$case_dir"

    echo "$CASE: $DESC"

    # --- Parse DVD_REGION file (same logic as run.sh) ---
    PARSED_TARGET=""
    DVD_REGION_FILE=""
    if [ -f "$USB/DVD_REGION" ]; then
        DVD_REGION_FILE="$USB/DVD_REGION"
    elif [ -f "$USB/DVD_REGION.txt" ]; then
        DVD_REGION_FILE="$USB/DVD_REGION.txt"
    fi
    if [ -n "$DVD_REGION_FILE" ]; then
        PARSED_TARGET=$(head -1 "$DVD_REGION_FILE" 2>/dev/null | tr -cd '0-9' | head -c 1)
        if [ -n "$PARSED_TARGET" ] && [ "$PARSED_TARGET" -ge 1 ] && [ "$PARSED_TARGET" -le 6 ]; then
            : # valid
        else
            PARSED_TARGET=""
        fi
    fi

    check "$CASE dvd_target parsed" "$PARSED_TARGET" "$DVD_TARGET"

    # --- Find offsets ---
    DVD_KEY_OFF=$(find_offset "$CONF" "IDX_GB_PTT_REGIONCODE")
    BD_KEY_OFF=$(find_offset "$CONF" "IDX_GB_PTT_BDREGIONCODE")
    DVD_VAL_OFF=$((DVD_KEY_OFF + 36))
    BD_VAL_OFF=$((BD_KEY_OFF + 36))

    # --- Read current values ---
    DVD_HEX=$(read_byte "$CONF" $DVD_VAL_OFF)
    BD_HEX=$(read_byte "$CONF" $BD_VAL_OFF)
    check "$CASE initial dvd" "$DVD_HEX" "$(printf '%02x' $INITIAL_DVD)"
    check "$CASE initial bd" "$BD_HEX" "$(printf '%02x' $INITIAL_BD)"

    # --- Restore mode ---
    if [ "$MODE" = "restore" ]; then
        if [ -f "$USB/.dvd_backup.bin" ] && [ -f "$USB/.bd_backup.bin" ]; then
            RESTORE_DVD_OFF=$(cat "$USB/.dvd_offset.txt")
            RESTORE_BD_OFF=$(cat "$USB/.bd_offset.txt")
            dd if="$USB/.dvd_backup.bin" of="$CONF" bs=1 seek=$RESTORE_DVD_OFF conv=notrunc 2>/dev/null
            dd if="$USB/.bd_backup.bin" of="$CONF" bs=1 seek=$RESTORE_BD_OFF conv=notrunc 2>/dev/null
            DVD_R=$(read_byte "$CONF" $RESTORE_DVD_OFF)
            BD_R=$(read_byte "$CONF" $RESTORE_BD_OFF)
            check "$CASE restore dvd" "$DVD_R" "$(printf '%02x' $EXP_DVD)"
            check "$CASE restore bd" "$BD_R" "$(printf '%02x' $EXP_BD)"

            # Verify backup files still exist (not clobbered)
            check "$CASE backup preserved" "$([ -f "$USB/.dvd_backup.bin" ] && echo yes)" "yes"
        else
            echo "  FAIL [$CASE restore]: backup files missing"
            FAIL=$((FAIL + 1))
        fi
        continue
    fi

    # --- Backup logic ---
    DVD_TARGET_HEX=""
    if [ -n "$PARSED_TARGET" ]; then
        DVD_TARGET_HEX=$(printf '%02x' "$PARSED_TARGET")
    fi

    if [ "$BD_HEX" = "07" ] && { [ -z "$PARSED_TARGET" ] || [ "$DVD_HEX" = "$DVD_TARGET_HEX" ]; } && [ -f "$USB/.dvd_backup.bin" ]; then
        : # nothing to change, keep existing backup
    else
        dd if="$CONF" bs=1 skip=$DVD_VAL_OFF count=1 of="$USB/.dvd_backup.bin" 2>/dev/null
        dd if="$CONF" bs=1 skip=$BD_VAL_OFF count=1 of="$USB/.bd_backup.bin" 2>/dev/null
    fi

    # Verify backup contains original values (not post-write values)
    BACKUP_DVD=$(read_byte "$USB/.dvd_backup.bin" 0)
    BACKUP_BD=$(read_byte "$USB/.bd_backup.bin" 0)
    check "$CASE backup dvd" "$BACKUP_DVD" "$(printf '%02x' $INITIAL_DVD)"
    check "$CASE backup bd" "$BACKUP_BD" "$(printf '%02x' $INITIAL_BD)"

    # --- Write ---
    if [ -n "$PARSED_TARGET" ]; then
        printf "\\x0${PARSED_TARGET}" | dd of="$CONF" bs=1 seek=$DVD_VAL_OFF conv=notrunc 2>/dev/null
    fi
    printf '\x07' | dd of="$CONF" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null

    # --- Verify ---
    DVD_AFTER=$(read_byte "$CONF" $DVD_VAL_OFF)
    BD_AFTER=$(read_byte "$CONF" $BD_VAL_OFF)
    check "$CASE after dvd" "$DVD_AFTER" "$(printf '%02x' $EXP_DVD)"
    check "$CASE after bd" "$BD_AFTER" "$(printf '%02x' $EXP_BD)"

    # --- Verify success detection logic ---
    BD_OK=false
    DVD_OK=false
    [ "$BD_AFTER" = "07" ] && BD_OK=true
    if [ -n "$DVD_TARGET_HEX" ]; then
        [ "$DVD_AFTER" = "$DVD_TARGET_HEX" ] && DVD_OK=true
    else
        DVD_OK=true
    fi
    check "$CASE success" "$($BD_OK && $DVD_OK && echo yes || echo no)" "yes"
done

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL $PASS DVD_REGION TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
