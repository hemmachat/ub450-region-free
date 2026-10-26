#!/bin/sh
# One-off persistence test for the UB450 config file. Not a release script.
# Copy to the USB root as run.sh. The BDJ_DEBUG/BDJ.jar trigger runs it.
#
# Phase A (clean shutdown): run, change one player setting, power off with the
# remote, boot, run again. Compare BEFORE with the previous TEST.
# Phase B (hard cut): create a file named HARDCUT on the USB, run once (the
# script writes PROBE_DONE and kills bdpprog), unplug, remove HARDCUT and
# PROBE_DONE, boot, run again.
# Phase A uses the remote deliberately (it tests the clean-shutdown path); the
# release flow tells users to unplug instead.
#
# It writes only the BD region byte. Restore afterwards with the release run.sh
# (current default BD=1; pick 1/2/4 with bd_region.txt).

CONF=${CONF:-/acfg/config_file_global.txt}
USB=${USB:-/mnt/sda1}
LOG=$USB/region_log.txt
BD_KEY_OFF=201
BD_VAL_OFF=237
BD_KEY=IDX_GB_PTT_BDREGIONCODE

log() { echo "$1" >> "$LOG"; }

# After the kill the player can restart with the disc still in and re-trigger
# this script. Exit before touching the log, so run 1's log and value survive.
[ -f "$USB/PROBE_DONE" ] && exit 0

echo "=== UB450 persistence test ===" > "$LOG"
log "Started: $(date)"
log "uid=$(id -u 2>/dev/null) yama=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)"
log "conf: $(ls -l "$CONF" 2>/dev/null)"
log "conf inode: $(ls -li "$CONF" 2>/dev/null)"
log "conf owner: $(ls -ln "$CONF" 2>/dev/null)"
log "tools: chmod=$(command -v chmod 2>/dev/null) reboot=$(command -v reboot 2>/dev/null)"
log "dev: $(ls -l /dev/mem /dev/kmem /dev/drvcli 2>&1)"
log "mounts: $(grep -E 'sda1|/acfg|ubi_boot' /proc/mounts 2>/dev/null | tr '\n' ' ')"
log "acfg: $(ls -l /acfg 2>/dev/null | head -6)"

[ -f "$CONF" ] || { log "ERROR: $CONF not found"; exit 1; }

key=$(dd if="$CONF" bs=1 skip=$BD_KEY_OFF count=23 2>/dev/null)
if [ "$key" != "$BD_KEY" ]; then
    log "ERROR: key mismatch at $BD_KEY_OFF: [$key]"
    exit 1
fi

