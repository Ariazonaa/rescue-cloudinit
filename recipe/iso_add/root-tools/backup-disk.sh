#!/bin/bash
# backup-disk.sh -- image a disk or partition to a compressed file in /root.
# Uses partclone (only used blocks) for unmounted filesystems, else falls back to dd.
. /root/rescue-lib.sh
activate_storage
echo "Available block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | sed 's/^/  /'
echo "VM disks: $(target_disks | xargs)"
read -rp "Device to back up (e.g. /dev/sda or /dev/sda1): " dev
[ -b "$dev" ] || { echo "not a block device"; exit 1; }
findmnt -rno TARGET "$dev" >/dev/null 2>&1 && echo "WARNING: $dev is mounted - the image may be inconsistent."
def="/root/$(basename "$dev")-$(date +%Y%m%d).img.gz"
read -rp "Output file [$def]: " out; out="${out:-$def}"
fst="$(blkid -o value -s TYPE "$dev" 2>/dev/null)"
echo "Backing up $dev (${fst:-raw}) -> $out"
if command -v "partclone.$fst" >/dev/null 2>&1 && ! findmnt -rno TARGET "$dev" >/dev/null 2>&1; then
    "partclone.$fst" -c -s "$dev" 2>/dev/null | gzip > "$out"
    echo "restore: gunzip -c $out | partclone.$fst -r -o $dev"
else
    dd if="$dev" bs=4M status=progress conv=noerror,sync | gzip > "$out"
    echo "restore: gunzip -c $out | dd of=$dev bs=4M"
fi
echo "done: $out ($(du -h "$out" | cut -f1))"
