#!/bin/sh
# DP-UB450/UB150 Region-Free Script v6
# Runs automatically when a Blu-ray disc is loaded with BDJ_DEBUG on the USB.
# Sets Blu-ray to all regions (A+B+C) and optionally DVD to a chosen region.
#
# Three methods, tried in order:
#   1. Web CLI (app.acfg.rg) — proper API, handles both DVD and BD
#   2. EEPROM direct write — writes DVD region to hardware (offset 0x200)
#   3. Config file write — always works for BD; DVD needs EEPROM too

CONF=/acfg/config_file_global.txt
USB=/mnt/sda1
LOG=$USB/region_log.txt

# DVD region: 0=free, 1=US, 2=Europe, 3=SE Asia, 4=Australia, 5=Russia/India, 6=China
# Set to empty to skip DVD region change. Default: 1 (US).
DVD_TARGET=1
# BD region: 7 = all regions (A+B+C)
BD_TARGET=7

# Allow override from USB file
if [ -f "$USB/dvd_region.txt" ]; then
    DVD_TARGET=$(cat "$USB/dvd_region.txt" | tr -cd '0-9' | head -c 1)
fi

log() { echo "$1" >> "$LOG"; }

echo "=== UB450 Region-Free v6 ===" > "$LOG"
log "Started: $(date)"
log "Target: DVD=$DVD_TARGET, BD=$BD_TARGET"

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
        # Restore EEPROM if we wrote to it
        if [ -f "$USB/.eeprom_dvd_backup.bin" ] && [ -f "$USB/.eeprom_device.txt" ]; then
            RESTORE_EEPROM=$(cat "$USB/.eeprom_device.txt")
            if [ -e "$RESTORE_EEPROM" ]; then
                dd if="$USB/.eeprom_dvd_backup.bin" of="$RESTORE_EEPROM" bs=1 seek=512 conv=notrunc 2>/dev/null
                log "EEPROM restored at $RESTORE_EEPROM offset 0x200"
            fi
        fi
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

# --- Backup (skip if nothing will change, so we don't overwrite the original) ---

BD_EXPECTED=$(printf '%02x' $BD_TARGET)
DVD_EXPECTED=$(printf '%02x' $DVD_TARGET)
if [ "$BD_HEX" = "$BD_EXPECTED" ] && [ "$DVD_HEX" = "$DVD_EXPECTED" ] && [ -f "$USB/.dvd_backup.bin" ]; then
    log "Nothing to change — keeping existing backup"
else
    if [ ! -f "$USB/.dvd_backup.bin" ]; then
        dd if="$CONF" bs=1 skip=$DVD_VAL_OFF count=1 of="$USB/.dvd_backup.bin" 2>/dev/null
        dd if="$CONF" bs=1 skip=$BD_VAL_OFF count=1 of="$USB/.bd_backup.bin" 2>/dev/null
        cp "$CONF" "$USB/.config_backup.txt" 2>/dev/null
        echo "$DVD_VAL_OFF" > "$USB/.dvd_offset.txt"
        echo "$BD_VAL_OFF" > "$USB/.bd_offset.txt"
        log "Backup saved to USB"
    else
        log "Backup already exists, not overwriting"
    fi
fi

# --- Method 1: Web CLI (proper API path, handles DVD + BD) ---

