#!/bin/sh
# End-to-end tests for run.sh target selection, write validation and RESTORE.
# Cases generated with Microsoft PICT (pairwise, 66 cases) from this model:
#
#   bd_file:  missing, value1, value2, value3, value4, value5, value6,
#             seven, empty, text, leadzero, padded, crlf, ten
#   dvd_file: missing, empty, value1, value6, value8, text
#   restore:  no, with_backup, without_backup
#   config:   valid, no_bd_key, no_dvd_key
#
# Each case builds a fake config and USB tree and runs the real run.sh.
# Expected: exit code, final BD/DVD byte, and which result file exists.
# Run from the repo root: sh tests/test_targets_pict.sh
#
# PICT pairwise alone produces few fully valid write combinations (one bad
# parameter masks the others), so 24 seeded cases cover the happy paths and
# the key error/restore branches explicitly.
#
# run.sh is executed with `zsh --emulate sh` because macOS dash's printf has no
# \x escape (the player's busybox printf does). `sync` is stubbed: the test
# checks file bytes and result files, not durability.

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
TMP=$(mktemp -d "$ROOT/tests/.targets.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
command -v zsh >/dev/null 2>&1 || { echo "SKIP: zsh not found"; exit 0; }
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sync"
chmod +x "$TMP/bin/sync"

rd() { dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
has() { [ -f "$1" ] && echo 1 || echo 0; }

mkconf() { # $1 file, $2 config kind
    dd if=/dev/zero of="$1" bs=1219 count=1 2>/dev/null
    if [ "$2" != "no_dvd_key" ]; then
        printf 'IDX_GB_PTT_REGIONCODE' | dd of="$1" bs=1 seek=127 conv=notrunc 2>/dev/null
        printf '\x04' | dd of="$1" bs=1 seek=163 conv=notrunc 2>/dev/null
    fi
    if [ "$2" != "no_bd_key" ]; then
        printf 'IDX_GB_PTT_BDREGIONCODE' | dd of="$1" bs=1 seek=201 conv=notrunc 2>/dev/null
        printf '\x02' | dd of="$1" bs=1 seek=237 conv=notrunc 2>/dev/null
    fi
}

mkfiles() { # $1 dir, $2 bd kind, $3 dvd kind, $4 restore kind
    case "$2" in
        missing) : ;;
        value1) printf '1\n' > "$1/bd_region.txt" ;;
        value2) printf '2\n' > "$1/bd_region.txt" ;;
        value4) printf '4\n' > "$1/bd_region.txt" ;;
        value3) printf '3\n' > "$1/bd_region.txt" ;;
        value5) printf '5\n' > "$1/bd_region.txt" ;;
        value6) printf '6\n' > "$1/bd_region.txt" ;;
        seven) printf '7\n' > "$1/bd_region.txt" ;;
        zero) printf '0\n' > "$1/bd_region.txt" ;;
        three) printf '3\n' > "$1/bd_region.txt" ;;
        v255) printf '255\n' > "$1/bd_region.txt" ;;
        empty) : > "$1/bd_region.txt" ;;
        text) printf 'abc\n' > "$1/bd_region.txt" ;;
        leadzero) printf '01\n' > "$1/bd_region.txt" ;;
        padded) printf ' 2 \n' > "$1/bd_region.txt" ;;
        crlf) printf '2\r\n' > "$1/bd_region.txt" ;;
        ten) printf '10\n' > "$1/bd_region.txt" ;;
    esac
    case "$3" in
        missing) : ;;
        empty) : > "$1/dvd_region.txt" ;;
        value1) printf '1\n' > "$1/dvd_region.txt" ;;
        value0) printf '0\n' > "$1/dvd_region.txt" ;;
        doublezero) printf '00\n' > "$1/dvd_region.txt" ;;
        value6) printf '6\n' > "$1/dvd_region.txt" ;;
        value8) printf '8\n' > "$1/dvd_region.txt" ;;
        text) printf 'abc\n' > "$1/dvd_region.txt" ;;
    esac
    case "$4" in
        no) : ;;
        without_backup) : > "$1/RESTORE" ;;
        with_backup)
            : > "$1/RESTORE"
            printf '\x04' > "$1/.dvd_backup.bin"
            printf '\x02' > "$1/.bd_backup.bin"
            ;;
    esac
}

