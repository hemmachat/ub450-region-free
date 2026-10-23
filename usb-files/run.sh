#!/bin/sh
# DP-UB450/UB150 Region-Free Script v3
# Runs automatically when a Blu-ray disc is loaded with BDJ_DEBUG on the USB.
# Sets the player to region-free (all DVD and Blu-ray regions).
# Finds region settings dynamically — adapts to different firmware versions.

CONF=/acfg/config_file_global.txt
USB=/mnt/sda1
LOG=$USB/region_log.txt

log() { echo "$1" >> "$LOG"; }

echo "=== UB450 Region-Free v3 ===" > "$LOG"
log "Started: $(date)"

if [ ! -f "$CONF" ]; then
    log "ERROR: $CONF not found"
    echo "FAILED — config file not found" > "$USB/REGION_FREE_FAILED.txt"
    exit 1
fi

FILE_SIZE=$(wc -c < "$CONF" 2>/dev/null | tr -d ' ')
log "Config file size: $FILE_SIZE bytes"

# Copy config to USB so users can share it for debugging
cp "$CONF" "$USB/.config_dump.bin" 2>/dev/null

# --- Helpers ---

# Find the byte offset of a key string inside a binary config file.
# Method 1: strings -t d (works on busybox and GNU).
# Method 2: od hex search (works on GNU/macOS, not all busybox).
# Method 3: dd linear scan (slow but always works).
find_offset() {
    _fo_file="$1"; _fo_key="$2"; _fo_off=""

    # Method 1: strings -t d — each null-terminated string with its byte offset
    _fo_off=$(strings -a -t d "$_fo_file" 2>/dev/null | grep "${_fo_key}$" | head -1 | awk '{print $1}')
    if [ -n "$_fo_off" ] && expr "$_fo_off" + 0 >/dev/null 2>&1; then
        _fo_check=$(dd if="$_fo_file" bs=1 skip="$_fo_off" count=${#_fo_key} 2>/dev/null)
        if [ "$_fo_check" = "$_fo_key" ]; then
            echo "$_fo_off"; return
        fi
    fi

    # Method 2: od hex dump + shell pattern match
    _fo_fhex=$(od -v -An -tx1 < "$_fo_file" 2>/dev/null | tr -cd '0-9a-f')
    _fo_khex=$(printf '%s' "$_fo_key" | od -v -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ -n "$_fo_fhex" ] && [ -n "$_fo_khex" ]; then
        _fo_before="${_fo_fhex%%${_fo_khex}*}"
        if [ "$_fo_before" != "$_fo_fhex" ]; then
            echo $(( ${#_fo_before} / 2 )); return
        fi
    fi

    # Method 3: dd byte-by-byte scan (slow fallback)
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

# Read one byte at a given offset, return as two-char hex.
# Tries od first (macOS/GNU), falls back to hexdump (busybox), then printf.
read_byte() {
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_val=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ ${#_rb_val} -ge 2 ]; then echo "$_rb_val"; return; fi
    _rb_raw=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)
    printf '%02x' "'$_rb_raw"
}

# --- Find region key offsets ---

DVD_KEY_OFF=$(find_offset "$CONF" "IDX_GB_PTT_REGIONCODE")
BD_KEY_OFF=$(find_offset "$CONF" "IDX_GB_PTT_BDREGIONCODE")

log "DVD key (IDX_GB_PTT_REGIONCODE) at offset: ${DVD_KEY_OFF:-(not found)}"
log "BD key (IDX_GB_PTT_BDREGIONCODE) at offset: ${BD_KEY_OFF:-(not found)}"

if [ -z "$DVD_KEY_OFF" ]; then
    log "ERROR: IDX_GB_PTT_REGIONCODE not found in config file"
    log "Config copied to USB as .config_dump.bin — please share it in a GitHub issue"
    echo "FAILED — DVD region key not found" > "$USB/REGION_FREE_FAILED.txt"
    exit 1
fi

if [ -z "$BD_KEY_OFF" ]; then
    log "ERROR: IDX_GB_PTT_BDREGIONCODE not found in config file"
    log "Config copied to USB as .config_dump.bin — please share it in a GitHub issue"
    echo "FAILED — BD region key not found" > "$USB/REGION_FREE_FAILED.txt"
    exit 1
fi

# Value is 36 bytes after the key name start (fixed record size on MT8581).
DVD_VAL_OFF=$((DVD_KEY_OFF + 36))
BD_VAL_OFF=$((BD_KEY_OFF + 36))

log "DVD value offset: $DVD_VAL_OFF"
log "BD value offset: $BD_VAL_OFF"

if [ "$DVD_VAL_OFF" -ge "$FILE_SIZE" ] || [ "$BD_VAL_OFF" -ge "$FILE_SIZE" ]; then
    log "ERROR: value offset beyond file size ($FILE_SIZE)"
    log "Config copied to USB as .config_dump.bin — please share it in a GitHub issue"
    echo "FAILED — value offset out of range" > "$USB/REGION_FREE_FAILED.txt"
    exit 1
fi

# --- Read current values ---

DVD_HEX=$(read_byte "$CONF" $DVD_VAL_OFF)
BD_HEX=$(read_byte "$CONF" $BD_VAL_OFF)
log "Before: DVD=0x$DVD_HEX, BD=0x$BD_HEX"

# --- Restore mode (checked before backup so we don't overwrite the original) ---

if [ -f "$USB/RESTORE" ]; then
    log "RESTORE flag found — restoring original region"

    if [ -f "$USB/.dvd_offset.txt" ] && [ -f "$USB/.bd_offset.txt" ]; then
        RESTORE_DVD_OFF=$(cat "$USB/.dvd_offset.txt")
        RESTORE_BD_OFF=$(cat "$USB/.bd_offset.txt")
    else
        RESTORE_DVD_OFF=$DVD_VAL_OFF
        RESTORE_BD_OFF=$BD_VAL_OFF
    fi

    if [ -f "$USB/.dvd_backup.bin" ] && [ -f "$USB/.bd_backup.bin" ]; then
        dd if="$USB/.dvd_backup.bin" of="$CONF" bs=1 seek=$RESTORE_DVD_OFF conv=notrunc 2>/dev/null
        dd if="$USB/.bd_backup.bin" of="$CONF" bs=1 seek=$RESTORE_BD_OFF conv=notrunc 2>/dev/null
        sync
        DVD_R=$(read_byte "$CONF" $RESTORE_DVD_OFF)
        BD_R=$(read_byte "$CONF" $RESTORE_BD_OFF)
        log "Restored: DVD=0x$DVD_R, BD=0x$BD_R"
        echo "RESTORED OK" > "$USB/REGION_RESTORED.txt"
        rm -f "$USB/REGION_FREE_OK.txt" 2>/dev/null
    else
        log "ERROR: backup files not found on USB"
        echo "FAILED — no backup found" > "$USB/REGION_RESTORE_FAILED.txt"
    fi
    log "Finished: $(date)"
    log "Power off the player, remove the USB, and turn it back on."
    exit 0
fi

# --- Backup (skip if already region-free, so we don't overwrite the original) ---

if [ "$DVD_HEX" = "00" ] && [ "$BD_HEX" = "07" ] && [ -f "$USB/.dvd_backup.bin" ]; then
    log "Already region-free — keeping existing backup"
else
    dd if="$CONF" bs=1 skip=$DVD_VAL_OFF count=1 of="$USB/.dvd_backup.bin" 2>/dev/null
    dd if="$CONF" bs=1 skip=$BD_VAL_OFF count=1 of="$USB/.bd_backup.bin" 2>/dev/null
    cp "$CONF" "$USB/.config_backup.txt" 2>/dev/null
    echo "$DVD_VAL_OFF" > "$USB/.dvd_offset.txt"
    echo "$BD_VAL_OFF" > "$USB/.bd_offset.txt"
    log "Backup saved to USB"
fi

# --- Write region-free values: DVD=0 (region-free), BD=7 (A+B+C) ---

printf '\x00' | dd of="$CONF" bs=1 seek=$DVD_VAL_OFF conv=notrunc 2>/dev/null
printf '\x07' | dd of="$CONF" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null
sync

# --- Verify ---

DVD_AFTER=$(read_byte "$CONF" $DVD_VAL_OFF)
BD_AFTER=$(read_byte "$CONF" $BD_VAL_OFF)
log "After: DVD=0x$DVD_AFTER, BD=0x$BD_AFTER"

if [ "$DVD_AFTER" = "00" ] && [ "$BD_AFTER" = "07" ]; then
    log "SUCCESS — player is now region-free"
    echo "REGION FREE OK" > "$USB/REGION_FREE_OK.txt"
    rm -f "$USB/REGION_FREE_FAILED.txt" 2>/dev/null
else
    log "ERROR — values not written correctly"
    echo "FAILED" > "$USB/REGION_FREE_FAILED.txt"
fi

log "Finished: $(date)"
log "Power off the player, remove the USB, and turn it back on."
