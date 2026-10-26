#!/bin/sh
# One-off test: writes the BD region byte once, then records it every few
# seconds while the player runs, to find out when the player clears it.
# Not a release script. Copy to the USB root as run.sh; the BDJ_DEBUG/BDJ.jar
# trigger runs it. No EEPROM scan, so the script lives longer than run.sh.
#
# The log answers one question: does the byte stay 0x07 until the player is
# switched off (shutdown/boot clears it), or does it change while running
# (and after how many seconds)?

CONF=${CONF:-/acfg/config_file_global.txt}
USB=${USB:-/mnt/sda1}
LOG=$USB/region_watch.txt
BD_KEY_OFF=201
BD_VAL_OFF=237
DVD_VAL_OFF=163
BD_TARGET=07
INTERVAL=${INTERVAL:-5}
MAX=${MAX:-180}

log() { echo "$1" >> "$LOG"; }

read_byte() {
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_raw=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)
    printf '%02x' "'$_rb_raw"
}

echo "=== UB450 region watch ===" > "$LOG"
log "Started: $(date)"

[ -f "$CONF" ] || { log "ERROR: $CONF not found"; exit 1; }

key=$(dd if="$CONF" bs=1 skip=$BD_KEY_OFF count=23 2>/dev/null)
if [ "$key" != "IDX_GB_PTT_BDREGIONCODE" ]; then
    log "ERROR: BD key mismatch at $BD_KEY_OFF: [$key]"
    exit 1
fi

log "Before: DVD=0x$(read_byte "$CONF" $DVD_VAL_OFF), BD=0x$(read_byte "$CONF" $BD_VAL_OFF)"

printf "\\x$BD_TARGET" | dd of="$CONF" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null
sync
log "Wrote: BD=0x$(read_byte "$CONF" $BD_VAL_OFF) at $(date)"

i=0
while [ $i -lt $MAX ]; do
    log "t=$((i * INTERVAL))s BD=0x$(read_byte "$CONF" $BD_VAL_OFF)"
    sync
    sleep $INTERVAL
    i=$((i + 1))
done
log "Finished: $(date)"
