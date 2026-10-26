#!/bin/sh
# Tests the tmo() helper extracted from run.sh: piped stdin must reach the
# command (async lists otherwise get /dev/null), a hung command must be killed,
# and normal output/exit codes must pass through. Run from the repo root:
#   sh tests/test_tmo.sh

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
T=$(mktemp -d "$ROOT/tests/.tmo.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

sed -n '/^# --- tmo:/,/^# --- end tmo ---/p' "$ROOT/usb-files/run.sh" > "$T/tmo.sh"
[ -s "$T/tmo.sh" ] || { echo "FAIL: tmo block not found in run.sh"; exit 1; }
. "$T/tmo.sh"

# Piped stdin (the EEPROM write path: printf | tmo 3 dd of=...)
printf 'abc' | tmo 3 dd of="$T/piped" bs=1 count=3 conv=notrunc 2>/dev/null
check "piped stdin" "$(cat "$T/piped" 2>/dev/null)" "abc"

# A hung command is killed within the limit and returns non-zero
T0=$(date +%s)
tmo 1 sleep 5
RC=$?
ELAPSED=$(( $(date +%s) - T0 ))
check "hung command killed" "$([ "$ELAPSED" -le 3 ] && [ "$RC" -ne 0 ] && echo y)" "y"

# stdout and exit code pass through unchanged
OUT=$(tmo 3 sh -c 'echo hi; exit 3')
check "stdout" "$OUT" "hi"
tmo 3 sh -c 'exit 3'
check "exit code" "$?" "3"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
