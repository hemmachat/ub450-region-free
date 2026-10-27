#!/bin/sh
# End-to-end tests for the v5.10 EEPROM guard in run.sh, using fake device
# files through the EEPROM_CANDIDATES hook. Covers: opt-in file, no-op skip,
# one match, ambiguous matches, invalid and mismatched values, IR byte,
# backup, write, and RESTORE.
# Run from the repo root: sh tests/test_eeprom_pairwise.sh

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
T=$(mktemp -d "$ROOT/tests/.eeprom.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
command -v zsh >/dev/null 2>&1 || { echo "SKIP: zsh not found"; exit 0; }
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sync"
chmod +x "$T/bin/sync"

oct() { printf "\\$(printf '%03o' "$1")"; }
rd() { dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
has() { [ -f "$1" ] && echo 1 || echo 0; }
logged() { grep -q "$1" "$2/region_log.txt" 2>/dev/null && echo 1 || echo 0; }

mkconf() { # $1 file, $2 DVD byte
    dd if=/dev/zero of="$1" bs=1219 count=1 2>/dev/null
    printf 'IDX_GB_PTT_REGIONCODE' | dd of="$1" bs=1 seek=127 conv=notrunc 2>/dev/null
    oct "$2" | dd of="$1" bs=1 seek=163 conv=notrunc 2>/dev/null
    printf 'IDX_GB_PTT_BDREGIONCODE' | dd of="$1" bs=1 seek=201 conv=notrunc 2>/dev/null
    oct 2 | dd of="$1" bs=1 seek=237 conv=notrunc 2>/dev/null
}

mkdev() { # $1 file, $2 DVD byte, $3 IR byte
    dd if=/dev/zero of="$1" bs=1024 count=1 2>/dev/null
    oct "$2" | dd of="$1" bs=1 seek=512 conv=notrunc 2>/dev/null
    oct "$3" | dd of="$1" bs=1 seek=517 conv=notrunc 2>/dev/null
}

# id | config DVD | dvd_region.txt | DVD_EEPROM | devices (value:ir,...) | dev0 after | log marker | backup
while IFS='|' read -r id dvd_before dvd_file optin devices after marker backup; do
    [ -n "$id" ] || continue
    d="$T/$id"
    mkdir -p "$d/usb" "$d/dev"
    mkconf "$d/conf.txt" "$dvd_before"
    printf '1\n' > "$d/usb/bd_region.txt"
    case "$dvd_file" in
        empty) : > "$d/usb/dvd_region.txt" ;;
        *) printf '%s\n' "$dvd_file" > "$d/usb/dvd_region.txt" ;;
    esac
    [ "$optin" = "yes" ] && : > "$d/usb/DVD_EEPROM"

    cands=""
    i=0
    old_ifs=$IFS
    IFS=','
    for spec in $devices; do
        IFS=$old_ifs
        case "$spec" in
            none) cands="$d/dev/missing/mtd0" ;;
            *)
                dev="$d/dev/mtd$i"
                mkdev "$dev" "${spec%%:*}" "${spec##*:}"
                cands="$cands $dev"
                i=$((i + 1))
            ;;
        esac
        IFS=','
    done
    IFS=$old_ifs

    EEPROM_CANDIDATES="$cands" USB="$d/usb" CONF="$d/conf.txt" \
        PATH="$T/bin:$PATH" zsh --emulate sh "$RUN" >/dev/null 2>&1
    rc=$?

    check "$id exit" "$rc" "0"
    case "$dvd_file" in
        empty) exp_cfg=$(printf '%02x' "$dvd_before") ;;
        *) exp_cfg=$(printf '%02x' "$dvd_file") ;;
    esac
    check "$id config DVD" "$(rd "$d/conf.txt" 163)" "$exp_cfg"
    check "$id dev0 byte" "$(rd "$d/dev/mtd0" 512)" "$after"
    check "$id log" "$(logged "$marker" "$d/usb")" "1"
    check "$id backup" "$(has "$d/usb/.eeprom_dvd_backup.bin")" "$backup"
    case "$id" in
        noopt|noop|empty)
            # Skipped before the device loop: no device was even read
            check "$id no scan" "$(logged "Trying EEPROM device" "$d/usb")" "0"
        ;;
    esac
done <<'CASES'
noopt|2|1|no|2:0|02|DVD_EEPROM file not on USB|0
match|2|1|yes|2:0|01|EEPROM write SUCCEEDED|1
ambiguous|2|1|yes|2:0,2:0|02|EEPROM write REFUSED|0
noop|2|2|yes|2:0|02|DVD already 2 in config|0
mismatch|2|1|yes|3:0|03|doesn't match config|0
invalid|2|1|yes|7:0|07|not a valid DVD region|0
ir|2|1|yes|2:2|02|IR at 0x205 = 2|0
empty|2|empty|yes|2:0|02|DVD target empty|0
missing|2|1|yes|none||read at 0x200 returned empty|0
CASES

# Ambiguous case: the second device must also be untouched
check "ambiguous dev1 byte" "$(rd "$T/ambiguous/dev/mtd1" 512)" "02"

# RESTORE: config bytes and the EEPROM copy go back to the saved values
d="$T/restore"
mkdir -p "$d/usb" "$d/dev"
mkconf "$d/conf.txt" 2
mkdev "$d/dev/mtd0" 5 0
printf '1\n' > "$d/usb/bd_region.txt"
printf '1\n' > "$d/usb/dvd_region.txt"
: > "$d/usb/RESTORE"
oct 4 > "$d/usb/.dvd_backup.bin"
oct 2 > "$d/usb/.bd_backup.bin"
printf '163\n' > "$d/usb/.dvd_offset.txt"
printf '237\n' > "$d/usb/.bd_offset.txt"
{ oct 5; oct 0; oct 0; oct 0; } > "$d/usb/.eeprom_dvd_backup.bin"
printf '%s\n' "$d/dev/mtd0" > "$d/usb/.eeprom_device.txt"
EEPROM_CANDIDATES="$d/dev/mtd0" USB="$d/usb" CONF="$d/conf.txt" \
    PATH="$T/bin:$PATH" zsh --emulate sh "$RUN" >/dev/null 2>&1
check "restore exit" "$?" "0"
check "restore config DVD" "$(rd "$d/conf.txt" 163)" "04"
check "restore config BD" "$(rd "$d/conf.txt" 237)" "02"
check "restore eeprom" "$(rd "$d/dev/mtd0" 512)" "05"
check "restore result" "$(has "$d/usb/REGION_RESTORED.txt")" "1"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL $PASS EEPROM GUARD TESTS PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
