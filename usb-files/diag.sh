#!/bin/sh
# DVD Region Diagnostic — collects data to fix the DVD region change.
# Runs on the player via the same BD-Java debug mode as run.sh.
# Saves everything to USB under diag_output/.

USB=/mnt/sda1
OUT=$USB/diag_output
LOG=$OUT/diag_log.txt

mkdir -p "$OUT"
echo "=== DVD Region Diagnostic ===" > "$LOG"
echo "Started: $(date)" >> "$LOG"

log() { echo "$1" >> "$LOG"; }

# 0. System info
log ""
log "--- System info ---"
log "Kernel: $(uname -a 2>/dev/null)"
log "CPU: $(grep -m1 'model name\|Processor\|Hardware' /proc/cpuinfo 2>/dev/null | head -1)"
log "Board: $(cat /proc/device-tree/model 2>/dev/null || grep -m1 'Hardware' /proc/cpuinfo 2>/dev/null)"
cat /etc/version >> "$LOG" 2>/dev/null
cat /etc/firmware_version >> "$LOG" 2>/dev/null
ls -la /dev/eeprom* /dev/mtd[0-9]* >> "$LOG" 2>&1

# Model name and country from config
MODEL_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_MODEL_NAME$' | head -1 | awk '{print $1}')
if [ -n "$MODEL_OFF" ]; then
    MODEL_VOFF=$((MODEL_OFF + 36))
    MODEL_VAL=$(dd if=/acfg/config_file_global.txt bs=1 skip=$MODEL_VOFF count=32 2>/dev/null | strings | head -1)
    log "Model: $MODEL_VAL"
