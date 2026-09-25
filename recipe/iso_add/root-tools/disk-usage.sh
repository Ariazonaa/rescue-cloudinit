#!/bin/bash
# disk-usage.sh -- mount each VM filesystem read-only and show usage + biggest dirs.
. /root/rescue-lib.sh
activate_storage
mp=/run/du.mnt; mkdir -p "$mp"
for d in $(target_disks); do
    while read -r name fst; do
        case "$fst" in ext4|ext3|ext2|xfs|btrfs) ;; *) continue;; esac
        dev="/dev/$name"; [ -b "$dev" ] || dev="/dev/mapper/${name##*/}"
        findmnt -rno TARGET "$dev" >/dev/null 2>&1 && continue
        mount -o ro "$dev" "$mp" 2>/dev/null || continue
        hr; echo "$dev ($fst)"
        df -h "$mp" | awk 'NR==2{print "  usage: "$3" / "$2"  ("$5" full)"}'
        echo "  largest directories:"
        du -xhd2 "$mp" 2>/dev/null | sort -rh | head -12 | sed "s|$mp|/|; s/^/    /"
        umount "$mp" 2>/dev/null
    done < <(lsblk -rno NAME,FSTYPE "$d")
done
rmdir "$mp" 2>/dev/null
