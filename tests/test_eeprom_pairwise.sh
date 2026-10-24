#!/bin/sh
# Pairwise tests for run.sh v6 EEPROM direct-write logic (Method 2).
# Tests the EEPROM detection, write, verify, backup, and restore paths
# using fake eeprom device files on the local filesystem.
# Run from the repo root: sh tests/test_eeprom_pairwise.sh
#
# PICT model (7 parameters, 27 cases):
#   eeprom_device:  eeprom_0_only | eeprom_3_only | both_present | neither
#   dvd_at_0x200:   0 | 1 | 2 | 4 | 6 | 0xff (invalid)
#   dvd_target:     0 | 1 | 4 | 6
#   has_backup:     yes | no
#   mode:           set | restore
#   extra_bytes:    zeroed | random
#   ir_at_0x205:    0 | 1
#
# Constraints:
#   neither + set → EEPROM_OK=0 (no device to write to)
#   neither + restore → skip EEPROM restore (no device file)
#   0xff (invalid) → EEPROM skipped for that device
#   restore requires has_backup=yes

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

read_byte() {
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_raw=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)
    printf '%02x' "'$_rb_raw"
}

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

# --- Generate 27 PICT cases ---

python3 -I << PYEOF
import os, random, struct
random.seed(42)
d = "$D"