CLI_OK=0
if [ -x /usr/bin/curl ]; then
    resp=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:8383/" 2>/dev/null)
    log "Web CLI probe: HTTP $resp"
    if [ "$resp" = "200" ] || [ "$resp" = "301" ] || [ "$resp" = "302" ]; then
        # Read current values via CLI
        CLI_READ=$(curl -s --connect-timeout 3 "http://127.0.0.1:8383/config.cgi?page=get_log_and_set_cli_result.html&flag=cli_cmd&cli_value=app.acfg.rg" 2>/dev/null)
        log "CLI read: $(echo "$CLI_READ" | strings 2>/dev/null | grep 'region code')"

        # Set regions via CLI: app.acfg.rg <dvd> <bd> <ir>
        CLI_CMD="app.acfg.rg+${DVD_TARGET}+${BD_TARGET}+0"
        CLI_RESP=$(curl -s --connect-timeout 5 "http://127.0.0.1:8383/config.cgi?page=get_log_and_set_cli_result.html&flag=cli_cmd&cli_value=${CLI_CMD}" 2>/dev/null)
        log "CLI write ($CLI_CMD): $(echo "$CLI_RESP" | strings 2>/dev/null | grep -i 'region\|error\|ok' | head -3)"

        # Verify via CLI read
        CLI_VERIFY=$(curl -s --connect-timeout 3 "http://127.0.0.1:8383/config.cgi?page=get_log_and_set_cli_result.html&flag=cli_cmd&cli_value=app.acfg.rg" 2>/dev/null)
        VERIFY_LINE=$(echo "$CLI_VERIFY" | strings 2>/dev/null | grep 'region code')
        log "CLI verify: $VERIFY_LINE"

        # Check if DVD and BD values match target
        if echo "$VERIFY_LINE" | grep -q "DVD region code=$DVD_TARGET" && echo "$VERIFY_LINE" | grep -q "BD region code=$BD_TARGET"; then
            CLI_OK=1
            log "CLI method SUCCEEDED"
        else
            log "CLI method: values may not match target, falling back to config write"
        fi
    else
        log "Web CLI not reachable, using config file method"
    fi
else
    log "curl not available, using config file method"
fi

# --- Method 2: EEPROM direct write (DVD region hardware source) ---
# The firmware reads DVD region from EEPROM at offset 0x200 on every boot,
# overriding the config file. Writing to EEPROM makes DVD region survive reboot.
# The EEPROM device is opened via a "fast_init_param" lookup internally;
# we try known device files. BD region has no EEPROM copy — config file is enough.

