#!/bin/bash
# mount-all-ro.sh -- mount every VM filesystem read-only under /mnt/<dev> for browsing.
. /root/rescue-lib.sh
activate_storage
n=0
for d in $(target_disks); do
    while read -r name fst; do
        case "$fst" in ext4|ext3|ext2|xfs|btrfs|vfat|ntfs) ;; *) continue;; esac
        dev="/dev/$name"; [ -b "$dev" ] || dev="/dev/mapper/${name##*/}"
        findmnt -rno TARGET "$dev" >/dev/null 2>&1 && { c_inf "$dev already mounted"; continue; }
        tgt="/mnt/${name##*/}"; mkdir -p "$tgt"
        if mount -o ro "$dev" "$tgt" 2>/dev/null; then c_ok "$dev ($fst) -> $tgt (ro)"; n=$((n+1))
        else c_warn "$dev: mount failed"; rmdir "$tgt" 2>/dev/null; fi
    done < <(lsblk -rno NAME,FSTYPE "$d")
done
echo
echo "mounted $n filesystem(s) read-only under /mnt/. Browse them, copy data out."
echo "unmount all again:  umount /mnt/*"