run_case() { # id bd dvd restore config exp_exit exp_bd exp_dvd exp_result
    id="$1"; bd="$2"; dvd="$3"; restore="$4"; config="$5"
    exp_exit="$6"; exp_bd="$7"; exp_dvd="$8"; exp_result="$9"
    d="$TMP/$id"; mkdir -p "$d/usb"; f="$d/conf.txt"
    mkconf "$f" "$config"
    mkfiles "$d/usb" "$bd" "$dvd" "$restore"
    USB="$d/usb" CONF="$f" PATH="$TMP/bin:$PATH" zsh --emulate sh "$RUN" >/dev/null 2>&1
    rc=$?
    check "$id exit" "$rc" "$exp_exit"
    check "$id BD byte" "$(rd "$f" 237)" "$exp_bd"
    check "$id DVD byte" "$(rd "$f" 163)" "$exp_dvd"
    case "$exp_result" in
        OK) want=REGION_FREE_OK.txt ;;
        FAILED) want=REGION_FREE_FAILED.txt ;;
        RESTORED) want=REGION_RESTORED.txt ;;
        RESTORE_FAILED) want=REGION_RESTORE_FAILED.txt ;;
    esac
    for rf in REGION_FREE_OK.txt REGION_FREE_FAILED.txt REGION_RESTORED.txt REGION_RESTORE_FAILED.txt; do
        [ "$rf" = "$want" ] && w=1 || w=0
        check "$id $rf" "$(has "$d/usb/$rf")" "$w"
    done
}

while IFS='|' read -r id bd dvd restore config exp_exit exp_bd exp_dvd exp_result; do
    [ -n "$id" ] && run_case "$id" "$bd" "$dvd" "$restore" "$config" \
        "$exp_exit" "$exp_bd" "$exp_dvd" "$exp_result"
