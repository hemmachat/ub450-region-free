#!/bin/sh
# AU validation script. Reads the BD region byte, or writes a chosen value to
# it. Mode comes from the first line of bd_region.txt on the USB:
#   read      -> log the current values only (no write)
#   0 .. 255  -> write that value to the BD byte (offset 237) only
# Each run keeps its own log and config copies. No DVD write, no EEPROM scan.
# Copy to the USB root as run.sh. The release tool stays as run.v5.7.sh.

CONF=${CONF:-/acfg/config_file_global.txt}
USB=${USB:-/mnt/sda1}
BD_KEY_OFF=201
BD_VAL_OFF=237
DVD_VAL_OFF=163

N=1
[ -f "$USB/.val_n" ] && N=$(( $(cat "$USB/.val_n" 2>/dev/null) + 1 ))
echo $N > "$USB/.val_n"
LOG=$USB/validation_log_$N.txt

log() { echo "$1" >> "$LOG"; }

read_byte() {
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_raw=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)
    printf '%02x' "'$_rb_raw"
}

echo "=== AU validation run $N ===" > "$LOG"
log "Started: $(date)"
log "Kernel: $(uname -a 2>/dev/null)"
log "conf: $(ls -l "$CONF" 2>/dev/null)"
log "acfg: $(ls -ld /acfg /var/local/acfg 2>/dev/null | tr '\n' ' ')"

[ -f "$CONF" ] || { log "ERROR: $CONF not found"; exit 1; }

key=$(dd if="$CONF" bs=1 skip=$BD_KEY_OFF count=23 2>/dev/null)
if [ "$key" != "IDX_GB_PTT_BDREGIONCODE" ]; then
    log "ERROR: BD key mismatch at $BD_KEY_OFF: [$key]"
    exit 1
fi

cp "$CONF" "$USB/config_run${N}_before.bin" 2>/dev/null
cp /acfg/config_file.txt "$USB/config_run${N}_config_file_before.txt" 2>/dev/null

# awk is already used by the release/diag scripts on this player; sed is not,
# and tr with \r escapes is unproven on its stripped busybox.
MODE=$(awk 'NR==1 {gsub(/\r/,""); print $1}' "$USB/bd_region.txt" 2>/dev/null)
log "Mode: ${MODE:-(missing)}"
log "Before: DVD=0x$(read_byte "$CONF" $DVD_VAL_OFF), BD=0x$(read_byte "$CONF" $BD_VAL_OFF)"

case "$MODE" in
    ''|read|READ)
        log "Read-only run — no write"
        ;;
    *[!0-9]*)
        log "ERROR: bd_region.txt first line must be a number 0-255 or 'read'"
        exit 1
        ;;
    *)
        VAL=$(awk -v m="$MODE" 'BEGIN { sub(/^0+/, "", m); if (m == "") m = 0; print m }')
        if [ "$VAL" -gt 255 ]; then
            log "ERROR: value $VAL out of range"
            exit 1
        fi
        printf "\\x$(printf '%02x' "$VAL")" | dd of="$CONF" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null
        RC=$?
        sync
        log "Write: BD=0x$(printf '%02x' "$VAL") rc=$RC, read back BD=0x$(read_byte "$CONF" $BD_VAL_OFF)"
        ;;
esac

log "After: DVD=0x$(read_byte "$CONF" $DVD_VAL_OFF), BD=0x$(read_byte "$CONF" $BD_VAL_OFF)"
cp "$CONF" "$USB/config_run${N}_after.bin" 2>/dev/null
cp /acfg/config_file.txt "$USB/config_run${N}_config_file_after.txt" 2>/dev/null
log "--- paths ---"
ls -ld /var/local /mnt/ubi_boot/var/local /mnt/ubi_boot/var/local/acfg >> "$LOG" 2>&1
log "--- /proc/mounts ---"
cat /proc/mounts >> "$LOG" 2>&1
log "--- /acfg/ ---"
ls -la /acfg/ >> "$LOG" 2>&1
log "--- /var/local/acfg/ ---"
ls -la /var/local/acfg/ >> "$LOG" 2>&1
log "Finished: $(date)"