fi
COUNTRY_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_COUNTRYCODE$' | head -1 | awk '{print $1}')
if [ -n "$COUNTRY_OFF" ]; then
    COUNTRY_VOFF=$((COUNTRY_OFF + 36))
    COUNTRY_VAL=$(dd if=/acfg/config_file_global.txt bs=1 skip=$COUNTRY_VOFF count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f ')
    log "Country code: $COUNTRY_VAL"
fi

# Current region values from config file
log ""
log "--- Current regions (config file) ---"
DVD_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_REGIONCODE$' | head -1 | awk '{print $1}')
if [ -n "$DVD_OFF" ]; then
    DVD_VOFF=$((DVD_OFF + 36))
    DVD_VAL=$(dd if=/acfg/config_file_global.txt bs=1 skip=$DVD_VOFF count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    DVD_DEC=$(printf '%d' "0x${DVD_VAL:-ff}" 2>/dev/null)
    log "DVD region: $DVD_DEC (0x$DVD_VAL)  [0=free 1=US 2=Europe 3=SE-Asia 4=AU 5=Russia 6=China]"
fi
BD_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_BDREGIONCODE$' | head -1 | awk '{print $1}')
if [ -n "$BD_OFF" ]; then
    BD_VOFF=$((BD_OFF + 36))
    BD_VAL=$(dd if=/acfg/config_file_global.txt bs=1 skip=$BD_VOFF count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    BD_DEC=$(printf '%d' "0x${BD_VAL:-ff}" 2>/dev/null)
    log "BD region:  $BD_DEC (0x$BD_VAL)  [1=A 2=B 4=C 7=all]"
fi
IR_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_IR_REGIONCODE$' | head -1 | awk '{print $1}')
if [ -n "$IR_OFF" ]; then
    IR_VOFF=$((IR_OFF + 36))
    IR_VAL=$(dd if=/acfg/config_file_global.txt bs=1 skip=$IR_VOFF count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    IR_DEC=$(printf '%d' "0x${IR_VAL:-ff}" 2>/dev/null)
    log "IR region:  $IR_DEC (0x$IR_VAL)"
fi

# Current live region from the player (via CLI — these are the values the player is actually using)
log ""
log "--- Current regions (player live) ---"
LIVE_REGION=""
# Try cliprog first (direct IPC to bdpprog)
if [ -x /usr/local/bin/cliprog ]; then
    LIVE_REGION=$(cliprog app.acfg.rg 2>/dev/null)
    [ -n "$LIVE_REGION" ] && log "cliprog app.acfg.rg: $LIVE_REGION"
fi
# Try Web CLI if cliprog didn't work
if [ -z "$LIVE_REGION" ] && [ -x /usr/bin/curl ]; then
    CLI_RESP=$(curl -s --connect-timeout 2 "http://127.0.0.1:8383/config.cgi?page=get_log_and_set_cli_result.html&flag=cli_cmd&cli_value=app.acfg.rg" 2>/dev/null)
    LIVE_REGION=$(echo "$CLI_RESP" | strings 2>/dev/null | grep "region code")
    [ -n "$LIVE_REGION" ] && log "Web CLI app.acfg.rg: $LIVE_REGION"
fi
if [ -z "$LIVE_REGION" ]; then
    log "Could not read live region (CLI not reachable) — config file values shown above"
fi

# 1. All config files under /acfg/
log ""
log "--- /acfg/ files ---"
ls -la /acfg/ >> "$LOG" 2>&1
for f in /acfg/config_file*.txt; do
    if [ -f "$f" ]; then
        base=$(basename "$f")
        cp "$f" "$OUT/$base" 2>/dev/null
        log "Copied $f ($(wc -c < "$f" | tr -d ' ') bytes)"
        # Check if this file has the DVD region key
        if strings "$f" 2>/dev/null | grep -q "IDX_GB_PTT_REGIONCODE"; then
            log "  -> HAS IDX_GB_PTT_REGIONCODE"
        else
            log "  -> no IDX_GB_PTT_REGIONCODE"
        fi
        if strings "$f" 2>/dev/null | grep -q "IDX_GB_PTT_BDREGIONCODE"; then
            log "  -> HAS IDX_GB_PTT_BDREGIONCODE"
        fi
    fi
done

# 2. MTD partition table
log ""
log "--- /proc/mtd ---"
cat /proc/mtd >> "$LOG" 2>&1

# 3. EEPROM / MTD devices
log ""
log "--- EEPROM and MTD devices ---"
ls -la /dev/eeprom* >> "$LOG" 2>&1
ls -la /dev/mtd[0-9]* >> "$LOG" 2>&1

# Dump small EEPROM devices (< 64KB) to USB
for dev in /dev/eeprom_0 /dev/eeprom_3; do
    if [ -e "$dev" ]; then
        base=$(basename "$dev")
        timeout 5 dd if="$dev" of="$OUT/$base.bin" bs=4096 count=16 2>/dev/null
        sz=$(wc -c < "$OUT/$base.bin" | tr -d ' ')
        log "Dumped $dev: $sz bytes"
        # Search for region key in EEPROM
        if strings "$OUT/$base.bin" 2>/dev/null | grep -q "IDX_GB_PTT_REGIONCODE"; then
            log "  -> HAS IDX_GB_PTT_REGIONCODE in EEPROM!"
        fi
    else
        log "$dev does not exist"
    fi
done

# Dump first 64KB of small MTD devices
for i in 0 1 2 3 4 5; do
    dev="/dev/mtd$i"
    if [ -e "$dev" ]; then
        timeout 5 dd if="$dev" of="$OUT/mtd${i}.bin" bs=4096 count=16 2>/dev/null
        sz=$(wc -c < "$OUT/mtd${i}.bin" | tr -d ' ')
        log "Dumped $dev: $sz bytes"
        if strings "$OUT/mtd${i}.bin" 2>/dev/null | grep -q "IDX_GB_PTT"; then
            log "  -> HAS IDX_GB_PTT key in MTD$i!"
        fi
    fi
done

# 4. Web CLI reachability from localhost
log ""
log "--- Web CLI (port 8383) ---"
# Test if the web server is running and reachable from localhost
if [ -x /usr/bin/curl ]; then
    resp=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://127.0.0.1:8383/" 2>/dev/null)
    log "curl http://127.0.0.1:8383/ => HTTP $resp"
    if [ "$resp" = "200" ] || [ "$resp" = "301" ] || [ "$resp" = "302" ]; then
        log "Web CLI IS reachable from localhost!"
        # Read current region via CLI
        curl -s --connect-timeout 2 "http://127.0.0.1:8383/config.cgi?page=get_log_and_set_cli_result.html&flag=cli_cmd&cli_value=app.acfg.rg" > "$OUT/cli_region_read.html" 2>/dev/null
        log "Sent app.acfg.rg READ query, response saved to cli_region_read.html"
        # Extract the region values from the HTML response
        REGION_LINE=$(strings "$OUT/cli_region_read.html" 2>/dev/null | grep "region code")
        log "Region response: $REGION_LINE"
        # Also test other CLI commands
        curl -s --connect-timeout 2 "http://127.0.0.1:8383/config.cgi?page=get_log_and_set_cli_result.html&flag=cli_cmd&cli_value=drv.hdmi.status" > "$OUT/cli_hdmi_status.html" 2>/dev/null
        log "Sent drv.hdmi.status, response saved to cli_hdmi_status.html"
    else
        log "Web CLI NOT reachable (HTTP $resp or timeout)"
        # Try other ports too
        for port in 80 8080 8888; do
            resp2=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 1 "http://127.0.0.1:$port/" 2>/dev/null)
            if [ "$resp2" != "000" ]; then
                log "Port $port responds: HTTP $resp2"
            fi
        done
    fi
else
    log "curl not found"
fi

# 5. Network ports (what's listening)
log ""
log "--- Listening ports ---"
netstat -tlnp >> "$LOG" 2>&1 || ss -tlnp >> "$LOG" 2>&1

# 6. ODD (optical disc drive) info
log ""
log "--- ODD device ---"
ls -la /dev/sr* /dev/cdrom* >> "$LOG" 2>&1
if [ -e /dev/sr0 ]; then
    log "ODD exists at /dev/sr0"
    # Check if sg_raw or similar tools exist
    which sg_raw >> "$LOG" 2>&1 && log "sg_raw available" || log "no sg_raw"
    which sdparm >> "$LOG" 2>&1 && log "sdparm available" || log "no sdparm"
    which hdparm >> "$LOG" 2>&1 && log "hdparm available" || log "no hdparm"
fi

# 7. Process info
log ""
log "--- bdpprog process ---"
ps | grep bdpprog >> "$LOG" 2>&1
# Check bdpprog's open file descriptors for CLI socket/pipe
BDPID=$(ps | grep bdpprog | grep -v grep | head -1 | awk '{print $1}')
if [ -n "$BDPID" ]; then
    log "bdpprog PID: $BDPID"
    ls -la /proc/$BDPID/fd/ >> "$LOG" 2>&1
fi

# 8. ACFG settings dump via settings command (if available)
log ""
log "--- settings list (region-related) ---"
if [ -x /system/bin/settings ] || [ -x /usr/bin/settings ]; then
    settings list system 2>/dev/null | grep -i region >> "$LOG" 2>&1
    settings list system 2>/dev/null | grep -i acfg >> "$LOG" 2>&1
fi

# 9. Search all of /acfg/ for any file containing the DVD region key
log ""
log "--- Search /acfg/ for IDX_GB_PTT_REGIONCODE ---"
for f in /acfg/*; do
    if [ -f "$f" ] && strings "$f" 2>/dev/null | grep -q "IDX_GB_PTT_REGIONCODE"; then
        log "Found in: $f"
    fi
done

# 10. Strace: trace what bdpprog reads at the ACFG region path
# This traces bdpprog for 5 seconds to catch any EEPROM/config file access
log ""
log "--- strace bdpprog (5s, file ops) ---"
if [ -n "$BDPID" ] && [ -x /bin/strace ]; then
    timeout 5 strace -p "$BDPID" -f -e trace=open,openat,read,write,ioctl -o "$OUT/strace_bdpprog.txt" 2>/dev/null &
    STPID=$!
    sleep 5
    kill $STPID 2>/dev/null
    wait $STPID 2>/dev/null
    sz=$(wc -c < "$OUT/strace_bdpprog.txt" 2>/dev/null | tr -d ' ')
    log "Strace captured: $sz bytes"
else
    log "Strace skipped (no bdpprog PID or no strace)"
fi

# 11. Read current DVD region byte from config_file.txt (non-global) if it has the key
log ""
log "--- config_file.txt region values ---"
if [ -f /acfg/config_file.txt ]; then
    OFF=$(strings -a -t d /acfg/config_file.txt 2>/dev/null | grep 'IDX_GB_PTT_REGIONCODE$' | head -1 | awk '{print $1}')
    if [ -n "$OFF" ]; then
        VAL_OFF=$((OFF + 36))
        VAL=$(dd if=/acfg/config_file.txt bs=1 skip=$VAL_OFF count=1 2>/dev/null | od -An -tx1 | tr -cd '0-9a-f')
        log "config_file.txt: IDX_GB_PTT_REGIONCODE at $OFF, value offset $VAL_OFF = 0x$VAL"
    else
        log "config_file.txt: IDX_GB_PTT_REGIONCODE not found"
    fi
    OFF=$(strings -a -t d /acfg/config_file.txt 2>/dev/null | grep 'IDX_GB_PTT_BDREGIONCODE$' | head -1 | awk '{print $1}')
    if [ -n "$OFF" ]; then
        VAL_OFF=$((OFF + 36))
        VAL=$(dd if=/acfg/config_file.txt bs=1 skip=$VAL_OFF count=1 2>/dev/null | od -An -tx1 | tr -cd '0-9a-f')
        log "config_file.txt: IDX_GB_PTT_BDREGIONCODE at $OFF, value offset $VAL_OFF = 0x$VAL"
    else
        log "config_file.txt: IDX_GB_PTT_BDREGIONCODE not found"
    fi
fi

# 12. Check offset 0x200 across all EEPROM/MTD devices (firmware reads DVD from here)
log ""
log "--- Offset 0x200 scan (DVD region hardware source) ---"
log "The firmware reads DVD region from EEPROM device 0x15 at offset 0x200 on every boot."
log "This value overrides the config file. BD has no EEPROM copy."
log "Scanning /dev/eeprom* and small /dev/mtd* partitions..."

# Get config file DVD region for cross-reference
DIAG_DVD_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_REGIONCODE$' | head -1 | awk '{print $1}')
if [ -n "$DIAG_DVD_OFF" ]; then
    DIAG_DVD_VOFF=$((DIAG_DVD_OFF + 36))
    DIAG_CFG_DVD=$(dd if=/acfg/config_file_global.txt bs=1 skip=$DIAG_DVD_VOFF count=1 2>/dev/null | od -An -tx1 | tr -cd '0-9a-f')
    DIAG_CFG_DEC=$(printf '%d' "0x${DIAG_CFG_DVD:-ff}" 2>/dev/null)
    log "Config file DVD region: $DIAG_CFG_DEC (0x$DIAG_CFG_DVD) — EEPROM match expected"
fi

DIAG_DEVS=""
for p in /dev/eeprom*; do [ -e "$p" ] && DIAG_DEVS="$DIAG_DEVS $p"; done
for p in /dev/mtd[0-9]*; do
    case "$p" in *block*) continue;; esac
    [ -e "$p" ] && DIAG_DEVS="$DIAG_DEVS $p"
done

for dev in $DIAG_DEVS; do
    EEPVAL=$(timeout 3 dd if="$dev" bs=1 skip=512 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f ')
    EEPBYTE=$(echo "$EEPVAL" | head -c 2)
    EEPDEC=$(printf '%d' "0x${EEPBYTE:-ff}" 2>/dev/null)
    if [ "$EEPDEC" -le 6 ] 2>/dev/null; then
        log "$dev offset 0x200: $EEPVAL (first byte=0x$EEPBYTE = $EEPDEC)"
        if [ -n "$DIAG_CFG_DEC" ] && [ "$EEPDEC" = "$DIAG_CFG_DEC" ]; then
            log "  -> MATCH — valid DVD region ($EEPDEC) matching config — THIS IS THE DVD EEPROM"
        else
            log "  -> VALID DVD region ($EEPDEC) but doesn't match config ($DIAG_CFG_DEC)"
        fi
        # Also check IR region at 0x205
        IRVAL=$(timeout 3 dd if="$dev" bs=1 skip=517 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f ')
        log "  offset 0x205 (IR region): $IRVAL"
        # Dump wider area
        timeout 3 dd if="$dev" bs=1 skip=496 count=32 2>/dev/null | od -An -tx1 > "$OUT/$(basename $dev)_0x1f0.hex" 2>/dev/null
        log "  (bytes 0x1F0-0x20F saved)"
    fi
done

# Compare EEPROM DVD region with config file DVD region
log ""
log "--- DVD region: EEPROM vs config file ---"
if [ -n "$DVD_KEY_OFF" ]; then
    :
else
    DVD_KEY_OFF=$(strings -a -t d /acfg/config_file_global.txt 2>/dev/null | grep 'IDX_GB_PTT_REGIONCODE$' | head -1 | awk '{print $1}')
fi
if [ -n "$DVD_KEY_OFF" ]; then
    CFG_DVD_OFF=$((DVD_KEY_OFF + 36))
    CFG_DVD=$(dd if=/acfg/config_file_global.txt bs=1 skip=$CFG_DVD_OFF count=1 2>/dev/null | od -An -tx1 | tr -cd '0-9a-f')
    log "Config file DVD region: 0x$CFG_DVD (at offset $CFG_DVD_OFF)"
    log "If EEPROM and config differ, EEPROM wins at boot."
fi

# 13. Dump /dev/sg* devices (SCSI generic)
log ""
log "--- SCSI generic devices ---"
ls -la /dev/sg* >> "$LOG" 2>&1

# 14. Kernel modules (check for SCSI/ODD drivers)
log ""
log "--- Loaded kernel modules (scsi/odd) ---"
lsmod 2>/dev/null | grep -iE '(scsi|sr_|cdrom|sg)' >> "$LOG" 2>&1
cat /proc/modules 2>/dev/null | grep -iE '(scsi|sr_|cdrom|sg)' >> "$LOG" 2>&1

log ""
log "Finished: $(date)"
log "Copy diag_output/ from USB and share it."
echo "DIAGNOSTIC DONE — check diag_output/ on USB" > "$USB/DIAG_DONE.txt"