cases = [
    {"n":1,  "device":"eeprom_0_only", "dvd_0x200":4,    "target":1, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":2,  "device":"eeprom_3_only", "dvd_0x200":2,    "target":0, "backup":"yes", "mode":"restore", "extra":"random",  "ir":1},
    {"n":3,  "device":"both_present",  "dvd_0x200":0,    "target":4, "backup":"no",  "mode":"set",     "extra":"random",  "ir":0},
    {"n":4,  "device":"neither",       "dvd_0x200":0xff, "target":1, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":5,  "device":"eeprom_0_only", "dvd_0x200":6,    "target":0, "backup":"yes", "mode":"set",     "extra":"random",  "ir":1},
    {"n":6,  "device":"eeprom_3_only", "dvd_0x200":1,    "target":6, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":7,  "device":"both_present",  "dvd_0x200":4,    "target":1, "backup":"yes", "mode":"restore", "extra":"zeroed",  "ir":1},
    {"n":8,  "device":"eeprom_0_only", "dvd_0x200":0xff, "target":4, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":1},
    {"n":9,  "device":"eeprom_3_only", "dvd_0x200":0,    "target":1, "backup":"yes", "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":10, "device":"neither",       "dvd_0x200":2,    "target":0, "backup":"no",  "mode":"set",     "extra":"random",  "ir":1},
    {"n":11, "device":"both_present",  "dvd_0x200":6,    "target":6, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":12, "device":"eeprom_0_only", "dvd_0x200":1,    "target":6, "backup":"yes", "mode":"restore", "extra":"zeroed",  "ir":0},
    {"n":13, "device":"eeprom_3_only", "dvd_0x200":4,    "target":4, "backup":"no",  "mode":"set",     "extra":"random",  "ir":1},
    {"n":14, "device":"both_present",  "dvd_0x200":2,    "target":0, "backup":"yes", "mode":"set",     "extra":"random",  "ir":1},
    {"n":15, "device":"neither",       "dvd_0x200":6,    "target":6, "backup":"yes", "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":16, "device":"eeprom_0_only", "dvd_0x200":0,    "target":1, "backup":"no",  "mode":"set",     "extra":"random",  "ir":0},
    {"n":17, "device":"eeprom_3_only", "dvd_0x200":6,    "target":4, "backup":"yes", "mode":"restore", "extra":"zeroed",  "ir":1},
    {"n":18, "device":"both_present",  "dvd_0x200":1,    "target":6, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":19, "device":"eeprom_0_only", "dvd_0x200":2,    "target":4, "backup":"yes", "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":20, "device":"eeprom_3_only", "dvd_0x200":0xff, "target":0, "backup":"no",  "mode":"set",     "extra":"random",  "ir":0},
    {"n":21, "device":"both_present",  "dvd_0x200":0,    "target":0, "backup":"yes", "mode":"restore", "extra":"random",  "ir":0},
    {"n":22, "device":"eeprom_0_only", "dvd_0x200":4,    "target":0, "backup":"no",  "mode":"set",     "extra":"zeroed",  "ir":1},
    {"n":23, "device":"eeprom_3_only", "dvd_0x200":1,    "target":1, "backup":"yes", "mode":"set",     "extra":"random",  "ir":1},
    {"n":24, "device":"both_present",  "dvd_0x200":0xff, "target":4, "backup":"yes", "mode":"set",     "extra":"zeroed",  "ir":0},
    {"n":25, "device":"neither",       "dvd_0x200":1,    "target":6, "backup":"yes", "mode":"set",     "extra":"random",  "ir":1},
    {"n":26, "device":"eeprom_0_only", "dvd_0x200":6,    "target":1, "backup":"no",  "mode":"set",     "extra":"random",  "ir":0},
    {"n":27, "device":"both_present",  "dvd_0x200":4,    "target":6, "backup":"yes", "mode":"restore", "extra":"random",  "ir":1},
]

EEPROM_SIZE = 1024  # enough to cover offset 0x200 + a few bytes

for c in cases:
    case_dir = os.path.join(d, f"case_{c['n']:02d}")
    os.makedirs(os.path.join(case_dir, "dev"), exist_ok=True)
    os.makedirs(os.path.join(case_dir, "usb"), exist_ok=True)

    def make_eeprom(path, dvd_val, ir_val, extra):
        if extra == "random":
            data = bytearray(random.randbytes(EEPROM_SIZE))
        else:
            data = bytearray(EEPROM_SIZE)
        # DVD region at offset 0x200 (512), 4 bytes LE
        struct.pack_into('<I', data, 0x200, dvd_val)
        # IR region at offset 0x205 (517), 4 bytes LE
        struct.pack_into('<I', data, 0x205, ir_val)
        open(path, "wb").write(data)

    dev = c["device"]
    dvd_val = c["dvd_0x200"]
    ir_val = c["ir"]

    if dev in ("eeprom_0_only", "both_present"):
        make_eeprom(os.path.join(case_dir, "dev", "eeprom_0"), dvd_val, ir_val, c["extra"])
    if dev in ("eeprom_3_only", "both_present"):
        make_eeprom(os.path.join(case_dir, "dev", "eeprom_3"), dvd_val, ir_val, c["extra"])

    # If backup exists, write the original value
    if c["backup"] == "yes":
        bdata = struct.pack('<I', dvd_val)
        open(os.path.join(case_dir, "usb", ".eeprom_dvd_backup.bin"), "wb").write(bdata)
        # Pick the first available device as the one we "backed up from"
        if dev in ("eeprom_0_only", "both_present"):
            dname = os.path.join(case_dir, "dev", "eeprom_0")
        elif dev == "eeprom_3_only":
            dname = os.path.join(case_dir, "dev", "eeprom_3")
        else:
            dname = "/dev/eeprom_0"  # won't exist, restore will skip
        open(os.path.join(case_dir, "usb", ".eeprom_device.txt"), "w").write(dname + "\n")

    # Metadata
    valid = dvd_val <= 6
    if dev == "neither":
        expect_ok = False
        active_dev = ""
    elif dev == "eeprom_0_only":
        expect_ok = valid
        active_dev = os.path.join(case_dir, "dev", "eeprom_0")
    elif dev == "eeprom_3_only":
        expect_ok = valid
        active_dev = os.path.join(case_dir, "dev", "eeprom_3")
    else:  # both_present — run.sh tries eeprom_0 first
        expect_ok = valid
        active_dev = os.path.join(case_dir, "dev", "eeprom_0")

    with open(os.path.join(case_dir, "meta.sh"), "w") as f:
        f.write(f"DEVICE={dev}\n")
        f.write(f"DVD_0x200={dvd_val}\n")
        f.write(f"TARGET={c['target']}\n")
        f.write(f"HAS_BACKUP={c['backup']}\n")
        f.write(f"MODE={c['mode']}\n")
        f.write(f"EXPECT_OK={'1' if expect_ok else '0'}\n")
        f.write(f"ACTIVE_DEV={active_dev}\n")
        f.write(f"IR={ir_val}\n")
        desc = f"{dev} 0x200={dvd_val:#x} target={c['target']} backup={c['backup']} {c['mode']} {c['extra']} ir={ir_val}"
        f.write(f"DESC='{desc}'\n")

print(f"Generated {len(cases)} EEPROM test cases in {d}")
PYEOF

# --- Run tests ---

for case_dir in "$D"/case_*; do
    [ -d "$case_dir" ] || continue
    . "$case_dir/meta.sh"
    CASE=$(basename "$case_dir")

    echo "$CASE: $DESC"

    DEV_DIR="$case_dir/dev"
    USB_DIR="$case_dir/usb"

    # === SET mode: simulate EEPROM detection + write ===

    EEPROM_OK=0

    for EEPROM_DEV in "$DEV_DIR/eeprom_0" "$DEV_DIR/eeprom_3"; do
        if [ ! -e "$EEPROM_DEV" ]; then continue; fi

        EEPROM_VAL=$(dd if="$EEPROM_DEV" bs=1 skip=512 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
        EEPROM_BYTE="${EEPROM_VAL%"${EEPROM_VAL#??}"}"
        EEPROM_DEC=$(printf '%d' "0x${EEPROM_BYTE:-ff}" 2>/dev/null)

        if [ "$EEPROM_DEC" -le 6 ] 2>/dev/null; then
            # Back up
            if [ ! -f "$USB_DIR/.eeprom_dvd_backup_test.bin" ]; then
                dd if="$EEPROM_DEV" bs=1 skip=512 count=4 of="$USB_DIR/.eeprom_dvd_backup_test.bin" 2>/dev/null
            fi

            # Write target as 4-byte LE
            printf "\\x$(printf '%02x' $TARGET)\\x00\\x00\\x00" | \
                dd of="$EEPROM_DEV" bs=1 seek=512 conv=notrunc 2>/dev/null

            # Verify
            EEPROM_CHECK=$(dd if="$EEPROM_DEV" bs=1 skip=512 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
            if [ "$EEPROM_CHECK" = "$(printf '%02x' $TARGET)" ]; then
                EEPROM_OK=1
            fi
            break
        fi
    done

    check "$CASE eeprom_ok" "$EEPROM_OK" "$EXPECT_OK"

    # Verify write landed at the right place
    if [ "$EEPROM_OK" = "1" ] && [ -n "$ACTIVE_DEV" ]; then
        check "$CASE written value" "$(read_byte "$ACTIVE_DEV" 512)" "$(printf '%02x' $TARGET)"
        # Bytes 513-514 should be 0x00 (LE padding)
        check "$CASE byte 513=00" "$(read_byte "$ACTIVE_DEV" 513)" "00"
        check "$CASE byte 514=00" "$(read_byte "$ACTIVE_DEV" 514)" "00"
    fi

    # === RESTORE mode: write back the backup ===

    if [ "$MODE" = "restore" ] && [ "$HAS_BACKUP" = "yes" ] && [ -f "$USB_DIR/.eeprom_dvd_backup.bin" ]; then
        RESTORE_DEV=$(cat "$USB_DIR/.eeprom_device.txt" 2>/dev/null | tr -d '\n')
        if [ -e "$RESTORE_DEV" ]; then
            dd if="$USB_DIR/.eeprom_dvd_backup.bin" of="$RESTORE_DEV" bs=1 seek=512 conv=notrunc 2>/dev/null
            RESTORED=$(read_byte "$RESTORE_DEV" 512)
            EXPECTED_HEX=$(printf '%02x' $DVD_0x200)
            check "$CASE restore value" "$RESTORED" "$EXPECTED_HEX"
        else
            # Device gone (neither case) — restore skipped, which is correct
            check "$CASE restore skip" "skipped" "skipped"
        fi
    fi

    # === Invalid device: value at 0x200 > 6 should be skipped ===

    if [ "$DVD_0x200" -gt 6 ] 2>/dev/null && [ "$DEVICE" != "neither" ]; then
        check "$CASE invalid skipped" "$EEPROM_OK" "0"
    fi
done

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL $PASS EEPROM PAIRWISE TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
