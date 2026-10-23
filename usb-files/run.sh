#!/bin/sh
# DP-UB450/UB150/UB820 Region-Free Script
# Runs automatically when a Blu-ray disc is loaded with BDJ_DEBUG on the USB.
# Sets the player to region-free (all DVD and Blu-ray regions).
# Finds region settings dynamically — adapts to different firmware versions.

CONF=/acfg/config_file_global.txt
USB=/mnt/sda1
LOG=$USB/region_log.txt

echo "=== UB450 Region-Free ===" > $LOG
echo "Started: $(date)" >> $LOG

# Check config file exists
if [ ! -f "$CONF" ]; then
    echo "ERROR: $CONF not found" >> $LOG
    echo "FAILED — config file not found" > $USB/REGION_FREE_FAILED.txt
    exit 1
fi

FILE_SIZE=$(wc -c < $CONF 2>/dev/null | tr -d ' ')
echo "Config file size: $FILE_SIZE bytes" >> $LOG

# Find key offsets dynamically by searching for the key names
# grep -boa prints the byte offset of each match
DVD_KEY_OFF=$(grep -boa "IDX_GB_PTT_REGIONCODE" $CONF 2>/dev/null | head -1 | cut -d: -f1)
BD_KEY_OFF=$(grep -boa "IDX_GB_PTT_BDREGIONCODE" $CONF 2>/dev/null | head -1 | cut -d: -f1)

echo "DVD key (IDX_GB_PTT_REGIONCODE) at offset: $DVD_KEY_OFF" >> $LOG
echo "BD key (IDX_GB_PTT_BDREGIONCODE) at offset: $BD_KEY_OFF" >> $LOG

if [ -z "$DVD_KEY_OFF" ]; then
    echo "ERROR: IDX_GB_PTT_REGIONCODE not found in config file" >> $LOG
    echo "FAILED — DVD region key not found" > $USB/REGION_FREE_FAILED.txt
    exit 1
fi

if [ -z "$BD_KEY_OFF" ]; then
    echo "ERROR: IDX_GB_PTT_BDREGIONCODE not found in config file" >> $LOG
    echo "FAILED — BD region key not found" > $USB/REGION_FREE_FAILED.txt
    exit 1
fi

# The value is 36 bytes after the key name start.
# Verify this by checking the known key length + padding:
#   IDX_GB_PTT_REGIONCODE   = 21 chars + 15 bytes padding/metadata = 36
#   IDX_GB_PTT_BDREGIONCODE = 23 chars + 13 bytes padding/metadata = 36
DVD_VAL_OFF=$((DVD_KEY_OFF + 36))
BD_VAL_OFF=$((BD_KEY_OFF + 36))

echo "DVD value at offset: $DVD_VAL_OFF" >> $LOG
echo "BD value at offset: $BD_VAL_OFF" >> $LOG

# Sanity check: the BD key should appear after the DVD key,
# and the value offsets should be within the file
if [ "$BD_KEY_OFF" -le "$DVD_KEY_OFF" ]; then
    echo "ERROR: unexpected key order (BD before DVD)" >> $LOG
    echo "FAILED — unexpected config layout" > $USB/REGION_FREE_FAILED.txt
    exit 1
fi

if [ "$BD_VAL_OFF" -ge "$FILE_SIZE" ]; then
    echo "ERROR: BD value offset ($BD_VAL_OFF) beyond file size ($FILE_SIZE)" >> $LOG
    echo "FAILED — value offset out of range" > $USB/REGION_FREE_FAILED.txt
    exit 1
fi

# Back up current region values and full config to USB
dd if=$CONF bs=1 skip=$DVD_VAL_OFF count=1 of=$USB/.dvd_backup.bin 2>/dev/null
dd if=$CONF bs=1 skip=$BD_VAL_OFF count=1 of=$USB/.bd_backup.bin 2>/dev/null
cp $CONF $USB/.config_backup.txt 2>/dev/null
echo "$DVD_VAL_OFF" > $USB/.dvd_offset.txt
echo "$BD_VAL_OFF" > $USB/.bd_offset.txt
echo "Backup saved to USB" >> $LOG