done <<'CASES'
c01|padded|text|no|no_bd_key|1|00|04|FAILED
c02|value1|value8|without_backup|no_dvd_key|1|02|00|FAILED
c03|missing|text|with_backup|valid|0|02|04|RESTORED
c04|value2|value8|no|valid|1|02|04|FAILED
c05|ten|empty|with_backup|no_dvd_key|1|02|00|FAILED
c06|missing|missing|without_backup|no_bd_key|1|00|04|FAILED
c07|seven|missing|with_backup|valid|0|02|04|RESTORED
c08|padded|value1|with_backup|no_dvd_key|1|02|00|FAILED
c09|missing|empty|without_backup|valid|0|02|04|RESTORE_FAILED
c10|crlf|missing|no|no_dvd_key|1|02|00|FAILED
c11|ten|text|without_backup|no_bd_key|1|00|04|FAILED
c12|leadzero|empty|with_backup|no_bd_key|1|00|04|FAILED
c13|value2|value1|without_backup|no_bd_key|1|00|04|FAILED
c14|padded|value8|without_backup|valid|0|02|04|RESTORE_FAILED
c15|leadzero|missing|no|no_dvd_key|1|02|00|FAILED
c16|leadzero|value6|without_backup|valid|0|02|04|RESTORE_FAILED
c17|value4|missing|no|no_bd_key|1|00|04|FAILED
c18|seven|value6|no|no_bd_key|1|00|04|FAILED
c19|crlf|text|with_backup|no_dvd_key|1|02|00|FAILED
c20|crlf|empty|no|no_bd_key|1|00|04|FAILED
c21|empty|text|with_backup|no_bd_key|1|00|04|FAILED
c22|value4|empty|with_backup|valid|0|02|04|RESTORED
c23|empty|missing|no|valid|0|01|01|OK
c24|value4|value1|without_backup|valid|0|02|04|RESTORE_FAILED
c25|crlf|value1|without_backup|valid|0|02|04|RESTORE_FAILED
c26|seven|empty|without_backup|no_dvd_key|1|02|00|FAILED
c27|padded|missing|without_backup|no_bd_key|1|00|04|FAILED
c28|text|missing|with_backup|valid|0|02|04|RESTORED
c29|ten|missing|no|valid|1|02|04|FAILED
c30|missing|value8|no|no_dvd_key|1|02|00|FAILED
c31|ten|value6|with_backup|no_dvd_key|1|02|00|FAILED
c32|value4|text|without_backup|no_dvd_key|1|02|00|FAILED
c33|seven|value8|with_backup|no_bd_key|1|00|04|FAILED
c34|empty|empty|without_backup|no_dvd_key|1|02|00|FAILED
c35|text|value8|no|no_dvd_key|1|02|00|FAILED
c36|value4|value8|no|valid|1|02|04|FAILED
c37|leadzero|value1|no|no_bd_key|1|00|04|FAILED
c38|leadzero|value8|with_backup|no_bd_key|1|00|04|FAILED
c39|missing|value6|without_backup|valid|0|02|04|RESTORE_FAILED
c40|ten|value8|with_backup|valid|0|02|04|RESTORED
c41|text|value1|without_backup|no_bd_key|1|00|04|FAILED
c42|seven|value1|no|no_dvd_key|1|02|00|FAILED
c43|crlf|value6|with_backup|valid|0|02|04|RESTORED
c44|seven|text|without_backup|no_bd_key|1|00|04|FAILED
c45|value2|missing|with_backup|no_dvd_key|1|02|00|FAILED
c46|leadzero|text|no|no_dvd_key|1|02|00|FAILED
c47|text|text|with_backup|valid|0|02|04|RESTORED
c48|empty|value1|without_backup|valid|0|02|04|RESTORE_FAILED
c49|value1|value6|with_backup|valid|0|02|04|RESTORED
c50|value2|value6|with_backup|no_dvd_key|1|02|00|FAILED
c51|crlf|value8|with_backup|valid|0|02|04|RESTORED
c52|padded|value6|no|valid|0|02|06|OK
c53|value1|missing|no|no_bd_key|1|00|04|FAILED
c54|value2|empty|without_backup|no_bd_key|1|00|04|FAILED
c55|padded|empty|no|no_bd_key|1|00|04|FAILED
c56|missing|value1|with_backup|valid|0|02|04|RESTORED
c57|value1|text|without_backup|no_bd_key|1|00|04|FAILED
c58|value1|value1|no|no_bd_key|1|00|04|FAILED
c59|value1|empty|with_backup|no_dvd_key|1|02|00|FAILED
c60|text|value6|with_backup|valid|0|02|04|RESTORED
c61|ten|value1|with_backup|no_dvd_key|1|02|00|FAILED
c62|empty|value6|without_backup|no_dvd_key|1|02|00|FAILED
c63|empty|value8|with_backup|no_bd_key|1|00|04|FAILED
c64|value2|text|with_backup|no_dvd_key|1|02|00|FAILED
c65|text|empty|with_backup|no_bd_key|1|00|04|FAILED
c66|value4|value6|without_backup|valid|0|02|04|RESTORE_FAILED
s01|value1|missing|no|valid|0|01|01|OK
s02|value2|empty|no|valid|0|02|04|OK
s03|value4|value1|no|valid|0|04|01|OK
s04|missing|value6|no|valid|0|01|06|OK
s05|empty|missing|no|valid|0|01|01|OK
s06|leadzero|missing|no|valid|0|01|01|OK
s07|padded|empty|no|valid|0|02|04|OK
s08|crlf|value6|no|valid|0|02|06|OK
s09|value1|value0|no|valid|0|01|00|OK
s10|value1|value8|no|valid|1|02|04|FAILED
s11|seven|value1|no|valid|1|02|04|FAILED
s12|text|empty|no|valid|1|02|04|FAILED
s13|ten|missing|no|valid|1|02|04|FAILED
s14|value2|text|no|valid|1|02|04|FAILED
s15|value1|value1|no|no_bd_key|1|00|04|FAILED
s16|value1|value1|no|no_dvd_key|1|02|00|FAILED
s17|seven|value8|with_backup|valid|0|02|04|RESTORED
s18|value1|value1|without_backup|valid|0|02|04|RESTORE_FAILED
s19|value1|value1|with_backup|no_bd_key|1|00|04|FAILED
s20|seven|value8|without_backup|no_dvd_key|1|02|00|FAILED
s21|zero|value1|no|valid|1|02|04|FAILED
s22|three|value1|no|valid|0|03|01|OK
s23|v255|value1|no|valid|1|02|04|FAILED
s24|value1|doublezero|no|valid|0|01|00|OK
b01|value3|value1|no|valid|0|03|01|OK
b02|value5|value1|no|valid|0|05|01|OK
b03|value6|value1|no|valid|0|06|01|OK
CASES

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL TARGET-SELECTION TESTS PASSED"
    exit 0
fi
echo "SOME TESTS FAILED"
exit 1