read_byte() {
    _v=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
    if [ ${#_v} -ge 2 ]; then echo "${_v%${_v#??}}"; return; fi
    _v=$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
    if [ ${#_v} -ge 2 ]; then echo "${_v%${_v#??}}"; return; fi
    printf '%02x' "'$(dd if="$1" bs=1 skip="$2" count=1 2>/dev/null)"
}

# Keep a per-run copy of the config
N=1
[ -f "$USB/.ptest_n" ] && N=$(( $(cat "$USB/.ptest_n" 2>/dev/null) + 1 ))
echo $N > "$USB/.ptest_n"
cp "$CONF" "$USB/persistence_run$N.bin" 2>/dev/null

CUR=$(read_byte "$CONF" $BD_VAL_OFF)
# Pick a value that differs from the current one, so a rewrite is visible.
case "$CUR" in
    01) TEST=02 ;;
    *)  TEST=01 ;;
esac

log "BEFORE=$CUR TEST=$TEST run=$N"

printf "\\x$TEST" | dd of="$CONF" bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null
RC=$?
sync
AFTER=$(read_byte "$CONF" $BD_VAL_OFF)
if [ "$AFTER" = "$TEST" ]; then
    log "WRITE VERIFIED: AFTER=$AFTER rc=$RC"
else
    log "WRITE MISMATCH: AFTER=$AFTER wanted=$TEST rc=$RC"
fi
log "conf after write: $(ls -li "$CONF" 2>/dev/null)"

# --- read-only probe of the live config image ---
PID=""
for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = "bdpprog" ] || continue
    PID=${p#/proc/}; break
done
log "bdpprog pid=${PID:-none}"
if [ -n "$PID" ]; then
    log "status: $(grep '^Uid:' /proc/$PID/status 2>/dev/null)"
    log "proc entries: $(ls /proc/$PID 2>/dev/null | tr '\n' ' ')"
    log "proc state: $(grep -E '^(State|TracerPid|NoNewPrivs)' /proc/$PID/status 2>/dev/null | tr '\n' ' ')"
    log "instances: $(for p in /proc/[0-9]*/comm; do [ "$(cat "$p" 2>/dev/null)" = bdpprog ] && printf '%s ' "$p"; done)"
    # V127: ctx 0x011a5ea0, file buffer ptr 0x011a5eb4, image ptr 0x011a5ebc
    # V113: ctx 0x011c6008, file buffer ptr 0x011c601c, image ptr 0x011c6024
    for pair in "18505396 18505404" "18636828 18636836"; do
        set -- $pair; P14=$1; P1C=$2
        log "probe ctx pair $P14 $P1C"
        h=$(dd if=/proc/$PID/mem bs=1 skip=$((P1C)) count=4 2>>"$LOG" | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
        [ -n "$h" ] || h=$(dd if=/proc/$PID/mem bs=1 skip=$((P1C)) count=4 2>>"$LOG" | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
        if [ -z "$h" ]; then log "  mem read failed at $P1C"; continue; fi
        b0=$(echo "$h" | cut -c1-2); b1=$(echo "$h" | cut -c3-4)
        b2=$(echo "$h" | cut -c5-6); b3=$(echo "$h" | cut -c7-8)
        ptr=$((0x$b0 + (0x$b1 << 8) + (0x$b2 << 16) + (0x$b3 << 24)))
        k=$(dd if=/proc/$PID/mem bs=1 skip=$((ptr + BD_KEY_OFF)) count=23 2>/dev/null)
        if [ "$k" = "$BD_KEY" ]; then
            img=$(dd if=/proc/$PID/mem bs=1 skip=$((ptr + BD_VAL_OFF)) count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -cd '0-9a-f')
            [ -n "$img" ] || img=$(dd if=/proc/$PID/mem bs=1 skip=$((ptr + BD_VAL_OFF)) count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)
            log "  IMAGE VALID base=$ptr image_bd=$img file_bd=$AFTER"
        else
            log "  ptr=$ptr key mismatch [$k]"
        fi
    done
    # /proc/<pid>/mem is missing on this kernel, but /dev/mem is 0600 owned by
    # system (our uid) and pagemap exists. Try the same pointers physically.
    pgh() { # $1 virtual address -> pagemap entry, 8 bytes as hex
        _off=$(( ($1 / 4096) * 8 ))
        _h=$(dd if=/proc/$PID/pagemap bs=8 skip=$(( _off / 8 )) count=1 2>>"$LOG" \
             | hexdump -v -e '1/1 "%02x"')
        if [ -z "$_h" ]; then
            # procfs may refuse the seek: read up to the entry and cut it out
            _h=$(dd if=/proc/$PID/pagemap bs=4096 count=$(( _off / 4096 + 1 )) 2>>"$LOG" \
                 | tail -c +$(( _off + 1 )) | head -c 8 \
                 | hexdump -v -e '1/1 "%02x"')
        fi
        printf '%s' "$_h"
    }
    log "  pagemap entry 0: [$(dd if=/proc/$PID/pagemap bs=8 count=1 2>>"$LOG" | hexdump -v -e '1/1 "%02x"')]"
    for slot in 18505404 18636836; do
        h=$(pgh "$slot")
        [ ${#h} -eq 16 ] || { log "  pagemap $slot unreadable [$h]"; continue; }
        # Bytes are little-endian: present is bit 7 of the last byte; the PFN
        # is in the low 4 bytes (RAM is under 4 GB, the rest are zero).
        case "${h:14:2}" in
            8*|9*|[a-fA-F]*) ;;
            *) log "  pagemap $slot not present"; continue;;
        esac
        pfn=$(( 0x${h:6:2} << 24 | 0x${h:4:2} << 16 | 0x${h:2:2} << 8 | 0x${h:0:2} ))
        phys=$(( pfn * 4096 + slot % 4096 ))
        log "  pagemap $slot -> pfn $pfn phys $phys"
        m=$(dd if=/dev/mem bs=1 skip=$phys count=4 2>>"$LOG" | hexdump -v -e '1/1 "%02x"')
        log "  /dev/mem ptr: [${m:-fail}]"
        [ ${#m} -eq 8 ] || continue
        ptr=$((0x${m:6:2}${m:4:2}${m:2:2}${m:0:2}))
        ia=$((ptr + BD_KEY_OFF))
        h2=$(pgh "$ia")
        [ ${#h2} -eq 16 ] || { log "  pagemap image ptr unreadable"; continue; }
        case "${h2:14:2}" in
            8*|9*|[a-fA-F]*) ;;
            *) log "  pagemap image ptr not present"; continue;;
        esac
        pfn2=$(( 0x${h2:6:2} << 24 | 0x${h2:4:2} << 16 | 0x${h2:2:2} << 8 | 0x${h2:0:2} ))
        phys2=$(( pfn2 * 4096 + ia % 4096 ))
        k=$(dd if=/dev/mem bs=1 skip=$phys2 count=23 2>/dev/null)
        log "  image ptr=0x$(printf '%x' $ptr) key phys $phys2: [${k}]"
    done
fi

sync
# Copy the log before the kill: killing bdpprog can take this shell with it.
cp "$LOG" "$USB/persistence_log_run$N.txt" 2>/dev/null
if [ -f "$USB/HARDCUT" ]; then
    : > "$USB/PROBE_DONE"
    sync
    log "HARDCUT requested: killing bdpprog ${PID:-none}"
    [ -n "$PID" ] && kill -9 "$PID" 2>>"$LOG"
    log "kill rc=$?"
fi
log "DONE run=$N"
cp "$LOG" "$USB/persistence_log_run$N.txt" 2>/dev/null
exit 0