# Read current values
DVD_HEX=$(dd if=$CONF bs=1 skip=$DVD_VAL_OFF count=1 2>/dev/null | hexdump -C | head -1 | sed 's/.*  \(..\).*/\1/')
BD_HEX=$(dd if=$CONF bs=1 skip=$BD_VAL_OFF count=1 2>/dev/null | hexdump -C | head -1 | sed 's/.*  \(..\).*/\1/')
echo "Before: DVD=0x$DVD_HEX, BD=0x$BD_HEX" >> $LOG

# Check for RESTORE flag
if [ -f "$USB/RESTORE" ]; then
    echo "RESTORE flag found — restoring original region" >> $LOG

    # Read saved offsets (in case they differ from current detection)
    if [ -f "$USB/.dvd_offset.txt" ] && [ -f "$USB/.bd_offset.txt" ]; then
        RESTORE_DVD_OFF=$(cat $USB/.dvd_offset.txt)
        RESTORE_BD_OFF=$(cat $USB/.bd_offset.txt)
    else
        RESTORE_DVD_OFF=$DVD_VAL_OFF
        RESTORE_BD_OFF=$BD_VAL_OFF
    fi

    if [ -f "$USB/.dvd_backup.bin" ] && [ -f "$USB/.bd_backup.bin" ]; then
        dd if=$USB/.dvd_backup.bin of=$CONF bs=1 seek=$RESTORE_DVD_OFF conv=notrunc 2>/dev/null
        dd if=$USB/.bd_backup.bin of=$CONF bs=1 seek=$RESTORE_BD_OFF conv=notrunc 2>/dev/null
        sync
        DVD_R=$(dd if=$CONF bs=1 skip=$RESTORE_DVD_OFF count=1 2>/dev/null | hexdump -C | head -1 | sed 's/.*  \(..\).*/\1/')
        BD_R=$(dd if=$CONF bs=1 skip=$RESTORE_BD_OFF count=1 2>/dev/null | hexdump -C | head -1 | sed 's/.*  \(..\).*/\1/')
        echo "Restored: DVD=0x$DVD_R, BD=0x$BD_R" >> $LOG
        echo "RESTORED OK" > $USB/REGION_RESTORED.txt
        rm -f $USB/REGION_FREE_OK.txt 2>/dev/null
    else
        echo "ERROR: backup files not found on USB" >> $LOG
        echo "FAILED — no backup found" > $USB/REGION_RESTORE_FAILED.txt
    fi
    echo "Finished: $(date)" >> $LOG
    echo "Power off the player, remove the USB, and turn it back on." >> $LOG
    exit 0
fi

# Write region-free values: DVD=0 (region-free), BD=7 (A+B+C)
printf '\x00' | dd of=$CONF bs=1 seek=$DVD_VAL_OFF conv=notrunc 2>/dev/null
printf '\x07' | dd of=$CONF bs=1 seek=$BD_VAL_OFF conv=notrunc 2>/dev/null
sync

# Verify
DVD_AFTER=$(dd if=$CONF bs=1 skip=$DVD_VAL_OFF count=1 2>/dev/null | hexdump -C | head -1 | sed 's/.*  \(..\).*/\1/')
BD_AFTER=$(dd if=$CONF bs=1 skip=$BD_VAL_OFF count=1 2>/dev/null | hexdump -C | head -1 | sed 's/.*  \(..\).*/\1/')
echo "After: DVD=0x$DVD_AFTER, BD=0x$BD_AFTER" >> $LOG

if [ "$DVD_AFTER" = "00" ] && [ "$BD_AFTER" = "07" ]; then
    echo "SUCCESS — player is now region-free" >> $LOG
    echo "REGION FREE OK" > $USB/REGION_FREE_OK.txt
    rm -f $USB/REGION_FREE_FAILED.txt 2>/dev/null
else
    echo "ERROR — values not written correctly" >> $LOG
    echo "FAILED" > $USB/REGION_FREE_FAILED.txt
fi

echo "Finished: $(date)" >> $LOG
echo "Power off the player, remove the USB, and turn it back on." >> $LOG