EEPROM_OK=0
if [ "$CLI_OK" = "0" ] && [ -n "$DVD_TARGET" ]; then
    for EEPROM_DEV in /dev/eeprom_0 /dev/eeprom_3; do
        if [ ! -e "$EEPROM_DEV" ]; then continue; fi

        # Read 4 bytes at offset 0x200 — the firmware stores DVD region here
        EEPROM_VAL=$(dd if="$EEPROM_DEV" bs=1 skip=512 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
        EEPROM_BYTE="${EEPROM_VAL%"${EEPROM_VAL#??}"}"
        log "EEPROM $EEPROM_DEV offset 0x200: first byte=0x$EEPROM_BYTE (full: $EEPROM_VAL)"

        # Validate: the current value should be a valid DVD region (0-6)
        EEPROM_DEC=$(printf '%d' "0x${EEPROM_BYTE:-ff}" 2>/dev/null)
        if [ "$EEPROM_DEC" -le 6 ] 2>/dev/null; then
            log "EEPROM $EEPROM_DEV looks like the DVD region source (current=$EEPROM_DEC)"

            # Back up original EEPROM value
            if [ ! -f "$USB/.eeprom_dvd_backup.bin" ]; then
                dd if="$EEPROM_DEV" bs=1 skip=512 count=4 of="$USB/.eeprom_dvd_backup.bin" 2>/dev/null
                echo "$EEPROM_DEV" > "$USB/.eeprom_device.txt"
                log "EEPROM backup saved"
            fi

            # Write new DVD region as a 4-byte LE value (firmware reads 4 bytes, uses low byte)
            printf "\\x$(printf '%02x' $DVD_TARGET)\\x00\\x00\\x00" | \
                dd of="$EEPROM_DEV" bs=1 seek=512 conv=notrunc 2>/dev/null
            sync

            # Verify
            EEPROM_CHECK=$(dd if="$EEPROM_DEV" bs=1 skip=512 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
            if [ "$EEPROM_CHECK" = "$(printf '%02x' $DVD_TARGET)" ]; then
                EEPROM_OK=1
                log "EEPROM write SUCCEEDED: DVD=$DVD_TARGET at $EEPROM_DEV offset 0x200"
            else
                log "EEPROM write FAILED to verify (got 0x$EEPROM_CHECK)"
            fi
            break
        else
            log "EEPROM $EEPROM_DEV offset 0x200 value $EEPROM_DEC not a valid DVD region, skipping"
        fi
    done

    if [ "$EEPROM_OK" = "0" ]; then
        log "No EEPROM device found with valid DVD region at offset 0x200"
    fi
fi

# --- Method 3: Config file write (always works for BD; DVD needs EEPROM too) ---

# Write BD region (this always works for BD — no EEPROM involved)
printf "\\x$(printf '%02x' $BD_TARGET)" | dd of="$CONF" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null

# Write DVD region to config file too (supplements EEPROM write)
if [ -n "$DVD_TARGET" ]; then
    printf "\\x$(printf '%02x' $DVD_TARGET)" | dd of="$CONF" bs=1 seek=$DVD_VAL_OFF conv=notrunc 2>/dev/null
    log "Config write: DVD=$DVD_TARGET at offset $DVD_VAL_OFF"
fi
sync

# Also write to config_file.txt if it has the keys
if [ -f /acfg/config_file.txt ]; then
    DVD_KEY_OFF2=$(find_offset /acfg/config_file.txt "IDX_GB_PTT_REGIONCODE")
    BD_KEY_OFF2=$(find_offset /acfg/config_file.txt "IDX_GB_PTT_BDREGIONCODE")
    if [ -n "$DVD_KEY_OFF2" ]; then
        DVD_VAL_OFF2=$((DVD_KEY_OFF2 + 36))
        printf "\\x$(printf '%02x' $DVD_TARGET)" | dd of=/acfg/config_file.txt bs=1 seek=$DVD_VAL_OFF2 conv=notrunc 2>/dev/null
        log "Also wrote DVD=$DVD_TARGET to config_file.txt at offset $DVD_VAL_OFF2"
    fi
    if [ -n "$BD_KEY_OFF2" ]; then
        BD_VAL_OFF2=$((BD_KEY_OFF2 + 36))
        printf "\\x$(printf '%02x' $BD_TARGET)" | dd of=/acfg/config_file.txt bs=1 seek=$BD_VAL_OFF2 conv=notrunc 2>/dev/null
        log "Also wrote BD=$BD_TARGET to config_file.txt at offset $BD_VAL_OFF2"
    fi
    sync
fi

# --- Verify ---

BD_AFTER=$(read_byte "$CONF" $BD_VAL_OFF)
DVD_AFTER=$(read_byte "$CONF" $DVD_VAL_OFF)
log "After (config): DVD=0x$DVD_AFTER, BD=0x$BD_AFTER"

if [ "$BD_AFTER" = "$BD_EXPECTED" ]; then
    if [ "$CLI_OK" = "1" ]; then
        RESULT="DVD=$DVD_TARGET BD=$BD_TARGET set via web CLI."
    elif [ "$EEPROM_OK" = "1" ]; then
        RESULT="DVD=$DVD_TARGET set via EEPROM + config. BD=$BD_TARGET set via config."
    else
        RESULT="BD=$BD_TARGET set via config. DVD=$DVD_TARGET written to config only (may not survive reboot — run diag.sh to help debug)."
    fi
    log "SUCCESS — $RESULT"
    echo "$RESULT" > "$USB/REGION_FREE_OK.txt"
    rm -f "$USB/REGION_FREE_FAILED.txt" 2>/dev/null
else
    log "ERROR — values not written correctly"
    echo "FAILED" > "$USB/REGION_FREE_FAILED.txt"
fi

log ""
log "Finished: $(date)"
if [ "$CLI_OK" = "1" ]; then
    log "Regions set via CLI. Eject disc, insert the target-region disc."
elif [ "$EEPROM_OK" = "1" ]; then
    log "DVD region written to EEPROM (survives reboot). Power off, remove USB, turn back on."
else
    log "Power off the player, remove the USB, and turn it back on."
fi
